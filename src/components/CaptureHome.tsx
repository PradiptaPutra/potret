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

const modes = [
  { key: "area"       as const, Icon: AreaIcon,       label: "Area",       desc: "Select a region",  shortcut: "⌘⇧4" },
  { key: "window"     as const, Icon: WindowIcon,     label: "Window",     desc: "Click any window", shortcut: "⌘⇧5" },
  { key: "fullscreen" as const, Icon: FullscreenIcon, label: "Fullscreen", desc: "Entire display",   shortcut: "⌘⇧3" },
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
    <div
      className="flex h-full w-full overflow-hidden"
      style={{ background: "var(--bg-base)", position: "relative", zIndex: 1 }}
    >
      {/* ── SIDEBAR ─────────────────────────────────────────────────── */}
      <aside
        className="glass-panel flex flex-col shrink-0"
        style={{
          width: 216,
          borderRight: "1px solid var(--border-default)",
        }}
      >
        {/* Brand row */}
        <div
          className="flex items-center gap-2.5 px-4"
          style={{ height: 44, borderBottom: "1px solid var(--border-subtle)" }}
        >
          {/* Amber aperture mark */}
          <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
            <circle cx="7" cy="7" r="6" stroke="#F59E0B" strokeWidth="1.25" />
            <circle cx="7" cy="7" r="2.5" stroke="#F59E0B" strokeWidth="1.25" />
            <circle cx="7" cy="7" r="1" fill="#F59E0B" />
          </svg>
          <span style={{ fontSize: 13, fontWeight: 600, color: "var(--text-primary)", letterSpacing: "-0.02em" }}>
            Potret
          </span>
        </div>

        {/* ── Capture section ── */}
        <div className="px-4 pt-4 pb-1.5">
          <span style={{
            fontSize: 9,
            fontWeight: 700,
            textTransform: "uppercase",
            letterSpacing: "0.12em",
            color: "var(--text-muted)",
          }}>
            Capture
          </span>
        </div>

        <div className="flex flex-col px-2 pb-2">
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
          <div className="mx-3 mb-2">
            <div
              className="flex items-center gap-2 px-3 py-2 rounded-lg"
              style={{
                background: loading ? "var(--accent-dim)" : "rgba(239,68,68,0.08)",
                border: `1px solid ${loading ? "var(--accent-border)" : "rgba(239,68,68,0.2)"}`,
              }}
            >
              {loading && <Loader2 style={{ width: 11, height: 11, color: "var(--accent)", flexShrink: 0 }} className="animate-spin" />}
              <span style={{ fontSize: 11, color: loading ? "var(--accent)" : "var(--accent-red)" }}>
                {loading ?? error}
              </span>
            </div>
          </div>
        )}

        <div className="flex-1" />

        {/* ── Divider + footer ── */}
        <div style={{ borderTop: "1px solid var(--border-subtle)" }} className="px-4 py-3 flex items-center justify-between">
          <span style={{ fontSize: 10, fontFamily: "'SF Mono', 'Menlo', monospace", color: "var(--text-muted)" }}>
            v0.1.0
          </span>
          <a
            href="https://github.com/aditpradipta/potret"
            target="_blank"
            rel="noreferrer"
            style={{ fontSize: 10, color: "var(--text-muted)", textDecoration: "none" }}
            onMouseEnter={e => (e.currentTarget.style.color = "var(--accent)")}
            onMouseLeave={e => (e.currentTarget.style.color = "var(--text-muted)")}
          >
            GitHub ↗
          </a>
        </div>
      </aside>

      {/* ── MAIN ─────────────────────────────────────────────────────── */}
      <main className="flex-1 flex flex-col overflow-hidden" style={{ position: "relative", zIndex: 1 }}>
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
      onClick={onClick}
      disabled={disabled}
      className="group relative flex items-center gap-2.5 w-full text-left rounded-lg cursor-pointer
                 disabled:opacity-40 disabled:cursor-not-allowed"
      style={{
        padding: "8px 10px",
        background: "transparent",
        border: "none",
        transition: "background 0.15s",
        marginBottom: 1,
      }}
    >
      {/* Amber left accent — only on hover via CSS */}
      <div
        className="capture-btn-accent"
        style={{
          position: "absolute",
          left: 0,
          top: 7,
          bottom: 7,
          width: 2,
          borderRadius: 2,
          background: "var(--accent)",
          opacity: 0,
          transition: "opacity 0.15s",
        }}
      />

      {/* Icon container */}
      <div
        className="capture-btn-icon flex items-center justify-center shrink-0 rounded-lg"
        style={{
          width: 30,
          height: 30,
          background: "rgba(255,255,255,0.04)",
          border: "1px solid rgba(255,255,255,0.07)",
          color: "rgba(148,163,184,0.6)",
          transition: "background 0.15s, border-color 0.15s, color 0.15s, box-shadow 0.15s",
        }}
      >
        <Icon />
      </div>

      {/* Label + description */}
      <div className="flex-1 min-w-0">
        <div
          className="capture-btn-label"
          style={{
            fontSize: 12,
            fontWeight: 500,
            color: "rgba(255,255,255,0.75)",
            lineHeight: 1,
            transition: "color 0.15s",
          }}
        >
          {label}
        </div>
        <div style={{ fontSize: 10, color: "var(--text-muted)", marginTop: 3.5, lineHeight: 1 }}>
          {desc}
        </div>
      </div>

      {/* Shortcut badge — system font so ⇧ renders */}
      <kbd style={{
        flexShrink: 0,
        fontSize: 10,
        fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
        fontWeight: 500,
        color: "var(--text-muted)",
        background: "rgba(255,255,255,0.04)",
        border: "1px solid rgba(255,255,255,0.07)",
        borderRadius: 5,
        padding: "2px 6px",
        lineHeight: 1.6,
        letterSpacing: "0.01em",
      }}>
        {shortcut}
      </kbd>
    </button>
  );
}
