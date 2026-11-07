// Notes: audio uploads, the transcription pipeline, and the copy of each
// transcript kept for the person's own devices.
// See specs/relay-api.md "Notes" and specs/transcription.md.
//
// Upload: auth -> repeat? (200, before the body is read) -> checks
// -> suspended? (403) -> held? (402) -> read body -> measure -> store in R2 ->
// create the note and count it in one batch (conditional, so concurrent
// uploads count once) -> transcribe in the background, waiting up to 8
// seconds to answer "done".
// The cron sweeper (every minute) runs retries and picks up lost attempts.

import { FREE_NOTES, loadAccount, recordUsage, suspendedResponse, usageUser } from './account.js';
import { authenticate } from './auth.js';
import {
  DAY,
  HOUR,
  MINUTE,
  UUID_RE,
  fail,
  iso,
  json,
  logId,
  randomToken,
  readJSON,
  unavailable,
  withTimeout,
} from './http.js';
import { alertKeyProblem, alertPermanentFailure } from './ops.js';
import { makeAgentCopies } from './relay.js';
import { INLINE_PROVIDER_TIMEOUT_MS, TranscribeError } from './transcribe.js';

export const AUDIO_TYPES = new Set(['audio/mp4', 'audio/m4a', 'audio/x-m4a', 'audio/aac']);
export const MAX_UPLOAD_BYTES = 20 * 1024 * 1024;
export const MAX_SECONDS = 61 * 60;
export const FUTURE_SLACK_MS = 5 * MINUTE;
export const BODY_TIMEOUT_MS = 30 * MINUTE;
export const INLINE_WAIT_MS = 8000;
export const ATTEMPT_LOST_MS = 8 * MINUTE;
// The first attempt (made on upload, attempts = 1) is lost sooner: it fits the
// Worker's waitUntil budget, so one still running after a minute was cut off.
export const INLINE_ATTEMPT_LOST_MS = MINUTE;
export const RETRY_WINDOW_MS = 20 * HOUR;
export const BACKOFF_MINUTES = [1, 2, 5, 10, 15, 30];
export const MAX_HAND_RETRIES = 3;
export const DEVICE_COPY_MS = 30 * DAY;
export const CLEARED_KEEP_MS = 30 * DAY;
export const AUDIO_MAX_AGE_MS = DAY;
export const NOTES_PAGE = 50;
const SWEEP_BATCH = 20;
const RECORDED_AT_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})$/i;

// --- Views and visibility ---------------------------------------------------------

const isFinal = (n) => n.status === 'done' || n.status === 'failed';

function isCleared(n, now) {
  return n.transcript_cleared_at != null || (n.ready_at != null && n.ready_at <= now - DEVICE_COPY_MS);
}

/** Past the 30 days a cleared note still reads: gone. */
function isExpired(n, now) {
  if (n.transcript_cleared_at != null) return n.transcript_cleared_at <= now - CLEARED_KEEP_MS;
  return n.ready_at != null && n.ready_at <= now - DEVICE_COPY_MS - CLEARED_KEEP_MS;
}

export function noteView(n, now) {
  const cleared = isCleared(n, now);
  return {
    id: n.id,
    source: n.source,
    status: n.status,
    result: n.result ?? null,
    recorded_at: n.recorded_at,
    received_at: iso(n.received_at),
    duration: n.status === 'done' ? n.duration : null,
    transcript: !cleared && n.status === 'done' ? (n.transcript ?? '') : null,
    transcript_cleared: cleared,
  };
}

/** The phone sees its inbox; a watch token sees watch notes, or once replaced only its own. */
function canSee(cred, n) {
  if (cred.kind === 'inbox') return true;
  if (cred.kind === 'watch') return n.source === 'watch';
  return n.watch_token_hash === cred.hash;
}

const readNote = (ctx, inboxId, id) =>
  ctx.db.prepare('SELECT * FROM notes WHERE inbox_id = ? AND id = ?').bind(inboxId, id).first();

