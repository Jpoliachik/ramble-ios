// Notes: upload acceptance, refusals, idempotency, holds, retries, the
// pipeline, visibility, the device copy and acks. specs/relay-api.md "Notes".

import assert from 'node:assert/strict';
import { beforeEach, describe, it } from 'node:test';

import { TranscribeError } from '../src/transcribe.js';
import { DAY, HOUR, MINUTE, T0, createHarness, noteId } from './harness.js';

let h;
beforeEach(() => {
  h = createHarness();
});

const freeUsed = async (secret) => (await h.call('GET', '/account', { auth: secret })).body.free_notes_remaining;

describe('upload acceptance', () => {
  it('answers 201 done with the transcript when it is quick, and deletes the audio', async () => {
    const secret = await h.inbox();
    const watch = await h.watchToken(secret);
    const res = await h.upload(watch, noteId(1).toLowerCase());
    assert.equal(res.status, 201);
    assert.deepEqual(res.body, {
      id: noteId(1),
      source: 'watch',
      status: 'done',
      result: 'transcript',
      recorded_at: '2026-11-01T06:59:00-05:00',
      received_at: new Date(T0).toISOString(),
      duration: 12,
      transcript: 'hello world',
      transcript_cleared: false,
    });
    await h.settle();
    assert.equal(h.bucket.objects.size, 0);
    assert.equal(h.rows('SELECT audio_key FROM notes')[0].audio_key, null);
    assert.equal(await freeUsed(secret), 24);
  });

  it('answers transcribing when the transcript takes longer, and finishes in the background', async () => {
    const secret = await h.inbox();
    let release;
    h.transcribe = () => new Promise((resolve) => (release = () => resolve({ result: 'transcript', text: 'later', provider: 'groq' })));
    const res = await h.upload(secret, noteId(1));
    assert.equal(res.status, 201);
    assert.equal(res.body.status, 'transcribing');
    assert.equal(res.body.transcript, null);
    assert.equal(res.body.duration, null);
    release();
    await h.settle();
    const read = await h.call('GET', `/notes/${noteId(1)}`, { auth: secret });
    assert.equal(read.body.status, 'done');
    assert.equal(read.body.transcript, 'later');
  });

  it('passes the inbox settings and the measured length to the transcriber', async () => {
    const secret = await h.inbox();
    await h.call('PUT', '/settings', { auth: secret, body: { language: 'es', remove_filler_words: true, vocabulary: 'Goodloop' } });
    h.measured = 42;
    await h.upload(secret, noteId(1), { type: 'audio/x-m4a; codecs=aac' });
    assert.deepEqual(h.transcribeCalls[0].opts, {
      contentType: 'audio/x-m4a',
      language: 'es',
      removeFillerWords: true,
      vocabulary: 'Goodloop',
      durationSeconds: 42,
    });
  });

  it('keeps note IDs per inbox', async () => {
    const a = await h.inbox();
    const b = await h.inbox();
    assert.equal((await h.upload(a, noteId(1))).status, 201);
    assert.equal((await h.upload(b, noteId(1))).status, 201);
    assert.equal(h.rows('SELECT COUNT(*) AS n FROM notes')[0].n, 2);
  });

  it('marks a silent note no_speech, uses a free note, and copies it to nobody', async () => {
    const secret = await h.inbox();
    const agent = await h.connect(secret);
    h.now = T0 + MINUTE;
    h.transcribe = async () => ({ result: 'no_speech', text: '', provider: 'groq' });
    const res = await h.upload(secret, noteId(1), { recordedAt: new Date(T0 + 30000).toISOString() });
    assert.equal(res.body.result, 'no_speech');
    assert.equal(res.body.transcript, '');
    assert.equal(await freeUsed(secret), 24);
    assert.deepEqual((await h.call('GET', '/inbox', { auth: agent })).body.items, []);
  });
});

