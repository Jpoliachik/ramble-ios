---
name: pr-review
description: Give a "safe to merge" verdict on a Ramble pull request or branch from a small panel of expert reviewers (deploy and ops, security, agent integrations, core values), each run only when the diff touches its area. Run it whenever you open a PR, and when Justin asks "is this safe to merge?"
---

# Ramble PR review: is it safe to merge?

The goal is one answer Justin can act on: can he press merge now, and what will he notice afterwards. You are the lead reviewer. You gather the diff, send it to the experts it touches, check what they find, and write the one verdict.

This skill says what each expert cares about, not what to check. The repo changes; the experts read the current code, specs and docs and work out the specifics themselves.

## 1. Gather

- The diff against `main`, whether it has conflicts, and its checks.
- What merging it sets in motion. Read `.github/workflows/` and CLAUDE.md for that rather than assuming: some areas deploy to production on merge with no staging, and the apps build elsewhere, so green GitHub checks may say nothing about them.

## 2. The panel

Pick the experts whose area the diff touches. A docs-only or tiny change needs no panel: review it yourself with the same questions.

Start the chosen experts in parallel with the Agent tool, in one message. Give each the PR or branch, its section below, and this brief: "Work out what matters for this diff from the current code, `specs/`, `docs/` and CLAUDE.md. Report at most three findings, each with severity (blocker, must-do-before-merge, or note), file:line, and evidence. Say 'nothing in my area' if that's true. Don't edit files or comment on GitHub."

**Deploy and ops.** Can this go to production safely the moment it merges, alongside the app builds already installed on people's devices? Think about what deploys and in what order, data and schema changes, configuration and secrets it needs, older clients and endpoints that must keep working, whether it can be rolled back, whether a note could ever get stuck, and anything Justin has to do by hand before or after.

**Security.** Could this let anyone read, change or cost something they shouldn't? Look at whatever the diff exposes or trusts: auth, tokens, sign-in flows, purchase checks, input, logs and outbound requests.

**Agent integrations.** Will agents and the platforms Ramble plugs into keep working, and does the change follow their current official guidance? Check the latest official docs and specs, not memory, and cite them with dates. Agent-facing docs must match the code.

**Core values.** Does the change keep Ramble true to what it stands for? Read the values fresh from `docs/brand.md` (the belief, the promises, what Ramble is not, the product principles, the copy rules) and `docs/design.md` (the philosophy). For each value the change touches, say whether it supports it or undercuts it, quoting the line it pulls against. This covers UX, user-facing words and privacy.

## 3. Check it yourself

- Specs: does any observable behavior change come with its spec update, as CLAUDE.md requires? If code and spec disagree in a way the PR didn't intend, name which one looks wrong and let Justin decide.
- Before you report an expert's blocker or must-do, open the file and confirm it. Drop what you can't confirm.

## 4. Answer

Lead with one of:
- **Safe to merge.**
- **Safe to merge once you** do X.
- **Not yet:** the blocker, in one sentence.

Then one sentence on what merging does (what deploys, and what isn't touched). Then at most five short bullets: only the risks that apply, what Justin will notice afterwards, and anything he has to do by hand. Don't list the experts or pad with checks that passed. End with which specs changed, or "No spec change" and why.

Example:

> Yes, PR 80 is safe to merge. It has no conflicts, CI is green and there's no database change. Merging deploys the relay and the site automatically, and the apps, pairing and legacy /transcribe aren't touched.
>
> - **Review path:** it stays off until you set REVIEW_CODE.
> - **If the code ever leaks:** someone could only see five sample notes, and changing the secret shuts them out.
> - **You'll notice:** Claude and ChatGPT ask before "Mark handled", because it's now flagged destructive.

Write in plain sentences, no jargon Justin would have to look up. Don't approve or merge the PR yourself, and don't comment on GitHub unless asked.
