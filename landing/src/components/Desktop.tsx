import type { ReactNode } from "react";
import { ApertureMark } from "./Logo";

/**
 * A fabricated macOS desktop for product shots to sit in.
 *
 * Drawn in CSS rather than photographed: a real desktop screenshot would carry
 * whatever happened to be on screen, which is exactly what these images exist
 * to avoid. The menu bar and dock are the cues that say "this is a Mac app" —
 * and the aperture in the menu bar says where Potret actually lives, which no
 * amount of body copy conveys as quickly.
 */
export default function Desktop({
  children,
  caption,
  className,
  dimmed = false,
}: {
  children: ReactNode;
  caption?: string;
  className?: string;
  /** The selector dims the desktop behind it; the menu bar dims with it. */
  dimmed?: boolean;
}) {
  return (
    <figure className={`m-0 ${className ?? ""}`}>
      <div
        className="relative isolate overflow-hidden rounded-xl border border-fog"
        style={{ boxShadow: "var(--shadow-mockup)", aspectRatio: "16 / 10" }}
      >
        <Wallpaper />
        <MenuBar dimmed={dimmed} />

        <div className="absolute inset-0 z-20">{children}</div>

        <Dock />
      </div>
      {caption ? (
        <figcaption className="mt-3 text-center text-[13px] text-graphite">
          {caption}
        </figcaption>
      ) : null}
    </figure>
  );
}

/** Deep blue with two blooms — the shape of a stock macOS wallpaper. */
function Wallpaper() {
  return (
    <div
      className="absolute inset-0 z-0"
      style={{
        background: [
          "radial-gradient(90% 70% at 18% 8%, rgba(96,132,255,.55) 0%, transparent 58%)",
          "radial-gradient(80% 65% at 82% 26%, rgba(176,106,179,.45) 0%, transparent 62%)",
          "radial-gradient(70% 60% at 60% 95%, rgba(56,189,248,.28) 0%, transparent 60%)",
          "linear-gradient(165deg, #1b2440 0%, #131a2e 45%, #0b1020 100%)",
        ].join(","),
      }}
    />
  );
}

function MenuBar({ dimmed }: { dimmed: boolean }) {
  return (
    <div
      className="absolute inset-x-0 top-0 z-30 flex items-center gap-[1.6%] px-[1.6%] backdrop-blur-md"
      style={{
        height: "5.4%",
        background: "rgba(255,255,255,.14)",
        borderBottom: "1px solid rgba(255,255,255,.10)",
        opacity: dimmed ? 0.55 : 1,
      }}
    >
      <AppleGlyph />
      <span className="text-[0.62em] font-semibold text-white/90">Finder</span>
      {["File", "Edit", "View", "Go"].map((item) => (
        <span key={item} className="hidden text-[0.62em] text-white/70 sm:inline">
          {item}
        </span>
      ))}

      <span className="flex-1" />

      {/* Potret sits here — the point of the whole frame. */}
      <span
        className="grid place-items-center rounded"
        style={{ width: "1.5em", height: "1.5em" }}
      >
        <ApertureMark size={11} />
      </span>
      <Glyph d="M2 8.5h12M2 5h12M2 12h8" />
      <Glyph d="M8 2.5a5.5 5.5 0 1 0 0 11 5.5 5.5 0 0 0 0-11ZM8 5v3.2l2 1.2" />
      <span className="text-[0.6em] tabular-nums text-white/85">Tue 9:41</span>
    </div>
  );
}

function AppleGlyph() {
  return (
    <svg viewBox="0 0 24 24" fill="rgba(255,255,255,.92)" style={{ width: "0.95em", height: "0.95em" }} aria-hidden="true">
      <path d="M16.36 12.78c-.02-2.3 1.88-3.4 1.96-3.46-1.07-1.56-2.73-1.78-3.32-1.8-1.41-.14-2.76.83-3.48.83-.72 0-1.83-.81-3.01-.79-1.55.02-2.98.9-3.78 2.28-1.61 2.79-.41 6.92 1.15 9.18.76 1.11 1.67 2.35 2.86 2.31 1.15-.05 1.58-.74 2.97-.74 1.38 0 1.78.74 2.99.72 1.24-.02 2.02-1.13 2.78-2.24.87-1.28 1.23-2.52 1.25-2.59-.03-.01-2.4-.92-2.42-3.66zM14.1 5.66c.63-.77 1.06-1.83.94-2.9-.91.04-2.01.61-2.66 1.37-.58.68-1.09 1.76-.95 2.8 1.01.08 2.04-.51 2.67-1.27z" />
    </svg>
  );
}

function Glyph({ d }: { d: string }) {
  return (
    <svg
      viewBox="0 0 16 16"
      fill="none"
      stroke="rgba(255,255,255,.8)"
      strokeWidth="1.4"
      strokeLinecap="round"
      style={{ width: "0.95em", height: "0.95em" }}
      aria-hidden="true"
    >
      <path d={d} />
    </svg>
  );
}

/** Seven tiles in the usual macOS gradients. Suggestion, not simulation. */
const DOCK = [
  "linear-gradient(160deg,#5aa9ff,#2563eb)",
  "linear-gradient(160deg,#7ee787,#22a06b)",
  "linear-gradient(160deg,#ffd479,#f59e0b)",
  "linear-gradient(160deg,#ff8f8f,#e5484d)",
  "linear-gradient(160deg,#c4b5fd,#7c3aed)",
  "linear-gradient(160deg,#a5b4c4,#64748b)",
  "linear-gradient(160deg,#6ee7d7,#0d9488)",
];

function Dock() {
  return (
    <div className="pointer-events-none absolute inset-x-0 bottom-[1.6%] z-30 flex justify-center">
      <div
        className="flex items-end gap-[0.5em] rounded-[0.9em] px-[0.6em] py-[0.45em] backdrop-blur-md"
        style={{
          background: "rgba(255,255,255,.18)",
          border: "1px solid rgba(255,255,255,.16)",
        }}
      >
        {DOCK.map((background, index) => (
          <span
            key={index}
            className="rounded-[0.35em]"
            style={{
              width: "1.9em",
              height: "1.9em",
              background,
              boxShadow: "0 1px 2px rgba(0,0,0,.28)",
            }}
          />
        ))}
      </div>
    </div>
  );
}
