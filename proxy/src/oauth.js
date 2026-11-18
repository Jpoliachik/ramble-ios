// OAuth for the MCP connector (specs/connector.md). Just enough of OAuth 2.1
// for a remote MCP client such as Claude: discovery metadata, dynamic client
// registration, an authorization page and a token endpoint.
//
// There are no accounts. The sign-in page asks for the pairing code the
// Ramble app shows on its Connect screen, the same code an agent sends to
// POST /pair/exchange. Redeeming the authorization code makes one agent
// connection, and its agent key (rmba_) is the access token. It never
// expires; disconnecting the agent in the app revokes it.

import { address, limit } from './auth.js';
import { MINUTE, json, randomToken, readJSON, sha256Hex } from './http.js';
import { claimPairCode, cleanName, createConnection, pairCodeWasUsed } from './relay.js';

export const OAUTH_CODE_TTL_MS = 10 * MINUTE;
export const CLIENT_UNUSED_TTL_MS = 24 * 60 * MINUTE;
const MAX_REDIRECT_URIS = 5;
const MAX_URI_LENGTH = 2000;

const origin = (ctx) => ctx.origin.replace(/\/+$/, '');
export const resourceURL = (ctx) => `${origin(ctx)}/mcp`;
export const resourceMetadataURL = (ctx) => `${origin(ctx)}/.well-known/oauth-protected-resource`;

// --- Discovery ---------------------------------------------------------------

/** RFC 9728: where to sign in for /mcp. */
export function protectedResourceMetadata(_request, ctx) {
  return json({
    resource: resourceURL(ctx),
    authorization_servers: [origin(ctx)],
    bearer_methods_supported: ['header'],
    resource_name: 'Ramble',
    resource_documentation: 'https://ramble.watch/docs',
  });
}

/** RFC 8414. */
export function authorizationServerMetadata(_request, ctx) {
  const base = origin(ctx);
  return json({
    issuer: base,
    authorization_endpoint: `${base}/authorize`,
    token_endpoint: `${base}/token`,
    registration_endpoint: `${base}/register`,
    response_types_supported: ['code'],
    grant_types_supported: ['authorization_code'],
    code_challenge_methods_supported: ['S256'],
    token_endpoint_auth_methods_supported: ['none'],
    authorization_response_iss_parameter_supported: true,
    service_documentation: 'https://ramble.watch/docs',
  });
}

// --- Registration ------------------------------------------------------------

const oauthError = (status, error, description) =>
  json({ error, ...(description ? { error_description: description } : {}) }, status);

const LOOPBACK = ['localhost', '127.0.0.1', '[::1]'];
const parseURL = (value) => {
  try {
    return new URL(value);
  } catch {
    return null;
  }
};
const isLoopback = (url) => url.protocol === 'http:' && LOOPBACK.includes(url.hostname);

/** HTTPS, or http on the local machine for developer tools. */
export function validRedirectURI(value) {
  if (typeof value !== 'string' || value.length > MAX_URI_LENGTH) return false;
  const url = parseURL(value);
  if (!url || url.hash || url.username || url.password) return false;
  return url.protocol === 'https:' || isLoopback(url);
}

/**
 * Exact match, except that a loopback redirect matches on any port
 * (RFC 8252 §7.3): local clients such as Claude Code pick a new port each run.
 */
export function redirectMatches(registered, given) {
  if (registered.includes(given)) return true;
  const url = parseURL(given);
  if (!url || !isLoopback(url)) return false;
  const portless = (u) => `${u.protocol}//${u.hostname}${u.pathname}${u.search}`;
  return registered.some((r) => {
    const reg = parseURL(r);
    return reg && isLoopback(reg) && portless(reg) === portless(url);
  });
}

/**
 * RFC 7591, public clients only. Claude registers a client on every new
 * connection, and all its traffic comes from a few addresses, so the
 * per-address limit is high; it only stops floods. Clients never used to
 * sign in are deleted after a day.
 */
