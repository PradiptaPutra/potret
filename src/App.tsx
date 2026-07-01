import { useState, useEffect, useCallback, useRef } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { desktopDir } from "@tauri-apps/api/path";
import { AppConfig, DEFAULT_CONFIG } from "./utils";
import CaptureHome from "./components/CaptureHome";
import AnnotationCanvas from "./components/AnnotationCanvas";
import Settings from "./components/Settings";
import PinnedView from "./components/PinnedView";
import BackgroundTool from "./components/BackgroundTool";
import CapturePopupWindow from "./components/CapturePopupWindow";
import CaptureSelector from "./components/CaptureSelector";
import HistoryPopupWindow from "./components/HistoryPopupWindow";
import CornerHistoryWindow from "./components/CornerHistoryWindow";
import { useHistory } from "./hooks/useHistory";
import "./index.css";

// Detect window type before React renders
const WINDOW_LABEL = getCurrentWindow().label;

export type AppScreen = "home" | "annotate" | "settings";

export interface CaptureData {
  data: string; // base64 PNG
  width: number;
  height: number;
}

export interface HistoryItem {
  id: string;
  path: string;
  thumbnail: string; // base64 PNG
  timestamp: number; // unix ms
  width: number;
  height: number;
  fileSize: number;
}

// ─── Toast ───────────────────────────────────────────────────────────────────

interface Toast {
  id: number;
  message: string;
  type: "success" | "error";
}

let toastCounter = 0;

function ToastContainer({ toasts }: { toasts: Toast[] }) {
  if (toasts.length === 0) return null;
  return (
    <>
      <style>{`
        @keyframes toast-in {
          from { transform: translateY(12px) scale(0.96); opacity: 0; }
          to   { transform: translateY(0)    scale(1);    opacity: 1; }
        }
      `}</style>
      <div style={{
        position: "fixed", bottom: 20, left: "50%", transform: "translateX(-50%)",
        display: "flex", flexDirection: "column", gap: 8,
        zIndex: 99999, pointerEvents: "none",
        fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
      }}>
        {toasts.map((t) => (
          <div
            key={t.id}
            style={{
              display: "flex", alignItems: "center", gap: 10,
              padding: "10px 16px 10px 12px",
              borderRadius: 12,
              background: "rgba(30, 30, 32, 0.92)",
              backdropFilter: "blur(20px)",
              WebkitBackdropFilter: "blur(20px)",
              border: `1px solid ${t.type === "success" ? "rgba(50,215,75,0.25)" : "rgba(255,69,58,0.25)"}`,
              boxShadow: "0 4px 24px rgba(0,0,0,0.5), 0 1px 4px rgba(0,0,0,0.3)",
              animation: "toast-in 0.18s cubic-bezier(0.34,1.56,0.64,1) forwards",
              minWidth: 200, maxWidth: 360,
              whiteSpace: "nowrap",
            }}
          >
            {/* Colored dot indicator */}
            <div style={{
              width: 7, height: 7, borderRadius: "50%", flexShrink: 0,
              background: t.type === "success" ? "#32D74B" : "#FF453A",
              boxShadow: `0 0 6px 1px ${t.type === "success" ? "rgba(50,215,75,0.5)" : "rgba(255,69,58,0.5)"}`,
            }} />
            <span style={{
              fontSize: 13, fontWeight: 500,
              color: "rgba(255,255,255,0.90)",
              letterSpacing: "-0.01em",
            }}>
              {t.message}
            </span>
          </div>
        ))}
      </div>
    </>
  );
}

// ─── Screen Recording permission banner ───────────────────────────────────────

