import type { ReactNode } from "react";
import { ApertureMark } from "./Logo";

/**
 * Fabricated macOS chrome — wallpaper, menu bar, dock — shared by the MacBook
 * and by the flat desktop frames.
 *
 * Drawn, never photographed: a real desktop screenshot carries whatever
 * happened to be on screen, which is the thing these images exist to avoid.
 * Everything sizes in container-query units so the same component reads
 * correctly at 300px and at 900px.
 */
export function Screen({ children }: { children: ReactNode }) {
  return (
    <div className="absolute inset-0" style={{ containerType: "inline-size" }}>
      <Wallpaper />
      <MenuBar />
      <div className="absolute inset-0 z-20">{children}</div>
      <Dock />
    </div>
  );
}

/**
 * After Sequoia's "Helios": warm tones folding through cool ones. The single
 * soft ray is what stops four coloured radial gradients reading as four
 * coloured circles.
 */
export function Wallpaper() {
  return (
    <div className="absolute inset-0 z-0" style={{ background: "#0a0d18" }}>
      <div
        className="absolute inset-0"
        style={{
          background: [
            "radial-gradient(70% 55% at 78% 12%, rgba(255,176,84,.55) 0%, transparent 62%)",
            "radial-gradient(65% 55% at 58% 30%, rgba(236,92,140,.48) 0%, transparent 65%)",
            "radial-gradient(85% 70% at 22% 62%, rgba(96,86,224,.62) 0%, transparent 68%)",
            "radial-gradient(70% 60% at 88% 86%, rgba(46,160,214,.42) 0%, transparent 66%)",
            "linear-gradient(155deg,#121736 0%,#0d1024 55%,#080a16 100%)",
          ].join(","),
        }}
      />
      <div
        className="absolute inset-0"
        style={{
          background:
            "linear-gradient(102deg, transparent 38%, rgba(255,214,170,.16) 48%, transparent 58%)",
        }}
      />
    </div>
  );
}

/**
 * The right-hand end follows the real order: menu extras first, then the
 * system items, with Control Centre, Siri and the clock pinned to the corner
 * because macOS will not let you move those three.
 */
export function MenuBar() {
  return (
    <div
      className="absolute inset-x-0 top-0 z-30 flex items-center backdrop-blur-md"
      style={{
        height: "4.2%",
        background: "rgba(16,16,20,.34)",
        fontSize: "1.35cqw",
        paddingInline: "1.4cqw",
        gap: "1.6cqw",
      }}
    >
      <AppleGlyph />
      <span className="font-semibold text-white/95">Finder</span>
      <span className="text-white/80">File</span>
      <span className="text-white/80">Edit</span>
      <span className="text-white/80">View</span>
      <span className="text-white/80">Go</span>

      <span className="flex-1" />

      {/* A third-party menu extra sits left of the system items — which is
          exactly where Potret puts itself. */}
      <ApertureMark size={9} />
      <Battery />
      <WiFi />
      <ControlCentre />
      <Spotlight />
      <span className="tabular-nums text-white/95">Tue 9:41</span>
    </div>
  );
}

function AppleGlyph() {
  return (
    <svg viewBox="0 0 24 24" fill="rgba(255,255,255,.95)" style={{ width: "1.05em", height: "1.05em" }} aria-hidden="true">
      <path d="M16.36 12.78c-.02-2.3 1.88-3.4 1.96-3.46-1.07-1.56-2.73-1.78-3.32-1.8-1.41-.14-2.76.83-3.48.83-.72 0-1.83-.81-3.01-.79-1.55.02-2.98.9-3.78 2.28-1.61 2.79-.41 6.92 1.15 9.18.76 1.11 1.67 2.35 2.86 2.31 1.15-.05 1.58-.74 2.97-.74 1.38 0 1.78.74 2.99.72 1.24-.02 2.02-1.13 2.78-2.24.87-1.28 1.23-2.52 1.25-2.59-.03-.01-2.4-.92-2.42-3.66zM14.1 5.66c.63-.77 1.06-1.83.94-2.9-.91.04-2.01.61-2.66 1.37-.58.68-1.09 1.76-.95 2.8 1.01.08 2.04-.51 2.67-1.27z" />
    </svg>
  );
}

