-- Ack deletes the transcript text but keeps a text-free receipt for a short
-- window so the phone can show "picked up". NULL = not yet picked up.
ALTER TABLE entries ADD COLUMN acked_at INTEGER;
