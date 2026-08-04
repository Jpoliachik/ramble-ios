import Link from "next/link";
import { Mic, Webhook, ShieldCheck } from "lucide-react";
import HeroFlow from "../components/hero-flow";

const BASE_PATH = "/ramble";

export default function Home() {
  return (
    <main className="flex-1">
      {/* Hero */}
      <section className="mx-auto max-w-6xl px-6 pt-32 pb-20 sm:pt-40 sm:pb-28">
        <div className="grid items-center gap-16 lg:grid-cols-[minmax(0,1fr)_auto] lg:gap-12">
          <div className="flex flex-col items-center text-center lg:items-start lg:text-left">
            <div className="hero-enter-logo">
              <HeroFlow />
            </div>
            <h1 className="hero-enter-title font-serif text-4xl font-semibold tracking-tight text-stone-900 sm:text-5xl lg:text-6xl">
              Voice in.
              <br />
              <span className="italic text-red-500">Webhooks out.</span>
            </h1>
            <p className="hero-enter-subtitle mt-6 text-base leading-relaxed text-stone-500 sm:text-lg lg:text-xl">
              Record your thoughts on iPhone or Apple Watch.
              <br />
              Get accurate transcripts.
              <br />
              Pipe them anywhere via webhook.
            </p>
            <div className="hero-enter-buttons mt-10 flex flex-col items-center gap-4 sm:flex-row lg:items-start">
              <a
                href="https://apps.apple.com/app/id6761857751"
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex items-center gap-2 rounded-full bg-stone-900 px-6 py-3 text-sm font-medium text-white shadow-sm transition-colors hover:bg-stone-800"
              >
                <svg className="h-5 w-5" viewBox="0 0 24 24" fill="currentColor">
                  <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z" />
                </svg>
                Download on the App Store
              </a>
              <Link
                href="/docs"
                className="inline-flex items-center gap-2 rounded-full border border-stone-300 px-6 py-3 text-sm font-medium text-stone-700 transition-colors hover:border-stone-400 hover:bg-stone-100"
              >
                Read the docs
                <span aria-hidden="true">&rarr;</span>
              </Link>
            </div>
          </div>

          {/* Device showcase */}
          <div className="hero-enter-devices relative mx-auto pl-12 sm:pl-16 lg:mx-0 lg:pl-12">
            <div className="relative w-[220px] sm:w-[260px] lg:w-[280px]">
              {/* iPhone 17 Pro frame */}
              <div className="relative">
                {/* Side buttons (Action button left, Camera Control right) */}
                <span
                  aria-hidden="true"
                  className="absolute -left-[3px] top-[18%] h-12 w-[4px] rounded-l-sm bg-stone-700"
                />
                <span
                  aria-hidden="true"
                  className="absolute -right-[3px] top-[14%] h-8 w-[4px] rounded-r-sm bg-stone-700"
                />
                <span
                  aria-hidden="true"
                  className="absolute -right-[3px] top-[26%] h-16 w-[4px] rounded-r-sm bg-stone-700"
                />
                <div className="rounded-[3rem] bg-stone-900 p-[10px] shadow-[0_30px_60px_-15px_rgba(26,25,23,0.35)] ring-1 ring-black/5">
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img
                    src={`${BASE_PATH}/screenshot-home-light.png`}
                    alt="Ramble app on iPhone showing the recordings list and an in-progress recording"
                    className="block w-full rounded-[2.4rem]"
                  />
                </div>
              </div>

              {/* Apple Watch Ultra frame, overlapping bottom-left */}
              <div className="absolute -left-10 sm:-left-14 -bottom-6 w-[110px] sm:w-[130px]">
                <div className="relative">
                  {/* Action button (left) */}
                  <span
                    aria-hidden="true"
                    className="absolute -left-[4px] top-[36%] h-6 w-[5px] rounded-l-sm bg-red-500/80"
                  />
                  {/* Digital crown (right) */}
                  <span
                    aria-hidden="true"
                    className="absolute -right-[5px] top-[22%] h-5 w-[6px] rounded-r-md bg-stone-700"
                  />
                  {/* Side button (right) */}
                  <span
                    aria-hidden="true"
                    className="absolute -right-[4px] top-[44%] h-7 w-[5px] rounded-r-sm bg-stone-700"
                  />
                  <div className="rounded-[2.25rem] bg-stone-900 p-[6px] shadow-[0_20px_40px_-10px_rgba(26,25,23,0.4)] ring-1 ring-black/5">
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img
                      src={`${BASE_PATH}/screenshot-watch-recording2.png`}
                      alt="Ramble recording on Apple Watch Ultra"
                      className="block w-full rounded-[1.85rem]"
                    />
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Value Props */}
      <section className="border-t border-stone-200 bg-stone-50">
        <div className="mx-auto max-w-5xl px-6 py-20 sm:py-28">
          <div className="grid gap-12 sm:grid-cols-3 sm:gap-8">
            <div className="flex flex-col items-center text-center sm:items-start sm:text-left">
              <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-sage-100 text-sage-600">
                <Mic className="h-5 w-5" />
              </div>
              <h3 className="mt-4 text-base font-semibold text-stone-900">Best-in-class transcription</h3>
              <p className="mt-2 text-sm leading-relaxed text-stone-500">
                Choose from the latest cloud models — Groq Whisper, Deepgram Nova-3, OpenAI GPT-Transcribe — or use
                free on-device Apple Speech. New models added as they ship.
              </p>
            </div>
            <div className="flex flex-col items-center text-center sm:items-start sm:text-left">
              <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-sage-100 text-sage-600">
                <Webhook className="h-5 w-5" />
              </div>
              <h3 className="mt-4 text-base font-semibold text-stone-900">Webhook-native</h3>
              <p className="mt-2 text-sm leading-relaxed text-stone-500">
                Every transcript can automatically POST to any HTTPS endpoint. Connect to an AI agent, a Zapier
                workflow, a Notion database, or your own backend.
              </p>
            </div>
            <div className="flex flex-col items-center text-center sm:items-start sm:text-left">
              <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-sage-100 text-sage-600">
                <ShieldCheck className="h-5 w-5" />
              </div>
              <h3 className="mt-4 text-base font-semibold text-stone-900">Private by design</h3>
              <p className="mt-2 text-sm leading-relaxed text-stone-500">
                No accounts. No login. No data on our servers. Audio and transcriptions stay on your device unless you
                send them somewhere. Fully open source — read the code.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* How it works */}
      <section className="border-t border-stone-200">
        <div className="mx-auto max-w-5xl px-6 py-20 sm:py-28">
          <h2 className="font-serif text-center text-2xl font-semibold tracking-tight text-stone-900 sm:text-3xl">
            Ramble. Transcribe. Act.
          </h2>
          <div className="mt-12 grid gap-8 sm:grid-cols-3">
            <div className="text-center">
              <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-stone-900 font-serif text-white text-sm font-semibold">
                1
              </div>
              <h3 className="mt-4 text-sm font-semibold text-stone-900">Ramble</h3>
              <p className="mt-1 text-sm text-stone-500">Tap and talk on your iPhone or Apple Watch.</p>
            </div>
            <div className="text-center">
              <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-stone-900 font-serif text-white text-sm font-semibold">
                2
              </div>
              <h3 className="mt-4 text-sm font-semibold text-stone-900">Transcribe</h3>
              <p className="mt-1 text-sm text-stone-500">Cloud models or free on-device Apple Speech.</p>
            </div>
            <div className="text-center">
              <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-stone-900 font-serif text-white text-sm font-semibold">
                3
              </div>
              <h3 className="mt-4 text-sm font-semibold text-stone-900">Send it anywhere</h3>
              <p className="mt-1 text-sm text-stone-500">Auto-POST transcripts to any webhook.</p>
            </div>
          </div>

          <div className="mt-14 text-center">
            <Link
              href="/docs"
              className="inline-flex items-center gap-2 rounded-full border border-stone-300 px-6 py-3 text-sm font-medium text-stone-700 transition-colors hover:border-stone-400 hover:bg-stone-100"
            >
              Build your automation
              <span aria-hidden="true">&rarr;</span>
            </Link>
          </div>
        </div>
      </section>

      {/* FAQ */}
      <section className="border-t border-stone-200">
        <div className="mx-auto max-w-3xl px-6 py-12 sm:py-16">
          <div className="divide-y divide-stone-200 border-t border-b border-stone-200">
            <details className="group">
              <summary className="flex cursor-pointer list-none items-center justify-between gap-4 py-5 text-sm font-medium text-stone-900 transition-colors hover:text-stone-700 sm:text-base">
                Is Ramble free?
                <span aria-hidden="true" className="text-stone-400 transition-transform group-open:rotate-45">
                  +
                </span>
              </summary>
              <div className="pb-5 text-sm leading-relaxed text-stone-500">
                Yes — on-device transcription via Apple Speech and webhook delivery are completely free. Cloud
                transcription models (Groq Whisper, Deepgram Nova-3, OpenAI GPT-Transcribe) are an optional{" "}
                <span className="text-stone-700">$3.99/month</span> subscription.
              </div>
            </details>
            <details className="group">
              <summary className="flex cursor-pointer list-none items-center justify-between gap-4 py-5 text-sm font-medium text-stone-900 transition-colors hover:text-stone-700 sm:text-base">
                What data do you collect?
                <span aria-hidden="true" className="text-stone-400 transition-transform group-open:rotate-45">
                  +
                </span>
              </summary>
              <div className="pb-5 text-sm leading-relaxed text-stone-500">
                None. There are no accounts and no logins. Audio and transcripts live on your device. Cloud
                transcription requests are forwarded to the provider you select and not retained on our end. It&apos;s
                all open source — verify it yourself.
              </div>
            </details>
            <details className="group">
              <summary className="flex cursor-pointer list-none items-center justify-between gap-4 py-5 text-sm font-medium text-stone-900 transition-colors hover:text-stone-700 sm:text-base">
                Where can the webhook send transcripts?
                <span aria-hidden="true" className="text-stone-400 transition-transform group-open:rotate-45">
                  +
                </span>
              </summary>
              <div className="pb-5 text-sm leading-relaxed text-stone-500">
                Any HTTPS endpoint. Plug into Zapier, Make, n8n, Notion, Airtable, your AI agent, or your own backend.
                Requests are signed with a shared secret and retried on failure.{" "}
                <Link href="/docs" className="text-red-500 underline-offset-2 hover:underline">
                  Read the docs
                </Link>
                .
              </div>
            </details>
            <details className="group">
              <summary className="flex cursor-pointer list-none items-center justify-between gap-4 py-5 text-sm font-medium text-stone-900 transition-colors hover:text-stone-700 sm:text-base">
                On-device vs. cloud transcription — what&apos;s the difference?
                <span aria-hidden="true" className="text-stone-400 transition-transform group-open:rotate-45">
                  +
                </span>
              </summary>
              <div className="pb-5 text-sm leading-relaxed text-stone-500">
                On-device uses Apple Speech — free, works offline, accuracy varies by device. Cloud routes audio through
                the model you pick (Whisper, Nova-3, GPT-Transcribe) for sharper transcripts on accents, technical terms, and
                noisy environments.
              </div>
            </details>
            <details className="group">
              <summary className="flex cursor-pointer list-none items-center justify-between gap-4 py-5 text-sm font-medium text-stone-900 transition-colors hover:text-stone-700 sm:text-base">
                Does the Apple Watch app work without my iPhone?
                <span aria-hidden="true" className="text-stone-400 transition-transform group-open:rotate-45">
                  +
                </span>
              </summary>
              <div className="pb-5 text-sm leading-relaxed text-stone-500">
                Yes. The watch records standalone. Recordings sync to your iPhone the next time it&apos;s in range,
                where transcription and webhook delivery happen.
              </div>
            </details>
            <details className="group">
              <summary className="flex cursor-pointer list-none items-center justify-between gap-4 py-5 text-sm font-medium text-stone-900 transition-colors hover:text-stone-700 sm:text-base">
                Is Ramble open source?
                <span aria-hidden="true" className="text-stone-400 transition-transform group-open:rotate-45">
                  +
                </span>
              </summary>
              <div className="pb-5 text-sm leading-relaxed text-stone-500">
                Yes — MIT licensed, hosted on{" "}
                <a
                  href="https://github.com/Jpoliachik/ramble-ios"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-red-500 underline-offset-2 hover:underline"
                >
                  GitHub
                </a>
                . Audit the code, build it yourself, or fork it.
              </div>
            </details>
            <details className="group">
              <summary className="flex cursor-pointer list-none items-center justify-between gap-4 py-5 text-sm font-medium text-stone-900 transition-colors hover:text-stone-700 sm:text-base">
                How do I cancel my subscription?
                <span aria-hidden="true" className="text-stone-400 transition-transform group-open:rotate-45">
                  +
                </span>
              </summary>
              <div className="pb-5 text-sm leading-relaxed text-stone-500">
                Like any iOS subscription — Settings → Apple ID → Subscriptions → Ramble → Cancel. On-device
                transcription and webhooks keep working after cancellation.
              </div>
            </details>
          </div>
        </div>
      </section>

      {/* Pricing */}
      <section className="border-t border-stone-200 bg-stone-50">
        <div className="mx-auto max-w-5xl px-6 py-16 text-center">
          <h2 className="font-serif text-2xl font-semibold tracking-tight text-stone-900 sm:text-3xl">
            Free to use. Open source.
          </h2>
          <p className="mt-4 text-base text-stone-500">
            On-device transcription and webhooks are completely free.
            <br className="hidden sm:block" /> Cloud transcription models available for{" "}
            <span className="font-medium text-stone-700">$3.99/month</span>.
          </p>
          <div className="mt-8 flex flex-col items-center gap-4 sm:flex-row sm:justify-center">
            <a
              href="https://apps.apple.com/app/id6761857751"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-2 rounded-full bg-stone-900 px-6 py-3 text-sm font-medium text-white shadow-sm transition-colors hover:bg-stone-800"
            >
              Get Ramble
            </a>
            <a
              href="https://github.com/Jpoliachik/ramble-ios"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-2 rounded-full border border-stone-300 px-6 py-3 text-sm font-medium text-stone-700 transition-colors hover:border-stone-400 hover:bg-stone-100"
            >
              <svg className="h-5 w-5" viewBox="0 0 24 24" fill="currentColor">
                <path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z" />
              </svg>
              View on GitHub
            </a>
          </div>
        </div>
      </section>
    </main>
  );
}
