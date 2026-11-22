// The dashboard page: plain server-rendered HTML, no scripts, no external
// assets. Colors and type follow docs/design.md (cream, ink, one amber accent).

const esc = (v) =>
  String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

const fmt = (n) => (n == null ? '–' : Number(n).toLocaleString('en-US'));
const pct = (part, whole) => (whole ? `${Math.round((100 * part) / whole)}%` : '–');

function tile(label, value, sub = '') {
  return `<div class="tile"><div class="label">${esc(label)}</div><div class="value">${esc(value)}</div>${
    sub ? `<div class="sub">${esc(sub)}</div>` : ''
  }</div>`;
}

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const shortDay = (iso) => `${MONTHS[Number(iso.slice(5, 7)) - 1]} ${Number(iso.slice(8, 10))}`;

// A bar per day (or week), each with its exact value on hover (or tap: the
// bar is focusable). Pass `totalUnit` when the sum means something (notes,
// installs); active users don't add up across days.
function bars(series, key, title, { unit, totalUnit } = {}) {
  const peak = Math.max(0, ...series.map((d) => d[key]));
  const max = Math.max(1, peak);
  const total = series.reduce((s, d) => s + d[key], 0);
  const cols = series
    .map((d, i) => {
      const h = Math.round((d[key] / max) * 100);
      const when = d.day ? shortDay(d.day) : `Week of ${shortDay(d.starts)}`;
      const tip = `${when}: ${fmt(d[key])} ${unit}`;
      const side = i < series.length / 2 ? 'l' : 'r';
      return `<div class="bar ${side}" tabindex="0" data-tip="${esc(tip)}" aria-label="${esc(tip)}"><span style="height:${h}%"></span></div>`;
    })
    .join('');
  const first = series[0]?.day ?? series[0]?.starts ?? '';
  const last = series.at(-1)?.day ?? series.at(-1)?.starts ?? '';
  const sub = totalUnit ? `${fmt(total)} ${totalUnit} · peak ${fmt(peak)}` : `Peak ${fmt(peak)}`;
  return `<section class="card"><h2>${esc(title)}</h2><div class="sub">${esc(sub)}</div><div class="bars">${cols}</div><div class="axis"><span>${esc(
    first,
  )}</span><span>${esc(last)}</span></div></section>`;
}

function table(title, headers, rows, note = '') {
  const body = rows.length
    ? rows.map((r) => `<tr>${r.map((c, i) => `<td${i ? ' class="num"' : ''}>${c}</td>`).join('')}</tr>`).join('')
    : `<tr><td colspan="${headers.length}" class="empty">Nothing yet</td></tr>`;
  return `<section class="card"><h2>${esc(title)}</h2>${note ? `<div class="sub">${esc(note)}</div>` : ''}<table><thead><tr>${headers
    .map((h, i) => `<th${i ? ' class="num"' : ''}>${esc(h)}</th>`)
    .join('')}</tr></thead><tbody>${body}</tbody></table></section>`;
}

