# Ramble Admin

Justin's private dashboard: installs, active users, notes, the funnel, purchases, reliability and app builds, read straight from the relay's D1 database. Behavior is in [`specs/admin.md`](../specs/admin.md).

- **URL:** https://ramble-admin.jpoliachik.workers.dev
- **JSON for agents:** `GET /api/overview` (same numbers as the page), `GET /api/whoami`
- **Deploys:** from `main` via `.github/workflows/deploy-admin.yml` when `admin/**` changes, after its tests pass

## How sign-in works

Two locks, both required:

1. **Cloudflare Access** sits in front of the Worker's hostname. A browser gets Cloudflare's sign-in page (a one-time code sent to Justin's email). An agent skips the page by sending a **service token** as two headers. Nobody else gets a request through, and the Worker never sees a password.
2. **The Worker checks Access's signed JWT** (`Cf-Access-Jwt-Assertion`) on every request: signature against the team's public keys, issuer, audience (this app's AUD tag), expiry. No valid JWT, no data, even if Access were switched off by mistake. Until both settings below exist it answers 503 to everything.

## Setup (once, in the Cloudflare dashboard)

The first deploy happens when this folder lands on `main`. Then:

1. **Turn on Access.** Workers & Pages → `ramble-admin` → Settings → Domains & Routes → `workers.dev` → **Enable Cloudflare Access**. If Cloudflare asks to set up Zero Trust first, pick a team name and the **Free** plan. Then **Manage Cloudflare Access** and make sure the policy allows only your email (`Include → Emails`).
2. **Copy two values.** In Zero Trust → Access controls → Applications → the `ramble-admin` app: copy the **Application Audience (AUD) Tag**. In Zero Trust → Settings, note your **team domain** (`<team>.cloudflareaccess.com`).
3. **Give them to the Worker.** Workers & Pages → `ramble-admin` → Settings → Variables and Secrets → add two **Secrets** (secrets survive deploys): `ACCESS_TEAM_DOMAIN` = the team domain, `ACCESS_AUD` = the AUD tag.
4. **Open the URL.** You get Cloudflare's sign-in page, enter the code from your email, and land on the dashboard.

### Letting an agent in (Muse)

1. Zero Trust → Access controls → Service credentials → **Create Service Token**, name it after the agent (e.g. `Muse`), pick a duration. Copy the **Client ID** and **Client Secret** now: the secret is shown once.
2. Open the `ramble-admin` application's policies and **add a policy** with Action **Service Auth**, Include → **Service Token** → `Muse`. (An Allow policy would send the agent to the login page; it has to be Service Auth.)
3. Give the agent the URL and the two headers:

```bash
curl -s https://ramble-admin.jpoliachik.workers.dev/api/overview \
  -H "CF-Access-Client-Id: <client id>" \
  -H "CF-Access-Client-Secret: <client secret>"
```

One token per agent. To cut an agent off, revoke its token; your own sign-in is untouched.

## Adding an admin tool (the pattern)

Everything operator-only goes here, never into the relay (`proxy/`), which stays the public API for apps and agents.

- **One Worker, one Access app.** New pages and endpoints are routes in this Worker (`src/index.js`), so they are behind the same Access policy and the same JWT check automatically. Don't add a route that skips `authorize`.
- **Read-only by default.** Today the Worker only runs SELECTs. A tool that changes data (suspend a user, revoke a purchase) should be a `POST` with its own confirmation step, written to an audit table with who did it (the JWT's email or service token name), and added to `specs/admin.md` first.
- **No one's words.** Counts and labels only: never a transcript, agent copy, vocabulary word, credential or note ID. `test/metrics.test.js` checks the SQL for those columns; extend it when you add queries.
- **Every page has JSON.** If a person can see it, an agent can fetch it under `/api/...`.
- **Tests run without Cloudflare.** `npm test` signs real RS256 JWTs with a throwaway key and runs the queries against the relay's real schema (`proxy/migrations` via `proxy/test/d1.js`).

## Development

```bash
cd admin
npm test
```

There is no local dev server with a sign-in bypass on purpose: any bypass is one a misconfigured production could honor. Preview a page change with the tests, or render it from a test with seeded rows.
