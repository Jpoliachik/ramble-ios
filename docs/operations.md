# Relay operations

The operator runbook for the relay: usage stats, heavy users, suspending, refunds, inbox caps, and the first-deploy checklist. The heavy-use alert threshold is the `HEAVY_USE_HOURS` secret on both the relay and admin Workers; the figure itself is internal and is never written in this repo.

## Usage stats: where to look

The quickest view is the admin dashboard, https://ramble-admin.jpoliachik.workers.dev (`admin/README.md`). For anything it doesn't show, read them in the Cloudflare dashboard (**D1 → ramble-relay → Console**), or from an agent with Cloudflare D1 access (Claude threads use the Cloudflare connector; Muse uses its own Cloudflare connection). Query `note_events` and `inboxes` only, and never select `notes.transcript` or `entries.text`: those are people's words. Times are Unix milliseconds, days are UTC.

```sql
-- Signups (new installs) per day
SELECT date(created_at / 1000, 'unixepoch') AS day, COUNT(*) AS signups
FROM inboxes GROUP BY day ORDER BY day DESC LIMIT 30;

-- Daily active users (recorded at least one note that day)
SELECT date(recorded_at / 1000, 'unixepoch') AS day, COUNT(DISTINCT user_id) AS users, COUNT(*) AS notes
FROM note_events GROUP BY day ORDER BY day DESC LIMIT 30;

-- Weekly active users
SELECT strftime('%Y-W%W', recorded_at / 1000, 'unixepoch') AS week, COUNT(DISTINCT user_id) AS users, COUNT(*) AS notes
FROM note_events GROUP BY week ORDER BY week DESC LIMIT 12;

-- Notes per user, including installs that never recorded
SELECT COUNT(*) AS users, ROUND(AVG(n), 1) AS avg_notes, MAX(n) AS most
FROM (SELECT i.usage_id, COUNT(e.note_key) AS n FROM inboxes i
      LEFT JOIN note_events e ON e.user_id = i.usage_id GROUP BY i.usage_id);

-- How many users reach 10 notes, and how many days after install
WITH ranked AS (
  SELECT user_id, recorded_at, ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY recorded_at) AS n
  FROM note_events)
SELECT COUNT(*) AS users_at_10, ROUND(AVG((r.recorded_at - i.created_at) / 86400000.0), 1) AS avg_days
FROM ranked r JOIN inboxes i ON i.usage_id = r.user_id WHERE r.n = 10;

-- Note length, watch vs phone
SELECT source, COUNT(*) AS notes, ROUND(AVG(duration) / 60, 1) AS avg_min,
       SUM(duration > 1800) AS over_30_min
FROM note_events GROUP BY source;

-- Reliability: results, first-try share, wait from upload to final
SELECT result, COUNT(*) AS notes, SUM(attempts = 1) AS first_try,
       ROUND(AVG(finished_at - accepted_at) / 1000.0, 1) AS avg_wait_s
FROM note_events GROUP BY result;

-- Which app builds are in use
SELECT phone_app, watch_app, COUNT(*) AS inboxes FROM inboxes GROUP BY 1, 2 ORDER BY inboxes DESC;
```

## Operations: heavy users, suspending one, and revoking a refund

There is no usage limit, and the heavy-use threshold is internal: it is never shown to people (not in the app, the Terms or the listing) and lives only in the `HEAVY_USE_HOURS` secret. The relay keeps a monthly tally per user, where the user is the purchase an inbox is unlocked by (`unlock:…`, `sub:…`, `app:…`) or the inbox ID (`inb_…`) when it has none, and sends one Telegram alert the first time a user passes that threshold in a UTC month. Nothing is refused. The global backstop is a spend limit in the Groq console.

