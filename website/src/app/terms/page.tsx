import type { Metadata } from "next";
import Link from "next/link";
import { FREE_NOTES, PRICE_STORY, PROVIDERS, RETENTION, SUPPORT_EMAIL } from "@/lib/site";

export const metadata: Metadata = {
  title: "Terms of Use",
  description: "Ramble terms of use: price, fair use, refunds, and the relay. Simple terms for a simple app.",
};

const link = "underline hover:text-stone-900";
const h2 = "text-base font-semibold text-stone-900";
const strong = "font-medium text-stone-900";

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
          Last updated: November 6, 2026
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
              <li>Audio recording, kept on your devices</li>
              <li>
                Cloud transcription by a third-party provider ({PROVIDERS.map((p) => p.name).join(", ")})
              </li>
              <li>
                Ramble&apos;s relay, which holds transcripts until an agent you
                have connected picks them up
              </li>
              <li>Webhook delivery of transcripts to a URL you configure</li>
            </ul>
          </section>

          <section>
            <h2 className={h2}>Price</h2>
            <p className="mt-2">{PRICE_STORY}</p>
            <ul className="mt-2 list-disc pl-5 space-y-1">
              <li>
                <span className={strong}>Free notes.</span> The first{" "}
                {FREE_NOTES} notes from your inbox transcribe for free. A note
                that can&apos;t be transcribed gives its free note back. A note
                with no speech uses one.
              </li>
              <li>
                <span className={strong}>The unlock.</span> &ldquo;Unlock
                Ramble&rdquo; is a one-time in-app purchase. It transcribes every
                note from the inboxes it is linked to, with no expiry, within
                fair use. One-time purchase. No subscription. The price in the
                app is the App Store&apos;s price for your country.
              </li>
              <li>
                <span className={strong}>Held notes.</span> Notes recorded after
                your free notes are used are kept on your device as &ldquo;Unlock
                to send&rdquo; and send once you unlock.
              </li>
              <li>
                <span className={strong}>Devices.</span> One purchase unlocks
                up to 10 iPhones, counting each iPhone (and each fresh start
                after a reinstall) it was ever linked to. Contact support to add
                more. Family Sharing is not available for the unlock.
              </li>
              <li>
                <span className={strong}>Refunds</span> are handled by Apple
                under its App Store policies. A refunded purchase no longer
                unlocks Ramble. Transcripts already made stay.
              </li>
            </ul>
          </section>

          <section>
            <h2 className={h2}>Fair use</h2>
            <p className="mt-2">
              Ramble is for your own notes. Ramble may pause uploads from a
              setup that abuses the service. A note that was already accepted
              is always transcribed in full. Questions? Email{" "}
              <a href={`mailto:${SUPPORT_EMAIL}`} className={link}>
                {SUPPORT_EMAIL}
              </a>
              .
            </p>
          </section>

          <section>
            <h2 className={h2}>Early buyers</h2>
            <p className="mt-2">
              If you bought Ramble before it became free to download, or ever
              subscribed to its old cloud subscription, there&apos;s nothing to
              unlock. Apple keeps billing a
              subscription until you cancel it in your Apple ID settings.
            </p>
          </section>

          <section>
            <h2 className={h2}>Your data</h2>
            <p className="mt-2">
              You own your recordings and transcripts. Your full history is
              kept on your iPhone. Audio is sent to a transcription provider and
              deleted from Ramble&apos;s server once transcribed. See our{" "}
              <Link href="/privacy" className={link}>
                Privacy Policy
              </Link>{" "}
              for exactly what is stored and for how long.
            </p>
          </section>

          <section>
            <h2 className={h2}>Ramble&apos;s relay</h2>
            <p className="mt-2">
              The relay is provided on a best-effort basis. Transcripts that
              your agent has not picked up are deleted after {RETENTION} at
              most. Your agent must pick them up within that window. A
              transcript deleted this way is still on your iPhone, but it will
              not be delivered to the agent again.
            </p>
            <p className="mt-2">
              When you connect an agent, you authorize it to read and
              acknowledge the transcripts sent to it. You are responsible for
              choosing which agents to connect and for what they do with your
              transcripts. You can cut an agent off at any time with Disconnect,
              and delete everything waiting for your agents with Delete waiting
              notes.
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
              Transcription is provided by a third-party service (
              {PROVIDERS.map((p) => p.name).join(", ")}).
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
                Use Ramble&apos;s server or relay for purposes other than
                Ramble&apos;s intended functionality, or interfere with their
                operation
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
              Questions about these terms? Email{" "}
              <a href={`mailto:${SUPPORT_EMAIL}`} className={link}>
                {SUPPORT_EMAIL}
              </a>
              .
            </p>
          </section>
        </div>
      </article>
    </main>
  );
}
