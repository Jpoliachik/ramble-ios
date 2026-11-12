import type { Metadata } from "next";
import HeroMotion from "../../components/hero-motion";

// A 1200×630 frame for recording the OG video (public/og-video.mp4). Not
// linked anywhere. It covers the site header and footer so a capture of the
// viewport is just the frame.
export const metadata: Metadata = {
  title: "OG frame",
  robots: { index: false, follow: false },
};

export default function OgFrame() {
  return (
    <div className="fixed inset-0 z-[100] flex items-center justify-center overflow-hidden bg-cream">
      <div className="flex h-[630px] w-[1200px] shrink-0 items-center justify-between pl-[80px] pr-[40px]">
        <div>
          <div className="flex items-center gap-3">
            <svg width="50" height="30" viewBox="0 0 50 30" aria-hidden="true">
              <circle cx="15" cy="15" r="15" fill="var(--color-brand)" />
              <rect x="34" y="2" width="5" height="26" rx="2.5" fill="#1a1917" />
              <rect x="43" y="7" width="5" height="16" rx="2.5" fill="#1a1917" />
            </svg>
            <span className="font-serif text-[30px] font-semibold italic text-stone-900">Ramble</span>
          </div>
          <h1 className="mt-8 font-serif text-[64px] font-semibold leading-[1.08] tracking-tight text-stone-900">
            <span className="block">Say it to your watch.</span>
            <span className="block italic text-brand-text">Then let it go.</span>
          </h1>
        </div>
        <HeroMotion size={500} />
      </div>
    </div>
  );
}
