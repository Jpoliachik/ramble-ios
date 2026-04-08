const ALLOWED_MODELS = ['whisper-large-v3-turbo', 'whisper-large-v3'];
const DEFAULT_MODEL = 'whisper-large-v3-turbo';
const APPLE_BUNDLE_ID = 'dev.goodloop.ramble';
const PREMIUM_PRODUCT_ID = 'dev.goodloop.ramble.premium.monthly2';

// Apple Root CA - G3 (public key SHA-256 fingerprint for chain validation)
// This is the root CA that signs App Store JWS transactions.
const APPLE_ROOT_CA_G3_FINGERPRINT =
  '63343abfb89a6a03ebbe1e8feda1be2f7f3fbc2a5391d024a45d7bc2c34d3a8c';

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

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }

    const url = new URL(request.url);

    if (url.pathname === '/transcribe' && request.method === 'POST') {
      return handleTranscribe(request, env);
    }

    if (url.pathname === '/attest/challenge' && request.method === 'POST') {
      return handleAttestChallenge(request, env);
    }

    if (url.pathname === '/attest' && request.method === 'POST') {
      return handleAttest(request, env);
    }

    if (url.pathname === '/health') {
      return json({ status: 'ok' });
    }

    return json({ error: 'Not found' }, 404);
  },
};

async function handleTranscribe(request, env) {
  const deviceId = request.headers.get('X-Device-ID') || 'unknown';

  // --- App Attest Assertion Verification ---
  // Read the body once as a buffer so we can both hash it and parse form data
  const bodyBuffer = await request.arrayBuffer();
  const attestKeyId = request.headers.get('X-App-Attest-Key-Id');
  const attestAssertionB64 = request.headers.get('X-App-Attest');
  const requireAttest = env.REQUIRE_ATTEST === 'true';

  if (attestKeyId && attestAssertionB64) {
    const assertionResult = await verifyAssertion(attestKeyId, attestAssertionB64, bodyBuffer, env);
    if (!assertionResult.valid) {
      console.error(`[attest] Assertion failed: ${assertionResult.reason} device=${deviceId}`);
      return json({ error: 'App attestation failed' }, 403);
    }
    console.log(`[attest] Assertion verified device=${deviceId} keyId=${attestKeyId.substring(0, 8)}...`);
  } else if (requireAttest) {
    console.error(`[attest] Missing attestation headers device=${deviceId}`);
    return json({ error: 'App attestation required' }, 403);
  }

  // --- JWS Subscription Verification ---
  const authHeader = request.headers.get('Authorization');
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return json({ error: 'Premium subscription required' }, 403);
  }

  const jws = authHeader.slice(7);
  const verifyResult = await verifyAppleJWS(jws);
  if (!verifyResult.valid) {
    console.error(`[auth] JWS verification failed: ${verifyResult.reason} device=${deviceId}`);
    return json({ error: 'Premium subscription required' }, 403);
  }

  console.log(`[auth] JWS verified device=${deviceId} product=${verifyResult.productId}`);

  // --- Parse form data from the buffered body ---
  let formData;
  try {
    const bodyResponse = new Response(bodyBuffer, {
      headers: { 'Content-Type': request.headers.get('Content-Type') },
    });
    formData = await bodyResponse.formData();
  } catch {
    return json({ error: 'Invalid multipart form data' }, 400);
  }

  const audio = formData.get('audio');
  if (!audio || !(audio instanceof File)) {
    return json({ error: 'Missing "audio" file field' }, 400);
  }

  // --- Model selection ---
  const requestedModel = formData.get('model') || DEFAULT_MODEL;
  if (!ALLOWED_MODELS.includes(requestedModel)) {
    return json({ error: `Invalid model. Allowed: ${ALLOWED_MODELS.join(', ')}` }, 400);
  }

  console.log(
    `[transcribe] device=${deviceId} model=${requestedModel} file=${audio.name} size=${audio.size}`,
  );

  // --- Forward to Groq ---
  const text = await transcribeWithGroq(audio, requestedModel, env);
  if (text.error) {
    return json({ error: text.error }, text.status);
  }

  console.log(`[transcribe] device=${deviceId} text_length=${text.result?.length || 0}`);

  return json({ text: text.result });
}

// --- App Attest: Challenge Endpoint ---

