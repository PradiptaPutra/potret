import { Loader2 } from "lucide-react";
import { HistoryItem } from "../App";
import HistoryPanel from "./HistoryPanel";

interface Props {
  onCapture: (mode: "fullscreen" | "area" | "window") => void;
  loading: string | null;
  error: string | null;
  history: HistoryItem[];
  onDeleteHistory: (id: string) => void;
  onCopyHistory: (item: HistoryItem) => void;
  onSelectHistory: (item: HistoryItem) => void;
  onClearHistory: () => void;
}

/* ── Distinct SVG icons per mode ─────────────────────────────────── */
const AreaIcon = () => (
  <svg width="15" height="15" viewBox="0 0 15 15" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round">
    <line x1="1" y1="7.5" x2="4.5" y2="7.5" />
    <line x1="10.5" y1="7.5" x2="14" y2="7.5" />
    <line x1="7.5" y1="1" x2="7.5" y2="4.5" />
    <line x1="7.5" y1="10.5" x2="7.5" y2="14" />
    <circle cx="7.5" cy="7.5" r="1.25" />
  </svg>
);

const WindowIcon = () => (
  <svg width="15" height="15" viewBox="0 0 15 15" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
    <rect x="1.5" y="2.5" width="12" height="10" rx="1.5" />
    <line x1="1.5" y1="6" x2="13.5" y2="6" />
    <circle cx="3.75" cy="4.25" r="0.75" fill="currentColor" stroke="none" />
  </svg>
);

const FullscreenIcon = () => (
  <svg width="15" height="15" viewBox="0 0 15 15" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
    <polyline points="1,4 1,1 4,1" />
    <polyline points="11,1 14,1 14,4" />
    <polyline points="14,11 14,14 11,14" />
    <polyline points="4,14 1,14 1,11" />
  </svg>
);

const modes = [
  { key: "area" as const,       Icon: AreaIcon,       label: "Area",       desc: "Select a region",   shortcut: "⌘⇧4" },
  { key: "window" as const,     Icon: WindowIcon,     label: "Window",     desc: "Click any window",  shortcut: "⌘⇧5" },
  { key: "fullscreen" as const, Icon: FullscreenIcon, label: "Fullscreen", desc: "Entire display",    shortcut: "⌘⇧3" },
];

export default function CaptureHome({
  onCapture,
  loading,
  error,
  history,
  onDeleteHistory,
  onCopyHistory,
  onSelectHistory,
  onClearHistory,
}: Props) {
  return (
    <div className="flex h-full w-full overflow-hidden" style={{ background: "var(--bg-base)" }}>

      {/* ── SIDEBAR ── */}
      <aside
        className="flex flex-col shrink-0"
        style={{
          width: 220,
          background: "var(--bg-surface)",
          borderRight: "1px solid var(--border-default)",
        }}
      >
        {/* App name — compact, no icon (OS titlebar handles branding) */}
        <div
          className="flex items-center gap-2 px-4 py-3"
          style={{ borderBottom: "1px solid var(--border-subtle)" }}
        >
          <div
            style={{
              width: 8, height: 8, borderRadius: "50%",
              background: "var(--accent)", flexShrink: 0,
            }}
          />
          <span style={{ fontSize: 12, fontWeight: 600, color: "var(--text-primary)", letterSpacing: "-0.01em" }}>
            Potret
          </span>
        </div>

        {/* Section label */}
        <div className="px-4 pt-3 pb-1">
          <span style={{ fontSize: 9.5, fontWeight: 700, textTransform: "uppercase", letterSpacing: "0.1em", color: "var(--text-muted)" }}>
            Capture
          </span>
        </div>

        {/* Capture mode buttons */}
        <div className="flex flex-col px-2">
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

        {/* Loading / error status */}
        {(loading || error) && (
          <div
            className="mx-3 mt-2 px-2.5 py-2 rounded"
            style={{ background: "rgba(255,255,255,0.03)", border: "1px solid var(--border-default)" }}
          >
            {loading && (
              <div className="flex items-center gap-1.5" style={{ color: "var(--accent)" }}>
                <Loader2 style={{ width: 11, height: 11 }} className="animate-spin shrink-0" />
                <span style={{ fontSize: 11 }}>{loading}</span>
              </div>
            )}
            {error && !loading && (
              <p style={{ fontSize: 11, color: "var(--accent-red)" }}>{error}</p>
            )}
          </div>
        )}

        <div className="flex-1" />

        {/* Footer */}
        <div
          className="px-4 py-3 flex items-center justify-between"
          style={{ borderTop: "1px solid var(--border-subtle)" }}
        >
          <span style={{ fontSize: 10, fontFamily: "'SF Mono', 'Menlo', monospace", color: "var(--text-muted)" }}>
            v0.1.0
          </span>
          <a
            href="https://github.com/aditpradipta/potret"
            target="_blank"
            rel="noreferrer"
            style={{ fontSize: 10, color: "var(--text-muted)", textDecoration: "none" }}
          >
            GitHub ↗
          </a>
        </div>
      </aside>

      {/* ── MAIN ── */}
      <main className="flex-1 flex flex-col overflow-hidden">
        <HistoryPanel
          items={history}
          onSelect={onSelectHistory}
          onDelete={onDeleteHistory}
          onCopy={onCopyHistory}
          onClear={onClearHistory}
          loading={false}
        />
      </main>
    </div>
  );
}

/* ── Capture button ─────────────────────────────────────────────── */
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
      onClick={onClick}
      disabled={disabled}
      title={label}
      className="group relative flex items-center gap-2.5 w-full text-left transition-colors rounded-md
                 disabled:opacity-40 disabled:cursor-not-allowed cursor-pointer"
      style={{ padding: "8px 10px", background: "transparent", border: "none" }}
    >
      {/* Amber left accent — hidden until hover via CSS class */}
      <div
        className="capture-btn-accent"
        style={{
          position: "absolute",
          left: 0, top: 6, bottom: 6,
          width: 2,
          borderRadius: 2,
          background: "var(--accent)",
          opacity: 0,
          transition: "opacity 0.1s",
        }}
      />

      {/* Icon box */}
      <div
        className="capture-btn-icon flex items-center justify-center shrink-0 rounded"
        style={{
          width: 28, height: 28,
          background: "rgba(255,255,255,0.04)",
          border: "1px solid rgba(255,255,255,0.07)",
          color: "rgba(255,255,255,0.4)",
          transition: "background 0.1s, color 0.1s, border-color 0.1s",
        }}
      >
        <Icon />
      </div>

      {/* Text */}
      <div className="flex-1 min-w-0">
        <div style={{ fontSize: 12, fontWeight: 500, color: "var(--text-primary)", lineHeight: 1 }}>
          {label}
        </div>
        <div style={{ fontSize: 10.5, color: "var(--text-tertiary)", marginTop: 3, lineHeight: 1 }}>
          {desc}
        </div>
      </div>

      {/* Shortcut — use system font so ⇧ renders properly */}
      <span
        style={{
          flexShrink: 0,
          fontSize: 10,
          fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
          color: "var(--text-muted)",
          background: "rgba(255,255,255,0.04)",
          border: "1px solid rgba(255,255,255,0.07)",
          borderRadius: 4,
          padding: "2px 5px",
          lineHeight: 1.5,
          letterSpacing: "0.02em",
        }}
      >
        {shortcut}
      </span>
    </button>
  );
}
