// Usage stats: one row per finished note, never text, under the inbox's random
// usage id; the app label each device last sent. specs/relay-api.md "Usage stats".

import assert from 'node:assert/strict';
import { beforeEach, describe, it } from 'node:test';

import { T0, createHarness, noteId } from './harness.js';

let h;
beforeEach(() => {
  h = createHarness();
});

const events = () => h.rows('SELECT * FROM note_events ORDER BY recorded_at');
const inboxRow = () => h.rows('SELECT * FROM inboxes')[0];

describe('usage stats', () => {
  it('records a finished note with no text and no inbox id', async () => {
    const secret = await h.inbox();
    await h.call('PUT', '/settings', { auth: secret, body: { language: 'es', vocabulary: 'Goodloop' } });
    const watch = await h.watchToken(secret);
    await h.upload(watch, noteId(1), { headers: { 'X-Ramble-Client': 'Ramble/1.3 (142) watchOS/11.5' } });
    await h.settle();

    const [e] = events();
    const inbox = inboxRow();
    assert.match(inbox.usage_id, /^[0-9a-f]{16}$/);
    assert.equal(e.user_id, inbox.usage_id);
    assert.notEqual(e.note_key, noteId(1));
    assert.equal(e.source, 'watch');
    assert.equal(e.recorded_at, Date.parse('2026-11-01T06:59:00-05:00'));
    assert.equal(e.accepted_at, T0);
    assert.equal(e.duration, 12);
    assert.equal(e.result, 'transcript');
    assert.equal(e.attempts, 1);
    assert.equal(e.hand_retries, 0);
    assert.equal(e.free_note, 1);
    assert.equal(e.language, 'es');
    assert.equal(e.filler_removal, 0);
    assert.equal(e.vocabulary, 1);
    assert.equal(e.app, 'Ramble/1.3 (142) watchOS/11.5');
    const stored = JSON.stringify(e);
    assert.ok(!stored.includes('hello world') && !stored.includes('Goodloop') && !stored.includes(inbox.id));
    assert.equal(inbox.watch_app, 'Ramble/1.3 (142) watchOS/11.5');
  });

  it('records a failed note as not free, and rewrites the row after a hand retry', async () => {
    const secret = await h.inbox();
    h.rejectAudio();
    await h.upload(secret, noteId(1));
    assert.equal(events()[0].result, 'audio_rejected');
    assert.equal(events()[0].free_note, 0);

    h.transcribe = async () => ({ result: 'transcript', text: 'ok', provider: 'groq', durationSeconds: 5 });
    await h.upload(secret, noteId(1), { headers: { 'X-Ramble-Retry': '1' } });
    await h.settle();
    assert.equal(events().length, 1);
    assert.equal(events()[0].result, 'transcript');
    assert.equal(events()[0].hand_retries, 1);
  });

  it('gives each inbox its own usage id', async () => {
    const a = await h.inbox();
    const b = await h.inbox();
    await h.upload(a, noteId(1));
    await h.upload(b, noteId(2));
    await h.settle();
    const [x, y] = events();
    assert.notEqual(x.user_id, y.user_id);
  });

  it('keeps the phone app label from check-ins, and ignores a malformed one', async () => {
    const secret = await h.inbox();
    await h.call('GET', '/notes', { auth: secret, headers: { 'X-Ramble-Client': 'Ramble/1.3 (142) iOS/26.2' } });
    assert.equal(inboxRow().phone_app, 'Ramble/1.3 (142) iOS/26.2');
    await h.call('GET', '/notes', { auth: secret, headers: { 'X-Ramble-Client': 'x'.repeat(200) } });
    assert.equal(inboxRow().phone_app, 'Ramble/1.3 (142) iOS/26.2');
  });

  it('keeps note rows after the note itself is purged', async () => {
    const secret = await h.inbox();
    await h.upload(secret, noteId(1));
    await h.settle();
    for (let i = 0; i < 2; i++) {
      h.now += 31 * 24 * 60 * 60 * 1000;
      await h.cron();
    }
    assert.equal(h.rows('SELECT COUNT(*) AS n FROM notes')[0].n, 0);
    assert.equal(events().length, 1);
  });
});

describe('delivery stats', () => {
  it('records how an agent last reached Ramble', async () => {
    const secret = await h.inbox();
    const key = await h.connect(secret, 'Muse');
    const via = () => h.rows('SELECT via FROM connections')[0].via;
    assert.equal(via(), 'api');
    h.db.sqlite.exec('UPDATE connections SET via = NULL');
    assert.equal((await h.call('GET', '/inbox', { auth: key })).status, 200);
    assert.equal(via(), 'api');
  });

  it('keeps whether the iPhone has a webhook set, never the URL', async () => {
    const secret = await h.inbox();
    const webhook = () => inboxRow().webhook;
    assert.equal(webhook(), null);
    await h.call('GET', '/notes', { auth: secret });
    assert.equal(webhook(), null);
    await h.call('GET', '/notes', { auth: secret, headers: { 'X-Ramble-Webhook': 'on' } });
    assert.equal(webhook(), 1);
    await h.call('GET', '/notes', { auth: secret, headers: { 'X-Ramble-Webhook': 'https://example.com/hook' } });
    assert.equal(webhook(), 1);
    await h.call('GET', '/notes', { auth: secret, headers: { 'X-Ramble-Webhook': 'off' } });
    assert.equal(webhook(), 0);
  });

  it('ignores the webhook header from the watch', async () => {
    const secret = await h.inbox();
    const watch = await h.watchToken(secret);
    await h.call('GET', '/notes', { auth: watch, headers: { 'X-Ramble-Webhook': 'on' } });
    assert.equal(inboxRow().webhook, null);
  });
});
