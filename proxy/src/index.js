import { handleAttestChallenge, handleAttest, verifyAssertionForRequest } from './attest.js';
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

// OpenAI's `gpt-4o-transcribe` retires around June 2026; `gpt-4o-transcribe-diarize`
// is the GA successor (retires 2027-04-16). We ignore diarization metadata and
// extract only the plain transcript.
const OPENAI_MODEL = 'gpt-4o-transcribe-diarize';

// Languages Deepgram Nova-3 supports as a `language=` hint. Mirror of
// `CloudModel.deepgramNova3Languages` in Ramble/Models/Settings.swift —
// keep in sync. Anything outside this set falls back to English.
// Authoritative list (Deepgram adds languages periodically — check before
// expanding the iOS enum):
//   https://developers.deepgram.com/docs/models-languages-overview
const DEEPGRAM_NOVA3_LANGUAGES = new Set([
  'ar','bg','bn','ca','cs','da','de','el','en','es','et','fa','fi','fr','he',
  'hi','hr','hu','id','it','ja','ko','lt','lv','ms','nl','no','pl','pt','ro',
  'ru','sk','sv','ta','te','th','tl','tr','uk','ur','vi','zh',
]);

// Filler words stripped from Whisper/OpenAI output when remove_filler_words=true.
// Deepgram already excludes fillers by default. Conservative list — only the
// disfluencies most users want gone, not slang ("like", "you know") which is
// often meaningful.
const FILLER_REGEX = /\b(?:um+|uh+|er+|ah+|hmm+|mhm+|uhm+|erm+)\b[\s,.;:!?]*/gi;
const APPLE_BUNDLE_ID = 'dev.goodloop.Ramble';
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

  const assertionResult = await verifyAssertionForRequest(attestKeyId, attestAssertionB64, bodyBuffer, env);
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

  // --- Optional transcription tuning ---
  const language = (formData.get('language') || '').trim().toLowerCase() || null;
  const vocabulary = (formData.get('vocabulary') || '').trim();
  const removeFillerWords = formData.get('remove_filler_words') === 'true';

  const options = { language, vocabulary };

  console.log(
    `[transcribe] device=${deviceId} model=${requestedModel} lang=${language || 'auto'} vocab=${vocabulary ? 'yes' : 'no'} fillers=${removeFillerWords ? 'strip' : 'keep'} file=${audio.name} size=${audio.size}`,
  );

  // --- Route to appropriate backend ---
  const startTime = Date.now();
  let result;
  if (requestedModel.startsWith('deepgram-')) {
    result = await transcribeWithDeepgram(audio, options, env);
  } else if (requestedModel.startsWith('openai-')) {
    result = await transcribeWithOpenAI(audio, options, env);
  } else {
    result = await transcribeWithGroq(audio, requestedModel, options, env);
  }
  const durationMs = Date.now() - startTime;

  // Post-process: strip fillers from Whisper/OpenAI output.
  // Deepgram's default excludes fillers, so we skip it there.
  if (!result.error && removeFillerWords && !requestedModel.startsWith('deepgram-')) {
    result.result = stripFillerWords(result.result);
  }

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

async function transcribeWithGroq(audio, modelName, options, env) {
  const groqForm = new FormData();
  groqForm.append('file', audio, audio.name || 'recording.m4a');
  groqForm.append('model', modelName);
  groqForm.append('response_format', 'verbose_json');
  if (options.language) {
    groqForm.append('language', options.language);
  }
  if (options.vocabulary) {
    // Whisper `prompt` accepts up to ~224 tokens of context — names, jargon, etc.
    groqForm.append('prompt', options.vocabulary);
  }

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

  const data = await groqRes.json();

  // Use segments to insert paragraph breaks on pauses (>2s gap between segments)
  if (data.segments && data.segments.length > 0) {
    return { result: formatSegmentsIntoParagraphs(data.segments) };
  }

  return { result: data.text };
}

// --- Deepgram Transcription ---

