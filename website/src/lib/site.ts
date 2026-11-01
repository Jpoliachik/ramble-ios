// Shared facts the site states in more than one place. Several are
// PLACEHOLDERS awaiting Justin's decision (handoff Section 7). Change them here
// and every page follows. Search for "PLACEHOLDER" before shipping.

// The site is served from the root of its own domain (no basePath).
export const BASE_PATH = "";

// PLACEHOLDER: Ramble's own domain isn't bought yet. Until NEXT_PUBLIC_SITE_URL
// is set in Vercel, this falls back to the Vercel production URL for the build.
export const SITE_URL =
  process.env.NEXT_PUBLIC_SITE_URL ??
  (process.env.VERCEL_PROJECT_PRODUCTION_URL
    ? `https://${process.env.VERCEL_PROJECT_PRODUCTION_URL}`
    : "http://localhost:3000");
export const APP_STORE_URL = "https://apps.apple.com/app/id6761857751";

// PLACEHOLDER: one-time app price. Justin said "a couple dollars"; no number is locked.
export const APP_PRICE = "$2.99";

// PLACEHOLDER: cloud transcription subscription. Today's price, kept until Justin decides.
export const CLOUD_PRICE = "$3.99/month";

// PLACEHOLDER: hard maximum for transcripts an agent never picks up. Justin is choosing 30 or 60 days.
export const RETENTION = "30 days";

// PLACEHOLDER: relay hostname is undecided. Do not replace with a real domain without Justin.
export const RELAY_URL = "https://<relay-host>";

// Pairing code defaults from the relay (PR #32). Proposed, not locked.
export const PAIR_CODE_EXAMPLE = "K7QX-MP4D";
export const PAIR_CODE_TTL = "10 minutes";

// Suggested agent pull cadence. Proposed, not locked.
export const PULL_CADENCE = "15 minutes";
