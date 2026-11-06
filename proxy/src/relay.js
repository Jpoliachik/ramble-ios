// Ramble Relay, agent side: pairing, connections, agent copies, pull and ack,
// delivery status, wake-up hooks, and the old builds' text upload.
// See specs/delivery.md and specs/relay-api.md "Agents and pairing".
//
// When a note's transcript is ready, notes.js calls makeAgentCopies: one copy
// per eligible connection, kept until that agent acks it, it is removed, or
// 30 days pass. After that only a small row without the text stays, so the
// phone can tell "picked up" from "removed unread".

import { address, authenticate, countLimit, limit, peekLimit } from './auth.js';
import { DAY, baseURL, fail, iso, json, randomToken, readJSON, sha256Hex, unavailable, UUID_RE } from './http.js';
import { alert } from './ops.js';

export const DEFAULT_RETENTION_SECONDS = 30 * 24 * 60 * 60;
export const PAIR_CODE_TTL_SECONDS = 10 * 60;
export const PAIR_CODE_LENGTH = 12;
// No 0/O, 1/I/L, or U, so codes are easy to read and retype.
export const PAIR_CODE_ALPHABET = '23456789ABCDEFGHJKMNPQRSTVWXYZ';
export const MAX_AGENTS = 10;
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
// Rows of acked or removed copies, kept for delivery status after expiry.
const TOMBSTONE_KEEP_MS = 30 * DAY;

const WAITING = 'e.acked_at IS NULL AND e.removed_at IS NULL AND e.expires_at > ?';

export function retentionSeconds(env) {
  const n = Number(env.RETENTION_SECONDS);
  return Number.isFinite(n) && n > 0 ? n : DEFAULT_RETENTION_SECONDS;
}

// --- Agent copies ------------------------------------------------------------

/**
 * One copy per agent connected now and paired before the note was recorded.
 * Pings hooked agents that got a new copy. Silent notes never get here.
 */
export async function makeAgentCopies(ctx, note) {
  const { results: connections } = await ctx.db
    .prepare(
      `SELECT id, hook_url, hook_headers, hook_pinged_at, last_pull_at FROM connections
        WHERE inbox_id = ? AND created_at < ?`,
    )
    .bind(note.inbox_id, note.recorded_ms)
    .all();
  if (connections.length === 0) return 0;
  return insertCopies(ctx, connections, {
    inboxId: note.inbox_id,
    recordingId: note.id,
    recordedAt: note.recorded_at,
    duration: note.duration ?? 0,
    text: note.transcript,
    receivedAt: note.received_at,
  });
}

