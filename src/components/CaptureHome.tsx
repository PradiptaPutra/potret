import { Loader2, Settings } from "lucide-react";
import { HistoryItem } from "../App";
import { AppConfig, formatShortcut } from "../utils";
import HistoryPanel from "./HistoryPanel";

interface Props {
  onCapture: (mode: "fullscreen" | "area" | "window") => void;
  loading: string | null;
  error: string | null;
  history: HistoryItem[];
  config: AppConfig;
  onDeleteHistory: (id: string) => void;
  onCopyHistory: (item: HistoryItem) => void;
  onSelectHistory: (item: HistoryItem) => void;
  onClearHistory: () => void;
  onPinHistory: (item: HistoryItem) => void;
  onBackgroundHistory: (item: HistoryItem) => void;
  onSettings: () => void;
}

/* ── Icons — distinct SVG per mode, consistent 1.5px stroke ─────────── */
const AreaIcon = () => (
  <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round">
    <circle cx="8" cy="8" r="1.5" />
    <line x1="8" y1="1.5" x2="8" y2="4.5" />
    <line x1="8" y1="11.5" x2="8" y2="14.5" />
    <line x1="1.5" y1="8" x2="4.5" y2="8" />
    <line x1="11.5" y1="8" x2="14.5" y2="8" />
  </svg>
);

const WindowIcon = () => (
  <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
    <rect x="1.5" y="2.5" width="13" height="11" rx="1.5" />
    <line x1="1.5" y1="6.5" x2="14.5" y2="6.5" />
    <circle cx="3.75" cy="4.5" r="0.75" fill="currentColor" stroke="none" />
    <circle cx="6"    cy="4.5" r="0.75" fill="currentColor" stroke="none" />
  </svg>
);

const FullscreenIcon = () => (
  <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
    <polyline points="1,4.5 1,1 4.5,1" />
    <polyline points="11.5,1 15,1 15,4.5" />
    <polyline points="15,11.5 15,15 11.5,15" />
    <polyline points="4.5,15 1,15 1,11.5" />
  </svg>
);

export default function CaptureHome({
  onCapture,
  loading,
  error,
  history,
  config,
  onDeleteHistory,
  onCopyHistory,
  onSelectHistory,
  onClearHistory,
  onPinHistory,
  onBackgroundHistory,
  onSettings,
}: Props) {
  const modes = [
    { key: "area"       as const, Icon: AreaIcon,       label: "Area",       desc: "Select a region",  shortcut: formatShortcut(config.shortcut_area) },
    { key: "window"     as const, Icon: WindowIcon,     label: "Window",     desc: "Click any window", shortcut: formatShortcut(config.shortcut_window) },
    { key: "fullscreen" as const, Icon: FullscreenIcon, label: "Fullscreen", desc: "Entire display",   shortcut: formatShortcut(config.shortcut_fullscreen) },
  ];
  return (
    <div
      className="flex h-full w-full overflow-hidden"
      style={{ background: "var(--bg-window)" }}
    >
      {/* ── SIDEBAR ─────────────────────────────────────────────────── */}
      <aside
        className="flex flex-col shrink-0"
        style={{
          width: 220,
          background: "var(--bg-panel)",
          borderRight: "1px solid var(--border)",
        }}
      >
        {/* Traffic lights zone — native buttons overlay here, content stays clear */}
        <div
          data-tauri-drag-region
          style={{ height: 38, flexShrink: 0, cursor: "default" }}
        />

        {/* App identity — sits below the traffic lights */}
        <div style={{
          display: "flex", alignItems: "center", gap: 8,
          padding: "0 16px 14px 16px",
          borderBottom: "1px solid var(--border)",
          flexShrink: 0,
        }}>
          <img
            src="/app-icon.png"
            style={{ width: 22, height: 22, borderRadius: 5, flexShrink: 0 }}
            alt=""
          />
          <span style={{ fontSize: 13, fontWeight: 600, color: "var(--text-primary)", letterSpacing: "-0.01em" }}>
            Potret
          </span>
        </div>

        <div style={{ height: 8 }} />

        {/* Capture buttons */}
        <div style={{ display: "flex", flexDirection: "column" }}>
          {modes.map(({ key, Icon, label, desc, shortcut }) => (
            <CaptureBtn
              key={key}
              Icon={Icon}
              label={label}
              desc={desc}
              shortcut={shortcut}
              disabled={!!loading}
              onClick={() => !loading && onCapture(key)}
            />
          ))}
        </div>

        {/* Loading / error pill */}
        {(loading || error) && (
          <div style={{ margin: "0 12px 8px" }}>
            <div
              style={{
                display: "flex", alignItems: "center", gap: 8,
                padding: "6px 10px",
                borderRadius: 6,
                background: loading ? "var(--accent-dim)" : "rgba(255,69,58,0.10)",
                border: `1px solid ${loading ? "var(--accent-border)" : "rgba(255,69,58,0.25)"}`,
              }}
            >
              {loading && (
                <Loader2 style={{ width: 11, height: 11, color: "var(--accent)", flexShrink: 0 }} className="animate-spin" />
              )}
              <span style={{ fontSize: 11, color: loading ? "var(--accent)" : "var(--red)" }}>
                {loading ?? error}
              </span>
            </div>
          </div>
        )}

        <div className="flex-1" />

        {/* Footer */}
        <div style={{
          borderTop: "1px solid var(--border)",
          padding: "8px 16px",
          display: "flex", alignItems: "center", justifyContent: "space-between",
        }}>
          <span style={{ fontSize: 10, color: "var(--text-tertiary)" }}>
            v0.1.0
          </span>
          <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
            <button
              onClick={onSettings}
              title="Settings"
              style={{
                background: "none", border: "none", cursor: "pointer",
                color: "var(--text-tertiary)", padding: 0, display: "flex",
                alignItems: "center",
              }}
              onMouseEnter={e => (e.currentTarget.style.color = "var(--text-primary)")}
              onMouseLeave={e => (e.currentTarget.style.color = "var(--text-tertiary)")}
            >
              <Settings size={13} />
            </button>
            <a
              href="https://github.com/aditpradipta/potret"
              target="_blank"
              rel="noreferrer"
              style={{ fontSize: 10, color: "var(--text-tertiary)", textDecoration: "none" }}
              onMouseEnter={e => (e.currentTarget.style.color = "var(--accent)")}
              onMouseLeave={e => (e.currentTarget.style.color = "var(--text-tertiary)")}
            >
              GitHub ↗
            </a>
          </div>
        </div>
      </aside>

      {/* ── MAIN ─────────────────────────────────────────────────────── */}
      <main className="flex-1 flex flex-col overflow-hidden" style={{ background: "var(--bg-window)" }}>
        <HistoryPanel
          items={history}
          onSelect={onSelectHistory}
          onDelete={onDeleteHistory}
          onCopy={onCopyHistory}
          onClear={onClearHistory}
          onPin={onPinHistory}
          onBackground={onBackgroundHistory}
          loading={false}
        />
      </main>
    </div>
  );
}