function PermissionBanner({
  onOpenSettings,
  onRestart,
}: {
  onOpenSettings: () => void;
  onRestart: () => void;
}) {
  return (
    <div style={{
      position: "fixed", left: 16, right: 16, bottom: 16, zIndex: 99998,
      background: "rgba(36,36,40,0.97)", backdropFilter: "blur(20px)",
      border: "1px solid rgba(255,159,10,0.35)", borderRadius: 12,
      boxShadow: "0 8px 32px rgba(0,0,0,0.5)",
      padding: 14, display: "flex", alignItems: "center", gap: 14,
      fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
    }}>
      <div style={{
        width: 30, height: 30, borderRadius: 8, flexShrink: 0,
        background: "rgba(255,159,10,0.15)", display: "flex",
        alignItems: "center", justifyContent: "center", fontSize: 16,
      }}>🎥</div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 13, fontWeight: 600, color: "rgba(255,255,255,0.9)" }}>
          Screen Recording permission needed
        </div>
        <div style={{ fontSize: 11.5, color: "rgba(255,255,255,0.5)", marginTop: 2, lineHeight: 1.4 }}>
          1. Click <b>Enable</b> and turn on Potret in System Settings. &nbsp;2. Click <b>Restart</b> for it to take effect.
        </div>
      </div>
      <button onClick={onOpenSettings} style={{
        flexShrink: 0, padding: "7px 12px", borderRadius: 7, cursor: "pointer",
        background: "rgba(255,255,255,0.08)", border: "1px solid rgba(255,255,255,0.12)",
        color: "rgba(255,255,255,0.85)", fontSize: 12, fontWeight: 500,
      }}>Enable…</button>
      <button onClick={onRestart} style={{
        flexShrink: 0, padding: "7px 14px", borderRadius: 7, cursor: "pointer",
        background: "#FF9F0A", border: "none", color: "#000", fontSize: 12, fontWeight: 600,
      }}>Restart</button>
    </div>
  );
}


// ─── App ─────────────────────────────────────────────────────────────────────

