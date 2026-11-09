// Shared facts the site states in more than one place. Change them here and
// every page follows. The specs in specs/ are the source of truth.

// The site is served from the root of its own domain (no basePath).
export const BASE_PATH = "";

// Ramble's own domain. Canonical URLs, OG tags, the sitemap and the setup
// message all use it, including on preview deployments.
export const SITE_URL = "https://ramble.watch";
export const APP_STORE_URL = "https://apps.apple.com/app/id6761857751";
export const SUPPORT_EMAIL = "support@ramble.watch";

// Pricing (specs/purchase.md "What Ramble says about price"). Never add a
// monthly price, "trial", "premium" or "Subscribe".
export const FREE_NOTES = 25;
export const APP_PRICE = "$14.99";
export const PRICE_STORY = `Free to download. ${FREE_NOTES} notes free, then ${APP_PRICE} once.`;

// specs/delivery.md "One privacy wording everywhere". Use it verbatim.
export const PRIVACY_WORDING =
  "Ramble's server is a relay, not an archive. Your audio is sent to a transcription provider and deleted as soon as the transcript is ready. Transcripts are deleted when your agent picks them up, or after 30 days. Your full history lives only on your iPhone.";

// specs/delivery.md "Usage stats wording". Use it verbatim, after PRIVACY_WORDING.
export const USAGE_WORDING =
  "Ramble also keeps basic usage stats for each note, like its length and whether it came from your watch or iPhone, under a random ID. Never your audio or your words.";

// How long an agent's copy waits if it is never picked up.
export const RETENTION = "30 days";

// The one transcription provider (specs/transcription.md).
export const PROVIDERS = [
  { name: "Groq", model: "Whisper v3 Turbo", privacy: "https://groq.com/privacy-policy/" },
] as const;

// Relay base URL (specs/relay-api.md "Base URL"). The workers.dev host serves
// the identical API, so agents paired against it keep working.
export const RELAY_URL = "https://api.ramble.watch";
export const RELAY_URL_LEGACY = "https://ramble-transcription-proxy.jpoliachik.workers.dev";

// Pairing codes: 12 characters, shown as XXXX-XXXX-XXXX, single use.
export const PAIR_CODE_EXAMPLE = "K7QX-MP4D-HN3R";
export const PAIR_CODE_TTL = "10 minutes";

// Minimum OS versions. Keep in sync with IPHONEOS_DEPLOYMENT_TARGET and
// WATCHOS_DEPLOYMENT_TARGET in Ramble/Ramble.xcodeproj.
export const MIN_IOS = "18.6";
export const MIN_WATCHOS = "10.0";
export const WATCH_MODELS = "Apple Watch Series 4 and later, every Apple Watch SE, and every Apple Watch Ultra";
