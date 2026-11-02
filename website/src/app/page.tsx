import Link from "next/link";
import type { ReactNode } from "react";
import { AudioLines, Clock, Trash2, UserX } from "lucide-react";
import HeroFlow from "../components/hero-flow";
import {
  APP_PRICE,
  APP_STORE_URL,
  BASE_PATH,
  CLOUD_PRICE,
  PAIR_CODE_EXAMPLE,
  PAIR_CODE_TTL,
  PULL_CADENCE,
  RETENTION,
} from "../lib/site";

const primaryButton =
  "inline-flex items-center gap-2 rounded-full bg-stone-900 px-6 py-3 text-sm font-medium text-white shadow-sm transition-colors hover:bg-stone-800";
const secondaryButton =
  "inline-flex items-center gap-2 rounded-full border border-stone-300 px-6 py-3 text-sm font-medium text-stone-700 transition-colors hover:border-stone-400 hover:bg-stone-100";
const inlineLink = "text-red-600 underline-offset-2 hover:underline";
const stepBadge =
  "flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-stone-900 font-serif text-sm font-semibold text-white";

function AppleLogo() {
  return (
    <svg className="h-5 w-5" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z" />
    </svg>
  );
}

function SectionHeading({ eyebrow, children, sub }: { eyebrow: string; children: ReactNode; sub?: ReactNode }) {
  return (
    <div className="text-center">
      <p className="text-xs font-medium uppercase tracking-[0.18em] text-stone-500">{eyebrow}</p>
      <h2 className="mt-3 font-serif text-2xl font-semibold tracking-tight text-stone-900 sm:text-3xl">{children}</h2>
      {sub && <p className="mx-auto mt-4 max-w-2xl text-base leading-relaxed text-stone-500">{sub}</p>}
    </div>
  );
}

const steps = [
  {
    title: "Say it",
    body: "Tap your watch and talk. A to-do, an idea, something to look up later. Messy is fine.",
  },
  {
    title: "Ramble writes it down",
    body: "Your iPhone turns it into text. The audio stays on your phone.",
  },
  {
    title: "Your agent takes it",
    body: `Your agent picks it up within about ${PULL_CADENCE} and deals with it. You don't have to.`,
  },
];

const privacyPoints = [
  {
    Icon: AudioLines,
    title: "Audio stays on your phone",
    body: "Only the text is sent on. With Apple Speech, transcription happens on your iPhone too.",
  },
  {
    Icon: Trash2,
    title: "Deleted once delivered",
    body: "Ramble holds the text until your agent picks it up. Then it's deleted.",
  },
  {
    Icon: UserX,
    title: "No accounts",
    body: "No email, no name, no login.",
  },
  {
    Icon: Clock,
    title: `${RETENTION} at most`,
    body: `If your agent never picks something up, it's deleted after ${RETENTION}. Long enough to ride out an agent hiccup.`,
  },
];

const cloudModels = [
  { name: "Whisper v3 Turbo", provider: "Groq", note: "Fast and accurate. The default." },
  { name: "Whisper Large v3", provider: "Groq", note: "Best for accents and multilingual audio." },
  { name: "Nova-3", provider: "Deepgram", note: "Strong English accuracy, smart formatting." },
  { name: "GPT-Transcribe", provider: "OpenAI", note: "Highest accuracy on noisy real-world audio." },
];

const included = [
  "Apple Watch and iPhone apps",
  "On-device transcription with Apple Speech",
  "Delivery to your agent through Ramble Relay",
  "Webhooks to your own endpoint",
];

