// Provider chain, fallback, spend breaker, options and formatting for
// src/transcribe.js. Fake fetch only: no network, no credentials.

import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { createTestDB } from './d1.js';
import {
  TranscribeError,
  transcribeNote,
  classifyHttpFailure,
  isSilenceText,
  parseKeywords,
  buildDeepgramParams,
  buildOpenAIForm,
  buildGroqForm,
  stripPromptEcho,
  stripFillerWords,
  formatSegmentsIntoParagraphs,
  formatTextIntoParagraphs,
  resolveDeepgramLanguage,
  fallbackBreakerOpen,
  recordSpend,
  utcDay,
  FALLBACK_DAILY_BUDGET_USD,
} from '../src/transcribe.js';

const NOW = Date.parse('2026-11-06T12:00:00Z');
const AUDIO = new Uint8Array([0, 1, 2, 3]).buffer;
const KEYS = { GROQ_API_KEY: 'g', DEEPGRAM_API_KEY: 'd', OPENAI_API_KEY: 'o' };

function providerOf(url) {
  if (url.includes('groq.com')) return 'groq';
  if (url.includes('deepgram.com')) return 'deepgram';
  return 'openai';
}

// handlers: { groq, deepgram, openai } each (url, init) => Response | throw.
function fakeFetch(handlers) {
  const calls = [];
  const fetch = async (url, init) => {
    const provider = providerOf(url);
    calls.push({ provider, url, init });
    const handler = handlers[provider];
    if (!handler) throw new Error(`unexpected call to ${provider}`);
    return handler(url, init);
  };
  return { fetch, calls };
}

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
const fail = (status, body = '{"error":"x"}') => () => new Response(body, { status });

const groqOK = (text, extra = {}) => () =>
  json({
    text,
    duration: 30,
    segments: [{ start: 0, end: 3, text, no_speech_prob: 0.01, avg_logprob: -0.2 }],
    ...extra,
  });
const deepgramOK = (transcript) => () =>
  json({
    metadata: { duration: 30 },
    results: { channels: [{ alternatives: [{ transcript, paragraphs: { transcript } }] }] },
  });
const openaiOK = (text) => () => json({ text, usage: { type: 'duration', seconds: 30 } });

function setup(handlers, envExtra = {}) {
  const db = createTestDB();
  const env = { ...KEYS, DB: db, ...envExtra };
  const { fetch, calls } = fakeFetch(handlers);
  return { env, db, calls, deps: { fetch, now: () => NOW } };
}

const opts = (extra = {}) => ({
  contentType: 'audio/mp4',
  language: null,
  removeFillerWords: false,
  vocabulary: '',
  durationSeconds: 30,
  ...extra,
});

describe('transcribeNote: primary provider', () => {
  it('uses Groq Whisper v3 Turbo first', async () => {
    const { env, calls, deps } = setup({ groq: groqOK('Hello there.') });
    const out = await transcribeNote(AUDIO, opts(), env, deps);
    assert.equal(out.result, 'transcript');
    assert.equal(out.text, 'Hello there.');
    assert.equal(out.provider, 'groq');
    assert.equal(out.model, 'whisper-large-v3-turbo');
    assert.equal(out.fallback, false);
    assert.equal(out.durationSeconds, 30);
    assert.equal(calls.length, 1);
    const form = calls[0].init.body;
    assert.equal(form.get('model'), 'whisper-large-v3-turbo');
    assert.equal(form.get('response_format'), 'verbose_json');
  });

  it('records Groq spend for the day', async () => {
    const { env, db, deps } = setup({ groq: groqOK('Hi.') });
    await transcribeNote(AUDIO, opts(), env, deps);
    const row = await db.prepare('SELECT * FROM provider_spend WHERE provider = ?').bind('groq').first();
    assert.equal(row.day, '2026-11-06');
    assert.equal(row.notes, 1);
    assert.ok(row.usd > 0);
  });
});

