import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Webhook API Docs — Ramble",
  description:
    "Set up webhooks to receive transcriptions from Ramble. HMAC-SHA256 signed, automatic retries, any HTTPS endpoint.",
};

export default function Docs() {
  return (
    <main className="flex-1">
      <article className="mx-auto max-w-2xl px-6 py-16 sm:py-24">
        <Link
          href="/"
          className="text-sm text-stone-400 hover:text-stone-600 transition-colors"
        >
          &larr; Back to Ramble
        </Link>
        <h1 className="mt-8 text-3xl font-semibold tracking-tight text-stone-900">
          Webhook API
        </h1>
        <p className="mt-4 text-base leading-relaxed text-stone-500">
          Ramble can automatically POST every transcription to an HTTPS endpoint
          you configure. Signed requests, automatic retries, zero setup on our
          end.
        </p>

        <div className="mt-12 space-y-12 text-sm leading-relaxed text-stone-600">
          {/* Setup */}
          <section>
            <h2 className="text-lg font-semibold text-stone-900">Setup</h2>
            <ol className="mt-3 list-decimal pl-5 space-y-2">
              <li>
                Open Ramble &rarr; <strong>Settings</strong> &rarr;{" "}
                <strong>Webhook</strong>
              </li>
              <li>Toggle webhooks on</li>
              <li>Enter your HTTPS endpoint URL</li>
              <li>
                Copy the auto-generated <strong>signing secret</strong> (base64)
                to your server
              </li>
              <li>
                Tap <strong>Send Test Webhook</strong> to verify connectivity
              </li>
            </ol>
            <p className="mt-3 text-stone-400">
              The URL must be HTTPS. Localhost, private IPs, and cloud metadata
              endpoints are blocked.
            </p>
          </section>

          {/* Request format */}
          <section>
            <h2 className="text-lg font-semibold text-stone-900">
              Request format
            </h2>
            <div className="mt-3 space-y-3">
              <p>
                <strong>Method:</strong> POST
              </p>
              <p>
                <strong>Headers:</strong>
              </p>
              <pre className="mt-1 overflow-x-auto rounded-lg bg-stone-800 p-4 text-xs text-stone-200">
                {`Content-Type: application/json
X-Webhook-Signature: sha256=<hex-encoded-hmac>`}
              </pre>
              <p>
                <strong>Timeout:</strong> 10 seconds
              </p>
            </div>
          </section>

          {/* Payload */}
          <section>
            <h2 className="text-lg font-semibold text-stone-900">Payload</h2>
            <pre className="mt-3 overflow-x-auto rounded-lg bg-stone-800 p-4 text-xs text-stone-200">
              {`{
  "recording_id": "550e8400-e29b-41d4-a716-446655440000",
  "created_at": "2026-03-17T13:19:00Z",
  "duration": 138.5,
  "transcription": "The full transcript text...",
  "device_id": "7a2b3c4d-5e6f-7890-abcd-ef1234567890"
}`}
            </pre>
            <div className="mt-4">
              <table className="w-full text-left">
                <thead>
                  <tr className="border-b border-stone-200">
                    <th className="pb-2 pr-4 font-semibold text-stone-900">
                      Field
                    </th>
                    <th className="pb-2 pr-4 font-semibold text-stone-900">
                      Type
                    </th>
                    <th className="pb-2 font-semibold text-stone-900">
                      Description
                    </th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-stone-100">
                  <tr>
                    <td className="py-2 pr-4 font-mono text-xs">
                      recording_id
                    </td>
                    <td className="py-2 pr-4 whitespace-nowrap">string</td>
                    <td className="py-2">UUID for the recording</td>
                  </tr>
                  <tr>
                    <td className="py-2 pr-4 font-mono text-xs">created_at</td>
                    <td className="py-2 pr-4 whitespace-nowrap">string</td>
                    <td className="py-2">ISO 8601 timestamp</td>
                  </tr>
                  <tr>
                    <td className="py-2 pr-4 font-mono text-xs">duration</td>
                    <td className="py-2 pr-4 whitespace-nowrap">number</td>
                    <td className="py-2">Recording duration in seconds</td>
                  </tr>
                  <tr>
                    <td className="py-2 pr-4 font-mono text-xs">
                      transcription
                    </td>
                    <td className="py-2 pr-4 whitespace-nowrap">string</td>
                    <td className="py-2">
                      Full transcript text (empty string if none)
                    </td>
                  </tr>
                  <tr>
                    <td className="py-2 pr-4 font-mono text-xs">device_id</td>
                    <td className="py-2 pr-4 whitespace-nowrap">string</td>
                    <td className="py-2">
                      Stable per-device identifier (not tied to any account)
                    </td>
                  </tr>
                  <tr>
                    <td className="py-2 pr-4 font-mono text-xs">test</td>
                    <td className="py-2 pr-4 whitespace-nowrap">
                      boolean?
                    </td>
                    <td className="py-2">
                      Present and <code>true</code> only on test webhooks
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>

          {/* Signature verification */}
          <section>
            <h2 className="text-lg font-semibold text-stone-900">
              Verifying signatures
            </h2>
            <p className="mt-3">
              Every request includes an{" "}
              <code className="rounded bg-stone-100 px-1.5 py-0.5 text-xs font-mono text-stone-800">
                X-Webhook-Signature
              </code>{" "}
              header containing an HMAC-SHA256 digest of the raw request body,
              signed with your webhook secret.
            </p>
            <p className="mt-2">
              The header format is{" "}
              <code className="rounded bg-stone-100 px-1.5 py-0.5 text-xs font-mono text-stone-800">
                sha256=&lt;lowercase_hex_digest&gt;
              </code>
              . Compare using a constant-time comparison to prevent timing
              attacks.
            </p>

            <h3 className="mt-6 text-sm font-semibold text-stone-900">
              Node.js
            </h3>
            <pre className="mt-2 overflow-x-auto rounded-lg bg-stone-800 p-4 text-xs text-stone-200">
              {`const crypto = require("crypto");

function verifySignature(body, header, secret) {
  const hmac = crypto.createHmac("sha256", secret);
  hmac.update(body);
  const expected = "sha256=" + hmac.digest("hex");
  return crypto.timingSafeEqual(
    Buffer.from(expected),
    Buffer.from(header)
  );
}`}
            </pre>

            <h3 className="mt-6 text-sm font-semibold text-stone-900">
              Python
            </h3>
            <pre className="mt-2 overflow-x-auto rounded-lg bg-stone-800 p-4 text-xs text-stone-200">
              {`import hmac, hashlib

def verify_signature(body: bytes, header: str, secret: str) -> bool:
    expected = "sha256=" + hmac.new(
        secret.encode(), body, hashlib.sha256
    ).hexdigest()
    return hmac.compare_digest(expected, header)`}
            </pre>
          </section>

          {/* Expected response */}
          <section>
            <h2 className="text-lg font-semibold text-stone-900">
              Expected response
            </h2>
            <p className="mt-3">
              Return any <strong>2xx status code</strong> (200–299) to
              acknowledge receipt. The response body is ignored.
            </p>
            <p className="mt-2">
              Any non-2xx response or network error triggers a retry.
            </p>
          </section>

          {/* Retries */}
          <section>
            <h2 className="text-lg font-semibold text-stone-900">Retries</h2>
            <p className="mt-3">
              Failed deliveries are retried up to <strong>3 times</strong> with
              increasing delays:
            </p>
            <table className="mt-3 w-full text-left">
              <thead>
                <tr className="border-b border-stone-200">
                  <th className="pb-2 pr-4 font-semibold text-stone-900">
                    Attempt
                  </th>
                  <th className="pb-2 font-semibold text-stone-900">Delay</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-stone-100">
                <tr>
                  <td className="py-2 pr-4">1st retry</td>
                  <td className="py-2">5 seconds</td>
                </tr>
                <tr>
                  <td className="py-2 pr-4">2nd retry</td>
                  <td className="py-2">30 seconds</td>
                </tr>
                <tr>
                  <td className="py-2 pr-4">3rd retry</td>
                  <td className="py-2">120 seconds</td>
                </tr>
              </tbody>
            </table>
            <p className="mt-3">
              After all retries are exhausted, the webhook is marked as failed.
              You can manually retry from the recording detail screen in the
              app.
            </p>
          </section>

          {/* Timing */}
          <section>
            <h2 className="text-lg font-semibold text-stone-900">
              When webhooks fire
            </h2>
            <ul className="mt-3 list-disc pl-5 space-y-2">
              <li>
                Webhooks fire <strong>after transcription completes</strong>,
                not after recording.
              </li>
              <li>
                Pending webhooks are persisted to disk and resume when the app
                relaunches.
              </li>
              <li>
                In background mode, webhooks continue for approximately 30
                seconds before pausing until the app returns to foreground.
              </li>
              <li>
                Webhook failures never block the UI or other recordings — each
                webhook is processed independently.
              </li>
            </ul>
          </section>

          {/* Test webhook */}
          <section>
            <h2 className="text-lg font-semibold text-stone-900">
              Test webhooks
            </h2>
            <p className="mt-3">
              The <strong>Send Test Webhook</strong> button in Settings sends a
              request with a{" "}
              <code className="rounded bg-stone-100 px-1.5 py-0.5 text-xs font-mono text-stone-800">
                &quot;test&quot;: true
              </code>{" "}
              flag, a{" "}
              <code className="rounded bg-stone-100 px-1.5 py-0.5 text-xs font-mono text-stone-800">
                recording_id
              </code>{" "}
              prefixed with{" "}
              <code className="rounded bg-stone-100 px-1.5 py-0.5 text-xs font-mono text-stone-800">
                test-
              </code>
              , zero duration, and the transcription{" "}
              <em>&quot;This is a test webhook from Ramble.&quot;</em>
            </p>
            <p className="mt-2">
              Use this to verify your endpoint is reachable and your signature
              verification is working before relying on it in production.
            </p>
          </section>

          {/* Security */}
          <section>
            <h2 className="text-lg font-semibold text-stone-900">
              Security notes
            </h2>
            <ul className="mt-3 list-disc pl-5 space-y-2">
              <li>
                <strong>Always verify the signature</strong> before processing
                a webhook. This confirms the request came from Ramble with your
                secret.
              </li>
              <li>
                Use <strong>constant-time comparison</strong> (e.g.{" "}
                <code className="rounded bg-stone-100 px-1.5 py-0.5 text-xs font-mono text-stone-800">
                  crypto.timingSafeEqual
                </code>{" "}
                or{" "}
                <code className="rounded bg-stone-100 px-1.5 py-0.5 text-xs font-mono text-stone-800">
                  hmac.compare_digest
                </code>
                ) to prevent timing attacks.
              </li>
              <li>
                The signing secret is stored in your device&apos;s Keychain. If
                you regenerate it in Settings, update your server accordingly.
              </li>
              <li>
                Webhook URLs must use HTTPS. HTTP, localhost, and private IPs
                are rejected.
              </li>
            </ul>
          </section>
        </div>
      </article>
    </main>
  );
}
