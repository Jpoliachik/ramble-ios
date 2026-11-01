// Ramble Relay — moves transcripts from the Ramble app to the user's agent.
// Served by the same Worker as the transcription proxy (see index.js), from
// its own D1 database. See RELAY.md.
//
// The app uploads a transcript; the relay queues one copy per connected agent;
// each agent pulls its copy and acknowledges it, which deletes the text right
// away. A text-free receipt (recording id + time) stays RECEIPT_RETENTION_
// SECONDS (default 24h) so the phone can show "Picked up". Copies never
// picked up are deleted after UNACKED_RETENTION_SECONDS (default 30 days),
// long enough to ride out an agent outage. Audio never reaches the
// relay — transcription happens before upload.
//
// Two credentials, two directions:
//   App   → relay: inbox secret (Bearer rmbi_…); App Attest once, when the
//                  inbox is created, so delivery never depends on attestation
//   Agent → relay: connection token (Bearer rmba_…), obtained by exchanging a
//                  single-use pairing code the user reads off the app
//
// We identify inboxes, not people. There are no accounts.

import { verifyAssertionForRequest } from './attest.js';

// --- Limits and defaults -----------------------------------------------------

// Retention. Defaults pending Justin's confirmation (30 vs 60 days); override
// per deployment with UNACKED_RETENTION_SECONDS and RECEIPT_RETENTION_SECONDS.
export const DEFAULT_UNACKED_RETENTION_SECONDS = 30 * 24 * 60 * 60;
export const DEFAULT_RECEIPT_RETENTION_SECONDS = 24 * 60 * 60;

// Pairing codes are read off the phone and pasted into chat, so they're
// short and die fast.
export const PAIR_CODE_TTL_SECONDS = 10 * 60;
// No 0/O, 1/I/L, or U — easy to read aloud and retype.
export const PAIR_CODE_ALPHABET = '23456789ABCDEFGHJKMNPQRSTVWXYZ';
export const PAIR_CODE_LENGTH = 8;

export const AGENT_TYPES = ['muse', 'chatgpt', 'grok', 'claude', 'other'];

export const MAX_CONNECTIONS_PER_INBOX = 10;
// A 20-minute recording is ~3,000 words (~20 KB). Long recordings are
// transcribed in 20-minute chunks and joined, so leave generous headroom.
export const MAX_TEXT_LENGTH = 200_000;
export const MAX_PULL_LIMIT = 100;
export const DEFAULT_PULL_LIMIT = 50;
export const MAX_ACK_IDS = 500;

const INBOX_SECRET_PREFIX = 'rmbi_';
const AGENT_TOKEN_PREFIX = 'rmba_';

// --- Routing -----------------------------------------------------------------

export const RELAY_PATHS = /^\/(inboxes|inbox|inbox\/ack|pair\/code|pair\/exchange|connections(\/[^/]+)?|receipts)$/;

export function isRelayPath(pathname) {
  return RELAY_PATHS.test(pathname);
}

/**
 * Route a relay request (index.js sends anything matching RELAY_PATHS here).
 * `deps` lets tests supply a clock and stand in for App Attest, which can't
 * be exercised without a real device.
 */
export async function handleRelayRequest(request, env, deps = {}) {
  if (!env.DB) {
    // The D1 binding isn't configured on this deployment yet.
    return json({ error: 'Relay not enabled on this server' }, 503);
  }

  const now = deps.now ?? Date.now();
  const verifyAssertion = deps.verifyAssertion ?? verifyAssertionForRequest;
  const ctx = { env, db: env.DB, now, verifyAssertion };

  const url = new URL(request.url);
  const { pathname } = url;
  const method = request.method;

  try {
    // App-facing
    if (pathname === '/inboxes' && method === 'POST') return createInbox(request, ctx);
    if (pathname === '/inbox' && method === 'POST') return uploadTranscript(request, ctx);
    if (pathname === '/inbox' && method === 'DELETE') return purgeInbox(request, url, ctx);
    if (pathname === '/pair/code' && method === 'POST') return createPairCode(request, ctx);
    if (pathname === '/connections' && method === 'GET') return listConnections(request, ctx);
    if (pathname === '/receipts' && method === 'GET') return listReceipts(request, ctx);
    const connMatch = pathname.match(/^\/connections\/([A-Za-z0-9_-]+)$/);
    if (connMatch && method === 'DELETE') return revokeConnection(request, connMatch[1], ctx);

    // Agent-facing
    if (pathname === '/pair/exchange' && method === 'POST') return exchangePairCode(request, ctx);
    if (pathname === '/inbox' && method === 'GET') return pullInbox(request, url, ctx);
    if (pathname === '/inbox/ack' && method === 'POST') return ackEntries(request, ctx);

    return json({ error: 'Not found' }, 404);
  } catch (err) {
    // Never echo request bodies here — they may hold transcript text.
    console.error(`[relay] ${method} ${pathname} failed: ${err.message}`);
    return json({ error: 'Internal error' }, 500);
  }
}

