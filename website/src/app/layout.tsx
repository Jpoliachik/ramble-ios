import type { Metadata } from "next";
import Link from "next/link";
import Header from "../components/header";
import { BASE_PATH, GITHUB_URL, SITE_URL } from "../lib/site";
import "./globals.css";

const TITLE = "Ramble: Record on your watch. Your agent handles it.";
const DESCRIPTION =
  "Tap your Apple Watch and talk. Your iPhone transcribes it, and your agent picks it up and takes it from there. On-device transcription, no accounts, open source.";
const SHORT_DESCRIPTION =
  "Tap your Apple Watch and talk. Your iPhone transcribes it. Your agent handles it.";

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
        url: `${SITE_URL}/og-image.png`,
        width: 1200,
        height: 630,
        alt: "Ramble",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: TITLE,
    description: SHORT_DESCRIPTION,
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
              <Link href="/docs" className="hover:text-stone-900 transition-colors">
                Docs
              </Link>
              <Link href="/docs/webhooks" className="hover:text-stone-900 transition-colors">
                Webhooks
              </Link>
              <Link href="/privacy" className="hover:text-stone-900 transition-colors">
                Privacy
              </Link>
              <Link href="/terms" className="hover:text-stone-900 transition-colors">
                Terms
              </Link>
              <a
                href={GITHUB_URL}
                target="_blank"
                rel="noopener noreferrer"
                className="hover:text-stone-900 transition-colors"
              >
                GitHub
              </a>
            </nav>
          </div>
        </footer>
      </body>
    </html>
  );
}
