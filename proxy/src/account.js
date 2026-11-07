// Inboxes as accounts: creation, free notes, the unlock and its binding,
// refunds, usage monitoring and suspension, transcription settings and the
// watch token. See specs/purchase.md and specs/relay-api.md "Phone setup and purchase".

import { AppleVerifyError } from './apple.js';
import { address, authenticate, limit } from './auth.js';
import {
  DAY,
  fail,
  json,
  logId,
  randomToken,
  readJSON,
  sha256Hex,
  unavailable,
  utcDayStart,
  utcMonth,
} from './http.js';
import { FREE_TIER_DAILY_SECONDS, alert, freeSecondsToday } from './ops.js';

export const FREE_NOTES = 25;
export const HEAVY_USE_SECONDS = 100 * 3600;
export const INBOX_DAILY_CAP = 2000;
export const MAX_INBOXES_PER_PURCHASE = 5;
export const BINDING_ACTIVE_MS = 90 * DAY;
export const MAX_VOCABULARY = 900;
const DEFAULT_UNLOCK_PRODUCT = 'dev.goodloop.ramble.unlock';
const DEFAULT_PREMIUM_PRODUCT = 'dev.goodloop.ramble.premium.monthly2';

// --- Account state -------------------------------------------------------------

/** The inbox with its purchase, and whether it may transcribe. Null if gone. */
export async function loadAccount(ctx, inboxId) {
  const row = await ctx.db
    .prepare(
      `SELECT i.id, i.account_token, i.free_notes_used, i.purchase_id, i.language, i.remove_filler_words,
              i.vocabulary, p.kind AS purchase_kind, p.revoked_at,
              (i.suspended != 0 OR COALESCE(p.suspended, 0) != 0) AS suspended
         FROM inboxes i LEFT JOIN purchases p ON p.id = i.purchase_id WHERE i.id = ?`,
    )
    .bind(inboxId)
    .first();
  if (!row) return null;
  const unlocked = row.purchase_kind != null && row.revoked_at == null;
  return {
    ...row,
    suspended: !!row.suspended,
    unlocked,
    activePurchase: unlocked ? row.purchase_id : null,
    freeRemaining: Math.max(0, FREE_NOTES - row.free_notes_used),
  };
}

export function accountView(account, { includeToken }) {
  const view = {
    unlocked: account.unlocked,
    free_notes_total: FREE_NOTES,
    free_notes_remaining: account.freeRemaining,
  };
  if (includeToken) view.account_token = account.account_token;
  return view;
}

// --- Usage monitoring and suspension -------------------------------------------

/** Set by the operator by hand; see proxy/README.md "Operations". */
export const suspendedResponse = () =>
  fail(403, 'Uploads from this Ramble setup are paused. Contact support@ramble.watch.', 'suspended');

/**
 * Adds transcribed audio to the user's tally for this UTC month: the purchase
 * an inbox is unlocked by, else the inbox. Alerts the operator once, when the
 * tally first passes HEAVY_USE_SECONDS. Monitoring only; never throws.
 */
export async function recordUsage(ctx, userId, seconds) {
  if (!userId || !(seconds > 0)) return;
  try {
    const month = utcMonth(ctx.now);
    const row = await ctx.db
      .prepare(
        `INSERT INTO usage (user_id, month, seconds) VALUES (?, ?, ?)
           ON CONFLICT (user_id, month) DO UPDATE SET seconds = seconds + excluded.seconds
         RETURNING seconds`,
      )
      .bind(userId, month, seconds)
      .first();
    const total = row?.seconds ?? 0;
    if (total >= HEAVY_USE_SECONDS && total - seconds < HEAVY_USE_SECONDS) {
      await alert(
        ctx,
        `heavy_use:${userId}:${month}`,
        `${userId} passed ${HEAVY_USE_SECONDS / 3600} hours of audio in ${month} (UTC). Nothing is refused; suspend by hand if needed (proxy/README.md).`,
      );
    }
  } catch (err) {
    console.error(`[account] usage not recorded: ${String(err?.message).slice(0, 200)}`);
  }
}

/** The tally key for an inbox's notes. Never throws. */
export async function usageUser(ctx, inboxId) {
  try {
    const account = await loadAccount(ctx, inboxId);
    return account ? (account.activePurchase ?? account.id) : null;
  } catch {
    return null;
  }
}

