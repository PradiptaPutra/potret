import { useState, useEffect, useCallback } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { save } from "@tauri-apps/plugin-dialog";
import CaptureHome from "./components/CaptureHome";
import AnnotationCanvas from "./components/AnnotationCanvas";
import CaptureOverlay from "./components/CaptureOverlay";
import { useHistory } from "./hooks/useHistory";
import "./index.css";

export type AppScreen = "home" | "annotate";

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
    <div className="fixed bottom-4 left-1/2 -translate-x-1/2 flex flex-col gap-2 z-50 pointer-events-none">
      {toasts.map((t) => (
        <div
          key={t.id}
          className={`px-4 py-2.5 rounded-xl text-sm font-medium shadow-lg transition-all duration-300
            ${t.type === "success"
              ? "bg-violet-600 text-white"
              : "bg-red-600 text-white"
            }`}
        >
          {t.message}
        </div>
      ))}
    </div>
  );
}

// ─── App ─────────────────────────────────────────────────────────────────────

function App() {
  const [screen, setScreen] = useState<AppScreen>("home");
  const [capture, setCapture] = useState<CaptureData | null>(null);
  const [loading, setLoading] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [toasts, setToasts] = useState<Toast[]>([]);
  const [capturing, setCapturing] = useState(false);

  const { items: history, loadHistory, deleteItem, clearAll } = useHistory();

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
      setError(null);
      setLoading(
        mode === "fullscreen"
          ? "Capturing screen..."
          : mode === "area"
          ? "Select an area..."
          : "Click a window..."
      );
      setCapturing(true);

      try {
        const cmd =
          mode === "fullscreen"
            ? "capture_fullscreen"
            : mode === "area"
            ? "capture_area"
            : "capture_window";

        const result = await invoke<{
          success: boolean;
          screenshot: CaptureData | null;
          error: string | null;
        }>(cmd);

        if (result.success && result.screenshot) {
          setCapture(result.screenshot);
          setScreen("annotate");
          showToast("Screenshot captured! Click to annotate.");
          // Reload history after a successful capture
          await loadHistory();
        } else {
          const msg = result.error ?? "Capture failed";
          setError(msg);
          showToast(msg, "error");
        }
      } catch (e) {
        const msg = String(e);
        setError(msg);
        showToast(msg, "error");
      } finally {
        setLoading(null);
        setTimeout(() => setCapturing(false), 500);
      }
    },
    [showToast, loadHistory]
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
    });

    return () => {
      unlisten?.();
    };
  }, [handleCapture]);

  // ── Window keyboard shortcuts ─────────────────────────────────────────────

  useEffect(() => {
    function onKeyDown(e: KeyboardEvent) {
      if (screen === "annotate") {
        // Escape → go back to home (with confirmation if there are changes)
        if (e.key === "Escape") {
          e.preventDefault();
          const confirmed = window.confirm(
            "Go back to home? Unsaved annotations will be lost."
          );
          if (confirmed) setScreen("home");
          return;
        }

        // ⌘Z → undo (dispatch custom event that AnnotationCanvas can listen for)
        if ((e.metaKey || e.ctrlKey) && e.key === "z" && !e.shiftKey) {
          e.preventDefault();
          window.dispatchEvent(new CustomEvent("annotation:undo"));
          return;
        }

        // ⌘S → save
        if ((e.metaKey || e.ctrlKey) && e.key === "s") {
          e.preventDefault();
          window.dispatchEvent(new CustomEvent("annotation:save"));
          return;
        }
      }
    }

    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [screen]);

  // ── Save / Copy ────────────────────────────────────────────────────────────

  async function handleSave(dataUrl: string) {
    const base64 = dataUrl.replace(/^data:image\/png;base64,/, "");
    const path = await save({
      defaultPath: `potret-${Date.now()}.png`,
      filters: [{ name: "PNG Image", extensions: ["png"] }],
    });
    if (path) {
      await invoke("save_image", { data: base64, path });
    }
  }

  async function handleCopy(dataUrl: string) {
    const base64 = dataUrl.replace(/^data:image\/png;base64,/, "");
    await invoke("copy_to_clipboard", { data: base64 });
  }

  // ── History management ────────────────────────────────────────────────────

  async function handleDeleteHistory(id: string) {
    await deleteItem(id);
  }

  async function handleCopyHistory(item: HistoryItem) {
    try {
      await invoke("copy_to_clipboard", { data: item.thumbnail });
    } catch (e) {
      showToast(String(e), "error");
    }
  }

  function handleSelectHistory(item: HistoryItem) {
    // Use the thumbnail as the capture data for now (full data may not be
    // separately stored yet — the thumbnail is good enough for re-annotation)
    setCapture({
      data: item.thumbnail,
      width: item.width,
      height: item.height,
    });
    setScreen("annotate");
  }

  // ─────────────────────────────────────────────────────────────────────────

  return (
    <div
      className="h-screen w-screen overflow-hidden flex flex-col"
      style={{ background: "var(--bg-base)", color: "var(--text-primary)" }}
    >
      {screen === "home" && (
        <CaptureHome
          onCapture={handleCapture}
          loading={loading}
          error={error}
          history={history}
          onDeleteHistory={handleDeleteHistory}
          onCopyHistory={handleCopyHistory}
          onSelectHistory={handleSelectHistory}
          onClearHistory={clearAll}
        />
      )}
      {screen === "annotate" && capture && (
        <AnnotationCanvas
          capture={capture}
          onBack={() => setScreen("home")}
          onSave={handleSave}
          onCopy={handleCopy}
        />
      )}
      <CaptureOverlay active={capturing} />
      <ToastContainer toasts={toasts} />
    </div>
  );
}

export default App;
