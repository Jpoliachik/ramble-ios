"use client";

import { useEffect, useRef, useState } from "react";
import { Bot, Check, Mic } from "lucide-react";

/*
  Hero motion graphic: you say something to your watch, it hops through your
  phone, and lands with your agent. Everything is drawn in HTML/CSS on a fixed
  440×440 stage that is scaled down at smaller breakpoints, so it sits on the
  page background with nothing to match.

  Two steps: the watch (with the phone tucked behind it) sends, the agent
  receives. The loop never resets. Each thought pushes a new row onto the phone
  and the agent, older rows slide down and fade out, and focus (size) moves
  from the watch to the agent and back.
*/

type Thought = { said: string; item: string; tag: string };

// Example thoughts. They play in a shuffled order, one per loop, and reshuffle
// after every pass. The first one is also the still frame for reduced motion.
const thoughts: Thought[] = [
  { said: "Add oat milk to my to-do list.", item: "Oat milk", tag: "To-do" },
  { said: "Remind me to call Sam after lunch.", item: "Call Sam", tag: "1:00 PM" },
  { said: "Idea: walking meetings on Fridays.", item: "Walking 1:1s", tag: "Ideas" },
  { said: "Book a haircut for next week.", item: "Haircut", tag: "Next week" },
  { said: "What was that podcast Maya mentioned?", item: "Maya's podcast", tag: "Look up" },
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
//   0 idle: watch in focus, record button
//   1 recording: tap, waveform, the words appear
//   2 sent: check on the watch, the thought leaves
//   3 the phone behind the watch relays it (a quick blip, new row)
//   4 the watch is back to idle. You're done.
//   5 the thought is on its way
//   6 it lands with your agent (agent in focus)
//   7 handled
// The next loop starts while the agent row is still settling, so there's no
// visible restart.
function beatsFor(said: string) {
  const sentAt = 250 + said.length * TYPE_MS + 250;
  const beats = [0, 250, sentAt, sentAt + 150, sentAt + 600, sentAt + 650, sentAt + 850, sentAt + 1200];
  return { beats, loopMs: sentAt + 2200 };
}

// The one hop, from the watch (with the phone behind it) to the agent, in
// stage coordinates.
const PATH_TO_AGENT = "M184 292 C 226 292, 252 226, 301 224";

type PhoneRow = { key: number; said: string };
type AgentRow = { key: number; item: string; tag: string; done: boolean };

const initialPhone: PhoneRow[] = [
  { key: -1, said: "Book a table for two on Friday." },
  { key: -2, said: "Look into standing desks." },
];
const initialAgent: AgentRow[] = [
  { key: -1, item: "Table for two", tag: "Friday", done: true },
  { key: -2, item: "Standing desk", tag: "Research", done: true },
];

const PHONE_ROW_H = 45;
const AGENT_ROW_H = 25;
const VISIBLE = 3;

export default function HeroMotion() {
  const [beat, setBeat] = useState(0);
  const [cycle, setCycle] = useState(0);
  const [thought, setThought] = useState<Thought>(thoughts[0]);
  const [typed, setTyped] = useState(0);
  const [reduced, setReduced] = useState(false);
  const [phoneRows, setPhoneRows] = useState<PhoneRow[]>(initialPhone);
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
            if (i === 3) setPhoneRows((prev) => [{ key: c, said: t.said }, ...prev].slice(0, VISIBLE + 1));
            if (i === 6)
              setAgentRows((prev) =>
                [{ key: c, item: t.item, tag: t.tag, done: false }, ...prev].slice(0, VISIBLE + 1),
              );
            if (i === 7) setAgentRows((prev) => prev.map((r) => (r.key === c ? { ...r, done: true } : r)));
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
  const b = reduced ? 4 : beat;
  const shownPhone = reduced ? [{ key: 0, said: thoughts[0].said }, ...initialPhone] : phoneRows;
  const shownAgent = reduced
    ? [{ key: 0, item: thoughts[0].item, tag: thoughts[0].tag, done: true }, ...initialAgent]
    : agentRows;
  const words = reduced ? thoughts[0].said : thought.said.slice(0, typed);

  const recording = b === 1;
  const sent = b === 2 || b === 3;
  const idle = b === 0 || b >= 4;
  const bubbleVisible = reduced || (b >= 1 && b <= 3);
  const agentFocus = !reduced && b >= 6;
  const phoneGlow = !reduced && b >= 2 && b <= 4;
  const agentGlow = agentFocus;

  return (
    <div
      role="img"
      aria-label="You say “Add oat milk to my to-do list” to your Apple Watch. Your iPhone transcribes it and sends it on, and it lands with your agent."
      className="relative h-[320px] w-[320px] sm:h-[400px] sm:w-[400px] lg:h-[440px] lg:w-[440px]"
    >
      <div className="hm-stage absolute left-0 top-0 h-[440px] w-[440px] origin-top-left">
        {/* Faint route: watch + phone → agent */}
        <svg className="absolute inset-0 z-[5]" width="440" height="440" viewBox="0 0 440 440" fill="none" aria-hidden="true">
          <path d={PATH_TO_AGENT} stroke="#d5d0c8" strokeWidth="1.5" strokeDasharray="2 6" strokeLinecap="round" />
        </svg>

        {/* What you say */}
        <div
          className={`absolute left-[4px] top-[44px] z-20 w-[236px] transition-all duration-500 ease-out ${
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
        <div
          className="hm-focus absolute left-[6px] top-[194px] z-10 w-[178px]"
          style={{ transformOrigin: "60% 50%", transform: `scale(${agentFocus ? 0.94 : 1})` }}
        >
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
                    idle ? "scale-100 opacity-100" : "scale-90 opacity-0"
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

        {/* iPhone: behind the watch, relays in the background */}
        <div
          className="hm-focus absolute left-[104px] top-[120px] w-[106px]"
          style={{ transformOrigin: "30% 70%", transform: `scale(${agentFocus ? 0.96 : 1})`, opacity: 0.92 }}
        >
          <div
            className={`rounded-[22px] bg-stone-900 p-[4px] shadow-[0_18px_36px_-14px_rgba(26,25,23,0.35)] ring-1 ring-black/5 transition-shadow duration-500 ${
              phoneGlow ? "hm-phone-glow" : ""
            }`}
          >
            <div className="relative h-[226px] overflow-hidden rounded-[18px] bg-white px-[8px] pt-[8px]">
              <span className="mx-auto block h-[7px] w-[30px] rounded-full bg-stone-900" />
              <p className="mt-[8px] font-serif text-[10px] font-semibold italic text-stone-900">
                <span className="mr-[3px] inline-block h-[5px] w-[5px] rounded-full bg-brand align-middle" />
                Ramble
              </p>
              <div className="relative mt-[6px]" style={{ height: PHONE_ROW_H * VISIBLE }}>
                {shownPhone.map((row, i) => (
                  <div
                    key={row.key}
                    className="hm-row absolute inset-x-0"
                    style={{ top: i * PHONE_ROW_H, opacity: i >= VISIBLE ? 0 : 1 }}
                  >
                    <div className="hm-row-in h-[40px] rounded-[7px] bg-stone-100 px-[6px] py-[5px]">
                      <p className="line-clamp-2 text-[7.5px] leading-[1.3] text-stone-800">{row.said}</p>
                      <p className="mt-[2px] flex items-center gap-[3px] text-[6.5px] font-medium text-stone-500">
                        <span className="inline-block h-[4px] w-[4px] rounded-full bg-brand" />
                        Sent to agent
                      </p>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>

        {/* Your agent: a big icon heads the card */}
        <div
          className="hm-focus absolute left-[224px] top-[224px] z-10 w-[214px]"
          style={{ transformOrigin: "50% 0%", transform: `scale(${agentFocus ? 1.06 : 0.97})` }}
        >
          <div
            className={`relative rounded-2xl bg-white px-3 pb-3 pt-[34px] shadow-sm ring-1 transition-shadow duration-500 ${
              agentGlow ? "ring-brand/40 hm-agent-glow" : "ring-stone-200/80"
            }`}
          >
            <span
              className={`absolute -top-[28px] left-1/2 flex h-[56px] w-[56px] -translate-x-1/2 items-center justify-center rounded-full bg-white shadow-sm ring-1 transition-shadow duration-500 ${
                agentGlow ? "ring-brand/40 hm-agent-glow" : "ring-stone-200/80"
              }`}
            >
              <span className="flex h-[46px] w-[46px] items-center justify-center rounded-full bg-brand/10">
                <Bot className="h-[26px] w-[26px] text-brand-text" strokeWidth={2} aria-hidden="true" />
              </span>
            </span>
            <p className="text-center text-[13px] font-medium text-stone-800">Agent</p>
            <ul className="relative mt-2" style={{ height: AGENT_ROW_H * VISIBLE }}>
              {shownAgent.map((it, i) => (
                <li
                  key={it.key}
                  className="hm-row absolute inset-x-0"
                  style={{ top: i * AGENT_ROW_H, opacity: i >= VISIBLE ? 0 : 1 }}
                >
                  <div className="hm-row-in flex h-[20px] items-center gap-2">
                    <span
                      className={`flex h-4 w-4 shrink-0 items-center justify-center rounded-full transition-colors duration-300 ${
                        it.done ? "bg-brand" : "ring-[1.5px] ring-inset ring-stone-300"
                      }`}
                    >
                      {it.done && (
                        <Check className="hm-check h-2.5 w-2.5 text-white" strokeWidth={3.5} aria-hidden="true" />
                      )}
                    </span>
                    <span className="truncate text-[12.5px] text-stone-700">{it.item}</span>
                    <span className="ml-auto shrink-0 rounded-full bg-stone-100 px-2 py-[1px] text-[10.5px] text-stone-500">
                      {it.tag}
                    </span>
                  </div>
                </li>
              ))}
            </ul>
          </div>
        </div>

        {/* The thought, travelling */}
        {!reduced && b >= 2 && b <= 6 && (
          <span key={`a-${cycle}`} className="hm-packet hm-packet-a" style={{ offsetPath: `path("${PATH_TO_AGENT}")` }} />
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
          transition:
            transform 900ms cubic-bezier(0.22, 1, 0.36, 1),
            opacity 700ms ease;
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
        }
        :global(.hm-packet-a) {
          animation: hm-travel 800ms cubic-bezier(0.55, 0, 0.35, 1) 50ms both;
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
          :global(.hm-check),
          :global(.hm-shimmer) {
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
