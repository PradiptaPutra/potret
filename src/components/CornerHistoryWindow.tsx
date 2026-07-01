import { useEffect, useRef } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen, emit } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { startDrag } from "@crabnebula/tauri-plugin-drag";
import { ImageIcon, Pin, Copy, Pencil, Trash2 } from "lucide-react";
import { useHistory } from "../hooks/useHistory";
import { HistoryItem } from "../App";

const HOVER_CLOSE_DELAY_MS = 260;
const RECENT_COUNT = 5;

// Bottom-left hover popup — hovering the screen's bottom-left corner (after a brief dwell,
// handled Rust-side) shows the last 5 captures as a bare fanned stack, no frame/header —
// just the thumbnails, same copy/drag/edit actions as the menubar (Cmd+Shift+H) popup.
// Closing is owned entirely by this component: mouse-leave debounce, Esc, or any interaction.
export default function CornerHistoryWindow() {
  const { items, loadHistory, deleteItem } = useHistory(RECENT_COUNT);
  const reloadTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const closeTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    document.body.classList.add("overlay-window");
    document.documentElement.style.background = "transparent";
  }, []);

  useEffect(() => {
    let unlistenUpdate: (() => void) | undefined;
    let unlistenShown: (() => void) | undefined;
    const reload = () => {
      if (reloadTimer.current) clearTimeout(reloadTimer.current);
      reloadTimer.current = setTimeout(() => void loadHistory(), 80);
    };
    listen("history-updated", reload)
      .then((fn) => { unlistenUpdate = fn; })
      .catch((err) => console.error("failed to listen for history-updated:", err));
    // Rust doesn't focus this window on show (so it doesn't steal focus from the
    // foreground app), so we can't rely on a `window focus` event to refresh — Rust
    // emits this explicitly right after showing the popup instead.
    listen("corner-popup-shown", reload)
      .then((fn) => { unlistenShown = fn; })
      .catch((err) => console.error("failed to listen for corner-popup-shown:", err));
    return () => {
      unlistenUpdate?.();
      unlistenShown?.();
      if (reloadTimer.current) clearTimeout(reloadTimer.current);
    };
  }, [loadHistory]);

  useEffect(() => {
    function onKeyDown(e: KeyboardEvent) {
      if (e.key === "Escape") void getCurrentWindow().hide();
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, []);

  function scheduleClose() {
    if (closeTimer.current) clearTimeout(closeTimer.current);
    closeTimer.current = setTimeout(() => void getCurrentWindow().hide(), HOVER_CLOSE_DELAY_MS);
  }
  function cancelClose() {
    if (closeTimer.current) {
      clearTimeout(closeTimer.current);
      closeTimer.current = null;
    }
  }

  async function loadFull(id: string): Promise<string | null> {
    try {
      return await invoke<string>("get_history_full", { id });
    } catch {
      return null;
    }
  }

  async function onCopy(item: HistoryItem) {
    const full = await loadFull(item.id);
    if (full) await invoke("copy_to_clipboard", { data: full });
    void getCurrentWindow().hide();
  }

  async function onPin(item: HistoryItem) {
    const full = await loadFull(item.id);
    if (full) await invoke("pin_screenshot", { data: full, imgWidth: item.width, imgHeight: item.height });
  }

  async function onSelect(item: HistoryItem) {
    await invoke("open_main_for_edit");
    await emit("history-edit-requested", { id: item.id, width: item.width, height: item.height });
    void getCurrentWindow().hide();
  }

  async function onBackground(item: HistoryItem) {
    await invoke("open_main_for_edit");
    await emit("history-background-requested", { id: item.id });
    void getCurrentWindow().hide();
  }

  async function onDragStart(e: React.DragEvent, item: HistoryItem) {
    e.preventDefault();  // cancel the HTML5 drag; use a native OS file drag instead
    e.stopPropagation();
    try {
      const path = await invoke<string>("stage_history_for_drag", { id: item.id });
      await startDrag({ item: [path], icon: path });
      void getCurrentWindow().hide();
    } catch (err) {
      console.error(err);
    }
  }

  const recent = items.slice(0, RECENT_COUNT);

  return (
    <div
      className="corner-stack"
      onMouseEnter={cancelClose}
      onMouseLeave={scheduleClose}
      style={{
        height: "100vh",
        width: "100vw",
        overflow: "hidden",
        display: "flex",
        flexDirection: "column-reverse",
        justifyContent: "flex-end",
        alignItems: "flex-start",
        gap: 8,
        padding: 14,
      }}
    >
      {recent.map((item) => (
        <div
          key={item.id}
          className="corner-stack-item"
          onClick={() => onSelect(item)}
          draggable
          onDragStart={(e) => onDragStart(e, item)}
        >
          {item.thumbnail ? (
            <img
              src={`data:image/png;base64,${item.thumbnail}`}
              alt="Screenshot"
              title="Drag to another app"
              draggable={false}
              style={{ width: 190, aspectRatio: "16/10", objectFit: "cover", display: "block", cursor: "grab" }}
            />
          ) : (
            <div style={{ width: 190, aspectRatio: "16/10", background: "#111" }} />
          )}
          <div className="corner-stack-actions">
            <button title="Background" onClick={(e) => { e.stopPropagation(); void onBackground(item); }}>
              <ImageIcon size={10} />
            </button>
            <button title="Pin" onClick={(e) => { e.stopPropagation(); void onPin(item); }}>
              <Pin size={10} />
            </button>
            <button title="Copy" onClick={(e) => { e.stopPropagation(); void onCopy(item); }}>
              <Copy size={10} />
            </button>
            <button title="Edit" onClick={(e) => { e.stopPropagation(); void onSelect(item); }}>
              <Pencil size={10} />
            </button>
            <button title="Delete" className="danger" onClick={(e) => { e.stopPropagation(); void deleteItem(item.id); }}>
              <Trash2 size={10} />
            </button>
          </div>
        </div>
      ))}
    </div>
  );
}