const ink = "rgba(255,255,255,.92)";

function Battery() {
  return (
    <svg viewBox="0 0 26 12" style={{ width: "1.85em", height: "1em" }} aria-hidden="true">
      <rect x="0.6" y="0.6" width="21" height="10.8" rx="3.2" fill="none" stroke={ink} strokeWidth="1.1" opacity=".65" />
      <rect x="2.1" y="2.1" width="15" height="7.8" rx="2" fill={ink} />
      <path d="M23.2 4.2v3.6a2.2 2.2 0 0 0 0-3.6Z" fill={ink} opacity=".65" />
    </svg>
  );
}

function WiFi() {
  return (
    <svg viewBox="0 0 16 12" style={{ width: "1.15em", height: "1em" }} aria-hidden="true">
      <path d="M1 4.2a10 10 0 0 1 14 0" fill="none" stroke={ink} strokeWidth="1.5" strokeLinecap="round" />
      <path d="M3.6 6.9a6.3 6.3 0 0 1 8.8 0" fill="none" stroke={ink} strokeWidth="1.5" strokeLinecap="round" />
      <circle cx="8" cy="9.8" r="1.2" fill={ink} />
    </svg>
  );
}

function ControlCentre() {
  return (
    <svg viewBox="0 0 16 12" style={{ width: "1.05em", height: "1em" }} aria-hidden="true">
      <rect x="0.7" y="0.7" width="14.6" height="4.2" rx="2.1" fill="none" stroke={ink} strokeWidth="1.1" />
      <circle cx="11.2" cy="2.8" r="1.3" fill={ink} />
      <rect x="0.7" y="7.1" width="14.6" height="4.2" rx="2.1" fill="none" stroke={ink} strokeWidth="1.1" />
      <circle cx="4.8" cy="9.2" r="1.3" fill={ink} />
    </svg>
  );
}

function Spotlight() {
  return (
    <svg viewBox="0 0 14 14" fill="none" stroke={ink} strokeWidth="1.4" strokeLinecap="round" style={{ width: "1em", height: "1em" }} aria-hidden="true">
      <circle cx="6" cy="6" r="4.2" />
      <path d="m9.3 9.3 3.1 3.1" />
    </svg>
  );
}

/** Squircle tiles carrying the apps a capture actually gets dropped into,
 *  running dots, and Trash past the divider — the three cues that make a row
 *  of coloured squares read as a Dock.
 *
 *  The marks are drawn from scratch at this size rather than imported as
 *  brand assets: a dock icon here is ~30px wide, where a faithful logo turns
 *  to mush and a simplified one still reads instantly. */
/**
 * Official mark geometry, from the Simple Icons set (CC0), drawn on a 24-unit
 * grid. The marks themselves remain the trademarks of their owners and appear
 * here only to populate a Dock, the way any screenshot of a Mac would.
 *
 * ChatGPT and Grok are deliberately absent from that set — Simple Icons drops
 * a mark when its owner asks — so those two stay as drawn approximations
 * rather than assets sourced from somewhere that has no right to hand them out.
 */