/** Inboxes made before accounts existed get their token on first read. */
async function ensureAccountToken(ctx, account) {
  if (account.account_token) return account;
  const token = crypto.randomUUID();
  await ctx.db
    .prepare('UPDATE inboxes SET account_token = ? WHERE id = ? AND account_token IS NULL')
    .bind(token, account.id)
    .run();
  return loadAccount(ctx, account.id);
}

export async function getAccount(request, ctx) {
  const { cred, response } = await authenticate(request, ctx, ['inbox', 'watch']);
  if (response) return response;
  const limited = await limit(ctx, ['reads', cred.hash]);
  if (limited) return limited;
  let account = await loadAccount(ctx, cred.inboxId);
  if (cred.kind === 'inbox') account = await ensureAccountToken(ctx, account);
  return json(accountView(account, { includeToken: cred.kind === 'inbox' }));
}

// --- Creating an inbox -------------------------------------------------------

// The developer bypass works only on a local relay (`wrangler dev`), where
// .dev.vars sets ENVIRONMENT=development and DEV_BYPASS_KEY. Production sets
// neither, so it never takes the bypass.
export async function localBypassAllowed(env, presented) {
  const key = env?.DEV_BYPASS_KEY;
  if (env?.ENVIRONMENT !== 'development' || typeof key !== 'string' || key.length < 16) return false;
  return (await sha256Hex(presented)) === (await sha256Hex(key));
}

export async function createInbox(request, ctx) {
  const limited = await limit(ctx, ['inboxes_addr', address(request, ctx)]);
  if (limited) return limited;

  const body = await request.arrayBuffer();
  const bypass = request.headers.get('X-Dev-Bypass');
  if (bypass !== null) {
    // Local development only (simulators can't use App Attest).
    if (!(await localBypassAllowed(ctx.env, bypass))) return fail(403, 'App attestation failed');
  } else {
    const keyId = request.headers.get('X-App-Attest-Key-Id');
    const assertion = request.headers.get('X-App-Attest');
    if (!keyId || !assertion) return fail(403, 'App attestation required');
    const result = await ctx.verifyAssertion(keyId, assertion, body, ctx.env);
    if (result?.unavailable) return unavailable();
    if (!result?.valid) {
      console.error(`[account] inbox attestation failed key=${await logId(keyId)}`);
      return fail(403, 'App attestation failed');
    }
    const keyLimited = await limit(ctx, ['inboxes_key', keyId]);
    if (keyLimited) return keyLimited;
  }

  // A buyer on a new iPhone skips the cap and the breaker. A proof that
  // doesn't verify or bind just means a normal, capped inbox.
  let proof = null;
  let parsed = null;
  try {
    parsed = body.byteLength ? JSON.parse(new TextDecoder().decode(body)) : null;
  } catch {
    parsed = null;
  }
  if (parsed && (parsed.signed_transaction || parsed.app_transaction)) {
    const verified = await verifyProof(ctx, parsed);
    if (verified.proof) proof = verified.proof;
  }

  if (!proof && (await freeTierBreakerTripped(ctx))) return unavailable();

  const id = `inb_${randomToken(12)}`;
  const secret = `rmbi_${randomToken(32)}`;
  const accountToken = crypto.randomUUID();
  const insert = await ctx.db
    .prepare(
      `INSERT INTO inboxes (id, secret_hash, created_at, account_token)
       SELECT ?, ?, ?, ? WHERE ? OR (SELECT COUNT(*) FROM inboxes WHERE created_at >= ?) < ?`,
    )
    .bind(id, await sha256Hex(secret), ctx.now, accountToken, proof ? 1 : 0, utcDayStart(ctx.now), INBOX_DAILY_CAP)
    .run();
  if (insert.meta.changes === 0) return inboxCapReached(ctx);
  if (proof) {
    // Only a proof that binds skips the cap and the breaker. Unbound, this is
    // a normal free inbox: it stays only if a capped request would be let in.
    let refused;
    try {
      refused = await bindPurchase(ctx, id, proof);
    } catch (err) {
      console.error(`[account] new inbox bind failed: ${String(err?.message).slice(0, 200)}`);
      refused = { status: 503 };
    }
    if (refused) {
      console.log(`[account] new inbox proof not bound: ${refused.status}`);
      const others = await ctx.db
        .prepare('SELECT COUNT(*) AS n FROM inboxes WHERE created_at >= ? AND id != ?')
        .bind(utcDayStart(ctx.now), id)
        .first();
      const capped = others.n >= INBOX_DAILY_CAP;
      if (capped || (await freeTierBreakerTripped(ctx))) {
        await ctx.db.prepare('DELETE FROM inboxes WHERE id = ? AND purchase_id IS NULL').bind(id).run();
        return capped ? inboxCapReached(ctx) : unavailable();
      }
    }
  }
  return json({ inbox_secret: secret, account_token: accountToken }, 201);
}

