# Ramble Relay

This is the server Ramble's iPhone and Apple Watch apps talk to. It's one Cloudflare Worker that takes each note's audio, transcribes it, keeps the transcript for the person's own devices until they have it, and hands a copy to each agent the person connected. The code is in this repo so you can verify exactly what it does.

Ramble's server is a relay, not an archive. Your audio is sent to a transcription provider and deleted as soon as the transcript is ready. Transcripts are deleted when your agent picks them up, or after 30 days. Your full history lives only on your iPhone.

The behavior is specified in [`specs/`](../specs/): the HTTP contract is [`relay-api.md`](../specs/relay-api.md), the pipeline [`transcription.md`](../specs/transcription.md), agents and retention [`delivery.md`](../specs/delivery.md), free notes and the unlock [`purchase.md`](../specs/purchase.md). Agent-facing docs are in [RELAY.md](RELAY.md).

## How it works

1. The watch or iPhone uploads a note's audio to `PUT /notes/:id` (the note's UUID is the idempotency key).
2. The relay stores the audio in a private R2 bucket, then accepts the note, counting a free note before the unlock.
3. It transcribes right away with Groq Whisper v3 Turbo, the only provider. Quick transcripts come back in the upload response; if Groq is overloaded or down, the note waits for a retry.
4. The audio is deleted. One copy of the transcript goes to each connected agent, and one is kept for the person's devices until the phone acks it (and, for a watch note, the watch has seen it), at most 30 days.
5. A cron job every minute retries failed attempts (for up to 20 hours), picks up stalled ones, expires old data, and alerts the operator about notes stuck for 30 minutes or a spike of server errors.

## Code map

| File | What it does |
|---|---|
| `src/index.js` | Routing, the request context, the cron |
| `src/auth.js` | Credentials (`rmbi_` phone, `rmbw_` watch, `rmba_` agent) and the rate limits (App Attest and inbox creation only) |
| `src/account.js` | Inbox creation, free notes, the unlock and its binding, revoked purchases, the usage tally and suspension, settings, the watch token |
| `src/notes.js` | Audio uploads, the transcription pipeline and retries, the device copy and acks |
| `src/relay.js` | Pairing, agent copies, pull and ack, delivery status, wake-up hooks, old builds' text upload |
| `src/mcp.js`, `src/oauth.js`, `src/events.js` | The MCP connector, its OAuth sign-in, and MCP Events webhook delivery (`specs/connector.md`) |
| `src/legacy.js` | Old builds' `POST /transcribe` for early subscribers, until the fixed retirement date `LEGACY_RETIRES_AT` (2027-01-07 00:00 UTC) |
| `src/usage.js` | Usage stats: one content-free row per finished note, the app label each device last sent (`specs/usage.md`) |
| `src/ops.js` | Operator alerts (Telegram): Groq key rejected or missing, a note stuck 30 minutes, permanent failures, 20+ server errors in 10 minutes |
| `src/transcribe.js`, `src/audio.js` | The Groq call, error classification, formatting; audio length from the container |
| `src/apple.js`, `src/attest.js`, `src/ratelimit.js`, `src/crypto.js` | Apple-signed records, App Attest, the D1 rate limiter |
| `migrations/` | D1 schema |

## Configuration

Bindings (in `wrangler.toml`):

| Binding | What |
|---|---|
| `DB` | D1 database `ramble-relay` (apply `migrations/` with `npx wrangler d1 migrations apply ramble-relay --remote`) |
| `AUDIO` | R2 bucket `ramble-audio`, private, with a 1-day object lifecycle rule as the backstop for failed deletes |
| `ATTEST_KV` | KV namespace for App Attest challenges and keys |

Secrets (`npx wrangler secret put NAME`):

