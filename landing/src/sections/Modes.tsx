import MacWindow from "../components/MacWindow";

type Mode = {
  id: string;
  eyebrow: string;
  title: string;
  body: string;
  points: string[];
  shot: string;
  alt: string;
  caption: string;
};

/**
 * Three stacked sections rather than three tabs.
 *
 * The first version put these behind a segmented control, which meant a
 * visitor scrolling past saw only the first one — recording and trimming, the
 * two headline features of this release, were invisible unless you happened to
 * click. Alternating the image side keeps the rhythm without hiding anything.
 */
const MODES: Mode[] = [
  {
    id: "capture",
    eyebrow: "Capture",
    title: "Drag once. Decide after.",
    body:
      "The selection stays put when you let go. Nudge it with handles, type an exact size, lock the aspect ratio — then capture it, or record it, without starting over.",
    points: [
      "Area, window, or the whole screen",
      "Type exact pixel dimensions, or lock the ratio",
      "Freeze the screen so a menu stops closing on you",
      "Self-timer for hover states that vanish",
    ],
    shot: "/shot-selector.png",
    alt: "A selected area with resize handles, and a bar beneath it holding capture, record, timer and freeze buttons beside width and height fields.",
    caption: "The options bar, after the drag",
  },
  {
    id: "record",
    eyebrow: "Record",
    title: "A demo people can actually follow.",
    body:
      "Record an area, a window or the screen to MP4. Every click gets a ring drawn into the video — never onto your screen — so a viewer sees what you did, not just what changed.",
    points: [
      "Click highlighting, composited into the frames",
      "A countdown before it rolls, so you can get set",
      "Hide the pointer for a clean walkthrough",
      "Standard or high quality, 30 or 60 fps",
    ],
    shot: "/shot-clicks.png",
    alt: "A frame from a recording with amber rings marking two places the pointer was clicked.",
    caption: "Clicks, marked in the video only",
  },
  {
    id: "trim",
    eyebrow: "Trim",
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
    caption: "Trimming a recording",
  },
];

export default function Modes() {
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

        <div className="mt-16 space-y-20">
          {MODES.map((mode, index) => (
            <div
              key={mode.id}
              id={mode.id}
              className="grid items-center gap-12 lg:grid-cols-2"
            >
              <div
                className={`reveal min-w-0 ${index % 2 === 1 ? "lg:order-2" : ""}`}
              >
                <p className="eyebrow">{mode.eyebrow}</p>
                <h3 className="heading mt-3">{mode.title}</h3>
                <p className="mt-4 max-w-[52ch] text-[16px] text-slate">
                  {mode.body}
                </p>
                <ul className="mt-6 space-y-3">
                  {mode.points.map((point) => (
                    <li key={point} className="flex gap-3 text-[15px] text-ink">
                      <Tick />
                      <span>{point}</span>
                    </li>
                  ))}
                </ul>
              </div>

              <div
                className={`reveal min-w-0 ${index % 2 === 1 ? "lg:order-1" : ""}`}
                style={{ transitionDelay: "80ms" }}
              >
                <MacWindow src={mode.shot} alt={mode.alt} title={mode.caption} />
              </div>
            </div>
          ))}
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