describe('upload refusals store and count nothing', () => {
  const cases = [
    ['too large', { bytes: 20 * 1024 * 1024 + 1 }, 413, 'too_large'],
    ['wrong type', { type: 'audio/wav' }, 415, 'unsupported_type'],
    ['empty', { bytes: 0 }, 400, 'bad_upload'],
    ['bad recorded time', { recordedAt: 'yesterday' }, 400, 'bad_upload'],
    ['recorded time without offset', { recordedAt: '2026-11-01T11:59:00' }, 400, 'bad_upload'],
  ];
  for (const [name, opts, status, reason] of cases) {
    it(name, async () => {
      const secret = await h.inbox();
      const res = await h.upload(secret, noteId(1), opts);
      assert.equal(res.status, status);
      assert.equal(res.body.reason, reason);
      assert.equal(h.rows('SELECT COUNT(*) AS n FROM notes')[0].n, 0);
      assert.equal(h.bucket.objects.size, 0);
      assert.equal(await freeUsed(secret), 25);
    });
  }

  it('too long by the container', async () => {
    const secret = await h.inbox();
    h.measured = 3 * 3600;
    const res = await h.upload(secret, noteId(1));
    assert.equal(res.status, 413);
    assert.equal(res.body.reason, 'too_long');
    assert.equal(h.bucket.objects.size, 0);
  });

  it('needs a Content-Length', async () => {
    const secret = await h.inbox();
    const res = await h.call('PUT', `/notes/${noteId(1)}`, {
      auth: secret,
      raw: null,
      headers: { 'Content-Type': 'audio/mp4', 'X-Ramble-Recorded-At': '2026-11-01T11:59:00Z' },
    });
    assert.equal(res.status, 411);
    assert.equal(res.body.reason, 'length_required');
  });

  it('a body shorter than its Content-Length is a bad upload', async () => {
    const secret = await h.inbox();
    const res = await h.upload(secret, noteId(1), { headers: { 'Content-Length': '5000' } });
    assert.equal(res.status, 400);
    assert.equal(res.body.reason, 'bad_upload');
  });

  it('fails closed when audio storage is down', async () => {
    const secret = await h.inbox();
    h.bucket.failPut = true;
    const res = await h.upload(secret, noteId(1));
    assert.equal(res.status, 503);
    assert.equal(res.body.reason, 'unavailable');
    assert.equal(await freeUsed(secret), 25);
  });

  it('fails closed when the database is down', async () => {
    const secret = await h.inbox();
    h.db.sqlite.exec('DROP TABLE purchases');
    const res = await h.upload(secret, noteId(1));
    assert.equal(res.status, 503);
    assert.equal(res.body.reason, 'unavailable');
    assert.equal(h.rows('SELECT COUNT(*) AS n FROM notes')[0].n, 0);
    assert.equal(h.bucket.objects.size, 0);
  });
});

describe('idempotency', () => {
  it('a repeat gets 200 with the current state, before the body is read, counting nothing', async () => {
    const secret = await h.inbox();
    await h.upload(secret, noteId(1));
    const again = await h.call('PUT', `/notes/${noteId(1)}`, { auth: secret, raw: null, headers: {} });
    assert.equal(again.status, 200);
    assert.equal(again.body.status, 'done');
    assert.equal(h.transcribeCalls.length, 1);
    assert.equal(await freeUsed(secret), 24);
  });

  it('concurrent uploads of one ID make one note, counted once', async () => {
    const secret = await h.inbox();
    const results = await Promise.all([h.upload(secret, noteId(1)), h.upload(secret, noteId(1)), h.upload(secret, noteId(1))]);
    await h.settle();
    assert.equal(results.filter((r) => r.status === 201).length, 1);
    assert.ok(results.every((r) => r.status === 201 || r.status === 200));
    assert.equal(await freeUsed(secret), 24);
    assert.equal(h.transcribeCalls.length, 1);
    assert.equal(h.bucket.objects.size, 0);
  });

  it('watch and phone racing for the last free note: exactly one is accepted', async () => {
    const secret = await h.inbox();
    const watch = await h.watchToken(secret);
    h.db.sqlite.exec('UPDATE inboxes SET free_notes_used = 24');
    const [a, b] = await Promise.all([h.upload(watch, noteId(1)), h.upload(secret, noteId(2))]);
    assert.deepEqual([a.status, b.status].sort(), [201, 402]);
    assert.equal(h.rows('SELECT COUNT(*) AS n FROM notes')[0].n, 1);
    assert.equal(await freeUsed(secret), 0);
    await h.settle();
    assert.equal(h.bucket.objects.size, 0);
  });
});

