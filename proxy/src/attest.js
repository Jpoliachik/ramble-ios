// Apple App Attest: challenge issuance, attestation registration,
// and per-request assertion verification.
//
// Registration accepts only attestations that chain to Apple's App Attest
// root, come from the production App Attest environment, and name this app
// (rpIdHash = SHA-256 of "<team ID>.<bundle ID>"). Any failure is a 403.

import {
  arrayBufferToBase64,
  arrayEqual,
  base64ToBytes,
  derChildren,
  derContent,
  derSignatureToRaw,
  importCertKey,
  isIssuedBy,
  isValidAt,
  parseCertificate,
  readDer,
  sha256,
} from './crypto.js';

const CHALLENGE_TTL_SECONDS = 300;
const DEFAULT_APP_ID = 'SW6VLKWS7Q.dev.goodloop.Ramble';

// Apple App Attestation Root CA (DER, base64), from
// https://www.apple.com/certificateauthority/Apple_App_Attestation_Root_CA.pem
// SHA-256 1cb9823ba28ba6ad2d33a006941de2ae4f513ef1d4e831b9f7e0fa7b6242c932
const APPLE_APP_ATTEST_ROOT_CA_B64 =
  'MIICITCCAaegAwIBAgIQC/O+DvHN0uD7jG5yH2IXmDAKBggqhkjOPQQDAzBSMSYw' +
  'JAYDVQQDDB1BcHBsZSBBcHAgQXR0ZXN0YXRpb24gUm9vdCBDQTETMBEGA1UECgwK' +
  'QXBwbGUgSW5jLjETMBEGA1UECAwKQ2FsaWZvcm5pYTAeFw0yMDAzMTgxODMyNTNa' +
  'Fw00NTAzMTUwMDAwMDBaMFIxJjAkBgNVBAMMHUFwcGxlIEFwcCBBdHRlc3RhdGlv' +
  'biBSb290IENBMRMwEQYDVQQKDApBcHBsZSBJbmMuMRMwEQYDVQQIDApDYWxpZm9y' +
  'bmlhMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAERTHhmLW07ATaFQIEVwTtT4dyctdh' +
  'NbJhFs/Ii2FdCgAHGbpphY3+d8qjuDngIN3WVhQUBHAoMeQ/cLiP1sOUtgjqK9au' +
  'Yen1mMEvRq9Sk3Jm5X8U62H+xTD3FE9TgS41o0IwQDAPBgNVHRMBAf8EBTADAQH/' +
  'MB0GA1UdDgQWBBSskRBTM72+aEH/pwyp5frq5eWKoTAOBgNVHQ8BAf8EBAMCAQYw' +
  'CgYIKoZIzj0EAwMDaAAwZQIwQgFGnByvsiVbpTKwSga0kP0e8EeDS4+sQmTvb7vn' +
  '53O5+FRXgeLhpJ06ysC5PrOyAjEAp5U4xDgEgllF7En3VcE3iexZZtKeYnpqtijV' +
  'oyFraWVIyd/dganmrduC1bmTBGwD';

// Nonce extension in the credential certificate.
const OID_APP_ATTEST_NONCE = '1.2.840.113635.100.8.2';

// aaguid values: production is "appattest" + 7 zero bytes.
const AAGUID_PRODUCTION = new Uint8Array([...new TextEncoder().encode('appattest'), 0, 0, 0, 0, 0, 0, 0]);
const AAGUID_DEVELOPMENT = new TextEncoder().encode('appattestdevelop');

function expectedRpIdHash(env) {
  return sha256(env?.APP_ATTEST_APP_ID || DEFAULT_APP_ID);
}

function readCounter(authData) {
  return ((authData[33] << 24) | (authData[34] << 16) | (authData[35] << 8) | authData[36]) >>> 0;
}

// --- Challenge Endpoint ---

