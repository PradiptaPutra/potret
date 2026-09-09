import type { ReactNode } from "react";

/**
 * A framed product screenshot.
 *
 * Deliberately no synthetic traffic lights: these are real captures of a real
 * macOS window and already carry their own chrome, so drawing a second title
 * bar around them gave every shot two sets of buttons. The frame here is a
 * hairline, a radius and a shadow — enough to lift the image off the page.
 *
 * `stage` fixes the height of the image area and centres the shot inside it.
 * Two shots of very different proportion — a wide panel beside a tall stack —
 * otherwise leave one column ending hundreds of pixels above the other, with
 * the gap reading as a mistake.
 */
export default function MacWindow({
  src,
  alt,
  title,
  stage,
  children,
  className,
}: {
  src?: string;
  alt?: string;
  title?: string;
  stage?: number;
  children?: ReactNode;
  className?: string;
}) {
  // The cap goes on the image, not on the box around it: capping the box and
  // letting the image keep its natural height just clips it against the box's
  // overflow, which is what cut the bottom off the taller shot.
  const image = src ? (
    <img
      src={src}
      alt={alt ?? ""}
      loading="lazy"
      className={stage ? "block w-auto" : undefined}
      style={stage ? { maxHeight: stage } : undefined}
    />
  ) : (
    children
  );

  return (
    <figure className={`m-0 ${className ?? ""}`}>
      {stage ? (
        <div className="flex items-center justify-center" style={{ height: stage }}>
          <div
            className="inline-flex overflow-hidden rounded-xl border border-fog bg-paper"
            style={{ boxShadow: "var(--shadow-mockup)" }}
          >
            {image}
          </div>
        </div>
      ) : (
        <div
          className="overflow-hidden rounded-xl border border-fog bg-paper"
          style={{ boxShadow: "var(--shadow-mockup)" }}
        >
          {image}
        </div>
      )}
      {title ? (
        <figcaption className="mt-3 text-center text-[13px] text-graphite">
          {title}
        </figcaption>
      ) : null}
    </figure>
  );
}