/* ── Capture button ─────────────────────────────────────────────────── */
interface CaptureBtnProps {
  Icon: React.ComponentType;
  label: string;
  desc: string;
  shortcut: string;
  disabled: boolean;
  onClick: () => void;
}

function CaptureBtn({ Icon, label, desc, shortcut, disabled, onClick }: CaptureBtnProps) {
  return (
    <button
      className="sidebar-btn"
      onClick={onClick}
      disabled={disabled}
      style={{
        position: "relative",
        display: "flex",
        alignItems: "center",
        gap: 10,
        padding: "7px 16px",
        background: "transparent",
        border: "none",
        width: "100%",
        cursor: disabled ? "not-allowed" : "pointer",
        borderRadius: 0,
        opacity: disabled ? 0.4 : 1,
        transition: "background 0.12s",
      }}
    >
      {/* Amber left accent — visible on hover via CSS */}
      <div
        className="capture-btn-accent"
        style={{
          position: "absolute",
          left: 0,
          top: 5,
          bottom: 5,
          width: 2,
          borderRadius: 2,
          background: "var(--accent)",
          opacity: 0,
          transition: "opacity 0.12s",
        }}
      />

      {/* Icon — bare, no surrounding box */}
      <div
        className="capture-btn-icon"
        style={{
          display: "flex", alignItems: "center", justifyContent: "center",
          flexShrink: 0,
          width: 16, height: 16,
          color: "var(--text-tertiary)",
          transition: "color 0.12s",
        }}
      >
        <Icon />
      </div>

      {/* Label + description */}
      <div style={{ flex: 1, minWidth: 0, textAlign: "left" }}>
        <div
          className="capture-btn-label"
          style={{
            fontSize: 13,
            fontWeight: 500,
            color: "var(--text-primary)",
            lineHeight: 1,
            transition: "color 0.12s",
          }}
        >
          {label}
        </div>
        <div style={{ fontSize: 11, color: "var(--text-secondary)", marginTop: 2, lineHeight: 1 }}>
          {desc}
        </div>
      </div>

      {/* Shortcut badge */}
      <kbd style={{
        flexShrink: 0,
        fontSize: 10,
        fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
        fontWeight: 500,
        color: "var(--text-tertiary)",
        background: "rgba(255,255,255,0.06)",
        border: "1px solid var(--border)",
        borderRadius: 4,
        padding: "1px 5px",
        lineHeight: 1.6,
      }}>
        {shortcut}
      </kbd>
    </button>
  );
}
