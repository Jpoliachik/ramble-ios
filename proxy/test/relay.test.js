// Relay endpoint tests against the real schema (node:sqlite standing in for
// D1). App Attest is stubbed because it needs a real device.

import assert from 'node:assert/strict';
import { beforeEach, describe, it } from 'node:test';

import {
  DEFAULT_RETENTION_SECONDS,
  PAIR_CODE_ALPHABET,
  PAIR_CODE_TTL_SECONDS,
  PULL_LIMIT,
  generatePairCode,
  handleRelayRequest,
  isRelayPath,
  normalizePairCode,
  purgeExpired,
  retentionSeconds,
  validateUpload,
} from '../src/relay.js';
import { createTestDB } from './d1.js';

const T0 = Date.UTC(2026, 10, 1, 12, 0, 0);
const DAY = 24 * 3600 * 1000;

let db, env, now, attestOK;

beforeEach(() => {
  db = createTestDB();
  env = { DB: db };
  now = T0;
  attestOK = true;
});

async function call(method, path, { body, auth, headers = {} } = {}) {
  const h = new Headers({ 'X-App-Attest-Key-Id': 'key', 'X-App-Attest': 'assertion', ...headers });
  if (auth) h.set('Authorization', `Bearer ${auth}`);
  const res = await handleRelayRequest(
    new Request(`https://relay.test${path}`, {
      method,
      headers: h,
      body: body === undefined ? undefined : JSON.stringify(body),
    }),
    env,
    { now, verifyAssertion: async () => ({ valid: attestOK, reason: 'stub' }) },
  );
  return { status: res.status, body: await res.json() };
}

const rows = (table) => db.sqlite.prepare(`SELECT COUNT(*) AS n FROM ${table}`).get().n;

async function newInbox() {
  const res = await call('POST', '/inboxes');
  assert.equal(res.status, 201);
  return res.body.inbox_secret;
}

async function connect(secret) {
  const { code } = (await call('POST', '/pair/code', { auth: secret })).body;
  const res = await call('POST', '/pair/exchange', { body: { code } });
  assert.equal(res.status, 201);
  return res.body.token;
}

function recording(n) {
  return {
    recording_id: `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`,
    created_at: '2026-11-01T11:59:00Z',
    duration: 12.5,
    transcription: `thought ${n}`,
  };
}

const upload = (secret, n) => call('POST', '/inbox', { auth: secret, body: recording(n) });
const pull = async (token) => (await call('GET', '/inbox', { auth: token })).body;
const ack = (token, ids) => call('POST', '/inbox/ack', { auth: token, body: { ids } });
const connections = async (secret) => (await call('GET', '/connections', { auth: secret })).body.connections;

describe('the whole loop', () => {
  it('pairs, uploads, pulls, acks, and leaves nothing behind', async () => {
    const secret = await newInbox();
    const token = await connect(secret);

    assert.deepEqual((await upload(secret, 1)).body, { queued: 1 });
    const { items, has_more } = await pull(token);
    assert.equal(has_more, false);
    assert.deepEqual(items, [{ id: items[0].id, ...recording(1) }]);

    assert.deepEqual((await ack(token, [items[0].id])).body, { deleted: 1 });
    assert.equal((await pull(token)).items.length, 0);
    assert.equal(rows('entries'), 0);
  });

  it('stores credentials only as hashes', async () => {
    const secret = await newInbox();
    const token = await connect(secret);
    const dump = JSON.stringify([
      db.sqlite.prepare('SELECT * FROM inboxes').all(),
      db.sqlite.prepare('SELECT * FROM connections').all(),
    ]);
    assert.match(secret, /^rmbi_/);
    assert.match(token, /^rmba_/);
    assert.ok(!dump.includes(secret) && !dump.includes(token));
  });
});

