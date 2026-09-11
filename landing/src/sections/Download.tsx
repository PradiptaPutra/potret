import CopyLine from "../components/CopyLine";
import StarButton from "../components/StarButton";
import { BREW, DMG, RELEASES, VERSION } from "../lib/site";

/**
 * The closing conversion block — a contained card on a faintly cooler wash, so
 * it reads as a distinct object rather than as more page.
 */
export default function Download() {
  return (
    <section id="download" className="py-20">
      <div className="shell">
        <div
          className="reveal rounded-2xl border border-fog bg-paper px-6 py-14 text-center sm:px-14"
          style={{ boxShadow: "var(--shadow-card)" }}
        >
          <p className="eyebrow">Version {VERSION}</p>
          <h2 className="heading mx-auto mt-3 max-w-[20ch]">
            Free, for as long as it exists.
          </h2>
          <p className="mx-auto mt-4 max-w-[48ch] text-[16px] text-slate">
            Universal for Apple Silicon and Intel. Requires macOS 14 Sonoma or
            later.
          </p>

          <div className="mt-8 flex flex-wrap items-center justify-center gap-3">
            <a href={DMG} className="btn btn-primary">
              Download the .dmg
            </a>
            <a href={RELEASES} className="btn btn-ghost">
              Release notes
            </a>
          </div>

          <div className="mx-auto mt-6 max-w-[440px] text-left">
            <CopyLine command={BREW} />
            <p className="mt-2 text-center text-[13px] text-graphite">
              Homebrew is the cleaner path — it clears the quarantine flag for
              you, so there is no Gatekeeper prompt.
            </p>
          </div>

          <div className="mx-auto mt-8 flex max-w-[52ch] flex-col items-center gap-3 border-t border-fog pt-8">
            <p className="text-[14px] text-slate">
              No account, no upsell, nothing to buy. If it earns a place in your
              menu bar, a star is the whole price.
            </p>
            <StarButton size="large" />
          </div>

          <details className="mx-auto mt-8 max-w-[52ch] text-left">
            <summary className="cursor-pointer text-[14px] font-medium text-ink">
              Installing the .dmg by hand? One extra step.
            </summary>
            <div className="mt-3 space-y-3 text-[14px] leading-[1.6] text-slate">
              <p>
                Potret is open source and not notarised by Apple, so the first
                open is blocked with “Apple could not verify…”. Drag Potret to
                Applications, then either run
              </p>
              <code className="block overflow-x-auto rounded-md border border-fog bg-mist px-3 py-2 font-mono text-[13px] text-slate">
                xattr -dr com.apple.quarantine /Applications/Potret.app
              </code>
              <p>
                or double-click it once and choose <strong>Open Anyway</strong>{" "}
                in System Settings under Privacy &amp; Security. Then grant
                Screen Recording and restart Potret. It lives in the menu bar,
                not the Dock.
              </p>
            </div>
          </details>
        </div>
      </div>
    </section>
  );
}
