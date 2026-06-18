import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { save } from "@tauri-apps/plugin-dialog";
import CaptureHome from "./components/CaptureHome";
import AnnotationCanvas from "./components/AnnotationCanvas";
import "./index.css";

export type AppScreen = "home" | "annotate";

export interface CaptureData {
  data: string; // base64 PNG
  width: number;
  height: number;
}

function App() {
  const [screen, setScreen] = useState<AppScreen>("home");
  const [capture, setCapture] = useState<CaptureData | null>(null);
  const [loading, setLoading] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function handleCapture(mode: "fullscreen" | "area" | "window") {
    setError(null);
    setLoading(
      mode === "fullscreen"
        ? "Capturing screen..."
        : mode === "area"
        ? "Select an area..."
        : "Click a window..."
    );

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
      } else {
        setError(result.error ?? "Capture failed");
      }
    } catch (e) {
      setError(String(e));
    } finally {
      setLoading(null);
    }
  }

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

  return (
    <div className="h-screen w-screen bg-gray-950 text-white overflow-hidden flex flex-col">
      {screen === "home" && (
        <CaptureHome
          onCapture={handleCapture}
          loading={loading}
          error={error}
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
    </div>
  );
}

export default App;
