# Ramble — Design

The design source of truth for the watch app, the iPhone app, and the website. Brand voice, positioning, and copy rules live in [`brand.md`](brand.md). This doc covers how Ramble looks, moves, and feels, and the tokens that make it consistent.

## Philosophy

Ramble is a mindfulness app as much as a capture app. Every design choice should get the person back to their life faster.

1. **Watch first.** The watch is the product. The iPhone does transcription, delivery, and settings, and should stay in the pocket. Design the watch screen first, then decide what the phone needs.
2. **Leave your phone behind.** Nothing on the watch should require the phone to be nearby. Offline is a normal state, not an error.
3. **Send it and let it go.** No reply to wait for, no spinner to watch. After a recording, the person should feel done, not pending.
4. **Iconography and motion over text.** On the watch home screen, state is shown with the button, a glyph, a dot, or a short animation. Words are for detail pages and for problems that block recording (e.g. "Mic off").
5. **Progressive disclosure.** The first screen does one thing. Status, history, and settings are one tap deeper, and only surface on the first screen when something needs the person.
6. **Minimal copy.** Short, calm, direct. Two or three words on the watch. If a sentence is needed, it belongs on a detail page or the phone.
7. **iOS-native.** SwiftUI defaults, SF Symbols, system materials. Custom chrome only where it carries the brand (record button, wordmark, logo mark).

## Brand at a glance

- **Name:** Ramble. App Store: "Ramble: Voice Notes for Watch".
- **Tagline:** "Talk to your watch. Your agent handles it." App Store subtitle: "Say it. Your agent handles it."
- **Color:** Deep amber is the only saturated color. It means "on" and "captured", never "danger".
- **Wordmark:** brand-amber dot + "Ramble" in bold italic New York serif (`OnboardingWordmark`).
- **Logo mark:** amber circle with three rounded bars riding to its right (`RambleBarsMark`, mirrors `website/src/components/animated-logo.tsx`).

## Color

Light / dark values. iOS asset catalog names are kebab-case; Swift accessors in parentheses.

| Token | Light | Dark | Usage |
|---|---|---|---|
| `brand-amber` (`Color.brandAmber`) | `#D97706` | `#F59E0B` | Record button, wordmark dot, logo, primary CTAs, selection, italic headline accents. |
| `brand-amber-soft` (`Color.brandAmberSoft`) | `#F9EBDA` | `#33230A` | Selected-row tint, soft badges. |
| amber text | `#B45309` | `#FBBF5A` | Amber on light surfaces. `#D97706` is under 3:1 on cream, so text uses this. |
| on-amber label | white | `#1F1404` | Label on a filled amber button. |
| `onboarding-ink` (`Color.obInk`) | `#141210` | `#F4EFE7` | Primary text. |
| `onboarding-ink-soft` (`Color.obInkSoft`) | `#403B33` | `#C9C2B5` | Body copy. |
| `onboarding-ink-faint` (`Color.obInkFaint`) | `#7A7163` | `#8A8275` | Captions, metadata. |
| `onboarding-hair` (`Color.obHair`) | `#E8E5DF` | `#2A2723` | Hairlines, inactive progress dots. |
| surface | `secondarySystemGroupedBackground` | same | Cards (`BrandCard`). |
| error | system red | system red | Errors only. |

The watch uses `brand-amber` (dark value, `#F59E0B`) on black and system colors for everything else.

**Website** (`website/src/app/globals.css`): `--color-brand: #d97706` for fills, `--color-brand-text: #b45309` for text and links, a warm `stone` neutral scale, and `cream` (`#f4f3ef`) / `cream-warm` (`#f9f5ed`) backgrounds.

**Rules:** one amber accent per view. Don't use amber for warnings or destructive actions. Status colors other than amber and red should come from the system (secondary label, etc.) rather than new hues. System green means one thing: done, nothing left to do (a note your agent has, a connected agent). The watch can't see agent pickup, so its checks stay gray. A note that is simply on its way stays gray too; it turns amber only once it needs the person.

