import { useEffect, useRef, useState, useCallback } from "react";
import {
  MousePointer2,
  Square,
  Circle,
  ArrowRight,
  Minus,
  Type,
  PenTool,
  Highlighter,
  Grid2x2,
  ListOrdered,
  Crop,
  Eraser,
  RotateCcw,
  RotateCw,
  Image as ImageIcon,
} from "lucide-react";
import { CaptureData } from "../App";

interface Props {
  capture: CaptureData;
  onBack: () => void;
  onDone: (dataUrl: string) => Promise<void>; // save to folder & finish
  onCopy: (dataUrl: string) => Promise<void>;
  onBackground: (dataUrl: string) => void; // send the annotated image to the Background tool
}

type Tool =
  | "select"
  | "rect"
  | "ellipse"
  | "arrow"
  | "line"
  | "text"
  | "pen"
  | "highlight"
  | "pixelate"
  | "step"
  | "crop"
  | "eraser";

interface Point {
  x: number;
  y: number;
}

interface CropRect {
  x: number;
  y: number;
  w: number;
  h: number;
}

interface DrawShape {
  type:
    | "rect"
    | "ellipse"
    | "arrow"
    | "line"
    | "text"
    | "pen"
    | "highlight"
    | "pixelate"
    | "step"
    | "eraser";
  points?: Point[];
  x?: number;
  y?: number;
  w?: number;
  h?: number;
  text?: string;
  num?: number; // step counter number
  color: string;
  lineWidth: number;
}

const COLOR_PRESETS = [
  "#FF453A",
  "#FF9F0A",
  "#32D74B",
  "#0A84FF",
  "#BF5AF2",
  "#ffffff",
  "#000000",
];

const LINE_WIDTH = 3;

// ── Pixelate helper ──────────────────────────────────────────────────────────

function applyPixelate(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  w: number,
  h: number,
  blockSize = 12
) {
  const endX = x + w;
  const endY = y + h;
  for (let bx = x; bx < endX; bx += blockSize) {
    for (let by = y; by < endY; by += blockSize) {
      const cx = Math.min(bx + Math.floor(blockSize / 2), ctx.canvas.width - 1);
      const cy = Math.min(by + Math.floor(blockSize / 2), ctx.canvas.height - 1);
      const data = ctx.getImageData(cx, cy, 1, 1).data;
      ctx.fillStyle = `rgba(${data[0]},${data[1]},${data[2]},${data[3] / 255})`;
      ctx.fillRect(
        bx,
        by,
        Math.min(blockSize, endX - bx),
        Math.min(blockSize, endY - by)
      );
    }
  }
}

// ── Arrow helper ─────────────────────────────────────────────────────────────

