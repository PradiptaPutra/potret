import type { ReactNode } from "react";
import { useReveal } from "../lib/useReveal";

/* ----------------------------------------------------------------------------
   Workflow — Capture → Mark up → Ship. Three steps, horizontal on desktop,
   stacked on mobile, joined by a thin amber flow line. Cinematic, airy.
---------------------------------------------------------------------------- */

type Step = {
  no: string;
  title: string;
  body: ReactNode;
  glyph: ReactNode;
};

/* small hand-drawn step glyphs, amber stroke, decorative */
const g = {
  width: 28,
  height: 28,
  viewBox: "0 0 24 24",
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 1.5,
  strokeLinecap: "round" as const,
  strokeLinejoin: "round" as const,
  "aria-hidden": true,
};

const STEPS: Step[] = [
  {
    no: "01",
    title: "Capture",
    body: (
      <>
        Snap an area, a window, or the whole screen — straight from a global shortcut. No app to
        open, no Dock detour.
      </>
    ),
    glyph: (
      <svg {...g}>
        <path d="M4 8V5.5A1.5 1.5 0 0 1 5.5 4H8" />
        <path d="M16 4h2.5A1.5 1.5 0 0 1 20 5.5V8" />
        <path d="M20 16v2.5a1.5 1.5 0 0 1-1.5 1.5H16" />
        <path d="M8 20H5.5A1.5 1.5 0 0 1 4 18.5V16" />
        <path d="M12 9v6M9 12h6" />
      </svg>
    ),
  },
  {
    no: "02",
    title: "Mark up",
    body: (
      <>
        The Quick Access popup appears. Copy it, annotate with the full kit, pin it on top, or drag
        it straight into another app.
      </>
    ),
    glyph: (
      <svg {...g}>
        <path d="M5 19l1-3.6L16 5.4a2 2 0 0 1 2.8 2.8L8.6 18 5 19Z" />
        <path d="M14.5 7.2 16.8 9.5" />
      </svg>
    ),
  },
  {
    no: "03",
    title: "Ship",
    body: (
      <>
        Drop it onto a gorgeous gradient background, then copy or save as PNG or JPG. Snap to shipped
        in seconds.
      </>
    ),
    glyph: (
      <svg {...g}>
        <path d="M12 3v12" />
        <path d="M8 7l4-4 4 4" />
        <path d="M5 14v5a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-5" />
      </svg>
    ),
  },
];

export default function Workflow() {
  const ref = useReveal<HTMLDivElement>();

  return (
    <section id="how" className="relative py-24 md:py-36">
      {/* faint vignette to set the steps apart from the bento above */}
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0 -z-10"
        style={{
          background:
            "radial-gradient(80% 60% at 50% 40%, rgba(255,122,26,0.06), transparent 70%)",
        }}
      />

      <div ref={ref} className="container-x">
        {/* ---- header ---- */}
        <header className="mx-auto max-w-2xl text-center">
          <p className="kicker reveal">CAPTURE → MARK UP → SHIP</p>
          <h2
            className="display reveal mt-5 text-[clamp(2.1rem,5vw,3.4rem)]"
            style={{ ["--reveal-delay" as string]: "80ms" }}
          >
            From snap to shipped in{" "}
            <em className="text-amber-grad font-light not-italic">three moves.</em>
          </h2>
          <p
            className="reveal mx-auto mt-5 max-w-xl text-[17px] leading-relaxed text-mist"
            style={{ ["--reveal-delay" as string]: "150ms" }}
          >
            No timeline, no learning curve. The whole loop happens in the floating panel, right where
            your capture lands.
          </p>
        </header>

        {/* ---- the three steps ---- */}
        <div className="relative mt-16 md:mt-24">
          {/* connecting amber flow line — desktop only, runs behind the badges */}
          <div
            aria-hidden
            className="reveal pointer-events-none absolute left-0 right-0 top-[34px] hidden h-px md:block"
            style={{
              ["--reveal-delay" as string]: "120ms",
              background:
                "linear-gradient(90deg, transparent 0%, rgba(255,159,10,0.05) 8%, rgba(255,159,10,0.55) 50%, rgba(255,159,10,0.05) 92%, transparent 100%)",
            }}
          />

          <ol className="grid grid-cols-1 gap-12 md:grid-cols-3 md:gap-8">
            {STEPS.map((step, i) => (
              <li
                key={step.no}
                className="reveal relative flex flex-col items-start md:items-center md:text-center"
                style={{ ["--reveal-delay" as string]: `${i * 130}ms` }}
              >
                {/* mono number badge — sits on the flow line */}
                <div className="relative flex w-full items-center gap-5 md:w-auto md:flex-col md:gap-0">
                  <span
                    className="relative z-10 inline-flex h-[68px] w-[68px] shrink-0 items-center justify-center rounded-full font-mono text-[22px] font-semibold tracking-tight text-amber"
                    style={{
                      background: "var(--color-ink-2)",
                      border: "1px solid rgba(255,159,10,0.28)",
                      boxShadow:
                        "0 0 0 6px var(--color-ink), 0 0 44px -10px rgba(255,122,26,0.55)",
                    }}
                  >
                    {step.no}
                  </span>

                  {/* glyph badge, tucked beside the number on mobile / below on desktop */}
                  <span
                    className="inline-flex h-11 w-11 items-center justify-center rounded-[12px] text-amber md:mt-6"
                    style={{
                      background: "rgba(255,159,10,0.07)",
                      border: "1px solid rgba(255,159,10,0.16)",
                    }}
                  >
                    {step.glyph}
                  </span>
                </div>

                <h3 className="font-display mt-6 text-[26px] leading-none tracking-[-0.01em] text-bone md:mt-7 md:text-[28px]">
                  {step.title}
                </h3>
                <p className="mt-3 max-w-xs text-[15.5px] leading-relaxed text-mist">{step.body}</p>

                {/* mobile flow connector between stacked steps */}
                {i < STEPS.length - 1 && (
                  <span
                    aria-hidden
                    className="mt-8 ml-[33px] block h-9 w-px md:hidden"
                    style={{
                      background:
                        "linear-gradient(180deg, rgba(255,159,10,0.5), rgba(255,159,10,0.05))",
                    }}
                  />
                )}
              </li>
            ))}
          </ol>
        </div>
      </div>
    </section>
  );
}
