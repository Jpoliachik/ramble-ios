import type { Metadata } from "next";
import Link from "next/link";
import { CodeBlock, InlineCode } from "@/components/code-block";
import DocsSidebar from "@/components/docs-sidebar";
import CopyLlmButton from "@/components/copy-llm-button";
import {
  GITHUB_URL,
  PAIR_CODE_EXAMPLE,
  PAIR_CODE_TTL,
  PULL_CADENCE,
  RELAY_URL,
  RETENTION,
} from "@/lib/site";

export const metadata: Metadata = {
  title: "Connect your agent",
  description:
    "Pair Ramble with Muse. Record on your watch, and the transcript waits in a relay inbox until your agent picks it up and acknowledges it.",
};

const RELAY_README_URL = `${GITHUB_URL}/blob/main/relay/README.md`;

const AGENT_INSTRUCTIONS = `Ramble connection
Relay: ${RELAY_URL}

1. When I say "I downloaded Ramble, connect it" and give you a code like ${PAIR_CODE_EXAMPLE},
   POST {"code": "<the code>"} to /pair/exchange. Save the returned "token" in your
   secret storage. Don't repeat the token in chat.
2. Every ${PULL_CADENCE}, GET /inbox with the header
   Authorization: Bearer <token>
3. For each item, do what I asked in "transcription". Use "recording_id" to skip
   anything you've already handled.
4. POST {"ids": [...]} to /inbox/ack with the ids you handled. Ack only after the
   work is done; unacked items come back on the next pull until they expire.
5. If a request returns 401, I disconnected you. Stop checking and tell me.`;

function SectionHeader({ id, children }: { id: string; children: React.ReactNode }) {
  return (
    <h2 id={id} className="scroll-mt-20 font-serif text-2xl font-semibold tracking-tight text-stone-900">
      {children}
    </h2>
  );
}

function SubHeader({ id, children }: { id?: string; children: React.ReactNode }) {
  return (
    <h3 id={id} className="scroll-mt-20 mt-10 font-serif text-lg font-semibold text-stone-900">
      {children}
    </h3>
  );
}

function Endpoint({ method, path }: { method: string; path: string }) {
  return (
    <div className="mt-4 flex items-center gap-3 font-mono text-[13px]">
      <span className="rounded bg-stone-900 px-2 py-0.5 font-semibold text-white">{method}</span>
      <span className="text-stone-900">{path}</span>
    </div>
  );
}

