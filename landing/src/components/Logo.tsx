/**
 * Potret aperture mark — 8-petal iris in the amber petal gradient.
 * Crisp inline SVG (no raster). Used by Nav and Footer.
 */
export function ApertureMark({
  size = 26,
  className,
}: {
  size?: number;
  className?: string;
}) {
  const petals = Array.from({ length: 8 }, (_, i) => i * 45);
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      aria-hidden="true"
      className={className}
    >
      <defs>
        <linearGradient id="potret-petal" x1="4" y1="2" x2="20" y2="22" gradientUnits="userSpaceOnUse">
          <stop stopColor="#FFB23E" />
          <stop offset="0.5" stopColor="#FF8A12" />
          <stop offset="1" stopColor="#F25C05" />
        </linearGradient>
      </defs>
      {petals.map((deg) => (
        <ellipse
          key={deg}
          cx="12"
          cy="6.4"
          rx="2.05"
          ry="4.7"
          fill="url(#potret-petal)"
          transform={`rotate(${deg} 12 12)`}
        />
      ))}
      <circle cx="12" cy="12" r="2.1" fill="#0b0a0c" />
    </svg>
  );
}

export function Wordmark({ className }: { className?: string }) {
  return (
    <span
      className={className}
      style={{
        fontFamily: "var(--font-display)",
        fontWeight: 600,
        letterSpacing: "-0.02em",
        fontSize: "20px",
      }}
    >
      Potret
    </span>
  );
}

export function Logo({ className }: { className?: string }) {
  return (
    <a href="#top" className={`inline-flex items-center gap-2.5 ${className ?? ""}`} aria-label="Potret — home">
      <ApertureMark size={26} />
      <Wordmark />
    </a>
  );
}