describe('held uploads', () => {
  it('402 free_notes_used after 25, and 201 after the unlock', async () => {
    const { inbox_secret: secret, account_token: token } = await h.newInbox();
    for (let i = 1; i <= 25; i++) assert.equal((await h.upload(secret, noteId(i))).status, 201);
    const held = await h.upload(secret, noteId(26));
    assert.equal(held.status, 402);
    assert.deepEqual({ ...held.body, error: undefined }, { error: undefined, reason: 'free_notes_used', free_notes_remaining: 0 });
    assert.equal(h.rows('SELECT COUNT(*) AS n FROM notes')[0].n, 25);

    const { unlockTx } = await import('./harness.js');
    assert.equal((await h.call('POST', '/entitlement', { auth: secret, body: { signed_transaction: unlockTx(token) } })).status, 200);
    assert.equal((await h.upload(secret, noteId(26))).status, 201);
  });

  it('a note with a long measured length transcribes, counts toward usage, and uses no free note when unlocked', async () => {
    const { unlockTx } = await import('./harness.js');
    const { inbox_secret: secret, account_token: token } = await h.newInbox();
    await h.call('POST', '/entitlement', { auth: secret, body: { signed_transaction: unlockTx(token) } });
    h.measured = 59 * 60;
    h.transcribe = async () => ({ result: 'transcript', text: 'x', provider: 'groq', durationSeconds: 5 * 3600 });
    assert.equal((await h.upload(secret, noteId(1))).status, 201);
    await h.settle();
    assert.deepEqual(h.rows('SELECT user_id, month, seconds FROM usage').map((r) => ({ ...r })), [
      { user_id: 'unlock:otx1', month: '2026-11', seconds: 5 * 3600 },
    ]);
    assert.equal(await freeUsed(secret), 25);
  });
});

describe('heavy use is monitored, never refused', () => {
  // The harness sets HEAVY_USE_HOURS to 50; the real figure is a Worker secret.
  const heavyAlerts = () => h.alerts.filter((a) => a.includes('50 hours of audio'));

  it('passing the threshold in a month alerts the operator once, and every note still transcribes', async () => {
    const { unlockTx } = await import('./harness.js');
    const { inbox_secret: secret, account_token: token } = await h.newInbox();
    await h.call('POST', '/entitlement', { auth: secret, body: { signed_transaction: unlockTx(token) } });
    h.db.sqlite.exec(`INSERT INTO usage (user_id, month, seconds) VALUES ('unlock:otx1', '2026-11', ${50 * 3600 - 600})`);
    h.measured = 59 * 60;
    h.transcribe = async () => ({ result: 'transcript', text: 'x', provider: 'groq', durationSeconds: 59 * 60 });
    assert.equal((await h.upload(secret, noteId(1))).status, 201);
    await h.settle();
    assert.equal(heavyAlerts().length, 1);
    assert.ok(heavyAlerts()[0].includes('unlock:otx1'));
    assert.ok(heavyAlerts()[0].includes('2026-11'));

    // Past the line, and past the alert cooldown: still accepted, no second alert.
    h.now += 7 * HOUR;
    for (let i = 2; i <= 4; i++) {
      const res = await h.upload(secret, noteId(i));
      assert.equal(res.status, 201);
      assert.equal(res.body.status, 'done');
    }
    await h.cron();
    assert.equal(heavyAlerts().length, 1);
  });

  it('sends no heavy-use alert while HEAVY_USE_HOURS is unset', async () => {
    h.envExtra = { HEAVY_USE_HOURS: undefined };
    const secret = await h.inbox();
    h.measured = 59 * 60;
    h.transcribe = async () => ({ result: 'transcript', text: 'x', provider: 'groq', durationSeconds: 59 * 60 });
    h.db.sqlite.exec(`INSERT INTO usage (user_id, month, seconds) SELECT id, '2026-11', ${50 * 3600 - 600} FROM inboxes`);
    assert.equal((await h.upload(secret, noteId(1))).status, 201);
    await h.settle();
    assert.equal(h.alerts.filter((a) => a.includes('hours of audio')).length, 0);
  });

  it('counts an inbox with no purchase by its inbox ID, and only transcribed audio', async () => {
    const secret = await h.inbox();
    h.measured = 30;
    h.transcribe = async () => ({ result: 'transcript', text: 'x', provider: 'groq', durationSeconds: 30 });
    await h.upload(secret, noteId(1));
    h.transcribe = async () => {
      throw new TranscribeError('bad audio', { retryable: false });
    };
    await h.upload(secret, noteId(2));
    await h.settle();
    const rows = h.rows('SELECT user_id, seconds FROM usage');
    assert.equal(rows.length, 1);
    assert.match(rows[0].user_id, /^inb_/);
    assert.equal(rows[0].seconds, 30);
  });

  it('starts a new tally each UTC month', async () => {
    const secret = await h.inbox();
    await h.upload(secret, noteId(1));
    h.now = Date.UTC(2026, 11, 1, 0, 5);
    await h.upload(secret, noteId(2), { recordedAt: new Date(h.now).toISOString() });
    await h.settle();
    assert.deepEqual(h.rows('SELECT month FROM usage ORDER BY month').map((r) => r.month), ['2026-11', '2026-12']);
  });
});

