import type { Metadata } from "next";
import Link from "next/link";
import { APP_PRICE, APP_STORE_URL, RETENTION } from "@/lib/site";

export const metadata: Metadata = {
  title: "Terms of Use",
  description: "Ramble terms of use. Simple terms for a simple app.",
};

const link = "underline hover:text-stone-900";
const h2 = "text-base font-semibold text-stone-900";

export default function TermsOfUse() {
  return (
    <main className="flex-1">
      <article className="mx-auto max-w-2xl px-6 py-16 sm:py-24">
        <Link
          href="/"
          className="text-sm text-stone-500 hover:text-stone-900 transition-colors"
        >
          &larr; Back to Ramble
        </Link>
        <h1 className="mt-8 text-3xl font-semibold tracking-tight text-stone-900">
          Terms of Use
        </h1>
        <p className="mt-2 text-sm text-stone-500">
          Last updated: November 1, 2026
        </p>

        <div className="mt-10 space-y-8 text-sm leading-relaxed text-stone-600">
          <section>
            <h2 className={h2}>Acceptance of terms</h2>
            <p className="mt-2">
              By downloading, installing, or using Ramble (&quot;the App&quot;),
              you agree to these Terms of Use. If you do not agree, do not use
              the App.
            </p>
          </section>

          <section>
            <h2 className={h2}>What Ramble provides</h2>
            <p className="mt-2">
              Ramble is an Apple Watch and iPhone app that records what you say,
              transcribes it, and forwards the transcript to your agent. It
              provides:
            </p>
            <ul className="mt-2 list-disc pl-5 space-y-1">
              <li>Audio recording with local storage on your devices</li>
              <li>On-device transcription via Apple Speech</li>
              <li>
                Ramble Relay, which holds transcripts until an agent you have
                connected picks them up
              </li>
              <li>Webhook delivery of transcripts to URLs you configure</li>
              <li>
                Optional cloud transcription via third-party providers
              </li>
            </ul>
          </section>

          <section>
            <h2 className={h2}>Purchase</h2>
            <p className="mt-2">
              Ramble is a one-time purchase of {APP_PRICE} through Apple&apos;s
              App Store. There are no subscriptions.
            </p>
            <p className="mt-2">
              Refunds are handled by Apple under its App Store policies.
            </p>
          </section>

          <section>
            <h2 className={h2}>Your data</h2>
            <p className="mt-2">
              You own your recordings and transcripts. They are stored on your
              devices. Transcripts you send to an agent pass through the relay
              and are deleted on delivery. See our{" "}
              <Link href="/privacy" className={link}>
                Privacy Policy
              </Link>{" "}
              for exactly what is stored and for how long.
            </p>
          </section>

          <section>
            <h2 className={h2}>Ramble Relay</h2>
            <p className="mt-2">
              The relay is provided on a best-effort basis. Transcripts that
              your agent has not acknowledged are deleted after {RETENTION} at
              most.
              Your agent must pull them within that window. A transcript deleted
              this way is still on your iPhone, but it will not be delivered to
              the agent again.
            </p>
            <p className="mt-2">
              When you connect an agent, you authorize it to read and
              acknowledge the transcripts sent to your inbox. You are
              responsible for choosing which agents to connect and for what
              they do with your transcripts. You can revoke an agent at any
              time with Disconnect, and delete everything queued for your
              agents with Delete everything now.
            </p>
          </section>

          <section>
            <h2 className={h2}>Agents, webhooks, and third-party services</h2>
            <p className="mt-2">
              Agents you connect and webhooks you configure are operated by
              you or by third parties. You are responsible for the security and
              handling of data once it reaches them. Ramble is not responsible
              for any third-party service you connect to, and your use of an
              agent is subject to its provider&apos;s terms.
            </p>
            <p className="mt-2">
              Cloud transcription is provided by third-party services (Groq,
              Deepgram, OpenAI). Your use of cloud transcription is also subject
              to the respective provider&apos;s terms of service.
            </p>
          </section>

          <section>
            <h2 className={h2}>Acceptable use</h2>
            <p className="mt-2">You agree not to:</p>
            <ul className="mt-2 list-disc pl-5 space-y-1">
              <li>
                Use the App in violation of any applicable laws or regulations
              </li>
              <li>
                Use the cloud transcription proxy or the hosted relay for
                purposes other than Ramble&apos;s intended functionality, or
                interfere with their operation
              </li>
              <li>
                Record others without their knowledge or consent where required
                by law
              </li>
            </ul>
          </section>

          <section>
            <h2 className={h2}>Disclaimer of warranties</h2>
            <p className="mt-2">
              The App and its hosted services are provided &quot;as is&quot;
              without warranties of any kind, express or implied. We do not
              guarantee uninterrupted service, transcription accuracy, or
              delivery to your agent or webhook.
            </p>
          </section>

          <section>
            <h2 className={h2}>Limitation of liability</h2>
            <p className="mt-2">
              To the maximum extent permitted by law, the developer of Ramble
              shall not be liable for any indirect, incidental, special, or
              consequential damages arising from your use of the App, including
              actions taken by agents or services you connect.
            </p>
          </section>

          <section>
            <h2 className={h2}>Changes to these terms</h2>
            <p className="mt-2">
              These terms may be updated from time to time. The updated version
              will be posted here with a new date. Continued use of the App
              after changes constitutes acceptance.
            </p>
          </section>

          <section>
            <h2 className={h2}>Contact</h2>
            <p className="mt-2">
              Questions about these terms? Use the support link on{" "}
              <a
                href={APP_STORE_URL}
                target="_blank"
                rel="noopener noreferrer"
                className={link}
              >
                Ramble&apos;s App Store page
              </a>
              .
            </p>
          </section>
        </div>
      </article>
    </main>
  );
}
