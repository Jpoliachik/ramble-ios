import type { Metadata } from "next";
import Link from "next/link";
import { CodeBlock, InlineCode } from "@/components/code-block";

export const metadata: Metadata = {
  title: "Webhook API Docs — Ramble",
  description:
    "Set up webhooks to receive transcriptions from Ramble. HMAC-SHA256 signed, automatic retries, any HTTPS endpoint.",
};

function SectionLink({ id, children }: { id: string; children: string }) {
  return (
    <a
      href={`#${id}`}
      className="block py-1 text-stone-400 transition-colors hover:text-stone-900"
    >
      {children}
    </a>
  );
}

function H2({ id, children }: { id: string; children: string }) {
  return (
    <h2 id={id} className="scroll-mt-8 text-xl font-semibold text-stone-900">
      {children}
    </h2>
  );
}

function H3({ children }: { children: string }) {
  return (
    <h3 className="text-sm font-semibold uppercase tracking-wide text-stone-400">
      {children}
    </h3>
  );
}

function Param({
  name,
  type,
  required = true,
  children,
}: {
  name: string;
  type: string;
  required?: boolean;
  children: React.ReactNode;
}) {
  return (
    <div className="border-b border-stone-100 py-3 last:border-0">
      <div className="flex items-baseline gap-3">
        <span className="font-mono text-[13px] font-semibold text-stone-900">
          {name}
        </span>
        <span className="font-mono text-xs text-stone-400">{type}</span>
        {!required && (
          <span className="rounded bg-stone-100 px-1.5 py-0.5 text-xs text-stone-400">
            optional
          </span>
        )}
      </div>
      <p className="mt-1 text-sm text-stone-500">{children}</p>
    </div>
  );
}

