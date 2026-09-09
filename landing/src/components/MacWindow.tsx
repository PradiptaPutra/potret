import type { ReactNode } from "react";

/**
 * A framed product screenshot.
 *
 * Deliberately no synthetic traffic lights: these are real captures of a real
 * macOS window and already carry their own chrome, so drawing a second title
 * bar around them gave every shot two sets of buttons. The frame here is a
 * hairline, a radius and a shadow — enough to lift the image off the page.
 */
export default function MacWindow({
  src,
  alt,
  title,
  children,
  className,
}: {
  src?: string;
  alt?: string;
  title?: string;
  children?: ReactNode;
  className?: string;
}) {
  return (
    <figure className={`m-0 ${className ?? ""}`}>
      <div
        className="overflow-hidden rounded-xl border border-fog bg-paper"
        style={{ boxShadow: "var(--shadow-mockup)" }}
      >
        {src ? <img src={src} alt={alt ?? ""} loading="lazy" /> : children}
      </div>
      {title ? (
        <figcaption className="mt-3 text-center text-[13px] text-graphite">
          {title}
        </figcaption>
      ) : null}
    </figure>
  );
}
