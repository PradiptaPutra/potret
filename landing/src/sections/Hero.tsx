import { useState } from "react";
import { motion, useReducedMotion } from "motion/react";
import ApertureShader from "../components/ApertureShader";

const BREW = "brew install --cask --no-quarantine PradiptaPutra/tap/potret";
const DMG = "https://github.com/PradiptaPutra/potret/releases/latest";
const REPO = "https://github.com/PradiptaPutra/potret";

function CommandChip() {
  const [copied, setCopied] = useState(false);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(BREW);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1500);
    } catch {
      /* clipboard blocked — fail quietly */
    }
  };

  return (
    <div
      className="flex w-full max-w-[560px] items-center gap-2 rounded-full border border-hair-2 bg-[rgba(246,241,233,0.03)] py-1.5 pl-4 pr-1.5 backdrop-blur-sm"
      style={{ boxShadow: "0 1px 0 0 rgba(246,241,233,0.04) inset" }}
    >
      <span aria-hidden className="select-none font-mono text-[13px] text-faint">
        $
      </span>
      <code className="min-w-0 flex-1 truncate font-mono text-[12.5px] tracking-tight text-mist md:text-[13px]">
        {BREW}
      </code>
      <button
        type="button"
        onClick={copy}
        aria-label={copied ? "Copied" : "Copy install command"}
        className="inline-flex h-8 shrink-0 items-center gap-1.5 rounded-full border border-hair-2 bg-[rgba(246,241,233,0.04)] px-3 font-mono text-[11px] uppercase tracking-[0.12em] text-bone transition-colors duration-200 hover:border-amber/40 hover:text-amber"
      >
        {copied ? (
          <>
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" aria-hidden>
              <path
                d="M20 6L9 17l-5-5"
                stroke="currentColor"
                strokeWidth="2.4"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
            </svg>
            Copied
          </>
        ) : (
          <>
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" aria-hidden>
              <rect x="9" y="9" width="11" height="11" rx="2.5" stroke="currentColor" strokeWidth="2" />
              <path
                d="M5 15V5a2 2 0 0 1 2-2h10"
                stroke="currentColor"
                strokeWidth="2"
                strokeLinecap="round"
              />
            </svg>
            Copy
          </>
        )}
      </button>
    </div>
  );
}

