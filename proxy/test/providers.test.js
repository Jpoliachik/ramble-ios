// Groq call, error classification, options and formatting for
// src/transcribe.js. Fake fetch only: no network, no credentials.

import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  TranscribeError,
  transcribeNote,
  classifyHttpFailure,
  isSilenceText,
  parseKeywords,
  buildGroqForm,
  stripPromptEcho,
  stripFillerWords,
  formatSegmentsIntoParagraphs,
  formatTextIntoParagraphs,
} from '../src/transcribe.js';

const AUDIO = new Uint8Array([0, 1, 2, 3]).buffer;
const KEYS = { GROQ_API_KEY: 'g' };

// groq: (url, init) => Response | throw.
function fakeFetch(groq) {
  const calls = [];
  const fetch = async (url, init) => {
    calls.push({ url, init });
    if (!url.includes('api.groq.com')) throw new Error(`unexpected call to ${url}`);
    if (!groq) throw new Error('unexpected call to groq');
    return groq(url, init);
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

function setup(groq, envExtra = {}) {
  const env = { ...KEYS, ...envExtra };
  const { fetch, calls } = fakeFetch(groq);
  return { env, calls, deps: { fetch } };
}

const opts = (extra = {}) => ({
  contentType: 'audio/mp4',
  language: null,
  removeFillerWords: false,
  vocabulary: '',
  ...extra,
});

describe('transcribeNote: Groq', () => {
  it('uses Groq Whisper v3 Turbo', async () => {
    const { env, calls, deps } = setup(groqOK('Hello there.'));
    const out = await transcribeNote(AUDIO, opts(), env, deps);
    assert.equal(out.result, 'transcript');
    assert.equal(out.text, 'Hello there.');
    assert.equal(out.provider, 'groq');
    assert.equal(out.model, 'whisper-large-v3-turbo');
    assert.equal(out.durationSeconds, 30);
    assert.deepEqual(out.attempts, [{ provider: 'groq', outcome: 'ok', status: null }]);
    assert.equal(calls.length, 1);
    assert.equal(calls[0].url, 'https://api.groq.com/openai/v1/audio/transcriptions');
    assert.equal(calls[0].init.headers.Authorization, 'Bearer g');
    const form = calls[0].init.body;
    assert.equal(form.get('model'), 'whisper-large-v3-turbo');
    assert.equal(form.get('response_format'), 'verbose_json');
    assert.equal(form.get('temperature'), '0');
  });

  it('gives the call 120 seconds by default, or the timeout it is given', async () => {
    for (const [deps, expected] of [[{}, 120_000], [{ timeoutMs: 20_000 }, 20_000]]) {
      const s = setup(groqOK('Hi there.'));
      const timeouts = [];
      const original = AbortSignal.timeout;
      AbortSignal.timeout = (ms) => {
        timeouts.push(ms);
        return original.call(AbortSignal, ms);
      };
      try {
        await transcribeNote(AUDIO, opts(), s.env, { ...s.deps, ...deps });
      } finally {
        AbortSignal.timeout = original;
      }
      assert.deepEqual(timeouts, [expected]);
    }
  });
});

describe('transcribeNote: failures', () => {
  it('Groq 429 is retryable and reported as rate_limited', async () => {
    const { env, deps } = setup(fail(429));
    await assert.rejects(transcribeNote(AUDIO, opts(), env, deps), (err) => {
      assert.ok(err instanceof TranscribeError);
      assert.equal(err.retryable, true);
      assert.equal(err.provider, 'groq');
      assert.equal(err.status, 429);
      assert.deepEqual(err.attempts, [{ provider: 'groq', outcome: 'rate_limited', status: 429 }]);
      return true;
    });
  });

  it('a rejected or missing key is retryable and reported', async () => {
    let s = setup(fail(401));
    await assert.rejects(transcribeNote(AUDIO, opts(), s.env, s.deps), (err) => {
      assert.equal(err.retryable, true);
      assert.equal(err.attempts[0].outcome, 'key_rejected');
      return true;
    });
    s = setup(null, { GROQ_API_KEY: '' });
    await assert.rejects(transcribeNote(AUDIO, opts(), s.env, s.deps), (err) => {
      assert.equal(err.retryable, true);
      assert.equal(err.attempts[0].outcome, 'key_missing');
      return true;
    });
    assert.equal(s.calls.length, 0);
  });

  it('Groq 5xx, unreachable, timeout and unreadable answers are retryable', async () => {
    for (const groq of [
      fail(503),
      () => {
        throw new TypeError('fetch failed');
      },
      () => {
        throw new DOMException('timed out', 'TimeoutError');
      },
      () => json({ nope: true }),
    ]) {
      const { env, deps } = setup(groq);
      await assert.rejects(transcribeNote(AUDIO, opts(), env, deps), (err) => {
        assert.equal(err.retryable, true);
        return true;
      });
    }
  });

  it('Groq billing error, 402 and 413 are retryable and never reject the audio', async () => {
    for (const groq of [
      fail(400, '{"error":{"message":"Organization spend limit reached","code":"spend_limit"}}'),
      fail(402),
      fail(413),
    ]) {
      const { env, deps } = setup(groq);
      await assert.rejects(transcribeNote(AUDIO, opts(), env, deps), (err) => {
        assert.equal(err.retryable, true);
        return true;
      });
    }
  });

  it('Groq 400 for undecodable audio is audio_rejected', async () => {
    const { env, calls, deps } = setup(fail(400, '{"error":{"message":"could not process file - is it a valid media file?"}}'));
    await assert.rejects(transcribeNote(AUDIO, opts(), env, deps), (err) => {
      assert.ok(err instanceof TranscribeError);
      assert.equal(err.retryable, false);
      assert.equal(err.provider, 'groq');
      assert.equal(err.status, 400);
      return true;
    });
    assert.equal(calls.length, 1);
  });

  it('keeps at most 200 characters of a provider error body', async () => {
    const long = 'x'.repeat(5000);
    const { env, deps } = setup(fail(400, long));
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

describe('silent notes', () => {
  it('"Thank you." alone is no speech', async () => {
    const { env, deps } = setup(groqOK('Thank you.'));
    const out = await transcribeNote(AUDIO, opts(), env, deps);
    assert.equal(out.result, 'no_speech');
    assert.equal(out.text, '');
  });

  it('a real thanks inside a longer note survives', async () => {
    const text = 'Thank you. Remind me to call Sam tomorrow.';
    const { env, deps } = setup(groqOK(text));
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
    const { env, deps } = setup(groq);
    const out = await transcribeNote(AUDIO, opts(), env, deps);
    assert.equal(out.result, 'no_speech');
  });

  it('empty text and "too short" rejections are no speech', async () => {
    let s = setup(() => json({ text: '', segments: [] }));
    assert.equal((await transcribeNote(AUDIO, opts(), s.env, s.deps)).result, 'no_speech');
    s = setup(fail(400, '{"error":{"message":"Audio file is too short. Minimum audio length is 0.01 seconds."}}'));
    assert.equal((await transcribeNote(AUDIO, opts(), s.env, s.deps)).result, 'no_speech');
  });

  it('a prompt echo over silence is no speech', async () => {
    const { env, deps } = setup(groqOK('Names and terms that may come up: Goodloop, Ramble.'));
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
  it('passes the language hint to Groq, and none for auto-detect', async () => {
    let s = setup(groqOK('Hola.'));
    await transcribeNote(AUDIO, opts({ language: 'es' }), s.env, s.deps);
    assert.equal(s.calls[0].init.body.get('language'), 'es');

    s = setup(groqOK('Hola.'));
    await transcribeNote(AUDIO, opts({ language: 'auto' }), s.env, s.deps);
    assert.equal(s.calls[0].init.body.get('language'), null);
  });

  it('vocabulary goes to Whisper as a prompt', () => {
    const options = { language: null, keywords: ['Ramble', 'Goodloop'], removeFillerWords: false };
    const groq = buildGroqForm(new Blob([AUDIO]), 'recording.m4a', options);
    assert.equal(groq.get('prompt'), 'Names and terms that may come up: Ramble, Goodloop.');
    const none = buildGroqForm(new Blob([AUDIO]), 'recording.m4a', { ...options, keywords: [] });
    assert.equal(none.get('prompt'), null);
  });

  it('removes filler words when on, keeps them when off', async () => {
    const said = 'Um, so I think, uh, we should ship it';
    let s = setup(groqOK(said));
    assert.equal((await transcribeNote(AUDIO, opts({ removeFillerWords: true }), s.env, s.deps)).text, 'so I think, we should ship it');
    s = setup(groqOK(said));
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
    const { env, deps } = setup(groq);
    const out = await transcribeNote(AUDIO, opts(), env, deps);
    assert.equal(out.text, 'First part.\n\nSecond part.');
  });

  it('groups sentences when Groq gives no timings', async () => {
    const sentence = 'This is a sentence that is about fifty characters. ';
    const text = sentence.repeat(12).trim();
    const { env, deps } = setup(() => json({ text }));
    const out = await transcribeNote(AUDIO, opts(), env, deps);
    assert.ok(out.text.includes('\n\n'));
    assert.equal(out.durationSeconds, null);
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
