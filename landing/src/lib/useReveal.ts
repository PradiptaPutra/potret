import { useEffect, useRef } from "react";

/**
 * Scroll-reveal hook. Attach the returned ref to a container; any descendant
 * with the `reveal` class (and the container itself if it has it) gets `is-in`
 * added when it scrolls into view. Stagger children with
 * `style={{ ["--reveal-delay" as string]: "120ms" }}`.
 *
 * Respects prefers-reduced-motion (CSS handles the no-op).
 */
export function useReveal<T extends HTMLElement = HTMLElement>() {
  const ref = useRef<T>(null);

  useEffect(() => {
    const root = ref.current;
    if (!root) return;

    const targets = new Set<Element>();
    if (root.classList.contains("reveal")) targets.add(root);
    root.querySelectorAll(".reveal").forEach((el) => targets.add(el));
    if (targets.size === 0) return;

    if (!("IntersectionObserver" in window)) {
      targets.forEach((el) => el.classList.add("is-in"));
      return;
    }

    const io = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-in");
            io.unobserve(entry.target);
          }
        }
      },
      { threshold: 0.12, rootMargin: "0px 0px -8% 0px" },
    );

    targets.forEach((el) => io.observe(el));
    return () => io.disconnect();
  }, []);

  return ref;
}
