// Operator alerts, sent as Telegram messages from the operator's bot
// (TELEGRAM_BOT_TOKEN to TELEGRAM_CHAT_ID), each
// with a 6-hour cooldown per alert key. See specs/transcription.md "Operator".
// Messages never carry transcript text or credentials. Everything else is in
// Cloudflare's logs.

import { HOUR, MINUTE } from './http.js';

export const ALERT_COOLDOWN_MS = 6 * HOUR;
export const STUCK_AFTER_MS = 30 * MINUTE;
export const ERROR_WINDOW_MS = 10 * MINUTE;
export const ERROR_SPIKE = 20;

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
  const token = ctx.env.TELEGRAM_BOT_TOKEN;
  const chatId = ctx.env.TELEGRAM_CHAT_ID;
  if (!token || !chatId) return;
  try {
    // Telegram Bot API sendMessage. The URL carries the token, so never log it.
    const res = await ctx.fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ chat_id: chatId, text: `Ramble relay: ${message}` }),
      signal: AbortSignal.timeout(5000),
    });
    if (!res.ok) console.error(`[ops] telegram alert failed: HTTP ${res.status}`);
  } catch (err) {
    console.error(`[ops] telegram alert failed: ${err.name}`);
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

/** A request failed with a server error (503 from a thrown handler). Never throws. */
export async function recordServerError(ctx) {
  try {
    await ctx.db
      .prepare(`INSERT INTO error_counts (minute, n) VALUES (?, 1) ON CONFLICT (minute) DO UPDATE SET n = n + 1`)
      .bind(Math.floor(ctx.now / MINUTE))
      .run();
  } catch {
    // The database may be what is failing; the log line already went out.
  }
}

/**
 * Cron, every minute: notes still transcribing 30 minutes after they were
 * accepted, and a spike of server errors in the last 10 minutes.
 */
export async function checkAlerts(ctx) {
  const since = Math.floor((ctx.now - ERROR_WINDOW_MS) / MINUTE);
  const errors = await ctx.db.prepare(`SELECT COALESCE(SUM(n), 0) AS n FROM error_counts WHERE minute > ?`).bind(since).first();
  const failed = errors?.n ?? 0;
  if (failed >= ERROR_SPIKE) await alert(ctx, 'errors', `${failed} requests failed with a server error in the last 10 minutes. See the Worker's logs.`);
  await ctx.db.prepare(`DELETE FROM error_counts WHERE minute < ?`).bind(Math.floor((ctx.now - HOUR) / MINUTE)).run();

  const row = await ctx.db
    .prepare(`SELECT COUNT(*) AS n FROM notes WHERE status = 'transcribing' AND accepted_at < ?`)
    .bind(ctx.now - STUCK_AFTER_MS)
    .first();
  const stuck = row?.n ?? 0;
  if (stuck > 0) await alert(ctx, 'stuck', `${stuck} accepted notes have waited more than 30 minutes for a transcript.`);
}
