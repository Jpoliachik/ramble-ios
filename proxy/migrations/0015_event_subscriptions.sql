-- MCP Events webhook subscriptions (specs/connector.md "Events"). A connector
-- such as ChatGPT subscribes to "note_received" with a callback URL and a
-- Standard Webhooks secret; when the connection gets a new copy, the relay
-- POSTs a signed event there. Subscriptions belong to one agent connection
-- and go away when it is disconnected or the subscription expires.
CREATE TABLE IF NOT EXISTS event_subscriptions (
  id TEXT PRIMARY KEY, -- deterministic: connection, event name, URL, arguments
  connection_id TEXT NOT NULL,
  name TEXT NOT NULL,
  url TEXT NOT NULL,
  secret TEXT NOT NULL, -- the whsec_ secret, encrypted with HOOK_ENCRYPTION_KEY
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  delivered_at INTEGER, -- last delivery attempt
  last_status INTEGER -- its HTTP status, 0 if nothing answered
);
CREATE INDEX IF NOT EXISTS event_subscriptions_connection ON event_subscriptions (connection_id);
CREATE INDEX IF NOT EXISTS event_subscriptions_expiry ON event_subscriptions (expires_at);