describe('inbox creation', () => {
  it('requires App Attest', async () => {
    attestOK = false;
    assert.equal((await call('POST', '/inboxes')).status, 403);
  });

  it('accepts the dev bypass only when configured and matching', async () => {
    attestOK = false;
    const bypass = { headers: { 'X-Dev-Bypass': 'dev' } };
    assert.equal((await call('POST', '/inboxes', bypass)).status, 403);
    env.DEV_BYPASS_TOKEN = 'dev';
    assert.equal((await call('POST', '/inboxes', bypass)).status, 201);
    assert.equal((await call('POST', '/inboxes', { headers: { 'X-Dev-Bypass': 'nope' } })).status, 403);
  });

  it('never needs attestation after that, so delivery and kill switches keep working', async () => {
    const secret = await newInbox();
    const token = await connect(secret);
    attestOK = false;
    assert.equal((await upload(secret, 1)).status, 200);
    assert.equal((await pull(token)).items.length, 1);
    assert.equal((await call('DELETE', '/inbox', { auth: secret })).status, 200);
  });
});

describe('pairing', () => {
  it('a code makes one connection, and stops working once the agent pulls', async () => {
    const secret = await newInbox();
    const { code, expires_at } = (await call('POST', '/pair/code', { auth: secret })).body;
    assert.match(code, /^[2-9A-Z]{4}-[2-9A-Z]{4}$/);
    assert.equal(expires_at, new Date(T0 + PAIR_CODE_TTL_SECONDS * 1000).toISOString());
    const first = await call('POST', '/pair/exchange', { body: { code } });
    assert.equal(first.status, 201);
    await pull(first.body.token);
    assert.equal((await call('POST', '/pair/exchange', { body: { code } })).status, 400);
    assert.equal((await connections(secret)).length, 1);
    assert.equal(rows('pair_codes'), 0);
  });

  it('a retried exchange gets the same token when the first response was lost', async () => {
    const secret = await newInbox();
    const { code } = (await call('POST', '/pair/code', { auth: secret })).body;
    const first = await call('POST', '/pair/exchange', { body: { code } });
    now += 60_000;
    const retry = await call('POST', '/pair/exchange', { body: { code } });
    assert.equal(retry.status, 200);
    assert.equal(retry.body.token, first.body.token);
    assert.equal((await connections(secret)).length, 1);
    assert.deepEqual((await pull(retry.body.token)).items, []);
  });

  it('stops replaying the token when the code expires or the user disconnects', async () => {
    const secret = await newInbox();
    const { code } = (await call('POST', '/pair/code', { auth: secret })).body;
    await call('POST', '/pair/exchange', { body: { code } });
    now = T0 + PAIR_CODE_TTL_SECONDS * 1000;
    assert.equal((await call('POST', '/pair/exchange', { body: { code } })).status, 400);

    now = T0;
    const other = (await call('POST', '/pair/code', { auth: secret })).body.code;
    await call('POST', '/pair/exchange', { body: { code: other } });
    const [, second] = await connections(secret);
    await call('DELETE', `/connections/${second.id}`, { auth: secret });
    assert.equal((await call('POST', '/pair/exchange', { body: { code: other } })).status, 400);
  });

  it('is lenient about how the agent sends things', async () => {
    const secret = await newInbox();
    const { code } = (await call('POST', '/pair/code', { auth: secret })).body;
    const res = await handleRelayRequest(
      new Request('https://relay.test/pair/exchange', { method: 'POST', body: JSON.stringify({ code }) }),
      env,
      { now },
    );
    assert.equal(res.status, 201);
    const { token } = await res.json();
    for (const authorization of [`bearer ${token}`, token, `Bearer  ${token} `]) {
      const pulled = await call('GET', '/inbox', { headers: { Authorization: authorization } });
      assert.equal(pulled.status, 200, authorization);
    }
    const missing = await call('POST', '/pair/exchange', { body: {} });
    assert.equal(missing.status, 400);
    assert.match(missing.body.error, /"code"/);
  });

  it('accepts codes pasted with odd spacing and case', async () => {
    const secret = await newInbox();
    const { code } = (await call('POST', '/pair/code', { auth: secret })).body;
    const messy = ` ${code.toLowerCase().replace('-', ' - ')} `;
    assert.equal((await call('POST', '/pair/exchange', { body: { code: messy } })).status, 201);
  });

  it('rejects expired codes', async () => {
    const secret = await newInbox();
    const { code } = (await call('POST', '/pair/code', { auth: secret })).body;
    now = T0 + PAIR_CODE_TTL_SECONDS * 1000;
    assert.equal((await call('POST', '/pair/exchange', { body: { code } })).status, 400);
  });

  it('a new code cancels the previous one', async () => {
    const secret = await newInbox();
    const a = (await call('POST', '/pair/code', { auth: secret })).body.code;
    const b = (await call('POST', '/pair/code', { auth: secret })).body.code;
    assert.equal((await call('POST', '/pair/exchange', { body: { code: a } })).status, 400);
    assert.equal((await call('POST', '/pair/exchange', { body: { code: b } })).status, 201);
  });

  it('needs the inbox secret to issue a code', async () => {
    assert.equal((await call('POST', '/pair/code')).status, 401);
  });
});

