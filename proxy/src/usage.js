// Usage stats: one row per finished note, and the app build each device last
// sent. Never audio, transcript text, vocabulary words or agent details.
// See specs/relay-api.md "Usage stats".

import { logId, sha256Hex } from './http.js';

const CLIENT_RE = /^[\x20-\x7E]{1,80}$/;

/** The X-Ramble-Client header ("Ramble/1.3 (142) iOS/26.2"), or null. */
export function clientLabel(request) {
  const value = (request.headers.get('X-Ramble-Client') || '').trim();
  return CLIENT_RE.test(value) ? value : null;
}

/** Keeps the latest app label per device on the inbox. Never rejects. */
export async function rememberClient(ctx, cred, app) {
  if (!app || (cred.kind !== 'inbox' && cred.kind !== 'watch')) return;
  const column = cred.kind === 'inbox' ? 'phone_app' : 'watch_app';
  try {
    await ctx.db
      .prepare(`UPDATE inboxes SET ${column} = ? WHERE id = ? AND ${column} IS NOT ?`)
      .bind(app, cred.inboxId, app)
      .run();
  } catch (err) {
    console.error(`[usage] client not recorded: ${String(err?.message).slice(0, 200)}`);
  }
}

/** Writes (or, after a hand retry, rewrites) a finished note's row. Never rejects. */
export async function recordNoteEvent(ctx, note) {
  try {
    const inbox = await ctx.db.prepare('SELECT usage_id FROM inboxes WHERE id = ?').bind(note.inbox_id).first();
    if (!inbox?.usage_id) return;
    const options = note.options ? JSON.parse(note.options) : {};
    const noteKey = (await sha256Hex(`ramble-usage:${note.inbox_id}:${note.id}`)).slice(0, 16);
    await ctx.db
      .prepare(
        `INSERT INTO note_events (user_id, note_key, source, recorded_at, accepted_at, finished_at, duration, result,
            attempts, hand_retries, free_note, language, filler_removal, vocabulary, app)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT (user_id, note_key) DO UPDATE SET accepted_at = excluded.accepted_at,
            finished_at = excluded.finished_at, duration = excluded.duration, result = excluded.result,
            attempts = excluded.attempts, hand_retries = excluded.hand_retries, free_note = excluded.free_note,
            language = excluded.language, filler_removal = excluded.filler_removal,
            vocabulary = excluded.vocabulary, app = excluded.app`,
      )
      .bind(
        inbox.usage_id,
        noteKey,
        note.source,
        note.recorded_ms,
        note.accepted_at,
        note.ready_at ?? ctx.now,
        note.duration ?? note.container_duration ?? null,
        note.result,
        note.attempts,
        note.retry_count,
        note.free_note === 1 ? 1 : 0,
        options.language ?? null,
        options.removeFillerWords ? 1 : 0,
        String(options.vocabulary ?? '').trim() ? 1 : 0,
        note.app ?? null,
      )
      .run();
  } catch (err) {
    console.error(`[usage] note not recorded inbox=${await logId(note.inbox_id)}: ${String(err?.message).slice(0, 200)}`);
  }
}