/** The device copy goes once the phone acked and, for a watch note, the watch has it. */
async function clearDelivered(ctx, inboxId, ids) {
  await ctx.db
    .prepare(
      `UPDATE notes SET transcript = NULL, transcript_cleared_at = ?
        WHERE inbox_id = ? AND id IN (${ids.map(() => '?').join(',')}) AND transcript_cleared_at IS NULL
          AND phone_acked_at IS NOT NULL AND (source != 'watch' OR watch_received_at IS NOT NULL)`,
    )
    .bind(ctx.now, inboxId, ...ids)
    .run();
}

/** Call after building the response, so this read still carries the transcript. */
async function noteWatchSaw(ctx, cred, n) {
  if (cred.kind === 'inbox' || !isFinal(n) || n.watch_received_at != null) return;
  await ctx.db
    .prepare('UPDATE notes SET watch_received_at = ? WHERE inbox_id = ? AND id = ? AND watch_received_at IS NULL')
    .bind(ctx.now, n.inbox_id, n.id)
    .run();
  await clearDelivered(ctx, n.inbox_id, [n.id]);
}

async function answerWithNote(ctx, cred, n, status) {
  const view = noteView(n, ctx.now);
  await noteWatchSaw(ctx, cred, n);
  return json(view, status);
}

// --- Upload --------------------------------------------------------------------------

const badUpload = (error) => fail(400, error, 'bad_upload');

function holdFor(account) {
  if (account.suspended) return suspendedResponse();
  if (account.unlocked || account.freeRemaining > 0) return null;
  return freeNotesUsed();
}

const freeNotesUsed = () =>
  fail(402, 'All 25 free notes are used. Unlock Ramble to transcribe this note.', 'free_notes_used', {
    free_notes_remaining: 0,
  });