const MARK = {
  claude:
    "m4.7144 15.9555 4.7174-2.6471.079-.2307-.079-.1275h-.2307l-.7893-.0486-2.6956-.0729-2.3375-.0971-2.2646-.1214-.5707-.1215-.5343-.7042.0546-.3522.4797-.3218.686.0608 1.5179.1032 2.2767.1578 1.6514.0972 2.4468.255h.3886l.0546-.1579-.1336-.0971-.1032-.0972L6.973 9.8356l-2.55-1.6879-1.3356-.9714-.7225-.4918-.3643-.4614-.1578-1.0078.6557-.7225.8803.0607.2246.0607.8925.686 1.9064 1.4754 2.4893 1.8336.3643.3035.1457-.1032.0182-.0728-.164-.2733-1.3539-2.4467-1.445-2.4893-.6435-1.032-.17-.6194c-.0607-.255-.1032-.4674-.1032-.7285L6.287.1335 6.6997 0l.9957.1336.419.3642.6192 1.4147 1.0018 2.2282 1.5543 3.0296.4553.8985.2429.8318.091.255h.1579v-.1457l.1275-1.706.2368-2.0947.2307-2.6957.0789-.7589.3764-.9107.7468-.4918.5828.2793.4797.686-.0668.4433-.2853 1.8517-.5586 2.9021-.3643 1.9429h.2125l.2429-.2429.9835-1.3053 1.6514-2.0643.7286-.8196.85-.9046.5464-.4311h1.0321l.759 1.1293-.34 1.1657-1.0625 1.3478-.8804 1.1414-1.2628 1.7-.7893 1.36.0729.1093.1882-.0183 2.8535-.607 1.5421-.2794 1.8396-.3157.8318.3886.091.3946-.3278.8075-1.967.4857-2.3072.4614-3.4364.8136-.0425.0304.0486.0607 1.5482.1457.6618.0364h1.621l3.0175.2247.7892.522.4736.6376-.079.4857-1.2142.6193-1.6393-.3886-3.825-.9107-1.3113-.3279h-.1822v.1093l1.0929 1.0686 2.0035 1.8092 2.5075 2.3314.1275.5768-.3218.4554-.34-.0486-2.2039-1.6575-.85-.7468-1.9246-1.621h-.1275v.17l.4432.6496 2.3436 3.5214.1214 1.0807-.17.3521-.6071.2125-.6679-.1214-1.3721-1.9246L14.38 17.959l-1.1414-1.9428-.1397.079-.674 7.2552-.3156.3703-.7286.2793-.6071-.4614-.3218-.7468.3218-1.4753.3886-1.9246.3157-1.53.2853-1.9004.17-.6314-.0121-.0425-.1397.0182-1.4328 1.9672-2.1796 2.9446-1.7243 1.8456-.4128.164-.7164-.3704.0667-.6618.4008-.5889 2.386-3.0357 1.4389-1.882.929-1.0868-.0062-.1579h-.0546l-6.3385 4.1164-1.1293.1457-.4857-.4554.0608-.7467.2307-.2429 1.9064-1.3114Z",
  notion:
    "M4.459 4.208c.746.606 1.026.56 2.428.466l13.215-.793c.28 0 .047-.28-.046-.326L17.86 1.968c-.42-.326-.981-.7-2.055-.607L3.01 2.295c-.466.046-.56.28-.374.466zm.793 3.08v13.904c0 .747.373 1.027 1.214.98l14.523-.84c.841-.046.935-.56.935-1.167V6.354c0-.606-.233-.933-.748-.887l-15.177.887c-.56.047-.747.327-.747.933zm14.337.745c.093.42 0 .84-.42.888l-.7.14v10.264c-.608.327-1.168.514-1.635.514-.748 0-.935-.234-1.495-.933l-4.577-7.186v6.952L12.21 19s0 .84-1.168.84l-3.222.186c-.093-.186 0-.653.327-.746l.84-.233V9.854L7.822 9.76c-.094-.42.14-1.026.793-1.073l3.456-.233 4.764 7.279v-6.44l-1.215-.139c-.093-.514.28-.887.747-.933zM1.936 1.035l13.31-.98c1.634-.14 2.055-.047 3.082.7l4.249 2.986c.7.513.934.653.934 1.213v16.378c0 1.026-.373 1.634-1.68 1.726l-15.458.934c-.98.047-1.448-.093-1.962-.747l-3.129-4.06c-.56-.747-.793-1.306-.793-1.96V2.667c0-.839.374-1.54 1.447-1.632z",
} as const;

type DockApp = {
  name: string;
  background: string;
  art: ReactNode;
  /** Chrome's disc is the whole icon; most marks sit inset like real artwork. */
  inset?: string;
  /** Official marks come on a 24 grid; the drawn ones are on 16. */
  viewBox?: string;
  running?: boolean;
};

const CLAUDE = "#d97757";
const NOTION_INK = "#191918";

