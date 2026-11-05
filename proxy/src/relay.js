// Ramble Relay: holds transcripts until the user's agent picks them up.
// Same Worker as the transcription proxy (see index.js), own D1 database.
// See RELAY.md.
//
// The app uploads a transcript, and the relay queues one copy per connected
// agent. The agent pulls and acks, and ack deletes the copy. Anything never
// picked up is deleted after RETENTION_SECONDS (30 days by default). Audio
// never comes here.
//
// Credentials:
//   App   → relay: inbox secret (Bearer rmbi_…). App Attest is checked once,
//                  when the inbox is created.
//   Agent → relay: token (Bearer rmba_…) from a single-use pairing code.

import { verifyAssertionForRequest } from './attest.js';

export const DEFAULT_RETENTION_SECONDS = 30 * 24 * 60 * 60;
export const PAIR_CODE_TTL_SECONDS = 10 * 60;
// No 0/O, 1/I/L, or U, so codes are easy to read and retype.
export const PAIR_CODE_ALPHABET = '23456789ABCDEFGHJKMNPQRSTVWXYZ';
export const PULL_LIMIT = 50;
export const MAX_TEXT_LENGTH = 200_000;
export const STATUS_LIMIT = 100;
export const MAX_NAME_LENGTH = 40;
export const MAX_HOOK_HEADERS = 8;
export const MAX_HOOK_HEADERS_BYTES = 4096;
// While a ping is unanswered (no pull since), don't send another for this
// long. A burst of recordings is one agent run, and a broken hook gets at
// most one ping per window.
export const HOOK_REPING_SECONDS = 10 * 60;
export const HOOK_TIMEOUT_MS = 5000;

const RELAY_PATHS = /^\/(inboxes|inbox|inbox\/ack|inbox\/status|pair\/code|pair\/exchange|agent|connections(\/[^/]+)?)$/;

export function isRelayPath(pathname) {
  return RELAY_PATHS.test(pathname);
}

/** `deps` lets tests supply a clock and stub App Attest. */
export async function handleRelayRequest(request, env, deps = {}) {
  if (!env.DB) return json({ error: 'Relay not enabled on this server' }, 503);

  const ctx = {
    env,
    db: env.DB,
    now: deps.now ?? Date.now(),
    verifyAssertion: deps.verifyAssertion ?? verifyAssertionForRequest,
    // Pings run after the response, so the app's upload never waits on them.
    waitUntil: deps.waitUntil ?? ((promise) => promise),
    fetch: deps.fetch ?? ((...args) => fetch(...args)),
    origin: new URL(request.url).origin,
  };
  const { pathname } = new URL(request.url);
  const route = `${request.method} ${pathname.replace(/^\/connections\/.+$/, '/connections/:id')}`;

  try {
    switch (route) {
      // App
      case 'POST /inboxes': return await createInbox(request, ctx);
      case 'POST /inbox': return await upload(request, ctx);
      case 'DELETE /inbox': return await purgeInbox(request, ctx);
      case 'POST /inbox/status': return await inboxStatus(request, ctx);
      case 'POST /pair/code': return await createPairCode(request, ctx);
      case 'GET /connections': return await listConnections(request, ctx);
      case 'DELETE /connections/:id': return await disconnect(request, pathname.split('/')[2], ctx);
      // Agent
      case 'POST /pair/exchange': return await exchangePairCode(request, ctx);
      case 'GET /inbox': return await pull(request, ctx);
      case 'POST /inbox/ack': return await ack(request, ctx);
      case 'GET /agent': return await getAgent(request, ctx);
      case 'PATCH /agent': return await updateAgent(request, ctx);
      default: return wrongMethod(pathname);
    }
  } catch (err) {
    // Never log request bodies: they hold transcript text.
    console.error(`[relay] ${route} failed: ${err.message}`);
    return json({ error: 'Internal error' }, 500);
  }
}