function Table({ head, rows }: { head: string[]; rows: React.ReactNode[][] }) {
  return (
    <div className="mt-4 overflow-x-auto rounded-lg border border-stone-200">
      <table className="w-full text-left text-sm">
        <thead className="bg-stone-50 text-xs uppercase tracking-wide text-stone-500">
          <tr>
            {head.map((h) => (
              <th key={h} className="px-4 py-2.5 font-medium">
                {h}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row, i) => (
            <tr key={i} className="border-t border-stone-100 align-top">
              {row.map((cell, j) => (
                <td key={j} className="px-4 py-3 text-stone-600">
                  {cell}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
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
            Connect your <span className="italic text-red-500">agent</span>
          </h1>
          <p className="mt-4 text-lg leading-relaxed text-stone-500">
            Record on your watch. Your agent handles it. Pairing takes one short code, and after that every transcript
            waits in a small inbox until your agent picks it up.
          </p>

          <div className="mt-14 space-y-16 text-sm leading-relaxed text-stone-600">
            {/* Overview */}
            <section className="space-y-4">
              <SectionHeader id="overview">Overview</SectionHeader>
              <CodeBlock>
                {`Watch ──► iPhone (transcribe) ──► relay inbox ──► your agent
                                         ▲                │
                                         └──── ack ───────┘ (deleted)`}
              </CodeBlock>
              <p>
                Tap the watch and talk. Your iPhone transcribes the recording, on-device by default. Ramble uploads the
                transcript text to the Ramble Relay, which holds one copy for each connected agent. Audio never goes to
                the relay.
              </p>
              <p>
                Your agent checks the inbox on a schedule, does what you asked, and acknowledges each transcript. The
                acknowledgment deletes it from the relay right away. Anything not picked up is deleted after{" "}
                <strong>{RETENTION}</strong>.
              </p>
              <p>
                This is asynchronous on purpose. Your agent checks about every {PULL_CADENCE}, so expect a short wait between
                recording and action. The agent doesn&apos;t need to reply. If your phone is offline, recordings queue
                on the watch and phone and go out when it reconnects.
              </p>
            </section>

            {/* Pairing */}
            <section className="space-y-4">
              <SectionHeader id="pairing">Pairing</SectionHeader>
              <ol className="list-decimal space-y-2 pl-5">
                <li>
                  On your iPhone, open <strong>Settings &rarr; Connect agent</strong>{" "}and tap Muse.
                </li>
                <li>
                  Ramble shows a short code like <InlineCode>{PAIR_CODE_EXAMPLE}</InlineCode>.
                </li>
                <li>
                  Tell your agent: <em>&ldquo;I downloaded Ramble, connect it,&rdquo;</em>{" "}and paste the code.
                </li>
              </ol>
              <p>
                The code is 8 characters, single-use, and expires in {PAIR_CODE_TTL}. It&apos;s case-insensitive and
                ignores dashes and spaces, so <InlineCode>k7qx mp4d</InlineCode>{" "}works too. If it expires, get a
                new one. A new code cancels the previous one.
              </p>
              <p>
                Your agent exchanges the code once for a long-lived token and keeps that token in its secret storage.
                The token never appears in chat. This is the same shape as OAuth&apos;s device authorization grant: the
                short code only works once and dies quickly, so pasting it into a chat is safe.
              </p>
              <p>
                The token is scoped to your one inbox and can only read and acknowledge transcripts. It can&apos;t
                upload, see other agents&apos; queues, or manage connections.
              </p>

              <SubHeader id="disconnect">Disconnect</SubHeader>
              <p>
                In <strong>Settings &rarr; Connect agent</strong>, tap <strong>Disconnect</strong>{" "}next to an agent.
                Its token stops working immediately and its queue is deleted. <strong>Delete everything now</strong>{" "}
                empties every queue at once. Both work from the phone alone and don&apos;t depend on the agent.
              </p>
            </section>

            {/* Muse */}
            <section className="space-y-4">
              <SectionHeader id="muse">Connect Muse</SectionHeader>
              <p>Muse is the supported agent today.</p>
              <ol className="list-decimal space-y-2 pl-5">
                <li>
                  In Ramble, go to <strong>Settings &rarr; Connect agent &rarr; Muse</strong>{" "}to get a code.
                </li>
                <li>
                  In Muse, say <em>&ldquo;I downloaded Ramble, connect it&rdquo;</em>{" "}and paste the code.
                </li>
                <li>
                  Muse checks your inbox on a schedule (every {PULL_CADENCE}{" "}is the suggested cadence), handles each
                  transcript, and acknowledges it.
                </li>
              </ol>
              <p>
                Record something short on your watch to try it. Muse picks it up on its next scheduled check.
              </p>
              <p className="text-stone-500">More agents later.</p>
            </section>

            {/* Instructions for the agent */}
            <section className="space-y-4">
              <SectionHeader id="agent-instructions">Instructions for the agent</SectionHeader>
              <p>
                This is the whole loop Muse runs. If it ever asks how the connection works, copy this and paste it in.
              </p>
              <CodeBlock filename="Paste to your agent">{AGENT_INSTRUCTIONS}</CodeBlock>
            </section>

            {/* API reference */}
            <section className="space-y-4">
              <SectionHeader id="api">How the connection works</SectionHeader>
              <p>
                The relay is a small open-source Cloudflare Worker. These are the three calls an agent makes. They&apos;re
                documented here so you can see exactly what happens, and for anyone running their own relay.
              </p>
              <p>
                All bodies are JSON. Errors are <InlineCode>{`{"error": "..."}`}</InlineCode>{" "}with a 4xx or 5xx
                status.
              </p>
              <p className="rounded-lg border border-stone-200 bg-stone-50 px-4 py-3 text-stone-500">
                The hosted relay&apos;s address will be listed here at launch. Examples below use{" "}
                <InlineCode>{RELAY_URL}</InlineCode>.
              </p>

              <SubHeader id="api-exchange">Exchange a pairing code</SubHeader>
              <Endpoint method="POST" path="/pair/exchange" />
              <p>No auth. The code is the credential. Returns <InlineCode>201</InlineCode>.</p>
              <CodeBlock language="bash">
                {`curl -X POST ${RELAY_URL}/pair/exchange \\
  -H "Content-Type: application/json" \\
  -d '{"code": "${PAIR_CODE_EXAMPLE}"}'`}
              </CodeBlock>
              <CodeBlock language="json">
                {`{
  "token": "rmba_…",
  "connection_id": "con_…",
  "agent_type": "muse",
  "retention_seconds": 86400
}`}
              </CodeBlock>
              <p>
                <InlineCode>retention_seconds</InlineCode>{" "}is how long an unacknowledged transcript waits before
                it&apos;s deleted. Store <InlineCode>token</InlineCode>{" "}as a secret.
              </p>

              <SubHeader id="api-pull">Pull new transcripts</SubHeader>
              <Endpoint method="GET" path="/inbox?since=<id>&limit=<n>" />
              <CodeBlock language="bash">
                {`curl ${RELAY_URL}/inbox \\
  -H "Authorization: Bearer rmba_…"`}
              </CodeBlock>
              <CodeBlock language="json">
                {`{
  "items": [
    {
      "id": 41,
      "recording_id": "6F1C2C1E-…",
      "created_at": "2026-11-01T19:00:00Z",
      "duration": 8.2,
      "transcription": "Remind me to book the dentist.",
      "expires_at": "2026-11-02T19:00:05Z"
    }
  ],
  "next_since": 41,
  "has_more": false
}`}
              </CodeBlock>
              <p>
                Oldest first. <InlineCode>limit</InlineCode>{" "}defaults to 50, max 100.{" "}
                <InlineCode>since</InlineCode>{" "}is optional: the relay keeps no cursor, and unacknowledged items stay
                put, so pulling without it returns everything still waiting. Pass{" "}
                <InlineCode>next_since</InlineCode>{" "}back to page through a backlog while{" "}
                <InlineCode>has_more</InlineCode>{" "}is true.
              </p>
              <p>
                <InlineCode>created_at</InlineCode>{" "}is when you recorded. <InlineCode>duration</InlineCode>{" "}is in
                seconds. Field names match the{" "}
                <Link href="/docs/webhooks" className="text-red-600 underline-offset-2 hover:underline">
                  webhook payload
                </Link>
                .
              </p>

              <SubHeader id="api-ack">Acknowledge</SubHeader>
              <Endpoint method="POST" path="/inbox/ack" />
              <CodeBlock language="bash">
                {`curl -X POST ${RELAY_URL}/inbox/ack \\
  -H "Authorization: Bearer rmba_…" \\
  -H "Content-Type: application/json" \\
  -d '{"ids": [41]}'`}
              </CodeBlock>
              <CodeBlock language="json">{`{"deleted": 1}`}</CodeBlock>
              <p>
                Deletes those items now. Up to 500 ids per call. Ack only after the item is durably handled. An
                unacknowledged item comes back on the next pull until it expires.
              </p>

              <SubHeader id="api-errors">Errors</SubHeader>
              <Table
                head={["Status", "When"]}
                rows={[
                  [
                    <InlineCode key="s">400</InlineCode>,
                    <>
                      Missing <InlineCode>code</InlineCode>, or the code is invalid, already used, or expired (
                      <InlineCode>Invalid or expired pairing code</InlineCode>). Also a malformed{" "}
                      <InlineCode>ids</InlineCode>{" "}list, or more than 500 ids.
                    </>,
                  ],
                  [
                    <InlineCode key="s">401</InlineCode>,
                    <>
                      Invalid or revoked token. The user tapped Disconnect. Stop polling and tell them; they can pair
                      again with a new code.
                    </>,
                  ],
                  [<InlineCode key="s">404</InlineCode>, "Unknown path or method."],
                  [<InlineCode key="s">500</InlineCode>, "Something went wrong on the relay. Retry on the next scheduled pull."],
                ]}
              />

              <SubHeader id="api-app">App-facing endpoints</SubHeader>
              <p>
                The Ramble app uses these. They&apos;re listed for transparency. Agents can&apos;t call them: each
                credential works only on its own side.
              </p>
              <Table
                head={["Endpoint", "Auth", "What it does"]}
                rows={[
                  [<InlineCode key="e">POST /inboxes</InlineCode>, "App Attest", "Creates the inbox. Returns its secret once."],
                  [
                    <InlineCode key="e">POST /inbox</InlineCode>,
                    "App Attest + inbox secret",
                    "Uploads one transcript and queues a copy per connected agent. Idempotent on recording_id.",
                  ],
                  [<InlineCode key="e">DELETE /inbox</InlineCode>, "Inbox secret", "Delete everything now. Empties every queue."],
                  [
                    <InlineCode key="e">POST /pair/code</InlineCode>,
                    "Inbox secret",
                    "Issues a pairing code. Cancels any previous code.",
                  ],
                  [
                    <InlineCode key="e">GET /connections</InlineCode>,
                    "Inbox secret",
                    "Lists connected agents with created, last-pull, and pending counts.",
                  ],
                  [
                    <InlineCode key="e">DELETE /connections/:id</InlineCode>,
                    "Inbox secret",
                    "Disconnect. Revokes the token and deletes its queue.",
                  ],
                ]}
              />
              <p>
                App Attest proves uploads come from a real copy of Ramble on a real Apple device. Disconnect and Delete
                everything need only the inbox secret, so they keep working even if attestation is having a bad day. An
                inbox can have up to 10 connected agents.
              </p>
            </section>

            {/* Storage */}
            <section className="space-y-4">
              <SectionHeader id="storage">What the relay stores</SectionHeader>
              <p>This is the whole list.</p>
              <Table
                head={["What", "Fields", "Deleted when"]}
                rows={[
                  ["Inbox", "Random id, hash of the app's inbox secret, created time", "—"],
                  [
                    "Pairing code",
                    "Hash of the code, inbox id, agent type, expiry",
                    `Used, replaced, or ${PAIR_CODE_TTL} pass`,
                  ],
                  [
                    "Connection",
                    "Random id, inbox id, agent type, hash of the agent's token, created and last-pull times",
                    "You tap Disconnect",
                  ],
                  [
                    "Queued transcript",
                    "Recording id, recorded-at time, duration, text, expiry. One copy per connected agent.",
                    `The agent acks it, you disconnect or tap Delete everything, or ${RETENTION} pass`,
                  ],
                ]}
              />
              <p>
                No accounts, emails, names, IP addresses, or audio. Credentials are stored only as SHA-256 hashes. Logs
                record counts and ids, never transcript text. We identify inboxes, not people.
              </p>
              <p>
                Transcripts pass through the relay and are deleted on delivery. They don&apos;t live there.
              </p>
            </section>

            {/* Self-host */}
            <section className="space-y-4">
              <SectionHeader id="self-host">Self-host</SectionHeader>
              <p>
                The relay is open source. You can run your own on Cloudflare: a Worker plus a D1 database. The free
                tier is enough for personal use.
              </p>
              <CodeBlock language="bash">
                {`cd relay && npm ci
cp wrangler.example.toml wrangler.toml   # set account_id
npx wrangler d1 create ramble-relay       # paste the id into wrangler.toml
npx wrangler d1 migrations apply ramble-relay --remote
npx wrangler kv namespace create ATTEST_KV
npx wrangler deploy`}
              </CodeBlock>
              <p>
                Set <InlineCode>RETENTION_SECONDS</InlineCode>{" "}in <InlineCode>wrangler.toml</InlineCode>{" "}to change
                how long unacknowledged transcripts wait (default 86400, 24 hours). App Attest only works from a real
                device running a copy of Ramble whose bundle ID matches.
              </p>
              <p>
                Full steps, local development, and tests are in the{" "}
                <a
                  href={RELAY_README_URL}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-red-600 underline-offset-2 hover:underline"
                >
                  relay README on GitHub
                </a>
                .
              </p>
            </section>

            <p className="border-t border-stone-200 pt-8 text-stone-500">
              Prefer to send transcripts to your own server or an automation platform? See{" "}
              <Link href="/docs/webhooks" className="text-red-600 underline-offset-2 hover:underline">
                Webhooks
              </Link>
              .
            </p>
          </div>
        </article>
      </div>
    </main>
  );
}