describe('suspended users', () => {
  it('a suspended inbox is refused with 403 suspended, storing and counting nothing; others are unaffected', async () => {
    const secret = await h.inbox();
    const other = await h.inbox();
    const watch = await h.watchToken(secret);
    assert.equal((await h.upload(secret, noteId(1))).status, 201);
    const [{ id }] = h.rows('SELECT id FROM inboxes ORDER BY created_at, rowid LIMIT 1');
    h.db.sqlite.exec(`UPDATE inboxes SET suspended = 1 WHERE id = '${id}'`);

    for (const cred of [secret, watch]) {
      const res = await h.upload(cred, noteId(cred === secret ? 2 : 3));
      assert.equal(res.status, 403);
      assert.equal(res.body.reason, 'suspended');
    }
    assert.equal(h.rows(`SELECT COUNT(*) AS n FROM notes WHERE inbox_id = '${id}'`)[0].n, 1);
    assert.equal(h.bucket.objects.size, 0);
    assert.equal(await freeUsed(secret), 24);
    // A repeat of a note accepted before still reads its state.
    assert.equal((await h.call('PUT', `/notes/${noteId(1)}`, { auth: secret, raw: null, headers: {} })).status, 200);
    // Everyone else uploads as usual.
    assert.equal((await h.upload(other, noteId(1))).status, 201);

    h.db.sqlite.exec(`UPDATE inboxes SET suspended = 0 WHERE id = '${id}'`);
    assert.equal((await h.upload(secret, noteId(2))).status, 201);
  });

  it('a suspended purchase refuses every inbox bound to it', async () => {
    const { unlockTx } = await import('./harness.js');
    const first = await h.newInbox();
    await h.call('POST', '/entitlement', { auth: first.inbox_secret, body: { signed_transaction: unlockTx(first.account_token) } });
    const second = await h.newInbox();
    await h.call('POST', '/entitlement', { auth: second.inbox_secret, body: { signed_transaction: unlockTx(first.account_token) } });
    const stranger = await h.inbox();
    h.db.sqlite.exec(`UPDATE purchases SET suspended = 1 WHERE id = 'unlock:otx1'`);

    for (const secret of [first.inbox_secret, second.inbox_secret]) {
      const res = await h.upload(secret, noteId(1));
      assert.equal(res.status, 403);
      assert.equal(res.body.reason, 'suspended');
    }
    assert.equal((await h.upload(stranger, noteId(1))).status, 201);
    // GET /account is unchanged by a suspension.
    assert.equal((await h.call('GET', '/account', { auth: first.inbox_secret })).body.unlocked, true);
  });
});

