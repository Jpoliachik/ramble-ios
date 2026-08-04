// Unit tests for the proxy's pure request-shaping and transcript-formatting
// helpers. No network, no credentials, no Worker runtime — run with `npm test`.

import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  MODELS,
  MODEL_ALIASES,
  DEFAULT_MODEL,
  resolveModel,
  parseKeywords,
  buildDeepgramParams,
  buildWhisperPrompt,
  stripPromptEcho,
  stripFillerWords,
  formatSegmentsIntoParagraphs,
  formatTextIntoParagraphs,
  resolveDeepgramLanguage,
} from '../src/index.js';

describe('resolveModel', () => {
  it('resolves every model the app can request', () => {
    for (const [id, entry] of Object.entries(MODELS)) {
      assert.deepEqual(resolveModel(id), { id, ...entry });
    }
  });

  it('routes GPT-Transcribe to OpenAI', () => {
    assert.deepEqual(resolveModel('openai-gpt-transcribe'), {
      id: 'openai-gpt-transcribe',
      provider: 'openai',
      upstream: 'gpt-transcribe',
    });
  });

  it('maps legacy model IDs from older app builds to their replacement', () => {
    const resolved = resolveModel('openai-gpt-4o-transcribe');
    assert.equal(resolved.provider, 'openai');
    assert.equal(resolved.upstream, 'gpt-transcribe');
    // Canonical ID, so analytics doesn't split one model across two names.
    assert.equal(resolved.id, 'openai-gpt-transcribe');
  });

  it('points every alias at a model that exists', () => {
    for (const target of Object.values(MODEL_ALIASES)) {
      assert.ok(MODELS[target], `alias target ${target} is not a known model`);
    }
  });

  it('rejects unknown models', () => {
    assert.equal(resolveModel('gpt-5-audio'), null);
    assert.equal(resolveModel(''), null);
  });

  it('has a default model that resolves', () => {
    assert.ok(resolveModel(DEFAULT_MODEL));
  });
});

describe('parseKeywords', () => {
  it('splits on commas and newlines', () => {
    assert.deepEqual(parseKeywords('Goodloop, Ramble\nCloudflare Workers'), [
      'Goodloop',
      'Ramble',
      'Cloudflare Workers',
    ]);
  });

  it('returns an empty list for empty input', () => {
    assert.deepEqual(parseKeywords(''), []);
    assert.deepEqual(parseKeywords('   ,,  \n '), []);
  });

  it('strips angle brackets, which GPT-Transcribe rejects outright', () => {
    assert.deepEqual(parseKeywords('<Ramble>, a<b>c'), ['Ramble', 'abc']);
  });

  it('never emits a keyword containing a line break or angle bracket', () => {
    const keywords = parseKeywords('a\r\nb, <c>\nd\re, f');
    for (const term of keywords) {
      assert.doesNotMatch(term, /[<>\r\n]/, `"${term}" is not a valid keyword`);
    }
  });

  it('collapses internal whitespace', () => {
    assert.deepEqual(parseKeywords('  Cloudflare   Workers  '), ['Cloudflare Workers']);
  });

  it('dedupes case-insensitively, keeping the first spelling', () => {
    assert.deepEqual(parseKeywords('Ramble, ramble, RAMBLE'), ['Ramble']);
  });

  it('caps the number of keywords', () => {
    const many = Array.from({ length: 250 }, (_, i) => `term${i}`).join(',');
    assert.equal(parseKeywords(many).length, 100);
  });

  it('caps the length of a single keyword', () => {
    const [term] = parseKeywords('x'.repeat(500));
    assert.equal(term.length, 100);
  });
});

describe('buildWhisperPrompt', () => {
  it('frames the keyword list as a complete sentence', () => {
    assert.equal(
      buildWhisperPrompt('Goodloop, Ramble'),
      'Names and terms that may come up: Goodloop, Ramble.',
    );
  });
});

describe('stripPromptEcho', () => {
  const vocabulary = 'Goodloop, Ramble';

  it('strips the prompt sentence when Whisper echoes it', () => {
    const text = `Shipping the new build today. ${buildWhisperPrompt(vocabulary)}`;
    assert.equal(stripPromptEcho(text, vocabulary), 'Shipping the new build today.');
  });

  it('strips a bare echoed list', () => {
    assert.equal(
      stripPromptEcho('Shipping the new build today. Goodloop, Ramble', vocabulary),
      'Shipping the new build today.',
    );
  });

  it('leaves the transcript alone when there is no echo', () => {
    const text = 'Shipping the new build today.';
    assert.equal(stripPromptEcho(text, vocabulary), text);
  });

  it('keeps a legitimate mention that only ends with a keyword', () => {
    const text = 'I was talking to the team about Ramble';
    assert.equal(stripPromptEcho(text, vocabulary), text);
  });

  it('does not cut mid-word', () => {
    const text = 'We should preramble';
    assert.equal(stripPromptEcho(text, 'ramble'), text);
  });

  it('handles empty inputs', () => {
    assert.equal(stripPromptEcho('', vocabulary), '');
    assert.equal(stripPromptEcho('Some text', ''), 'Some text');
  });
});

