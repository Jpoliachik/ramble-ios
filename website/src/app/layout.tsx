import type { Metadata } from "next";
import Link from "next/link";
import { Analytics } from "@vercel/analytics/next";
import Header from "../components/header";
import { BASE_PATH, SITE_URL } from "../lib/site";
import "./globals.css";

const TITLE = "Ramble for Apple Watch: Say it. Let it go.";
const DESCRIPTION =
  "One-way voice notes from your Apple Watch to your agent. Say a thought and get back to your day. No reply to wait for, no signal needed. Your agent picks it up later.";
const SHORT_DESCRIPTION =
  "Say a thought to your Apple Watch and let it go. No reply to wait for. Your agent picks it up later.";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: {
    default: TITLE,
    template: "%s — Ramble",
  },
  description: DESCRIPTION,
  openGraph: {
    type: "website",
    siteName: "Ramble",
    title: TITLE,
    description: SHORT_DESCRIPTION,
    url: SITE_URL,
    images: [
      {
        url: `${SITE_URL}/og-image.png?v=3`,
        width: 1200,
        height: 630,
        alt: "Ramble for Apple Watch: Say it to your watch. Then let it go.",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: TITLE,
    description: SHORT_DESCRIPTION,
    images: [`${SITE_URL}/og-image.png?v=3`],
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className="h-full antialiased" data-scroll-behavior="smooth">
      <body className="min-h-full flex flex-col bg-cream text-stone-900">
        <Header />
        {children}
        <footer className="border-t border-stone-200 bg-stone-50">
          <div className="mx-auto max-w-5xl px-6 py-10 flex flex-col items-center gap-6 sm:flex-row sm:justify-between">
            <div className="flex items-center gap-2 text-stone-500 text-sm">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={`${BASE_PATH}/ramble-icon-light.png`} alt="Ramble" width={20} height={20} className="rounded" />
              <span>Ramble</span>
            </div>
            <nav className="flex flex-wrap items-center justify-center gap-x-6 gap-y-2 text-sm text-stone-500">
              <Link href="/docs" className="hover:text-stone-900 transition-colors">
                Docs
              </Link>
              <Link href="/docs/webhooks" className="hover:text-stone-900 transition-colors">
                Webhooks
              </Link>
              <Link href="/docs/help" className="hover:text-stone-900 transition-colors">
                Help
              </Link>
              <Link href="/support" className="hover:text-stone-900 transition-colors">
                Support
              </Link>
              <Link href="/privacy" className="hover:text-stone-900 transition-colors">
                Privacy
              </Link>
              <Link href="/terms" className="hover:text-stone-900 transition-colors">
                Terms
              </Link>
            </nav>
          </div>
        </footer>
        <Analytics />
      </body>
    </html>
  );
}
