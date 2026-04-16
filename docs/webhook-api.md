# Ramble Webhook API

Ramble can POST each transcript to a URL you configure. This doc is the complete reference for receiving those webhooks.

## Setup

In the Ramble app, go to **Settings → Webhook** and toggle it on. Enter your HTTPS endpoint URL.

> The URL must use HTTPS. Localhost, private IPs, and cloud metadata endpoints are blocked.

## Automation Platforms

These platforms accept Ramble's webhook out of the box — create a webhook trigger, copy the URL, paste it into Ramble:

- **Zapier** — Use the "Webhooks by Zapier" Catch Hook trigger. [Setup guide](https://help.zapier.com/hc/en-us/articles/8496288690317-Trigger-Zaps-from-webhooks)
- **Make** — Use the Custom Webhook module. [Setup guide](https://www.make.com/en/help/tools/webhooks)
- **Airtable** — Use the "When webhook received" automation trigger. [Setup guide](https://support.airtable.com/docs/when-webhook-received-trigger)
- **n8n** — Use the Webhook node. [Setup guide](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.webhook/)

Notion and IFTTT don't accept incoming webhooks directly — use Zapier or Make as a bridge.

## Custom Endpoint Reference

If you're building your own endpoint, the rest of this document covers the payload format, signature verification, and retry behavior.

## Request

**Method:** `POST`
**Content-Type:** `application/json`

### Headers

| Header                 | Description                                                                 |
| ---------------------- | --------------------------------------------------------------------------- |
| `Content-Type`         | `application/json`                                                          |
| `X-Webhook-Signature`  | HMAC-SHA256 digest of the raw request body, keyed with your signing secret. |

### Body

```json
{
  "recording_id": "550e8400-e29b-41d4-a716-446655440000",
  "created_at": "2026-03-17T13:19:00Z",
  "duration": 138.5,
  "transcription": "Just had a great idea for the landing page...",
  "device_id": "7a2b3c4d-5e6f-7890-abcd-ef1234567890"
}
```

| Field           | Type                | Description                                                                       |
| --------------- | ------------------- | --------------------------------------------------------------------------------- |
| `recording_id`  | `string` (UUID v4)  | Unique identifier for this recording.                                             |
| `created_at`    | `string` (ISO 8601) | When the recording was created.                                                   |
| `duration`      | `number`            | Recording duration in seconds.                                                    |
| `transcription` | `string`            | Full transcript text. Empty string if transcription produced no output.            |
| `device_id`     | `string` (UUID)     | Stable per-device identifier. Not tied to any account — useful for distinguishing multiple devices. |

## Response

Return any **2xx** status code within **10 seconds** to acknowledge receipt. The response body is ignored — Ramble does not read or store it.

## Retries

If your endpoint returns a non-2xx status or the request fails, Ramble retries up to **3 times** with exponential backoff:

| Attempt   | Delay        |
| --------- | ------------ |
| 1st retry | ~5 seconds   |
| 2nd retry | ~30 seconds  |
| 3rd retry | ~120 seconds |

After 3 failed retries, the webhook is marked as failed. The user can manually retry from the recording detail screen. Pending webhooks are persisted to disk so nothing is lost if the app is closed.

## Verifying the Signature

Every request includes an `X-Webhook-Signature` header — an HMAC-SHA256 digest of the raw request body, keyed with your signing secret. Always verify this before processing to confirm the request came from Ramble. Use constant-time comparison to prevent timing attacks.

```js
const crypto = require("crypto");

function verifySignature(rawBody, signatureHeader, secret) {
  const hmac = crypto.createHmac("sha256", secret);
  hmac.update(rawBody);
  const expected = "sha256=" + hmac.digest("hex");

  return crypto.timingSafeEqual(
    Buffer.from(expected),
    Buffer.from(signatureHeader)
  );
}
```

If you regenerate the signing secret in Settings, update your server before the next transcription completes.

### Full Express Server Example

```js
const express = require("express");
const crypto = require("crypto");

const app = express();
const WEBHOOK_SECRET = process.env.RAMBLE_WEBHOOK_SECRET;

app.post(
  "/webhook",
  express.raw({ type: "application/json" }),
  (req, res) => {
    const signature = req.headers["x-webhook-signature"];
    if (!signature) {
      return res.status(401).json({ error: "Missing signature" });
    }

    const hmac = crypto.createHmac("sha256", WEBHOOK_SECRET);
    hmac.update(req.body);
    const expected = "sha256=" + hmac.digest("hex");

    if (
      !crypto.timingSafeEqual(
        Buffer.from(expected),
        Buffer.from(signature)
      )
    ) {
      return res.status(401).json({ error: "Invalid signature" });
    }

    const payload = JSON.parse(req.body);
    console.log("Transcription:", payload.transcription);

    res.status(200).json({ ok: true });
  }
);

app.listen(3000, () => console.log("Listening on :3000"));
```

## Test Webhooks

Tap **Settings → Send Test Webhook** to fire a test payload at your endpoint. The test payload is identical to a real one, with two differences: `test` is `true`, and `recording_id` is prefixed with `test-`. Filter on either to skip test payloads in production.

```json
{
  "recording_id": "test-550e8400-...",
  "created_at": "2026-04-09T12:00:00Z",
  "duration": 0,
  "transcription": "This is a test webhook from Ramble.",
  "device_id": "7a2b3c4d-...",
  "test": true
}
```

## Timing

Webhooks fire after transcription completes — not after recording. Transcription timing depends on audio length and network conditions.

The webhook queue is independent from transcription. A slow or failing webhook never blocks the UI or other recordings.
