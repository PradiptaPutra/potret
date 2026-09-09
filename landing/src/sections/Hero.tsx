import CopyLine from "../components/CopyLine";
import { BREW, DMG, RELEASES, SPECS, VERSION } from "../lib/site";

/**
 * Centred rather than two-column.
 *
 * The product shot moved into the MacBook below, which opens as you scroll
 * into it — so a second copy of the same window beside the headline would only
 * have stolen its arrival. What is left is the claim and the download.
 */
export default function Hero() {
  return (
    <section className="pt-32 pb-10 sm:pt-40">
      <div className="shell text-center">
        <p className="eyebrow reveal">Free &amp; open source · v{VERSION}</p>

        <h1 className="display reveal mx-auto mt-4 max-w-[18ch]">
          Screenshots and screen recording for macOS.
        </h1>

        <p className="reveal mx-auto mt-5 max-w-[58ch] text-[16px] text-slate">
          Potret lives in your menu bar. Capture an area, a window or the whole
          screen — then annotate it, pin it, or drag it straight into another
          app. Record your screen with click highlighting and trim it on a real
          timeline. No subscription, no account, no telemetry.
        </p>

        <div className="reveal mt-8 flex flex-wrap items-center justify-center gap-3">
          <a href={DMG} className="btn btn-primary">
            <AppleMark />
            Download for macOS
          </a>
          <a href={RELEASES} className="btn btn-ghost">
            All releases
          </a>
        </div>

        <div className="reveal mx-auto mt-5 max-w-[440px] text-left">
          <CopyLine command={BREW} />
        </div>

        <dl className="reveal mt-8 flex flex-wrap justify-center gap-x-10 gap-y-3">
          {SPECS.map((spec) => (
            <div key={spec.label}>
              <dt className="text-[12px] text-graphite">{spec.label}</dt>
              <dd className="text-[14px] font-medium text-ink">{spec.value}</dd>
            </div>
          ))}
        </dl>
      </div>
    </section>
  );
}

function AppleMark() {
  return (
    <svg width="15" height="15" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path d="M16.36 12.78c-.02-2.3 1.88-3.4 1.96-3.46-1.07-1.56-2.73-1.78-3.32-1.8-1.41-.14-2.76.83-3.48.83-.72 0-1.83-.81-3.01-.79-1.55.02-2.98.9-3.78 2.28-1.61 2.79-.41 6.92 1.15 9.18.76 1.11 1.67 2.35 2.86 2.31 1.15-.05 1.58-.74 2.97-.74 1.38 0 1.78.74 2.99.72 1.24-.02 2.02-1.13 2.78-2.24.87-1.28 1.23-2.52 1.25-2.59-.03-.01-2.4-.92-2.42-3.66zM14.1 5.66c.63-.77 1.06-1.83.94-2.9-.91.04-2.01.61-2.66 1.37-.58.68-1.09 1.76-.95 2.8 1.01.08 2.04-.51 2.67-1.27z" />
    </svg>
  );
}