export async function register(request, ctx) {
  const limited = await limit(ctx, ['oauth_register', address(request, ctx)]);
  if (limited) return limited;

  const body = await readJSON(request);
  const uris = body?.redirect_uris;
  if (!Array.isArray(uris) || uris.length === 0 || uris.length > MAX_REDIRECT_URIS || !uris.every(validRedirectURI)) {
    return oauthError(400, 'invalid_redirect_uri', `"redirect_uris" must be 1–${MAX_REDIRECT_URIS} https:// URLs`);
  }
  const id = `rmbc_${randomToken(16)}`;
  const name = cleanName(body.client_name);
  await ctx.db
    .prepare('INSERT INTO oauth_clients (id, name, redirect_uris, created_at) VALUES (?, ?, ?, ?)')
    .bind(id, name, JSON.stringify(uris), ctx.now)
    .run();
  return json(
    {
      client_id: id,
      client_id_issued_at: Math.floor(ctx.now / 1000),
      ...(name ? { client_name: name } : {}),
      redirect_uris: uris,
      grant_types: ['authorization_code'],
      response_types: ['code'],
      token_endpoint_auth_method: 'none',
    },
    201,
  );
}

async function findClient(ctx, id) {
  if (typeof id !== 'string' || !id) return null;
  const row = await ctx.db.prepare('SELECT id, name, redirect_uris FROM oauth_clients WHERE id = ?').bind(id).first();
  return row ? { id: row.id, name: row.name, redirectURIs: JSON.parse(row.redirect_uris) } : null;
}

// --- Authorization -----------------------------------------------------------

const AUTH_FIELDS = ['response_type', 'client_id', 'redirect_uri', 'state', 'code_challenge', 'code_challenge_method', 'scope', 'resource'];

/**
 * Checks the request's OAuth parameters. Until the client and redirect URI
 * are known good, errors are shown on the page, never redirected.
 * Returns { params, client } or { response }.
 */
async function checkAuthorizeParams(params, ctx) {
  const client = await findClient(ctx, params.client_id);
  if (!client) return { response: errorPage(400, 'This connector isn’t registered with Ramble. Remove it and add it again.') };
  if (!redirectMatches(client.redirectURIs, params.redirect_uri)) {
    return { response: errorPage(400, 'This sign-in link doesn’t match the connector. Remove it and add it again.') };
  }
  if (params.response_type !== 'code') return { response: redirectError(params, 'unsupported_response_type', ctx) };
  if (!/^[A-Za-z0-9_-]{43,128}$/.test(params.code_challenge ?? '') || params.code_challenge_method !== 'S256') {
    return { response: redirectError(params, 'invalid_request', ctx, 'PKCE with S256 is required') };
  }
  return { params, client };
}

function redirectError(params, error, ctx, description) {
  const url = new URL(params.redirect_uri);
  url.searchParams.set('error', error);
  if (description) url.searchParams.set('error_description', description);
  if (params.state) url.searchParams.set('state', params.state);
  url.searchParams.set('iss', origin(ctx));
  return redirect(url.href);
}

const redirect = (location) => new Response(null, { status: 302, headers: { Location: location, 'Cache-Control': 'no-store' } });

/** GET /authorize: the sign-in page. */
export async function authorizePage(request, ctx) {
  const query = new URL(request.url).searchParams;
  const params = Object.fromEntries(AUTH_FIELDS.map((k) => [k, query.get(k) ?? '']));
  const checked = await checkAuthorizeParams(params, ctx);
  if (checked.response) return checked.response;
  return signInPage(checked.params, checked.client);
}

/**
 * POST /authorize: the person submitted the pairing code (or the whole
 * message the app copies). A good code is claimed and the browser goes back
 * to the connector with a one-time authorization code.
 */
