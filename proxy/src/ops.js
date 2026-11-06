// Operator: counted events, threshold alerts with a cooldown, and the daily
// usage summary, all posted to one external webhook (ALERT_WEBHOOK_URL).
// See specs/transcription.md "Operator". Messages never carry transcript
// text or credentials.

import { DAY, HOUR, MINUTE, utcDayStart, utcMonth } from './http.js';

export const ALERT_COOLDOWN_MS = 6 * HOUR;
export const SPEND_ALERT_USD = 5;
export const FREE_TIER_DAILY_SECONDS = 200 * 3600;
export const FAIR_USE_SECONDS = 100 * 3600;
const EVENT_RETENTION_MS = 3 * DAY;

// Rough list prices per audio hour, for the spend estimate when the
// transcriber's own spend table isn't available.
const USD_PER_HOUR = { groq: 0.04, deepgram: 0.26, openai: 0.36 };

/** Never throws: counting must not break the request it describes. */
export async function recordEvent(ctx, kind, detail = null) {
  try {
    await ctx.db.prepare('INSERT INTO events (at, kind, detail) VALUES (?, ?, ?)').bind(ctx.now, kind, detail).run();
  } catch (err) {
    console.error(`[ops] event ${kind} not recorded: ${err.message}`);
  }
}

/** What a transcription attempt says about the providers (see transcribe.js). */
export async function recordAttempt(ctx, { attempts = [], fallback = false, breakerOpen = false } = {}) {
  for (const a of attempts ?? []) {
    if (a.status === 429 && a.provider === 'groq') await recordEvent(ctx, 'groq_429');
    if (a.status === 401 || a.status === 403 || /key/i.test(a.outcome ?? '')) {
      await recordEvent(ctx, 'key_problem', a.provider ?? null);
    }
  }
  if (fallback) await recordEvent(ctx, 'fallback');
  if (breakerOpen || (attempts ?? []).some((a) => a.outcome === 'breaker_open')) await recordEvent(ctx, 'breaker_open');
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

/** Measured audio from free notes accepted this UTC day (the breaker's count). */
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

/** Estimated spend for one UTC day, from the transcriber's table if it exists. */
export async function spendForDay(ctx, dayStart) {
  const day = new Date(dayStart).toISOString().slice(0, 10);
  try {
    const { results } = await ctx.db
      .prepare('SELECT provider, usd FROM provider_spend WHERE day = ?')
      .bind(day)
      .all();
    return Object.fromEntries(results.map((r) => [r.provider, r.usd]));
  } catch {
    const { results } = await ctx.db
      .prepare(
        `SELECT provider, SUM(COALESCE(duration, 0)) AS s FROM notes
          WHERE ready_at >= ? AND ready_at < ? AND provider IS NOT NULL GROUP BY provider`,
      )
      .bind(dayStart, dayStart + DAY)
      .all();
    return Object.fromEntries(results.map((r) => [r.provider, ((r.s ?? 0) / 3600) * (USD_PER_HOUR[r.provider] ?? 0.4)]));
  }
}

/** Every minute. Each alert has its own cooldown key. */
export async function checkAlerts(ctx) {
  const hourAgo = ctx.now - HOUR;

  const groq429 = await eventsSince(ctx, 'groq_429', hourAgo);
  if (groq429 >= 3) await alert(ctx, 'groq_429', `Groq answered 429 ${groq429} times in the last hour.`);

  const fallbacks = await eventsSince(ctx, 'fallback', hourAgo);
  if (fallbacks > 0) await alert(ctx, 'fallback', `Fallback providers were used ${fallbacks} times in the last hour.`);
  if ((await eventsSince(ctx, 'breaker_open', hourAgo)) > 0) {
    await alert(ctx, 'breaker_open', 'The fallback spend breaker is open: notes Groq cannot take are waiting.');
  }

  const { results: keys } = await ctx.db
    .prepare(`SELECT DISTINCT detail FROM events WHERE kind = 'key_problem' AND at > ?`)
    .bind(hourAgo)
    .all();
  for (const k of keys) {
    await alert(ctx, `key:${k.detail}`, `${k.detail ?? 'A provider'} rejected Ramble's API key, or the key is missing.`);
  }

  const stuck = await count(
    ctx,
    `SELECT COUNT(*) AS n FROM notes WHERE status = 'transcribing' AND accepted_at < ?`,
    ctx.now - 5 * MINUTE,
  );
  if (stuck > 0) await alert(ctx, 'stuck', `${stuck} accepted notes have waited more than 5 minutes for a transcript.`);

  const spend = Object.values(await spendForDay(ctx, utcDayStart(ctx.now))).reduce((a, b) => a + b, 0);
  if (spend > SPEND_ALERT_USD) await alert(ctx, 'spend', `Estimated transcription spend today is $${spend.toFixed(2)}.`);

  const { results: heavy } = await ctx.db
    .prepare('SELECT purchase_id, seconds FROM fair_use WHERE month = ? AND seconds >= ?')
    .bind(utcMonth(ctx.now), FAIR_USE_SECONDS * 0.8)
    .all();
  for (const p of heavy) {
    const hours = (p.seconds / 3600).toFixed(1);
    if (p.seconds >= FAIR_USE_SECONDS) {
      await alert(ctx, `fair_use_100:${p.purchase_id}`, `Purchase ${p.purchase_id} used its fair-use allowance (${hours} h): its notes are held.`);
    } else {
      await alert(ctx, `fair_use_80:${p.purchase_id}`, `Purchase ${p.purchase_id} reached 80% of fair use (${hours} h).`);
    }
  }

  if ((await freeSecondsToday(ctx)) >= FREE_TIER_DAILY_SECONDS) {
    await alert(ctx, 'free_tier_breaker', 'Free inboxes reached 200 hours of audio today: new inboxes are refused until tomorrow (UTC).');
  }

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
  const refusedFairUse = await between('refused_fair_use');
  const fallbacks = await between('fallback');

  const { results: providers } = await ctx.db
    .prepare(
      `SELECT provider, COUNT(*) AS n FROM notes
        WHERE ready_at >= ? AND ready_at < ? AND status = 'done' AND provider IS NOT NULL GROUP BY provider`,
    )
    .bind(start, end)
    .all();
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
  const providerLine =
    providers.map((p) => `${p.provider} ${p.n} notes ~$${(spend[p.provider] ?? 0).toFixed(2)}`).join(', ') || 'none';
  return [
    `Summary for ${day} (UTC)`,
    `Active inboxes: ${accepted.inboxes ?? 0}`,
    `Notes accepted: ${accepted.free_notes ?? 0} free (${hours(accepted.free_s)} h), ${accepted.unlocked_notes ?? 0} unlocked (${hours(accepted.unlocked_s)} h)`,
    `New unlocks: ${unlocks}. Refused: ${refusedFree} free notes used, ${refusedFairUse} fair use`,
    `Providers: ${providerLine}. Fallbacks: ${fallbacks}`,
    `No speech: ${outcomes.silent ?? 0}. Permanent failures: ${outcomes.failed ?? 0}`,
    `Upload to transcript: median ${pct(0.5).toFixed(1)} s, p95 ${pct(0.95).toFixed(1)} s`,
  ].join('\n');
}

export async function purgeEvents(ctx) {
  await ctx.db.prepare('DELETE FROM events WHERE at < ?').bind(ctx.now - EVENT_RETENTION_MS).run();
}
