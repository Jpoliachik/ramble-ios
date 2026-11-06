import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { sign } from 'node:crypto';

import {
  AppleVerifyError,
  verifyAppleJWS,
  verifyAppTransaction,
  verifyNotification,
  verifySignedTransaction,
} from '../src/apple.js';
import { ecKey, makeCA, makeCert } from './x509.js';

const LEAF_OID = '1.2.840.113635.100.6.11.1';
const WWDR_OID = '1.2.840.113635.100.6.2.1';
const NULL = Buffer.from([0x05, 0x00]);

// A stand-in "Apple" chain: root -> WWDR-style intermediate -> receipt-signing leaf.
const root = makeCA({ cn: 'Test Root CA - G3' });
const intermediate = makeCA({ cn: 'Test WWDR G6', issuer: root, extensions: [[WWDR_OID, NULL]] });
const leafKey = ecKey('P-256');
const leaf = makeCert({ cn: 'Test StoreKit', key: leafKey, issuer: intermediate, extensions: [[LEAF_OID, NULL]] });

const deps = { rootCertDer: root.der };
const env = { APPLE_BUNDLE_ID: 'dev.goodloop.Ramble' };
const SIGNED_AT = Date.UTC(2026, 10, 1);

const b64url = (buf) => Buffer.from(buf).toString('base64url');

function makeJWS(payload, { x5c = [leaf, intermediate.der, root.der], key = leafKey.privateKey, alg = 'ES256' } = {}) {
  const header = b64url(JSON.stringify({ alg, x5c: x5c.map((c) => Buffer.from(c).toString('base64')) }));
  const body = b64url(JSON.stringify(payload));
  const sig = sign('sha256', Buffer.from(`${header}.${body}`), { key, dsaEncoding: 'ieee-p1363' });
  return `${header}.${body}.${b64url(sig)}`;
}

function transaction(overrides = {}) {
  return {
    transactionId: '2000000123',
    originalTransactionId: '2000000100',
    bundleId: 'dev.goodloop.Ramble',
    productId: 'dev.goodloop.ramble.unlock',
    environment: 'Production',
    signedDate: SIGNED_AT,
    appAccountToken: '7b1f4c64-0000-4000-8000-000000000000',
    ...overrides,
  };
}

async function rejects(promise, pattern) {
  await assert.rejects(promise, (err) => {
    assert.ok(err instanceof AppleVerifyError, `expected AppleVerifyError, got ${err}`);
    assert.equal(err.reason, 'invalid_transaction');
    if (pattern) assert.match(err.message, pattern);
    return true;
  });
}