export default function Docs() {
  return (
    <main className="flex-1">
      <div className="mx-auto max-w-6xl px-6 py-16 sm:py-24 lg:grid lg:grid-cols-[220px_1fr] lg:gap-12">
        {/* Sidebar nav */}
        <nav className="hidden lg:block">
          <div className="sticky top-8 text-sm">
            <p className="font-semibold text-stone-900">On this page</p>
            <div className="mt-3 space-y-0.5">
              <SectionLink id="overview">Overview</SectionLink>
              <SectionLink id="quick-start">Quick start</SectionLink>
              <SectionLink id="request-format">Request format</SectionLink>
              <SectionLink id="payload">Payload</SectionLink>
              <SectionLink id="signature-verification">
                Signature verification
              </SectionLink>
              <SectionLink id="full-examples">Full examples</SectionLink>
              <SectionLink id="retries">Retries</SectionLink>
              <SectionLink id="test-webhooks">Test webhooks</SectionLink>
              <SectionLink id="behavior">Behavior</SectionLink>
              <SectionLink id="security">Security</SectionLink>
            </div>
          </div>
        </nav>

        {/* Main content */}
        <article className="min-w-0 max-w-3xl">
          <Link
            href="/"
            className="text-sm text-stone-400 hover:text-stone-600 transition-colors"
          >
            &larr; Back to Ramble
          </Link>

          <h1 className="mt-8 text-3xl font-semibold tracking-tight text-stone-900 sm:text-4xl">
            Webhook API
          </h1>
          <p className="mt-4 text-lg leading-relaxed text-stone-500">
            Receive transcriptions as they happen. Every transcript can POST to
            your endpoint — signed, retried, and delivered.
          </p>

          <div className="mt-14 space-y-16 text-sm leading-relaxed text-stone-600">
            {/* Overview */}
            <section>
              <H2 id="overview">Overview</H2>
              <div className="mt-4 rounded-lg border border-stone-200 bg-stone-50 p-4">
                <div className="grid gap-4 sm:grid-cols-2">
                  <div>
                    <p className="text-xs font-medium uppercase tracking-wide text-stone-400">
                      Method
                    </p>
                    <p className="mt-1 font-mono text-sm text-stone-900">
                      POST
                    </p>
                  </div>
                  <div>
                    <p className="text-xs font-medium uppercase tracking-wide text-stone-400">
                      Content-Type
                    </p>
                    <p className="mt-1 font-mono text-sm text-stone-900">
                      application/json
                    </p>
                  </div>
                  <div>
                    <p className="text-xs font-medium uppercase tracking-wide text-stone-400">
                      Signing
                    </p>
                    <p className="mt-1 font-mono text-sm text-stone-900">
                      HMAC-SHA256
                    </p>
                  </div>
                  <div>
                    <p className="text-xs font-medium uppercase tracking-wide text-stone-400">
                      Timeout
                    </p>
                    <p className="mt-1 font-mono text-sm text-stone-900">
                      10 seconds
                    </p>
                  </div>
                  <div>
                    <p className="text-xs font-medium uppercase tracking-wide text-stone-400">
                      Retries
                    </p>
                    <p className="mt-1 font-mono text-sm text-stone-900">
                      3 attempts (5s, 30s, 120s)
                    </p>
                  </div>
                  <div>
                    <p className="text-xs font-medium uppercase tracking-wide text-stone-400">
                      Success
                    </p>
                    <p className="mt-1 font-mono text-sm text-stone-900">
                      Any 2xx status
                    </p>
                  </div>
                </div>
              </div>
            </section>

            {/* Quick start */}
            <section>
              <H2 id="quick-start">Quick start</H2>
              <ol className="mt-4 space-y-3">
                <li className="flex gap-3">
                  <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-stone-900 text-xs font-semibold text-white">
                    1
                  </span>
                  <span>
                    In Ramble, go to{" "}
                    <strong>Settings &rarr; Webhook</strong> and toggle it on.
                  </span>
                </li>
                <li className="flex gap-3">
                  <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-stone-900 text-xs font-semibold text-white">
                    2
                  </span>
                  <span>
                    Enter your HTTPS endpoint URL.
                  </span>
                </li>
                <li className="flex gap-3">
                  <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-stone-900 text-xs font-semibold text-white">
                    3
                  </span>
                  <span>
                    Copy the <strong>signing secret</strong> (auto-generated,
                    base64) to your server.
                  </span>
                </li>
                <li className="flex gap-3">
                  <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-stone-900 text-xs font-semibold text-white">
                    4
                  </span>
                  <span>
                    Tap <strong>Send Test Webhook</strong> to verify everything
                    works.
                  </span>
                </li>
              </ol>
              <div className="mt-4 rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-800">
                The URL must use HTTPS. Localhost, private IPs, and cloud
                metadata endpoints are blocked.
              </div>
            </section>

            {/* Request format */}
            <section>
              <H2 id="request-format">Request format</H2>
              <p className="mt-4">
                Ramble sends a <InlineCode>POST</InlineCode> request to your
                endpoint with the following headers:
              </p>
              <div className="mt-4">
                <CodeBlock language="http">
                  {`POST https://your-endpoint.com/webhook HTTP/1.1
Content-Type: application/json
X-Webhook-Signature: sha256=a1b2c3d4e5f6...`}
                </CodeBlock>
              </div>
              <p className="mt-4">
                Your endpoint has <strong>10 seconds</strong> to respond.
                Return any <strong>2xx status code</strong> to acknowledge
                receipt. The response body is ignored.
              </p>
            </section>

            {/* Payload */}
            <section>
              <H2 id="payload">Payload</H2>
              <div className="mt-4">
                <CodeBlock language="json">
                  {`{
  "recording_id": "550e8400-e29b-41d4-a716-446655440000",
  "created_at": "2026-03-17T13:19:00Z",
  "duration": 138.5,
  "transcription": "Just had a great idea for the landing page. We should lead with the webhook angle...",
  "device_id": "7a2b3c4d-5e6f-7890-abcd-ef1234567890"
}`}
                </CodeBlock>
              </div>
              <div className="mt-6 rounded-lg border border-stone-200">
                <Param name="recording_id" type="string">
                  UUID v4. Unique identifier for this recording.
                </Param>
                <Param name="created_at" type="string">
                  ISO 8601 timestamp of when the recording was created.
                </Param>
                <Param name="duration" type="number">
                  Recording duration in seconds.
                </Param>
                <Param name="transcription" type="string">
                  Full transcript text. Empty string if transcription produced
                  no output.
                </Param>
                <Param name="device_id" type="string">
                  Stable per-device UUID. Not tied to any account — useful for
                  distinguishing multiple devices.
                </Param>
                <Param name="test" type="boolean" required={false}>
                  Present and <InlineCode>true</InlineCode> only on test
                  webhooks sent from Settings.
                </Param>
              </div>
            </section>

            {/* Signature verification */}
            <section>
              <H2 id="signature-verification">Signature verification</H2>
              <p className="mt-4">
                Every request includes an{" "}
                <InlineCode>X-Webhook-Signature</InlineCode> header. The value
                is an HMAC-SHA256 digest of the raw request body, keyed with
                your signing secret.
              </p>
              <div className="mt-4 rounded-lg border border-stone-200 bg-stone-50 p-4">
                <p className="font-mono text-xs text-stone-600">
                  <span className="text-stone-400">Header format:</span>{" "}
                  sha256=&lt;lowercase_hex_digest&gt;
                </p>
              </div>
              <p className="mt-4">
                Always use a constant-time comparison to prevent timing attacks.
              </p>

              <div className="mt-6 space-y-4">
                <H3>Node.js</H3>
                <CodeBlock filename="verify.js">
                  {`const crypto = require("crypto");

function verifySignature(rawBody, signatureHeader, secret) {
  const hmac = crypto.createHmac("sha256", secret);
  hmac.update(rawBody);
  const expected = "sha256=" + hmac.digest("hex");

  return crypto.timingSafeEqual(
    Buffer.from(expected),
    Buffer.from(signatureHeader)
  );
}`}
                </CodeBlock>
              </div>

              <div className="mt-6 space-y-4">
                <H3>Python</H3>
                <CodeBlock filename="verify.py">
                  {`import hmac
import hashlib

def verify_signature(raw_body: bytes, signature_header: str, secret: str) -> bool:
    expected = "sha256=" + hmac.new(
        secret.encode(),
        raw_body,
        hashlib.sha256,
    ).hexdigest()
    return hmac.compare_digest(expected, signature_header)`}
                </CodeBlock>
              </div>

              <div className="mt-6 space-y-4">
                <H3>cURL (test manually)</H3>
                <CodeBlock language="bash">
                  {`# Compute the signature for a test payload
SECRET="your-base64-secret-here"
BODY='{"recording_id":"test","transcription":"hello"}'
SIG=$(echo -n "$BODY" | openssl dgst -sha256 -hmac "$SECRET" | cut -d' ' -f2)

curl -X POST https://your-endpoint.com/webhook \\
  -H "Content-Type: application/json" \\
  -H "X-Webhook-Signature: sha256=$SIG" \\
  -d "$BODY"`}
                </CodeBlock>
              </div>
            </section>

            {/* Full examples */}
            <section>
              <H2 id="full-examples">Full examples</H2>
              <p className="mt-4">
                Complete webhook receivers you can copy and deploy. Each example
                verifies the signature and logs the transcription.
              </p>

              <div className="mt-6 space-y-4">
                <H3>Express (Node.js)</H3>
                <CodeBlock filename="server.js">
                  {`const express = require("express");
const crypto = require("crypto");

const app = express();
const WEBHOOK_SECRET = process.env.RAMBLE_WEBHOOK_SECRET;

// Important: use raw body for signature verification
app.post(
  "/webhook",
  express.raw({ type: "application/json" }),
  (req, res) => {
    const signature = req.headers["x-webhook-signature"];
    if (!signature) {
      return res.status(401).json({ error: "Missing signature" });
    }

    // Verify HMAC-SHA256 signature
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

    // Parse and handle the webhook
    const payload = JSON.parse(req.body);

    if (payload.test) {
      console.log("Test webhook received");
      return res.status(200).json({ ok: true });
    }

    console.log("New transcription:", {
      id: payload.recording_id,
      duration: payload.duration,
      text: payload.transcription,
    });

    // TODO: Do something with the transcription
    // - Save to database
    // - Forward to an AI agent
    // - Post to Slack
    // - Append to a Notion page

    res.status(200).json({ ok: true });
  }
);

app.listen(3000, () => console.log("Listening on :3000"));`}
                </CodeBlock>
              </div>

              <div className="mt-6 space-y-4">
                <H3>Flask (Python)</H3>
                <CodeBlock filename="server.py">
                  {`from flask import Flask, request, jsonify
import hmac
import hashlib
import os

app = Flask(__name__)
WEBHOOK_SECRET = os.environ["RAMBLE_WEBHOOK_SECRET"]


def verify_signature(raw_body: bytes, header: str) -> bool:
    expected = "sha256=" + hmac.new(
        WEBHOOK_SECRET.encode(),
        raw_body,
        hashlib.sha256,
    ).hexdigest()
    return hmac.compare_digest(expected, header)


@app.route("/webhook", methods=["POST"])
def webhook():
    signature = request.headers.get("X-Webhook-Signature", "")

    if not verify_signature(request.get_data(), signature):
        return jsonify({"error": "Invalid signature"}), 401

    payload = request.get_json()

    if payload.get("test"):
        print("Test webhook received")
        return jsonify({"ok": True})

    print(f"New transcription: {payload['recording_id']}")
    print(f"  Duration: {payload['duration']}s")
    print(f"  Text: {payload['transcription'][:100]}...")

    # TODO: Do something with the transcription

    return jsonify({"ok": True})


if __name__ == "__main__":
    app.run(port=3000)`}
                </CodeBlock>
              </div>
            </section>

            {/* Retries */}
            <section>
              <H2 id="retries">Retries</H2>
              <p className="mt-4">
                Any non-2xx response or network error triggers automatic
                retries with exponential backoff.
              </p>
              <div className="mt-4 overflow-hidden rounded-lg border border-stone-200">
                <table className="w-full text-left">
                  <thead>
                    <tr className="border-b border-stone-200 bg-stone-50">
                      <th className="px-4 py-2.5 text-xs font-semibold uppercase tracking-wide text-stone-500">
                        Attempt
                      </th>
                      <th className="px-4 py-2.5 text-xs font-semibold uppercase tracking-wide text-stone-500">
                        Delay
                      </th>
                      <th className="px-4 py-2.5 text-xs font-semibold uppercase tracking-wide text-stone-500">
                        Cumulative
                      </th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-stone-100">
                    <tr>
                      <td className="px-4 py-2.5 font-medium text-stone-900">
                        Initial
                      </td>
                      <td className="px-4 py-2.5 font-mono text-xs">
                        Immediate
                      </td>
                      <td className="px-4 py-2.5 font-mono text-xs">0s</td>
                    </tr>
                    <tr>
                      <td className="px-4 py-2.5 font-medium text-stone-900">
                        1st retry
                      </td>
                      <td className="px-4 py-2.5 font-mono text-xs">5s</td>
                      <td className="px-4 py-2.5 font-mono text-xs">~5s</td>
                    </tr>
                    <tr>
                      <td className="px-4 py-2.5 font-medium text-stone-900">
                        2nd retry
                      </td>
                      <td className="px-4 py-2.5 font-mono text-xs">30s</td>
                      <td className="px-4 py-2.5 font-mono text-xs">~35s</td>
                    </tr>
                    <tr>
                      <td className="px-4 py-2.5 font-medium text-stone-900">
                        3rd retry
                      </td>
                      <td className="px-4 py-2.5 font-mono text-xs">120s</td>
                      <td className="px-4 py-2.5 font-mono text-xs">
                        ~2.5 min
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <p className="mt-4">
                After all retries are exhausted, the webhook is marked as
                failed. You can manually retry from the recording detail screen
                in the app.
              </p>
            </section>

            {/* Test webhooks */}
            <section>
              <H2 id="test-webhooks">Test webhooks</H2>
              <p className="mt-4">
                Use <strong>Settings &rarr; Send Test Webhook</strong> to verify
                your endpoint before going live. The test payload looks like:
              </p>
              <div className="mt-4">
                <CodeBlock language="json">
                  {`{
  "recording_id": "test-550e8400-e29b-41d4-a716-446655440000",
  "created_at": "2026-04-09T12:00:00Z",
  "duration": 0,
  "transcription": "This is a test webhook from Ramble.",
  "device_id": "7a2b3c4d-5e6f-7890-abcd-ef1234567890",
  "test": true
}`}
                </CodeBlock>
              </div>
              <p className="mt-4">
                Filter on <InlineCode>{`"test": true`}</InlineCode> or
                the <InlineCode>test-</InlineCode> prefix on{" "}
                <InlineCode>recording_id</InlineCode> to skip test payloads in
                production.
              </p>
            </section>

            {/* Behavior */}
            <section>
              <H2 id="behavior">Behavior</H2>
              <div className="mt-4 space-y-3">
                <div className="flex gap-3">
                  <span className="mt-0.5 shrink-0 text-sage-500">
                    &#8226;
                  </span>
                  <span>
                    Webhooks fire <strong>after transcription completes</strong>,
                    not immediately after recording.
                  </span>
                </div>
                <div className="flex gap-3">
                  <span className="mt-0.5 shrink-0 text-sage-500">
                    &#8226;
                  </span>
                  <span>
                    Pending webhooks are <strong>persisted to disk</strong> and
                    resume automatically when the app relaunches.
                  </span>
                </div>
                <div className="flex gap-3">
                  <span className="mt-0.5 shrink-0 text-sage-500">
                    &#8226;
                  </span>
                  <span>
                    In background mode, webhooks continue for ~30 seconds
                    before pausing until the app returns to foreground.
                  </span>
                </div>
                <div className="flex gap-3">
                  <span className="mt-0.5 shrink-0 text-sage-500">
                    &#8226;
                  </span>
                  <span>
                    Each webhook is processed independently — failures never
                    block the UI or other recordings.
                  </span>
                </div>
              </div>
            </section>

            {/* Security */}
            <section>
              <H2 id="security">Security</H2>
              <div className="mt-4 space-y-4">
                <div className="rounded-lg border border-stone-200 p-4">
                  <p className="font-semibold text-stone-900">
                    Always verify signatures
                  </p>
                  <p className="mt-1 text-stone-500">
                    Check <InlineCode>X-Webhook-Signature</InlineCode> on every
                    request before processing. This confirms the request was
                    sent by Ramble with your secret.
                  </p>
                </div>
                <div className="rounded-lg border border-stone-200 p-4">
                  <p className="font-semibold text-stone-900">
                    Use constant-time comparison
                  </p>
                  <p className="mt-1 text-stone-500">
                    Use{" "}
                    <InlineCode>crypto.timingSafeEqual</InlineCode> (Node.js)
                    or <InlineCode>hmac.compare_digest</InlineCode> (Python)
                    to prevent timing attacks.
                  </p>
                </div>
                <div className="rounded-lg border border-stone-200 p-4">
                  <p className="font-semibold text-stone-900">
                    HTTPS required
                  </p>
                  <p className="mt-1 text-stone-500">
                    Webhook URLs must use HTTPS. HTTP, localhost, private IP
                    ranges, and cloud metadata endpoints are all rejected.
                  </p>
                </div>
                <div className="rounded-lg border border-stone-200 p-4">
                  <p className="font-semibold text-stone-900">
                    Rotate secrets carefully
                  </p>
                  <p className="mt-1 text-stone-500">
                    The signing secret is stored in your device&apos;s Keychain.
                    If you regenerate it in Settings, update your server before
                    the next transcription completes.
                  </p>
                </div>
              </div>
            </section>
          </div>
        </article>
      </div>
    </main>
  );
}