async function transcribeWithDeepgram(audio, options, env) {
  if (!env.DEEPGRAM_API_KEY) {
    return { error: 'Deepgram API key not configured', status: 503 };
  }

  const audioBuffer = await audio.arrayBuffer();

  const params = new URLSearchParams({
    model: 'nova-3',
    smart_format: 'true',
    paragraphs: 'true',
    // Auto-detect: use `multi` to handle codeswitching across the 10-language
    // set. Explicit user choices are passed through verbatim — respecting the
    // user's pick is more accurate than overriding with `multi` on the chance
    // they might also speak another language.
    language: resolveDeepgramLanguage(options.language),
  });
  if (options.vocabulary) {
    // Deepgram supports `keyterm` repeated; a single comma-separated list is
    // accepted as one term but multiple terms work better — split on commas/newlines.
    const terms = options.vocabulary
      .split(/[,\n]+/)
      .map((t) => t.trim())
      .filter(Boolean);
    for (const term of terms) {
      params.append('keyterm', term);
    }
  }

  let res;
  try {
    res = await fetch(`https://api.deepgram.com/v1/listen?${params.toString()}`, {
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
  const alternative = data.results?.channels?.[0]?.alternatives?.[0];
  const transcript = alternative?.paragraphs?.transcript ?? alternative?.transcript;

  if (transcript === undefined || transcript === null) {
    return { error: 'No transcript in Deepgram response', status: 502 };
  }

  return { result: transcript };
}

// --- OpenAI Transcription ---

async function transcribeWithOpenAI(audio, options, env) {
  if (!env.OPENAI_API_KEY) {
    return { error: 'OpenAI API key not configured', status: 503 };
  }

  const form = new FormData();
  form.append('file', audio, audio.name || 'recording.m4a');
  form.append('model', OPENAI_MODEL);
  // diarize model returns `diarized_json`; we ignore speaker labels and
  // concatenate segment text. `chunking_strategy=auto` is required for audio
  // longer than 30s.
  form.append('response_format', 'diarized_json');
  form.append('chunking_strategy', 'auto');
  if (options.language) {
    form.append('language', options.language);
  }
  if (options.vocabulary) {
    form.append('prompt', options.vocabulary);
  }

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

  // diarized_json: { segments: [{ speaker, text, start, end }, ...] }
  // plain json: { text: "..." }
  if (Array.isArray(data.segments) && data.segments.length > 0) {
    const hasTimings = data.segments.every((s) => typeof s.start === 'number' && typeof s.end === 'number');
    return {
      result: hasTimings
        ? formatSegmentsIntoParagraphs(data.segments)
        : data.segments.map((s) => (s.text || '').trim()).filter(Boolean).join(' '),
    };
  }
  if (typeof data.text === 'string') {
    return { result: data.text };
  }
  return { error: 'No transcript in OpenAI response', status: 502 };
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

// --- Transcript Formatting ---

/**
 * Group segments into paragraphs based on pauses in speech.
 * A gap of >2 seconds between segments triggers a paragraph break.
 */
function formatSegmentsIntoParagraphs(segments, pauseThreshold = 2.0) {
  if (segments.length === 0) return '';

  const paragraphs = [];
  let currentParagraph = [segments[0].text.trim()];

  for (let i = 1; i < segments.length; i++) {
    const gap = segments[i].start - segments[i - 1].end;
    if (gap >= pauseThreshold) {
      paragraphs.push(currentParagraph.join(' '));
      currentParagraph = [];
    }
    currentParagraph.push(segments[i].text.trim());
  }

  if (currentParagraph.length > 0) {
    paragraphs.push(currentParagraph.join(' '));
  }

  return paragraphs.join('\n\n');
}

/**
 * Remove disfluencies ("um", "uh", "er", "hmm", etc.) from a transcript and
 * collapse the resulting whitespace.
 */
function resolveDeepgramLanguage(code) {
  if (!code) return 'multi';
  if (DEEPGRAM_NOVA3_LANGUAGES.has(code)) return code;
  return 'en';
}

function stripFillerWords(text) {
  if (!text) return text;
  const stripped = text.replace(FILLER_REGEX, '');
  // Collapse multiple spaces but preserve paragraph breaks.
  return stripped
    .split('\n')
    .map((line) => line.replace(/[ \t]+/g, ' ').replace(/\s+([,.!?;:])/g, '$1').trim())
    .join('\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
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