// --- App ---------------------------------------------------------------------

async function createInbox(request, ctx) {
  const denied = await checkAttestation(request, await request.arrayBuffer(), ctx);
  if (denied) return denied;

  const id = `inb_${randomToken(12)}`;
  const secret = `rmbi_${randomToken(32)}`;
  await ctx.db
    .prepare('INSERT INTO inboxes (id, secret_hash, created_at) VALUES (?, ?, ?)')
    .bind(id, await sha256Hex(secret), ctx.now)
    .run();
  return json({ inbox_secret: secret }, 201);
}

/** Idempotent on recording_id, so the app's retry queue can resend safely. */
async function upload(request, ctx) {
  const inbox = await authInbox(request, ctx);
  if (!inbox) return unauthorized();

  const item = validateUpload(await readJSON(request));
  if (item.error) return json({ error: item.error }, 400);

  const { results: connections } = await ctx.db
    .prepare('SELECT id, hook_url, hook_headers, hook_pinged_at, last_pull_at FROM connections WHERE inbox_id = ?')
    .bind(inbox.id)
    .all();
  if (connections.length > 0) {
    const expiresAt = ctx.now + retentionSeconds(ctx.env) * 1000;
    const inserted = await ctx.db.batch(
      connections.map((c) =>
        ctx.db
          .prepare(
            `INSERT OR IGNORE INTO entries
               (connection_id, recording_id, recorded_at, duration, text, expires_at, received_at)
             VALUES (?, ?, ?, ?, ?, ?, ?)`,
          )
          .bind(c.id, item.recordingId, item.createdAt, item.duration, item.text, expiresAt, ctx.now),
      ),
    );
    // Wake hooked agents that got a new copy (a resent upload pings no one).
    const toPing = connections.filter((c, i) => inserted[i].meta.changes > 0 && shouldPing(c, ctx.now));
    if (toPing.length > 0) ctx.waitUntil(Promise.all(toPing.map((c) => pingHook(c, ctx))));
  }
  return json({ queued: connections.length });
}

/**
 * How many agents each recording is still waiting for. Ack deletes, so 0
 * means every agent picked it up (or it expired, or its agent was
 * disconnected). Lets the app tell "sent" from "your agent has it" without
 * the relay storing anything more.
 */
async function inboxStatus(request, ctx) {
  const inbox = await authInbox(request, ctx);
  if (!inbox) return unauthorized();

  const ids = (await readJSON(request))?.recording_ids;
  if (
    !Array.isArray(ids) ||
    ids.length === 0 ||
    ids.length > STATUS_LIMIT ||
    !ids.every((id) => typeof id === 'string' && /^[A-Za-z0-9-]{1,64}$/.test(id))
  ) {
    return json({ error: `"recording_ids" must be an array of 1–${STATUS_LIMIT} recording ids` }, 400);
  }
  const unique = [...new Set(ids)];
  const { results } = await ctx.db
    .prepare(
      `SELECT e.recording_id, COUNT(*) AS waiting FROM entries e
         JOIN connections c ON c.id = e.connection_id
        WHERE c.inbox_id = ? AND e.expires_at > ? AND e.recording_id IN (${unique.map(() => '?').join(',')})
        GROUP BY e.recording_id`,
    )
    .bind(inbox.id, ctx.now, ...unique)
    .all();
  const waiting = new Map(results.map((r) => [r.recording_id, r.waiting]));
  return json({
    recordings: unique.map((id) => ({ recording_id: id, waiting: waiting.get(id) ?? 0 })),
  });
}

/** "Delete everything now". Connections stay. */
async function purgeInbox(request, ctx) {
  const inbox = await authInbox(request, ctx);
  if (!inbox) return unauthorized();
  const result = await ctx.db
    .prepare('DELETE FROM entries WHERE connection_id IN (SELECT id FROM connections WHERE inbox_id = ?)')
    .bind(inbox.id)
    .run();
  return json({ deleted: result.meta.changes });
}

