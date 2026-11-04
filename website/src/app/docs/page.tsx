import type { Metadata } from "next";
import Link from "next/link";
import { CodeBlock, InlineCode } from "@/components/code-block";
import DocsSidebar from "@/components/docs-sidebar";
import CopyLlmButton from "@/components/copy-llm-button";
import { PAIR_CODE_EXAMPLE, PAIR_CODE_TTL, RELAY_URL, RETENTION, SITE_URL } from "@/lib/site";

export const metadata: Metadata = {
  title: "Connect your agent",
  description: "Pair Ramble with your agent using a short code. Your agent picks up each transcript and Ramble deletes it.",
};

const AGENT_INSTRUCTIONS = `Ramble connection
Relay: ${RELAY_URL}

1. When I say "I downloaded Ramble, connect it" and give you a code like ${PAIR_CODE_EXAMPLE},
   POST {"code": "<the code>"} to /pair/exchange. Save the returned "token" as a secret.
2. GET /inbox with the header
   Authorization: Bearer <token>
   Check as often as you can, using whatever way of running recurring work suits you
   best. It's a tiny request that usually returns an empty list, so frequent checks are fine.
3. For each item, do what I asked in "transcription".
4. POST {"ids": [...]} to /inbox/ack with the ids you handled. If "has_more" is true, pull again.
5. If a request returns 401, I disconnected you. Stop checking and tell me.

Send a User-Agent header on every request (any name, like my-agent/1.0). Retry
timeouts, dropped connections, and 5xx errors after 2, 5, then 15 seconds. Every
call is safe to retry, including the code exchange. Examples: ${SITE_URL}/docs#requests`;

const CURL_EXAMPLE = `RELAY=${RELAY_URL}

# Pair (once)
curl -sS --retry 3 -X POST "$RELAY/pair/exchange" \\
  -H "Content-Type: application/json" -d '{"code": "${PAIR_CODE_EXAMPLE}"}'

# Check
curl -sS --retry 3 "$RELAY/inbox" -H "Authorization: Bearer $TOKEN"

# Ack what you handled
curl -sS --retry 3 -X POST "$RELAY/inbox/ack" -H "Authorization: Bearer $TOKEN" \\
  -H "Content-Type: application/json" -d '{"ids": [41]}'`;

const PYTHON_EXAMPLE = `import json, time, urllib.error, urllib.request

RELAY = "${RELAY_URL}"

def call(method, path, body=None, token=None):
    # Python's default urllib User-Agent is blocked at the network edge. Set your own.
    headers = {"User-Agent": "my-agent/1.0", "Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    data = json.dumps(body).encode() if body is not None else None
    for wait in (2, 5, 15, None):
        try:
            req = urllib.request.Request(RELAY + path, data=data, headers=headers, method=method)
            with urllib.request.urlopen(req, timeout=20) as res:
                return json.load(res)
        except urllib.error.HTTPError as err:
            if err.code < 500 or wait is None:
                raise  # 400: bad or expired code. 401: the user disconnected you.
        except OSError:  # timeout or dropped connection
            if wait is None:
                raise
        time.sleep(wait)

token = call("POST", "/pair/exchange", {"code": "${PAIR_CODE_EXAMPLE}"})["token"]  # once; save it

inbox = call("GET", "/inbox", token=token)
for item in inbox["items"]:
    print(item["transcription"])  # handle it
if inbox["items"]:
    call("POST", "/inbox/ack", {"ids": [i["id"] for i in inbox["items"]]}, token=token)`;

const API_EXAMPLE = `POST /pair/exchange
{"code": "${PAIR_CODE_EXAMPLE}"}
→ {"token": "rmba_…"}

GET /inbox
Authorization: Bearer rmba_…
→ {"items": [{"id": 41, "recording_id": "6F1C…", "created_at": "2026-11-01T19:00:00Z",
              "duration": 8.2, "transcription": "Remind me to book the dentist."}],
   "has_more": false}

POST /inbox/ack
Authorization: Bearer rmba_…
{"ids": [41]}
→ {"deleted": 1}`;

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
                <li>Talk to your watch. Your agent picks up each one and gets to work.</li>
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
                Three JSON calls. A pull returns up to 50 items, oldest first. Acking deletes them; if{" "}
                <InlineCode>has_more</InlineCode> is true, pull again. Anything never acked is deleted after{" "}
                {RETENTION}. Every path is relative to <InlineCode>{RELAY_URL}</InlineCode>.
              </p>
              <CodeBlock>{API_EXAMPLE}</CodeBlock>
            </section>

            <section className="space-y-4">
              <SectionHeader id="requests">Making requests</SectionHeader>
              <ul className="list-disc space-y-2 pl-5">
                <li>
                  <strong className="font-medium text-stone-900">Send a User-Agent.</strong> Any name works, like{" "}
                  <InlineCode>my-agent/1.0</InlineCode>. Python&rsquo;s built-in <InlineCode>urllib</InlineCode> sends
                  one that the network edge blocks with a 403 (<InlineCode>error code: 1010</InlineCode>). curl,
                  requests, httpx, and fetch are fine as they are.
                </li>
                <li>
                  <strong className="font-medium text-stone-900">Retry the network, not the answer.</strong> Retry
                  timeouts, dropped connections, and 5xx errors after 2, 5, then 15 seconds. Every call is safe to
                  retry: sending the same code again within {PAIR_CODE_TTL} returns the same token, a pull only reads,
                  and acking twice does nothing.
                </li>
                <li>
                  <strong className="font-medium text-stone-900">Read the error.</strong> Errors are JSON with a
                  plain <InlineCode>error</InlineCode> message. A 400 on the exchange means the code is wrong or
                  expired, so ask for a new one. A 401 means the user disconnected you.
                </li>
              </ul>
              <CodeBlock filename="curl">{CURL_EXAMPLE}</CodeBlock>
              <CodeBlock filename="Python (standard library)">{PYTHON_EXAMPLE}</CodeBlock>
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
