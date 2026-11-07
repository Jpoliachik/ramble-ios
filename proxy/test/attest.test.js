import { beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { createHash, sign } from 'node:crypto';

import { handleAttest, handleAttestChallenge, verifyAssertionForRequest } from '../src/attest.js';
import { ecKey, makeCA, makeCert, octets, tlv } from './x509.js';

const APP_ID = 'SW6VLKWS7Q.dev.goodloop.Ramble';
const NONCE_OID = '1.2.840.113635.100.8.2';
const PROD = Buffer.concat([Buffer.from('appattest'), Buffer.alloc(7)]);
const DEV = Buffer.from('appattestdevelop');

const sha = (b) => createHash('sha256').update(b).digest();

// A stand-in App Attest root and intermediate.
const root = makeCA({ cn: 'Test App Attestation Root CA' });
const intermediate = makeCA({ cn: 'Test App Attestation CA 1', issuer: root });
const deps = { rootCertDer: root.der };

// --- minimal CBOR encoder (maps with text keys, byte strings, arrays) ---
function head(major, n) {
  if (n < 24) return Buffer.from([(major << 5) | n]);
  if (n < 256) return Buffer.from([(major << 5) | 24, n]);
  return Buffer.from([(major << 5) | 25, n >> 8, n & 0xff]);
}
function cbor(v) {
  if (Buffer.isBuffer(v)) return Buffer.concat([head(2, v.length), v]);
  if (typeof v === 'string') return Buffer.concat([head(3, Buffer.byteLength(v)), Buffer.from(v)]);
  if (Array.isArray(v)) return Buffer.concat([head(4, v.length), ...v.map(cbor)]);
  const entries = Object.entries(v);
  return Buffer.concat([head(5, entries.length), ...entries.flatMap(([k, x]) => [cbor(k), cbor(x)])]);
}

function rawPublicKey(key) {
  const spki = key.publicKey.export({ type: 'spki', format: 'der' });
  return spki.subarray(spki.length - 65); // uncompressed P-256 point
}

// Builds an attestation for `challenge`. Options break one thing at a time.
function makeAttestation(challenge, o = {}) {
  const key = o.key || ecKey('P-256');
  const keyIdBytes = sha(rawPublicKey(key));
  const counter = Buffer.alloc(4);
  counter.writeUInt32BE(o.counter ?? 0);
  const credId = o.credId || keyIdBytes;
  const authData = Buffer.concat([
    sha(o.appId || APP_ID),
    Buffer.from([0x41]),
    counter,
    o.aaguid || PROD,
    Buffer.from([0, credId.length]),
    credId,
    Buffer.from([0xa0]), // COSE key, unused by the relay
  ]);
  const nonce = o.nonce || sha(Buffer.concat([authData, sha(Buffer.from(challenge))]));
  const nonceExt = tlv(0x30, tlv(0xa1, octets(nonce)));
  const issuer = o.intermediate || intermediate;
  const leaf = makeCert({ cn: 'cred', key, issuer, hash: 'sha256', extensions: [[NONCE_OID, nonceExt]] });
  const attestation = cbor({
    fmt: 'apple-appattest',
    attStmt: { x5c: [leaf, issuer.der], receipt: Buffer.from('r') },
    authData,
  }).toString('base64');
  return { key, keyId: o.keyId || keyIdBytes.toString('base64'), attestation };
}

function makeKV() {
  const map = new Map();
  return {
    map,
    async get(k) { return map.has(k) ? map.get(k) : null; },
    async put(k, v) { map.set(k, v); },
    async delete(k) { map.delete(k); },
  };
}

let env;
beforeEach(() => {
  env = { ATTEST_KV: makeKV() };
});

const req = (path, body) =>
  new Request(`https://relay.test${path}`, {
    method: 'POST',
    headers: { 'X-Device-ID': 'device-1' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });

async function challenge() {
  return (await handleAttestChallenge(req('/attest/challenge'), env)).challenge;
}

async function register(opts = {}, d = deps) {
  const c = await challenge();
  const a = makeAttestation(c, opts);
  const result = await handleAttest(req('/attest', { keyId: a.keyId, attestation: a.attestation, challenge: c }), env, d);
  return { ...a, result };
}

const storedKeys = () => [...env.ATTEST_KV.map.keys()].filter((k) => k.startsWith('key:'));

describe('App Attest registration', () => {
  it('registers a production attestation for this app', async () => {
    const { keyId, key, result } = await register();
    assert.deepEqual(result, { status: 'ok' });
    const stored = JSON.parse(env.ATTEST_KV.map.get(`key:${keyId}`));
    assert.equal(stored.counter, 0);
    assert.equal(stored.publicKey, rawPublicKey(key).toString('base64'));
  });

  it('rejects another app (wrong rpIdHash) and stores nothing', async () => {
    const { result } = await register({ appId: 'ABCDE12345.dev.goodloop.Ramble' });
    assert.equal(result.status, 403);
    assert.deepEqual(storedKeys(), []);
  });

  it('uses APP_ATTEST_APP_ID when set', async () => {
    env.APP_ATTEST_APP_ID = 'TEAM000000.other.app';
    assert.equal((await register()).result.status, 403);
    assert.deepEqual((await register({ appId: 'TEAM000000.other.app' })).result, { status: 'ok' });
  });

  it('rejects a development attestation', async () => {
    const { result } = await register({ aaguid: DEV });
    assert.equal(result.status, 403);
    assert.deepEqual(storedKeys(), []);
  });

  it('accepts a development attestation only on a development relay', async () => {
    env.ENVIRONMENT = 'development';
    assert.deepEqual((await register({ aaguid: DEV })).result, { status: 'ok' });
    env.ENVIRONMENT = 'production';
    assert.equal((await register({ aaguid: DEV })).result.status, 403);
  });

  it('rejects a chain to a different root, including the real Apple root', async () => {
    const otherRoot = makeCA({ cn: 'Other Root' });
    const otherInt = makeCA({ cn: 'Other Int', issuer: otherRoot });
    assert.equal((await register({ intermediate: otherInt })).result.status, 403);
    assert.equal((await register({}, {})).result.status, 403); // pinned to Apple's App Attest root
  });

  it('rejects a nonzero counter, a nonce mismatch, a key ID mismatch and a credential ID mismatch', async () => {
    assert.equal((await register({ counter: 1 })).result.status, 403);
    assert.equal((await register({ nonce: Buffer.alloc(32) })).result.status, 403);
    assert.equal((await register({ keyId: Buffer.alloc(32).toString('base64') })).result.status, 403);
    assert.equal((await register({ credId: Buffer.alloc(32, 1) })).result.status, 403);
    assert.deepEqual(storedKeys(), []);
  });

  it('accepts a challenge only once, and only for its device', async () => {
    const c = await challenge();
    const a = makeAttestation(c);
    const body = { keyId: a.keyId, attestation: a.attestation, challenge: c };
    const other = new Request('https://relay.test/attest', {
      method: 'POST', headers: { 'X-Device-ID': 'device-2' }, body: JSON.stringify(body),
    });
    assert.equal((await handleAttest(other, env, deps)).status, 403);
    assert.equal((await handleAttest(req('/attest', body), env, deps)).status, 403);
  });

  it('re-registering the same key changes nothing; another public key gets 409', async () => {
    const first = await register();
    const before = env.ATTEST_KV.map.get(`key:${first.keyId}`);
    const c = await challenge();
    const again = makeAttestation(c, { key: first.key });
    const result = await handleAttest(req('/attest', { keyId: again.keyId, attestation: again.attestation, challenge: c }), env, deps);
    assert.deepEqual(result, { status: 'ok' });
    assert.equal(env.ATTEST_KV.map.get(`key:${first.keyId}`), before);

    // A stored record with a different key under the same ID.
    const second = await register();
    const tampered = { ...JSON.parse(env.ATTEST_KV.map.get(`key:${second.keyId}`)), publicKey: 'AAAA' };
    env.ATTEST_KV.map.set(`key:${second.keyId}`, JSON.stringify(tampered));
    const c2 = await challenge();
    const a2 = makeAttestation(c2, { key: second.key });
    const conflict = await handleAttest(req('/attest', { keyId: a2.keyId, attestation: a2.attestation, challenge: c2 }), env, deps);
    assert.equal(conflict.status, 409);
    assert.equal(conflict.reason, 'key_exists');
    assert.equal(JSON.parse(env.ATTEST_KV.map.get(`key:${second.keyId}`)).publicKey, 'AAAA');
  });

  it('answers 403 when the key store fails', async () => {
    const c = await challenge();
    const a = makeAttestation(c);
    env.ATTEST_KV.get = async () => { throw new Error('KV down'); };
    const result = await handleAttest(req('/attest', { keyId: a.keyId, attestation: a.attestation, challenge: c }), env, deps);
    assert.equal(result.status, 403);
  });

  it('rejects garbage attestations with 403', async () => {
    const c = await challenge();
    const result = await handleAttest(req('/attest', { keyId: 'AAAA', attestation: 'bm90IGNib3I=', challenge: c }), env, deps);
    assert.equal(result.status, 403);
  });
});

describe('App Attest assertions', () => {
  function assertion(key, body, counter, appId = APP_ID) {
    const c = Buffer.alloc(4);
    c.writeUInt32BE(counter);
    const authenticatorData = Buffer.concat([sha(appId), Buffer.from([0x01]), c]);
    const nonce = sha(Buffer.concat([authenticatorData, sha(body)]));
    const signature = sign('sha256', nonce, { key: key.privateKey, dsaEncoding: 'der' });
    return cbor({ signature, authenticatorData }).toString('base64');
  }

  it('accepts an increasing counter and rejects a replay', async () => {
    const { key, keyId } = await register();
    const body = Buffer.from('{"x":1}');
    assert.equal((await verifyAssertionForRequest(keyId, assertion(key, body, 1), body, env)).valid, true);
    assert.equal((await verifyAssertionForRequest(keyId, assertion(key, body, 1), body, env)).valid, false);
    assert.equal((await verifyAssertionForRequest(keyId, assertion(key, body, 2), body, env)).valid, true);
    assert.equal(JSON.parse(env.ATTEST_KV.map.get(`key:${keyId}`)).counter, 2);
  });

  it('rejects a wrong rpIdHash, a different body, another key and unknown key IDs', async () => {
    const { key, keyId } = await register();
    const body = Buffer.from('');
    assert.equal((await verifyAssertionForRequest(keyId, assertion(key, body, 1, 'X.other'), body, env)).valid, false);
    assert.equal((await verifyAssertionForRequest(keyId, assertion(key, Buffer.from('a'), 1), body, env)).valid, false);
    assert.equal((await verifyAssertionForRequest(keyId, assertion(ecKey('P-256'), body, 1), body, env)).valid, false);
    assert.equal((await verifyAssertionForRequest('nope', assertion(key, body, 1), body, env)).valid, false);
    assert.equal((await verifyAssertionForRequest(keyId, 'garbage', body, env)).valid, false);
  });

  it('marks key store failures as unavailable', async () => {
    const { key, keyId } = await register();
    env.ATTEST_KV.get = async () => { throw new Error('KV down'); };
    const r = await verifyAssertionForRequest(keyId, assertion(key, Buffer.from(''), 1), Buffer.from(''), env);
    assert.equal(r.valid, false);
    assert.equal(r.unavailable, true);
  });
});
