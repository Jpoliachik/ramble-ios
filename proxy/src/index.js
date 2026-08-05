import { handleAttestChallenge, handleAttest, verifyAssertionForRequest } from './attest.js';
import { writeTranscriptionEvent } from './analytics.js';
import {
  base64ToArrayBuffer,
  base64UrlDecode,
  importPublicKeyFromCert,
  jwsSignatureToRaw,
} from './crypto.js';

// Model IDs the app may request, mapped to the provider that serves them and
// that provider's own model name. Mirror of `CloudModel` in
// Ramble/Models/Settings.swift — keep in sync.
const MODELS = {
  'whisper-large-v3-turbo': { provider: 'groq', upstream: 'whisper-large-v3-turbo' },
  'whisper-large-v3': { provider: 'groq', upstream: 'whisper-large-v3' },
  'deepgram-nova-3': { provider: 'deepgram', upstream: 'nova-3' },
  // GPT-Transcribe replaced the gpt-4o-transcribe family (OpenAI's own Real
  // World Audio Benchmark: 8.98% WER vs 15.21% for Whisper). Unlike the 4o
  // models it takes structured `keywords[]`/`languages[]` hints and returns
  // JSON only — see transcribeWithOpenAI.
  'openai-gpt-transcribe': { provider: 'openai', upstream: 'gpt-transcribe' },
};
const DEFAULT_MODEL = 'whisper-large-v3-turbo';

// Model IDs that shipped in older app versions. Those builds are still in
// users' hands and can't be updated retroactively, so their requests resolve
// to the current replacement instead of failing.
const MODEL_ALIASES = {
  'openai-gpt-4o-transcribe': 'openai-gpt-transcribe',
};

/**
 * Resolve a client-requested model ID to `{ id, provider, upstream }`, or null
 * if it isn't one we serve. `id` is the canonical ID — aliases resolve to their
 * replacement so analytics doesn't split one model across two names.
 */
function resolveModel(requested) {
  const id = MODEL_ALIASES[requested] ?? requested;
  const entry = MODELS[id];
  return entry ? { id, ...entry } : null;
}

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

// Filler words stripped from any provider's output when remove_filler_words=true.
// Deepgram also filters natively via `filler_words`, but only "uh" and "um" and
// only in English, so this still does the work for the rest. Conservative list —
// only the disfluencies most users want gone, not slang ("like", "you know")
// which is often meaningful.
const FILLER_REGEX = /\b(?:um+|uh+|er+|ah+|hmm+|mhm+|uhm+|erm+)\b[\s,.;:!?]*/gi;

// Keyword hints. GPT-Transcribe rejects a request outright if any keyword
// contains `<`, `>`, or a line break, and Deepgram caps keyterms at ~500 tokens
// (~100 words) per request — so both the shape and the size are bounded here.
// The app already clamps the field to 900 characters on input.
const MAX_KEYWORDS = 100;
const MAX_KEYWORD_LENGTH = 100;

