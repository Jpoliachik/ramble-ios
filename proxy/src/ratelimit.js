// Fixed-window rate limiter backed by D1 (table rate_limits, migration 0006).
//
// A window is [start, start + windowSeconds) on wall-clock boundaries. Each
// (key, window) pair is one row whose primary key is SHA-256(key + window
// start), so keys that contain a network address or credential hash are never
// stored readable. Any database error throws: callers answer 503 and act on
// nothing (fail closed).

import { bytesToHex, sha256 } from './crypto.js';

function windowFor(key, windowSeconds, now) {
  const windowMs = windowSeconds * 1000;
  const start = Math.floor(now / windowMs) * windowMs;
  const end = start + windowMs;
  return { start, end, retryAfter: Math.max(1, Math.ceil((end - now) / 1000)) };
}

async function rowKey(key, start) {
  return bytesToHex(await sha256(`${key}|${start}`));
}

// Counts one hit. key: e.g. 'notes:<inboxHash>:h'. Returns { ok: true } or
// { ok: false, retryAfter } once the window holds more than `limit` hits.
export async function hit(db, key, limit, windowSeconds, now = Date.now()) {
  if (!db) throw new Error('Rate limit store unavailable');
  const w = windowFor(key, windowSeconds, now);
  const row = await db
    .prepare(
      `INSERT INTO rate_limits (key, count, expires_at) VALUES (?, 1, ?)
       ON CONFLICT (key) DO UPDATE SET count = count + 1
       RETURNING count`,
    )
    .bind(await rowKey(key, w.start), w.end)
    .first();
  if (!row || typeof row.count !== 'number') throw new Error('Rate limit store returned no count');
  return row.count <= limit ? { ok: true } : { ok: false, retryAfter: w.retryAfter };
}

// Reads without counting, for "failed attempts" limits checked before acting
// (call hit() on each failure). { ok: false } once `limit` hits are recorded.
export async function peek(db, key, limit, windowSeconds, now = Date.now()) {
  if (!db) throw new Error('Rate limit store unavailable');
  const w = windowFor(key, windowSeconds, now);
  const row = await db
    .prepare('SELECT count FROM rate_limits WHERE key = ?')
    .bind(await rowKey(key, w.start))
    .first();
  const count = row ? row.count : 0;
  return count < limit ? { ok: true } : { ok: false, retryAfter: w.retryAfter };
}

// Deletes counters whose window has ended. For the cron. Returns rows deleted.
export async function purgeRateLimits(db, now = Date.now()) {
  const result = await db.prepare('DELETE FROM rate_limits WHERE expires_at <= ?').bind(now).run();
  return result.meta?.changes ?? 0;
}

// Network address for limiter keys only (CF-Connecting-IP). Never store or log it.
export function clientAddress(request) {
  return request.headers.get('CF-Connecting-IP') || 'unknown';
}
