import { useState, useEffect, useRef } from "react";
import { invoke } from "@tauri-apps/api/core";
import { enable, disable, isEnabled } from "@tauri-apps/plugin-autostart";
import { ArrowLeft, Folder, RotateCcw } from "lucide-react";
import { AppConfig, DEFAULT_CONFIG, formatShortcut } from "../utils";

/* Live preview of a filename template (mirrors the Rust render_filename) */
function previewFilename(template: string, format: string): string {
  const now = new Date();
  const pad = (n: number) => String(n).padStart(2, "0");
  const date = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
  const time = `${pad(now.getHours())}-${pad(now.getMinutes())}-${pad(now.getSeconds())}`;
  let name = template
    .replace("{date}", date)
    .replace("{time}", time)
    .replace("{unix}", String(Math.floor(now.getTime() / 1000)))
    .replace("{seq}", "0");
  name = name.replace(/[/\\:*?"<>|]/g, "-").trim();
  if (!name) name = "Screenshot";
  return `${name}.${format}`;
}

/* Small iOS-style toggle switch */
function Toggle({ on, onChange }: { on: boolean; onChange: (v: boolean) => void }) {
  return (
    <button
      onClick={() => onChange(!on)}
      style={{
        width: 38, height: 22, borderRadius: 999, border: "none", cursor: "pointer",
        background: on ? "#32D74B" : "rgba(255,255,255,0.18)",
        position: "relative", transition: "background 0.15s", flexShrink: 0, padding: 0,
      }}
    >
      <span style={{
        position: "absolute", top: 2, left: on ? 18 : 2,
        width: 18, height: 18, borderRadius: "50%", background: "#fff",
        transition: "left 0.15s", boxShadow: "0 1px 3px rgba(0,0,0,0.3)",
      }} />
    </button>
  );
}

interface Props {
  onBack: () => void;
}

export default function Settings({ onBack }: Props) {
  const [config, setConfig] = useState<AppConfig>(DEFAULT_CONFIG);
  const [recording, setRecording] = useState<keyof AppConfig | null>(null);
  const [saved, setSaved] = useState(false);
  const [screenRecordingGranted, setScreenRecordingGranted] = useState<boolean | null>(null);
  const [autoStart, setAutoStart] = useState(false);
  const badgeRefs = useRef<Partial<Record<keyof AppConfig, HTMLDivElement | null>>>({});

  useEffect(() => {
    invoke<AppConfig>("get_config").then(setConfig).catch(console.error);
    invoke<boolean>("check_screen_recording_permission")
      .then(setScreenRecordingGranted)
      .catch(() => setScreenRecordingGranted(null));
    isEnabled().then(setAutoStart).catch(() => {});
  }, []);

  async function toggleAutoStart(v: boolean) {
    try {
      if (v) await enable();
      else await disable();
      setAutoStart(v);
    } catch (e) {
      console.error(e);
    }
  }

  // Focus the badge when recording starts
  useEffect(() => {
    if (recording) {
      const el = badgeRefs.current[recording];
      if (el) el.focus();
    }
  }, [recording]);

  async function updateConfig(updated: AppConfig) {
    setConfig(updated);
    await invoke("save_config", { config: updated });
    setSaved(true);
    setTimeout(() => setSaved(false), 1500);
  }

  function handleKeyDown(e: React.KeyboardEvent, key: keyof AppConfig) {
    e.preventDefault();
    const parts: string[] = [];
    if (e.metaKey || e.ctrlKey) parts.push("CommandOrControl");
    if (e.shiftKey) parts.push("Shift");
    if (e.altKey) parts.push("Alt");
    const k = e.key.toUpperCase();
    if (
      (!["META", "CTRL", "SHIFT", "ALT", "CONTROL", "COMMAND"].includes(k) &&
        k.length === 1) ||
      /^F\d+$/.test(k)
    ) {
      parts.push(k);
      updateConfig({ ...config, [key]: parts.join("+") });
      setRecording(null);
    }
  }

  async function handlePickFolder() {
    const path = await invoke<string | null>("pick_folder");
    if (path !== null) updateConfig({ ...config, save_path: path });
  }

  const shortcutRows: { label: string; key: keyof AppConfig }[] = [
    { label: "Capture Area", key: "shortcut_area" },
    { label: "Capture Window", key: "shortcut_window" },
    { label: "Capture Fullscreen", key: "shortcut_fullscreen" },
    { label: "Recent Captures", key: "shortcut_history" },
  ];

  return (
    <div
      style={{
        height: "100%",
        background: "#1C1C1E",
        color: "rgba(255,255,255,0.88)",
        fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
        display: "flex",
        flexDirection: "column",
        userSelect: "none",
      }}
      onClick={() => {
        if (recording) setRecording(null);
      }}
    >
      {/* Traffic lights zone */}
      <div
        data-tauri-drag-region
        style={{ height: 38, flexShrink: 0, cursor: "default" }}
      />

      {/* Header — below traffic lights */}
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: 8,
          padding: "0 16px 14px 16px",
          borderBottom: "1px solid rgba(255,255,255,0.08)",
          flexShrink: 0,
        }}
      >
        <button
          onClick={onBack}
          style={{
            background: "none",
            border: "none",
            color: "rgba(255,255,255,0.55)",
            cursor: "pointer",
            padding: "4px 6px 4px 0",
            display: "flex",
            alignItems: "center",
          }}
        >
          <ArrowLeft size={14} />
        </button>
        <span style={{ fontSize: 13, fontWeight: 600, flex: 1 }}>Settings</span>
        {saved && (
          <span
            style={{
              fontSize: 11,
              color: "#30D158",
              transition: "opacity 0.3s",
            }}
          >
            Saved ✓
          </span>
        )}
      </div>

      {/* Content */}
      <div
        style={{
          flex: 1,
          overflowY: "auto",
          padding: 16,
        }}
      >
        {/* General section */}
        <div style={{ marginBottom: 24 }}>
          <div style={{
            fontSize: 11, textTransform: "uppercase", letterSpacing: "0.06em",
            color: "rgba(255,255,255,0.28)", marginBottom: 8,
          }}>
            General
          </div>
          <div style={{
            background: "rgba(255,255,255,0.04)", borderRadius: 8,
            border: "1px solid rgba(255,255,255,0.08)", overflow: "hidden",
          }}>
            <div style={{ display: "flex", alignItems: "center", padding: "10px 14px", gap: 12 }}>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 13 }}>Launch at login</div>
                <div style={{ fontSize: 11, color: "rgba(255,255,255,0.35)", marginTop: 2 }}>
                  Start Potret automatically when you log in
                </div>
              </div>
              <Toggle on={autoStart} onChange={toggleAutoStart} />
            </div>
            <div style={{
              display: "flex", alignItems: "center", padding: "10px 14px", gap: 12,
              borderTop: "1px solid rgba(255,255,255,0.08)",
            }}>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 13 }}>Hover for recent captures</div>
                <div style={{ fontSize: 11, color: "rgba(255,255,255,0.35)", marginTop: 2 }}>
                  Hover the bottom-left corner of the screen to show the last 5 captures
                </div>
              </div>
              <Toggle
                on={config.corner_popup_enabled}
                onChange={(v) => void updateConfig({ ...config, corner_popup_enabled: v })}
              />
            </div>
          </div>
        </div>

        {/* Keyboard Shortcuts section */}
        <div style={{ marginBottom: 24 }}>
          <div
            style={{
              fontSize: 11,
              textTransform: "uppercase",
              letterSpacing: "0.06em",
              color: "rgba(255,255,255,0.28)",
              marginBottom: 8,
            }}
          >
            Keyboard Shortcuts
          </div>
          <div
            style={{
              background: "rgba(255,255,255,0.04)",
              borderRadius: 8,
              border: "1px solid rgba(255,255,255,0.08)",
              overflow: "hidden",
            }}
          >
            {shortcutRows.map(({ label, key }, i) => {
              const isRecording = recording === key;
              const isLast = i === shortcutRows.length - 1;
              return (
                <div
                  key={key}
                  style={{
                    display: "flex",
                    alignItems: "center",
                    padding: "10px 14px",
                    borderBottom: isLast
                      ? "none"
                      : "1px solid rgba(255,255,255,0.06)",
                  }}
                >
                  <span style={{ fontSize: 13, flex: 1 }}>{label}</span>
                  <div
                    ref={(el) => {
                      badgeRefs.current[key] = el;
                    }}
                    tabIndex={0}
                    onClick={(e) => {
                      e.stopPropagation();
                      setRecording(isRecording ? null : key);
                    }}
                    onKeyDown={
                      isRecording ? (e) => handleKeyDown(e, key) : undefined
                    }
                    style={{
                      fontSize: 11,
                      fontFamily: isRecording
                        ? "-apple-system, BlinkMacSystemFont, sans-serif"
                        : "-apple-system, monospace",
                      fontStyle: isRecording ? "italic" : "normal",
                      background: isRecording
                        ? "rgba(10, 132, 255, 0.18)"
                        : "rgba(255,255,255,0.08)",
                      border: isRecording
                        ? "1px solid rgba(10, 132, 255, 0.4)"
                        : "1px solid rgba(255,255,255,0.1)",
                      borderRadius: 5,
                      padding: "3px 7px",
                      cursor: "pointer",
                      color: isRecording
                        ? "rgba(255,255,255,0.45)"
                        : "rgba(255,255,255,0.88)",
                      outline: "none",
                      minWidth: 60,
                      textAlign: "center",
                    }}
                  >
                    {isRecording
                      ? "Press shortcut…"
                      : formatShortcut(config[key] as string)}
                  </div>
                </div>
              );
            })}
          </div>

          {/* Reset defaults */}
          <div style={{ marginTop: 8, textAlign: "right" }}>
            <button
              onClick={() => updateConfig(DEFAULT_CONFIG)}
              style={{
                background: "none",
                border: "none",
                color: "rgba(255,255,255,0.35)",
                fontSize: 11,
                cursor: "pointer",
                display: "inline-flex",
                alignItems: "center",
                gap: 4,
                padding: "2px 0",
              }}
            >
              <RotateCcw size={10} />
              Reset to defaults
            </button>
          </div>
        </div>

        {/* Save Location section */}
        <div style={{ marginBottom: 24 }}>
          <div
            style={{
              fontSize: 11,
              textTransform: "uppercase",
              letterSpacing: "0.06em",
              color: "rgba(255,255,255,0.28)",
              marginBottom: 8,
            }}
          >
            Save Location
          </div>
          <div
            style={{
              background: "rgba(255,255,255,0.04)",
              borderRadius: 8,
              border: "1px solid rgba(255,255,255,0.08)",
              overflow: "hidden",
            }}
          >
            <div
              style={{
                display: "flex",
                alignItems: "center",
                padding: "10px 14px",
              }}
            >
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 13 }}>Screenshot folder</div>
                <div
                  style={{
                    fontSize: 11,
                    color: "rgba(255,255,255,0.35)",
                    marginTop: 2,
                    overflow: "hidden",
                    textOverflow: "ellipsis",
                    whiteSpace: "nowrap",
                  }}
                >
                  {config.save_path ?? "Default (App Support)"}
                </div>
              </div>
              <div style={{ display: "flex", alignItems: "center", gap: 8, flexShrink: 0 }}>
                {config.save_path && (
                  <button
                    onClick={() =>
                      updateConfig({ ...config, save_path: null })
                    }
                    style={{
                      background: "none",
                      border: "none",
                      color: "rgba(255,255,255,0.35)",
                      fontSize: 11,
                      cursor: "pointer",
                      padding: 0,
                    }}
                  >
                    Reset
                  </button>
                )}
                <button
                  onClick={handlePickFolder}
                  style={{
                    background: "rgba(255,255,255,0.08)",
                    border: "1px solid rgba(255,255,255,0.1)",
                    borderRadius: 5,
                    color: "rgba(255,255,255,0.75)",
                    fontSize: 11,
                    cursor: "pointer",
                    display: "inline-flex",
                    alignItems: "center",
                    gap: 5,
                    padding: "3px 9px",
                  }}
                >
                  <Folder size={11} />
                  Browse…
                </button>
              </div>
            </div>
          </div>
        </div>

        {/* Output section */}
        <div style={{ marginBottom: 24 }}>
          <div style={{
            fontSize: 11, textTransform: "uppercase", letterSpacing: "0.06em",
            color: "rgba(255,255,255,0.28)", marginBottom: 8,
          }}>
            Output
          </div>
          <div style={{
            background: "rgba(255,255,255,0.04)", borderRadius: 8,
            border: "1px solid rgba(255,255,255,0.08)", overflow: "hidden",
          }}>
            {/* Format */}
            <div style={{
              display: "flex", alignItems: "center", padding: "10px 14px",
              borderBottom: "1px solid rgba(255,255,255,0.06)",
            }}>
              <span style={{ fontSize: 13, flex: 1 }}>Format</span>
              <div style={{
                display: "flex", background: "rgba(255,255,255,0.06)",
                borderRadius: 6, padding: 2, gap: 2,
              }}>
                {(["png", "jpg"] as const).map((f) => (
                  <button
                    key={f}
                    onClick={() => updateConfig({ ...config, format: f })}
                    style={{
                      padding: "3px 12px", borderRadius: 5, border: "none", cursor: "pointer",
                      fontSize: 11, fontWeight: 500,
                      background: config.format === f ? "rgba(255,255,255,0.16)" : "transparent",
                      color: config.format === f ? "#fff" : "rgba(255,255,255,0.5)",
                    }}
                  >
                    {f.toUpperCase()}
                  </button>
                ))}
              </div>
            </div>

            {/* JPEG quality — only for jpg */}
            {config.format === "jpg" && (
              <div style={{
                display: "flex", alignItems: "center", gap: 12, padding: "10px 14px",
                borderBottom: "1px solid rgba(255,255,255,0.06)",
              }}>
                <span style={{ fontSize: 13, flex: 1 }}>
                  Quality <span style={{ color: "rgba(255,255,255,0.4)" }}>{config.jpeg_quality}</span>
                </span>
                <input
                  type="range" min={10} max={100} value={config.jpeg_quality}
                  onChange={(e) => updateConfig({ ...config, jpeg_quality: Number(e.target.value) })}
                  style={{ width: 140, accentColor: "#FF9F0A" }}
                />
              </div>
            )}

            {/* Filename template */}
            <div style={{ padding: "10px 14px" }}>
              <div style={{ fontSize: 13, marginBottom: 6 }}>Filename template</div>
              <input
                type="text"
                value={config.filename_template}
                onChange={(e) => updateConfig({ ...config, filename_template: e.target.value })}
                style={{
                  width: "100%", boxSizing: "border-box",
                  background: "rgba(255,255,255,0.06)",
                  border: "1px solid rgba(255,255,255,0.1)", borderRadius: 6,
                  color: "rgba(255,255,255,0.88)", fontSize: 12,
                  padding: "6px 9px", outline: "none",
                  fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
                }}
              />
              <div style={{ fontSize: 11, color: "rgba(255,255,255,0.35)", marginTop: 6 }}>
                {previewFilename(config.filename_template, config.format)}
              </div>
              <div style={{ fontSize: 10, color: "rgba(255,255,255,0.25)", marginTop: 4 }}>
                Tokens: {"{date}"} {"{time}"} {"{seq}"} {"{unix}"}
              </div>
            </div>
          </div>
        </div>

        {/* Permissions section */}
        <div style={{ marginBottom: 24 }}>
          <div style={{
            fontSize: 11, textTransform: "uppercase", letterSpacing: "0.06em",
            color: "rgba(255,255,255,0.28)", marginBottom: 8,
          }}>
            Permissions
          </div>
          <div style={{
            background: "rgba(255,255,255,0.04)", borderRadius: 8,
            border: "1px solid rgba(255,255,255,0.08)", overflow: "hidden",
          }}>
            {/* Screen Recording row */}
            <div style={{ display: "flex", alignItems: "center", padding: "12px 14px", gap: 12 }}>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 13, color: "rgba(255,255,255,0.88)" }}>Screen Recording</div>
                <div style={{ fontSize: 11, color: "rgba(255,255,255,0.35)", marginTop: 2 }}>
                  Required to capture the screen
                </div>
              </div>
              {/* Status badge */}
              <div style={{
                display: "flex", alignItems: "center", gap: 5,
                padding: "3px 8px", borderRadius: 20, fontSize: 11, fontWeight: 500,
                background: screenRecordingGranted === true
                  ? "rgba(50,215,75,0.12)" : screenRecordingGranted === false
                  ? "rgba(255,69,58,0.12)" : "rgba(255,255,255,0.06)",
                border: `1px solid ${screenRecordingGranted === true
                  ? "rgba(50,215,75,0.3)" : screenRecordingGranted === false
                  ? "rgba(255,69,58,0.3)" : "rgba(255,255,255,0.1)"}`,
                color: screenRecordingGranted === true ? "#32D74B"
                  : screenRecordingGranted === false ? "#FF453A"
                  : "rgba(255,255,255,0.4)",
              }}>
                <div style={{
                  width: 6, height: 6, borderRadius: "50%",
                  background: screenRecordingGranted === true ? "#32D74B"
                    : screenRecordingGranted === false ? "#FF453A"
                    : "rgba(255,255,255,0.3)",
                }} />
                {screenRecordingGranted === true ? "Granted"
                  : screenRecordingGranted === false ? "Not granted"
                  : "Unknown"}
              </div>
              {screenRecordingGranted !== true && (
                <button
                  onClick={async () => {
                    await invoke("request_screen_recording_permission");
                    await invoke("open_system_settings_permissions");
                  }}
                  style={{
                    background: "rgba(255,159,10,0.12)", border: "1px solid rgba(255,159,10,0.3)",
                    borderRadius: 6, color: "#FF9F0A", fontSize: 11, fontWeight: 500,
                    cursor: "pointer", padding: "4px 10px",
                  }}
                >
                  Open Settings →
                </button>
              )}
            </div>
          </div>
          {screenRecordingGranted === false && (
            <p style={{
              fontSize: 11, color: "rgba(255,159,10,0.8)", marginTop: 8,
              lineHeight: 1.5,
            }}>
              Grant Screen Recording in System Settings → Privacy & Security, then restart Potret.
            </p>
          )}
        </div>
      </div>
    </div>
  );
}
