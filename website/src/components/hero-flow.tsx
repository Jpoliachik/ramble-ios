"use client";

import { useEffect, useState } from "react";
import { BrainCircuit, Zap, Code, Workflow, GitBranch } from "lucide-react";
import type { LucideIcon } from "lucide-react";

const destinations: { label: string; Icon: LucideIcon }[] = [
  { label: "Your Agent", Icon: BrainCircuit },
  { label: "Zapier", Icon: Zap },
  { label: "Your API", Icon: Code },
  { label: "Make", Icon: Workflow },
  { label: "n8n", Icon: GitBranch },
];

const SLIDE_MS = 350;

export default function HeroFlow() {
  const [animate, setAnimate] = useState(false);
  const [index, setIndex] = useState(0);
  const [prevIndex, setPrevIndex] = useState<number | null>(null);

  useEffect(() => {
    const timeout = setTimeout(() => setAnimate(true), 600);
    return () => clearTimeout(timeout);
  }, []);

  useEffect(() => {
    if (prevIndex === null) return;
    const t = setTimeout(() => setPrevIndex(null), SLIDE_MS);
    return () => clearTimeout(t);
  }, [prevIndex]);

  const advance = () => {
    setIndex((curr) => {
      setPrevIndex(curr);
      return (curr + 1) % destinations.length;
    });
  };

  const Current = destinations[index];
  const Prev = prevIndex !== null ? destinations[prevIndex] : null;

  return (
    <div className="mb-8 flex items-center gap-3 sm:gap-4" aria-label="Ramble sends transcripts to your destination of choice">
      {/* Left tile: Ramble app icon */}
      <div className="flex h-16 w-16 sm:h-20 sm:w-20 shrink-0 items-center justify-center rounded-2xl bg-white shadow-sm ring-1 ring-stone-200/80">
        <svg
          width="56"
          height="56"
          viewBox="0 0 100 100"
          fill="none"
          xmlns="http://www.w3.org/2000/svg"
          aria-label="Ramble"
        >
          <rect
            x="53" y="34" width="10" height="32" rx="5"
            fill="currentColor"
            className={`text-stone-800 ${animate ? "hf-bar-1" : ""}`}
          />
          <rect
            x="66" y="26" width="10" height="48" rx="5"
            fill="currentColor"
            className={`text-stone-800 ${animate ? "hf-bar-2" : ""}`}
          />
          <rect
            x="79" y="34" width="10" height="32" rx="5"
            fill="currentColor"
            className={`text-stone-800 ${animate ? "hf-bar-3" : ""}`}
          />
          <circle
            cx="36" cy="50" r="22"
            fill="#D7263D"
            className={animate ? "hf-pulse" : ""}
          />
        </svg>
      </div>

      {/* Arrow with traveling dot */}
      <div className="relative flex h-3 w-10 sm:w-16 shrink-0 items-center text-stone-400">
        <div className="h-[1.5px] w-full rounded-full bg-current" />
        <svg
          className="absolute -right-[2px] top-1/2 -translate-y-1/2"
          width="10" height="10" viewBox="0 0 10 10" fill="none"
          aria-hidden="true"
        >
          <path d="M1.5 1.5 L6 5 L1.5 8.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
        {animate && (
          <span
            aria-hidden="true"
            className="hf-dot absolute top-1/2 h-3 w-3 rounded-full bg-red-500"
            style={{ boxShadow: "0 0 12px rgba(215, 38, 61, 0.6)" }}
            onAnimationIteration={advance}
          />
        )}
      </div>

      {/* Right tile: cycling destination */}
      <div
        className={`flex shrink-0 items-center rounded-2xl bg-white px-3 py-2.5 sm:px-4 sm:py-3 shadow-sm ring-1 ring-stone-200/80 ${animate ? "hf-tile-flash" : ""}`}
      >
        <div className="relative h-5 sm:h-6 w-[5.75rem] sm:w-[6.5rem] overflow-hidden">
          {/* Outgoing label */}
          {Prev && (
            <div
              key={`prev-${prevIndex}`}
              className="hf-slide-out absolute inset-0 flex items-center gap-2"
              aria-hidden="true"
            >
              <Prev.Icon className="h-4 w-4 shrink-0 text-red-500" strokeWidth={2.25} />
              <span className="whitespace-nowrap text-xs sm:text-sm font-medium text-stone-700">
                {Prev.label}
              </span>
            </div>
          )}
          {/* Incoming / current label */}
          <div
            key={`curr-${index}`}
            className={`absolute inset-0 flex items-center gap-2 ${Prev ? "hf-slide-in" : ""}`}
          >
            <Current.Icon className="h-4 w-4 shrink-0 text-red-500" strokeWidth={2.25} aria-hidden="true" />
            <span className="whitespace-nowrap text-xs sm:text-sm font-medium text-stone-700">
              {Current.label}
            </span>
          </div>
        </div>
        <span className="sr-only">
          Send to your agent, Zapier, your API, Make, or n8n.
        </span>
      </div>

      <style jsx>{`
        @keyframes hf-pulse {
          0%, 100% { transform: scale(1); }
          8% { transform: scale(1.14); }
          20% { transform: scale(1); }
        }
        @keyframes hf-bar-1 {
          0%, 100% { transform: scaleY(1); }
          14% { transform: scaleY(1.2); }
          28% { transform: scaleY(1); }
        }
        @keyframes hf-bar-2 {
          0%, 100% { transform: scaleY(1); }
          22% { transform: scaleY(1.24); }
          38% { transform: scaleY(1); }
        }
        @keyframes hf-bar-3 {
          0%, 100% { transform: scaleY(1); }
          30% { transform: scaleY(1.28); }
          46% { transform: scaleY(1); }
        }
        @keyframes hf-dot {
          0%, 6% { left: 0%; opacity: 0; }
          10% { left: 0%; opacity: 1; }
          58% { left: 100%; opacity: 1; }
          66% { left: 100%; opacity: 0; }
          100% { left: 100%; opacity: 0; }
        }
        @keyframes hf-tile-flash {
          0%, 56%, 92%, 100% {
            box-shadow: 0 1px 2px rgba(0,0,0,0.04);
          }
          62%, 88% {
            box-shadow: 0 0 0 5px rgba(215, 38, 61, 0.2), 0 1px 2px rgba(0,0,0,0.04);
          }
        }
        @keyframes hf-slide-in {
          from { transform: translateY(100%); opacity: 0; }
          to { transform: translateY(0); opacity: 1; }
        }
        @keyframes hf-slide-out {
          from { transform: translateY(0); opacity: 1; }
          to { transform: translateY(-100%); opacity: 0; }
        }

        :global(.hf-pulse) {
          transform-origin: 36px 50px;
          animation: hf-pulse 2s ease-in-out infinite;
        }
        :global(.hf-bar-1) {
          transform-box: fill-box;
          transform-origin: center;
          animation: hf-bar-1 2s ease-in-out infinite;
        }
        :global(.hf-bar-2) {
          transform-box: fill-box;
          transform-origin: center;
          animation: hf-bar-2 2s ease-in-out infinite;
        }
        :global(.hf-bar-3) {
          transform-box: fill-box;
          transform-origin: center;
          animation: hf-bar-3 2s ease-in-out infinite;
        }
        .hf-dot {
          transform: translate(-50%, -50%);
          animation: hf-dot 2s linear infinite;
        }
        .hf-tile-flash {
          animation: hf-tile-flash 2s ease-in-out infinite;
        }
        .hf-slide-in {
          animation: hf-slide-in 350ms ease-out both;
        }
        .hf-slide-out {
          animation: hf-slide-out 350ms ease-in both;
        }
      `}</style>
    </div>
  );
}