export async function authorizeSubmit(request, ctx) {
  const form = await readForm(request);
  const params = Object.fromEntries(AUTH_FIELDS.map((k) => [k, form[k] ?? '']));
  const checked = await checkAuthorizeParams(params, ctx);
  if (checked.response) return checked.response;
  const { client } = checked;

  const pairCode = extractPairCode(form.pairing_code);
  const typed = typeof form.pairing_code === 'string' ? form.pairing_code.slice(0, 500) : '';
  if (!pairCode) return signInPage(params, client, 'That doesn’t look like a pairing code.', typed);
  const claimed = await claimPairCode(ctx, pairCode);
  if (!claimed) {
    const used = await pairCodeWasUsed(ctx, pairCode);
    return signInPage(
      params,
      client,
      used ? 'That code was already used. Make a new one in Ramble.' : 'That code didn’t work. Codes last 10 minutes, so make a new one in Ramble.',
      typed,
    );
  }

  const code = randomToken(32);
  await ctx.db
    .prepare(
      `INSERT INTO oauth_codes (code_hash, client_id, redirect_uri, code_challenge, inbox_id, connection_id, name, expires_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    )
    .bind(
      await sha256Hex(code),
      client.id,
      params.redirect_uri,
      params.code_challenge,
      claimed.inboxId,
      claimed.connectionId,
      client.name,
      ctx.now + OAUTH_CODE_TTL_MS,
    )
    .run();

  const url = new URL(params.redirect_uri);
  url.searchParams.set('code', code);
  if (params.state) url.searchParams.set('state', params.state);
  url.searchParams.set('iss', origin(ctx));
  return redirect(url.href);
}

/** The code alone, or the whole "My pairing code is …" message pasted in. */
export function extractPairCode(input) {
  if (typeof input !== 'string') return null;
  const text = input.trim();
  const inMessage = text.match(/\b[2-9A-Z]{4}-[2-9A-Z]{4}-[2-9A-Z]{4}\b/i);
  if (inMessage) return inMessage[0];
  const bare = text.replace(/[\s-]/g, '');
  return /^[2-9A-Z]{12}$/i.test(bare) ? bare : null;
}

// --- Token -------------------------------------------------------------------

/**
 * POST /token: authorization_code with PKCE. The code is used up by the first
 * attempt, right or wrong. Success makes the agent connection.
 */
export async function token(request, ctx) {
  const form = await readForm(request);
  if (form.grant_type !== 'authorization_code') {
    return oauthError(400, 'unsupported_grant_type', 'Only authorization_code is supported');
  }
  if (typeof form.code !== 'string' || !form.code || typeof form.code_verifier !== 'string') {
    return oauthError(400, 'invalid_request', '"code" and "code_verifier" are required');
  }
  const row = await ctx.db
    .prepare('DELETE FROM oauth_codes WHERE code_hash = ? RETURNING *')
    .bind(await sha256Hex(form.code))
    .first();
  if (
    !row ||
    row.expires_at <= ctx.now ||
    row.client_id !== form.client_id ||
    row.redirect_uri !== form.redirect_uri ||
    (await pkceChallenge(form.code_verifier)) !== row.code_challenge
  ) {
    return oauthError(400, 'invalid_grant', 'The authorization code is invalid, expired or already used');
  }
  const accessToken = await createConnection(ctx, { inboxId: row.inbox_id, connectionId: row.connection_id, name: row.name, via: 'mcp' });
  if (!accessToken) return oauthError(400, 'invalid_grant', 'This Ramble inbox already has the most agents it can connect');
  await ctx.db.prepare('UPDATE oauth_clients SET last_used_at = ? WHERE id = ?').bind(ctx.now, row.client_id).run();
  return json({ access_token: accessToken, token_type: 'Bearer' });
}

export async function pkceChallenge(verifier) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier));
  return btoa(String.fromCharCode(...new Uint8Array(digest))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/** Form-encoded per OAuth; JSON accepted too. */
async function readForm(request) {
  const text = await request.text().catch(() => '');
  if (/^\s*\{/.test(text)) {
    try {
      const body = JSON.parse(text);
      return body && typeof body === 'object' ? body : {};
    } catch {
      return {};
    }
  }
  return Object.fromEntries(new URLSearchParams(text));
}

/**
 * Cron: unredeemed authorization codes (their claimed pairing codes just
 * lapse), and clients a day old that never signed anyone in.
 */
export async function purgeOAuthCodes(db, now) {
  await db.batch([
    db.prepare('DELETE FROM oauth_codes WHERE expires_at <= ?').bind(now),
    db.prepare('DELETE FROM oauth_clients WHERE last_used_at IS NULL AND created_at <= ?').bind(now - CLIENT_UNUSED_TTL_MS),
  ]);
}

// --- Pages -------------------------------------------------------------------

const escape = (s) =>
  String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

function page(status, body, formAction = "'self'") {
  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Connect Ramble</title>
<style>
  :root { --bg: #f9f5ed; --card: #fff; --ink: #141210; --soft: #403b33; --faint: #7a7163; --hair: #e8e5df; --amber: #d97706; --amber-text: #b45309; --on-amber: #fff; --err: #b42318; }
  @media (prefers-color-scheme: dark) {
    :root { --bg: #141210; --card: #1d1a17; --ink: #f4efe7; --soft: #c9c2b5; --faint: #8a8275; --hair: #2a2723; --amber: #f59e0b; --amber-text: #fbbf5a; --on-amber: #1f1404; --err: #f97066; }
  }
  * { box-sizing: border-box; }
  body { margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: 24px 16px; background: var(--bg); color: var(--ink); font: 16px/1.5 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Arial, sans-serif; }
  main { width: 100%; max-width: 420px; background: var(--card); border: 1px solid var(--hair); border-radius: 20px; padding: 32px 24px; }
  .mark { display: flex; align-items: center; gap: 8px; font: italic 700 20px/1 "New York", Georgia, serif; margin-bottom: 24px; }
  .mark::before { content: ""; width: 10px; height: 10px; border-radius: 50%; background: var(--amber); }
  h1 { font: 600 24px/1.25 "New York", Georgia, serif; margin: 0 0 8px; }
  p { color: var(--soft); margin: 0 0 16px; }
  ol { color: var(--soft); padding-left: 20px; margin: 0 0 20px; }
  label { display: block; font-weight: 600; margin-bottom: 6px; }
  textarea { width: 100%; min-height: 56px; resize: vertical; padding: 12px; border-radius: 12px; border: 1px solid var(--hair); background: var(--bg); color: var(--ink); font: 16px/1.4 ui-monospace, "SF Mono", Menlo, monospace; }
  textarea:focus { outline: 2px solid var(--amber); outline-offset: 1px; }
  button { width: 100%; margin-top: 16px; padding: 14px; border: 0; border-radius: 14px; background: var(--amber); color: var(--on-amber); font: 600 17px/1 inherit; font-family: inherit; cursor: pointer; }
  .error { color: var(--err); margin: 12px 0 0; }
  .host { color: var(--faint); font-size: 15px; margin: -4px 0 20px; }
  .fine { color: var(--faint); font-size: 14px; margin: 16px 0 0; }
</style>
</head>
<body><main><div class="mark">Ramble</div>${body}</main></body>
</html>`;
  return new Response(html, {
    status,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'no-store',
      'X-Frame-Options': 'DENY',
      'Content-Security-Policy': `default-src 'none'; style-src 'unsafe-inline'; form-action ${formAction}; frame-ancestors 'none'; base-uri 'none'`,
      'Referrer-Policy': 'no-referrer',
    },
  });
}