const faqs: { q: string; a: ReactNode }[] = [
  {
    q: "Why not just talk to my agent directly?",
    a: "You can, if your phone is out. Ramble is for when it isn't: on a walk, in the car, between meetings. One tap, say it, done.",
  },
  {
    q: "Does my agent reply on my watch?",
    a: "No. You say it and move on. Your agent handles it on its own time, and you can check in with it later.",
  },
  {
    q: "How fast does it get to my agent?",
    a: `Usually within ${PULL_CADENCE}. Transcription takes seconds; your agent checks for new ones on a schedule.`,
  },
  {
    q: "What does the relay store?",
    a: (
      <>
        Only the text waiting for your agent, with when it was recorded and how long it was, plus what it needs to
        route it. Text is deleted when your agent picks it up, or after {RETENTION} if it never does. No audio, no
        accounts, no names, emails, or IP addresses.{" "}
        <Link href="/privacy" className={inlineLink}>
          Privacy policy
        </Link>
        .
      </>
    ),
  },
  {
    q: "Do webhooks still work?",
    a: (
      <>
        Yes. Ramble can still send every transcript to your own HTTPS endpoint, alongside your agent or instead of it.{" "}
        <Link href="/docs/webhooks" className={inlineLink}>
          Webhook docs
        </Link>
        .
      </>
    ),
  },
  {
    q: "Do I need my phone nearby?",
    a: "Not to record. The watch records on its own and syncs to your iPhone when it's back in range.",
  },
  {
    q: "What if I'm offline?",
    a: "Nothing gets lost. Recordings wait on your watch and iPhone and go out when you're back online.",
  },
  {
    q: "What if it doesn't work for me?",
    a: (
      <>
        Purchases go through Apple. You can request a refund at{" "}
        <a href="https://reportaproblem.apple.com" target="_blank" rel="noopener noreferrer" className={inlineLink}>
          reportaproblem.apple.com
        </a>
        .
      </>
    ),
  },
];


const [cloudAmount, cloudPeriod] = CLOUD_PRICE.split("/");