function App() {
  // Lightweight popup and pinned windows — render without the full app shell
  if (WINDOW_LABEL === "capture-popup") return <CapturePopupWindow />;
  if (WINDOW_LABEL === "capture-selector") return <CaptureSelector />;
  if (WINDOW_LABEL === "history") return <HistoryPopupWindow />;
  if (WINDOW_LABEL === "corner-history") return <CornerHistoryWindow />;
  if (WINDOW_LABEL.startsWith("pinned-")) return <PinnedView windowLabel={WINDOW_LABEL} />;

  const [screen, setScreen] = useState<AppScreen>("home");
  const [config, setConfig] = useState<AppConfig>(DEFAULT_CONFIG);
  const [capture, setCapture] = useState<CaptureData | null>(null);
  // Bumped on every new capture and used as AnnotationCanvas's `key`, forcing a clean
  // remount per screenshot — without it React reuses the instance and annotations from
  // the previous session bleed onto the new image (issue #5).
  const [captureKey, setCaptureKey] = useState(0);
  const [loading, setLoading] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [toasts, setToasts] = useState<Toast[]>([]);
  const [backgroundSrc, setBackgroundSrc] = useState<string | null>(null);
  const [screenPerm, setScreenPerm] = useState<boolean | null>(null);

  const { items: history, loadHistory, deleteItem, clearAll } = useHistory();
  const captureRequestIdRef = useRef(0);
  const activeCaptureModeRef = useRef<"fullscreen" | "area" | "window" | null>(null);
  // True when the editor was opened from the Quick Access popup / history popup
  // (a transient edit) — Done/back then hides the window instead of showing home.
  const editFromPopupRef = useRef(false);
  const historyReloadTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const lastCaptureAtRef = useRef(0);

  useEffect(() => {
    invoke<AppConfig>("get_config").then(setConfig).catch(console.error);
  }, [screen]); // reload every time screen changes (catches settings saves)

  // Track Screen Recording permission (re-check when the window regains focus, e.g. after the
  // user toggles it in System Settings). Note: the grant only truly applies after an app restart.
  useEffect(() => {
    const check = () =>
      invoke<boolean>("check_screen_recording_permission")
        .then(setScreenPerm)
        .catch(() => setScreenPerm(null));
    check();
    window.addEventListener("focus", check);
    return () => window.removeEventListener("focus", check);
  }, []);

  // ── Toast helpers ──────────────────────────────────────────────────────────

  const showToast = useCallback(
    (message: string, type: "success" | "error" = "success") => {
      const id = ++toastCounter;
      setToasts((prev) => [...prev, { id, message, type }]);
      setTimeout(() => {
        setToasts((prev) => prev.filter((t) => t.id !== id));
      }, 3000);
    },
    []
  );

  // ── Capture ────────────────────────────────────────────────────────────────

  const handleCapture = useCallback(
    async (mode: "fullscreen" | "area" | "window") => {
      // Debounce — collapse accidental double-fires (one trigger was invoking capture twice)
      const now = Date.now();
      if (now - lastCaptureAtRef.current < 500) return;
      lastCaptureAtRef.current = now;

      // Block capture if Screen Recording isn't granted — re-check live (it may have changed)
      const granted = await invoke<boolean>("check_screen_recording_permission").catch(() => true);
      setScreenPerm(granted);
      if (!granted) {
        showToast("Grant Screen Recording permission first", "error");
        return;
      }

      const requestId = ++captureRequestIdRef.current;
      activeCaptureModeRef.current = mode;
      setError(null);
      setLoading(null);

      // Area capture: open the custom selector overlay; Rust emits capture-completed when done
      if (mode === "area") {
        try {
          await invoke("open_capture_selector");
        } catch (e) {
          if (captureRequestIdRef.current === requestId) {
            activeCaptureModeRef.current = null;
          }
          showToast(String(e), "error");
        }
        return;
      }

      setLoading(
        mode === "fullscreen"
          ? "Capturing screen..."
          : "Click a window..."
      );

      try {
        const cmd =
          mode === "fullscreen"
            ? "capture_fullscreen"
            : "capture_window";

        const result = await invoke<{
          success: boolean;
          screenshot: CaptureData | null;
          error: string | null;
        }>(cmd);

        if (result.success) {
          activeCaptureModeRef.current = null;
        } else if (result.error) {
          activeCaptureModeRef.current = null;
          // null error = user cancelled — stay silent
          setError(result.error);
          showToast(result.error, "error");
        } else {
          activeCaptureModeRef.current = null;
        }
      } catch (e) {
        activeCaptureModeRef.current = null;
        const msg = String(e);
        setError(msg);
        showToast(msg, "error");
      } finally {
        if (captureRequestIdRef.current === requestId) {
          setLoading(null);
        }
      }
    },
    [showToast]
  );

  // ── Global shortcut listener (Tauri events from Rust) ─────────────────────

  useEffect(() => {
    let unlisten: (() => void) | undefined;

    listen<{ mode: "fullscreen" | "area" | "window" }>(
      "shortcut-triggered",
      (event) => {
        handleCapture(event.payload.mode);
      }
    ).then((fn) => {
      unlisten = fn;
    }).catch((err) => console.error("failed to listen for shortcut-triggered:", err));

    return () => {
      unlisten?.();
    };
  }, [handleCapture]);

  // ── Capture popup "Background" → open background tool with full-res image ──

  useEffect(() => {
    let unlisten: (() => void) | undefined;
    listen<{ captureId: number }>("capture-background-requested", async (event) => {
      const captureId = event.payload.captureId;
      const full = await invoke<string | null>("get_capture_full_data", { captureId });
      if (full) {
        setBackgroundSrc(full);
        invoke("close_capture_popup", { captureId });
      }
    }).then((fn) => { unlisten = fn; }).catch((err) => console.error("failed to listen for capture-background-requested:", err));
    return () => { unlisten?.(); };
  }, []);

  // ── Capture popup "Edit" → fetch full-res image from Rust state ───────────

  useEffect(() => {
    let unlisten: (() => void) | undefined;

    listen<{ captureId: number }>("capture-edit-requested", async (event) => {
      const captureId = event.payload.captureId;
      // Fetch metadata (dimensions) from popup state
      const info = await invoke<{ captureId: number; path: string; width: number; height: number } | null>(
        "get_capture_popup_data"
      );
      // Fetch the full-resolution PNG (only fetched on user intent to edit)
      const full = await invoke<string | null>("get_capture_full_data", { captureId });
      if (info?.captureId === captureId && full) {
        editFromPopupRef.current = true; // opened transiently from the popup
        setCaptureKey((k) => k + 1);
        setCapture({ data: full, width: info.width, height: info.height });
        setScreen("annotate");
        invoke("close_capture_popup", { captureId }); // clear Rust state now that main window has the data
      }
    }).then((fn) => {
      unlisten = fn;
    }).catch((err) => console.error("failed to listen for capture-edit-requested:", err));

    return () => {
      unlisten?.();
    };
  }, []);

  // ── History popup "Edit"/"Background" → open the editor here with the item ──

  useEffect(() => {
    let unEdit: (() => void) | undefined;
    let unBg: (() => void) | undefined;
    listen<{ id: string; width: number; height: number }>("history-edit-requested", async (e) => {
      const { id, width, height } = e.payload;
      const full = await invoke<string | null>("get_history_full", { id }).catch(() => null);
      if (!full) return;
      editFromPopupRef.current = true;
      setCaptureKey((k) => k + 1);
      setCapture({ data: full, width, height });
      setScreen("annotate");
    }).then((fn) => { unEdit = fn; }).catch((err) => console.error("failed to listen for history-edit-requested:", err));
    listen<{ id: string }>("history-background-requested", async (e) => {
      const full = await invoke<string | null>("get_history_full", { id: e.payload.id }).catch(() => null);
      if (full) setBackgroundSrc(full);
    }).then((fn) => { unBg = fn; }).catch((err) => console.error("failed to listen for history-background-requested:", err));
    return () => { unEdit?.(); unBg?.(); };
  }, []);

  // ── Region capture done (emitted by Rust after capture_region_and_crop) ──

  useEffect(() => {
    let unlisten: (() => void) | undefined;
    listen("capture-completed", () => {
      if (activeCaptureModeRef.current === "area") {
        activeCaptureModeRef.current = null;
        setLoading(null);
      }
    }).then((fn) => { unlisten = fn; }).catch((err) => console.error("failed to listen for capture-completed:", err));
    return () => { unlisten?.(); };
  }, []);

  // The backend emits this only after the background history write is complete.
  useEffect(() => {
    let unlisten: (() => void) | undefined;
    listen("history-updated", () => {
      if (historyReloadTimerRef.current) clearTimeout(historyReloadTimerRef.current);
      historyReloadTimerRef.current = setTimeout(() => void loadHistory(), 80);
    }).then((fn) => { unlisten = fn; }).catch((err) => console.error("failed to listen for history-updated:", err));
    return () => {
      unlisten?.();
      if (historyReloadTimerRef.current) clearTimeout(historyReloadTimerRef.current);
    };
  }, [loadHistory]);

  // ── Surface background save failures (history / auto-save folder) ──────────

  useEffect(() => {
    let unlisten: (() => void) | undefined;
    listen<string>("save-error", (e) => {
      showToast(e.payload || "Failed to save screenshot", "error");
    }).then((fn) => { unlisten = fn; }).catch((err) => console.error("failed to listen for save-error:", err));
    return () => { unlisten?.(); };
  }, [showToast]);

  // ── Window keyboard shortcuts ─────────────────────────────────────────────

  // Editor keyboard shortcuts (⌘Z/⌘⇧Z/⌘S/Escape) live solely inside
  // AnnotationCanvas — handling them here too made every ⌘Z undo twice.

  // ── Save / Copy ────────────────────────────────────────────────────────────

  // Re-encode a PNG data URL into the user's chosen output format (PNG passes through;
  // JPG re-encodes via a canvas with a white matte since JPEG has no alpha).
  async function encodeForOutput(
    pngDataUrl: string
  ): Promise<{ base64: string; ext: string }> {
    if (config.format !== "jpg") {
      return { base64: pngDataUrl.replace(/^data:image\/png;base64,/, ""), ext: "png" };
    }
    const img = new Image();
    await new Promise<void>((res, rej) => {
      img.onload = () => res();
      img.onerror = () => rej(new Error("encode failed"));
      img.src = pngDataUrl;
    });
    const c = document.createElement("canvas");
    c.width = img.naturalWidth;
    c.height = img.naturalHeight;
    const ctx = c.getContext("2d")!;
    ctx.fillStyle = "#fff";
    ctx.fillRect(0, 0, c.width, c.height);
    ctx.drawImage(img, 0, 0);
    const jpg = c.toDataURL("image/jpeg", config.jpeg_quality / 100);
    return { base64: jpg.replace(/^data:image\/jpeg;base64,/, ""), ext: "jpg" };
  }

  async function handleSave(dataUrl: string): Promise<boolean> {
    const pngBase64 = dataUrl.replace(/^data:image\/png;base64,/, "");
    try {
      if (config.save_path) {
        // Auto-save to the configured folder — Rust applies the filename
        // template and output format (PNG/JPG), same as a direct capture.
        await invoke("save_image_with_config", { data: pngBase64 });
        showToast(`Saved to ${config.save_path}`);
      } else {
        // No folder configured — auto-save to the Desktop instead of prompting,
        // so Done always finishes without a dialog.
        const { base64, ext } = await encodeForOutput(dataUrl);
        const dir = await desktopDir();
        const n = new Date();
        const p2 = (x: number) => String(x).padStart(2, "0");
        const stamp = `${n.getFullYear()}-${p2(n.getMonth() + 1)}-${p2(n.getDate())} at ${p2(n.getHours())}.${p2(n.getMinutes())}.${p2(n.getSeconds())}`;
        await invoke("save_image", { data: base64, path: `${dir}/Screenshot ${stamp}.${ext}` });
        showToast("Saved to Desktop");
      }
      // History always stores PNG (lossless re-editing), regardless of export format
      await invoke("add_to_history", { data: pngBase64 });
      await loadHistory();
      return true;
    } catch (e) {
      showToast(String(e), "error");
      return false;
    }
  }

  // Done = save to folder (or dialog) and finish. If the editor was opened from
  // the Quick Access popup (a transient edit), hide the window afterward so the
  // app returns to the menubar instead of lingering on the home screen.
  async function handleDone(dataUrl: string) {
    const ok = await handleSave(dataUrl);
    if (!ok) return; // save failed or dialog cancelled — stay in the editor
    if (editFromPopupRef.current) {
      editFromPopupRef.current = false;
      setTimeout(() => {
        void getCurrentWindow().hide();
        setScreen("home");
      }, 650); // let the "Saved" toast flash before the window hides
    } else {
      setScreen("home");
    }
  }

  function handleEditorBack() {
    setScreen("home");
    if (editFromPopupRef.current) {
      editFromPopupRef.current = false;
      void getCurrentWindow().hide();
    }
  }

  async function handleCopy(dataUrl: string) {
    const base64 = dataUrl.replace(/^data:image\/png;base64,/, "");
    try {
      await invoke("copy_to_clipboard", { data: base64 });
      showToast("Copied to clipboard");
    } catch (e) {
      showToast(String(e), "error");
    }
  }

  // ── History management ────────────────────────────────────────────────────

  // Load the full-resolution PNG for a history item (history cards only hold a 640px thumbnail)
  async function loadHistoryFull(item: HistoryItem): Promise<string | null> {
    try {
      return await invoke<string>("get_history_full", { id: item.id });
    } catch (e) {
      showToast(String(e), "error");
      return null;
    }
  }

  async function handleDeleteHistory(id: string) {
    await deleteItem(id);
  }

  async function handleCopyHistory(item: HistoryItem) {
    const full = await loadHistoryFull(item);
    if (!full) return;
    try {
      await invoke("copy_to_clipboard", { data: full });
      showToast("Copied to clipboard");
    } catch (e) {
      showToast(String(e), "error");
    }
  }

  async function handlePin(item: HistoryItem) {
    const full = await loadHistoryFull(item);
    if (!full) return;
    try {
      await invoke("pin_screenshot", {
        data: full,
        imgWidth: item.width,
        imgHeight: item.height,
      });
    } catch (e) {
      showToast(String(e), "error");
    }
  }

  async function handleBackground(item: HistoryItem) {
    const full = await loadHistoryFull(item);
    if (full) setBackgroundSrc(full);
  }

  async function handleSelectHistory(item: HistoryItem) {
    const full = await loadHistoryFull(item);
    if (!full) return;
    editFromPopupRef.current = false; // editing inside the app — return home on Done
    setCaptureKey((k) => k + 1);
    setCapture({ data: full, width: item.width, height: item.height });
    setScreen("annotate");
  }

  // ─────────────────────────────────────────────────────────────────────────

  return (
    <div
      className="h-screen w-screen overflow-hidden flex flex-col"
      style={{ background: "var(--bg-window)", color: "var(--text-primary)" }}
    >
      {screen === "home" && (
        <div className="anim-screen-left" style={{ flex: 1, minHeight: 0, display: "flex", flexDirection: "column" }}>
          <CaptureHome
            onCapture={handleCapture}
            loading={loading}
            error={error}
            history={history}
            config={config}
            onDeleteHistory={handleDeleteHistory}
            onCopyHistory={handleCopyHistory}
            onSelectHistory={handleSelectHistory}
            onClearHistory={clearAll}
            onPinHistory={handlePin}
            onBackgroundHistory={handleBackground}
            onSettings={() => setScreen("settings")}
          />
        </div>
      )}
      {screen === "annotate" && capture && (
        <AnnotationCanvas
          key={captureKey}
          capture={capture}
          onBack={handleEditorBack}
          onDone={handleDone}
          onCopy={handleCopy}
          onBackground={(dataUrl) => setBackgroundSrc(dataUrl)}
        />
      )}
      {screen === "settings" && (
        <div className="anim-screen-right" style={{ flex: 1, minHeight: 0, display: "flex", flexDirection: "column" }}>
          <Settings onBack={() => setScreen("home")} />
        </div>
      )}
      {backgroundSrc && (
        <BackgroundTool
          imageSrc={backgroundSrc}
          onClose={() => setBackgroundSrc(null)}
        />
      )}
      {screen === "home" && screenPerm === false && (
        <PermissionBanner
          onOpenSettings={async () => {
            await invoke("request_screen_recording_permission").catch(() => {});
            await invoke("open_system_settings_permissions").catch(() => {});
          }}
          onRestart={() => invoke("restart_app")}
        />
      )}
      <ToastContainer toasts={toasts} />
    </div>
  );
}

export default App;
