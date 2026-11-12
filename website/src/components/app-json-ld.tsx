import {
  APP_PRICE,
  APP_STORE_URL,
  FREE_NOTES,
  MIN_IOS,
  MIN_WATCHOS,
  SITE_URL,
} from "../lib/site";

// SoftwareApplication structured data for the landing page. Facts only:
// never add ratings, review counts or download counts.
const APP_JSON_LD = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: "Ramble",
  alternateName: "Ramble for Apple Watch",
  description:
    "Say it. Let it go. One-way voice notes from your Apple Watch to your agent. No reply to wait for, no signal needed. Your agent picks it up later.",
  url: SITE_URL,
  image: `${SITE_URL}/ramble-icon-light.png`,
  applicationCategory: "ProductivityApplication",
  operatingSystem: `iOS ${MIN_IOS} or later, watchOS ${MIN_WATCHOS} or later`,
  installUrl: APP_STORE_URL,
  sameAs: [APP_STORE_URL],
  offers: [
    {
      "@type": "Offer",
      name: `Free download with ${FREE_NOTES} free notes`,
      price: "0",
      priceCurrency: "USD",
      url: APP_STORE_URL,
    },
    {
      "@type": "Offer",
      name: "One-time unlock",
      price: APP_PRICE.replace("$", ""),
      priceCurrency: "USD",
      url: APP_STORE_URL,
    },
  ],
};

export default function AppJsonLd() {
  return (
    <script
      type="application/ld+json"
      dangerouslySetInnerHTML={{ __html: JSON.stringify(APP_JSON_LD).replace(/</g, "\\u003c") }}
    />
  );
}
