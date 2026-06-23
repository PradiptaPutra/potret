import { useEffect, useState } from "react";
import { Logo } from "./Logo";

const LINKS = [
  { label: "Features", href: "#features" },
  { label: "How it works", href: "#how" },
  { label: "Download", href: "#download" },
];

const GITHUB = "https://github.com/PradiptaPutra/potret";

export default function Nav() {
  const [scrolled, setScrolled] = useState(false);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 16);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  return (
    <header
      className="fixed inset-x-0 top-0 z-50 transition-all duration-300"
      style={{
        backdropFilter: scrolled ? "blur(14px) saturate(140%)" : "none",
        WebkitBackdropFilter: scrolled ? "blur(14px) saturate(140%)" : "none",
        background: scrolled ? "rgba(11,10,12,0.66)" : "transparent",
        borderBottom: scrolled ? "1px solid var(--color-hair)" : "1px solid transparent",
      }}
    >
      <nav className="container-x flex h-16 items-center justify-between md:h-[72px]">
        <Logo />

        <div className="hidden items-center gap-1 md:flex">
          {LINKS.map((l) => (
            <a
              key={l.href}
              href={l.href}
              className="rounded-full px-3.5 py-2 text-[14px] text-mist transition-colors duration-200 hover:text-bone"
            >
              {l.label}
            </a>
          ))}
        </div>

        <div className="flex items-center gap-2.5">
          <a
            href={GITHUB}
            target="_blank"
            rel="noreferrer"
            className="hidden text-[14px] text-mist transition-colors duration-200 hover:text-bone sm:inline-flex"
          >
            GitHub
          </a>
          <a href="#download" className="btn btn-primary !px-4 !py-2 !text-[14px]">
            Download
          </a>
        </div>
      </nav>
    </header>
  );
}
