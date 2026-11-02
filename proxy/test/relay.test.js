// End-to-end tests for the relay's HTTP surface, run against real SQLite via
// the D1 stand-in. App Attest is stubbed (it needs a real device); everything
// else — pairing, fan-out, pull, ack, expiry, revoke — runs for real.

import assert from 'node:assert/strict';
import { beforeEach, describe, it } from 'node:test';

import {
  AGENT_TYPES,
  DEFAULT_RECEIPT_RETENTION_SECONDS,
  DEFAULT_UNACKED_RETENTION_SECONDS,
  MAX_CONNECTIONS_PER_INBOX,
  PAIR_CODE_ALPHABET,
  PAIR_CODE_TTL_SECONDS,
  generatePairCode,
  handleRelayRequest,
  isRelayPath,
  normalizePairCode,
  purgeExpired,
  retention,
  validateUpload,
} from '../src/relay.js';
import { createTestDB } from './d1.js';

const T0 = Date.UTC(2026, 10, 1, 12, 0, 0);
const HOUR = 3600 * 1000;

let db;
let env;
let now;
let attestOK;

beforeEach(() => {
  db = createTestDB();
  env = { DB: db };
  now = T0;
  attestOK = true;
});

async function call(method, path, { body, auth, attest = true, headers = {} } = {}) {
  const h = new Headers(headers);
  if (auth) h.set('Authorization', `Bearer ${auth}`);
  if (attest) {
    h.set('X-App-Attest-Key-Id', 'key-1');
    h.set('X-App-Attest', 'assertion');
  }
  if (body !== undefined) h.set('Content-Type', 'application/json');
  const request = new Request(`https://relay.test${path}`, {
    method,
    headers: h,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const res = await handleRelayRequest(request, env, {
    now,
    verifyAssertion: async () => (attestOK ? { valid: true } : { valid: false, reason: 'stub' }),
  });
  return { status: res.status, body: await res.json() };
}

async function newInbox() {
  const res = await call('POST', '/inboxes');
  assert.equal(res.status, 201);
  return res.body.inbox_secret;
}

async function connect(secret, agentType = 'muse') {
  const code = await call('POST', '/pair/code', { auth: secret, attest: false, body: { agent_type: agentType } });
  assert.equal(code.status, 201);
  const ex = await call('POST', '/pair/exchange', { attest: false, body: { code: code.body.code } });
  assert.equal(ex.status, 201);
  return ex.body;
}

function recording(n, text = `thought ${n}`) {
  return {
    recording_id: `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`,
    created_at: '2026-11-01T11:59:00Z',
    duration: 12.5,
    transcription: text,
  };
}

const upload = (secret, rec) => call('POST', '/inbox', { auth: secret, body: rec });
const pull = (token, query = '') => call('GET', `/inbox${query}`, { auth: token, attest: false });
const ack = (token, ids) => call('POST', '/inbox/ack', { auth: token, attest: false, body: { ids } });

describe('inbox creation', () => {
  it('requires App Attest', async () => {
    attestOK = false;
    assert.equal((await call('POST', '/inboxes')).status, 403);
    assert.equal((await call('POST', '/inboxes', { attest: false })).status, 403);
  });

  it('accepts the dev bypass token only when configured and matching', async () => {
    const bypass = { attest: false, headers: { 'X-Dev-Bypass': 'letmein' } };
    assert.equal((await call('POST', '/inboxes', bypass)).status, 403);
    env.DEV_BYPASS_TOKEN = 'letmein';
    assert.equal((await call('POST', '/inboxes', bypass)).status, 201);
    assert.equal(
      (await call('POST', '/inboxes', { attest: false, headers: { 'X-Dev-Bypass': 'nope' } })).status,
      403,
    );
  });

  it('stores only a hash of the secret', async () => {
    const secret = await newInbox();
    assert.match(secret, /^rmbi_/);
    const row = db.sqlite.prepare('SELECT * FROM inboxes').get();
    assert.notEqual(row.secret_hash, secret);
    assert.ok(!JSON.stringify(row).includes(secret));
  });
});

describe('pairing', () => {
  it('exchanges a code for a scoped token, once', async () => {
    const secret = await newInbox();
    const code = (await call('POST', '/pair/code', { auth: secret, attest: false, body: { agent_type: 'muse' } })).body;
    assert.match(code.code, /^[2-9A-Z]{4}-[2-9A-Z]{4}$/);
    assert.equal(code.expires_at, new Date(T0 + PAIR_CODE_TTL_SECONDS * 1000).toISOString());

    const first = await call('POST', '/pair/exchange', { attest: false, body: { code: code.code } });
    assert.equal(first.status, 201);
    assert.match(first.body.token, /^rmba_/);
    assert.equal(first.body.agent_type, 'muse');
    assert.equal(first.body.unacked_retention_seconds, DEFAULT_UNACKED_RETENTION_SECONDS);

    const second = await call('POST', '/pair/exchange', { attest: false, body: { code: code.code } });
    assert.equal(second.status, 400);
  });

  it('accepts codes pasted with odd spacing and case', async () => {
    const secret = await newInbox();
    const { code } = (await call('POST', '/pair/code', { auth: secret, attest: false, body: {} })).body;
    const messy = ` ${code.toLowerCase().replace('-', ' - ')} `;
    const res = await call('POST', '/pair/exchange', { attest: false, body: { code: messy } });
    assert.equal(res.status, 201);
    assert.equal(res.body.agent_type, 'other');
  });

  it('rejects expired codes', async () => {
    const secret = await newInbox();
    const { code } = (await call('POST', '/pair/code', { auth: secret, attest: false, body: {} })).body;
    now = T0 + PAIR_CODE_TTL_SECONDS * 1000;
    assert.equal((await call('POST', '/pair/exchange', { attest: false, body: { code } })).status, 400);
  });

  it('cancels the previous code when a new one is issued', async () => {
    const secret = await newInbox();
    const a = (await call('POST', '/pair/code', { auth: secret, attest: false, body: {} })).body.code;
    const b = (await call('POST', '/pair/code', { auth: secret, attest: false, body: {} })).body.code;
    assert.equal((await call('POST', '/pair/exchange', { attest: false, body: { code: a } })).status, 400);
    assert.equal((await call('POST', '/pair/exchange', { attest: false, body: { code: b } })).status, 201);
  });

  it('rejects unknown agent types and missing credentials', async () => {
    const secret = await newInbox();
    assert.equal((await call('POST', '/pair/code', { auth: secret, attest: false, body: { agent_type: 'siri' } })).status, 400);
    assert.equal((await call('POST', '/pair/code', { attest: false, body: {} })).status, 401);
  });

  it('caps connections per inbox', async () => {
    const secret = await newInbox();
    for (let i = 0; i < MAX_CONNECTIONS_PER_INBOX; i++) await connect(secret);
    assert.equal((await call('POST', '/pair/code', { auth: secret, attest: false, body: {} })).status, 409);
  });
});

describe('upload, pull, ack', () => {
  it('runs the whole loop and leaves nothing behind', async () => {
    const secret = await newInbox();
    const { token } = await connect(secret);

    const up = await upload(secret, recording(1, 'Buy oat milk and call the plumber.'));
    assert.equal(up.status, 200);
    assert.equal(up.body.queued, 1);

    const got = await pull(token);
    assert.equal(got.status, 200);
    assert.equal(got.body.items.length, 1);
    const item = got.body.items[0];
    assert.equal(item.transcription, 'Buy oat milk and call the plumber.');
    assert.equal(item.recording_id, recording(1).recording_id);
    assert.equal(item.created_at, '2026-11-01T11:59:00Z');
    assert.equal(item.duration, 12.5);
    assert.equal(item.expires_at, new Date(T0 + DEFAULT_UNACKED_RETENTION_SECONDS * 1000).toISOString());
    assert.equal(got.body.next_since, item.id);
    assert.equal(got.body.has_more, false);

    assert.deepEqual((await ack(token, [item.id])).body, { acknowledged: 1 });
    assert.equal((await pull(token)).body.items.length, 0);

    // The text is gone at ack; only a text-free receipt remains, briefly.
    assert.equal(db.sqlite.prepare("SELECT COUNT(*) AS n FROM entries WHERE text != ''").get().n, 0);
    now = T0 + DEFAULT_RECEIPT_RETENTION_SECONDS * 1000;
    await purgeExpired(db, now);
    assert.equal(db.sqlite.prepare('SELECT COUNT(*) AS n FROM entries').get().n, 0);
  });

  it('needs only the inbox secret to upload, so attestation never blocks delivery', async () => {
    const secret = await newInbox();
    const { token } = await connect(secret);
    attestOK = false;
    const res = await call('POST', '/inbox', { auth: secret, attest: false, body: recording(1) });
    assert.equal(res.status, 200);
    assert.equal((await pull(token)).body.items.length, 1);
    assert.equal((await upload(undefined, recording(1))).status, 401);
    assert.equal((await upload('rmbi_wrong', recording(1))).status, 401);
  });

  it('queues nothing when no agent is connected', async () => {
    const secret = await newInbox();
    assert.equal((await upload(secret, recording(1))).body.queued, 0);
    assert.equal(db.sqlite.prepare('SELECT COUNT(*) AS n FROM entries').get().n, 0);
  });

  it('is idempotent on recording_id so app retries do not duplicate', async () => {
    const secret = await newInbox();
    const { token } = await connect(secret);
    await upload(secret, recording(1));
    await upload(secret, recording(1));
    assert.equal((await pull(token)).body.items.length, 1);
  });

  it('gives each agent its own copy, acked independently', async () => {
    const secret = await newInbox();
    const muse = await connect(secret, 'muse');
    const gpt = await connect(secret, 'chatgpt');
    assert.equal((await upload(secret, recording(1))).body.queued, 2);

    const museItems = (await pull(muse.token)).body.items;
    await ack(muse.token, museItems.map((i) => i.id));
    assert.equal((await pull(muse.token)).body.items.length, 0);
    assert.equal((await pull(gpt.token)).body.items.length, 1);
  });

  it('pages with since/limit, oldest first', async () => {
    const secret = await newInbox();
    const { token } = await connect(secret);
    for (let i = 1; i <= 5; i++) await upload(secret, recording(i));

    const p1 = (await pull(token, '?limit=2')).body;
    assert.deepEqual(p1.items.map((i) => i.transcription), ['thought 1', 'thought 2']);
    assert.equal(p1.has_more, true);
    const p2 = (await pull(token, `?limit=2&since=${p1.next_since}`)).body;
    assert.deepEqual(p2.items.map((i) => i.transcription), ['thought 3', 'thought 4']);
    const p3 = (await pull(token, `?limit=2&since=${p2.next_since}`)).body;
    assert.deepEqual(p3.items.map((i) => i.transcription), ['thought 5']);
    assert.equal(p3.has_more, false);
    // Without acks, a fresh pull starts over.
    assert.equal((await pull(token)).body.items.length, 5);
  });

  it("cannot ack another agent's entries", async () => {
    const secret = await newInbox();
    const a = await connect(secret);
    const b = await connect(secret);
    await upload(secret, recording(1));
    const bItem = (await pull(b.token)).body.items[0];
    assert.deepEqual((await ack(a.token, [bItem.id])).body, { acknowledged: 0 });
    assert.equal((await pull(b.token)).body.items.length, 1);
  });

  it("cannot read another inbox's transcripts", async () => {
    const mine = await newInbox();
    const theirs = await newInbox();
    const myAgent = await connect(mine);
    await connect(theirs);
    await upload(theirs, recording(1, 'not yours'));
    assert.equal((await pull(myAgent.token)).body.items.length, 0);
  });

  it('rejects inbox secrets on agent routes and agent tokens on app routes', async () => {
    const secret = await newInbox();
    const { token } = await connect(secret);
    assert.equal((await pull(secret)).status, 401);
    assert.equal((await upload(token, recording(1))).status, 401);
  });

  it('validates ack bodies', async () => {
    const secret = await newInbox();
    const { token } = await connect(secret);
    assert.equal((await ack(token, [])).status, 400);
    assert.equal((await ack(token, ['1'])).status, 400);
    assert.equal((await ack(token, Array.from({ length: 501 }, (_, i) => i + 1))).status, 400);
  });

  it('records when the agent last pulled', async () => {
    const secret = await newInbox();
    const { token } = await connect(secret);
    let conns = (await call('GET', '/connections', { auth: secret, attest: false })).body.connections;
    assert.equal(conns[0].last_pull_at, null);
    now = T0 + HOUR;
    await upload(secret, recording(1));
    await pull(token);
    conns = (await call('GET', '/connections', { auth: secret, attest: false })).body.connections;
    assert.equal(conns[0].last_pull_at, new Date(T0 + HOUR).toISOString());
    assert.equal(conns[0].pending, 1);
    assert.equal(conns[0].agent_type, 'muse');
  });
});

describe('expiry', () => {
  it('hides expired entries immediately, and the cron deletes them', async () => {
    const secret = await newInbox();
    const { token } = await connect(secret);
    await upload(secret, recording(1));

    now = T0 + DEFAULT_UNACKED_RETENTION_SECONDS * 1000 - 1;
    assert.equal((await pull(token)).body.items.length, 1);
    now = T0 + DEFAULT_UNACKED_RETENTION_SECONDS * 1000;
    assert.equal((await pull(token)).body.items.length, 0);

    // Still on disk until the scheduled purge runs.
    assert.equal(db.sqlite.prepare('SELECT COUNT(*) AS n FROM entries').get().n, 1);
    const purged = await purgeExpired(db, now);
    assert.equal(purged.entries, 1);
    assert.equal(db.sqlite.prepare('SELECT COUNT(*) AS n FROM entries').get().n, 0);
  });

  it('purges expired pairing codes', async () => {
    const secret = await newInbox();
    await call('POST', '/pair/code', { auth: secret, attest: false, body: {} });
    assert.equal((await purgeExpired(db, T0)).pairCodes, 0);
    assert.equal((await purgeExpired(db, T0 + PAIR_CODE_TTL_SECONDS * 1000)).pairCodes, 1);
  });

  it('keeps unacked transcripts 30 days by default, through an agent outage', async () => {
    const secret = await newInbox();
    const { token } = await connect(secret);
    await upload(secret, recording(1));
    now = T0 + 29 * 24 * HOUR;
    assert.equal((await pull(token)).body.items.length, 1);
  });

  it('deletes text at ack and re-acking is a no-op', async () => {
    const secret = await newInbox();
    const { token } = await connect(secret);
    await upload(secret, recording(1));
    await upload(secret, recording(2));
    const [first] = (await pull(token)).body.items;
    await ack(token, [first.id]);
    assert.deepEqual((await pull(token)).body.items.map((i) => i.transcription), ['thought 2']);
    const row = db.sqlite.prepare('SELECT text, acked_at FROM entries WHERE id = ?').get(first.id);
    assert.equal(row.text, '');
    assert.equal(row.acked_at, T0);
    assert.deepEqual((await ack(token, [first.id])).body, { acknowledged: 0 });
  });

  it('never lengthens retention when acking near expiry', async () => {
    const secret = await newInbox();
    const { token } = await connect(secret);
    await upload(secret, recording(1));
    const [item] = (await pull(token)).body.items;
    now = T0 + DEFAULT_UNACKED_RETENTION_SECONDS * 1000 - HOUR;
    await ack(token, [item.id]);
    const row = db.sqlite.prepare('SELECT expires_at FROM entries WHERE id = ?').get(item.id);
    assert.equal(row.expires_at, T0 + DEFAULT_UNACKED_RETENTION_SECONDS * 1000);
  });

  it('gives the phone pickup receipts without text', async () => {
    const secret = await newInbox();
    const { token } = await connect(secret, 'muse');
    await upload(secret, recording(1));
    await upload(secret, recording(2));
    const [first] = (await pull(token)).body.items;
    now = T0 + HOUR;
    await ack(token, [first.id]);

    const res = await call('GET', '/receipts', { auth: secret, attest: false });
    assert.equal(res.status, 200);
    assert.equal(res.body.receipts.length, 1);
    assert.equal(res.body.receipts[0].recording_id, recording(1).recording_id);
    assert.equal(res.body.receipts[0].agent_type, 'muse');
    assert.equal(res.body.receipts[0].picked_up_at, new Date(T0 + HOUR).toISOString());
    assert.ok(!JSON.stringify(res.body).includes('thought'));
    assert.equal((await call('GET', '/receipts', { auth: token, attest: false })).status, 401);

    const conns = (await call('GET', '/connections', { auth: secret, attest: false })).body.connections;
    assert.equal(conns[0].pending, 1);
  });

  it('honors configured retention windows', async () => {
    env.UNACKED_RETENTION_SECONDS = '3600';
    const secret = await newInbox();
    const { token } = await connect(secret);
    await upload(secret, recording(1));
    now = T0 + HOUR;
    assert.equal((await pull(token)).body.items.length, 0);
  });
});

describe('revoke and purge', () => {
  it('Disconnect kills the token and deletes its queue', async () => {
    const secret = await newInbox();
    const { token, connection_id: id } = await connect(secret);
    await upload(secret, recording(1));

    const res = await call('DELETE', `/connections/${id}`, { auth: secret, attest: false });
    assert.equal(res.status, 200);
    assert.equal((await pull(token)).status, 401);
    assert.equal(db.sqlite.prepare('SELECT COUNT(*) AS n FROM entries').get().n, 0);
    assert.equal((await call('DELETE', `/connections/${id}`, { auth: secret, attest: false })).status, 404);
  });

  it("cannot revoke another inbox's connection", async () => {
    const mine = await newInbox();
    const theirs = await newInbox();
    const theirAgent = await connect(theirs);
    const res = await call('DELETE', `/connections/${theirAgent.connection_id}`, { auth: mine, attest: false });
    assert.equal(res.status, 404);
    assert.equal((await pull(theirAgent.token)).status, 200);
  });

  it('Delete everything now empties every queue but keeps connections', async () => {
    const secret = await newInbox();
    const a = await connect(secret);
    const b = await connect(secret);
    await upload(secret, recording(1));
    await upload(secret, recording(2));

    const res = await call('DELETE', '/inbox', { auth: secret, attest: false });
    assert.deepEqual(res.body, { deleted: 4 });
    assert.equal((await pull(a.token)).body.items.length, 0);
    assert.equal((await pull(b.token)).status, 200);
  });

  it('can purge a single connection', async () => {
    const secret = await newInbox();
    const a = await connect(secret);
    const b = await connect(secret);
    await upload(secret, recording(1));
    const res = await call('DELETE', `/inbox?connection_id=${a.connection_id}`, { auth: secret, attest: false });
    assert.deepEqual(res.body, { deleted: 1 });
    assert.equal((await pull(b.token)).body.items.length, 1);
  });

  it('works without attestation, so the kill switch always works', async () => {
    attestOK = false;
    env.DEV_BYPASS_TOKEN = 'x';
    const secret = (await call('POST', '/inboxes', { attest: false, headers: { 'X-Dev-Bypass': 'x' } })).body.inbox_secret;
    assert.equal((await call('DELETE', '/inbox', { auth: secret, attest: false })).status, 200);
  });
});

describe('helpers', () => {
  it('generates readable codes from the unambiguous alphabet', () => {
    for (let i = 0; i < 200; i++) {
      const code = generatePairCode();
      assert.match(code, /^.{4}-.{4}$/);
      for (const ch of code.replace('-', '')) assert.ok(PAIR_CODE_ALPHABET.includes(ch), ch);
    }
  });

  it('normalizes pasted codes', () => {
    assert.equal(normalizePairCode(' abcd - efgh\n'), 'ABCDEFGH');
  });

  it('validates uploads', () => {
    assert.ok(!validateUpload(recording(1)).error);
    assert.ok(validateUpload({ ...recording(1), transcription: '   ' }).error);
    assert.ok(validateUpload({ ...recording(1), duration: -1 }).error);
    assert.ok(validateUpload({ ...recording(1), created_at: 'yesterday' }).error);
    assert.ok(validateUpload({ ...recording(1), recording_id: 'x/../y' }).error);
    assert.ok(validateUpload({ ...recording(1), transcription: 'a'.repeat(200_001) }).error);
  });

  it('falls back to the default retention for bad config', () => {
    assert.deepEqual(retention({}), {
      unacked: DEFAULT_UNACKED_RETENTION_SECONDS,
      receipt: DEFAULT_RECEIPT_RETENTION_SECONDS,
    });
    assert.equal(retention({ UNACKED_RETENTION_SECONDS: 'soon' }).unacked, DEFAULT_UNACKED_RETENTION_SECONDS);
    assert.equal(retention({ UNACKED_RETENTION_SECONDS: '5184000' }).unacked, 5184000);
    assert.equal(retention({ RECEIPT_RETENTION_SECONDS: '3600' }).receipt, 3600);
  });

  it('lists the agents the app offers', () => {
    assert.deepEqual(AGENT_TYPES, ['muse', 'chatgpt', 'grok', 'claude', 'other']);
  });
});

describe('routing', () => {
  it('claims only relay paths', () => {
    for (const p of ['/inboxes', '/inbox', '/inbox/ack', '/pair/code', '/pair/exchange', '/connections', '/connections/con_abc', '/receipts']) {
      assert.ok(isRelayPath(p), p);
    }
    for (const p of ['/transcribe', '/health', '/attest', '/attest/challenge', '/analytics', '/inbox/x/y']) {
      assert.ok(!isRelayPath(p), p);
    }
  });

  it('404s unknown methods on relay paths', async () => {
    assert.equal((await call('PUT', '/inbox', { attest: false })).status, 404);
  });

  it('answers 503 until the D1 binding exists', async () => {
    env = {};
    assert.equal((await call('GET', '/inbox', { attest: false })).status, 503);
  });
});
