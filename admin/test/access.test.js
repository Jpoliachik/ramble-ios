// Every admin request needs a valid Cloudflare Access JWT (specs/admin.md).

import assert from 'node:assert/strict';
import { before, describe, it } from 'node:test';

import { teamOrigin } from '../src/access.js';
import { AUD, NOW, TEAM, createAdmin, createKeys, sign } from './helpers.js';

let keys;
let other;
before(async () => {
  keys = await createKeys('k1');
  other = await createKeys('k2');
});

describe('access', () => {
  it('lets Justin in with a valid JWT', async () => {
    const admin = createAdmin([keys]);
    const res = await admin.get('/', await sign(keys));
    assert.equal(res.status, 200);
    assert.match(res.headers.get('Content-Type'), /text\/html/);
    assert.equal(res.headers.get('Cache-Control'), 'no-store');
    assert.match(await res.text(), /Signed in as justin@example\.com/);
  });

  it('lets an agent in with a service token JWT', async () => {
    const admin = createAdmin([keys]);
    const token = await sign(keys, { email: undefined, common_name: 'abc123.access', sub: '' });
    const res = await admin.get('/api/whoami', token);
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { kind: 'service', name: 'abc123.access' });
  });

  it('refuses a request with no JWT', async () => {
    const admin = createAdmin([keys]);
    const res = await admin.get('/api/overview');
    assert.equal(res.status, 403);
    assert.equal(await res.text(), 'Forbidden');
  });

  const bad = {
    'a JWT signed by another key': async () => sign(other, {}, { kid: 'k1' }),
    'an unknown key id': async () => sign(other),
    'the wrong audience': async () => sign(keys, { aud: ['some-other-app'] }),
    'the wrong issuer': async () => sign(keys, { iss: 'https://evil.cloudflareaccess.com' }),
    'an expired JWT': async () => sign(keys, { exp: Math.floor(NOW / 1000) - 120 }),
    'a JWT not valid yet': async () => sign(keys, { nbf: Math.floor(NOW / 1000) + 600 }),
    'alg none': async () => {
      const t = await sign(keys, {}, { alg: 'none' });
      return `${t.split('.').slice(0, 2).join('.')}.`;
    },
    'a JWT with no identity': async () => sign(keys, { email: undefined }),
    garbage: async () => 'not.a.jwt',
  };
  for (const [name, make] of Object.entries(bad)) {
    it(`refuses ${name}`, async () => {
      const admin = createAdmin([keys]);
      const res = await admin.get('/api/overview', await make());
      assert.equal(res.status, 403);
    });
  }

  it('refuses everything until Access is configured', async () => {
    const admin = createAdmin([keys]);
    const token = await sign(keys);
    for (const envOverride of [{ ACCESS_AUD: '' }, { ACCESS_TEAM_DOMAIN: '' }, { ACCESS_TEAM_DOMAIN: 'http://x.example' }]) {
      const res = await admin.get('/', token, { envOverride });
      assert.equal(res.status, 503);
    }
  });

  it('checks the JWT before anything else', async () => {
    const admin = createAdmin([keys]);
    assert.equal((await admin.get('/nope')).status, 403);
    assert.equal((await admin.get('/', null, { method: 'POST' })).status, 403);
  });

  it('is read-only', async () => {
    const admin = createAdmin([keys]);
    const res = await admin.get('/api/overview', await sign(keys), { method: 'POST' });
    assert.equal(res.status, 405);
  });

  it('caches the signing keys', async () => {
    const admin = createAdmin([keys]);
    const token = await sign(keys);
    await admin.get('/api/whoami', token);
    await admin.get('/api/whoami', token);
    assert.equal(admin.calls.length, 1);
  });

  it('accepts the team name in any common form', () => {
    for (const v of ['goodloop', 'goodloop.cloudflareaccess.com', 'https://goodloop.cloudflareaccess.com/']) {
      assert.equal(teamOrigin(v), TEAM);
    }
    assert.equal(teamOrigin(''), null);
    assert.equal(teamOrigin('http://goodloop.cloudflareaccess.com'), null);
    assert.ok(AUD);
  });
});
