import { useState } from "react";
import { useReveal } from "../lib/useReveal";

const BREW_INSTALL = "brew install --cask --no-quarantine PradiptaPutra/tap/potret";
const BREW_UPGRADE = "brew upgrade --cask potret";
const DMG_URL = "https://github.com/PradiptaPutra/potret/releases/latest";
const README_URL = "https://github.com/PradiptaPutra/potret#readme";
const XATTR_CMD = "xattr -dr com.apple.quarantine /Applications/Potret.app";

export default function Download() {
  const ref = useReveal<HTMLDivElement>();
  const [copied, setCopied] = useState(false);

  const copyBrew = async () => {
    try {
      await navigator.clipboard.writeText(BREW_INSTALL);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1500);
    } catch {
      /* clipboard unavailable — no-op */
    }
  };

  return (
    <section id="download" className="relative py-24 md:py-36">
      <div ref={ref} className="container-x">
        {/* header */}
        <div className="max-w-2xl reveal">
          <p className="kicker">GET POTRET</p>
          <h2 className="display mt-4 text-4xl sm:text-5xl md:text-6xl">
            Free. Open-source.{" "}
            <span className="text-amber-grad">Yours in one command.</span>
          </h2>
          <p className="mt-5 text-base md:text-lg text-mist leading-relaxed">
            macOS, universal — Apple Silicon &amp; Intel. Lives quietly in your
            menu bar, never in the Dock.
          </p>
        </div>

        {/* two install paths */}
        <div className="mt-12 grid gap-6 md:grid-cols-2">
          {/* Homebrew */}
          <div
            className="surface reveal flex flex-col p-6 md:p-8"
            style={{ ["--reveal-delay" as string]: "80ms" }}
          >
            <div className="flex items-center justify-between gap-3">
              <h3 className="font-display text-2xl text-bone tracking-tight">
                Homebrew
              </h3>
              <span className="inline-flex items-center rounded-full border border-[color:var(--color-hair-2)] bg-[rgba(255,159,10,0.08)] px-3 py-1 font-mono text-[10.5px] font-medium uppercase tracking-[0.14em] text-amber">
                Recommended — cleanest install
              </span>
            </div>

            {/* code block + copy */}
            <div className="mt-6 rounded-[14px] border border-[color:var(--color-hair)] bg-ink-2 p-1.5">
              <div className="flex items-start gap-3 px-3.5 py-3">
                <code className="flex-1 break-all font-mono text-[12.5px] leading-relaxed text-bone">
                  <span className="select-none text-faint">$ </span>
                  {BREW_INSTALL}
                </code>
                <button
                  type="button"
                  onClick={copyBrew}
                  aria-label={copied ? "Copied" : "Copy install command"}
                  className="shrink-0 rounded-md border border-[color:var(--color-hair-2)] bg-[rgba(246,241,233,0.04)] px-2.5 py-1.5 font-mono text-[11px] font-medium text-mist transition-colors hover:text-bone hover:border-[rgba(246,241,233,0.22)] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-amber"
                >
                  {copied ? "✓ copied" : "copy"}
                </button>
              </div>
            </div>

            <p className="mt-3.5 text-sm text-faint leading-relaxed">
              <code className="font-mono text-mist">--no-quarantine</code> skips
              the Gatekeeper warning, so Potret just opens.
            </p>

            <p className="mt-auto pt-6 font-mono text-[11.5px] text-faint">
              update ·{" "}
              <span className="text-mist">{BREW_UPGRADE}</span>
            </p>
          </div>

          {/* Direct .dmg */}
          <div
            className="surface reveal flex flex-col p-6 md:p-8"
            style={{ ["--reveal-delay" as string]: "160ms" }}
          >
            <h3 className="font-display text-2xl text-bone tracking-tight">
              Direct download
            </h3>
            <p className="mt-3 text-sm text-mist leading-relaxed">
              Prefer to grab the app yourself? Pull the latest signed{" "}
              <code className="font-mono text-bone">.dmg</code> straight from
              GitHub Releases.
            </p>

            <div className="mt-auto pt-7">
              <a
                href={DMG_URL}
                target="_blank"
                rel="noreferrer"
                className="btn btn-primary"
              >
                Download .dmg ↓
              </a>
              <p className="mt-4 font-mono text-[11.5px] text-faint">
                universal — Apple Silicon &amp; Intel
              </p>
            </div>
          </div>
        </div>

        {/* first-launch note */}
        <div
          className="reveal mt-6 rounded-[18px] border border-[color:var(--color-hair)] bg-[rgba(255,159,10,0.035)] p-6 md:p-7"
          style={{ ["--reveal-delay" as string]: "220ms" }}
        >
          <div className="flex flex-col gap-3 md:flex-row md:items-start md:gap-5">
            <span
              aria-hidden="true"
              className="font-mono text-sm text-amber md:pt-0.5"
            >
              ✦ first launch
            </span>
            <div className="text-sm leading-relaxed text-mist">
              <p>
                Potret isn&apos;t Apple-notarized — it&apos;s open-source, so
                there&apos;s no developer account paying the toll. The first open
                needs one tiny step, just once:
              </p>
              <ul className="mt-3 space-y-2">
                <li className="flex flex-col gap-1.5 sm:flex-row sm:items-baseline sm:gap-3">
                  <code className="break-all rounded-md bg-ink-2 px-2.5 py-1 font-mono text-[12px] text-bone">
                    {XATTR_CMD}
                  </code>
                  <span className="text-faint">in Terminal, or…</span>
                </li>
                <li>
                  <span className="text-bone">System Settings → Privacy &amp; Security</span>{" "}
                  → <span className="text-bone">Open Anyway</span>. Then grant{" "}
                  <span className="text-bone">Screen Recording</span> and
                  you&apos;re set.
                </li>
              </ul>
              <p className="mt-3 text-faint">
                Want the full walkthrough?{" "}
                <a
                  href={README_URL}
                  target="_blank"
                  rel="noreferrer"
                  className="text-amber underline decoration-[rgba(255,159,10,0.4)] underline-offset-4 transition-colors hover:decoration-amber focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-amber"
                >
                  see the README ↗
                </a>
              </p>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
