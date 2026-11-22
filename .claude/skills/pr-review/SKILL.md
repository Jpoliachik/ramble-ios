---
name: pr-review
description: Give a "safe to merge" verdict on a Ramble pull request or branch from a small panel of expert reviewers (deploy and ops, security, agent integrations, UX and copy, privacy and App Store), each run only when the diff touches its area. Run it whenever you open a PR, and when Justin asks "is this safe to merge?"
---

# Ramble PR review: is it safe to merge?

The goal is one answer Justin can act on: can he press merge now, and what will he notice afterwards. You are the lead reviewer. You gather the diff, send it to the experts it touches, check their findings, and write the one verdict.

## 1. Gather

- The diff against `main`: the PR's files (GitHub MCP `pull_request_read`), or `git fetch origin main` then `git diff origin/main...HEAD`.
- Mergeable state (conflicts) and checks. `CI passed` is the one required check. iOS and watch builds run on Xcode Cloud, not GitHub, and only when `Ramble/` changes, so green GitHub CI says nothing about the apps.
- What merging deploys, with no staging:
  - `proxy/**`: the relay Worker, after D1 migrations are applied (`deploy-proxy.yml`).
  - `admin/**`: the admin Worker.
  - `website/**`: Vercel deploys https://ramble.watch.
  - `Ramble/**`: Xcode Cloud builds TestFlight. Nothing reaches the App Store until Justin submits.

## 2. Pick the panel

Run an expert only when the diff touches its area. Docs-only or one-line changes need no panel: check them yourself against the lists below.

| Expert | Runs when the diff touches |
|---|---|
| Deploy and ops | `proxy/`, `admin/`, `.github/`, `wrangler.toml`, migrations |
| Security | auth, tokens, OAuth, App Attest, purchase verification, input handling, anything new on the public relay |
| Agent integrations | `/mcp`, OAuth, pairing, agent keys, hooks, webhooks, `proxy/RELAY.md`, `/docs`, `llms*.txt` |
| UX and copy | any screen, haptic or user-facing words (app, site, App Store text, agent docs) |
| Privacy and App Store | data collected, stored or sent, `PrivacyInfo.xcprivacy`, purchase, new targets or entitlements, App Store text |

Start the chosen experts in parallel with the Agent tool, one message, `subagent_type: general-purpose`. Give each: the PR number or branch, the diff (or how to get it), its own checklist below copied in full, and this brief: "Read only the files and specs your checklist names. Report at most three findings, each with severity (blocker, must-do-before-merge, or note), file:line, and the evidence. Say 'nothing in my area' if that's true. Don't edit files or comment on GitHub."

