"use client";

import { useEffect, useState } from "react";

const BASE_PATH = "/ramble";

export default function Header() {
  const [scrolled, setScrolled] = useState(false);
  const [showCta, setShowCta] = useState(false);

  useEffect(() => {
    const handleScroll = () => {
      const y = window.scrollY;
      setScrolled(y > 20);
      // Show CTA after scrolling past the hero area
      setShowCta(y > 300);
    };
    window.addEventListener("scroll", handleScroll, { passive: true });
    handleScroll();
    return () => window.removeEventListener("scroll", handleScroll);
  }, []);

  return (
    <header
      className={`fixed top-0 left-0 right-0 z-50 transition-all duration-300 ${
        scrolled
          ? "bg-cream/80 backdrop-blur-lg shadow-sm"
          : "bg-transparent"
      }`}
    >
      <div className="mx-auto max-w-5xl px-6 flex items-center justify-between h-14">
        {/* Logo */}
        <a href="/" className="flex items-center gap-2.5 group">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={`${BASE_PATH}/ramble-icon-light.png`}
            alt="Ramble"
            width={32}
            height={32}
            className="rounded-lg shadow-sm transition-transform duration-300 group-hover:scale-105"
          />
          <span className="font-serif font-bold italic text-xl text-stone-900 tracking-tight">
            Ramble
          </span>
        </a>

        {/* CTA — slides in from right on scroll */}
        <div
          className={`transition-all duration-500 ease-out ${
            showCta
              ? "opacity-100 translate-x-0"
              : "opacity-0 translate-x-4 pointer-events-none"
          }`}
        >
          <a
            href="https://apps.apple.com/app/ramble"
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-1.5 rounded-full bg-stone-900 px-4 py-2 text-sm font-medium text-white shadow-sm transition-all duration-200 hover:bg-stone-800 hover:shadow-md active:scale-95"
          >
            <svg
              className="h-4 w-4"
              viewBox="0 0 24 24"
              fill="currentColor"
            >
              <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z" />
            </svg>
            App Store
          </a>
        </div>
      </div>
    </header>
  );
}
