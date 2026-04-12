# Ramble Transcription Proxy

This is the production proxy that Ramble uses for cloud transcription. It's a stateless Cloudflare Worker that receives audio, forwards it to a transcription provider, and returns text. It stores nothing — no audio, no transcriptions, no user data.

The code is in this repo so you can verify exactly what it does.

## How It Works

1. App sends audio to `POST /transcribe`
2. Proxy verifies the request (App Attest assertion + active subscription)
3. Audio is forwarded to the selected transcription provider
4. Provider returns text, proxy passes it back to the app

That's it. No logging of audio or transcripts. No database. No user accounts.

## Supported Models

| Model | Provider | Key |
|-------|----------|-----|
| Whisper v3 Turbo | Groq | `whisper-large-v3-turbo` (default) |
| Whisper Large v3 | Groq | `whisper-large-v3` |
| Nova-3 | Deepgram | `deepgram-nova-3` |
| GPT-4o Transcribe | OpenAI | `openai-gpt-4o-transcribe` |

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/transcribe` | Multipart audio in, `{"text": "..."}` out |
| `POST` | `/attest/challenge` | Issue a challenge for App Attest registration |
| `POST` | `/attest` | Register a device via App Attest |
| `GET` | `/health` | Health check |

## Authentication

**App Attest** — Apple's device attestation proves requests come from a real copy of Ramble on a real Apple device. The app attests once, then sends an assertion with each request. Controlled by the `REQUIRE_ATTEST` flag.

**Subscription verification** — Cloud transcription requires an active StoreKit 2 subscription. The proxy verifies Apple's signed JWS transaction directly — no server-side receipt validation, no App Store Server API calls.

## Deploy Your Own

1. Copy the example config:
   ```bash
   cp wrangler.example.toml wrangler.toml
   ```

2. Edit `wrangler.toml` — set your Cloudflare account ID.

3. Create the KV namespace for App Attest state:
   ```bash
   npx wrangler kv namespace create ATTEST_KV
   ```
   Paste the returned ID into `wrangler.toml`.

4. Set your API keys as secrets:
   ```bash
   npx wrangler secret put GROQ_API_KEY
   npx wrangler secret put DEEPGRAM_API_KEY    # optional
   npx wrangler secret put OPENAI_API_KEY      # optional
   ```

5. Deploy:
   ```bash
   npm install
   npm run deploy
   ```

## Anonymous Usage Analytics

When you use cloud transcription, the proxy records anonymous usage metrics via Cloudflare Analytics Engine. This helps us understand which models are popular and keep the service running well.

**What's collected per transcription request:**
- Model name and provider (e.g. "whisper-large-v3-turbo" via Groq)
- Audio file size and transcript length (character count, not the text itself)
- Processing duration
- Success or failure status
- SHA-256 hashed device ID — a one-way hash for counting unique devices, not reversible to your actual device ID

**What's NOT collected:**
- Audio content
- Transcription text
- IP addresses
- Anything that identifies you as a person

On-device transcription (Apple Speech) never contacts the proxy, so it generates zero analytics data. You can verify all of this in [`proxy/src/analytics.js`](src/analytics.js).

### Local Development

```bash
npm install
npm run dev
```

You'll likely want to set `DEV_BYPASS_TOKEN` as a var in `wrangler.toml` during development to skip subscription verification.