const DOCK: DockApp[] = [
  {
    name: "Claude",
    background: `linear-gradient(160deg,#e08b6c,${CLAUDE})`,
    running: true,
    viewBox: "0 0 24 24",
    art: <path d={MARK.claude} fill="#faf7f2" />,
  },
  {
    name: "ChatGPT",
    background: "linear-gradient(160deg,#2b2b2b,#0b0b0b)",
    running: true,
    art: (
      <g fill="none" stroke="#ffffff" strokeWidth="1.3" strokeLinejoin="round" strokeLinecap="round">
        <path d="M8 2.4 12.9 5.2v5.6L8 13.6 3.1 10.8V5.2Z" />
        <path d="M8 2.4V8l4.9 2.8M8 8 3.1 5.2" />
      </g>
    ),
  },
  {
    name: "Grok",
    background: "linear-gradient(160deg,#242424,#000000)",
    art: (
      <g fill="#ffffff">
        <path d="M4.1 12.6 10.4 4.2h1.8L5.9 12.6Z" />
        <path d="M8.6 12.6 11.1 9.2h1.8l-2.5 3.4Z" />
      </g>
    ),
  },
  {
    name: "Chrome",
    background: "linear-gradient(160deg,#ffffff,#e6e9ec)",
    inset: "6%",
    running: true,
    art: (
      <g>
        <path d="M8 8 2.8 5A6 6 0 0 1 13.2 5Z" fill="#ea4335" />
        <path d="M8 8 13.2 5A6 6 0 0 1 8 14Z" fill="#fbbc05" />
        <path d="M8 8v6A6 6 0 0 1 2.8 5Z" fill="#34a853" />
        <circle cx="8" cy="8" r="3.3" fill="#ffffff" />
        <circle cx="8" cy="8" r="2.5" fill="#4285f4" />
      </g>
    ),
  },
  {
    name: "Notion",
    background: "linear-gradient(160deg,#ffffff,#eceae5)",
    viewBox: "0 0 24 24",
    art: <path d={MARK.notion} fill={NOTION_INK} />,
  },
];

export function Dock() {
  return (
    <div className="pointer-events-none absolute inset-x-0 bottom-[1.4%] z-30 flex justify-center">
      <div
        className="flex items-end backdrop-blur-md"
        style={{
          gap: "0.75cqw",
          borderRadius: "1.35cqw",
          paddingInline: "0.85cqw",
          paddingBlock: "0.65cqw",
          background: "rgba(255,255,255,.17)",
          border: "1px solid rgba(255,255,255,.16)",
          boxShadow: "inset 0 1px 0 rgba(255,255,255,.22), 0 0.6cqw 1.4cqw rgba(0,0,0,.28)",
        }}
      >
        {DOCK.map((app) => (
          <Tile key={app.name} {...app} />
        ))}
        <span
          style={{
            width: "1px",
            height: "2.9cqw",
            margin: "0 0.25cqw",
            background: "rgba(255,255,255,.28)",
          }}
        />
        <Tile
          name="Trash"
          background="linear-gradient(160deg,#cfd6de,#8a939d)"
          art={
            <g fill="none" stroke="rgba(255,255,255,.9)" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
              <path d="M5 6h6l-.6 6H5.6zM6.4 6V4.8h3.2V6" />
            </g>
          }
        />
      </div>
    </div>
  );
}

function Tile({ background, art, inset = "22%", running = false, viewBox = "0 0 16 16" }: DockApp) {
  return (
    <span className="relative block" style={{ width: "2.9cqw" }}>
      <span
        className="block"
        style={{
          width: "2.9cqw",
          height: "2.9cqw",
          background,
          /* macOS icons are squircles, not rounded squares. */
          borderRadius: "23%",
          boxShadow: "0 1px 3px rgba(0,0,0,.35), inset 0 1px 0 rgba(255,255,255,.3)",
        }}
      >
        {/* Inset, the way a real icon's artwork sits inside its tile rather
            than running to the edge. */}
        <svg viewBox={viewBox} style={{ width: "100%", height: "100%", padding: inset }} aria-hidden="true">
          {art}
        </svg>
      </span>
      {running ? (
        <span
          className="absolute left-1/2 -translate-x-1/2"
          style={{
            bottom: "-0.55cqw",
            width: "0.32cqw",
            height: "0.32cqw",
            minWidth: "2px",
            minHeight: "2px",
            borderRadius: "9999px",
            background: "rgba(255,255,255,.8)",
          }}
        />
      ) : null}
    </span>
  );
}
