// Agent side: pairing, copies, pull and ack, delivery status, disconnect,
// delete waiting, wake-up hooks. specs/relay-api.md "Agents and pairing",
// specs/delivery.md.

import assert from 'node:assert/strict';
import { beforeEach, describe, it } from 'node:test';

import {
  PAIR_CODE_ALPHABET,
  cleanName,
  generatePairCode,
  normalizePairCode,
  openHeaders,
  sealHeaders,
  shouldPing,
  validateHook,
  HOOK_REPING_SECONDS,
} from '../src/relay.js';
import { DAY, MINUTE, T0, createHarness, noteId } from './harness.js';

let h;
beforeEach(() => {
  h = createHarness();
});

const pull = async (token) => (await h.call('GET', '/inbox', { auth: token })).body;
const ack = (token, ids) => h.call('POST', '/inbox/ack', { auth: token, body: { ids } });
const status = (secret, ids) => h.call('POST', '/inbox/status', { auth: secret, body: { recording_ids: ids } });

/** An inbox with one agent connected before the note is uploaded. */
async function setup() {
  const secret = await h.inbox();
  const agent = await h.connect(secret);
  h.now = T0 + MINUTE;
  return { secret, agent };
}
const recordedAt = () => new Date(h.now - 1000).toISOString();
const say = (secret, n, text = `thought ${n}`) => {
  h.transcribe = async () => ({ result: 'transcript', text, provider: 'groq', durationSeconds: 7 });
  return h.upload(secret, noteId(n), { recordedAt: recordedAt() });
};

describe('the whole loop', () => {
  it('note in, copy out, ack, and the copy is gone', async () => {
    const { secret, agent } = await setup();
    await say(secret, 1);
    await h.settle();
    const { items, has_more } = await pull(agent);
    assert.equal(has_more, false);
    assert.deepEqual(items, [
      {
        id: items[0].id,
        recording_id: noteId(1),
        created_at: recordedAt(),
        received_at: new Date(h.now).toISOString(),
        duration: 7,
        transcription: 'thought 1',
        note: {
          type: 'ramble.note',
          version: 1,
          id: noteId(1),
          source: 'phone',
          recorded_at: recordedAt(),
          received_at: new Date(h.now).toISOString(),
          duration_seconds: 7,
          transcript: 'thought 1',
        },
      },
    ]);
    assert.deepEqual((await ack(agent, [items[0].id])).body, { deleted: 1 });
    assert.deepEqual(await pull(agent), { items: [], has_more: false });
    assert.equal(h.rows("SELECT COUNT(*) AS n FROM entries WHERE text != ''")[0].n, 0);
  });

  it('copies to agents connected when the server accepted the note, whatever its recorded time', async () => {
    const secret = await h.inbox();
    h.now = T0 + 5 * MINUTE;
    const early = await h.connect(secret);
    h.now += MINUTE;
    const releases = [];
    h.transcribe = () => new Promise((r) => releases.push(() => r({ result: 'transcript', text: 'x', provider: 'groq' })));
    // Recorded before the agent paired, and with a clock far ahead: neither matters.
    await h.upload(secret, noteId(1), { recordedAt: new Date(T0).toISOString() });
    await h.upload(secret, noteId(2), { recordedAt: new Date(T0 + 30 * DAY).toISOString() });
    h.now += MINUTE;
    const late = await h.connect(secret);
    releases.forEach((release) => release());
    await h.settle();
    assert.deepEqual((await pull(early)).items.map((i) => i.recording_id).sort(), [noteId(1), noteId(2)].sort());
    assert.equal((await pull(late)).items.length, 0);
  });

  it('gives each agent its own copy; acking one leaves the other', async () => {
    const secret = await h.inbox();
    const a = await h.connect(secret, 'Grok Bot');
    const b = await h.connect(secret, 'Muse');
    h.now = T0 + MINUTE;
    await say(secret, 1);
    const [item] = (await pull(a)).items;
    await ack(a, [item.id]);
    assert.equal((await pull(b)).items.length, 1);
    assert.deepEqual((await ack(b, [item.id])).body, { deleted: 0 });
  });

  it('returns oldest first, 50 at a time', async () => {
    const { secret, agent } = await setup();
    h.db.sqlite.exec('UPDATE inboxes SET free_notes_used = -100');
    for (let i = 1; i <= 52; i++) await say(secret, i);
    const first = await pull(agent);
    assert.equal(first.items.length, 50);
    assert.equal(first.has_more, true);
    assert.equal(first.items[0].recording_id, noteId(1));
  });

  it('rejects bad ack bodies', async () => {
    const { agent } = await setup();
    for (const ids of [[], ['1'], Array(501).fill(1)]) assert.equal((await ack(agent, ids)).status, 400);
  });

  it('expires unacked copies after 30 days', async () => {
    const { secret, agent } = await setup();
    await say(secret, 1);
    h.now += 30 * DAY;
    assert.equal((await pull(agent)).items.length, 0);
    await h.cron();
    const { agents, ...counts } = (await status(secret, [noteId(1)])).body.recordings[0];
    assert.deepEqual(counts, {
      recording_id: noteId(1), copies: 1, waiting: 0, picked_up: 0, removed: 1, first_picked_up_at: null,
    });
    assert.deepEqual(agents.map((a) => a.state), ['removed']);
  });
});

