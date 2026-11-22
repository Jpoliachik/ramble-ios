import type { Metadata } from "next";
import Link from "next/link";
import { PAIR_CODE_TTL, PRIVACY_WORDING, PROVIDERS, RETENTION, SUPPORT_EMAIL, USAGE_WORDING } from "@/lib/site";

export const metadata: Metadata = {
  title: "Privacy Policy",
  description:
    "Ramble privacy policy. No accounts. Ramble's server is a relay, not an archive: audio is deleted once transcribed, and transcripts once your agent picks them up, or after 30 days. Usage stats never include your audio or words.",
  alternates: { canonical: "/privacy" },
};

const link = "underline hover:text-stone-900";
const h2 = "text-base font-semibold text-stone-900";
const strong = "font-medium text-stone-900";

const stored: [string, string, string][] = [
  [
    "Inbox",
    "Random id, hash of the app's inbox secret, your transcription settings (language, vocabulary, filler words), the free-note count, whether it is unlocked, a separate random usage id, the app version and iOS or watchOS version each device last sent, and whether your iPhone has a webhook destination set (never its address)",
    "Kept while you use Ramble",
  ],
  ["Watch connection", "Hash of the watch's token", "Replaced when the iPhone connects the watch again, or revoked"],
  [
    "Audio",
    "The recording, in private storage that no endpoint returns",
    "As soon as the note has a transcript, has no speech, or fails for good. At most 1 day after upload",
  ],
  [
    "Note",
    "Note id, which device recorded it, recorded-at time, received time, length measured by the server, status, and the transcript for your own devices",
    "The transcript once your iPhone has saved it (and, for a watch note, the watch has read it), or after 30 days. The rest 30 days after that",
  ],
  [
    "Agent copy",
    "Note id, recorded-at time, received time, length, transcript. One copy per agent",
    `Your agent picks it up, you disconnect it, you tap Delete waiting notes, or ${RETENTION} pass`,
  ],
  [
    "Pairing code",
    `Hash of the code, expiry. Once used, the agent's new key, encrypted, so a retried connection gets the same key`,
    `Replaced, or ${PAIR_CODE_TTL} after it was made`,
  ],
  [
    "Agent connection",
    "Random id, hash of the agent's key, the name it gave itself, created and last check-in times, whether it last checked in through the relay API or the MCP connector, its wake-up hook (URL, encrypted headers, last ping time and status), and any event subscriptions its connector made (callback URL, encrypted signing secret, expiry, last delivery time and status)",
    "You disconnect it",
  ],
  [
    "Purchase",
    "Apple's purchase or app record ids, product, dates, the inboxes it unlocks, and audio hours used this month",
    "Kept while the purchase is valid",
  ],
  [
    "Usage stats",
    "One row per note, under the inbox's random usage id: when it was recorded and received, its length, which device recorded it, how it turned out (transcribed, no speech, or failed) and how many tries it took, whether it used a free note, its language setting, whether filler-word removal and vocabulary were on (not the words), and the app version. No note id, audio, or transcript text",
    "Kept indefinitely, to fix problems and see how Ramble is used",
  ],
  ["App Attest key", "Key id and public key from Apple App Attest", "Kept while you use Ramble"],
];

