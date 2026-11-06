// Transcription providers, fallback and formatting for uploaded notes.
// Behavior is specs/transcription.md; this file is the one place that talks
// to Groq, Deepgram and OpenAI.

import { measureDurationSeconds } from './audio.js';

export class TranscribeError extends Error {
  // retryable: true = provider overloaded/down/key rejected/spend breaker; try again later
  // retryable: false = no provider could transcribe this audio (result "audio_rejected")
  constructor(message, { retryable, provider = null, status = null } = {}) {
    super(message);
    this.name = 'TranscribeError';
    this.retryable = retryable;
    this.provider = provider;
    this.status = status;
    // Filled in by transcribeNote for the caller's alerts and usage records.
    this.attempts = [];
    this.breakerOpen = false;
  }
}

// --- Configuration ---

// Provider order. Groq is the one primary for everyone; the rest are
// fallbacks used only when the one before is overloaded, down, rate limited
// or rejects Ramble's key.
export const PROVIDER_CHAIN = ['groq', 'deepgram', 'openai'];
export const FALLBACK_PROVIDERS = ['deepgram', 'openai'];

export const MODELS = {
  groq: 'whisper-large-v3-turbo',
  deepgram: 'nova-3',
  openai: 'gpt-transcribe',
};

// Fallback spend breaker: Deepgram + OpenAI combined, per UTC day.
export const FALLBACK_DAILY_BUDGET_USD = 5.0;

// OpenAI takes at most 25 minutes of audio per request.
export const OPENAI_MAX_SECONDS = 25 * 60;

// Each provider call is given up after this long.
export const PROVIDER_TIMEOUT_MS = 120_000;

// Estimated list prices in dollars per audio minute. Estimates only: they
// drive the spend breaker and the operator's numbers, not billing.
export const COST_PER_MINUTE = {
  groq: 0.04 / 60, // $0.04 per hour
  deepgram: 0.0052, // Nova-3 pre-recorded, multilingual rate (the higher one)
  openai: 0.006,
};
// Groq bills every request as at least 10 seconds.
const GROQ_MIN_BILLED_SECONDS = 10;

// Languages Deepgram Nova-3 takes as a `language=` hint. Anything else gets
// no hint (`multi`, Deepgram's own detection). Check before expanding:
//   https://developers.deepgram.com/docs/models-languages-overview
const DEEPGRAM_NOVA3_LANGUAGES = new Set([
  'ar','bg','bn','ca','cs','da','de','el','en','es','et','fa','fi','fr','he',
  'hi','hr','hu','id','it','ja','ko','lt','lv','ms','nl','no','pl','pt','ro',
  'ru','sk','sv','ta','te','th','tl','tr','uk','ur','vi','zh',
]);

// Filler words removed when "Remove filler words" is on. Keeps "like" and
// "you know", which often carry meaning.
const FILLER_REGEX = /\b(?:um+|uh+|er+|ah+|hmm+|mhm+|uhm+|erm+)\b[\s,.;:!?]*/gi;

// Vocabulary limits. GPT-Transcribe rejects keywords containing `<`, `>` or
// line breaks, so those are dropped here.
const MAX_KEYWORDS = 100;
const MAX_KEYWORD_LENGTH = 100;
// Whisper's prompt holds about 224 tokens; stay well inside it so Groq never
// rejects a note because of the person's vocabulary.
const MAX_WHISPER_PROMPT_TERMS_LENGTH = 600;

// Paragraphs when the provider gives no timing.
const PARAGRAPH_PAUSE_SECONDS = 2.0;
const PARAGRAPH_MIN_LENGTH = 500;
const PARAGRAPH_TARGET_LENGTH = 350;
const PARAGRAPH_ORPHAN_LENGTH = 80;

// What Whisper says over silence. A transcript that is only one of these,
// ignoring case and surrounding punctuation, is "No speech detected".
const SILENCE_PHRASES = new Set([
  'thank you',
  'thanks for watching',
  'thank you for watching',
  'you',
  'bye',
]);