### Deploy and ops
- Migrations run on production D1 before the new Worker starts, and the old Worker keeps serving until then. They must be additive or safe for the old Worker. Flag `DROP`, `RENAME`, type changes, or rewrites of existing rows. Merged migrations are never edited. The admin Worker reads the same schema.
- Every new `env.X` read: what happens when it's unset (feature off, 503, crash), and must Justin run `npx wrangler secret put X` before or after merging. `proxy/README.md` lists it. Never `ENVIRONMENT` or `DEV_BYPASS_KEY` in production config.
- Installed phones and watches run older builds. `/inboxes`, `/notes`, `/account` and the watch token keep their request and response shapes, status codes and auth (`specs/relay-api.md`).
- `POST /transcribe` and text `POST /inbox` keep working until 2027-01-07 (`src/legacy.js`).
- Never stuck: a note still retries when Groq is down (`specs/transcription.md`), nothing new can strand a note, and a bad deploy can be undone by reverting the commit (migrations can't be, so they get extra care).
- New Telegram alerts have dedup or a threshold. Justin wants signal, not noise.

### Security
- Auth on every new or changed endpoint: inbox secret (`rmbi_`), watch token (`rmbw_`, upload only), agent key (`rmba_`). No endpoint reads another inbox's data. The dev bypass stays in its one check on `POST /inboxes`, unreachable in production.
- OAuth (`src/oauth.js`): redirect URI checks, PKCE, code reuse, token scope. Pairing codes stay one-time and rate limited.
- Purchases are still verified against Apple's root CA (`src/apple.js`). No client-supplied unlock is trusted.
- No secrets, transcripts or audio in logs, alerts, errors, `note_events` or the admin dashboard. Webhook and hook URLs can't be used to reach internal hosts.
- Rate limits cover anything new that costs money (Groq) or can be enumerated.

### Agent integrations
- Check against the current official docs, not memory, and cite them with dates: the MCP spec and authorization spec, and the connector guidance from Anthropic (Claude), OpenAI (ChatGPT) and others the change affects.
- Tool names `list_new_notes`, `get_note`, `mark_handled` and their annotations are a contract. A rename or annotation change changes what Claude, ChatGPT and Muse see, and may need re-review by the directories Ramble is listed in (`specs/connector.md`).
- Pairing still works for agents that use the plain HTTP API (`proxy/RELAY.md`), including clients with unusual user agents (Cloudflare can 403 some).
- Agent-facing docs (`proxy/RELAY.md`, website `/docs`, `website/public/llms*.txt`) match the code.

### UX and copy
- Against `docs/design.md`: one centered button and one bottom bar on the watch, icons over text, the design tokens, motion and haptics. The watch is the core product: polish every detail.
- Never stuck: every new state has a way forward the person can see, and recording works with no signal.
- Against `docs/brand.md`: never mention the 100-hour figure or any usage number. "Send", not "transcribe". "Your agent", not a list of agent brands. No "trial", "premium", "Subscribe" or price per month. No "open source", "on-device transcription" or "no servers". No promises that haven't shipped. Website copy is for new visitors: never refer to a previous version.

### Privacy and App Store
- A new kind of data collected or sent means `PrivacyInfo.xcprivacy` (phone and watch) and the App Store label in `docs/app-store.md` change together, and Justin updates the label in App Store Connect.
- Privacy wording matches `specs/delivery.md`. Audio is still deleted after transcription, transcripts after ack or 30 days.
- Purchase: product ID `dev.goodloop.ramble.unlock`, 25 free notes, restore, early buyers (`specs/purchase.md`). The relay's `UNLOCK_PRODUCT_ID` still matches.
- A new target or bundle ID needs its App ID registered by hand at developer.apple.com first, or Xcode Cloud fails.
- A deployment target change updates `MIN_IOS`/`MIN_WATCHOS` in `website/src/lib/site.ts` and `website/public/llms*.txt`.
- Anything App Review would reject: current App Review Guidelines, checked with a date.

## 3. Check it yourself

- Specs: any observable behavior change updates the right file in `specs/` in the same PR. A refactor leaves specs alone. If code and spec disagree in a way the PR didn't intend, name which one looks wrong and let Justin decide.
- Before you report a blocker or a must-do from an expert, open the file and confirm it. Drop what you can't confirm.

## 4. Answer

Lead with one of:
- **Safe to merge.**
- **Safe to merge once you** do X (set a secret, register an App ID, update the App Store label).
- **Not yet:** the blocker, in one sentence.

Then one sentence on what merging does (what deploys, and what isn't touched). Then at most five short bullets: only the risks that apply, what Justin will notice afterwards, and anything he has to do by hand. Don't list the experts or pad with checks that passed. End with which specs changed, or "No spec change" and why.

Example:

> Yes, PR 80 is safe to merge. It has no conflicts, CI is green and there's no database change. Merging deploys the relay and the site automatically, and the apps, pairing and legacy /transcribe aren't touched.
>
> - **Review path:** it stays off until you set REVIEW_CODE.
> - **If the code ever leaks:** someone could only see five sample notes, and changing the secret shuts them out.
> - **You'll notice:** Claude and ChatGPT ask before "Mark handled", because it's now flagged destructive.

Write in plain sentences, no jargon Justin would have to look up. Don't approve or merge the PR yourself, and don't comment on GitHub unless asked.
