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
| GPT-Transcribe | OpenAI | `openai-gpt-transcribe` |

Retired model keys keep working — `openai-gpt-4o-transcribe` resolves to `openai-gpt-transcribe`, so app versions already on people's phones don't break when a model is replaced.

## Transcription Request

`POST /transcribe` takes multipart form data:

| Field | Required | Description |
|-------|----------|-------------|
| `audio` | yes | The recording. The app sends 16 kHz mono AAC, split client-side into pieces under 24 MB and 20 minutes so every request stays inside the providers' size and length limits. |
| `model` | no | One of the keys above. Defaults to `whisper-large-v3-turbo`. |
| `language` | no | ISO-639-1 hint. Omit to auto-detect. |
| `vocabulary` | no | Comma- or newline-separated names and jargon. |
| `remove_filler_words` | no | `"true"` to strip "um", "uh", and friends. |

Each provider takes those hints differently, which is the reason the proxy exists rather than the app calling providers directly:

| | Groq (Whisper) | Deepgram Nova-3 | OpenAI GPT-Transcribe |
|---|---|---|---|
| Vocabulary | `prompt` (framed as a sentence, echo stripped from the result) | one `keyterm` per term | one `keywords[]` per term |
| Language | `language` | `language`, or `multi` to auto-detect | `languages[]` (sending `language` too is rejected) |
| Filler words | stripped from the response | `filler_words` parameter | stripped from the response |
| Paragraphs | from segment timings, breaking on pauses | native `paragraphs=true` | grouped from sentences — the model returns plain text with no timings |

Response is `{"text": "..."}`, or `{"error": "..."}` with a 4xx/5xx status.

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/transcribe` | Multipart audio in, `{"text": "..."}` out |
| `POST` | `/attest/challenge` | Issue a challenge for App Attest registration |
| `POST` | `/attest` | Register a device via App Attest |
| `GET` | `/health` | Health check |

## Authentication

**App Attest** — Apple's device attestation proves requests come from a real copy of Ramble on a real Apple device. The app attests once, then sends an assertion with each request. All `/transcribe` requests must include valid attestation headers.

**Subscription verification** — Cloud transcription requires an active StoreKit 2 subscription. The proxy verifies Apple's signed JWS transaction directly — no server-side receipt validation, no App Store Server API calls.

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

`DCAppAttestService` works on any real Apple device, including apps built directly from Xcode. The only difference is the environment: dev builds use `appattestdevelop` as the AAGUID, while TestFlight/App Store builds use `appattest`. The proxy accepts both. App Attest does NOT work on the iOS Simulator.

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
npm test        # Unit tests — no credentials or Worker runtime needed
```

`npm test` covers the pure parts: model resolution, keyword sanitizing, language
resolution, and transcript formatting. CI runs it on every PR touching `proxy/`
and the deploy is gated on it.

You'll likely want to set `DEV_BYPASS_TOKEN` as a var in `wrangler.toml` during development to skip subscription verification.
