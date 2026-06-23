import { useEffect, useRef, useState } from "react";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { listen } from "@tauri-apps/api/event";
import { invoke } from "@tauri-apps/api/core";

interface Rect { x: number; y: number; w: number; h: number; }

function norm(x1: number, y1: number, x2: number, y2: number): Rect {
  return { x: Math.min(x1, x2), y: Math.min(y1, y2), w: Math.abs(x2 - x1), h: Math.abs(y2 - y1) };
}

export default function CaptureSelector() {
  const [rect, setRect] = useState<Rect | null>(null);
  const [cursor, setCursor] = useState<"crosshair" | "default">("crosshair");
  const [cursorPos, setCursorPos] = useState<{ x: number; y: number } | null>(null);
  const dragging = useRef(false);
  const fired = useRef(false); // prevent double-fire on mouseup
  const start = useRef({ x: 0, y: 0 });
  const windowOffset = useRef({ x: 0, y: 0 });
  const activationId = useRef(0);
  const captureId = useRef(0);
  const offsetPromise = useRef<Promise<void> | null>(null);

  function readOffset(id = activationId.current) {
    const task = getCurrentWindow()
      .outerPosition()
      .then((pos) => {
        if (activationId.current !== id) return;
        const sf = window.devicePixelRatio || 1;
        windowOffset.current = { x: pos.x / sf, y: pos.y / sf };
      })
      .catch(() => {});
    offsetPromise.current = task;
    return task;
  }

  // Clear all drag state + restore the crosshair, THEN reveal the window. The window is shown
  // here (not by Rust) so it never composites the previous selection — same pattern as the popup.
  async function resetState(id = ++activationId.current) {
    dragging.current = false;
    fired.current = false;
    setRect(null);
    setCursor("crosshair");
    const nextOffset = readOffset(id);
    const w = getCurrentWindow();
    // Show directly — do NOT await requestAnimationFrame: rAF never fires while the window is
    // hidden, so awaiting it here meant show() was never reached and the overlay never appeared.
    if (activationId.current !== id) return;
    await w.show();
    if (activationId.current !== id) return;
    await Promise.allSettled([nextOffset, w.setFocus()]);
    // No native cursor call here: the OS crosshair is unreliable on the shortcut path (it only
    // repaints for the key window on a mouse move). We hide the OS cursor and draw our own
    // crosshair instead — see the render below — so it's always visible immediately.
  }

  // Reset the cursor to the arrow BEFORE hiding so macOS doesn't leave the crosshair "stuck".
  async function dismiss() {
    activationId.current += 1;
    dragging.current = false;
    fired.current = false;
    setRect(null);
    setCursor("default");
    setCursorPos(null);
    await getCurrentWindow().hide();
  }

  useEffect(() => {
    document.body.classList.add("overlay-window");
    document.documentElement.style.background = "transparent";

    // ESC → cancel: clear state + reset cursor, then hide (window is persistent)
    function onKeyDown(e: KeyboardEvent) {
      if (e.key === "Escape") dismiss();
    }
    document.addEventListener("keydown", onKeyDown);

    readOffset();

    // Each time Rust shows the persistent selector it emits this — reset drag state + refocus
    let unlisten: (() => void) | undefined;
    listen<{ captureId: number; cursorX: number; cursorY: number }>("selector-activate", (event) => {
      captureId.current = event.payload.captureId;
      // Seed the crosshair at the current cursor position so it's drawn correctly the instant
      // the overlay shows — before any pointermove (which may never come on the shortcut path).
      setCursorPos({ x: event.payload.cursorX, y: event.payload.cursorY });
      void resetState();
    }).then((fn) => { unlisten = fn; });

    return () => {
      document.removeEventListener("keydown", onKeyDown);
      unlisten?.();
    };
  }, []);

  function onMouseDown(e: React.MouseEvent) {
    e.preventDefault();
    dragging.current = true;
    fired.current = false;
    start.current = { x: e.clientX, y: e.clientY };
    setRect({ x: e.clientX, y: e.clientY, w: 0, h: 0 });
  }

  function onMouseMove(e: React.MouseEvent) {
    if (!dragging.current) return;
    setRect(norm(start.current.x, start.current.y, e.clientX, e.clientY));
  }

  // Track the pointer to drive the self-drawn crosshair (works whether or not we're dragging).
  function onPointerMove(e: React.PointerEvent) {
    setCursorPos({ x: e.clientX, y: e.clientY });
  }

  async function onMouseUp(e: React.MouseEvent) {
    if (!dragging.current || fired.current) return;
    dragging.current = false;
    fired.current = true;

    const r = norm(start.current.x, start.current.y, e.clientX, e.clientY);
    if (r.w < 10 || r.h < 10) {
      setRect(null);
      fired.current = false;
      return;
    }

    await offsetPromise.current?.catch(() => {});
    const off = windowOffset.current;
    const dpr = window.devicePixelRatio || 1;

    // Clear the selection + restore cursor BEFORE the window goes away, so nothing residual
    // remains for the next show and the crosshair doesn't stick.
    setRect(null);
    setCursor("default");
    setCursorPos(null);
    const hideWindow = getCurrentWindow().hide().catch(() => {});

    // Rust hides the selector, waits, then screenshots + crops.
    invoke("capture_region_and_crop", {
      captureId: captureId.current,
      x: Math.round(r.x + off.x),
      y: Math.round(r.y + off.y),
      w: Math.round(r.w),
      h: Math.round(r.h),
      dpr,
    }).catch(() => {});
    await hideWindow;
  }

  // Pointer left the overlay mid-drag (e.g. multi-monitor) — abort the drag so it doesn't stick.
  function onMouseLeave() {
    if (dragging.current) {
      dragging.current = false;
      fired.current = false;
      setRect(null);
    }
  }

  const sw = window.innerWidth;
  const sh = window.innerHeight;
  const AMBER = "#FF9F0A";

  // Dimension badge placement
  let badge: { top: number; left: number } | null = null;
  if (rect && rect.w >= 20 && rect.h >= 20) {
    let bx = rect.x + rect.w + 10;
    let by = rect.y + rect.h + 10;
    if (bx + 90 > sw - 8) bx = rect.x + rect.w - 96;
    if (by + 26 > sh - 8) by = rect.y - 34;
    badge = { top: by, left: bx };
  }

  return (
    <div
      onMouseDown={onMouseDown}
      onMouseMove={onMouseMove}
      onMouseUp={onMouseUp}
      onMouseLeave={onMouseLeave}
      onPointerMove={onPointerMove}
      style={{
        position: "fixed", inset: 0,
        cursor: cursor === "crosshair" ? "none" : "default", // hide OS arrow; we draw our own crosshair
        userSelect: "none", WebkitUserSelect: "none",
        overflow: "hidden",
        fontFamily: "-apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif",
      }}
    >
      {/* Compact ring + center dot reticle at the pointer (camera-focus style). Self-drawn so
          it's reliable (unlike the OS cursor) and branded amber. */}
      {cursorPos && !rect && (
        <div style={{
          position: "absolute", left: cursorPos.x, top: cursorPos.y,
          width: 16, height: 16, transform: "translate(-50%, -50%)", pointerEvents: "none",
        }}>
          <div style={{
            position: "absolute", inset: 0, borderRadius: "50%",
            border: `1px solid ${AMBER}`,
            boxShadow: "0 0 0 0.5px rgba(0,0,0,0.5), inset 0 0 0 0.5px rgba(0,0,0,0.4)",
          }} />
          <div style={{
            position: "absolute", left: "50%", top: "50%", width: 2.5, height: 2.5,
            marginLeft: -1.25, marginTop: -1.25, borderRadius: "50%", background: AMBER,
          }} />
        </div>
      )}

      {/* Helper hint — shows before a selection is drawn, disappears once dragging. */}
      {!rect && (
        <div style={{
          position: "absolute", top: 28, left: "50%", transform: "translateX(-50%)",
          background: "rgba(20,20,22,0.66)", backdropFilter: "blur(12px)", WebkitBackdropFilter: "blur(12px)",
          borderRadius: 9, padding: "7px 14px", color: "rgba(255,255,255,0.92)",
          fontSize: 12.5, fontWeight: 500, whiteSpace: "nowrap", pointerEvents: "none",
          boxShadow: "0 6px 20px rgba(0,0,0,0.4)", border: "1px solid rgba(255,255,255,0.10)",
        }}>
          Drag to capture an area&nbsp;&nbsp;<span style={{ opacity: 0.55 }}>Esc to cancel</span>
        </div>
      )}
      {rect && rect.w > 2 && rect.h > 2 && (
        <>
          {/* Subtle tint outside selection */}
          <div style={{ position: "absolute", top: 0, left: 0, width: sw, height: rect.y, background: "rgba(0,0,0,0.32)", pointerEvents: "none" }} />
          <div style={{ position: "absolute", top: rect.y + rect.h, left: 0, width: sw, height: sh - rect.y - rect.h, background: "rgba(0,0,0,0.32)", pointerEvents: "none" }} />
          <div style={{ position: "absolute", top: rect.y, left: 0, width: rect.x, height: rect.h, background: "rgba(0,0,0,0.32)", pointerEvents: "none" }} />
          <div style={{ position: "absolute", top: rect.y, left: rect.x + rect.w, width: sw - rect.x - rect.w, height: rect.h, background: "rgba(0,0,0,0.32)", pointerEvents: "none" }} />

          {/* Amber selection border */}
          <div style={{
            position: "absolute", top: rect.y, left: rect.x, width: rect.w, height: rect.h,
            border: `1.5px solid ${AMBER}`,
            boxShadow: `0 0 0 1px rgba(0,0,0,0.35)`,
            boxSizing: "border-box", pointerEvents: "none",
          }} />

          {/* Corner handles */}
          {[
            { top: rect.y - 4, left: rect.x - 4 },
            { top: rect.y - 4, left: rect.x + rect.w - 3 },
            { top: rect.y + rect.h - 3, left: rect.x - 4 },
            { top: rect.y + rect.h - 3, left: rect.x + rect.w - 3 },
          ].map((pos, i) => (
            <div key={i} style={{
              position: "absolute", ...pos, width: 7, height: 7,
              background: AMBER, borderRadius: 2, pointerEvents: "none",
              boxShadow: "0 1px 4px rgba(0,0,0,0.5)",
            }} />
          ))}

          {/* Dimension badge */}
          {badge && (
            <div style={{
              position: "absolute", top: badge.top, left: badge.left,
              background: "rgba(0,0,0,0.65)",
              backdropFilter: "blur(10px)", WebkitBackdropFilter: "blur(10px)",
              borderRadius: 5, padding: "3px 8px",
              color: "rgba(255,255,255,0.88)", fontSize: 11, fontWeight: 500,
              fontFamily: "'SF Mono', 'Menlo', monospace",
              whiteSpace: "nowrap", pointerEvents: "none",
              boxShadow: "0 2px 6px rgba(0,0,0,0.4)",
            }}>
              {Math.round(rect.w)} × {Math.round(rect.h)}
            </div>
          )}
        </>
      )}
    </div>
  );
}
