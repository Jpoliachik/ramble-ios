// Inboxes as accounts: creation, free notes, the unlock and its binding,
// revoked purchases, usage monitoring and suspension, transcription settings and the
// watch token. See specs/purchase.md and specs/relay-api.md "Phone setup and purchase".

import { AppleVerifyError } from './apple.js';
import { address, authenticate, limit } from './auth.js';
import { DAY, fail, json, logId, randomHex, randomToken, readJSON, sha256Hex, unavailable, utcMonth } from './http.js';
import { alert } from './ops.js';

export const FREE_NOTES = 25;
export const HEAVY_USE_SECONDS = 100 * 3600;
// Inboxes one purchase may ever be bound to, unless the operator raised its
// inbox_cap by hand (proxy/README.md "Operations").
export const MAX_INBOXES_PER_PURCHASE = 10;
export const MAX_VOCABULARY = 900;
const DEFAULT_UNLOCK_PRODUCT = 'dev.goodloop.ramble.unlock';
const DEFAULT_PREMIUM_PRODUCT = 'dev.goodloop.ramble.premium.monthly2';

// --- Account state -------------------------------------------------------------

/** The inbox with its purchase, and whether it may transcribe. Null if gone. */
export async function loadAccount(ctx, inboxId) {
  const row = await ctx.db
    .prepare(
      `SELECT i.id, i.free_notes_used, i.purchase_id, i.language, i.remove_filler_words,
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

export function accountView(account) {
  return {
    unlocked: account.unlocked,
    free_notes_total: FREE_NOTES,
    free_notes_remaining: account.freeRemaining,
  };
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

export async function getAccount(request, ctx) {
  const { cred, response } = await authenticate(request, ctx, ['inbox', 'watch']);
  if (response) return response;
  return json(accountView(await loadAccount(ctx, cred.inboxId)));
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

  const secret = `rmbi_${randomToken(32)}`;
  await ctx.db
    .prepare('INSERT INTO inboxes (id, secret_hash, created_at, usage_id) VALUES (?, ?, ?, ?)')
    .bind(`inb_${randomToken(12)}`, await sha256Hex(secret), ctx.now, randomHex(8))
    .run();
  return json({ inbox_secret: secret }, 201);
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
 * Returns { proof: { id, kind, environment } } or { response }.
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
      return { proof: { id: `unlock:${tx.originalTransactionId}`, kind: 'unlock', environment: tx.environment } };
    }
    if (tx.productId === (env.PREMIUM_PRODUCT_ID || DEFAULT_PREMIUM_PRODUCT)) {
      // Early subscriber: the old subscription was only ever sold before
      // Ramble became free, so any real record of it counts, lapsed or not.
      if (tx.environment === 'Production') {
        return { proof: { id: `sub:${tx.originalTransactionId}`, kind: 'subscriber', environment: 'Production' } };
      }
      return invalid();
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
 * Binds a verified purchase to an inbox, within its inbox cap (10 unless the
 * operator raised it). Bindings are never released, so the cap counts every
 * inbox the purchase was ever bound to. Returns null on success (or when
 * nothing needed changing), else the refusal response.
 */
export async function bindPurchase(ctx, inboxId, proof) {
  const existing = await ctx.db.prepare('SELECT revoked_at FROM purchases WHERE id = ?').bind(proof.id).first();
  if (existing?.revoked_at != null) return fail(403, 'This purchase was refunded or revoked.', 'invalid_transaction');

  const account = await loadAccount(ctx, inboxId);
  if (account.purchase_id === proof.id) return null;
  // Already unlocked by another record: nothing to change.
  if (account.unlocked) return null;

  // Sandbox (TestFlight, App Review) unlocks like a real purchase; it is kept
  // out of revenue counts by its environment.
  const [, bound] = await ctx.db.batch([
    ctx.db
      .prepare('INSERT OR IGNORE INTO purchases (id, kind, environment, created_at) VALUES (?, ?, ?, ?)')
      .bind(proof.id, proof.kind, proof.environment, ctx.now),
    // Conditional, so two inboxes binding at once can't both take the last spot.
    ctx.db
      .prepare(
        `UPDATE inboxes SET purchase_id = ? WHERE id = ? AND
           (SELECT COUNT(*) FROM inboxes WHERE purchase_id = ? AND id != ?) <
           COALESCE((SELECT inbox_cap FROM purchases WHERE id = ?), ?)`,
      )
      .bind(proof.id, inboxId, proof.id, inboxId, proof.id, MAX_INBOXES_PER_PURCHASE),
  ]);
  if (bound.meta.changes === 0) {
    return fail(403, 'This purchase has reached its limit of iPhones.', 'too_many_inboxes');
  }
  console.log(`[account] bound ${proof.kind} (${proof.environment}) inbox=${await logId(inboxId)}`);
  return null;
}

export async function postEntitlement(request, ctx) {
  const { cred, response } = await authenticate(request, ctx, ['inbox']);
  if (response) return response;

  const verified = await verifyProof(ctx, await readJSON(request));
  if (verified.response) return verified.response;
  const refused = await bindPurchase(ctx, cred.inboxId, verified.proof);
  if (refused) return refused;
  return json(accountView(await loadAccount(ctx, cred.inboxId)));
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