export async function handleAttestChallenge(request, env) {
  const deviceId = request.headers.get('X-Device-ID') || 'unknown';

  const challengeBytes = new Uint8Array(32);
  crypto.getRandomValues(challengeBytes);
  const challenge = arrayBufferToBase64(challengeBytes);

  await env.ATTEST_KV.put(`challenge:${challenge}`, deviceId, {
    expirationTtl: CHALLENGE_TTL_SECONDS,
  });

  return { challenge };
}

// --- Attestation Registration Endpoint ---

// Returns { status: 'ok' } or { error, status, reason? }.
// deps: { rootCertDer, now } for tests only.
export async function handleAttest(request, env, deps = {}) {
  const deviceId = request.headers.get('X-Device-ID') || 'unknown';

  let body;
  try {
    body = await request.json();
  } catch {
    return { error: 'Invalid JSON body', status: 400 };
  }

  const { keyId, attestation, challenge } = body || {};
  if (typeof keyId !== 'string' || typeof attestation !== 'string' || typeof challenge !== 'string') {
    return { error: 'Missing keyId, attestation, or challenge', status: 400 };
  }

  try {
    const storedDeviceId = await env.ATTEST_KV.get(`challenge:${challenge}`);
    if (!storedDeviceId) {
      return { error: 'Invalid or expired challenge', status: 403 };
    }
    await env.ATTEST_KV.delete(`challenge:${challenge}`);
    if (storedDeviceId !== deviceId) {
      return { error: 'Challenge was issued to a different device', status: 403 };
    }

    const result = await verifyAttestation(keyId, attestation, challenge, env, deps);
    if (!result.valid) {
      console.error(`[attest] Attestation rejected: ${result.reason}`);
      return { error: 'Attestation rejected', status: 403 };
    }

    // A key ID is registered once. Same key again: nothing changes.
    const existingRaw = await env.ATTEST_KV.get(`key:${keyId}`);
    if (existingRaw) {
      const existing = JSON.parse(existingRaw);
      if (existing.publicKey === result.record.publicKey) return { status: 'ok' };
      return { error: 'This key ID is already registered', status: 409, reason: 'key_exists' };
    }

    await env.ATTEST_KV.put(`key:${keyId}`, JSON.stringify(result.record));
    return { status: 'ok' };
  } catch (err) {
    console.error(`[attest] Attestation could not be checked: ${err.message}`);
    return { error: 'Attestation rejected', status: 403 };
  }
}

// --- Assertion Verification (called before attested requests) ---

// Returns { valid: true } or { valid: false, reason, unavailable? }.
// `unavailable` is set when the key store couldn't be read.
export async function verifyAssertionForRequest(keyId, assertionB64, requestBody, env) {
  let stored;
  try {
    const storedRaw = await env.ATTEST_KV.get(`key:${keyId}`);
    if (!storedRaw) return { valid: false, reason: 'Unknown key, device not attested' };
    stored = JSON.parse(storedRaw);
  } catch (err) {
    return { valid: false, unavailable: true, reason: `Key store error: ${err.message}` };
  }

  try {
    const assertion = decodeCBOR(base64ToBytes(assertionB64));
    const signature = cborMapGet(assertion, 'signature');
    const authenticatorData = cborMapGet(assertion, 'authenticatorData');
    if (!(signature instanceof Uint8Array) || !(authenticatorData instanceof Uint8Array) || authenticatorData.length < 37) {
      return { valid: false, reason: 'Invalid assertion structure' };
    }

    if (!arrayEqual(authenticatorData.slice(0, 32), await expectedRpIdHash(env))) {
      return { valid: false, reason: 'rpIdHash mismatch' };
    }

    // Apple signs nonce = SHA256(authenticatorData || SHA256(body)).
    const clientDataHash = await sha256(new Uint8Array(requestBody));
    const composite = new Uint8Array(authenticatorData.length + clientDataHash.length);
    composite.set(authenticatorData);
    composite.set(clientDataHash, authenticatorData.length);
    const nonce = await sha256(composite);

    const publicKey = await crypto.subtle.importKey(
      'raw',
      base64ToBytes(stored.publicKey),
      { name: 'ECDSA', namedCurve: 'P-256' },
      false,
      ['verify'],
    );
    const isValid = await crypto.subtle.verify(
      { name: 'ECDSA', hash: 'SHA-256' },
      publicKey,
      derSignatureToRaw(signature, 32),
      nonce,
    );
    if (!isValid) return { valid: false, reason: 'Invalid signature' };

    const newCounter = readCounter(authenticatorData);
    if (!(newCounter > stored.counter)) {
      return { valid: false, reason: `Counter not increasing: ${newCounter} <= ${stored.counter}` };
    }

    stored.counter = newCounter;
    try {
      await env.ATTEST_KV.put(`key:${keyId}`, JSON.stringify(stored));
    } catch (err) {
      return { valid: false, unavailable: true, reason: `Key store error: ${err.message}` };
    }
    return { valid: true };
  } catch (err) {
    return { valid: false, reason: `Assertion error: ${err.message}` };
  }
}

