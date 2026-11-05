// Relay endpoint tests against the real schema (node:sqlite standing in for
// D1). App Attest is stubbed because it needs a real device.

import assert from 'node:assert/strict';
import { beforeEach, describe, it } from 'node:test';

import {
  DEFAULT_RETENTION_SECONDS,
  PAIR_CODE_ALPHABET,
  PAIR_CODE_TTL_SECONDS,
  PULL_LIMIT,
  STATUS_LIMIT,
  generatePairCode,
  handleRelayRequest,
  isRelayPath,
  normalizePairCode,
  purgeExpired,
  retentionSeconds,
  validateUpload,
  validateHook,
  cleanName,
  shouldPing,
  HOOK_REPING_SECONDS,
} from '../src/relay.js';
import { createTestDB } from './d1.js';

const T0 = Date.UTC(2026, 10, 1, 12, 0, 0);
const DAY = 24 * 3600 * 1000;

let db, env, now, attestOK, pings, pingStatus, background;

beforeEach(() => {
  db = createTestDB();
  env = { DB: db };
  now = T0;
  attestOK = true;
  pings = [];
  pingStatus = 200;
  background = [];
});

// Stands in for outbound fetch: records each hook ping.
async function fakeFetch(url, init) {
  pings.push({ url, headers: init.headers, body: JSON.parse(init.body) });
  if (pingStatus === 0) throw new Error('network down');
  return new Response(null, { status: pingStatus });
}

