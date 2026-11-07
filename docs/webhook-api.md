# Ramble Webhook API

Ramble can POST each transcript to one URL you choose. This doc is the complete reference for receiving those webhooks. The behavior it describes is specified in [`specs/delivery.md`](../specs/delivery.md) ("Webhooks"); if the two ever disagree, the spec wins.

Webhooks and agents are independent. You can use either, or both at once.

## Setup

In the Ramble app on your iPhone, open **Settings → Where notes go → Webhook** and tap **Add destination**. Enter your HTTPS endpoint URL and save. Ramble has one webhook destination; **Edit destination** changes it and **Remove destination** stops sending ("Transcripts will no longer be sent anywhere.").

> The URL must use HTTPS ("URL must use HTTPS" otherwise). Localhost, loopback, private and link-local IPv4 addresses, and `.internal` hosts are refused, and Save stays disabled until the URL is valid.

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
| `X-Webhook-Signature`  | `sha256=<hex>`: HMAC-SHA256 of the raw request body, keyed with your signing secret. |

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
| `created_at`    | `string` (ISO 8601) | When the recording started, in UTC.                                               |
| `duration`      | `number`            | Recording duration in seconds.                                                    |
| `transcription` | `string`            | Full transcript text. Never empty: notes with no speech detected send no webhook. |
| `device_id`     | `string` (UUID)     | A random per-install ID. Not tied to any account — useful for telling installs apart. |

## Response

Return any **2xx** status code within **10 seconds** to acknowledge receipt. The response body is ignored — Ramble does not read or store it.

## Retries

If your endpoint doesn't return a 2xx within 10 seconds, or the request fails, your iPhone tries again. It makes **3 attempts in total**:

| Attempt | When                          |
| ------- | ----------------------------- |
| 1st     | As soon as the transcript arrives |
| 2nd     | 30 seconds after the 1st fails |
| 3rd     | 2 minutes after the 2nd fails  |

After the third failure the note reads **Didn't send**, and its activity shows the reason (for example "Webhook failed after 3 attempts — HTTP 500"). **Retry** on the note starts 3 fresh attempts, and **More → Resend Webhook** sends a note again. Pending webhooks survive the app closing, and wait while the iPhone is locked.

## Health

The destination in Settings shows a dot for the most recent finished delivery: green when it was delivered, red when it failed, grey before any has finished. VoiceOver reads "Last delivery succeeded", "Last delivery failed" or "Webhook not yet tested".

## Verifying the Signature

Every request includes an `X-Webhook-Signature: sha256=<hex>` header — the HMAC-SHA256 of the exact raw request body, keyed with your signing secret. The app makes the secret (24 random bytes) and keeps it hidden until you reveal it; copy it from the destination editor. Always verify this before processing to confirm the request came from Ramble. Use constant-time comparison to prevent timing attacks.

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

If you tap **Regenerate** on the signing secret, your endpoint will need the new secret to accept requests. Update your server before the next transcript arrives.

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

Open the destination from **Settings → Where notes go → Webhook** and tap **Send test webhook**. The app shows "Test delivered" or "Failed — <reason>". The test payload has the same shape as a real one, with `test` set to `true`, a `recording_id` starting with `test-`, `duration` 0, and the text "This is a test webhook from Ramble." Filter on `test` or the `test-` prefix to skip test payloads in production.

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

Your iPhone sends the webhook once it has the transcript, not when you stop recording. That includes notes recorded on Apple Watch: the watch uploads them straight to Ramble's server, and the iPhone sends the webhook when it next pulls the transcript. If your iPhone is off or offline, the webhook waits until it's back. Expect minutes, not seconds.

The webhook goes from your iPhone straight to your URL. Ramble's server never sees your webhook URL or signing secret.

A slow or failing webhook never blocks the app, other notes, or delivery to your agent.
