import { DMG } from "../lib/site";
import { Logo } from "./Logo";
import StarButton from "./StarButton";

// Only sections that exist at every moment. The mode panel swaps its content
// in place, so #record and #trim are not addressable — linking to them from
// here would have been a dead anchor two thirds of the time.
const LINKS = [
  { href: "#modes", label: "How it works" },
  { href: "#features", label: "Features" },
  { href: "#changelog", label: "Changelog" },
  { href: "#download", label: "Download" },
];

/**
 * A floating pill, centred at the top with margin from the viewport edge —
 * the signature silhouette of this design system.
 */
export default function Nav() {
  return (
    <header className="pointer-events-none fixed inset-x-0 top-0 z-50 flex justify-center px-5 pt-4">
      <nav
        className="pointer-events-auto flex items-center gap-1 rounded-full border border-ash bg-paper/90 px-3 py-2 backdrop-blur-xl"
        style={{ boxShadow: "var(--shadow-nav)" }}
        aria-label="Primary"
      >
        <Logo className="mr-2 pl-1" />

        <ul className="hidden items-center gap-1 md:flex">
          {LINKS.map((link) => (
            <li key={link.href}>
              <a
                href={link.href}
                className="rounded-full px-3 py-1.5 text-[14px] font-medium text-slate transition-colors hover:bg-mist hover:text-ink"
              >
                {link.label}
              </a>
            </li>
          ))}
        </ul>

        <span className="mx-1 hidden h-5 w-px bg-fog sm:block" aria-hidden="true" />

        <StarButton size="compact" />
        <a href={DMG} className="btn btn-primary ml-1 !px-4 !py-1.5 !text-[14px]">
          Download
        </a>
      </nav>
    </header>
  );
}
