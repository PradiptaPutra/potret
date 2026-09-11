/**
 * Everything about the current release in one place, so a version bump is one
 * edit rather than a search across sections.
 */
export const VERSION = "0.4.2";
export const REPO = "https://github.com/PradiptaPutra/potret";
export const DMG = `${REPO}/releases/download/v${VERSION}/Potret_${VERSION}_universal.dmg`;
export const RELEASES = `${REPO}/releases/latest`;
export const BREW = "brew install --cask PradiptaPutra/tap/potret";

/** The person behind it. */
export const X_HANDLE = "@bydipta";
export const X_URL = "https://x.com/bydipta";

/** What the app costs you to install, stated plainly. */
export const SPECS = [
  { label: "Download", value: "3.1 MB" },
  { label: "Chips", value: "Apple Silicon + Intel" },
  { label: "Requires", value: "macOS 14+" },
  { label: "Licence", value: "MIT" },
];
