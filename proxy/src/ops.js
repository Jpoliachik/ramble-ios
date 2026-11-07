// Operator: counted events, threshold alerts with a cooldown, and the daily
// usage summary, all posted to one external webhook (ALERT_WEBHOOK_URL).
// See specs/transcription.md "Operator". Messages never carry transcript
// text or credentials.

import { DAY, HOUR, MINUTE, utcDayStart } from './http.js';

export const ALERT_COOLDOWN_MS = 6 * HOUR;
export const SPEND_ALERT_USD = 5;
const EVENT_RETENTION_MS = 3 * DAY;

// Groq's list price per audio hour, for the spend estimate.
const USD_PER_HOUR = 0.04;

/** Never throws: counting must not break the request it describes. */
export async function recordEvent(ctx, kind, detail = null) {
  try {
    await ctx.db.prepare('INSERT INTO events (at, kind, detail) VALUES (?, ?, ?)').bind(ctx.now, kind, detail).run();
  } catch (err) {
    console.error(`[ops] event ${kind} not recorded: ${err.message}`);
  }
}

/** What a transcription attempt says about Groq (see transcribe.js). */
export async function recordAttempt(ctx, { attempts = [] } = {}) {
  for (const a of attempts ?? []) {
    if (a.status === 429 && a.provider === 'groq') await recordEvent(ctx, 'groq_429');
    if (a.status === 401 || a.status === 403 || /key/i.test(a.outcome ?? '')) {
      await recordEvent(ctx, 'key_problem', a.provider ?? null);
    }
  }
}

/**
 * Sends `message` unless the same alert key went out in the last 6 hours.
 * Returns true when it was sent (or would have been, with no webhook set).
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

const count = async (ctx, sql, ...params) => (await ctx.db.prepare(sql).bind(...params).first())?.n ?? 0;
const eventsSince = (ctx, kind, since) =>
  count(ctx, 'SELECT COUNT(*) AS n FROM events WHERE kind = ? AND at > ?', kind, since);

/** Estimated Groq spend for one UTC day, from the measured length of notes finished that day. */
export async function spendForDay(ctx, dayStart) {
  const row = await ctx.db
    .prepare(
      `SELECT SUM(COALESCE(duration, 0)) AS s FROM notes
        WHERE ready_at >= ? AND ready_at < ? AND provider IS NOT NULL`,
    )
    .bind(dayStart, dayStart + DAY)
    .first();
  return ((row?.s ?? 0) / 3600) * USD_PER_HOUR;
}

/** Every minute. Each alert has its own cooldown key. */
export async function checkAlerts(ctx) {
  const hourAgo = ctx.now - HOUR;

  const groq429 = await eventsSince(ctx, 'groq_429', hourAgo);
  if (groq429 >= 3) await alert(ctx, 'groq_429', `Groq answered 429 ${groq429} times in the last hour.`);

  const { results: keys } = await ctx.db
    .prepare(`SELECT DISTINCT detail FROM events WHERE kind = 'key_problem' AND at > ?`)
    .bind(hourAgo)
    .all();
  for (const k of keys) {
    await alert(ctx, `key:${k.detail}`, `${k.detail ?? 'Groq'} rejected Ramble's API key, or the key is missing.`);
  }

  const stuck = await count(
    ctx,
    `SELECT COUNT(*) AS n FROM notes WHERE status = 'transcribing' AND accepted_at < ?`,
    ctx.now - 5 * MINUTE,
  );
  if (stuck > 0) await alert(ctx, 'stuck', `${stuck} accepted notes have waited more than 5 minutes for a transcript.`);

  const spend = await spendForDay(ctx, utcDayStart(ctx.now));
  if (spend > SPEND_ALERT_USD) await alert(ctx, 'spend', `Estimated transcription spend today is $${spend.toFixed(2)}.`);

  const finished = await ctx.db
    .prepare(
      `SELECT COUNT(*) AS n, SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed
         FROM notes WHERE ready_at > ? AND status IN ('done', 'failed')`,
    )
    .bind(hourAgo)
    .first();
  if (finished.n >= 10 && finished.failed / finished.n > 0.03) {
    await alert(ctx, 'failures', `${finished.failed} of ${finished.n} notes finished in the last hour failed permanently.`);
  }
}