// Whisper's own thresholds for "this segment is silence".
const NO_SPEECH_PROB_THRESHOLD = 0.6;
const LOGPROB_THRESHOLD = -1.0;

// Provider error bodies kept in logs and messages.
const MAX_ERROR_BODY = 200;

// --- Entry point ---

// audio: ArrayBuffer of the stored note (AAC in MP4/M4A or raw ADTS AAC).
// opts: { contentType, language, removeFillerWords, vocabulary, durationSeconds }
// env: GROQ_API_KEY, DEEPGRAM_API_KEY, OPENAI_API_KEY, DB (spend breaker).
// deps: { fetch, now, timeoutMs } for tests.
//
// Resolves { result: 'transcript' | 'no_speech', text, provider, model,
//            durationSeconds, fallback, attempts }.
//   durationSeconds: length the provider reported, or null if it gave none.
//   fallback: true when a provider other than Groq produced the result.
//   attempts: [{ provider, outcome, status }] in call order, for alerts.
// Rejects with TranscribeError (also carrying attempts and breakerOpen).
export async function transcribeNote(audio, opts = {}, env = {}, deps = {}) {
  const fetchFn = deps.fetch ?? globalThis.fetch;
  const now = deps.now ?? Date.now;
  const timeoutMs = deps.timeoutMs ?? PROVIDER_TIMEOUT_MS;

  const options = {
    contentType: normalizeContentType(opts.contentType),
    language: normalizeLanguage(opts.language),
    keywords: parseKeywords(opts.vocabulary ?? ''),
    removeFillerWords: opts.removeFillerWords === true,
  };
  const knownSeconds = opts.durationSeconds ?? safeMeasure(audio);

  const attempts = [];
  let breakerOpen = false;
  let breakerChecked = false;

  for (const provider of PROVIDER_CHAIN) {
    const isFallback = provider !== 'groq';

    if (provider === 'openai' && !(knownSeconds > 0 && knownSeconds <= OPENAI_MAX_SECONDS)) {
      // Too long for OpenAI, or a length we can't confirm fits.
      attempts.push({ provider, outcome: 'skipped_length', status: null });
      continue;
    }

    if (isFallback) {
      if (!breakerChecked) {
        breakerOpen = await fallbackBreakerOpen(env, now());
        breakerChecked = true;
      }
      if (breakerOpen) {
        attempts.push({ provider, outcome: 'breaker_open', status: null });
        break; // every remaining provider is a fallback
      }
    }

    const outcome = await callProvider(provider, audio, options, env, fetchFn, timeoutMs);
    attempts.push({ provider, outcome: outcome.kind, status: outcome.status ?? null });

    if (outcome.kind === 'ok' || outcome.kind === 'too_short') {
      const seconds = outcome.seconds ?? null;
      if (outcome.kind === 'ok') {
        await recordSpend(env, provider, seconds ?? knownSeconds ?? 0, now());
      }
      const text = outcome.kind === 'ok' ? finishText(outcome, provider, options) : '';
      const silent = outcome.kind === 'too_short' || outcome.allSilent || isSilenceText(text);
      return {
        result: silent ? 'no_speech' : 'transcript',
        text: silent ? '' : text,
        provider,
        model: MODELS[provider],
        durationSeconds: seconds,
        fallback: isFallback,
        attempts,
      };
    }

    if (outcome.kind === 'audio_rejected') {
      const err = new TranscribeError(outcome.message, {
        retryable: false,
        provider,
        status: outcome.status,
      });
      err.attempts = attempts;
      throw err;
    }
    // Overloaded, down, slow, rate limited, billing, or key trouble: next provider.
  }

  const last = [...attempts].reverse().find((a) => a.status !== null) ?? attempts[attempts.length - 1];
  const message = breakerOpen
    ? 'Groq is unavailable and the fallback spend breaker is open'
    : 'No transcription provider is available right now';
  const err = new TranscribeError(message, {
    retryable: true,
    provider: last?.provider ?? null,
    status: last?.status ?? null,
  });
  err.attempts = attempts;
  err.breakerOpen = breakerOpen;
  throw err;
}

