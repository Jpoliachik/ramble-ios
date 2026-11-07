// Ramble relay: one Cloudflare Worker for the phone, the watch, agents and
// Apple. The HTTP contract is specs/relay-api.md. Modules:
//
//   index.js     routing, the request context, the cron
//   auth.js      credentials and rate limits
//   account.js   inboxes, free notes, purchases, refunds, settings, watch token
//   notes.js     audio uploads, the transcription pipeline, the device copy
//   relay.js     pairing, agent copies, pull/ack, delivery status, hooks
//   legacy.js    old builds' POST /transcribe
//   ops.js       operator alerts and the daily summary
//   transcribe.js, audio.js, apple.js, attest.js, ratelimit.js, crypto.js
//
// `deps` lets tests supply a clock and fakes for everything outside D1.

import {
  appStoreNotification,
  createInbox,
  deleteWatchToken,
  getAccount,
  getSettings,
  postEntitlement,
  postWatchToken,
  purgeWatchTokens,
  putSettings,
} from './account.js';
import { verifyAppTransaction, verifyNotification, verifySignedTransaction } from './apple.js';
import { handleAttest, handleAttestChallenge, verifyAssertionForRequest } from './attest.js';
import { measureDurationSeconds } from './audio.js';
import { address, countLimit, limit, peekLimit } from './auth.js';
import { DOCS_URL, fail, gone, json, rateLimited, unavailable } from './http.js';
import { legacyOpen, legacyTranscribe } from './legacy.js';
import { BODY_TIMEOUT_MS, INLINE_WAIT_MS, ackNotes, getNote, listNotes, purgeNotes, sweep, sweepCopies, uploadNote } from './notes.js';
import { checkAlerts, maybeDailySummary, purgeEvents } from './ops.js';
import { clientAddress, hit, peek, purgeRateLimits } from './ratelimit.js';
import {
  ack,
  createPairCode,
  disconnect,
  exchangePairCode,
  getAgent,
  inboxStatus,
  legacyTextUpload,
  listConnections,
  pull,
  purgeExpired,
  purgeInbox,
  resolvesPublic,
  updateAgent,
} from './relay.js';
import { transcribeNote } from './transcribe.js';

export function makeContext(request, env, deps = {}) {
  const clock = deps.clock ?? (deps.now != null ? () => deps.now : () => Date.now());
  return {
    env,
    db: env.DB,
    now: deps.now ?? clock(),
    clock,
    origin: request ? new URL(request.url).origin : null,
    verifyAssertion: deps.verifyAssertion ?? verifyAssertionForRequest,
    handleAttest: deps.handleAttest ?? ((req, e) => handleAttest(req, e)),
    // Work that outlives the response: transcription, hook pings.
    waitUntil: deps.waitUntil ?? ((promise) => promise),
    fetch: deps.fetch ?? ((...args) => fetch(...args)),
    rateLimit: deps.rateLimit ?? { hit, peek },
    clientAddress: deps.clientAddress ?? clientAddress,
    apple: deps.apple ?? { verifySignedTransaction, verifyAppTransaction, verifyNotification },
    appleDeps: deps.appleDeps ?? {},
    transcribe: deps.transcribe ?? transcribeNote,
    transcribeDeps: deps.transcribeDeps ?? {},
    measureDuration: deps.measureDuration ?? measureDurationSeconds,
    resolvesPublic: deps.resolvesPublic ?? resolvesPublic,
    inlineWaitMs: deps.inlineWaitMs ?? INLINE_WAIT_MS,
    bodyTimeoutMs: deps.bodyTimeoutMs ?? BODY_TIMEOUT_MS,
  };
}

// --- Routes ------------------------------------------------------------------

const root = () =>
  json({ service: 'Ramble relay', docs: 'https://ramble.watch/docs', llms: 'https://ramble.watch/llms-full.txt' });

async function attestChallenge(request, ctx) {
  const limited = await limit(ctx, ['attest_challenge', address(request, ctx)]);
  if (limited) return limited;
  return json(await handleAttestChallenge(request, ctx.env));
}

/** 5 key registrations a day per address; failed tries don't use them up. */
async function attestRegister(request, ctx) {
  const addr = address(request, ctx);
  const room = await peekLimit(ctx, 'attest_register', addr);
  if (!room.ok) return rateLimited(room.retryAfter);
  const result = await ctx.handleAttest(request, ctx.env);
  if (result.error) return fail(result.status, result.error, result.reason ?? null);
  await countLimit(ctx, 'attest_register', addr);
  return json({ status: 'ok' });
}

