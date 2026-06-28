import {
  AbsoluteFill,
  Img,
  Sequence,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
  interpolate,
  Easing,
} from "remotion";
import "./style.css";

const palette = {
  ink: "#0b0a0c",
  ink2: "#0f0e11",
  surface: "#141317",
  surface2: "#1b1a1f",
  bone: "#f6f1e9",
  mist: "#a8a299",
  faint: "#6c665e",
  hair: "rgba(246,241,233,0.10)",
  hair2: "rgba(246,241,233,0.16)",
  amber: "#ff9f0a",
  hot: "#ff7a1a",
  ember: "#f25c05",
  glow: "#ffd08a",
};

function clamp01(value: number) {
  return Math.max(0, Math.min(1, value));
}

function easedProgress(frame: number, start: number, duration: number) {
  return clamp01(
    interpolate(frame, [start, start + duration], [0, 1], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
      easing: Easing.bezier(0.16, 1, 0.3, 1),
    }),
  );
}

function fade(frame: number, start: number, duration = 24) {
  return easedProgress(frame, start, duration);
}

function AccentText({ children }: { children: React.ReactNode }) {
  return <span className="textGradient">{children}</span>;
}

function ApertureMark({ size = 96, rotate = 0 }: { size?: number; rotate?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 1024 1024" style={{ transform: `rotate(${rotate}deg)` }}>
      <defs>
        <linearGradient id="promoBladeA" x1="0" y1="1" x2="0" y2="0">
          <stop offset="0%" stopColor="#b36200" />
          <stop offset="45%" stopColor="#ff9f0a" />
          <stop offset="100%" stopColor="#ffcb60" />
        </linearGradient>
        <linearGradient id="promoBladeB" x1="0" y1="1" x2="0" y2="0">
          <stop offset="0%" stopColor="#6b3a00" />
          <stop offset="45%" stopColor="#cc7500" />
          <stop offset="100%" stopColor="#e8a030" />
        </linearGradient>
      </defs>
      <rect width="1024" height="1024" rx="224" fill="#111014" />
      <g transform="translate(512,512)">
        {[60, 180, 300].map((deg) => (
          <path
            key={deg}
            d="M 0,-52 C 72,-108 80,-236 0,-310 C -80,-236 -72,-108 0,-52 Z"
            fill="url(#promoBladeB)"
            transform={`rotate(${deg})`}
          />
        ))}
        {[0, 120, 240].map((deg) => (
          <path
            key={deg}
            d="M 0,-52 C 72,-108 80,-236 0,-310 C -80,-236 -72,-108 0,-52 Z"
            fill="url(#promoBladeA)"
            transform={`rotate(${deg})`}
          />
        ))}
      </g>
      <circle cx="512" cy="512" r="78" fill="#050505" stroke="#ff9f0a" strokeWidth="5" strokeOpacity="0.55" />
    </svg>
  );
}

function Background() {
  const frame = useCurrentFrame();
  const spin = frame * 0.045;

  return (
    <AbsoluteFill className="bg">
      <div className="grain" />
      <div className="apertureField" style={{ transform: `translate(-50%, -50%) rotate(${spin}deg)` }}>
        {Array.from({ length: 12 }, (_, index) => (
          <span
            key={index}
            className="irisBlade"
            style={{
              transform: `rotate(${index * 30}deg) translateY(-355px)`,
              opacity: 0.18 + (index % 3) * 0.035,
            }}
          />
        ))}
      </div>
      <div className="lightSweep" style={{ transform: `translateX(${-120 + frame * 0.55}px) rotate(-14deg)` }} />
      <div className="vignette" />
    </AbsoluteFill>
  );
}

function Kicker({ children, style }: { children: React.ReactNode; style?: React.CSSProperties }) {
  return (
    <div className="kicker" style={style}>
      {children}
    </div>
  );
}

