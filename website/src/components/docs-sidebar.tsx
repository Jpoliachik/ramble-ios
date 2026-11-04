"use client";

import { useEffect, useState } from "react";
import Link from "next/link";

type Section = { id: string; label: string; indent?: boolean };

export type DocsPage = "agent" | "webhooks";

const pages: { key: DocsPage; href: string; label: string }[] = [
  { key: "agent", href: "/docs", label: "Connect your agent" },
  { key: "webhooks", href: "/docs/webhooks", label: "Webhooks" },
];

const sectionsByPage: Record<DocsPage, Section[]> = {
  agent: [
    { id: "pairing", label: "Pairing" },
    { id: "agent-instructions", label: "Instructions for the agent" },
    { id: "checking", label: "Checking cheaply" },
    { id: "api", label: "API" },
    { id: "connections", label: "Tokens and connections" },
    { id: "requests", label: "Making requests" },
    { id: "relay-or-webhook", label: "Relay or webhook" },
    { id: "platforms", label: "Platform notes" },
  ],
  webhooks: [
    { id: "step-1", label: "1. Add a destination" },
    { id: "step-2", label: "2. Connect a destination" },
    { id: "platforms", label: "Automation platforms", indent: true },
    { id: "custom", label: "Build your own endpoint", indent: true },
    { id: "step-3", label: "3. Test it" },
  ],
};

export default function DocsSidebar({ page }: { page: DocsPage }) {
  const sections = sectionsByPage[page];
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
  }, [sections]);

  return (
    <nav className="hidden lg:block">
      <div className="sticky top-20 text-sm">
        <p className="font-semibold text-stone-900">Docs</p>
        <div className="mt-3 space-y-0.5">
          {pages.map((p) => (
            <Link
              key={p.key}
              href={p.href}
              className={`block py-1 transition-colors ${
                p.key === page ? "text-brand-text font-medium" : "text-stone-500 hover:text-stone-900"
              }`}
            >
              {p.label}
            </Link>
          ))}
        </div>

        <p className="mt-8 font-semibold text-stone-900">On this page</p>
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
                  : "text-stone-500 hover:text-stone-900"
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
