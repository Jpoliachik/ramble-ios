-- When the relay received each transcript. created_at (recorded_at here) is
-- when the user started recording on the watch or phone; the two can be hours
-- apart if the phone was offline. Rows from before this migration have none.
ALTER TABLE entries ADD COLUMN received_at INTEGER;
