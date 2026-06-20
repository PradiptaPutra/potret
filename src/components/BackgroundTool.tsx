import { useState, useEffect, useRef, useCallback } from "react";
import { invoke } from "@tauri-apps/api/core";
import { save } from "@tauri-apps/plugin-dialog";
import { X, Download, Copy, Upload, Check } from "lucide-react";

interface Props {
  imageSrc: string; // "data:image/png;base64,..." or bare base64 string
  onClose: () => void;
}

interface BgPreset {
  id: string;
  name: string;
  type: "gradient";
  stops: string[];
  // gradient direction as [x1_pct, y1_pct, x2_pct, y2_pct] of canvas size
  dir: [number, number, number, number];
}

const PRESETS: BgPreset[] = [
  { id: "pink-sunset",  name: "Pink Sunset",  type: "gradient", stops: ["#f093fb", "#f5576c"], dir: [0, 0, 1, 1] },
  { id: "ocean",        name: "Ocean Blue",   type: "gradient", stops: ["#4facfe", "#00f2fe"], dir: [0, 0, 1, 1] },
  { id: "mint",         name: "Mint Fresh",   type: "gradient", stops: ["#43e97b", "#38f9d7"], dir: [0, 0, 1, 1] },
  { id: "rose-gold",    name: "Rose Gold",    type: "gradient", stops: ["#fa709a", "#fee140"], dir: [0, 0, 1, 1] },
  { id: "lavender",     name: "Lavender",     type: "gradient", stops: ["#a18cd1", "#fbc2eb"], dir: [0, 0, 1, 1] },
  { id: "peach-purple", name: "Peach Purple", type: "gradient", stops: ["#fccb90", "#d57eeb"], dir: [0, 0, 1, 1] },
  { id: "purple-night", name: "Purple Night", type: "gradient", stops: ["#667eea", "#764ba2"], dir: [0, 0, 1, 1] },
  { id: "deep-space",   name: "Deep Space",   type: "gradient", stops: ["#1a1a2e", "#16213e", "#0f3460"], dir: [0, 0, 0, 1] },
  { id: "golden-sun",   name: "Golden Sun",   type: "gradient", stops: ["#f7971e", "#ffd200"], dir: [0, 0, 1, 1] },
  { id: "midnight",     name: "Midnight",     type: "gradient", stops: ["#0f2027", "#203a43", "#2c5364"], dir: [0, 0, 1, 1] },
];

function drawScreenshot(
  ctx: CanvasRenderingContext2D,
  img: HTMLImageElement,
  P: number,
  R: number,
  W: number,
  H: number,
  shadow: boolean,
  scale: number,
) {
  const imgW = W - P * 2;
  const imgH = H - P * 2;

  ctx.save();
  if (shadow) {
    ctx.shadowBlur = 32 * scale;
    ctx.shadowColor = "rgba(0,0,0,0.35)";
    ctx.shadowOffsetY = 6 * scale;
  }
  if (R > 0) {
    ctx.beginPath();
    ctx.roundRect(P, P, imgW, imgH, R);
    ctx.clip();
  }
  ctx.drawImage(img, P, P, imgW, imgH);
  ctx.restore();
}