describe('upload and pull', () => {
  it('requires the inbox secret', async () => {
    assert.equal((await call('POST', '/inbox', { body: recording(1) })).status, 401);
    assert.equal((await call('POST', '/inbox', { auth: 'rmbi_wrong', body: recording(1) })).status, 401);
  });

  it('queues nothing when no agent is connected', async () => {
    const secret = await newInbox();
    assert.deepEqual((await upload(secret, 1)).body, { queued: 0 });
    assert.equal(rows('entries'), 0);
  });

  it('is idempotent on recording_id', async () => {
    const secret = await newInbox();
    const token = await connect(secret);
    await upload(secret, 1);
    await upload(secret, 1);
    assert.equal((await pull(token)).items.length, 1);
  });

  it('gives each agent its own copy', async () => {
    const secret = await newInbox();
    const a = await connect(secret);
    const b = await connect(secret);
    assert.equal((await upload(secret, 1)).body.queued, 2);
    await ack(a, (await pull(a)).items.map((i) => i.id));
    assert.equal((await pull(a)).items.length, 0);
    assert.equal((await pull(b)).items.length, 1);
  });

  it('returns oldest first, PULL_LIMIT at a time', async () => {
    const secret = await newInbox();
    const token = await connect(secret);
    for (let i = 1; i <= PULL_LIMIT + 2; i++) await upload(secret, i);

    const first = await pull(token);
    assert.equal(first.items.length, PULL_LIMIT);
    assert.equal(first.items[0].transcription, 'thought 1');
    assert.equal(first.has_more, true);
    await ack(token, first.items.map((i) => i.id));
    const rest = await pull(token);
    assert.deepEqual(rest.items.map((i) => i.transcription), [`thought ${PULL_LIMIT + 1}`, `thought ${PULL_LIMIT + 2}`]);
    assert.equal(rest.has_more, false);
  });

  it("keeps inboxes and agents apart", async () => {
    const mine = await newInbox();
    const theirs = await newInbox();
    const myAgent = await connect(mine);
    const theirAgent = await connect(theirs);
    await upload(theirs, 1);
    assert.equal((await pull(myAgent)).items.length, 0);

    const [item] = (await pull(theirAgent)).items;
    assert.deepEqual((await ack(myAgent, [item.id])).body, { deleted: 0 });
    assert.equal((await pull(theirAgent)).items.length, 1);
  });

  it('keeps each credential on its own side', async () => {
    const secret = await newInbox();
    const token = await connect(secret);
    assert.equal((await call('GET', '/inbox', { auth: secret })).status, 401);
    assert.equal((await call('POST', '/inbox', { auth: token, body: recording(1) })).status, 401);
  });

  it('validates ack bodies', async () => {
    const token = await connect(await newInbox());
    assert.equal((await ack(token, [])).status, 400);
    assert.equal((await ack(token, ['1'])).status, 400);
    assert.equal((await ack(token, Array.from({ length: 501 }, (_, i) => i + 1))).status, 400);
  });

  it('shows the app each agent’s last check and pending count', async () => {
    const secret = await newInbox();
    const token = await connect(secret);
    assert.equal((await connections(secret))[0].last_pull_at, null);
    now = T0 + 3600_000;
    await upload(secret, 1);
    await pull(token);
    const [conn] = await connections(secret);
    assert.equal(conn.last_pull_at, new Date(now).toISOString());
    assert.equal(conn.pending, 1);
  });
});