export async function uploadNote(request, rawId, ctx) {
  const { cred, response } = await authenticate(request, ctx, ['inbox', 'watch']);
  if (response) return response;
  if (!UUID_RE.test(rawId)) return badUpload('The note ID in the path must be a UUID.');
  if (!ctx.env.AUDIO) return unavailable();
  const id = rawId.toUpperCase();
  const inboxId = cred.inboxId;

  // Repeats are answered before the body is read, and count for nothing.
  let existing = await readNote(ctx, inboxId, id);
  if (existing && isExpired(existing, ctx.now)) {
    await ctx.db.prepare('DELETE FROM notes WHERE inbox_id = ? AND id = ?').bind(inboxId, id).run();
    existing = null;
  }
  const retry = !!existing && cred.kind === 'inbox' && request.headers.get('X-Ramble-Retry') === '1' && existing.status === 'failed';
  if (existing && !retry) {
    if (!canSee(cred, existing)) return fail(409, 'This note ID is already in use.', 'id_in_use');
    return answerWithNote(ctx, cred, existing, 200);
  }
  if (retry && existing.retry_count >= MAX_HAND_RETRIES) {
    return fail(409, 'This note was already retried 3 times.', 'retry_limit');
  }

  // Refusals: nothing stored or counted.
  const lengthHeader = request.headers.get('Content-Length');
  if (lengthHeader == null) return fail(411, 'Send a Content-Length header.', 'length_required');
  const length = Number(lengthHeader);
  if (!/^\d+$/.test(lengthHeader.trim()) || !Number.isSafeInteger(length)) return badUpload('Invalid Content-Length.');
  if (length > MAX_UPLOAD_BYTES) return fail(413, 'Recordings must be at most 20 MB.', 'too_large');
  const contentType = (request.headers.get('Content-Type') || '').split(';')[0].trim().toLowerCase();
  if (!AUDIO_TYPES.has(contentType)) {
    return fail(415, 'Send the recording as audio/mp4, audio/m4a, audio/x-m4a or audio/aac.', 'unsupported_type');
  }
  if (length === 0) return badUpload('The recording is empty.');
  const recordedAt = existing?.recorded_at ?? request.headers.get('X-Ramble-Recorded-At') ?? '';
  const recordedMs = Date.parse(recordedAt);
  if (!RECORDED_AT_RE.test(recordedAt) || Number.isNaN(recordedMs)) {
    return badUpload('Send X-Ramble-Recorded-At as an ISO 8601 time with its UTC offset.');
  }
  if (!existing && recordedMs > ctx.now + FUTURE_SLACK_MS) {
    return fail(400, "The recorded time is in the future. Retry once the device's clock has passed it.", 'recorded_in_future');
  }

  const account = await loadAccount(ctx, inboxId);
  const hold = holdFor(account);
  if (hold) return hold;

  let bytes;
  try {
    const body = await withTimeout(request.arrayBuffer(), ctx.bodyTimeoutMs, null);
    if (body === null) return fail(408, 'The upload took too long. Try again.', 'upload_timeout');
    bytes = new Uint8Array(body);
  } catch {
    return badUpload('The upload broke off.');
  }
  if (bytes.byteLength !== length) return badUpload("The body doesn't match its Content-Length.");
  const seconds = ctx.measureDuration(bytes);
  if (seconds != null && seconds > MAX_SECONDS) return fail(413, 'Recordings must be at most 60 minutes.', 'too_long');

  // Store first: a note exists only once its audio does.
  const audioKey = `audio/${randomToken(18)}`;
  try {
    await ctx.env.AUDIO.put(audioKey, bytes, { httpMetadata: { contentType } });
  } catch (err) {
    console.error(`[notes] audio store failed inbox=${await logId(inboxId)}: ${err.message}`);
    return unavailable();
  }

  // Accepted now, after the (possibly long) body arrived.
  ctx = { ...ctx, now: ctx.clock() };
  const accepted = await acceptNote(ctx, {
    cred, id, retry, account, contentType, seconds, audioKey, recordedAt, recordedMs,
  });
  if (accepted.response) {
    await ctx.env.AUDIO.delete(audioKey).catch(() => {});
    return accepted.response;
  }

  // Transcription continues if the client goes away, within the Worker's
  // waitUntil budget: a short Groq timeout, and a short lease (attempt 1).
  const inline = {
    ...ctx,
    transcribeDeps: { ...ctx.transcribeDeps, timeoutMs: INLINE_PROVIDER_TIMEOUT_MS },
  };
  const attempt = runAttempt(inline, accepted.note);
  ctx.waitUntil(attempt);
  await withTimeout(attempt, ctx.inlineWaitMs, null);
  const fresh = await readNote(ctx, inboxId, id);
  return answerWithNote({ ...ctx, now: ctx.clock() }, cred, fresh, 201);
}

/**
 * Creates (or, for a hand retry, resets) the note and counts it, in one
 * batch. Every statement after the first is conditioned on the note holding
 * this upload's audio key, so a lost race changes nothing.
 */