/** One live code per inbox: a new one cancels the last. */
async function createPairCode(request, ctx) {
  const inbox = await authInbox(request, ctx);
  if (!inbox) return unauthorized();

  const code = generatePairCode();
  const expiresAt = ctx.now + PAIR_CODE_TTL_SECONDS * 1000;
  await ctx.db.batch([
    ctx.db.prepare('DELETE FROM pair_codes WHERE inbox_id = ?').bind(inbox.id),
    ctx.db
      .prepare('INSERT INTO pair_codes (code_hash, inbox_id, expires_at) VALUES (?, ?, ?)')
      .bind(await sha256Hex(normalizePairCode(code)), inbox.id, expiresAt),
  ]);
  return json({ code, expires_at: iso(expiresAt) }, 201);
}

async function listConnections(request, ctx) {
  const inbox = await authInbox(request, ctx);
  if (!inbox) return unauthorized();

  const { results } = await ctx.db
    .prepare(
      `SELECT c.id, c.name, c.created_at, c.last_pull_at, c.hook_url, c.hook_pinged_at, c.hook_status,
              (SELECT COUNT(*) FROM entries e
                WHERE e.connection_id = c.id AND e.expires_at > ?) AS pending
         FROM connections c WHERE c.inbox_id = ? ORDER BY c.created_at`,
    )
    .bind(ctx.now, inbox.id)
    .all();

  return json({
    connections: results.map((c) => ({
      id: c.id,
      name: c.name ?? null,
      created_at: iso(c.created_at),
      last_pull_at: c.last_pull_at ? iso(c.last_pull_at) : null,
      pending: c.pending,
      // The URL and headers stay on the relay; the app only needs to know
      // a hook exists and whether its last ping worked.
      hook: c.hook_url
        ? { last_ping_at: c.hook_pinged_at ? iso(c.hook_pinged_at) : null, last_status: c.hook_status ?? null }
        : null,
    })),
  });
}

/** Kills the agent's token and deletes everything queued for it. */
async function disconnect(request, connectionId, ctx) {
  const inbox = await authInbox(request, ctx);
  if (!inbox) return unauthorized();

  const [, removed] = await ctx.db.batch([
    ctx.db
      .prepare('DELETE FROM entries WHERE connection_id IN (SELECT id FROM connections WHERE id = ? AND inbox_id = ?)')
      .bind(connectionId, inbox.id),
    ctx.db.prepare('DELETE FROM connections WHERE id = ? AND inbox_id = ?').bind(connectionId, inbox.id),
  ]);
  if (removed.meta.changes === 0) return json({ error: 'Connection not found' }, 404);
  return json({ status: 'disconnected' });
}

// --- Agent -------------------------------------------------------------------

/**
 * No auth: the code is the credential. It makes one connection. Retrying the
 * same code returns the same token until the agent first pulls with it (or
 * the code expires), so a lost response never strands the agent.
 */
async function exchangePairCode(request, ctx) {
  const body = await readJSON(request);
  const code = body?.code;
  if (typeof code !== 'string' || !code.trim()) {
    return json({ error: 'Send JSON like {"code": "K7QX-MP4D"} with the code from the Ramble app' }, 400);
  }
  // Optional, so the user can tell agents apart in the app. Bad names are
  // dropped rather than failing the pairing.
  const name = cleanName(body?.name);
  const codeHash = await sha256Hex(normalizePairCode(code));

  // Claim the code. The conditional update makes only one exchange win, even
  // under concurrent tries; the others fall through to the replay below.
  const token = `rmba_${randomToken(32)}`;
  const connectionId = `con_${randomToken(12)}`;
  const claimed = await ctx.db
    .prepare(
      `UPDATE pair_codes SET token = ?, connection_id = ?
        WHERE code_hash = ? AND token IS NULL AND expires_at > ?
        RETURNING inbox_id`,
    )
    .bind(token, connectionId, codeHash, ctx.now)
    .first();
  if (claimed) {
    await ctx.db
      .prepare('INSERT INTO connections (id, inbox_id, token_hash, created_at, name) VALUES (?, ?, ?, ?, ?)')
      .bind(connectionId, claimed.inbox_id, await sha256Hex(token), ctx.now, name)
      .run();
    return json({ token }, 201);
  }

  // Already claimed: hand back the same token while it's still unused.
  const replay = await ctx.db
    .prepare(
      `SELECT p.token FROM pair_codes p JOIN connections c ON c.id = p.connection_id
        WHERE p.code_hash = ? AND p.expires_at > ? AND c.last_pull_at IS NULL`,
    )
    .bind(codeHash, ctx.now)
    .first();
  if (replay?.token) return json({ token: replay.token }, 200);

  return json({ error: 'Invalid or expired pairing code. Ask the user for a new one in the Ramble app.' }, 400);
}