describe('retention', () => {
  it('keeps unclaimed transcripts 30 days, then hides and purges them', async () => {
    const secret = await newInbox();
    const token = await connect(secret);
    await upload(secret, 1);

    now = T0 + DEFAULT_RETENTION_SECONDS * 1000 - 1;
    assert.equal((await pull(token)).items.length, 1);
    now = T0 + DEFAULT_RETENTION_SECONDS * 1000;
    assert.equal((await pull(token)).items.length, 0);
    assert.equal((await connections(secret))[0].pending, 0);

    assert.equal((await purgeExpired(db, now)).entries, 1);
    assert.equal(rows('entries'), 0);
  });

  it('purges expired pairing codes', async () => {
    await call('POST', '/pair/code', { auth: await newInbox() });
    assert.equal((await purgeExpired(db, T0)).pairCodes, 0);
    assert.equal((await purgeExpired(db, T0 + PAIR_CODE_TTL_SECONDS * 1000)).pairCodes, 1);
  });

  it('honors RETENTION_SECONDS', async () => {
    env.RETENTION_SECONDS = String(DAY / 1000);
    const secret = await newInbox();
    const token = await connect(secret);
    await upload(secret, 1);
    now = T0 + DAY;
    assert.equal((await pull(token)).items.length, 0);
    assert.equal(retentionSeconds({ RETENTION_SECONDS: 'soon' }), DEFAULT_RETENTION_SECONDS);
  });
});

describe('disconnect and delete everything', () => {
  it('disconnect kills the token and deletes its queue', async () => {
    const secret = await newInbox();
    const token = await connect(secret);
    await upload(secret, 1);
    const [{ id }] = await connections(secret);

    assert.equal((await call('DELETE', `/connections/${id}`, { auth: secret })).status, 200);
    assert.equal((await call('GET', '/inbox', { auth: token })).status, 401);
    assert.equal(rows('entries'), 0);
    assert.equal((await call('DELETE', `/connections/${id}`, { auth: secret })).status, 404);
  });

  it("can't disconnect another inbox's agent", async () => {
    const theirs = await newInbox();
    const theirAgent = await connect(theirs);
    const [{ id }] = await connections(theirs);
    assert.equal((await call('DELETE', `/connections/${id}`, { auth: await newInbox() })).status, 404);
    assert.equal((await call('GET', '/inbox', { auth: theirAgent })).status, 200);
  });

  it('delete everything empties every queue and keeps connections', async () => {
    const secret = await newInbox();
    const a = await connect(secret);
    await connect(secret);
    await upload(secret, 1);
    await upload(secret, 2);
    assert.deepEqual((await call('DELETE', '/inbox', { auth: secret })).body, { deleted: 4 });
    assert.equal((await call('GET', '/inbox', { auth: a })).status, 200);
  });
});

describe('helpers and routing', () => {
  it('generates readable codes', () => {
    for (let i = 0; i < 200; i++) {
      const code = generatePairCode();
      assert.match(code, /^.{4}-.{4}$/);
      for (const ch of code.replace('-', '')) assert.ok(PAIR_CODE_ALPHABET.includes(ch));
    }
    assert.equal(normalizePairCode(' abcd - efgh\n'), 'ABCDEFGH');
  });

  it('validates uploads', () => {
    assert.ok(!validateUpload(recording(1)).error);
    assert.ok(validateUpload(null).error);
    assert.ok(validateUpload({ ...recording(1), transcription: '  ' }).error);
    assert.ok(validateUpload({ ...recording(1), duration: -1 }).error);
    assert.ok(validateUpload({ ...recording(1), created_at: 'yesterday' }).error);
    assert.ok(validateUpload({ ...recording(1), recording_id: 'x/../y' }).error);
    assert.ok(validateUpload({ ...recording(1), transcription: 'a'.repeat(200_001) }).error);
  });

  it('claims only relay paths', () => {
    for (const p of ['/inboxes', '/inbox', '/inbox/ack', '/pair/code', '/pair/exchange', '/connections', '/connections/con_x']) {
      assert.ok(isRelayPath(p), p);
    }
    for (const p of ['/transcribe', '/health', '/attest', '/receipts', '/inbox/x/y']) assert.ok(!isRelayPath(p), p);
  });

  it('405s wrong methods with a hint, and 503s without a database', async () => {
    const wrong = await call('GET', '/pair/exchange');
    assert.equal(wrong.status, 405);
    assert.match(wrong.body.error, /Use POST/);
    assert.equal((await call('PUT', '/inbox')).status, 405);
    env = {};
    assert.equal((await call('GET', '/inbox')).status, 503);
  });
});
