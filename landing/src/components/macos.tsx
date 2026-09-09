import type { ReactNode } from "react";
import { ApertureMark } from "./Logo";

/**
 * Fabricated macOS chrome — wallpaper, menu bar, dock — shared by the MacBook
 * and by the flat desktop frames.
 *
 * Drawn, never photographed: a real desktop screenshot carries whatever
 * happened to be on screen, which is the thing these images exist to avoid.
 * Everything sizes in container-query units so the same component reads
 * correctly at 300px and at 900px.
 */
export function Screen({ children }: { children: ReactNode }) {
  return (
    <div className="absolute inset-0" style={{ containerType: "inline-size" }}>
      <Wallpaper />
      <MenuBar />
      <div className="absolute inset-0 z-20">{children}</div>
      <Dock />
    </div>
  );
}

/**
 * After Sequoia's "Helios": warm tones folding through cool ones. The single
 * soft ray is what stops four coloured radial gradients reading as four
 * coloured circles.
 */
export function Wallpaper() {
  return (
    <div className="absolute inset-0 z-0" style={{ background: "#0a0d18" }}>
      <div
        className="absolute inset-0"
        style={{
          background: [
            "radial-gradient(70% 55% at 78% 12%, rgba(255,176,84,.55) 0%, transparent 62%)",
            "radial-gradient(65% 55% at 58% 30%, rgba(236,92,140,.48) 0%, transparent 65%)",
            "radial-gradient(85% 70% at 22% 62%, rgba(96,86,224,.62) 0%, transparent 68%)",
            "radial-gradient(70% 60% at 88% 86%, rgba(46,160,214,.42) 0%, transparent 66%)",
            "linear-gradient(155deg,#121736 0%,#0d1024 55%,#080a16 100%)",
          ].join(","),
        }}
      />
      <div
        className="absolute inset-0"
        style={{
          background:
            "linear-gradient(102deg, transparent 38%, rgba(255,214,170,.16) 48%, transparent 58%)",
        }}
      />
    </div>
  );
}

/**
 * The right-hand end follows the real order: menu extras first, then the
 * system items, with Control Centre, Siri and the clock pinned to the corner
 * because macOS will not let you move those three.
 */
export function MenuBar() {
  return (
    <div
      className="absolute inset-x-0 top-0 z-30 flex items-center backdrop-blur-md"
      style={{
        height: "4.2%",
        background: "rgba(16,16,20,.34)",
        fontSize: "1.35cqw",
        paddingInline: "1.4cqw",
        gap: "1.6cqw",
      }}
    >
      <AppleGlyph />
      <span className="font-semibold text-white/95">Finder</span>
      <span className="text-white/80">File</span>
      <span className="text-white/80">Edit</span>
      <span className="text-white/80">View</span>
      <span className="text-white/80">Go</span>

      <span className="flex-1" />

      {/* A third-party menu extra sits left of the system items — which is
          exactly where Potret puts itself. */}
      <ApertureMark size={9} />
      <Battery />
      <WiFi />
      <ControlCentre />
      <Spotlight />
      <span className="tabular-nums text-white/95">Tue 9:41</span>
    </div>
  );
}

function AppleGlyph() {
  return (
    <svg viewBox="0 0 24 24" fill="rgba(255,255,255,.95)" style={{ width: "1.05em", height: "1.05em" }} aria-hidden="true">
      <path d="M16.36 12.78c-.02-2.3 1.88-3.4 1.96-3.46-1.07-1.56-2.73-1.78-3.32-1.8-1.41-.14-2.76.83-3.48.83-.72 0-1.83-.81-3.01-.79-1.55.02-2.98.9-3.78 2.28-1.61 2.79-.41 6.92 1.15 9.18.76 1.11 1.67 2.35 2.86 2.31 1.15-.05 1.58-.74 2.97-.74 1.38 0 1.78.74 2.99.72 1.24-.02 2.02-1.13 2.78-2.24.87-1.28 1.23-2.52 1.25-2.59-.03-.01-2.4-.92-2.42-3.66zM14.1 5.66c.63-.77 1.06-1.83.94-2.9-.91.04-2.01.61-2.66 1.37-.58.68-1.09 1.76-.95 2.8 1.01.08 2.04-.51 2.67-1.27z" />
    </svg>
  );
}

const ink = "rgba(255,255,255,.92)";

function Battery() {
  return (
    <svg viewBox="0 0 26 12" style={{ width: "1.85em", height: "1em" }} aria-hidden="true">
      <rect x="0.6" y="0.6" width="21" height="10.8" rx="3.2" fill="none" stroke={ink} strokeWidth="1.1" opacity=".65" />
      <rect x="2.1" y="2.1" width="15" height="7.8" rx="2" fill={ink} />
      <path d="M23.2 4.2v3.6a2.2 2.2 0 0 0 0-3.6Z" fill={ink} opacity=".65" />
    </svg>
  );
}

