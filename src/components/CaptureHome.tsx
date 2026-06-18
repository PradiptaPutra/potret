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

const modes = [
  {
    key: "area" as const,
    label: "Area",
    desc: "Select a region",
    shortcut: "⌘⇧4",
    icon: (
      <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round">
        <circle cx="7" cy="7" r="1.2"/>
        <line x1="7" y1="1.5" x2="7" y2="3.5"/>
        <line x1="7" y1="10.5" x2="7" y2="12.5"/>
        <line x1="1.5" y1="7" x2="3.5" y2="7"/>
        <line x1="10.5" y1="7" x2="12.5" y2="7"/>
      </svg>
    ),
  },
  {
    key: "window" as const,
    label: "Window",
    desc: "Click any window",
    shortcut: "⌘⇧5",
    icon: (
      <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round">
        <rect x="1.5" y="2.5" width="11" height="8" rx="1.5"/>
        <line x1="4" y1="12" x2="10" y2="12"/>
      </svg>
    ),
  },
  {
    key: "fullscreen" as const,
    label: "Fullscreen",
    desc: "Entire display",
    shortcut: "⌘⇧3",
    icon: (
      <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round">
        <rect x="1" y="2" width="12" height="8.5" rx="1"/>
        <line x1="3.5" y1="12" x2="10.5" y2="12"/>
      </svg>
    ),
  },
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
          width: "220px",
          background: "var(--bg-surface)",
          borderRight: "1px solid var(--border-default)",
        }}
      >
        {/* Logo row */}
        <div
          className="flex items-center gap-2.5 px-4 py-[18px]"
          style={{ borderBottom: "1px solid var(--border-subtle)" }}
        >
          <div
            className="flex items-center justify-center shrink-0 rounded-[7px]"
            style={{ width: 28, height: 28, background: "var(--accent)" }}
          >
            <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="#000" strokeWidth="1.6" strokeLinecap="round">
              <circle cx="7" cy="7" r="2.5"/>
              <path d="M1 7a6 6 0 016-6 6 6 0 016 6 6 6 0 01-6 6 6 6 0 01-6-6z" strokeWidth="1"/>
            </svg>
          </div>
          <span style={{ fontSize: 13, fontWeight: 600, color: "var(--text-primary)", letterSpacing: "-0.01em" }}>
            Potret
          </span>
        </div>

        {/* Section label */}
        <div className="px-4 pt-4 pb-1.5">
          <span style={{ fontSize: 10, fontWeight: 600, textTransform: "uppercase", letterSpacing: "0.08em", color: "var(--text-muted)" }}>
            Capture
          </span>
        </div>

        {/* Capture mode buttons */}
        <div className="flex flex-col px-2 gap-px">
          {modes.map(({ key, icon, label, desc, shortcut }) => (
            <button
              key={key}
              onClick={() => !loading && onCapture(key)}
              disabled={!!loading}
              className="group relative flex items-center gap-2.5 w-full rounded-md text-left cursor-pointer
                         disabled:opacity-40 disabled:cursor-not-allowed transition-colors duration-100"
              style={{
                padding: "9px 10px",
                background: "transparent",
                border: "none",
              }}
              onMouseEnter={e => (e.currentTarget.style.background = "var(--bg-hover)")}
              onMouseLeave={e => (e.currentTarget.style.background = "transparent")}
            >
              {/* Amber left-bar on hover */}
              <div
                className="absolute left-0 top-1.5 bottom-1.5 rounded-full opacity-0 group-hover:opacity-100 transition-opacity"
                style={{ width: 2, background: "var(--accent)" }}
              />

              {/* Icon */}
              <div
                className="flex items-center justify-center shrink-0 rounded-[5px]"
                style={{
                  width: 28, height: 28,
                  background: "rgba(255,255,255,0.05)",
                  border: "1px solid rgba(255,255,255,0.07)",
                  color: "rgba(255,255,255,0.45)",
                }}
              >
                {icon}
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

              {/* Shortcut */}
              <span
                className="shrink-0 font-mono"
                style={{
                  fontSize: 9,
                  color: "var(--text-muted)",
                  background: "rgba(255,255,255,0.04)",
                  border: "1px solid rgba(255,255,255,0.07)",
                  borderRadius: 3,
                  padding: "2px 4px",
                  lineHeight: 1.5,
                }}
              >
                {shortcut}
              </span>
            </button>
          ))}
        </div>

        {/* Status */}
        {(loading || error) && (
          <div
            className="mx-3 mt-3 px-3 py-2 rounded-md"
            style={{ background: "rgba(255,255,255,0.03)", border: "1px solid var(--border-default)" }}
          >
            {loading && (
              <div className="flex items-center gap-2" style={{ color: "var(--accent)" }}>
                <Loader2 className="w-3 h-3 animate-spin shrink-0" />
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
          <span style={{ fontSize: 10, fontFamily: "'SF Mono', monospace", color: "var(--text-muted)" }}>v0.1.0</span>
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

      {/* ── MAIN PANEL ── */}
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
