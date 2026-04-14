"use client";

import { useEffect, useState } from "react";

const sections = [
  { id: "step-1", label: "1. Enable the webhook" },
  { id: "step-2", label: "2. Connect a destination" },
  { id: "platforms", label: "Automation platforms", indent: true },
  { id: "custom", label: "Build your own endpoint", indent: true },
  { id: "step-3", label: "3. Test it" },
];

export default function DocsSidebar() {
  const [activeId, setActiveId] = useState<string>("");

  useEffect(() => {
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            setActiveId(entry.target.id);
          }
        }
      },
      { rootMargin: "-64px 0px -75% 0px", threshold: 0 }
    );

    for (const section of sections) {
      const el = document.getElementById(section.id);
      if (el) observer.observe(el);
    }

    return () => observer.disconnect();
  }, []);

  return (
    <nav className="hidden lg:block">
      <div className="sticky top-8 text-sm">
        <p className="font-semibold text-stone-900">On this page</p>
        <div className="mt-3 space-y-0.5">
          {sections.map((section) => (
            <a
              key={section.id}
              href={`#${section.id}`}
              className={`block py-1 transition-colors ${
                section.indent ? "pl-4 text-xs" : ""
              } ${
                activeId === section.id
                  ? "text-stone-900 font-medium"
                  : "text-stone-400 hover:text-stone-900"
              }`}
            >
              {section.label}
            </a>
          ))}
        </div>
      </div>
    </nav>
  );
}
