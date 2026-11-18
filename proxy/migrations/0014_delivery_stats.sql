-- Delivery stats for the operator (specs/usage.md "How notes reach people").
-- No content: which way each agent reaches Ramble, and whether the iPhone
-- has a webhook destination set (never its URL or secret).

-- 'api' (pairing + GET /inbox) or 'mcp' (the connector at /mcp): set when the
-- connection is made and on every check-in. NULL for connections that haven't
-- checked in since this column was added.
ALTER TABLE connections ADD COLUMN via TEXT;

-- Last X-Ramble-Webhook the iPhone sent on GET /notes: 1 on, 0 off, NULL
-- when it never sent one (older builds).
ALTER TABLE inboxes ADD COLUMN webhook INTEGER;
