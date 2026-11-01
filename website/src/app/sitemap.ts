import type { MetadataRoute } from "next";
import { SITE_URL } from "../lib/site";

export const dynamic = "force-static";

export default function sitemap(): MetadataRoute.Sitemap {
  return ["", "/docs", "/docs/webhooks", "/privacy", "/terms"].map((path) => ({
    url: `${SITE_URL}${path}`,
  }));
}