describe('stripFillerWords', () => {
  it('removes disfluencies', () => {
    assert.equal(
      stripFillerWords('Um, I think, uh, we should ship it.'),
      'I think, we should ship it.',
    );
  });

  it('preserves paragraph breaks', () => {
    assert.equal(
      stripFillerWords('Um, first thought.\n\nUh, second thought.'),
      'first thought.\n\nsecond thought.',
    );
  });

  it('leaves words that merely contain a filler substring', () => {
    const text = 'The number is umbrella-shaped.';
    assert.equal(stripFillerWords(text), text);
  });

  it('handles empty input', () => {
    assert.equal(stripFillerWords(''), '');
  });
});

describe('formatSegmentsIntoParagraphs', () => {
  it('breaks on pauses longer than the threshold', () => {
    const segments = [
      { text: 'First thought.', start: 0, end: 2 },
      { text: 'Still the first.', start: 2.5, end: 4 },
      { text: 'New thought.', start: 8, end: 10 },
    ];
    assert.equal(
      formatSegmentsIntoParagraphs(segments),
      'First thought. Still the first.\n\nNew thought.',
    );
  });

  it('returns an empty string for no segments', () => {
    assert.equal(formatSegmentsIntoParagraphs([]), '');
  });
});

describe('formatTextIntoParagraphs', () => {
  const sentence = 'This is a sentence of a reasonable length that a person might actually say. ';

  it('leaves short transcripts as a single block', () => {
    const text = 'Just a quick note to self. Buy milk.';
    assert.equal(formatTextIntoParagraphs(text), text);
  });

  it('groups sentences into paragraphs once the transcript is long', () => {
    const result = formatTextIntoParagraphs(sentence.repeat(12));
    const paragraphs = result.split('\n\n');
    assert.ok(paragraphs.length > 1, 'expected multiple paragraphs');
    for (const paragraph of paragraphs) {
      assert.doesNotMatch(paragraph, /^\s|\s$/, 'paragraphs should be trimmed');
    }
  });

  it('preserves every word', () => {
    const input = sentence.repeat(12).trim();
    const result = formatTextIntoParagraphs(input);
    assert.equal(result.split(/\s+/).join(' '), input.split(/\s+/).join(' '));
  });

  it('leaves text that the provider already paragraphed', () => {
    const text = `${sentence.repeat(5)}\n\n${sentence.repeat(5)}`.trim();
    assert.equal(formatTextIntoParagraphs(text), text);
  });

  it('leaves a long transcript with no sentence boundaries alone', () => {
    const text = 'word '.repeat(200).trim();
    assert.equal(formatTextIntoParagraphs(text), text);
  });

  it('does not leave a stubby orphan paragraph at the end', () => {
    const result = formatTextIntoParagraphs(`${sentence.repeat(12)}Yeah.`);
    const paragraphs = result.split('\n\n');
    assert.ok(paragraphs[paragraphs.length - 1].length >= 80);
  });

  it('handles empty and whitespace input', () => {
    assert.equal(formatTextIntoParagraphs(''), '');
    assert.equal(formatTextIntoParagraphs('   '), '');
  });

  it('breaks on CJK sentence terminators', () => {
    const cjk = '今日は新しいビルドを出荷します。'.repeat(60);
    const result = formatTextIntoParagraphs(cjk);
    assert.ok(result.includes('\n\n'), 'expected paragraph breaks in CJK text');
  });
});

describe('buildDeepgramParams', () => {
  const options = { language: null, keywords: [], removeFillerWords: false };

  it('requests Nova-3 with smart formatting and paragraphs', () => {
    const params = buildDeepgramParams(options);
    assert.equal(params.get('model'), 'nova-3');
    assert.equal(params.get('smart_format'), 'true');
    assert.equal(params.get('paragraphs'), 'true');
  });

  it('opts into filler words when the user is not removing them', () => {
    assert.equal(buildDeepgramParams(options).get('filler_words'), 'true');
  });

  it('opts out of filler words when the user is removing them', () => {
    const params = buildDeepgramParams({ ...options, removeFillerWords: true });
    assert.equal(params.get('filler_words'), 'false');
  });

  it('sends one keyterm per keyword', () => {
    const params = buildDeepgramParams({ ...options, keywords: ['Goodloop', 'Ramble'] });
    assert.deepEqual(params.getAll('keyterm'), ['Goodloop', 'Ramble']);
  });

  it('sends no keyterm when there are no keywords', () => {
    assert.deepEqual(buildDeepgramParams(options).getAll('keyterm'), []);
  });

  it('passes the resolved language hint', () => {
    assert.equal(buildDeepgramParams(options).get('language'), 'multi');
    assert.equal(buildDeepgramParams({ ...options, language: 'de' }).get('language'), 'de');
  });
});

describe('resolveDeepgramLanguage', () => {
  it('uses multilingual mode when no language is set', () => {
    assert.equal(resolveDeepgramLanguage(null), 'multi');
    assert.equal(resolveDeepgramLanguage(''), 'multi');
  });

  it('passes supported languages through verbatim', () => {
    assert.equal(resolveDeepgramLanguage('de'), 'de');
    assert.equal(resolveDeepgramLanguage('ja'), 'ja');
  });

  it('falls back to English for languages Nova-3 does not support', () => {
    assert.equal(resolveDeepgramLanguage('cy'), 'en');
  });
});