async function inboxCapReached(ctx) {
  await alert(ctx, 'inbox_cap', `${INBOX_DAILY_CAP} inboxes were created today: new inboxes are refused until tomorrow (UTC).`);
  return unavailable();
}

async function freeTierBreakerTripped(ctx) {
  if ((await freeSecondsToday(ctx)) < FREE_TIER_DAILY_SECONDS) return false;
  await alert(ctx, 'free_tier_breaker', 'Free inboxes reached 200 hours of audio today: new inboxes are refused until tomorrow (UTC).');
  return true;
}

// --- Purchases -----------------------------------------------------------------

const invalid = (error = "This purchase record couldn't be verified.") => ({
  response: fail(403, error, 'invalid_transaction'),
});

function appleFailure(err) {
  if (err instanceof AppleVerifyError && err.reason !== 'unavailable') return invalid();
  console.error(`[account] Apple record check unavailable: ${err?.message}`);
  return { response: unavailable() };
}

/**
 * Checks a purchase or early-buyer proof and says which purchase it is.
 * Returns { proof: { id, kind, environment, appAccountToken } } or { response }.
 */
export async function verifyProof(ctx, body) {
  const env = ctx.env;
  if (typeof body?.signed_transaction === 'string') {
    let tx;
    try {
      tx = await ctx.apple.verifySignedTransaction(body.signed_transaction, env, ctx.appleDeps);
    } catch (err) {
      return appleFailure(err);
    }
    if (tx.revocationDate) return invalid('This purchase was refunded or revoked.');
    if (tx.inAppOwnershipType === 'FAMILY_SHARED') return invalid("Family-shared purchases don't unlock Ramble.");
    if (tx.environment !== 'Production' && tx.environment !== 'Sandbox') return invalid();
    if (!tx.originalTransactionId) return invalid();

    if (tx.productId === (env.UNLOCK_PRODUCT_ID || DEFAULT_UNLOCK_PRODUCT)) {
      return {
        proof: {
          id: `unlock:${tx.originalTransactionId}`,
          kind: 'unlock',
          environment: tx.environment,
          appAccountToken: tx.appAccountToken ?? null,
        },
      };
    }
    if (tx.productId === (env.PREMIUM_PRODUCT_ID || DEFAULT_PREMIUM_PRODUCT)) {
      // Early subscriber: active when the first free build was released.
      const releasedAt = Date.parse(env.FREE_RELEASE_AT ?? '');
      if (
        tx.environment === 'Production' &&
        Number.isFinite(releasedAt) &&
        Number(tx.originalPurchaseDate) < releasedAt &&
        Number(tx.expiresDate) > releasedAt
      ) {
        return { proof: { id: `sub:${tx.originalTransactionId}`, kind: 'subscriber', environment: 'Production' } };
      }
      return invalid('This subscription was not active when Ramble became free to download.');
    }
    return invalid();
  }

  if (typeof body?.app_transaction === 'string') {
    let tx;
    try {
      tx = await ctx.apple.verifyAppTransaction(body.app_transaction, env, ctx.appleDeps);
    } catch (err) {
      return appleFailure(err);
    }
    // Sandbox app records always say "1.0": never early-buyer proof.
    const environment = tx.receiptType ?? tx.environment;
    const version = String(tx.originalApplicationVersion ?? '');
    const firstFree = String(env.FIRST_FREE_BUILD ?? '');
    if (
      environment === 'Production' &&
      tx.appTransactionId &&
      /^\d+$/.test(version) &&
      /^\d+$/.test(firstFree) &&
      Number(version) < Number(firstFree)
    ) {
      return { proof: { id: `app:${tx.appTransactionId}`, kind: 'early_buyer', environment: 'Production' } };
    }
    return invalid('This download is not from before Ramble became free.');
  }

  return { response: fail(400, 'Send {"signed_transaction": "<JWS>"} or {"app_transaction": "<JWS>"}.') };
}