function WindowMock({ scale = 1, glow = 1 }: { scale?: number; glow?: number }) {
  return (
    <div className="windowMock" style={{ transform: `scale(${scale})`, boxShadow: `0 0 0 1px rgba(255,159,10,${0.13 * glow}), 0 54px 120px -42px rgba(0,0,0,.95), 0 34px 95px -48px rgba(255,122,26,${0.6 * glow})` }}>
      <div className="windowChrome">
        <span style={{ background: "#ff5f57" }} />
        <span style={{ background: "#febc2e" }} />
        <span style={{ background: "#28c840" }} />
        <b>Potret</b>
      </div>
      <Img className="homeShot" src={staticFile("home.png")} />
    </div>
  );
}

function MenuBar() {
  return (
    <div className="menuBar">
      <div className="menuLeft">
        <span className="appleDot" />
        <span>Finder</span>
        <span>File</span>
        <span>Edit</span>
        <span>View</span>
      </div>
      <div className="menuRight">
        <span>Wi-Fi</span>
        <span>100%</span>
        <span className="trayIcon">
          <ApertureMark size={20} />
        </span>
        <span>9:41</span>
      </div>
    </div>
  );
}

function HeroScene() {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const in1 = spring({ frame, fps, config: { damping: 200, stiffness: 120 } });
  const in2 = fade(frame, 16);
  const in3 = fade(frame, 32);
  const markRotation = interpolate(frame, [0, 120], [-18, 18], { extrapolateRight: "clamp" });

  return (
    <AbsoluteFill>
      <MenuBar />
      <div className="heroGrid">
        <div className="heroCopy">
          <div style={{ opacity: in1, transform: `translateY(${(1 - in1) * 24}px)` }}>
            <Kicker>FREE / OPEN SOURCE / MACOS</Kicker>
          </div>
          <h1 style={{ opacity: in2, transform: `translateY(${(1 - in2) * 30}px)` }}>
            Screenshots with a sense of <AccentText>style.</AccentText>
          </h1>
          <p style={{ opacity: in3, transform: `translateY(${(1 - in3) * 22}px)` }}>
            Potret lives in your menu bar. Capture, annotate, pin, and ship polished screenshots without a heavy editor or subscription.
          </p>
          <div className="commandChip" style={{ opacity: fade(frame, 50), transform: `translateY(${(1 - fade(frame, 50)) * 18}px)` }}>
            <span>$</span>
            <code>brew install --cask PradiptaPutra/tap/potret</code>
          </div>
        </div>
        <div className="heroShow" style={{ opacity: fade(frame, 20), transform: `translateY(${(1 - fade(frame, 20)) * 34}px) rotateX(7deg) rotateY(-8deg)` }}>
          <div className="markHalo">
            <ApertureMark size={136} rotate={markRotation} />
          </div>
          <WindowMock scale={0.86} />
        </div>
      </div>
    </AbsoluteFill>
  );
}

function CaptureScene() {
  const frame = useCurrentFrame();
  const modes = [
    ["01", "Area", "Drag a precise frame"],
    ["02", "Window", "Click the app you need"],
    ["03", "Fullscreen", "Grab the whole display"],
  ];

  return (
    <AbsoluteFill className="scene splitScene">
      <div className="sceneCopy">
        <Kicker>CAPTURE MODES</Kicker>
        <h2>
          From menu bar to screenshot in <AccentText>one move.</AccentText>
        </h2>
        <p>Pick an area, click a window, or capture the whole screen. Potret stays out of the Dock and in your flow.</p>
      </div>
      <div className="capturePanel">
        {modes.map((mode, index) => {
          const p = fade(frame, 14 + index * 12);
          return (
            <div key={mode[1]} className="modeCard" style={{ opacity: p, transform: `translateY(${(1 - p) * 28}px)` }}>
              <span className="modeNo">{mode[0]}</span>
              <div className={`captureDiagram captureDiagram${index + 1}`}>
                <i />
                <b />
              </div>
              <strong>{mode[1]}</strong>
              <small>{mode[2]}</small>
            </div>
          );
        })}
      </div>
    </AbsoluteFill>
  );
}