function WiFi() {
  return (
    <svg viewBox="0 0 16 12" style={{ width: "1.15em", height: "1em" }} aria-hidden="true">
      <path d="M1 4.2a10 10 0 0 1 14 0" fill="none" stroke={ink} strokeWidth="1.5" strokeLinecap="round" />
      <path d="M3.6 6.9a6.3 6.3 0 0 1 8.8 0" fill="none" stroke={ink} strokeWidth="1.5" strokeLinecap="round" />
      <circle cx="8" cy="9.8" r="1.2" fill={ink} />
    </svg>
  );
}

function ControlCentre() {
  return (
    <svg viewBox="0 0 16 12" style={{ width: "1.05em", height: "1em" }} aria-hidden="true">
      <rect x="0.7" y="0.7" width="14.6" height="4.2" rx="2.1" fill="none" stroke={ink} strokeWidth="1.1" />
      <circle cx="11.2" cy="2.8" r="1.3" fill={ink} />
      <rect x="0.7" y="7.1" width="14.6" height="4.2" rx="2.1" fill="none" stroke={ink} strokeWidth="1.1" />
      <circle cx="4.8" cy="9.2" r="1.3" fill={ink} />
    </svg>
  );
}

function Spotlight() {
  return (
    <svg viewBox="0 0 14 14" fill="none" stroke={ink} strokeWidth="1.4" strokeLinecap="round" style={{ width: "1em", height: "1em" }} aria-hidden="true">
      <circle cx="6" cy="6" r="4.2" />
      <path d="m9.3 9.3 3.1 3.1" />
    </svg>
  );
}

/** Squircle tiles with a hint of a glyph, running dots, and Trash past the
 *  divider — the three cues that make a row of coloured squares read as a Dock. */
const DOCK = [
  { background: "linear-gradient(160deg,#7cc4ff,#2563eb)", glyph: "M4 11h8M8 7v8", running: true },
  { background: "linear-gradient(160deg,#9be79b,#22a06b)", glyph: "M4.5 8.5h7M4.5 11h4.5", running: true },
  { background: "linear-gradient(160deg,#ffe08a,#f59e0b)", glyph: "M8 4.5v7M5 8.5l3 3 3-3", running: false },
  { background: "linear-gradient(160deg,#ffa3a3,#e5484d)", glyph: "M5 5.5h6v6H5z", running: false },
  { background: "linear-gradient(160deg,#d5c7ff,#7c3aed)", glyph: "M8 4.8a3.2 3.2 0 1 0 0 6.4 3.2 3.2 0 0 0 0-6.4Z", running: true },
  { background: "linear-gradient(160deg,#8ff0e2,#0d9488)", glyph: "M4.5 10.5 7 7l2 2.4L11.5 6", running: false },
];

export function Dock() {
  return (
    <div className="pointer-events-none absolute inset-x-0 bottom-[1.4%] z-30 flex justify-center">
      <div
        className="flex items-end backdrop-blur-md"
        style={{
          gap: "0.75cqw",
          borderRadius: "1.35cqw",
          paddingInline: "0.85cqw",
          paddingBlock: "0.65cqw",
          background: "rgba(255,255,255,.17)",
          border: "1px solid rgba(255,255,255,.16)",
          boxShadow: "inset 0 1px 0 rgba(255,255,255,.22), 0 0.6cqw 1.4cqw rgba(0,0,0,.28)",
        }}
      >
        {DOCK.map((tile, index) => (
          <Tile key={index} {...tile} />
        ))}
        <span
          style={{
            width: "1px",
            height: "2.9cqw",
            margin: "0 0.25cqw",
            background: "rgba(255,255,255,.28)",
          }}
        />
        <Tile background="linear-gradient(160deg,#cfd6de,#8a939d)" glyph="M5 6h6l-.6 6H5.6zM6.4 6V4.8h3.2V6" running={false} />
      </div>
    </div>
  );
}

function Tile({
  background,
  glyph,
  running,
}: {
  background: string;
  glyph: string;
  running: boolean;
}) {
  return (
    <span className="relative block" style={{ width: "2.9cqw" }}>
      <span
        className="block"
        style={{
          width: "2.9cqw",
          height: "2.9cqw",
          background,
          /* macOS icons are squircles, not rounded squares. */
          borderRadius: "23%",
          boxShadow: "0 1px 3px rgba(0,0,0,.35), inset 0 1px 0 rgba(255,255,255,.3)",
        }}
      >
        {/* Inset, the way a real icon's artwork sits inside its tile rather
            than running to the edge. */}
        <svg viewBox="0 0 16 16" fill="none" stroke="rgba(255,255,255,.9)" strokeWidth="1.5" strokeLinecap="round" style={{ width: "100%", height: "100%", padding: "22%" }} aria-hidden="true">
          <path d={glyph} />
        </svg>
      </span>
      {running ? (
        <span
          className="absolute left-1/2 -translate-x-1/2"
          style={{
            bottom: "-0.55cqw",
            width: "0.32cqw",
            height: "0.32cqw",
            minWidth: "2px",
            minHeight: "2px",
            borderRadius: "9999px",
            background: "rgba(255,255,255,.8)",
          }}
        />
      ) : null}
    </span>
  );
}