function signInPage(params, client, error, typed = '') {
  const back = new URL(params.redirect_uri);
  const name = client.name ? escape(client.name) : '';
  const hidden = AUTH_FIELDS.map((k) => `<input type="hidden" name="${k}" value="${escape(params[k])}">`).join('');
  // Any MCP client can register any name, so the page always shows where the
  // browser goes next (the redirect host) under it.
  // Chromium checks form-action on the redirect after the submit too, so the
  // connector's origin must be allowed or the browser never goes back.
  return page(
    error ? 400 : 200,
    `<h1>Connect ${name || 'your agent'}</h1>
<p class="host">from ${escape(back.host)}</p>
<p>Paste the pairing code from the Ramble app: Settings → Your agent → Connect.</p>
<form method="post" action="/authorize">${hidden}
  <textarea id="pairing_code" name="pairing_code" aria-label="Pairing code" autocomplete="off" autocapitalize="characters" spellcheck="false" placeholder="Pairing code" required>${escape(typed)}</textarea>
  ${error ? `<p class="error" role="alert">${escape(error)}</p>` : ''}
  <button type="submit">Connect</button>
</form>
<p class="fine">${name || 'It'} can read your new notes. Disconnect anytime in Ramble.</p>`,
    `'self' ${back.origin}`,
  );
}

function errorPage(status, message) {
  return page(status, `<h1>Can’t connect</h1><p>${escape(message)}</p>`);
}