describe('transcribeNote: fallback', () => {
  it('Groq 429 goes to Deepgram', async () => {
    const { env, calls, deps } = setup({ groq: fail(429), deepgram: deepgramOK('From Deepgram.') });
    const out = await transcribeNote(AUDIO, opts(), env, deps);
    assert.equal(out.provider, 'deepgram');
    assert.equal(out.model, 'nova-3');
    assert.equal(out.fallback, true);
    assert.deepEqual(calls.map((c) => c.provider), ['groq', 'deepgram']);
    assert.deepEqual(out.attempts[0], { provider: 'groq', outcome: 'rate_limited', status: 429 });
  });

  it('Groq 401 goes to Deepgram and is reported as key_rejected', async () => {
    const { env, deps } = setup({ groq: fail(401), deepgram: deepgramOK('Ok.') });
    const out = await transcribeNote(AUDIO, opts(), env, deps);
    assert.equal(out.provider, 'deepgram');
    assert.equal(out.attempts[0].outcome, 'key_rejected');
  });

  it('a missing Groq key goes to Deepgram', async () => {
    const { env, calls, deps } = setup({ deepgram: deepgramOK('Ok.') }, { GROQ_API_KEY: '' });
    const out = await transcribeNote(AUDIO, opts(), env, deps);
    assert.equal(out.provider, 'deepgram');
    assert.equal(out.attempts[0].outcome, 'key_missing');
    assert.deepEqual(calls.map((c) => c.provider), ['deepgram']);
  });

  it('Groq 5xx, unreachable, and timeout all fall back', async () => {
    for (const groq of [
      fail(503),
      () => {
        throw new TypeError('fetch failed');
      },
      () => {
        throw new DOMException('timed out', 'TimeoutError');
      },
    ]) {
      const { env, deps } = setup({ groq, deepgram: deepgramOK('Ok.') });
      const out = await transcribeNote(AUDIO, opts(), env, deps);
      assert.equal(out.provider, 'deepgram');
    }
  });

  it('Groq billing error, 402 and 413 fall back and never reject the audio', async () => {
    for (const groq of [
      fail(400, '{"error":{"message":"Organization spend limit reached","code":"spend_limit"}}'),
      fail(402),
      fail(413),
    ]) {
      const { env, deps } = setup({ groq, deepgram: deepgramOK('Ok.') });
      const out = await transcribeNote(AUDIO, opts(), env, deps);
      assert.equal(out.provider, 'deepgram');
    }
  });

  it('Groq 400 for undecodable audio stops the chain as audio_rejected', async () => {
    const { env, calls, deps } = setup({
      groq: fail(400, '{"error":{"message":"could not process file - is it a valid media file?"}}'),
    });
    await assert.rejects(transcribeNote(AUDIO, opts(), env, deps), (err) => {
      assert.ok(err instanceof TranscribeError);
      assert.equal(err.retryable, false);
      assert.equal(err.provider, 'groq');
      assert.equal(err.status, 400);
      return true;
    });
    assert.equal(calls.length, 1);
  });

  it('Groq and Deepgram down goes to OpenAI', async () => {
    const { env, calls, deps } = setup({
      groq: fail(500),
      deepgram: fail(503),
      openai: openaiOK('From OpenAI.'),
    });
    const out = await transcribeNote(AUDIO, opts(), env, deps);
    assert.equal(out.provider, 'openai');
    assert.equal(out.model, 'gpt-transcribe');
    assert.deepEqual(calls.map((c) => c.provider), ['groq', 'deepgram', 'openai']);
  });

  it('skips OpenAI for notes over 25 minutes', async () => {
    const { env, calls, deps } = setup({ groq: fail(500), deepgram: fail(503) });
    await assert.rejects(transcribeNote(AUDIO, opts({ durationSeconds: 26 * 60 }), env, deps), (err) => {
      assert.equal(err.retryable, true);
      return true;
    });
    assert.deepEqual(calls.map((c) => c.provider), ['groq', 'deepgram']);
  });

  it('everything down is a retryable failure', async () => {
    const { env, deps } = setup({ groq: fail(503), deepgram: fail(502), openai: fail(500) });
    await assert.rejects(transcribeNote(AUDIO, opts(), env, deps), (err) => {
      assert.equal(err.retryable, true);
      assert.equal(err.attempts.length, 3);
      return true;
    });
  });

  it('keeps at most 200 characters of a provider error body', async () => {
    const long = 'x'.repeat(5000);
    const { env, deps } = setup({ groq: fail(400, long) });
    const originalError = console.error;
    const logged = [];
    console.error = (msg) => logged.push(msg);
    try {
      await assert.rejects(transcribeNote(AUDIO, opts(), env, deps), (err) => {
        assert.ok(err.message.length < 300);
        return true;
      });
    } finally {
      console.error = originalError;
    }
    assert.ok(logged.every((line) => !line.includes('x'.repeat(201))));
  });
});

