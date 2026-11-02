-- Ramble Relay schema. This is everything it stores: no users, emails, names,
-- audio, or transcript archive. Credentials are stored only as SHA-256 hashes.

CREATE TABLE IF NOT EXISTS inboxes (
  id TEXT PRIMARY KEY,
  secret_hash TEXT NOT NULL UNIQUE,
  created_at INTEGER NOT NULL
);

-- Single-use, 10-minute pairing codes.
CREATE TABLE IF NOT EXISTS pair_codes (
  code_hash TEXT PRIMARY KEY,
  inbox_id TEXT NOT NULL,
  expires_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS pair_codes_inbox ON pair_codes (inbox_id);

-- One row per connected agent.
CREATE TABLE IF NOT EXISTS connections (
  id TEXT PRIMARY KEY,
  inbox_id TEXT NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  created_at INTEGER NOT NULL,
  last_pull_at INTEGER
);
CREATE INDEX IF NOT EXISTS connections_inbox ON connections (inbox_id);

-- Queued transcripts, one copy per connection. Deleted on ack, disconnect,
-- "delete everything", or expiry.
CREATE TABLE IF NOT EXISTS entries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  connection_id TEXT NOT NULL,
  recording_id TEXT NOT NULL,
  recorded_at TEXT NOT NULL,
  duration REAL NOT NULL,
  text TEXT NOT NULL,
  expires_at INTEGER NOT NULL,
  UNIQUE (connection_id, recording_id)
);
CREATE INDEX IF NOT EXISTS entries_expiry ON entries (expires_at);
