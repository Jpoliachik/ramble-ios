// MCP connector: discovery, registration, sign-in with a pairing code,
// token, and the tools. specs/connector.md.

import assert from 'node:assert/strict';
import { beforeEach, describe, it } from 'node:test';

import { handleRequest } from '../src/index.js';
import { extractPairCode, pkceChallenge } from '../src/oauth.js';
import { MINUTE, T0, createHarness, noteId } from './harness.js';

let h;
beforeEach(() => {
  h = createHarness();
});

const REDIRECT = 'https://claude.ai/api/mcp/auth_callback';
const VERIFIER = 'v'.repeat(64);

/** A raw request, for forms, HTML and redirects. */
async function send(method, path, { form, json, auth, headers = {} } = {}) {
  const hdrs = new Headers(headers);
  if (auth) hdrs.set('Authorization', `Bearer ${auth}`);
  let body;
  if (form) {
    hdrs.set('Content-Type', 'application/x-www-form-urlencoded');
    body = new URLSearchParams(form).toString();
  } else if (json !== undefined) {
    hdrs.set('Content-Type', 'application/json');
    body = JSON.stringify(json);
  }
  const res = await handleRequest(new Request(`https://relay.test${path}`, { method, headers: hdrs, body }), h.env(), h.deps());
  return { status: res.status, headers: res.headers, text: await res.text() };
}

async function registerClient(extra = {}) {
  const res = await send('POST', '/register', { json: { client_name: 'Claude', redirect_uris: [REDIRECT], ...extra } });
  assert.equal(res.status, 201, res.text);
  return JSON.parse(res.text).client_id;
}

async function authParams(clientId) {
  return {
    response_type: 'code',
    client_id: clientId,
    redirect_uri: REDIRECT,
    state: 'st8',
    code_challenge: await pkceChallenge(VERIFIER),
    code_challenge_method: 'S256',
  };
}

async function pairCode(secret) {
  return (await h.call('POST', '/pair/code', { auth: secret })).body.code;
}

/** Whole sign-in: register, enter the code, redeem. Returns the access token. */
async function signIn(secret) {
  const clientId = await registerClient();
  const params = await authParams(clientId);
  const res = await send('POST', '/authorize', { form: { ...params, pairing_code: await pairCode(secret) } });
  assert.equal(res.status, 302, res.text);
  const code = new URL(res.headers.get('Location')).searchParams.get('code');
  const tok = await send('POST', '/token', {
    form: { grant_type: 'authorization_code', code, redirect_uri: REDIRECT, client_id: clientId, code_verifier: VERIFIER },
  });
  assert.equal(tok.status, 200, tok.text);
  return JSON.parse(tok.text).access_token;
}

let rpcId = 0;
async function rpc(auth, method, params) {
  const res = await send('POST', '/mcp', { auth, json: { jsonrpc: '2.0', id: ++rpcId, method, params } });
  return { status: res.status, headers: res.headers, body: res.text ? JSON.parse(res.text) : null };
}
async function tool(auth, name, args = {}) {
  const res = await rpc(auth, 'tools/call', { name, arguments: args });
  assert.equal(res.status, 200);
  return res.body.result;
}

const say = (secret, n, text = `thought ${n}`) => {
  h.transcribe = async () => ({ result: 'transcript', text, provider: 'groq', durationSeconds: 7 });
  return h.upload(secret, noteId(n), { recordedAt: '2026-11-01T06:59:00-05:00' });
};

describe('discovery', () => {
  it('points /mcp at the relay as its own authorization server', async () => {
    const pr = JSON.parse((await send('GET', '/.well-known/oauth-protected-resource')).text);
    assert.deepEqual(pr.resource, 'https://relay.test/mcp');
    assert.deepEqual(pr.authorization_servers, ['https://relay.test']);
    const as = JSON.parse((await send('GET', '/.well-known/oauth-authorization-server')).text);
    assert.equal(as.issuer, 'https://relay.test');
    assert.equal(as.authorization_endpoint, 'https://relay.test/authorize');
    assert.equal(as.token_endpoint, 'https://relay.test/token');
    assert.equal(as.registration_endpoint, 'https://relay.test/register');
    assert.deepEqual(as.code_challenge_methods_supported, ['S256']);
  });

  it('answers /mcp without a key with 401 and the metadata URL', async () => {
    const res = await rpc(undefined, 'initialize', {});
    assert.equal(res.status, 401);
    assert.equal(
      res.headers.get('WWW-Authenticate'),
      'Bearer resource_metadata="https://relay.test/.well-known/oauth-protected-resource"',
    );
  });
});

describe('registration', () => {
  it('refuses non-https redirect URIs, allows localhost', async () => {
    assert.equal((await send('POST', '/register', { json: { redirect_uris: ['http://evil.example/cb'] } })).status, 400);
    assert.equal((await send('POST', '/register', { json: { redirect_uris: [] } })).status, 400);
    assert.equal((await send('POST', '/register', { json: { redirect_uris: ['http://localhost:6274/cb'] } })).status, 201);
  });

  it('is limited to 20 an hour per address', async () => {
    for (let i = 0; i < 20; i++) await registerClient();
    const res = await send('POST', '/register', { json: { redirect_uris: [REDIRECT] } });
    assert.equal(res.status, 429);
  });
});

