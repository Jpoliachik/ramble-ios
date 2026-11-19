// MCP Events (specs/connector.md "Events"): webhook delivery from the draft
// MCP Events extension, as ChatGPT implements it
// (developers.openai.com/plugins/build/mcp-events). A connector subscribes to
// "note_received" through /mcp; when its connection gets a new copy, the
// relay POSTs a Standard Webhooks-signed event to the callback URL. Polling
// and streaming from the draft are not offered. Kept in one file so a change
// in the draft is a change here.

import { countLimit } from './auth.js';
import { base64ToBytes, arrayBufferToBase64 } from './crypto.js';
import { baseURL, randomToken, sha256Hex } from './http.js';
import { isPublicHttpsURL, openHeaders, sealHeaders } from './relay.js';

export const EVENT_NAME = 'note_received';
const DAY_MS = 24 * 60 * 60 * 1000;
// Long on purpose: weeks can pass between notes, and a lapsed subscription
// would silently stop push. The client refreshes before refreshBefore.
export const DEFAULT_TTL_MS = 30 * DAY_MS;
export const MAX_TTL_MS = 365 * DAY_MS;
export const MIN_TTL_MS = 60 * 1000;
export const MAX_SUBSCRIPTIONS = 10;
// A callback that has failed every delivery for this long is dropped, so a
// dead or re-registered domain stops getting events.
export const FAILING_DROP_MS = 7 * DAY_MS;
// After a refresh with a new secret, events are signed with both for this long.
export const ROTATION_WINDOW_MS = 60 * 60 * 1000;
// 3 tries fit in the ~30 s a Worker gets after its response: 5 + 1 + 5 + 3 + 5.
export const EVENT_TIMEOUT_MS = 5000;
export const DEFAULT_RETRY_MS = [1000, 3000];
const PARALLEL_SENDS = 4;
const MAX_VERIFY_BODY = 4096;
// JSON-RPC error ChatGPT uses when the callback can't be verified.
export const CALLBACK_ERROR = -32015;

export const EVENTS = [
  {
    name: EVENT_NAME,
    title: 'Note received',
    description:
      'Fires when a new Ramble voice note is ready for this connection. The event carries the note id, not its text: call get_note with the id for the transcript, and mark_handled once it has been dealt with.',
    delivery: ['webhook'],
    inputSchema: { type: 'object', properties: {}, additionalProperties: false },
    payloadSchema: {
      type: 'object',
      properties: {
        id: { type: 'string', description: 'The note id, for get_note and mark_handled.' },
        recorded_at: { type: 'string', description: "When it was recorded, in the device's local time with its offset." },
        duration_seconds: { type: 'number' },
      },
      required: ['id', 'recorded_at', 'duration_seconds'],
    },
  },
];

class RpcError extends Error {
  constructor(code, message, data) {
    super(message);
    this.code = code;
    this.data = data;
  }
}

/** events/list, events/subscribe or events/unsubscribe: a JSON-RPC result, or {error}. */
export async function handleEventsMethod(method, params, connection, ctx) {
  try {
    if (method === 'events/list') return { result: { events: EVENTS } };
    if (method === 'events/subscribe') return { result: await subscribe(params, connection, ctx) };
    return { result: await unsubscribe(params, connection, ctx) };
  } catch (err) {
    if (err instanceof RpcError) return { error: { code: err.code, message: err.message, ...(err.data ? { data: err.data } : {}) } };
    throw err;
  }
}

const invalid = (message) => new RpcError(-32602, message);

