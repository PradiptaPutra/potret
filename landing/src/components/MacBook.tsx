import { useEffect, useRef, useState, type ReactNode } from "react";
import { ApertureMark } from "./Logo";

/**
 * A MacBook whose lid opens as you scroll it into view.
 *
 * The lid is a plane rotated about its bottom edge — the hinge — inside a
 * container with perspective. Scroll progress drives the angle from nearly
 * shut to upright, so the product reveals itself rather than simply being
 * there. The same trick Apple's product pages use.
 *
 * Everything is drawn: the device, the wallpaper, the menu bar, the dock. A
 * photograph of a real Mac would carry a real desktop, which is the thing
 * these images exist to avoid.
 */
export default function MacBook({ children }: { children: ReactNode }) {
  const ref = useRef<HTMLDivElement>(null);
  const [progress, setProgress] = useState(0);

  useEffect(() => {
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduced) {
      // No theatre for anyone who asked not to have it — just show the thing.
      setProgress(1);
      return;
    }

    let frame = 0;
    const measure = () => {
      frame = 0;
      const el = ref.current;
      if (!el) return;
      const rect = el.getBoundingClientRect();
      // Shut when the device is a screen-height away; fully open by the time
      // it is a third of the way up the viewport.
      const from = window.innerHeight * 0.95;
      const to = window.innerHeight * 0.3;
      const next = (from - rect.top) / (from - to);
      setProgress(Math.min(1, Math.max(0, next)));
    };
    const onScroll = () => {
      if (frame) return;
      frame = window.requestAnimationFrame(measure);
    };

    measure();
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onScroll);
    return () => {
      window.removeEventListener("scroll", onScroll);
      window.removeEventListener("resize", onScroll);
      if (frame) window.cancelAnimationFrame(frame);
    };
  }, []);

  // Eased, so the last few degrees settle rather than snap.
  const eased = 1 - Math.pow(1 - progress, 3);
  const angle = -84 + 84 * eased;

  return (
    <div ref={ref} className="mx-auto w-full max-w-[820px]" style={{ containerType: "inline-size" }}>
      <div style={{ perspective: "1700px", perspectiveOrigin: "50% 82%" }}>
        {/* Lid: a thin aluminium rim, a black bezel, then the screen. On a
            real machine the aluminium is only a couple of millimetres at the
            edge — a thick grey frame is the thing that made this read as a
            monitor rather than a laptop. */}
        <div
          className="relative origin-bottom"
          style={{
            transform: `rotateX(${angle}deg)`,
            transformStyle: "preserve-3d",
            transformOrigin: "50% 100%",
            aspectRatio: "16 / 10.6",
            background: "linear-gradient(180deg,#6a6e75 0%,#4a4e54 4%,#3a3d43 100%)",
            padding: "0.5%",
            borderRadius: "1.4% 1.4% 0.2% 0.2% / 2.1% 2.1% 0.3% 0.3%",
            boxShadow:
              "0 40px 60px -30px rgba(0,0,0,.55), inset 0 0 0 1px rgba(255,255,255,.10)",
          }}
        >
          <div
            className="relative h-full w-full"
            style={{
              background: "#0b0b0d",
              borderRadius: "1.1% 1.1% 0.15% 0.15% / 1.7% 1.7% 0.2% 0.2%",
              padding: "1.15%",
              paddingBottom: "1.5%",
            }}
          >
            <div className="relative h-full w-full overflow-hidden" style={{ borderRadius: "3px" }}>
              <Screen>{children}</Screen>
              <Notch />
            </div>
          </div>
          {/* The glass catches the room light, most of all while it is tilted. */}
          <div
            className="pointer-events-none absolute inset-0"
            style={{
              borderRadius: "1.4% 1.4% 0.2% 0.2% / 2.1% 2.1% 0.3% 0.3%",
              background:
                "linear-gradient(103deg, rgba(255,255,255,.16) 0%, rgba(255,255,255,0) 34%)",
              opacity: 0.5 + 0.5 * (1 - eased),
            }}
          />
        </div>

        <Base />
      </div>
    </div>
  );
}

function Notch() {
  return (
    <div className="pointer-events-none absolute inset-x-0 top-0 z-40 flex justify-center">
      <div
        className="flex items-center justify-center"
        style={{
          width: "13.5%",
          height: "4.6%",
          background: "#000",
          borderRadius: "0 0 7px 7px",
        }}
      >
        <span
          style={{
            width: "5%",
            height: "26%",
            borderRadius: "9999px",
            background: "rgba(120,130,150,.5)",
          }}
        />
      </div>
    </div>
  );
}

/**
 * The deck.
 *
 * Head-on you are looking at the front edge of the base, and three things make
 * it read as one: it is *wider* than the lid, because you see past the lid's
 * sides; it flares slightly towards you rather than being a rectangle; and it
 * has the thumb notch cut into the middle of its front edge. Without those it
 * is a monitor stand.
 */
