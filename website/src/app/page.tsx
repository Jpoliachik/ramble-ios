import Link from "next/link";
import type { ReactNode } from "react";
import { AudioLines, Bot, Trash2, UserX } from "lucide-react";
import HeroFlow from "../components/hero-flow";
import HeroMotion from "../components/hero-motion";
import CopyTextButton from "../components/copy-text-button";
import PopIn from "../components/pop-in";
import Waveform from "../components/waveform";
import {
  APP_PRICE,
  APP_STORE_URL,
  FREE_NOTES,
  PRIVACY_WORDING,
  RETENTION,
  SITE_URL,
} from "../lib/site";

const SITE_HOST = SITE_URL.replace(/^https?:\/\//, "");
const SETUP_MESSAGE = "I just downloaded Ramble. Help me set it up!";

const primaryButton =
  "inline-flex items-center gap-2 rounded-full bg-stone-900 px-6 py-3 text-sm font-medium text-white shadow-sm transition-colors hover:bg-stone-800";
const secondaryButton =
  "inline-flex items-center gap-2 rounded-full border border-stone-300 px-6 py-3 text-sm font-medium text-stone-700 transition-colors hover:border-stone-400 hover:bg-stone-100";
const inlineLink = "text-brand-text underline-offset-2 hover:underline";
const stepBadge =
  "flex h-9 w-9 shrink-0 items-center justify-center rounded-full font-serif text-sm font-semibold text-white shadow-sm";

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
    body: "Tap your watch and talk. Messy is fine.",
  },
  {
    title: "Let it go",
    body: "No reply to wait for. Works offline, too.",
  },
  {
    title: "Come back later",
    body: "Your agent picks it up and gets to work.",
  },
];

const privacyPoints = [
  {
    Icon: AudioLines,
    title: "Audio deleted after transcription",
    body: "Your audio goes to a transcription provider and is deleted as soon as the text is ready.",
    tint: "bg-[#f9ebda] text-[#b45309]",
  },
  {
    Icon: Trash2,
    title: "Deleted once delivered",
    body: `Gone as soon as your agent picks it up, or after ${RETENTION} if it never does.`,
    tint: "bg-[#f7e2e1] text-[#a63a4f]",
  },
  {
    Icon: UserX,
    title: "No accounts",
    body: "No email, no name, no login.",
    tint: "bg-[#efe3ef] text-[#6e3474]",
  },
];


