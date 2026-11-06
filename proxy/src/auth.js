// Credentials and rate limits. See specs/relay-api.md "Three credentials"
// and "Rate limits".
//
//   rmbi_  inbox secret   the phone
//   rmbw_  watch token    the watch (a replaced one may only read its notes)
//   rmba_  agent key      an agent

import { DAY, bearerValue, logId, rateLimited, sha256Hex, unauthorized, wrongCredential } from './http.js';

export const WATCH_REPLACED_READ_MS = 30 * DAY;

/**
 * Looks up the caller's credential and checks it may call this endpoint.
 * `allowed` holds kinds: 'inbox', 'watch', 'watch_replaced', 'agent'.
 * Returns { cred } or { response }.
 */
export async function authenticate(request, ctx, allowed) {
  const value = bearerValue(request);
  const cred = await lookup(value, ctx);
  if (!cred) return { response: unauthorized() };
  if (!allowed.includes(cred.kind)) {
    // A replaced watch token is dead except for reading its own notes.
    return { response: cred.kind === 'watch_replaced' ? unauthorized() : wrongCredential() };
  }
  return { cred };
}

async function lookup(value, ctx) {
  if (!/^rmb[iwa]_[A-Za-z0-9_-]{16,}$/.test(value)) return null;
  const hash = await sha256Hex(value);
  if (value.startsWith('rmbi_')) {
    const inbox = await ctx.db.prepare('SELECT id FROM inboxes WHERE secret_hash = ?').bind(hash).first();
    return inbox ? { kind: 'inbox', inboxId: inbox.id, hash } : null;
  }
  if (value.startsWith('rmbw_')) {
    const row = await ctx.db
      .prepare('SELECT inbox_id, replaced_at FROM watch_tokens WHERE token_hash = ?')
      .bind(hash)
      .first();
    if (!row) return null;
    if (row.replaced_at != null) {
      if (ctx.now - row.replaced_at > WATCH_REPLACED_READ_MS) return null;
      return { kind: 'watch_replaced', inboxId: row.inbox_id, hash };
    }
    return { kind: 'watch', inboxId: row.inbox_id, hash };
  }
  const connection = await ctx.db
    .prepare(
      `SELECT id, inbox_id, name, created_at, last_pull_at, hook_url, hook_headers, hook_pinged_at, hook_status
         FROM connections WHERE token_hash = ?`,
    )
    .bind(hash)
    .first();
  return connection ? { kind: 'agent', inboxId: connection.inbox_id, hash, connection } : null;
}

// --- Rate limits --------------------------------------------------------------

// [limit, window seconds] per named rule, from relay-api.md "Rate limits".
export const LIMITS = {
  attest_challenge: [20, 3600],
  attest_register: [5, 86400],
  inboxes_key: [3, 86400],
  inboxes_addr: [20, 3600],
  pair_code: [10, 3600],
  pair_fail_addr: [100, 3600],
  pair_fail_all: [1000, 3600],
  notes_hour: [120, 3600],
  notes_day: [500, 86400],
  reads: [120, 60],
  agent: [60, 60],
  agent_patch: [10, 3600],
  entitlement: [20, 3600],
  settings: [20, 3600],
  watch_token: [10, 86400],
};

/**
 * Counts one call against each rule; the first that is over answers 429.
 * `subjects` pairs a rule name with what it counts (an inbox, a key, an
 * address). Subjects are hashed so the limiter never stores raw addresses or
 * IDs. Throws when the store can't be read (the router answers 503).
 */
export async function limit(ctx, ...pairs) {
  for (const [rule, subject] of pairs) {
    const [max, window] = LIMITS[rule];
    const result = await ctx.rateLimit.hit(ctx.db, `${rule}:${await logId(subject)}`, max, window, ctx.now);
    if (!result.ok) return rateLimited(result.retryAfter);
  }
  return null;
}

/** Reads a rule without counting. Returns the limiter's { ok, retryAfter }. */
export async function peekLimit(ctx, rule, subject) {
  const [max, window] = LIMITS[rule];
  return ctx.rateLimit.peek(ctx.db, `${rule}:${await logId(subject)}`, max, window, ctx.now);
}

export async function countLimit(ctx, rule, subject) {
  const [max, window] = LIMITS[rule];
  return ctx.rateLimit.hit(ctx.db, `${rule}:${await logId(subject)}`, max, window, ctx.now);
}

/** The caller's network address, for limiter keys only. */
export function address(request, ctx) {
  return `addr:${ctx.clientAddress(request)}`;
}
