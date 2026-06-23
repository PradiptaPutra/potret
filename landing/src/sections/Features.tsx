import type { ReactNode } from "react";
import { useReveal } from "../lib/useReveal";

/* ----------------------------------------------------------------------------
   Hand-drawn 24px inline glyphs (lucide is not installed). amber stroke,
   round caps/joins so they read as one cohesive set. decorative → aria-hidden.
---------------------------------------------------------------------------- */
type GlyphProps = { className?: string };

const svgBase = {
  width: 24,
  height: 24,
  viewBox: "0 0 24 24",
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 1.6,
  strokeLinecap: "round" as const,
  strokeLinejoin: "round" as const,
  "aria-hidden": true,
};

/* Capture — crosshair / marquee selection */
function GlyphCapture({ className }: GlyphProps) {
  return (
    <svg {...svgBase} className={className}>
      <path d="M4 8V5.5A1.5 1.5 0 0 1 5.5 4H8" />
      <path d="M16 4h2.5A1.5 1.5 0 0 1 20 5.5V8" />
      <path d="M20 16v2.5a1.5 1.5 0 0 1-1.5 1.5H16" />
      <path d="M8 20H5.5A1.5 1.5 0 0 1 4 18.5V16" />
      <path d="M12 9v6M9 12h6" />
    </svg>
  );
}

/* Quick Access popup — floating panel + cursor */
function GlyphPopup({ className }: GlyphProps) {
  return (
    <svg {...svgBase} className={className}>
      <rect x="3.5" y="5" width="13" height="9" rx="2" />
      <path d="M3.5 8.5h13" />
      <path d="M13.5 13.5l3.2 7 1.7-3.4 3.4-1.7-8.3-1.9Z" />
    </svg>
  );
}

/* Annotation — pen nib */
function GlyphPen({ className }: GlyphProps) {
  return (
    <svg {...svgBase} className={className}>
      <path d="M5 19l1-3.6L16 5.4a2 2 0 0 1 2.8 2.8L8.6 18 5 19Z" />
      <path d="M14.5 7.2 16.8 9.5" />
      <path d="M6 15.4 8.6 18" />
    </svg>
  );
}

/* Background tool — image dropped on a gradient panel */
function GlyphBackground({ className }: GlyphProps) {
  return (
    <svg {...svgBase} className={className}>
      <rect x="3" y="4" width="18" height="16" rx="3" />
      <rect x="7" y="8.5" width="10" height="7" rx="1.6" />
      <circle cx="9.6" cy="11" r="1" />
      <path d="M7 15.5l3-2.2 3 2.2" />
    </svg>
  );
}

/* Pin to screen — pushpin */
function GlyphPin({ className }: GlyphProps) {
  return (
    <svg {...svgBase} className={className}>
      <path d="M9 4h6l-1 5 3 2.4V13H7v-1.6L10 9 9 4Z" />
      <path d="M12 13v7" />
    </svg>
  );
}

/* History — clock with hand */
function GlyphHistory({ className }: GlyphProps) {
  return (
    <svg {...svgBase} className={className}>
      <path d="M3.5 11a8.5 8.5 0 1 1 1.2 5" />
      <path d="M3.2 19v-3.2H6.4" />
      <path d="M12 7.5V12l3 1.8" />
    </svg>
  );
}

/* Output options — file with format mark */
function GlyphFile({ className }: GlyphProps) {
  return (
    <svg {...svgBase} className={className}>
      <path d="M6 3.5h7L18.5 9v10.5A1 1 0 0 1 17.5 20.5h-11A1 1 0 0 1 5.5 19.5V4.5A1 1 0 0 1 6 3.5Z" />
      <path d="M13 3.5V9h5.5" />
      <path d="M8 14.5h6M8 17h4" />
    </svg>
  );
}