describe('sign-in', () => {
  it('shows the page, naming the client and where the browser goes back', async () => {
    const clientId = await registerClient();
    const q = new URLSearchParams(await authParams(clientId));
    const res = await send('GET', `/authorize?${q}`);
    assert.equal(res.status, 200);
    assert.match(res.headers.get('Content-Type'), /text\/html/);
    assert.equal(res.headers.get('X-Frame-Options'), 'DENY');
    assert.match(res.text, /Connect Claude to your notes/);
    assert.match(res.text, /go back to claude\.ai/);
  });

  it('never redirects to a URI the client did not register', async () => {
    const clientId = await registerClient();
    const q = new URLSearchParams({ ...(await authParams(clientId)), redirect_uri: 'https://evil.example/cb' });
    const res = await send('GET', `/authorize?${q}`);
    assert.equal(res.status, 400);
    assert.equal(res.headers.get('Location'), null);
    assert.equal((await send('GET', `/authorize?${new URLSearchParams({ client_id: 'rmbc_nope', redirect_uri: REDIRECT })}`)).status, 400);
  });

  it('requires PKCE S256', async () => {
    const clientId = await registerClient();
    const q = new URLSearchParams({ ...(await authParams(clientId)), code_challenge_method: 'plain' });
    const res = await send('GET', `/authorize?${q}`);
    assert.equal(res.status, 302);
    const loc = new URL(res.headers.get('Location'));
    assert.equal(loc.searchParams.get('error'), 'invalid_request');
    assert.equal(loc.searchParams.get('state'), 'st8');
  });

  it('accepts the whole message the app copies', async () => {
    const secret = await h.inbox();
    const clientId = await registerClient();
    const code = await pairCode(secret);
    const message = `I downloaded Ramble, connect it. My pairing code is ${code}. Instructions: https://ramble.watch/docs`;
    const res = await send('POST', '/authorize', { form: { ...(await authParams(clientId)), pairing_code: message } });
    assert.equal(res.status, 302);
    const loc = new URL(res.headers.get('Location'));
    assert.equal(loc.origin + loc.pathname, REDIRECT);
    assert.equal(loc.searchParams.get('state'), 'st8');
    assert.equal(loc.searchParams.get('iss'), 'https://relay.test');
    assert.ok(loc.searchParams.get('code'));
  });

  it('shows an error on the page for a wrong or used code', async () => {
    const secret = await h.inbox();
    const clientId = await registerClient();
    const params = await authParams(clientId);
    const wrong = await send('POST', '/authorize', { form: { ...params, pairing_code: 'AAAA-BBBB-CCCC' } });
    assert.equal(wrong.status, 400);
    assert.match(wrong.text, /wrong or has expired/);

    const code = await pairCode(secret);
    await h.call('POST', '/pair/exchange', { body: { code } });
    const used = await send('POST', '/authorize', { form: { ...params, pairing_code: code } });
    assert.equal(used.status, 400);
    assert.match(used.text, /already used/);
  });

  it('makes one agent connection named after the client, shown in the app', async () => {
    const secret = await h.inbox();
    const token = await signIn(secret);
    assert.match(token, /^rmba_/);
    const { connections } = (await h.call('GET', '/connections', { auth: secret })).body;
    assert.equal(connections.length, 1);
    assert.equal(connections[0].name, 'Claude');
  });

  it('uses up the authorization code on the first try, right or wrong', async () => {
    const secret = await h.inbox();
    const clientId = await registerClient();
    const res = await send('POST', '/authorize', { form: { ...(await authParams(clientId)), pairing_code: await pairCode(secret) } });
    const code = new URL(res.headers.get('Location')).searchParams.get('code');
    const form = { grant_type: 'authorization_code', code, redirect_uri: REDIRECT, client_id: clientId };
    const bad = await send('POST', '/token', { form: { ...form, code_verifier: 'w'.repeat(64) } });
    assert.equal(bad.status, 400);
    assert.equal(JSON.parse(bad.text).error, 'invalid_grant');
    const late = await send('POST', '/token', { form: { ...form, code_verifier: VERIFIER } });
    assert.equal(late.status, 400);
    assert.equal((await h.call('GET', '/connections', { auth: secret })).body.connections.length, 0);
  });

  it('refuses an expired authorization code', async () => {
    const secret = await h.inbox();
    const clientId = await registerClient();
    const res = await send('POST', '/authorize', { form: { ...(await authParams(clientId)), pairing_code: await pairCode(secret) } });
    const code = new URL(res.headers.get('Location')).searchParams.get('code');
    h.now += 11 * MINUTE;
    const tok = await send('POST', '/token', {
      form: { grant_type: 'authorization_code', code, redirect_uri: REDIRECT, client_id: clientId, code_verifier: VERIFIER },
    });
    assert.equal(tok.status, 400);
  });

  it('extracts codes from what people paste', () => {
    assert.equal(extractPairCode('k7qx-mp4d-2hnv'), 'k7qx-mp4d-2hnv');
    assert.equal(extractPairCode(' K7QX MP4D 2HNV '), 'K7QXMP4D2HNV');
    assert.equal(extractPairCode('My pairing code is K7QX-MP4D-2HNV. Instructions: …'), 'K7QX-MP4D-2HNV');
    assert.equal(extractPairCode('hello'), null);
  });
});