function QuickAccessScene() {
  const frame = useCurrentFrame();
  const items = ["Copy", "Save", "Annotate", "Pin", "Drag"];
  const p = fade(frame, 8);

  return (
    <AbsoluteFill className="scene quickScene">
      <div className="tiltedShot" style={{ opacity: p, transform: `translateY(${(1 - p) * 30}px) rotateX(8deg) rotateY(7deg)` }}>
        <WindowMock scale={0.72} glow={0.7} />
      </div>
      <div className="quickAccess" style={{ opacity: fade(frame, 24), transform: `translate(${(1 - fade(frame, 24)) * 80}px, ${(1 - fade(frame, 24)) * -32}px)` }}>
        <div className="quickTitle">Quick Access</div>
        <div className="quickActions">
          {items.map((item, index) => (
            <span key={item} style={{ opacity: fade(frame, 32 + index * 5) }}>
              {item}
            </span>
          ))}
        </div>
        <p>Appears after every capture and follows across Spaces.</p>
      </div>
      <div className="sceneCopy rightCopy">
        <Kicker>CAPTURE - ACT - KEEP MOVING</Kicker>
        <h2>
          The popup does the <AccentText>boring part fast.</AccentText>
        </h2>
        <p>Copy to clipboard, save to disk, open the editor, pin a reference, or drag the image into another app.</p>
      </div>
    </AbsoluteFill>
  );
}

function AnnotationScene() {
  const frame = useCurrentFrame();
  const tools = ["Pen", "Arrow", "Rect", "Ellipse", "Text", "Highlight", "Blur", "Step", "Crop", "Eraser"];

  return (
    <AbsoluteFill className="scene annotationScene">
      <div className="annotationCanvas" style={{ opacity: fade(frame, 8), transform: `scale(${0.96 + fade(frame, 8) * 0.04})` }}>
        <div className="toolRail">
          {tools.map((tool, index) => (
            <span key={tool} style={{ opacity: fade(frame, 18 + index * 3) }}>
              {tool.slice(0, 2)}
            </span>
          ))}
        </div>
        <div className="markedScreenshot">
          <div className="cropBox" />
          <svg className="annotationMarks" viewBox="0 0 760 430">
            <path
              d="M156 135 C 230 70, 365 88, 420 154"
              stroke={palette.amber}
              strokeWidth="10"
              fill="none"
              strokeLinecap="round"
              strokeDasharray="480"
              strokeDashoffset={480 - 480 * fade(frame, 35)}
            />
            <path d="M596 145 L676 95 L650 186 Z" fill="rgba(255,159,10,0.22)" stroke={palette.amber} strokeWidth="5" />
            <rect x="486" y="245" width="190" height="92" rx="14" fill="rgba(255,159,10,0.12)" stroke={palette.amber} strokeWidth="4" />
            <circle cx="150" cy="296" r="24" fill={palette.amber} />
            <text x="150" y="305" textAnchor="middle" fontSize="26" fontFamily="JetBrains Mono, monospace" fill="#1a0f02">
              1
            </text>
          </svg>
        </div>
      </div>
      <div className="annotationCopy">
        <Kicker>ANNOTATION STUDIO</Kicker>
        <h2>
          Markups that look <AccentText>intentional.</AccentText>
        </h2>
        <p>Pen, arrows, shapes, text, highlighter, pixelate/blur, numbered steps, crop, eraser, undo/redo, and a custom color picker.</p>
      </div>
    </AbsoluteFill>
  );
}

