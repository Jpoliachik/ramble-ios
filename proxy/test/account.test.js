// Inboxes, account state, purchases, binding, revoking, settings.
// specs/relay-api.md "Phone setup and purchase", specs/purchase.md.

import assert from 'node:assert/strict';
import { beforeEach, describe, it } from 'node:test';

import { DAY, PREMIUM, T0, createHarness, jws, noteId, unlockTx } from './harness.js';

let h;
beforeEach(() => {
  h = createHarness();
});

const account = async (auth) => (await h.call('GET', '/account', { auth })).body;
const entitle = (auth, body) => h.call('POST', '/entitlement', { auth, body });

describe('creating an inbox', () => {
  it('needs an assertion, and returns a secret', async () => {
    assert.equal((await h.call('POST', '/inboxes', { headers: { 'X-App-Attest': '' } })).status, 403);
    h.attestOK = false;
    const failed = await h.call('POST', '/inboxes');
    assert.equal(failed.status, 403);
    assert.equal(failed.body.error, 'App attestation failed');
    h.attestOK = true;
    const { inbox_secret } = await h.newInbox();
    assert.match(inbox_secret, /^rmbi_/);
    assert.ok(!JSON.stringify(h.rows('SELECT * FROM inboxes')).includes(inbox_secret));
  });

  it('honors no developer bypass outside a local development relay', async () => {
    h.attestOK = false;
    const key = 'local-dev-key-0123456789';
    h.envExtra = { DEV_BYPASS_KEY: key };
    assert.equal((await h.call('POST', '/inboxes', { headers: { 'X-Dev-Bypass': key } })).status, 403);
    h.envExtra = { DEV_BYPASS_KEY: key, ENVIRONMENT: 'production' };
    assert.equal((await h.call('POST', '/inboxes', { headers: { 'X-Dev-Bypass': key } })).status, 403);
    h.envExtra = { ENVIRONMENT: 'development' };
    assert.equal((await h.call('POST', '/inboxes', { headers: { 'X-Dev-Bypass': key } })).status, 403);
  });

  it('takes the bypass key on a local development relay', async () => {
    h.attestOK = false;
    const key = 'local-dev-key-0123456789';
    h.envExtra = { DEV_BYPASS_KEY: key, ENVIRONMENT: 'development' };
    assert.equal((await h.call('POST', '/inboxes', { headers: { 'X-Dev-Bypass': 'wrong-key-0123456789' } })).status, 403);
    const res = await h.call('POST', '/inboxes', { headers: { 'X-Dev-Bypass': key } });
    assert.equal(res.status, 201);
    assert.match(res.body.inbox_secret, /^rmbi_/);
  });

  it('starts every inbox free, whatever the body carries', async () => {
    const res = await h.call('POST', '/inboxes', {
      headers: { 'X-App-Attest-Key-Id': 'k2' },
      body: { signed_transaction: unlockTx() },
    });
    assert.equal(res.status, 201);
    assert.deepEqual(Object.keys(res.body), ['inbox_secret']);
    const a = await account(res.body.inbox_secret);
    assert.equal(a.unlocked, false);
    assert.equal(a.free_notes_remaining, 25);
  });

  it('limits 3 a day per App Attest key', async () => {
    for (let i = 0; i < 3; i++) assert.equal((await h.call('POST', '/inboxes')).status, 201);
    const res = await h.call('POST', '/inboxes');
    assert.equal(res.status, 429);
    assert.equal(res.body.reason, 'rate_limited');
  });
});

describe('account state', () => {
  it('starts with 25 free notes, the same for phone and watch', async () => {
    const secret = await h.inbox();
    const expected = { unlocked: false, free_notes_total: 25, free_notes_remaining: 25 };
    assert.deepEqual(await account(secret), expected);
    assert.deepEqual(await account(await h.watchToken(secret)), expected);
  });

  it('shows no usage for an unlocked inbox', async () => {
    const secret = await h.inbox();
    await entitle(secret, { signed_transaction: unlockTx() });
    h.db.sqlite.exec(`INSERT INTO usage (user_id, month, seconds) VALUES ('unlock:otx1', '2026-11', ${141 * 3600})`);
    assert.deepEqual(await account(secret), { unlocked: true, free_notes_total: 25, free_notes_remaining: 25 });
  });
});

