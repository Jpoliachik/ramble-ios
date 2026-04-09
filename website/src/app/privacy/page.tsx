import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Privacy Policy — Ramble",
  description: "Ramble privacy policy. Your data stays yours.",
};

export default function PrivacyPolicy() {
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
          Privacy Policy
        </h1>
        <p className="mt-2 text-sm text-stone-400">
          Last updated: April 9, 2026
        </p>

        <div className="mt-10 space-y-8 text-sm leading-relaxed text-stone-600">
          <section>
            <h2 className="text-base font-semibold text-stone-900">
              The short version
            </h2>
            <p className="mt-2">
              Ramble does not collect, store, or transmit your personal data. No
              accounts. No analytics. No tracking. Your audio recordings and
              transcriptions stay on your device unless you explicitly choose to
              send them somewhere.
            </p>
          </section>

          <section>
            <h2 className="text-base font-semibold text-stone-900">
              Audio recordings
            </h2>
            <p className="mt-2">
              All audio is recorded and stored locally on your device. Ramble
              never uploads your audio to our servers. If you enable cloud
              transcription, your audio is sent directly to the transcription
              provider (Groq, Deepgram, or OpenAI) via our stateless proxy for
              processing. The proxy does not store your audio — it forwards the
              request and returns the result.
            </p>
          </section>

          <section>
            <h2 className="text-base font-semibold text-stone-900">
              Transcriptions
            </h2>
            <p className="mt-2">
              Transcriptions are stored locally on your device. If you configure
              a webhook, transcriptions are sent to the URL you specify. Ramble
              has no visibility into or control over what happens at your webhook
              endpoint.
            </p>
          </section>

          <section>
            <h2 className="text-base font-semibold text-stone-900">
              Cloud transcription proxy
            </h2>
            <p className="mt-2">
              When using cloud transcription, requests pass through a stateless
              Cloudflare Worker proxy. The proxy:
            </p>
            <ul className="mt-2 list-disc pl-5 space-y-1">
              <li>Does not store audio or transcription data</li>
              <li>Does not log request content</li>
              <li>
                Uses a device identifier solely for usage tracking and rate
                limiting
              </li>
              <li>
                Verifies requests via Apple App Attest to prevent unauthorized
                access
              </li>
            </ul>
          </section>

          <section>
            <h2 className="text-base font-semibold text-stone-900">
              On-device transcription
            </h2>
            <p className="mt-2">
              When using Apple Speech (the default), transcription happens
              entirely on your device. No audio data leaves your phone.
            </p>
          </section>

          <section>
            <h2 className="text-base font-semibold text-stone-900">
              Third-party services
            </h2>
            <p className="mt-2">
              If you opt into cloud transcription, your audio is processed by
              the provider you select. Each provider has their own privacy
              policy:
            </p>
            <ul className="mt-2 list-disc pl-5 space-y-1">
              <li>
                <a
                  href="https://groq.com/privacy-policy/"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="underline hover:text-stone-900"
                >
                  Groq Privacy Policy
                </a>
              </li>
              <li>
                <a
                  href="https://deepgram.com/privacy"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="underline hover:text-stone-900"
                >
                  Deepgram Privacy Policy
                </a>
              </li>
              <li>
                <a
                  href="https://openai.com/policies/privacy-policy"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="underline hover:text-stone-900"
                >
                  OpenAI Privacy Policy
                </a>
              </li>
            </ul>
          </section>

          <section>
            <h2 className="text-base font-semibold text-stone-900">
              Apple App Attest
            </h2>
            <p className="mt-2">
              Ramble uses Apple&apos;s App Attest service to verify that cloud
              transcription requests originate from a legitimate copy of the app
              on a real Apple device. This process does not collect or transmit
              personal information.
            </p>
          </section>

          <section>
            <h2 className="text-base font-semibold text-stone-900">
              Data you control
            </h2>
            <p className="mt-2">
              All your data is stored locally. You can delete any recording at
              any time from within the app. Uninstalling the app removes all
              data.
            </p>
          </section>

          <section>
            <h2 className="text-base font-semibold text-stone-900">
              Open source
            </h2>
            <p className="mt-2">
              Ramble is fully open source. You can inspect exactly what data the
              app accesses and transmits by reviewing the{" "}
              <a
                href="https://github.com/jpoliachik/ramble-ios"
                target="_blank"
                rel="noopener noreferrer"
                className="underline hover:text-stone-900"
              >
                source code
              </a>
              .
            </p>
          </section>

          <section>
            <h2 className="text-base font-semibold text-stone-900">
              Changes to this policy
            </h2>
            <p className="mt-2">
              If this policy changes, the updated version will be posted here
              with a new date. Material changes will be noted in the app&apos;s
              release notes.
            </p>
          </section>

          <section>
            <h2 className="text-base font-semibold text-stone-900">Contact</h2>
            <p className="mt-2">
              Questions about this policy? Open an issue on{" "}
              <a
                href="https://github.com/jpoliachik/ramble-ios/issues"
                target="_blank"
                rel="noopener noreferrer"
                className="underline hover:text-stone-900"
              >
                GitHub
              </a>
              .
            </p>
          </section>
        </div>
      </article>
    </main>
  );
}