describe('delivery status', () => {
  it('counts copies, waiting, picked up and removed, and lists unknown IDs as missing', async () => {
    const secret = await h.inbox();
    const a = await h.connect(secret);
    const b = await h.connect(secret);
    h.now = T0 + MINUTE;
    await say(secret, 1);
    const [item] = (await pull(a)).items;
    await ack(a, [item.id]);
    const res = await status(secret, [noteId(1), noteId(2)]);
    const [ca, cb] = (await h.call('GET', '/connections', { auth: secret })).body.connections.map((c) => c.id);
    assert.deepEqual(res.body, {
      recordings: [
        {
          recording_id: noteId(1), copies: 2, waiting: 1, picked_up: 1, removed: 0, first_picked_up_at: new Date(h.now).toISOString(),
          agents: [
            { connection_id: ca, name: null, state: 'picked_up', picked_up_at: new Date(h.now).toISOString() },
            { connection_id: cb, name: null, state: 'waiting', picked_up_at: null },
          ],
        },
      ],
      missing: [noteId(2)],
    });
    await h.call('DELETE', `/connections/${cb}`, { auth: secret });
    assert.equal((await pull(b)).items, undefined);
    const after = (await status(secret, [noteId(1)])).body.recordings[0];
    assert.equal(after.removed, 1);
    assert.deepEqual(after.agents.map((x) => [x.connection_id, x.state]), [[ca, 'picked_up'], [cb, 'removed']]);
  });

  it('names each agent that has a copy', async () => {
    const secret = await h.inbox();
    const a = await h.connect(secret, 'Grok Bot');
    await h.connect(secret, 'Muse');
    h.now = T0 + MINUTE;
    await say(secret, 1);
    const [item] = (await pull(a)).items;
    await ack(a, [item.id]);
    const { agents } = (await status(secret, [noteId(1)])).body.recordings[0];
    assert.deepEqual(agents.map((x) => [x.name, x.state]), [['Grok Bot', 'picked_up'], ['Muse', 'waiting']]);
  });

  it("can't see another inbox, and needs the phone's credential", async () => {
    const { secret, agent } = await setup();
    await say(secret, 1);
    const other = await h.inbox();
    assert.deepEqual((await status(other, [noteId(1)])).body.missing, [noteId(1)]);
    assert.equal((await status(agent, [noteId(1)])).body.reason, 'wrong_credential');
    assert.equal((await status(secret, [])).status, 400);
  });
});

