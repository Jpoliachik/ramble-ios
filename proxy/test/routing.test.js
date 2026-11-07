// Routing, failing closed, old builds' paths, the cron and operator alerts.

import assert from 'node:assert/strict';
import { beforeEach, describe, it } from 'node:test';

import { handleRequest } from '../src/index.js';
import { LEGACY_RETIRES_AT } from '../src/legacy.js';
import { DAY, HOUR, PREMIUM, T0, createHarness, jws, noteId } from './harness.js';

let h;
beforeEach(() => {
  h = createHarness();
});

describe('basics', () => {
  it('describes itself at GET / and /health, without a database', async () => {
    const res = await handleRequest(new Request('https://relay.test/'), {});
    assert.deepEqual(await res.json(), {
      service: 'Ramble relay',
      docs: 'https://ramble.watch/docs',
      llms: 'https://ramble.watch/llms-full.txt',
    });
    assert.equal((await handleRequest(new Request('https://relay.test/health'), {})).status, 200);
  });

  it('405s a wrong method naming the right one', async () => {
    const res = await h.call('GET', '/inbox/ack');
    assert.equal(res.status, 405);
    assert.match(res.body.error, /Use POST/);
    assert.match(res.body.error, /ramble\.watch\/docs/);
    assert.equal((await h.call('POST', `/notes/${noteId(1)}`)).status, 405);
    assert.equal((await h.call('GET', '/nope')).status, 404);
  });

  it('answers 503 unavailable without a database', async () => {
    const res = await handleRequest(new Request('https://relay.test/account'), {});
    assert.equal(res.status, 503);
    assert.equal((await res.json()).reason, 'unavailable');
  });

  it('answers 503 when the database fails mid-request', async () => {
    const secret = await h.inbox();
    h.db.sqlite.exec('DROP TABLE purchases');
    const res = await h.call('GET', '/account', { auth: secret });
    assert.equal(res.status, 503);
    assert.equal(res.body.reason, 'unavailable');
  });

  it('401s unknown credentials with the spec sentence', async () => {
    const res = await h.call('GET', '/account', { auth: 'rmbi_doesnotexistdoesnotexist' });
    assert.equal(res.status, 401);
    assert.equal(res.body.error, 'Invalid or revoked credentials. Send "Authorization: Bearer <token>".');
  });

  it('passes the attest result reason through', async () => {
    const res = await h.call('POST', '/attest', {
      body: {},
      deps: { handleAttest: async () => ({ error: 'This key ID is already registered', status: 409, reason: 'key_exists' }) },
    });
    assert.deepEqual([res.status, res.body.reason], [409, 'key_exists']);
  });
});

