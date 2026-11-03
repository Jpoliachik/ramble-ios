"use client";

import { useEffect, useRef, useState } from "react";
import type { ReactNode } from "react";

// Subtle pop when the element first scrolls into view. Skipped for reduced motion.
export default function PopIn({ children, className = "" }: { children: ReactNode; className?: string }) {
  const ref = useRef<HTMLDivElement>(null);
  const [shown, setShown] = useState(false);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setShown(true);
          observer.disconnect();
        }
      },
      { threshold: 0.6 },
    );
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  return (
    <div
      ref={ref}
      className={`${className} origin-bottom-right transition-all duration-500 ease-[cubic-bezier(0.34,1.56,0.64,1)] ${
        shown ? "translate-y-0 scale-100 opacity-100" : "translate-y-2 scale-90 opacity-0"
      } motion-reduce:translate-y-0 motion-reduce:scale-100 motion-reduce:opacity-100 motion-reduce:transition-none`}
    >
      {children}
    </div>
  );
}