describe('verifyAppleJWS', () => {
  it('accepts a JWS chained to the trusted root and returns the payload', async () => {
    const payload = await verifyAppleJWS(makeJWS(transaction()), deps);
    assert.equal(payload.transactionId, '2000000123');
  });

  it('rejects our test chain against the real Apple Root CA - G3 pin', async () => {
    await rejects(verifyAppleJWS(makeJWS(transaction())), /Apple Root CA - G3/);
  });

  it('rejects a self-signed JWS', async () => {
    const selfKey = ecKey('P-256');
    const selfCert = makeCert({ cn: 'Me', key: selfKey, hash: 'sha256', extensions: [[LEAF_OID, NULL], [WWDR_OID, NULL]] });
    await rejects(verifyAppleJWS(makeJWS(transaction(), { x5c: [selfCert], key: selfKey.privateKey }), deps));
    await rejects(
      verifyAppleJWS(makeJWS(transaction(), { x5c: [selfCert, selfCert, selfCert], key: selfKey.privateKey }), deps),
      /trusted root/,
    );
  });

  it('rejects a chain to a non-Apple root carrying the real root bytes at the end', async () => {
    // Attacker's own CA signs an intermediate, then appends the trusted root.
    const evilRoot = makeCA({ cn: 'Evil Root' });
    const evilInt = makeCA({ cn: 'Evil WWDR', issuer: evilRoot, extensions: [[WWDR_OID, NULL]] });
    const evilKey = ecKey('P-256');
    const evilLeaf = makeCert({ cn: 'Evil', key: evilKey, issuer: evilInt, extensions: [[LEAF_OID, NULL]] });
    await rejects(
      verifyAppleJWS(makeJWS(transaction(), { x5c: [evilLeaf, evilInt.der, root.der], key: evilKey.privateKey }), deps),
      /Intermediate not signed/,
    );
    await rejects(
      verifyAppleJWS(makeJWS(transaction(), { x5c: [evilLeaf, evilInt.der, evilRoot.der], key: evilKey.privateKey }), deps),
      /trusted root/,
    );
  });

  it('rejects a signature from a key other than the leaf', async () => {
    await rejects(verifyAppleJWS(makeJWS(transaction(), { key: ecKey('P-256').privateKey }), deps), /Bad JWS signature/);
  });

  it('rejects a tampered payload', async () => {
    const [h, , s] = makeJWS(transaction()).split('.');
    const forged = b64url(JSON.stringify(transaction({ productId: 'other' })));
    await rejects(verifyAppleJWS(`${h}.${forged}.${s}`, deps), /Bad JWS signature/);
  });

  it('rejects certificates without the Apple marker extensions', async () => {
    const plainInt = makeCA({ cn: 'Plain Int', issuer: root });
    const plainLeaf = makeCert({ cn: 'Leaf', key: leafKey, issuer: plainInt, extensions: [[LEAF_OID, NULL]] });
    await rejects(verifyAppleJWS(makeJWS(transaction(), { x5c: [plainLeaf, plainInt.der, root.der] }), deps), /WWDR/);
    const noOidLeaf = makeCert({ cn: 'Leaf', key: leafKey, issuer: intermediate });
    await rejects(verifyAppleJWS(makeJWS(transaction(), { x5c: [noOidLeaf, intermediate.der, root.der] }), deps), /receipt signing/);
  });

  it('checks certificate validity at the signing time', async () => {
    const shortLeaf = makeCert({
      cn: 'Leaf', key: leafKey, issuer: intermediate, extensions: [[LEAF_OID, NULL]],
      notBefore: Date.UTC(2024, 0, 1), notAfter: Date.UTC(2025, 0, 1),
    });
    const x5c = [shortLeaf, intermediate.der, root.der];
    // Signed while the leaf was valid: fine even though it has since expired.
    await verifyAppleJWS(makeJWS(transaction({ signedDate: Date.UTC(2024, 5, 1) }), { x5c }), deps);
    await rejects(verifyAppleJWS(makeJWS(transaction({ signedDate: SIGNED_AT }), { x5c }), deps), /not valid/);
    // No signedDate: falls back to now.
    const noDate = transaction();
    delete noDate.signedDate;
    await rejects(verifyAppleJWS(makeJWS(noDate, { x5c }), { ...deps, now: () => SIGNED_AT }), /not valid/);
  });

  it('rejects other algorithms and garbage', async () => {
    await rejects(verifyAppleJWS(makeJWS(transaction(), { alg: 'none' }), deps), /algorithm/);
    await rejects(verifyAppleJWS('not.a.jws', deps));
    await rejects(verifyAppleJWS(null, deps));
  });
});

