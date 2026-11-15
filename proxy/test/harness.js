// Shared test harness: the real router and schema (node:sqlite standing in
// for D1), with fakes for R2, the rate limiter, App Attest, Apple's signed
// records, the transcriber and outbound fetch.

import assert from 'node:assert/strict';

import { AppleVerifyError } from '../src/apple.js';
import { handleRequest, runScheduled } from '../src/index.js';
import { TranscribeError } from '../src/transcribe.js';
import { createTestDB } from './d1.js';

export const T0 = Date.UTC(2026, 10, 1, 12, 0, 0);
export const MINUTE = 60 * 1000;
export const HOUR = 60 * MINUTE;
export const DAY = 24 * HOUR;

export function createBucket() {
  const objects = new Map();
  return {
    objects,
    failPut: false,
    async put(key, body) {
      if (this.failPut) throw new Error('R2 down');
      objects.set(key, new Uint8Array(body));
    },
    async get(key) {
      const bytes = objects.get(key);
      return bytes ? { arrayBuffer: async () => bytes.buffer.slice(0) } : null;
    },
    async delete(key) {
      objects.delete(key);
    },
  };
}

/** Fixed-window counters in memory, same contract as ratelimit.js. */
export function createLimiter() {
  const counts = new Map();
  const bucket = (key, windowSeconds, now) => `${key}|${Math.floor(now / (windowSeconds * 1000))}`;
  return {
    counts,
    down: false,
    async hit(_db, key, limit, windowSeconds, now) {
      if (this.down) throw new Error('limiter down');
      const k = bucket(key, windowSeconds, now);
      const n = (counts.get(k) ?? 0) + 1;
      counts.set(k, n);
      return n <= limit ? { ok: true } : { ok: false, retryAfter: 30 };
    },
    async peek(_db, key, limit, windowSeconds, now) {
      if (this.down) throw new Error('limiter down');
      return (counts.get(bucket(key, windowSeconds, now)) ?? 0) < limit ? { ok: true } : { ok: false, retryAfter: 30 };
    },
  };
}

/** A fake signed record: "jws:<json payload>". "forged" fails verification. */
export const jws = (payload) => `jws:${JSON.stringify(payload)}`;
function decode(record) {
  if (typeof record !== 'string' || !record.startsWith('jws:')) throw new AppleVerifyError('Not signed by Apple');
  return JSON.parse(record.slice(4));
}

export const UNLOCK = 'dev.goodloop.ramble.unlock';
export const PREMIUM = 'dev.goodloop.ramble.premium.monthly2';

export function unlockTx(extra = {}) {
  return jws({
    productId: UNLOCK,
    transactionId: 't1',
    originalTransactionId: 'otx1',
    environment: 'Production',
    inAppOwnershipType: 'PURCHASED',
    ...extra,
  });
}

