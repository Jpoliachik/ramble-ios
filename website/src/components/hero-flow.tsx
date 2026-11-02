"use client";

import { useEffect, useState } from "react";

// A thought (the red dot) leaves the Ramble mark, arcs over, and drops into an
// open box: your agent's inbox. Toss it in, stop thinking about it.
export default function HeroFlow() {
  const [animate, setAnimate] = useState(false);

  useEffect(() => {
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduce) return;
    const timeout = setTimeout(() => setAnimate(true), 600);
    return () => clearTimeout(timeout);
  }, []);

  return (
    <div className="mb-8 flex items-end gap-1" role="img" aria-label="Ramble tosses your thought into your agent's inbox">
      {/* Ramble mark */}
      <div className="flex h-16 w-16 shrink-0 items-center justify-center rounded-2xl bg-white shadow-sm ring-1 ring-stone-200/80 sm:h-20 sm:w-20">
        <svg width="56" height="56" viewBox="0 0 100 100" fill="none" aria-hidden="true">
          <rect x="53" y="34" width="10" height="32" rx="5" fill="currentColor" className="text-stone-800" />
          <rect x="66" y="26" width="10" height="48" rx="5" fill="currentColor" className="text-stone-800" />
          <rect x="79" y="34" width="10" height="32" rx="5" fill="currentColor" className="text-stone-800" />
          <circle cx="36" cy="50" r="22" fill="#D7263D" className={animate ? "hf-launch" : ""} />
        </svg>
      </div>

      {/* Arc + box */}
      <svg
        className="h-16 w-[132px] shrink-0 sm:h-20 sm:w-[160px]"
        viewBox="0 0 160 80"
        fill="none"
        aria-hidden="true"
      >
        {/* dotted throw path */}
        <path
          d="M6 40 Q 62 -14 124 40"
          stroke="currentColor"
          strokeWidth="1.5"
          strokeDasharray="2 5"
          strokeLinecap="round"
          className="text-stone-400"
        />
        {/* the thought */}
        {animate && <circle r="5" fill="#D7263D" className="hf-toss" />}
        {/* open box */}
        <g className={animate ? "hf-box" : ""}>
          <path
            d="M104 44 L108 74 H140 L144 44"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinejoin="round"
            strokeLinecap="round"
            className="text-stone-800"
            fill="white"
          />
          <path d="M100 44 H148" stroke="currentColor" strokeWidth="2" strokeLinecap="round" className="text-stone-800" />
        </g>
      </svg>

      <style jsx>{`
        @keyframes hf-launch {
          0%, 100% { transform: scale(1); }
          6% { transform: scale(0.9); }
          14% { transform: scale(1.08); }
          24% { transform: scale(1); }
        }
        @keyframes hf-toss {
          0%, 10% { offset-distance: 0%; opacity: 0; }
          14% { opacity: 1; }
          58% { offset-distance: 100%; opacity: 1; }
          64%, 100% { offset-distance: 100%; opacity: 0; }
        }
        @keyframes hf-box {
          0%, 56%, 76%, 100% { transform: translateY(0); }
          62% { transform: translateY(2px); }
        }
        :global(.hf-launch) {
          transform-origin: 36px 50px;
          animation: hf-launch 2.6s ease-in-out infinite;
        }
        .hf-toss {
          offset-path: path("M6 40 Q 62 -14 124 52");
          offset-rotate: 0deg;
          animation: hf-toss 2.6s cubic-bezier(0.45, 0, 0.55, 1) infinite;
        }
        .hf-box {
          animation: hf-box 2.6s ease-in-out infinite;
        }
      `}</style>
    </div>
  );
}