/**
 * Binds a verified purchase to an inbox, within the 5-inbox cap. Returns null
 * on success (or when nothing needed changing), else the refusal response.
 */
export async function bindPurchase(ctx, inboxId, proof) {
  const existing = await ctx.db.prepare('SELECT revoked_at FROM purchases WHERE id = ?').bind(proof.id).first();
  if (existing?.revoked_at != null) return fail(403, 'This purchase was refunded or revoked.', 'invalid_transaction');

  const account = await loadAccount(ctx, inboxId);
  if (account.purchase_id === proof.id) return null;
  // Already unlocked by another record: nothing to change.
  if (account.unlocked) return null;

  // A first-time unlock must be bought from this inbox; a restore may not be.
  if (proof.kind === 'unlock' && !existing) {
    const token = String(proof.appAccountToken ?? '').toLowerCase();
    if (!token || token !== String(account.account_token ?? '').toLowerCase()) {
      return fail(403, 'This purchase was made for another Ramble inbox.', 'wrong_account');
    }
  }

  // Sandbox (TestFlight, App Review) unlocks like a real purchase; it is kept
  // out of revenue counts by its environment.
  const since = ctx.now - BINDING_ACTIVE_MS;
  const [, bound] = await ctx.db.batch([
    ctx.db
      .prepare('INSERT OR IGNORE INTO purchases (id, kind, environment, created_at) VALUES (?, ?, ?, ?)')
      .bind(proof.id, proof.kind, proof.environment, ctx.now),
    // Conditional, so two inboxes binding at once can't both take the 5th spot.
    ctx.db
      .prepare(
        `UPDATE inboxes SET purchase_id = ?, bound_at = ? WHERE id = ? AND
           (SELECT COUNT(*) FROM inboxes WHERE purchase_id = ? AND id != ? AND (bound_at > ? OR last_upload_at > ?)) < ?`,
      )
      .bind(proof.id, ctx.now, inboxId, proof.id, inboxId, since, since, MAX_INBOXES_PER_PURCHASE),
  ]);
  if (bound.meta.changes === 0) {
    return fail(403, `This purchase is in use on ${MAX_INBOXES_PER_PURCHASE} iPhones.`, 'too_many_inboxes');
  }
  console.log(`[account] bound ${proof.kind} (${proof.environment}) inbox=${await logId(inboxId)}`);
  return null;
}

export async function postEntitlement(request, ctx) {
  const { cred, response } = await authenticate(request, ctx, ['inbox']);
  if (response) return response;
  const limited = await limit(ctx, ['entitlement', cred.inboxId]);
  if (limited) return limited;

  const verified = await verifyProof(ctx, await readJSON(request));
  if (verified.response) return verified.response;
  const refused = await bindPurchase(ctx, cred.inboxId, verified.proof);
  if (refused) return refused;
  const account = await ensureAccountToken(ctx, await loadAccount(ctx, cred.inboxId));
  return json(accountView(account, { includeToken: true }));
}

