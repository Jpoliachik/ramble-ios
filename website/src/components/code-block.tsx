"use client";

import { useState, useCallback } from "react";

interface CodeBlockProps {
  children: string;
  language?: string;
  filename?: string;
}

export function CodeBlock({ children, language, filename }: CodeBlockProps) {
  const [copied, setCopied] = useState(false);

  const copy = useCallback(() => {
    navigator.clipboard.writeText(children).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    });
  }, [children]);

  return (
    <div className="group relative rounded-lg bg-stone-900 text-sm">
      {(filename || language) && (
        <div className="flex items-center justify-between border-b border-stone-700/50 px-4 py-2">
          <span className="font-mono text-xs text-stone-400">
            {filename || language}
          </span>
        </div>
      )}
      <button
        onClick={copy}
        className="absolute right-3 top-2.5 rounded-md border border-stone-700 bg-stone-800 px-2 py-1 font-mono text-xs text-stone-400 opacity-0 transition-opacity hover:bg-stone-700 hover:text-stone-200 group-hover:opacity-100"
        style={filename || language ? { top: "2.75rem" } : undefined}
      >
        {copied ? "Copied" : "Copy"}
      </button>
      <pre className="overflow-x-auto p-4 text-[13px] leading-relaxed text-stone-200">
        <code>{children}</code>
      </pre>
    </div>
  );
}

interface InlineCodeProps {
  children: React.ReactNode;
}

export function InlineCode({ children }: InlineCodeProps) {
  return (
    <code className="rounded bg-stone-100 px-1.5 py-0.5 font-mono text-[13px] text-stone-800">
      {children}
    </code>
  );
}
