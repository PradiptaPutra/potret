export interface AppConfig {
  shortcut_area: string;
  shortcut_window: string;
  shortcut_fullscreen: string;
  save_path: string | null;
  format: "png" | "jpg";
  jpeg_quality: number;
  filename_template: string;
}

export const DEFAULT_CONFIG: AppConfig = {
  shortcut_area: "CommandOrControl+Shift+4",
  shortcut_window: "CommandOrControl+Shift+5",
  shortcut_fullscreen: "CommandOrControl+Shift+3",
  save_path: null,
  format: "png",
  jpeg_quality: 90,
  filename_template: "Screenshot {date} at {time}",
};

export function formatShortcut(s: string): string {
  return s
    .replace("CommandOrControl", "⌘")
    .replace("Command", "⌘")
    .replace("Control", "⌃")
    .replace("Shift", "⇧")
    .replace("Alt", "⌥")
    .replace(/\+/g, "");
}
