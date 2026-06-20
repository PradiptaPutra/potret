import { useState, useEffect, useRef } from "react";
import { invoke } from "@tauri-apps/api/core";
import { emit, listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { startDrag } from "@crabnebula/tauri-plugin-drag";
import { Copy, Download, Pencil, Layers, X, Check } from "lucide-react";

interface CaptureInfo {
  captureId: number;
  data: string;   // base64 PNG thumbnail (inline data URL — reliable in dev + prod)
  width: number;
  height: number;
}

const WIN_W = 320;
const AUTO_DISMISS_MS = 12000;

export default function CapturePopupWindow() {
  const [capture, setCapture] = useState<CaptureInfo | null>(null);
  const [pending, setPending] = useState(false);
  const [progress, setProgress] = useState(1);
  const [paused, setPaused] = useState(false);
  const [shellHeight, setShellHeight] = useState(200);
  const [feedback, setFeedback] = useState<{ msg: string; ok: boolean } | null>(null);
  const startRef = useRef(Date.now());
  const pausedAtRef = useRef<number | null>(null);
  const rafRef = useRef<number | null>(null);
  const fbTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const pendingRef = useRef(false);
  const pendingCaptureIdRef = useRef(0);
  const latestCaptureIdRef = useRef(0);
  const mountedRef = useRef(true);
  const decodeTokenRef = useRef(0);

  function getImageHeight(info: CaptureInfo | null) {
    if (!info) return shellHeight;
    return Math.min(Math.max(Math.round(WIN_W * info.height / info.width), 120), 260);
  }

  function showWindow() {
    const w = getCurrentWindow();
    void w.show();
    void w.setFocus();
  }

  function resetDismissTimer() {
    startRef.current = Date.now();
    pausedAtRef.current = null;
    setProgress(1);
    setPaused(false);
  }

  function startPending(captureId: number, nextCapture?: CaptureInfo | null) {
    pendingCaptureIdRef.current = captureId;
    pendingRef.current = true;
    setPending(true);
    setCapture(null);
    setShellHeight(getImageHeight(nextCapture ?? capture));
    resetDismissTimer();
  }

  function commitCapture(info: CaptureInfo, reveal: boolean) {
    const token = ++decodeTokenRef.current;
    const nextShellHeight = getImageHeight(info);
    const src = `data:image/png;base64,${info.data}`;
    const finalize = () => {
      if (
        !mountedRef.current ||
        token !== decodeTokenRef.current ||
        info.captureId !== latestCaptureIdRef.current
      ) return;
      setShellHeight(nextShellHeight);
      setCapture(info);
      pendingRef.current = false;
      setPending(false);
      resetDismissTimer();
      if (reveal) showWindow();
    };

    setShellHeight(nextShellHeight);

    const im = new Image();
    if (typeof im.decode === "function") {
      im.src = src;
      im.decode().then(finalize).catch(finalize);
      return;
    }
    im.onload = finalize;
    im.onerror = finalize;
    im.src = src;
  }

  useEffect(() => {
    document.body.classList.add("overlay-window");
    document.documentElement.style.background = "transparent";
    return () => {
      mountedRef.current = false;
      decodeTokenRef.current += 1;
      if (fbTimer.current) clearTimeout(fbTimer.current);
    };
  }, []);

  useEffect(() => {
    let unlisten: (() => void) | undefined;
    let unlistenPending: (() => void) | undefined;
    let unlistenInvalidated: (() => void) | undefined;

    listen<{ captureId: number }>("popup-invalidated", (event) => {
      const captureId = event.payload.captureId;
      if (captureId < latestCaptureIdRef.current) return;
      latestCaptureIdRef.current = captureId;
      decodeTokenRef.current += 1;
      pendingCaptureIdRef.current = captureId;
      pendingRef.current = false;
      setPending(false);
      setCapture(null);
    }).then(fn => { unlistenInvalidated = fn; });

    listen<{ captureId: number }>("popup-pending", (event) => {
      const captureId = event.payload.captureId;
      if (captureId < latestCaptureIdRef.current) return;
      latestCaptureIdRef.current = captureId;
      decodeTokenRef.current += 1;
      startPending(captureId);
      showWindow();
    }).then(fn => { unlistenPending = fn; });

    listen<CaptureInfo>("popup-refreshed", (event) => {
      const info = event.payload;
      if (!info || info.captureId < latestCaptureIdRef.current) return;
      const wasPending = pendingRef.current && pendingCaptureIdRef.current === info.captureId;
      latestCaptureIdRef.current = info.captureId;
      startPending(info.captureId, info);
      commitCapture(info, !wasPending);
    }).then(fn => { unlisten = fn; });

    invoke<CaptureInfo | null>("get_capture_popup_data").then((info) => {
      if (!info || info.captureId < latestCaptureIdRef.current) return;
      latestCaptureIdRef.current = info.captureId;
      startPending(info.captureId, info);
      commitCapture(info, false);
    });
    return () => {
      unlisten?.();
      unlistenPending?.();
      unlistenInvalidated?.();
    };
  }, []);

  useEffect(() => {
    if (!capture) return;
    function tick() {
      if (!paused) {
        const elapsed =
          pausedAtRef.current != null
            ? pausedAtRef.current - startRef.current
            : Date.now() - startRef.current;
        const p = Math.max(0, 1 - elapsed / AUTO_DISMISS_MS);
        setProgress(p);
        if (p <= 0) { dismiss(); return; }
      }
      rafRef.current = requestAnimationFrame(tick);
    }
    rafRef.current = requestAnimationFrame(tick);
    return () => { if (rafRef.current) cancelAnimationFrame(rafRef.current); };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [capture, paused]);

  function handleMouseEnter() {
    setPaused(true);
    pausedAtRef.current = Date.now();
  }
  function handleMouseLeave() {
    if (pausedAtRef.current != null) {
      startRef.current += Date.now() - pausedAtRef.current;
      pausedAtRef.current = null;
    }
    setPaused(false);
  }

  function flash(msg: string, ok = true) {
    setFeedback({ msg, ok });
    if (fbTimer.current) clearTimeout(fbTimer.current);
    fbTimer.current = setTimeout(() => setFeedback(null), 1800);
  }

  function dismiss() {
    if (!capture) return;
    void invoke("close_capture_popup", { captureId: capture.captureId });
  }

  async function handleCopy() {
    if (!capture) return;
    const full = await invoke<string | null>("get_capture_full_data", { captureId: capture.captureId });
    if (!full) return;
    await invoke("copy_to_clipboard", { data: full });
    flash("Copied!");
  }

  async function handleSave() {
    try {
      if (!capture) return;
      await invoke<string>("quick_save_capture", { captureId: capture.captureId });
      flash("Saved!");
    } catch {
      flash("Set a save folder in Settings", false);
    }
  }

  async function handleDragOut(e: React.DragEvent) {
    e.preventDefault(); // cancel the HTML5 drag; use a native OS file drag instead
    setPaused(true); // hold the auto-dismiss timer during the drag
    try {
      if (!capture) return;
      const path = await invoke<string>("stage_capture_for_drag", { captureId: capture.captureId });
      await startDrag({ item: [path], icon: path });
    } catch (err) {
      console.error(err);
    }
  }

  async function handleEdit() {
    if (!capture) return;
    await invoke("open_main_for_edit");
    await emit("capture-edit-requested", { captureId: capture.captureId });
    getCurrentWindow().hide(); // persistent window — hide, don't destroy
  }

  async function handleBackground() {
    if (!capture) return;
    await invoke("open_main_for_edit");
    await emit("capture-background-requested", { captureId: capture.captureId });
    getCurrentWindow().hide(); // persistent window — hide, don't destroy
  }

  if (!capture && !pending) return null;

  const imgH = getImageHeight(capture);

  return (
    <div
      onMouseEnter={handleMouseEnter}
      onMouseLeave={handleMouseLeave}
      style={{
        width: WIN_W,
        borderRadius: 16,
        overflow: "hidden",
        background: "#0a0a0b",
        border: "1px solid rgba(255,255,255,0.10)",
        boxShadow:
          "0 20px 60px rgba(0,0,0,0.70), 0 4px 16px rgba(0,0,0,0.50), inset 0 1px 0 rgba(255,255,255,0.06)",
        fontFamily: "-apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif",
        userSelect: "none",
        WebkitUserSelect: "none",
        position: "relative",
      }}
    >
      {capture ? (
      <div style={{ position: "relative", width: WIN_W, height: imgH }}>
        {/* The screenshot — drag it out to Finder / Slack / etc. */}
        <img
          src={`data:image/png;base64,${capture.data}`}
          title="Drag to another app"
          style={{ width: "100%", height: "100%", objectFit: "contain", display: "block", cursor: "grab" }}
          draggable
          onDragStart={handleDragOut}
        />

        {/* Vignette gradient so corner buttons are legible over any image */}
        <div
          style={{
            position: "absolute", inset: 0, pointerEvents: "none",
            background:
              "radial-gradient(ellipse at center, transparent 40%, rgba(0,0,0,0.45) 100%)",
          }}
        />

        {/* ── 4 corner buttons ─────────────────────────────────────────── */}
        <CornerBtn style={{ top: 10, left: 10 }}  icon={Copy}     label="Copy"       onClick={handleCopy}       />
        <CornerBtn style={{ top: 10, right: 10 }} icon={Download} label="Save"       onClick={handleSave}       />
        <CornerBtn style={{ bottom: 10, left: 10  }} icon={Pencil}   label="Annotate"  onClick={handleEdit}       />
        <CornerBtn style={{ bottom: 10, right: 10 }} icon={Layers}   label="Background" onClick={handleBackground} />

        {/* ── Dismiss circle, top-center ───────────────────────────────── */}
        <button
          onClick={dismiss}
          title="Dismiss"
          style={{
            position: "absolute", top: 10, left: "50%", transform: "translateX(-50%)",
            width: 22, height: 22, borderRadius: "50%",
            background: "rgba(0,0,0,0.50)",
            border: "1px solid rgba(255,255,255,0.14)",
            backdropFilter: "blur(8px)",
            WebkitBackdropFilter: "blur(8px)",
            cursor: "pointer",
            display: "flex", alignItems: "center", justifyContent: "center",
            color: "rgba(255,255,255,0.55)",
            transition: "background 0.12s, color 0.12s",
            zIndex: 10,
          }}
          onMouseEnter={e => {
            e.currentTarget.style.background = "rgba(255,69,58,0.75)";
            e.currentTarget.style.color = "#fff";
          }}
          onMouseLeave={e => {
            e.currentTarget.style.background = "rgba(0,0,0,0.50)";
            e.currentTarget.style.color = "rgba(255,255,255,0.55)";
          }}
        >
          <X size={10} strokeWidth={2.5} />
        </button>

        {/* ── Feedback toast overlay ───────────────────────────────────── */}
        {feedback && (
          <div
            style={{
              position: "absolute", inset: 0,
              display: "flex", alignItems: "center", justifyContent: "center",
              pointerEvents: "none",
            }}
          >
            <div
              style={{
                display: "flex", alignItems: "center", gap: 7,
                padding: "8px 16px",
                borderRadius: 99,
                background: "rgba(0,0,0,0.72)",
                backdropFilter: "blur(16px)",
                WebkitBackdropFilter: "blur(16px)",
                border: `1px solid ${feedback.ok ? "rgba(50,215,75,0.35)" : "rgba(255,69,58,0.35)"}`,
                color: feedback.ok ? "#32D74B" : "#FF453A",
                fontSize: 12,
                fontWeight: 600,
                boxShadow: "0 4px 16px rgba(0,0,0,0.4)",
              }}
            >
              {feedback.ok
                ? <Check size={13} strokeWidth={2.5} />
                : <X size={12} strokeWidth={2.5} />}
              {feedback.msg}
            </div>
          </div>
        )}

        {/* ── Dimensions label, bottom-center ─────────────────────────── */}
        <div
          style={{
            position: "absolute", bottom: 46, left: 0, right: 0,
            textAlign: "center",
            fontSize: 10, fontWeight: 500,
            color: "rgba(255,255,255,0.30)",
            letterSpacing: "0.04em",
            pointerEvents: "none",
          }}
        >
          {capture.width.toLocaleString()} × {capture.height.toLocaleString()}
        </div>
      </div>
      ) : (
      <div
        style={{
          width: WIN_W,
          height: imgH,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          background:
            "radial-gradient(circle at top, rgba(255,255,255,0.08), transparent 45%), linear-gradient(180deg, rgba(22,22,24,0.98), rgba(10,10,11,0.98))",
          position: "relative",
        }}
      >
        <style>{`
          @keyframes popup-spin {
            from { transform: rotate(0deg); }
            to { transform: rotate(360deg); }
          }
          @keyframes popup-shimmer {
            0% { transform: translateX(-130%); }
            100% { transform: translateX(130%); }
          }
        `}</style>
        <div
          style={{
            position: "absolute",
            inset: 18,
            borderRadius: 14,
            border: "1px solid rgba(255,255,255,0.08)",
            background: "linear-gradient(180deg, rgba(255,255,255,0.03), rgba(255,255,255,0.01))",
            overflow: "hidden",
          }}
        >
          <div
            style={{
              position: "absolute",
              inset: 0,
              background: "linear-gradient(90deg, transparent, rgba(255,255,255,0.08), transparent)",
              animation: "popup-shimmer 1.1s ease-in-out infinite",
            }}
          />
        </div>
        <div
          style={{
            width: 42,
            height: 42,
            borderRadius: "50%",
            border: "2px solid rgba(255,255,255,0.14)",
            borderTopColor: "rgba(255,255,255,0.65)",
            animation: "popup-spin 0.8s linear infinite",
            position: "relative",
            zIndex: 1,
          }}
        />
        <div
          style={{
            position: "absolute",
            left: 24,
            right: 24,
            bottom: 18,
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between",
            color: "rgba(255,255,255,0.55)",
            fontSize: 10,
            fontWeight: 600,
            letterSpacing: "0.08em",
            textTransform: "uppercase",
          }}
        >
          <span>{pending ? "Processing capture" : "Loading capture"}</span>
          <span>Preparing preview</span>
        </div>
      </div>
      )}

      {/* ── Auto-dismiss progress bar ──────────────────────────────────── */}
      <div style={{ height: 3, background: "rgba(255,255,255,0.05)" }}>
        <div
          style={{
            height: "100%",
            width: `${progress * 100}%`,
            background: "linear-gradient(to right, #FF9F0A, #FFB84D)",
            transition: "none",
          }}
        />
      </div>
    </div>
  );
}

/* ── Corner button ─────────────────────────────────────────────────────────── */
function CornerBtn({
  style: posStyle,
  icon: Icon,
  label,
  onClick,
}: {
  style: React.CSSProperties;
  icon: React.ComponentType<{ size?: number; strokeWidth?: number }>;
  label: string;
  onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      title={label}
      style={{
        position: "absolute",
        ...posStyle,
        display: "flex", alignItems: "center", gap: 5,
        padding: "5px 10px 5px 8px",
        borderRadius: 10,
        background: "rgba(0,0,0,0.52)",
        backdropFilter: "blur(16px)",
        WebkitBackdropFilter: "blur(16px)",
        border: "1px solid rgba(255,255,255,0.16)",
        color: "rgba(255,255,255,0.88)",
        fontSize: 11, fontWeight: 500,
        cursor: "pointer",
        fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
        boxShadow: "0 2px 8px rgba(0,0,0,0.35)",
        transition: "background 0.12s, border-color 0.12s, transform 0.08s",
        zIndex: 10,
        letterSpacing: "-0.01em",
      }}
      onMouseEnter={e => {
        e.currentTarget.style.background = "rgba(255,255,255,0.18)";
        e.currentTarget.style.borderColor = "rgba(255,255,255,0.28)";
        e.currentTarget.style.transform = "scale(1.04)";
      }}
      onMouseLeave={e => {
        e.currentTarget.style.background = "rgba(0,0,0,0.52)";
        e.currentTarget.style.borderColor = "rgba(255,255,255,0.16)";
        e.currentTarget.style.transform = "scale(1)";
      }}
    >
      <Icon size={13} strokeWidth={1.8} />
      {label}
    </button>
  );
}