async function insertCopies(ctx, connections, item) {
  const expiresAt = ctx.now + retentionSeconds(ctx.env) * 1000;
  const inserted = await ctx.db.batch(
    connections.map((c) =>
      ctx.db
        .prepare(
          `INSERT OR IGNORE INTO entries
             (connection_id, inbox_id, recording_id, recorded_at, duration, text, expires_at, received_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
        )
        .bind(c.id, item.inboxId, item.recordingId, item.recordedAt, item.duration, item.text, expiresAt, item.receivedAt),
    ),
  );
  // Wake hooked agents that got a new copy (a repeat pings no one).
  const toPing = connections.filter((c, i) => inserted[i].meta.changes > 0 && shouldPing(c, ctx.now));
  if (toPing.length > 0) ctx.waitUntil(Promise.all(toPing.map((c) => pingHook(c, ctx))));
  return inserted.filter((r) => r.meta.changes > 0).length;
}

// --- Phone ---------------------------------------------------------------------

/** Old builds: text transcripts in, one copy per connected agent, as before. */
export async function legacyTextUpload(request, ctx) {
  const { cred, response } = await authenticate(request, ctx, ['inbox']);
  if (response) return response;
  const limited = await limit(ctx, ['notes_hour', cred.inboxId], ['notes_day', cred.inboxId]);
  if (limited) return limited;

  const item = validateUpload(await readJSON(request));
  if (item.error) return fail(400, item.error);

  const { results: connections } = await ctx.db
    .prepare('SELECT id, hook_url, hook_headers, hook_pinged_at, last_pull_at FROM connections WHERE inbox_id = ?')
    .bind(cred.inboxId)
    .all();
  if (connections.length > 0) {
    await insertCopies(ctx, connections, {
      inboxId: cred.inboxId,
      recordingId: item.recordingId,
      recordedAt: item.createdAt,
      duration: item.duration,
      text: item.text,
      receivedAt: ctx.now,
    });
  }
  return json({ queued: connections.length });
}

/** Per note: agent copies made, waiting, picked up, removed unread. */
export async function inboxStatus(request, ctx) {
  const { cred, response } = await authenticate(request, ctx, ['inbox']);
  if (response) return response;
  const limited = await limit(ctx, ['reads', cred.hash]);
  if (limited) return limited;

  const ids = (await readJSON(request))?.recording_ids;
  if (
    !Array.isArray(ids) ||
    ids.length === 0 ||
    ids.length > STATUS_LIMIT ||
    !ids.every((id) => typeof id === 'string' && /^[A-Za-z0-9-]{1,64}$/.test(id))
  ) {
    return fail(400, `"recording_ids" must be an array of 1–${STATUS_LIMIT} note IDs`);
  }
  const unique = [...new Set(ids.map((id) => (UUID_RE.test(id) ? id.toUpperCase() : id)))];
  const marks = unique.map(() => '?').join(',');
  const { results: copies } = await ctx.db
    .prepare(
      `SELECT e.recording_id, COUNT(*) AS copies,
              SUM(CASE WHEN ${WAITING} THEN 1 ELSE 0 END) AS waiting,
              SUM(CASE WHEN e.acked_at IS NOT NULL THEN 1 ELSE 0 END) AS picked_up,
              MIN(e.acked_at) AS first_ack
         FROM entries e WHERE e.inbox_id = ? AND e.recording_id IN (${marks}) GROUP BY e.recording_id`,
    )
    .bind(ctx.now, cred.inboxId, ...unique)
    .all();
  const { results: notes } = await ctx.db
    .prepare(`SELECT id FROM notes WHERE inbox_id = ? AND id IN (${marks})`)
    .bind(cred.inboxId, ...unique)
    .all();
  const byId = new Map(copies.map((r) => [r.recording_id, r]));
  const known = new Set([...notes.map((n) => n.id), ...byId.keys()]);

  return json({
    recordings: unique
      .filter((id) => known.has(id))
      .map((id) => {
        const r = byId.get(id) ?? { copies: 0, waiting: 0, picked_up: 0, first_ack: null };
        return {
          recording_id: id,
          copies: r.copies,
          waiting: r.waiting,
          picked_up: r.picked_up,
          removed: r.copies - r.waiting - r.picked_up,
          first_picked_up_at: iso(r.first_ack),
        };
      }),
    missing: unique.filter((id) => !known.has(id)),
  });
}

/** "Delete waiting notes": every agent copy still waiting. Nothing else. */
export async function purgeInbox(request, ctx) {
  const { cred, response } = await authenticate(request, ctx, ['inbox']);
  if (response) return response;
  const result = await ctx.db
    .prepare(`UPDATE entries AS e SET removed_at = ?, text = '' WHERE e.inbox_id = ? AND ${WAITING}`)
    .bind(ctx.now, cred.inboxId, ctx.now)
    .run();
  return json({ deleted: result.meta.changes });
}

/** One live code per inbox: a new one cancels the last. */
export async function createPairCode(request, ctx) {
  const { cred, response } = await authenticate(request, ctx, ['inbox']);
  if (response) return response;
  const limited = await limit(ctx, ['pair_code', cred.inboxId]);
  if (limited) return limited;

  const agents = await ctx.db
    .prepare('SELECT COUNT(*) AS n FROM connections WHERE inbox_id = ?')
    .bind(cred.inboxId)
    .first();
  if (agents.n >= MAX_AGENTS) {
    return fail(409, `${MAX_AGENTS} agents are connected. Disconnect one to connect another.`, 'too_many_agents');
  }

  const code = generatePairCode();
  const expiresAt = ctx.now + PAIR_CODE_TTL_SECONDS * 1000;
  await ctx.db.batch([
    ctx.db.prepare('DELETE FROM pair_codes WHERE inbox_id = ? AND token IS NULL').bind(cred.inboxId),
    ctx.db
      .prepare('INSERT INTO pair_codes (code_hash, inbox_id, expires_at) VALUES (?, ?, ?)')
      .bind(await sha256Hex(normalizePairCode(code)), cred.inboxId, expiresAt),
  ]);
  return json({ code, expires_at: iso(expiresAt) }, 201);
}

export async function listConnections(request, ctx) {
  const { cred, response } = await authenticate(request, ctx, ['inbox']);
  if (response) return response;

  const { results } = await ctx.db
    .prepare(
      `SELECT c.id, c.name, c.created_at, c.last_pull_at, c.hook_url, c.hook_pinged_at, c.hook_status,
              (SELECT COUNT(*) FROM entries e WHERE e.connection_id = c.id AND ${WAITING}) AS pending
         FROM connections c WHERE c.inbox_id = ? ORDER BY c.created_at`,
    )
    .bind(ctx.now, cred.inboxId)
    .all();

  return json({
    connections: results.map((c) => ({
      id: c.id,
      name: c.name ?? null,
      created_at: iso(c.created_at),
      last_pull_at: iso(c.last_pull_at),
      pending: c.pending,
      // The URL and headers stay on the relay; the app only needs to know
      // a hook exists and whether its last ping worked.
      hook: c.hook_url ? { last_ping_at: iso(c.hook_pinged_at), last_status: c.hook_status ?? null } : null,
    })),
  });
}

/** Kills the agent's key, its hook, and every copy waiting for it. */
export async function disconnect(request, connectionId, ctx) {
  const { cred, response } = await authenticate(request, ctx, ['inbox']);
  if (response) return response;

  const [, , removed] = await ctx.db.batch([
    ctx.db
      .prepare(
        `UPDATE entries AS e SET removed_at = ?, text = ''
          WHERE e.connection_id = ? AND e.inbox_id = ? AND e.acked_at IS NULL AND e.removed_at IS NULL`,
      )
      .bind(ctx.now, connectionId, cred.inboxId),
    ctx.db.prepare('DELETE FROM pair_codes WHERE connection_id = ? AND inbox_id = ?').bind(connectionId, cred.inboxId),
    ctx.db.prepare('DELETE FROM connections WHERE id = ? AND inbox_id = ?').bind(connectionId, cred.inboxId),
  ]);
  if (removed.meta.changes === 0) return fail(404, 'Connection not found');
  return json({ status: 'disconnected' });
}

// --- Agent -------------------------------------------------------------------

const INVALID_CODE = 'Invalid or expired pairing code. Ask the user for a new one in the Ramble app.';

/**
 * No credential: the code is the credential. It makes one connection. The new
 * key is kept for the code's 10 minutes encrypted with a key derived from the
 * agent's request_id, so only a retry with the same request_id gets it back.
 */
export async function exchangePairCode(request, ctx) {
  const addr = address(request, ctx);
  if (!(await peekLimit(ctx, 'pair_fail_all', 'all')).ok) {
    await alert(ctx, 'pairing_circuit', 'More than 1,000 failed pairing exchanges this hour: pairing is paused.');
    return unavailable();
  }
  const perAddr = await peekLimit(ctx, 'pair_fail_addr', addr);
  if (!perAddr.ok) return fail(429, 'Too many requests. Try again later.', 'rate_limited', {}, { 'Retry-After': String(Math.ceil(perAddr.retryAfter || 60)) });

  const body = await readJSON(request);
  const code = body?.code;
  const requestId = body?.request_id;
  if (typeof code !== 'string' || !code.trim()) {
    return fail(400, 'Send JSON like {"code": "K7QX-MP4D-2HNV", "request_id": "<16-64 random characters>"} with the code from the Ramble app');
  }
  if (typeof requestId !== 'string' || requestId.length < 16 || requestId.length > 64) {
    return fail(400, '"request_id" must be a random string of 16–64 characters. Reuse it if you retry.');
  }
  // Optional, so the user can tell agents apart. Bad names are dropped.
  const name = cleanName(body?.name);
  const codeHash = await sha256Hex(normalizePairCode(code));
  const requestHash = await sha256Hex(`ramble-request:${requestId}`);

  const failed = async (response) => {
    await countLimit(ctx, 'pair_fail_addr', addr);
    await countLimit(ctx, 'pair_fail_all', 'all');
    return response;
  };

  // Claim the code. The conditional update lets only one exchange win.
  const token = `rmba_${randomToken(32)}`;
  const connectionId = `con_${randomToken(12)}`;
  const claimed = await ctx.db
    .prepare(
      `UPDATE pair_codes SET token = ?, connection_id = ?, request_hash = ?
        WHERE code_hash = ? AND token IS NULL AND expires_at > ?
        RETURNING inbox_id`,
    )
    .bind(await sealWithRequest(token, requestId), connectionId, requestHash, codeHash, ctx.now)
    .first();
  if (claimed) {
    await ctx.db
      .prepare('INSERT INTO connections (id, inbox_id, token_hash, created_at, name) VALUES (?, ?, ?, ?, ?)')
      .bind(connectionId, claimed.inbox_id, await sha256Hex(token), ctx.now, name)
      .run();
    return json({ token }, 201);
  }

  const row = await ctx.db
    .prepare(
      `SELECT p.token, p.request_hash, c.id AS live FROM pair_codes p
         LEFT JOIN connections c ON c.id = p.connection_id
        WHERE p.code_hash = ? AND p.expires_at > ?`,
    )
    .bind(codeHash, ctx.now)
    .first();
  if (!row?.token || !row.live) return failed(fail(400, INVALID_CODE));
  if (row.request_hash !== requestHash) {
    return failed(fail(409, 'This pairing code was already used. Ask the user for a new one.', 'code_used'));
  }
  const replay = await openWithRequest(row.token, requestId);
  if (!replay) return failed(fail(400, INVALID_CODE));
  return json({ token: replay }, 200);
}

async function requestKey(requestId) {
  const raw = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(`ramble-pair-key:${requestId}`));
  return crypto.subtle.importKey('raw', raw, 'AES-GCM', false, ['encrypt', 'decrypt']);
}

async function sealWithRequest(token, requestId) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const data = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, await requestKey(requestId), new TextEncoder().encode(token));
  return `${toB64(iv)}.${toB64(data)}`;
}

async function openWithRequest(sealed, requestId) {
  try {
    const [iv, data] = sealed.split('.');
    const plain = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: fromB64(iv) }, await requestKey(requestId), fromB64(data));
    return new TextDecoder().decode(plain);
  } catch {
    return null;
  }
}

async function agentCred(request, ctx, rule = 'agent') {
  const { cred, response } = await authenticate(request, ctx, ['agent']);
  if (response) return { response };
  const limited = await limit(ctx, [rule, cred.connection.id]);
  if (limited) return { response: limited };
  return { connection: cred.connection };
}

/** Oldest first, up to PULL_LIMIT. Ack what you handled, then pull again. */
export async function pull(request, ctx) {
  const { connection, response } = await agentCred(request, ctx);
  if (response) return response;

  const [{ results }] = await ctx.db.batch([
    ctx.db
      .prepare(
        `SELECT e.id, e.recording_id, e.recorded_at, e.received_at, e.duration, e.text FROM entries e
          WHERE e.connection_id = ? AND ${WAITING} ORDER BY e.id LIMIT ?`,
      )
      .bind(connection.id, ctx.now, PULL_LIMIT + 1),
    ctx.db.prepare('UPDATE connections SET last_pull_at = ? WHERE id = ?').bind(ctx.now, connection.id),
  ]);

  return json({
    items: results.slice(0, PULL_LIMIT).map((row) => ({
      id: row.id,
      recording_id: row.recording_id,
      // As the device sent it: recording start, with its UTC offset.
      created_at: row.recorded_at,
      received_at: iso(row.received_at),
      duration: row.duration,
      transcription: row.text,
    })),
    has_more: results.length > PULL_LIMIT,
  });
}

/** Acked copies lose their text; a small row stays for delivery status. */
export async function ack(request, ctx) {
  const { connection, response } = await agentCred(request, ctx);
  if (response) return response;

  const ids = (await readJSON(request))?.ids;
  if (!Array.isArray(ids) || ids.length === 0 || ids.length > 500 || !ids.every(Number.isSafeInteger)) {
    return fail(400, '"ids" must be an array of 1–500 item ids');
  }
  const result = await ctx.db
    .prepare(
      `UPDATE entries AS e SET acked_at = ?, text = ''
        WHERE e.connection_id = ? AND e.id IN (${ids.map(() => '?').join(',')}) AND ${WAITING}`,
    )
    .bind(ctx.now, connection.id, ...ids, ctx.now)
    .run();
  return json({ deleted: result.meta.changes });
}

/** What the relay knows about this agent. Header values are never echoed. */
export async function getAgent(request, ctx) {
  const { connection, response } = await agentCred(request, ctx);
  if (response) return response;
  return json(await agentView(connection, ctx.env));
}

/**
 * The agent sets its own name and, optionally, a wake-up webhook:
 *   {"name": "Grok Bot", "hook": {"url": "https://…", "headers": {"Authorization": "Bearer …"}}}
 * "hook": null removes it. Setting a hook sends one test ping right away.
 */
export async function updateAgent(request, ctx) {
  const { connection, response } = await agentCred(request, ctx, 'agent_patch');
  if (response) return response;

  const body = await readJSON(request);
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    return fail(400, 'Send JSON like {"name": "My agent", "hook": {"url": "https://…", "headers": {…}}}');
  }

  const updates = [];
  if ('name' in body) {
    const name = cleanName(body.name);
    if (body.name !== null && !name) return fail(400, `"name" must be 1–${MAX_NAME_LENGTH} characters`);
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
      hook = validateHook(body.hook, new URL(baseURL(ctx)).origin);
      if (hook.error) return fail(400, hook.error);
      // Header values are stored only encrypted; no key, no hook.
      if (!ctx.env.HOOK_ENCRYPTION_KEY) return unavailable();
      const headers = await sealHeaders(hook.headers, ctx.env);
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

  if (hook) connection.hook_status = await pingHook(connection, ctx, 'ramble.test');
  return json(await agentView(connection, ctx.env));
}

async function agentView(c, env) {
  return {
    name: c.name ?? null,
    hook: c.hook_url
      ? {
          url: c.hook_url,
          header_names: Object.keys(await openHeaders(c.hook_headers, env)),
          last_ping_at: iso(c.hook_pinged_at),
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
 * One POST, no retries, no redirects, never throws. Carries no transcript
 * text. Sent only when the hostname resolves to public addresses right now.
 * Returns the HTTP status, or 0 if nothing answered.
 */
export async function pingHook(c, ctx, event = 'ramble.notes_waiting') {
  const pullURL = `${baseURL(ctx)}/inbox`;
  const text =
    event === 'ramble.test'
      ? 'Ramble test ping: your wake-up hook works. Nothing new to pick up, no action needed.'
      : `New Ramble notes are waiting. Pull them from ${pullURL} with your Ramble token, handle them, then ack.`;
  let status = 0;
  try {
    // The test ping doesn't count as an unanswered ping: there's nothing to pull.
    if (event !== 'ramble.test') {
      await ctx.db.prepare('UPDATE connections SET hook_pinged_at = ? WHERE id = ?').bind(ctx.now, c.id).run();
    }
    if (await ctx.resolvesPublic(new URL(c.hook_url).hostname, ctx)) {
      const res = await ctx.fetch(c.hook_url, {
        method: 'POST',
        headers: {
          ...(await openHeaders(c.hook_headers, ctx.env)),
          'Content-Type': 'application/json',
          'User-Agent': 'Ramble-Relay/1 (+https://ramble.watch/docs)',
        },
        body: JSON.stringify({ event, text, pull_url: pullURL }),
        redirect: 'manual',
        signal: AbortSignal.timeout(HOOK_TIMEOUT_MS),
      });
      status = res.status;
    }
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

/** DNS over HTTPS: true only when every A/AAAA answer is a public address. */
export async function resolvesPublic(hostname, ctx) {
  const addresses = [];
  for (const type of ['A', 'AAAA']) {
    const res = await ctx.fetch(`https://cloudflare-dns.com/dns-query?name=${encodeURIComponent(hostname)}&type=${type}`, {
      headers: { Accept: 'application/dns-json' },
      signal: AbortSignal.timeout(3000),
    });
    if (!res.ok) return false;
    const data = await res.json();
    for (const answer of data.Answer ?? []) {
      if (answer.type === 1 || answer.type === 28) addresses.push(String(answer.data));
    }
  }
  return addresses.length > 0 && addresses.every(isPublicAddress);
}

