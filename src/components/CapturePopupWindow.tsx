import { useState, useEffect, useRef } from "react";
import { invoke } from "@tauri-apps/api/core";
import { emit, listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { startDrag } from "@crabnebula/tauri-plugin-drag";
import { Pin, Pencil, UploadCloud, X, Check } from "lucide-react";

interface CaptureInfo {
  captureId: number;
  data: string;   // base64 PNG thumbnail (inline data URL — reliable in dev + prod)
  width: number;
  height: number;
}

const WIN_W = 300;
const CONTENT_H = 207;           // panel body; +3px progress bar = 210 total window
const AUTO_DISMISS_MS = 12000;

export default function CapturePopupWindow() {
  const [capture, setCapture] = useState<CaptureInfo | null>(null);
  const [pending, setPending] = useState(false);
  const [progress, setProgress] = useState(1);
  const [paused, setPaused] = useState(false);
  const [exiting, setExiting] = useState(false);
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

  function startPending(captureId: number) {
    pendingCaptureIdRef.current = captureId;
    pendingRef.current = true;
    setPending(true);
    setExiting(false);
    setCapture(null);
    resetDismissTimer();
  }

  function commitCapture(info: CaptureInfo, reveal: boolean) {
    const token = ++decodeTokenRef.current;
    const src = `data:image/png;base64,${info.data}`;
    const finalize = () => {
      if (
        !mountedRef.current ||
        token !== decodeTokenRef.current ||
        info.captureId !== latestCaptureIdRef.current
      ) return;
      setCapture(info);
      pendingRef.current = false;
      setPending(false);
      resetDismissTimer();
      if (reveal) showWindow();
    };

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
      latestCaptureIdRef.current = info.captureId;
      startPending(info.captureId);
      // Guarantee the window is visible on every completed capture (shows the loading shell),
      // then swap in the decoded image. Don't depend on the earlier popup-pending show —
      // that path could race/be skipped, leaving a saved capture with no popup.
      showWindow();
      commitCapture(info, true);
    }).then(fn => { unlisten = fn; });

    invoke<CaptureInfo | null>("get_capture_popup_data").then((info) => {
      if (!info || info.captureId < latestCaptureIdRef.current) return;
      latestCaptureIdRef.current = info.captureId;
      startPending(info.captureId);
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

  // Show a confirmation, then close the popup — its job is done after a terminal action.
  function flashThenDismiss(msg: string) {
    flash(msg);
    setTimeout(() => dismiss(), 700);
  }

  function dismiss() {
    if (!capture || exiting) return;
    setExiting(true); // play the exit animation, then actually close
    const id = capture.captureId;
    setTimeout(() => void invoke("close_capture_popup", { captureId: id }), 150);
  }

  async function handleCopy() {
    if (!capture) return;
    const full = await invoke<string | null>("get_capture_full_data", { captureId: capture.captureId });
    if (!full) return;
    await invoke("copy_to_clipboard", { data: full });
    flashThenDismiss("Copied!");
  }

  async function handleSave() {
    try {
      if (!capture) return;
      await invoke<string>("quick_save_capture", { captureId: capture.captureId });
      flashThenDismiss("Saved!");
    } catch {
      flash("Set a save folder in Settings", false);
    }
  }

  async function handlePin() {
    if (!capture) return;
    const full = await invoke<string | null>("get_capture_full_data", { captureId: capture.captureId });
    if (!full) return;
    await invoke("pin_screenshot", { data: full, imgWidth: capture.width, imgHeight: capture.height });
    flashThenDismiss("Pinned!");
  }

  async function handleDragOut(e: React.DragEvent) {
    e.preventDefault(); // cancel the HTML5 drag; use a native OS file drag instead
    if (!capture) return;
    setPaused(true); // hold the auto-dismiss timer during the drag
    try {
      const path = await invoke<string>("stage_capture_for_drag", { captureId: capture.captureId });
      // onEvent fires when the drag ends. If the screenshot was dropped into
      // another app the popup has done its job, so dismiss it; if the drag was
      // cancelled, resume the auto-dismiss timer instead of lingering forever.
      await startDrag({ item: [path], icon: path }, (payload) => {
        if (payload.result === "Dropped") dismiss();
        else setPaused(false);
      });
    } catch (err) {
      console.error(err);
      setPaused(false); // drag failed — let the auto-dismiss timer resume
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

  return (
    <div
      key={capture?.captureId ?? pendingCaptureIdRef.current}
      className={exiting ? "anim-popup-out" : "anim-popup-in"}
      onMouseEnter={handleMouseEnter}
      onMouseLeave={handleMouseLeave}
      style={{
        width: WIN_W,
        borderRadius: 26,
        overflow: "hidden",
        background: "#0a0a0b",
        border: "1px solid rgba(255,255,255,0.22)",
        boxShadow:
          "0 24px 60px rgba(0,0,0,0.55), 0 2px 10px rgba(0,0,0,0.40), inset 0 1px 0 rgba(255,255,255,0.22)",
        fontFamily: "-apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif",
        userSelect: "none",
        WebkitUserSelect: "none",
        position: "relative",
      }}
    >
      {capture ? (
      <div style={{ position: "relative", width: WIN_W, height: CONTENT_H }}>
        {/* Frosted screenshot — also the drag-out handle (drag empty glass area to Finder / Slack) */}
        <img
          src={`data:image/png;base64,${capture.data}`}
          title="Drag to another app"
          style={{
            position: "absolute", inset: 0,
            width: "100%", height: "100%", objectFit: "cover",
            filter: "blur(18px) saturate(1.2) brightness(0.9)",
            transform: "scale(1.3)",
            cursor: "grab",
          }}
          draggable
          onDragStart={handleDragOut}
        />

        {/* Purple-grey tint over the blur — gives the glass its color, keeps pills legible */}
        <div
          style={{
            position: "absolute", inset: 0, pointerEvents: "none",
            background: "linear-gradient(150deg, rgba(118,112,140,0.46), rgba(58,54,78,0.62))",
          }}
        />

        {/* ── 4 circular corner buttons ─────────────────────────────────── */}
        <CircleBtn style={{ top: 14, left: 14 }}     icon={Pin}         label="Pin"        onClick={handlePin}        />
        <CircleBtn style={{ top: 14, right: 14 }}    icon={X}           label="Dismiss"    onClick={dismiss} small    />
        <CircleBtn style={{ bottom: 14, left: 14 }}  icon={Pencil}      label="Annotate"   onClick={handleEdit}       />
        <CircleBtn style={{ bottom: 14, right: 14 }} icon={UploadCloud} label="Background"  onClick={handleBackground} />

        {/* ── Center Copy / Save pills ──────────────────────────────────── */}
        <div
          style={{
            position: "absolute", inset: 0,
            display: "flex", flexDirection: "column",
            alignItems: "center", justifyContent: "center", gap: 16,
            pointerEvents: "none", // gaps stay draggable; pills re-enable below
          }}
        >
          <Pill label="Copy" onClick={handleCopy} />
          <Pill label="Save" onClick={handleSave} />
        </div>

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
      </div>
      ) : (
      <div
        style={{
          width: WIN_W,
          height: CONTENT_H,
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
        `}</style>
        <div
          style={{
            width: 42,
            height: 42,
            borderRadius: "50%",
            border: "2px solid rgba(255,255,255,0.14)",
            borderTopColor: "rgba(255,255,255,0.65)",
            animation: "popup-spin 0.8s linear infinite",
          }}
        />
      </div>
      )}

      {/* ── Auto-dismiss progress bar ──────────────────────────────────── */}
      <div style={{ height: 3, background: "rgba(255,255,255,0.10)" }}>
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

/* ── Center pill (Copy / Save) ───────────────────────────────────────────── */
function Pill({ label, onClick }: { label: string; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      style={{
        pointerEvents: "auto",
        minWidth: 132,
        padding: "11px 30px",
        borderRadius: 999,
        background: "#fafafa",
        color: "#1c1c1e",
        fontSize: 21,
        fontWeight: 650,
        letterSpacing: "-0.01em",
        fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
        border: "none",
        cursor: "pointer",
        boxShadow: "0 6px 18px rgba(0,0,0,0.28), inset 0 1px 0 rgba(255,255,255,0.9)",
        transition: "transform var(--dur-fast) var(--ease-out), background var(--dur-fast) var(--ease-out)",
      }}
      onMouseEnter={e => (e.currentTarget.style.background = "#ffffff")}
      onMouseLeave={e => (e.currentTarget.style.background = "#fafafa")}
      onMouseDown={e => (e.currentTarget.style.transform = "scale(0.97)")}
      onMouseUp={e => (e.currentTarget.style.transform = "scale(1)")}
    >
      {label}
    </button>
  );
}

/* ── Circular corner button ──────────────────────────────────────────────── */
function CircleBtn({
  style: posStyle,
  icon: Icon,
  label,
  onClick,
  small,
}: {
  style: React.CSSProperties;
  icon: React.ComponentType<{ size?: number; strokeWidth?: number }>;
  label: string;
  onClick: () => void;
  small?: boolean;
}) {
  return (
    <button
      onClick={onClick}
      title={label}
      style={{
        position: "absolute",
        ...posStyle,
        width: 38,
        height: 38,
        borderRadius: "50%",
        background: "#fafafa",
        border: "none",
        color: "#2a2a2e",
        cursor: "pointer",
        display: "flex", alignItems: "center", justifyContent: "center",
        boxShadow: "0 4px 12px rgba(0,0,0,0.30), inset 0 1px 0 rgba(255,255,255,0.9)",
        transition: "background var(--dur-fast) var(--ease-out), transform var(--dur-fast) var(--ease-out)",
        zIndex: 10,
      }}
      onMouseEnter={e => {
        e.currentTarget.style.background = "#ffffff";
        e.currentTarget.style.transform = "scale(1.08)";
      }}
      onMouseLeave={e => {
        e.currentTarget.style.background = "#fafafa";
        e.currentTarget.style.transform = "scale(1)";
      }}
    >
      <Icon size={small ? 15 : 17} strokeWidth={2} />
    </button>
  );
}
