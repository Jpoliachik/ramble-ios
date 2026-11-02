import type { Metadata } from "next";
import Link from "next/link";
import { CodeBlock, InlineCode } from "@/components/code-block";
import DocsSidebar from "@/components/docs-sidebar";
import CopyLlmButton from "@/components/copy-llm-button";
import { PAIR_CODE_EXAMPLE, PAIR_CODE_TTL, PULL_CADENCE, RELAY_URL, RETENTION } from "@/lib/site";

export const metadata: Metadata = {
  title: "Connect your agent",
  description: "Pair Ramble with your agent using a short code. Your agent picks up each transcript and Ramble deletes it.",
};

const AGENT_INSTRUCTIONS = `Ramble connection
Relay: ${RELAY_URL}

1. When I say "I downloaded Ramble, connect it" and give you a code like ${PAIR_CODE_EXAMPLE},
   POST {"code": "<the code>"} to /pair/exchange. Save the returned "token" as a secret.
2. Every ${PULL_CADENCE}, GET /inbox with the header
   Authorization: Bearer <token>
3. For each item, do what I asked in "transcription".
4. POST {"ids": [...]} to /inbox/ack with the ids you handled.
5. If a request returns 401, I disconnected you. Stop checking and tell me.`;

const API_EXAMPLE = `POST /pair/exchange
{"code": "${PAIR_CODE_EXAMPLE}"}
→ {"token": "rmba_…", "connection_id": "con_…"}

GET /inbox
Authorization: Bearer rmba_…
→ {"items": [{"id": 41, "recording_id": "6F1C…", "created_at": "2026-11-01T19:00:00Z",
              "duration": 8.2, "transcription": "Remind me to book the dentist."}],
   "next_since": 41, "has_more": false}

POST /inbox/ack
Authorization: Bearer rmba_…
{"ids": [41]}
→ {"acknowledged": 1}`;

function SectionHeader({ id, children }: { id: string; children: React.ReactNode }) {
  return (
    <h2 id={id} className="scroll-mt-20 font-serif text-2xl font-semibold tracking-tight text-stone-900">
      {children}
    </h2>
  );
}

export default function AgentDocs() {
  return (
    <main className="flex-1">
      <div className="mx-auto max-w-6xl px-6 py-16 sm:py-24 lg:grid lg:grid-cols-[220px_1fr] lg:gap-12">
        <DocsSidebar page="agent" />

        <article className="min-w-0 max-w-3xl">
          <div className="flex items-center justify-between">
            <Link href="/" className="text-sm text-stone-500 hover:text-stone-900 transition-colors">
              &larr; Back to Ramble
            </Link>
            <CopyLlmButton />
          </div>

          <h1 className="mt-8 font-serif text-3xl font-semibold tracking-tight text-stone-900 sm:text-4xl">
            Connect your agent
          </h1>
          <p className="mt-4 text-lg leading-relaxed text-stone-500">
            One short code, and every transcript waits in a small inbox until your agent picks it up.
          </p>

          <div className="mt-14 space-y-16 text-sm leading-relaxed text-stone-600">
            <section className="space-y-4">
              <SectionHeader id="pairing">Pairing</SectionHeader>
              <ol className="list-decimal space-y-2 pl-5">
                <li>In Ramble on your iPhone, open Settings → Connect agent and pick your agent.</li>
                <li>
                  Tell your agent &ldquo;I downloaded Ramble, connect it&rdquo; and paste the code (like{" "}
                  <InlineCode>{PAIR_CODE_EXAMPLE}</InlineCode>). It works once and expires in {PAIR_CODE_TTL}.
                </li>
                <li>Talk to your watch. Your agent checks about every {PULL_CADENCE}.</li>
              </ol>
              <p>
                Your agent can only pick up your transcripts. Tap Disconnect on the same screen to cut it off; anything
                still waiting is deleted.
              </p>
            </section>

            <section className="space-y-4">
              <SectionHeader id="agent-instructions">Instructions for the agent</SectionHeader>
              <p>This is the whole loop. If your agent asks how the connection works, paste this in.</p>
              <CodeBlock filename="Paste to your agent">{AGENT_INSTRUCTIONS}</CodeBlock>
            </section>

            <section className="space-y-4">
              <SectionHeader id="api">API</SectionHeader>
              <p>
                Three JSON calls. Pulls return the oldest items first; pass <InlineCode>since</InlineCode> with{" "}
                <InlineCode>next_since</InlineCode> to page through a backlog. Acking deletes the text. Anything never
                acked is deleted after {RETENTION}. The relay&apos;s address will be listed here at launch.
              </p>
              <CodeBlock>{API_EXAMPLE}</CodeBlock>
              <p>
                What the relay stores and for how long is in the{" "}
                <Link href="/privacy" className="text-brand-text underline-offset-2 hover:underline">
                  privacy policy
                </Link>
                . To send transcripts to your own server instead, see{" "}
                <Link href="/docs/webhooks" className="text-brand-text underline-offset-2 hover:underline">
                  Webhooks
                </Link>
                .
              </p>
            </section>
          </div>
        </article>
      </div>
    </main>
  );
}