// --- Provider calls ---

// One provider call. Returns one of:
//   { kind: 'ok', text, segments, timed, seconds, allSilent }
//   { kind: 'too_short', status }                   audio too short: no speech
//   { kind: 'audio_rejected', status, message }     stop: nobody can take it
//   { kind: <fallback outcome>, status, message }   try the next provider
// Fallback outcomes: key_missing, key_rejected, rate_limited, unavailable,
// timeout, billing, too_large, bad_response.
async function callProvider(provider, audio, options, env, fetchFn, timeoutMs) {
  const key = env[API_KEY_NAMES[provider]];
  if (!key) {
    console.error(`[transcribe] ${provider} key missing`);
    return { kind: 'key_missing', status: null, message: `${provider} key not configured` };
  }

  const request = buildRequest(provider, audio, options, key);
  let res;
  try {
    res = await fetchFn(request.url, { ...request.init, signal: AbortSignal.timeout(timeoutMs) });
  } catch (err) {
    const timedOut = err?.name === 'TimeoutError' || err?.name === 'AbortError';
    console.error(`[transcribe] ${provider} ${timedOut ? 'timed out' : 'unreachable'}`);
    return { kind: timedOut ? 'timeout' : 'unavailable', status: null, message: `${provider} unreachable` };
  }

  if (!res.ok) {
    const body = truncateBody(await safeText(res));
    const kind = classifyHttpFailure(res.status, body);
    console.error(`[transcribe] ${provider} error ${res.status} (${kind}): ${body}`);
    return { kind, status: res.status, message: `${provider} answered ${res.status}: ${body}` };
  }

  let data;
  try {
    data = await res.json();
  } catch {
    data = null;
  }
  const parsed = data ? PARSERS[provider](data) : null;
  if (!parsed) {
    console.error(`[transcribe] ${provider} returned an unreadable response`);
    return { kind: 'bad_response', status: res.status, message: `${provider} returned no transcript` };
  }
  return { kind: 'ok', ...parsed };
}

const API_KEY_NAMES = {
  groq: 'GROQ_API_KEY',
  deepgram: 'DEEPGRAM_API_KEY',
  openai: 'OPENAI_API_KEY',
};

function buildRequest(provider, audio, options, key) {
  const blob = new Blob([audio], { type: options.contentType });
  const fileName = options.contentType === 'audio/aac' ? 'recording.aac' : 'recording.m4a';

  if (provider === 'groq') {
    return {
      url: 'https://api.groq.com/openai/v1/audio/transcriptions',
      init: {
        method: 'POST',
        headers: { Authorization: `Bearer ${key}` },
        body: buildGroqForm(blob, fileName, options),
      },
    };
  }
  if (provider === 'deepgram') {
    return {
      url: `https://api.deepgram.com/v1/listen?${buildDeepgramParams(options).toString()}`,
      init: {
        method: 'POST',
        headers: { Authorization: `Token ${key}`, 'Content-Type': options.contentType },
        body: audio,
      },
    };
  }
  return {
    url: 'https://api.openai.com/v1/audio/transcriptions',
    init: {
      method: 'POST',
      headers: { Authorization: `Bearer ${key}` },
      body: buildOpenAIForm(blob, fileName, options),
    },
  };
}

/** Multipart body for Groq's Whisper endpoint. */
export function buildGroqForm(file, fileName, options) {
  const form = new FormData();
  form.append('file', file, fileName);
  form.append('model', MODELS.groq);
  form.append('response_format', 'verbose_json');
  form.append('temperature', '0');
  if (options.language) form.append('language', options.language);
  const terms = whisperPromptTerms(options.keywords);
  if (terms) form.append('prompt', buildWhisperPrompt(terms));
  return form;
}

