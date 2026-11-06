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

// The block agents actually follow. Keep it agnostic: every rule here has to
// work for any agent stack. Platform specifics go under "Platform notes".
const AGENT_INSTRUCTIONS = `Ramble connection
Relay: ${RELAY_URL}

1. Pair. When I give you a code like ${PAIR_CODE_EXAMPLE}, POST {"code": "<the code>"}
   to /pair/exchange and save the returned "token". If that request times out or
   drops, send the same code again: for ${PAIR_CODE_TTL} it returns the same token.
   A 400 means the code is wrong or expired, so ask me for a new one.
   The token is a password to my transcripts: anyone who has it can read and
   delete them. Store it the way your platform stores secrets, and keep it out
   of chat, memory, and logs.

2. Separate checking from acting. Most checks find nothing, so the cost of this
   connection is the empty checks, not the transcripts. Make the check as cheap
   as you can: a small script, hook, or scheduled HTTP fetch that runs without
   you, calls GET /inbox with "Authorization: Bearer <token>", and wakes you
   only when "items" is not empty. Every 1 to 5 minutes is fine for a check
   like that. Only if your platform can't run anything without you, schedule
   your own run instead. Hourly or even daily is fine (nothing expires for
   ${RETENTION}), and tell me how often you'll check.

3. Act. For each item, do what I asked in "transcription". "created_at" is when
   I started recording, in my local time, which can be hours before you see it
   (my phone may have been offline). Read relative times like "in an hour" or
   "tomorrow" from created_at. If that time has already passed, treat it as
   overdue and tell me.

4. Ack. POST {"ids": [...]} to /inbox/ack with the ids you handled. That deletes
   them. Anything not acked comes back on the next check. If "has_more" is
   true, check again right away.

5. Only 401 means stop. 401 means I disconnected you: stop checking and tell
   me. Anything else (403, 5xx, a timeout) is temporary: retry after 2, 5, then
   15 seconds, and keep your schedule.

Send a User-Agent header on every request (any name, like my-agent/1.0).
Full reference and examples: ${SITE_URL}/docs`;

const API_EXAMPLE = `POST /pair/exchange
{"code": "${PAIR_CODE_EXAMPLE}"}
→ 201 {"token": "rmba_…"}          (a retry with the same code: 200, same token)

GET /inbox
Authorization: Bearer rmba_…
→ {"items": [{"id": 41, "recording_id": "6F1C…", "created_at": "2026-11-01T14:00:00-05:00",
              "received_at": "2026-11-01T19:00:04.120Z", "duration": 8.2,
              "transcription": "Remind me to book the dentist."}],
   "has_more": false}

POST /inbox/ack
Authorization: Bearer rmba_…
{"ids": [41]}
→ {"deleted": 1}`;

const WATCHER_EXAMPLE = `#!/bin/sh
# Run every few minutes from cron, a hook, or any scheduler. Prints the inbox
# only when there's something for the agent; wire that output to whatever
# wakes your agent. Silent otherwise, so empty checks cost nothing.
RELAY=${RELAY_URL}

out=$(curl -sS --retry 3 -A "ramble-watcher/1.0" -w '\\n%{http_code}' \\
  "$RELAY/inbox" -H "Authorization: Bearer $RAMBLE_TOKEN") || exit 0
status=$(printf '%s\\n' "$out" | tail -n 1)
body=$(printf '%s\\n' "$out" | sed '$d')

case "$status" in
  200) case "$body" in *'"items":[]'*) exit 0 ;; esac ;;  # nothing waiting
  401) ;;                                                 # disconnected: tell the agent
  *) exit 0 ;;                                            # temporary: next run retries
esac
echo "$body"`;

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

const ERRORS: [string, string, string][] = [
  ["401", "You were disconnected, or the token is wrong", "Stop checking and tell the user. This is the only status that means stop."],
  ["400 on /pair/exchange", "The code is wrong or expired", "Ask the user for a new code."],
  ["400 elsewhere", "The request is malformed", "Fix it. The error message says what's wrong."],
  ["403", "Filtered before it reached the relay", "Set a User-Agent or use another HTTP client, then retry. Not a token problem."],
  ["405", "Wrong HTTP method", "The error message names the right one."],
  ["5xx, timeout, dropped connection", "Temporary", "Retry after 2, 5, then 15 seconds. Keep your schedule."],
];

function SectionHeader({ id, children }: { id: string; children: React.ReactNode }) {
  return (
    <h2 id={id} className="scroll-mt-20 font-serif text-2xl font-semibold tracking-tight text-stone-900">
      {children}
    </h2>
  );
}