describe('old builds', () => {
  const transcribeRequest = (record) => {
    const form = new FormData();
    form.append('audio', new File([new Uint8Array(500)], 'r.m4a', { type: 'audio/m4a' }));
    form.append('model', 'openai-gpt-transcribe');
    form.append('language', 'es');
    return new Request('https://relay.test/transcribe', {
      method: 'POST',
      headers: { Authorization: `Bearer ${record}`, 'X-App-Attest-Key-Id': 'k', 'X-App-Attest': 'a' },
      body: form,
    });
  };
  const sub = (extra = {}) =>
    jws({ productId: PREMIUM, originalTransactionId: 's1', environment: 'Production', expiresDate: T0 + DAY, ...extra });

  it('POST /transcribe works for an active subscriber with the default chain, ignoring the model', async () => {
    const res = await handleRequest(transcribeRequest(sub()), h.env(), h.deps());
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { text: 'hello world' });
    assert.equal(h.transcribeCalls[0].opts.language, 'es');
    assert.equal(h.transcribeCalls[0].opts.model, undefined);
    assert.deepEqual(h.rows('SELECT user_id, seconds FROM usage').map((r) => ({ ...r })), [{ user_id: 'sub:s1', seconds: 12 }]);
  });

  it('refuses an expired subscription, a forged one, and no attestation', async () => {
    assert.equal((await handleRequest(transcribeRequest(sub({ expiresDate: T0 - DAY })), h.env(), h.deps())).status, 403);
    assert.equal((await handleRequest(transcribeRequest('forged'), h.env(), h.deps())).status, 403);
    h.attestOK = false;
    assert.equal((await handleRequest(transcribeRequest(sub()), h.env(), h.deps())).status, 403);
    assert.equal(h.transcribeCalls.length, 0);
  });

  it('never caps a subscription: past 100 hours it alerts once and keeps transcribing', async () => {
    h.db.sqlite.exec(`INSERT INTO usage (user_id, month, seconds) VALUES ('sub:s1', '2026-11', ${100 * 3600 - 5})`);
    for (let i = 0; i < 2; i++) {
      assert.equal((await handleRequest(transcribeRequest(sub()), h.env(), h.deps())).status, 200);
    }
    assert.equal(h.alerts.filter((a) => a.includes('sub:s1 passed 100 hours')).length, 1);
  });

  it('refuses a suspended subscription with 403 suspended', async () => {
    h.db.sqlite.exec(
      `INSERT INTO purchases (id, kind, environment, created_at, suspended) VALUES ('sub:s1', 'suspended', 'Production', 0, 1)`,
    );
    const res = await handleRequest(transcribeRequest(sub()), h.env(), h.deps());
    assert.equal(res.status, 403);
    assert.equal((await res.json()).reason, 'suspended');
    assert.equal(h.transcribeCalls.length, 0);
    const other = await handleRequest(transcribeRequest(sub({ originalTransactionId: 's2' })), h.env(), h.deps());
    assert.equal(other.status, 200);
  });

  it('text POST /inbox queues for agents until 2027-01-07, then both paths answer 410', async () => {
    assert.equal(LEGACY_RETIRES_AT, Date.UTC(2027, 0, 7));
    const secret = await h.inbox();
    const agent = await h.connect(secret);
    const item = { recording_id: noteId(1), created_at: '2026-11-01T11:59:00Z', duration: 3, transcription: 'on device' };
    assert.deepEqual((await h.call('POST', '/inbox', { auth: secret, body: item })).body, { queued: 1 });
    assert.equal((await h.call('GET', '/inbox', { auth: agent })).body.items[0].transcription, 'on device');

    h.now = LEGACY_RETIRES_AT;
    const gone = await h.call('POST', '/inbox', { auth: secret, body: { ...item, recording_id: noteId(2) } });
    assert.equal(gone.status, 410);
    assert.equal(gone.body.error, 'This version of Ramble is out of date. Update Ramble from the App Store.');
    const t = await handleRequest(transcribeRequest(sub()), h.env(), h.deps());
    assert.equal(t.status, 410);
    assert.equal(h.transcribeCalls.length, 0);
    assert.equal(h.rows('SELECT COUNT(*) AS n FROM entries')[0].n, 1);
  });

  it('GET /analytics is gone', async () => {
    assert.equal((await h.call('GET', '/analytics?token=x')).status, 410);
  });
});

describe('operator', () => {
  const err = (outcome, status) =>
    Object.assign(new Error('groq trouble'), { retryable: true, provider: 'groq', status, attempts: [{ provider: 'groq', outcome, status }] });

  it('alerts when Groq rejects the key or it is missing, with cooldown; a 429 alone alerts nothing', async () => {
    const secret = await h.inbox();
    h.transcribe = async () => {
      throw err('rate_limited', 429);
    };
    await h.upload(secret, noteId(1));
    assert.equal(h.alerts.length, 0);
    h.transcribe = async () => {
      throw err('key_rejected', 401);
    };
    await h.upload(secret, noteId(2));
    h.transcribe = async () => {
      throw err('key_missing', null);
    };
    await h.upload(secret, noteId(3));
    const keyAlerts = () => h.alerts.filter((a) => a.includes("groq rejected Ramble's API key, or the key is missing")).length;
    assert.equal(keyAlerts(), 1);
    // Retries keep failing the same way for the next hour: no repeat alerts.
    h.now += HOUR;
    await h.cron();
    assert.equal(keyAlerts(), 1);
  });

  it('alerts on a permanent failure, once per 6 hours per result', async () => {
    const secret = await h.inbox();
    h.rejectAudio();
    await h.upload(secret, noteId(1));
    await h.upload(secret, noteId(2));
    const failed = h.alerts.filter((a) => a.includes('failed permanently (audio_rejected)'));
    assert.equal(failed.length, 1);
    assert.ok(!failed[0].includes(secret));
  });

  it('sends nothing without an alert webhook', async () => {
    h.envExtra = { ALERT_WEBHOOK_URL: undefined };
    const secret = await h.inbox();
    const [{ id }] = h.rows('SELECT id FROM inboxes');
    h.db.sqlite.exec(`INSERT INTO usage (user_id, month, seconds) VALUES ('${id}', '2026-11', ${100 * 3600 - 1})`);
    await h.upload(secret, noteId(1));
    await h.cron();
    assert.equal(h.alerts.length, 0);
  });
});

describe('audio retention', () => {
  it('deletes any stored audio a day after it was stored, even if a delete failed', async () => {
    const secret = await h.inbox();
    h.transcribe = () => new Promise(() => {});
    await h.upload(secret, noteId(1));
    assert.equal(h.bucket.objects.size, 1);
    h.transcribe = async () => {
      throw new Error('still failing');
    };
    h.now = T0 + DAY;
    await h.cron();
    assert.equal(h.bucket.objects.size, 0);
  });
});