function readTarget(params, ctx, { withSecret }) {
  if (!params || typeof params !== 'object' || Array.isArray(params)) throw invalid('Send {"name", "arguments", "delivery"}');
  if (params.name !== EVENT_NAME) throw invalid(`Unknown event: ${String(params.name)}. Ramble offers "${EVENT_NAME}".`);
  const args = params.arguments ?? {};
  if (typeof args !== 'object' || Array.isArray(args) || Object.keys(args).length > 0) {
    throw invalid(`"${EVENT_NAME}" takes no arguments`);
  }
  const delivery = params.delivery;
  // Unsubscribe may leave out the mode; subscribe must say webhook.
  if (!delivery || typeof delivery !== 'object' || (delivery.mode !== 'webhook' && (withSecret || delivery.mode !== undefined))) {
    throw invalid('Only "webhook" delivery is supported');
  }
  if (!callbackOK(delivery.url, ctx)) throw invalid('"delivery.url" must be a public https:// URL with a hostname, on port 443');
  const url = new URL(delivery.url).href;
  if (!withSecret) return { url };
  if (!signingKey(delivery.secret)) throw invalid('"delivery.secret" must be "whsec_" and base64 of 24–64 bytes');
  return { url, secret: delivery.secret };
}

function callbackOK(raw, ctx) {
  if (typeof raw !== 'string' || !isPublicHttpsURL(raw, new URL(baseURL(ctx)).origin)) return false;
  const url = new URL(raw);
  return url.port === '' && url.hostname.replace(/\.$/, '') !== new URL(baseURL(ctx)).hostname;
}

/** The raw HMAC key from a whsec_ secret, or null if it isn't one. */
export function signingKey(secret) {
  if (typeof secret !== 'string' || !/^whsec_[A-Za-z0-9+/]+={0,2}$/.test(secret)) return null;
  try {
    const bytes = base64ToBytes(secret.slice('whsec_'.length));
    return bytes.length >= 24 && bytes.length <= 64 ? bytes : null;
  } catch {
    return null;
  }
}

/** Same connection, event, URL and (empty) arguments: same subscription. */
const subscriptionId = async (connection, url) => `sub_${(await sha256Hex(`${connection.id}\n${EVENT_NAME}\n${url}\n{}`)).slice(0, 32)}`;

const LIVE = '(expires_at IS NULL OR expires_at > ?)';

async function subscribe(params, connection, ctx) {
  const { url, secret } = readTarget(params, ctx, { withSecret: true });
  const ttl = grantedTTL(params.ttlMs);
  const id = await subscriptionId(connection, url);
  // Before anything leaves the relay: without the key nothing can be stored.
  const sealed = await sealHeaders({ secret }, ctx.env);

  const existing = await ctx.db
    .prepare(`SELECT secret FROM event_subscriptions WHERE id = ? AND ${LIVE}`)
    .bind(id, ctx.now)
    .first();
  if (existing) {
    // A refresh. A new secret keeps the old one for the rotation window.
    const old = (await openHeaders(existing.secret, ctx.env)).secret;
    if (old && old !== secret) {
      await ctx.db
        .prepare('UPDATE event_subscriptions SET prev_secret = secret, rotated_at = ? WHERE id = ?')
        .bind(ctx.now, id)
        .run();
    }
  } else {
    const limited = await countLimit(ctx, 'events_subscribe', connection.id);
    if (!limited.ok) throw new RpcError(-32000, 'Too many new subscriptions. Try again later.');
    await verifyCallback(id, url, secret, ctx);
    // Full: the least recently refreshed gives way, so forgotten chats never block a new one.
    await ctx.db
      .prepare(
        `DELETE FROM event_subscriptions WHERE id IN
           (SELECT id FROM event_subscriptions WHERE connection_id = ? AND id != ?
             ORDER BY ${LIVE} DESC, refreshed_at DESC, id LIMIT -1 OFFSET ?)`,
      )
      .bind(connection.id, id, ctx.now, MAX_SUBSCRIPTIONS - 1)
      .run();
  }

  const expiresAt = ttl === null ? null : ctx.now + ttl;
  // Only while the connection still exists: a disconnect during verification wins.
  const saved = await ctx.db
    .prepare(
      `INSERT INTO event_subscriptions (id, connection_id, name, url, secret, created_at, refreshed_at, expires_at)
       SELECT ?, ?, ?, ?, ?, ?, ?, ? WHERE EXISTS (SELECT 1 FROM connections WHERE id = ?)
       ON CONFLICT (id) DO UPDATE SET secret = excluded.secret, refreshed_at = excluded.refreshed_at,
         expires_at = excluded.expires_at`,
    )
    .bind(id, connection.id, EVENT_NAME, url, sealed, ctx.now, ctx.now, expiresAt, connection.id)
    .run();
  if (saved.meta.changes === 0) throw new RpcError(-32000, 'This connection was disconnected in the Ramble app.');
  // No replay: events missed while unsubscribed are still waiting in list_new_notes.
  return { id, refreshBefore: expiresAt === null ? null : new Date(expiresAt).toISOString(), cursor: null, truncated: false };
}

