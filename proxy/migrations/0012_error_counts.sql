-- Server errors per minute, for the error-spike alert (specs/transcription.md
-- "Operator alerts"). Counts only: no paths, bodies or credentials. Rows older
-- than an hour are purged by the cron.

CREATE TABLE IF NOT EXISTS error_counts (
  minute INTEGER PRIMARY KEY,
  n INTEGER NOT NULL
);
