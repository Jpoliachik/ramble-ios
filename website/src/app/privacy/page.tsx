import type { Metadata } from "next";
import Link from "next/link";
import { APP_STORE_URL, PAIR_CODE_TTL, RETENTION } from "@/lib/site";

export const metadata: Metadata = {
  title: "Privacy Policy",
  description:
    "Ramble privacy policy. No accounts. With on-device transcription, audio stays on your phone. Transcripts pass through the relay and are deleted on delivery.",
};

const link = "underline hover:text-stone-900";
const h2 = "text-base font-semibold text-stone-900";

export default function PrivacyPolicy() {
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
          Privacy Policy
        </h1>
        <p className="mt-2 text-sm text-stone-500">
          Last updated: November 1, 2026
        </p>

        <div className="mt-10 space-y-8 text-sm leading-relaxed text-stone-600">
          <section>
            <h2 className={h2}>The short version</h2>
            <p className="mt-2">
              Ramble has no accounts. Your recordings and transcripts are stored
              on your iPhone and Apple Watch. Audio never goes to Ramble&apos;s
              relay. When you connect an agent, the transcript text passes
              through the relay and is deleted as soon as your agent picks it
              up. If your agent never picks it up, it is deleted after{" "}
              {RETENTION} at most.
            </p>
          </section>

          <section>
            <h2 className={h2}>On your device</h2>
            <p className="mt-2">
              Audio is recorded and stored locally on your Apple Watch and
              iPhone. Transcripts are stored locally on your iPhone. You can
              delete any recording from within the app. Uninstalling the app
              removes everything stored on the device.
            </p>
          </section>

          <section>
            <h2 className={h2}>On-device transcription</h2>
            <p className="mt-2">
              When you use Apple Speech (the default), transcription happens
              entirely on your iPhone. No audio is sent to any server for
              transcription.
            </p>
          </section>

          <section>
            <h2 className={h2}>Cloud transcription proxy</h2>
            <p className="mt-2">
              If you turn on cloud transcription, your audio is sent
              through a stateless Cloudflare Worker proxy to the provider you
              select (Groq, Deepgram, or OpenAI), and the transcript is returned
              to your phone. The proxy:
            </p>
            <ul className="mt-2 list-disc pl-5 space-y-1">
              <li>Does not store audio or transcripts</li>
              <li>Does not log request content</li>
              <li>
                Records anonymous usage analytics: the model used, audio size,
                transcript character count, whether the request succeeded, and
                a hashed device identifier used for usage tracking and rate
                limiting
              </li>
              <li>
                Verifies requests with Apple App Attest to prevent unauthorized
                access
              </li>
            </ul>
          </section>

          <section>
            <h2 className={h2}>Ramble Relay</h2>
            <p className="mt-2">
              The relay is how transcripts reach your agent. It is a small
              Cloudflare Worker that holds transcripts temporarily. It runs
              alongside the transcription proxy. It is used
              only if you connect an agent.
            </p>
            <p className="mt-2">
              <span className="font-medium text-stone-900">
                What is sent.
              </span>{" "}
              After your iPhone transcribes a recording, Ramble uploads the
              transcript text together with the recording&apos;s id, the time
              it was recorded, and its duration. One copy is queued for each
              agent you have connected.
            </p>
            <p className="mt-2">
              <span className="font-medium text-stone-900">
                What is never sent.
              </span>{" "}
              Audio. Transcription happens before upload, so the relay never
              receives a recording.
            </p>
            <p className="mt-2">
              <span className="font-medium text-stone-900">
                How long it stays.
              </span>{" "}
              Your agent pulls new transcripts on a schedule and acknowledges
              each one after handling it. Acknowledging deletes it from the
              relay immediately. That is the normal path. Anything never
              acknowledged is deleted after {RETENTION} at most. The window is
              that long so a transcript is not lost if your agent has trouble
              picking it up for a while.
            </p>

            <p className="mt-4">This is everything the relay stores:</p>
            <div className="mt-2 overflow-x-auto">
              <table className="w-full text-left text-xs">
                <thead className="text-stone-900">
                  <tr className="border-b border-stone-200">
                    <th className="py-2 pr-3 font-semibold">What</th>
                    <th className="py-2 pr-3 font-semibold">Fields</th>
                    <th className="py-2 font-semibold">Deleted when</th>
                  </tr>
                </thead>
                <tbody className="align-top">
                  <tr className="border-b border-stone-100">
                    <td className="py-2 pr-3">Inbox</td>
                    <td className="py-2 pr-3">
                      Random id, hash of the app&apos;s inbox secret, created
                      time
                    </td>
                    <td className="py-2">&mdash;</td>
                  </tr>
                  <tr className="border-b border-stone-100">
                    <td className="py-2 pr-3">Pairing code</td>
                    <td className="py-2 pr-3">
                      Hash of the code, inbox id, expiry. Once your agent
                      uses it, the agent&apos;s new token, until the agent
                      first checks in
                    </td>
                    <td className="py-2">
                      Your agent first checks in, replaced, or {PAIR_CODE_TTL}{" "}
                      pass
                    </td>
                  </tr>
                  <tr className="border-b border-stone-100">
                    <td className="py-2 pr-3">Connection</td>
                    <td className="py-2 pr-3">
                      Random id, inbox id, hash of the agent&apos;s token,
                      created and last-pull times
                    </td>
                    <td className="py-2">You tap Disconnect</td>
                  </tr>
                  <tr>
                    <td className="py-2 pr-3">Transcript</td>
                    <td className="py-2 pr-3">
                      Recording id, recorded-at time, received time, duration, text, expiry.
                      One copy per connected agent.
                    </td>
                    <td className="py-2">
                      The agent acknowledges it, you disconnect or tap Delete
                      everything, or {RETENTION} pass
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <ul className="mt-4 list-disc pl-5 space-y-1">
              <li>
                No accounts, emails, names, IP addresses, or audio are stored.
              </li>
              <li>
                Credentials (the inbox secret, pairing codes, and agent tokens)
                are stored only as SHA-256 hashes. The one exception: a new
                agent token is kept for at most {PAIR_CODE_TTL}, until your
                agent first checks in, so a retried connection still works.
              </li>
              <li>Logs record counts and ids, never transcript text.</li>
              <li>
                Creating an inbox is verified with Apple App Attest. After that,
                the app uses only its inbox secret.
              </li>
            </ul>
            <p className="mt-2">We identify inboxes, not people.</p>
          </section>

          <section>
            <h2 className={h2}>Your controls</h2>
            <ul className="mt-2 list-disc pl-5 space-y-1">
              <li>
                <span className="font-medium text-stone-900">Disconnect</span>{" "}
                revokes that agent&apos;s token and deletes its queue.
              </li>
              <li>
                <span className="font-medium text-stone-900">
                  Delete everything now
                </span>{" "}
                empties every queue on the relay.
              </li>
              <li>
                You can turn off delivery to agents entirely and use Ramble with
                no relay at all.
              </li>
            </ul>
          </section>

          <section>
            <h2 className={h2}>Your agent</h2>
            <p className="mt-2">
              Once your agent pulls a transcript, it has a copy. What it does
              with that copy is governed by the agent provider&apos;s own
              privacy policy, not this one. Ramble has no visibility into or
              control over your agent.
            </p>
          </section>

          <section>
            <h2 className={h2}>Webhooks</h2>
            <p className="mt-2">
              If you configure a webhook, Ramble sends the transcript directly
              from your iPhone to the URL you specify. Webhooks do not go
              through the relay. Ramble has no visibility into or control over
              what happens at your webhook endpoint.
            </p>
          </section>

          <section>
            <h2 className={h2}>Third-party services</h2>
            <p className="mt-2">
              If you opt into cloud transcription, your audio is processed by
              the provider you select. Each provider has its own privacy policy:
            </p>
            <ul className="mt-2 list-disc pl-5 space-y-1">
              <li>
                <a
                  href="https://groq.com/privacy-policy/"
                  target="_blank"
                  rel="noopener noreferrer"
                  className={link}
                >
                  Groq Privacy Policy
                </a>
              </li>
              <li>
                <a
                  href="https://deepgram.com/privacy"
                  target="_blank"
                  rel="noopener noreferrer"
                  className={link}
                >
                  Deepgram Privacy Policy
                </a>
              </li>
              <li>
                <a
                  href="https://openai.com/policies/privacy-policy"
                  target="_blank"
                  rel="noopener noreferrer"
                  className={link}
                >
                  OpenAI Privacy Policy
                </a>
              </li>
            </ul>
            <p className="mt-2">
              The proxy and the relay run on Cloudflare. The agent you connect
              receives your transcripts once it pulls them, under its own
              policy.
            </p>
          </section>

          <section>
            <h2 className={h2}>Apple App Attest</h2>
            <p className="mt-2">
              Ramble uses Apple&apos;s App Attest service to verify that
              transcription requests, and the creation of your relay inbox,
              come from a legitimate copy of the app on a real Apple device. This process
              does not collect or transmit personal information.
            </p>
          </section>

          <section>
            <h2 className={h2}>Purchases</h2>
            <p className="mt-2">
              The app purchase and the optional cloud transcription
              subscription are handled by Apple through the App Store. Ramble
              does not receive your name, email, or payment details.
            </p>
          </section>

          <section>
            <h2 className={h2}>Changes to this policy</h2>
            <p className="mt-2">
              If this policy changes, the updated version will be posted here
              with a new date. Material changes will be noted in the app&apos;s
              release notes.
            </p>
          </section>

          <section>
            <h2 className={h2}>Contact</h2>
            <p className="mt-2">
              Questions about this policy? Use the support link on{" "}
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
