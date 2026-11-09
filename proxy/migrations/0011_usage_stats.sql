-- Usage stats (specs/relay-api.md "Usage stats"): one row per finished note,
-- never any audio or text, kept indefinitely. Rows carry the inbox's random
-- usage_id, not the inbox id. The app build and OS each device last sent are
-- kept on the inbox for debugging.

ALTER TABLE inboxes ADD COLUMN usage_id TEXT;
UPDATE inboxes SET usage_id = lower(hex(randomblob(8))) WHERE usage_id IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS inboxes_usage_id ON inboxes (usage_id);

ALTER TABLE inboxes ADD COLUMN phone_app TEXT;
ALTER TABLE inboxes ADD COLUMN watch_app TEXT;

ALTER TABLE notes ADD COLUMN app TEXT;

CREATE TABLE IF NOT EXISTS note_events (
  user_id TEXT NOT NULL,
  note_key TEXT NOT NULL,
  source TEXT NOT NULL,
  recorded_at INTEGER NOT NULL,
  accepted_at INTEGER NOT NULL,
  finished_at INTEGER NOT NULL,
  duration REAL,
  result TEXT NOT NULL,
  attempts INTEGER NOT NULL,
  hand_retries INTEGER NOT NULL,
  free_note INTEGER NOT NULL,
  language TEXT,
  filler_removal INTEGER NOT NULL,
  vocabulary INTEGER NOT NULL,
  app TEXT,
  PRIMARY KEY (user_id, note_key)
);
CREATE INDEX IF NOT EXISTS note_events_recorded ON note_events (recorded_at);
