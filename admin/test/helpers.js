// Test helpers: a real RS256 key pair standing in for the Access team's
// signing key, a fake certs endpoint, and the relay's real schema (the
// proxy's node:sqlite D1 stand-in applies proxy/migrations).

import { clearKeyCache } from '../src/access.js';
import { handleRequest } from '../src/index.js';
import { createTestDB } from '../../proxy/test/d1.js';

export const TEAM = 'https://goodloop.cloudflareaccess.com';
export const AUD = 'aud-ramble-admin';
export const NOW = Date.UTC(2026, 10, 18, 15, 0, 0);
export const DAY = 24 * 60 * 60 * 1000;

const enc = (v) => Buffer.from(typeof v === 'string' ? v : JSON.stringify(v)).toString('base64url');

export async function createKeys(kid = 'k1') {
  const pair = await crypto.subtle.generateKey(
    { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
    true,
    ['sign', 'verify'],
  );
  const jwk = await crypto.subtle.exportKey('jwk', pair.publicKey);
  return { kid, privateKey: pair.privateKey, jwk: { ...jwk, kid, alg: 'RS256', use: 'sig' } };
}

export async function sign(keys, claims = {}, header = {}) {
  const nowS = Math.floor(NOW / 1000);
  const payload = { iss: TEAM, aud: [AUD], email: 'justin@example.com', iat: nowS, nbf: nowS, exp: nowS + 3600, ...claims };
  const head = enc({ alg: 'RS256', kid: keys.kid, typ: 'JWT', ...header });
  const body = enc(payload);
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', keys.privateKey, new TextEncoder().encode(`${head}.${body}`));
  return `${head}.${body}.${Buffer.from(sig).toString('base64url')}`;
}

export function createAdmin(keySets) {
  clearKeyCache();
  const db = createTestDB();
  const calls = [];
  const fetchFn = async (url) => {
    calls.push(url);
    if (url !== `${TEAM}/cdn-cgi/access/certs`) return new Response('no', { status: 404 });
    return Response.json({ keys: keySets.map((k) => k.jwk) });
  };
  const env = { DB: db, ACCESS_TEAM_DOMAIN: 'goodloop.cloudflareaccess.com', ACCESS_AUD: AUD, HEAVY_USE_HOURS: '50' };
  return {
    db,
    env,
    calls,
    async get(path, token, { method = 'GET', envOverride = {} } = {}) {
      const headers = token ? { 'Cf-Access-Jwt-Assertion': token } : {};
      const req = new Request(`https://ramble-admin.example.workers.dev${path}`, { method, headers });
      return handleRequest(req, { ...env, ...envOverride }, { fetch: fetchFn, now: NOW });
    },
    exec(sql, ...params) {
      db.sqlite.prepare(sql).run(...params);
    },
  };
}
