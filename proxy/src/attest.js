// Apple App Attest: challenge issuance, attestation registration,
// and per-request assertion verification.

import {
  arrayBufferToBase64,
  arrayEqual,
  base64ToArrayBuffer,
  bytesToHex,
  derSignatureToRaw,
  importP384PublicKeyFromCert,
  importPublicKeyFromCert,
  importPublicKeyFromCertExportable,
  verifyCertSignature,
} from './crypto.js';

const CHALLENGE_TTL_SECONDS = 300;

// Apple App Attestation Root CA (DER, base64-encoded)
const APPLE_APP_ATTEST_ROOT_CA_B64 =
  'MIICITCCAaegAwIBAgIQC/O+DvHN0uD7jG5yH2IXmDAKBggqhkjOPQQDAzBSMSYw' +
  'JAYDVQQDDB1BcHBsZSBBcHAgQXR0ZXN0YXRpb24gUm9vdCBDQTETMBEGA1UECgwK' +
  'QXBwbGUgSW5jLjETMBEGA1UECAwKQ2FsaWZvcm5pYTAeFw0yMDAzMTgxODMyNTNa' +
  'Fw00NTAzMTUwMDAwMDBaMFIxJjAkBgNVBAMMHUFwcGxlIEFwcCBBdHRlc3RhdGlv' +
  'biBSb290IENBMRMwEQYDVQQKDApBcHBsZSBJbmMuMRMwEQYDVQQIDApDYWxpZm9y' +
  'bmlhMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAERTHhmLW07ATaFQIEVwTtT4dyctdh' +
  'NbJhFs/Ii2FdCgAHGbpphY3+d8qjuDnzczMhp1WpFQEdeRmFcdYOo82MZO5SXKhF' +
  'T0bQ5MYJhLqWjyQ0FQxeCIxKWKng2VLhiJWTo0IwQDAPBgNVHRMBAf8EBTADAQH/' +
  'MB0GA1UdDgQWBBSskRBTM72+aEH/pwyp5frq5eWKoTAOBgNVHQ8BAf8EBAMCAQYw' +
  'CgYIKoZIzj0EAwMDaAAwZQIwQgFGnByvsiVbpTKwSga0kP0e8EeDS4+sQmTvb7vn' +
  '53O5+FRXgeLhd2sedicMBXn5AIxNXLgTk/2vcp+hmAmo4HqmJBO0cjstoY68rVlv' +
  's1w7c4tZPFQrcOxIDNBJiSFA';

// OID for the App Attest nonce extension: 1.2.840.113635.100.8.2
const APP_ATTEST_NONCE_OID = [0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x63, 0x64, 0x08, 0x02];

// --- Challenge Endpoint ---

export async function handleAttestChallenge(request, env) {
  const deviceId = request.headers.get('X-Device-ID') || 'unknown';

  const challengeBytes = new Uint8Array(32);
  crypto.getRandomValues(challengeBytes);
  const challenge = arrayBufferToBase64(challengeBytes);

  await env.ATTEST_KV.put(`challenge:${challenge}`, deviceId, {
    expirationTtl: CHALLENGE_TTL_SECONDS,
  });

  console.log(`[attest] Challenge issued device=${deviceId}`);
  return { challenge };
}

// --- Attestation Registration Endpoint ---

export async function handleAttest(request, env) {
  const deviceId = request.headers.get('X-Device-ID') || 'unknown';

  let body;
  try {
    body = await request.json();
  } catch {
    return { error: 'Invalid JSON body', status: 400 };
  }

  const { keyId, attestation, challenge } = body;
  if (!keyId || !attestation || !challenge) {
    return { error: 'Missing keyId, attestation, or challenge', status: 400 };
  }

  const storedDeviceId = await env.ATTEST_KV.get(`challenge:${challenge}`);
  if (!storedDeviceId) {
    return { error: 'Invalid or expired challenge', status: 403 };
  }
  if (storedDeviceId !== deviceId) {
    return { error: 'Challenge was issued to a different device', status: 403 };
  }
  await env.ATTEST_KV.delete(`challenge:${challenge}`);

  const result = await verifyAttestation(keyId, attestation, challenge, env);
  if (!result.valid) {
    console.error(`[attest] Attestation rejected: ${result.reason} device=${deviceId}`);
    return { error: `Attestation rejected: ${result.reason}`, status: 403 };
  }

  console.log(`[attest] Device attested device=${deviceId} keyId=${keyId.substring(0, 8)}...`);
  return { status: 'ok' };
}