describe('the pipeline', () => {
  it('retries retryable failures with backoff, then succeeds from the sweeper', async () => {
    const secret = await h.inbox();
    h.providersDown();
    const res = await h.upload(secret, noteId(1));
    assert.equal(res.body.status, 'transcribing');
    await h.settle();
    const row = h.rows('SELECT next_attempt_at, attempt_started_at FROM notes')[0];
    assert.equal(row.next_attempt_at, T0 + MINUTE);
    assert.equal(row.attempt_started_at, null);

    h.transcribe = async () => ({ result: 'transcript', text: 'finally', provider: 'groq' });
    h.now = T0 + MINUTE;
    await h.cron();
    const read = await h.call('GET', `/notes/${noteId(1)}`, { auth: secret });
    assert.equal(read.body.transcript, 'finally');
  });

  it('fails retries_exhausted after 20 hours and gives the free note back', async () => {
    const secret = await h.inbox();
    h.providersDown();
    await h.upload(secret, noteId(1));
    await h.settle();
    assert.equal(await freeUsed(secret), 24);
    for (let i = 0; i < 60 && h.rows("SELECT status FROM notes")[0].status === 'transcribing'; i++) {
      h.now = h.rows('SELECT next_attempt_at FROM notes')[0].next_attempt_at ?? h.now + MINUTE;
      await h.cron();
    }
    const note = (await h.call('GET', `/notes/${noteId(1)}`, { auth: secret })).body;
    assert.equal(note.status, 'failed');
    assert.equal(note.result, 'retries_exhausted');
    assert.ok(h.now <= T0 + 20 * HOUR);
    assert.equal(await freeUsed(secret), 25);
    assert.equal(h.bucket.objects.size, 0);
  });

  it('fails audio_rejected at once, refunds once, and deletes the audio', async () => {
    const secret = await h.inbox();
    h.rejectAudio();
    const res = await h.upload(secret, noteId(1));
    assert.equal(res.body.status, 'failed');
    assert.equal(res.body.result, 'audio_rejected');
    assert.equal(await freeUsed(secret), 25);
    await h.cron();
    assert.equal(await freeUsed(secret), 25);
    assert.equal(h.bucket.objects.size, 0);
  });

  it('gives the upload attempt a short Groq timeout, and the sweeper the long one', async () => {
    const secret = await h.inbox();
    h.providersDown();
    await h.upload(secret, noteId(1));
    assert.deepEqual(h.transcribeCalls[0].deps, { timeoutMs: 20_000 });
    h.transcribe = async () => ({ result: 'transcript', text: 'ok', provider: 'groq' });
    h.now = T0 + MINUTE;
    await h.cron();
    assert.equal(h.transcribeCalls.length, 2);
    assert.deepEqual(h.transcribeCalls[1].deps, {});
  });

  it('picks up an upload attempt lost for 1 minute', async () => {
    const secret = await h.inbox();
    h.transcribe = () => new Promise(() => {}); // the worker was cut off mid-attempt
    await h.upload(secret, noteId(1));
    h.transcribe = async () => ({ result: 'transcript', text: 'recovered', provider: 'groq' });
    h.now = T0 + 59 * 1000;
    await h.cron();
    assert.equal(h.transcribeCalls.length, 1);
    h.now = T0 + MINUTE;
    await h.cron();
    assert.equal(h.transcribeCalls.length, 2);
    assert.equal((await h.call('GET', `/notes/${noteId(1)}`, { auth: secret })).body.transcript, 'recovered');
  });

  it('picks up a sweeper attempt lost for 8 minutes', async () => {
    const secret = await h.inbox();
    h.transcribe = () => new Promise(() => {}); // the worker stopped mid-attempt
    await h.upload(secret, noteId(1));
    // As if that attempt had been a later one, started by the cron.
    h.db.sqlite.exec('UPDATE notes SET attempts = 2');
    h.transcribe = async () => ({ result: 'transcript', text: 'recovered', provider: 'groq' });
    h.now = T0 + 7 * MINUTE;
    await h.cron();
    assert.equal(h.transcribeCalls.length, 1);
    h.now = T0 + 8 * MINUTE;
    await h.cron();
    assert.equal(h.transcribeCalls.length, 2);
    assert.equal((await h.call('GET', `/notes/${noteId(1)}`, { auth: secret })).body.transcript, 'recovered');
  });

  it('makes agent copies first, and the sweeper makes any that failed, once', async () => {
    const secret = await h.inbox();
    const agent = await h.connect(secret);
    h.now = T0 + MINUTE;
    // The first copy insertion fails, as if D1 hiccuped mid-pipeline.
    const batch = h.db.batch;
    let failures = 1;
    h.db.batch = async (statements) => {
      if (failures > 0 && statements.some((s) => /INTO entries/.test(s.sql))) {
        failures--;
        throw new Error('D1 hiccup');
      }
      return batch(statements);
    };
    const res = await h.upload(secret, noteId(1), { recordedAt: new Date(T0 + 30000).toISOString() });
    await h.settle();
    assert.equal(res.body.status, 'done');
    assert.equal(h.bucket.objects.size, 0); // later steps still ran
    assert.equal(h.rows('SELECT copies_made_at FROM notes')[0].copies_made_at, null);
    assert.deepEqual((await h.call('GET', '/inbox', { auth: agent })).body.items, []);

    h.now = T0 + 2 * MINUTE;
    await h.cron();
    const items = (await h.call('GET', '/inbox', { auth: agent })).body.items;
    assert.equal(items.length, 1);
    assert.equal(items[0].transcription, 'hello world');
    assert.equal(h.rows('SELECT copies_made_at FROM notes')[0].copies_made_at, T0 + 2 * MINUTE);

    // Marked made: later sweeps copy nothing again, even after the agent acked.
    await h.call('POST', '/inbox/ack', { auth: agent, body: { ids: [items[0].id] } });
    h.now = T0 + 3 * MINUTE;
    await h.cron();
    assert.equal((await h.call('GET', '/inbox', { auth: agent })).body.items.length, 0);
  });

  it('marks copies made when a note finishes normally', async () => {
    const secret = await h.inbox();
    await h.connect(secret);
    h.now = T0 + MINUTE;
    await h.upload(secret, noteId(1), { recordedAt: new Date(T0 + 30000).toISOString() });
    await h.settle();
    assert.equal(h.rows('SELECT copies_made_at FROM notes')[0].copies_made_at, T0 + MINUTE);
  });

  it('fixes options at the first attempt; retries keep them', async () => {
    const secret = await h.inbox();
    h.providersDown();
    await h.upload(secret, noteId(1));
    await h.settle();
    await h.call('PUT', '/settings', { auth: secret, body: { language: null, remove_filler_words: true, vocabulary: '' } });
    h.now = T0 + MINUTE;
    await h.cron();
    assert.equal(h.transcribeCalls[1].opts.removeFillerWords, false);
  });

  it('alerts the operator about a note stuck for 30 minutes, once per 6 hours', async () => {
    const secret = await h.inbox();
    h.transcribe = async () => {
      throw new TranscribeError('slow', { retryable: true, provider: 'groq', status: 503 });
    };
    await h.upload(secret, noteId(1));
    const stuck = () => h.alerts.filter((a) => a.includes('waited more than 30 minutes')).length;
    h.now = T0 + 29 * MINUTE;
    await h.cron();
    assert.equal(stuck(), 0);
    h.now = T0 + 31 * MINUTE;
    await h.cron();
    h.now = T0 + 32 * MINUTE;
    await h.cron();
    assert.equal(stuck(), 1);
  });
});

