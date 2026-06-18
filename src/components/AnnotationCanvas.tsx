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
  "#ef4444", // red
  "#f97316", // orange
  "#eab308", // yellow
  "#22c55e", // green
  "#3b82f6", // blue
  "#a855f7", // purple
  "#ec4899", // pink
  "#ffffff", // white
  "#000000", // black
];

const TOOLS: { key: Tool; icon: any; label: string }[] = [
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

  // Draw all committed shapes onto the base canvas
  const redrawBase = useCallback(
    (ctx: CanvasRenderingContext2D, img: HTMLImageElement) => {
      ctx.clearRect(0, 0, ctx.canvas.width, ctx.canvas.height);
      ctx.drawImage(img, 0, 0);
      shapes.forEach((s) => drawShape(ctx, s));
    },
    [shapes]
  );

  // Draw a single shape
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

  // Load image and draw it
  const imgRef = useRef<HTMLImageElement | null>(null);

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
      // Preview shape
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

  function getExportDataUrl(): string {
    return canvasRef.current!.toDataURL("image/png");
  }

  async function handleSave() {
    await onSave(getExportDataUrl());
    setSaved(true);
    setTimeout(() => setSaved(false), 2000);
  }

  async function handleCopy() {
    await onCopy(getExportDataUrl());
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  return (
    <div className="flex flex-col h-full bg-gray-950">
      {/* Top toolbar */}
      <div className="flex items-center gap-2 px-4 py-2 bg-gray-900 border-b border-white/10 shrink-0">
        <button
          onClick={onBack}
          className="flex items-center gap-1.5 text-white/50 hover:text-white text-sm px-2 py-1 rounded transition-colors cursor-pointer"
        >
          <ArrowLeft className="w-4 h-4" />
          Back
        </button>

        <div className="w-px h-5 bg-white/10 mx-1" />

        {/* Tools */}
        <div className="flex items-center gap-1">
          {TOOLS.map(({ key, icon: Icon, label }) => (
            <button
              key={key}
              title={label}
              onClick={() => setTool(key)}
              className={`p-2 rounded-lg transition-colors cursor-pointer ${
                tool === key
                  ? "bg-violet-500 text-white"
                  : "text-white/50 hover:text-white hover:bg-white/10"
              }`}
            >
              <Icon className="w-4 h-4" />
            </button>
          ))}
        </div>

        <div className="w-px h-5 bg-white/10 mx-1" />

        {/* Colors */}
        <div className="flex items-center gap-1">
          {COLORS.map((c) => (
            <button
              key={c}
              onClick={() => setColor(c)}
              className="w-5 h-5 rounded-full border-2 transition-transform hover:scale-110 cursor-pointer"
              style={{
                backgroundColor: c,
                borderColor: color === c ? "white" : "transparent",
              }}
            />
          ))}
        </div>

        <div className="w-px h-5 bg-white/10 mx-1" />

        {/* Line width */}
        <div className="flex items-center gap-2">
          <span className="text-xs text-white/30">Size</span>
          <input
            type="range"
            min={1}
            max={12}
            value={lineWidth}
            onChange={(e) => setLineWidth(Number(e.target.value))}
            className="w-20 accent-violet-500"
          />
          <span className="text-xs text-white/40 w-4">{lineWidth}</span>
        </div>

        <div className="w-px h-5 bg-white/10 mx-1" />

        {/* Undo / Clear */}
        <button
          onClick={() => setShapes((prev) => prev.slice(0, -1))}
          disabled={shapes.length === 0}
          className="text-xs text-white/40 hover:text-white disabled:opacity-20 px-2 py-1 rounded hover:bg-white/10 transition-colors cursor-pointer"
        >
          Undo
        </button>
        <button
          onClick={() => setShapes([])}
          disabled={shapes.length === 0}
          title="Clear all annotations"
          className="text-white/40 hover:text-red-400 disabled:opacity-20 p-1.5 rounded hover:bg-white/10 transition-colors cursor-pointer"
        >
          <Trash2 className="w-4 h-4" />
        </button>

        <div className="flex-1" />

        {/* Copy & Save */}
        <button
          onClick={handleCopy}
          className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-white/10 hover:bg-white/20 text-sm text-white transition-colors cursor-pointer"
        >
          {copied ? (
            <Check className="w-4 h-4 text-green-400" />
          ) : (
            <Copy className="w-4 h-4" />
          )}
          {copied ? "Copied!" : "Copy"}
        </button>
        <button
          onClick={handleSave}
          className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-violet-600 hover:bg-violet-500 text-sm text-white transition-colors cursor-pointer"
        >
          {saved ? (
            <Check className="w-4 h-4" />
          ) : (
            <Save className="w-4 h-4" />
          )}
          {saved ? "Saved!" : "Save"}
        </button>
      </div>

      {/* Canvas area */}
      <div
        ref={containerRef}
        className="flex-1 overflow-auto flex items-center justify-center bg-gray-950 p-4"
      >
        <div className="relative shadow-2xl">
          {/* Base canvas: image + committed shapes */}
          <canvas
            ref={canvasRef}
            className="block max-w-full max-h-[calc(100vh-120px)] object-contain"
            style={{ imageRendering: "auto" }}
          />
          {/* Overlay canvas: live drawing preview */}
          <canvas
            ref={overlayRef}
            onMouseDown={onMouseDown}
            onMouseMove={onMouseMove}
            onMouseUp={onMouseUp}
            onMouseLeave={onMouseUp}
            className="absolute inset-0 w-full h-full"
            style={{
              cursor:
                tool === "eraser"
                  ? "cell"
                  : tool === "text"
                  ? "text"
                  : "crosshair",
            }}
          />
        </div>
      </div>
    </div>
  );
}
