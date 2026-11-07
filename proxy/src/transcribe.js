// Transcription and formatting for uploaded notes. Behavior is
// specs/transcription.md; this file is the one place that talks to Groq.

export class TranscribeError extends Error {
  // retryable: true = Groq overloaded/down/slow/key rejected or missing; try again later
  // retryable: false = Groq rejected the audio itself (result "audio_rejected")
  constructor(message, { retryable, provider = null, status = null } = {}) {
    super(message);
    this.name = 'TranscribeError';
    this.retryable = retryable;
    this.provider = provider;
    this.status = status;
    // Filled in by transcribeNote for the caller's alerts.
    this.attempts = [];
  }
}

// --- Configuration ---

// The one provider and model, for everyone.
export const PROVIDER = 'groq';
export const MODEL = 'whisper-large-v3-turbo';

// The Groq call is given up after this long.
export const PROVIDER_TIMEOUT_MS = 120_000;

// The first attempt runs as the upload is accepted, inside the Worker's
// waitUntil budget (about 30 seconds after the response), so its call gets
// at most 20 seconds. Later attempts, from the cron, keep the long timeout.
export const INLINE_PROVIDER_TIMEOUT_MS = 20_000;

// Filler words removed when "Remove filler words" is on. Keeps "like" and
// "you know", which often carry meaning.
const FILLER_REGEX = /\b(?:um+|uh+|er+|ah+|hmm+|mhm+|uhm+|erm+)\b[\s,.;:!?]*/gi;

// Vocabulary limits. `<`, `>` and line breaks inside a term are dropped.
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
// opts: { contentType, language, removeFillerWords, vocabulary }
// env: GROQ_API_KEY.
// deps: { fetch, timeoutMs }: timeoutMs for the call. The first attempt
// passes the inline value.
//
// Resolves { result: 'transcript' | 'no_speech', text, provider, model,
//            durationSeconds, attempts }.
//   durationSeconds: length Groq reported, or null if it gave none.
//   attempts: [{ provider, outcome, status }], for alerts.
// Rejects with TranscribeError (also carrying attempts).
export async function transcribeNote(audio, opts = {}, env = {}, deps = {}) {
  const fetchFn = deps.fetch ?? globalThis.fetch;
  const timeoutMs = deps.timeoutMs ?? PROVIDER_TIMEOUT_MS;

  const options = {
    contentType: normalizeContentType(opts.contentType),
    language: normalizeLanguage(opts.language),
    keywords: parseKeywords(opts.vocabulary ?? ''),
    removeFillerWords: opts.removeFillerWords === true,
  };

  const outcome = await callGroq(audio, options, env, fetchFn, timeoutMs);
  const attempts = [{ provider: PROVIDER, outcome: outcome.kind, status: outcome.status ?? null }];

  if (outcome.kind === 'ok' || outcome.kind === 'too_short') {
    const text = outcome.kind === 'ok' ? finishText(outcome, options) : '';
    const silent = outcome.kind === 'too_short' || outcome.allSilent || isSilenceText(text);
    return {
      result: silent ? 'no_speech' : 'transcript',
      text: silent ? '' : text,
      provider: PROVIDER,
      model: MODEL,
      durationSeconds: outcome.seconds ?? null,
      attempts,
    };
  }

  // audio_rejected stops for good; anything about load, keys, money or size
  // waits and is retried.
  const err = new TranscribeError(outcome.message, {
    retryable: outcome.kind !== 'audio_rejected',
    provider: PROVIDER,
    status: outcome.status ?? null,
  });
  err.attempts = attempts;
  throw err;
}

// --- The Groq call ---

// Returns one of:
//   { kind: 'ok', text, timed, seconds, allSilent }
//   { kind: 'too_short', status }                   audio too short: no speech
//   { kind: 'audio_rejected', status, message }     stop: Groq can't take it
//   { kind: <retryable outcome>, status, message }  try again later
// Retryable outcomes: key_missing, key_rejected, rate_limited, unavailable,
// timeout, billing, too_large, bad_response.
async function callGroq(audio, options, env, fetchFn, timeoutMs) {
  const key = env.GROQ_API_KEY;
  if (!key) {
    console.error('[transcribe] groq key missing');
    return { kind: 'key_missing', status: null, message: 'groq key not configured' };
  }

  const blob = new Blob([audio], { type: options.contentType });
  const fileName = options.contentType === 'audio/aac' ? 'recording.aac' : 'recording.m4a';
  let res;
  try {
    res = await fetchFn('https://api.groq.com/openai/v1/audio/transcriptions', {
      method: 'POST',
      headers: { Authorization: `Bearer ${key}` },
      body: buildGroqForm(blob, fileName, options),
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch (err) {
    const timedOut = err?.name === 'TimeoutError' || err?.name === 'AbortError';
    console.error(`[transcribe] groq ${timedOut ? 'timed out' : 'unreachable'}`);
    return { kind: timedOut ? 'timeout' : 'unavailable', status: null, message: 'groq unreachable' };
  }

  if (!res.ok) {
    const body = truncateBody(await safeText(res));
    const kind = classifyHttpFailure(res.status, body);
    console.error(`[transcribe] groq error ${res.status} (${kind}): ${body}`);
    return { kind, status: res.status, message: `groq answered ${res.status}: ${body}` };
  }

  let data;
  try {
    data = await res.json();
  } catch {
    data = null;
  }
  const parsed = data ? parseGroq(data) : null;
  if (!parsed) {
    console.error('[transcribe] groq returned an unreadable response');
    return { kind: 'bad_response', status: res.status, message: 'groq returned no transcript' };
  }
  return { kind: 'ok', ...parsed };
}

/** Multipart body for Groq's Whisper endpoint. */
export function buildGroqForm(file, fileName, options) {
  const form = new FormData();
  form.append('file', file, fileName);
  form.append('model', MODEL);
  form.append('response_format', 'verbose_json');
  form.append('temperature', '0');
  if (options.language) form.append('language', options.language);
  const terms = whisperPromptTerms(options.keywords);
  if (terms) form.append('prompt', buildWhisperPrompt(terms));
  return form;
}

// --- Response parsing ---

function parseGroq(data) {
  if (typeof data.text !== 'string') return null;
  const segments = Array.isArray(data.segments) ? data.segments : [];
  return {
    text: segments.length > 0 ? formatSegmentsIntoParagraphs(segments) : data.text,
    timed: segments.length > 0,
    seconds: finiteOrNull(data.duration),
    allSilent: segments.length > 0 && segments.every(isSilentSegment),
  };
}

// Prompt echo, filler words and paragraphs, in that order.
function finishText(outcome, options) {
  let text = (outcome.text ?? '').trim();
  // Whisper gets the vocabulary as a prompt, and sometimes echoes it.
  const terms = whisperPromptTerms(options.keywords);
  if (terms) text = stripPromptEcho(text, terms);
  if (options.removeFillerWords) text = stripFillerWords(text);
  if (!outcome.timed) text = formatTextIntoParagraphs(text);
  return (text ?? '').trim();
}

// --- Error classification ---

const BILLING_PATTERN = /billing|quota|spend|credit|payment|insufficient|balance|organization_restricted/i;
const RATE_PATTERN = /rate.?limit|too many requests/i;
const TOO_SHORT_PATTERN = /too short/i;

// What a non-2xx answer means. Only a 4xx about the audio itself fails the
// note; anything that is about load, keys, money or size is retried.
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

function finiteOrNull(n) {
  return typeof n === 'number' && Number.isFinite(n) ? n : null;
}
