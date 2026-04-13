import { handleAttestChallenge, handleAttest, verifyAssertion } from './attest.js';
import { writeTranscriptionEvent } from './analytics.js';
import {
  base64ToArrayBuffer,
  base64UrlDecode,
  importPublicKeyFromCert,
  jwsSignatureToRaw,
} from './crypto.js';

const ALLOWED_MODELS = [
  'whisper-large-v3-turbo',
  'whisper-large-v3',
  'deepgram-nova-3',
  'openai-gpt-4o-transcribe',
];
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

    if (url.pathname === '/analytics' && request.method === 'GET') {
      return handleAnalytics(request, env);
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

  if (!attestKeyId || !attestAssertionB64) {
    console.error(`[attest] Missing attestation headers device=${deviceId}`);
    return json({ error: 'App attestation required' }, 403);
  }

  const assertionResult = await verifyAssertion(attestKeyId, attestAssertionB64, bodyBuffer, env);
  if (!assertionResult.valid) {
    console.error(`[attest] Assertion failed: ${assertionResult.reason} device=${deviceId}`);
    return json({ error: 'App attestation failed' }, 403);
  }
  console.log(`[attest] Assertion verified device=${deviceId} keyId=${attestKeyId.substring(0, 8)}...`);

  // --- Subscription Verification ---
  const authHeader = request.headers.get('Authorization') || '';
  let authBypassed = false;

  if (authHeader.startsWith('DevBypass ') && env.DEV_BYPASS_TOKEN) {
    const token = authHeader.slice('DevBypass '.length);
    if (token === env.DEV_BYPASS_TOKEN) {
      authBypassed = true;
      console.log(`[auth] Dev bypass accepted device=${deviceId}`);
    } else {
      return json({ error: 'Invalid dev bypass token' }, 403);
    }
  }

  if (!authBypassed) {
    if (!authHeader.startsWith('Bearer ')) {
      return json({ error: 'Premium subscription required' }, 403);
    }

    const jws = authHeader.slice(7);
    const verifyResult = await verifyAppleJWS(jws);
    if (!verifyResult.valid) {
      console.error(`[auth] JWS verification failed: ${verifyResult.reason} device=${deviceId}`);
      return json({ error: 'Premium subscription required' }, 403);
    }

    console.log(`[auth] JWS verified device=${deviceId} product=${verifyResult.productId}`);
  }

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

  // --- Route to appropriate backend ---
  const startTime = Date.now();
  let result;
  if (requestedModel.startsWith('deepgram-')) {
    result = await transcribeWithDeepgram(audio, env);
  } else if (requestedModel.startsWith('openai-')) {
    result = await transcribeWithOpenAI(audio, env);
  } else {
    result = await transcribeWithGroq(audio, requestedModel, env);
  }
  const durationMs = Date.now() - startTime;

  if (result.error) {
    writeTranscriptionEvent(env, {
      deviceId,
      model: requestedModel,
      audioSize: audio.size,
      textLength: 0,
      durationMs,
      error: result.error,
    });
    return json({ error: result.error }, result.status);
  }

  const textLength = result.result?.length || 0;
  console.log(`[transcribe] device=${deviceId} text_length=${textLength} duration=${durationMs}ms`);

  writeTranscriptionEvent(env, {
    deviceId,
    model: requestedModel,
    audioSize: audio.size,
    textLength,
    durationMs,
    error: null,
  });

  return json({ text: result.result });
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

// --- Deepgram Transcription ---

async function transcribeWithDeepgram(audio, env) {
  if (!env.DEEPGRAM_API_KEY) {
    return { error: 'Deepgram API key not configured', status: 503 };
  }

  const audioBuffer = await audio.arrayBuffer();

  let res;
  try {
    res = await fetch('https://api.deepgram.com/v1/listen?model=nova-3&smart_format=true', {
      method: 'POST',
      headers: {
        Authorization: `Token ${env.DEEPGRAM_API_KEY}`,
        'Content-Type': audio.type || 'audio/m4a',
      },
      body: audioBuffer,
    });
  } catch (err) {
    console.error(`[transcribe] Deepgram request failed: ${err.message}`);
    return { error: 'Transcription service unavailable', status: 503 };
  }

  if (!res.ok) {
    const errorBody = await res.text();
    console.error(`[transcribe] Deepgram error ${res.status}: ${errorBody}`);
    return { error: 'Transcription failed', status: res.status >= 500 ? 502 : 400 };
  }

  const data = await res.json();
  const transcript = data.results?.channels?.[0]?.alternatives?.[0]?.transcript;

  if (transcript === undefined || transcript === null) {
    return { error: 'No transcript in Deepgram response', status: 502 };
  }

  return { result: transcript };
}

// --- OpenAI Transcription ---

async function transcribeWithOpenAI(audio, env) {
  if (!env.OPENAI_API_KEY) {
    return { error: 'OpenAI API key not configured', status: 503 };
  }

  const form = new FormData();
  form.append('file', audio, audio.name || 'recording.m4a');
  form.append('model', 'gpt-4o-transcribe');
  form.append('response_format', 'json');

  let res;
  try {
    res = await fetch('https://api.openai.com/v1/audio/transcriptions', {
      method: 'POST',
      headers: { Authorization: `Bearer ${env.OPENAI_API_KEY}` },
      body: form,
    });
  } catch (err) {
    console.error(`[transcribe] OpenAI request failed: ${err.message}`);
    return { error: 'Transcription service unavailable', status: 503 };
  }

  if (!res.ok) {
    const errorBody = await res.text();
    console.error(`[transcribe] OpenAI error ${res.status}: ${errorBody}`);
    return { error: 'Transcription failed', status: res.status >= 500 ? 502 : 400 };
  }

  const data = await res.json();
  return { result: data.text };
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

// --- Admin Analytics ---

async function handleAnalytics(request, env) {
  // Protected by a shared secret — set ANALYTICS_TOKEN via `wrangler secret put ANALYTICS_TOKEN`
  const token = new URL(request.url).searchParams.get('token');
  if (!env.ANALYTICS_TOKEN || token !== env.ANALYTICS_TOKEN) {
    return json({ error: 'Unauthorized' }, 401);
  }

  if (!env.USAGE_ANALYTICS) {
    return json({ error: 'Analytics Engine not configured' }, 503);
  }

  const days = Math.min(parseInt(new URL(request.url).searchParams.get('days') || '7', 10), 90);

  // Run all queries in parallel
  const [overview, byModel, daily, uniqueDevices] = await Promise.all([
    // Overall counts and averages
    env.USAGE_ANALYTICS.sql(`
      SELECT
        count() as total_requests,
        sum(if(blob3 = 'success', 1, 0)) as successes,
        sum(if(blob3 = 'error', 1, 0)) as errors,
        avg(double1) as avg_audio_bytes,
        avg(double2) as avg_text_length,
        avg(double3) as avg_duration_ms
      FROM ramble_usage
      WHERE timestamp > now() - interval '${days}' day
    `),

    // Breakdown by model
    env.USAGE_ANALYTICS.sql(`
      SELECT
        blob1 as model,
        blob2 as provider,
        count() as requests,
        sum(if(blob3 = 'success', 1, 0)) as successes,
        avg(double1) as avg_audio_bytes,
        avg(double2) as avg_text_length,
        avg(double3) as avg_duration_ms
      FROM ramble_usage
      WHERE timestamp > now() - interval '${days}' day
      GROUP BY blob1, blob2
      ORDER BY requests DESC
    `),

    // Daily volume
    env.USAGE_ANALYTICS.sql(`
      SELECT
        toDate(timestamp) as date,
        count() as requests,
        sum(if(blob3 = 'success', 1, 0)) as successes
      FROM ramble_usage
      WHERE timestamp > now() - interval '${days}' day
      GROUP BY date
      ORDER BY date DESC
    `),

    // Unique devices
    env.USAGE_ANALYTICS.sql(`
      SELECT count(distinct index1) as unique_devices
      FROM ramble_usage
      WHERE timestamp > now() - interval '${days}' day
    `),
  ]);

  return json({
    period_days: days,
    overview: overview.toArray(),
    by_model: byModel.toArray(),
    daily: daily.toArray(),
    unique_devices: uniqueDevices.toArray(),
  });
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
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, X-Device-ID, Authorization, X-App-Attest, X-App-Attest-Key-Id',
  };
}
