# Potret landing — build spec (READ FIRST)

You are building ONE section of a single, cohesive landing page for **Potret**, a
free, open-source **macOS screenshot & annotation tool** (a CleanShot X alternative,
without the price tag). The page must look intentionally designed — **never generic
"AI slop."** Inspiration: the live, animated, cinematic feel of unicorn.studio
(WebGL gradients, motion, depth) — but executed with restraint and taste.

## Non-negotiables
- **Dark, cinematic "optical instrument" aesthetic.** Amber aperture-glow on warm near-black.
- **One accent only: amber** (`#FF9F0A` / petal gradient). No purple, no blue, no rainbow. No stock-photo vibes.
- Use the **shared primitives** (below). Do NOT invent new colors, fonts, button styles, or container widths.
- Generous negative space, big editorial type, precise spacing. Quality over density.
- Respect `prefers-reduced-motion` (the global CSS already neutralizes `.reveal` + transitions).
- Mobile-first responsive. Looks great at 375px and 1440px.
- Accessible: real semantic tags, alt text, focus-visible, sufficient contrast, `aria-hidden` on decoration.

## Tech
- Vite + React 19 + TypeScript + **Tailwind v4** (utilities available) + **Motion** (`import { motion } from "motion/react"`).
- Tokens live in `src/styles/global.css` as Tailwind `@theme` vars → available as utilities.

## Design tokens (already defined — USE THESE)
Colors (as Tailwind utilities `bg-*` / `text-*` / `border-*`):
- `ink` `#0b0a0c` (page base) · `ink-2` `#0f0e11` · `surface` `#141317` · `surface-2` `#1b1a1f`
- `bone` `#f6f1e9` (primary text) · `mist` `#a8a299` (secondary) · `faint` `#6c665e` (captions)
- `amber` `#ff9f0a` · `amber-hot` `#ff7a1a` · `ember` `#f25c05` · `glow` `#ffd08a`
- borders: `hair` (rgba bone .08), `hair-2` (.14)

CSS vars (use via `style`/CSS): `--grad-petal`, `--grad-amber-text`, `--glow-amber`,
`--shadow-card`, `--radius-lg` (22px), `--radius-md` (14px), `--ease-out-expo`, `--ease-spring`.

Fonts (utilities `font-display` / `font-sans` / `font-mono`):
- **Fraunces** (`font-display`) — editorial serif, for big headlines. Optical sizing on. Use light italic for accent words.
- **Hanken Grotesk** (`font-sans`) — body/UI (default on body).
- **JetBrains Mono** (`font-mono`) — kickers, keyboard shortcuts (⌘1), code/commands, tiny labels.

## Shared primitives (CSS classes — prefer these over re-rolling)
- `.container-x` — page width (max 1180px) + responsive horizontal padding. Wrap section content in it.
- `.kicker` — mono uppercase amber eyebrow above headings.
- `.display` — Fraunces heading base (set size with Tailwind text-* on top).
- `.text-amber-grad` — amber gradient text for ONE emphasized phrase per section, max.
- `.surface` — card (bg + hairline border + soft shadow + radius-lg).
- `.btn` + `.btn-primary` (amber, filled) / `.btn-ghost` (outline). Buttons are pill-shaped.
- `.hairline` — 1px divider.
- `.reveal` — start hidden; gets `.is-in` when scrolled into view. Drive it with the hook:

```tsx
import { useReveal } from "../lib/useReveal";
const ref = useReveal<HTMLDivElement>();
// <div ref={ref}> ... children with className="reveal" ... </div>
// stagger: style={{ ["--reveal-delay" as any]: "120ms" }}
```

(Motion is also fine for richer in-view animation; keep it subtle and amber-tinted.)

## Section vertical rhythm
Each section: `className="relative py-24 md:py-36"` (≈96/144px). Hero is full-height (min-h-screen).

## Component contract (STRICT — so everything composes)
- Each file = **one default-export React component, no props**: `export default function Hero() { ... }`.
- Return a single top-level `<section id="...">` (Footer returns `<footer>`).
- Anchor IDs (for nav): Hero → none needed (page top), Features → `id="features"`,
  Workflow → `id="how"`, Download → `id="download"`, Support → `id="support"`.
