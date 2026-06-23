import { useReveal } from "../lib/useReveal";

const COFFEE_URL = "https://tiptap.gg/dipta";

export default function Support() {
  const ref = useReveal<HTMLDivElement>();

  return (
    <section id="support" className="relative py-24 md:py-36">
      <div ref={ref} className="container-x">
        <div
          className="surface reveal relative mx-auto max-w-3xl overflow-hidden p-8 text-center md:p-14"
          style={{
            background:
              "radial-gradient(120% 140% at 50% 0%, rgba(255,159,10,0.08) 0%, rgba(255,122,26,0.02) 36%, var(--color-surface) 70%)",
          }}
        >
          {/* soft amber glow halo */}
          <div
            aria-hidden="true"
            className="pointer-events-none absolute -top-24 left-1/2 h-56 w-56 -translate-x-1/2 rounded-full"
            style={{
              background:
                "radial-gradient(closest-side, rgba(255,159,10,0.28), transparent 72%)",
              filter: "blur(18px)",
            }}
          />

          <p className="kicker relative">SUPPORT</p>

          <h2 className="display relative mx-auto mt-5 max-w-xl text-3xl sm:text-4xl md:text-5xl">
            Potret is free.{" "}
            <span className="text-amber-grad">The coffee isn&apos;t.</span>
          </h2>

          <p className="relative mx-auto mt-6 max-w-xl text-base md:text-lg leading-relaxed text-mist">
            The app is 100% free and open-source. The developer&apos;s Claude
            Code subscription, however, is not. The whole thing was vibe-coded by
            an AI that bills by the token — so every coffee literally keeps the
            prompts flowing.
          </p>

          <div className="relative mt-9">
            <a
              href={COFFEE_URL}
              target="_blank"
              rel="noreferrer"
              className="btn btn-primary"
            >
              ☕ Buy me a coffee
            </a>
          </div>

          <p className="relative mt-6 font-mono text-[11.5px] tracking-wide text-faint">
            free forever either way · no paywall, no nag
          </p>
        </div>
      </div>
    </section>
  );
}
