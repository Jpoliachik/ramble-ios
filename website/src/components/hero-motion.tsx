"use client";

import { useEffect, useRef, useState } from "react";
import { Bot, Check, CircleCheck } from "lucide-react";

/*
  Hero motion graphic: you say something to your watch and it lands with your
  agent. Drawn in HTML/CSS on a fixed 440×440 stage, so it sits on the page
  background with nothing to match. By default the stage scales with the page
  breakpoints; pass `size` to pin it to one size (the OG video does this).

  The watch face mirrors the real Watch app (WatchRecordButtonView): an amber
  ring with a filled circle, and while recording three amber bars inside the
  ring with the timer below in amber serif.

  The loop never resets. Each thought pushes a new row onto the agent card and
  the oldest slides out.
*/

type Thought = { said: string; item: string; tag: string };

// Example thoughts. They play in a shuffled order, one per loop, and reshuffle
// after every pass. The first one is also the still frame for reduced motion.
const thoughts: Thought[] = [
  { said: "Add oat milk to my to-do list.", item: "Oat milk", tag: "To-do" },
  { said: "Remind me to call Sam after lunch.", item: "Call Sam", tag: "1:00 PM" },
  { said: "Idea: walking meetings on Fridays.", item: "Walking 1:1s", tag: "Ideas" },
  { said: "Book a haircut for next week.", item: "Haircut", tag: "Next week" },
  { said: "What was that podcast Maya mentioned?", item: "Podcast", tag: "Look up" },
  { said: "Draft a thank-you note to Alex.", item: "Note to Alex", tag: "Draft" },
  { said: "Move my 3pm to tomorrow.", item: "Move 3pm", tag: "Calendar" },
  { said: "Pick up dry cleaning on the way home.", item: "Dry cleaning", tag: "Errand" },
  { said: "Pay the water bill.", item: "Water bill", tag: "Bills" },
  { said: "Ask Priya about the Lisbon trip.", item: "Lisbon trip", tag: "Ask Priya" },
];

function shuffled(avoidFirst?: number): number[] {
  const order = thoughts.map((_, i) => i);
  for (let i = order.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [order[i], order[j]] = [order[j], order[i]];
  }
  // Don't play the same thought twice in a row across a reshuffle.
  if (order[0] === avoidFirst) [order[0], order[1]] = [order[1], order[0]];
  return order;
}

const TYPE_MS = 38;

// Beats of one loop, in ms from the start of the loop. Recording lasts as long
// as the words take to type out.
//   0 idle: record button, "Tap to record"
//   1 recording: tap, bars inside the ring, timer, the words appear
//   2 stopped: "Saved on watch", the thought leaves for the agent
//   3 it lands with your agent
//   4 handled
//   5 the watch is back to "Tap to record". You're done.
// The next loop starts while the agent row is still settling, so there's no
// visible restart.
function beatsFor(said: string) {
  const sentAt = 250 + said.length * TYPE_MS + 250;
  const beats = [0, 250, sentAt, sentAt + 750, sentAt + 1100, sentAt + 1500];
  return { beats, loopMs: sentAt + 2300 };
}

// The one hop, from the watch to the agent, in stage coordinates.
const PATH_TO_AGENT = "M222 284 C 262 284, 276 210, 309 206";

type AgentRow = { key: number; item: string; tag: string; done: boolean };

const initialAgent: AgentRow[] = [
  { key: -1, item: "Table for two", tag: "Friday", done: true },
  { key: -2, item: "Desks", tag: "Research", done: true },
];

const AGENT_ROW_H = 27;
const VISIBLE = 2;