function Base() {
  return (
    <div className="relative">
      {/* The hinge, in the shadow under the lid. */}
      <div
        className="mx-auto"
        style={{
          width: "99%",
          height: "0.55cqw",
          minHeight: "3px",
          background: "linear-gradient(180deg,#1a1c1f,#303338)",
          borderRadius: "0 0 2px 2px",
        }}
      />
      <div className="relative" style={{ width: "109%", marginLeft: "-4.5%" }}>
        <div
          style={{
            height: "1.5cqw",
            minHeight: "11px",
            background:
              "linear-gradient(180deg,#8f949c 0%,#6c7076 14%,#4c5055 55%,#33363b 100%)",
            clipPath: "polygon(2.4% 0, 97.6% 0, 100% 100%, 0 100%)",
            borderRadius: "0 0 10px 10px",
          }}
        />
        {/* Thumb notch. */}
        <div className="absolute inset-x-0 top-0 flex justify-center">
          <div
            style={{
              width: "11%",
              height: "0.42cqw",
              minHeight: "3px",
              background: "linear-gradient(180deg,#1f2124,#33363b)",
              borderRadius: "0 0 999px 999px",
            }}
          />
        </div>
      </div>
      {/* The shadow the machine casts on the page. */}
      <div
        className="mx-auto"
        style={{
          width: "84%",
          height: "30px",
          marginTop: "-4px",
          background:
            "radial-gradient(50% 50% at 50% 40%, rgba(0,0,0,.26) 0%, rgba(0,0,0,0) 72%)",
        }}
      />
    </div>
  );
}

/**
 * The desktop itself: wallpaper, menu bar, dock, and whatever window the
 * caller puts on it.
 */
function Screen({ children }: { children: ReactNode }) {
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
 * In the spirit of Sequoia's "Helios": warm tones folding through cool ones,
 * as if light were coming through something tall.
 */
function Wallpaper() {
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
      {/* A single soft ray, the thing that makes it read as light rather than
          as four coloured circles. */}
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

function MenuBar() {
  return (
    <div
      className="absolute inset-x-0 top-0 z-30 flex items-center gap-[1.5cqw] px-[1.5cqw] backdrop-blur-md"
      style={{
        height: "4.2%",
        background: "rgba(18,18,22,.38)",
        fontSize: "1.35cqw",
      }}
    >
      <AppleGlyph />
      <span className="font-semibold text-white/95">Finder</span>
      <span className="hidden text-white/75 sm:inline">File</span>
      <span className="hidden text-white/75 sm:inline">Edit</span>
      <span className="hidden text-white/75 sm:inline">View</span>
      <span className="flex-1" />
      {/* Where Potret actually lives. */}
      <ApertureMark size={9} />
      <Glyph d="M2 8.5h12M2 5h12M2 12h8" />
      <Glyph d="M8 2.5a5.5 5.5 0 1 0 0 11 5.5 5.5 0 0 0 0-11ZM8 5v3.2l2 1.2" />
      <span className="tabular-nums text-white/90">Tue 9:41</span>
    </div>
  );
}

function AppleGlyph() {
  return (
    <svg viewBox="0 0 24 24" fill="rgba(255,255,255,.95)" style={{ width: "1em", height: "1em" }} aria-hidden="true">
      <path d="M16.36 12.78c-.02-2.3 1.88-3.4 1.96-3.46-1.07-1.56-2.73-1.78-3.32-1.8-1.41-.14-2.76.83-3.48.83-.72 0-1.83-.81-3.01-.79-1.55.02-2.98.9-3.78 2.28-1.61 2.79-.41 6.92 1.15 9.18.76 1.11 1.67 2.35 2.86 2.31 1.15-.05 1.58-.74 2.97-.74 1.38 0 1.78.74 2.99.72 1.24-.02 2.02-1.13 2.78-2.24.87-1.28 1.23-2.52 1.25-2.59-.03-.01-2.4-.92-2.42-3.66zM14.1 5.66c.63-.77 1.06-1.83.94-2.9-.91.04-2.01.61-2.66 1.37-.58.68-1.09 1.76-.95 2.8 1.01.08 2.04-.51 2.67-1.27z" />
    </svg>
  );
}

function Glyph({ d }: { d: string }) {
  return (
    <svg
      viewBox="0 0 16 16"
      fill="none"
      stroke="rgba(255,255,255,.85)"
      strokeWidth="1.4"
      strokeLinecap="round"
      style={{ width: "1em", height: "1em" }}
      aria-hidden="true"
    >
      <path d={d} />
    </svg>
  );
}

const DOCK = [
  "linear-gradient(160deg,#5aa9ff,#2563eb)",
  "linear-gradient(160deg,#7ee787,#22a06b)",
  "linear-gradient(160deg,#ffd479,#f59e0b)",
  "linear-gradient(160deg,#ff8f8f,#e5484d)",
  "linear-gradient(160deg,#c4b5fd,#7c3aed)",
  "linear-gradient(160deg,#6ee7d7,#0d9488)",
  "linear-gradient(160deg,#a5b4c4,#64748b)",
];

function Dock() {
  return (
    <div className="pointer-events-none absolute inset-x-0 bottom-[1.4%] z-30 flex justify-center">
      <div
        className="flex items-end gap-[0.7cqw] rounded-[1.2cqw] px-[0.8cqw] py-[0.6cqw] backdrop-blur-md"
        style={{
          background: "rgba(255,255,255,.16)",
          border: "1px solid rgba(255,255,255,.14)",
        }}
      >
        {DOCK.map((background, index) => (
          <span
            key={index}
            className="rounded-[0.7cqw]"
            style={{
              width: "2.9cqw",
              height: "2.9cqw",
              background,
              boxShadow: "0 1px 3px rgba(0,0,0,.35)",
            }}
          />
        ))}
      </div>
    </div>
  );
}