- Import shared helpers by relative path (`../lib/useReveal`, `../components/Logo`).
- Do NOT edit `App.tsx`, `global.css`, `Nav.tsx`, `Logo.tsx`, `useReveal.ts`, `index.html`,
  `main.tsx`, or any file outside your assigned list. Main thread integrates.

## Brand facts (use real values — do not invent)
- Name: **Potret**. macOS menu-bar app. Free + open-source. MIT. Current version **v0.2.4**.
- GitHub: `https://github.com/PradiptaPutra/potret`
- Latest release: `https://github.com/PradiptaPutra/potret/releases/latest`
- Homebrew install: `brew install --cask --no-quarantine PradiptaPutra/tap/potret`
- Support / donate: `https://tiptap.gg/dipta`
- Universal build: Apple Silicon **and** Intel. Lives in the **menu bar**, not the Dock.
- Built with: Tauri 2 (Rust), React 19, Tailwind v4, native macOS `screencapture`.
- Assets in `public/`: `app-icon.png` (the amber aperture icon), `home.png` (real app screenshot).

### The 8 feature groups (source of truth for copy)
1. **Capture** — area (drag to select), window (click any window), or fullscreen.
2. **Quick Access popup** — after a capture, a floating panel: copy, save, annotate, pin, or
   drag the shot straight into another app. Follows you across Spaces/desktops.
3. **Annotation** — pen, line, arrow, rectangle, ellipse, text, highlighter, pixelate/blur,
   numbered steps, crop, eraser — with undo/redo and a custom color picker.
4. **Background tool** — drop a screenshot onto gradient or custom backgrounds with padding,
   rounded corners, and shadow. Great for social posts.
5. **Pin to screen** — keep a floating screenshot on top while you work.
6. **History** — recent captures with copy / edit / pin / delete, plus a Recent Captures
   menu-bar popup (⌘⇧H).
7. **Output options** — PNG or JPG, adjustable quality, filename templates.
8. **System** — customizable global shortcuts, menu-bar only, launch at login, fluid
   animations (respects Reduce Motion).

## Voice (approved tone)
Confident, clean, a little playful and self-aware — never corny, never salesy. Short sentences.
Lowercase-friendly captions are OK. The product is genuinely nice; let it breathe. One or two
witty lines max per section. The signature joke (use ONLY in the Support section): the whole app
was "vibe-coded by an AI that bills its developer by the token," so coffees keep the prompts flowing.

### Approved copy you MAY use (don't pad with filler)
- Kicker examples: `FREE · OPEN-SOURCE · macOS`, `LIVES IN YOUR MENU BAR`, `CAPTURE → MARK UP → SHIP`.
- Hero H1 (Agent A, keep it): **Screenshots with a sense of style.**
- Hero sub: *Potret lives in your menu bar. Snap an area, a window, or the whole screen — then
  copy, annotate, pin, or drop it onto a gorgeous background. No heavy editor. No subscription.*
- Hero CTAs: primary **Install with Homebrew** (also show the brew command in mono, copy-to-clipboard),
  secondary **Download .dmg** → releases/latest, tertiary text-link **View source ↗** → GitHub.
- Download section: lead with Homebrew (recommended, cleanest), then `.dmg` (universal), then a one-line
  honest note about the first-launch Gatekeeper step (open-source, not Apple-notarized) — keep it light.
- Support: the coffee joke + button **☕ Buy me a coffee →** to tiptap.gg/dipta. Make clear it's free forever either way.

---

## Agent assignments (build ONLY your files)

### Agent A — Hero + signature WebGL
Files: `src/components/ApertureShader.tsx`, `src/sections/Hero.tsx`
- `ApertureShader`: a full-bleed **WebGL fragment-shader** canvas (raw WebGL, NO heavy deps) that
  fills the Hero background. Flowing amber-on-near-black field — think a slow aperture/iris glow,
  soft fluid gradient + animated film noise, gently **reactive to the mouse** (parallax/warp).
  Cap devicePixelRatio at 2, `requestAnimationFrame`, pause when tab hidden / element offscreen,
  clean up on unmount. **Respect `prefers-reduced-motion`**: render a single static gradient frame.
  Provide a graceful fallback (CSS radial-gradient div) if WebGL context fails. Keep GPU cost modest.