describe('purchases', () => {
  it('unlocks with a verified unlock purchase; re-sending changes nothing', async () => {
    const secret = await h.inbox();
    const res = await entitle(secret, { signed_transaction: unlockTx() });
    assert.equal(res.status, 200);
    assert.equal(res.body.unlocked, true);
    assert.equal((await entitle(secret, { signed_transaction: unlockTx() })).status, 200);
    assert.equal(h.rows('SELECT COUNT(*) AS n FROM purchases')[0].n, 1);
  });

  it('rejects forged, refunded, Xcode, family-shared and other products as invalid_transaction', async () => {
    const secret = await h.inbox();
    for (const record of [
      'forged',
      unlockTx({ revocationDate: T0 }),
      unlockTx({ environment: 'Xcode' }),
      unlockTx({ inAppOwnershipType: 'FAMILY_SHARED' }),
      unlockTx({ productId: 'dev.goodloop.something' }),
    ]) {
      const res = await entitle(secret, { signed_transaction: record });
      assert.equal(res.status, 403);
      assert.equal(res.body.reason, 'invalid_transaction');
    }
    assert.equal((await account(secret)).unlocked, false);
  });

  it('unlocks at most 10 inboxes ever per purchase, from any inbox, until the operator raises its cap', async () => {
    for (let i = 0; i < 10; i++) {
      assert.equal((await entitle(await h.inbox(), { signed_transaction: unlockTx() })).status, 200);
    }
    const eleventh = await h.inbox();
    const refused = await entitle(eleventh, { signed_transaction: unlockTx() });
    assert.equal(refused.status, 403);
    assert.equal(refused.body.reason, 'too_many_inboxes');

    // Time frees nothing; the operator's inbox_cap does.
    h.now = T0 + 365 * DAY;
    assert.equal((await entitle(eleventh, { signed_transaction: unlockTx() })).status, 403);
    h.db.sqlite.exec("UPDATE purchases SET inbox_cap = 11 WHERE id = 'unlock:otx1'");
    assert.equal((await entitle(eleventh, { signed_transaction: unlockTx() })).status, 200);
  });

  it('a sandbox purchase (TestFlight, App Review) unlocks for good', async () => {
    const secret = await h.inbox();
    await entitle(secret, { signed_transaction: unlockTx({ environment: 'Sandbox' }) });
    assert.equal((await account(secret)).unlocked, true);
    h.now = T0 + 60 * DAY;
    assert.equal((await account(secret)).unlocked, true);
  });

  it('early buyers: a production download below FIRST_FREE_BUILD unlocks; sandbox and later builds do not', async () => {
    h.envExtra = { FIRST_FREE_BUILD: '120' };
    const secret = await h.inbox();
    const app = (extra) => jws({ receiptType: 'Production', appTransactionId: 'app1', originalApplicationVersion: '87', ...extra });
    for (const bad of [app({ receiptType: 'Sandbox', originalApplicationVersion: '1.0' }), app({ originalApplicationVersion: '120' }), app({ originalApplicationVersion: '87.1' })]) {
      const res = await entitle(secret, { app_transaction: bad });
      assert.equal(res.status, 403);
      assert.equal(res.body.reason, 'invalid_transaction');
    }
    const ok = await entitle(secret, { app_transaction: app() });
    assert.equal(ok.status, 200);
    assert.equal(ok.body.unlocked, true);
  });

  it('early subscribers: any production record of the old subscription unlocks, lapsed or not; sandbox does not', async () => {
    const sub = (extra) =>
      jws({ productId: PREMIUM, originalTransactionId: 's1', environment: 'Production', expiresDate: T0 - 300 * DAY, ...extra });
    const secret = await h.inbox();
    const sandbox = await entitle(secret, { signed_transaction: sub({ environment: 'Sandbox' }) });
    assert.equal(sandbox.status, 403);
    assert.equal(sandbox.body.reason, 'invalid_transaction');
    assert.equal((await entitle(secret, { signed_transaction: sub({ revocationDate: T0 }) })).status, 403);
    assert.equal((await entitle(secret, { signed_transaction: sub() })).body.unlocked, true);
  });
});

describe('revoking a purchase by hand', () => {
  // The command in docs/operations.md.
  const revoke = (otx) =>
    h.db.sqlite.exec(`UPDATE purchases SET revoked_at = CAST(strftime('%s', 'now') AS INTEGER) * 1000 WHERE id = 'unlock:${otx}'`);

  it('locks every bound inbox, keeps used free notes, and rejects the record from then on', async () => {
    const a = await h.newInbox();
    const b = await h.newInboxWithKey(1);
    for (let i = 1; i <= 25; i++) await h.upload(a.inbox_secret, noteId(i));
    await entitle(a.inbox_secret, { signed_transaction: unlockTx(a.account_token) });
    await entitle(b, { signed_transaction: unlockTx(a.account_token) });
    assert.equal((await h.upload(a.inbox_secret, noteId(30))).status, 201);

    revoke('otx1');
    const after = await account(a.inbox_secret);
    assert.equal(after.unlocked, false);
    assert.equal(after.free_notes_remaining, 0);
    assert.equal((await account(b)).free_notes_remaining, 25);
    const held = await h.upload(a.inbox_secret, noteId(31));
    assert.equal(held.status, 402);
    assert.equal(held.body.reason, 'free_notes_used');
    assert.equal((await entitle(a.inbox_secret, { signed_transaction: unlockTx(a.account_token) })).body.reason, 'invalid_transaction');
  });

  it('has no App Store notification endpoint', async () => {
    assert.equal((await h.call('POST', '/appstore/notifications', { body: {} })).status, 404);
  });
});

describe('settings', () => {
  it('round-trips, and a bad field changes nothing', async () => {
    const secret = await h.inbox();
    assert.deepEqual((await h.call('GET', '/settings', { auth: secret })).body, { language: null, remove_filler_words: false, vocabulary: '' });
    const put = await h.call('PUT', '/settings', { auth: secret, body: { language: 'haw', remove_filler_words: true, vocabulary: 'Goodloop' } });
    assert.deepEqual(put.body, { language: 'haw', remove_filler_words: true, vocabulary: 'Goodloop' });
    const bad = await h.call('PUT', '/settings', { auth: secret, body: { language: 'haw', remove_filler_words: true, vocabulary: 'x'.repeat(901) } });
    assert.equal(bad.status, 400);
    assert.equal((await h.call('PUT', '/settings', { auth: secret, body: { language: 'english' } })).status, 400);
    assert.equal((await h.call('GET', '/settings', { auth: secret })).body.language, 'haw');
  });
});