/** Query string for Deepgram's `/v1/listen`. */
export function buildDeepgramParams(options) {
  const params = new URLSearchParams({
    model: MODELS.deepgram,
    smart_format: 'true',
    paragraphs: 'true',
    language: resolveDeepgramLanguage(options.language),
    // Deepgram drops "um" and "uh" unless told not to, so keeping them is an
    // explicit opt-in that matches Groq's output.
    filler_words: options.removeFillerWords ? 'false' : 'true',
    // Never let Deepgram use the audio to improve its models.
    mip_opt_out: 'true',
  });
  for (const term of options.keywords) params.append('keyterm', term);
  return params;
}

/**
 * Multipart body for OpenAI's `/v1/audio/transcriptions`. Array fields repeat
 * with a `[]` suffix, as OpenAI's SDKs send `keywords` and `languages`.
 */
export function buildOpenAIForm(file, fileName, options) {
  const form = new FormData();
  form.append('file', file, fileName);
  form.append('model', MODELS.openai);
  // GPT-Transcribe returns JSON only, with no timings.
  form.append('response_format', 'json');
  if (options.language) form.append('languages[]', options.language);
  for (const term of options.keywords) form.append('keywords[]', term);
  return form;
}

// --- Response parsing ---

const PARSERS = {
  groq(data) {
    if (typeof data.text !== 'string') return null;
    const segments = Array.isArray(data.segments) ? data.segments : [];
    return {
      text: segments.length > 0 ? formatSegmentsIntoParagraphs(segments) : data.text,
      timed: segments.length > 0,
      seconds: finiteOrNull(data.duration),
      allSilent: segments.length > 0 && segments.every(isSilentSegment),
    };
  },

  deepgram(data) {
    const alternative = data.results?.channels?.[0]?.alternatives?.[0];
    if (!alternative) return null;
    const seconds = finiteOrNull(data.metadata?.duration);
    // Sentences carry timings: rebuild paragraphs on the 2-second rule.
    const sentences = (alternative.paragraphs?.paragraphs ?? []).flatMap((p) => p.sentences ?? []);
    if (sentences.length > 0) {
      return { text: formatSegmentsIntoParagraphs(sentences), timed: true, seconds, allSilent: false };
    }
    const text = alternative.paragraphs?.transcript ?? alternative.transcript;
    if (typeof text !== 'string') return null;
    return { text, timed: false, seconds, allSilent: false };
  },

  openai(data) {
    if (typeof data.text !== 'string') return null;
    const seconds = data.usage?.type === 'duration' ? finiteOrNull(data.usage.seconds) : finiteOrNull(data.duration);
    return { text: data.text, timed: false, seconds, allSilent: false };
  },
};

// Prompt echo, filler words and paragraphs, in that order.
function finishText(outcome, provider, options) {
  let text = (outcome.text ?? '').trim();
  if (provider === 'groq') {
    // Only Whisper gets the vocabulary as a prompt, and only Whisper echoes it.
    const terms = whisperPromptTerms(options.keywords);
    if (terms) text = stripPromptEcho(text, terms);
  }
  if (options.removeFillerWords) text = stripFillerWords(text);
  if (!outcome.timed) text = formatTextIntoParagraphs(text);
  return (text ?? '').trim();
}

// --- Error classification ---

const BILLING_PATTERN = /billing|quota|spend|credit|payment|insufficient|balance|organization_restricted/i;
const RATE_PATTERN = /rate.?limit|too many requests/i;
const TOO_SHORT_PATTERN = /too short/i;

// What a non-2xx answer means. Only a 4xx about the audio itself stops the
// chain; anything that is about load, keys, money or size moves on.
export function classifyHttpFailure(status, body = '') {
  if (status === 429) return 'rate_limited';
  if (status >= 500) return 'unavailable';
  if (status === 401 || status === 403) return 'key_rejected';
  if (status === 402) return 'billing';
  if (status === 413) return 'too_large';
  if (status >= 400) {
    if (BILLING_PATTERN.test(body)) return 'billing';
    if (RATE_PATTERN.test(body)) return 'rate_limited';
    if (TOO_SHORT_PATTERN.test(body)) return 'too_short';
    return 'audio_rejected';
  }
  return 'unavailable'; // 1xx/3xx: not an answer we can use
}

