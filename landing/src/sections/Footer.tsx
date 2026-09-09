import { ApertureMark } from "../components/Logo";
import { REPO, RELEASES, VERSION } from "../lib/site";

const COLUMNS = [
  {
    heading: "Product",
    links: [
      { label: "Capture", href: "#modes" },
      { label: "Record", href: "#modes" },
      { label: "Trim", href: "#modes" },
      { label: "Features", href: "#features" },
    ],
  },
  {
    heading: "Get it",
    links: [
      { label: "Download", href: "#download" },
      { label: "Releases", href: RELEASES },
      { label: "Homebrew tap", href: "https://github.com/PradiptaPutra/homebrew-tap" },
    ],
  },
  {
    heading: "Project",
    links: [
      { label: "Source", href: REPO },
      { label: "Report a bug", href: `${REPO}/issues` },
      { label: "Contributing", href: `${REPO}/blob/main/CONTRIBUTING.md` },
      { label: "Licence", href: `${REPO}/blob/main/LICENSE` },
    ],
  },
];

export default function Footer() {
  return (
    <footer className="border-t border-ash bg-paper py-14">
      <div className="shell">
        <div className="grid gap-10 sm:grid-cols-2 lg:grid-cols-[2fr_1fr_1fr_1fr]">
          <div>
            <div className="flex items-center gap-2">
              <ApertureMark size={22} />
              <span className="text-[17px] font-bold tracking-[-0.02em]">
                Potret
              </span>
            </div>
            <p className="mt-3 max-w-[34ch] text-[14px] leading-[1.6] text-graphite">
              A free, open-source screenshot and screen-recording tool for
              macOS. Built in the open, MIT licensed.
            </p>
          </div>

          {COLUMNS.map((column) => (
            <nav key={column.heading} aria-label={column.heading}>
              <h3 className="text-[15px] font-medium text-ink">
                {column.heading}
              </h3>
              <ul className="mt-3 space-y-2">
                {column.links.map((link) => (
                  <li key={link.label}>
                    <a
                      href={link.href}
                      className="text-[14px] text-graphite transition-colors hover:text-ink"
                    >
                      {link.label}
                    </a>
                  </li>
                ))}
              </ul>
            </nav>
          ))}
        </div>

        <div className="mt-12 flex flex-wrap items-center justify-between gap-3 border-t border-ash pt-6">
          <p className="text-[13px] text-graphite">
            © {new Date().getFullYear()} Potret · MIT
          </p>
          <p className="font-mono text-[12px] text-steel">v{VERSION}</p>
        </div>
      </div>
    </footer>
  );
}
