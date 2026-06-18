import { useEffect, useRef, useState, useCallback } from "react";
import {
  ArrowLeft,
  Save,
  Copy,
  Pencil,
  Square,
  Circle,
  ArrowRight,
  Type,
  Eraser,
  Minus,
  Trash2,
  Check,
  RotateCcw,
} from "lucide-react";
import { CaptureData } from "../App";

interface Props {
  capture: CaptureData;
  onBack: () => void;
  onSave: (dataUrl: string) => Promise<void>;
  onCopy: (dataUrl: string) => Promise<void>;
}

type Tool =
  | "select"
  | "pen"
  | "line"
  | "arrow"
  | "rect"
  | "ellipse"
  | "text"
  | "eraser";

interface Point {
  x: number;
  y: number;
}

interface DrawShape {
  type: Tool;
  points?: Point[];
  x?: number;
  y?: number;
  w?: number;
  h?: number;
  text?: string;
  color: string;
  lineWidth: number;
}

const COLORS = [
  "#ef4444",
  "#f97316",
  "#eab308",
  "#22c55e",
  "#3b82f6",
  "#a855f7",
  "#ec4899",
  "#ffffff",
  "#000000",
];

const TOOLS: { key: Tool; icon: React.ComponentType<{ className?: string }>; label: string }[] = [
  { key: "pen", icon: Pencil, label: "Pen" },
  { key: "line", icon: Minus, label: "Line" },
  { key: "arrow", icon: ArrowRight, label: "Arrow" },
  { key: "rect", icon: Square, label: "Rectangle" },
  { key: "ellipse", icon: Circle, label: "Ellipse" },
  { key: "text", icon: Type, label: "Text" },
  { key: "eraser", icon: Eraser, label: "Eraser" },
];

