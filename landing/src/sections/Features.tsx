import type { ReactElement } from "react";
type Feature = {
  title: string;
  body: string;
  icon: () => ReactElement;
};

const stroke = {
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 1.7,
  strokeLinecap: "round" as const,
  strokeLinejoin: "round" as const,
};

const FEATURES: Feature[] = [
  {
    title: "Annotation that undoes",
    body:
      "Pen, arrow, line, rectangle, ellipse, text, highlighter, numbered steps, pixelate and blur, plus crop. Undo and redo sit at the head of the toolbar, and text is typed straight onto the canvas at its real size.",
    icon: () => (
      <svg viewBox="0 0 24 24" {...stroke} className="size-5">
        <path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L8 18l-4 1 1-4z" />
        <path d="M14 6l4 4" />
      </svg>
    ),
  },
  {
    title: "Backgrounds",
    body:
      "Drop a screenshot onto a gradient or an image of your own, with padding, rounded corners and a real shadow. The kind of shot a changelog or a launch post wants.",
    icon: () => (
      <svg viewBox="0 0 24 24" {...stroke} className="size-5">
        <rect x="2.5" y="4.5" width="19" height="15" rx="2.5" />
        <rect x="7" y="8.5" width="10" height="7" rx="1.5" />
      </svg>
    ),
  },
  {
    title: "Pin to screen",
    body:
      "Keep a capture floating above everything while you work from it. It stays put across desktops and full-screen apps.",
    icon: () => (
      <svg viewBox="0 0 24 24" {...stroke} className="size-5">
        <path d="M12 17v4" />
        <path d="M9 3h6l-1 6 3 3v2H7v-2l3-3z" />
      </svg>
    ),
  },
  {
    title: "A library, not a pile",
    body:
      "Everything you have captured, grouped by day, with search and a sidebar that collapses to a rail. Filter to screenshots or recordings, and set how much history to keep.",
    icon: () => (
      <svg viewBox="0 0 24 24" {...stroke} className="size-5">
        <rect x="3" y="4" width="7.5" height="7.5" rx="1.6" />
        <rect x="13.5" y="4" width="7.5" height="7.5" rx="1.6" />
        <rect x="3" y="14.5" width="7.5" height="5.5" rx="1.6" />
        <rect x="13.5" y="14.5" width="7.5" height="5.5" rx="1.6" />
      </svg>
    ),
  },
  {
    title: "Output on your terms",
    body:
      "PNG or JPEG at a quality you choose, filenames from a template, and a save folder that is wherever you say. Recordings export as MP4 or GIF, with the GIF size estimated before it writes.",
    icon: () => (
      <svg viewBox="0 0 24 24" {...stroke} className="size-5">
        <path d="M12 3v11" />
        <path d="m7.5 10 4.5 4.5 4.5-4.5" />
        <path d="M4 17.5V19a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-1.5" />
      </svg>
    ),
  },
  {
    title: "Shortcuts that cannot brick",
    body:
      "Global hotkeys for every capture mode, recorded as real key codes rather than parsed from text. A shortcut macOS already owns is refused with a reason instead of silently killing the rest.",
    icon: () => (
      <svg viewBox="0 0 24 24" {...stroke} className="size-5">
        <rect x="2.5" y="6" width="19" height="12" rx="2.5" />
        <path d="M6.5 10h.01M10 10h.01M13.5 10h.01M17 10h.01M8 14h8" />
      </svg>
    ),
  },
  {
    title: "Menu bar only",
    body:
      "No Dock tile unless a window is open. Launch at login if you want it, and every animation respects Reduce Motion.",
    icon: () => (
      <svg viewBox="0 0 24 24" {...stroke} className="size-5">
        <rect x="2.5" y="4.5" width="19" height="15" rx="2.5" />
        <path d="M2.5 9h19" />
        <path d="M17 6.7h.01" />
      </svg>
    ),
  },
];

export default function Features() {
  return (
    <section id="features" className="py-20">
      <div className="shell">
        <div className="reveal mx-auto max-w-[52ch] text-center">
          <p className="eyebrow">Everything else</p>
          <h2 className="heading mt-3">The parts you use every day.</h2>
        </div>

        <div className="mt-12 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {FEATURES.map((feature, index) => (
            <article
              key={feature.title}
              className="card reveal"
              style={{ transitionDelay: `${Math.min(index, 5) * 60}ms` }}
            >
              <span className="inline-flex size-9 items-center justify-center rounded-lg bg-[var(--color-spark-wash)] text-[var(--color-spark-deep)]">
                {feature.icon()}
              </span>
              <h3 className="mt-4 text-[17px] font-medium text-ink">
                {feature.title}
              </h3>
              <p className="mt-2 text-[14px] leading-[1.6] text-slate">
                {feature.body}
              </p>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}
