// The review inbox (specs/connector.md "Review inbox"): how directory
// reviewers (Claude, ChatGPT, Gemini and others) sign in to the connector without
// the Ramble app. The operator sets a long review code as the Worker secret
// REVIEW_CODE. The sign-in page accepts it any number of times, and it only
// ever connects to one inbox, which holds sample notes and nothing else. No
// device ever uploads to it, so no real person's notes can be reached with it.

import { randomToken, sha256Hex } from './http.js';
import { MAX_AGENTS, normalizePairCode } from './relay.js';

export const REVIEW_INBOX_ID = 'review';
// Shorter codes are ignored, so a weak secret can't open the review inbox.
export const REVIEW_CODE_MIN_LENGTH = 16;

const HOUR = 60 * 60 * 1000;

// Fixed ids, so restocking puts back the same notes.
export const REVIEW_NOTES = [
  {
    id: '7A1D2C10-5B8E-4F2A-9C61-0E3B4D5F6A71',
    hoursAgo: 1,
    duration: 9,
    text: 'Book the dentist for Thursday afternoon, and ask if they can do a cleaning at the same time.',
  },
  {
    id: '7A1D2C10-5B8E-4F2A-9C61-0E3B4D5F6A72',
    hoursAgo: 3,
    duration: 11,
    text: 'Grocery list: oat milk, eggs, spinach, coffee beans, and something easy for dinner on Friday.',
  },
  {
    id: '7A1D2C10-5B8E-4F2A-9C61-0E3B4D5F6A73',
    hoursAgo: 5,
    duration: 18,
    text: 'Follow up with Sam about the Q3 plan. Send the draft by Monday and ask who owns the budget section.',
  },
  {
    id: '7A1D2C10-5B8E-4F2A-9C61-0E3B4D5F6A74',
    hoursAgo: 26,
    duration: 14,
    text: 'Idea for a blog post: walking meetings, and why I think better on my feet than at a desk.',
  },
  {
    id: '7A1D2C10-5B8E-4F2A-9C61-0E3B4D5F6A75',
    hoursAgo: 30,
    duration: 6,
    text: 'Remind me to renew the car registration before the end of the month.',
  },
];

/** True when the sign-in input is the review code. Off unless REVIEW_CODE is set. */
export async function isReviewCode(env, input) {
  const code = typeof env.REVIEW_CODE === 'string' ? normalizePairCode(env.REVIEW_CODE) : '';
  if (code.length < REVIEW_CODE_MIN_LENGTH || typeof input !== 'string') return false;
  return (await sha256Hex(normalizePairCode(input.trim()))) === (await sha256Hex(code));
}

/**
 * A new connection ID on the review inbox, made on first use. The oldest
 * review connections are dropped to leave room, so reviewers never hit the
 * agent limit. Returns { inboxId, connectionId } like claimPairCode.
 */
export async function claimReviewCode(ctx) {
  const db = ctx.db;
  await db
    .prepare('INSERT OR IGNORE INTO inboxes (id, secret_hash, created_at) VALUES (?, ?, ?)')
    .bind(REVIEW_INBOX_ID, await sha256Hex(randomToken(32)), ctx.now)
    .run();
  const { results: stale } = await db
    .prepare('SELECT id FROM connections WHERE inbox_id = ? ORDER BY created_at DESC LIMIT -1 OFFSET ?')
    .bind(REVIEW_INBOX_ID, MAX_AGENTS - 1)
    .all();
  for (const { id } of stale) await dropConnection(db, id);
  return { inboxId: REVIEW_INBOX_ID, connectionId: `con_${randomToken(12)}` };
}

async function dropConnection(db, id) {
  await db.batch([
    db.prepare('DELETE FROM event_subscriptions WHERE connection_id = ?').bind(id),
    db.prepare('DELETE FROM entries WHERE connection_id = ?').bind(id),
    db.prepare('DELETE FROM connections WHERE id = ? AND inbox_id = ?').bind(id, REVIEW_INBOX_ID),
  ]);
}

/**
 * Before a tool call on the review inbox: when the connection has no notes
 * waiting (new, or all marked handled), the sample notes come back as new.
 */
export async function stockReviewNotes(ctx, connection) {
  if (connection.inbox_id !== REVIEW_INBOX_ID) return;
  const db = ctx.db;
  const waiting = await db
    .prepare('SELECT 1 FROM entries WHERE connection_id = ? AND acked_at IS NULL AND removed_at IS NULL AND expires_at > ? LIMIT 1')
    .bind(connection.id, ctx.now)
    .first();
  if (waiting) return;
  const expiresAt = ctx.now + 30 * 24 * HOUR;
  // Oldest first, so ids (and list order) put the newest note on top.
  const notes = [...REVIEW_NOTES].sort((a, b) => b.hoursAgo - a.hoursAgo);
  await db.batch([
    db.prepare('DELETE FROM entries WHERE connection_id = ?').bind(connection.id),
    ...notes.map((n) =>
      db
        .prepare(
          `INSERT INTO entries (connection_id, inbox_id, recording_id, recorded_at, duration, text, expires_at, received_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
        )
        .bind(
          connection.id,
          REVIEW_INBOX_ID,
          n.id,
          new Date(ctx.now - n.hoursAgo * HOUR).toISOString(),
          n.duration,
          n.text,
          expiresAt,
          ctx.now - n.hoursAgo * HOUR + 60 * 1000,
        ),
    ),
  ]);
}

// --- Directory domain checks -------------------------------------------------

// Directories prove we own the MCP host by fetching a token they issued from a
// fixed path. Each token is a Worker setting; unset means 404.
const DOMAIN_TOKENS = {
  '/.well-known/openai-apps-challenge': 'OPENAI_APPS_CHALLENGE',
  '/.well-known/google-connected-apps': 'GOOGLE_CONNECTED_APPS_TOKEN',
};
export const DOMAIN_TOKEN_PATHS = Object.keys(DOMAIN_TOKENS);

/** GET a directory's verification path: its token as plain text. */
export function domainToken(request, ctx) {
  const value = ctx.env[DOMAIN_TOKENS[new URL(request.url).pathname]];
  if (typeof value !== 'string' || !value.trim()) {
    return new Response('Not found', { status: 404, headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
  }
  return new Response(value.trim(), { headers: { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store' } });
}