function truncateBody(body) {
  return (body ?? '').slice(0, MAX_ERROR_BODY);
}

async function safeText(res) {
  try {
    return await res.text();
  } catch {
    return '';
  }
}

// --- Spend breaker ---

export function utcDay(ms) {
  return new Date(ms).toISOString().slice(0, 10);
}

export function estimateCostUSD(provider, seconds) {
  const billed = provider === 'groq' ? Math.max(seconds, GROQ_MIN_BILLED_SECONDS) : seconds;
  return (billed / 60) * (COST_PER_MINUTE[provider] ?? 0);
}

// True when today's Deepgram + OpenAI spend has reached the budget. Fails
// safe: if spend can't be read, the fallbacks stay closed.
export async function fallbackBreakerOpen(env, nowMs) {
  try {
    const row = await env.DB.prepare(
      `SELECT COALESCE(SUM(usd), 0) AS usd FROM provider_spend
       WHERE day = ? AND provider IN ('deepgram', 'openai')`,
    )
      .bind(utcDay(nowMs))
      .first();
    return Number(row?.usd ?? 0) >= FALLBACK_DAILY_BUDGET_USD;
  } catch (err) {
    console.error(`[transcribe] spend breaker unreadable, fallbacks closed: ${err?.message}`);
    return true;
  }
}

// Adds a successful call's estimated cost to today's row. A failed write is
// logged and never fails the note.
export async function recordSpend(env, provider, seconds, nowMs) {
  const safeSeconds = Number.isFinite(seconds) && seconds > 0 ? seconds : 0;
  const usd = estimateCostUSD(provider, safeSeconds);
  try {
    await env.DB.prepare(
      `INSERT INTO provider_spend (day, provider, usd, seconds, notes) VALUES (?, ?, ?, ?, 1)
       ON CONFLICT (day, provider) DO UPDATE SET
         usd = usd + excluded.usd, seconds = seconds + excluded.seconds, notes = notes + 1`,
    )
      .bind(utcDay(nowMs), provider, usd, safeSeconds)
      .run();
  } catch (err) {
    console.error(`[transcribe] spend record failed for ${provider}: ${err?.message}`);
  }
}

// --- Silence ---

// A transcript that is empty or only a known Whisper silence phrase.
export function isSilenceText(text) {
  const core = (text ?? '')
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .replace(/^[\s\p{P}]+|[\s\p{P}]+$/gu, '');
  return core === '' || SILENCE_PHRASES.has(core);
}

// Whisper's own rule: likely no speech and low confidence in the words.
function isSilentSegment(segment) {
  return (
    typeof segment.no_speech_prob === 'number' &&
    typeof segment.avg_logprob === 'number' &&
    segment.no_speech_prob > NO_SPEECH_PROB_THRESHOLD &&
    segment.avg_logprob < LOGPROB_THRESHOLD
  );
}

// --- Formatting helpers ---

/** Paragraph break wherever two timed pieces are 2 seconds or more apart. */
export function formatSegmentsIntoParagraphs(segments, pauseThreshold = PARAGRAPH_PAUSE_SECONDS) {
  if (!segments || segments.length === 0) return '';

  const paragraphs = [];
  let current = [];
  for (let i = 0; i < segments.length; i++) {
    if (i > 0 && segments[i].start - segments[i - 1].end >= pauseThreshold && current.length > 0) {
      paragraphs.push(current.join(' '));
      current = [];
    }
    const text = (segments[i].text ?? '').trim();
    if (text) current.push(text);
  }
  if (current.length > 0) paragraphs.push(current.join(' '));
  return paragraphs.join('\n\n');
}