// --- App-facing handlers -----------------------------------------------------

/** POST /inboxes — App Attest required. Returns the inbox secret once. */
async function createInbox(request, ctx) {
  const body = await request.arrayBuffer();
  const attest = await checkAttestation(request, body, ctx);
  if (attest) return attest;

  const id = `inb_${randomToken(12)}`;
  const secret = `${INBOX_SECRET_PREFIX}${randomToken(32)}`;
  await ctx.db
    .prepare('INSERT INTO inboxes (id, secret_hash, created_at) VALUES (?, ?, ?)')
    .bind(id, await sha256Hex(secret), ctx.now)
    .run();

  console.log(`[inbox] created ${id}`);
  return json({ inbox_id: id, inbox_secret: secret }, 201);
}

/**
 * POST /inbox — inbox secret. Fans the transcript out to one
 * queue entry per connected agent. Idempotent on recording_id, so the app's
 * retry queue can resend safely.
 */
async function uploadTranscript(request, ctx) {
  const inbox = await authenticateInbox(request, ctx);
  if (!inbox) return unauthorized();

  const parsed = parseJSON(await request.arrayBuffer());
  if (!parsed) return json({ error: 'Invalid JSON body' }, 400);
  const upload = validateUpload(parsed);
  if (upload.error) return json({ error: upload.error }, 400);

  const { results: connections } = await ctx.db
    .prepare('SELECT id FROM connections WHERE inbox_id = ?')
    .bind(inbox.id)
    .all();

  const expiresAt = ctx.now + retention(ctx.env).unacked * 1000;
  if (connections.length > 0) {
    await ctx.db.batch(
      connections.map((c) =>
        ctx.db
          .prepare(
            `INSERT OR IGNORE INTO entries
               (connection_id, recording_id, recorded_at, duration, text, expires_at)
             VALUES (?, ?, ?, ?, ?, ?)`,
          )
          .bind(c.id, upload.recordingId, upload.createdAt, upload.duration, upload.text, expiresAt),
      ),
    );
  }

  console.log(`[inbox] upload inbox=${inbox.id} connections=${connections.length} chars=${upload.text.length}`);
  return json({ queued: connections.length, expires_at: new Date(expiresAt).toISOString() });
}

/**
 * DELETE /inbox — inbox secret. Deletes every queued transcript for this
 * inbox, or just one connection's with ?connection_id=. No attestation: a
 * "delete everything now" button must always work.
 */
async function purgeInbox(request, url, ctx) {
  const inbox = await authenticateInbox(request, ctx);
  if (!inbox) return unauthorized();

  const connectionId = url.searchParams.get('connection_id');
  const result = connectionId
    ? await ctx.db
        .prepare(
          `DELETE FROM entries WHERE connection_id IN
             (SELECT id FROM connections WHERE id = ? AND inbox_id = ?)`,
        )
        .bind(connectionId, inbox.id)
        .run()
    : await ctx.db
        .prepare(
          `DELETE FROM entries WHERE connection_id IN
             (SELECT id FROM connections WHERE inbox_id = ?)`,
        )
        .bind(inbox.id)
        .run();

  return json({ deleted: result.meta.changes });
}

/** POST /pair/code — inbox secret. Issues a single-use code for one agent. */
async function createPairCode(request, ctx) {
  const inbox = await authenticateInbox(request, ctx);
  if (!inbox) return unauthorized();

  const parsed = parseJSON(await request.arrayBuffer()) ?? {};
  const agentType = parsed.agent_type ?? 'other';
  if (!AGENT_TYPES.includes(agentType)) {
    return json({ error: `agent_type must be one of: ${AGENT_TYPES.join(', ')}` }, 400);
  }

  const count = await ctx.db
    .prepare('SELECT COUNT(*) AS n FROM connections WHERE inbox_id = ?')
    .bind(inbox.id)
    .first();
  if (count.n >= MAX_CONNECTIONS_PER_INBOX) {
    return json({ error: `At most ${MAX_CONNECTIONS_PER_INBOX} agents can be connected` }, 409);
  }

  const code = generatePairCode();
  const expiresAt = ctx.now + PAIR_CODE_TTL_SECONDS * 1000;
  // One live code per inbox: asking for a new one cancels the last.
  await ctx.db.batch([
    ctx.db.prepare('DELETE FROM pair_codes WHERE inbox_id = ?').bind(inbox.id),
    ctx.db
      .prepare('INSERT INTO pair_codes (code_hash, inbox_id, agent_type, expires_at) VALUES (?, ?, ?, ?)')
      .bind(await sha256Hex(normalizePairCode(code)), inbox.id, agentType, expiresAt),
  ]);

  return json({ code, agent_type: agentType, expires_at: new Date(expiresAt).toISOString() }, 201);
}