function drawArrow(
  ctx: CanvasRenderingContext2D,
  from: Point,
  to: Point,
  lw: number
) {
  const headLen = Math.max(14, lw * 5);
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

// ── Shape renderer ────────────────────────────────────────────────────────────

function drawShape(ctx: CanvasRenderingContext2D, s: DrawShape) {
  ctx.save();
  ctx.strokeStyle = s.color;
  ctx.fillStyle = s.color;
  ctx.lineWidth = s.lineWidth;
  ctx.lineJoin = "round";
  ctx.lineCap = "round";

  if (s.type === "eraser" && s.points && s.points.length > 1) {
    ctx.globalCompositeOperation = "destination-out";
    ctx.lineWidth = s.lineWidth * 4;
    ctx.beginPath();
    ctx.moveTo(s.points[0].x, s.points[0].y);
    s.points.slice(1).forEach((p) => ctx.lineTo(p.x, p.y));
    ctx.stroke();
  } else if (s.type === "pen" && s.points && s.points.length > 1) {
    ctx.beginPath();
    ctx.moveTo(s.points[0].x, s.points[0].y);
    s.points.slice(1).forEach((p) => ctx.lineTo(p.x, p.y));
    ctx.stroke();
  } else if (s.type === "highlight" && s.points && s.points.length > 1) {
    ctx.globalAlpha = 0.35;
    ctx.lineWidth = s.lineWidth * 6;
    ctx.beginPath();
    ctx.moveTo(s.points[0].x, s.points[0].y);
    s.points.slice(1).forEach((p) => ctx.lineTo(p.x, p.y));
    ctx.stroke();
  } else if (s.type === "arrow" && s.points && s.points.length === 2) {
    drawArrow(ctx, s.points[0], s.points[1], s.lineWidth);
  } else if (s.type === "line" && s.points && s.points.length === 2) {
    ctx.beginPath();
    ctx.moveTo(s.points[0].x, s.points[0].y);
    ctx.lineTo(s.points[1].x, s.points[1].y);
    ctx.stroke();
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
  } else if (s.type === "step" && s.x != null && s.y != null) {
    const r = 14;
    ctx.beginPath();
    ctx.arc(s.x!, s.y!, r, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = "#fff";
    ctx.font = `bold 16px -apple-system, BlinkMacSystemFont, sans-serif`;
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText(String(s.num ?? 1), s.x!, s.y! + 1);
  } else if (s.type === "text" && s.text && s.x != null && s.y != null) {
    ctx.font = `bold ${s.lineWidth * 6 + 12}px -apple-system, BlinkMacSystemFont, sans-serif`;
    ctx.fillText(s.text, s.x!, s.y!);
  } else if (s.type === "pixelate" && s.x != null && s.y != null) {
    // Pixelate is re-applied during redraw — handled specially in redrawBase
  }

  ctx.restore();
}

// ─────────────────────────────────────────────────────────────────────────────

export default function AnnotationCanvas({ capture, onBack, onDone, onCopy, onBackground }: Props) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const overlayRef = useRef<HTMLCanvasElement>(null);
  // Base image source — an <img> initially, becomes the cropped <canvas> after a crop
  const imgRef = useRef<CanvasImageSource | null>(null);
  const textInputRef = useRef<HTMLInputElement>(null);
  const stepCount = useRef(0); // monotonic step number (never reuses → no duplicates after crop)

  const [tool, setTool] = useState<Tool>("rect");
  const [color, setColor] = useState(COLOR_PRESETS[3]); // default blue
  const [showColors, setShowColors] = useState(false);
  const [shapes, setShapes] = useState<DrawShape[]>([]);
  const [redoStack, setRedoStack] = useState<DrawShape[]>([]);

  const [drawing, setDrawing] = useState(false);
  const [startPt, setStartPt] = useState<Point>({ x: 0, y: 0 });
  const [currentPoints, setCurrentPoints] = useState<Point[]>([]);

  const [textInput, setTextInput] = useState<{
    screenX: number;
    screenY: number;
    canvasX: number;
    canvasY: number;
  } | null>(null);
  const [textValue, setTextValue] = useState("");

  // Crop state
  const [cropRect, setCropRect] = useState<CropRect | null>(null);

  // Mirror latest values so the keydown handler can read them without re-registering
  const escState = useRef({ count: 0, typing: false });
  escState.current = { count: shapes.length, typing: textInput !== null };

  // ── Image load ─────────────────────────────────────────────────────────────

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

  // ── Redraw ─────────────────────────────────────────────────────────────────

  const redrawBase = useCallback(
    (ctx: CanvasRenderingContext2D, img: CanvasImageSource) => {
      ctx.clearRect(0, 0, ctx.canvas.width, ctx.canvas.height);
      ctx.drawImage(img, 0, 0);
      shapes.forEach((s) => {
        if (s.type === "pixelate" && s.x != null && s.y != null) {
          applyPixelate(ctx, s.x!, s.y!, s.w!, s.h!);
        } else {
          drawShape(ctx, s);
        }
      });
    },
    [shapes]
  );

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || !imgRef.current) return;
    const ctx = canvas.getContext("2d")!;
    redrawBase(ctx, imgRef.current);
  }, [shapes, redrawBase]);

  // ── Keyboard shortcuts ─────────────────────────────────────────────────────

  // Save to the configured folder (or save dialog) and finish — used by ⌘S and Done.
  const handleDone = useCallback(async () => {
    await onDone(canvasRef.current!.toDataURL("image/png"));
  }, [onDone]);

  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.metaKey && e.key === "z" && !e.shiftKey) {
        e.preventDefault();
        setShapes((prev) => {
          if (prev.length === 0) return prev;
          const popped = prev[prev.length - 1];
          setRedoStack((r) => [...r, popped]);
          return prev.slice(0, -1);
        });
      }
      if ((e.metaKey && e.shiftKey && e.key === "z") || (e.metaKey && e.key === "y")) {
        e.preventDefault();
        setRedoStack((prev) => {
          if (prev.length === 0) return prev;
          const shape = prev[prev.length - 1];
          setShapes((s) => [...s, shape]);
          return prev.slice(0, -1);
        });
      }
      if (e.metaKey && e.key === "s") {
        e.preventDefault();
        handleDone();
      }
      if (e.key === "Escape") {
        if (escState.current.typing) return; // the text input handles its own Escape
        e.preventDefault();
        if (escState.current.count > 0) {
          if (window.confirm("Go back to home? Unsaved annotations will be lost.")) onBack();
        } else {
          onBack(); // nothing drawn — no need to nag
        }
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [handleDone, onBack]);


  // ── Mouse position helper ──────────────────────────────────────────────────

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

  // ── Text commit ────────────────────────────────────────────────────────────

  function commitText(value: string, pos: { canvasX: number; canvasY: number }) {
    if (value.trim()) {
      setShapes((prev) => [
        ...prev,
        {
          type: "text",
          text: value.trim(),
          x: pos.canvasX,
          y: pos.canvasY,
          color,
          lineWidth: LINE_WIDTH,
        },
      ]);
      setRedoStack([]);
    }
    setTextInput(null);
    setTextValue("");
  }

  // ── Mouse handlers ─────────────────────────────────────────────────────────

  function onMouseDown(e: React.MouseEvent<HTMLCanvasElement>) {
    if (tool === "select") return;

    if (tool === "step") {
      const pt = getPos(e);
      const n = ++stepCount.current; // monotonic — survives crop (which bakes prior steps in)
      setShapes((prev) => [
        ...prev,
        { type: "step", x: pt.x, y: pt.y, num: n, color, lineWidth: LINE_WIDTH },
      ]);
      setRedoStack([]);
      return;
    }

    if (tool === "text") {
      const pt = getPos(e);
      const overlay = overlayRef.current!;
      const rect = overlay.getBoundingClientRect();
      setTextInput({
        screenX: e.clientX - rect.left,
        screenY: e.clientY - rect.top,
        canvasX: pt.x,
        canvasY: pt.y,
      });
      setTextValue("");
      setTimeout(() => textInputRef.current?.focus(), 0);
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

    if (tool === "eraser" || tool === "pen" || tool === "highlight") {
      setCurrentPoints((prev) => {
        const updated = [...prev, pt];
        ctx.save();
        if (tool === "eraser") {
          ctx.strokeStyle = "rgba(255,100,100,0.5)";
          ctx.lineWidth = LINE_WIDTH * 4;
        } else if (tool === "highlight") {
          ctx.strokeStyle = color;
          ctx.globalAlpha = 0.35;
          ctx.lineWidth = LINE_WIDTH * 6;
        } else {
          ctx.strokeStyle = color;
          ctx.lineWidth = LINE_WIDTH;
        }
        ctx.lineJoin = "round";
        ctx.lineCap = "round";
        ctx.beginPath();
        ctx.moveTo(updated[0].x, updated[0].y);
        updated.slice(1).forEach((p) => ctx.lineTo(p.x, p.y));
        ctx.stroke();
        ctx.restore();
        return updated;
      });
    } else if (tool === "arrow") {
      ctx.save();
      ctx.strokeStyle = color;
      ctx.lineWidth = LINE_WIDTH;
      ctx.lineJoin = "round";
      ctx.lineCap = "round";
      drawArrow(ctx, startPt, pt, LINE_WIDTH);
      ctx.restore();
    } else if (tool === "line") {
      ctx.save();
      ctx.strokeStyle = color;
      ctx.lineWidth = LINE_WIDTH;
      ctx.lineCap = "round";
      ctx.beginPath();
      ctx.moveTo(startPt.x, startPt.y);
      ctx.lineTo(pt.x, pt.y);
      ctx.stroke();
      ctx.restore();
    } else if (tool === "rect") {
      ctx.save();
      ctx.strokeStyle = color;
      ctx.lineWidth = LINE_WIDTH;
      ctx.lineJoin = "round";
      ctx.lineCap = "round";
      ctx.strokeRect(startPt.x, startPt.y, pt.x - startPt.x, pt.y - startPt.y);
      ctx.restore();
    } else if (tool === "ellipse") {
      ctx.save();
      ctx.strokeStyle = color;
      ctx.lineWidth = LINE_WIDTH;
      const ex = Math.min(startPt.x, pt.x);
      const ey = Math.min(startPt.y, pt.y);
      const ew = Math.abs(pt.x - startPt.x);
      const eh = Math.abs(pt.y - startPt.y);
      ctx.beginPath();
      ctx.ellipse(ex + ew / 2, ey + eh / 2, ew / 2, eh / 2, 0, 0, Math.PI * 2);
      ctx.stroke();
      ctx.restore();
    } else if (tool === "pixelate" || tool === "crop") {
      // Draw a dashed rectangle preview
      ctx.save();
      ctx.strokeStyle = tool === "crop" ? "#fff" : "rgba(255,255,255,0.7)";
      ctx.lineWidth = 1.5;
      ctx.setLineDash([6, 4]);
      ctx.strokeRect(startPt.x, startPt.y, pt.x - startPt.x, pt.y - startPt.y);
      ctx.restore();
    }
  }

  function onMouseUp(e: React.MouseEvent<HTMLCanvasElement>) {
    if (!drawing) return;
    setDrawing(false);
    const pt = getPos(e);
    const overlay = overlayRef.current!;
    overlay.getContext("2d")!.clearRect(0, 0, overlay.width, overlay.height);

    const x = Math.min(startPt.x, pt.x);
    const y = Math.min(startPt.y, pt.y);
    const w = Math.abs(pt.x - startPt.x);
    const h = Math.abs(pt.y - startPt.y);

    if (tool === "eraser" || tool === "pen" || tool === "highlight") {
      if (currentPoints.length > 1) {
        setShapes((prev) => [
          ...prev,
          { type: tool, points: currentPoints, color, lineWidth: LINE_WIDTH },
        ]);
        setRedoStack([]);
      }
    } else if (tool === "arrow") {
      if (w > 3 || h > 3) {
        setShapes((prev) => [
          ...prev,
          { type: "arrow", points: [startPt, pt], color, lineWidth: LINE_WIDTH },
        ]);
        setRedoStack([]);
      }
    } else if (tool === "line") {
      if (w > 3 || h > 3) {
        setShapes((prev) => [
          ...prev,
          { type: "line", points: [startPt, pt], color, lineWidth: LINE_WIDTH },
        ]);
        setRedoStack([]);
      }
    } else if (tool === "rect") {
      if (w > 3 || h > 3) {
        setShapes((prev) => [
          ...prev,
          { type: "rect", x, y, w, h, color, lineWidth: LINE_WIDTH },
        ]);
        setRedoStack([]);
      }
    } else if (tool === "ellipse") {
      if (w > 3 && h > 3) {
        setShapes((prev) => [
          ...prev,
          { type: "ellipse", x, y, w, h, color, lineWidth: LINE_WIDTH },
        ]);
        setRedoStack([]);
      }
    } else if (tool === "pixelate") {
      if (w > 3 && h > 3) {
        // Apply pixelation directly to main canvas and store as shape for redo
        const canvas = canvasRef.current!;
        const ctx = canvas.getContext("2d")!;
        applyPixelate(ctx, x, y, w, h);
        setShapes((prev) => [
          ...prev,
          { type: "pixelate", x, y, w, h, color, lineWidth: LINE_WIDTH },
        ]);
        setRedoStack([]);
      }
    } else if (tool === "crop") {
      if (w > 10 && h > 10) {
        setCropRect({ x, y, w, h });
      }
    }

    setCurrentPoints([]);
  }

  // ── Crop apply ─────────────────────────────────────────────────────────────

  function applyCrop() {
    if (!cropRect) return;
    const canvas = canvasRef.current!;
    const ctx = canvas.getContext("2d")!;

    const { x, y, w, h } = cropRect;
    const offscreen = document.createElement("canvas");
    offscreen.width = w;
    offscreen.height = h;
    const offCtx = offscreen.getContext("2d")!;
    offCtx.drawImage(canvas, x, y, w, h, 0, 0, w, h);

    canvas.width = w;
    canvas.height = h;
    if (overlayRef.current) {
      overlayRef.current.width = w;
      overlayRef.current.height = h;
    }
    ctx.drawImage(offscreen, 0, 0);

    // Swap the base image to the cropped canvas SYNCHRONOUSLY so the redraw effect (fired by
    // setShapes below) paints the cropped pixels — not the old full-size image. (The previous
    // async newImg.onload set imgRef too late, leaving the canvas showing the wrong image.)
    imgRef.current = offscreen;

    // Clear shapes since they are baked in
    setShapes([]);
    setRedoStack([]);
    setCropRect(null);
    setTool("rect");
  }

  // ── Copy / Done ────────────────────────────────────────────────────────────

  async function handleCopy() {
    await onCopy(canvasRef.current!.toDataURL("image/png"));
  }

  // ── Cursor ────────────────────────────────────────────────────────────────

  function getCursor(): string {
    if (tool === "select") return "default";
    if (tool === "text") return "text";
    if (tool === "eraser") return "cell";
    return "crosshair";
  }

  // ── Toolbar button style helpers ──────────────────────────────────────────

  function toolBtnStyle(active: boolean): React.CSSProperties {
    return {
      width: 30,
      height: 30,
      borderRadius: 6,
      border: "none",
      background: active ? "rgba(255,255,255,0.18)" : "transparent",
      color: active ? "#fff" : "rgba(255,255,255,0.55)",
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      cursor: "pointer",
      flexShrink: 0,
    };
  }

  const sepStyle: React.CSSProperties = {
    width: 1,
    height: 20,
    background: "rgba(255,255,255,0.12)",
    margin: "0 4px",
    flexShrink: 0,
  };

  // ─────────────────────────────────────────────────────────────────────────────
  // Render
  // ─────────────────────────────────────────────────────────────────────────────

  const toolDefs: { key: Tool; icon: React.ReactNode; label: string }[] = [
    { key: "select", icon: <MousePointer2 size={15} />, label: "Select" },
    { key: "rect", icon: <Square size={15} />, label: "Rectangle" },
    { key: "ellipse", icon: <Circle size={15} />, label: "Ellipse" },
    { key: "arrow", icon: <ArrowRight size={15} />, label: "Arrow" },
    { key: "line", icon: <Minus size={15} />, label: "Line" },
    { key: "text", icon: <Type size={15} />, label: "Text" },
    { key: "pen", icon: <PenTool size={15} />, label: "Pen" },
    { key: "highlight", icon: <Highlighter size={15} />, label: "Highlighter" },
    { key: "pixelate", icon: <Grid2x2 size={15} />, label: "Pixelate" },
    { key: "step", icon: <ListOrdered size={15} />, label: "Step number" },
    { key: "eraser", icon: <Eraser size={15} />, label: "Eraser" },
  ];

  return (
    <div
      style={{
        position: "relative",
        background: "#111",
        flex: 1,
        overflow: "hidden",
        display: "flex",
        flexDirection: "column",
      }}
    >
      {/* ── Floating pill toolbar ─────────────────────────────────────────── */}
      <div
        style={{
          position: "absolute",
          top: 16,
          left: "50%",
          transform: "translateX(-50%)",
          zIndex: 100,
          background: "rgba(30,30,32,0.88)",
          backdropFilter: "blur(16px)",
          WebkitBackdropFilter: "blur(16px)",
          border: "1px solid rgba(255,255,255,0.12)",
          borderRadius: 999,
          padding: "4px 8px",
          display: "flex",
          alignItems: "center",
          gap: 2,
          fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
          whiteSpace: "nowrap",
        }}
      >
        {cropRect ? (
          // ── Crop confirmation mode ──────────────────────────────────────
          <>
            <span
              style={{
                fontSize: 12,
                color: "rgba(255,255,255,0.6)",
                padding: "0 8px",
              }}
            >
              Crop selection
            </span>
            <div style={sepStyle} />
            <button
              onClick={() => { setCropRect(null); setTool("rect"); }}
              style={{
                padding: "4px 12px",
                borderRadius: 6,
                background: "rgba(255,255,255,0.10)",
                border: "1px solid rgba(255,255,255,0.15)",
                fontSize: 12,
                fontWeight: 500,
                color: "rgba(255,255,255,0.85)",
                cursor: "pointer",
              }}
            >
              Cancel
            </button>
            <button
              onClick={applyCrop}
              style={{
                padding: "4px 12px",
                borderRadius: 6,
                background: "#32D74B",
                border: "none",
                fontSize: 12,
                fontWeight: 600,
                color: "#000",
                cursor: "pointer",
              }}
            >
              Apply Crop
            </button>
          </>
        ) : (
          // ── Normal toolbar ──────────────────────────────────────────────
          <>
            {/* Tools group 1: select → pixelate */}
            {toolDefs.map(({ key, icon, label }) => (
              <button
                key={key}
                title={label}
                onClick={() => setTool(key)}
                style={toolBtnStyle(tool === key)}
              >
                {icon}
              </button>
            ))}

            {/* Color picker */}
            <div style={{ position: "relative" }}>
              <button
                title="Color"
                onClick={() => setShowColors((v) => !v)}
                style={{
                  width: 30,
                  height: 30,
                  borderRadius: 6,
                  border: "none",
                  background: "transparent",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  cursor: "pointer",
                  flexShrink: 0,
                }}
              >
                <div
                  style={{
                    width: 14,
                    height: 14,
                    borderRadius: "50%",
                    background: color,
                    border: "2px solid rgba(255,255,255,0.3)",
                    flexShrink: 0,
                  }}
                />
              </button>
              {showColors && (
                <div
                  style={{
                    position: "absolute",
                    top: "calc(100% + 10px)",
                    left: "50%",
                    transform: "translateX(-50%)",
                    background: "rgba(36,36,40,0.97)",
                    backdropFilter: "blur(16px)",
                    WebkitBackdropFilter: "blur(16px)",
                    border: "1px solid rgba(255,255,255,0.14)",
                    borderRadius: 10,
                    padding: 10,
                    display: "flex",
                    flexDirection: "column",
                    gap: 8,
                    zIndex: 200,
                    boxShadow: "0 8px 32px rgba(0,0,0,0.5)",
                  }}
                >
                  <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 6 }}>
                    {COLOR_PRESETS.map((c) => (
                      <button
                        key={c}
                        title={c}
                        onClick={() => { setColor(c); setShowColors(false); }}
                        style={{
                          width: 22,
                          height: 22,
                          borderRadius: "50%",
                          background: c,
                          cursor: "pointer",
                          padding: 0,
                          border: color.toLowerCase() === c.toLowerCase()
                            ? "2px solid #fff"
                            : "2px solid rgba(255,255,255,0.2)",
                        }}
                      />
                    ))}
                  </div>
                  <label
                    style={{
                      display: "flex",
                      alignItems: "center",
                      gap: 6,
                      fontSize: 11,
                      color: "rgba(255,255,255,0.6)",
                      cursor: "pointer",
                    }}
                  >
                    <input
                      type="color"
                      value={color}
                      onChange={(e) => setColor(e.target.value)}
                      style={{
                        width: 24,
                        height: 24,
                        border: "none",
                        background: "none",
                        cursor: "pointer",
                        padding: 0,
                      }}
                    />
                    Custom color
                  </label>
                </div>
              )}
            </div>

            <div style={sepStyle} />

            {/* Crop tool */}
            <button
              title="Crop"
              onClick={() => setTool("crop")}
              style={toolBtnStyle(tool === "crop")}
            >
              <Crop size={15} />
            </button>

            <div style={sepStyle} />

            {/* Undo */}
            <button
              title="Undo (⌘Z)"
              onClick={() => {
                setShapes((prev) => {
                  if (prev.length === 0) return prev;
                  const popped = prev[prev.length - 1];
                  setRedoStack((r) => [...r, popped]);
                  return prev.slice(0, -1);
                });
              }}
              disabled={shapes.length === 0}
              style={{
                ...toolBtnStyle(false),
                opacity: shapes.length === 0 ? 0.3 : 1,
              }}
            >
              <RotateCcw size={15} />
            </button>

            {/* Redo */}
            <button
              title="Redo (⌘⇧Z)"
              onClick={() => {
                setRedoStack((prev) => {
                  if (prev.length === 0) return prev;
                  const shape = prev[prev.length - 1];
                  setShapes((s) => [...s, shape]);
                  return prev.slice(0, -1);
                });
              }}
              disabled={redoStack.length === 0}
              style={{
                ...toolBtnStyle(false),
                opacity: redoStack.length === 0 ? 0.3 : 1,
              }}
            >
              <RotateCw size={15} />
            </button>

            <div style={sepStyle} />

            {/* Background — drop the annotated image onto a gradient/custom backdrop */}
            <button
              title="Add a background (gradient or your own image)"
              onClick={() => onBackground(canvasRef.current!.toDataURL("image/png"))}
              style={toolBtnStyle(false)}
            >
              <ImageIcon size={15} />
            </button>

            {/* Copy */}
            <button
              title="Copy to clipboard (⌘C)"
              onClick={handleCopy}
              className="press"
              style={{
                padding: "4px 12px",
                borderRadius: 6,
                background: "rgba(255,255,255,0.10)",
                border: "1px solid rgba(255,255,255,0.15)",
                fontSize: 12,
                fontWeight: 500,
                color: "rgba(255,255,255,0.85)",
                cursor: "pointer",
              }}
            >
              Copy
            </button>

            <div style={sepStyle} />

            {/* Done — saves to folder & finishes */}
            <button
              title="Save & finish — auto-saves to your folder or Desktop (⌘S)"
              onClick={handleDone}
              className="press"
              style={{
                padding: "4px 12px",
                borderRadius: 6,
                background: "#32D74B",
                border: "none",
                fontSize: 12,
                fontWeight: 600,
                color: "#000",
                cursor: "pointer",
              }}
            >
              ✓ Done
            </button>
          </>
        )}
      </div>

      {/* ── Canvas scroll area ──────────────────────────────────────────────── */}
      <div
        style={{
          width: "100%",
          height: "100%",
          overflow: "auto",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          padding: "80px 24px 24px",
          boxSizing: "border-box",
        }}
      >
        <div style={{ position: "relative" }}>
          {/* Main canvas */}
          <canvas
            ref={canvasRef}
            style={{
              display: "block",
              maxWidth: "100%",
              boxShadow: "0 8px 48px rgba(0,0,0,0.6)",
            }}
          />

          {/* Overlay canvas — receives mouse events */}
          <canvas
            ref={overlayRef}
            onMouseDown={onMouseDown}
            onMouseMove={onMouseMove}
            onMouseUp={onMouseUp}
            onMouseLeave={(e) => {
              if (drawing) onMouseUp(e);
            }}
            style={{
              position: "absolute",
              inset: 0,
              width: "100%",
              height: "100%",
              cursor: getCursor(),
            }}
          />

          {/* Crop overlay — darkened region outside selection */}
          {cropRect && (
            <>
              {/* Dark overlay — rendered as 4 rects around the crop area */}
              {(() => {
                const canvas = canvasRef.current;
                if (!canvas) return null;
                const cw = canvas.width;
                const ch = canvas.height;
                const { x, y, w, h } = cropRect;

                // We render the overlay as a single absolutely-positioned div
                // with clip-path that "punches a hole" in the crop area.
                return (
                  <div
                    style={{
                      position: "absolute",
                      inset: 0,
                      pointerEvents: "none",
                      zIndex: 5,
                    }}
                  >
                    <svg
                      width="100%"
                      height="100%"
                      viewBox={`0 0 ${cw} ${ch}`}
                      preserveAspectRatio="none"
                      style={{ position: "absolute", inset: 0 }}
                    >
                      <defs>
                        <mask id="cropHole">
                          <rect width={cw} height={ch} fill="white" />
                          <rect x={x} y={y} width={w} height={h} fill="black" />
                        </mask>
                      </defs>
                      <rect
                        width={cw}
                        height={ch}
                        fill="rgba(0,0,0,0.5)"
                        mask="url(#cropHole)"
                      />
                      {/* Crop border */}
                      <rect
                        x={x}
                        y={y}
                        width={w}
                        height={h}
                        fill="none"
                        stroke="rgba(255,255,255,0.8)"
                        strokeWidth={1}
                        strokeDasharray="6 4"
                      />
                    </svg>

                    {/* Corner handles */}
                    {[
                      { cx: x, cy: y },
                      { cx: x + w, cy: y },
                      { cx: x, cy: y + h },
                      { cx: x + w, cy: y + h },
                    ].map((corner, i) => {
                      // Convert canvas coords to percentage-based position
                      const canvas = canvasRef.current!;
                      const pctX = (corner.cx / canvas.width) * 100;
                      const pctY = (corner.cy / canvas.height) * 100;
                      return (
                        <div
                          key={i}
                          style={{
                            position: "absolute",
                            left: `${pctX}%`,
                            top: `${pctY}%`,
                            width: 8,
                            height: 8,
                            borderRadius: "50%",
                            background: "#fff",
                            transform: "translate(-50%, -50%)",
                            boxShadow: "0 0 0 1.5px rgba(0,0,0,0.4)",
                          }}
                        />
                      );
                    })}
                  </div>
                );
              })()}
            </>
          )}

          {/* Inline text input */}
          {textInput && (
            <input
              ref={textInputRef}
              value={textValue}
              onChange={(e) => setTextValue(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  e.preventDefault();
                  commitText(textValue, textInput);
                }
                if (e.key === "Escape") {
                  setTextInput(null);
                  setTextValue("");
                }
              }}
              onBlur={() => commitText(textValue, textInput)}
              style={{
                position: "absolute",
                left: textInput.screenX,
                top: textInput.screenY - 2,
                minWidth: 120,
                maxWidth: 400,
                background: "rgba(0,0,0,0.55)",
                backdropFilter: "blur(8px)",
                border: `2px solid ${color}`,
                borderRadius: 4,
                color,
                fontSize: Math.max(12, LINE_WIDTH * 4),
                fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
                fontWeight: 600,
                padding: "2px 6px",
                outline: "none",
                zIndex: 20,
                letterSpacing: "-0.01em",
              }}
              placeholder="Type & press Enter"
            />
          )}
        </div>
      </div>
    </div>
  );
}
