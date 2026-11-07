-- Usage monitoring and the operator's kill switch. See specs/purchase.md
-- "Heavy use" and proxy/README.md "Operations".

-- Transcribed audio seconds per user per UTC month ("2026-11"). The user is
-- the purchase an inbox is unlocked by ("unlock:<id>", "sub:<id>",
-- "app:<id>"), or the inbox ID ("inb_...") when it has none. Monitoring only:
-- it never refuses a note.
CREATE TABLE IF NOT EXISTS usage (
  user_id TEXT NOT NULL,
  month TEXT NOT NULL,
  seconds REAL NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, month)
);
CREATE INDEX IF NOT EXISTS usage_month ON usage (month, seconds);

-- Set by hand (wrangler d1 execute). A suspended inbox, or every inbox bound
-- to a suspended purchase, has its uploads refused with 403 "suspended".
ALTER TABLE inboxes ADD COLUMN suspended INTEGER NOT NULL DEFAULT 0;
ALTER TABLE purchases ADD COLUMN suspended INTEGER NOT NULL DEFAULT 0;
