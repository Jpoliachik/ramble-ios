-- Optional per-agent extras, all set by the agent itself.
--
-- name: what the agent calls itself at pairing ("Grok Bot"), so the app can
--   tell several connected agents apart.
-- hook_*: an optional wake-up webhook. When a transcript arrives, the relay
--   POSTs a small "notes are waiting" ping (never the transcript text) to
--   hook_url with hook_headers, and the agent pulls as usual. hook_headers is
--   stored as given, not hashed, because the relay has to send it back out.
--   It only lets someone start the agent's own run, which then pulls with
--   the separate rmba_ token.
ALTER TABLE connections ADD COLUMN name TEXT;
ALTER TABLE connections ADD COLUMN hook_url TEXT;
ALTER TABLE connections ADD COLUMN hook_headers TEXT;
ALTER TABLE connections ADD COLUMN hook_pinged_at INTEGER;
ALTER TABLE connections ADD COLUMN hook_status INTEGER;
