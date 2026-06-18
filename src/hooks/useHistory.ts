import { useState, useEffect, useCallback } from "react";
import { invoke } from "@tauri-apps/api/core";
import { HistoryItem } from "../App";

export function useHistory() {
  const [items, setItems] = useState<HistoryItem[]>([]);

  const loadHistory = useCallback(async () => {
    try {
      const history = await invoke<HistoryItem[]>("get_history");
      setItems(history ?? []);
    } catch {
      // Backend command may not exist yet — gracefully return empty
      setItems([]);
    }
  }, []);

  const deleteItem = useCallback(async (id: string) => {
    try {
      await invoke("delete_history_item", { id });
    } catch {
      // Ignore if backend command doesn't exist yet
    }
    setItems((prev) => prev.filter((item) => item.id !== id));
  }, []);

  const clearAll = useCallback(async () => {
    try {
      await invoke("clear_history");
    } catch {
      // Ignore if backend command doesn't exist yet
    }
    setItems([]);
  }, []);

  // Auto-load on mount
  useEffect(() => {
    loadHistory();
  }, [loadHistory]);

  return { items, loadHistory, deleteItem, clearAll };
}
