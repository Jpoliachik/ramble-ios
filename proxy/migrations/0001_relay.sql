-- Ramble Relay schema. This is the whole state inventory: no users, no
-- emails, no names, no audio, no transcript archive.

-- One row per installed copy of Ramble that has turned the relay on.
-- The secret is stored only as a SHA-256 hash.
CREATE TABLE IF NOT EXISTS inboxes (
  id TEXT PRIMARY KEY,
  secret_hash TEXT NOT NULL UNIQUE,
  created_at INTEGER NOT NULL
);

-- Short-lived, single-use pairing codes. Stored hashed, deleted on use.
CREATE TABLE IF NOT EXISTS pair_codes (
  code_hash TEXT PRIMARY KEY,
  inbox_id TEXT NOT NULL,
  agent_type TEXT NOT NULL,
  expires_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS pair_codes_inbox ON pair_codes (inbox_id);
CREATE INDEX IF NOT EXISTS pair_codes_expiry ON pair_codes (expires_at);

-- One row per connected agent. The token is stored only as a SHA-256 hash.
CREATE TABLE IF NOT EXISTS connections (
  id TEXT PRIMARY KEY,
  inbox_id TEXT NOT NULL,
  agent_type TEXT NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  created_at INTEGER NOT NULL,
  last_pull_at INTEGER
);
CREATE INDEX IF NOT EXISTS connections_inbox ON connections (inbox_id);

-- Queued transcripts, one copy per connection. Deleted on ack, on revoke,
-- on purge, or when expires_at passes.
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
