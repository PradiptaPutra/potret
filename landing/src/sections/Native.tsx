const POINTS = [
  {
    stat: "3.1 MB",
    label: "the whole app",
    body: "Swift and AppKit, no bundled browser. The previous build was roughly fifteen megabytes of web runtime.",
  },
  {
    stat: "0",
    label: "accounts, trackers, uploads",
    body: "Captures live in a folder on your Mac. Nothing is sent anywhere, because there is nowhere to send it.",
  },
  {
    stat: "126",
    label: "tests, and a public CI",
    body: "Every push builds a universal binary and runs the suite. The code is MIT-licensed and open to read.",
  },
];

/**
 * The rewrite is the reason half of this release exists, so it gets said
 * plainly — in numbers rather than adjectives.
 */
export default function Native() {
  return (
    <section className="py-20">
      <div className="shell">
        <div className="reveal mx-auto max-w-[56ch] text-center">
          <p className="eyebrow">Native, and small</p>
          <h2 className="heading mt-3">
            Rewritten in Swift, because a web view could not do this.
          </h2>
          <p className="mt-4 text-[16px] text-slate">
            Seven releases in a row went to one bug: a browser window pretending
            to be a Mac window. Overlays now sit where you left them, captures
            never steal focus, and screen recording became possible at all.
          </p>
        </div>

        <div className="mt-12 grid gap-4 sm:grid-cols-3">
          {POINTS.map((point, index) => (
            <div
              key={point.label}
              className="card reveal"
              style={{ transitionDelay: `${index * 70}ms` }}
            >
              <p className="text-[36px] font-bold leading-none tracking-[-0.02em] text-ink">
                {point.stat}
              </p>
              <p className="mt-2 text-[13px] font-medium uppercase tracking-[0.14em] text-graphite">
                {point.label}
              </p>
              <p className="mt-3 text-[14px] leading-[1.6] text-slate">
                {point.body}
              </p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