describe('pairing', () => {
  it('makes 12-character codes from the readable alphabet', () => {
    for (let i = 0; i < 50; i++) {
      const code = generatePairCode();
      assert.match(code, /^[^-]{4}-[^-]{4}-[^-]{4}$/);
      assert.ok([...code.replace(/-/g, '')].every((c) => PAIR_CODE_ALPHABET.includes(c)));
    }
    assert.equal(normalizePairCode(' k7qx-mp4d 2hnv '), 'K7QXMP4D2HNV');
  });

  it('a code makes one connection, once; a second exchange gets 409 and no key', async () => {
    const secret = await h.inbox();
    const { code } = (await h.call('POST', '/pair/code', { auth: secret })).body;
    const body = { code: code.toLowerCase().replace(/-/g, ' ') };
    const first = await h.call('POST', '/pair/exchange', { body });
    assert.equal(first.status, 201);
    await pull(first.body.token);
    h.now += 9 * MINUTE;
    const again = await h.call('POST', '/pair/exchange', { body });
    assert.equal(again.status, 409);
    assert.equal(again.body.reason, 'code_used');
    assert.equal(again.body.token, undefined);
    assert.equal((await h.call('GET', '/connections', { auth: secret })).body.connections.length, 1);
    assert.ok(!JSON.stringify(h.rows('SELECT * FROM pair_codes')).includes(first.body.token));
    h.now += 2 * MINUTE;
    assert.equal((await h.call('POST', '/pair/exchange', { body })).status, 400);
  });

  it('a new code cancels the previous one; expired codes fail', async () => {
    const secret = await h.inbox();
    const { code: old } = (await h.call('POST', '/pair/code', { auth: secret })).body;
    const { code } = (await h.call('POST', '/pair/code', { auth: secret })).body;
    const exchange = (c) => h.call('POST', '/pair/exchange', { body: { code: c } });
    assert.equal((await exchange(old)).status, 400);
    h.now += 10 * MINUTE;
    assert.equal((await exchange(code)).status, 400);
  });

  it('needs a code, ignores a request_id, and drops a bad name', async () => {
    const secret = await h.inbox();
    const { code } = (await h.call('POST', '/pair/code', { auth: secret })).body;
    assert.equal((await h.call('POST', '/pair/exchange', { body: { request_id: 'z'.repeat(16) } })).status, 400);
    const res = await h.call('POST', '/pair/exchange', { body: { code, request_id: 'short', name: 'x'.repeat(41) } });
    assert.equal(res.status, 201);
    assert.equal((await h.call('GET', '/connections', { auth: secret })).body.connections[0].name, null);
  });

  it('caps an inbox at 10 agents', async () => {
    const secret = await h.inbox();
    for (let i = 0; i < 10; i++) await h.connect(secret);
    const res = await h.call('POST', '/pair/code', { auth: secret });
    assert.equal(res.status, 409);
    assert.equal(res.body.reason, 'too_many_agents');
  });

  it('never limits exchanges: failed tries block no one', async () => {
    const bad = () => h.call('POST', '/pair/exchange', { body: { code: 'AAAA-AAAA-AAAA', request_id: 'w'.repeat(16) } });
    for (let i = 0; i < 150; i++) assert.equal((await bad()).status, 400);
    const secret = await h.inbox();
    const { code } = (await h.call('POST', '/pair/code', { auth: secret })).body;
    const res = await h.call('POST', '/pair/exchange', { body: { code, request_id: 'v'.repeat(16) } });
    assert.equal(res.status, 201);
    assert.equal(h.limiter.counts.size, 2); // only the inbox creation limits counted
  });
});

describe('credentials', () => {
  it('accepts a bare key, and 403s a key on the wrong side without breaking it', async () => {
    const { secret, agent } = await setup();
    const bare = await h.call('GET', '/inbox', { headers: { Authorization: agent } });
    assert.equal(bare.status, 200);
    const wrong = await h.call('GET', '/connections', { auth: agent });
    assert.equal(wrong.status, 403);
    assert.equal(wrong.body.reason, 'wrong_credential');
    assert.equal((await h.call('GET', '/inbox', { auth: agent })).status, 200);
    assert.equal((await h.call('GET', '/inbox', { auth: secret })).status, 403);
    assert.equal((await h.call('GET', '/inbox', { auth: 'rmba_nope' })).status, 401);
  });

  it('never rate-limits an agent', async () => {
    const { agent } = await setup();
    for (let i = 0; i < 100; i++) assert.equal((await h.call('GET', '/inbox', { auth: agent })).status, 200);
  });
});

describe('disconnect and delete waiting', () => {
  it('disconnect revokes the key and removes its copies', async () => {
    const { secret, agent } = await setup();
    for (let i = 1; i <= 3; i++) await say(secret, i);
    const [c] = (await h.call('GET', '/connections', { auth: secret })).body.connections;
    assert.equal(c.pending, 3);
    assert.deepEqual((await h.call('DELETE', `/connections/${c.id}`, { auth: secret })).body, { status: 'disconnected' });
    assert.equal((await h.call('GET', '/inbox', { auth: agent })).status, 401);
    assert.equal((await h.call('DELETE', `/connections/${c.id}`, { auth: secret })).status, 404);
  });

  it('DELETE /inbox removes waiting copies only, keeping the device copy and transcribing notes', async () => {
    const { secret, agent } = await setup();
    const watch = await h.watchToken(secret);
    h.transcribe = async () => ({ result: 'transcript', text: 'kept', provider: 'groq' });
    await h.upload(watch, noteId(1), { recordedAt: recordedAt() });
    let release;
    h.transcribe = () => new Promise((r) => (release = () => r({ result: 'transcript', text: 'later', provider: 'groq' })));
    await h.upload(secret, noteId(2), { recordedAt: recordedAt() });

    assert.deepEqual((await h.call('DELETE', '/inbox', { auth: secret })).body, { deleted: 1 });
    const listed = (await h.call('GET', '/notes', { auth: secret })).body.notes;
    assert.equal(listed.find((n) => n.id === noteId(1)).transcript, 'kept');
    release();
    await h.settle();
    assert.deepEqual((await pull(agent)).items.map((i) => i.recording_id), [noteId(2)]);
    assert.equal((await h.call('GET', '/connections', { auth: secret })).body.connections.length, 1);
  });
});

