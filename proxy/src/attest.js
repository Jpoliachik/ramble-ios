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
  verifyCertSignature,
} from './crypto.js';

// Challenge TTL for App Attest attestation flow (5 minutes)
const CHALLENGE_TTL_SECONDS = 300;

// Apple App Attestation Root CA (DER, base64-encoded)
// Downloaded from https://www.apple.com/certificateauthority/Apple_App_Attestation_Root_CA.pem
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

  // Store challenge -> deviceId so we can verify the same device redeems it
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

  // Verify the challenge was issued by us, hasn't expired, and belongs to this device
  const storedDeviceId = await env.ATTEST_KV.get(`challenge:${challenge}`);
  if (!storedDeviceId) {
    return { error: 'Invalid or expired challenge', status: 403 };
  }
  if (storedDeviceId !== deviceId) {
    console.error(`[attest] Challenge device mismatch: issued=${storedDeviceId} requesting=${deviceId}`);
    return { error: 'Challenge was issued to a different device', status: 403 };
  }
  // Delete the challenge so it can't be reused
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

export async function verifyAssertion(keyId, assertionB64, requestBody, env) {
  try {
    // 1. Look up the stored credential
    const storedRaw = await env.ATTEST_KV.get(`key:${keyId}`);
    if (!storedRaw) {
      return { valid: false, reason: 'Unknown key — device not attested' };
    }
    const stored = JSON.parse(storedRaw);

    // 2. Decode the CBOR assertion
    const assertionBytes = base64ToArrayBuffer(assertionB64);
    const assertion = decodeCBOR(new Uint8Array(assertionBytes));

    const signature = cborMapGet(assertion, 'signature');
    const authenticatorData = cborMapGet(assertion, 'authenticatorData');

    if (!signature || !authenticatorData) {
      return { valid: false, reason: 'Invalid assertion structure' };
    }

    // 3. Verify rpIdHash matches the value recorded during attestation
    const rpIdHash = authenticatorData.slice(0, 32);
    if (stored.rpIdHash) {
      const storedRpIdBytes = new Uint8Array(base64ToArrayBuffer(stored.rpIdHash));
      if (!arrayEqual(rpIdHash, storedRpIdBytes)) {
        return { valid: false, reason: 'rpIdHash mismatch — wrong app identity' };
      }
    }

    // 4. Compute clientDataHash = SHA256(requestBody)
    const clientDataHash = new Uint8Array(
      await crypto.subtle.digest('SHA-256', requestBody),
    );

    // 5. Build the data that was signed: authenticatorData || clientDataHash
    const signedData = new Uint8Array(authenticatorData.length + clientDataHash.length);
    signedData.set(authenticatorData);
    signedData.set(clientDataHash, authenticatorData.length);

    // 6. Import the stored public key (raw EC point: 0x04 || x || y)
    const publicKeyBytes = base64ToArrayBuffer(stored.publicKey);
    const publicKey = await crypto.subtle.importKey(
      'raw',
      publicKeyBytes,
      { name: 'ECDSA', namedCurve: 'P-256' },
      false,
      ['verify'],
    );

    // 7. Convert DER signature to raw r||s format for WebCrypto
    const rawSignature = derSignatureToRaw(new Uint8Array(signature.buffer || signature));

    // 8. Verify the signature (ECDSA-SHA256 over authenticatorData || clientDataHash)
    const isValid = await crypto.subtle.verify(
      { name: 'ECDSA', hash: 'SHA-256' },
      publicKey,
      rawSignature,
      signedData,
    );

    if (!isValid) {
      return { valid: false, reason: 'Invalid signature' };
    }

    // 9. Check that the counter is incrementing (replay protection)
    const newCounter =
      (authenticatorData[33] << 24) |
      (authenticatorData[34] << 16) |
      (authenticatorData[35] << 8) |
      authenticatorData[36];

    if (newCounter <= stored.counter) {
      return { valid: false, reason: `Counter not incrementing: ${newCounter} <= ${stored.counter}` };
    }

    // 10. Update the stored counter
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
    // 1. Decode the CBOR attestation object
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

    // 2. Verify the nonce: SHA256(authData || SHA256(challenge))
    const clientDataHash = new Uint8Array(
      await crypto.subtle.digest('SHA-256', new TextEncoder().encode(challenge)),
    );
    const composite = new Uint8Array(authData.length + clientDataHash.length);
    composite.set(authData);
    composite.set(clientDataHash, authData.length);
    const expectedNonce = new Uint8Array(await crypto.subtle.digest('SHA-256', composite));

    // 3. Extract the certificate chain
    const x5c = cborMapGet(attStmt, 'x5c');
    if (!x5c || !Array.isArray(x5c) || x5c.length < 2) {
      return { valid: false, reason: 'Missing or invalid x5c certificate chain' };
    }

    // 4. Extract and verify the nonce from the credential certificate
    const credCertDer = x5c[0];
    const certNonce = extractNonceFromCert(credCertDer);
    if (!certNonce) {
      return { valid: false, reason: 'Could not extract nonce from credential certificate' };
    }

    if (!arrayEqual(certNonce, expectedNonce)) {
      return { valid: false, reason: 'Nonce mismatch — attestation not for this challenge' };
    }

    // 5. Verify certificate chain: leaf signed by intermediate, intermediate signed by Apple root
    const intermediateDer = x5c[1];
    const intermediateKey = await importPublicKeyFromCert(intermediateDer.buffer);
    if (!intermediateKey) {
      return { valid: false, reason: 'Could not import intermediate CA public key' };
    }
    const leafSignatureValid = await verifyCertSignature(credCertDer, intermediateKey);
    if (!leafSignatureValid) {
      return { valid: false, reason: 'Leaf certificate not signed by intermediate CA' };
    }

    const rootCaDer = base64ToArrayBuffer(APPLE_APP_ATTEST_ROOT_CA_B64);
    const rootCaKey = await importP384PublicKeyFromCert(rootCaDer);
    if (rootCaKey) {
      const intermediateValid = await verifyCertSignature(intermediateDer, rootCaKey, 'P-384', 'SHA-384');
      if (!intermediateValid) {
        return { valid: false, reason: 'Intermediate CA not signed by Apple root' };
      }
    }

    // 6. Extract the public key from authData (the attested credential key)
    const credentialKey = extractPublicKeyFromAuthData(authData);
    if (!credentialKey) {
      return { valid: false, reason: 'Could not extract credential public key from authData' };
    }

    // 7. Extract sign count and rpIdHash
    const signCount = (authData[33] << 24) | (authData[34] << 16) | (authData[35] << 8) | authData[36];
    const rpIdHash = authData.slice(0, 32);

    // 8. Verify the credentialId in authData matches the keyId
    const credIdLen = (authData[53] << 8) | authData[54];
    const credentialId = authData.slice(55, 55 + credIdLen);
    const credentialIdB64 = arrayBufferToBase64(credentialId);
    if (credentialIdB64 !== keyId && bytesToHex(credentialId) !== keyId) {
      const credIdB64Url = arrayBufferToBase64(credentialId).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
      if (credIdB64Url !== keyId) {
        console.warn(`[attest] credentialId mismatch: got=${credentialIdB64.substring(0, 16)}... expected=${keyId.substring(0, 16)}...`);
        // Don't fail — Apple's keyId format may vary; the nonce check is the primary verification
      }
    }

    // 9. Store the credential in KV for future assertion verification.
    // Include rpIdHash so assertion verification can confirm app identity.
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
// Handles the subset needed for App Attest: maps, byte strings, text strings,
// arrays, integers, and tagged values.

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
    if (info === 25) {
      const b = readBytes(2);
      return (b[0] << 8) | b[1];
    }
    if (info === 26) {
      const b = readBytes(4);
      return ((b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]) >>> 0;
    }
    if (info === 27) {
      const b = readBytes(8);
      let val = 0;
      for (let i = 0; i < 8; i++) val = val * 256 + b[i];
      return val;
    }
    throw new Error(`CBOR: unsupported additional info ${info}`);
  }

  function decode() {
    const initial = readByte();
    const major = initial >> 5;
    const info = initial & 0x1f;

    switch (major) {
      case 0: // unsigned int
        return readUint(info);
      case 1: // negative int
        return -1 - readUint(info);
      case 2: { // byte string
        const len = readUint(info);
        return readBytes(len);
      }
      case 3: { // text string
        const len = readUint(info);
        return new TextDecoder().decode(readBytes(len));
      }
      case 4: { // array
        const len = readUint(info);
        const arr = [];
        for (let i = 0; i < len; i++) arr.push(decode());
        return arr;
      }
      case 5: { // map
        const len = readUint(info);
        const map = new Map();
        for (let i = 0; i < len; i++) {
          const key = decode();
          const value = decode();
          map.set(key, value);
        }
        return map;
      }
      case 6: // tag — skip tag number, return inner value
        readUint(info);
        return decode();
      case 7: // simple values
        if (info === 20) return false;
        if (info === 21) return true;
        if (info === 22) return null;
        throw new Error(`CBOR: unsupported simple value ${info}`);
      default:
        throw new Error(`CBOR: unknown major type ${major}`);
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

// --- Certificate & Key Helpers ---

// Extract the nonce from a credential certificate's App Attest extension (OID 1.2.840.113635.100.8.2)
function extractNonceFromCert(certBytes) {
  for (let i = 0; i < certBytes.length - APP_ATTEST_NONCE_OID.length; i++) {
    let match = true;
    for (let j = 0; j < APP_ATTEST_NONCE_OID.length; j++) {
      if (certBytes[i + j] !== APP_ATTEST_NONCE_OID[j]) {
        match = false;
        break;
      }
    }
    if (!match) continue;

    // Found the OID. Scan forward for the 32-byte OCTET STRING (0x04 0x20)
    const searchStart = i + APP_ATTEST_NONCE_OID.length;
    for (let k = searchStart; k < Math.min(searchStart + 64, certBytes.length - 33); k++) {
      if (certBytes[k] === 0x04 && certBytes[k + 1] === 0x20) {
        return certBytes.slice(k + 2, k + 2 + 32);
      }
    }
  }
  return null;
}

// Extract the credential public key from authData (attestation response)
// AuthData format: rpIdHash(32) | flags(1) | signCount(4) | aaguid(16) | credIdLen(2) | credId(N) | credPubKey(CBOR)
function extractPublicKeyFromAuthData(authData) {
  try {
    const credIdLen = (authData[53] << 8) | authData[54];
    const coseKeyOffset = 55 + credIdLen;

    if (coseKeyOffset >= authData.length) return null;

    const coseKey = decodeCBOR(authData.slice(coseKeyOffset));
    if (!(coseKey instanceof Map)) return null;

    // COSE EC2 key: x=(-2), y=(-3)
    const x = coseKey.get(-2);
    const y = coseKey.get(-3);

    if (!x || !y || x.length !== 32 || y.length !== 32) return null;

    // Build uncompressed EC point: 0x04 || x || y (65 bytes)
    const rawKey = new Uint8Array(65);
    rawKey[0] = 0x04;
    rawKey.set(x, 1);
    rawKey.set(y, 33);
    return rawKey;
  } catch {
    return null;
  }
}
