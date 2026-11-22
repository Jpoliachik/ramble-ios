-- Agent copies remember which device recorded the note, for the note
-- record's "source" (specs/note.md). Copies from old builds' text uploads,
-- and copies whose note is gone, stay NULL: unknown.
ALTER TABLE entries ADD COLUMN source TEXT;
UPDATE entries SET source = (
  SELECT n.source FROM notes n WHERE n.inbox_id = entries.inbox_id AND n.id = entries.recording_id
) WHERE source IS NULL;
