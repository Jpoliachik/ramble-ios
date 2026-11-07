// Operator alerts, posted to one external webhook (ALERT_WEBHOOK_URL), each
// with a 6-hour cooldown per alert key. See specs/transcription.md "Operator".
// Messages never carry transcript text or credentials. Everything else is in
// Cloudflare's logs.

import { HOUR, MINUTE, utcDayStart } from './http.js';

export const ALERT_COOLDOWN_MS = 6 * HOUR;
export const STUCK_AFTER_MS = 30 * MINUTE;
export const FREE_TIER_DAILY_SECONDS = 200 * 3600;

/**
 * Sends `message` unless the same alert key went out in the last 6 hours.
 * Returns true when it was sent (or would have been, with no webhook set).
 * Never throws.
 */
export async function alert(ctx, key, message) {
  try {
    const claimed = await ctx.db
      .prepare(
        `INSERT INTO alerts (key, sent_at) VALUES (?, ?)
           ON CONFLICT (key) DO UPDATE SET sent_at = excluded.sent_at WHERE alerts.sent_at <= ?
         RETURNING key`,
      )
      .bind(key, ctx.now, ctx.now - ALERT_COOLDOWN_MS)
      .first();
    if (!claimed) return false;
    await post(ctx, message);
    return true;
  } catch (err) {
    console.error(`[ops] alert ${key} failed: ${err.message}`);
    return false;
  }
}

async function post(ctx, message) {
  const url = ctx.env.ALERT_WEBHOOK_URL;
  if (!url) return;
  try {
    await ctx.fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'text/plain; charset=utf-8' },
      body: `Ramble relay: ${message}`,
      signal: AbortSignal.timeout(5000),
    });
  } catch (err) {
    console.error(`[ops] alert webhook failed: ${err.message}`);
  }
}

/** A failed attempt whose Groq key was rejected or missing (attempts from transcribe.js). */
export async function alertKeyProblem(ctx, attempts) {
  const bad = (attempts ?? []).find((a) => a.outcome === 'key_rejected' || a.outcome === 'key_missing');
  if (!bad) return;
  await alert(ctx, `key:${bad.provider ?? 'groq'}`, `${bad.provider ?? 'groq'} rejected Ramble's API key, or the key is missing.`);
}

/** A note failed for good. */
export async function alertPermanentFailure(ctx, result, error) {
  await alert(ctx, `failed:${result}`, `A note failed permanently (${result}): ${String(error ?? '').slice(0, 120)}`);
}

/** Cron, every minute: notes still transcribing 30 minutes after they were accepted. */
export async function checkAlerts(ctx) {
  const row = await ctx.db
    .prepare(`SELECT COUNT(*) AS n FROM notes WHERE status = 'transcribing' AND accepted_at < ?`)
    .bind(ctx.now - STUCK_AFTER_MS)
    .first();
  const stuck = row?.n ?? 0;
  if (stuck > 0) await alert(ctx, 'stuck', `${stuck} accepted notes have waited more than 30 minutes for a transcript.`);
}

/** Measured audio from free notes accepted this UTC day (account.js's free-tier breaker). */
export async function freeSecondsToday(ctx) {
  const row = await ctx.db
    .prepare(
      `SELECT COALESCE(SUM(COALESCE(duration, container_duration, 0)), 0) AS s FROM notes
        WHERE free_note != 0 AND accepted_at >= ?`,
    )
    .bind(utcDayStart(ctx.now))
    .first();
  return row?.s ?? 0;
}