export default function Hero() {
  const reduce = useReducedMotion();

  // staggered load-in: kicker → H1 → sub → CTAs → chip → mockup
  const rise = {
    hidden: { opacity: 0, y: reduce ? 0 : 24 },
    show: (i: number) => ({
      opacity: 1,
      y: 0,
      transition: {
        duration: reduce ? 0 : 0.9,
        delay: reduce ? 0 : 0.12 + i * 0.12,
        ease: [0.16, 1, 0.3, 1] as const,
      },
    }),
  };

  const scrollToDownload = (e: React.MouseEvent<HTMLAnchorElement>) => {
    e.preventDefault();
    document
      .getElementById("download")
      ?.scrollIntoView({ behavior: reduce ? "auto" : "smooth", block: "start" });
  };

  return (
    <section className="relative flex min-h-screen flex-col items-center justify-center overflow-hidden pb-20 pt-28 md:pb-28 md:pt-32">
      <ApertureShader />

      {/* readability scrim — keeps text crisp over the bright iris */}
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0 -z-10"
        style={{
          background:
            "radial-gradient(150% 80% at 50% 0%, rgba(11,10,12,0) 35%, rgba(11,10,12,0.55) 100%)",
        }}
      />

      <div className="container-x relative flex flex-col items-center text-center">
        {/* kicker */}
        <motion.p
          className="kicker mb-6"
          custom={0}
          variants={rise}
          initial="hidden"
          animate="show"
        >
          FREE · OPEN-SOURCE · macOS
        </motion.p>

        {/* H1 */}
        <motion.h1
          className="display mx-auto max-w-[16ch] text-balance text-5xl md:text-7xl lg:text-8xl"
          custom={1}
          variants={rise}
          initial="hidden"
          animate="show"
        >
          Screenshots with a sense of{" "}
          <span className="text-amber-grad font-light italic">style.</span>
        </motion.h1>

        {/* sub */}
        <motion.p
          className="mx-auto mt-7 max-w-[58ch] text-[17px] leading-relaxed text-mist md:text-[19px]"
          custom={2}
          variants={rise}
          initial="hidden"
          animate="show"
        >
          Potret lives in your menu bar. Snap an area, a window, or the whole
          screen — then copy, annotate, pin, or drop it onto a gorgeous
          background. No heavy editor. No subscription.
        </motion.p>

        {/* CTAs */}
        <motion.div
          className="mt-9 flex flex-col items-center gap-x-4 gap-y-3 sm:flex-row sm:flex-wrap sm:justify-center"
          custom={3}
          variants={rise}
          initial="hidden"
          animate="show"
        >
          <a href="#download" onClick={scrollToDownload} className="btn btn-primary">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" aria-hidden>
              <path
                d="M12 3v12m0 0 4.5-4.5M12 15l-4.5-4.5M5 19h14"
                stroke="currentColor"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
            </svg>
            Install with Homebrew
          </a>
          <a href={DMG} target="_blank" rel="noreferrer" className="btn btn-ghost">
            Download .dmg
          </a>
          <a
            href={REPO}
            target="_blank"
            rel="noreferrer"
            className="px-2 py-2 text-[14px] text-mist transition-colors duration-200 hover:text-bone"
          >
            View source ↗
          </a>
        </motion.div>

        {/* command chip */}
        <motion.div
          className="mt-7 flex w-full justify-center"
          custom={4}
          variants={rise}
          initial="hidden"
          animate="show"
        >
          <CommandChip />
        </motion.div>

        {/* floating, perspective-tilted app mockup */}
        <motion.div
          className="mt-16 w-full max-w-[940px] md:mt-20"
          style={{ perspective: "1600px" }}
          custom={5}
          variants={rise}
          initial="hidden"
          animate="show"
        >
          <motion.div
            animate={reduce ? undefined : { y: [0, -10, 0] }}
            transition={
              reduce
                ? undefined
                : { duration: 7, repeat: Infinity, ease: "easeInOut" }
            }
            style={{ transform: reduce ? "none" : "rotateX(7deg)" }}
            className="origin-top"
          >
            <div
              className="surface overflow-hidden"
              style={{
                boxShadow:
                  "var(--glow-amber), 0 60px 120px -40px rgba(0,0,0,0.85)",
              }}
            >
              {/* faux macOS window chrome */}
              <div className="flex h-9 items-center gap-2 border-b border-hair bg-[rgba(20,19,23,0.9)] px-4">
                <span className="h-3 w-3 rounded-full bg-[#ff5f57]" />
                <span className="h-3 w-3 rounded-full bg-[#febc2e]" />
                <span className="h-3 w-3 rounded-full bg-[#28c840]" />
                <span className="ml-3 font-mono text-[11px] tracking-tight text-faint">
                  Potret
                </span>
              </div>
              <img
                src="/home.png"
                alt="Potret capturing a screenshot from the macOS menu bar"
                width={1880}
                height={1180}
                loading="eager"
                decoding="async"
                className="block w-full"
              />
            </div>
          </motion.div>
        </motion.div>
      </div>

      {/* scroll cue */}
      <motion.a
        href="#features"
        aria-hidden
        tabIndex={-1}
        className="pointer-events-none absolute bottom-6 left-1/2 hidden -translate-x-1/2 flex-col items-center gap-2 md:flex"
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: reduce ? 0 : 1.5, duration: 0.8 }}
      >
        <span className="font-mono text-[10px] uppercase tracking-[0.3em] text-faint">
          Scroll
        </span>
        <motion.svg
          width="16"
          height="22"
          viewBox="0 0 16 22"
          fill="none"
          animate={reduce ? undefined : { y: [0, 5, 0] }}
          transition={
            reduce ? undefined : { duration: 1.8, repeat: Infinity, ease: "easeInOut" }
          }
        >
          <path
            d="M8 1v14m0 0 5-5M8 15l-5-5"
            stroke="var(--color-faint)"
            strokeWidth="1.4"
            strokeLinecap="round"
            strokeLinejoin="round"
          />
        </motion.svg>
      </motion.a>
    </section>
  );
}