/** Oldest first, up to PULL_LIMIT. Ack what you handled, then pull again. */
async function pull(request, ctx) {
  const connection = await authAgent(request, ctx);
  if (!connection) return unauthorized();

  const [{ results }] = await ctx.db.batch([
    ctx.db
      .prepare(
        `SELECT id, recording_id, recorded_at, received_at, duration, text FROM entries
          WHERE connection_id = ? AND expires_at > ? ORDER BY id LIMIT ?`,
      )
      .bind(connection.id, ctx.now, PULL_LIMIT + 1),
    ctx.db.prepare('UPDATE connections SET last_pull_at = ? WHERE id = ?').bind(ctx.now, connection.id),
    // The agent has its token, so the pairing code's copy can go.
    ctx.db.prepare('DELETE FROM pair_codes WHERE connection_id = ?').bind(connection.id),
  ]);

  return json({
    items: results.slice(0, PULL_LIMIT).map((row) => ({
      id: row.id,
      recording_id: row.recording_id,
      // As the phone sent it: recording start, with the phone's UTC offset.
      created_at: row.recorded_at,
      received_at: row.received_at ? iso(row.received_at) : null,
      duration: row.duration,
      transcription: row.text,
    })),
    has_more: results.length > PULL_LIMIT,
  });
}

/** Deletes the acked items. */
async function ack(request, ctx) {
  const connection = await authAgent(request, ctx);
  if (!connection) return unauthorized();

  const ids = (await readJSON(request))?.ids;
  if (!Array.isArray(ids) || ids.length === 0 || ids.length > 500 || !ids.every(Number.isSafeInteger)) {
    return json({ error: '"ids" must be an array of 1–500 item ids' }, 400);
  }
  const result = await ctx.db
    .prepare(`DELETE FROM entries WHERE connection_id = ? AND id IN (${ids.map(() => '?').join(',')})`)
    .bind(connection.id, ...ids)
    .run();
  return json({ deleted: result.meta.changes });
}

/** What the relay knows about this agent. Header values are never echoed. */
async function getAgent(request, ctx) {
  const connection = await authAgent(request, ctx);
  if (!connection) return unauthorized();
  return json(agentView(connection));
}

/**
 * The agent sets its own name and, optionally, a wake-up webhook:
 *   {"name": "Grok Bot", "hook": {"url": "https://…", "headers": {"Authorization": "Bearer …"}}}
 * Either field can be left out. "hook": null removes the hook. Setting a hook
 * sends one test ping right away and returns its HTTP status, so the agent
 * knows at once whether its URL and headers work.
 */