export function renderPage(data, who) {
  const t = data.totals;
  const a = data.active_users;
  const h = data.health;
  const s = data.settings_30_days;
  const installs = data.funnel[0].n;
  const w = data.delivery.webhook;

  const healthy = h.server_errors_last_hour < 20 && (h.oldest_waiting_minutes ?? 0) < 30;
  const healthLine = `${healthy ? 'All clear' : 'Needs a look'} · ${fmt(h.waiting_to_transcribe)} waiting${
    h.oldest_waiting_minutes != null ? ` (oldest ${fmt(h.oldest_waiting_minutes)} min)` : ''
  } · ${fmt(h.server_errors_last_hour)} server errors in the last hour · ${fmt(h.suspended_installs + h.suspended_purchases)} suspended`;

  const sections = [
    `<section class="tiles">
      ${tile('Installs', fmt(t.installs), `+${fmt(t.installs_last_7_days)} this week`)}
      ${tile('Active, 24 h', fmt(a.day), `${fmt(a.week)} in 7 days · ${fmt(a.month)} in 30 days`)}
      ${tile('Notes', fmt(t.notes), `+${fmt(t.notes_last_7_days)} this week · ${fmt(t.hours)} h`)}
      ${tile('Unlocked', fmt(t.unlocked_installs), `${pct(t.unlocked_installs, t.installs)} of installs`)}
      ${tile('Agents', fmt(t.agents_connected), `${fmt(t.installs_with_agent)} installs · ${fmt(t.agents_pulled_last_7_days)} pulled this week`)}
    </section>`,
    `<p class="health ${healthy ? 'ok' : 'warn'}"><span class="dot"></span>${esc(healthLine)}</p>`,
    `<div class="grid charts">`,
    bars(data.daily, 'users', 'Daily active users, 30 days', { unit: 'users' }),
    bars(data.daily, 'notes', 'Notes per day, 30 days', { unit: 'notes', totalUnit: 'notes' }),
    bars(data.daily, 'signups', 'Installs per day, 30 days', { unit: 'installs', totalUnit: 'installs' }),
    bars(data.weekly, 'users', 'Weekly active users, 12 weeks', { unit: 'users' }),
    `</div><div class="grid">`,
    table(
      'Funnel',
      ['Step', 'Installs', 'Of all'],
      data.funnel.map((f) => [esc(f.step), esc(fmt(f.n)), esc(pct(f.n, installs))]),
    ),
    table(
      'Purchases',
      ['Kind', 'Environment', 'Total', 'This week', 'Revoked'],
      data.purchases.map((p) => [esc(p.kind), esc(p.environment), esc(fmt(p.n)), esc(fmt(p.last_7_days)), esc(fmt(p.revoked))]),
      'Sandbox rows are TestFlight.',
    ),
    table(
      'How agents get notes',
      ['Method', 'Agents', 'This week', 'Installs'],
      data.delivery.agents
        .filter((m) => m.agents > 0 || ['mcp', 'hook', 'poll'].includes(m.method))
        .map((m) => [esc(m.label), esc(fmt(m.agents)), esc(fmt(m.pulled_last_7_days)), esc(fmt(m.installs))]),
      'By how each agent last checked in',
    ),
    table(
      'iPhone webhook',
      ['Webhook', 'Installs', 'Active in 30 days'],
      [
        ['On', w.on, w.active_30_days.on],
        ['Off', w.off, w.active_30_days.off],
        ['Not reported (older app)', w.not_reported, w.active_30_days.not_reported],
      ].map(([k, n, a]) => [esc(k), esc(fmt(n)), esc(fmt(a))]),
      'Custom webhook destination set in the app',
    ),
    table(
      'Watch vs phone',
      ['Device', 'Notes', 'Avg min', 'Over 30 min'],
      data.devices_30_days.map((d) => [esc(d.source), esc(fmt(d.notes)), esc(fmt(d.avg_minutes)), esc(fmt(d.over_30_min))]),
      'Last 30 days',
    ),
    table(
      'Reliability',
      ['Result', 'Notes', 'First try', 'Avg wait', 'Max wait'],
      data.reliability_7_days.map((r) => [
        esc(r.result),
        esc(fmt(r.notes)),
        esc(pct(r.first_try, r.notes)),
        esc(`${fmt(r.avg_wait_s)} s`),
        esc(`${fmt(r.max_wait_s)} s`),
      ]),
      'Last 7 days, upload to final',
    ),
    table(
      'Settings in use',
      ['Setting', 'Notes', 'Share'],
      [
        ['Language set', s.language_set],
        ['Filler-word removal', s.filler_removal],
        ['Vocabulary', s.vocabulary],
      ].map(([k, n]) => [esc(k), esc(fmt(n)), esc(pct(n, s.notes))]),
      `Of ${fmt(s.notes)} notes in the last 30 days`,
    ),
    table(
      'Heaviest this month',
      ['User', 'Hours'],
      data.heaviest_this_month.map((u) => [
        `<code>${esc(u.user)}</code>`,
        `${u.over_line ? `<span class="flag">over ${esc(fmt(data.heavy_use_hours))} h</span> ` : ''}${esc(fmt(u.hours))}`,
      ]),
      'UTC month. Internal only.',
    ),
    table(
      'Phone builds',
      ['App', 'Installs'],
      data.apps_30_days.phone.map((r) => [`<code>${esc(r.label)}</code>`, esc(fmt(r.installs))]),
      'Uploaded in the last 30 days',
    ),
    table(
      'Watch builds',
      ['App', 'Installs'],
      data.apps_30_days.watch.map((r) => [`<code>${esc(r.label)}</code>`, esc(fmt(r.installs))]),
      'Uploaded in the last 30 days',
    ),
    `</div>`,
  ];

  const signedIn = who.kind === 'person' ? who.email : `service token ${who.name}`;
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>Ramble Admin</title>
<style>
:root{--bg:#f4f3ef;--card:#fff;--ink:#141210;--soft:#403b33;--faint:#7a7163;--hair:#e8e5df;--amber:#d97706;--amber-text:#b45309;--amber-soft:#f9ebda;--green:#2f8a4c;--red:#c2410c;color-scheme:light dark}
@media (prefers-color-scheme:dark){:root{--bg:#141210;--card:#1d1b18;--ink:#f4efe7;--soft:#c9c2b5;--faint:#8a8275;--hair:#2a2723;--amber:#f59e0b;--amber-text:#fbbf5a;--amber-soft:#33230a;--green:#4ade80;--red:#fb923c}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.45 -apple-system,BlinkMacSystemFont,"SF Pro Text","Helvetica Neue",sans-serif}
main{max-width:1100px;margin:0 auto;padding:28px 16px 48px}
header{display:flex;justify-content:space-between;align-items:baseline;gap:12px;flex-wrap:wrap;margin-bottom:20px}
h1{margin:0;font:italic 700 28px/1.1 "New York",ui-serif,Georgia,serif;letter-spacing:-.4px}
h1 .dot{display:inline-block;width:10px;height:10px;border-radius:50%;background:var(--amber);margin-right:8px;vertical-align:middle}
h1 small{font:500 15px -apple-system,BlinkMacSystemFont,sans-serif;color:var(--faint);font-style:normal;margin-left:6px}
.meta{color:var(--faint);font-size:13px}
.tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:12px}
.tile,.card{background:var(--card);border-radius:16px;padding:16px}
.label{font-size:12px;font-weight:500;color:var(--faint);text-transform:uppercase;letter-spacing:.4px}
.value{font:500 30px/1.15 "New York",ui-serif,Georgia,serif;margin:4px 0 2px}
.sub{color:var(--faint);font-size:13px}
.health{margin:16px 2px;color:var(--soft);font-size:14px}
.health .dot{display:inline-block;width:8px;height:8px;border-radius:50%;margin-right:8px;vertical-align:middle}
.health.ok .dot{background:var(--green)}.health.warn .dot{background:var(--red)}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,320px),1fr));gap:12px;margin-top:12px}
.charts{grid-template-columns:repeat(auto-fit,minmax(min(100%,440px),1fr))}
h2{margin:0 0 2px;font-size:15px;font-weight:600}
.bars{display:flex;align-items:flex-end;gap:2px;height:124px;padding-top:28px;margin-top:4px}
.bar{flex:1;height:100%;display:flex;align-items:flex-end;position:relative;outline:none;cursor:default}
.bar span{display:block;width:100%;min-height:1px;background:var(--amber);border-radius:3px 3px 0 0;opacity:.85}
.bars:hover .bar span,.bars:focus-within .bar span{opacity:.45}
.bars .bar:hover span,.bars .bar:focus span{opacity:1}
.bar:hover::after,.bar:focus::after{content:attr(data-tip);position:absolute;bottom:calc(100% + 6px);white-space:nowrap;background:var(--ink);color:var(--bg);font-size:12px;font-weight:500;padding:4px 8px;border-radius:8px;z-index:2;pointer-events:none;font-variant-numeric:tabular-nums}
.bar.l::after{left:0}.bar.r::after{right:0}
.axis{display:flex;justify-content:space-between;color:var(--faint);font-size:11px;margin-top:4px}
table{width:100%;border-collapse:collapse;margin-top:10px;font-size:14px}
th{font-size:12px;font-weight:500;color:var(--faint);text-align:left;padding:4px 0}
td{padding:6px 0;border-top:1px solid var(--hair);color:var(--soft)}
.num{text-align:right;padding-left:12px;font-variant-numeric:tabular-nums}
.empty{color:var(--faint);text-align:left}
code{font:12px ui-monospace,"SF Mono",Menlo,monospace;word-break:break-all}
.flag{font-size:11px;color:var(--amber-text);background:var(--amber-soft);border-radius:999px;padding:1px 8px}
footer{margin-top:24px;color:var(--faint);font-size:12px}
a{color:var(--amber-text)}
</style>
</head>
<body>
<main>
<header>
  <h1><span class="dot"></span>Ramble<small>Admin</small></h1>
  <div class="meta">Signed in as ${esc(signedIn)} · ${esc(data.generated_at.slice(0, 16).replace('T', ' '))} UTC</div>
</header>
${sections.join('\n')}
<footer>Read-only. Counts and labels only, never anyone's words. Same data as JSON: <a href="/api/overview">/api/overview</a>.</footer>
</main>
</body>
</html>`;
}