describe('spend breaker', () => {
  it('opens at $5.00 of Deepgram + OpenAI spend today', async () => {
    const { env, calls, deps } = setup({ groq: fail(503), deepgram: deepgramOK('no') });
    await env.DB.prepare("INSERT INTO provider_spend (day, provider, usd) VALUES (?, 'deepgram', 3), (?, 'openai', 2)")
      .bind(utcDay(NOW), utcDay(NOW))
      .run();
    await assert.rejects(transcribeNote(AUDIO, opts(), env, deps), (err) => {
      assert.equal(err.retryable, true);
      assert.equal(err.breakerOpen, true);
      return true;
    });
    assert.deepEqual(calls.map((c) => c.provider), ['groq']);
  });

  it('ignores Groq spend and other days', async () => {
    const db = createTestDB();
    await db
      .prepare("INSERT INTO provider_spend (day, provider, usd) VALUES (?, 'groq', 50), ('2026-11-05', 'deepgram', 50)")
      .bind(utcDay(NOW))
      .run();
    assert.equal(await fallbackBreakerOpen({ DB: db }, NOW), false);
  });

  it('fails safe: unreadable spend keeps fallbacks closed', async () => {
    const originalError = console.error;
    console.error = () => {};
    try {
      assert.equal(await fallbackBreakerOpen({}, NOW), true);
    } finally {
      console.error = originalError;
    }
  });

  it('accumulates fallback spend until the breaker opens', async () => {
    const db = createTestDB();
    const env = { DB: db };
    // Deepgram at $0.0052/min: 1000 minutes = $5.20.
    await recordSpend(env, 'deepgram', 500 * 60, NOW);
    assert.equal(await fallbackBreakerOpen(env, NOW), false);
    await recordSpend(env, 'deepgram', 500 * 60, NOW);
    assert.equal(await fallbackBreakerOpen(env, NOW), true);
    const row = await db.prepare('SELECT * FROM provider_spend').first();
    assert.equal(row.notes, 2);
    assert.ok(row.usd >= FALLBACK_DAILY_BUDGET_USD);
  });
});

describe('silent notes', () => {
  it('"Thank you." alone is no speech', async () => {
    const { env, deps } = setup({ groq: groqOK('Thank you.') });
    const out = await transcribeNote(AUDIO, opts(), env, deps);
    assert.equal(out.result, 'no_speech');
    assert.equal(out.text, '');
  });

  it('a real thanks inside a longer note survives', async () => {
    const text = 'Thank you. Remind me to call Sam tomorrow.';
    const { env, deps } = setup({ groq: groqOK(text) });
    const out = await transcribeNote(AUDIO, opts(), env, deps);
    assert.equal(out.result, 'transcript');
    assert.equal(out.text, text);
  });

  it('every segment silent by Whisper\'s own measure is no speech', async () => {
    const groq = () =>
      json({
        text: 'Okay.',
        duration: 20,
        segments: [{ start: 0, end: 20, text: 'Okay.', no_speech_prob: 0.95, avg_logprob: -1.4 }],
      });
    const { env, deps } = setup({ groq });
    const out = await transcribeNote(AUDIO, opts(), env, deps);
    assert.equal(out.result, 'no_speech');
  });

  it('empty text and "too short" rejections are no speech', async () => {
    let s = setup({ groq: () => json({ text: '', segments: [] }) });
    assert.equal((await transcribeNote(AUDIO, opts(), s.env, s.deps)).result, 'no_speech');
    s = setup({ groq: fail(400, '{"error":{"message":"Audio file is too short. Minimum audio length is 0.01 seconds."}}') });
    assert.equal((await transcribeNote(AUDIO, opts(), s.env, s.deps)).result, 'no_speech');
  });

  it('a prompt echo over silence is no speech', async () => {
    const { env, deps } = setup({ groq: groqOK('Names and terms that may come up: Goodloop, Ramble.') });
    const out = await transcribeNote(AUDIO, opts({ vocabulary: 'Goodloop, Ramble' }), env, deps);
    assert.equal(out.result, 'no_speech');
  });

  it('isSilenceText matches the listed phrases only', () => {
    for (const t of ['Thank you.', 'thanks for watching!', ' Thank you for watching. ', 'you', 'Bye.', '', '...']) {
      assert.equal(isSilenceText(t), true, t);
    }
    for (const t of ['Thank you. Remind me to call Sam.', 'Bye bye.', 'Thanks!']) {
      assert.equal(isSilenceText(t), false, t);
    }
  });
});

