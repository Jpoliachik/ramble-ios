const ALLOWED_MODELS = ['whisper-large-v3-turbo', 'whisper-large-v3'];
const DEFAULT_MODEL = 'whisper-large-v3-turbo';
const APPLE_BUNDLE_ID = 'com.goodloop.ramble';
const PREMIUM_PRODUCT_ID = 'com.goodloop.ramble.premium.monthly';

// Apple Root CA - G3 (public key SHA-256 fingerprint for chain validation)
// This is the root CA that signs App Store JWS transactions.
const APPLE_ROOT_CA_G3_FINGERPRINT =
  '63343abfb89a6a03ebbe1e8feda1be2f7f3fbc2a5391d024a45d7bc2c34d3a8c';

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }

    const url = new URL(request.url);

    if (url.pathname === '/transcribe' && request.method === 'POST') {
      return handleTranscribe(request, env);
    }

    if (url.pathname === '/health') {
      return json({ status: 'ok' });
    }

    return json({ error: 'Not found' }, 404);
  },
};

async function handleTranscribe(request, env) {
  const deviceId = request.headers.get('X-Device-ID') || 'unknown';

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

  // --- Parse form data ---
  let formData;
  try {
    formData = await request.formData();
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
    'Access-Control-Allow-Headers': 'Content-Type, X-Device-ID, Authorization',
  };
}