async function acceptNote(ctx, u) {
  const { db, now } = ctx;
  const inboxId = u.cred.inboxId;
  const free = !u.account.unlocked;
  // Free notes are claimed in SQL, so two devices can't both take the last one.
  const freeSQL = free ? `(SELECT free_notes_used FROM inboxes WHERE id = ?) < ${FREE_NOTES}` : '1';
  const freeParams = free ? [inboxId] : [];
  const mine = 'EXISTS (SELECT 1 FROM notes WHERE inbox_id = ? AND id = ? AND audio_key = ?)';
  const mineParams = [inboxId, u.id, u.audioKey];

  const statements = [
    u.retry
      ? db
          .prepare(
            `UPDATE notes SET status = 'transcribing', result = NULL, transcript = NULL, duration = NULL,
                provider = NULL, model = NULL, ready_at = NULL, transcript_cleared_at = NULL, phone_acked_at = NULL,
                watch_received_at = NULL, retry_count = retry_count + 1, attempts = 1, attempt_started_at = ?,
                next_attempt_at = NULL, options = NULL, accepted_at = ?, content_type = ?, container_duration = ?,
                audio_key = ?, audio_stored_at = ?, free_note = ?, last_error = NULL
              WHERE inbox_id = ? AND id = ? AND status = 'failed' AND retry_count < ? AND ${freeSQL}`,
          )
          .bind(now, now, u.contentType, u.seconds, u.audioKey, now, free ? 1 : 0,
            inboxId, u.id, MAX_HAND_RETRIES, ...freeParams)
      : db
          .prepare(
            `INSERT INTO notes (inbox_id, id, source, watch_token_hash, status, recorded_at, recorded_ms, received_at,
                accepted_at, content_type, container_duration, attempts, attempt_started_at, audio_key, audio_stored_at,
                free_note)
             SELECT ?, ?, ?, ?, 'transcribing', ?, ?, ?, ?, ?, ?, 1, ?, ?, ?, ? WHERE ${freeSQL}
             ON CONFLICT (inbox_id, id) DO NOTHING`,
          )
          .bind(inboxId, u.id, u.cred.kind === 'inbox' ? 'phone' : 'watch', u.cred.kind === 'inbox' ? null : u.cred.hash,
            u.recordedAt, u.recordedMs, now, now, u.contentType, u.seconds, now, u.audioKey, now, free ? 1 : 0,
            ...freeParams),
    db
      .prepare(
        `UPDATE inboxes SET free_notes_used = free_notes_used + ?, last_upload_at = ? WHERE id = ? AND ${mine}`,
      )
      .bind(free ? 1 : 0, now, inboxId, ...mineParams),
  ];
  await db.batch(statements);

  const note = await readNote(ctx, inboxId, u.id);
  if (note?.audio_key === u.audioKey) {
    console.log(`[notes] accepted ${u.retry ? 'retry' : 'note'} inbox=${await logId(inboxId)} free=${free}`);
    return { note };
  }
  // Lost a race: another upload of this note won, or the free notes ran out.
  if (note && (!u.retry || note.status !== 'failed')) {
    if (!canSee(u.cred, note)) return { response: fail(409, 'This note ID is already in use.', 'id_in_use') };
    return { response: await answerWithNote(ctx, u.cred, note, 200) };
  }
  if (u.retry && note && note.retry_count >= MAX_HAND_RETRIES) {
    return { response: fail(409, 'This note was already retried 3 times.', 'retry_limit') };
  }
  return { response: freeNotesUsed() };
}

// --- Reading -------------------------------------------------------------------------

export async function getNote(request, rawId, ctx) {
  const { cred, response } = await authenticate(request, ctx, ['inbox', 'watch', 'watch_replaced']);
  if (response) return response;
  const notFound = () => fail(404, 'Note not found');
  if (!UUID_RE.test(rawId)) return notFound();
  const n = await readNote(ctx, cred.inboxId, rawId.toUpperCase());
  if (!n || isExpired(n, ctx.now) || !canSee(cred, n)) return notFound();
  return answerWithNote(ctx, cred, n, 200);
}

/** Every note the phone hasn't acked, oldest accepted first. */
export async function listNotes(request, ctx) {
  const { cred, response } = await authenticate(request, ctx, ['inbox']);
  if (response) return response;

  const after = new URL(request.url).searchParams.get('after');
  let afterAt = -1;
  let afterId = '';
  if (after) {
    const m = after.match(/^(\d+)_([0-9A-F-]{36})$/);
    if (!m) return fail(400, '"after" must be a cursor from a previous page.');
    afterAt = Number(m[1]);
    afterId = m[2];
  }
  const { results } = await ctx.db
    .prepare(
      `SELECT * FROM notes WHERE inbox_id = ? AND phone_acked_at IS NULL
          AND (accepted_at > ? OR (accepted_at = ? AND id > ?))
        ORDER BY accepted_at, id LIMIT ?`,
    )
    .bind(cred.inboxId, afterAt, afterAt, afterId, NOTES_PAGE + 1)
    .all();
  const page = results.slice(0, NOTES_PAGE);
  const last = page[page.length - 1];
  return json({
    notes: page.filter((n) => !isExpired(n, ctx.now)).map((n) => noteView(n, ctx.now)),
    next: results.length > NOTES_PAGE ? `${last.accepted_at}_${last.id}` : null,
  });
}

