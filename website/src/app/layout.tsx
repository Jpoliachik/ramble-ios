import type { Metadata } from "next";
import Link from "next/link";
import Header from "../components/header";
import "./globals.css";

const BASE_PATH = "/ramble";
const SITE_URL = "https://goodloop.dev/ramble";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: {
    default: "Ramble — Voice in, webhooks out",
    template: "%s — Ramble",
  },
  description:
    "Speak a thought and Ramble POSTs the transcript straight to your stack — your AI agent, n8n, Home Assistant, Zapier, or any webhook. Open source, no account, no cloud required.",
  openGraph: {
    type: "website",
    siteName: "Ramble",
    title: "Ramble — Voice in, webhooks out",
    description:
      "Speak a thought and Ramble POSTs the transcript straight to your stack — your AI agent, n8n, Home Assistant, or any webhook.",
    url: SITE_URL,
    images: [
      {
        url: `${SITE_URL}/og-image.png`,
        width: 1200,
        height: 630,
        alt: "Ramble — Voice in, webhooks out",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "Ramble — Voice in, webhooks out",
    description:
      "Speak a thought and Ramble POSTs the transcript straight to your stack — your AI agent, n8n, Home Assistant, or any webhook.",
    images: [`${SITE_URL}/og-image.png`],
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className="h-full antialiased">
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
              <a
                href="https://apps.apple.com/app/id6761857751"
                target="_blank"
                rel="noopener noreferrer"
                className="hover:text-stone-900 transition-colors"
              >
                App Store
              </a>
              <a
                href="https://github.com/Jpoliachik/ramble-ios"
                target="_blank"
                rel="noopener noreferrer"
                className="hover:text-stone-900 transition-colors"
              >
                GitHub
              </a>
              <Link href="/docs" className="hover:text-stone-900 transition-colors">
                Docs
              </Link>
              <Link href="/privacy" className="hover:text-stone-900 transition-colors">
                Privacy Policy
              </Link>
              <Link href="/terms" className="hover:text-stone-900 transition-colors">
                Terms of Use
              </Link>
            </nav>
          </div>
        </footer>
      </body>
    </html>
  );
}