/* System — sliders */
function GlyphSliders({ className }: GlyphProps) {
  return (
    <svg {...svgBase} className={className}>
      <path d="M5 5v6M5 15v4" />
      <path d="M12 5v3M12 12v7" />
      <path d="M19 5v9M19 18v1" />
      <circle cx="5" cy="13" r="1.8" />
      <circle cx="12" cy="10" r="1.8" />
      <circle cx="19" cy="16" r="1.8" />
    </svg>
  );
}

/* ----------------------------------------------------------------------------
   Reusable bento cell. .surface + reveal + hover lift via inline handlers
   (the base .surface class has no hover state, so we drive it here so the
   amber hairline + faint glow stay perfectly on-token).
---------------------------------------------------------------------------- */
type CellProps = {
  className?: string;
  delay?: number;
  children: ReactNode;
};

function Cell({ className = "", delay = 0, children }: CellProps) {
  return (
    <article
      className={`group reveal surface relative overflow-hidden p-6 md:p-7 ${className}`}
      style={{ ["--reveal-delay" as string]: `${delay}ms` }}
      onMouseEnter={(e) => {
        const el = e.currentTarget;
        el.style.transform = "translateY(-4px)";
        el.style.borderColor = "rgba(255,159,10,0.34)";
        el.style.boxShadow =
          "0 1px 0 0 rgba(246,241,233,0.04) inset, 0 28px 70px -30px rgba(0,0,0,0.9), 0 0 60px -28px rgba(255,122,26,0.65)";
      }}
      onMouseLeave={(e) => {
        const el = e.currentTarget;
        el.style.transform = "";
        el.style.borderColor = "";
        el.style.boxShadow = "";
      }}
    >
      {children}
    </article>
  );
}

/* the icon chip every cell shares */
function IconChip({ children }: { children: ReactNode }) {
  return (
    <span
      className="mb-5 inline-flex h-11 w-11 items-center justify-center rounded-[13px] text-amber"
      style={{
        background: "rgba(255,159,10,0.08)",
        border: "1px solid rgba(255,159,10,0.18)",
      }}
    >
      {children}
    </span>
  );
}

function Title({ children }: { children: ReactNode }) {
  return (
    <h3 className="font-display text-[22px] leading-tight tracking-[-0.01em] text-bone md:text-[24px]">
      {children}
    </h3>
  );
}

function Desc({ children }: { children: ReactNode }) {
  return <p className="mt-2 max-w-prose text-[15px] leading-relaxed text-mist">{children}</p>;
}