export default function PrivacyPolicy() {
  return (
    <main className="flex-1">
      <article className="mx-auto max-w-2xl px-6 py-16 sm:py-24">
        <Link href="/" className="text-sm text-stone-500 hover:text-stone-900 transition-colors">
          &larr; Back to Ramble
        </Link>
        <h1 className="mt-8 text-3xl font-semibold tracking-tight text-stone-900">Privacy Policy</h1>
        <p className="mt-2 text-sm text-stone-500">Last updated: November 15, 2026</p>

        <div className="mt-10 space-y-8 text-sm leading-relaxed text-stone-600">
          <section>
            <h2 className={h2}>The short version</h2>
            <p className="mt-2">
              {PRIVACY_WORDING} {USAGE_WORDING}
            </p>
            <p className="mt-2">
              Ramble has no accounts. We never ask for your name or email, and we identify inboxes, not people.
            </p>
          </section>

          <section>
            <h2 className={h2}>On your devices</h2>
            <p className="mt-2">
              Your iPhone keeps every note&apos;s audio and transcript until you delete it or delete the app. The watch
              keeps a note&apos;s audio until the transcript is done and your iPhone has the audio, or for 30 days at
              most after that. You can delete any note in the app, and Settings &rarr; Your data &rarr; Delete all data
              removes every note from your iPhone.
            </p>
          </section>

          <section>
            <h2 className={h2}>Transcription</h2>
            <p className="mt-2">
              All transcription happens in the cloud. Nothing is uploaded until you tap Get started in the app. After
              that, your watch or iPhone uploads each recording to Ramble&apos;s server, which sends the audio to one
              transcription provider, <span className={strong}>Groq</span> (Whisper v3 Turbo). No other provider
              receives your audio.
            </p>
            <p className="mt-2">
              Groq&apos;s API terms exclude training on your audio. Groq also receives your language and vocabulary
              settings, if you set them. Ramble deletes the audio as soon as the transcript is ready.
            </p>
          </section>

          <section>
            <h2 className={h2}>Who receives your transcripts</h2>
            <ul className="mt-2 list-disc pl-5 space-y-1">
              <li>
                <span className={strong}>Your own devices.</span> Your iPhone, and the watch for its own notes.
              </li>
              <li>
                <span className={strong}>The agents you connect.</span> Each agent gets its own copy of notes recorded
                after it connected. Once it picks one up, what it does with it is governed by that agent&apos;s own
                privacy policy, not this one.
              </li>
              <li>
                <span className={strong}>Your webhook, if you set one.</span> Your iPhone sends the transcript straight
                to your URL. Ramble&apos;s server never sees the URL or its secret.
              </li>
            </ul>
            <p className="mt-2">Notes with no speech go nowhere.</p>
          </section>

          <section>
            <h2 className={h2}>What Ramble&apos;s server stores</h2>
            <p className="mt-2">
              The server runs on Cloudflare. This is everything it stores, and when each piece is deleted:
            </p>
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
                  {stored.map(([what, fields, deleted]) => (
                    <tr key={what} className="border-b border-stone-100 last:border-0">
                      <td className="py-2 pr-3">{what}</td>
                      <td className="py-2 pr-3">{fields}</td>
                      <td className="py-2">{deleted}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <ul className="mt-4 list-disc pl-5 space-y-1">
              <li>
                <span className={strong}>Backups.</span> Deleted transcripts can remain in the database&apos;s
                point-in-time backup for up to 30 days. That backup is used only to recover from an outage.
              </li>
              <li>
                Credentials (the inbox secret, the watch token, and agent keys) are stored only as SHA-256 hashes,
                except a new agent key during its pairing code&apos;s {PAIR_CODE_TTL}, which is kept encrypted. Wake-up
                hook headers and event signing secrets are stored only encrypted.
              </li>
              <li>
                Logs contain no audio, transcript text, request bodies, credentials, or network addresses, and record
                inbox ids only as hashes.
              </li>
              <li>
                Your network address is used only to apply rate limits, and is never stored with your notes or logged.
              </li>
              <li>
                <span className={strong}>Usage stats.</span> We use them only to find and fix problems and to see how
                Ramble is used, for example how many notes people record and how long they are. They are never sold,
                shared, or used for advertising, and never include your audio or your words.
              </li>
              <li>No names, emails, or payment details.</li>
            </ul>
          </section>

          <section>
            <h2 className={h2}>Your controls</h2>
            <ul className="mt-2 list-disc pl-5 space-y-1">
              <li>
                <span className={strong}>Disconnect</span> cuts an agent off at once and deletes everything waiting for
                it.
              </li>
              <li>
                <span className={strong}>Delete waiting notes</span> deletes every copy your agents haven&apos;t picked
                up.
              </li>
              <li>
                <span className={strong}>Delete</span> on a note, or <span className={strong}>Delete all data</span>,
                removes notes from your iPhone.
              </li>
            </ul>
          </section>

          <section>
            <h2 className={h2}>Third-party services</h2>
            <p className="mt-2">The transcription provider has its own privacy policy:</p>
            <ul className="mt-2 list-disc pl-5 space-y-1">
              {PROVIDERS.map((p) => (
                <li key={p.name}>
                  <a href={p.privacy} target="_blank" rel="noopener noreferrer" className={link}>
                    {p.name} Privacy Policy
                  </a>
                </li>
              ))}
            </ul>
            <p className="mt-2">
              Ramble&apos;s server, its database, and its audio storage run on Cloudflare. Apple handles App Attest and
              App Store purchases.
            </p>
          </section>

          <section>
            <h2 className={h2}>Apple App Attest</h2>
            <p className="mt-2">
              Ramble uses Apple&apos;s App Attest to check that a new inbox is created by a real copy of the app on a
              real Apple device. It does not collect or send personal information.
            </p>
          </section>

          <section>
            <h2 className={h2}>Purchases</h2>
            <p className="mt-2">
              Purchases are handled by Apple through the App Store. To unlock your notes, the app sends Ramble&apos;s
              server Apple&apos;s signed purchase record, which holds ids, the product, and dates. Ramble never receives
              your name, email, or payment details.
            </p>
          </section>

          <section>
            <h2 className={h2}>This website</h2>
            <p className="mt-2">
              ramble.watch is hosted on Vercel and uses Vercel Web Analytics to count page views. It sets no cookies,
              and visitors are counted without being identified across sites or across days. The app sends nothing to
              it.
            </p>
          </section>

          <section>
            <h2 className={h2}>Changes to this policy</h2>
            <p className="mt-2">
              If this policy changes, the updated version will be posted here with a new date. Material changes will
              be noted in the app&apos;s release notes.
            </p>
          </section>

          <section>
            <h2 className={h2}>Contact</h2>
            <p className="mt-2">
              Ramble is made by Good Loop Software LLC. Questions about this policy? Email{" "}
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
