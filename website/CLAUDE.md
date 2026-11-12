@AGENTS.md

# Website

Marketing site for Ramble. Next.js with Tailwind CSS, statically exported.

## Build

```bash
npm install
npm run build    # Static export to out/
npm run dev      # Dev server at localhost:3000
```

## Deployment

- Hosted on Vercel (its own project, root directory `website`). Every PR that touches `website/` gets a preview deployment; `vercel.json` skips builds for commits that don't.
- Served from the root of Ramble's own domain, https://ramble.watch (`SITE_URL` in `src/lib/site.ts`). There is no `basePath`.
- `output: "export"` still produces a plain static `out/` folder.

## Image paths

Use plain `<img>` tags with `BASE_PATH` from `src/lib/site.ts` (currently empty) for images in `public/`, e.g. `src={`${BASE_PATH}/ramble-icon-light.png`}`, so a future basePath change stays one line.

## Pages

| Route | File | Description |
|-------|------|-------------|
| `/` | `src/app/page.tsx` | Landing page — hero, value props, how-it-works, pricing |
| `/docs` | `src/app/docs/page.tsx` | Connect your agent: pairing, Muse, relay API, what the relay stores |
| `/docs/webhooks` | `src/app/docs/webhooks/page.tsx` | Webhook API docs (developer-targeted) |
| `/docs/help` | `src/app/docs/help/page.tsx` | Requirements (min iOS/watchOS) and troubleshooting |
| `/support` | `src/app/support/page.tsx` | Support email and short answers (the App Store Support URL) |
| `/privacy` | `src/app/privacy/page.tsx` | Privacy policy |
| `/terms` | `src/app/terms/page.tsx` | Terms of use |

## Shared components

- `src/components/code-block.tsx` — Client component with copy-to-clipboard button, used in docs pages
- `src/components/docs-sidebar.tsx` — Docs page switcher + "On this page" nav; pass `page="agent"` or `page="webhooks"`
- `src/components/app-json-ld.tsx` — SoftwareApplication JSON-LD on the landing page, built from `site.ts` facts. Never add ratings or download counts
- Every indexed page sets `alternates.canonical` to its own path in its `metadata`; a new page needs one too
- `src/lib/site.ts` — Shared constants (prices, retention, relay URL, pairing code). Several are placeholders
- `public/llms.txt` / `public/llms-full.txt` — Agent-readable summary and full reference; keep in sync with the docs pages
- Footer is in `src/app/layout.tsx` (shared across all pages)

## Style

- Palette: sage/stone/cream (see `globals.css` for custom color tokens)
- Tone: calm, direct, no hype (see `docs/brand.md` in repo root)
- System fonts (SF Pro stack)
