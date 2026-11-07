// Inboxes, account state, purchases, binding, refunds, settings.
// specs/relay-api.md "Phone setup and purchase", specs/purchase.md.

import assert from 'node:assert/strict';
import { beforeEach, describe, it } from 'node:test';

import { DAY, HOUR, PREMIUM, T0, UNLOCK, createHarness, jws, noteId, unlockTx } from './harness.js';

let h;
beforeEach(() => {
  h = createHarness();
});

const account = async (auth) => (await h.call('GET', '/account', { auth })).body;
const entitle = (auth, body) => h.call('POST', '/entitlement', { auth, body });

describe('creating an inbox', () => {
  it('needs an assertion, and returns a secret and an account token', async () => {
    assert.equal((await h.call('POST', '/inboxes', { headers: { 'X-App-Attest': '' } })).status, 403);
    h.attestOK = false;
    const failed = await h.call('POST', '/inboxes');
    assert.equal(failed.status, 403);
    assert.equal(failed.body.error, 'App attestation failed');
    h.attestOK = true;
    const { inbox_secret, account_token } = await h.newInbox();
    assert.match(inbox_secret, /^rmbi_/);
    assert.match(account_token, /^[0-9a-f-]{36}$/);
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

  it('answers 503 once 2,000 inboxes were made today, except for a buyer', async () => {
    const insert = h.db.sqlite.prepare('INSERT INTO inboxes (id, secret_hash, created_at) VALUES (?, ?, ?)');
    for (let i = 0; i < 2000; i++) insert.run(`inb_${i}`, `h${i}`, T0);
    const capped = await h.call('POST', '/inboxes', { headers: { 'X-App-Attest-Key-Id': 'k2' } });
    assert.equal(capped.status, 503);
    assert.equal(capped.body.reason, 'unavailable');
    assert.ok(h.alerts.some((a) => a.includes('2000 inboxes')));

    // A buyer restoring on a new iPhone: the purchase is already known.
    const first = h.db.sqlite.prepare("INSERT INTO purchases (id, kind, environment, created_at) VALUES ('unlock:otx1', 'unlock', 'Production', ?)");
    first.run(T0);
    const buyer = await h.call('POST', '/inboxes', {
      headers: { 'X-App-Attest-Key-Id': 'k3' },
      body: { signed_transaction: unlockTx('someone-elses-token') },
    });
    assert.equal(buyer.status, 201);
    assert.equal((await account(buyer.body.inbox_secret)).unlocked, true);

    // Not early-buyer proof: still capped, never a 403.
    const plain = await h.call('POST', '/inboxes', {
      headers: { 'X-App-Attest-Key-Id': 'k4' },
      body: { app_transaction: jws({ receiptType: 'Production', appTransactionId: 'a1', originalApplicationVersion: '90' }) },
    });
    assert.equal(plain.status, 503);
  });

  it('a verified proof that will not bind is capped like any request, and creates nothing', async () => {
    const insert = h.db.sqlite.prepare('INSERT INTO inboxes (id, secret_hash, created_at) VALUES (?, ?, ?)');
    for (let i = 0; i < 2000; i++) insert.run(`inb_${i}`, `h${i}`, T0);
    const count = () => h.rows('SELECT COUNT(*) AS n FROM inboxes')[0].n;

    // A first-time unlock bought for another inbox: wrong_account.
    const wrong = await h.call('POST', '/inboxes', {
      headers: { 'X-App-Attest-Key-Id': 'k2' },
      body: { signed_transaction: unlockTx('someone-elses-token') },
    });
    assert.equal(wrong.status, 503);
    assert.equal(wrong.body.reason, 'unavailable');
    assert.equal(count(), 2000);

    // A known purchase already on 5 iPhones: too_many_inboxes.
    h.db.sqlite.prepare("INSERT INTO purchases (id, kind, environment, created_at) VALUES ('unlock:otx1', 'unlock', 'Production', ?)").run(T0);
    h.db.sqlite.exec("UPDATE inboxes SET purchase_id = 'unlock:otx1', bound_at = created_at WHERE id IN ('inb_0', 'inb_1', 'inb_2', 'inb_3', 'inb_4')");
    const full = await h.call('POST', '/inboxes', {
      headers: { 'X-App-Attest-Key-Id': 'k3' },
      body: { signed_transaction: unlockTx('someone-elses-token') },
    });
    assert.equal(full.status, 503);
    assert.equal(count(), 2000);
  });

  it('a proof that will not bind under the cap gets a normal free inbox', async () => {
    const res = await h.call('POST', '/inboxes', {
      headers: { 'X-App-Attest-Key-Id': 'k2' },
      body: { signed_transaction: unlockTx('someone-elses-token') },
    });
    assert.equal(res.status, 201);
    const a = await account(res.body.inbox_secret);
    assert.equal(a.unlocked, false);
    assert.equal(a.free_notes_remaining, 25);
  });

  it('a proof that will not bind is refused while the free-tier breaker is tripped', async () => {
    await h.inbox();
    h.db.sqlite.exec(`INSERT INTO notes (inbox_id, id, source, status, recorded_at, recorded_ms, received_at, accepted_at, content_type, duration, free_note)
      SELECT id, 'X', 'phone', 'done', '', 0, ${T0}, ${T0}, 'audio/mp4', ${200 * 3600}, 1 FROM inboxes`);
    const res = await h.call('POST', '/inboxes', {
      headers: { 'X-App-Attest-Key-Id': 'k2' },
      body: { signed_transaction: unlockTx('someone-elses-token') },
    });
    assert.equal(res.status, 503);
    assert.equal(h.rows('SELECT COUNT(*) AS n FROM inboxes')[0].n, 1);
  });

  it('answers 503 once free inboxes used 200 hours today', async () => {
    const secret = await h.inbox();
    h.db.sqlite.exec(`INSERT INTO notes (inbox_id, id, source, status, recorded_at, recorded_ms, received_at, accepted_at, content_type, duration, free_note)
      SELECT id, 'X', 'phone', 'done', '', 0, ${T0}, ${T0}, 'audio/mp4', ${200 * 3600}, 1 FROM inboxes`);
    const res = await h.call('POST', '/inboxes', { headers: { 'X-App-Attest-Key-Id': 'k2' } });
    assert.equal(res.status, 503);
    assert.ok(h.alerts.some((a) => a.includes('200 hours')));
    assert.ok(secret);
  });

  it('limits 3 a day per App Attest key', async () => {
    for (let i = 0; i < 3; i++) assert.equal((await h.call('POST', '/inboxes')).status, 201);
    const res = await h.call('POST', '/inboxes');
    assert.equal(res.status, 429);
    assert.equal(res.body.reason, 'rate_limited');
  });
});

describe('account state', () => {
  it('starts with 25 free notes; the watch gets no account token', async () => {
    const { inbox_secret: secret, account_token } = await h.newInbox();
    assert.deepEqual(await account(secret), {
      unlocked: false,
      free_notes_total: 25,
      free_notes_remaining: 25,
      account_token,
    });
    const watch = await h.watchToken(secret);
    assert.equal((await account(watch)).account_token, undefined);
  });

  it('shows no usage for an unlocked inbox', async () => {
    const { inbox_secret: secret, account_token: token } = await h.newInbox();
    await entitle(secret, { signed_transaction: unlockTx(token) });
    h.db.sqlite.exec(`INSERT INTO usage (user_id, month, seconds) VALUES ('unlock:otx1', '2026-11', ${141 * 3600})`);
    assert.deepEqual(await account(secret), {
      unlocked: true,
      free_notes_total: 25,
      free_notes_remaining: 25,
      account_token: token,
    });
  });

  it('gives old inboxes an account token on first read', async () => {
    const secret = await h.inbox();
    h.db.sqlite.exec('UPDATE inboxes SET account_token = NULL');
    assert.match((await account(secret)).account_token, /^[0-9a-f-]{36}$/);
  });
});

describe('purchases', () => {
  it('unlocks with a verified unlock purchase; re-sending changes nothing', async () => {
    const { inbox_secret: secret, account_token: token } = await h.newInbox();
    const res = await entitle(secret, { signed_transaction: unlockTx(token.toUpperCase()) });
    assert.equal(res.status, 200);
    assert.equal(res.body.unlocked, true);
    assert.equal((await entitle(secret, { signed_transaction: unlockTx(token) })).status, 200);
    assert.equal(h.rows('SELECT COUNT(*) AS n FROM purchases')[0].n, 1);
  });

  it('rejects forged, refunded, Xcode, family-shared and other products as invalid_transaction', async () => {
    const { inbox_secret: secret, account_token: token } = await h.newInbox();
    for (const record of [
      'forged',
      unlockTx(token, { revocationDate: T0 }),
      unlockTx(token, { environment: 'Xcode' }),
      unlockTx(token, { inAppOwnershipType: 'FAMILY_SHARED' }),
      unlockTx(token, { productId: 'dev.goodloop.something' }),
    ]) {
      const res = await entitle(secret, { signed_transaction: record });
      assert.equal(res.status, 403);
      assert.equal(res.body.reason, 'invalid_transaction');
    }
    assert.equal((await account(secret)).unlocked, false);
  });

  it('a first purchase made for another inbox is wrong_account; a restore is fine', async () => {
    const a = await h.newInbox();
    const b = await h.newInbox();
    const wrong = await entitle(b.inbox_secret, { signed_transaction: unlockTx(a.account_token) });
    assert.equal(wrong.status, 403);
    assert.equal(wrong.body.reason, 'wrong_account');
    assert.equal((await entitle(a.inbox_secret, { signed_transaction: unlockTx(a.account_token) })).status, 200);
    assert.equal((await entitle(b.inbox_secret, { signed_transaction: unlockTx(a.account_token) })).status, 200);
  });

  it('unlocks at most 5 inboxes per purchase, counting fresh bindings, freeing a spot after 90 days', async () => {
    const first = await h.newInbox();
    await entitle(first.inbox_secret, { signed_transaction: unlockTx(first.account_token) });
    for (let i = 0; i < 4; i++) {
      h.now += 1000;
      const restore = await h.newInboxWithKey(i);
      assert.equal((await entitle(restore, { signed_transaction: unlockTx(first.account_token) })).status, 200);
    }
    const sixth = await h.newInboxWithKey(9);
    const refused = await entitle(sixth, { signed_transaction: unlockTx(first.account_token) });
    assert.equal(refused.status, 403);
    assert.equal(refused.body.reason, 'too_many_inboxes');

    h.now = T0 + 91 * DAY;
    assert.equal((await entitle(sixth, { signed_transaction: unlockTx(first.account_token) })).status, 200);
  });

  it('a sandbox purchase (TestFlight, App Review) unlocks for good', async () => {
    const { inbox_secret: secret, account_token: token } = await h.newInbox();
    await entitle(secret, { signed_transaction: unlockTx(token, { environment: 'Sandbox' }) });
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

  it('early subscribers: active at FREE_RELEASE_AT unlocks; lapsed does not', async () => {
    const release = Date.UTC(2026, 10, 10);
    h.envExtra = { FREE_RELEASE_AT: new Date(release).toISOString() };
    const secret = await h.inbox();
    const sub = (expiresDate) =>
      jws({ productId: PREMIUM, originalTransactionId: 's1', environment: 'Production', originalPurchaseDate: release - 100 * DAY, expiresDate });
    assert.equal((await entitle(secret, { signed_transaction: sub(release - 30 * DAY) })).status, 403);
    assert.equal((await entitle(secret, { signed_transaction: sub(release + 20 * DAY) })).body.unlocked, true);
  });
});

describe('refunds', () => {
  const refund = (otx, extra = {}) =>
    h.call('POST', '/appstore/notifications', {
      body: { signedPayload: jws({ notificationType: 'REFUND', environment: 'Production', transaction: { productId: UNLOCK, originalTransactionId: otx }, ...extra }) },
    });

  it('locks every bound inbox, keeps used free notes, and rejects the record from then on', async () => {
    const a = await h.newInbox();
    const b = await h.newInboxWithKey(1);
    for (let i = 1; i <= 25; i++) await h.upload(a.inbox_secret, noteId(i));
    await entitle(a.inbox_secret, { signed_transaction: unlockTx(a.account_token) });
    await entitle(b, { signed_transaction: unlockTx(a.account_token) });
    assert.equal((await h.upload(a.inbox_secret, noteId(30))).status, 201);

    assert.equal((await refund('otx1')).status, 200);
    const after = await account(a.inbox_secret);
    assert.equal(after.unlocked, false);
    assert.equal(after.free_notes_remaining, 0);
    assert.equal((await account(b)).free_notes_remaining, 25);
    const held = await h.upload(a.inbox_secret, noteId(31));
    assert.equal(held.status, 402);
    assert.equal(held.body.reason, 'free_notes_used');
    assert.equal((await entitle(a.inbox_secret, { signed_transaction: unlockTx(a.account_token) })).body.reason, 'invalid_transaction');
  });

  it('answers 400 to anything unsigned or for another environment', async () => {
    assert.equal((await h.call('POST', '/appstore/notifications', { body: { signedPayload: 'forged' } })).status, 400);
    assert.equal((await h.call('POST', '/appstore/notifications', { body: {} })).status, 400);
    assert.equal((await refund('otx1', { environment: 'Sandbox' })).status, 400);
    assert.equal(h.rows('SELECT COUNT(*) AS n FROM purchases')[0].n, 0);
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

it('limits entitlement submissions to 20 an hour per inbox', async () => {
  const secret = await h.inbox();
  for (let i = 0; i < 20; i++) await entitle(secret, { signed_transaction: 'forged' });
  assert.equal((await entitle(secret, { signed_transaction: 'forged' })).status, 429);
  h.now = T0 + HOUR;
  assert.equal((await entitle(secret, { signed_transaction: 'forged' })).status, 403);
});