/** App Store Server Notifications v2: refunds and revocations lock inboxes. */
export async function appStoreNotification(request, ctx) {
  const body = await readJSON(request);
  if (typeof body?.signedPayload !== 'string') return fail(400, 'Expected an App Store server notification.');
  let note;
  try {
    note = await ctx.apple.verifyNotification(body.signedPayload, ctx.env, ctx.appleDeps);
  } catch (err) {
    if (err instanceof AppleVerifyError && err.reason !== 'unavailable') {
      return fail(400, "This notification couldn't be verified.");
    }
    return unavailable();
  }
  if (note.environment !== (ctx.env.APPSTORE_ENVIRONMENT || 'Production')) {
    return fail(400, 'This notification is for another App Store environment.');
  }

  const tx = note.transaction;
  if ((note.notificationType === 'REFUND' || note.notificationType === 'REVOKE') && tx?.originalTransactionId) {
    const unlock = tx.productId === (ctx.env.UNLOCK_PRODUCT_ID || DEFAULT_UNLOCK_PRODUCT);
    const id = `${unlock ? 'unlock' : 'sub'}:${tx.originalTransactionId}`;
    // Insert when unknown too, so the record is refused if it's sent later.
    await ctx.db
      .prepare(
        `INSERT INTO purchases (id, kind, environment, revoked_at, created_at) VALUES (?, ?, ?, ?, ?)
           ON CONFLICT (id) DO UPDATE SET revoked_at = COALESCE(purchases.revoked_at, excluded.revoked_at)`,
      )
      .bind(id, unlock ? 'unlock' : 'subscriber', note.environment, ctx.now, ctx.now)
      .run();
    console.log(`[account] ${note.notificationType} for purchase ${await logId(id)}`);
  }
  return json({ status: 'ok' });
}

// --- Settings ----------------------------------------------------------------------

function settingsView(row) {
  return {
    language: row.language ?? null,
    remove_filler_words: !!row.remove_filler_words,
    vocabulary: row.vocabulary ?? '',
  };
}

export async function getSettings(request, ctx) {
  const { cred, response } = await authenticate(request, ctx, ['inbox']);
  if (response) return response;
  return json(settingsView(await loadAccount(ctx, cred.inboxId)));
}

export async function putSettings(request, ctx) {
  const { cred, response } = await authenticate(request, ctx, ['inbox']);
  if (response) return response;
  const limited = await limit(ctx, ['settings', cred.inboxId]);
  if (limited) return limited;

  const body = await readJSON(request);
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    return fail(400, 'Send {"language": "es" | null, "remove_filler_words": false, "vocabulary": "..."}.');
  }
  const language = body.language ?? null;
  if (language !== null && (typeof language !== 'string' || !/^[a-z]{2,3}$/i.test(language))) {
    return fail(400, '"language" must be an ISO 639-1 code (or ISO 639-3 where none exists), or null.');
  }
  const removeFillerWords = body.remove_filler_words ?? false;
  if (typeof removeFillerWords !== 'boolean') return fail(400, '"remove_filler_words" must be true or false.');
  const vocabulary = body.vocabulary ?? '';
  if (typeof vocabulary !== 'string' || vocabulary.length > MAX_VOCABULARY) {
    return fail(400, `"vocabulary" must be text of up to ${MAX_VOCABULARY} characters.`);
  }

  await ctx.db
    .prepare('UPDATE inboxes SET language = ?, remove_filler_words = ?, vocabulary = ? WHERE id = ?')
    .bind(language?.toLowerCase() ?? null, removeFillerWords ? 1 : 0, vocabulary, cred.inboxId)
    .run();
  return json(settingsView(await loadAccount(ctx, cred.inboxId)));
}

// --- Watch token -------------------------------------------------------------------

export async function postWatchToken(request, ctx) {
  const { cred, response } = await authenticate(request, ctx, ['inbox']);
  if (response) return response;
  const limited = await limit(ctx, ['watch_token', cred.inboxId]);
  if (limited) return limited;

  const replaces = (await readJSON(request))?.replaces;
  const replacedHash = typeof replaces === 'string' && replaces.startsWith('rmbw_') ? await sha256Hex(replaces) : '';
  const token = `rmbw_${randomToken(32)}`;
  // A replaced token is simply revoked.
  await ctx.db.batch([
    ctx.db.prepare('DELETE FROM watch_tokens WHERE inbox_id = ? OR token_hash = ?').bind(cred.inboxId, replacedHash),
    ctx.db
      .prepare('INSERT INTO watch_tokens (token_hash, inbox_id, created_at) VALUES (?, ?, ?)')
      .bind(await sha256Hex(token), cred.inboxId, ctx.now),
  ]);
  return json({ watch_token: token }, 201);
}

export async function deleteWatchToken(request, ctx) {
  const { cred, response } = await authenticate(request, ctx, ['inbox']);
  if (response) return response;
  const result = await ctx.db
    .prepare('DELETE FROM watch_tokens WHERE inbox_id = ?')
    .bind(cred.inboxId)
    .run();
  return json({ revoked: result.meta.changes });
}