describe('options', () => {
  it('passes the language hint to Groq and OpenAI', async () => {
    let s = setup({ groq: groqOK('Hola.') });
    await transcribeNote(AUDIO, opts({ language: 'es' }), s.env, s.deps);
    assert.equal(s.calls[0].init.body.get('language'), 'es');

    s = setup({ groq: fail(500), deepgram: fail(500), openai: openaiOK('Hola.') });
    await transcribeNote(AUDIO, opts({ language: 'es' }), s.env, s.deps);
    assert.deepEqual(s.calls[2].init.body.getAll('languages[]'), ['es']);
  });

  it('Deepgram: opts out of model improvement, detects language when unset or unsupported', async () => {
    const { env, calls, deps } = setup({ groq: fail(503), deepgram: deepgramOK('Ok.') });
    await transcribeNote(AUDIO, opts({ language: 'cy' }), env, deps);
    const params = new URL(calls[1].url).searchParams;
    assert.equal(params.get('mip_opt_out'), 'true');
    assert.equal(params.get('language'), 'multi');
    assert.equal(resolveDeepgramLanguage(null), 'multi');
    assert.equal(resolveDeepgramLanguage('es'), 'es');
    assert.equal(resolveDeepgramLanguage('pt-br'), 'pt');
  });

  it('Deepgram params carry filler choice and keyterms', () => {
    const keep = buildDeepgramParams({ language: 'en', keywords: ['Ramble', 'Goodloop'], removeFillerWords: false });
    assert.equal(keep.get('filler_words'), 'true');
    assert.deepEqual(keep.getAll('keyterm'), ['Ramble', 'Goodloop']);
    assert.equal(keep.get('mip_opt_out'), 'true');
    const strip = buildDeepgramParams({ language: null, keywords: [], removeFillerWords: true });
    assert.equal(strip.get('filler_words'), 'false');
  });

  it('vocabulary goes to Whisper as a prompt and OpenAI as keywords', () => {
    const options = { language: null, keywords: ['Ramble', 'Goodloop'], removeFillerWords: false };
    const groq = buildGroqForm(new Blob([AUDIO]), 'recording.m4a', options);
    assert.equal(groq.get('prompt'), 'Names and terms that may come up: Ramble, Goodloop.');
    const openai = buildOpenAIForm(new Blob([AUDIO]), 'recording.m4a', options);
    assert.deepEqual(openai.getAll('keywords[]'), ['Ramble', 'Goodloop']);
    assert.equal(openai.get('prompt'), null);
  });

  it('removes filler words when on, keeps them when off', async () => {
    const said = 'Um, so I think, uh, we should ship it';
    let s = setup({ groq: groqOK(said) });
    assert.equal((await transcribeNote(AUDIO, opts({ removeFillerWords: true }), s.env, s.deps)).text, 'so I think, we should ship it');
    s = setup({ groq: groqOK(said) });
    assert.equal((await transcribeNote(AUDIO, opts(), s.env, s.deps)).text, said);
  });

  it('breaks paragraphs on 2-second pauses from Groq segments', async () => {
    const groq = () =>
      json({
        text: 'First part. Second part.',
        duration: 10,
        segments: [
          { start: 0, end: 2, text: ' First part.', no_speech_prob: 0, avg_logprob: -0.1 },
          { start: 5, end: 7, text: ' Second part.', no_speech_prob: 0, avg_logprob: -0.1 },
        ],
      });
    const { env, deps } = setup({ groq });
    const out = await transcribeNote(AUDIO, opts(), env, deps);
    assert.equal(out.text, 'First part.\n\nSecond part.');
  });

  it('rebuilds Deepgram paragraphs from sentence timings', async () => {
    const deepgram = () =>
      json({
        metadata: { duration: 10 },
        results: {
          channels: [
            {
              alternatives: [
                {
                  transcript: 'One. Two. Three.',
                  paragraphs: {
                    transcript: '\nOne. Two. Three.',
                    paragraphs: [
                      {
                        sentences: [
                          { text: 'One.', start: 0, end: 1 },
                          { text: 'Two.', start: 1.5, end: 2 },
                          { text: 'Three.', start: 4.5, end: 5 },
                        ],
                      },
                    ],
                  },
                },
              ],
            },
          ],
        },
      });
    const { env, deps } = setup({ groq: fail(503), deepgram });
    const out = await transcribeNote(AUDIO, opts(), env, deps);
    assert.equal(out.text, 'One. Two.\n\nThree.');
  });

  it('groups sentences for OpenAI text with no timings', async () => {
    const sentence = 'This is a sentence that is about fifty characters. ';
    const text = sentence.repeat(12).trim();
    const { env, deps } = setup({ groq: fail(500), deepgram: fail(500), openai: openaiOK(text) });
    const out = await transcribeNote(AUDIO, opts(), env, deps);
    assert.ok(out.text.includes('\n\n'));
  });
});