export function createHarness() {
  const h = {
    db: createTestDB(),
    bucket: createBucket(),
    limiter: createLimiter(),
    now: T0,
    attestOK: true,
    background: [],
    fetches: [],
    alerts: [],
    pingStatus: 200,
    // Transcriber behavior for the next attempts: a function of the call.
    transcribe: async () => ({ result: 'transcript', text: 'hello world', provider: 'groq', model: 'whisper-large-v3-turbo', durationSeconds: 12 }),
    transcribeCalls: [],
    measured: 12,
    envExtra: {},
  };
  h.env = () => ({ DB: h.db, AUDIO: h.bucket, HOOK_ENCRYPTION_KEY: 'k', TELEGRAM_BOT_TOKEN: 't', TELEGRAM_CHAT_ID: '1', ...h.envExtra });

  h.deps = (extra = {}) => ({
    now: h.now,
    clock: () => h.now,
    verifyAssertion: async () => ({ valid: h.attestOK, reason: 'stub' }),
    handleAttest: async () => ({ status: 'ok' }),
    fetch: async (url, init) => {
      if (url === 'https://api.telegram.org/bott/sendMessage') {
        h.alerts.push(JSON.parse(init.body).text);
        return new Response('ok');
      }
      h.fetches.push({ url, headers: init.headers, body: JSON.parse(init.body) });
      if (h.pingStatus === 0) throw new Error('network down');
      return new Response(null, { status: h.pingStatus });
    },
    waitUntil: (p) => h.background.push(p),
    rateLimit: h.limiter,
    clientAddress: () => '203.0.113.9',
    apple: {
      verifySignedTransaction: async (r) => decode(r),
      verifyAppTransaction: async (r) => decode(r),
    },
    transcribe: async (audio, opts, _env, transcribeDeps) => {
      h.transcribeCalls.push({ bytes: audio.byteLength, opts, deps: transcribeDeps });
      return h.transcribe(audio, opts);
    },
    measureDuration: () => h.measured,
    inlineWaitMs: 50,
    ...extra,
  });

  h.call = async (method, path, { body, raw, auth, headers = {}, deps } = {}) => {
    const hdrs = new Headers({ 'X-App-Attest-Key-Id': 'key', 'X-App-Attest': 'assertion', ...headers });
    if (auth) hdrs.set('Authorization', `Bearer ${auth}`);
    const res = await handleRequest(
      new Request(`https://relay.test${path}`, {
        method,
        headers: hdrs,
        body: raw !== undefined ? raw : body === undefined ? undefined : JSON.stringify(body),
      }),
      h.env(),
      h.deps(deps),
    );
    const text = await res.text();
    return { status: res.status, body: text ? JSON.parse(text) : null, headers: res.headers };
  };

  // Work handed to waitUntil. An attempt that never ends (a "dead worker")
  // is dropped after a moment instead of hanging the test.
  h.settle = async () => {
    while (h.background.length) {
      await Promise.race([Promise.all(h.background.splice(0)), new Promise((r) => setTimeout(r, 100))]);
    }
  };
  h.cron = async () => {
    await runScheduled(h.env(), h.deps());
    await h.settle();
  };

  let keys = 0;
  h.newInbox = async (body) => {
    const res = await h.call('POST', '/inboxes', { body, headers: { 'X-App-Attest-Key-Id': `key-${++keys}` } });
    assert.equal(res.status, 201, JSON.stringify(res.body));
    return res.body;
  };
  h.inbox = async () => (await h.newInbox()).inbox_secret;
  h.newInboxWithKey = h.inbox;

  h.watchToken = async (secret, replaces) => {
    const res = await h.call('POST', '/watch-token', { auth: secret, body: replaces ? { replaces } : {} });
    assert.equal(res.status, 201);
    return res.body.watch_token;
  };

  h.connect = async (secret, name) => {
    const { code } = (await h.call('POST', '/pair/code', { auth: secret })).body;
    const res = await h.call('POST', '/pair/exchange', { body: { code, name } });
    assert.equal(res.status, 201, JSON.stringify(res.body));
    return res.body.token;
  };

  h.upload = (auth, id, { bytes = 1000, type = 'audio/mp4', recordedAt = '2026-11-01T06:59:00-05:00', headers = {} } = {}) =>
    h.call('PUT', `/notes/${id}`, {
      auth,
      raw: new Uint8Array(bytes),
      headers: {
        'Content-Type': type,
        'Content-Length': String(bytes),
        'X-Ramble-Recorded-At': recordedAt,
        ...headers,
      },
    });

  h.rejectAudio = () => {
    h.transcribe = async () => {
      throw new TranscribeError('Groq 400: could not decode', { retryable: false, provider: 'groq', status: 400 });
    };
  };
  h.providersDown = () => {
    h.transcribe = async () => {
      throw new TranscribeError('groq down', { retryable: true, provider: 'groq', status: 503 });
    };
  };

  h.rows = (sql, ...params) => h.db.sqlite.prepare(sql).all(...params);
  return h;
}

export const noteId = (n) => `6F1C0000-0000-4000-8000-${String(n).padStart(12, '0')}`;