/** GET /connections — inbox secret. What the app shows under Connected agents. */
async function listConnections(request, ctx) {
  const inbox = await authenticateInbox(request, ctx);
  if (!inbox) return unauthorized();

  const { results } = await ctx.db
    .prepare(
      `SELECT c.id, c.agent_type, c.created_at, c.last_pull_at,
              (SELECT COUNT(*) FROM entries e
                WHERE e.connection_id = c.id AND e.acked_at IS NULL
                  AND e.expires_at > ?) AS pending
         FROM connections c WHERE c.inbox_id = ? ORDER BY c.created_at`,
    )
    .bind(ctx.now, inbox.id)
    .all();

  return json({
    connections: results.map((c) => ({
      id: c.id,
      agent_type: c.agent_type,
      created_at: new Date(c.created_at).toISOString(),
      last_pull_at: c.last_pull_at ? new Date(c.last_pull_at).toISOString() : null,
      pending: c.pending,
    })),
  });
}

/** DELETE /connections/:id — inbox secret. Kills the token and its queue. */
async function revokeConnection(request, connectionId, ctx) {
  const inbox = await authenticateInbox(request, ctx);
  if (!inbox) return unauthorized();

  const [, removed] = await ctx.db.batch([
    ctx.db
      .prepare(
        `DELETE FROM entries WHERE connection_id IN
           (SELECT id FROM connections WHERE id = ? AND inbox_id = ?)`,
      )
      .bind(connectionId, inbox.id),
    ctx.db.prepare('DELETE FROM connections WHERE id = ? AND inbox_id = ?').bind(connectionId, inbox.id),
  ]);

  if (removed.meta.changes === 0) return json({ error: 'Connection not found' }, 404);
  console.log(`[pair] revoked ${connectionId}`);
  return json({ status: 'revoked' });
}

// --- Agent-facing handlers ---------------------------------------------------

/** POST /pair/exchange — no auth; the code is the credential. */
async function exchangePairCode(request, ctx) {
  const parsed = parseJSON(await request.arrayBuffer());
  if (!parsed || typeof parsed.code !== 'string') {
    return json({ error: 'Missing "code"' }, 400);
  }
  const code = normalizePairCode(parsed.code);
  if (code.length !== PAIR_CODE_LENGTH) return invalidCode();

  // Delete-and-return makes the code single-use even under concurrent tries.
  const pairing = await ctx.db
    .prepare('DELETE FROM pair_codes WHERE code_hash = ? RETURNING inbox_id, agent_type, expires_at')
    .bind(await sha256Hex(code))
    .first();
  if (!pairing || pairing.expires_at <= ctx.now) return invalidCode();

  const id = `con_${randomToken(12)}`;
  const token = `${AGENT_TOKEN_PREFIX}${randomToken(32)}`;
  await ctx.db
    .prepare(
      `INSERT INTO connections (id, inbox_id, agent_type, token_hash, created_at)
       VALUES (?, ?, ?, ?, ?)`,
    )
    .bind(id, pairing.inbox_id, pairing.agent_type, await sha256Hex(token), ctx.now)
    .run();

  console.log(`[pair] connected ${id} agent=${pairing.agent_type}`);
  return json(
    {
      token,
      connection_id: id,
      agent_type: pairing.agent_type,
      unacked_retention_seconds: retention(ctx.env).unacked,

    },
    201,
  );
}

/**
 * GET /inbox?since=<id>&limit=<n> — agent token. Oldest first. The relay
 * keeps no cursor: the agent passes back `next_since`. Unacked entries stay
 * until acked or expired, so pulling without `since` is also safe.
 */
