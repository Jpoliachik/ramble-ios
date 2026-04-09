import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Terms of Use — Ramble",
  description: "Ramble terms of use.",
};

export default function TermsOfUse() {
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
          Terms of Use
        </h1>
        <p className="mt-2 text-sm text-stone-400">
          Last updated: April 9, 2026
        </p>

        <div className="mt-10 space-y-8 text-sm leading-relaxed text-stone-600">
          <section>
            <h2 className="text-base font-semibold text-stone-900">
              Acceptance of terms
            </h2>
            <p className="mt-2">
              By downloading, installing, or using Ramble (&quot;the App&quot;),
              you agree to these Terms of Use. If you do not agree, do not use
              the App.
            </p>
          </section>

          <section>
            <h2 className="text-base font-semibold text-stone-900">
              What Ramble provides
            </h2>
            <p className="mt-2">
              Ramble is a voice recording and transcription app for iPhone and
              Apple Watch. It provides:
            </p>
            <ul className="mt-2 list-disc pl-5 space-y-1">
              <li>Audio recording with local storage on your device</li>
              <li>
                On-device transcription via Apple Speech (free, included)
              </li>
              <li>
                Cloud transcription via third-party providers (requires
                subscription)
              </li>
              <li>
                Webhook delivery of transcriptions to URLs you configure
              </li>
            </ul>
          </section>

          <section>
            <h2 className="text-base font-semibold text-stone-900">
              Subscription
            </h2>
            <p className="mt-2">
              Cloud transcription requires a paid subscription at $2.99/month,
              billed through Apple&apos;s App Store. The subscription
              auto-renews unless cancelled at least 24 hours before the end of
              the current billing period. You can manage or cancel your
              subscription in your Apple ID settings.
            </p>
            <p className="mt-2">
              On-device transcription (Apple Speech) and webhook delivery are
              free and do not require a subscription.
            </p>
          </section>

          <section>
            <h2 className="text-base font-semibold text-stone-900">
              Your data
            </h2>
            <p className="mt-2">
              You own your data. Ramble stores recordings and transcriptions
              locally on your device. We do not have access to your content. See
              our{" "}
              <Link href="/privacy" className="underline hover:text-stone-900">
                Privacy Policy
              </Link>{" "}
              for details.
            </p>
          </section>

          <section>
            <h2 className="text-base font-semibold text-stone-900">
              Webhooks and third-party services
            </h2>
            <p className="mt-2">
              If you configure a webhook, Ramble will send transcription data to
              the URL you provide. You are responsible for the security and
              handling of data at your webhook endpoint. Ramble is not
              responsible for any third-party service you connect to.
            </p>
            <p className="mt-2">
              Cloud transcription is provided by third-party services (Groq,
              Deepgram, OpenAI). Your use of cloud transcription is also subject
              to the respective provider&apos;s terms of service.
            </p>
          </section>

          <section>
            <h2 className="text-base font-semibold text-stone-900">
              Acceptable use
            </h2>
            <p className="mt-2">You agree not to:</p>
            <ul className="mt-2 list-disc pl-5 space-y-1">
              <li>
                Use the App in violation of any applicable laws or regulations
              </li>
              <li>
                Attempt to circumvent the subscription requirement for cloud
                transcription
              </li>
              <li>
                Use the cloud transcription proxy for purposes other than
                Ramble&apos;s intended functionality
              </li>
              <li>
                Record others without their knowledge or consent where required
                by law
              </li>
            </ul>
          </section>

          <section>
            <h2 className="text-base font-semibold text-stone-900">
              Open source
            </h2>
            <p className="mt-2">
              Ramble&apos;s source code is available under an open source
              license on{" "}
              <a
                href="https://github.com/jpoliachik/ramble-ios"
                target="_blank"
                rel="noopener noreferrer"
                className="underline hover:text-stone-900"
              >
                GitHub
              </a>
              . The open source license governs use of the source code. These
              Terms govern your use of the App as distributed on the App Store.
            </p>
          </section>

          <section>
            <h2 className="text-base font-semibold text-stone-900">
              Disclaimer of warranties
            </h2>
            <p className="mt-2">
              The App is provided &quot;as is&quot; without warranties of any
              kind, express or implied. We do not guarantee uninterrupted
              service, transcription accuracy, or webhook delivery reliability.
            </p>
          </section>

          <section>
            <h2 className="text-base font-semibold text-stone-900">
              Limitation of liability
            </h2>
            <p className="mt-2">
              To the maximum extent permitted by law, the developer of Ramble
              shall not be liable for any indirect, incidental, special, or
              consequential damages arising from your use of the App.
            </p>
          </section>

          <section>
            <h2 className="text-base font-semibold text-stone-900">
              Changes to these terms
            </h2>
            <p className="mt-2">
              These terms may be updated from time to time. The updated version
              will be posted here with a new date. Continued use of the App
              after changes constitutes acceptance.
            </p>
          </section>

          <section>
            <h2 className="text-base font-semibold text-stone-900">Contact</h2>
            <p className="mt-2">
              Questions about these terms? Open an issue on{" "}
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
