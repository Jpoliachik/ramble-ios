import type { Metadata } from "next";
import Link from "next/link";
import DocsSidebar from "@/components/docs-sidebar";
import CopyLlmButton from "@/components/copy-llm-button";
import { MIN_IOS, MIN_WATCHOS, PAIR_CODE_TTL, RETENTION, WATCH_MODELS } from "@/lib/site";

export const metadata: Metadata = {
  title: "Requirements and troubleshooting",
  description: `Ramble needs iOS ${MIN_IOS} and watchOS ${MIN_WATCHOS} or later. Fixes for the common problems: a missing watch app, recordings stuck on the watch, and an agent that isn't picking up.`,
};

function SectionHeader({ id, children }: { id: string; children: React.ReactNode }) {
  return (
    <h2 id={id} className="scroll-mt-20 font-serif text-2xl font-semibold tracking-tight text-stone-900">
      {children}
    </h2>
  );
}

// Each question is collapsed so the page stays skimmable. The answer is still
// in the HTML, so an agent reading the page sees all of it.
function Question({ id, q, children }: { id: string; q: string; children: React.ReactNode }) {
  return (
    <details id={id} className="group scroll-mt-20 border-b border-stone-200 py-3">
      <summary className="cursor-pointer list-none font-medium text-stone-900 [&::-webkit-details-marker]:hidden">
        <span className="mr-2 inline-block text-stone-400 transition-transform group-open:rotate-90">&rsaquo;</span>
        {q}
      </summary>
      <div className="mt-3 space-y-3 pl-5">{children}</div>
    </details>
  );
}

const linkClass = "text-brand-text underline-offset-2 hover:underline";

