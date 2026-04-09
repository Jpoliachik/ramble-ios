import { handleAttestChallenge, handleAttest, verifyAssertion } from './attest.js';
import {
  base64ToArrayBuffer,
  base64UrlDecode,
  importPublicKeyFromCert,
  jwsSignatureToRaw,
} from './crypto.js';

const ALLOWED_MODELS = ['whisper-large-v3-turbo', 'whisper-large-v3'];
const DEFAULT_MODEL = 'whisper-large-v3-turbo';
const APPLE_BUNDLE_ID = 'dev.goodloop.ramble';
const PREMIUM_PRODUCT_ID = 'dev.goodloop.ramble.premium.monthly2';

// Apple Root CA - G3 (public key SHA-256 fingerprint for chain validation)
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

    if (url.pathname === '/attest/challenge' && request.method === 'POST') {
      const result = await handleAttestChallenge(request, env);
      return json(result);
    }

    if (url.pathname === '/attest' && request.method === 'POST') {
      const result = await handleAttest(request, env);
      if (result.error) {
        return json({ error: result.error }, result.status);
      }
      return json({ status: 'ok' });
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

async function verifyAppleJWS(jws) {
  try {
    const parts = jws.split('.');
    if (parts.length !== 3) return { valid: false, reason: 'Invalid JWT format' };

    const header = JSON.parse(base64UrlDecode(parts[0]));
    const payload = JSON.parse(base64UrlDecode(parts[1]));

    if (header.alg !== 'ES256') {
      return { valid: false, reason: `Unexpected algorithm: ${header.alg}` };
    }

    if (!header.x5c || !Array.isArray(header.x5c) || header.x5c.length === 0) {
      return { valid: false, reason: 'Missing x5c certificate chain' };
    }

    const leafCertDer = base64ToArrayBuffer(header.x5c[0]);
    const publicKey = await importPublicKeyFromCert(leafCertDer);
    if (!publicKey) {
      return { valid: false, reason: 'Failed to extract public key from certificate' };
    }

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

    if (payload.bundleId !== APPLE_BUNDLE_ID) {
      return { valid: false, reason: `Wrong bundleId: ${payload.bundleId}` };
    }

    if (payload.productId !== PREMIUM_PRODUCT_ID) {
      return { valid: false, reason: `Wrong productId: ${payload.productId}` };
    }

    if (payload.expiresDate && payload.expiresDate < Date.now()) {
      return { valid: false, reason: 'Subscription expired' };
    }

    const env = payload.environment || 'Production';
    if (!['Production', 'Sandbox', 'Xcode'].includes(env)) {
      return { valid: false, reason: `Unknown environment: ${env}` };
    }

    return { valid: true, productId: payload.productId, environment: env };
  } catch (err) {
    return { valid: false, reason: `Verification error: ${err.message}` };
  }
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
    'Access-Control-Allow-Headers': 'Content-Type, X-Device-ID, Authorization, X-App-Attest, X-App-Attest-Key-Id',
  };
}