## Typography

| Role | Font | Where |
|---|---|---|
| Headline | New York serif, medium, 34pt (48pt welcome), tracking −0.6 (−1.0 at 44pt+) | `OnboardingHeadline` |
| Italic accent | Same serif, italic, often amber | Second half of a headline: "First, *let it hear you.*" |
| Wordmark | New York serif, bold italic | `OnboardingWordmark` |
| Body | SF Pro 16pt (17pt large), line spacing 2, `obInkSoft` | `OnboardingBody` |
| Section header | SF Pro 12pt medium | `OnboardingFont.sectionHeader` |
| Watch timer | New York serif, bold, 28pt | `WatchMainView` while recording |
| Watch status / meta | `.caption2` | Watch home, list rows |
| Code / pairing codes | SF Mono | Website `--font-mono`; pairing code display |

Website mirrors this: `--font-sans` = SF Pro stack, `--font-serif` = New York stack. Prefer Dynamic Type styles for anything that isn't a hero or brand element.

## Spacing and shape

- **Spacing scale:** 4, 8, 12, 16, 24 (with 6, 10, 14, 20 in tight spots). 16 is the default screen gutter and card padding.
- **Corner radius:** 16 for cards (`BrandCard`), 12 for rows and inner controls, capsules for pills and progress, circles for the record button.
- **Tap targets:** 44pt minimum (nav back button is 44×44).
- **Dividers:** hairline `obHair`, inset to the content column (`BrandRowDivider`, 50pt default).

## Record button

The one control that matters. Amber ring + filled amber disc when idle; while recording, the disc gives way to three live audio-level bars (the logo bars, alive).

| | Watch | iPhone |
|---|---|---|
| Size | 88pt ring, 4pt stroke, 72pt disc | 76pt ring, 66pt disc → 24pt rounded square while recording |
| Recording | 3 bars, 10pt wide, 6pt gap, 10–38pt tall, scales 0.7 / 1.0 / 0.8 | Stop square |
| Shortcut | Double tap (`handGestureShortcut(.primaryAction)`) | — |

Watch direction under exploration: one start/stop control only (no tap-anywhere), larger button (~120pt), a brief check inside the button on save, history button bottom right with a dot badge when notes need attention, bottom left reserved for 2–3 word blocking alerts.

## Motion

Motion is how the watch talks instead of text. Keep it short, calm, and meaningful: every animation should confirm something happened or show live state.

| Use | Curve | Duration |
|---|---|---|
| State change (idle ↔ recording) | `easeInOut` | 0.3s |
| Small status swaps (saved, error line) | `easeInOut` | 0.2s |
| Progress / selection | `.smooth` | 0.3s |
| Audio-level bars | `spring(response: 0.15, dampingFraction: 0.6)` | live |
| Logo entrance | spring pop (response 0.42, damping 0.62), circle then bars at +0.22 / 0.30 / 0.38s | ~0.8s |
| Logo idle pulse | wave from circle through bars, peak scale 1.12 → 1.26 | 2.8s cycle |
| Website hero entrance | fade + rise 8–12px, `ease-out`, staggered 0.2 / 0.35 / 0.5 / 0.7s | 0.4–0.7s |

Respect Reduce Motion: drop pulses and staggered entrances, keep instant state changes. The website already gates smooth scrolling on `prefers-reduced-motion`.

## Haptics

Haptics confirm the record loop so the person never has to look.

| Moment | Watch (`WatchHapticService`) | iPhone (`HapticService`) |
|---|---|---|
| Start recording | `.start` | heavy impact |
| Stop / saved | `.success` | success notification |
| Failure | `.failure` | warning notification |
| Button tap / selection | — | light impact |

## Iconography

SF Symbols only, matched to the text weight next to them. Prefer one glyph to a sentence. The waveform (`waveform`) and the bars mark mean "Ramble" or "recording". Status dots are small and colorless unless they need the person (then amber, or red for failure) or the note is done (green). Badges are dots, not counts.
