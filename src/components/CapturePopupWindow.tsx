import { useState, useEffect, useRef } from "react";
import { invoke } from "@tauri-apps/api/core";
import { emit, listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { startDrag } from "@crabnebula/tauri-plugin-drag";
import { Copy, Download, Pencil, Image as ImageIcon, X, Check, Pin } from "lucide-react";

interface CaptureInfo {
  captureId: number;
  data: string;   // base64 PNG thumbnail (inline data URL — reliable in dev + prod)
  width: number;
  height: number;
}

const WIN_W = 230;
const IMG_MIN = 100;
const IMG_MAX = 150;
const AUTO_DISMISS_MS = 5000;

export default function CapturePopupWindow() {
  const [capture, setCapture] = useState<CaptureInfo | null>(null);
  const [pending, setPending] = useState(false);
  const [progress, setProgress] = useState(1);
  const [paused, setPaused] = useState(false);
  const [hovered, setHovered] = useState(false);
  const [exiting, setExiting] = useState(false);
  const [shellHeight, setShellHeight] = useState(135);
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
    return Math.min(Math.max(Math.round(WIN_W * info.height / info.width), IMG_MIN), IMG_MAX);
  }

  function showWindow() {
    const w = getCurrentWindow();
    // No setFocus(): focusing this popup activates the app on EVERY capture, and if the
    // main window is visible on another Space, macOS switches the user to that desktop
    // (issue #6). Hover actions, clicks, and native drag-out all work without key focus.
    //
    // show() itself still makes Potret the frontmost app, and while it's frontmost a manual
    // Space switch drags the user back to the popup's desktop — the "still need to click" bug.
    // Resign frontmost right after showing so macOS stops following us (backend delays a beat
    // so the deactivate undoes show()'s activation instead of racing it).
    void w.show().then(() => void invoke("resign_frontmost_app"));
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
    setExiting(false);
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
      latestCaptureIdRef.current = info.captureId;
      startPending(info.captureId, info);
      // Guarantee the window is visible on every completed capture (shows the loading shell),
      // then swap in the decoded image. Don't depend on the earlier popup-pending show —
      // that path could race/be skipped, leaving a saved capture with no popup.
      showWindow();
      commitCapture(info, true);
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
    setHovered(true);
    setPaused(true);
    pausedAtRef.current = Date.now();
  }
  function handleMouseLeave() {
    setHovered(false);
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

  const imgH = getImageHeight(capture);

  return (
    <div
      key={capture?.captureId ?? pendingCaptureIdRef.current}
      className={exiting ? "anim-popup-out" : "anim-popup-in"}
      onMouseEnter={handleMouseEnter}
      onMouseLeave={handleMouseLeave}
      style={{
        width: WIN_W,
        borderRadius: 14,
        overflow: "hidden",
        background: "#0a0a0b",
        border: "1px solid rgba(255,255,255,0.12)",
        boxShadow:
          "0 18px 50px rgba(0,0,0,0.60), 0 3px 12px rgba(0,0,0,0.45), inset 0 1px 0 rgba(255,255,255,0.06)",
        fontFamily: "-apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif",
        userSelect: "none",
        WebkitUserSelect: "none",
        position: "relative",
      }}
    >
      {capture ? (
      <div style={{ position: "relative", width: WIN_W, height: imgH }}>
        {/* The sharp screenshot — drag it out to Finder / Slack / etc. */}
        <img
          src={`data:image/png;base64,${capture.data}`}
          title="Drag to another app"
          style={{ width: "100%", height: "100%", objectFit: "cover", display: "block", cursor: "grab" }}
          draggable
          onDragStart={handleDragOut}
        />

        {/* Chrome layer: scrim + corner icon buttons + center action pills — hidden until you hover */}
        <div
          style={{
            position: "absolute", inset: 0,
            opacity: hovered ? 1 : 0,
            transition: "opacity var(--dur-fast) var(--ease-out)",
            pointerEvents: "none", // never block the image; only the buttons below opt back in
          }}
        >
          {/* Frosted scrim so buttons stay legible over any image */}
          <div
            style={{
              position: "absolute", inset: 0, pointerEvents: "none",
              background: "rgba(40,38,46,0.42)",
              backdropFilter: "blur(14px)",
              WebkitBackdropFilter: "blur(14px)",
            }}
          />

          {/* ── 4 corner icon-only buttons ───────────────────────────────── */}
          <CircleBtn style={{ top: 10, left: 10 }}     icon={Pin}       label="Pin"        onClick={handlePin}        active={hovered} />
          <CircleBtn style={{ top: 10, right: 10 }}    icon={X}         label="Dismiss"    onClick={dismiss}          active={hovered} danger />
          <CircleBtn style={{ bottom: 10, left: 10 }}  icon={Pencil}    label="Annotate"   onClick={handleEdit}       active={hovered} />
          <CircleBtn style={{ bottom: 10, right: 10 }} icon={ImageIcon} label="Background" onClick={handleBackground} active={hovered} />

          {/* ── Center stacked pills — primary actions ───────────────────── */}
          {/* pointerEvents stays "none" here — only the pill buttons themselves opt back
              in, so the rest of the image (drag-out target) is never blocked by this box. */}
          <div
            style={{
              position: "absolute", inset: 0,
              display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 10,
              pointerEvents: "none",
            }}
          >
            <PillBtn icon={Copy} label="Copy" onClick={handleCopy} active={hovered} />
            <PillBtn icon={Download} label="Save" onClick={handleSave} active={hovered} />
          </div>
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
                display: "flex", alignItems: "center", gap: 6,
                padding: "7px 14px",
                borderRadius: 99,
                background: "rgba(0,0,0,0.72)",
                backdropFilter: "blur(16px)",
                WebkitBackdropFilter: "blur(16px)",
                border: `1px solid ${feedback.ok ? "rgba(50,215,75,0.35)" : "rgba(255,69,58,0.35)"}`,
                color: feedback.ok ? "#32D74B" : "#FF453A",
                fontSize: 11,
                fontWeight: 600,
                boxShadow: "0 4px 16px rgba(0,0,0,0.4)",
              }}
            >
              {feedback.ok
                ? <Check size={12} strokeWidth={2.5} />
                : <X size={11} strokeWidth={2.5} />}
              {feedback.msg}
            </div>
          </div>
        )}
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
        `}</style>
        <div
          style={{
            width: 36,
            height: 36,
            borderRadius: "50%",
            border: "2px solid rgba(255,255,255,0.14)",
            borderTopColor: "rgba(255,255,255,0.65)",
            animation: "popup-spin 0.8s linear infinite",
          }}
        />
      </div>
      )}

      {/* ── Auto-dismiss progress bar ──────────────────────────────────── */}
      <div style={{ height: 3, background: "rgba(255,255,255,0.08)" }}>
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

/* ── Corner button (icon-only circle) ─────────────────────────────────────── */
function CircleBtn({
  style: posStyle,
  icon: Icon,
  label,
  onClick,
  active,
  danger,
}: {
  style: React.CSSProperties;
  icon: React.ComponentType<{ size?: number; strokeWidth?: number }>;
  label: string;
  onClick: () => void;
  active: boolean;
  danger?: boolean;
}) {
  return (
    <button
      onClick={onClick}
      title={label}
      style={{
        position: "absolute",
        ...posStyle,
        width: 30, height: 30, borderRadius: "50%",
        display: "flex", alignItems: "center", justifyContent: "center",
        background: "rgba(255,255,255,0.16)",
        backdropFilter: "blur(12px)",
        WebkitBackdropFilter: "blur(12px)",
        border: "1px solid rgba(255,255,255,0.24)",
        color: "rgba(255,255,255,0.95)",
        cursor: "pointer",
        boxShadow: "0 2px 8px rgba(0,0,0,0.35)",
        transition: "background var(--dur-fast) var(--ease-out), border-color var(--dur-fast) var(--ease-out), transform var(--dur-fast) var(--ease-out)",
        pointerEvents: active ? "auto" : "none",
        zIndex: 10,
      }}
      onMouseEnter={e => {
        e.currentTarget.style.background = danger ? "rgba(255,69,58,0.78)" : "rgba(255,255,255,0.20)";
        e.currentTarget.style.borderColor = danger ? "rgba(255,69,58,0.5)" : "rgba(255,255,255,0.30)";
        e.currentTarget.style.transform = "scale(1.08)";
      }}
      onMouseLeave={e => {
        e.currentTarget.style.background = "rgba(0,0,0,0.52)";
        e.currentTarget.style.borderColor = "rgba(255,255,255,0.18)";
        e.currentTarget.style.transform = "scale(1)";
      }}
    >
      <Icon size={14} strokeWidth={2} />
    </button>
  );
}

/* ── Center action pill (icon + label) ─────────────────────────────────────── */
function PillBtn({
  icon: Icon,
  label,
  onClick,
  active,
}: {
  icon: React.ComponentType<{ size?: number; strokeWidth?: number }>;
  label: string;
  onClick: () => void;
  active: boolean;
}) {
  return (
    <button
      onClick={onClick}
      style={{
        display: "flex", alignItems: "center", justifyContent: "center", gap: 7,
        width: 118,
        padding: "10px 0",
        borderRadius: 999,
        background: "rgba(244,244,246,0.97)",
        color: "#0a0a0b",
        fontSize: 13.5, fontWeight: 650,
        border: "none",
        cursor: "pointer",
        fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
        boxShadow: "0 4px 14px rgba(0,0,0,0.35)",
        transition: "background var(--dur-fast) var(--ease-out), transform var(--dur-fast) var(--ease-out)",
        pointerEvents: active ? "auto" : "none",
        zIndex: 10,
        letterSpacing: "-0.01em",
      }}
      onMouseEnter={e => {
        e.currentTarget.style.background = "#ffffff";
        e.currentTarget.style.transform = "scale(1.04)";
      }}
      onMouseLeave={e => {
        e.currentTarget.style.background = "rgba(244,244,246,0.96)";
        e.currentTarget.style.transform = "scale(1)";
      }}
    >
      <Icon size={13} strokeWidth={2} />
      {label}
    </button>
  );
}
