import { useEffect, useRef } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen, emit } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import HistoryPanel from "./HistoryPanel";
import { useHistory } from "../hooks/useHistory";
import { HistoryItem } from "../App";

// Menubar "Recent Captures" popup — a standalone window so you can browse, copy,
// pin, edit, or delete recent screenshots without opening the full app.
export default function HistoryPopupWindow() {
  const { items, loadHistory, deleteItem, clearAll } = useHistory();
  const reloadTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    document.body.classList.add("overlay-window"); // transparent body → rounded window
    document.documentElement.style.background = "transparent";
  }, []);

  // Refresh when a new capture is persisted, and whenever the popup regains focus.
  useEffect(() => {
    let unlisten: (() => void) | undefined;
    listen("history-updated", () => {
      if (reloadTimer.current) clearTimeout(reloadTimer.current);
      reloadTimer.current = setTimeout(() => void loadHistory(), 80);
    }).then((fn) => {
      unlisten = fn;
    });
    const onFocus = () => void loadHistory();
    window.addEventListener("focus", onFocus);
    return () => {
      unlisten?.();
      window.removeEventListener("focus", onFocus);
      if (reloadTimer.current) clearTimeout(reloadTimer.current);
    };
  }, [loadHistory]);

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
  }

  async function onPin(item: HistoryItem) {
    const full = await loadFull(item.id);
    if (full) await invoke("pin_screenshot", { data: full, imgWidth: item.width, imgHeight: item.height });
  }

  // Edit / Background need the full editor — open the main window, hand off the
  // item id, and hide this popup.
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

  return (
    <div
      className="anim-overlay-in"
      style={{
        height: "100vh",
        width: "100vw",
        overflow: "hidden",
        display: "flex",
        flexDirection: "column",
        background: "var(--bg-window)",
        color: "var(--text-primary)",
        borderRadius: 14,
        border: "1px solid var(--border)",
        boxShadow: "0 20px 60px rgba(0,0,0,0.7)",
      }}
    >
      <HistoryPanel
        items={items}
        loading={false}
        onSelect={onSelect}
        onCopy={onCopy}
        onPin={onPin}
        onBackground={onBackground}
        onDelete={(id) => void deleteItem(id)}
        onClear={() => void clearAll()}
      />
    </div>
  );
}