// Paragraph reconstruction for providers that return plain text. Below
// PARAGRAPH_MIN_LENGTH a transcript reads fine as one block; above it,
// sentences accumulate until a paragraph reaches PARAGRAPH_TARGET_LENGTH.
const PARAGRAPH_MIN_LENGTH = 500;
const PARAGRAPH_TARGET_LENGTH = 350;
const PARAGRAPH_ORPHAN_LENGTH = 80;

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
  const model = resolveModel(requestedModel);
  if (!model) {
    return json({ error: `Invalid model. Allowed: ${Object.keys(MODELS).join(', ')}` }, 400);
  }

  // --- Optional transcription tuning ---
  const language = (formData.get('language') || '').trim().toLowerCase() || null;
  const keywords = parseKeywords(formData.get('vocabulary') || '');
  const removeFillerWords = formData.get('remove_filler_words') === 'true';

  const options = { language, keywords, removeFillerWords };

  console.log(
    `[transcribe] device=${deviceId} model=${model.id} lang=${language || 'auto'} keywords=${keywords.length} fillers=${removeFillerWords ? 'strip' : 'keep'} file=${audio.name} size=${audio.size}`,
  );

  // --- Route to appropriate backend ---
  const startTime = Date.now();
  let result;
  switch (model.provider) {
    case 'deepgram':
      result = await transcribeWithDeepgram(audio, options, env);
      break;
    case 'openai':
      result = await transcribeWithOpenAI(audio, model.upstream, options, env);
      break;
    default:
      result = await transcribeWithGroq(audio, model.upstream, options, env);
  }
  const durationMs = Date.now() - startTime;

  // --- Post-processing ---
  if (!result.error) {
    result.result = postProcessTranscript(result.result, {
      provider: model.provider,
      keywords,
      removeFillerWords,
    });
  }

  if (result.error) {
    writeTranscriptionEvent(env, {
      deviceId,
      model: model.id,
      provider: model.provider,
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
    model: model.id,
    provider: model.provider,
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
  if (options.keywords.length > 0) {
    // Whisper `prompt` accepts up to ~224 tokens of context — names, jargon, etc.
    groqForm.append('prompt', buildWhisperPrompt(options.keywords.join(', ')));
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

/** Query string for Deepgram's `/v1/listen`. */
function buildDeepgramParams(options) {
  const params = new URLSearchParams({
    model: 'nova-3',
    smart_format: 'true',
    paragraphs: 'true',
    // Auto-detect: use `multi` to handle codeswitching across the 10-language
    // set. Explicit user choices are passed through verbatim — respecting the
    // user's pick is more accurate than overriding with `multi` on the chance
    // they might also speak another language.
    language: resolveDeepgramLanguage(options.language),
    // Deepgram strips "uh" and "um" unless asked not to, so the toggle is
    // bidirectional here: keeping fillers means opting into them explicitly.
    // Without this, turning the setting off left Deepgram transcripts
    // filler-free anyway, unlike every other model.
    //
    // Deepgram documents this as English-only, so on a `multi` or non-English
    // request it may be ignored and fillers dropped regardless. Nothing can
    // recover them after the fact; the reverse direction (strip) is covered by
    // the regex pass in postProcessTranscript, which is language-agnostic.
    filler_words: options.removeFillerWords ? 'false' : 'true',
  });

  // Keyterm prompting is repeated once per term. Nova-3 supports it for both
  // monolingual and `multi` requests, so it applies whatever the language hint.
  for (const term of options.keywords) {
    params.append('keyterm', term);
  }

  return params;
}

async function transcribeWithDeepgram(audio, options, env) {
  if (!env.DEEPGRAM_API_KEY) {
    return { error: 'Deepgram API key not configured', status: 503 };
  }

  const audioBuffer = await audio.arrayBuffer();
  const params = buildDeepgramParams(options);

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

/**
 * Multipart body for OpenAI's `/v1/audio/transcriptions`.
 *
 * Array fields are repeated with a `[]` suffix — the wire format OpenAI's own
 * SDKs generate for `keywords` and `languages`.
 */
function buildOpenAIForm(audio, upstreamModel, options) {
  const form = new FormData();
  form.append('file', audio, audio.name || 'recording.m4a');
  form.append('model', upstreamModel);
  // `gpt-transcribe` returns JSON only — `verbose_json`, `srt` and `vtt` aren't
  // valid for it, so no segment timings come back and paragraph breaks are
  // reconstructed from the text instead.
  form.append('response_format', 'json');
  // The new models take `languages[]` (repeated, ISO-639-1) rather than
  // Whisper's single `language`, and reject requests that send both.
  if (options.language) {
    form.append('languages[]', options.language);
  }
  // Literal terms belong in `keywords[]`, not `prompt`: the model treats them
  // as optional hints it only uses when the audio actually contains them, so
  // there's nothing to echo back into the transcript. `prompt` stays free for
  // describing the recording itself.
  for (const term of options.keywords) {
    form.append('keywords[]', term);
  }

  return form;
}

async function transcribeWithOpenAI(audio, upstreamModel, options, env) {
  if (!env.OPENAI_API_KEY) {
    return { error: 'OpenAI API key not configured', status: 503 };
  }

  const form = buildOpenAIForm(audio, upstreamModel, options);

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

  // json: { text: "...", languages: [{ code: "en" }] }. `languages` is the
  // model's own detection and may be an empty array — we don't use it, the
  // transcript is all the app needs.
  if (typeof data.text !== 'string') {
    return { error: 'No transcript in OpenAI response', status: 502 };
  }

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
 * Cleanup applied to a successful transcript, in order: strip any echoed
 * keyword prompt, honor the filler-word setting, then make sure the text has
 * paragraph breaks. Pure, so the ordering is covered by tests — stripping
 * fillers before grouping matters, since removing them can drop a transcript
 * back under the length where paragraphs are worth adding.
 */
function postProcessTranscript(text, { provider, keywords, removeFillerWords }) {
  let result = text;

  // Whisper occasionally echoes the `prompt` (keyword hint) at the tail of the
  // transcript. Only Groq gets its hints via `prompt` — Deepgram uses `keyterm`
  // and GPT-Transcribe uses `keywords[]`, neither of which leaks into output.
  if (keywords.length > 0 && provider === 'groq') {
    result = stripPromptEcho(result, keywords.join(', '));
  }

  // Every provider gets the regex pass, Deepgram included. `filler_words=false`
  // asks Deepgram to do its own filtering, but that only covers "uh" and "um"
  // and only for English — so for the rest of the list (er, ah, hmm, erm), or
  // on a `multi`/non-English request, the regex is what actually honors the
  // setting. Running both is harmless: the regex is a superset.
  if (removeFillerWords) {
    result = stripFillerWords(result);
  }

  // Paragraph breaks: Deepgram returns them natively, and Groq derives them
  // from segment timings whenever the speaker pauses. GPT-Transcribe always
  // returns one block, and so does a gap-free Groq recording, so fall back to
  // grouping sentences. No-op on text that already has paragraph breaks or is
  // too short to need them.
  return formatTextIntoParagraphs(result);
}

/**
 * Group a plain-text transcript into paragraphs by grouping sentences, for
 * providers that return text without timings. Deliberately conservative:
 * returns the text untouched when it already has paragraph breaks, is short
 * enough to read as one block, or has no sentence boundaries to break on.
 */
function formatTextIntoParagraphs(text) {
  if (!text) return text;

  const trimmed = text.trim();
  if (trimmed.length < PARAGRAPH_MIN_LENGTH) return trimmed;
  // Already paragraphed by the provider — leave it alone.
  if (/\n\s*\n/.test(trimmed)) return trimmed;

  // Sentence = run of non-terminator characters plus its trailing terminators
  // and any closing quote/bracket. Covers CJK terminators too.
  const sentences = trimmed.match(/[^.!?…。！？]+(?:[.!?…。！？]+["'”’)\]]*|$)/g);
  if (!sentences || sentences.length < 2) return trimmed;

  const paragraphs = [];
  let current = '';

  for (const sentence of sentences) {
    const clean = sentence.trim();
    if (!clean) continue;
    current = current ? `${current} ${clean}` : clean;
    if (current.length >= PARAGRAPH_TARGET_LENGTH) {
      paragraphs.push(current);
      current = '';
    }
  }

  if (current) {
    // Fold a stubby remainder into the previous paragraph rather than leaving
    // a one-line orphan at the end.
    if (paragraphs.length > 0 && current.length < PARAGRAPH_ORPHAN_LENGTH) {
      paragraphs[paragraphs.length - 1] += ` ${current}`;
    } else {
      paragraphs.push(current);
    }
  }

  return paragraphs.join('\n\n');
}

/**
 * Normalize the user's custom-vocabulary field into discrete keyword hints.
 *
 * Providers take these as structured lists (`keywords[]` for GPT-Transcribe,
 * repeated `keyterm` for Deepgram), and GPT-Transcribe rejects the whole
 * request if any keyword is multi-line or contains `<` or `>` — so sanitize
 * rather than trust the field.
 */
function parseKeywords(vocabulary) {
  if (!vocabulary) return [];

  const seen = new Set();
  const keywords = [];

  for (const raw of vocabulary.split(/[,\n\r]+/)) {
    const term = raw
      .replace(/[<>]/g, '')
      .replace(/\s+/g, ' ')
      .trim()
      .slice(0, MAX_KEYWORD_LENGTH)
      .trim();
    if (!term) continue;

    const key = term.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    keywords.push(term);

    if (keywords.length >= MAX_KEYWORDS) break;
  }

  return keywords;
}

function resolveDeepgramLanguage(code) {
  if (!code) return 'multi';
  if (DEEPGRAM_NOVA3_LANGUAGES.has(code)) return code;
  return 'en';
}

// Phrase the Whisper `prompt` as a complete sentence. Whisper biases toward
// outputs that continue the prompt, so a bare comma list often gets echoed
// into the transcript; framing it as already-complete prose reduces that.
function buildWhisperPrompt(vocabulary) {
  return `Names and terms that may come up: ${vocabulary}.`;
}

// Backstop for the above — if Whisper still echoes the prompt at the tail,
// strip it. Matches either the sentence form or the bare list, requires a
// word boundary before the match so we don't eat legitimate content.
function stripPromptEcho(text, vocabulary) {
  if (!text || !vocabulary) return text;
  const trimTrailing = (s) => s.replace(/[\s.,;:!?]+$/, '');
  const candidates = [buildWhisperPrompt(vocabulary), vocabulary]
    .map(trimTrailing)
    .filter(Boolean)
    .map((c) => c.toLowerCase())
    .sort((a, b) => b.length - a.length);

  const haystackTrimmed = trimTrailing(text);
  const haystackLower = haystackTrimmed.toLowerCase();

  for (const candidate of candidates) {
    if (!haystackLower.endsWith(candidate)) continue;
    const cutPos = haystackTrimmed.length - candidate.length;
    if (cutPos !== 0 && !/[\s.,;:!?]/.test(haystackTrimmed[cutPos - 1])) continue;
    return haystackTrimmed.slice(0, cutPos).replace(/[\s,;:]+$/, '');
  }
  return text;
}

/**
 * Remove disfluencies ("um", "uh", "er", "hmm", etc.) from a transcript and
 * collapse the resulting whitespace.
 */
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

// --- Exported for tests (see proxy/test) ---
// The Worker entry point is the default export above; these are the pure
// request-shaping and transcript-formatting helpers, exported so `npm test`
// can cover them without a live Worker or provider credentials.
export {
  MODELS,
  MODEL_ALIASES,
  DEFAULT_MODEL,
  resolveModel,
  parseKeywords,
  buildOpenAIForm,
  buildDeepgramParams,
  buildWhisperPrompt,
  stripPromptEcho,
  stripFillerWords,
  postProcessTranscript,
  formatSegmentsIntoParagraphs,
  formatTextIntoParagraphs,
  resolveDeepgramLanguage,
};
