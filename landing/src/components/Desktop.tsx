import type { ReactNode } from "react";
import { Screen } from "./macos";

/**
 * A flat pane of desktop, for shots where the point is *where on screen* a
 * thing appears rather than the machine it appears on. Same chrome as the
 * MacBook, so the two never disagree about what macOS looks like.
 */
export default function Desktop({
  children,
  caption,
  className,
}: {
  children: ReactNode;
  caption?: string;
  className?: string;
}) {
  return (
    <figure className={`m-0 ${className ?? ""}`}>
      <div
        className="relative isolate overflow-hidden rounded-xl border border-fog"
        style={{ boxShadow: "var(--shadow-mockup)", aspectRatio: "16 / 10" }}
      >
        <Screen>{children}</Screen>
      </div>
      {caption ? (
        <figcaption className="mt-3 text-center text-[13px] text-graphite">
          {caption}
        </figcaption>
      ) : null}
    </figure>
  );
}