describe('MCP', () => {
  async function setup() {
    const secret = await h.inbox();
    const token = await signIn(secret);
    h.now = T0 + MINUTE;
    return { secret, token };
  }

  it('initializes, echoing a supported protocol version', async () => {
    const { token } = await setup();
    const res = await rpc(token, 'initialize', { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'claude' } });
    assert.equal(res.body.result.protocolVersion, '2025-06-18');
    assert.equal(res.body.result.serverInfo.name, 'ramble');
    assert.match(res.body.result.instructions, /not instructions/);
    const n = await send('POST', '/mcp', { auth: token, json: { jsonrpc: '2.0', method: 'notifications/initialized' } });
    assert.equal(n.status, 202);
    assert.equal((await send('GET', '/mcp', { auth: token })).status, 405);
  });

  it('lists the three tools with annotations', async () => {
    const { token } = await setup();
    const { tools } = (await rpc(token, 'tools/list')).body.result;
    assert.deepEqual(tools.map((t) => t.name), ['list_new_notes', 'get_note', 'mark_handled']);
    assert.equal(tools[0].annotations.readOnlyHint, true);
    assert.equal(tools[2].annotations.readOnlyHint, false);
  });

  it('lists new notes newest first, reads one, marks it handled', async () => {
    const { secret, token } = await setup();
    await say(secret, 1, 'first');
    await say(secret, 2, `second ${'word '.repeat(100)}`);
    await h.settle();

    const list = (await tool(token, 'list_new_notes')).structuredContent;
    assert.deepEqual(list.notes.map((n) => n.id), [noteId(2), noteId(1)]);
    assert.equal(list.notes[1].transcript_preview, 'first');
    assert.equal(list.notes[1].recorded_at, '2026-11-01T06:59:00-05:00');
    assert.equal(list.notes[1].duration_seconds, 7);
    assert.ok(list.notes[0].transcript_preview.length <= 201);
    assert.ok(list.notes[0].transcript_preview.endsWith('…'));
    assert.equal(list.has_more, false);

    const note = (await tool(token, 'get_note', { id: noteId(1).toLowerCase() })).structuredContent;
    assert.equal(note.transcript, 'first');
    assert.equal(note.id, noteId(1));

    assert.deepEqual((await tool(token, 'mark_handled', { id: noteId(1) })).structuredContent, { id: noteId(1), handled: true });
    assert.deepEqual((await tool(token, 'mark_handled', { id: noteId(1) })).structuredContent, { id: noteId(1), handled: true });
    assert.deepEqual((await tool(token, 'list_new_notes')).structuredContent.notes.map((n) => n.id), [noteId(2)]);
    const again = await tool(token, 'get_note', { id: noteId(1) });
    assert.equal(again.isError, true);
    assert.match(again.content[0].text, /already marked handled/);

    // The app sees the pickup like any agent's.
    const status = (await h.call('POST', '/inbox/status', { auth: secret, body: { recording_ids: [noteId(1)] } })).body;
    assert.equal(status.recordings[0].picked_up, 1);
    const { connections } = (await h.call('GET', '/connections', { auth: secret })).body;
    assert.equal(connections[0].last_pull_at, new Date(h.now).toISOString());
  });

  it('honors limit and reports more', async () => {
    const { secret, token } = await setup();
    for (const n of [1, 2, 3]) await say(secret, n);
    await h.settle();
    const list = (await tool(token, 'list_new_notes', { limit: 2 })).structuredContent;
    assert.equal(list.notes.length, 2);
    assert.equal(list.has_more, true);
    assert.equal((await tool(token, 'list_new_notes', { limit: 0 })).isError, true);
  });

  it("can't see another connection's notes", async () => {
    const { secret, token } = await setup();
    const other = await h.inbox();
    const otherToken = await signIn(other);
    await say(other, 9);
    await h.settle();
    assert.deepEqual((await tool(token, 'list_new_notes')).structuredContent.notes, []);
    assert.equal((await tool(token, 'get_note', { id: noteId(9) })).isError, true);
    assert.equal((await tool(token, 'mark_handled', { id: noteId(9) })).isError, true);
    assert.equal((await tool(otherToken, 'list_new_notes')).structuredContent.notes.length, 1);
    void secret;
  });

  it('stops working once the person disconnects it in the app', async () => {
    const { secret, token } = await setup();
    const { connections } = (await h.call('GET', '/connections', { auth: secret })).body;
    await h.call('DELETE', `/connections/${connections[0].id}`, { auth: secret });
    assert.equal((await rpc(token, 'tools/list')).status, 401);
  });

  it('refuses the inbox secret', async () => {
    const { secret } = await setup();
    assert.equal((await rpc(secret, 'tools/list')).status, 403);
  });
});