// --- Assertion Verification (called from transcribe handler) ---

export async function verifyAssertionForRequest(keyId, assertionB64, requestBody, env) {
  try {
    const storedRaw = await env.ATTEST_KV.get(`key:${keyId}`);
    if (!storedRaw) {
      return { valid: false, reason: 'Unknown key — device not attested' };
    }
    const stored = JSON.parse(storedRaw);

    // Decode the CBOR assertion
    const assertionBytes = base64ToArrayBuffer(assertionB64);
    const assertion = decodeCBOR(new Uint8Array(assertionBytes));

    const signature = cborMapGet(assertion, 'signature');
    const authenticatorData = cborMapGet(assertion, 'authenticatorData');

    if (!signature || !authenticatorData) {
      return { valid: false, reason: 'Invalid assertion structure' };
    }

    // Verify rpIdHash matches attestation
    const rpIdHash = authenticatorData.slice(0, 32);
    if (stored.rpIdHash) {
      const storedRpIdBytes = new Uint8Array(base64ToArrayBuffer(stored.rpIdHash));
      if (!arrayEqual(rpIdHash, storedRpIdBytes)) {
        return { valid: false, reason: 'rpIdHash mismatch' };
      }
    }

    // Compute clientDataHash = SHA256(requestBody)
    const clientDataHash = new Uint8Array(
      await crypto.subtle.digest('SHA-256', requestBody),
    );

    // Compute nonce = SHA256(authenticatorData || clientDataHash)
    // Apple signs the nonce, NOT the raw concatenation.
    const composite = new Uint8Array(authenticatorData.length + clientDataHash.length);
    composite.set(authenticatorData);
    composite.set(clientDataHash, authenticatorData.length);
    const nonce = new Uint8Array(await crypto.subtle.digest('SHA-256', composite));

    // Import the stored public key
    const publicKeyBytes = base64ToArrayBuffer(stored.publicKey);
    const publicKey = await crypto.subtle.importKey(
      'raw',
      publicKeyBytes,
      { name: 'ECDSA', namedCurve: 'P-256' },
      false,
      ['verify'],
    );

    // Convert DER signature to raw r||s format
    const rawSignature = derSignatureToRaw(new Uint8Array(signature.buffer || signature));

    // Verify the signature over the nonce
    const isValid = await crypto.subtle.verify(
      { name: 'ECDSA', hash: 'SHA-256' },
      publicKey,
      rawSignature,
      nonce,
    );

    if (!isValid) {
      return { valid: false, reason: 'Invalid signature' };
    }

    // Check counter is incrementing (replay protection)
    const newCounter =
      (authenticatorData[33] << 24) |
      (authenticatorData[34] << 16) |
      (authenticatorData[35] << 8) |
      authenticatorData[36];

    if (newCounter <= stored.counter) {
      return { valid: false, reason: `Counter not incrementing: ${newCounter} <= ${stored.counter}` };
    }

    stored.counter = newCounter;
    await env.ATTEST_KV.put(`key:${keyId}`, JSON.stringify(stored));

    return { valid: true };
  } catch (err) {
    return { valid: false, reason: `Assertion error: ${err.message}` };
  }
}

// --- Attestation Verification (internal) ---