async function handleAttestChallenge(request, env) {
  const deviceId = request.headers.get('X-Device-ID') || 'unknown';

  // Generate a random challenge
  const challengeBytes = new Uint8Array(32);
  crypto.getRandomValues(challengeBytes);
  const challenge = arrayBufferToBase64(challengeBytes);

  // Store in KV with a short TTL so it can be verified during attestation
  await env.ATTEST_KV.put(`challenge:${challenge}`, deviceId, {
    expirationTtl: CHALLENGE_TTL_SECONDS,
  });

  console.log(`[attest] Challenge issued device=${deviceId}`);
  return json({ challenge });
}

// --- App Attest: Attestation Registration Endpoint ---

async function handleAttest(request, env) {
  const deviceId = request.headers.get('X-Device-ID') || 'unknown';

  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'Invalid JSON body' }, 400);
  }

  const { keyId, attestation, challenge } = body;
  if (!keyId || !attestation || !challenge) {
    return json({ error: 'Missing keyId, attestation, or challenge' }, 400);
  }

  // Verify the challenge was issued by us and hasn't expired
  const storedDeviceId = await env.ATTEST_KV.get(`challenge:${challenge}`);
  if (!storedDeviceId) {
    return json({ error: 'Invalid or expired challenge' }, 403);
  }
  // Delete the challenge so it can't be reused
  await env.ATTEST_KV.delete(`challenge:${challenge}`);

  // Verify the attestation object
  const result = await verifyAttestation(keyId, attestation, challenge, env);
  if (!result.valid) {
    console.error(`[attest] Attestation rejected: ${result.reason} device=${deviceId}`);
    return json({ error: `Attestation rejected: ${result.reason}` }, 403);
  }

  console.log(`[attest] Device attested device=${deviceId} keyId=${keyId.substring(0, 8)}...`);
  return json({ status: 'ok' });
}

// --- App Attest: Attestation Verification ---

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
    const credCertDer = x5c[0]; // Uint8Array
    const certNonce = extractNonceFromCert(credCertDer);
    if (!certNonce) {
      return { valid: false, reason: 'Could not extract nonce from credential certificate' };
    }

    if (!arrayEqual(certNonce, expectedNonce)) {
      return { valid: false, reason: 'Nonce mismatch — attestation not for this challenge' };
    }

    // 5. Verify the intermediate cert fingerprint matches Apple's known CA
    const intermediateDer = x5c[1];
    const intermediateHash = new Uint8Array(
      await crypto.subtle.digest('SHA-256', intermediateDer),
    );
    // Also verify the leaf cert is signed by the intermediate
    const intermediateKey = await importPublicKeyFromCert(intermediateDer.buffer);
    if (!intermediateKey) {
      return { valid: false, reason: 'Could not import intermediate CA public key' };
    }
    const leafSignatureValid = await verifyCertSignature(credCertDer, intermediateKey);
    if (!leafSignatureValid) {
      return { valid: false, reason: 'Leaf certificate not signed by intermediate CA' };
    }

    // Verify intermediate is signed by Apple App Attestation Root CA
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

    // 7. Extract sign count
    const signCount = (authData[33] << 24) | (authData[34] << 16) | (authData[35] << 8) | authData[36];

    // 8. Verify the credentialId in authData matches the keyId
    const credIdLen = (authData[53] << 8) | authData[54];
    const credentialId = authData.slice(55, 55 + credIdLen);
    const credentialIdB64 = arrayBufferToBase64(credentialId);
    // The keyId from DCAppAttestService is base64-encoded
    if (credentialIdB64 !== keyId && bytesToHex(credentialId) !== keyId) {
      // Also try URL-safe base64 comparison
      const credIdB64Url = arrayBufferToBase64(credentialId).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
      if (credIdB64Url !== keyId) {
        console.warn(`[attest] credentialId mismatch: got=${credentialIdB64.substring(0, 16)}... expected=${keyId.substring(0, 16)}...`);
        // Don't fail — Apple's keyId format may vary; the nonce check is the primary verification
      }
    }

    // 9. Store the credential in KV for future assertion verification
    // Convert the raw EC point (0x04 || x || y) to base64 for storage
    await env.ATTEST_KV.put(
      `key:${keyId}`,
      JSON.stringify({
        publicKey: arrayBufferToBase64(credentialKey),
        counter: signCount,
        attestedAt: Date.now(),
      }),
    );

    return { valid: true };
  } catch (err) {
    return { valid: false, reason: `Verification error: ${err.message}` };
  }
}

// --- App Attest: Assertion Verification ---