async function pullInbox(request, url, ctx) {
  const connection = await authenticateAgent(request, ctx);
  if (!connection) return unauthorized();

  const since = parseNonNegativeInt(url.searchParams.get('since'), 0);
  const limit = Math.min(parseNonNegativeInt(url.searchParams.get('limit'), DEFAULT_PULL_LIMIT) || DEFAULT_PULL_LIMIT, MAX_PULL_LIMIT);

  const [{ results }] = await ctx.db.batch([
    ctx.db
      .prepare(
        `SELECT id, recording_id, recorded_at, duration, text, expires_at
           FROM entries
          WHERE connection_id = ? AND id > ? AND expires_at > ? AND acked_at IS NULL
          ORDER BY id LIMIT ?`,
      )
      .bind(connection.id, since, ctx.now, limit + 1),
    ctx.db.prepare('UPDATE connections SET last_pull_at = ? WHERE id = ?').bind(ctx.now, connection.id),
  ]);

  const hasMore = results.length > limit;
  const page = hasMore ? results.slice(0, limit) : results;
  return json({
    items: page.map(formatEntry),
    next_since: page.length ? page[page.length - 1].id : since,
    has_more: hasMore,
  });
}

/**
 * POST /inbox/ack {"ids": [...]} — agent token. Deletes the transcript text
 * now and leaves a text-free receipt for the phone, which expires after the
 * receipt window. Acking an already-acked id is a no-op.
 */
async function ackEntries(request, ctx) {
  const connection = await authenticateAgent(request, ctx);
  if (!connection) return unauthorized();

  const parsed = parseJSON(await request.arrayBuffer());
  const ids = parsed?.ids;
  if (!Array.isArray(ids) || ids.length === 0 || !ids.every((id) => Number.isSafeInteger(id) && id > 0)) {
    return json({ error: '"ids" must be a non-empty array of entry ids' }, 400);
  }
  if (ids.length > MAX_ACK_IDS) {
    return json({ error: `At most ${MAX_ACK_IDS} ids per ack` }, 400);
  }

  const placeholders = ids.map(() => '?').join(',');
  const result = await ctx.db
    .prepare(
      `UPDATE entries SET acked_at = ?, text = '', expires_at = MIN(expires_at, ?)
        WHERE connection_id = ? AND acked_at IS NULL AND expires_at > ?
          AND id IN (${placeholders})`,
    )
    .bind(ctx.now, ctx.now + retention(ctx.env).receipt * 1000, connection.id, ctx.now, ...ids)
    .run();

  return json({ acknowledged: result.meta.changes });
}

/**
 * GET /receipts — inbox secret. Which recordings each agent has picked up in
 * the last receipt window. The phone uses this to show "Picked up by Muse".
 * Ids and times only; the text was deleted at ack.
 */
async function listReceipts(request, ctx) {
  const inbox = await authenticateInbox(request, ctx);
  if (!inbox) return unauthorized();

  const { results } = await ctx.db
    .prepare(
      `SELECT e.recording_id, e.connection_id, c.agent_type, e.acked_at
         FROM entries e JOIN connections c ON c.id = e.connection_id
        WHERE c.inbox_id = ? AND e.acked_at IS NOT NULL AND e.expires_at > ?
        ORDER BY e.acked_at`,
    )
    .bind(inbox.id, ctx.now)
    .all();

  return json({
    receipts: results.map((r) => ({
      recording_id: r.recording_id,
      connection_id: r.connection_id,
      agent_type: r.agent_type,
      picked_up_at: new Date(r.acked_at).toISOString(),
    })),
  });
}

// --- Expiry ------------------------------------------------------------------

export async function purgeExpired(db, now) {
  const [entries, pairCodes] = await db.batch([
    db.prepare('DELETE FROM entries WHERE expires_at <= ?').bind(now),
    db.prepare('DELETE FROM pair_codes WHERE expires_at <= ?').bind(now),
  ]);
  return { entries: entries.meta.changes, pairCodes: pairCodes.meta.changes };
}

// --- Auth helpers ------------------------------------------------------------

async function checkAttestation(request, body, ctx) {
  const bypass = request.headers.get('X-Dev-Bypass');
  if (bypass && ctx.env.DEV_BYPASS_TOKEN && bypass === ctx.env.DEV_BYPASS_TOKEN) return null;

  const keyId = request.headers.get('X-App-Attest-Key-Id');
  const assertion = request.headers.get('X-App-Attest');
  if (!keyId || !assertion) return json({ error: 'App attestation required' }, 403);

  const result = await ctx.verifyAssertion(keyId, assertion, body, ctx.env);
  if (!result.valid) {
    console.error(`[attest] Assertion failed: ${result.reason}`);
    return json({ error: 'App attestation failed' }, 403);
  }
  return null;
}