export function isPublicAddress(ip) {
  const v4 = ip.match(/^(?:::ffff:)?(\d+)\.(\d+)\.(\d+)\.(\d+)$/i);
  if (v4) {
    const [a, b] = [Number(v4[1]), Number(v4[2])];
    return !(
      a === 0 || a === 10 || a === 127 || a >= 224 ||
      (a === 100 && b >= 64 && b <= 127) ||
      (a === 169 && b === 254) ||
      (a === 172 && b >= 16 && b <= 31) ||
      (a === 192 && b === 168) ||
      (a === 192 && b === 0 && Number(v4[3]) === 0) ||
      (a === 198 && (b === 18 || b === 19))
    );
  }
  const v6 = ip.toLowerCase();
  if (!v6.includes(':')) return false;
  return !(v6 === '::' || v6 === '::1' || /^f[cd]/.test(v6) || /^fe[89ab]/.test(v6) || v6.startsWith('ff') || v6.startsWith('::ffff:'));
}

// Hook headers usually hold a key that starts the agent's runs, so they're
// encrypted at rest (AES-GCM) with HOOK_ENCRYPTION_KEY. Reads still handle
// plain JSON stored before encryption was required.
const SEALED_PREFIX = 'enc:v1:';

async function hookCryptoKey(env) {
  if (!env.HOOK_ENCRYPTION_KEY) return null;
  const raw = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(env.HOOK_ENCRYPTION_KEY));
  return crypto.subtle.importKey('raw', raw, 'AES-GCM', false, ['encrypt', 'decrypt']);
}

