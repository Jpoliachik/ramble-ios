import { beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import { clientAddress, hit, peek, purgeRateLimits } from '../src/ratelimit.js';
import { createTestDB } from './d1.js';

const HOUR = 3600;
const T0 = Date.UTC(2026, 10, 6, 10, 0, 0); // on an hour boundary

let db;
beforeEach(() => {
  db = createTestDB();
});

describe('rate limiter', () => {
  it('allows `limit` hits per window, then answers with Retry-After until the window ends', async () => {
    for (let i = 0; i < 3; i++) assert.deepEqual(await hit(db, 'notes:abc:h', 3, HOUR, T0 + i), { ok: true });
    const over = await hit(db, 'notes:abc:h', 3, HOUR, T0 + 10 * 60 * 1000);
    assert.deepEqual(over, { ok: false, retryAfter: 50 * 60 });
    // Next window starts fresh.
    assert.deepEqual(await hit(db, 'notes:abc:h', 3, HOUR, T0 + HOUR * 1000), { ok: true });
  });

  it('keeps keys separate', async () => {
    assert.equal((await hit(db, 'a', 1, HOUR, T0)).ok, true);
    assert.equal((await hit(db, 'a', 1, HOUR, T0)).ok, false);
    assert.equal((await hit(db, 'b', 1, HOUR, T0)).ok, true);
  });

  it('peek reads without counting', async () => {
    for (let i = 0; i < 5; i++) assert.equal((await peek(db, 'pair:x', 2, HOUR, T0)).ok, true);
    await hit(db, 'pair:x', 2, HOUR, T0);
    assert.equal((await peek(db, 'pair:x', 2, HOUR, T0)).ok, true);
    await hit(db, 'pair:x', 2, HOUR, T0);
    const r = await peek(db, 'pair:x', 2, HOUR, T0 + 1000);
    assert.equal(r.ok, false);
    assert.equal(r.retryAfter, HOUR - 1);
  });

  it('never stores the raw key, so network addresses stay out of the table', async () => {
    await hit(db, 'attest:203.0.113.7:h', 20, HOUR, T0);
    const rows = db.sqlite.prepare('SELECT * FROM rate_limits').all();
    assert.equal(rows.length, 1);
    assert.match(rows[0].key, /^[0-9a-f]{64}$/);
    assert.ok(!JSON.stringify(rows).includes('203.0.113.7'));
  });

  it('purges counters whose window has ended', async () => {
    await hit(db, 'm', 10, 60, T0);
    await hit(db, 'h', 10, HOUR, T0);
    assert.equal(await purgeRateLimits(db, T0 + 61 * 1000), 1);
    assert.equal(db.sqlite.prepare('SELECT COUNT(*) AS n FROM rate_limits').get().n, 1);
  });

  it('fails closed: throws when the store errors or is missing', async () => {
    const broken = { prepare() { throw new Error('D1 down'); } };
    await assert.rejects(hit(broken, 'k', 1, 60, T0), /D1 down/);
    await assert.rejects(peek(broken, 'k', 1, 60, T0), /D1 down/);
    await assert.rejects(hit(undefined, 'k', 1, 60, T0));
  });

  it('reads the client address from CF-Connecting-IP', () => {
    const r = new Request('https://relay.test/', { headers: { 'CF-Connecting-IP': '198.51.100.2' } });
    assert.equal(clientAddress(r), '198.51.100.2');
    assert.equal(clientAddress(new Request('https://relay.test/')), 'unknown');
  });
});