If one user needs stopping, suspend them by hand. Uploads (`PUT /notes/:id` and old builds' `POST /transcribe`) from a suspended inbox, or from any inbox bound to a suspended purchase, get `403` with `"reason": "suspended"`; the apps show "Couldn't send" and stop retrying. Notes already accepted still transcribe, and everyone else is unaffected. Each command is one line:

```bash
# Heaviest users this month (UTC)
npx wrangler d1 execute ramble-relay --remote --command "SELECT user_id, ROUND(seconds / 3600.0, 1) AS hours FROM usage WHERE month = strftime('%Y-%m', 'now') ORDER BY seconds DESC LIMIT 20"

# Inboxes bound to a purchase
npx wrangler d1 execute ramble-relay --remote --command "SELECT id, suspended, last_upload_at FROM inboxes WHERE purchase_id = 'unlock:2000000123456789'"

# Suspend a purchase (every inbox bound to it)
npx wrangler d1 execute ramble-relay --remote --command "UPDATE purchases SET suspended = 1 WHERE id = 'unlock:2000000123456789'"

# Suspend an old-build subscriber (POST /transcribe) whose sub:… ID may not be in purchases yet
npx wrangler d1 execute ramble-relay --remote --command "INSERT INTO purchases (id, kind, environment, created_at, suspended) VALUES ('sub:2000000123456789', 'subscriber', 'Production', 0, 1) ON CONFLICT (id) DO UPDATE SET suspended = 1"

# Suspend one inbox
npx wrangler d1 execute ramble-relay --remote --command "UPDATE inboxes SET suspended = 1 WHERE id = 'inb_abc123'"

# Unsuspend
npx wrangler d1 execute ramble-relay --remote --command "UPDATE purchases SET suspended = 0 WHERE id = 'unlock:2000000123456789'"
npx wrangler d1 execute ramble-relay --remote --command "UPDATE inboxes SET suspended = 0 WHERE id = 'inb_abc123'"

# Everyone suspended
npx wrangler d1 execute ramble-relay --remote --command "SELECT 'purchase' AS kind, id FROM purchases WHERE suspended = 1 UNION ALL SELECT 'inbox', id FROM inboxes WHERE suspended = 1"

# Revoke a refunded unlock (every inbox bound to it goes back to the free state, and the record is refused from then on)
npx wrangler d1 execute ramble-relay --remote --command "UPDATE purchases SET revoked_at = CAST(strftime('%s', 'now') AS INTEGER) * 1000 WHERE id = 'unlock:2000000123456789'"
```

The `UPDATE` reports `changes: 1` when it found the purchase. The old-build subscriber command adds a row only when the `sub:` ID isn't known yet; that row is dated 1970, so it never counts as a new unlock. Notes the apps marked "Couldn't send" while suspended don't upload again by themselves after an unsuspend; new notes do.

Refunds: the relay doesn't listen for Apple's refund notifications. A refunded purchase whose signed record Apple marks with a `revocationDate` is refused when it is sent again, but inboxes it already unlocked stay unlocked until you revoke it with the command above. Use the original transaction ID from App Store Connect or the refund report. Notes accepted before the revoke still transcribe.

## Operations: a purchase on more than 10 iPhones

One purchase unlocks at most 10 inboxes ever (each fresh start after a reinstall is a new inbox), and time frees no spot. The 11th gets `403` `too_many_inboxes`, and the app asks the person to contact support. To check and raise one purchase's cap (the person then taps "Restore Purchases"):

```bash
# How many inboxes it is bound to, and its cap (empty means 10)
npx wrangler d1 execute ramble-relay --remote --command "SELECT p.id, p.inbox_cap, COUNT(i.id) AS inboxes FROM purchases p LEFT JOIN inboxes i ON i.purchase_id = p.id WHERE p.id = 'unlock:2000000123456789' GROUP BY p.id"

# Raise its cap
npx wrangler d1 execute ramble-relay --remote --command "UPDATE purchases SET inbox_cap = 15 WHERE id = 'unlock:2000000123456789'"
```

## Before the first deploy of this version

Merging to `main` deploys the Worker and applies migrations (`.github/workflows/deploy-proxy.yml`), so do steps 1–4 first. Run the `npx wrangler` commands from `proxy/`.

1. **CI token.** The `CLOUDFLARE_API_TOKEN` GitHub secret needs, for the account: Workers Scripts Edit, Workers KV Storage Edit, D1 Edit, and now **Workers R2 Storage Edit** (My Profile → API Tokens → edit the token). Without R2 the deploy fails on the `AUDIO` binding.
2. **R2 bucket.** Create it private (the default) with a 1-day expiry rule as the backstop for failed deletes:
   ```bash
   npx wrangler r2 bucket create ramble-audio
   npx wrangler r2 bucket lifecycle add ramble-audio expire-1-day --expire-days 1
   ```
   Don't enable public access or an r2.dev URL. The binding is already in `wrangler.toml`.
3. **Secrets.** Each command prompts for the value:
   ```bash
   npx wrangler secret put GROQ_API_KEY          # console.groq.com → API Keys
   npx wrangler secret put HOOK_ENCRYPTION_KEY   # paste the output of: openssl rand -base64 32
   npx wrangler secret put TELEGRAM_BOT_TOKEN    # Telegram → @BotFather → /newbot → copy the token
   npx wrangler secret put TELEGRAM_CHAT_ID      # send your bot any message, then open https://api.telegram.org/bot<token>/getUpdates and copy result[0].message.chat.id
   ```
   Keep `HOOK_ENCRYPTION_KEY` stable: changing it makes stored hook headers unreadable. Only after this version is deployed (the Worker running before it still calls Deepgram and OpenAI), delete the ones no longer read: `npx wrangler secret delete NAME` for `DEEPGRAM_API_KEY`, `OPENAI_API_KEY`, `DEV_BYPASS_TOKEN` and `ANALYTICS_TOKEN`, if they exist (`npx wrangler secret list`).
4. **Groq spend limit.** On the paid Developer tier, set a monthly spend limit (about $50) in console.groq.com; it is the only global cost cap. The free tier never bills, so it needs none, but its rate limits cap throughput: past them Groq answers 429 and notes wait for a retry (the stuck-note alert fires after 30 minutes).
5. **App Store Connect.** Create the in-app purchase: type Non-Consumable, product ID `dev.goodloop.ramble.unlock`, price $14.99, Family Sharing **off** (shared purchases don't unlock). Add it to the app version you submit. Take `dev.goodloop.ramble.premium.monthly2` off sale at launch. Leave the App Store Server Notifications URL empty.
6. **`FIRST_FREE_BUILD`, at release.** Set it in `wrangler.toml` `[vars]` to the build number of the first free-notes build you ship (Xcode Cloud's build number for it), commit, and let it deploy. Downloads from a lower build are early buyers. Old builds' paths retire on their own on 2027-01-07; there is no `LEGACY_UNTIL` to set.
7. **`api.ramble.watch`.** Done: the zone is on Cloudflare and the host is a custom domain on the Worker; the website and agent docs use it, and the apps keep using the `workers.dev` host. Setup: [RELAY.md](RELAY.md) "Operator: the api.ramble.watch domain".
8. **Local relay** (any time): `cp .dev.vars.example .dev.vars`, put your Groq key in `GROQ_API_KEY`, keep `ENVIRONMENT=development` and `DEV_BYPASS_KEY` as they are, then `npx wrangler d1 migrations apply ramble-relay --local` and `npm run dev`.

