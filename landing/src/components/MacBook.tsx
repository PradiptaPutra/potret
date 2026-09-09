import { useEffect, useRef, useState, type ReactNode } from "react";
import { Screen } from "./macos";

/**
 * A MacBook whose lid opens as you scroll it into view.
 *
 * The lid is a plane rotated about its bottom edge — the hinge — inside a
 * container with perspective. Scroll progress drives the angle from nearly
 * shut to upright, so the product reveals itself rather than simply being
 * there. The same trick Apple's product pages use.
 *
 * Everything is drawn: the device, the wallpaper, the menu bar, the dock. A
 * photograph of a real Mac would carry a real desktop, which is the thing
 * these images exist to avoid.
 */
export default function MacBook({ children }: { children: ReactNode }) {
  const ref = useRef<HTMLDivElement>(null);
  const [progress, setProgress] = useState(0);

  useEffect(() => {
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduced) {
      // No theatre for anyone who asked not to have it — just show the thing.
      setProgress(1);
      return;
    }

    let frame = 0;
    const measure = () => {
      frame = 0;
      const el = ref.current;
      if (!el) return;
      const rect = el.getBoundingClientRect();
      // Shut when the device is a screen-height away; fully open by the time
      // it is a third of the way up the viewport.
      const from = window.innerHeight * 0.95;
      const to = window.innerHeight * 0.3;
      const next = (from - rect.top) / (from - to);
      setProgress(Math.min(1, Math.max(0, next)));
    };
    const onScroll = () => {
      if (frame) return;
      frame = window.requestAnimationFrame(measure);
    };

    measure();
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onScroll);
    return () => {
      window.removeEventListener("scroll", onScroll);
      window.removeEventListener("resize", onScroll);
      if (frame) window.cancelAnimationFrame(frame);
    };
  }, []);

  // Eased, so the last few degrees settle rather than snap.
  const eased = 1 - Math.pow(1 - progress, 3);
  const angle = -84 + 84 * eased;

  return (
    <div ref={ref} className="mx-auto w-full max-w-[820px]" style={{ containerType: "inline-size" }}>
      <div style={{ perspective: "1700px", perspectiveOrigin: "50% 82%" }}>
        {/* Lid: a thin aluminium rim, a black bezel, then the screen. On a
            real machine the aluminium is only a couple of millimetres at the
            edge — a thick grey frame is the thing that made this read as a
            monitor rather than a laptop. */}
        <div
          className="relative origin-bottom"
          style={{
            transform: `rotateX(${angle}deg)`,
            transformStyle: "preserve-3d",
            transformOrigin: "50% 100%",
            aspectRatio: "16 / 10.6",
            background: "linear-gradient(180deg,#6a6e75 0%,#4a4e54 4%,#3a3d43 100%)",
            padding: "0.5%",
            borderRadius: "1.4% 1.4% 0.2% 0.2% / 2.1% 2.1% 0.3% 0.3%",
            boxShadow:
              "0 40px 60px -30px rgba(0,0,0,.55), inset 0 0 0 1px rgba(255,255,255,.10)",
          }}
        >
          <div
            className="relative h-full w-full"
            style={{
              background: "#0b0b0d",
              borderRadius: "1.1% 1.1% 0.15% 0.15% / 1.7% 1.7% 0.2% 0.2%",
              padding: "1.15%",
              paddingBottom: "1.5%",
            }}
          >
            <div className="relative h-full w-full overflow-hidden" style={{ borderRadius: "3px" }}>
              <Screen>{children}</Screen>
              <Notch />
            </div>
          </div>
          {/* The glass catches the room light, most of all while it is tilted. */}
          <div
            className="pointer-events-none absolute inset-0"
            style={{
              borderRadius: "1.4% 1.4% 0.2% 0.2% / 2.1% 2.1% 0.3% 0.3%",
              background:
                "linear-gradient(103deg, rgba(255,255,255,.16) 0%, rgba(255,255,255,0) 34%)",
              opacity: 0.5 + 0.5 * (1 - eased),
            }}
          />
        </div>

        <Base />
      </div>
    </div>
  );
}

function Notch() {
  return (
    <div className="pointer-events-none absolute inset-x-0 top-0 z-40 flex justify-center">
      <div
        className="flex items-center justify-center"
        style={{
          width: "13.5%",
          height: "4.6%",
          background: "#000",
          borderRadius: "0 0 7px 7px",
        }}
      >
        <span
          style={{
            width: "5%",
            height: "26%",
            borderRadius: "9999px",
            background: "rgba(120,130,150,.5)",
          }}
        />
      </div>
    </div>
  );
}

/**
 * The deck.
 *
 * Head-on you are looking at the front edge of the base, and three things make
 * it read as one: it is *wider* than the lid, because you see past the lid's
 * sides; it flares slightly towards you rather than being a rectangle; and it
 * has the thumb notch cut into the middle of its front edge. Without those it
 * is a monitor stand.
 */
function Base() {
  return (
    <div className="relative">
      {/* The hinge, in the shadow under the lid. */}
      <div
        className="mx-auto"
        style={{
          width: "99%",
          height: "0.55cqw",
          minHeight: "3px",
          background: "linear-gradient(180deg,#1a1c1f,#303338)",
          borderRadius: "0 0 2px 2px",
        }}
      />
      <div className="relative" style={{ width: "109%", marginLeft: "-4.5%" }}>
        <div
          style={{
            height: "1.5cqw",
            minHeight: "11px",
            background:
              "linear-gradient(180deg,#8f949c 0%,#6c7076 14%,#4c5055 55%,#33363b 100%)",
            clipPath: "polygon(2.4% 0, 97.6% 0, 100% 100%, 0 100%)",
            borderRadius: "0 0 10px 10px",
          }}
        />
        {/* Thumb notch. */}
        <div className="absolute inset-x-0 top-0 flex justify-center">
          <div
            style={{
              width: "11%",
              height: "0.42cqw",
              minHeight: "3px",
              background: "linear-gradient(180deg,#1f2124,#33363b)",
              borderRadius: "0 0 999px 999px",
            }}
          />
        </div>
      </div>
      {/* The shadow the machine casts on the page. */}
      <div
        className="mx-auto"
        style={{
          width: "84%",
          height: "30px",
          marginTop: "-4px",
          background:
            "radial-gradient(50% 50% at 50% 40%, rgba(0,0,0,.26) 0%, rgba(0,0,0,0) 72%)",
        }}
      />
    </div>
  );
}
