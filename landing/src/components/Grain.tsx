/**
 * Grain — fixed, full-viewport cinematic atmosphere overlay.
 *
 * Sits above the page (z-40) and is decorative only: pointer-events-none so it
 * never blocks clicks, position:fixed/inset:0 so it never causes layout shift.
 * Two layers:
 *   1. A static film-grain texture from an inline SVG `feTurbulence` data-URI,
 *      kept at very low opacity (~4%) so it adds texture without hurting
 *      readability.
 *   2. A faint radial vignette (transparent center → subtly darker edges) for
 *      "optical instrument" depth.
 *
 * The grain is intentionally static — no animation — which is friendly to
 * `prefers-reduced-motion` and cheap to render. (A static grain is preferred.)
 */

// Inline SVG noise → data URI. feTurbulence fractalNoise tiled across a small
// 160×160 tile, desaturated to greyscale so it reads as neutral film grain.
const NOISE_SVG = encodeURIComponent(
  `<svg xmlns="http://www.w3.org/2000/svg" width="160" height="160" viewBox="0 0 160 160">` +
    `<filter id="n">` +
    `<feTurbulence type="fractalNoise" baseFrequency="0.8" numOctaves="2" stitchTiles="stitch"/>` +
    `<feColorMatrix type="saturate" values="0"/>` +
    `</filter>` +
    `<rect width="100%" height="100%" filter="url(#n)"/>` +
    `</svg>`
);

const NOISE_URI = `url("data:image/svg+xml,${NOISE_SVG}")`;

export default function Grain() {
  return (
    <div
      aria-hidden="true"
      style={{
        position: "fixed",
        inset: 0,
        zIndex: 40,
        pointerEvents: "none",
        // Don't repaint on scroll-driven content beneath; this layer is static.
        contain: "strict",
      }}
    >
      {/* Film grain */}
      <div
        style={{
          position: "absolute",
          inset: 0,
          backgroundImage: NOISE_URI,
          backgroundRepeat: "repeat",
          backgroundSize: "160px 160px",
          opacity: 0.045,
          // Soft-light keeps the texture neutral over both dark and light areas.
          mixBlendMode: "soft-light",
        }}
      />
      {/* Vignette — transparent center, gently darker edges for depth */}
      <div
        style={{
          position: "absolute",
          inset: 0,
          background:
            "radial-gradient(120% 120% at 50% 42%, transparent 55%, rgba(11,10,12,0.28) 100%)",
        }}
      />
    </div>
  );
}