describe('hand retries', () => {
  const retry = (secret, id, extra = {}) => h.upload(secret, id, { headers: { 'X-Ramble-Retry': '1' }, ...extra });

  it('re-transcribes a failed note once, then 409 retry_limit', async () => {
    const secret = await h.inbox();
    h.rejectAudio();
    await h.upload(secret, noteId(1));
    await h.call('POST', '/notes/ack', { auth: secret, body: { ids: [noteId(1)] } });
    const res = await retry(secret, noteId(1), { recordedAt: '2030-01-01T00:00:00Z' });
    assert.equal(res.status, 201);
    assert.equal(res.body.recorded_at, '2026-11-01T06:59:00-05:00');
    assert.equal(res.body.status, 'failed');
    assert.equal(h.rows('SELECT retry_count FROM notes')[0].retry_count, 1);
    const calls = h.transcribeCalls.length;
    const second = await retry(secret, noteId(1));
    assert.equal(second.status, 409);
    assert.equal(second.body.reason, 'retry_limit');
    assert.equal(h.transcribeCalls.length, calls);
    assert.equal(await freeUsed(secret), 25);
  });

  it('lists the retried note again, and the header means nothing on other notes or from the watch', async () => {
    const secret = await h.inbox();
    const watch = await h.watchToken(secret);
    h.rejectAudio();
    await h.upload(watch, noteId(1));
    await h.call('POST', '/notes/ack', { auth: secret, body: { ids: [noteId(1)] } });
    assert.equal((await h.call('GET', '/notes', { auth: secret })).body.notes.length, 0);

    assert.equal((await retry(watch, noteId(1))).status, 200);
    h.transcribe = async () => ({ result: 'transcript', text: 'second time', provider: 'groq' });
    const res = await retry(secret, noteId(1));
    assert.equal(res.status, 201);
    assert.equal(res.body.source, 'watch');
    assert.equal(res.body.transcript, 'second time');
    assert.equal((await h.call('GET', '/notes', { auth: secret })).body.notes.length, 1);
    assert.equal((await retry(secret, noteId(1))).status, 200);
  });

  it('a retry uses no free note and is never held for free notes', async () => {
    const secret = await h.inbox();
    h.rejectAudio();
    await h.upload(secret, noteId(1));
    assert.equal(await freeUsed(secret), 25);
    h.db.sqlite.exec('UPDATE inboxes SET free_notes_used = 25');
    h.transcribe = async () => ({ result: 'transcript', text: 'ok', provider: 'groq' });
    const res = await retry(secret, noteId(1));
    assert.equal(res.status, 201);
    assert.equal(res.body.transcript, 'ok');
    assert.equal(await freeUsed(secret), 0);
  });

  it('copies a retried note to the agents connected when the retry was accepted', async () => {
    const secret = await h.inbox();
    const early = await h.connect(secret);
    h.now = T0 + 2 * HOUR;
    h.rejectAudio();
    await h.upload(secret, noteId(1), { recordedAt: new Date(T0 + HOUR).toISOString() });
    h.now += MINUTE;
    const late = await h.connect(secret);
    h.now += MINUTE;
    h.transcribe = async () => ({ result: 'transcript', text: 'ok', provider: 'groq' });
    await retry(secret, noteId(1));
    await h.settle();
    assert.equal((await h.call('GET', '/inbox', { auth: early })).body.items.length, 1);
    assert.equal((await h.call('GET', '/inbox', { auth: late })).body.items.length, 1);
  });
});