- `Hero`: min-h-screen `<section>`. Shader behind; content in front via `.container-x`. Kicker,
  big Fraunces H1 (the approved line, with one accent word in `.text-amber-grad` or light italic),
  sub, the 3 CTAs, and the brew command in a mono "chip" with a copy button (use
  `navigator.clipboard`, show a ✓ for ~1.5s). Tasteful staggered load-in animation. Below the fold,
  a floating, perspective-tilted mock of the app using `public/home.png` inside a faux macOS window
  chrome (traffic-light dots), with an amber glow — this is the hero showpiece. Subtle scroll cue.

### Agent B — Product showcase (bento + workflow)
Files: `src/sections/Features.tsx`, `src/sections/Workflow.tsx`
- `Features` (`id="features"`): a **bento grid** (asymmetric, varied cell sizes, NOT a uniform
  3×3 of identical cards) covering the 8 feature groups. Each cell = `.surface` with a crafted icon
  (lucide is NOT installed — draw small inline SVG glyphs in amber, or styled mono labels),
  a short title + one-line description from the source of truth. One or two larger "feature spotlight"
  cells (e.g. Annotation, Background tool) may include a small visual/diagram. Hover = subtle lift +
  amber hairline. Reveal on scroll, staggered.
- `Workflow` (`id="how"`): a 3-step narrative — **Capture → Mark up → Ship** — shown as a horizontal
  (stacked on mobile) sequence with numbered mono badges (01/02/03), short copy, and a connecting
  amber line/flow. Convey the "snap → quick-access → drop on background" story. Keep it cinematic.

### Agent C — Download + Support + Footer
Files: `src/sections/Download.tsx`, `src/sections/Support.tsx`, `src/sections/Footer.tsx`
- `Download` (`id="download"`): two clear paths in `.surface` cards — **Homebrew** (recommended;
  show the brew command in a mono block with copy button) and **Direct .dmg** (button →
  releases/latest, note "universal — Apple Silicon & Intel"). A compact, friendly first-launch note
  (not notarized → one-time Gatekeeper step; link the README for detail). Mention "lives in your menu bar."
- `Support` (`id="support"`): the coffee joke (vibe-coded by a token-billing AI), button
  **☕ Buy me a coffee** → tiptap.gg/dipta, reassure it's free forever. Warm, funny, brief.
- `Footer`: import `{ ApertureMark, Wordmark }` from `../components/Logo`. Columns/links: GitHub,
  Releases, License (MIT), Support. Tagline, `v0.2.4`, "Made with too much Claude Code." Small print.
  Built-with line (Tauri · React · Tailwind). Keep it elegant, not heavy.

### Agent D — Atmosphere + infra
Files: `src/components/Grain.tsx`, `public/favicon.svg`, `vercel.json`, `SEO_HEAD.html` (snippet for main thread), `public/robots.txt`
- `Grain` (default export): a **fixed, full-viewport, pointer-events-none** overlay that sits above
  the page (`z-40`) adding tasteful film grain/noise + a very subtle vignette for cinematic depth.
  Pure CSS/SVG noise (e.g. an inline SVG `feTurbulence` data-URI) at low opacity (~3–6%). Must not
  hurt readability or block clicks. Honor `prefers-reduced-motion` (no animation; static grain fine).
- `public/favicon.svg`: the amber 8-petal aperture mark on transparent/ink (match `Logo.tsx`).
- `vercel.json`: static SPA config for a Vite build — framework "vite", proper rewrites so it serves
  index.html, sensible cache headers for assets. (Root dir will be `landing/`.)
- `public/robots.txt`: allow all + (placeholder) sitemap line.
- `SEO_HEAD.html`: a block of `<meta>` tags (Open Graph + Twitter card + canonical + description)
  for Potret that the MAIN THREAD will merge into `index.html`. Title:
  "Potret — Screenshots with a sense of style". Use og:image `/og.png` (main thread will supply it).

## If a "Fact-Forcing Gate" blocks a Write
A local hook may block your FIRST file write asking for facts. Respond by retrying the SAME write
immediately; if it asks again, state one line ("file X is a Potret landing section imported by App.tsx;
no data files; building the landing page") and retry. It passes on retry. Do not get stuck.
