// Small helpers shared by every relay module: responses, errors, hashing,
// tokens and times. See specs/relay-api.md "Errors, and failing closed".

export const DOCS_URL = 'https://ramble.watch/docs';
export const DEFAULT_BASE_URL = 'https://ramble-transcription-proxy.jpoliachik.workers.dev';
export const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export const MINUTE = 60 * 1000;
export const HOUR = 60 * MINUTE;
export const DAY = 24 * HOUR;

export function json(data, status = 200, headers = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', ...headers },
  });
}

/** `{"error": sentence, "reason"?: code, ...extra}` */
export function fail(status, error, reason = null, extra = {}, headers = {}) {
  return json({ error, ...(reason ? { reason } : {}), ...extra }, status, headers);
}

export function unauthorized() {
  return fail(401, 'Invalid or revoked credentials. Send "Authorization: Bearer <token>".');
}

export function wrongCredential() {
  return fail(403, "This credential can't call this endpoint.", 'wrong_credential');
}

export function unavailable() {
  return fail(503, 'Ramble is temporarily unavailable. Try again shortly.', 'unavailable');
}

export function rateLimited(retryAfter) {
  const seconds = Math.max(1, Math.ceil(retryAfter || 1));
  return fail(429, 'Too many requests. Try again later.', 'rate_limited', {}, { 'Retry-After': String(seconds) });
}

export const GONE_ERROR = 'This version of Ramble is out of date. Update Ramble from the App Store.';
export function gone() {
  return fail(410, GONE_ERROR);
}

/** Bodies are JSON whatever their Content-Type. Null when unreadable. */
export async function readJSON(request) {
  try {
    const text = await request.text();
    return text ? JSON.parse(text) : null;
  } catch {
    return null;
  }
}

/** Lenient: "Bearer <t>", "bearer <t>", or the bare credential. */
export function bearerValue(request) {
  return (request.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '').trim();
}

export async function sha256Hex(value) {
  const data = typeof value === 'string' ? new TextEncoder().encode(value) : value;
  const digest = await crypto.subtle.digest('SHA-256', data);
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, '0')).join('');
}

/** Short one-way ID for logs and limiter keys: never log raw inbox or key IDs. */
export async function logId(value) {
  return (await sha256Hex(`ramble-log:${value}`)).slice(0, 12);
}

export function randomToken(bytes) {
  const raw = String.fromCharCode(...crypto.getRandomValues(new Uint8Array(bytes)));
  return btoa(raw).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export const iso = (ms) => (ms == null ? null : new Date(ms).toISOString());

export function utcDayStart(ms) {
  const d = new Date(ms);
  return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate());
}

export function utcMonth(ms) {
  return new Date(ms).toISOString().slice(0, 7);
}

export function nextMonthStart(ms) {
  const d = new Date(ms);
  return Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 1);
}

export function baseURL(ctx) {
  return (ctx.env.RELAY_BASE_URL || ctx.origin || DEFAULT_BASE_URL).replace(/\/+$/, '');
}

/** Resolves to the promise's value, or `onTimeout` after `ms`. */
export function withTimeout(promise, ms, onTimeout) {
  let timer;
  const timeout = new Promise((resolve) => {
    timer = setTimeout(() => resolve(onTimeout), ms);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}