export default function HeroMotion({ size }: { size?: number }) {
  const [beat, setBeat] = useState(0);
  const [cycle, setCycle] = useState(0);
  const [thought, setThought] = useState<Thought>(thoughts[0]);
  const [typed, setTyped] = useState(0);
  const [reduced, setReduced] = useState(false);
  const [agentRows, setAgentRows] = useState<AgentRow[]>(initialAgent);
  const cycleRef = useRef(0);

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
    let order = shuffled();
    const runLoop = () => {
      const c = cycleRef.current;
      const pos = c % thoughts.length;
      if (pos === 0 && c > 0) order = shuffled(order[order.length - 1]);
      const t = thoughts[order[pos]];
      const { beats, loopMs } = beatsFor(t.said);
      setCycle(c);
      setThought(t);
      setBeat(0);
      setTyped(0);
      beats.forEach((at, i) => {
        if (i === 0) return;
        timers.push(
          setTimeout(() => {
            setBeat(i);
            // Keep one extra row so the oldest can fade out instead of vanishing.
            if (i === 3)
              setAgentRows((prev) =>
                [{ key: c, item: t.item, tag: t.tag, done: false }, ...prev].slice(0, VISIBLE + 1),
              );
            if (i === 4) setAgentRows((prev) => prev.map((r) => (r.key === c ? { ...r, done: true } : r)));
          }, at),
        );
      });
      timers.push(
        setTimeout(() => {
          cycleRef.current = c + 1;
          runLoop();
        }, loopMs),
      );
    };
    const start = setTimeout(runLoop, 500);
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
  const b = reduced ? 5 : beat;
  const shownAgent = reduced
    ? [{ key: 0, item: thoughts[0].item, tag: thoughts[0].tag, done: true }, initialAgent[0]]
    : agentRows;
  const words = reduced ? thoughts[0].said : thought.said.slice(0, typed);

  const recording = b === 1;
  const saved = b >= 2 && b <= 4;
  const bubbleVisible = reduced || (b >= 1 && b <= 2);
  const agentGlow = !reduced && b >= 3;
  const seconds = Math.min(4, Math.floor((typed * TYPE_MS) / 1000) + 1);

  const fixed = size !== undefined;
  const boxStyle = fixed ? { width: size, height: size } : undefined;
  const stageStyle = fixed ? { transform: `scale(${size / 440})` } : undefined;

  return (
    <div
      role="img"
      aria-label="You say “Add oat milk to my to-do list” to your Apple Watch, and it lands with your agent."
      className={`relative ${fixed ? "" : "h-[320px] w-[320px] sm:h-[400px] sm:w-[400px] lg:h-[440px] lg:w-[440px]"}`}
      style={boxStyle}
    >
      <div
        className={`absolute left-0 top-0 h-[440px] w-[440px] origin-top-left ${fixed ? "" : "hm-stage"}`}
        style={stageStyle}
      >
        {/* Faint route: watch → agent */}
        <svg className="absolute inset-0" width="440" height="440" viewBox="0 0 440 440" fill="none" aria-hidden="true">
          <path d={PATH_TO_AGENT} stroke="#d5d0c8" strokeWidth="1.5" strokeDasharray="2 6" strokeLinecap="round" />
        </svg>

        {/* What you say */}
        <div
          className={`absolute left-[4px] top-[48px] z-20 w-[250px] transition-all duration-500 ease-out ${
            bubbleVisible ? "translate-y-0 opacity-100" : "translate-y-2 opacity-0"
          }`}
        >
          <div className="relative rounded-2xl bg-white px-4 py-3 shadow-sm ring-1 ring-stone-200/80">
            <p className="min-h-[2.6em] font-serif text-[16px] italic leading-snug text-stone-800">
              <span aria-hidden="true">“</span>
              {words}
              {recording && typed < thought.said.length && (
                <span className="hm-caret ml-[1px] inline-block h-[1em] w-[1.5px] translate-y-[2px] bg-brand" />
              )}
              {(!recording || typed >= thought.said.length) && words.length > 0 && <span aria-hidden="true">”</span>}
            </p>
            <span className="absolute -bottom-[6px] left-[100px] h-3 w-3 rotate-45 bg-white ring-1 ring-stone-200/80 [clip-path:polygon(100%_0,100%_100%,0_100%)]" />
          </div>
        </div>

        {/* Apple Watch */}
        <div
          className="hm-focus absolute left-[8px] top-[160px] z-10 w-[212px]"
          style={{ transformOrigin: "60% 50%", transform: `scale(${agentGlow ? 0.97 : 1})` }}
        >
          <div className="relative">
            <span aria-hidden="true" className="absolute -left-[6px] top-[34%] h-10 w-[7px] rounded-l-sm bg-brand/85" />
            <span aria-hidden="true" className="absolute -right-[8px] top-[22%] h-8 w-[9px] rounded-r-md bg-stone-700" />
            <span aria-hidden="true" className="absolute -right-[6px] top-[47%] h-11 w-[7px] rounded-r-sm bg-stone-700" />
            <div className="rounded-[52px] bg-stone-900 p-[9px] shadow-[0_30px_60px_-14px_rgba(26,25,23,0.45)] ring-1 ring-black/5">
              <div className="relative h-[230px] overflow-hidden rounded-[44px] bg-black">
                <span className="absolute right-[26px] top-[18px] text-[14px] font-semibold tabular-nums text-white">
                  9:41
                </span>

                {/* Record button: amber ring, filled circle at rest, three bars while recording */}
                <div className="absolute left-1/2 top-[50px] h-[100px] w-[100px] -translate-x-1/2">
                  <span className="absolute inset-0 rounded-full border-[5px] border-brand" />
                  <span
                    className={`absolute inset-[9px] rounded-full bg-brand transition-all duration-300 ${
                      recording ? "scale-50 opacity-0" : "scale-100 opacity-100"
                    }`}
                  />
                  <div
                    className={`absolute inset-0 flex items-center justify-center gap-[7px] transition-opacity duration-300 ${
                      recording ? "opacity-100" : "opacity-0"
                    }`}
                  >
                    {[0.7, 1, 0.8].map((s, i) => (
                      <span
                        key={i}
                        className={`w-[11px] rounded-full bg-brand ${recording ? "hm-bar" : ""}`}
                        style={{
                          height: 42 * s,
                          animationDelay: `${i * 170}ms`,
                          animationDuration: `${420 + i * 90}ms`,
                          transform: "scaleY(0.3)",
                        }}
                      />
                    ))}
                  </div>
                  {recording && <span className="hm-tap absolute left-1/2 top-1/2 h-[100px] w-[100px] rounded-full" />}
                </div>

                {/* Status line under the button */}
                <div className="absolute inset-x-0 top-[164px] flex h-[40px] items-center justify-center">
                  <span
                    className={`absolute font-serif text-[30px] font-bold tabular-nums text-brand transition-opacity duration-300 ${
                      recording ? "opacity-100" : "opacity-0"
                    }`}
                  >
                    0:0{seconds}
                  </span>
                  <span
                    className={`absolute flex items-center gap-1 text-[12px] text-stone-400 transition-opacity duration-300 ${
                      saved ? "opacity-100" : "opacity-0"
                    }`}
                  >
                    <CircleCheck className="h-3.5 w-3.5" strokeWidth={2} aria-hidden="true" />
                    Saved on watch
                  </span>
                  <span
                    className={`absolute text-[12px] text-stone-400 transition-opacity duration-300 ${
                      !recording && !saved ? "opacity-100" : "opacity-0"
                    }`}
                  >
                    Tap to record
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Your agent: a big icon heads the card */}
        <div
          className="hm-focus absolute left-[244px] top-[206px] z-10 w-[192px]"
          style={{ transformOrigin: "50% 0%", transform: `scale(${agentGlow ? 1.05 : 1})` }}
        >
          <div
            className={`relative rounded-2xl bg-white px-3 pb-3 pt-[36px] shadow-sm ring-1 transition-shadow duration-500 ${
              agentGlow ? "ring-brand/40 hm-agent-glow" : "ring-stone-200/80"
            }`}
          >
            <span
              className={`absolute -top-[30px] left-1/2 flex h-[60px] w-[60px] -translate-x-1/2 items-center justify-center rounded-full bg-white shadow-sm ring-1 transition-shadow duration-500 ${
                agentGlow ? "ring-brand/40 hm-agent-glow" : "ring-stone-200/80"
              }`}
            >
              <span className="flex h-[50px] w-[50px] items-center justify-center rounded-full bg-brand/10">
                <Bot className="h-[28px] w-[28px] text-brand-text" strokeWidth={2} aria-hidden="true" />
              </span>
            </span>
            <p className="text-center text-[14px] font-medium text-stone-800">Agent</p>
            <ul className="relative mt-2" style={{ height: AGENT_ROW_H * VISIBLE }}>
              {shownAgent.map((it, i) => (
                <li
                  key={it.key}
                  className="hm-row absolute inset-x-0"
                  style={{ top: i * AGENT_ROW_H, opacity: i >= VISIBLE ? 0 : 1 }}
                >
                  <div className="hm-row-in flex h-[22px] items-center gap-2">
                    <span
                      className={`flex h-[17px] w-[17px] shrink-0 items-center justify-center rounded-full transition-colors duration-300 ${
                        it.done ? "bg-brand" : "ring-[1.5px] ring-inset ring-stone-300"
                      }`}
                    >
                      {it.done && (
                        <Check className="hm-check h-2.5 w-2.5 text-white" strokeWidth={3.5} aria-hidden="true" />
                      )}
                    </span>
                    <span className="truncate text-[13px] text-stone-700">{it.item}</span>
                    <span className="ml-auto shrink-0 rounded-full bg-stone-100 px-2 py-[1px] text-[11px] text-stone-500">
                      {it.tag}
                    </span>
                  </div>
                </li>
              ))}
            </ul>
          </div>
        </div>

        {/* The thought, travelling */}
        {!reduced && b >= 2 && b <= 3 && (
          <span key={`a-${cycle}`} className="hm-packet" style={{ offsetPath: `path("${PATH_TO_AGENT}")` }} />
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

        :global(.hm-focus) {
          transition: transform 900ms cubic-bezier(0.22, 1, 0.36, 1);
        }
        :global(.hm-row) {
          transition:
            top 600ms cubic-bezier(0.22, 1, 0.36, 1),
            opacity 450ms ease;
        }
        :global(.hm-row-in) {
          animation: hm-row-in 500ms cubic-bezier(0.22, 1, 0.36, 1) both;
        }
        @keyframes hm-row-in {
          from {
            opacity: 0;
            transform: translateY(-8px) scale(0.97);
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
          animation: hm-travel 700ms cubic-bezier(0.55, 0, 0.35, 1) 50ms both;
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
          animation: hm-bar 500ms ease-in-out infinite alternate;
        }
        @keyframes hm-bar {
          0% {
            transform: scaleY(0.35);
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
            box-shadow: 0 0 0 0 rgba(217, 119, 6, 0.45);
          }
          100% {
            box-shadow: 0 0 0 16px rgba(217, 119, 6, 0);
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

        :global(.hm-agent-glow) {
          box-shadow: 0 0 0 5px rgba(217, 119, 6, 0.12), 0 1px 2px rgba(0, 0, 0, 0.04);
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
          :global(.hm-row-in),
          :global(.hm-check) {
            animation: none;
          }
          :global(.hm-focus),
          :global(.hm-row) {
            transition: none;
          }
        }
      `}</style>
    </div>
  );
}