/** Milliseconds, or null for a subscription that never expires (what the client asked with ttlMs: null). */
function grantedTTL(asked) {
  if (asked === undefined) return DEFAULT_TTL_MS;
  if (asked === null) return null;
  if (typeof asked !== 'number' || !Number.isFinite(asked) || asked <= 0) throw invalid('"ttlMs" must be a positive number of milliseconds or null');
  return Math.min(Math.max(asked, MIN_TTL_MS), MAX_TTL_MS);
}

async function unsubscribe(params, connection, ctx) {
  const { url } = readTarget(params, ctx, { withSecret: false });
  await ctx.db
    .prepare('DELETE FROM event_subscriptions WHERE id = ? AND connection_id = ?')
    .bind(await subscriptionId(connection, url), connection.id)
    .run();
  return {};
}

// --- Sending -------------------------------------------------------------------

async function sign(secrets, msgId, timestamp, body) {
  const data = new TextEncoder().encode(`${msgId}.${timestamp}.${body}`);
  const sigs = [];
  for (const secret of secrets) {
    const key = await crypto.subtle.importKey('raw', signingKey(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
    sigs.push(`v1,${arrayBufferToBase64(await crypto.subtle.sign('HMAC', key, data))}`);
  }
  return sigs.join(' ');
}

/** The first `max` bytes of a response body as text; the rest is never read. */
async function readCapped(res, max) {
  if (!res.body) return '';
  const reader = res.body.getReader();
  const chunks = [];
  let size = 0;
  while (size <= max) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value);
    size += value.byteLength;
  }
  reader.cancel().catch(() => {});
  if (size > max) return '';
  const all = new Uint8Array(size);
  let at = 0;
  for (const c of chunks) {
    all.set(c, at);
    at += c.byteLength;
  }
  return new TextDecoder().decode(all);
}

/**
 * One signed POST. Returns {status, text, timedOut}; status 0 if nothing
 * answered. Never follows redirects. Reads the body only when asked to.
 */
async function post(ctx, { url, secrets, subscriptionId: subId, msgId, body, read = false }) {
  const timestamp = String(Math.floor(ctx.clock() / 1000));
  try {
    const res = await ctx.fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'Ramble-Relay/1 (+https://ramble.watch/docs)',
        'webhook-id': msgId,
        'webhook-timestamp': timestamp,
        'webhook-signature': await sign(secrets, msgId, timestamp, body),
        'X-MCP-Subscription-Id': subId,
      },
      body,
      redirect: 'manual',
      signal: AbortSignal.timeout(EVENT_TIMEOUT_MS),
    });
    const ok = res.status >= 200 && res.status < 300;
    const text = read && ok ? await readCapped(res, MAX_VERIFY_BODY) : '';
    if (!read || !ok) res.body?.cancel().catch(() => {});
    return { status: res.status, text };
  } catch (err) {
    return { status: 0, text: '', timedOut: err?.name === 'TimeoutError' };
  }
}