// --- Attestation Verification (internal) ---

// Follows Apple's "Verify the attestation" steps. Returns
// { valid: true, record } (the KV record to store) or { valid: false, reason }.
// Exported for tests.
export async function verifyAttestation(keyId, attestationB64, challenge, env, deps = {}) {
  try {
    const attestObj = decodeCBOR(base64ToBytes(attestationB64));
    if (cborMapGet(attestObj, 'fmt') !== 'apple-appattest') return { valid: false, reason: 'Unexpected format' };

    const attStmt = cborMapGet(attestObj, 'attStmt');
    const authData = cborMapGet(attestObj, 'authData');
    if (!(attStmt instanceof Map) || !(authData instanceof Uint8Array) || authData.length < 55) {
      return { valid: false, reason: 'Missing attStmt or authData' };
    }

    // 1. Certificate chain: credential cert <- intermediate <- App Attest root.
    const x5c = cborMapGet(attStmt, 'x5c');
    if (!Array.isArray(x5c) || x5c.length !== 2) return { valid: false, reason: 'x5c must hold credential and intermediate' };
    const leaf = parseCertificate(x5c[0]);
    const intermediate = parseCertificate(x5c[1]);
    const root = parseCertificate(deps.rootCertDer ? new Uint8Array(deps.rootCertDer) : base64ToBytes(APPLE_APP_ATTEST_ROOT_CA_B64));
    if (!(await isIssuedBy(intermediate, root))) return { valid: false, reason: 'Intermediate not signed by App Attest root' };
    if (!(await isIssuedBy(leaf, intermediate))) return { valid: false, reason: 'Credential cert not signed by intermediate' };
    const now = deps.now ? deps.now() : Date.now();
    if (![leaf, intermediate, root].every((c) => isValidAt(c, now))) return { valid: false, reason: 'Certificate expired' };

    // 2-4. nonce = SHA256(authData || SHA256(challenge)) must be in the credential cert.
    const clientDataHash = await sha256(challenge);
    const composite = new Uint8Array(authData.length + clientDataHash.length);
    composite.set(authData);
    composite.set(clientDataHash, authData.length);
    const nonce = await sha256(composite);
    const certNonce = readNonceExtension(leaf);
    if (!certNonce || !arrayEqual(certNonce, nonce)) return { valid: false, reason: 'Nonce mismatch' };

    // 5. The key ID is the SHA-256 of the credential public key.
    if (leaf.curve !== 'P-256') return { valid: false, reason: 'Credential key is not P-256' };
    const publicKey = new Uint8Array(await crypto.subtle.exportKey('raw', await importCertKey(leaf, true)));
    const keyIdBytes = base64ToBytes(keyId);
    if (!arrayEqual(await sha256(publicKey), keyIdBytes)) return { valid: false, reason: 'Key ID does not match public key' };

    // 6. rpIdHash names this app.
    const rpIdHash = authData.slice(0, 32);
    if (!arrayEqual(rpIdHash, await expectedRpIdHash(env))) return { valid: false, reason: 'rpIdHash is not this app' };

    // 7. Fresh key: counter 0.
    const counter = readCounter(authData);
    if (counter !== 0) return { valid: false, reason: 'Counter is not 0' };

    // 8. Production App Attest environment. A local development relay
    // (ENVIRONMENT = "development") also takes development attestations.
    const aaguid = authData.slice(37, 53);
    const devAllowed = env?.ENVIRONMENT === 'development' && arrayEqual(aaguid, AAGUID_DEVELOPMENT);
    if (!arrayEqual(aaguid, AAGUID_PRODUCTION) && !devAllowed) return { valid: false, reason: 'Not the production App Attest environment' };

    // 9. Credential ID equals the key ID.
    const credIdLength = (authData[53] << 8) | authData[54];
    const credentialId = authData.slice(55, 55 + credIdLength);
    if (!arrayEqual(credentialId, keyIdBytes)) return { valid: false, reason: 'Credential ID does not match key ID' };

    return {
      valid: true,
      record: {
        publicKey: arrayBufferToBase64(publicKey),
        rpIdHash: arrayBufferToBase64(rpIdHash),
        counter,
        attestedAt: now,
      },
    };
  } catch (err) {
    return { valid: false, reason: `Verification error: ${err.message}` };
  }
}

