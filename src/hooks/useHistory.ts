import { useState, useEffect, useCallback } from "react";
import { invoke } from "@tauri-apps/api/core";
import { HistoryItem } from "../App";

export function useHistory(limit?: number) {
  const [items, setItems] = useState<HistoryItem[]>([]);

  const loadHistory = useCallback(async () => {
    try {
      // Rust serializes snake_case fields and stores unix SECONDS — normalize here
      const raw = await invoke<Array<Record<string, unknown>>>("get_history", { limit: limit ?? null });
      const history: HistoryItem[] = (raw ?? []).map((h) => ({
        id: h.id as string,
        path: h.path as string,
        thumbnail: h.thumbnail as string,
        timestamp: (h.timestamp as number) * 1000, // seconds → ms for JS Date
        width: h.width as number,
        height: h.height as number,
        fileSize: h.file_size as number, // snake_case → camelCase
      }));
      setItems(history);
    } catch {
      // Backend command may not exist yet — gracefully return empty
      setItems([]);
    }
  }, [limit]);

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
