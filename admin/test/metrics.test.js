// The dashboard's numbers, against the relay's real schema (specs/admin.md).

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { before, describe, it } from 'node:test';

import { DAY, NOW, createAdmin, createKeys, sign } from './helpers.js';

let keys;
before(async () => {
  keys = await createKeys();
});

function seed(admin) {
  const inbox = (id, usage, createdAt, extra = {}) =>
    admin.exec(
      `INSERT INTO inboxes (id, secret_hash, created_at, usage_id, free_notes_used, purchase_id, phone_app, watch_app, last_upload_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      id,
      `h-${id}`,
      createdAt,
      usage,
      extra.free ?? 0,
      extra.purchase ?? null,
      extra.phone ?? null,
      extra.watch ?? null,
      extra.lastUpload ?? null,
    );
  inbox('inb_a', 'ua', NOW - 40 * DAY, {
    free: 25,
    purchase: 'unlock:1',
    phone: 'Ramble/1.2.1 (30) iOS/26.1',
    watch: 'Ramble/1.2.1 (30) watchOS/26.1',
    lastUpload: NOW - DAY,
  });
  inbox('inb_b', 'ub', NOW - 2 * DAY, { free: 3, phone: 'Ramble/1.2.1 (30) iOS/26.1', lastUpload: NOW - 2 * DAY });
  inbox('inb_c', 'uc', NOW - 3 * 60 * 60 * 1000);

  admin.exec(`INSERT INTO purchases (id, kind, environment, created_at) VALUES ('unlock:1', 'unlock', 'Production', ?)`, NOW - 10 * DAY);
  admin.exec(
    `INSERT INTO purchases (id, kind, environment, created_at, revoked_at) VALUES ('unlock:2', 'unlock', 'Sandbox', ?, ?)`,
    NOW - 3 * DAY,
    NOW - DAY,
  );

  let k = 0;
  const event = (user, recordedAt, extra = {}) => {
    k += 1;
    admin.exec(
      `INSERT INTO note_events (user_id, note_key, source, recorded_at, accepted_at, finished_at, duration, result,
         attempts, hand_retries, free_note, language, filler_removal, vocabulary, app)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 1, ?, ?, ?, NULL)`,
      user,
      `n${k}`,
      extra.source ?? 'watch',
      recordedAt,
      recordedAt + 1000,
      recordedAt + 1000 + (extra.wait ?? 4000),
      extra.duration ?? 60,
      extra.result ?? 'transcript',
      extra.attempts ?? 1,
      extra.language ?? null,
      extra.filler ? 1 : 0,
      extra.vocab ? 1 : 0,
    );
  };
  for (let i = 0; i < 12; i += 1) event('ua', NOW - (i + 1) * 60 * 60 * 1000, { language: i < 2 ? 'es' : null });
  event('ub', NOW - 2 * 60 * 60 * 1000, { source: 'phone', duration: 2400, filler: true });
  event('ub', NOW - 3 * DAY, { source: 'phone', result: 'failed', attempts: 3, wait: 60000 });

  admin.exec(
    `INSERT INTO connections (id, inbox_id, token_hash, created_at, last_pull_at) VALUES ('c1', 'inb_a', 't1', ?, ?)`,
    NOW - 30 * DAY,
    NOW - DAY,
  );
  admin.exec(
    `INSERT INTO connections (id, inbox_id, token_hash, created_at, last_pull_at, via) VALUES ('c2', 'inb_a', 't2', ?, ?, 'mcp')`,
    NOW - 3 * DAY,
    NOW - 60 * 1000,
  );
  admin.exec(
    `INSERT INTO connections (id, inbox_id, token_hash, created_at, last_pull_at, via, hook_url)
     VALUES ('c3', 'inb_b', 't3', ?, ?, 'api', 'https://hooks.example/x')`,
    NOW - 2 * DAY,
    NOW - 20 * DAY,
  );
  admin.exec(`INSERT INTO connections (id, inbox_id, token_hash, created_at, via) VALUES ('c4', 'inb_c', 't4', ?, 'api')`, NOW - DAY);
  admin.exec(`UPDATE inboxes SET webhook = 1 WHERE id = 'inb_a'`);
  admin.exec(`UPDATE inboxes SET webhook = 0 WHERE id = 'inb_b'`);
  admin.exec(
    `INSERT INTO notes (inbox_id, id, source, status, recorded_at, recorded_ms, received_at, accepted_at, content_type, transcript)
     VALUES ('inb_b', 'x', 'phone', 'transcribing', '2026-11-18T14:00:00Z', ?, ?, ?, 'audio/mp4', 'SECRET WORDS')`,
    NOW - 45 * 60 * 1000,
    NOW - 45 * 60 * 1000,
    NOW - 45 * 60 * 1000,
  );
  admin.exec(`INSERT INTO usage (user_id, month, seconds) VALUES ('unlock:1', '2026-11', 400000)`);
  admin.exec(`INSERT INTO error_counts (minute, n) VALUES (?, 3)`, Math.floor(NOW / 60000) - 5);
}

describe('metrics', () => {
  it('reports totals, activity, funnel and health', async () => {
    const admin = createAdmin([keys]);
    seed(admin);
    const res = await admin.get('/api/overview', await sign(keys));
    assert.equal(res.status, 200);
    const d = await res.json();

    assert.deepEqual(d.totals, {
      installs: 3,
      installs_last_7_days: 2,
      users_with_notes: 2,
      notes: 14,
      notes_last_7_days: 14,
      hours: 0.9,
      unlocked_installs: 1,
      agents_connected: 4,
      installs_with_agent: 3,
      agents_pulled_last_7_days: 2,
    });
    assert.deepEqual(d.active_users, { day: 2, week: 2, month: 2 });
    assert.deepEqual(
      d.funnel.map((f) => f.n),
      [3, 2, 1, 1, 1],
    );
    assert.equal(d.daily.length, 30);
    assert.equal(d.daily.at(-1).day, '2026-11-18');
    assert.equal(d.weekly.length, 12);
    assert.equal(d.daily.reduce((s, x) => s + x.notes, 0), 14);
    assert.equal(d.daily.reduce((s, x) => s + x.signups, 0), 2);

    assert.deepEqual(
      d.purchases.map((p) => [p.environment, p.n, p.revoked]).sort(),
      [
        ['Production', 1, 0],
        ['Sandbox', 1, 1],
      ],
    );
    const failed = d.reliability_7_days.find((r) => r.result === 'failed');
    assert.deepEqual(failed, { result: 'failed', notes: 1, first_try: 0, avg_wait_s: 60, max_wait_s: 60 });
    assert.equal(d.devices_30_days.find((x) => x.source === 'phone').over_30_min, 1);
    assert.deepEqual(d.settings_30_days, { notes: 14, language_set: 2, filler_removal: 1, vocabulary: 0 });
    assert.deepEqual(d.apps_30_days.phone, [{ label: 'Ramble/1.2.1 (30) iOS/26.1', installs: 2 }]);
    assert.deepEqual(d.health, {
      waiting_to_transcribe: 1,
      oldest_waiting_minutes: 45,
      server_errors_last_hour: 3,
      suspended_installs: 0,
      suspended_purchases: 0,
    });
    assert.deepEqual(
      d.delivery.agents.map((m) => [m.method, m.agents, m.pulled_last_7_days, m.installs]),
      [
        ['mcp', 1, 1, 1],
        ['hook', 1, 0, 1],
        ['poll', 0, 0, 0],
        ['unknown', 1, 1, 1],
        ['never', 1, 0, 1],
      ],
    );
    assert.deepEqual(d.delivery.webhook, {
      on: 1,
      off: 1,
      not_reported: 1,
      active_30_days: { on: 1, off: 1, not_reported: 0 },
    });
    assert.deepEqual(d.heaviest_this_month, [{ user: 'unlock:1', hours: 111.1, over_line: true }]);
  });

  it('never shows anyone’s words', async () => {
    const admin = createAdmin([keys]);
    seed(admin);
    const token = await sign(keys);
    for (const path of ['/', '/api/overview']) {
      const body = await (await admin.get(path, token)).text();
      assert.doesNotMatch(body, /SECRET WORDS/);
      assert.doesNotMatch(body, /inb_[abc]/);
    }
    const sql = readFileSync(new URL('../src/metrics.js', import.meta.url), 'utf8');
    // note_events.vocabulary is an on/off flag; the words live on inboxes and
    // in notes.options, which this file never reads.
    for (const column of ['transcript', 'entries', 'options', 'secret_hash', 'token_hash', 'note_key', 'last_error']) {
      assert.ok(!sql.includes(column), `metrics.js mentions ${column}`);
    }
  });

  it('flags a note stuck for 30 minutes or more', async () => {
    const admin = createAdmin([keys]);
    seed(admin);
    const html = await (await admin.get('/', await sign(keys))).text();
    assert.match(html, /Needs a look/);
    assert.match(html, /oldest 45 min/);
    assert.match(html, /over 50 h/);
    assert.match(html, /How agents get notes/);
    assert.match(html, /data-tip="Nov 18: 13 notes"/);
    assert.doesNotMatch(html, /hooks\.example/);
  });

  it('renders an empty database', async () => {
    const admin = createAdmin([keys]);
    const res = await admin.get('/', await sign(keys));
    assert.equal(res.status, 200);
    const html = await res.text();
    assert.match(html, /Nothing yet/);
    assert.match(html, /All clear/);
  });
});