async function verifyAttestation(keyId, attestationB64, challenge, env) {
  try {
    const attestationBytes = base64ToArrayBuffer(attestationB64);
    const attestObj = decodeCBOR(new Uint8Array(attestationBytes));

    const fmt = cborMapGet(attestObj, 'fmt');
    if (fmt !== 'apple-appattest') {
      return { valid: false, reason: `Unexpected format: ${fmt}` };
    }

    const attStmt = cborMapGet(attestObj, 'attStmt');
    const authData = cborMapGet(attestObj, 'authData');
    if (!attStmt || !authData) {
      return { valid: false, reason: 'Missing attStmt or authData' };
    }

    // Verify the nonce: SHA256(authData || SHA256(challenge))
    const clientDataHash = new Uint8Array(
      await crypto.subtle.digest('SHA-256', new TextEncoder().encode(challenge)),
    );
    const composite = new Uint8Array(authData.length + clientDataHash.length);
    composite.set(authData);
    composite.set(clientDataHash, authData.length);
    const expectedNonce = new Uint8Array(await crypto.subtle.digest('SHA-256', composite));

    // Extract and validate certificate chain
    const x5c = cborMapGet(attStmt, 'x5c');
    if (!x5c || !Array.isArray(x5c) || x5c.length < 2) {
      return { valid: false, reason: 'Missing or invalid x5c certificate chain' };
    }

    // Verify nonce in credential certificate
    const credCertDer = x5c[0];
    const certNonce = extractNonceFromCert(credCertDer);
    if (!certNonce || !arrayEqual(certNonce, expectedNonce)) {
      return { valid: false, reason: 'Nonce mismatch' };
    }

    // Verify cert chain: leaf → intermediate → Apple root
    const intermediateDer = x5c[1];
    let intermediateKey = await importPublicKeyFromCert(intermediateDer.buffer);
    let intermediateCurve = 'P-256';
    if (!intermediateKey) {
      intermediateKey = await importP384PublicKeyFromCert(intermediateDer.buffer);
      intermediateCurve = 'P-384';
    }
    if (!intermediateKey) {
      return { valid: false, reason: 'Could not import intermediate CA public key' };
    }

    // Try standard hash pairing, then fallback.
    // Apple's P-384 intermediate signs leaf certs with SHA-256.
    const primaryHash = intermediateCurve === 'P-384' ? 'SHA-384' : 'SHA-256';
    const fallbackHash = intermediateCurve === 'P-384' ? 'SHA-256' : 'SHA-384';
    let leafValid = await verifyCertSignature(credCertDer, intermediateKey, intermediateCurve, primaryHash);
    if (!leafValid) {
      leafValid = await verifyCertSignature(credCertDer, intermediateKey, intermediateCurve, fallbackHash);
    }
    if (!leafValid) {
      return { valid: false, reason: 'Leaf certificate not signed by intermediate CA' };
    }

    const rootCaDer = base64ToArrayBuffer(APPLE_APP_ATTEST_ROOT_CA_B64);
    const rootCaKey = await importP384PublicKeyFromCert(rootCaDer);
    if (rootCaKey) {
      const intValid = await verifyCertSignature(intermediateDer, rootCaKey, 'P-384', 'SHA-384');
      if (!intValid) {
        return { valid: false, reason: 'Intermediate CA not signed by Apple root' };
      }
    }

    // Extract credential public key from the certificate (more reliable than COSE parsing)
    const certPublicKey = await importPublicKeyFromCertExportable(credCertDer.buffer || credCertDer);
    if (!certPublicKey) {
      return { valid: false, reason: 'Could not extract credential public key' };
    }
    const credentialKey = new Uint8Array(await crypto.subtle.exportKey('raw', certPublicKey));

    const signCount = (authData[33] << 24) | (authData[34] << 16) | (authData[35] << 8) | authData[36];
    const rpIdHash = authData.slice(0, 32);

    await env.ATTEST_KV.put(
      `key:${keyId}`,
      JSON.stringify({
        publicKey: arrayBufferToBase64(credentialKey),
        rpIdHash: arrayBufferToBase64(rpIdHash),
        counter: signCount,
        attestedAt: Date.now(),
      }),
    );

    return { valid: true };
  } catch (err) {
    return { valid: false, reason: `Verification error: ${err.message}` };
  }
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

// --- Certificate Helpers ---

function extractNonceFromCert(certBytes) {
  for (let i = 0; i < certBytes.length - APP_ATTEST_NONCE_OID.length; i++) {
    let match = true;
    for (let j = 0; j < APP_ATTEST_NONCE_OID.length; j++) {
      if (certBytes[i + j] !== APP_ATTEST_NONCE_OID[j]) { match = false; break; }
    }
    if (!match) continue;
    const searchStart = i + APP_ATTEST_NONCE_OID.length;
    for (let k = searchStart; k < Math.min(searchStart + 64, certBytes.length - 33); k++) {
      if (certBytes[k] === 0x04 && certBytes[k + 1] === 0x20) {
        return certBytes.slice(k + 2, k + 2 + 32);
      }
    }
  }
  return null;
}
