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

const RELAY_PATHS = /^\/(inboxes|inbox|inbox\/ack|pair\/code|pair\/exchange|connections(\/[^/]+)?)$/;

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
  };
  const { pathname } = new URL(request.url);
  const route = `${request.method} ${pathname.replace(/^\/connections\/.+$/, '/connections/:id')}`;

  try {
    switch (route) {
      // App
      case 'POST /inboxes': return await createInbox(request, ctx);
      case 'POST /inbox': return await upload(request, ctx);
      case 'DELETE /inbox': return await purgeInbox(request, ctx);
      case 'POST /pair/code': return await createPairCode(request, ctx);
      case 'GET /connections': return await listConnections(request, ctx);
      case 'DELETE /connections/:id': return await disconnect(request, pathname.split('/')[2], ctx);
      // Agent
      case 'POST /pair/exchange': return await exchangePairCode(request, ctx);
      case 'GET /inbox': return await pull(request, ctx);
      case 'POST /inbox/ack': return await ack(request, ctx);
      default: return json({ error: 'Not found' }, 404);
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
    .prepare('SELECT id FROM connections WHERE inbox_id = ?')
    .bind(inbox.id)
    .all();
  if (connections.length > 0) {
    const expiresAt = ctx.now + retentionSeconds(ctx.env) * 1000;
    await ctx.db.batch(
      connections.map((c) =>
        ctx.db
          .prepare(
            `INSERT OR IGNORE INTO entries
               (connection_id, recording_id, recorded_at, duration, text, expires_at)
             VALUES (?, ?, ?, ?, ?, ?)`,
          )
          .bind(c.id, item.recordingId, item.createdAt, item.duration, item.text, expiresAt),
      ),
    );
  }
  return json({ queued: connections.length });
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
      `SELECT c.id, c.created_at, c.last_pull_at,
              (SELECT COUNT(*) FROM entries e
                WHERE e.connection_id = c.id AND e.expires_at > ?) AS pending
         FROM connections c WHERE c.inbox_id = ? ORDER BY c.created_at`,
    )
    .bind(ctx.now, inbox.id)
    .all();

  return json({
    connections: results.map((c) => ({
      id: c.id,
      created_at: iso(c.created_at),
      last_pull_at: c.last_pull_at ? iso(c.last_pull_at) : null,
      pending: c.pending,
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

/** No auth: the single-use code is the credential. */
async function exchangePairCode(request, ctx) {
  const body = await readJSON(request);
  if (typeof body?.code !== 'string') return json({ error: 'Missing "code"' }, 400);

  // Delete-and-return makes the code single-use even under concurrent tries.
  const pairing = await ctx.db
    .prepare('DELETE FROM pair_codes WHERE code_hash = ? RETURNING inbox_id, expires_at')
    .bind(await sha256Hex(normalizePairCode(body.code)))
    .first();
  if (!pairing || pairing.expires_at <= ctx.now) {
    return json({ error: 'Invalid or expired pairing code' }, 400);
  }

  const token = `rmba_${randomToken(32)}`;
  await ctx.db
    .prepare('INSERT INTO connections (id, inbox_id, token_hash, created_at) VALUES (?, ?, ?, ?)')
    .bind(`con_${randomToken(12)}`, pairing.inbox_id, await sha256Hex(token), ctx.now)
    .run();
  return json({ token }, 201);
}

/** Oldest first, up to PULL_LIMIT. Ack what you handled, then pull again. */
async function pull(request, ctx) {
  const connection = await authAgent(request, ctx);
  if (!connection) return unauthorized();

  const [{ results }] = await ctx.db.batch([
    ctx.db
      .prepare(
        `SELECT id, recording_id, recorded_at, duration, text FROM entries
          WHERE connection_id = ? AND expires_at > ? ORDER BY id LIMIT ?`,
      )
      .bind(connection.id, ctx.now, PULL_LIMIT + 1),
    ctx.db.prepare('UPDATE connections SET last_pull_at = ? WHERE id = ?').bind(ctx.now, connection.id),
  ]);

  return json({
    items: results.slice(0, PULL_LIMIT).map((row) => ({
      id: row.id,
      recording_id: row.recording_id,
      created_at: row.recorded_at,
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
  return ctx.db.prepare('SELECT id FROM connections WHERE token_hash = ?').bind(await sha256Hex(token)).first();
}

function bearer(request, prefix) {
  const value = (request.headers.get('Authorization') || '').replace(/^Bearer\s+/, '').trim();
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
  return json({ error: 'Invalid or revoked credentials' }, 401);
}