describe('wake-up hooks', () => {
  const setHook = (agent, hook) => h.call('PATCH', '/agent', { auth: agent, body: { hook } });
  const hook = { url: 'https://agent.example/wake', headers: { Authorization: 'Bearer s3cret' } };

  it('sends a test ping when set, shows header names only, and stores values encrypted', async () => {
    const { agent } = await setup();
    const res = await setHook(agent, hook);
    assert.equal(res.status, 200);
    assert.deepEqual(res.body.hook, { url: hook.url, header_names: ['Authorization'], last_ping_at: null, last_status: 200 });
    assert.equal(h.fetches[0].body.event, 'ramble.test');
    assert.equal(h.fetches[0].headers['User-Agent'], 'Ramble-Relay/1 (+https://ramble.watch/docs)');
    assert.ok(!JSON.stringify(h.rows('SELECT hook_headers FROM connections')).includes('s3cret'));
  });

  it('refuses to set a hook without an encryption key', async () => {
    const { agent } = await setup();
    h.envExtra = { HOOK_ENCRYPTION_KEY: undefined };
    assert.equal((await setHook(agent, hook)).status, 503);
  });

  it('pings once on a new copy, without text, then waits for a pull or 10 minutes', async () => {
    const { secret, agent } = await setup();
    await setHook(agent, hook);
    h.fetches = [];
    await say(secret, 1, 'secret words');
    await h.settle();
    assert.equal(h.fetches.length, 1);
    assert.equal(h.fetches[0].body.event, 'ramble.notes_waiting');
    assert.ok(!JSON.stringify(h.fetches[0].body).includes('secret words'));
    await say(secret, 2);
    await h.settle();
    assert.equal(h.fetches.length, 1);
    h.now += 1000;
    await pull(agent);
    await say(secret, 3);
    await h.settle();
    assert.equal(h.fetches.length, 2);
  });

  it('never pings for a silent note', async () => {
    const { secret, agent } = await setup();
    await setHook(agent, hook);
    h.fetches = [];
    h.transcribe = async () => ({ result: 'no_speech', text: '', provider: 'groq' });
    await h.upload(secret, noteId(1), { recordedAt: recordedAt() });
    await h.settle();
    assert.equal(h.fetches.length, 0);
  });

  it('rejects private URLs and reserved headers', () => {
    for (const url of ['https://192.168.1.5/run', 'https://box.local/run', 'http://agent.example/', 'https://localhost/x']) {
      assert.ok(validateHook({ url }, 'https://relay.test').error, url);
    }
    assert.ok(validateHook({ url: 'https://a.example/', headers: { Host: 'x' } }, 'https://relay.test').error);
    assert.ok(!validateHook({ url: 'https://a.example/', headers: { 'X-Key': 'v' } }, 'https://relay.test').error);
  });

  it('round-trips sealed headers, and reads anything else as no headers', async () => {
    const env = { HOOK_ENCRYPTION_KEY: 'k' };
    assert.deepEqual(await openHeaders(await sealHeaders({ A: 'b' }, env), env), { A: 'b' });
    assert.deepEqual(await openHeaders('{"A":"b"}', env), {});
    assert.deepEqual(await openHeaders('enc:v1:garbage', env), {});
  });

  it('decides when to ping', () => {
    const now = T0;
    assert.equal(shouldPing({ hook_url: null }, now), false);
    assert.equal(shouldPing({ hook_url: 'u', hook_pinged_at: null }, now), true);
    assert.equal(shouldPing({ hook_url: 'u', hook_pinged_at: now - 1000, last_pull_at: null }, now), false);
    assert.equal(shouldPing({ hook_url: 'u', hook_pinged_at: now - 1000, last_pull_at: now }, now), true);
    assert.equal(shouldPing({ hook_url: 'u', hook_pinged_at: now - HOOK_REPING_SECONDS * 1000 }, now), true);
  });

  it('cleans names', () => {
    assert.equal(cleanName('  Grok\nBot '), 'Grok Bot');
    assert.equal(cleanName(''), null);
    assert.equal(cleanName(5), null);
  });
});
