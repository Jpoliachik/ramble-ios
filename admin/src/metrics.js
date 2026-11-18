// Read-only metrics from the relay's D1 database. Every query is a SELECT over
// counts and labels: never the text of a note or an agent copy, vocabulary
// words, credentials or note IDs. The privacy test in test/metrics.test.js
// checks this file for those columns and tables. Times in the database are Unix ms, days
// are UTC.

const DAY = 24 * 60 * 60 * 1000;
const FREE_NOTES = 25; // specs/purchase.md "Free notes"
const HEAVY_HOURS = 100; // internal heavy-use line (specs/purchase.md); admin only

const AGENT_METHODS = [
  ['mcp', 'MCP connector'],
  ['hook', 'Relay API, wake-up hook'],
  ['poll', 'Relay API, polling'],
  ['unknown', 'Not seen since tracking began'],
  ['never', "Hasn't checked in"],
];

const utcDay = (ms) => new Date(ms).toISOString().slice(0, 10);

async function all(db, sql, ...params) {
  const { results } = await db.prepare(sql).bind(...params).all();
  return results;
}

async function one(db, sql, ...params) {
  return (await db.prepare(sql).bind(...params).first()) || {};
}

const num = (v) => Number(v ?? 0);
const round = (v, places = 1) => (v == null ? null : Math.round(Number(v) * 10 ** places) / 10 ** places);