describe('reading notes', () => {
  it('the watch reads only watch notes; the phone reads everything; others get 404', async () => {
    const secret = await h.inbox();
    const watch = await h.watchToken(secret);
    await h.upload(secret, noteId(1));
    await h.upload(watch, noteId(2));
    assert.equal((await h.call('GET', `/notes/${noteId(1)}`, { auth: watch })).status, 404);
    assert.equal((await h.call('GET', `/notes/${noteId(2)}`, { auth: watch })).status, 200);
    assert.equal((await h.call('GET', `/notes/${noteId(2)}`, { auth: secret })).status, 200);
    assert.equal((await h.call('GET', `/notes/${noteId(3)}`, { auth: secret })).status, 404);
    const other = await h.inbox();
    assert.equal((await h.call('GET', `/notes/${noteId(1)}`, { auth: other })).status, 404);
  });

  it('keeps the copy until the phone acked and the watch has seen it done', async () => {
    const secret = await h.inbox();
    const watch = await h.watchToken(secret);
    let release;
    h.transcribe = () => new Promise((r) => (release = () => r({ result: 'transcript', text: 'hi', provider: 'groq' })));
    assert.equal((await h.upload(watch, noteId(1))).body.status, 'transcribing');
    release();
    await h.settle();
    const ack = await h.call('POST', '/notes/ack', { auth: secret, body: { ids: [noteId(1)] } });
    assert.deepEqual(ack.body, { acked: 1, not_final: [] });
    const first = await h.call('GET', `/notes/${noteId(1)}`, { auth: watch });
    assert.equal(first.body.transcript, 'hi');
    const later = await h.call('GET', `/notes/${noteId(1)}`, { auth: watch });
    assert.equal(later.body.transcript, null);
    assert.equal(later.body.transcript_cleared, true);
    assert.equal(h.rows('SELECT transcript FROM notes')[0].transcript, null);
  });

  it('a phone note clears on ack; cleared notes read for 30 more days, then 404', async () => {
    const secret = await h.inbox();
    await h.upload(secret, noteId(1));
    await h.call('POST', '/notes/ack', { auth: secret, body: { ids: [noteId(1)] } });
    const read = await h.call('GET', `/notes/${noteId(1)}`, { auth: secret });
    assert.equal(read.body.transcript_cleared, true);
    h.now = T0 + 31 * DAY;
    await h.cron();
    assert.equal((await h.call('GET', `/notes/${noteId(1)}`, { auth: secret })).status, 404);
  });

  it('keeps an unacked copy at most 30 days', async () => {
    const secret = await h.inbox();
    await h.upload(secret, noteId(1));
    h.now = T0 + 30 * DAY;
    const read = await h.call('GET', `/notes/${noteId(1)}`, { auth: secret });
    assert.equal(read.body.transcript, null);
    assert.equal(read.body.transcript_cleared, true);
  });

  it('acks leave transcribing notes listed, and ignore unknown ones', async () => {
    const secret = await h.inbox();
    h.transcribe = () => new Promise(() => {});
    await h.upload(secret, noteId(1));
    const res = await h.call('POST', '/notes/ack', { auth: secret, body: { ids: [noteId(1), noteId(9)] } });
    assert.deepEqual(res.body, { acked: 0, not_final: [noteId(1)] });
    assert.equal((await h.call('GET', '/notes', { auth: secret })).body.notes.length, 1);
    assert.equal((await h.call('POST', '/notes/ack', { auth: secret, body: { ids: ['nope'] } })).status, 400);
  });

  it('lists 50 at a time, oldest first, with a cursor', async () => {
    const secret = await h.inbox();
    h.db.sqlite.exec('UPDATE inboxes SET free_notes_used = -100');
    for (let i = 1; i <= 55; i++) {
      h.now = T0 + i * 1000;
      await h.upload(secret, noteId(i));
    }
    const first = await h.call('GET', '/notes', { auth: secret });
    assert.equal(first.body.notes.length, 50);
    assert.equal(first.body.notes[0].id, noteId(1));
    const second = await h.call('GET', `/notes?after=${encodeURIComponent(first.body.next)}`, { auth: secret });
    assert.deepEqual(second.body.notes.map((n) => n.id), [51, 52, 53, 54, 55].map(noteId));
    assert.equal(second.body.next, null);
  });
});

