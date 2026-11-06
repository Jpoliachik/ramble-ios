import type { Metadata } from "next";
import Link from "next/link";
import DocsSidebar from "@/components/docs-sidebar";
import CopyLlmButton from "@/components/copy-llm-button";
import {
  FAIR_USE,
  FREE_NOTES,
  MIN_IOS,
  MIN_WATCHOS,
  PAIR_CODE_TTL,
  RETENTION,
  SUPPORT_EMAIL,
  WATCH_MODELS,
} from "@/lib/site";

export const metadata: Metadata = {
  title: "Requirements and troubleshooting",
  description: `Ramble needs iOS ${MIN_IOS} and watchOS ${MIN_WATCHOS} or later. Fixes for the common problems: a missing watch app, notes waiting on the watch, held notes, and an agent that isn't picking up.`,
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

function Strong({ children }: { children: React.ReactNode }) {
  return <strong className="font-medium text-stone-900">{children}</strong>;
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
                  <Strong>iPhone:</Strong> iOS {MIN_IOS} or later.
                </li>
                <li>
                  <Strong>Apple Watch:</Strong> watchOS {MIN_WATCHOS} or later. That&rsquo;s {WATCH_MODELS}.
                </li>
                <li>
                  <Strong>A connection, now and then.</Strong> Recording works anywhere. Transcription happens in the
                  cloud, so notes send once the watch has Wi-Fi, cellular, or your iPhone nearby.
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
              <Question id="set-up" q="The watch shows “Set up”">
                <p>
                  The watch isn&rsquo;t connected to Ramble yet. Open Ramble on your iPhone once, and tap Get started if
                  it&rsquo;s your first time. The watch connects on its own and waiting notes send. Until then
                  they&rsquo;re safe on the watch.
                </p>
              </Question>
              <Question id="no-phone" q="The watch shows “No phone”">
                <p>
                  Ramble isn&rsquo;t on your iPhone. Install it from the App Store and open it once. Waiting notes send
                  on their own.
                </p>
              </Question>
              <Question id="mic" q="The watch shows “Mic off”">
                <p>
                  Ramble needs the microphone on the watch. On the watch, open Settings → Privacy &amp; Security →
                  Microphone and turn on Ramble.
                </p>
              </Question>
              <Question id="unlock" q="A note says “Unlock to transcribe”">
                <p>
                  Your {FREE_NOTES} free notes are used. The note is saved on the device that recorded it. Unlock Ramble
                  in Settings on your iPhone, and held notes transcribe on their own, from the watch too. Bought it
                  already? Tap Restore Purchases in Settings.
                </p>
              </Question>
              <Question id="usage-limit" q="A note says “Usage limit reached”">
                <p>
                  Ramble pauses transcription after {FAIR_USE} to stop abuse. The note is kept and transcribes on its
                  own on the date shown. If that looks wrong, tap Contact support on the note on your iPhone.
                </p>
              </Question>
              <Question id="stuck-on-watch" q="Notes wait on the watch, or “Still on your watch”">
                <p>
                  The watch sends each note straight to Ramble over Wi-Fi, cellular, or your iPhone. Away from the
                  iPhone, it sends while the app is open or soon after you stop. In Low Power Mode, watchOS turns off
                  Wi-Fi and cellular away from the iPhone, so notes wait until the iPhone is back. Opening Ramble on the
                  watch sends anything waiting.
                </p>
                <p>Nothing is lost. The watch keeps each note until Ramble has it.</p>
              </Question>
              <Question id="refused" q="A note says “Too long to transcribe” or “Couldn’t send”">
                <p>
                  Notes stop at 60 minutes, and Ramble can&rsquo;t take a longer file. &ldquo;Couldn&rsquo;t send&rdquo;
                  means the file was damaged. Either way the audio stays on your devices.
                </p>
              </Question>
            </section>

            <section className="space-y-2">
              <SectionHeader id="transcription">Transcription</SectionHeader>
              <Question id="transcribing" q="A note stays on “Transcribing…”">
                <p>
                  Most notes take seconds, long ones a little longer. If the transcription services are busy or down,
                  Ramble keeps trying on its own for up to 20 hours. You don&rsquo;t need to do anything.
                </p>
              </Question>
              <Question id="couldnt-transcribe" q="A note says “Couldn’t transcribe”">
                <p>
                  Ramble couldn&rsquo;t turn the audio into text, or couldn&rsquo;t reach a transcription service in
                  time. Open the note on your iPhone and tap Retry. You can retry 3 times. A note that couldn&rsquo;t
                  transcribe gives its free note back.
                </p>
              </Question>
              <Question id="no-speech" q="A note says “No speech detected”">
                <p>
                  Ramble heard nothing to transcribe, like a recording in a pocket. Nothing is sent to your agent or
                  webhook.
                </p>
              </Question>
              <Question id="accuracy" q="Names or words come out wrong">
                <p>
                  In Settings → Transcription on the iPhone, set your Language, and add names and jargon to Vocabulary.
                  New notes from the watch and the iPhone use them.
                </p>
              </Question>
              <Question id="setup-failed" q="“Ramble can’t finish setting up right now”">
                <p>
                  The iPhone couldn&rsquo;t reach Ramble, or Ramble has paused new setups for the day. Keep recording:
                  notes wait as &ldquo;Waiting to send&rdquo;, and setup finishes on its own when you open Ramble later.
                </p>
              </Question>
            </section>

            <section className="space-y-2">
              <SectionHeader id="purchase">Purchase</SectionHeader>
              <Question id="restore" q="I bought Ramble on another iPhone">
                <p>
                  Open Ramble with the same Apple ID and it unlocks on its own. If it doesn&rsquo;t, tap Restore
                  Purchases in Settings.
                </p>
              </Question>
              <Question id="five-iphones" q="“This purchase is in use on 5 iPhones”">
                <p>
                  One purchase works on up to 5 iPhones. Each fresh start after a reinstall counts as one. A spot opens
                  when one of them goes 90 days without sending a note.
                </p>
              </Question>
              <Question id="refund" q="I want a refund">
                <p>
                  Purchases go through Apple, so Apple handles refunds at{" "}
                  <a href="https://reportaproblem.apple.com" target="_blank" rel="noopener noreferrer" className={linkClass}>
                    reportaproblem.apple.com
                  </a>
                  .
                </p>
              </Question>
            </section>

            <section className="space-y-2">
              <SectionHeader id="agent">Your agent</SectionHeader>
              <Question id="agent-not-picking-up" q="My agent isn’t getting my notes">
                <p>
                  Open Settings → Your agent on the iPhone. Each agent shows when it last checked in and how many notes
                  are waiting for it.
                </p>
                <ul className="list-disc space-y-2 pl-5">
                  <li>
                    <Strong>&ldquo;Hasn&rsquo;t checked in&rdquo;:</Strong> the agent isn&rsquo;t checking. Tap Connect
                    again and paste it the fresh message, or paste it the{" "}
                    <Link href="/docs#agent-instructions" className={linkClass}>
                      instructions for the agent
                    </Link>
                    . Notes wait for {RETENTION}, so nothing is lost yet.
                  </li>
                  <li>
                    <Strong>&ldquo;Waiting for your agent&rdquo;:</Strong> the note is ready and the agent hasn&rsquo;t
                    picked it up. Many agents check on a schedule, so this can take a while.
                  </li>
                  <li>
                    <Strong>&ldquo;Not picked up&rdquo;:</Strong> the copy expired after {RETENTION}, was deleted, or its
                    agent was disconnected before reading it.
                  </li>
                </ul>
              </Question>
              <Question id="not-sent" q="A note says “Saved, no agent connected”">
                <p>
                  An agent receives only notes recorded after it connected. Connect one in Settings → Your agent, and
                  your next notes go to it. Older notes stay on your iPhone.
                </p>
              </Question>
              <Question id="code-expired" q="The pairing code expired or didn’t work">
                <p>
                  A code works once and expires after {PAIR_CODE_TTL}. Tap New code and paste the fresh message to your
                  agent.
                </p>
              </Question>
              <Question id="agent-errors" q="My agent gets 401, 403, 429, or connection errors">
                <p>
                  401 means the agent was disconnected; connect it again with a new code. 403 usually means its HTTP
                  client is filtered, and it should send a User-Agent header. 429 means it&rsquo;s checking too often
                  and should wait the seconds in Retry-After. Agents in a sandbox need the relay host on their network
                  allowlist. Details are in{" "}
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
              <Question id="webhook-failed" q="A note says “Didn’t send”">
                <p>
                  Your webhook didn&rsquo;t accept it after 3 tries. Fix the endpoint, then open the note and tap Retry.
                  See{" "}
                  <Link href="/docs/webhooks" className={linkClass}>
                    webhooks
                  </Link>
                  .
                </p>
              </Question>
            </section>

            <p>
              Still stuck? Email{" "}
              <a href={`mailto:${SUPPORT_EMAIL}`} className={linkClass}>
                {SUPPORT_EMAIL}
              </a>
              .
            </p>
          </div>
        </article>
      </div>
    </main>
  );
}