| Secret | What |
|---|---|
| `GROQ_API_KEY` | The transcription provider |
| `HOOK_ENCRYPTION_KEY` | Encrypts agents' wake-up hook headers at rest. Without it, setting a hook answers 503 |
| `TELEGRAM_BOT_TOKEN` | Token of the operator's Telegram bot (from @BotFather). Operator alerts are sent by this bot. Unset: nothing is sent |
| `TELEGRAM_CHAT_ID` | The chat the bot sends alerts to (the operator's own chat with the bot). Unset: nothing is sent |
| `HEAVY_USE_HOURS` | Hours of transcribed audio in a UTC month after which the operator gets one heavy-use alert per user. Internal; kept as a secret so the figure isn't published. Nothing is ever refused. Unset: no heavy-use alert |
| `REVIEW_CODE` | The connector's review code for directory reviewers: signs in only to the sample-note review inbox (`specs/connector.md` "Review inbox"). Make one with `openssl rand -hex 12` and give it only to directory review forms. Unset or under 16 characters: off |
| `OPENAI_APPS_CHALLENGE` | Token from the OpenAI plugin dashboard, served at `/.well-known/openai-apps-challenge`. Unset: 404 |
| `GOOGLE_CONNECTED_APPS_TOKEN` | Token from Google Connected Console, served at `/.well-known/google-connected-apps`. Unset: 404 |

Vars (`[vars]`): `RETENTION_SECONDS`, `APPLE_BUNDLE_ID`, `UNLOCK_PRODUCT_ID`, `PREMIUM_PRODUCT_ID`, `RELAY_BASE_URL`, and one set at release: `FIRST_FREE_BUILD` (build number of the first free-notes build). Without it no paid download counts as an early buyer (old subscribers still do). Old builds' paths (`POST /transcribe`, text `POST /inbox`) answer 410 from 2027-01-07 00:00 UTC, a date fixed in `src/legacy.js`, not a var.

Production has no developer bypass: never set `ENVIRONMENT` or `DEV_BYPASS_KEY` on the deployed Worker (see Local Development). `DEV_BYPASS_TOKEN`, `ANALYTICS_TOKEN`, `DEEPGRAM_API_KEY` and `OPENAI_API_KEY` are no longer read and can be deleted.

Apple: the relay takes no App Store Server Notifications; leave the App Store Server Notifications URL unset in App Store Connect. Refunds are revoked by hand by the operator.

## What is stored

- **Inboxes:** a hash of the secret, the free-note count, the bound purchase, the transcription settings, and the operator's `suspended` flag.
- **Notes:** ID, source device, status, recorded time as sent, measured length, and the transcript until the person's devices have it. Audio sits in R2 only until transcription ends, and at most 1 day.
- **Agent copies:** transcript text until the agent acks it or 30 days pass; afterwards a row without text, so the app can show "picked up" or "not picked up".
- **Purchases:** Apple's original transaction ID, kind, environment, the operator's revoke time, `inbox_cap` (empty means 10) and `suspended` flag.
- **Usage:** transcribed audio seconds per user (purchase, or inbox without one) per UTC month, for monitoring only.
- **Usage stats (`note_events`):** one row per finished note under the inbox's random `usage_id`: device, times, length, result, tries, free or not, language, whether filler removal and vocabulary were on, app label. No inbox ID, note ID or text. Kept indefinitely. Inboxes also keep `phone_app` and `watch_app`, the last `X-Ramble-Client` each device sent. Inboxes keep `webhook` (1/0, the last `X-Ramble-Webhook` the iPhone sent; never the URL) and connections keep `via` (`api` or `mcp`, how the agent last checked in).
- **Operator data:** alert cooldowns, server-error counts per minute (kept an hour), and rate-limit counters for App Attest and inbox creation.

Logs carry no request bodies, transcript text, audio, credentials or network addresses; inbox IDs and App Attest key IDs appear only as short hashes, and provider error bodies are cut to 200 characters.

## App Attest Implementation Notes

The proxy implements Apple's [App Attest](https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity) server-side verification entirely in hand-rolled JavaScript using only the Web Crypto API. This section documents why and the gotchas we hit along the way.

### Why not use a library?

Two npm libraries exist for App Attest server verification: `node-app-attest` and `appattest-checker-node`. Both depend on Node.js built-in `crypto` (`X509Certificate`, `createHash`, `createVerify`). Cloudflare Workers run on V8 (not Node.js), and while the `nodejs_compat` flag polyfills most of `crypto`, the `X509Certificate` polyfill doesn't support EC curves — it fails with `"Unrecognized or unimplemented EC curve"` when parsing Apple's certificates. So neither library works on Workers.

Our implementation uses only `crypto.subtle` (Web Crypto API), which is native in Workers. Zero npm dependencies for the attest/assert flow.

### Gotchas we hit

**1. Apple's intermediate CA is P-384 but signs leaf certs with SHA-256**

The App Attest certificate chain is: Apple Root CA (P-384) → Intermediate CA (P-384) → Credential cert (P-256). The intermediate CA uses a P-384 key but signs the leaf certificate using `ecdsa-with-SHA256`, not the standard `ecdsa-with-SHA384` pairing. Our cert chain verification tries SHA-384 first, then falls back to SHA-256.

**2. Assertion signature is over a nonce hash, not raw authenticator data**

Apple's assertion verification docs say: compute `nonce = SHA256(authenticatorData || clientDataHash)`, then verify the signature over the nonce. The signature is over the **nonce** (a 32-byte hash), not the raw concatenation. Since `crypto.subtle.verify` with `hash: 'SHA-256'` also hashes its input, you must pass the nonce — not the pre-hash data — to get the correct double-hash that matches what the Secure Enclave signed.

```js
// WRONG — verifies over SHA256(authData || clientDataHash)
crypto.subtle.verify({hash: 'SHA-256'}, key, sig, authData || clientDataHash);

// CORRECT — verifies over SHA256(SHA256(authData || clientDataHash))
const nonce = SHA256(authData || clientDataHash);
crypto.subtle.verify({hash: 'SHA-256'}, key, sig, nonce);
```

**3. Public key extraction: use the certificate, not COSE**

During attestation, the credential public key is available in two places: the COSE key map in `authData` and the credential certificate's SPKI. We extract from the certificate because WebCrypto's `importKey('spki', ...)` handles it natively, avoiding hand-rolled COSE-to-raw-EC-point conversion.

**4. App Attest works on local Xcode dev builds**

`DCAppAttestService` works on any real Apple device, including apps built directly from Xcode. The only difference is the environment: dev builds use `appattestdevelop` as the AAGUID, while TestFlight/App Store builds use `appattest`. The production relay accepts only `appattest`. App Attest does NOT work on the iOS Simulator.

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

4. Create the D1 database and the R2 bucket (see Configuration), paste the D1 id into `wrangler.toml`, and apply the migrations.

5. Set the secrets listed under Configuration.

6. Deploy:
   ```bash
   npm install
   npm run deploy
   ```

## Local Development

```bash
npm install
cp .dev.vars.example .dev.vars          # once; add your GROQ_API_KEY
npx wrangler d1 migrations apply ramble-relay --local   # once, and after new migrations
npm run dev                             # http://localhost:8787
npm test        # Unit tests — no credentials or Worker runtime needed
```

`npm run dev` runs the exact Worker that production runs, with local D1, R2 and
KV, so every endpoint (including new ones) works locally with no extra wiring.
There is no separate local route list.

**Simulators.** App Attest doesn't work in the Simulator, so debug simulator
builds of the iPhone app default to `http://localhost:8787` and send
`X-Dev-Bypass` instead of an assertion. The relay accepts that header in one
place only, `POST /inboxes` (the only call that needs App Attest; every other
call uses the inbox secret it returns), and only when `ENVIRONMENT=development`
and `DEV_BYPASS_KEY` match `.dev.vars`. The watch simulator follows the phone's
relay URL. Release builds contain no bypass code. Purchases and App Attest
still need a real device.

`npm test` runs every endpoint against the real schema (node:sqlite stands in for
D1) with fakes for R2, providers, App Attest and Apple, plus the provider, audio,
Apple and App Attest unit tests. CI runs it on every PR touching `proxy/` and the
deploy is gated on it.