/**
 * Paragraphs for text without timings: from 500 characters up, break at the
 * first sentence end once a paragraph reaches 350, and fold a last piece
 * under 80 characters into the paragraph before it.
 */
export function formatTextIntoParagraphs(text) {
  if (!text) return text;

  const trimmed = text.trim();
  if (trimmed.length < PARAGRAPH_MIN_LENGTH) return trimmed;
  if (/\n\s*\n/.test(trimmed)) return trimmed;

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
    if (paragraphs.length > 0 && current.length < PARAGRAPH_ORPHAN_LENGTH) {
      paragraphs[paragraphs.length - 1] += ` ${current}`;
    } else {
      paragraphs.push(current);
    }
  }
  return paragraphs.join('\n\n');
}

/**
 * The vocabulary as terms: split on commas and line breaks, `<` and `>`
 * dropped, case-only duplicates ignored, at most 100 terms of 100 characters.
 */
export function parseKeywords(vocabulary) {
  if (!vocabulary || typeof vocabulary !== 'string') return [];

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

/** Deepgram's `language` value: the code if Nova-3 has it, else `multi` (detect). */
export function resolveDeepgramLanguage(code) {
  if (!code) return 'multi';
  if (DEEPGRAM_NOVA3_LANGUAGES.has(code)) return code;
  const base = code.split('-')[0];
  if (DEEPGRAM_NOVA3_LANGUAGES.has(base)) return base;
  return 'multi';
}

// Terms joined for the Whisper prompt, cut at a term boundary to fit.
function whisperPromptTerms(keywords) {
  let joined = '';
  for (const term of keywords) {
    const next = joined ? `${joined}, ${term}` : term;
    if (next.length > MAX_WHISPER_PROMPT_TERMS_LENGTH) break;
    joined = next;
  }
  return joined;
}

// A complete sentence: Whisper continues a bare list into the transcript
// more often than it repeats finished prose.
export function buildWhisperPrompt(vocabulary) {
  return `Names and terms that may come up: ${vocabulary}.`;
}

// If Whisper still echoes the prompt at the end, cut it. Needs a word
// boundary before the match so real speech isn't eaten.
export function stripPromptEcho(text, vocabulary) {
  if (!text || !vocabulary) return text;
  const trimTrailing = (s) => s.replace(/[\s.,;:!?]+$/, '');
  const candidates = [buildWhisperPrompt(vocabulary), vocabulary]
    .map(trimTrailing)
    .filter(Boolean)
    .map((c) => c.toLowerCase())
    .sort((a, b) => b.length - a.length);

  const haystack = trimTrailing(text);
  const lower = haystack.toLowerCase();
  for (const candidate of candidates) {
    if (!lower.endsWith(candidate)) continue;
    const cut = haystack.length - candidate.length;
    if (cut !== 0 && !/[\s.,;:!?]/.test(haystack[cut - 1])) continue;
    return haystack.slice(0, cut).replace(/[\s,;:]+$/, '');
  }
  return text;
}

/** Remove "um", "uh" and friends, keeping paragraph breaks. */
export function stripFillerWords(text) {
  if (!text) return text;
  return text
    .replace(FILLER_REGEX, '')
    .split('\n')
    .map((line) => line.replace(/[ \t]+/g, ' ').replace(/\s+([,.!?;:])/g, '$1').trim())
    .join('\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

// --- Small utilities ---

function normalizeContentType(type) {
  const base = (type ?? '').split(';')[0].trim().toLowerCase();
  return base || 'audio/mp4';
}

function normalizeLanguage(language) {
  const code = (language ?? '').trim().toLowerCase();
  return code && code !== 'auto' ? code : null;
}

function safeMeasure(audio) {
  try {
    return measureDurationSeconds(audio instanceof Uint8Array ? audio : new Uint8Array(audio));
  } catch {
    return null;
  }
}

function finiteOrNull(n) {
  return typeof n === 'number' && Number.isFinite(n) ? n : null;
}