/** Everything the dashboard shows, as one plain object (also the JSON API). */
export async function overview(db, now = Date.now()) {
  const d1 = now - DAY;
  const d7 = now - 7 * DAY;
  const d30 = now - 30 * DAY;
  const todayStart = Date.parse(`${utcDay(now)}T00:00:00Z`);
  const days30Start = todayStart - 29 * DAY;
  const weeksStart = todayStart - 12 * 7 * DAY;
  const month = utcDay(now).slice(0, 7);

  const [
    installs,
    notes,
    active,
    agents,
    unlocked,
    purchases,
    suspended,
    signupsByDay,
    notesByDay,
    weekly,
    funnel,
    devices,
    results,
    live,
    errors,
    settings,
    phoneApps,
    watchApps,
    heavy,
    agentMethods,
    webhooks,
  ] = await Promise.all([
    one(db, 'SELECT COUNT(*) AS n, SUM(created_at >= ?) AS last7 FROM inboxes', d7),
    one(
      db,
      `SELECT COUNT(*) AS n, SUM(duration) AS seconds, COUNT(DISTINCT user_id) AS users,
              SUM(recorded_at >= ?) AS last7
       FROM note_events`,
      d7,
    ),
    one(
      db,
      `SELECT COUNT(DISTINCT CASE WHEN recorded_at >= ? THEN user_id END) AS dau,
              COUNT(DISTINCT CASE WHEN recorded_at >= ? THEN user_id END) AS wau,
              COUNT(DISTINCT user_id) AS mau
       FROM note_events WHERE recorded_at >= ?`,
      d1,
      d7,
      d30,
    ),
    one(
      db,
      `SELECT COUNT(*) AS n, COUNT(DISTINCT inbox_id) AS inboxes, SUM(last_pull_at >= ?) AS pulled7
       FROM connections`,
      d7,
    ),
    one(
      db,
      `SELECT COUNT(*) AS n FROM inboxes i JOIN purchases p ON p.id = i.purchase_id
       WHERE p.revoked_at IS NULL`,
    ),
    all(
      db,
      `SELECT kind, environment, COUNT(*) AS n, SUM(revoked_at IS NOT NULL) AS revoked, SUM(created_at >= ?) AS last7
       FROM purchases GROUP BY kind, environment ORDER BY n DESC`,
      d7,
    ),
    one(
      db,
      `SELECT (SELECT COUNT(*) FROM inboxes WHERE suspended = 1) AS inboxes,
              (SELECT COUNT(*) FROM purchases WHERE suspended = 1) AS purchases`,
    ),
    all(
      db,
      `SELECT date(created_at / 1000, 'unixepoch') AS day, COUNT(*) AS n
       FROM inboxes WHERE created_at >= ? GROUP BY day`,
      days30Start,
    ),
    all(
      db,
      `SELECT date(recorded_at / 1000, 'unixepoch') AS day, COUNT(*) AS notes,
              COUNT(DISTINCT user_id) AS users, SUM(duration) AS seconds
       FROM note_events WHERE recorded_at >= ? GROUP BY day`,
      days30Start,
    ),
    all(
      db,
      `SELECT CAST((recorded_at - ?) / ? AS INTEGER) AS week, COUNT(*) AS notes, COUNT(DISTINCT user_id) AS users
       FROM note_events WHERE recorded_at >= ? GROUP BY week`,
      weeksStart,
      7 * DAY,
      weeksStart,
    ),
    one(
      db,
      `SELECT COUNT(*) AS installs,
              SUM(COALESCE(c.n, 0) >= 1) AS first_note,
              SUM(COALESCE(c.n, 0) >= 10) AS ten_notes,
              SUM(i.free_notes_used >= ?) AS used_free,
              SUM(p.id IS NOT NULL AND p.revoked_at IS NULL) AS unlocked
       FROM inboxes i
       LEFT JOIN (SELECT user_id, COUNT(*) AS n FROM note_events GROUP BY user_id) c ON c.user_id = i.usage_id
       LEFT JOIN purchases p ON p.id = i.purchase_id`,
      FREE_NOTES,
    ),
    all(
      db,
      `SELECT source, COUNT(*) AS notes, AVG(duration) AS avg_s, SUM(duration > 1800) AS over_30_min
       FROM note_events WHERE recorded_at >= ? GROUP BY source ORDER BY notes DESC`,
      d30,
    ),
    all(
      db,
      `SELECT result, COUNT(*) AS notes, SUM(attempts = 1) AS first_try,
              AVG(finished_at - accepted_at) AS avg_wait_ms, MAX(finished_at - accepted_at) AS max_wait_ms
       FROM note_events WHERE finished_at >= ? GROUP BY result ORDER BY notes DESC`,
      d7,
    ),
    one(
      db,
      `SELECT COUNT(*) AS waiting, MIN(accepted_at) AS oldest
       FROM notes WHERE status = 'transcribing'`,
    ),
    one(db, 'SELECT SUM(n) AS n FROM error_counts WHERE minute >= ?', Math.floor((now - 60 * 60 * 1000) / 60000)),
    one(
      db,
      `SELECT COUNT(*) AS notes, SUM(language IS NOT NULL AND language != '') AS language,
              SUM(filler_removal) AS filler_removal, SUM(vocabulary) AS vocabulary
       FROM note_events WHERE recorded_at >= ?`,
      d30,
    ),
    all(
      db,
      `SELECT phone_app AS label, COUNT(*) AS n FROM inboxes
       WHERE phone_app IS NOT NULL AND last_upload_at >= ? GROUP BY phone_app ORDER BY n DESC LIMIT 8`,
      d30,
    ),
    all(
      db,
      `SELECT watch_app AS label, COUNT(*) AS n FROM inboxes
       WHERE watch_app IS NOT NULL AND last_upload_at >= ? GROUP BY watch_app ORDER BY n DESC LIMIT 8`,
      d30,
    ),
    all(db, 'SELECT user_id, seconds FROM usage WHERE month = ? ORDER BY seconds DESC LIMIT 10', month),
    // How each agent gets notes. `via` is how it last checked in; a hook means
    // the relay pings it when a note is ready (it still pulls over the API).
    all(
      db,
      `SELECT CASE WHEN last_pull_at IS NULL THEN 'never'
                   WHEN via = 'mcp' THEN 'mcp'
                   WHEN hook_url IS NOT NULL THEN 'hook'
                   WHEN via = 'api' THEN 'poll'
                   ELSE 'unknown' END AS method,
              COUNT(*) AS n, SUM(last_pull_at >= ?) AS active7, COUNT(DISTINCT inbox_id) AS installs
       FROM connections GROUP BY method`,
      d7,
    ),
    one(
      db,
      `SELECT SUM(webhook = 1) AS on_all, SUM(webhook = 0) AS off_all, SUM(webhook IS NULL) AS unknown_all,
              SUM(webhook = 1 AND last_upload_at >= ?) AS on_30, SUM(webhook = 0 AND last_upload_at >= ?) AS off_30,
              SUM(webhook IS NULL AND last_upload_at >= ?) AS unknown_30
       FROM inboxes`,
      d30,
      d30,
      d30,
    ),
  ]);

  // Daily series: one entry per UTC day, oldest first, zeros filled in.
  const signups = new Map(signupsByDay.map((r) => [r.day, num(r.n)]));
  const byDay = new Map(notesByDay.map((r) => [r.day, r]));
  const daily = [];
  for (let t = days30Start; t <= todayStart; t += DAY) {
    const day = utcDay(t);
    const r = byDay.get(day);
    daily.push({
      day,
      signups: signups.get(day) ?? 0,
      users: num(r?.users),
      notes: num(r?.notes),
      minutes: round(num(r?.seconds) / 60),
    });
  }

  const byWeek = new Map(weekly.map((r) => [num(r.week), r]));
  const weeks = [];
  for (let w = 0; w < 12; w += 1) {
    const r = byWeek.get(w);
    weeks.push({ starts: utcDay(weeksStart + w * 7 * DAY), users: num(r?.users), notes: num(r?.notes) });
  }

  const methodRows = new Map(agentMethods.map((r) => [r.method, r]));
  const agentDelivery = AGENT_METHODS.map(([method, label]) => {
    const r = methodRows.get(method);
    return { method, label, agents: num(r?.n), pulled_last_7_days: num(r?.active7), installs: num(r?.installs) };
  });

  return {
    generated_at: new Date(now).toISOString(),
    totals: {
      installs: num(installs.n),
      installs_last_7_days: num(installs.last7),
      users_with_notes: num(notes.users),
      notes: num(notes.n),
      notes_last_7_days: num(notes.last7),
      hours: round(num(notes.seconds) / 3600),
      unlocked_installs: num(unlocked.n),
      agents_connected: num(agents.n),
      installs_with_agent: num(agents.inboxes),
      agents_pulled_last_7_days: num(agents.pulled7),
    },
    active_users: { day: num(active.dau), week: num(active.wau), month: num(active.mau) },
    funnel: [
      { step: 'Installed', n: num(funnel.installs) },
      { step: 'First note', n: num(funnel.first_note) },
      { step: '10 notes', n: num(funnel.ten_notes) },
      { step: `Used all ${FREE_NOTES} free notes`, n: num(funnel.used_free) },
      { step: 'Unlocked', n: num(funnel.unlocked) },
    ],
    purchases: purchases.map((r) => ({
      kind: r.kind,
      environment: r.environment,
      n: num(r.n),
      revoked: num(r.revoked),
      last_7_days: num(r.last7),
    })),
    daily,
    weekly: weeks,
    devices_30_days: devices.map((r) => ({
      source: r.source,
      notes: num(r.notes),
      avg_minutes: round(num(r.avg_s) / 60),
      over_30_min: num(r.over_30_min),
    })),
    reliability_7_days: results.map((r) => ({
      result: r.result,
      notes: num(r.notes),
      first_try: num(r.first_try),
      avg_wait_s: round(num(r.avg_wait_ms) / 1000),
      max_wait_s: round(num(r.max_wait_ms) / 1000),
    })),
    health: {
      waiting_to_transcribe: num(live.waiting),
      oldest_waiting_minutes: live.oldest == null ? null : round((now - live.oldest) / 60000, 0),
      server_errors_last_hour: num(errors.n),
      suspended_installs: num(suspended.inboxes),
      suspended_purchases: num(suspended.purchases),
    },
    settings_30_days: {
      notes: num(settings.notes),
      language_set: num(settings.language),
      filler_removal: num(settings.filler_removal),
      vocabulary: num(settings.vocabulary),
    },
    apps_30_days: {
      phone: phoneApps.map((r) => ({ label: r.label, installs: num(r.n) })),
      watch: watchApps.map((r) => ({ label: r.label, installs: num(r.n) })),
    },
    delivery: {
      agents: agentDelivery,
      webhook: {
        on: num(webhooks.on_all),
        off: num(webhooks.off_all),
        not_reported: num(webhooks.unknown_all),
        active_30_days: { on: num(webhooks.on_30), off: num(webhooks.off_30), not_reported: num(webhooks.unknown_30) },
      },
    },
    heaviest_this_month: heavy.map((r) => ({
      user: r.user_id,
      hours: round(num(r.seconds) / 3600),
      over_line: num(r.seconds) / 3600 >= HEAVY_HOURS,
    })),
  };
}