async function authenticateInbox(request, ctx) {
  const secret = bearer(request, INBOX_SECRET_PREFIX);
  if (!secret) return null;
  return ctx.db
    .prepare('SELECT id FROM inboxes WHERE secret_hash = ?')
    .bind(await sha256Hex(secret))
    .first();
}

async function authenticateAgent(request, ctx) {
  const token = bearer(request, AGENT_TOKEN_PREFIX);
  if (!token) return null;
  return ctx.db
    .prepare('SELECT id, inbox_id FROM connections WHERE token_hash = ?')
    .bind(await sha256Hex(token))
    .first();
}

function bearer(request, prefix) {
  const header = request.headers.get('Authorization') || '';
  if (!header.startsWith('Bearer ')) return null;
  const value = header.slice(7).trim();
  return value.startsWith(prefix) ? value : null;
}

// --- Pure helpers (exported for tests) ---------------------------------------

/** Validate an upload body; returns normalized fields or `{ error }`. */
export function validateUpload(body) {
  if (!body || typeof body !== 'object') return { error: 'Body must be a JSON object' };
  const { recording_id: recordingId, created_at: createdAt, duration, transcription } = body;

  if (typeof recordingId !== 'string' || !/^[A-Za-z0-9-]{1,64}$/.test(recordingId)) {
    return { error: '"recording_id" must be a UUID string' };
  }
  if (typeof createdAt !== 'string' || Number.isNaN(Date.parse(createdAt))) {
    return { error: '"created_at" must be an ISO 8601 timestamp' };
  }
  if (typeof duration !== 'number' || !Number.isFinite(duration) || duration < 0) {
    return { error: '"duration" must be a non-negative number of seconds' };
  }
  if (typeof transcription !== 'string' || transcription.trim() === '') {
    return { error: '"transcription" must be a non-empty string' };
  }
  if (transcription.length > MAX_TEXT_LENGTH) {
    return { error: `"transcription" exceeds ${MAX_TEXT_LENGTH} characters` };
  }
  return { recordingId, createdAt, duration, text: transcription };
}

/** A fresh code, formatted for display as XXXX-XXXX. */
export function generatePairCode() {
  // Rejection sampling keeps every symbol equally likely.
  const limit = 256 - (256 % PAIR_CODE_ALPHABET.length);
  let chars = '';
  while (chars.length < PAIR_CODE_LENGTH) {
    const bytes = new Uint8Array(PAIR_CODE_LENGTH * 2);
    crypto.getRandomValues(bytes);
    for (const b of bytes) {
      if (b < limit && chars.length < PAIR_CODE_LENGTH) chars += PAIR_CODE_ALPHABET[b % PAIR_CODE_ALPHABET.length];
    }
  }
  return `${chars.slice(0, 4)}-${chars.slice(4)}`;
}

/** Canonical form of a code a person typed or pasted: uppercase, no spaces or dashes. */
export function normalizePairCode(input) {
  return String(input).toUpperCase().replace(/[\s-]/g, '').slice(0, 32);
}

/** Retention windows in seconds, from env vars or the defaults. */
export function retention(env) {
  const read = (value, fallback) => {
    const n = Number(value);
    return Number.isFinite(n) && n > 0 ? n : fallback;
  };
  return {
    unacked: read(env.UNACKED_RETENTION_SECONDS, DEFAULT_UNACKED_RETENTION_SECONDS),
    receipt: read(env.RECEIPT_RETENTION_SECONDS, DEFAULT_RECEIPT_RETENTION_SECONDS),
  };
}

function formatEntry(row) {
  return {
    id: row.id,
    recording_id: row.recording_id,
    created_at: row.recorded_at,
    duration: row.duration,
    transcription: row.text,
    expires_at: new Date(row.expires_at).toISOString(),
  };
}

function parseNonNegativeInt(value, fallback) {
  if (value === null || value === '') return fallback;
  const n = Number(value);
  return Number.isSafeInteger(n) && n >= 0 ? n : fallback;
}

function parseJSON(buffer) {
  try {
    return JSON.parse(new TextDecoder().decode(buffer));
  } catch {
    return null;
  }
}

export function randomToken(byteLength) {
  const bytes = new Uint8Array(byteLength);
  crypto.getRandomValues(bytes);
  let binary = '';
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export async function sha256Hex(value) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, '0')).join('');
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  });
}

function unauthorized() {
  return json({ error: 'Invalid or revoked credentials' }, 401);
}

function invalidCode() {
  return json({ error: 'Invalid or expired pairing code' }, 400);
}
