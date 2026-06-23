import { ApertureMark, Wordmark } from "../components/Logo";

const GITHUB_URL = "https://github.com/PradiptaPutra/potret";
const RELEASES_URL = "https://github.com/PradiptaPutra/potret/releases/latest";
const LICENSE_URL =
  "https://github.com/PradiptaPutra/potret/blob/main/LICENSE";
const COFFEE_URL = "https://tiptap.gg/dipta";

type Col = {
  title: string;
  links: { label: string; href: string; external?: boolean }[];
};

const COLUMNS: Col[] = [
  {
    title: "Product",
    links: [
      { label: "Features", href: "#features" },
      { label: "How it works", href: "#how" },
      { label: "Download", href: "#download" },
    ],
  },
  {
    title: "Project",
    links: [
      { label: "GitHub", href: GITHUB_URL, external: true },
      { label: "Releases", href: RELEASES_URL, external: true },
      { label: "License (MIT)", href: LICENSE_URL, external: true },
    ],
  },
  {
    title: "Support",
    links: [{ label: "Buy me a coffee", href: COFFEE_URL, external: true }],
  },
];

export default function Footer() {
  return (
    <footer className="relative border-t border-[color:var(--color-hair)] bg-ink-2">
      <div className="container-x py-16 md:py-20">
        <div className="grid gap-12 md:grid-cols-[1.4fr_repeat(3,1fr)]">
          {/* brand */}
          <div className="max-w-xs">
            <div className="flex items-center gap-2.5">
              <ApertureMark size={24} />
              <Wordmark />
            </div>
            <p className="mt-4 font-display text-[15px] italic leading-snug text-mist">
              Screenshots with a sense of style.
            </p>
          </div>

          {/* link columns */}
          {COLUMNS.map((col) => (
            <nav key={col.title} aria-label={col.title}>
              <h2 className="font-mono text-[11px] font-medium uppercase tracking-[0.2em] text-faint">
                {col.title}
              </h2>
              <ul className="mt-4 space-y-3">
                {col.links.map((link) => (
                  <li key={link.label}>
                    <a
                      href={link.href}
                      {...(link.external
                        ? { target: "_blank", rel: "noreferrer" }
                        : {})}
                      className="text-sm text-mist transition-colors hover:text-bone focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-amber"
                    >
                      {link.label}
                      {link.external && (
                        <span aria-hidden="true" className="text-faint">
                          {" "}
                          ↗
                        </span>
                      )}
                    </a>
                  </li>
                ))}
              </ul>
            </nav>
          ))}
        </div>

        <hr className="hairline my-10" />

        {/* bottom bar */}
        <div className="flex flex-col gap-4 text-[12.5px] text-faint md:flex-row md:items-center md:justify-between">
          <div className="flex flex-wrap items-center gap-x-3 gap-y-1.5">
            <span>© 2026 Potret · MIT</span>
            <span aria-hidden="true" className="text-[color:var(--color-hair-2)]">
              ·
            </span>
            <span className="font-mono text-mist">v0.2.4</span>
            <span aria-hidden="true" className="text-[color:var(--color-hair-2)]">
              ·
            </span>
            <span>Made with too much Claude Code 🤎</span>
          </div>
          <p className="font-mono text-mist">Tauri · React · Tailwind</p>
        </div>
      </div>
    </footer>
  );
}