describe('verifySignedTransaction', () => {
  it('returns the decoded transaction', async () => {
    const tx = await verifySignedTransaction(makeJWS(transaction()), env, deps);
    assert.equal(tx.productId, 'dev.goodloop.ramble.unlock');
    assert.equal(tx.originalTransactionId, '2000000100');
  });

  it('accepts Sandbox (policy is the caller’s)', async () => {
    const tx = await verifySignedTransaction(makeJWS(transaction({ environment: 'Sandbox' })), env, deps);
    assert.equal(tx.environment, 'Sandbox');
  });

  it('defaults the bundle ID to dev.goodloop.Ramble', async () => {
    await verifySignedTransaction(makeJWS(transaction()), {}, deps);
  });

  it('rejects a wrong bundle ID', async () => {
    await rejects(verifySignedTransaction(makeJWS(transaction({ bundleId: 'com.other.app' })), env, deps), /bundle/);
  });

  it('rejects Xcode and unknown environments', async () => {
    await rejects(verifySignedTransaction(makeJWS(transaction({ environment: 'Xcode' })), env, deps), /Xcode/);
    await rejects(verifySignedTransaction(makeJWS(transaction({ environment: 'LocalTesting' })), env, deps));
    await rejects(verifySignedTransaction(makeJWS(transaction({ environment: undefined })), env, deps));
  });
});

describe('verifyAppTransaction', () => {
  const appTx = (o = {}) => ({
    appTransactionId: '7050000001',
    bundleId: 'dev.goodloop.Ramble',
    originalApplicationVersion: '41',
    originalPurchaseDate: Date.UTC(2025, 0, 1),
    receiptType: 'Production',
    receiptCreationDate: SIGNED_AT,
    ...o,
  });

  it('returns the payload with environment taken from receiptType', async () => {
    const p = await verifyAppTransaction(makeJWS(appTx()), env, deps);
    assert.equal(p.environment, 'Production');
    assert.equal(p.originalApplicationVersion, '41');
  });

  it('rejects Xcode receipts and wrong bundle IDs', async () => {
    await rejects(verifyAppTransaction(makeJWS(appTx({ receiptType: 'Xcode' })), env, deps));
    await rejects(verifyAppTransaction(makeJWS(appTx({ bundleId: 'x' })), env, deps));
  });
});

describe('verifyNotification', () => {
  const note = (data, o = {}) => ({
    notificationType: 'REFUND',
    notificationUUID: 'b1c2',
    signedDate: SIGNED_AT,
    data: { bundleId: 'dev.goodloop.Ramble', environment: 'Production', ...data },
    ...o,
  });

  it('returns the type and the verified nested transaction', async () => {
    const signedTransactionInfo = makeJWS(transaction({ revocationDate: SIGNED_AT }));
    const n = await verifyNotification(makeJWS(note({ signedTransactionInfo })), env, deps);
    assert.equal(n.notificationType, 'REFUND');
    assert.equal(n.subtype, null);
    assert.equal(n.environment, 'Production');
    assert.equal(n.transaction.originalTransactionId, '2000000100');
    assert.equal(n.transaction.revocationDate, SIGNED_AT);
  });

  it('returns transaction null when there is none', async () => {
    const n = await verifyNotification(makeJWS(note({}, { notificationType: 'TEST' })), env, deps);
    assert.equal(n.transaction, null);
  });

  it('rejects a forged nested transaction', async () => {
    const otherKey = ecKey('P-256');
    const selfCert = makeCert({ cn: 'Me', key: otherKey, hash: 'sha256' });
    const signedTransactionInfo = makeJWS(transaction(), { x5c: [selfCert, selfCert, selfCert], key: otherKey.privateKey });
    await rejects(verifyNotification(makeJWS(note({ signedTransactionInfo })), env, deps));
  });

  it('rejects a wrong bundle ID, no data, and a mismatched transaction environment', async () => {
    await rejects(verifyNotification(makeJWS(note({ bundleId: 'x' })), env, deps), /bundle/);
    await rejects(verifyNotification(makeJWS({ notificationType: 'REFUND', signedDate: SIGNED_AT }), env, deps));
    const signedTransactionInfo = makeJWS(transaction({ environment: 'Sandbox' }));
    await rejects(verifyNotification(makeJWS(note({ signedTransactionInfo })), env, deps), /environment/);
  });

  it('rejects a notification not chained to Apple', async () => {
    await rejects(verifyNotification(makeJWS(note({}))), /Apple Root CA - G3/);
  });
});