function sameString(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function failureReason(res) {
  if (res.timedOut) return 'timeout';
  if (res.status === 0) return 'connection_refused';
  if (res.status >= 500) return 'http_5xx';
  if (res.status >= 300) return 'http_4xx';
  return 'challenge_failed';
}

/** Before a new subscription is stored, the callback must echo a challenge. */
async function verifyCallback(subId, url, secret, ctx) {
  const challenge = randomToken(24);
  const res = await post(ctx, {
    url,
    secrets: [secret],
    subscriptionId: subId,
    msgId: `msg_verification_${randomToken(12)}`,
    body: JSON.stringify({ type: 'verification', challenge }),
    read: true,
  });
  let echoed = null;
  try {
    echoed = JSON.parse(res.text).challenge;
  } catch {
    // Not JSON: fails below.
  }
  if (res.status >= 200 && res.status < 300 && sameString(echoed, challenge)) return;
  throw new RpcError(CALLBACK_ERROR, 'The callback URL did not answer the verification challenge', { reason: failureReason(res) });
}

/**
 * A new copy reached these connections: one event to each live subscription,
 * a few at a time. A lost event costs only speed: the note still waits in
 * list_new_notes.
 */
export async function sendNoteEvents(ctx, connectionIds, item) {
  if (connectionIds.length === 0) return;
  const { results: subs } = await ctx.db
    .prepare(
      `SELECT id, url, secret, prev_secret, rotated_at, failing_since FROM event_subscriptions
        WHERE connection_id IN (${connectionIds.map(() => '?').join(', ')}) AND ${LIVE}`,
    )
    .bind(...connectionIds, ctx.now)
    .all();
  const queue = [...subs];
  const worker = async () => {
    while (queue.length) await sendOne(ctx, queue.shift(), item);
  };
  await Promise.all(Array.from({ length: Math.min(PARALLEL_SENDS, queue.length) }, worker));
}

// Not worth another try: the answer won't change. 408 and 429 are worth one.
const isFinal = (status) => (status >= 200 && status < 300) || (status >= 300 && status < 500 && status !== 408 && status !== 429);

/**
 * Up to three tries, same event id, fresh signature each time. Carries no
 * transcript text. After a week of nothing but failures, the subscription is
 * dropped.
 */
async function sendOne(ctx, sub, item) {
  const { secret } = await openHeaders(sub.secret, ctx.env);
  if (!signingKey(secret)) return;
  const secrets = [secret];
  if (sub.prev_secret && sub.rotated_at != null && ctx.now - sub.rotated_at < ROTATION_WINDOW_MS) {
    const prev = (await openHeaders(sub.prev_secret, ctx.env)).secret;
    if (signingKey(prev)) secrets.push(prev);
  }
  const eventId = `evt_${(await sha256Hex(`${sub.id}\n${item.recordingId}`)).slice(0, 32)}`;
  const body = JSON.stringify({
    eventId,
    name: EVENT_NAME,
    timestamp: new Date(item.receivedAt ?? ctx.now).toISOString(),
    data: { id: item.recordingId, recorded_at: item.recordedAt, duration_seconds: item.duration },
    cursor: null,
  });
  let status = 0;
  const waits = ctx.eventRetryMs ?? DEFAULT_RETRY_MS;
  for (let attempt = 0; attempt <= waits.length; attempt++) {
    if (attempt > 0) await new Promise((r) => setTimeout(r, waits[attempt - 1]));
    ({ status } = await post(ctx, { url: sub.url, secrets, subscriptionId: sub.id, msgId: eventId, body }));
    if (isFinal(status)) break;
  }
  const ok = status >= 200 && status < 300;
  try {
    if (!ok && sub.failing_since != null && ctx.now - sub.failing_since >= FAILING_DROP_MS) {
      await ctx.db.prepare('DELETE FROM event_subscriptions WHERE id = ?').bind(sub.id).run();
      return;
    }
    await ctx.db
      .prepare(
        `UPDATE event_subscriptions SET delivered_at = ?, last_status = ?,
           failing_since = CASE WHEN ? THEN NULL ELSE COALESCE(failing_since, ?) END
         WHERE id = ?`,
      )
      .bind(ctx.now, status, ok ? 1 : 0, ctx.now, sub.id)
      .run();
  } catch {
    // Best effort: the status is for debugging and the failure clock.
  }
}

/** Cron: expired subscriptions, and any whose connection is gone, are deleted. */
export async function purgeSubscriptions(db, now) {
  const [expired, orphaned] = await db.batch([
    db.prepare('DELETE FROM event_subscriptions WHERE expires_at <= ?').bind(now),
    db.prepare('DELETE FROM event_subscriptions WHERE connection_id NOT IN (SELECT id FROM connections)'),
  ]);
  return expired.meta.changes + orphaned.meta.changes;
}
