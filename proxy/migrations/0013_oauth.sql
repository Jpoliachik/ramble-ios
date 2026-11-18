-- MCP connector sign-in (specs/connector.md). A connector such as Claude
-- registers itself as an OAuth client, then the person enters the pairing
-- code from the Ramble app on the sign-in page. The connector ends up as one
-- more agent connection with its own agent key; nothing new is stored about
-- the person.

-- Clients registered with POST /register. No secrets: public clients with PKCE.
CREATE TABLE IF NOT EXISTS oauth_clients (
  id TEXT PRIMARY KEY,
  name TEXT,
  redirect_uris TEXT NOT NULL, -- JSON array of exact URIs
  created_at INTEGER NOT NULL
);

-- Authorization codes: single use, 10 minutes. The pairing code is already
-- claimed for `connection_id`; the connection and its key are made when the
-- code is redeemed at POST /token.
CREATE TABLE IF NOT EXISTS oauth_codes (
  code_hash TEXT PRIMARY KEY,
  client_id TEXT NOT NULL,
  redirect_uri TEXT NOT NULL,
  code_challenge TEXT NOT NULL,
  inbox_id TEXT NOT NULL,
  connection_id TEXT NOT NULL,
  name TEXT,
  expires_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS oauth_codes_expiry ON oauth_codes (expires_at);