// The nonce extension holds SEQUENCE { [1] { OCTET STRING nonce } }.
function readNonceExtension(cert) {
  const value = cert.extensions.get(OID_APP_ATTEST_NONCE);
  if (!value) return null;
  const seq = readDer(value, 0);
  const [tagged] = derChildren(value, seq);
  if (!tagged || tagged.tag !== 0xa1) return null;
  const [octets] = derChildren(value, tagged);
  if (!octets || octets.tag !== 0x04) return null;
  return derContent(value, octets);
}

// --- Minimal CBOR Decoder ---

function decodeCBOR(data) {
  let offset = 0;

  function readByte() {
    if (offset >= data.length) throw new Error('CBOR: unexpected end of data');
    return data[offset++];
  }

  function readBytes(n) {
    if (offset + n > data.length) throw new Error('CBOR: unexpected end of data');
    const bytes = data.slice(offset, offset + n);
    offset += n;
    return bytes;
  }

  function readUint(info) {
    if (info < 24) return info;
    if (info === 24) return readByte();
    if (info === 25) { const b = readBytes(2); return (b[0] << 8) | b[1]; }
    if (info === 26) { const b = readBytes(4); return ((b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]) >>> 0; }
    if (info === 27) { const b = readBytes(8); let v = 0; for (let i = 0; i < 8; i++) v = v * 256 + b[i]; return v; }
    throw new Error(`CBOR: unsupported additional info ${info}`);
  }

  function decode() {
    const initial = readByte();
    const major = initial >> 5;
    const info = initial & 0x1f;
    switch (major) {
      case 0: return readUint(info);
      case 1: return -1 - readUint(info);
      case 2: return readBytes(readUint(info));
      case 3: return new TextDecoder().decode(readBytes(readUint(info)));
      case 4: { const arr = []; for (let i = 0, len = readUint(info); i < len; i++) arr.push(decode()); return arr; }
      case 5: { const map = new Map(); for (let i = 0, len = readUint(info); i < len; i++) { const k = decode(); map.set(k, decode()); } return map; }
      case 6: readUint(info); return decode();
      case 7: if (info === 20) return false; if (info === 21) return true; if (info === 22) return null; throw new Error(`CBOR: unsupported simple value ${info}`);
      default: throw new Error(`CBOR: unknown major type ${major}`);
    }
  }

  return decode();
}

function cborMapGet(map, key) {
  if (!(map instanceof Map)) return undefined;
  if (map.has(key)) return map.get(key);
  const numKey = Number(key);
  if (!isNaN(numKey) && map.has(numKey)) return map.get(numKey);
  return undefined;
}

