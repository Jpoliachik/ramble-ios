"use client";

import { useEffect, useRef, useState } from "react";
import { Bot, Check, Mic } from "lucide-react";

/*
  Hero motion graphic: you say something to your watch, it hops through your
  phone, and lands with your agent. Everything is drawn in HTML/CSS on a fixed
  440×440 stage that is scaled down at smaller breakpoints, so it sits on the
  page background with nothing to match.
*/

type Thought = { said: string; item: string; tag: string };

const thoughts: Thought[] = [
  { said: "Add oat milk to my to-do list.", item: "Oat milk", tag: "To-do" },
  { said: "Remind me to call Sam after lunch.", item: "Call Sam", tag: "1:00 PM" },
  { said: "Idea: walking meetings on Fridays.", item: "Walking meetings", tag: "Ideas" },
];

// Beats of one loop, in ms from the start of the loop.
const BEATS = [
  0, //    0 idle: watch shows the record button
  600, //  1 recording: tap, waveform, the words appear
  3100, // 2 sent: check on the watch, the thought leaves
  4000, // 3 the watch is back to idle. You're done.
  4100, // 4 the phone transcribes
  4700, // 5 the text heads to the agent
  5300, // 6 it lands with your agent
  5900, // 7 handled
];
const LOOP_MS = 8600;
const TYPE_MS = 52;

// Motion paths in stage coordinates.
const PATH_TO_PHONE = "M184 262 C 238 262, 246 140, 302 140";
const PATH_TO_AGENT = "M352 246 C 352 262, 340 270, 330 292";

type AgentItem = { key: number; item: string; tag: string; done: boolean };

