@AGENTS.md

# Website

Marketing site for Ramble. Next.js with Tailwind CSS, statically exported.

## Build

```bash
npm install
npm run build    # Static export to out/
npm run dev      # Dev server at localhost:3000/ramble
```

## Deployment

- Hosted at `goodloop.dev/ramble` (separate repo)
- `basePath: "/ramble"` is set in `next.config.ts` — all routes and assets are prefixed
- `output: "export"` produces a plain `out/` folder of static HTML/CSS/JS
- Copy the contents of `out/` into the goodloop.dev repo at the path serving `/ramble/`
- No server runtime needed

## Image paths

`next/image` with `unoptimized: true` does not prepend `basePath` in the static HTML output. Use plain `<img>` tags with the `BASE_PATH` constant (defined in each page file) for any images in `public/`. Example: `src={\`${BASE_PATH}/ramble-icon-light.png\`}`.

## Pages

| Route | File | Description |
|-------|------|-------------|
| `/` | `src/app/page.tsx` | Landing page — hero, value props, how-it-works, pricing |
| `/docs` | `src/app/docs/page.tsx` | Webhook API docs (developer-targeted) |
| `/privacy` | `src/app/privacy/page.tsx` | Privacy policy |
| `/terms` | `src/app/terms/page.tsx` | Terms of use |

## Shared components

- `src/components/code-block.tsx` — Client component with copy-to-clipboard button, used in docs page
- Footer is in `src/app/layout.tsx` (shared across all pages)

## Style

- Palette: sage/stone/cream (see `globals.css` for custom color tokens)
- Tone: calm, direct, no hype (see `docs/brand.md` in repo root)
- System fonts (SF Pro stack)
