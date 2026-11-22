// The Ramble note record (specs/note.md): one shape for a note wherever an
// agent or automation sees it: GET /inbox, the MCP tools, MCP events and the
// iPhone's webhook. Fields are only ever added within a version; a rename or
// removal would be version 2.

import { iso } from './http.js';

export const NOTE_TYPE = 'ramble.note';
export const NOTE_VERSION = 1;
export const NOTE_SCHEMA_URL = 'https://ramble.watch/schemas/note-v1.json';

/**
 * `receivedAt` is epoch ms; `recordedAt` is kept exactly as the device sent
 * it. Leave `transcript` undefined for a summary (lists and events).
 */
export function noteRecord({ id, source, recordedAt, receivedAt, duration, transcript }) {
  const note = {
    type: NOTE_TYPE,
    version: NOTE_VERSION,
    id,
    source: source === 'watch' || source === 'phone' ? source : null,
    recorded_at: recordedAt ?? null,
    received_at: iso(receivedAt),
    duration_seconds: duration ?? 0,
  };
  if (transcript !== undefined) note.transcript = transcript ?? '';
  return note;
}

/** An agent copy (an entries row) as the note record, with or without its transcript. */
export const entryNote = (row, withTranscript) =>
  noteRecord({
    id: row.recording_id,
    source: row.source,
    recordedAt: row.recorded_at,
    receivedAt: row.received_at,
    duration: row.duration,
    transcript: withTranscript ? row.text : undefined,
  });

/** The JSON Schema of a summary (no transcript), for MCP event payloads. */
export const NOTE_SUMMARY_SCHEMA = {
  type: 'object',
  properties: {
    type: { const: NOTE_TYPE },
    version: { const: NOTE_VERSION },
    id: { type: 'string', description: 'The note id (a UUID). Stable everywhere the note appears.' },
    source: { type: ['string', 'null'], enum: ['watch', 'phone', null], description: 'The device that recorded it, or null when unknown.' },
    recorded_at: { type: 'string', description: "When recording started, in the device's local time with its offset." },
    received_at: { type: ['string', 'null'], description: 'When Ramble received the audio, ISO 8601 UTC.' },
    duration_seconds: { type: 'number' },
  },
  required: ['type', 'version', 'id', 'source', 'recorded_at', 'received_at', 'duration_seconds'],
};
