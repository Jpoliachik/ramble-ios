-- The person's own name for an agent connection, set from the iPhone
-- (specs/relay-api.md "Connections"). The agent's own name stays in `name`;
-- the app shows `label` when set. NULL: no label.
ALTER TABLE connections ADD COLUMN label TEXT;
