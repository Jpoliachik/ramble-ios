import type { Metadata } from "next";
import Link from "next/link";
import { FAIR_USE, SUPPORT_EMAIL } from "@/lib/site";

export const metadata: Metadata = {
  title: "Support",
  description: `Get help with Ramble. Email ${SUPPORT_EMAIL}, or find quick answers on usage limits, restoring a purchase, refunds, and setting up the watch.`,
};

const link = "text-brand-text underline-offset-2 hover:underline";
const h2 = "text-base font-semibold text-stone-900";

export default function Support() {
  return (
    <main className="flex-1">
      <article className="mx-auto max-w-2xl px-6 py-16 sm:py-24">
        <Link href="/" className="text-sm text-stone-500 hover:text-stone-900 transition-colors">
          &larr; Back to Ramble
        </Link>
        <h1 className="mt-8 font-serif text-3xl font-semibold tracking-tight text-stone-900 sm:text-4xl">Support</h1>
        <p className="mt-4 text-lg leading-relaxed text-stone-500">
          Email{" "}
          <a href={`mailto:${SUPPORT_EMAIL}`} className={link}>
            {SUPPORT_EMAIL}
          </a>
          . We read every message.
        </p>

        <div className="mt-12 space-y-8 text-sm leading-relaxed text-stone-600">
          <section>
            <h2 className={h2}>A note says &ldquo;Usage limit reached&rdquo;</h2>
            <p className="mt-2">
              To stop abuse, Ramble pauses transcription after {FAIR_USE}. Your notes are kept, and they transcribe on
              their own on the date shown on the note. If that looks wrong, tap Contact support on the note, or email
              us.
            </p>
          </section>

          <section>
            <h2 className={h2}>Restore your purchase on a new iPhone</h2>
            <p className="mt-2">
              Install Ramble and open it, signed in with the same Apple ID. It unlocks on its own. If it doesn&rsquo;t,
              open Settings in Ramble and tap Restore Purchases.
            </p>
            <p className="mt-2">
              One purchase works on up to 5 iPhones. Each fresh start after a reinstall counts as one, and a spot opens
              when one of them goes 90 days without sending a note.
            </p>
          </section>

          <section>
            <h2 className={h2}>Refunds</h2>
            <p className="mt-2">
              Purchases go through Apple, so Apple handles refunds. Request one at{" "}
              <a href="https://reportaproblem.apple.com" target="_blank" rel="noopener noreferrer" className={link}>
                reportaproblem.apple.com
              </a>
              .
            </p>
          </section>

          <section>
            <h2 className={h2}>The watch shows &ldquo;Set up&rdquo;</h2>
            <p className="mt-2">
              The watch isn&rsquo;t connected to Ramble yet. Open Ramble on your iPhone once, and tap Get started if
              it&rsquo;s your first time. The watch connects on its own and waiting notes send. Until then they&rsquo;re
              safe on the watch.
            </p>
          </section>

          <section>
            <h2 className={h2}>Something else</h2>
            <p className="mt-2">
              <Link href="/docs/help" className={link}>
                Requirements and troubleshooting
              </Link>{" "}
              covers the watch, transcription, and your agent. Or email{" "}
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