async function updateAgent(request, ctx) {
  const connection = await authAgent(request, ctx);
  if (!connection) return unauthorized();

  const body = await readJSON(request);
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    return json({ error: 'Send JSON like {"name": "My agent", "hook": {"url": "https://…", "headers": {…}}}' }, 400);
  }

  const updates = [];
  if ('name' in body) {
    const name = cleanName(body.name);
    if (body.name !== null && !name) return json({ error: `"name" must be 1–${MAX_NAME_LENGTH} characters` }, 400);
    updates.push(ctx.db.prepare('UPDATE connections SET name = ? WHERE id = ?').bind(name, connection.id));
    connection.name = name;
  }

  let hook;
  if ('hook' in body) {
    if (body.hook === null) {
      updates.push(
        ctx.db
          .prepare(
            `UPDATE connections SET hook_url = NULL, hook_headers = NULL, hook_pinged_at = NULL, hook_status = NULL
              WHERE id = ?`,
          )
          .bind(connection.id),
      );
      Object.assign(connection, { hook_url: null, hook_headers: null, hook_pinged_at: null, hook_status: null });
    } else {
      hook = validateHook(body.hook, ctx.origin);
      if (hook.error) return json({ error: hook.error }, 400);
      const headers = JSON.stringify(hook.headers);
      updates.push(
        ctx.db
          .prepare(
            `UPDATE connections SET hook_url = ?, hook_headers = ?, hook_pinged_at = NULL, hook_status = NULL
              WHERE id = ?`,
          )
          .bind(hook.url, headers, connection.id),
      );
      Object.assign(connection, { hook_url: hook.url, hook_headers: headers });
    }
  }
  if (updates.length > 0) await ctx.db.batch(updates);

  if (hook) {
    const status = await pingHook(connection, ctx, 'ramble.test');
    connection.hook_status = status;
  }
  return json(agentView(connection));
}

function agentView(c) {
  return {
    name: c.name ?? null,
    hook: c.hook_url
      ? {
          url: c.hook_url,
          header_names: Object.keys(JSON.parse(c.hook_headers || '{}')),
          last_ping_at: c.hook_pinged_at ? iso(c.hook_pinged_at) : null,
          last_status: c.hook_status ?? null,
        }
      : null,
  };
}

// --- Wake-up hooks -----------------------------------------------------------

/**
 * Ping unless a ping is already out that the agent hasn't answered with a
 * pull, and it went out less than HOOK_REPING_SECONDS ago.
 */
export function shouldPing(c, now) {
  if (!c.hook_url) return false;
  if (c.hook_pinged_at == null) return true;
  if (c.last_pull_at != null && c.last_pull_at >= c.hook_pinged_at) return true;
  return now - c.hook_pinged_at >= HOOK_REPING_SECONDS * 1000;
}

/**
 * One POST, no retries, never throws. Carries no transcript text: the agent
 * pulls with its own token, so text only ever leaves the relay that way.
 * Returns the HTTP status, or 0 if the request failed.
 */
async function pingHook(c, ctx, event = 'ramble.notes_waiting') {
  const pullURL = `${ctx.origin}/inbox`;
  const text =
    event === 'ramble.test'
      ? 'Ramble test ping: your wake-up hook works. Nothing new to pick up.'
      : `New Ramble notes are waiting. Pull them from ${pullURL} with your Ramble token, handle them, then ack.`;
  let status = 0;
  try {
    // The test ping doesn't count as an unanswered ping: there's nothing to pull.
    if (event !== 'ramble.test') {
      await ctx.db.prepare('UPDATE connections SET hook_pinged_at = ? WHERE id = ?').bind(ctx.now, c.id).run();
    }
    const res = await ctx.fetch(c.hook_url, {
      method: 'POST',
      headers: {
        ...JSON.parse(c.hook_headers || '{}'),
        'Content-Type': 'application/json',
        'User-Agent': 'Ramble-Relay/1 (+https://ramble.watch/docs)',
      },
      body: JSON.stringify({ event, text, pull_url: pullURL }),
      redirect: 'manual',
      signal: AbortSignal.timeout(HOOK_TIMEOUT_MS),
    });
    status = res.status;
  } catch {
    status = 0;
  }
  try {
    await ctx.db.prepare('UPDATE connections SET hook_status = ? WHERE id = ?').bind(status, c.id).run();
  } catch {
    // Best effort: a lost status only affects what the app displays.
  }
  return status;
}