function BackgroundPinHistoryScene() {
  const frame = useCurrentFrame();

  return (
    <AbsoluteFill className="scene productScene">
      <div className="socialCanvas" style={{ opacity: fade(frame, 6), transform: `translateY(${(1 - fade(frame, 6)) * 32}px)` }}>
        <div className="socialPad">
          <WindowMock scale={0.5} glow={0.5} />
        </div>
        <div className="pinNote" style={{ opacity: fade(frame, 44) }}>
          <b>PINNED</b>
          <span>stays above your work</span>
        </div>
      </div>
      <div className="historyStack">
        {["Capture 042", "Capture 041", "Capture 040"].map((item, index) => (
          <div key={item} className="historyItem" style={{ opacity: fade(frame, 26 + index * 8), transform: `translateX(${(1 - fade(frame, 26 + index * 8)) * 40}px)` }}>
            <span />
            <div>
              <strong>{item}</strong>
              <small>copy / edit / pin / delete</small>
            </div>
          </div>
        ))}
      </div>
      <div className="sceneCopy bottomCopy">
        <Kicker>BACKGROUND / PIN / HISTORY</Kicker>
        <h2>
          Dress the shot, keep the reference, find it <AccentText>later.</AccentText>
        </h2>
        <p>Gradient or custom backgrounds, padding, rounded corners, shadows, floating pins, and recent captures from the menu bar.</p>
      </div>
    </AbsoluteFill>
  );
}

function OutputSystemScene() {
  const frame = useCurrentFrame();
  const cards = [
    ["PNG / JPG", "Choose format and quality"],
    ["Filename templates", "Clean names, less cleanup"],
    ["Global shortcuts", "Customize capture keys"],
    ["Launch at login", "Ready when macOS starts"],
  ];

  return (
    <AbsoluteFill className="scene outputScene">
      <div className="settingsPanel" style={{ opacity: fade(frame, 8) }}>
        <div className="settingsHeader">
          <ApertureMark size={42} />
          <div>
            <strong>Potret Settings</strong>
            <small>menu-bar only, native macOS capture</small>
          </div>
        </div>
        <div className="settingsGrid">
          {cards.map((card, index) => (
            <div key={card[0]} className="settingCard" style={{ opacity: fade(frame, 22 + index * 8), transform: `translateY(${(1 - fade(frame, 22 + index * 8)) * 18}px)` }}>
              <b>{card[0]}</b>
              <span>{card[1]}</span>
            </div>
          ))}
        </div>
      </div>
      <div className="sceneCopy rightCopy">
        <Kicker>OUTPUT + SYSTEM</Kicker>
        <h2>
          Native, tidy, and built for <AccentText>repeat work.</AccentText>
        </h2>
        <p>Small Tauri app, native screencapture engine, PNG/JPG output, shortcuts, launch at login, and fluid motion with Reduce Motion support.</p>
      </div>
    </AbsoluteFill>
  );
}

function FinalScene() {
  const frame = useCurrentFrame();
  const p = fade(frame, 8);

  return (
    <AbsoluteFill className="finalScene">
      <div className="finalCard" style={{ opacity: p, transform: `translateY(${(1 - p) * 26}px)` }}>
        <ApertureMark size={132} rotate={frame * 0.12} />
        <h2>Potret</h2>
        <p>Free, open-source screenshots for macOS.</p>
        <div className="finalCommand">
          <span>$</span>
          <code>brew install --cask PradiptaPutra/tap/potret</code>
        </div>
        <small>Area, window, fullscreen. Annotate, pin, background, history.</small>
      </div>
    </AbsoluteFill>
  );
}

export function PotretPromo() {
  const frame = useCurrentFrame();
  const outro = interpolate(frame, [780, 810], [1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });

  return (
    <AbsoluteFill style={{ backgroundColor: palette.ink }}>
      <Background />
      <Sequence from={0} durationInFrames={120}>
        <HeroScene />
      </Sequence>
      <Sequence from={120} durationInFrames={120}>
        <CaptureScene />
      </Sequence>
      <Sequence from={240} durationInFrames={120}>
        <QuickAccessScene />
      </Sequence>
      <Sequence from={360} durationInFrames={120}>
        <AnnotationScene />
      </Sequence>
      <Sequence from={480} durationInFrames={120}>
        <BackgroundPinHistoryScene />
      </Sequence>
      <Sequence from={600} durationInFrames={120}>
        <OutputSystemScene />
      </Sequence>
      <Sequence from={720} durationInFrames={90}>
        <FinalScene />
      </Sequence>
      <div className="fadeOut" style={{ opacity: 1 - outro }} />
    </AbsoluteFill>
  );
}
