import Link from "next/link";
import { Mic, Webhook, ShieldCheck, Zap, BrainCircuit, Database, Code } from "lucide-react";

export default function Home() {
  return (
    <main className="flex-1">
      {/* Hero */}
      <section className="mx-auto max-w-5xl px-6 pt-32 pb-20 sm:pt-40 sm:pb-28">
        <div className="flex flex-col items-center text-center">
          <h1 className="font-serif text-4xl font-semibold tracking-tight text-stone-900 sm:text-5xl lg:text-6xl">
            Voice that goes somewhere
          </h1>
          <p className="mt-6 text-base leading-relaxed text-stone-500 sm:text-lg lg:text-xl">
            Record your thoughts on iPhone or Apple Watch.
            <br />
            Get accurate transcripts.
            <br />
            Pipe them anywhere via webhook.
          </p>
          <div className="mt-10 flex flex-col items-center gap-4 sm:flex-row">
            <a
              href="https://apps.apple.com/app/ramble"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-2 rounded-full bg-stone-900 px-6 py-3 text-sm font-medium text-white shadow-sm transition-colors hover:bg-stone-800"
            >
              <svg className="h-5 w-5" viewBox="0 0 24 24" fill="currentColor">
                <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z" />
              </svg>
              Free on the App Store
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
                Choose from the latest cloud models — Groq Whisper, Deepgram Nova-3, OpenAI GPT-4o Transcribe — or use
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
        </div>
      </section>

      {/* Webhook / Automations */}
      <section className="border-t border-stone-200 bg-stone-50">
        <div className="mx-auto max-w-5xl px-6 py-20 sm:py-28">
          <div className="max-w-2xl mx-auto text-center">
            <h2 className="font-serif text-2xl font-semibold tracking-tight text-stone-900 sm:text-3xl">
              Your voice triggers anything.
            </h2>
          </div>

          <div className="mt-14 grid gap-6 sm:grid-cols-2 lg:grid-cols-4">
            <div className="rounded-xl border border-stone-200 bg-cream p-5">
              <BrainCircuit className="h-5 w-5 text-sage-600" />
              <h3 className="mt-3 text-sm font-semibold text-stone-900">AI agents</h3>
              <p className="mt-1 text-sm text-stone-500">Ramble your thoughts, let AI sort them out.</p>
            </div>
            <div className="rounded-xl border border-stone-200 bg-cream p-5">
              <Zap className="h-5 w-5 text-sage-600" />
              <h3 className="mt-3 text-sm font-semibold text-stone-900">Zapier &amp; Make</h3>
              <p className="mt-1 text-sm text-stone-500">Plug into any automation platform with a single webhook.</p>
            </div>
            <div className="rounded-xl border border-stone-200 bg-cream p-5">
              <Database className="h-5 w-5 text-sage-600" />
              <h3 className="mt-3 text-sm font-semibold text-stone-900">Notion &amp; Airtable</h3>
              <p className="mt-1 text-sm text-stone-500">
                Ramble a thought, it shows up in your database. Journaling, meeting notes, field logs.
              </p>
            </div>
            <div className="rounded-xl border border-stone-200 bg-cream p-5">
              <Code className="h-5 w-5 text-sage-600" />
              <h3 className="mt-3 text-sm font-semibold text-stone-900">Your own backend</h3>
              <p className="mt-1 text-sm text-stone-500">Any HTTPS endpoint. Signed requests, automatic retries.</p>
            </div>
          </div>

          <div className="mt-10 text-center">
            <Link
              href="/docs"
              className="inline-flex items-center gap-2 rounded-full border border-stone-300 px-6 py-3 text-sm font-medium text-stone-700 transition-colors hover:border-stone-400 hover:bg-stone-100"
            >
              Build your first automation
              <span aria-hidden="true">&rarr;</span>
            </Link>
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
            <span className="font-medium text-stone-700">$2.99/month</span>.
          </p>
          <div className="mt-8">
            <a
              href="https://apps.apple.com/app/ramble"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-2 rounded-full bg-stone-900 px-6 py-3 text-sm font-medium text-white shadow-sm transition-colors hover:bg-stone-800"
            >
              Get Ramble
            </a>
          </div>
        </div>
      </section>
    </main>
  );
}
