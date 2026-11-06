-- Estimated transcription spend per provider per UTC day.
-- The fallback spend breaker (specs/transcription.md) sums the Deepgram and
-- OpenAI rows for today; the operator summary and spend alert read all rows.
-- Holds lengths and dollar estimates only, never audio or transcript text.
CREATE TABLE IF NOT EXISTS provider_spend (
  day TEXT NOT NULL,              -- 'YYYY-MM-DD', UTC
  provider TEXT NOT NULL,         -- 'groq' | 'deepgram' | 'openai'
  usd REAL NOT NULL DEFAULT 0,    -- estimated dollars
  seconds REAL NOT NULL DEFAULT 0, -- billed audio seconds
  notes INTEGER NOT NULL DEFAULT 0, -- successful provider calls
  PRIMARY KEY (day, provider)
);
