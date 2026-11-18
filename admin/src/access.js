// Cloudflare Access check. Access sits in front of this Worker and signs in
// Justin (email code) or his agent (service token); every request it lets
// through carries a signed JWT in Cf-Access-Jwt-Assertion. We verify that JWT
// ourselves too, so a request that somehow skipped Access (Access turned off,
// a misconfigured route) is refused rather than served. See admin/README.md.
//
// No dependencies: RS256 with WebCrypto, keys from the team's certs endpoint.

const LEEWAY_S = 60;
const KEYS_TTL_MS = 10 * 60 * 1000;
const REFETCH_GAP_MS = 30 * 1000;

const keyCache = new Map(); // team -> { keys: Map(kid -> CryptoKey), fetchedAt }

export class AccessError extends Error {}

/** "goodloop", "goodloop.cloudflareaccess.com" or a full URL -> "https://goodloop.cloudflareaccess.com". */
export function teamOrigin(value) {
  let v = String(value || '').trim().replace(/\/+$/, '');
  if (!v) return null;
  if (!v.includes('.') && !v.includes('/')) v = `${v}.cloudflareaccess.com`;
  if (!/^https?:\/\//.test(v)) v = `https://${v}`;
  try {
    const url = new URL(v);
    return url.protocol === 'https:' ? url.origin : null;
  } catch {
    return null;
  }
}

function b64urlBytes(s) {
  const b64 = s.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((s.length + 3) % 4);
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}

function b64urlJSON(s) {
  return JSON.parse(new TextDecoder().decode(b64urlBytes(s)));
}

async function loadKeys(team, fetchFn, now, force) {
  const cached = keyCache.get(team);
  if (cached && !force && now - cached.fetchedAt < KEYS_TTL_MS) return cached.keys;
  if (cached && force && now - cached.fetchedAt < REFETCH_GAP_MS) return cached.keys;
  const res = await fetchFn(`${team}/cdn-cgi/access/certs`);
  if (!res.ok) throw new AccessError(`certs ${res.status}`);
  const body = await res.json();
  const keys = new Map();
  for (const jwk of body.keys || []) {
    if (jwk.kty !== 'RSA' || !jwk.kid) continue;
    const key = await crypto.subtle.importKey(
      'jwk',
      { kty: 'RSA', n: jwk.n, e: jwk.e, alg: 'RS256', ext: true },
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
      false,
      ['verify'],
    );
    keys.set(jwk.kid, key);
  }
  keyCache.set(team, { keys, fetchedAt: now });
  return keys;
}

/**
 * Verifies an Access JWT. Returns who it is: { kind: 'person', email } or
 * { kind: 'service', name } for a service token. Throws AccessError.
 */
export async function verifyAccessJWT(token, { team, aud, fetchFn = fetch, now = Date.now() }) {
  if (!token) throw new AccessError('missing token');
  const parts = token.split('.');
  if (parts.length !== 3) throw new AccessError('malformed token');
  let header;
  let payload;
  try {
    header = b64urlJSON(parts[0]);
    payload = b64urlJSON(parts[1]);
  } catch {
    throw new AccessError('malformed token');
  }
  if (header.alg !== 'RS256' || !header.kid) throw new AccessError('unexpected algorithm');

  let key = (await loadKeys(team, fetchFn, now, false)).get(header.kid);
  if (!key) key = (await loadKeys(team, fetchFn, now, true)).get(header.kid); // keys rotate
  if (!key) throw new AccessError('unknown key');

  const signed = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);
  let sig;
  try {
    sig = b64urlBytes(parts[2]);
  } catch {
    throw new AccessError('malformed token');
  }
  const ok = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, sig, signed);
  if (!ok) throw new AccessError('bad signature');

  const nowS = Math.floor(now / 1000);
  if (payload.iss !== team) throw new AccessError('wrong issuer');
  const auds = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
  if (!auds.includes(aud)) throw new AccessError('wrong audience');
  if (typeof payload.exp !== 'number' || payload.exp + LEEWAY_S < nowS) throw new AccessError('expired');
  if (typeof payload.nbf === 'number' && payload.nbf - LEEWAY_S > nowS) throw new AccessError('not yet valid');

  if (payload.email) return { kind: 'person', email: String(payload.email) };
  if (payload.common_name) return { kind: 'service', name: String(payload.common_name) };
  throw new AccessError('no identity');
}

/** Test hook: forget cached keys. */
export function clearKeyCache() {
  keyCache.clear();
}
