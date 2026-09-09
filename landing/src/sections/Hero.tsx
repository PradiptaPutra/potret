import MacWindow from "../components/MacWindow";
import { BREW, DMG, RELEASES, SPECS, VERSION } from "../lib/site";
import CopyLine from "../components/CopyLine";

/**
 * Two-column asymmetric split: the claim on the left, the product on the
 * right. The product is a real screenshot of the shipping app, not an
 * illustration — it is the entire argument.
 */
export default function Hero() {
  return (
    <section className="pt-32 pb-20 sm:pt-40">
      <div className="shell grid items-center gap-14 lg:grid-cols-[55fr_45fr]">
        <div className="reveal min-w-0">
          <p className="eyebrow">Free &amp; open source · v{VERSION}</p>

          <h1 className="display mt-4 max-w-[15ch]">
            Screenshots and screen recording for macOS.
          </h1>

          <p className="mt-5 max-w-[52ch] text-[16px] text-slate">
            Potret lives in your menu bar. Capture an area, a window or the
            whole screen — then annotate it, pin it, or drag it straight into
            another app. Record your screen with click highlighting and trim it
            on a real timeline. No subscription, no account, no telemetry.
          </p>

          <div className="mt-8 flex flex-wrap items-center gap-3">
            <a href={DMG} className="btn btn-primary">
              <AppleMark />
              Download for macOS
            </a>
            <a href={RELEASES} className="btn btn-ghost">
              All releases
            </a>
          </div>

          <div className="mt-5 max-w-[560px]">
            <CopyLine command={BREW} />
          </div>

          <dl className="mt-8 flex flex-wrap gap-x-8 gap-y-3">
            {SPECS.map((spec) => (
              <div key={spec.label}>
                <dt className="text-[12px] text-graphite">{spec.label}</dt>
                <dd className="text-[14px] font-medium text-ink">
                  {spec.value}
                </dd>
              </div>
            ))}
          </dl>
        </div>

        <div className="reveal min-w-0" style={{ transitionDelay: "120ms" }}>
          <MacWindow
            src="/shot-home.png"
            alt="The Potret window: a gallery of captures grouped by day, with a sidebar and a capture toolbar."
          />
        </div>
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