describe('helpers', () => {
  it('classifyHttpFailure', () => {
    assert.equal(classifyHttpFailure(429), 'rate_limited');
    assert.equal(classifyHttpFailure(503), 'unavailable');
    assert.equal(classifyHttpFailure(401), 'key_rejected');
    assert.equal(classifyHttpFailure(403), 'key_rejected');
    assert.equal(classifyHttpFailure(402), 'billing');
    assert.equal(classifyHttpFailure(413), 'too_large');
    assert.equal(classifyHttpFailure(400, 'insufficient_quota'), 'billing');
    assert.equal(classifyHttpFailure(400, 'rate_limit_exceeded'), 'rate_limited');
    assert.equal(classifyHttpFailure(400, 'invalid file format'), 'audio_rejected');
    assert.equal(classifyHttpFailure(422, ''), 'audio_rejected');
  });

  it('parseKeywords splits, cleans and dedupes', () => {
    assert.deepEqual(parseKeywords('Ramble, ramble\nGood<loop>\r\n  Sam  '), ['Ramble', 'Goodloop', 'Sam']);
    assert.equal(parseKeywords(Array.from({ length: 150 }, (_, i) => `t${i}`).join(',')).length, 100);
    assert.equal(parseKeywords('a'.repeat(150))[0].length, 100);
    assert.deepEqual(parseKeywords(''), []);
  });

  it('stripPromptEcho removes a trailing echo only at a word boundary', () => {
    assert.equal(stripPromptEcho('Buy milk. Goodloop, Ramble', 'Goodloop, Ramble'), 'Buy milk.');
    assert.equal(stripPromptEcho('Hello xGoodloop, Ramble', 'Goodloop, Ramble'), 'Hello xGoodloop, Ramble');
  });

  it('stripFillerWords handles drawn-out forms and keeps paragraphs and "like"', () => {
    assert.equal(stripFillerWords('Ummm I like it.\n\nHmm, you know, yes.'), 'I like it.\n\nyou know, yes.');
  });

  it('formatSegmentsIntoParagraphs and formatTextIntoParagraphs', () => {
    assert.equal(formatSegmentsIntoParagraphs([]), '');
    assert.equal(formatTextIntoParagraphs('Short. Text.'), 'Short. Text.');
    const long = 'A sentence of roughly forty characters here. '.repeat(15).trim();
    const paragraphs = formatTextIntoParagraphs(long).split('\n\n');
    assert.ok(paragraphs.length >= 2);
    assert.ok(paragraphs.every((p) => p.length >= 80));
  });
});