export default function BackgroundTool({ imageSrc, onClose }: Props) {
  const [selectedPreset, setSelectedPreset] = useState(0);
  const [padding, setPadding] = useState(60);
  const [cornerRadius, setCornerRadius] = useState(12);
  const [shadow, setShadow] = useState(true);
  const [customBg, setCustomBg] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const [copyError, setCopyError] = useState(false);
  const [exportError, setExportError] = useState(false);

  const previewCanvasRef = useRef<HTMLCanvasElement>(null);
  const imgRef = useRef<HTMLImageElement | null>(null);
  // Cache the loaded custom bg image to avoid re-loading on every render
  const customBgImgRef = useRef<HTMLImageElement | null>(null);

  // Returns a Promise that resolves once the canvas is fully drawn (incl. async custom bg load),
  // so export/copy never read a half-rendered canvas.
  const renderToCanvas = useCallback(
    (canvas: HTMLCanvasElement, img: HTMLImageElement, scale: number): Promise<void> => {
      const preset = PRESETS[selectedPreset];
      const P = Math.round(padding * scale);
      const R = cornerRadius * scale;
      const W = Math.round(img.naturalWidth * scale) + P * 2;
      const H = Math.round(img.naturalHeight * scale) + P * 2;

      canvas.width = W;
      canvas.height = H;
      const ctx = canvas.getContext("2d")!;
      ctx.clearRect(0, 0, W, H);

      if (customBg) {
        return new Promise<void>((resolve) => {
          const doDraw = (bgImg: HTMLImageElement) => {
            ctx.drawImage(bgImg, 0, 0, W, H);
            drawScreenshot(ctx, img, P, R, W, H, shadow, scale);
            resolve();
          };
          if (customBgImgRef.current && customBgImgRef.current.src === customBg) {
            doDraw(customBgImgRef.current);
          } else {
            const bgImg = new Image();
            bgImg.onload = () => {
              customBgImgRef.current = bgImg;
              doDraw(bgImg);
            };
            bgImg.onerror = () => resolve(); // give up — leave background blank rather than hang
            bgImg.src = customBg;
          }
        });
      }

      const [x1p, y1p, x2p, y2p] = preset.dir;
      const grad = ctx.createLinearGradient(x1p * W, y1p * H, x2p * W, y2p * H);
      preset.stops.forEach((c, i) =>
        grad.addColorStop(i / (preset.stops.length - 1), c),
      );
      ctx.fillStyle = grad;
      ctx.fillRect(0, 0, W, H);
      drawScreenshot(ctx, img, P, R, W, H, shadow, scale);
      return Promise.resolve();
    },
    [selectedPreset, padding, cornerRadius, shadow, customBg],
  );

  const redrawPreview = useCallback(() => {
    const img = imgRef.current;
    const canvas = previewCanvasRef.current;
    if (!img || !canvas) return;
    // Render at a high enough resolution that the canvas stays crisp when CSS shrinks it to
    // fit the panel on a Retina display (480px was ~2× too few pixels → blurry).
    const maxW = 1600;
    const scale = Math.min(maxW / img.naturalWidth, 1);
    void renderToCanvas(canvas, img, scale);
  }, [renderToCanvas]);

  // Load the source image once (or when imageSrc changes)
  useEffect(() => {
    const img = new Image();
    img.onload = () => {
      imgRef.current = img;
      redrawPreview();
    };
    img.src = imageSrc.startsWith("data:") ? imageSrc : `data:image/png;base64,${imageSrc}`;
  }, [imageSrc]); // eslint-disable-line react-hooks/exhaustive-deps

  // Redraw whenever any control changes
  useEffect(() => {
    redrawPreview();
  }, [selectedPreset, padding, cornerRadius, shadow, customBg, redrawPreview]);

  // Clear cached bg image when customBg changes
  useEffect(() => {
    if (!customBg) {
      customBgImgRef.current = null;
    }
  }, [customBg]);

  async function handleExport() {
    const img = imgRef.current;
    if (!img) return;
    const fullCanvas = document.createElement("canvas");
    await renderToCanvas(fullCanvas, img, 1); // wait for the full render (incl. custom bg)
    const base64 = fullCanvas
      .toDataURL("image/png")
      .replace(/^data:image\/png;base64,/, "");
    try {
      // The webview blocks <a download>; use Tauri's save dialog + a real file write.
      const path = await save({
        defaultPath: `potret-bg-${Date.now()}.png`,
        filters: [{ name: "PNG Image", extensions: ["png"] }],
      });
      if (path) {
        await invoke("save_image", { data: base64, path });
      }
    } catch {
      setExportError(true);
      setTimeout(() => setExportError(false), 1800);
    }
  }

  function flashCopyError() {
    setCopyError(true);
    setTimeout(() => setCopyError(false), 1800);
  }

  async function handleCopy() {
    const img = imgRef.current;
    if (!img) return;
    const fullCanvas = document.createElement("canvas");
    await renderToCanvas(fullCanvas, img, 1);
    fullCanvas.toBlob(async (blob) => {
      if (!blob) { flashCopyError(); return; }
      try {
        await navigator.clipboard.write([
          new ClipboardItem({ "image/png": blob }),
        ]);
        setCopied(true);
        setTimeout(() => setCopied(false), 1500);
      } catch {
        flashCopyError();
      }
    }, "image/png");
  }

  function handleCustomBg(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = (ev) => {
      setCustomBg(ev.target?.result as string);
    };
    reader.readAsDataURL(file);
  }

  return (
    <div
      style={{
        position: "fixed",
        inset: 0,
        zIndex: 9000,
        background: "rgba(0,0,0,0.85)",
        backdropFilter: "blur(8px)",
        display: "flex",
        flexDirection: "column",
        fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
      }}
    >
      {/* Header — inset left so the macOS traffic lights don't overlap the title */}
      <div
        data-tauri-drag-region
        style={{
          height: 48,
          flexShrink: 0,
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          paddingLeft: 92,
          paddingRight: 20,
          borderBottom: "1px solid rgba(255,255,255,0.07)",
        }}
      >
        <span
          style={{
            fontSize: 13,
            fontWeight: 600,
            color: "rgba(255,255,255,0.88)",
          }}
        >
          Background
        </span>
        <button
          onClick={onClose}
          style={{
            background: "none",
            border: "none",
            cursor: "pointer",
            color: "rgba(255,255,255,0.5)",
            display: "flex",
            padding: 4,
          }}
          onMouseEnter={(e) =>
            (e.currentTarget.style.color = "rgba(255,255,255,0.9)")
          }
          onMouseLeave={(e) =>
            (e.currentTarget.style.color = "rgba(255,255,255,0.5)")
          }
        >
          <X size={16} />
        </button>
      </div>

      {/* Body */}
      <div style={{ flex: 1, display: "flex", overflow: "hidden" }}>
        {/* Left: controls */}
        <div
          style={{
            width: 240,
            flexShrink: 0,
            background: "rgba(255,255,255,0.03)",
            borderRight: "1px solid rgba(255,255,255,0.06)",
            padding: 16,
            overflowY: "auto",
            display: "flex",
            flexDirection: "column",
            gap: 20,
          }}
        >
          {/* Background presets */}
          <div>
            <p
              style={{
                fontSize: 10,
                fontWeight: 600,
                textTransform: "uppercase",
                letterSpacing: "0.07em",
                color: "rgba(255,255,255,0.28)",
                marginBottom: 10,
                margin: "0 0 10px 0",
              }}
            >
              Background
            </p>
            <div
              style={{
                display: "grid",
                gridTemplateColumns: "1fr 1fr",
                gap: 6,
              }}
            >
              {PRESETS.map((p, i) => {
                const isSelected = selectedPreset === i && !customBg;
                const stopsCss = p.stops.join(", ");
                const dirCss =
                  p.dir[0] === p.dir[2]
                    ? "to bottom"
                    : p.dir[1] === p.dir[3]
                      ? "to right"
                      : "135deg";
                return (
                  <button
                    key={p.id}
                    onClick={() => {
                      setSelectedPreset(i);
                      setCustomBg(null);
                    }}
                    title={p.name}
                    style={{
                      height: 40,
                      borderRadius: 8,
                      background: `linear-gradient(${dirCss}, ${stopsCss})`,
                      border: isSelected
                        ? "2px solid rgba(255,255,255,0.9)"
                        : "2px solid transparent",
                      cursor: "pointer",
                      outline: "none",
                      boxShadow: isSelected
                        ? "0 0 0 1px rgba(0,0,0,0.5)"
                        : "none",
                      transition: "border-color 0.1s",
                      position: "relative",
                    }}
                  >
                    {isSelected && (
                      <div
                        style={{
                          position: "absolute",
                          inset: 0,
                          display: "flex",
                          alignItems: "center",
                          justifyContent: "center",
                        }}
                      >
                        <Check size={14} color="white" strokeWidth={2.5} />
                      </div>
                    )}
                  </button>
                );
              })}
            </div>

            {/* Custom background upload */}
            <label
              style={{
                display: "flex",
                alignItems: "center",
                gap: 8,
                marginTop: 10,
                padding: "8px 10px",
                background: customBg
                  ? "rgba(255,159,10,0.1)"
                  : "rgba(255,255,255,0.04)",
                border: `1px solid ${customBg ? "rgba(255,159,10,0.3)" : "rgba(255,255,255,0.08)"}`,
                borderRadius: 7,
                cursor: "pointer",
                fontSize: 12,
                color: customBg
                  ? "rgba(255,159,10,0.9)"
                  : "rgba(255,255,255,0.55)",
              }}
            >
              <Upload size={12} />
              {customBg ? "Custom image set" : "Add your own"}
              <input
                type="file"
                accept="image/*"
                style={{ display: "none" }}
                onChange={handleCustomBg}
              />
            </label>
            {customBg && (
              <button
                onClick={() => setCustomBg(null)}
                style={{
                  marginTop: 4,
                  fontSize: 10,
                  color: "rgba(255,255,255,0.3)",
                  background: "none",
                  border: "none",
                  cursor: "pointer",
                  padding: 0,
                }}
              >
                Remove custom
              </button>
            )}
          </div>

          {/* Padding slider */}
          <div>
            <div
              style={{
                display: "flex",
                justifyContent: "space-between",
                marginBottom: 8,
              }}
            >
              <span style={{ fontSize: 12, color: "rgba(255,255,255,0.55)" }}>
                Padding
              </span>
              <span
                style={{
                  fontSize: 11,
                  fontFamily: "ui-monospace, monospace",
                  color: "rgba(255,255,255,0.35)",
                }}
              >
                {padding}px
              </span>
            </div>
            <input
              type="range"
              min={0}
              max={160}
              value={padding}
              onChange={(e) => setPadding(Number(e.target.value))}
              style={{ width: "100%", accentColor: "#FF9F0A" }}
            />
          </div>

          {/* Corner radius slider */}
          <div>
            <div
              style={{
                display: "flex",
                justifyContent: "space-between",
                marginBottom: 8,
              }}
            >
              <span style={{ fontSize: 12, color: "rgba(255,255,255,0.55)" }}>
                Corner Radius
              </span>
              <span
                style={{
                  fontSize: 11,
                  fontFamily: "ui-monospace, monospace",
                  color: "rgba(255,255,255,0.35)",
                }}
              >
                {cornerRadius}px
              </span>
            </div>
            <input
              type="range"
              min={0}
              max={32}
              value={cornerRadius}
              onChange={(e) => setCornerRadius(Number(e.target.value))}
              style={{ width: "100%", accentColor: "#FF9F0A" }}
            />
          </div>

          {/* Shadow toggle */}
          <div
            style={{
              display: "flex",
              alignItems: "center",
              justifyContent: "space-between",
            }}
          >
            <span style={{ fontSize: 12, color: "rgba(255,255,255,0.55)" }}>
              Drop Shadow
            </span>
            <button
              onClick={() => setShadow(!shadow)}
              style={{
                width: 36,
                height: 20,
                borderRadius: 10,
                background: shadow ? "#FF9F0A" : "rgba(255,255,255,0.12)",
                border: "none",
                cursor: "pointer",
                position: "relative",
                transition: "background 0.15s",
              }}
            >
              <div
                style={{
                  position: "absolute",
                  top: 2,
                  left: shadow ? 18 : 2,
                  width: 16,
                  height: 16,
                  borderRadius: "50%",
                  background: "white",
                  transition: "left 0.15s",
                  boxShadow: "0 1px 3px rgba(0,0,0,0.3)",
                }}
              />
            </button>
          </div>
        </div>

        {/* Right: preview */}
        <div
          style={{
            flex: 1,
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            justifyContent: "center",
            padding: 32,
            overflow: "hidden",
            background: "rgba(0,0,0,0.2)",
          }}
        >
          <canvas
            ref={previewCanvasRef}
            style={{
              maxWidth: "100%",
              maxHeight: "100%",
              borderRadius: 8,
              boxShadow: "0 8px 32px rgba(0,0,0,0.5)",
            }}
          />
        </div>
      </div>

      {/* Footer actions */}
      <div
        style={{
          height: 56,
          flexShrink: 0,
          display: "flex",
          alignItems: "center",
          justifyContent: "flex-end",
          gap: 8,
          padding: "0 20px",
          borderTop: "1px solid rgba(255,255,255,0.07)",
        }}
      >
        <button
          onClick={handleCopy}
          style={{
            display: "flex",
            alignItems: "center",
            gap: 6,
            padding: "7px 14px",
            borderRadius: 7,
            background: "rgba(255,255,255,0.07)",
            border: "1px solid rgba(255,255,255,0.1)",
            color: copied ? "#32D74B" : copyError ? "#FF453A" : "rgba(255,255,255,0.75)",
            fontSize: 13,
            cursor: "pointer",
            transition: "color 0.15s, background 0.15s",
          }}
        >
          {copied ? <Check size={14} /> : copyError ? <X size={14} /> : <Copy size={14} />}
          {copied ? "Copied!" : copyError ? "Copy failed" : "Copy"}
        </button>
        <button
          onClick={handleExport}
          style={{
            display: "flex",
            alignItems: "center",
            gap: 6,
            padding: "7px 14px",
            borderRadius: 7,
            background: "#FF9F0A",
            border: "none",
            color: "#000",
            fontSize: 13,
            fontWeight: 600,
            cursor: "pointer",
          }}
          onMouseEnter={(e) => (e.currentTarget.style.background = "#e8900a")}
          onMouseLeave={(e) => (e.currentTarget.style.background = "#FF9F0A")}
        >
          <Download size={14} />
          {exportError ? "Export failed" : "Export PNG"}
        </button>
      </div>
    </div>
  );
}