export default function AnnotationCanvas({
  capture,
  onBack,
  onSave,
  onCopy,
}: Props) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const overlayRef = useRef<HTMLCanvasElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);

  const [tool, setTool] = useState<Tool>("pen");
  const [color, setColor] = useState("#ef4444");
  const [lineWidth, setLineWidth] = useState(3);
  const [shapes, setShapes] = useState<DrawShape[]>([]);
  const [drawing, setDrawing] = useState(false);
  const [startPt, setStartPt] = useState<Point>({ x: 0, y: 0 });
  const [currentPoints, setCurrentPoints] = useState<Point[]>([]);
  const [saved, setSaved] = useState(false);
  const [copied, setCopied] = useState(false);

  // ── Drawing helpers ──────────────────────────────────────────────────────────

  function drawArrow(
    ctx: CanvasRenderingContext2D,
    from: Point,
    to: Point,
    lw: number
  ) {
    const headLen = Math.max(12, lw * 5);
    const dx = to.x - from.x;
    const dy = to.y - from.y;
    const angle = Math.atan2(dy, dx);
    ctx.beginPath();
    ctx.moveTo(from.x, from.y);
    ctx.lineTo(to.x, to.y);
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(to.x, to.y);
    ctx.lineTo(
      to.x - headLen * Math.cos(angle - Math.PI / 6),
      to.y - headLen * Math.sin(angle - Math.PI / 6)
    );
    ctx.moveTo(to.x, to.y);
    ctx.lineTo(
      to.x - headLen * Math.cos(angle + Math.PI / 6),
      to.y - headLen * Math.sin(angle + Math.PI / 6)
    );
    ctx.stroke();
  }

  function drawShape(ctx: CanvasRenderingContext2D, s: DrawShape) {
    ctx.save();
    ctx.strokeStyle = s.color;
    ctx.fillStyle = s.color;
    ctx.lineWidth = s.lineWidth;
    ctx.lineJoin = "round";
    ctx.lineCap = "round";

    if (s.type === "pen" && s.points && s.points.length > 1) {
      ctx.beginPath();
      ctx.moveTo(s.points[0].x, s.points[0].y);
      s.points.slice(1).forEach((p) => ctx.lineTo(p.x, p.y));
      ctx.stroke();
    } else if (s.type === "eraser" && s.points && s.points.length > 1) {
      ctx.globalCompositeOperation = "destination-out";
      ctx.lineWidth = s.lineWidth * 4;
      ctx.beginPath();
      ctx.moveTo(s.points[0].x, s.points[0].y);
      s.points.slice(1).forEach((p) => ctx.lineTo(p.x, p.y));
      ctx.stroke();
    } else if (s.type === "line" && s.points && s.points.length === 2) {
      ctx.beginPath();
      ctx.moveTo(s.points[0].x, s.points[0].y);
      ctx.lineTo(s.points[1].x, s.points[1].y);
      ctx.stroke();
    } else if (s.type === "arrow" && s.points && s.points.length === 2) {
      drawArrow(ctx, s.points[0], s.points[1], s.lineWidth);
    } else if (s.type === "rect" && s.x != null && s.y != null) {
      ctx.strokeRect(s.x!, s.y!, s.w!, s.h!);
    } else if (s.type === "ellipse" && s.x != null && s.y != null) {
      ctx.beginPath();
      ctx.ellipse(
        s.x! + s.w! / 2,
        s.y! + s.h! / 2,
        Math.abs(s.w! / 2),
        Math.abs(s.h! / 2),
        0,
        0,
        Math.PI * 2
      );
      ctx.stroke();
    } else if (s.type === "text" && s.text && s.x != null && s.y != null) {
      ctx.font = `${s.lineWidth * 6 + 12}px -apple-system, sans-serif`;
      ctx.fillText(s.text, s.x!, s.y!);
    }
    ctx.restore();
  }

  const imgRef = useRef<HTMLImageElement | null>(null);

  const redrawBase = useCallback(
    (ctx: CanvasRenderingContext2D, img: HTMLImageElement) => {
      ctx.clearRect(0, 0, ctx.canvas.width, ctx.canvas.height);
      ctx.drawImage(img, 0, 0);
      shapes.forEach((s) => drawShape(ctx, s));
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [shapes]
  );

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const img = new Image();
    img.src = `data:image/png;base64,${capture.data}`;
    img.onload = () => {
      imgRef.current = img;
      canvas.width = img.naturalWidth;
      canvas.height = img.naturalHeight;
      if (overlayRef.current) {
        overlayRef.current.width = img.naturalWidth;
        overlayRef.current.height = img.naturalHeight;
      }
      const ctx = canvas.getContext("2d")!;
      ctx.drawImage(img, 0, 0);
    };
  }, [capture]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || !imgRef.current) return;
    const ctx = canvas.getContext("2d")!;
    redrawBase(ctx, imgRef.current);
  }, [shapes, redrawBase]);

  // ── Global keyboard shortcut listeners ─────────────────────────────────────

  const handleSave = useCallback(async () => {
    await onSave(canvasRef.current!.toDataURL("image/png"));
    setSaved(true);
    setTimeout(() => setSaved(false), 2000);
  }, [onSave]);

  useEffect(() => {
    function onUndo() {
      setShapes((prev) => prev.slice(0, -1));
    }
    window.addEventListener("annotation:undo", onUndo);
    window.addEventListener("annotation:save", handleSave as EventListener);
    return () => {
      window.removeEventListener("annotation:undo", onUndo);
      window.removeEventListener("annotation:save", handleSave as EventListener);
    };
  }, [handleSave]);

  // ── Mouse handling ─────────────────────────────────────────────────────────

  function getPos(e: React.MouseEvent<HTMLCanvasElement>): Point {
    const canvas = overlayRef.current!;
    const rect = canvas.getBoundingClientRect();
    const scaleX = canvas.width / rect.width;
    const scaleY = canvas.height / rect.height;
    return {
      x: (e.clientX - rect.left) * scaleX,
      y: (e.clientY - rect.top) * scaleY,
    };
  }

  function onMouseDown(e: React.MouseEvent<HTMLCanvasElement>) {
    if (tool === "text") {
      const pt = getPos(e);
      const text = prompt("Enter text:");
      if (text) {
        setShapes((prev) => [
          ...prev,
          { type: "text", text, x: pt.x, y: pt.y, color, lineWidth },
        ]);
      }
      return;
    }
    setDrawing(true);
    const pt = getPos(e);
    setStartPt(pt);
    setCurrentPoints([pt]);
  }

  function onMouseMove(e: React.MouseEvent<HTMLCanvasElement>) {
    if (!drawing) return;
    const pt = getPos(e);
    const overlay = overlayRef.current!;
    const ctx = overlay.getContext("2d")!;
    ctx.clearRect(0, 0, overlay.width, overlay.height);

    if (tool === "pen" || tool === "eraser") {
      setCurrentPoints((prev) => {
        const updated = [...prev, pt];
        ctx.save();
        ctx.strokeStyle = color;
        ctx.lineWidth = tool === "eraser" ? lineWidth * 4 : lineWidth;
        ctx.lineJoin = "round";
        ctx.lineCap = "round";
        if (tool === "eraser") {
          ctx.strokeStyle = "rgba(255,0,0,0.4)";
        }
        ctx.beginPath();
        ctx.moveTo(updated[0].x, updated[0].y);
        updated.slice(1).forEach((p) => ctx.lineTo(p.x, p.y));
        ctx.stroke();
        ctx.restore();
        return updated;
      });
    } else {
      ctx.save();
      ctx.strokeStyle = color;
      ctx.fillStyle = color;
      ctx.lineWidth = lineWidth;
      ctx.lineJoin = "round";
      ctx.lineCap = "round";
      if (tool === "line") {
        ctx.beginPath();
        ctx.moveTo(startPt.x, startPt.y);
        ctx.lineTo(pt.x, pt.y);
        ctx.stroke();
      } else if (tool === "arrow") {
        drawArrow(ctx, startPt, pt, lineWidth);
      } else if (tool === "rect") {
        ctx.strokeRect(startPt.x, startPt.y, pt.x - startPt.x, pt.y - startPt.y);
      } else if (tool === "ellipse") {
        const cx = (startPt.x + pt.x) / 2;
        const cy = (startPt.y + pt.y) / 2;
        ctx.beginPath();
        ctx.ellipse(
          cx,
          cy,
          Math.abs((pt.x - startPt.x) / 2),
          Math.abs((pt.y - startPt.y) / 2),
          0,
          0,
          Math.PI * 2
        );
        ctx.stroke();
      }
      ctx.restore();
    }
  }

  function onMouseUp(e: React.MouseEvent<HTMLCanvasElement>) {
    if (!drawing) return;
    setDrawing(false);
    const pt = getPos(e);
    const overlay = overlayRef.current!;
    overlay.getContext("2d")!.clearRect(0, 0, overlay.width, overlay.height);

    if (tool === "pen" || tool === "eraser") {
      if (currentPoints.length > 1) {
        setShapes((prev) => [
          ...prev,
          { type: tool, points: currentPoints, color, lineWidth },
        ]);
      }
    } else if (tool === "line") {
      setShapes((prev) => [
        ...prev,
        { type: "line", points: [startPt, pt], color, lineWidth },
      ]);
    } else if (tool === "arrow") {
      setShapes((prev) => [
        ...prev,
        { type: "arrow", points: [startPt, pt], color, lineWidth },
      ]);
    } else if (tool === "rect") {
      setShapes((prev) => [
        ...prev,
        {
          type: "rect",
          x: startPt.x,
          y: startPt.y,
          w: pt.x - startPt.x,
          h: pt.y - startPt.y,
          color,
          lineWidth,
        },
      ]);
    } else if (tool === "ellipse") {
      setShapes((prev) => [
        ...prev,
        {
          type: "ellipse",
          x: startPt.x,
          y: startPt.y,
          w: pt.x - startPt.x,
          h: pt.y - startPt.y,
          color,
          lineWidth,
        },
      ]);
    }
    setCurrentPoints([]);
  }

  async function handleCopy() {
    await onCopy(canvasRef.current!.toDataURL("image/png"));
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  // ── Render ─────────────────────────────────────────────────────────────────

  return (
    <div className="flex flex-col h-full" style={{ background: "#0d0d14" }}>
      {/* ── Top toolbar — slim 44px ── */}
      <div
        className="flex items-center gap-1.5 px-3 shrink-0"
        style={{
          height: "44px",
          background: "#0d0d14",
          borderBottom: "1px solid rgba(255,255,255,0.07)",
        }}
      >
        {/* Back */}
        <button
          onClick={onBack}
          className="flex items-center gap-1.5 rounded-md transition-colors cursor-pointer hover:bg-white/8"
          style={{
            padding: "5px 8px",
            color: "rgba(255,255,255,0.40)",
            fontSize: "12px",
            fontWeight: 500,
            background: "transparent",
            border: "none",
          }}
        >
          <ArrowLeft className="w-3.5 h-3.5" />
          <span>Back</span>
        </button>

        <div style={{ width: "1px", height: "18px", background: "rgba(255,255,255,0.08)", flexShrink: 0 }} />

        {/* Tool pill group */}
        <div
          className="flex items-center gap-0.5 rounded-lg p-0.5"
          style={{
            background: "rgba(255,255,255,0.05)",
            border: "1px solid rgba(255,255,255,0.07)",
          }}
        >
          {TOOLS.map(({ key, icon: Icon, label }) => (
            <button
              key={key}
              title={label}
              onClick={() => setTool(key)}
              className="flex items-center justify-center rounded-md transition-all duration-100 cursor-pointer"
              style={{
                width: "28px",
                height: "28px",
                background: tool === key ? "#7c3aed" : "transparent",
                border: "none",
                color: tool === key ? "#fff" : "rgba(255,255,255,0.45)",
                boxShadow: tool === key ? "0 1px 4px rgba(124,58,237,0.5)" : "none",
              }}
            >
              <Icon className="w-3.5 h-3.5" />
            </button>
          ))}
        </div>

        <div style={{ width: "1px", height: "18px", background: "rgba(255,255,255,0.08)", flexShrink: 0 }} />

        {/* Color swatches */}
        <div className="flex items-center gap-1">
          {COLORS.map((c) => (
            <button
              key={c}
              onClick={() => setColor(c)}
              title={c}
              className="rounded-full transition-transform hover:scale-110 cursor-pointer"
              style={{
                width: "14px",
                height: "14px",
                backgroundColor: c,
                border: color === c ? "2px solid #8b5cf6" : "2px solid transparent",
                outline: color === c ? "1px solid rgba(139,92,246,0.4)" : "none",
                outlineOffset: "1px",
                padding: 0,
                flexShrink: 0,
              }}
            />
          ))}
        </div>

        <div style={{ width: "1px", height: "18px", background: "rgba(255,255,255,0.08)", flexShrink: 0 }} />

        {/* Stroke size */}
        <div className="flex items-center gap-2">
          <span style={{ fontSize: "10px", color: "rgba(255,255,255,0.25)", whiteSpace: "nowrap" }}>Size</span>
          <input
            type="range"
            min={1}
            max={12}
            value={lineWidth}
            onChange={(e) => setLineWidth(Number(e.target.value))}
            className="accent-violet-500"
            style={{ width: "60px" }}
          />
          <span
            className="font-mono tabular-nums"
            style={{ fontSize: "10px", color: "rgba(255,255,255,0.35)", width: "14px" }}
          >
            {lineWidth}
          </span>
        </div>

        <div style={{ width: "1px", height: "18px", background: "rgba(255,255,255,0.08)", flexShrink: 0 }} />

        {/* Undo */}
        <button
          onClick={() => setShapes((prev) => prev.slice(0, -1))}
          disabled={shapes.length === 0}
          title="Undo (⌘Z)"
          className="flex items-center justify-center rounded-md transition-colors cursor-pointer disabled:opacity-20 hover:bg-white/8"
          style={{ width: "28px", height: "28px", background: "transparent", border: "none", color: "rgba(255,255,255,0.40)" }}
        >
          <RotateCcw className="w-3.5 h-3.5" />
        </button>

        {/* Clear */}
        <button
          onClick={() => setShapes([])}
          disabled={shapes.length === 0}
          title="Clear all annotations"
          className="flex items-center justify-center rounded-md transition-colors cursor-pointer disabled:opacity-20 hover:bg-red-500/15 hover:text-red-400"
          style={{ width: "28px", height: "28px", background: "transparent", border: "none", color: "rgba(255,255,255,0.40)" }}
        >
          <Trash2 className="w-3.5 h-3.5" />
        </button>

        {/* Spacer */}
        <div className="flex-1" />

        {/* Copy — ghost style */}
        <button
          onClick={handleCopy}
          className="flex items-center gap-1.5 rounded-lg transition-all duration-150 cursor-pointer hover:bg-white/12"
          style={{
            padding: "5px 12px",
            fontSize: "12px",
            fontWeight: 500,
            background: "rgba(255,255,255,0.07)",
            border: "1px solid rgba(255,255,255,0.10)",
            color: copied ? "#10b981" : "rgba(255,255,255,0.80)",
          }}
        >
          {copied ? <Check className="w-3.5 h-3.5" /> : <Copy className="w-3.5 h-3.5" />}
          {copied ? "Copied!" : "Copy"}
        </button>

        {/* Save — violet filled */}
        <button
          onClick={handleSave}
          className="flex items-center gap-1.5 rounded-lg transition-all duration-150 cursor-pointer"
          style={{
            padding: "5px 12px",
            fontSize: "12px",
            fontWeight: 500,
            background: saved ? "#059669" : "#7c3aed",
            border: "none",
            color: "#fff",
            boxShadow: saved ? "0 2px 8px rgba(5,150,105,0.4)" : "0 2px 8px rgba(124,58,237,0.45)",
          }}
        >
          {saved ? <Check className="w-3.5 h-3.5" /> : <Save className="w-3.5 h-3.5" />}
          {saved ? "Saved!" : "Save"}
        </button>
      </div>

      {/* ── Canvas area ── */}
      <div
        ref={containerRef}
        className="flex-1 overflow-auto flex items-center justify-center"
        style={{ background: "#0d0d14", padding: "24px" }}
      >
        <div
          className="relative"
          style={{
            boxShadow: "0 8px 48px rgba(0,0,0,0.6), 0 2px 8px rgba(0,0,0,0.4)",
            borderRadius: "2px",
          }}
        >
          <canvas
            ref={canvasRef}
            className="block"
            style={{
              maxWidth: "100%",
              maxHeight: "calc(100vh - 92px)",
              objectFit: "contain",
              imageRendering: "auto",
            }}
          />
          <canvas
            ref={overlayRef}
            onMouseDown={onMouseDown}
            onMouseMove={onMouseMove}
            onMouseUp={onMouseUp}
            onMouseLeave={onMouseUp}
            className="absolute inset-0 w-full h-full"
            style={{
              cursor: tool === "eraser" ? "cell" : tool === "text" ? "text" : "crosshair",
            }}
          />
        </div>
      </div>
    </div>
  );
}
