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
| `GET` | `/analytics?token=SECRET&days=7` | Anonymous usage stats (admin only) |

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

5. (Optional) Set up Analytics Engine for anonymous usage stats:
   ```bash
   # Create via Cloudflare dashboard: Account → Analytics Engine → Create dataset "ramble_usage"
   # Then add the dataset binding to wrangler.toml (see wrangler.example.toml)
   npx wrangler secret put ANALYTICS_TOKEN   # secret for /analytics endpoint
   ```

6. Deploy:
   ```bash
   npm install
   npm run deploy
   ```

## Usage Analytics

Anonymous usage tracking via Cloudflare Analytics Engine. This helps us understand which models are popular and how the service is being used, without collecting any personal information.

**What's collected per transcription request:**
- Model name and provider (e.g. "whisper-large-v3-turbo" via Groq)
- Audio file size and transcript length
- Processing duration
- Success or failure
- SHA-256 hashed device ID (for unique-user counts — not reversible)

**What's NOT collected:** audio content, transcription text, IP addresses, or anything that identifies a person.

**Query the data:**
```bash
curl "https://your-worker.workers.dev/analytics?token=YOUR_SECRET&days=30"
```

Returns: total requests, model breakdown, daily volume, unique device counts, and averages (file size, text length, duration).

You can also query the raw data via the Cloudflare dashboard (Account → Analytics Engine → ramble_usage).

### Local Development

```bash
npm install
npm run dev
```

You'll likely want to set `DEV_BYPASS_TOKEN` as a var in `wrangler.toml` during development to skip subscription verification.
