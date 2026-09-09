/**
 * The Potret aperture — the same six-blade mark the app draws in its menu bar,
 * in the same amber. Inline SVG so it stays crisp at any size and needs no
 * raster pair.
 */
export function ApertureMark({
  size = 24,
  className,
}: {
  size?: number;
  className?: string;
}) {
  const blades = Array.from({ length: 6 }, (_, i) => i * 60);
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      aria-hidden="true"
      className={className}
    >
      {blades.map((deg, index) => (
        <ellipse
          key={deg}
          cx="12"
          cy="6.6"
          rx="2.1"
          ry="4.6"
          fill="var(--color-spark)"
          /* The three rear blades sit back at lower opacity — the depth cue
             that makes six ellipses read as an iris. */
          opacity={index % 2 === 1 ? 0.55 : 1}
          transform={`rotate(${deg} 12 12)`}
        />
      ))}
    </svg>
  );
}

export function Logo({ className }: { className?: string }) {
  return (
    <a
      href="#top"
      className={`inline-flex items-center gap-2 ${className ?? ""}`}
      aria-label="Potret — home"
    >
      <ApertureMark size={22} />
      <span className="text-[17px] font-bold tracking-[-0.02em] text-ink">
        Potret
      </span>
    </a>
  );
}
