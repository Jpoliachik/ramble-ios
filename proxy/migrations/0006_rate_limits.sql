-- Fixed-window rate limit counters. `key` is a SHA-256 hex of the limiter key
-- plus the window start, so no credential hash or network address is stored
-- readable. Rows are dead once expires_at (ms) passes; cron purges them.
CREATE TABLE IF NOT EXISTS rate_limits (
  key TEXT PRIMARY KEY,
  count INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS rate_limits_expires_at ON rate_limits (expires_at);