export default function HelpDocs() {
  return (
    <main className="flex-1">
      <div className="mx-auto max-w-6xl px-6 py-16 sm:py-24 lg:grid lg:grid-cols-[220px_1fr] lg:gap-12">
        <DocsSidebar page="help" />

        <article className="min-w-0 max-w-3xl">
          <div className="flex items-center justify-between">
            <Link href="/" className="text-sm text-stone-500 hover:text-stone-900 transition-colors">
              &larr; Back to Ramble
            </Link>
            <CopyLlmButton />
          </div>

          <h1 className="mt-8 font-serif text-3xl font-semibold tracking-tight text-stone-900 sm:text-4xl">
            Requirements and troubleshooting
          </h1>
          <p className="mt-4 text-lg leading-relaxed text-stone-500">
            What Ramble runs on, and what to check when something doesn&rsquo;t show up.
          </p>

          <div className="mt-14 space-y-16 text-sm leading-relaxed text-stone-600">
            <section className="space-y-4">
              <SectionHeader id="requirements">Requirements</SectionHeader>
              <ul className="list-disc space-y-2 pl-5">
                <li>
                  <strong className="font-medium text-stone-900">iPhone:</strong> iOS {MIN_IOS} or later.
                </li>
                <li>
                  <strong className="font-medium text-stone-900">Apple Watch:</strong> watchOS {MIN_WATCHOS} or{" "}
                  later. That&rsquo;s {WATCH_MODELS}.
                </li>
              </ul>
              <p>
                To see your versions, open Settings → General → About on the iPhone, and the Watch app on the iPhone →
                General → About for the watch.
              </p>
            </section>

            <section className="space-y-2">
              <SectionHeader id="watch">Apple Watch</SectionHeader>
              <Question id="watch-app-missing" q="The iPhone app installed, but the watch app didn’t">
                <p>
                  Check the watch&rsquo;s watchOS version first. If it&rsquo;s older than {MIN_WATCHOS}, the App Store
                  installs the iPhone app and quietly skips the watch app. Update the watch in the Watch app on the
                  iPhone → General → Software Update.
                </p>
                <p>
                  If the version is fine, open the Watch app on the iPhone, scroll down to Available Apps, and tap Install
                  next to Ramble. To have this happen on its own next time, turn on Automatic App Install under Watch app →
                  App Store.
                </p>
              </Question>
              <Question id="mic" q="The watch says “Allow microphone in Settings”">
                <p>
                  Ramble needs the microphone on the watch. On the watch, open Settings → Privacy &amp; Security →
                  Microphone and turn on Ramble.
                </p>
              </Question>
              <Question id="stuck-on-watch" q="A recording says “Saved on watch” or “Sending to iPhone”">
                <p>
                  That&rsquo;s normal when the iPhone isn&rsquo;t nearby. Recordings stay on the watch until the iPhone
                  has them, then send on their own. Nothing is lost. If one seems stuck with the iPhone close by, open
                  Ramble on the iPhone.
                </p>
              </Question>
            </section>

            <section className="space-y-2">
              <SectionHeader id="transcription">Transcription</SectionHeader>
              <Question id="speech-permission" q="On-device transcription fails or asks for permission">
                <p>
                  Apple Speech needs speech recognition permission. Turn it on in iPhone Settings → Ramble → Speech
                  Recognition, then tap Retry on the recording.
                </p>
                <p>
                  If the recording says Speech Model Required, tap Download Speech Model &amp; Retry. It needs a network
                  connection once; after that it works offline.
                </p>
              </Question>
              <Question id="cloud-transcription" q="Cloud transcription doesn’t work">
                <p>
                  Cloud models need the optional upgrade and a network connection. If Ramble says it couldn&rsquo;t
                  verify the device with Apple, wait a moment and retry. You can always switch back to Apple Speech in
                  Settings.
                </p>
              </Question>
            </section>

            <section className="space-y-2">
              <SectionHeader id="agent">Your agent</SectionHeader>
              <Question id="agent-not-picking-up" q="My agent isn’t getting my recordings">
                <p>
                  Open Settings → Connect agent on the iPhone. Each agent shows when it last checked and how many
                  transcripts are waiting for it.
                </p>
                <ul className="list-disc space-y-2 pl-5">
                  <li>
                    <strong className="font-medium text-stone-900">&ldquo;Hasn&rsquo;t checked in yet&rdquo;</strong> or
                    an old check time: the agent isn&rsquo;t checking. Ask it to set up the check again, or paste it the{" "}
                    <Link href="/docs#agent-instructions" className={linkClass}>
                      instructions for the agent
                    </Link>
                    . Transcripts wait for {RETENTION}, so nothing is lost yet.
                  </li>
                  <li>
                    <strong className="font-medium text-stone-900">Transcripts waiting:</strong> they reached the relay
                    and the agent just hasn&rsquo;t picked them up. Many agents check on a schedule, so this can take a
                    while.
                  </li>
                  <li>
                    <strong className="font-medium text-stone-900">Nothing waiting, nothing received:</strong> the
                    recording may not have been sent. Open it on the iPhone and tap Send to Agent.
                  </li>
                </ul>
              </Question>
              <Question id="not-sent" q="A recording says “Not sent · connect your agent”">
                <p>
                  Ramble only sends recordings made while an agent is connected. Connect one in Settings → Connect agent,
                  then open the recording and tap Send to Agent.
                </p>
              </Question>
              <Question id="code-expired" q="The pairing code expired or didn’t work">
                <p>
                  A code works once and expires after {PAIR_CODE_TTL}. Tap New code in Settings → Connect agent and
                  paste the new one to your agent.
                </p>
              </Question>
              <Question id="agent-errors" q="My agent gets 401, 403, or connection errors">
                <p>
                  401 means the agent was disconnected; pair it again with a new code. 403 usually means its HTTP client
                  is filtered, and it should send a User-Agent header. Agents in a sandbox need the relay host on their
                  network allowlist. Details are in{" "}
                  <Link href="/docs#requests" className={linkClass}>
                    making requests
                  </Link>{" "}
                  and{" "}
                  <Link href="/docs#platforms" className={linkClass}>
                    platform notes
                  </Link>
                  .
                </p>
              </Question>
              <Question id="webhook-failed" q="A webhook delivery failed">
                <p>
                  Ramble retries 3 times, then marks it failed. Fix the endpoint, then open the recording and tap Resend
                  Webhook. See{" "}
                  <Link href="/docs/webhooks" className={linkClass}>
                    webhooks
                  </Link>
                  .
                </p>
              </Question>
            </section>
          </div>
        </article>
      </div>
    </main>
  );
}