/** Once a day, between 14:00 and 14:05 UTC, a summary of yesterday. */
export async function maybeDailySummary(ctx) {
  const d = new Date(ctx.now);
  if (d.getUTCHours() !== 14 || d.getUTCMinutes() >= 5) return false;
  const end = utcDayStart(ctx.now);
  const start = end - DAY;
  const day = new Date(start).toISOString().slice(0, 10);
  return alert(ctx, `summary:${day}`, await dailySummary(ctx, start, end));
}

export async function dailySummary(ctx, start, end) {
  const day = new Date(start).toISOString().slice(0, 10);
  const accepted = await ctx.db
    .prepare(
      `SELECT COUNT(DISTINCT inbox_id) AS inboxes,
              SUM(CASE WHEN free_note != 0 THEN 1 ELSE 0 END) AS free_notes,
              SUM(CASE WHEN free_note = 0 THEN 1 ELSE 0 END) AS unlocked_notes,
              SUM(CASE WHEN free_note != 0 THEN COALESCE(duration, container_duration, 0) ELSE 0 END) AS free_s,
              SUM(CASE WHEN free_note = 0 THEN COALESCE(duration, container_duration, 0) ELSE 0 END) AS unlocked_s
         FROM notes WHERE accepted_at >= ? AND accepted_at < ?`,
    )
    .bind(start, end)
    .first();
  const unlocks = await count(
    ctx,
    `SELECT COUNT(*) AS n FROM purchases WHERE created_at >= ? AND created_at < ? AND environment = 'Production'`,
    start,
    end,
  );
  const between = (kind) =>
    count(ctx, 'SELECT COUNT(*) AS n FROM events WHERE kind = ? AND at >= ? AND at < ?', kind, start, end);
  const refusedFree = await between('refused_free');
  const refusedSuspended = await between('refused_suspended');

  const transcribed = await count(
    ctx,
    `SELECT COUNT(*) AS n FROM notes
      WHERE ready_at >= ? AND ready_at < ? AND status = 'done' AND provider IS NOT NULL`,
    start,
    end,
  );
  const spend = await spendForDay(ctx, start);
  const outcomes = await ctx.db
    .prepare(
      `SELECT SUM(CASE WHEN result = 'no_speech' THEN 1 ELSE 0 END) AS silent,
              SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed
         FROM notes WHERE ready_at >= ? AND ready_at < ?`,
    )
    .bind(start, end)
    .first();
  const { results: waits } = await ctx.db
    .prepare(
      `SELECT ready_at - accepted_at AS ms FROM notes
        WHERE status = 'done' AND ready_at >= ? AND ready_at < ? ORDER BY ms`,
    )
    .bind(start, end)
    .all();
  const pct = (p) => (waits.length ? waits[Math.min(waits.length - 1, Math.floor(p * waits.length))].ms / 1000 : 0);

  const hours = (s) => ((s ?? 0) / 3600).toFixed(1);
  return [
    `Summary for ${day} (UTC)`,
    `Active inboxes: ${accepted.inboxes ?? 0}`,
    `Notes accepted: ${accepted.free_notes ?? 0} free (${hours(accepted.free_s)} h), ${accepted.unlocked_notes ?? 0} unlocked (${hours(accepted.unlocked_s)} h)`,
    `New unlocks: ${unlocks}. Refused: ${refusedFree} free notes used, ${refusedSuspended} suspended`,
    `Groq: ${transcribed} notes ~$${spend.toFixed(2)}`,
    `No speech: ${outcomes.silent ?? 0}. Permanent failures: ${outcomes.failed ?? 0}`,
    `Upload to transcript: median ${pct(0.5).toFixed(1)} s, p95 ${pct(0.95).toFixed(1)} s`,
  ].join('\n');
}

export async function purgeEvents(ctx) {
  await ctx.db.prepare('DELETE FROM events WHERE at < ?').bind(ctx.now - EVENT_RETENTION_MS).run();
}