export async function ackNotes(request, ctx) {
  const { cred, response } = await authenticate(request, ctx, ['inbox']);
  if (response) return response;

  const ids = (await readJSON(request))?.ids;
  if (!Array.isArray(ids) || ids.length === 0 || ids.length > 500 || !ids.every((id) => typeof id === 'string' && UUID_RE.test(id))) {
    return fail(400, '"ids" must be an array of 1–500 note IDs');
  }
  const unique = [...new Set(ids.map((id) => id.toUpperCase()))];
  const marks = unique.map(() => '?').join(',');
  const acked = await ctx.db
    .prepare(
      `UPDATE notes SET phone_acked_at = ?
        WHERE inbox_id = ? AND id IN (${marks}) AND status IN ('done', 'failed') AND phone_acked_at IS NULL`,
    )
    .bind(ctx.now, cred.inboxId, ...unique)
    .run();
  const { results: notFinal } = await ctx.db
    .prepare(`SELECT id FROM notes WHERE inbox_id = ? AND id IN (${marks}) AND status = 'transcribing'`)
    .bind(cred.inboxId, ...unique)
    .all();
  await clearDelivered(ctx, cred.inboxId, unique);
  return json({ acked: acked.meta.changes, not_final: notFinal.map((n) => n.id) });
}

// --- Transcription pipeline -------------------------------------------------------------

/** Runs one claimed attempt. Never rejects. */
export async function runAttempt(ctx, note) {
  try {
    await attempt(ctx, note);
  } catch (err) {
    console.error(`[notes] attempt crashed inbox=${await logId(note.inbox_id)}: ${String(err?.message).slice(0, 200)}`);
  }
}

async function attempt(ctx, note) {
  if (ctx.clock() > note.accepted_at + RETRY_WINDOW_MS) {
    return finishFailed({ ...ctx, now: ctx.clock() }, note, 'retries_exhausted', 'retry window ended');
  }
  // Options are fixed when a note's first attempt starts.
  let options = note.options ? JSON.parse(note.options) : null;
  if (!options) {
    const s = await ctx.db
      .prepare('SELECT language, remove_filler_words, vocabulary FROM inboxes WHERE id = ?')
      .bind(note.inbox_id)
      .first();
    options = { language: s?.language ?? null, removeFillerWords: !!s?.remove_filler_words, vocabulary: s?.vocabulary ?? '' };
    await ctx.db
      .prepare('UPDATE notes SET options = ? WHERE inbox_id = ? AND id = ? AND options IS NULL')
      .bind(JSON.stringify(options), note.inbox_id, note.id)
      .run();
  }

  const object = note.audio_key ? await ctx.env.AUDIO.get(note.audio_key) : null;
  if (!object) return finishFailed({ ...ctx, now: ctx.clock() }, note, 'retries_exhausted', 'audio missing');
  const audio = await object.arrayBuffer();

  let out;
  try {
    out = await ctx.transcribe(
      audio,
      { contentType: note.content_type, ...options, durationSeconds: note.container_duration ?? null },
      ctx.env,
      ctx.transcribeDeps,
    );
  } catch (err) {
    const actx = { ...ctx, now: ctx.clock() };
    await alertKeyProblem(actx, err?.attempts);
    const message = String(err?.message ?? err).slice(0, 200);
    console.error(`[notes] attempt failed inbox=${await logId(note.inbox_id)} provider=${err?.provider ?? '-'} status=${err?.status ?? '-'}: ${message}`);
    if (err instanceof TranscribeError && err.retryable === false) {
      return finishFailed(actx, note, 'audio_rejected', message);
    }
    return scheduleRetry(actx, note, message);
  }
  return finishDone({ ...ctx, now: ctx.clock() }, note, out);
}

