import type { ReactElement } from "react";
import { useState } from "react";
import MacWindow from "../components/MacWindow";

type Mode = {
  id: string;
  label: string;
  eyebrow: string;
  title: string;
  body: string;
  points: string[];
  shot: string;
  alt: string;
  frame: string;
  icon: () => ReactElement;
};

const MODES: Mode[] = [
  {
    id: "capture",
    label: "Capture",
    eyebrow: "Capture mode",
    title: "Drag once. Decide after.",
    body:
      "The selection stays put when you let go. Nudge it with handles, type an exact size, lock the aspect ratio — then capture it, or record it, without starting over.",
    points: [
      "Area, window, or the whole screen",
      "Type exact pixel dimensions, or lock to 16:9",
      "Freeze the screen so a menu stops closing on you",
      "Self-timer for hover states that vanish",
    ],
    shot: "/shot-selector.png",
    alt: "The Potret selection bar under a selected area, showing capture, record, timer and freeze buttons beside a width and height field.",
    frame: "Selecting an area",
    icon: () => (
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" className="size-5">
        <path d="M3 8V5a2 2 0 0 1 2-2h3M16 3h3a2 2 0 0 1 2 2v3M21 16v3a2 2 0 0 1-2 2h-3M8 21H5a2 2 0 0 1-2-2v-3" strokeLinecap="round" />
      </svg>
    ),
  },
  {
    id: "record",
    label: "Record",
    eyebrow: "Record mode",
    title: "A demo people can follow.",
    body:
      "Record an area, a window or the screen to MP4. Every click gets a ring drawn into the video — never onto your actual screen — so a viewer can see what you did, not just what changed.",
    points: [
      "Click highlighting, composited into the frames",
      "A countdown before it rolls, so you can get set",
      "Hide the pointer for a clean walkthrough",
      "Standard or high quality, 30 or 60 fps",
    ],
    shot: "/shot-clicks.png",
    alt: "A frame from a Potret recording with an amber ring marking where the pointer was clicked.",
    frame: "A click, marked in the video",
    icon: () => (
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" className="size-5">
        <circle cx="12" cy="12" r="8.5" />
        <circle cx="12" cy="12" r="3.5" fill="currentColor" stroke="none" />
      </svg>
    ),
  },
  {
    id: "trim",
    label: "Trim",
    eyebrow: "Trim mode",
    title: "Cut it on a real timeline.",
    body:
      "Recordings open in a timeline with a ruler, the clip bracketed between drag handles, a transport and zoom. Export as video or GIF — and the cut applies to your library, not only to the copy you export.",
    points: [
      "Ruler ticks that stay readable at any length",
      "Zoom in when a tenth of a second matters",
      "Export MP4, or a GIF with its size estimated first",
      "The library stops offering the take you just cut",
    ],
    shot: "/shot-trim.png",
    alt: "The Potret trim window: a video player above a timeline with a time ruler, a filmstrip and amber drag handles.",
    frame: "Recording · 0:14",
    icon: () => (
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" className="size-5">
        <circle cx="6" cy="6" r="2.6" />
        <circle cx="6" cy="18" r="2.6" />
        <path d="M20 4 8.5 16.2M8.5 7.8 20 20" strokeLinecap="round" />
      </svg>
    ),
  },
];

/**
 * The segmented control — one app, three jobs. Switching swaps the copy and
 * the screenshot in place rather than scrolling somewhere else.
 */
export default function Modes() {
  const [active, setActive] = useState(0);
  const mode = MODES[active];

  return (
    <section id="modes" className="py-20">
      <div className="shell">
        <div className="reveal mx-auto max-w-[52ch] text-center">
          <p className="eyebrow">Three modes</p>
          <h2 className="heading mt-3">One app, the whole loop.</h2>
          <p className="mt-4 text-[16px] text-slate">
            Capture it, record it, cut it. Nothing here opens a second
            application or asks you to sign in.
          </p>
        </div>

        <div className="reveal mt-8 flex justify-center">
          <div
            role="tablist"
            aria-label="Modes"
            className="inline-flex gap-1 rounded-full bg-mist p-1"
          >
            {MODES.map((item, index) => {
              const selected = index === active;
              return (
                <button
                  key={item.id}
                  role="tab"
                  type="button"
                  aria-selected={selected}
                  onClick={() => setActive(index)}
                  className={`flex items-center gap-2 rounded-full px-4 py-2 text-[14px] font-medium transition-colors ${
                    selected
                      ? "border border-fog bg-paper text-ink"
                      : "border border-transparent text-graphite hover:text-ink"
                  }`}
                  style={selected ? { boxShadow: "var(--shadow-button)" } : undefined}
                >
                  <span className={selected ? "text-[var(--color-spark-deep)]" : ""}>
                    {item.icon()}
                  </span>
                  {item.label}
                </button>
              );
            })}
          </div>
        </div>

        <div className="mt-12 grid items-center gap-12 lg:grid-cols-2">
          <div className="reveal min-w-0">
            <p className="eyebrow">{mode.eyebrow}</p>
            <h3 className="heading mt-3">{mode.title}</h3>
            <p className="mt-4 max-w-[52ch] text-[16px] text-slate">{mode.body}</p>
            <ul className="mt-6 space-y-3">
              {mode.points.map((point) => (
                <li key={point} className="flex gap-3 text-[15px] text-ink">
                  <Tick />
                  <span>{point}</span>
                </li>
              ))}
            </ul>
          </div>

          <div className="reveal min-w-0" style={{ transitionDelay: "80ms" }}>
            <MacWindow src={mode.shot} alt={mode.alt} title={mode.frame} />
          </div>
        </div>
      </div>
    </section>
  );
}

function Tick() {
  return (
    <svg
      viewBox="0 0 20 20"
      fill="none"
      stroke="var(--color-spark-deep)"
      strokeWidth="2"
      className="mt-1 size-4 shrink-0"
      aria-hidden="true"
    >
      <path d="m4 10.5 4 4 8-9" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