const RESERVED_HEADERS = new Set([
  'host', 'content-length', 'content-type', 'connection', 'transfer-encoding', 'user-agent', 'cookie',
]);

/** HTTPS only, public hostnames only, a few plain headers. */
export function validateHook(hook, relayOrigin) {
  if (!hook || typeof hook !== 'object' || Array.isArray(hook)) {
    return { error: '"hook" must be {"url": "https://…", "headers": {…}} or null' };
  }
  let url;
  try {
    url = new URL(hook.url);
  } catch {
    return { error: '"hook.url" must be a full https:// URL' };
  }
  const host = url.hostname.toLowerCase();
  if (
    url.protocol !== 'https:' ||
    String(hook.url).length > 2048 ||
    url.username ||
    url.password ||
    !host.includes('.') ||
    /^[\d.]+$/.test(host) ||
    host.startsWith('[') ||
    /\.(local|internal|localhost|lan|home|arpa)$/.test(host) ||
    url.origin === relayOrigin
  ) {
    return { error: '"hook.url" must be a public https:// URL with a hostname' };
  }

  const headers = hook.headers ?? {};
  if (typeof headers !== 'object' || Array.isArray(headers)) {
    return { error: '"hook.headers" must be an object of header names to values' };
  }
  const entries = Object.entries(headers);
  if (entries.length > MAX_HOOK_HEADERS) return { error: `"hook.headers" can have at most ${MAX_HOOK_HEADERS} headers` };
  for (const [name, value] of entries) {
    if (!/^[A-Za-z0-9-]{1,64}$/.test(name) || RESERVED_HEADERS.has(name.toLowerCase())) {
      return { error: `"hook.headers" can't set "${name}"` };
    }
    if (typeof value !== 'string' || /[\r\n\0]/.test(value)) {
      return { error: `"hook.headers.${name}" must be a single-line string` };
    }
  }
  if (JSON.stringify(headers).length > MAX_HOOK_HEADERS_BYTES) {
    return { error: `"hook.headers" must be under ${MAX_HOOK_HEADERS_BYTES} bytes` };
  }
  return { url: url.href, headers };
}

/** Trimmed, single line, 1–MAX_NAME_LENGTH characters; anything else is null. */
export function cleanName(value) {
  if (typeof value !== 'string') return null;
  const name = value.replace(/[\u0000-\u001f\u007f]/g, ' ').replace(/\s+/g, ' ').trim();
  return name && name.length <= MAX_NAME_LENGTH ? name : null;
}

// --- Expiry (cron) -----------------------------------------------------------

/** Reads already skip expired rows; this only reclaims space. */
export async function purgeExpired(db, now) {
  const [entries, pairCodes] = await db.batch([
    db.prepare('DELETE FROM entries WHERE expires_at <= ?').bind(now),
    db.prepare('DELETE FROM pair_codes WHERE expires_at <= ?').bind(now),
  ]);
  return { entries: entries.meta.changes, pairCodes: pairCodes.meta.changes };
}

// --- Helpers -----------------------------------------------------------------

async function checkAttestation(request, body, ctx) {
  const bypass = request.headers.get('X-Dev-Bypass');
  if (bypass && ctx.env.DEV_BYPASS_TOKEN && bypass === ctx.env.DEV_BYPASS_TOKEN) return null;

  const keyId = request.headers.get('X-App-Attest-Key-Id');
  const assertion = request.headers.get('X-App-Attest');
  if (!keyId || !assertion) return json({ error: 'App attestation required' }, 403);

  const result = await ctx.verifyAssertion(keyId, assertion, body, ctx.env);
  if (!result.valid) {
    console.error(`[relay] attestation failed: ${result.reason}`);
    return json({ error: 'App attestation failed' }, 403);
  }
  return null;
}