async function finishDone(ctx, note, out) {
  const result = out.result === 'no_speech' ? 'no_speech' : 'transcript';
  const text = result === 'transcript' ? String(out.text ?? '') : '';
  const duration = out.durationSeconds ?? note.container_duration ?? 0;
  // First result wins; one from an earlier round of retries is dropped.
  const done = await ctx.db
    .prepare(
      `UPDATE notes SET status = 'done', result = ?, transcript = ?, duration = ?, provider = ?, model = ?,
              ready_at = ?, attempt_started_at = NULL, next_attempt_at = NULL, last_error = NULL
        WHERE inbox_id = ? AND id = ? AND status = 'transcribing' AND retry_count = ?
        RETURNING *`,
    )
    .bind(result, text, duration, out.provider ?? null, out.model ?? null, ctx.now, note.inbox_id, note.id, note.retry_count)
    .first();
  if (!done) return;
  // Agents first: if a later step fails or the Worker stops, the sweeper
  // makes any copies not yet marked made. Silent notes go nowhere.
  if (result === 'transcript') await copyToAgents(ctx, done);

  // Monitoring: the measured length counts once, when the note is done.
  await recordUsage(ctx, await usageUser(ctx, note.inbox_id), duration);
  await deleteAudio(ctx, done);
}

/** Makes a done note's agent copies (idempotent), then marks them made. Never rejects. */
async function copyToAgents(ctx, note) {
  try {
    await makeAgentCopies(ctx, note);
    await ctx.db
      .prepare('UPDATE notes SET copies_made_at = ? WHERE inbox_id = ? AND id = ? AND copies_made_at IS NULL')
      .bind(ctx.now, note.inbox_id, note.id)
      .run();
  } catch (err) {
    console.error(`[notes] agent copies failed inbox=${await logId(note.inbox_id)}: ${String(err?.message).slice(0, 200)}`);
  }
}

async function finishFailed(ctx, note, result, error) {
  const failed = await ctx.db
    .prepare(
      `UPDATE notes SET status = 'failed', result = ?, ready_at = ?, attempt_started_at = NULL,
              next_attempt_at = NULL, last_error = ?
        WHERE inbox_id = ? AND id = ? AND status = 'transcribing' AND retry_count = ?
        RETURNING *`,
    )
    .bind(result, ctx.now, String(error).slice(0, 200), note.inbox_id, note.id, note.retry_count)
    .first();
  if (!failed) return;

  // Give the free note back, once.
  const refunded = await ctx.db
    .prepare('UPDATE notes SET free_note = -1 WHERE inbox_id = ? AND id = ? AND free_note = 1 RETURNING id')
    .bind(note.inbox_id, note.id)
    .first();
  if (refunded) {
    await ctx.db
      .prepare('UPDATE inboxes SET free_notes_used = MAX(0, free_notes_used - 1) WHERE id = ?')
      .bind(note.inbox_id)
      .run();
  }
  console.log(`[notes] failed ${result} inbox=${await logId(note.inbox_id)}`);
  await alertPermanentFailure(ctx, result, error);
  await deleteAudio(ctx, failed);
}

async function scheduleRetry(ctx, note, error) {
  const wait = BACKOFF_MINUTES[Math.min(Math.max(note.attempts, 1) - 1, BACKOFF_MINUTES.length - 1)] * MINUTE;
  if (ctx.now + wait > note.accepted_at + RETRY_WINDOW_MS) {
    return finishFailed(ctx, note, 'retries_exhausted', error);
  }
  await ctx.db
    .prepare(
      `UPDATE notes SET attempt_started_at = NULL, next_attempt_at = ?, last_error = ?
        WHERE inbox_id = ? AND id = ? AND status = 'transcribing' AND retry_count = ? AND attempt_started_at = ?`,
    )
    .bind(ctx.now + wait, error, note.inbox_id, note.id, note.retry_count, note.attempt_started_at)
    .run();
}