const whileLegacy = (handler) => (request, ctx) => (legacyOpen(ctx) ? handler(request, ctx) : gone());

// [path or pattern, { METHOD: handler(request, ctx, param) }]
const ROUTES = [
  ['/', { GET: root }],
  ['/health', { GET: () => json({ status: 'ok' }) }],
  ['/attest/challenge', { POST: attestChallenge }],
  ['/attest', { POST: attestRegister }],
  ['/inboxes', { POST: createInbox }],
  ['/account', { GET: getAccount }],
  ['/entitlement', { POST: postEntitlement }],
  ['/appstore/notifications', { POST: appStoreNotification }],
  ['/settings', { GET: getSettings, PUT: putSettings }],
  ['/watch-token', { POST: postWatchToken, DELETE: deleteWatchToken }],
  ['/notes', { GET: listNotes }],
  ['/notes/ack', { POST: ackNotes }],
  [/^\/notes\/([^/]+)$/, { GET: (r, c, id) => getNote(r, id, c), PUT: (r, c, id) => uploadNote(r, id, c) }],
  ['/inbox', { GET: pull, POST: whileLegacy(legacyTextUpload), DELETE: purgeInbox }],
  ['/inbox/ack', { POST: ack }],
  ['/inbox/status', { POST: inboxStatus }],
  ['/pair/code', { POST: createPairCode }],
  ['/pair/exchange', { POST: exchangePairCode }],
  ['/connections', { GET: listConnections }],
  [/^\/connections\/([^/]+)$/, { DELETE: (r, c, id) => disconnect(r, id, c) }],
  ['/agent', { GET: getAgent, PATCH: updateAgent }],
  ['/transcribe', { POST: whileLegacy(legacyTranscribe) }],
  ['/analytics', { GET: () => gone() }],
];

const NO_DB = new Set(['/', '/health']);

function route(pathname) {
  for (const [path, methods] of ROUTES) {
    if (typeof path === 'string') {
      if (path === pathname) return { name: path, methods, param: null };
    } else {
      const m = pathname.match(path);
      if (m) return { name: path.source, methods, param: decodeURIComponent(m[1]) };
    }
  }
  return null;
}

export async function handleRequest(request, env, deps = {}) {
  const { pathname } = new URL(request.url);
  const match = route(pathname);
  if (!match) return fail(404, `Not found. Docs: ${DOCS_URL}`);
  const handler = match.methods[request.method];
  if (!handler) {
    const allowed = Object.keys(match.methods).join(' or ');
    return fail(405, `Wrong method for ${pathname}. Use ${allowed}. Docs: ${DOCS_URL}`, null, {}, { Allow: Object.keys(match.methods).join(', ') });
  }
  if (!env.DB && !NO_DB.has(match.name)) return unavailable();

  const ctx = makeContext(request, env, deps);
  try {
    return await handler(request, ctx, match.param);
  } catch (err) {
    // Can't check a credential, count or limit: accept nothing. Never log bodies.
    console.error(`[relay] ${request.method} ${match.name} failed: ${String(err?.message).slice(0, 200)}`);
    return unavailable();
  }
}

// --- Cron (every minute) -------------------------------------------------------------

export async function runScheduled(env, deps = {}) {
  if (!env.DB) return;
  const ctx = makeContext(null, env, deps);
  const steps = [
    ['sweep', () => sweep(ctx)],
    ['copies', () => sweepCopies(ctx)],
    ['entries', () => purgeExpired(env.DB, ctx.now)],
    ['notes', () => purgeNotes(ctx)],
    ['watch_tokens', () => purgeWatchTokens(ctx)],
    ['events', () => purgeEvents(ctx)],
    ['rate_limits', () => purgeRateLimits(env.DB, ctx.now)],
    ['alerts', () => checkAlerts(ctx)],
    ['summary', () => maybeDailySummary(ctx)],
  ];
  for (const [name, step] of steps) {
    try {
      await step();
    } catch (err) {
      console.error(`[cron] ${name} failed: ${String(err?.message).slice(0, 200)}`);
    }
  }
}

export default {
  async scheduled(_event, env, executionCtx) {
    const work = runScheduled(env, {
      waitUntil: executionCtx ? (promise) => executionCtx.waitUntil(promise) : undefined,
    });
    if (executionCtx) executionCtx.waitUntil(work);
    await work;
  },

  async fetch(request, env, executionCtx) {
    return handleRequest(request, env, {
      waitUntil: executionCtx ? (promise) => executionCtx.waitUntil(promise) : undefined,
    });
  },
};