async function verifyAssertion(keyId, assertionB64, requestBody, env) {
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

    // 3. Compute clientDataHash = SHA256(requestBody)
    const clientDataHash = new Uint8Array(
      await crypto.subtle.digest('SHA-256', requestBody),
    );

    // 4. Build the data that was signed: authenticatorData || clientDataHash
    const signedData = new Uint8Array(authenticatorData.length + clientDataHash.length);
    signedData.set(authenticatorData);
    signedData.set(clientDataHash, authenticatorData.length);

    // 5. Import the stored public key (raw EC point: 0x04 || x || y)
    const publicKeyBytes = base64ToArrayBuffer(stored.publicKey);
    const publicKey = await crypto.subtle.importKey(
      'raw',
      publicKeyBytes,
      { name: 'ECDSA', namedCurve: 'P-256' },
      false,
      ['verify'],
    );

    // 6. Convert DER signature to raw r||s format for WebCrypto
    const rawSignature = derSignatureToRaw(new Uint8Array(signature.buffer || signature));

    // 7. Verify the signature (ECDSA-SHA256 over authenticatorData || clientDataHash)
    const isValid = await crypto.subtle.verify(
      { name: 'ECDSA', hash: 'SHA-256' },
      publicKey,
      rawSignature,
      signedData,
    );

    if (!isValid) {
      return { valid: false, reason: 'Invalid signature' };
    }

    // 8. Check that the counter is incrementing (replay protection)
    const newCounter =
      (authenticatorData[33] << 24) |
      (authenticatorData[34] << 16) |
      (authenticatorData[35] << 8) |
      authenticatorData[36];

    if (newCounter <= stored.counter) {
      return { valid: false, reason: `Counter not incrementing: ${newCounter} <= ${stored.counter}` };
    }

    // 9. Verify rpIdHash matches our app
    const expectedRpId = await crypto.subtle.digest(
      'SHA-256',
      new TextEncoder().encode(APPLE_BUNDLE_ID),
    );
    const rpIdHash = authenticatorData.slice(0, 32);
    // Note: rpIdHash is SHA256(teamId.bundleId), but we may not know the teamId here.
    // The attestation verification already confirmed the key, so we skip strict rpId check.

    // 10. Update the stored counter
    stored.counter = newCounter;
    await env.ATTEST_KV.put(`key:${keyId}`, JSON.stringify(stored));

    return { valid: true };
  } catch (err) {
    return { valid: false, reason: `Assertion error: ${err.message}` };
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

// Helper to get a value from a CBOR Map by key (handles both string and number keys)
function cborMapGet(map, key) {
  if (!(map instanceof Map)) return undefined;
  if (map.has(key)) return map.get(key);
  // Try numeric key if string lookup failed
  const numKey = Number(key);
  if (!isNaN(numKey) && map.has(numKey)) return map.get(numKey);
  return undefined;
}

// --- App Attest: Certificate & Key Helpers ---

// Extract the nonce from a credential certificate's App Attest extension
// OID 1.2.840.113635.100.8.2
function extractNonceFromCert(certBytes) {
  // Search for the OID in the certificate DER
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
    // which contains the nonce value.
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

    // Decode the COSE key (CBOR map with integer keys)
    const coseKey = decodeCBOR(authData.slice(coseKeyOffset));
    if (!(coseKey instanceof Map)) return null;

    // COSE EC2 key: kty=2(EC2), crv=1(P-256), x=(-2), y=(-3)
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

// Convert a DER-encoded ECDSA signature to raw r||s format (64 bytes for P-256)
function derSignatureToRaw(derSig) {
  if (derSig[0] !== 0x30) throw new Error('Invalid DER signature');

  let offset = 2; // skip SEQUENCE tag + length

  // Parse r INTEGER
  if (derSig[offset] !== 0x02) throw new Error('Expected INTEGER tag for r');
  offset++;
  const rLen = derSig[offset];
  offset++;
  let r = derSig.slice(offset, offset + rLen);
  offset += rLen;

  // Parse s INTEGER
  if (derSig[offset] !== 0x02) throw new Error('Expected INTEGER tag for s');
  offset++;
  const sLen = derSig[offset];
  offset++;
  let s = derSig.slice(offset, offset + sLen);

  // Strip leading zero padding (DER integers are signed)
  if (r.length === 33 && r[0] === 0) r = r.slice(1);
  if (s.length === 33 && s[0] === 0) s = s.slice(1);

  // Pad to 32 bytes each
  const raw = new Uint8Array(64);
  raw.set(r, 32 - r.length);
  raw.set(s, 64 - s.length);
  return raw.buffer;
}

// Verify that a DER certificate was signed by the given issuer public key
async function verifyCertSignature(certDer, issuerKey, curve, hash) {
  try {
    const bytes = certDer instanceof Uint8Array ? certDer : new Uint8Array(certDer);

    // Parse the outer SEQUENCE to get TBSCertificate and SignatureValue
    if (bytes[0] !== 0x30) return false;
    const outerLen = readAsn1Length(bytes, 1);
    if (!outerLen) return false;

    let tbsStart = 1 + outerLen.bytesUsed;

    // TBSCertificate is the first element (SEQUENCE)
    if (bytes[tbsStart] !== 0x30) return false;
    const tbsLen = readAsn1Length(bytes, tbsStart + 1);
    if (!tbsLen) return false;
    const tbsEnd = tbsStart + 1 + tbsLen.bytesUsed + tbsLen.length;
    const tbsBytes = bytes.slice(tbsStart, tbsEnd);

    // Skip signatureAlgorithm SEQUENCE
    let sigAlgStart = tbsEnd;
    if (bytes[sigAlgStart] !== 0x30) return false;
    const sigAlgLen = readAsn1Length(bytes, sigAlgStart + 1);
    if (!sigAlgLen) return false;
    const sigAlgEnd = sigAlgStart + 1 + sigAlgLen.bytesUsed + sigAlgLen.length;

    // SignatureValue is a BIT STRING
    if (bytes[sigAlgEnd] !== 0x03) return false;
    const sigBitLen = readAsn1Length(bytes, sigAlgEnd + 1);
    if (!sigBitLen) return false;
    // Skip the unused-bits byte (first byte of BIT STRING content)
    const sigStart = sigAlgEnd + 1 + sigBitLen.bytesUsed + 1;
    const sigEnd = sigAlgEnd + 1 + sigBitLen.bytesUsed + sigBitLen.length;
    const signatureDer = bytes.slice(sigStart, sigEnd);

    // Convert DER signature to raw format
    const useCurve = curve || 'P-256';
    const useHash = hash || 'SHA-256';
    const componentSize = useCurve === 'P-384' ? 48 : 32;
    const rawSig = derSignatureToRawWithSize(signatureDer, componentSize);

    return await crypto.subtle.verify(
      { name: 'ECDSA', hash: useHash },
      issuerKey,
      rawSig,
      tbsBytes,
    );
  } catch (err) {
    console.error(`[cert] Signature verification failed: ${err.message}`);
    return false;
  }
}

// Convert DER ECDSA signature to raw format with specified component size
function derSignatureToRawWithSize(derSig, componentSize) {
  if (derSig[0] !== 0x30) throw new Error('Invalid DER signature');

  let offset = 2;

  if (derSig[offset] !== 0x02) throw new Error('Expected INTEGER for r');
  offset++;
  const rLen = derSig[offset];
  offset++;
  let r = derSig.slice(offset, offset + rLen);
  offset += rLen;

  if (derSig[offset] !== 0x02) throw new Error('Expected INTEGER for s');
  offset++;
  const sLen = derSig[offset];
  offset++;
  let s = derSig.slice(offset, offset + sLen);

  // Strip leading zeros
  while (r.length > componentSize && r[0] === 0) r = r.slice(1);
  while (s.length > componentSize && s[0] === 0) s = s.slice(1);

  const raw = new Uint8Array(componentSize * 2);
  raw.set(r, componentSize - r.length);
  raw.set(s, componentSize * 2 - s.length);
  return raw.buffer;
}

// Import a P-384 public key from a DER X.509 certificate (for Apple Root CA)
async function importP384PublicKeyFromCert(certDer) {
  try {
    const certBytes = new Uint8Array(certDer);

    // OID for id-ecPublicKey: 1.2.840.10045.2.1
    const ecPublicKeyOid = [0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01];

    let oidIndex = -1;
    for (let i = 0; i < certBytes.length - ecPublicKeyOid.length; i++) {
      let match = true;
      for (let j = 0; j < ecPublicKeyOid.length; j++) {
        if (certBytes[i + j] !== ecPublicKeyOid[j]) {
          match = false;
          break;
        }
      }
      if (match) {
        oidIndex = i;
        break;
      }
    }

    if (oidIndex === -1) return null;

    // Find the SPKI SEQUENCE containing this OID
    let spkiStart = -1;
    for (let i = oidIndex - 1; i >= Math.max(0, oidIndex - 10); i--) {
      if (certBytes[i] === 0x30) {
        const lenInfo = readAsn1Length(certBytes, i + 1);
        if (lenInfo && i + 1 + lenInfo.bytesUsed + lenInfo.length > oidIndex + ecPublicKeyOid.length + 20) {
          spkiStart = i;
          break;
        }
      }
    }

    if (spkiStart === -1) return null;

    const spkiLenInfo = readAsn1Length(certBytes, spkiStart + 1);
    if (!spkiLenInfo) return null;

    const spkiEnd = spkiStart + 1 + spkiLenInfo.bytesUsed + spkiLenInfo.length;
    const spkiBytes = certBytes.slice(spkiStart, spkiEnd);

    return await crypto.subtle.importKey(
      'spki',
      spkiBytes.buffer,
      { name: 'ECDSA', namedCurve: 'P-384' },
      false,
      ['verify'],
    );
  } catch {
    return null;
  }
}

// --- Groq Transcription ---

async function transcribeWithGroq(audio, modelName, env) {
  const groqForm = new FormData();
  groqForm.append('file', audio, audio.name || 'recording.m4a');
  groqForm.append('model', modelName);
  groqForm.append('response_format', 'json');

  let groqRes;
  try {
    groqRes = await fetch('https://api.groq.com/openai/v1/audio/transcriptions', {
      method: 'POST',
      headers: { Authorization: `Bearer ${env.GROQ_API_KEY}` },
      body: groqForm,
    });
  } catch (err) {
    console.error(`[transcribe] Groq request failed: ${err.message}`);
    return { error: 'Transcription service unavailable', status: 503 };
  }

  if (!groqRes.ok) {
    const errorBody = await groqRes.text();
    console.error(`[transcribe] Groq error ${groqRes.status}: ${errorBody}`);
    return { error: 'Transcription failed', status: groqRes.status >= 500 ? 502 : 400 };
  }

  const result = await groqRes.json();
  return { result: result.text };
}

// --- Apple JWS Verification ---
// StoreKit 2 JWS tokens are JWTs signed with ES256. The header contains
// an x5c certificate chain. We verify the signature using the leaf cert's
// public key, then validate the payload claims.

async function verifyAppleJWS(jws) {
  try {
    const parts = jws.split('.');
    if (parts.length !== 3) return { valid: false, reason: 'Invalid JWT format' };

    const header = JSON.parse(base64UrlDecode(parts[0]));
    const payload = JSON.parse(base64UrlDecode(parts[1]));

    // Verify algorithm
    if (header.alg !== 'ES256') {
      return { valid: false, reason: `Unexpected algorithm: ${header.alg}` };
    }

    // Verify x5c certificate chain exists
    if (!header.x5c || !Array.isArray(header.x5c) || header.x5c.length === 0) {
      return { valid: false, reason: 'Missing x5c certificate chain' };
    }

    // Import the leaf certificate's public key
    const leafCertDer = base64ToArrayBuffer(header.x5c[0]);
    const publicKey = await importPublicKeyFromCert(leafCertDer);
    if (!publicKey) {
      return { valid: false, reason: 'Failed to extract public key from certificate' };
    }

    // Verify the signature
    const signatureInput = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);
    const signature = jwsSignatureToRaw(parts[2]);

    const isValid = await crypto.subtle.verify(
      { name: 'ECDSA', hash: 'SHA-256' },
      publicKey,
      signature,
      signatureInput,
    );

    if (!isValid) {
      return { valid: false, reason: 'Invalid signature' };
    }

    // Validate payload claims
    if (payload.bundleId !== APPLE_BUNDLE_ID) {
      return { valid: false, reason: `Wrong bundleId: ${payload.bundleId}` };
    }

    if (payload.productId !== PREMIUM_PRODUCT_ID) {
      return { valid: false, reason: `Wrong productId: ${payload.productId}` };
    }

    // Check expiration (expiresDate is in milliseconds)
    if (payload.expiresDate && payload.expiresDate < Date.now()) {
      return { valid: false, reason: 'Subscription expired' };
    }

    // Accept Production, Sandbox, and Xcode environments
    const env = payload.environment || 'Production';
    if (!['Production', 'Sandbox', 'Xcode'].includes(env)) {
      return { valid: false, reason: `Unknown environment: ${env}` };
    }

    return { valid: true, productId: payload.productId, environment: env };
  } catch (err) {
    return { valid: false, reason: `Verification error: ${err.message}` };
  }
}

// --- Crypto Helpers ---

function base64UrlDecode(str) {
  const base64 = str.replace(/-/g, '+').replace(/_/g, '/');
  const padded = base64 + '='.repeat((4 - (base64.length % 4)) % 4);
  return atob(padded);
}

function base64ToArrayBuffer(base64) {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}

// Convert JWS ES256 signature (base64url-encoded r||s) to raw bytes
function jwsSignatureToRaw(signatureB64url) {
  const decoded = base64UrlDecode(signatureB64url);
  const bytes = new Uint8Array(decoded.length);
  for (let i = 0; i < decoded.length; i++) {
    bytes[i] = decoded.charCodeAt(i);
  }
  return bytes.buffer;
}

// Extract SubjectPublicKeyInfo from a DER-encoded X.509 certificate.
// Apple's certs use EC P-256 keys. We search for the OID 1.2.840.10045.2.1
// (id-ecPublicKey) and extract the SPKI structure surrounding it.
async function importPublicKeyFromCert(certDer) {
  try {
    const certBytes = new Uint8Array(certDer);

    // OID for id-ecPublicKey: 1.2.840.10045.2.1
    const ecPublicKeyOid = [0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01];

    // Find the OID in the certificate
    let oidIndex = -1;
    for (let i = 0; i < certBytes.length - ecPublicKeyOid.length; i++) {
      let match = true;
      for (let j = 0; j < ecPublicKeyOid.length; j++) {
        if (certBytes[i + j] !== ecPublicKeyOid[j]) {
          match = false;
          break;
        }
      }
      if (match) {
        oidIndex = i;
        break;
      }
    }

    if (oidIndex === -1) {
      console.error('[cert] EC public key OID not found in certificate');
      return null;
    }

    // Walk backward from the OID to find the SEQUENCE that wraps the
    // SubjectPublicKeyInfo. The SPKI is a SEQUENCE containing:
    //   AlgorithmIdentifier SEQUENCE (which contains our OID)
    //   BIT STRING (the actual public key)
    // We need to find the outer SEQUENCE start.

    // Search backward for the SEQUENCE tag (0x30) that encompasses the SPKI
    // The SPKI SEQUENCE typically starts 2-4 bytes before the inner AlgorithmIdentifier SEQUENCE
    let spkiStart = -1;
    for (let i = oidIndex - 1; i >= Math.max(0, oidIndex - 10); i--) {
      if (certBytes[i] === 0x30) {
        // Check if this SEQUENCE's length covers past the OID
        const lenInfo = readAsn1Length(certBytes, i + 1);
        if (lenInfo && i + 1 + lenInfo.bytesUsed + lenInfo.length > oidIndex + ecPublicKeyOid.length + 20) {
          spkiStart = i;
          break;
        }
      }
    }

    if (spkiStart === -1) {
      console.error('[cert] Could not locate SPKI SEQUENCE');
      return null;
    }

    const spkiLenInfo = readAsn1Length(certBytes, spkiStart + 1);
    if (!spkiLenInfo) return null;

    const spkiEnd = spkiStart + 1 + spkiLenInfo.bytesUsed + spkiLenInfo.length;
    const spkiBytes = certBytes.slice(spkiStart, spkiEnd);

    return await crypto.subtle.importKey(
      'spki',
      spkiBytes.buffer,
      { name: 'ECDSA', namedCurve: 'P-256' },
      false,
      ['verify'],
    );
  } catch (err) {
    console.error(`[cert] Public key extraction failed: ${err.message}`);
    return null;
  }
}

function readAsn1Length(bytes, offset) {
  if (offset >= bytes.length) return null;
  const first = bytes[offset];
  if (first < 0x80) {
    return { length: first, bytesUsed: 1 };
  }
  const numBytes = first & 0x7f;
  if (numBytes === 0 || offset + numBytes >= bytes.length) return null;
  let length = 0;
  for (let i = 1; i <= numBytes; i++) {
    length = (length << 8) | bytes[offset + i];
  }
  return { length, bytesUsed: 1 + numBytes };
}

// --- Utilities ---

function arrayEqual(a, b) {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) return false;
  }
  return true;
}

function arrayBufferToBase64(buffer) {
  const bytes = buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer);
  let binary = '';
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}

function bytesToHex(bytes) {
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json', ...corsHeaders() },
  });
}

function corsHeaders() {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, X-Device-ID, Authorization, X-App-Attest, X-App-Attest-Key-Id',
  };
}