function Strong({ children }: { children: React.ReactNode }) {
  return <strong className="font-medium text-stone-900">{children}</strong>;
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
                  <InlineCode>{PAIR_CODE_EXAMPLE}</InlineCode>). It connects one agent and expires in {PAIR_CODE_TTL}.
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
              <SectionHeader id="checking">Checking cheaply</SectionHeader>
              <p>
                An empty inbox is the common case, so what this connection costs is mostly empty checks. The HTTP
                request is tiny. Waking a whole agent to make it is not. The cheap shape is a watcher that checks on
                its own and wakes the agent only when something is waiting:
              </p>
              <ul className="list-disc space-y-2 pl-5">
                <li>
                  <Strong>Best:</Strong> a script, hook, or scheduled fetch your platform runs without the model, like
                  the one below. Every 1 to 5 minutes is fine.
                </li>
                <li>
                  <Strong>Fallback:</Strong> if the agent can only run as itself on a schedule, check less often. Hourly
                  or even daily works, since nothing expires for {RETENTION}. Tell the user the interval.
                </li>
                <li>
                  <Strong>No polling at all:</Strong> if your agent has an always-on HTTPS URL that wakes it, a{" "}
                  <Link href="/docs/webhooks" className="text-brand-text underline-offset-2 hover:underline">
                    webhook
                  </Link>{" "}
                  may suit it better. See{" "}
                  <a href="#relay-or-webhook" className="text-brand-text underline-offset-2 hover:underline">
                    relay or webhook
                  </a>
                  .
                </li>
              </ul>
              <CodeBlock filename="watcher.sh">{WATCHER_EXAMPLE}</CodeBlock>
            </section>

            <section className="space-y-4">
              <SectionHeader id="api">API</SectionHeader>
              <p>
                Three JSON calls. Every path is relative to <InlineCode>{RELAY_URL}</InlineCode>. A check returns up
                to 50 items, oldest first.
              </p>
              <CodeBlock>{API_EXAMPLE}</CodeBlock>
              <ul className="list-disc space-y-2 pl-5">
                <li>
                  <Strong>Timestamps.</Strong> <InlineCode>created_at</InlineCode> is when the user started recording,
                  taken from the watch or phone clock, with the phone&rsquo;s UTC offset (so{" "}
                  <InlineCode>-05:00</InlineCode> means the user is 5 hours behind UTC).{" "}
                  <InlineCode>received_at</InlineCode> (UTC) is when the relay got it. The two can be hours apart if the
                  phone was offline. Read relative times like &ldquo;tomorrow&rdquo; from{" "}
                  <InlineCode>created_at</InlineCode> in that offset, and if the moment has passed, treat it as overdue
                  rather than moving it. <InlineCode>duration</InlineCode> is in seconds.
                </li>
                <li>
                  <Strong>Acks.</Strong> Up to 500 ids per call. Acking an id that&rsquo;s already gone, or isn&rsquo;t
                  yours, does nothing; <InlineCode>deleted</InlineCode> counts what was actually removed. Anything never
                  acked comes back on every check and is deleted after {RETENTION}.
                </li>
                <li>
                  <Strong>Pairing retries.</Strong> A code makes one connection. If the exchange times out, send the
                  same code again: until the agent first checks the inbox, or {PAIR_CODE_TTL} pass, it returns the
                  same token, so a lost response never costs the user a new code.
                </li>
              </ul>
            </section>

            <section className="space-y-4">
              <SectionHeader id="connections">Tokens and connections</SectionHeader>
              <ul className="list-disc space-y-2 pl-5">
                <li>The token doesn&rsquo;t expire. It works until the user taps Disconnect in Ramble.</li>
                <li>
                  Each code makes its own connection, so several agents can be connected at once. Each gets its own
                  copy of every transcript, and acking deletes only your copy. Pairing a new agent leaves the others
                  alone.
                </li>
                <li>
                  The user sees every connected agent in Settings → Connect agent, with when it last checked and how many
                  transcripts are waiting for it.
                </li>
                <li>Ramble sends only recordings made while at least one agent is connected.</li>
              </ul>
            </section>

            <section className="space-y-4">
              <SectionHeader id="requests">Making requests</SectionHeader>
              <p>
                <Strong>Send a User-Agent.</Strong> Any name works, like <InlineCode>my-agent/1.0</InlineCode>. Some
                HTTP stacks get filtered before they reach the relay; Python&rsquo;s built-in{" "}
                <InlineCode>urllib</InlineCode> is one, and gets a 403 (<InlineCode>error code: 1010</InlineCode>).
                curl, requests, httpx, and fetch are fine as they are. If you see 403s or dropped connections with a
                valid token, set a User-Agent or switch clients.
              </p>
              <div className="overflow-x-auto">
                <table className="w-full text-left text-sm">
                  <thead>
                    <tr className="border-b border-stone-200 text-stone-900">
                      <th className="py-2 pr-3 font-medium">Status</th>
                      <th className="py-2 pr-3 font-medium">Means</th>
                      <th className="py-2 font-medium">Do</th>
                    </tr>
                  </thead>
                  <tbody>
                    {ERRORS.map(([status, means, todo]) => (
                      <tr key={status} className="border-b border-stone-100 align-top">
                        <td className="py-2 pr-3 whitespace-nowrap font-mono text-xs text-stone-900">{status}</td>
                        <td className="py-2 pr-3">{means}</td>
                        <td className="py-2">{todo}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              <p>
                Errors are JSON: <InlineCode>{`{"error": "..."}`}</InlineCode>. Every call is safe to retry. There is no
                rate limit today, but please keep checks to once a minute or slower.
              </p>
              <CodeBlock filename="curl">{CURL_EXAMPLE}</CodeBlock>
              <CodeBlock filename="Python (standard library)">{PYTHON_EXAMPLE}</CodeBlock>
            </section>

            <section className="space-y-4">
              <SectionHeader id="relay-or-webhook">Relay or webhook</SectionHeader>
              <p>Ramble can deliver to an agent two ways. Use either or both.</p>
              <ul className="list-disc space-y-2 pl-5">
                <li>
                  <Strong>Relay (this page).</Strong> The agent pulls. If the phone is offline, Ramble keeps retrying
                  the upload until it gets through (hourly once it&rsquo;s been a while), and the relay then holds each transcript for up to {RETENTION} until the
                  agent acks it. If the agent is down for a while, nothing is lost. The agent needs to make outbound
                  HTTPS calls on a schedule.
                </li>
                <li>
                  <Strong>
                    <Link href="/docs/webhooks" className="text-brand-text underline-offset-2 hover:underline">
                      Webhook
                    </Link>
                    .
                  </Strong>{" "}
                  The phone POSTs each transcript to your HTTPS URL as soon as it&rsquo;s transcribed. Nothing is stored
                  in between and there&rsquo;s no polling. If the URL is down, Ramble retries 3 times (after 5 seconds,
                  30 seconds, and 2 minutes), then marks it failed, and the user can resend it from the recording. Best
                  when the agent has an always-on URL that wakes it.
                </li>
              </ul>
            </section>

            <section className="space-y-4">
              <SectionHeader id="timing">Delivery timing</SectionHeader>
              <p>
                A note goes watch → iPhone → transcription → relay. With the iPhone nearby, even locked in a pocket,
                that usually takes seconds to a minute. Apple&rsquo;s limits can make it longer:
              </p>
              <ul className="list-disc space-y-2 pl-5">
                <li>
                  <Strong>iPhone out of range or off.</Strong> Notes wait on the watch and send once the two are back
                  together.
                </li>
                <li>
                  <Strong>Longer notes.</Strong> Watch-to-iPhone file transfers are{" "}
                  <a
                    href="https://developer.apple.com/documentation/watchconnectivity/wcsession/transferfile(_:metadata:)"
                    className="text-brand-text underline-offset-2 hover:underline"
                  >
                    paced by the system
                  </a>{" "}
                  for power, so they can take minutes, occasionally more.
                </li>
                <li>
                  <Strong>iPhone just restarted.</Strong> Nothing moves until it&rsquo;s{" "}
                  <a
                    href="https://developer.apple.com/documentation/watchconnectivity/wcsession/iosdeviceneedsunlockafterrebootforreachability"
                    className="text-brand-text underline-offset-2 hover:underline"
                  >
                    unlocked once
                  </a>
                  .
                </li>
                <li>
                  <Strong>Limited background time.</Strong> iOS gives Ramble{" "}
                  <a
                    href="https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app"
                    className="text-brand-text underline-offset-2 hover:underline"
                  >
                    short, system-scheduled windows
                  </a>{" "}
                  to transcribe and upload, so a note can wait for the next one or for the app to open.
                </li>
              </ul>
              <p>
                So notes can arrive late and out of order. Go by <InlineCode>created_at</InlineCode>, not arrival time,
                and don&rsquo;t read an empty inbox as &ldquo;nothing was recorded&rdquo;. A late note isn&rsquo;t lost: the
                watch keeps each one until the iPhone confirms it has it.
              </p>
            </section>

            <section className="space-y-4">
              <SectionHeader id="platforms">Platform notes</SectionHeader>
              <p>Everything above works for any agent. These are the specifics we know about.</p>
              <ul className="list-disc space-y-2 pl-5">
                <li>
                  <Strong>Muse.</Strong> Use a hook: a small script watches the inbox and wakes the agent when something
                  arrives. Avoid a scheduled agent run every few minutes.
                </li>
                <li>
                  <Strong>Agents in a sandbox with a network allowlist.</Strong> Add{" "}
                  <InlineCode>{new URL(RELAY_URL).host}</InlineCode> to the allowed hosts, or every request fails
                  before it leaves the sandbox.
                </li>
              </ul>
              <p>
                What the relay stores and for how long is in the{" "}
                <Link href="/privacy" className="text-brand-text underline-offset-2 hover:underline">
                  privacy policy
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