async function deleteAudio(ctx, note) {
  if (!note.audio_key) return;
  try {
    await ctx.env.AUDIO.delete(note.audio_key);
    await ctx.db
      .prepare('UPDATE notes SET audio_key = NULL, audio_stored_at = NULL WHERE inbox_id = ? AND id = ? AND audio_key = ?')
      .bind(note.inbox_id, note.id, note.audio_key)
      .run();
  } catch (err) {
    // The cron tries again, and deletes any audio after a day regardless.
    console.error(`[notes] audio delete failed inbox=${await logId(note.inbox_id)}: ${err.message}`);
  }
}

/**
 * Cron, every minute: start due retries, and attempts lost (the upload's
 * first attempt after 1 minute, the cron's after 8). The claim is
 * conditional, so one attempt runs per note.
 */
export async function sweep(ctx) {
  const { results } = await ctx.db
    .prepare(
      `SELECT inbox_id, id, attempt_started_at FROM notes
        WHERE status = 'transcribing'
          AND ((attempt_started_at IS NULL AND next_attempt_at <= ?) OR attempt_started_at <= ?
            OR (attempts = 1 AND attempt_started_at <= ?))
        ORDER BY accepted_at LIMIT ?`,
    )
    .bind(ctx.now, ctx.now - ATTEMPT_LOST_MS, ctx.now - INLINE_ATTEMPT_LOST_MS, SWEEP_BATCH)
    .all();
  const running = [];
  for (const n of results) {
    const claimed = await ctx.db
      .prepare(
        `UPDATE notes SET attempt_started_at = ?, attempts = attempts + 1
          WHERE inbox_id = ? AND id = ? AND status = 'transcribing' AND attempt_started_at IS ?
          RETURNING *`,
      )
      .bind(ctx.now, n.inbox_id, n.id, n.attempt_started_at)
      .first();
    if (claimed) running.push(runAttempt(ctx, claimed));
  }
  await Promise.all(running);
  return running.length;
}

/**
 * Cron, every minute: agent copies for transcripts done over a minute ago
 * whose copies were never marked made. Insertion is idempotent and keeps the
 * "paired before it was recorded" rule; only new copies ping a hook.
 */
export async function sweepCopies(ctx) {
  const { results } = await ctx.db
    .prepare(
      `SELECT * FROM notes
        WHERE status = 'done' AND result = 'transcript' AND copies_made_at IS NULL
          AND transcript IS NOT NULL AND ready_at <= ?
        ORDER BY ready_at LIMIT ?`,
    )
    .bind(ctx.now - MINUTE, SWEEP_BATCH)
    .all();
  for (const n of results) await copyToAgents(ctx, n);
  return results.length;
}

/** Cron: device copies after 30 days, old notes, and audio no longer needed. */
export async function purgeNotes(ctx) {
  await ctx.db
    .prepare(
      `UPDATE notes SET transcript = NULL, transcript_cleared_at = ?
        WHERE transcript_cleared_at IS NULL AND ready_at <= ?`,
    )
    .bind(ctx.now, ctx.now - DEVICE_COPY_MS)
    .run();
  await ctx.db
    .prepare('DELETE FROM notes WHERE transcript_cleared_at <= ?')
    .bind(ctx.now - CLEARED_KEEP_MS)
    .run();
  if (!ctx.env.AUDIO) return;
  const { results } = await ctx.db
    .prepare(
      `SELECT inbox_id, id, audio_key FROM notes
        WHERE audio_key IS NOT NULL AND (status != 'transcribing' OR audio_stored_at <= ?) LIMIT 100`,
    )
    .bind(ctx.now - AUDIO_MAX_AGE_MS)
    .all();
  for (const n of results) await deleteAudio(ctx, n);
}