describe('watch token', () => {
  it('a replaced token is revoked; the new one reads the watch notes of its own inbox only', async () => {
    const secret = await h.inbox();
    const old = await h.watchToken(secret);
    h.transcribe = () => new Promise(() => {});
    await h.upload(old, noteId(1));
    const same = await h.watchToken(secret, old);
    assert.equal((await h.call('GET', `/notes/${noteId(1)}`, { auth: old })).status, 401);
    assert.equal((await h.call('GET', `/notes/${noteId(1)}`, { auth: same })).status, 200);

    const fresh = await h.inbox();
    const next = await h.watchToken(fresh, same);
    assert.equal((await h.upload(same, noteId(2))).status, 401);
    assert.equal((await h.call('GET', `/notes/${noteId(1)}`, { auth: same })).status, 401);
    assert.equal((await h.call('GET', `/notes/${noteId(1)}`, { auth: next })).status, 404);
    assert.equal((await h.upload(next, noteId(2))).status, 201);
  });

  it('one live token per inbox; revoking leaves agents alone', async () => {
    const secret = await h.inbox();
    const agent = await h.connect(secret);
    const first = await h.watchToken(secret);
    const second = await h.watchToken(secret);
    assert.equal((await h.upload(first, noteId(1))).status, 401);
    assert.deepEqual((await h.call('DELETE', '/watch-token', { auth: secret })).body, { revoked: 1 });
    assert.equal((await h.call('GET', '/account', { auth: second })).status, 401);
    assert.deepEqual((await h.call('DELETE', '/watch-token', { auth: secret })).body, { revoked: 0 });
    assert.equal((await h.call('GET', '/inbox', { auth: agent })).status, 200);
  });

  it('the watch cannot call phone endpoints', async () => {
    const secret = await h.inbox();
    const watch = await h.watchToken(secret);
    const res = await h.call('GET', '/notes', { auth: watch });
    assert.equal(res.status, 403);
    assert.equal(res.body.reason, 'wrong_credential');
  });
});

it('uploads are not rate-limited', async () => {
  const secret = await h.inbox();
  h.db.sqlite.exec('UPDATE inboxes SET free_notes_used = -1000');
  for (let i = 1; i <= 130; i++) assert.equal((await h.upload(secret, noteId(i))).status, 201);
});

it('a TranscribeError without retryable=false is retried', () => {
  assert.equal(new TranscribeError('x', { retryable: true }).retryable, true);
});
