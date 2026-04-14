import type { Metadata } from "next";
import Link from "next/link";
import { CodeBlock, InlineCode } from "@/components/code-block";
import DocsSidebar from "@/components/docs-sidebar";
import CopyLlmButton from "@/components/copy-llm-button";

export const metadata: Metadata = {
  title: "Receive Transcripts — Ramble",
  description:
    "Ramble auto-POSTs every transcript to your endpoint. Set up a webhook to pipe voice notes into your agent, workflow, or backend.",
};

function StepHeader({ id, step, children }: { id: string; step: number; children: string }) {
  return (
    <div id={id} className="scroll-mt-8 flex items-center gap-4">
      <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-stone-900 font-serif text-base font-semibold text-white">
        {step}
      </span>
      <h2 className="font-serif text-xl font-semibold text-stone-900">{children}</h2>
    </div>
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
    <div className="border-b border-stone-100 px-4 py-3 last:border-0">
      <div className="flex items-baseline gap-3">
        <span className="font-mono text-[13px] font-semibold text-stone-900">{name}</span>
        <span className="font-mono text-xs text-stone-400">{type}</span>
        {!required && <span className="rounded bg-stone-100 px-1.5 py-0.5 text-xs text-stone-400">optional</span>}
      </div>
      <p className="mt-1 text-sm text-stone-500">{children}</p>
    </div>
  );
}

export default function Docs() {
  return (
    <main className="flex-1">
      <div className="mx-auto max-w-6xl px-6 py-16 sm:py-24 lg:grid lg:grid-cols-[220px_1fr] lg:gap-12">
        <DocsSidebar />

        {/* Main content */}
        <article className="min-w-0 max-w-3xl">
          <div className="flex items-center justify-between">
            <Link href="/" className="text-sm text-stone-400 hover:text-stone-600 transition-colors">
              &larr; Back to Ramble
            </Link>
            <CopyLlmButton />
          </div>

          <h1 className="mt-8 font-serif text-3xl font-semibold tracking-tight text-stone-900 sm:text-4xl">
            Receive your transcripts
          </h1>
          <p className="mt-4 text-lg leading-relaxed text-stone-500">
            Every time you finish a recording, Ramble can automatically POST the transcript to any HTTPS endpoint — an
            AI agent, a workflow, your own backend. Four steps to set it up.
          </p>

          <div className="mt-14 space-y-16 text-sm leading-relaxed text-stone-600">
            {/* Step 1 */}
            <section>
              <StepHeader id="step-1" step={1}>
                Enable the webhook
              </StepHeader>
              <div className="mt-6 space-y-5 pl-14">
                <p>
                  In Ramble, go to <strong>Settings &rarr; Webhook</strong> and toggle it on. Enter your endpoint URL
                  (must be HTTPS) and copy the auto-generated <strong>signing secret</strong> (base64) — you&apos;ll
                  need it on your server to verify requests.
                </p>
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src="/ramble/webhook-settings.png"
                  alt="Ramble webhook settings screen showing the Post-Transcription Webhook toggle, URL field, and signing secret controls"
                  className="mx-auto max-w-xs rounded-2xl shadow-md"
                />
              </div>
            </section>

            {/* Step 2 */}
            <section>
              <StepHeader id="step-2" step={2}>
                Receive the POST
              </StepHeader>
              <div className="mt-6 space-y-6 pl-14">
                <p>
                  After transcription completes, Ramble sends a <InlineCode>POST</InlineCode> with{" "}
                  <InlineCode>Content-Type: application/json</InlineCode> to your endpoint. Return any{" "}
                  <strong>2xx</strong> within <strong>10 seconds</strong> to acknowledge receipt. If your endpoint is
                  down or returns an error, Ramble retries up to 3 times with backoff (5s, 30s, 120s) and persists
                  pending webhooks to disk so nothing is lost if the app is closed.
                </p>

                <p>Here&apos;s the payload:</p>

                <CodeBlock language="json">
                  {`{
  "recording_id": "550e8400-e29b-41d4-a716-446655440000",
  "created_at": "2026-03-17T13:19:00Z",
  "duration": 138.5,
  "transcription": "Just had a great idea for the landing page...",
  "device_id": "7a2b3c4d-5e6f-7890-abcd-ef1234567890"
}`}
                </CodeBlock>

                <div className="rounded-lg border border-stone-200">
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
                    Full transcript text. Empty string if transcription produced no output.
                  </Param>
                  <Param name="device_id" type="string">
                    Stable per-device UUID. Not tied to any account — useful for distinguishing multiple devices.
                  </Param>
                </div>
              </div>
            </section>

            {/* Step 3 */}
            <section>
              <StepHeader id="step-3" step={3}>
                Verify the signature
              </StepHeader>
              <div className="mt-6 space-y-4 pl-14">
                <p>
                  Every request includes an <InlineCode>X-Webhook-Signature</InlineCode> header — an HMAC-SHA256 digest
                  of the raw request body, keyed with your signing secret. Always verify this before processing to
                  confirm the request came from Ramble. Use constant-time comparison to prevent timing attacks.
                </p>

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

                <p>
                  If you regenerate the signing secret in Settings, update your server before the next transcription
                  completes.
                </p>

                <details className="rounded-lg border border-stone-200">
                  <summary className="cursor-pointer px-4 py-3 text-sm font-medium text-stone-700 hover:text-stone-900">
                    Full Express server example
                  </summary>
                  <div className="border-t border-stone-200 p-4">
                    <CodeBlock filename="server.js">
                      {`const express = require("express");
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

app.listen(3000, () => console.log("Listening on :3000"));`}
                    </CodeBlock>
                  </div>
                </details>
              </div>
            </section>

            {/* Step 4 */}
            <section>
              <StepHeader id="step-4" step={4}>
                Test it
              </StepHeader>
              <div className="mt-6 space-y-4 pl-14">
                <p>
                  Tap <strong>Settings &rarr; Send Test Webhook</strong> to fire a test payload at your endpoint. The
                  test payload is identical to a real one, with two differences: <InlineCode>test</InlineCode> is{" "}
                  <InlineCode>true</InlineCode>, and <InlineCode>recording_id</InlineCode> is prefixed with{" "}
                  <InlineCode>test-</InlineCode>. Filter on either to skip test payloads in production.
                </p>

                <CodeBlock language="json">
                  {`{
  "recording_id": "test-550e8400-...",
  "created_at": "2026-04-09T12:00:00Z",
  "duration": 0,
  "transcription": "This is a test webhook from Ramble.",
  "device_id": "7a2b3c4d-...",
  "test": true
}`}
                </CodeBlock>

                <p>
                  If the test succeeds, you&apos;re all set — every future transcription will POST automatically. If it
                  fails, check that your endpoint returns a 2xx and that you&apos;re verifying the signature with the
                  correct secret.
                </p>
              </div>
            </section>
          </div>
        </article>
      </div>
    </main>
  );
}
