"use client";

import { useState, useCallback } from "react";

const BASE_PATH = "/ramble";

export default function CopyLlmButton() {
  const [copied, setCopied] = useState(false);
  const [loading, setLoading] = useState(false);

  const copy = useCallback(async () => {
    setLoading(true);
    try {
      const res = await fetch(`${BASE_PATH}/llms-full.txt`);
      const text = await res.text();
      await navigator.clipboard.writeText(text);
      setCopied(true);
      setTimeout(() => setCopied(false), 2500);
    } catch {
      // Fallback: open the file in a new tab
      window.open(`${BASE_PATH}/llms-full.txt`, "_blank");
    } finally {
      setLoading(false);
    }
  }, []);

  return (
    <button
      onClick={copy}
      disabled={loading}
      className="inline-flex items-center gap-1.5 rounded-lg border border-stone-200 bg-white px-3 py-1.5 text-xs font-medium text-stone-600 shadow-sm transition-all hover:bg-stone-50 hover:text-stone-900 hover:shadow active:scale-95 disabled:opacity-50"
    >
      {copied ? (
        <>
          <svg className="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.5} strokeLinecap="round" strokeLinejoin="round">
            <polyline points="20 6 9 17 4 12" />
          </svg>
          Copied
        </>
      ) : (
        <>
          <svg className="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
            <rect x="9" y="9" width="13" height="13" rx="2" ry="2" />
            <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
          </svg>
          Copy llms.txt
        </>
      )}
    </button>
  );
}
