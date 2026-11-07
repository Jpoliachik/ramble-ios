-- When a done note's agent copies were made. The cron sweeper makes the
-- copies again for a transcript whose copies were never marked made (the
-- Worker stopped or a step failed after the note was done); copy insertion is
-- idempotent on entries (connection_id, recording_id).
-- Notes already done had their copies made when they finished: mark them so
-- they aren't copied again.
ALTER TABLE notes ADD COLUMN copies_made_at INTEGER;
UPDATE notes SET copies_made_at = COALESCE(ready_at, accepted_at) WHERE status = 'done';
CREATE INDEX IF NOT EXISTS notes_copies_pending ON notes (ready_at)
  WHERE status = 'done' AND result = 'transcript' AND copies_made_at IS NULL;