/** Runs the pings the relay handed to waitUntil. */
async function settle() {
  await Promise.all(background.splice(0));
}

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
    {
      now,
      verifyAssertion: async () => ({ valid: attestOK, reason: 'stub' }),
      fetch: fakeFetch,
      waitUntil: (promise) => background.push(promise),
    },
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
    assert.deepEqual(items, [{ id: items[0].id, ...recording(1), received_at: new Date(T0).toISOString() }]);

    assert.deepEqual((await ack(token, [items[0].id])).body, { deleted: 1 });
    assert.equal((await pull(token)).items.length, 0);
    assert.equal(rows('entries'), 0);
  });

  it('keeps the recording time as sent, offset included, and adds when the relay got it', async () => {
    const secret = await newInbox();
    const token = await connect(secret);
    now = T0 + 3 * 3600 * 1000; // the phone was offline for three hours
    await call('POST', '/inbox', { auth: secret, body: { ...recording(1), created_at: '2026-11-01T07:59:00-05:00' } });
    const [item] = (await pull(token)).items;
    assert.equal(item.created_at, '2026-11-01T07:59:00-05:00');
    assert.equal(item.received_at, '2026-11-01T15:00:00.000Z');
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

describe('pickup status', () => {
  const status = (secret, ids) => call('POST', '/inbox/status', { auth: secret, body: { recording_ids: ids } });
  const id = (n) => recording(n).recording_id;

  it('counts agents still waiting, and drops to 0 once every agent acks', async () => {
    const secret = await newInbox();
    const a = await connect(secret);
    const b = await connect(secret);
    await upload(secret, 1);
    await upload(secret, 2);

    assert.deepEqual((await status(secret, [id(1), id(2)])).body, {
      recordings: [{ recording_id: id(1), waiting: 2 }, { recording_id: id(2), waiting: 2 }],
    });

    const first = (await pull(a)).items.find((item) => item.recording_id === id(1));
    await ack(a, [first.id]);
    assert.equal((await status(secret, [id(1)])).body.recordings[0].waiting, 1);

    const second = (await pull(b)).items.find((item) => item.recording_id === id(1));
    await ack(b, [second.id]);
    assert.deepEqual((await status(secret, [id(1), id(2)])).body.recordings, [
      { recording_id: id(1), waiting: 0 },
      { recording_id: id(2), waiting: 2 },
    ]);
  });

  it('treats expired items as no longer waiting', async () => {
    const secret = await newInbox();
    await connect(secret);
    await upload(secret, 1);
    now = T0 + DEFAULT_RETENTION_SECONDS * 1000 + 1;
    assert.equal((await status(secret, [id(1)])).body.recordings[0].waiting, 0);
  });

  it("only sees the caller's own inbox", async () => {
    const mine = await newInbox();
    const theirs = await newInbox();
    await connect(theirs);
    await upload(theirs, 1);
    assert.equal((await status(mine, [id(1)])).body.recordings[0].waiting, 0);
  });

  it('rejects bad input and agent tokens', async () => {
    const secret = await newInbox();
    const token = await connect(secret);
    assert.equal((await status(secret, [])).status, 400);
    assert.equal((await status(secret, ['not ok!'])).status, 400);
    assert.equal((await status(secret, Array.from({ length: STATUS_LIMIT + 1 }, (_, n) => id(n)))).status, 400);
    assert.equal((await status(token, [id(1)])).status, 401);
    assert.equal((await call('GET', '/inbox/status', { auth: secret })).status, 405);
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
    for (const p of ['/inboxes', '/inbox', '/inbox/ack', '/pair/code', '/pair/exchange', '/agent', '/connections', '/connections/con_x']) {
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

describe('agent name', () => {
  it('takes an optional name at pairing and shows it to the app', async () => {
    const secret = await newInbox();
    const { code } = (await call('POST', '/pair/code', { auth: secret })).body;
    assert.equal((await call('POST', '/pair/exchange', { body: { code, name: '  Grok\nBot ' } })).status, 201);
    const [c] = await connections(secret);
    assert.equal(c.name, 'Grok Bot');
    assert.equal(c.hook, null);
  });

  it('drops a bad name at pairing instead of failing', async () => {
    const secret = await newInbox();
    const { code } = (await call('POST', '/pair/code', { auth: secret })).body;
    assert.equal((await call('POST', '/pair/exchange', { body: { code, name: 'x'.repeat(41) } })).status, 201);
    assert.equal((await connections(secret))[0].name, null);
  });

  it('lets an agent rename itself later', async () => {
    const secret = await newInbox();
    const token = await connect(secret);
    const res = await call('PATCH', '/agent', { auth: token, body: { name: 'Muse' } });
    assert.equal(res.status, 200);
    assert.equal(res.body.name, 'Muse');
    assert.equal((await connections(secret))[0].name, 'Muse');
    assert.equal((await call('PATCH', '/agent', { auth: token, body: { name: '' } })).status, 400);
    assert.equal((await call('GET', '/agent', { auth: token })).body.name, 'Muse');
  });
});

describe('wake-up hooks', () => {
  const HOOK = { url: 'https://hooks.example.com/run/abc', headers: { Authorization: 'Bearer key_123' } };

  async function hooked() {
    const secret = await newInbox();
    const token = await connect(secret);
    const res = await call('PATCH', '/agent', { auth: token, body: { hook: HOOK } });
    assert.equal(res.status, 200);
    pings = [];
    return { secret, token };
  }

  it('sends a test ping when a hook is set, and reports its status', async () => {
    const secret = await newInbox();
    const token = await connect(secret);
    const res = await call('PATCH', '/agent', { auth: token, body: { hook: HOOK } });
    assert.equal(res.body.hook.last_status, 200);
    assert.deepEqual(res.body.hook.header_names, ['Authorization']);
    assert.ok(!JSON.stringify(res.body).includes('key_123'), 'header values are never echoed');
    assert.equal(pings.length, 1);
    assert.equal(pings[0].url, HOOK.url);
    assert.equal(pings[0].headers.Authorization, 'Bearer key_123');
    assert.equal(pings[0].body.event, 'ramble.test');

    const [c] = await connections(secret);
    assert.equal(c.hook.last_status, 200);
    assert.ok(!('url' in c.hook), 'the app never sees the hook URL');
  });

  it('pings on a new note without the transcript text', async () => {
    const { secret } = await hooked();
    await upload(secret, 1);
    await settle();
    assert.equal(pings.length, 1);
    assert.equal(pings[0].body.event, 'ramble.notes_waiting');
    assert.equal(pings[0].body.pull_url, 'https://relay.test/inbox');
    assert.ok(!JSON.stringify(pings[0].body).includes('thought 1'));
  });

  it("doesn't ping again for a resent upload", async () => {
    const { secret } = await hooked();
    await upload(secret, 1);
    await upload(secret, 1);
    await settle();
    assert.equal(pings.length, 1);
  });

  it('holds further pings until the agent pulls, then pings again', async () => {
    const { secret, token } = await hooked();
    await upload(secret, 1);
    await settle();
    now += 1000;
    await upload(secret, 2);
    await settle();
    assert.equal(pings.length, 1, 'the first ping is still unanswered');

    now += 1000;
    await pull(token);
    now += 1000;
    await upload(secret, 3);
    await settle();
    assert.equal(pings.length, 2, 'the agent pulled, so the next note pings');
  });

  it('pings again after the re-ping window if the agent never pulls', async () => {
    const { secret } = await hooked();
    await upload(secret, 1);
    await settle();
    now += HOOK_REPING_SECONDS * 1000;
    await upload(secret, 2);
    await settle();
    assert.equal(pings.length, 2);
  });

  it('records a failed ping and keeps the note queued', async () => {
    const { secret, token } = await hooked();
    pingStatus = 0;
    await upload(secret, 1);
    await settle();
    assert.equal((await connections(secret))[0].hook.last_status, 0);
    assert.equal((await pull(token)).items.length, 1);
  });

  it('only pings agents that have a hook', async () => {
    const { secret } = await hooked();
    await connect(secret);
    const res = await upload(secret, 1);
    await settle();
    assert.equal(res.body.queued, 2);
    assert.equal(pings.length, 1);
  });

  it('removes a hook with null', async () => {
    const { secret, token } = await hooked();
    const res = await call('PATCH', '/agent', { auth: token, body: { hook: null } });
    assert.equal(res.body.hook, null);
    await upload(secret, 1);
    await settle();
    assert.equal(pings.length, 0);
    assert.equal((await connections(secret))[0].hook, null);
  });

  it('needs the agent token', async () => {
    const secret = await newInbox();
    assert.equal((await call('PATCH', '/agent', { auth: secret, body: { hook: HOOK } })).status, 401);
    assert.equal((await call('GET', '/agent')).status, 401);
  });

  it('rejects unsafe URLs and headers', () => {
    const relay = 'https://relay.test';
    assert.ok(!validateHook(HOOK, relay).error);
    for (const url of [
      'http://hooks.example.com/x',
      'https://localhost/x',
      'https://127.0.0.1/x',
      'https://[::1]/x',
      'https://printer.local/x',
      'https://user:pw@hooks.example.com/x',
      'https://relay.test/inbox',
      'not a url',
    ]) {
      assert.ok(validateHook({ url }, relay).error, url);
    }
    assert.ok(validateHook({ url: HOOK.url, headers: { Host: 'x' } }, relay).error);
    assert.ok(validateHook({ url: HOOK.url, headers: { 'X-A': 'a\r\nX-B: b' } }, relay).error);
    assert.ok(validateHook({ url: HOOK.url, headers: { 'Bad Name': 'x' } }, relay).error);
    assert.ok(validateHook({ url: HOOK.url, headers: { A: 1 } }, relay).error);
    assert.ok(validateHook(null, relay).error);
  });

  it('cleans names', () => {
    assert.equal(cleanName(' Grok   Bot '), 'Grok Bot');
    assert.equal(cleanName(''), null);
    assert.equal(cleanName(42), null);
    assert.equal(cleanName('x'.repeat(41)), null);
  });

  it('decides when to ping', () => {
    const base = { hook_url: 'https://h.example.com' };
    assert.equal(shouldPing({ hook_url: null }, T0), false);
    assert.equal(shouldPing({ ...base, hook_pinged_at: null }, T0), true);
    assert.equal(shouldPing({ ...base, hook_pinged_at: T0, last_pull_at: T0 + 1 }, T0 + 2), true);
    assert.equal(shouldPing({ ...base, hook_pinged_at: T0, last_pull_at: null }, T0 + 1), false);
  });
});
