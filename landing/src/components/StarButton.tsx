import { useEffect, useState } from "react";
import { REPO } from "../lib/site";

const API = "https://api.github.com/repos/PradiptaPutra/potret";

// Below this the number hurts more than it helps. A "★ 1" next to a star
// button says nobody has; no number says nothing at all, which is better.
const SHOW_COUNT_FROM = 10;

function useStarCount() {
  const [count, setCount] = useState<number | null>(null);

  useEffect(() => {
    const controller = new AbortController();
    fetch(API, { signal: controller.signal, headers: { Accept: "application/vnd.github+json" } })
      .then((response) => (response.ok ? response.json() : null))
      .then((data) => {
        const n = data?.stargazers_count;
        if (typeof n === "number" && n >= SHOW_COUNT_FROM) setCount(n);
      })
      // Unauthenticated, rate-limited, and purely decorative: failure means no number.
      .catch(() => {});
    return () => controller.abort();
  }, []);

  return count;
}

function format(n: number) {
  return n >= 1000 ? `${(n / 1000).toFixed(n >= 10_000 ? 0 : 1)}k` : String(n);
}

function Star({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" className={className}>
      <path
        fill="currentColor"
        d="M8 .8l2.2 4.6 5 .7-3.6 3.5.9 5L8 12.2l-4.5 2.4.9-5L.8 6.1l5-.7L8 .8z"
      />
    </svg>
  );
}

/**
 * The one thing a free app can ask for. Links straight to the repo — the
 * star button itself is GitHub's, this just gets people to it.
 */
export default function StarButton({ size = "compact" }: { size?: "compact" | "large" }) {
  const count = useStarCount();

  if (size === "large") {
    return (
      <a href={REPO} className="btn btn-ghost" aria-label="Star Potret on GitHub">
        <Star className="text-spark" />
        Star on GitHub
        {count !== null && (
          <span className="ml-1 rounded-full bg-mist px-2 py-[1px] font-mono text-[12px] text-slate">
            {format(count)}
          </span>
        )}
      </a>
    );
  }

  return (
    <a
      href={REPO}
      className="hidden items-center gap-1.5 rounded-full px-3 py-1.5 text-[14px] font-medium text-slate transition-colors hover:bg-mist hover:text-ink sm:inline-flex"
      aria-label="Star Potret on GitHub"
    >
      <Star className="text-spark" />
      Star
      {count !== null && (
        <span className="rounded-full bg-mist px-1.5 font-mono text-[12px] text-graphite">
          {format(count)}
        </span>
      )}
    </a>
  );
}
