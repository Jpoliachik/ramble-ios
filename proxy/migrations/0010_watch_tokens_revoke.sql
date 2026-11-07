-- A replaced watch token is now simply revoked: it no longer reads the notes
-- it uploaded. Delete the replaced ones still kept for those reads, so none
-- of them authenticates as a live token. See specs/relay-api.md "Watch token".
DELETE FROM watch_tokens WHERE replaced_at IS NOT NULL;
