import Link from "next/link";
import type { ReactNode } from "react";
import { AudioLines, Code, Trash2, UserX } from "lucide-react";
import HeroFlow from "../components/hero-flow";
import {
  APP_PRICE,
  APP_STORE_URL,
  BASE_PATH,
  CLOUD_PRICE,
  GITHUB_URL,
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

function GitHubLogo() {
  return (
    <svg className="h-5 w-5" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z" />
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
    title: "Tap your Watch and talk",
    body: "Raise your wrist, tap record, say what's on your mind. No screen to read, nothing to type.",
  },
  {
    title: "Your iPhone transcribes",
    body: "On-device with Apple Speech by default. The audio stays on your phone.",
  },
  {
    title: "Your agent picks it up",
    body: `Your agent checks in on a schedule, about every ${PULL_CADENCE}, and handles what you said.`,
  },
  {
    title: "Then it's gone",
    body: "Once your agent has it, Ramble deletes its copy.",
  },
];

const privacyPoints = [
  {
    Icon: AudioLines,
    title: "Audio never goes to the relay",
    body: "Only transcript text does. Apple Speech transcribes on your iPhone by default.",
  },
  {
    Icon: Trash2,
    title: "Deleted on delivery",
    body: `The relay holds text until your agent picks it up. Anything unclaimed is deleted after ${RETENTION}.`,
  },
  {
    Icon: UserX,
    title: "No accounts",
    body: "No email, no name, no login. We identify inboxes, not people.",
  },
  {
    Icon: Code,
    title: "Open source",
    body: "The app, the relay, and the transcription proxy. Read the code, or run your own relay.",
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
    q: "Why not just talk to Muse directly?",
    a: "You can, if your phone is out. Ramble is for when it isn't: on a walk, driving, between meetings. One tap on your wrist, no app to open, no reply to read.",
  },
  {
    q: "What if I stop using Muse?",
    a: "Disconnect it in one tap. Webhooks can still send every transcript to a URL you choose.",
  },
  {
    q: "Does my agent reply on my watch?",
    a: "No. Ramble is one-way. You say it, your agent handles it on its own time. Check the results in your agent later.",
  },
  {
    q: "How fast does it get to my agent?",
    a: `Transcription takes seconds once the recording is on your iPhone. Your agent checks for new transcripts about every ${PULL_CADENCE}, so expect minutes, not seconds.`,
  },
  {
    q: "Which agents can I connect?",
    a: "Muse today. More agents later. Webhooks work with anything that accepts an HTTPS request.",
  },
  {
    q: "What does the relay store?",
    a: (
      <>
        Transcript text waiting for pickup, with its recording time and duration. Plus what it needs to route it: a
        random inbox id, hashed credentials, and when each agent connected and last checked in. Text is deleted the
        moment your agent picks it up, or after {RETENTION} if it never does. No audio, no accounts, no names, emails,
        or IP addresses.{" "}
        <Link href="/privacy" className={inlineLink}>
          Privacy policy
        </Link>
        .
      </>
    ),
  },
  {
    q: "Can I run my own relay?",
    a: (
      <>
        Yes. The relay is a small open-source Cloudflare Worker. Deploy it to your own Cloudflare account (the free tier
        is fine) and point Ramble at it. The code is in{" "}
        <a href={`${GITHUB_URL}/tree/main/relay`} target="_blank" rel="noopener noreferrer" className={inlineLink}>
          relay/
        </a>{" "}
        on GitHub.
      </>
    ),
  },
  {
    q: "Do webhooks still work?",
    a: (
      <>
        Yes, exactly as before. Ramble can POST every transcript to any HTTPS endpoint, signed with your secret and
        retried on failure. Use it alongside your agent or on its own.{" "}
        <Link href="/docs/webhooks" className={inlineLink}>
          Webhook docs
        </Link>
        .
      </>
    ),
  },
  {
    q: "Do I need my phone nearby?",
    a: "Not to record. The Watch records on its own. Recordings sync to your iPhone the next time it's in range, and transcription and delivery happen there.",
  },
  {
    q: "What if I'm offline?",
    a: "Nothing gets lost. Recordings wait in a queue on your Watch and iPhone and go out when you're back online. Each one shows its status along the way.",
  },
  {
    q: "Is Ramble open source?",
    a: (
      <>
        Yes, MIT licensed, on{" "}
        <a href={GITHUB_URL} target="_blank" rel="noopener noreferrer" className={inlineLink}>
          GitHub
        </a>
        . Audit it, build it yourself, or fork it.
      </>
    ),
  },
  {
    q: "How do I cancel cloud transcription?",
    a: "Like any iOS subscription: Settings → your name → Subscriptions → Ramble → Cancel. On-device transcription, your agent connection, and webhooks keep working.",
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
            <h1 className="hero-enter-title font-serif text-4xl font-semibold tracking-tight text-stone-900 sm:text-5xl lg:text-[3.25rem] lg:leading-[1.1]">
              Record on your watch.
              <br />
              <span className="italic text-red-500">Your agent handles it.</span>
            </h1>
            <p className="hero-enter-subtitle mt-6 max-w-xl text-base leading-relaxed text-stone-500 sm:text-lg lg:text-xl">
              Tap your Apple Watch and say it: remind me to book the dentist, add oat milk to the list. Your iPhone
              transcribes it and Muse takes care of it.
            </p>
            <div className="hero-enter-buttons mt-10 flex flex-col items-center gap-3 lg:items-start">
              <div className="flex flex-col items-center gap-4 sm:flex-row">
                <a href={APP_STORE_URL} target="_blank" rel="noopener noreferrer" className={primaryButton}>
                  <AppleLogo />
                  Download on the App Store
                </a>
                <a href="#connect" className={secondaryButton}>
                  See how pairing works
                  <span aria-hidden="true">&darr;</span>
                </a>
              </div>
              <p className="text-sm text-stone-500">{APP_PRICE}, one time. Works with Muse. No account.</p>
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
      <section className="border-t border-stone-200 bg-stone-50">
        <div className="mx-auto max-w-5xl px-6 py-20 sm:py-28">
          <SectionHeading eyebrow="How it works">
            Say it once. <span className="italic">It&apos;s handled.</span>
          </SectionHeading>
          <ol className="mt-14 grid gap-10 sm:grid-cols-2 sm:gap-x-12 lg:grid-cols-4 lg:gap-8">
            {steps.map((step, i) => (
              <li key={step.title} className="text-left">
                <div className={stepBadge}>{i + 1}</div>
                <h3 className="mt-4 text-sm font-semibold text-stone-900">{step.title}</h3>
                <p className="mt-1 text-sm leading-relaxed text-stone-500">{step.body}</p>
              </li>
            ))}
          </ol>
          <p className="mt-12 text-center text-sm text-stone-500">
            It&apos;s asynchronous on purpose. You don&apos;t wait for a reply. Your agent works through it while you get
            on with your day.
          </p>
        </div>
      </section>

      {/* Connect your agent */}
      <section id="connect" className="scroll-mt-20 border-t border-stone-200">
        <div className="mx-auto max-w-5xl px-6 py-20 sm:py-28">
          <SectionHeading eyebrow="Connect your agent" sub="Ramble works with Muse. Pairing takes about a minute.">
            Hook it up to <span className="italic text-red-500">Muse</span>.
          </SectionHeading>

          <div className="mt-14 grid items-start gap-10 lg:grid-cols-[minmax(0,1fr)_minmax(0,22rem)] lg:gap-16">
            <ol className="space-y-8">
              <li className="flex gap-4">
                <span className={stepBadge}>1</span>
                <div>
                  <h3 className="text-sm font-semibold text-stone-900">Get a pairing code</h3>
                  <p className="mt-1 text-sm leading-relaxed text-stone-500">
                    In Ramble on your iPhone, open Settings → Connect agent → Muse. Ramble shows a short code. It works
                    once and expires in {PAIR_CODE_TTL}.
                  </p>
                </div>
              </li>
              <li className="flex gap-4">
                <span className={stepBadge}>2</span>
                <div>
                  <h3 className="text-sm font-semibold text-stone-900">Tell Muse</h3>
                  <p className="mt-1 text-sm leading-relaxed text-stone-500">
                    Say &ldquo;I downloaded Ramble, connect it&rdquo; and paste the code. Muse uses it to connect. Its
                    access is limited to picking up your transcripts.
                  </p>
                </div>
              </li>
              <li className="flex gap-4">
                <span className={stepBadge}>3</span>
                <div>
                  <h3 className="text-sm font-semibold text-stone-900">Talk to your Watch</h3>
                  <p className="mt-1 text-sm leading-relaxed text-stone-500">
                    Muse checks for new recordings about every {PULL_CADENCE}. Expect minutes, not seconds. Disconnect
                    from the same screen any time. Muse loses access and anything still waiting is deleted.
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
                <p className="text-xs font-medium uppercase tracking-[0.18em] text-stone-500">Chat with Muse</p>
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

          <div className="mt-14 grid gap-4 sm:grid-cols-2">
            <div className="rounded-xl border border-stone-200 p-5">
              <h3 className="text-sm font-semibold text-stone-900">More agents later</h3>
              <p className="mt-1 text-sm leading-relaxed text-stone-500">
                Muse is the one we support today. Curious how the connection works?{" "}
                <Link href="/docs" className={inlineLink}>
                  Read the docs
                </Link>
                .
              </p>
            </div>
            <div className="rounded-xl border border-stone-200 p-5">
              <h3 className="text-sm font-semibold text-stone-900">Have your own endpoint?</h3>
              <p className="mt-1 text-sm leading-relaxed text-stone-500">
                Webhooks still work. Ramble can POST each transcript to any HTTPS URL, signed and retried.{" "}
                <Link href="/docs/webhooks" className={inlineLink}>
                  Webhook docs
                </Link>
                .
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Transcription */}
      <section className="border-t border-stone-200 bg-stone-50">
        <div className="mx-auto max-w-5xl px-6 py-20 sm:py-28">
          <SectionHeading
            eyebrow="Transcription"
            sub="Apple Speech runs on your iPhone by default. Free, private, works out of the box."
          >
            On-device by default. <span className="italic">Cloud if you want it.</span>
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
                Groq, Deepgram, and OpenAI, for sharper transcripts on accents, jargon, or wind. {CLOUD_PRICE}.
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
          <SectionHeading eyebrow="Pricing">
            Pay once. <span className="italic">Cloud is optional.</span>
          </SectionHeading>
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
              <p className="mt-6 border-t border-stone-200 pt-4 text-sm text-stone-500">
                What you need: an Apple Watch paired with an iPhone, and Muse.
              </p>
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
                Groq, Deepgram, and OpenAI models. Cancel any time in iOS Settings; everything else keeps working.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Privacy */}
      <section className="border-t border-stone-200 bg-stone-50">
        <div className="mx-auto max-w-5xl px-6 py-20 sm:py-28">
          <SectionHeading
            eyebrow="Privacy"
            sub="Your transcripts pass through the relay on their way to your agent. They don't live there."
          >
            Passes through. <span className="italic">Doesn&apos;t stay.</span>
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
            Disconnect any time from the app, and anything still waiting is deleted. Pairing codes and agent tokens are
            stored only as hashes. If you turn on cloud transcription, audio goes to the model you pick through a proxy
            that stores nothing.{" "}
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
            Tap. Talk. <span className="italic text-red-500">Handled.</span>
          </h2>
          <p className="mt-4 text-base text-stone-500">
            {APP_PRICE}, one time. Apple Watch and iPhone. Works with Muse. Open source.
          </p>
          <div className="mt-8 flex flex-col items-center gap-4 sm:flex-row sm:justify-center">
            <a href={APP_STORE_URL} target="_blank" rel="noopener noreferrer" className={primaryButton}>
              <AppleLogo />
              Get Ramble
            </a>
            <a href={GITHUB_URL} target="_blank" rel="noopener noreferrer" className={secondaryButton}>
              <GitHubLogo />
              View on GitHub
            </a>
          </div>
        </div>
      </section>
    </main>
  );
}
