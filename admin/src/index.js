// Ramble Admin: Justin's private dashboard. Cloudflare Access signs people in
// before a request reaches this Worker; every handler here also requires a
// valid Access JWT (see access.js and admin/README.md). Read-only.

import { AccessError, teamOrigin, verifyAccessJWT } from './access.js';
import { overview } from './metrics.js';
import { renderPage } from './page.js';

const SECURITY_HEADERS = {
  'Cache-Control': 'no-store',
  'X-Content-Type-Options': 'nosniff',
  'X-Frame-Options': 'DENY',
  'Referrer-Policy': 'no-referrer',
  'X-Robots-Tag': 'noindex, nofollow',
  'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'",
};

function respond(status, body, type) {
  return new Response(body, { status, headers: { 'Content-Type': type, ...SECURITY_HEADERS } });
}
const json = (status, value) => respond(status, JSON.stringify(value, null, 2), 'application/json; charset=utf-8');
const text = (status, message) => respond(status, message, 'text/plain; charset=utf-8');

/** Resolves who is calling, or a refusal Response. Never lets a request through without a valid JWT. */
async function authorize(request, env, deps) {
  const team = teamOrigin(env.ACCESS_TEAM_DOMAIN);
  const aud = String(env.ACCESS_AUD || '').trim();
  if (!team || !aud) return { response: text(503, 'Admin is not set up yet: Cloudflare Access settings are missing.') };
  try {
    const who = await verifyAccessJWT(request.headers.get('Cf-Access-Jwt-Assertion'), {
      team,
      aud,
      fetchFn: deps.fetch ?? fetch,
      now: deps.now ?? Date.now(),
    });
    return { who };
  } catch (err) {
    if (!(err instanceof AccessError)) console.error(`[admin] access check failed: ${String(err?.message).slice(0, 200)}`);
    return { response: text(403, 'Forbidden') };
  }
}

export async function handleRequest(request, env, deps = {}) {
  const auth = await authorize(request, env, deps);
  if (auth.response) return auth.response;

  const { pathname } = new URL(request.url);
  if (request.method !== 'GET' && request.method !== 'HEAD') return text(405, 'Read-only');
  if (!env.DB) return text(503, 'Database binding missing');

  const now = deps.now ?? Date.now();
  if (pathname === '/') {
    return respond(200, renderPage(await overview(env.DB, now), auth.who), 'text/html; charset=utf-8');
  }
  if (pathname === '/api/overview') return json(200, await overview(env.DB, now));
  if (pathname === '/api/whoami') return json(200, auth.who);
  return text(404, 'Not found');
}

export default {
  fetch: (request, env) => handleRequest(request, env),
};