const faqs: { q: string; a: ReactNode }[] = [
  {
    q: "Do I need my phone with me?",
    a: "No. Your watch records on its own, even with no signal. It sends each thought over Wi-Fi, cellular, or your iPhone, whichever it has. Anything it can't send yet waits safely on the watch.",
  },
  {
    q: "Why not just talk to my agent directly?",
    a: "Then you're on your phone, waiting for a reply. With Ramble you say it and keep going. Your agent works on it while you get on with your day.",
  },
  {
    q: "Why not use my agent's own app?",
    a: "Most agent apps don't have a real Watch app, and the ones that do need a connection. Ramble records with no phone and no signal, queues everything up, and makes sure each thought reaches your agent once you're back online. It's also simple on purpose: you say it and move on, instead of staring at your phone waiting for a reply.",
  },
  {
    q: "Does my agent reply on my watch?",
    a: "No, and that's the point. Nothing pulls you back in. You check in with your agent when you're ready.",
  },
  {
    q: "How fast does it get to my agent?",
    a: "Most thoughts are transcribed within seconds of reaching Ramble. After that it depends on your agent: some pick it up right away, others check in on a schedule.",
  },
  {
    q: "What happens after my free notes?",
    a: `Your first ${FREE_NOTES} notes are free. After that, new ones wait on your watch or iPhone, marked "Unlock to transcribe". Unlock once for ${APP_PRICE} and they transcribe on their own. Nothing is lost.`,
  },
  {
    q: "What does Ramble's server keep?",
    a: (
      <>
        {PRIVACY_WORDING} No accounts, names, or emails.{" "}
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
    q: "What if it doesn't work for me?",
    a: (
      <>
        Try it with your free notes first. Purchases go through Apple, so refunds do too, at{" "}
        <a href="https://reportaproblem.apple.com" target="_blank" rel="noopener noreferrer" className={inlineLink}>
          reportaproblem.apple.com
        </a>
        . Stuck on something?{" "}
        <Link href="/support" className={inlineLink}>
          Support
        </Link>
        .
      </>
    ),
  },
];



export default function Home() {
  return (
    <main className="flex-1">
      {/* Hero */}
      <section className="sunset-wash relative overflow-hidden">
        <Waveform
          height={90}
          className="pointer-events-none absolute inset-x-0 bottom-4 h-14 w-full text-[#b4593a] opacity-[0.13] sm:h-20"
        />
        <div className="relative mx-auto max-w-5xl px-6 pt-32 pb-24 sm:pt-40 sm:pb-32">
        <div className="grid items-center gap-16 lg:grid-cols-[minmax(0,1fr)_auto] lg:gap-12">
          <div className="flex flex-col items-center text-center lg:items-start lg:text-left">
            <div className="hero-enter-logo">
              <HeroFlow />
            </div>
            <h1 className="hero-enter-title font-serif text-[1.9rem] font-semibold leading-[1.15] tracking-tight text-stone-900 min-[400px]:text-4xl sm:text-5xl lg:text-[2.9rem] lg:leading-[1.1]">
              <span className="block whitespace-nowrap">Talk to your watch.</span>
              <span className="block whitespace-nowrap italic text-brand-text">Your agent handles it.</span>
            </h1>
            <p className="hero-enter-subtitle mt-6 max-w-xl text-base leading-relaxed text-stone-500 sm:text-lg lg:text-xl">
              <span className="block">Stay in the moment, capture the thought.</span>
              <span className="block">Ramble gets it to your AI agent.</span>
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
            </div>
          </div>

          {/* Motion graphic: watch → phone → your agent */}
          <div className="hero-enter-devices relative mx-auto lg:mx-0">
            <HeroMotion />
          </div>
        </div>
        </div>
      </section>

      {/* How it works */}
      <section id="how" className="scroll-mt-20 border-t border-stone-200 bg-stone-50">
        <div className="mx-auto max-w-5xl px-6 py-20 sm:py-28">
          <SectionHeading eyebrow="How it works" sub="Your watch is all you need. Leave your phone in your pocket, or at home.">
            Say it and move on.
          </SectionHeading>
          <ol className="mt-14 grid gap-10 sm:grid-cols-3 sm:gap-8">
            {steps.map((step, i) => (
              <li key={step.title} className="text-left">
                <div className={`${stepBadge} sunset-step-${i + 1}`}>{i + 1}</div>
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
          <SectionHeading eyebrow="Setup" sub="Ask your agent to set up Ramble. It takes it from there.">
            One message
          </SectionHeading>

          {/* Chat mockup: setup is just asking your agent */}
          <div className="mx-auto mt-12 max-w-sm rounded-3xl bg-white px-5 pt-5 pb-6 shadow-sm ring-1 ring-stone-200/80">
            <div className="flex flex-col items-center gap-1.5">
              <span className="flex h-9 w-9 items-center justify-center rounded-full bg-stone-100 text-stone-600">
                <Bot className="h-5 w-5" aria-hidden="true" />
              </span>
              <span className="text-xs font-medium text-stone-500">Agent</span>
            </div>
            <div className="mt-5 flex flex-col text-sm">
              <PopIn className="max-w-[90%] self-end">
                <p className="rounded-2xl rounded-br-md sunset-bubble px-4 py-2.5 text-white">
                  {SETUP_MESSAGE}
                  <br />
                  <span className="whitespace-nowrap underline underline-offset-2">{SITE_HOST}/docs</span>
                </p>
              </PopIn>
            </div>
          </div>
          <div className="mt-4 flex justify-center">
            <CopyTextButton text={`${SETUP_MESSAGE}\n${SITE_URL}/docs`} label="Copy message" />
          </div>

          <div className="mt-14 space-y-1.5 text-center text-sm text-stone-500">
            <p>Works best with personal agents like Muse, Grok Bot and Dot.</p>
            <p>
              Have your own custom endpoint?{" "}
              <Link href="/docs/webhooks" className={inlineLink}>
                Webhooks work too
              </Link>
              .
            </p>
          </div>
        </div>
      </section>

      {/* Pricing */}
      <section className="border-t border-stone-200 bg-stone-50">
        <div className="mx-auto max-w-5xl px-6 py-20 sm:py-28">
          {/* Reads as the spec's pricing line: "Free to download. 25 notes free, then $14.99 once." */}
          <div className="relative mx-auto max-w-md overflow-hidden rounded-2xl bg-white px-6 pt-9 pb-8 text-center shadow-sm ring-1 ring-stone-200/80">
            <div aria-hidden="true" className="sunset-rule absolute inset-x-0 top-0 h-1" />
            <h2 className="font-serif text-4xl font-semibold tracking-tight text-stone-900">Free to download.</h2>
            <p className="mt-3 text-base text-stone-700">
              {FREE_NOTES} notes free, then {APP_PRICE} once.
            </p>
            <p className="mt-1 text-sm text-stone-500">No subscription.</p>
            <a href={APP_STORE_URL} target="_blank" rel="noopener noreferrer" className={`${primaryButton} mt-7`}>
              <AppleLogo />
              Get Ramble
            </a>
          </div>
        </div>
      </section>

      {/* Privacy */}
      <section className="border-t border-stone-200">
        <div className="mx-auto max-w-5xl px-6 py-20 sm:py-28">
          <SectionHeading eyebrow="Privacy">Your thoughts don&apos;t stick around</SectionHeading>
          <div className="mt-14 grid gap-10 sm:grid-cols-3 sm:gap-8">
            {privacyPoints.map(({ Icon, title, body, tint }) => (
              <div key={title} className="flex flex-col items-center text-center sm:items-start sm:text-left">
                <div className={`flex h-10 w-10 items-center justify-center rounded-lg ${tint}`}>
                  <Icon className="h-5 w-5" aria-hidden="true" />
                </div>
                <h3 className="mt-4 text-base font-semibold text-stone-900">{title}</h3>
                <p className="mt-2 text-sm leading-relaxed text-stone-500">{body}</p>
              </div>
            ))}
          </div>
          <p className="mx-auto mt-12 max-w-3xl text-center text-sm leading-relaxed text-stone-500">
            {PRIVACY_WORDING}{" "}
            <Link href="/privacy" className={inlineLink}>
              Full privacy policy
            </Link>
            .
          </p>
        </div>
      </section>

      {/* FAQ */}
      <section className="border-t border-stone-200 bg-stone-50">
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
      <section className="sunset-deep relative overflow-hidden">
        <Waveform
          height={90}
          className="pointer-events-none absolute inset-x-0 bottom-4 h-14 w-full text-[#fff1dc] opacity-[0.15] sm:h-20"
        />
        <div className="relative mx-auto max-w-5xl px-6 pt-20 pb-28 text-center sm:pt-24 sm:pb-32">
          <h2 className="font-serif text-3xl font-semibold tracking-tight text-[#fbf1e3] sm:text-4xl">
            Get it off your mind.
          </h2>
          <p className="mt-4 font-serif text-lg italic text-[#fbf1e3]/80">
            Leave the phone. Keep the thought.
          </p>
          <div className="mt-8 flex flex-col items-center gap-4 sm:flex-row sm:justify-center">
            <a
              href={APP_STORE_URL}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-2 rounded-full bg-[#fbf1e3] px-6 py-3 text-sm font-medium text-stone-900 shadow-sm transition-colors hover:bg-white"
            >
              <AppleLogo />
              Get Ramble
            </a>
          </div>
        </div>
      </section>
    </main>
  );
}