const toB64 = (bytes) => btoa(String.fromCharCode(...new Uint8Array(bytes)));
const fromB64 = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));

export async function sealHeaders(headers, env) {
  const plain = JSON.stringify(headers);
  const key = await hookCryptoKey(env);
  if (!key) throw new Error('HOOK_ENCRYPTION_KEY is not set');
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const sealed = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, new TextEncoder().encode(plain));
  return `${SEALED_PREFIX}${toB64(iv)}.${toB64(sealed)}`;
}

/** Never throws: unreadable headers come back empty, and the ping then fails visibly. */
export async function openHeaders(stored, env) {
  if (!stored) return {};
  try {
    if (!stored.startsWith(SEALED_PREFIX)) return JSON.parse(stored);
    const key = await hookCryptoKey(env);
    if (!key) return {};
    const [iv, data] = stored.slice(SEALED_PREFIX.length).split('.');
    const plain = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: fromB64(iv) }, key, fromB64(data));
    return JSON.parse(new TextDecoder().decode(plain));
  } catch {
    return {};
  }
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

/** Expired copies lose their text; old status rows and codes are deleted. */
export async function purgeExpired(db, now) {
  const [entries, , pairCodes] = await db.batch([
    db
      .prepare(
        `UPDATE entries SET removed_at = ?, text = ''
          WHERE acked_at IS NULL AND removed_at IS NULL AND expires_at <= ?`,
      )
      .bind(now, now),
    db.prepare('DELETE FROM entries WHERE expires_at <= ?').bind(now - TOMBSTONE_KEEP_MS),
    db.prepare('DELETE FROM pair_codes WHERE expires_at <= ?').bind(now),
  ]);
  return { entries: entries.meta.changes, pairCodes: pairCodes.meta.changes };
}

// --- Helpers -----------------------------------------------------------------

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

/** Formatted for display as XXXX-XXXX-XXXX. Rejection sampling avoids bias. */
export function generatePairCode() {
  const limitByte = 256 - (256 % PAIR_CODE_ALPHABET.length);
  let chars = '';
  while (chars.length < PAIR_CODE_LENGTH) {
    for (const b of crypto.getRandomValues(new Uint8Array(32))) {
      if (b < limitByte && chars.length < PAIR_CODE_LENGTH) chars += PAIR_CODE_ALPHABET[b % PAIR_CODE_ALPHABET.length];
    }
  }
  return chars.match(/.{4}/g).join('-');
}

/** Codes as typed or pasted: any case, spaces and dashes ignored. */
export function normalizePairCode(input) {
  return String(input).toUpperCase().replace(/[\s-]/g, '').slice(0, 32);
}