export default function Features() {
  const ref = useReveal<HTMLDivElement>();

  return (
    <section id="features" className="relative py-24 md:py-36">
      {/* soft amber bloom anchored top-center, behind the grid */}
      <div
        aria-hidden
        className="pointer-events-none absolute inset-x-0 top-0 -z-10 h-[420px]"
        style={{
          background:
            "radial-gradient(60% 100% at 50% 0%, rgba(255,122,26,0.10), transparent 70%)",
        }}
      />

      <div ref={ref} className="container-x">
        {/* ---- section header ---- */}
        <header className="max-w-2xl">
          <p className="kicker reveal">EVERYTHING, NOTHING EXTRA</p>
          <h2
            className="display reveal mt-5 text-[clamp(2.1rem,5vw,3.4rem)]"
            style={{ ["--reveal-delay" as string]: "80ms" }}
          >
            A full screenshot studio,{" "}
            <em className="text-amber-grad font-light not-italic">tucked in your menu bar.</em>
          </h2>
          <p
            className="reveal mt-5 text-[17px] leading-relaxed text-mist"
            style={{ ["--reveal-delay" as string]: "150ms" }}
          >
            Eight tools that earn their keep — capture, mark up, dress up, and ship. No heavy
            editor, no clutter, no subscription.
          </p>
        </header>

        {/* ---- bento grid ----
            6 columns on desktop. asymmetric: Annotation (spotlight, 3 cols) and
            Background tool (spotlight, 3 cols) anchor the middle; Capture spans
            2 cols and is taller; the rest tile around them. ---- */}
        <div className="mt-12 grid grid-cols-1 gap-4 sm:grid-cols-2 md:mt-16 md:grid-cols-6 md:gap-5">
          {/* Capture — tall feature, 2 cols × 2 rows */}
          <Cell delay={0} className="md:col-span-2 md:row-span-2 flex flex-col">
            <IconChip>
              <GlyphCapture />
            </IconChip>
            <Title>Capture, three ways</Title>
            <Desc>
              Drag to select an area, click any window, or grab the whole screen. Hotkeys do it
              without breaking your flow.
            </Desc>

            {/* little inline diagram: three capture modes */}
            <div className="mt-auto pt-8" aria-hidden>
              <svg viewBox="0 0 200 84" className="w-full" fill="none">
                <rect
                  x="4"
                  y="10"
                  width="58"
                  height="64"
                  rx="6"
                  stroke="rgba(255,159,10,0.55)"
                  strokeWidth="1.4"
                  strokeDasharray="4 4"
                />
                <text x="33" y="83" textAnchor="middle" fontSize="8" fill="#6c665e" fontFamily="var(--font-mono)">area</text>

                <rect x="74" y="10" width="52" height="64" rx="6" stroke="rgba(246,241,233,0.16)" strokeWidth="1.4" />
                <path d="M74 24h52" stroke="rgba(255,159,10,0.55)" strokeWidth="1.4" />
                <circle cx="80" cy="17" r="1.5" fill="#ff9f0a" />
                <circle cx="86" cy="17" r="1.5" fill="rgba(246,241,233,0.3)" />
                <text x="100" y="83" textAnchor="middle" fontSize="8" fill="#6c665e" fontFamily="var(--font-mono)">window</text>

                <rect x="138" y="10" width="58" height="64" rx="6" fill="rgba(255,159,10,0.10)" stroke="rgba(255,159,10,0.45)" strokeWidth="1.4" />
                <text x="167" y="83" textAnchor="middle" fontSize="8" fill="#6c665e" fontFamily="var(--font-mono)">full</text>
              </svg>
            </div>
          </Cell>

          {/* Quick Access popup — wide, 2 cols */}
          <Cell delay={70} className="md:col-span-2">
            <IconChip>
              <GlyphPopup />
            </IconChip>
            <Title>Quick Access popup</Title>
            <Desc>
              After every capture, a floating panel: copy, save, annotate, pin, or drag the shot
              straight into another app. Follows you across Spaces.
            </Desc>
          </Cell>

          {/* Pin to screen — 2 cols */}
          <Cell delay={140} className="md:col-span-2">
            <IconChip>
              <GlyphPin />
            </IconChip>
            <Title>Pin to screen</Title>
            <Desc>Keep a floating screenshot on top while you work. Reference without alt-tabbing.</Desc>
          </Cell>

          {/* Annotation — SPOTLIGHT, 3 cols */}
          <Cell delay={210} className="md:col-span-3 flex flex-col">
            <div className="flex items-start justify-between gap-4">
              <div>
                <IconChip>
                  <GlyphPen />
                </IconChip>
                <Title>A real annotation kit</Title>
                <Desc>
                  Pen, line, arrow, rectangle, ellipse, text, highlighter, pixelate/blur, numbered
                  steps, crop, eraser — with undo/redo and a custom color picker.
                </Desc>
              </div>
            </div>

            {/* tasteful arrangement of tool glyphs */}
            <div className="mt-7 flex flex-wrap items-center gap-2.5" aria-hidden>
              {[
                "M5 19l1-3.6L16 5.4a2 2 0 0 1 2.8 2.8L8.6 18 5 19Z", // pen
                "M5 19L19 5M14 5h5v5", // arrow
                "M4 12h16", // line
                "RECT",
                "ELLIPSE",
                "TEXT",
                "STEPS",
              ].map((d, i) => (
                <span
                  key={i}
                  className="inline-flex h-9 w-9 items-center justify-center rounded-[10px] text-amber"
                  style={{
                    background: "rgba(255,159,10,0.06)",
                    border: "1px solid rgba(255,159,10,0.16)",
                  }}
                >
                  {d === "RECT" ? (
                    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6">
                      <rect x="5" y="6.5" width="14" height="11" rx="1.5" />
                    </svg>
                  ) : d === "ELLIPSE" ? (
                    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6">
                      <ellipse cx="12" cy="12" rx="8" ry="6" />
                    </svg>
                  ) : d === "TEXT" ? (
                    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round">
                      <path d="M6 7h12M12 7v11" />
                    </svg>
                  ) : d === "STEPS" ? (
                    <span className="font-mono text-[12px] font-semibold leading-none">3</span>
                  ) : (
                    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
                      <path d={d} />
                    </svg>
                  )}
                </span>
              ))}
              <span className="ml-1 flex items-center gap-1.5">
                {["#ff9f0a", "#f25c05", "#ffd08a", "#a8a299"].map((c) => (
                  <span
                    key={c}
                    className="h-4 w-4 rounded-full"
                    style={{ background: c, boxShadow: "0 0 0 1px rgba(0,0,0,0.4) inset" }}
                  />
                ))}
              </span>
            </div>
          </Cell>

          {/* Background tool — SPOTLIGHT, 3 cols */}
          <Cell delay={280} className="md:col-span-3 flex flex-col">
            <IconChip>
              <GlyphBackground />
            </IconChip>
            <Title>Dress it up for sharing</Title>
            <Desc>
              Drop a screenshot onto a gradient or custom background with padding, rounded corners,
              and a soft shadow. Made for social posts.
            </Desc>

            {/* mini preview: screenshot on a petal gradient */}
            <div className="mt-7" aria-hidden>
              <div
                className="flex aspect-[16/7] items-center justify-center rounded-[14px] p-5"
                style={{ background: "var(--grad-petal)" }}
              >
                <div
                  className="h-full w-full rounded-[8px]"
                  style={{
                    background: "linear-gradient(160deg, #1b1a1f, #0f0e11)",
                    boxShadow: "0 14px 34px -10px rgba(0,0,0,0.7)",
                    border: "1px solid rgba(246,241,233,0.10)",
                  }}
                >
                  <div className="flex items-center gap-1.5 px-3 pt-2.5">
                    <span className="h-2 w-2 rounded-full" style={{ background: "#ff5f57" }} />
                    <span className="h-2 w-2 rounded-full" style={{ background: "#febc2e" }} />
                    <span className="h-2 w-2 rounded-full" style={{ background: "#28c840" }} />
                  </div>
                </div>
              </div>
            </div>
          </Cell>

          {/* History — 2 cols */}
          <Cell delay={350} className="md:col-span-2">
            <IconChip>
              <GlyphHistory />
            </IconChip>
            <Title>History at hand</Title>
            <Desc>
              Recent captures with copy, edit, pin, or delete — plus a menu-bar popup at{" "}
              <kbd className="font-mono text-[12px] text-glow">⌘⇧H</kbd>.
            </Desc>
          </Cell>

          {/* Output options — 2 cols */}
          <Cell delay={420} className="md:col-span-2">
            <IconChip>
              <GlyphFile />
            </IconChip>
            <Title>Output, your way</Title>
            <Desc>PNG or JPG, adjustable quality, and filename templates that stay tidy.</Desc>
          </Cell>

          {/* System — 2 cols */}
          <Cell delay={490} className="md:col-span-2">
            <IconChip>
              <GlyphSliders />
            </IconChip>
            <Title>Yours to tune</Title>
            <Desc>
              Custom global shortcuts, menu-bar only, launch at login, and fluid animations that
              respect Reduce Motion.
            </Desc>
          </Cell>
        </div>
      </div>
    </section>
  );
}
