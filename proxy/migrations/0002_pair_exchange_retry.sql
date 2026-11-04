-- Retry-safe pairing. The first exchange used to delete the code, so an agent
-- whose response got lost (timeout, dropped connection) had no way back. Now
-- the code row keeps the issued token until the agent first pulls with it, or
-- the code's 10 minutes run out, whichever comes first. A retried exchange in
-- that window gets the same token instead of "Invalid or expired".
ALTER TABLE pair_codes ADD COLUMN token TEXT;
ALTER TABLE pair_codes ADD COLUMN connection_id TEXT;
CREATE INDEX IF NOT EXISTS pair_codes_connection ON pair_codes (connection_id);