export default function HeroMotion() {
  const [beat, setBeat] = useState(0);
  const [cycle, setCycle] = useState(0);
  const [typed, setTyped] = useState(0);
  const [reduced, setReduced] = useState(false);
  const [items, setItems] = useState<AgentItem[]>([
    { key: -1, item: "Dentist", tag: "Thursday", done: true },
  ]);
  const [phoneItems, setPhoneItems] = useState<{ key: number; said: string }[]>([]);
  const cycleRef = useRef(0);

  const thought = thoughts[cycle % thoughts.length];

  useEffect(() => {
    const mq = window.matchMedia("(prefers-reduced-motion: reduce)");
    const update = () => setReduced(mq.matches);
    update();
    mq.addEventListener("change", update);
    return () => mq.removeEventListener("change", update);
  }, []);

  // Drive the beats of each loop.
  useEffect(() => {
    if (reduced) return;
    const timers: ReturnType<typeof setTimeout>[] = [];
    const runLoop = () => {
      const c = cycleRef.current;
      const t = thoughts[c % thoughts.length];
      setBeat(0);
      setTyped(0);
      BEATS.forEach((at, i) => {
        if (i === 0) return;
        timers.push(
          setTimeout(() => {
            setBeat(i);
            if (i === 4) {
              setPhoneItems((prev) => [{ key: c, said: t.said }, ...prev].slice(0, 4));
            }
            if (i === 6) {
              setItems((prev) => [{ key: c, item: t.item, tag: t.tag, done: false }, ...prev].slice(0, 3));
            }
            if (i === 7) {
              setItems((prev) => prev.map((it) => (it.key === c ? { ...it, done: true } : it)));
            }
          }, at),
        );
      });
      timers.push(
        setTimeout(() => {
          cycleRef.current = c + 1;
          setCycle(c + 1);
          runLoop();
        }, LOOP_MS),
      );
    };
    const start = setTimeout(runLoop, 900);
    return () => {
      clearTimeout(start);
      timers.forEach(clearTimeout);
    };
  }, [reduced]);

  // Type the words while recording.
  useEffect(() => {
    if (reduced || beat !== 1) return;
    const id = setInterval(() => {
      setTyped((n) => (n >= thought.said.length ? n : n + 1));
    }, TYPE_MS);
    return () => clearInterval(id);
  }, [beat, reduced, thought.said.length]);

  // Reduced motion: one calm, finished frame.
  const b = reduced ? 3 : beat;
  const shownItems = reduced
    ? [
        { key: 0, item: thoughts[0].item, tag: thoughts[0].tag, done: true },
        { key: -1, item: "Dentist", tag: "Thursday", done: true },
      ]
    : items;
  const words = reduced ? thoughts[0].said : thought.said.slice(0, typed);
  const shownPhoneItems = reduced ? [{ key: 0, said: thoughts[0].said }] : phoneItems;

  const recording = b === 1;
  const sent = b === 2;
  const bubbleVisible = reduced || (b >= 1 && b <= 2);
  const phoneActive = b >= 4 && b <= 5;
  const transcribing = !reduced && b === 4;
  const agentGlow = b === 6 || b === 7;

  return (
    <div
      role="img"
      aria-label="You say “Add oat milk to my to-do list” to your Apple Watch. Your iPhone transcribes it and sends it on, and it lands with your agent."
      className="relative h-[320px] w-[320px] sm:h-[400px] sm:w-[400px] lg:h-[440px] lg:w-[440px]"
    >
      <div className="hm-stage absolute left-0 top-0 h-[440px] w-[440px] origin-top-left">
        {/* Faint route: watch → phone → agent */}
        <svg className="absolute inset-0" width="440" height="440" viewBox="0 0 440 440" fill="none" aria-hidden="true">
          <path d={PATH_TO_PHONE} stroke="#d5d0c8" strokeWidth="1.5" strokeDasharray="2 6" strokeLinecap="round" />
          <path d={PATH_TO_AGENT} stroke="#d5d0c8" strokeWidth="1.5" strokeDasharray="2 6" strokeLinecap="round" />
        </svg>

        {/* What you say */}
        <div
          className={`absolute left-[4px] top-[70px] w-[236px] transition-all duration-500 ease-out ${
            bubbleVisible ? "translate-y-0 opacity-100" : "translate-y-2 opacity-0"
          }`}
        >
          <div className="relative rounded-2xl bg-white px-4 py-3 shadow-sm ring-1 ring-stone-200/80">
            <p className="min-h-[2.6em] font-serif text-[15px] italic leading-snug text-stone-800">
              <span aria-hidden="true">“</span>
              {words}
              {recording && typed < thought.said.length && (
                <span className="hm-caret ml-[1px] inline-block h-[1em] w-[1.5px] translate-y-[2px] bg-brand" />
              )}
              {(!recording || typed >= thought.said.length) && words.length > 0 && <span aria-hidden="true">”</span>}
            </p>
            <span className="absolute -bottom-[6px] left-[86px] h-3 w-3 rotate-45 bg-white ring-1 ring-stone-200/80 [clip-path:polygon(100%_0,100%_100%,0_100%)]" />
          </div>
        </div>

        {/* Apple Watch */}
        <div className="absolute left-[6px] top-[168px] z-10 w-[178px]">
          <div className="relative">
            <span aria-hidden="true" className="absolute -left-[5px] top-[34%] h-8 w-[6px] rounded-l-sm bg-brand/85" />
            <span aria-hidden="true" className="absolute -right-[7px] top-[22%] h-7 w-[8px] rounded-r-md bg-stone-700" />
            <span aria-hidden="true" className="absolute -right-[5px] top-[46%] h-9 w-[6px] rounded-r-sm bg-stone-700" />
            <div className="rounded-[44px] bg-stone-900 p-[8px] shadow-[0_30px_60px_-14px_rgba(26,25,23,0.45)] ring-1 ring-black/5">
              <div className="relative h-[196px] overflow-hidden rounded-[37px] bg-black">
                <span className="absolute right-[22px] top-[16px] text-[13px] font-semibold tabular-nums text-white">
                  9:41
                </span>
                <span className="absolute left-[22px] top-[16px] text-[13px] font-semibold text-brand">Ramble</span>

                {/* Idle: the record button */}
                <div
                  className={`absolute inset-0 flex items-center justify-center transition-all duration-500 ${
                    b === 0 || b >= 3 ? "scale-100 opacity-100" : "scale-90 opacity-0"
                  }`}
                >
                  <div className="mt-4 flex h-[84px] w-[84px] items-center justify-center rounded-full bg-brand">
                    <Mic className="h-8 w-8 text-white" strokeWidth={2.25} aria-hidden="true" />
                  </div>
                </div>
                {recording && <span className="hm-tap absolute left-1/2 top-[56%] h-[84px] w-[84px] rounded-full" />}

                {/* Recording: waveform and timer */}
                <div
                  className={`absolute inset-0 flex flex-col items-center justify-center gap-4 pt-4 transition-opacity duration-300 ${
                    recording ? "opacity-100" : "opacity-0"
                  }`}
                >
                  <div className="flex h-[52px] items-center gap-[5px]">
                    {[0, 1, 2, 3, 4, 5, 6].map((i) => (
                      <span
                        key={i}
                        className={`w-[7px] rounded-full bg-brand ${recording ? "hm-bar" : ""}`}
                        style={{ height: 52, animationDelay: `${(i * 137) % 520}ms`, transform: "scaleY(0.25)" }}
                      />
                    ))}
                  </div>
                  <div className="flex items-center gap-2">
                    <span className="h-[10px] w-[10px] rounded-[3px] bg-white/90" />
                    <span className="text-[13px] font-medium tabular-nums text-white/80">
                      0:0{Math.min(3, Math.floor(typed / 9) + 1)}
                    </span>
                  </div>
                </div>

                {/* Sent */}
                <div
                  className={`absolute inset-0 flex flex-col items-center justify-center gap-2 pt-4 transition-all duration-300 ${
                    sent ? "scale-100 opacity-100" : "scale-95 opacity-0"
                  }`}
                >
                  <div className="flex h-[60px] w-[60px] items-center justify-center rounded-full bg-brand/20">
                    <Check className="h-8 w-8 text-brand" strokeWidth={2.75} aria-hidden="true" />
                  </div>
                  <span className="text-[14px] font-semibold text-white">Sent</span>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* iPhone: secondary, does the work in the background */}
        <div
          className={`absolute left-[302px] top-[30px] w-[104px] transition-opacity duration-500 ${
            phoneActive ? "opacity-100" : "opacity-80"
          }`}
        >
          <div
            className={`rounded-[22px] bg-stone-900 p-[4px] shadow-[0_18px_36px_-14px_rgba(26,25,23,0.35)] ring-1 ring-black/5 transition-shadow duration-500 ${
              phoneActive ? "hm-phone-glow" : ""
            }`}
          >
            <div className="relative h-[208px] overflow-hidden rounded-[18px] bg-white px-[8px] pt-[8px]">
              <span className="mx-auto block h-[7px] w-[30px] rounded-full bg-stone-900" />
              <p className="mt-[8px] font-serif text-[10px] font-semibold italic text-stone-900">
                <span className="mr-[3px] inline-block h-[5px] w-[5px] rounded-full bg-brand align-middle" />
                Ramble
              </p>
              <div className="mt-[6px] space-y-[5px]">
                {shownPhoneItems.map((row, i) => {
                  const pending = transcribing && i === 0;
                  return (
                    <div key={row.key} className="hm-item rounded-[7px] bg-stone-100 px-[6px] py-[5px]">
                      {pending ? (
                        <div className="space-y-[3px] py-[1px]">
                          <span className="hm-shimmer block h-[4px] w-full rounded-full" />
                          <span className="hm-shimmer block h-[4px] w-2/3 rounded-full" />
                        </div>
                      ) : (
                        <p className="text-[7.5px] leading-[1.3] text-stone-800">{row.said}</p>
                      )}
                      <p className="mt-[3px] flex items-center gap-[3px] text-[6.5px] font-medium text-stone-500">
                        <span className={`inline-block h-[4px] w-[4px] rounded-full ${pending ? "bg-stone-300" : "bg-brand"}`} />
                        {pending ? "Transcribing" : "Sent to agent"}
                      </p>
                    </div>
                  );
                })}
                {[0, 1, 2].slice(0, Math.max(0, 3 - shownPhoneItems.length)).map((i) => (
                  <div key={`s-${i}`} className="space-y-[3px] rounded-[7px] bg-stone-100 px-[6px] py-[6px]">
                    <span className="block h-[4px] w-full rounded-full bg-stone-200" />
                    <span className="block h-[4px] w-1/2 rounded-full bg-stone-200" />
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>

        {/* Your agent */}
        <div
          className={`absolute left-[218px] top-[292px] w-[214px] rounded-2xl bg-white p-3 shadow-sm ring-1 transition-shadow duration-500 ${
            agentGlow ? "ring-brand/40 hm-agent-glow" : "ring-stone-200/80"
          }`}
        >
          <div className="flex items-center gap-2">
            <span className="flex h-7 w-7 items-center justify-center rounded-full bg-brand/10">
              <Bot className="h-4 w-4 text-brand-text" strokeWidth={2.25} aria-hidden="true" />
            </span>
            <span className="text-[13px] font-medium text-stone-800">Your agent</span>
          </div>
          <ul className="mt-2.5 space-y-1.5">
            {shownItems.map((it, i) => (
              <li
                key={it.key}
                className={`hm-item flex items-center gap-2 ${i === 2 ? "opacity-40" : ""}`}
              >
                <span
                  className={`flex h-4 w-4 shrink-0 items-center justify-center rounded-full transition-colors duration-300 ${
                    it.done ? "bg-brand" : "ring-[1.5px] ring-inset ring-stone-300"
                  }`}
                >
                  {it.done && <Check className="hm-check h-2.5 w-2.5 text-white" strokeWidth={3.5} aria-hidden="true" />}
                </span>
                <span className="truncate text-[12.5px] text-stone-700">{it.item}</span>
                <span className="ml-auto shrink-0 rounded-full bg-stone-100 px-2 py-[1px] text-[10.5px] text-stone-500">
                  {it.tag}
                </span>
              </li>
            ))}
          </ul>
        </div>

        {/* The thought, travelling */}
        {!reduced && b === 2 && (
          <span key={`a-${cycle}`} className="hm-packet hm-packet-a" style={{ offsetPath: `path("${PATH_TO_PHONE}")` }} />
        )}
        {!reduced && b === 5 && (
          <span key={`b-${cycle}`} className="hm-packet hm-packet-b" style={{ offsetPath: `path("${PATH_TO_AGENT}")` }} />
        )}
      </div>

      <style jsx>{`
        .hm-stage {
          transform: scale(0.7273);
        }
        @media (min-width: 640px) {
          .hm-stage {
            transform: scale(0.9091);
          }
        }
        @media (min-width: 1024px) {
          .hm-stage {
            transform: none;
          }
        }

        :global(.hm-packet) {
          position: absolute;
          left: 0;
          top: 0;
          width: 12px;
          height: 12px;
          border-radius: 9999px;
          background: var(--color-brand);
          box-shadow: 0 0 0 4px rgba(217, 119, 6, 0.18), 0 0 16px rgba(217, 119, 6, 0.55);
          offset-anchor: center;
          offset-rotate: 0deg;
          z-index: 20;
        }
        :global(.hm-packet-a) {
          animation: hm-travel 850ms cubic-bezier(0.55, 0, 0.35, 1) 150ms both;
        }
        :global(.hm-packet-b) {
          animation: hm-travel 520ms cubic-bezier(0.5, 0, 0.4, 1) 40ms both;
        }
        @keyframes hm-travel {
          0% {
            offset-distance: 0%;
            opacity: 0;
            transform: scale(0.4);
          }
          15% {
            opacity: 1;
            transform: scale(1);
          }
          85% {
            opacity: 1;
            transform: scale(1);
          }
          100% {
            offset-distance: 100%;
            opacity: 0;
            transform: scale(0.5);
          }
        }

        :global(.hm-bar) {
          animation: hm-bar 620ms ease-in-out infinite alternate;
        }
        @keyframes hm-bar {
          0% {
            transform: scaleY(0.22);
          }
          100% {
            transform: scaleY(1);
          }
        }

        :global(.hm-tap) {
          transform: translate(-50%, -50%);
          animation: hm-tap 700ms ease-out both;
        }
        @keyframes hm-tap {
          0% {
            box-shadow: 0 0 0 0 rgba(255, 255, 255, 0.5);
          }
          100% {
            box-shadow: 0 0 0 18px rgba(255, 255, 255, 0);
          }
        }

        :global(.hm-caret) {
          animation: hm-blink 900ms steps(1) infinite;
        }
        @keyframes hm-blink {
          50% {
            opacity: 0;
          }
        }

        :global(.hm-shimmer) {
          background: linear-gradient(90deg, #e7e4df 0%, #f5f3f0 50%, #e7e4df 100%);
          background-size: 200% 100%;
          animation: hm-shimmer 900ms linear infinite;
        }
        @keyframes hm-shimmer {
          from {
            background-position: 200% 0;
          }
          to {
            background-position: 0 0;
          }
        }

        :global(.hm-phone-glow) {
          box-shadow: 0 0 0 5px rgba(217, 119, 6, 0.14), 0 18px 36px -14px rgba(26, 25, 23, 0.35);
        }
        :global(.hm-agent-glow) {
          box-shadow: 0 0 0 5px rgba(217, 119, 6, 0.12), 0 1px 2px rgba(0, 0, 0, 0.04);
        }

        :global(.hm-item) {
          animation: hm-item-in 420ms cubic-bezier(0.2, 0.8, 0.2, 1) both;
        }
        @keyframes hm-item-in {
          from {
            opacity: 0;
            transform: translateY(-6px);
          }
        }
        :global(.hm-check) {
          animation: hm-pop 300ms cubic-bezier(0.3, 1.6, 0.5, 1) both;
        }
        @keyframes hm-pop {
          from {
            transform: scale(0.3);
          }
        }

        @media (prefers-reduced-motion: reduce) {
          :global(.hm-item),
          :global(.hm-check),
          :global(.hm-shimmer) {
            animation: none;
          }
        }
      `}</style>
    </div>
  );
}
