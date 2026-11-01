// Shared facts the site states in more than one place. Several are
// PLACEHOLDERS awaiting Justin's decision (handoff Section 7). Change them here
// and every page follows. Search for "PLACEHOLDER" before shipping.

export const BASE_PATH = "/ramble";
export const SITE_URL = "https://goodloop.dev/ramble";
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