async function authInbox(request, ctx) {
  const secret = bearer(request, 'rmbi_');
  if (!secret) return null;
  return ctx.db.prepare('SELECT id FROM inboxes WHERE secret_hash = ?').bind(await sha256Hex(secret)).first();
}

async function authAgent(request, ctx) {
  const token = bearer(request, 'rmba_');
  if (!token) return null;
  return ctx.db
    .prepare(
      `SELECT id, name, hook_url, hook_headers, hook_pinged_at, hook_status
         FROM connections WHERE token_hash = ?`,
    )
    .bind(await sha256Hex(token))
    .first();
}

/** Lenient: "Bearer <t>", "bearer <t>", or the bare token all work. */
function bearer(request, prefix) {
  const value = (request.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '').trim();
  return value.startsWith(prefix) ? value : null;
}

export function validateUpload(body) {
  const { recording_id: recordingId, created_at: createdAt, duration, transcription } = body ?? {};
  if (typeof recordingId !== 'string' || !/^[A-Za-z0-9-]{1,64}$/.test(recordingId)) {
    return { error: '"recording_id" must be a UUID string' };
  }
  if (typeof createdAt !== 'string' || Number.isNaN(Date.parse(createdAt))) {
    return { error: '"created_at" must be an ISO 8601 timestamp' };
  }
  if (typeof duration !== 'number' || !(duration >= 0)) {
    return { error: '"duration" must be a non-negative number' };
  }
  if (typeof transcription !== 'string' || !transcription.trim() || transcription.length > MAX_TEXT_LENGTH) {
    return { error: `"transcription" must be 1–${MAX_TEXT_LENGTH} characters` };
  }
  return { recordingId, createdAt, duration, text: transcription };
}

/** Formatted for display as XXXX-XXXX. Rejection sampling avoids bias. */
export function generatePairCode() {
  const limit = 256 - (256 % PAIR_CODE_ALPHABET.length);
  let chars = '';
  while (chars.length < 8) {
    for (const b of crypto.getRandomValues(new Uint8Array(16))) {
      if (b < limit && chars.length < 8) chars += PAIR_CODE_ALPHABET[b % PAIR_CODE_ALPHABET.length];
    }
  }
  return `${chars.slice(0, 4)}-${chars.slice(4)}`;
}

/** Codes as typed or pasted: any case, spaces and dashes ignored. */
export function normalizePairCode(input) {
  return String(input).toUpperCase().replace(/[\s-]/g, '').slice(0, 32);
}

export function retentionSeconds(env) {
  const n = Number(env.RETENTION_SECONDS);
  return Number.isFinite(n) && n > 0 ? n : DEFAULT_RETENTION_SECONDS;
}

function randomToken(bytes) {
  const raw = String.fromCharCode(...crypto.getRandomValues(new Uint8Array(bytes)));
  return btoa(raw).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function sha256Hex(value) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, '0')).join('');
}

async function readJSON(request) {
  try {
    return await request.json();
  } catch {
    return null;
  }
}

const iso = (ms) => new Date(ms).toISOString();

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  });
}

function unauthorized() {
  return json({ error: 'Invalid or revoked credentials. Send "Authorization: Bearer <token>".' }, 401);
}

const METHODS = {
  '/inboxes': 'POST',
  '/inbox': 'GET (agent pull), POST or DELETE (app)',
  '/inbox/ack': 'POST',
  '/inbox/status': 'POST',
  '/pair/code': 'POST',
  '/pair/exchange': 'POST',
  '/connections': 'GET',
  '/agent': 'GET or PATCH',
};

/** Every relay path exists; only the method was wrong. Say which one fits. */
function wrongMethod(pathname) {
  const allowed = METHODS[pathname] ?? 'DELETE';
  return json({ error: `Wrong method for ${pathname}. Use ${allowed}. Docs: https://ramble.watch/docs` }, 405);
}
