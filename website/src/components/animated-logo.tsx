"use client";

import { useEffect, useState } from "react";

export default function AnimatedLogo() {
  const [animate, setAnimate] = useState(false);

  useEffect(() => {
    // Start the animation after mount
    const timeout = setTimeout(() => setAnimate(true), 600);
    return () => clearTimeout(timeout);
  }, []);

  return (
    <div className="mb-8 flex items-center justify-center">
      <svg
        width="80"
        height="80"
        viewBox="0 0 100 100"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
        aria-label="Ramble logo"
      >
        <defs>
          <filter id="logo-shadow" x="-20%" y="-20%" width="140%" height="140%">
            <feDropShadow dx="0" dy="1" stdDeviation="2" floodColor="#000" floodOpacity="0.15" />
          </filter>
        </defs>

        {/* Bars drawn first so circle renders on top */}
        {/* Bar 1 (closest to circle, tucks under) */}
        <rect
          x="53"
          y="34"
          width="10"
          height="32"
          rx="5"
          fill="currentColor"
          filter="url(#logo-shadow)"
          className={`text-stone-800 origin-center ${animate ? "animate-bar-1" : ""}`}
        />

        {/* Bar 2 (middle, tallest) */}
        <rect
          x="66"
          y="26"
          width="10"
          height="48"
          rx="5"
          fill="currentColor"
          filter="url(#logo-shadow)"
          className={`text-stone-800 origin-center ${animate ? "animate-bar-2" : ""}`}
        />

        {/* Bar 3 (farthest, same height as bar 1) */}
        <rect
          x="79"
          y="34"
          width="10"
          height="32"
          rx="5"
          fill="currentColor"
          filter="url(#logo-shadow)"
          className={`text-stone-800 origin-center ${animate ? "animate-bar-3" : ""}`}
        />

        {/* Red circle (on top) */}
        <circle
          cx="36"
          cy="50"
          r="22"
          fill="#D93025"
          filter="url(#logo-shadow)"
          className={animate ? "animate-logo-pulse" : ""}
        />
      </svg>

      <style jsx>{`
        @keyframes logo-pulse {
          0%, 100% {
            transform-origin: 36px 50px;
            transform: scale(1);
          }
          10% {
            transform-origin: 36px 50px;
            transform: scale(1.12);
          }
          22% {
            transform-origin: 36px 50px;
            transform: scale(1);
          }
        }

        @keyframes bar-expand-1 {
          0%, 100% {
            transform: scaleY(1);
          }
          22% {
            transform: scaleY(1.18);
          }
          38% {
            transform: scaleY(1);
          }
        }

        @keyframes bar-expand-2 {
          0%, 100% {
            transform: scaleY(1);
          }
          34% {
            transform: scaleY(1.22);
          }
          50% {
            transform: scaleY(1);
          }
        }

        @keyframes bar-expand-3 {
          0%, 100% {
            transform: scaleY(1);
          }
          46% {
            transform: scaleY(1.26);
          }
          62% {
            transform: scaleY(1);
          }
        }

        .animate-logo-pulse {
          animation: logo-pulse 2.8s ease-in-out infinite;
        }

        .animate-bar-1 {
          transform-box: fill-box;
          transform-origin: center;
          animation: bar-expand-1 2.8s ease-in-out infinite;
        }

        .animate-bar-2 {
          transform-box: fill-box;
          transform-origin: center;
          animation: bar-expand-2 2.8s ease-in-out infinite;
        }

        .animate-bar-3 {
          transform-box: fill-box;
          transform-origin: center;
          animation: bar-expand-3 2.8s ease-in-out infinite;
        }
      `}</style>
    </div>
  );
}