export default function Home() {
  return (
    <main className="flex-1">
      {/* Hero */}
      <section className="mx-auto max-w-5xl px-6 pt-32 pb-20 sm:pt-40 sm:pb-28">
        <div className="grid items-center gap-16 lg:grid-cols-[minmax(0,1fr)_auto] lg:gap-12">
          <div className="flex flex-col items-center text-center lg:items-start lg:text-left">
            <div className="hero-enter-logo">
              <HeroFlow />
            </div>
            <h1 className="hero-enter-title font-serif text-4xl font-semibold tracking-tight text-stone-900 sm:text-5xl lg:text-[2.9rem] lg:leading-[1.1]">
              Ramble into your watch.
              <br />
              <span className="italic text-red-500">Your agent handles it.</span>
            </h1>
            <p className="hero-enter-subtitle mt-6 max-w-xl text-base leading-relaxed text-stone-500 sm:text-lg lg:text-xl">
              Got a thought? Tap your watch and say it. Ramble writes it down and hands it to your agent, so you can
              stop holding onto it.
            </p>
            <div className="hero-enter-buttons mt-10 flex flex-col items-center gap-3 lg:items-start">
              <div className="flex flex-col items-center gap-4 sm:flex-row">
                <a href={APP_STORE_URL} target="_blank" rel="noopener noreferrer" className={primaryButton}>
                  <AppleLogo />
                  Download on the App Store
                </a>
                <a href="#how" className={secondaryButton}>
                  How it works
                  <span aria-hidden="true">&darr;</span>
                </a>
              </div>
              <p className="text-sm text-stone-500">{APP_PRICE}, once.</p>
            </div>
          </div>

          {/* Device showcase: Watch primary in front, iPhone behind. The Watch overlaps only the phone's frame edge. */}
          <div className="hero-enter-devices relative mx-auto lg:mx-0">
            <div className="relative w-[306px] sm:w-[376px] lg:w-[426px]">
              {/* iPhone 17 Pro frame, secondary */}
              <div className="relative ml-auto w-[140px] opacity-90 sm:w-[170px] lg:w-[190px]">
                <span
                  aria-hidden="true"
                  className="absolute -left-[3px] top-[18%] h-8 w-[4px] rounded-l-sm bg-stone-700"
                />
                <span
                  aria-hidden="true"
                  className="absolute -right-[3px] top-[14%] h-6 w-[4px] rounded-r-sm bg-stone-700"
                />
                <span
                  aria-hidden="true"
                  className="absolute -right-[3px] top-[26%] h-10 w-[4px] rounded-r-sm bg-stone-700"
                />
                <div className="rounded-[2.1rem] bg-stone-900 p-[7px] shadow-[0_24px_48px_-16px_rgba(26,25,23,0.3)] ring-1 ring-black/5">
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img
                    src={`${BASE_PATH}/screenshot-home-light.png`}
                    alt="Ramble on iPhone showing the recordings list"
                    className="block w-full rounded-[1.7rem]"
                  />
                </div>
              </div>

              {/* Apple Watch Ultra frame, primary */}
              <div className="absolute left-0 top-1/2 z-10 w-[170px] -translate-y-1/2 sm:w-[210px] lg:w-[240px]">
                <div className="relative">
                  <span
                    aria-hidden="true"
                    className="absolute -left-[5px] top-[36%] h-9 w-[6px] rounded-l-sm bg-red-500/80"
                  />
                  <span
                    aria-hidden="true"
                    className="absolute -right-[7px] top-[22%] h-8 w-[8px] rounded-r-md bg-stone-700"
                  />
                  <span
                    aria-hidden="true"
                    className="absolute -right-[5px] top-[44%] h-10 w-[6px] rounded-r-sm bg-stone-700"
                  />
                  <div className="rounded-[3rem] bg-stone-900 p-[9px] shadow-[0_30px_60px_-12px_rgba(26,25,23,0.45)] ring-1 ring-black/5">
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img
                      src={`${BASE_PATH}/screenshot-watch-recording2.png`}
                      alt="Ramble recording on Apple Watch Ultra"
                      className="block w-full rounded-[2.5rem]"
                    />
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* How it works */}
      <section id="how" className="scroll-mt-20 border-t border-stone-200 bg-stone-50">
        <div className="mx-auto max-w-5xl px-6 py-20 sm:py-28">
          <SectionHeading eyebrow="How it works">Say it, then forget about it.</SectionHeading>
          <ol className="mt-14 grid gap-10 sm:grid-cols-3 sm:gap-8">
            {steps.map((step, i) => (
              <li key={step.title} className="text-left">
                <div className={stepBadge}>{i + 1}</div>
                <h3 className="mt-4 text-sm font-semibold text-stone-900">{step.title}</h3>
                <p className="mt-1 text-sm leading-relaxed text-stone-500">{step.body}</p>
              </li>
            ))}
          </ol>
        </div>
      </section>

      {/* Connect your agent */}
      <section id="connect" className="scroll-mt-20 border-t border-stone-200">
        <div className="mx-auto max-w-5xl px-6 py-20 sm:py-28">
          <SectionHeading eyebrow="Setup" sub="Takes about a minute.">
            Connect your agent
          </SectionHeading>

          <div className="mt-14 grid items-start gap-10 lg:grid-cols-[minmax(0,1fr)_minmax(0,22rem)] lg:gap-16">
            <ol className="space-y-8">
              <li className="flex gap-4">
                <span className={stepBadge}>1</span>
                <div>
                  <h3 className="text-sm font-semibold text-stone-900">Get a pairing code</h3>
                  <p className="mt-1 text-sm leading-relaxed text-stone-500">
                    On your iPhone, open Ramble → Settings → Connect agent. You&apos;ll get a short code.
                  </p>
                </div>
              </li>
              <li className="flex gap-4">
                <span className={stepBadge}>2</span>
                <div>
                  <h3 className="text-sm font-semibold text-stone-900">Tell your agent</h3>
                  <p className="mt-1 text-sm leading-relaxed text-stone-500">
                    Say &ldquo;I downloaded Ramble, connect it&rdquo; and paste the code. It can only pick up your
                    transcripts, nothing else.
                  </p>
                </div>
              </li>
              <li className="flex gap-4">
                <span className={stepBadge}>3</span>
                <div>
                  <h3 className="text-sm font-semibold text-stone-900">Start talking</h3>
                  <p className="mt-1 text-sm leading-relaxed text-stone-500">
                    That&apos;s it. You can disconnect from the same screen any time.
                  </p>
                </div>
              </li>
            </ol>

            {/* Pairing illustration */}
            <div className="rounded-2xl bg-white p-6 shadow-sm ring-1 ring-stone-200/80">
              <p className="text-xs font-medium uppercase tracking-[0.18em] text-stone-500">Pairing code</p>
              <p className="mt-3 font-mono text-3xl font-semibold tracking-[0.12em] text-stone-900">
                {PAIR_CODE_EXAMPLE}
              </p>
              <p className="mt-2 text-xs text-stone-500">Single use. Expires in {PAIR_CODE_TTL}.</p>
              <div className="mt-6 border-t border-stone-200 pt-6">
                <p className="text-xs font-medium uppercase tracking-[0.18em] text-stone-500">Chat with your agent</p>
                <div className="mt-3 flex flex-col gap-2">
                  <p className="max-w-[90%] self-end rounded-2xl rounded-br-md bg-stone-900 px-4 py-2.5 text-sm text-white">
                    I downloaded Ramble, connect it.{" "}
                    <span className="font-mono whitespace-nowrap">{PAIR_CODE_EXAMPLE}</span>
                  </p>
                  <p className="max-w-[90%] self-start rounded-2xl rounded-bl-md bg-stone-100 px-4 py-2.5 text-sm text-stone-900">
                    Connected. I&apos;ll check for new recordings every {PULL_CADENCE}.
                  </p>
                </div>
              </div>
            </div>
          </div>

          <p className="mt-14 text-center text-sm text-stone-500">
            Have your own endpoint?
                Ramble can also send each transcript to any HTTPS URL.{" "}
                <Link href="/docs/webhooks" className={inlineLink}>
                  Webhook docs
                </Link>
                .
          </p>
        </div>
      </section>

      {/* Transcription */}
      <section className="border-t border-stone-200 bg-stone-50">
        <div className="mx-auto max-w-5xl px-6 py-20 sm:py-28">
          <SectionHeading eyebrow="Transcription" sub="Apple Speech runs on your iPhone and is included. Cloud models are optional.">
            On your phone by default
          </SectionHeading>
          <div className="mx-auto mt-12 max-w-3xl overflow-hidden rounded-2xl bg-white shadow-sm ring-1 ring-stone-200/80">
            <div className="flex items-center justify-between gap-4 border-b border-stone-200 bg-sage-50 px-5 py-4">
              <div>
                <p className="text-sm font-semibold text-stone-900">Apple Speech</p>
                <p className="text-sm text-stone-500">On-device. Audio never leaves your phone.</p>
              </div>
              <span className="shrink-0 rounded-full bg-sage-100 px-3 py-1 text-xs font-medium text-sage-700">
                Included
              </span>
            </div>
            <div className="px-5 py-4">
              <p className="text-sm font-semibold text-stone-900">Cloud models</p>
              <p className="text-sm text-stone-500">
                More accurate with accents, jargon, or background noise. {CLOUD_PRICE}.
              </p>
            </div>
            <details className="group border-t border-stone-200">
              <summary className="flex cursor-pointer list-none items-center justify-between gap-4 px-5 py-3 text-sm font-medium text-stone-700 transition-colors hover:text-stone-900">
                See cloud models
                <span aria-hidden="true" className="text-stone-500 transition-transform group-open:rotate-45">
                  +
                </span>
              </summary>
              <ul className="divide-y divide-stone-200 border-t border-stone-200">
                {cloudModels.map((m) => (
                  <li
                    key={m.name}
                    className="flex flex-col gap-1 px-5 py-4 sm:flex-row sm:items-center sm:justify-between"
                  >
                    <p className="text-sm font-semibold text-stone-900">
                      {m.name} <span className="font-normal text-stone-500">· {m.provider}</span>
                    </p>
                    <p className="text-sm text-stone-500">{m.note}</p>
                  </li>
                ))}
              </ul>
            </details>
            <div className="border-t border-stone-200 px-5 py-3 text-xs text-stone-500">
              Custom vocabulary, filler-word removal, and a language hint are in Settings.
            </div>
          </div>
        </div>
      </section>

      {/* Pricing */}
      <section className="border-t border-stone-200">
        <div className="mx-auto max-w-5xl px-6 py-20 sm:py-28">
          <SectionHeading eyebrow="Pricing">Pay once</SectionHeading>
          <div className="mx-auto mt-12 grid max-w-3xl gap-6 sm:grid-cols-2">
            <div className="rounded-2xl bg-white p-6 shadow-sm ring-1 ring-stone-200/80">
              <p className="text-sm font-semibold text-stone-900">Ramble</p>
              <p className="mt-2 font-serif text-4xl font-semibold text-stone-900">
                {APP_PRICE}
                <span className="ml-2 font-sans text-sm font-normal text-stone-500">one time</span>
              </p>
              <ul className="mt-6 space-y-2.5">
                {included.map((item) => (
                  <li key={item} className="flex gap-2.5 text-sm text-stone-600">
                    <span aria-hidden="true" className="mt-[7px] h-1.5 w-1.5 shrink-0 rounded-full bg-stone-400" />
                    {item}
                  </li>
                ))}
              </ul>
            </div>
            <div className="rounded-2xl border border-stone-200 p-6">
              <div className="flex items-center justify-between gap-3">
                <p className="text-sm font-semibold text-stone-900">Cloud transcription</p>
                <span className="rounded-full bg-stone-100 px-2.5 py-0.5 text-xs font-medium text-stone-600">
                  Optional
                </span>
              </div>
              <p className="mt-2 font-serif text-4xl font-semibold text-stone-900">
                {cloudAmount}
                {cloudPeriod && (
                  <span className="ml-1 font-sans text-sm font-normal text-stone-500">/{cloudPeriod}</span>
                )}
              </p>
              <p className="mt-6 text-sm leading-relaxed text-stone-500">
                For better accuracy. Cancel any time and everything else keeps working.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Privacy */}
      <section className="border-t border-stone-200 bg-stone-50">
        <div className="mx-auto max-w-5xl px-6 py-20 sm:py-28">
          <SectionHeading eyebrow="Privacy" sub="Ramble keeps your words only as long as it takes to get them to your agent.">
            Your thoughts don&apos;t stick around
          </SectionHeading>
          <div className="mt-14 grid gap-10 sm:grid-cols-2 lg:grid-cols-4 lg:gap-8">
            {privacyPoints.map(({ Icon, title, body }) => (
              <div key={title} className="flex flex-col items-center text-center sm:items-start sm:text-left">
                <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-sage-100 text-sage-600">
                  <Icon className="h-5 w-5" aria-hidden="true" />
                </div>
                <h3 className="mt-4 text-base font-semibold text-stone-900">{title}</h3>
                <p className="mt-2 text-sm leading-relaxed text-stone-500">{body}</p>
              </div>
            ))}
          </div>
          <p className="mx-auto mt-12 max-w-3xl text-center text-sm leading-relaxed text-stone-500">
            Disconnect any time and anything still waiting is deleted. With cloud transcription on, audio goes to the
            model you pick and isn&apos;t stored.{" "}
            <Link href="/privacy" className={inlineLink}>
              Full privacy policy
            </Link>
            .
          </p>
        </div>
      </section>

      {/* FAQ */}
      <section className="border-t border-stone-200">
        <div className="mx-auto max-w-3xl px-6 py-20 sm:py-28">
          <SectionHeading eyebrow="FAQ">Questions</SectionHeading>
          <div className="mt-12 divide-y divide-stone-200 border-t border-b border-stone-200">
            {faqs.map((f) => (
              <details key={f.q} className="group">
                <summary className="flex cursor-pointer list-none items-center justify-between gap-4 py-5 text-sm font-medium text-stone-900 transition-colors hover:text-stone-700 sm:text-base">
                  {f.q}
                  <span aria-hidden="true" className="text-stone-500 transition-transform group-open:rotate-45">
                    +
                  </span>
                </summary>
                <div className="pb-5 text-sm leading-relaxed text-stone-500">{f.a}</div>
              </details>
            ))}
          </div>
        </div>
      </section>

      {/* Final CTA */}
      <section className="border-t border-stone-200 bg-stone-50">
        <div className="mx-auto max-w-5xl px-6 py-20 text-center sm:py-24">
          <h2 className="font-serif text-3xl font-semibold tracking-tight text-stone-900 sm:text-4xl">
            Get it off your mind.
          </h2>
          <p className="mt-4 text-base text-stone-500">
            {APP_PRICE}, once. For Apple Watch and iPhone.
          </p>
          <div className="mt-8 flex flex-col items-center gap-4 sm:flex-row sm:justify-center">
            <a href={APP_STORE_URL} target="_blank" rel="noopener noreferrer" className={primaryButton}>
              <AppleLogo />
              Get Ramble
            </a>
          </div>
        </div>
      </section>
    </main>
  );
}
