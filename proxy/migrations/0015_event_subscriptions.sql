-- MCP Events webhook subscriptions (specs/connector.md "Events"). A connector
-- such as ChatGPT subscribes to "note_received" with a callback URL and a
-- Standard Webhooks secret; when the connection gets a new copy, the relay
-- POSTs a signed event there. Subscriptions belong to one agent connection
-- and go away when it is disconnected, the subscription expires, or its
-- callback has failed for a week.
CREATE TABLE IF NOT EXISTS event_subscriptions (
  id TEXT PRIMARY KEY, -- deterministic: connection, event name, URL, arguments
  connection_id TEXT NOT NULL,
  name TEXT NOT NULL,
  url TEXT NOT NULL,
  secret TEXT NOT NULL, -- the whsec_ secret, encrypted with HOOK_ENCRYPTION_KEY
  prev_secret TEXT, -- the one it replaced, encrypted; also signed with for an hour
  rotated_at INTEGER,
  created_at INTEGER NOT NULL,
  refreshed_at INTEGER NOT NULL, -- last subscribe; the least recently refreshed gives way at the cap
  expires_at INTEGER, -- NULL: never expires (asked with ttlMs: null)
  delivered_at INTEGER, -- last delivery attempt
  last_status INTEGER, -- its HTTP status, 0 if nothing answered
  failing_since INTEGER -- first failed delivery since the last success
);
CREATE INDEX IF NOT EXISTS event_subscriptions_connection ON event_subscriptions (connection_id);
CREATE INDEX IF NOT EXISTS event_subscriptions_expiry ON event_subscriptions (expires_at);
