-- Cloud-only redesign: notes uploaded as audio, transcribed on the relay.
-- Additive: existing inboxes, connections and queued entries keep working.
-- See specs/relay-api.md, transcription.md, delivery.md and purchase.md.

-- Inboxes become accounts: the token StoreKit binds a purchase to, the free
-- note count, the bound purchase, and the transcription settings.
ALTER TABLE inboxes ADD COLUMN account_token TEXT;
ALTER TABLE inboxes ADD COLUMN free_notes_used INTEGER NOT NULL DEFAULT 0;
ALTER TABLE inboxes ADD COLUMN purchase_id TEXT;
ALTER TABLE inboxes ADD COLUMN bound_at INTEGER;
ALTER TABLE inboxes ADD COLUMN last_upload_at INTEGER;
ALTER TABLE inboxes ADD COLUMN language TEXT;
ALTER TABLE inboxes ADD COLUMN remove_filler_words INTEGER NOT NULL DEFAULT 0;
ALTER TABLE inboxes ADD COLUMN vocabulary TEXT NOT NULL DEFAULT '';
CREATE INDEX IF NOT EXISTS inboxes_created ON inboxes (created_at);
CREATE INDEX IF NOT EXISTS inboxes_purchase ON inboxes (purchase_id);

-- One row per purchase, keyed on Apple's original transaction ID (or the app
-- transaction ID for early buyers): "unlock:<id>", "sub:<id>", "app:<id>".
-- Inboxes point at it through inboxes.purchase_id. A refund sets revoked_at,
-- which locks every bound inbox and rejects the record from then on.
-- test_until is set for sandbox purchases: a 7-day test unlock.
CREATE TABLE IF NOT EXISTS purchases (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL,
  environment TEXT NOT NULL,
  test_until INTEGER,
  revoked_at INTEGER,
  created_at INTEGER NOT NULL
);

-- Fair use: measured audio seconds per purchase per UTC month ("2026-11").
CREATE TABLE IF NOT EXISTS fair_use (
  purchase_id TEXT NOT NULL,
  month TEXT NOT NULL,
  seconds REAL NOT NULL DEFAULT 0,
  PRIMARY KEY (purchase_id, month)
);

-- Watch tokens. One live token per inbox; a replaced token keeps reading the
-- notes it uploaded for 30 days. Revoking deletes the row.
CREATE TABLE IF NOT EXISTS watch_tokens (
  token_hash TEXT PRIMARY KEY,
  inbox_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  replaced_at INTEGER
);
CREATE INDEX IF NOT EXISTS watch_tokens_inbox ON watch_tokens (inbox_id);

-- Notes. The ID is the device's UUID, scoped to the inbox. The transcript
-- here is the copy for the person's own devices; agents get rows in entries.
-- Audio lives in R2 under audio_key until it is no longer needed.
CREATE TABLE IF NOT EXISTS notes (
  inbox_id TEXT NOT NULL,
  id TEXT NOT NULL,
  source TEXT NOT NULL,
  watch_token_hash TEXT,
  status TEXT NOT NULL,
  result TEXT,
  recorded_at TEXT NOT NULL,
  recorded_ms INTEGER NOT NULL,
  received_at INTEGER NOT NULL,
  accepted_at INTEGER NOT NULL,
  content_type TEXT NOT NULL,
  container_duration REAL,
  duration REAL,
  transcript TEXT,
  provider TEXT,
  model TEXT,
  ready_at INTEGER,
  transcript_cleared_at INTEGER,
  phone_acked_at INTEGER,
  watch_received_at INTEGER,
  retry_count INTEGER NOT NULL DEFAULT 0,
  attempts INTEGER NOT NULL DEFAULT 0,
  attempt_started_at INTEGER,
  next_attempt_at INTEGER,
  options TEXT,
  audio_key TEXT,
  audio_stored_at INTEGER,
  free_note INTEGER NOT NULL DEFAULT 0,
  fair_use_purchase TEXT,
  fair_use_month TEXT,
  fair_use_seconds REAL NOT NULL DEFAULT 0,
  last_error TEXT,
  PRIMARY KEY (inbox_id, id)
);
CREATE INDEX IF NOT EXISTS notes_status ON notes (status, next_attempt_at);
CREATE INDEX IF NOT EXISTS notes_accepted ON notes (accepted_at);
CREATE INDEX IF NOT EXISTS notes_ready ON notes (ready_at);
CREATE INDEX IF NOT EXISTS notes_audio ON notes (audio_key);

-- Agent copies keep a small row after they are acked or removed, without the
-- text, so the phone can tell "picked up" from "removed unread". The inbox is
-- stored on the copy so it survives its connection being deleted.
ALTER TABLE entries ADD COLUMN inbox_id TEXT;
ALTER TABLE entries ADD COLUMN acked_at INTEGER;
ALTER TABLE entries ADD COLUMN removed_at INTEGER;
UPDATE entries SET inbox_id = (SELECT inbox_id FROM connections WHERE connections.id = entries.connection_id);
CREATE INDEX IF NOT EXISTS entries_inbox_recording ON entries (inbox_id, recording_id);

-- Pairing: the issued agent key is kept only encrypted with a key derived
-- from the exchange's request_id (in pair_codes.token), for the code's 10
-- minutes, so only the agent that paired can recover it.
-- Already-exchanged codes held their key in plain text: drop them.
ALTER TABLE pair_codes ADD COLUMN request_hash TEXT;
DELETE FROM pair_codes WHERE token IS NOT NULL;

-- Operator: counted events (refusals, provider trouble) and alert cooldowns.
CREATE TABLE IF NOT EXISTS events (
  at INTEGER NOT NULL,
  kind TEXT NOT NULL,
  detail TEXT
);
CREATE INDEX IF NOT EXISTS events_kind ON events (kind, at);

CREATE TABLE IF NOT EXISTS alerts (
  key TEXT PRIMARY KEY,
  sent_at INTEGER NOT NULL
);
