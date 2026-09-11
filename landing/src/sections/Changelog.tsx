import { RELEASES, REPO } from "../lib/site";

type Kind = "fixed" | "new";

interface Change {
  kind: Kind;
  text: string;
}

interface Release {
  version: string;
  date: string;
  title: string;
  changes: Change[];
}

// Newest first. Each entry says what changed in the user's terms — what they
// would have noticed, not which file moved. The full history, including the
// pre-rewrite releases, lives on GitHub.
const RELEASES_LOG: Release[] = [
  {
    version: "0.4.2",
    date: "11 Sep 2026",
    title: "Panels that go away",
    changes: [
      {
        kind: "fixed",
        text: "The Recent Captures panel (⇧⌘H) stayed on screen until you went back to the menu bar. It now closes on a click anywhere else, on a Space change, and after Annotate, Copy or Show in Finder.",
      },
      {
        kind: "fixed",
        text: "The capture popup could get stuck permanently. Clicking Copy closed it under the cursor without clearing its hover-pause, so every popup after that never counted down.",
      },
      {
        kind: "fixed",
        text: "The corner hover stack got the same treatment: click-outside, Space change and actions all dismiss it.",
      },
      {
        kind: "fixed",
        text: "Corner hover worked on one Space and not another. The trigger sat inside the Dock strip, reachable only when the Dock was hidden. It is now a strip up the left edge that clears the Dock, and it follows display changes.",
      },
    ],
  },
  {
    version: "0.4.1",
    date: "9 Sep 2026",
    title: "Trimming on Sonoma",
    changes: [
      {
        kind: "fixed",
        text: "Trimming a recording did nothing on macOS 14. The export used an API that only exists on 15; CI caught it minutes after 0.4.0 went out.",
      },
    ],
  },
  {
    version: "0.4.0",
    date: "9 Sep 2026",
    title: "Native Swift, and screen recording",
    changes: [
      {
        kind: "new",
        text: "Rewritten from Tauri to Swift and AppKit. 3.1 MB instead of about 15, and the Spaces and focus bugs that took seven releases are gone by construction.",
      },
      {
        kind: "new",
        text: "Record an area, a window or the whole screen to MP4, with a countdown, optional pointer, and click highlighting drawn into the video.",
      },
      {
        kind: "new",
        text: "Recordings open in a timeline: ruler, drag handles, transport, zoom. Export as video or GIF. The trim applies to your library entry, not just the export.",
      },
      {
        kind: "new",
        text: "The area selection stays put with resize handles and an options bar — exact size, aspect lock, freeze, self-timer.",
      },
      {
        kind: "new",
        text: "A gallery home window grouped by day with search and a collapsible sidebar, and undo/redo in the annotation editor.",
      },
    ],
  },
];

const KIND: Record<Kind, { label: string; className: string }> = {
  fixed: {
    label: "Fixed",
    className: "border-fog bg-mist text-slate",
  },
  new: {
    label: "New",
    className: "border-spark/30 bg-spark-wash text-spark-deep",
  },
};

function Tag({ kind }: { kind: Kind }) {
  const meta = KIND[kind];
  return (
    <span
      className={`inline-flex shrink-0 items-center rounded-full border px-2 py-[1px] font-mono text-[11px] font-medium uppercase tracking-[0.08em] ${meta.className}`}
    >
      {meta.label}
    </span>
  );
}

function Header() {
  return (
    <div className="reveal mx-auto max-w-[56ch] text-center">
      <p className="eyebrow">Changelog</p>
      <h2 className="heading mt-3">What changed, and what got fixed.</h2>
      <p className="mt-4 text-[16px] text-slate">
        Every release, in plain terms. Bugs are named as bugs.
      </p>
    </div>
  );
}

function FullHistory() {
  return (
    <div className="reveal mt-10 flex flex-wrap items-center justify-center gap-x-6 gap-y-2 text-[14px]">
      <a href={RELEASES} className="font-medium text-ink underline-offset-4 hover:underline">
        Full release history →
      </a>
      <a href={`${REPO}/issues`} className="text-graphite transition-colors hover:text-ink">
        Found something? Report it.
      </a>
    </div>
  );
}

/**
 * A timeline. Version and date sit in a narrow left rail; the entry hangs off
 * a hairline. Reads top to bottom like a log should, and stays that way as
 * releases accumulate — a card grid was tried and went uneven at three.
 */
function Timeline() {
  return (
    <ol className="mt-12 border-l border-fog">
      {RELEASES_LOG.map((release, index) => (
        <li
          key={release.version}
          className="reveal relative grid gap-3 pb-10 pl-7 sm:grid-cols-[120px_1fr] sm:gap-8 sm:pl-10"
          style={{ transitionDelay: `${index * 80}ms` }}
        >
          <span
            className={`absolute -left-[5px] top-[7px] h-[9px] w-[9px] rounded-full border-2 border-paper ${
              index === 0 ? "bg-spark" : "bg-steel"
            }`}
            aria-hidden="true"
          />
          <div>
            <p className="font-mono text-[14px] font-medium text-ink">
              v{release.version}
              {index === 0 && (
                <span className="ml-2 rounded-full bg-spark-wash px-2 py-[1px] font-sans text-[11px] font-medium text-spark-deep">
                  Latest
                </span>
              )}
            </p>
            <p className="mt-1 text-[13px] text-graphite">{release.date}</p>
          </div>
          <div>
            <h3 className="text-[17px] font-medium tracking-[-0.01em] text-ink">
              {release.title}
            </h3>
            <ul className="mt-3 space-y-2.5">
              {release.changes.map((change) => (
                <li key={change.text} className="flex items-start gap-3">
                  <Tag kind={change.kind} />
                  <p className="text-[14px] leading-[1.6] text-slate">{change.text}</p>
                </li>
              ))}
            </ul>
          </div>
        </li>
      ))}
    </ol>
  );
}

export default function Changelog() {
  return (
    <section id="changelog" className="py-20">
      <div className="shell">
        <Header />
        <Timeline />
        <FullHistory />
      </div>
    </section>
  );
}
