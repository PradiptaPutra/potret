import { Camera, Crosshair, AppWindow, Loader2 } from "lucide-react";
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
    icon: Crosshair,
    label: "Capture Area",
    desc: "Select a region of your screen",
    shortcut: "⌘⇧4",
  },
  {
    key: "window" as const,
    icon: AppWindow,
    label: "Capture Window",
    desc: "Click any window to capture",
    shortcut: "⌘⇧5",
  },
  {
    key: "fullscreen" as const,
    icon: Camera,
    label: "Fullscreen",
    desc: "Capture the entire display",
    shortcut: "⌘⇧3",
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
}: Props) {
  return (
    <div
      className="flex h-full w-full overflow-hidden"
      style={{ background: "var(--bg-base)" }}
    >
      {/* ── LEFT SIDEBAR ── */}
      <aside
        className="flex flex-col shrink-0 overflow-hidden"
        style={{
          width: "240px",
          background: "var(--bg-surface)",
          borderRight: "1px solid var(--border-default)",
        }}
      >
        {/* Branding */}
        <div
          className="flex items-center gap-2.5 px-5 py-4"
          style={{ borderBottom: "1px solid var(--border-subtle)" }}
        >
          <div
            className="flex items-center justify-center rounded-lg shrink-0"
            style={{
              width: "28px",
              height: "28px",
              background: "linear-gradient(135deg, #7c3aed 0%, #6d28d9 100%)",
              boxShadow: "0 2px 8px rgba(124,58,237,0.45)",
            }}
          >
            <Camera className="w-3.5 h-3.5 text-white" />
          </div>
          <span
            className="font-semibold tracking-tight"
            style={{ color: "var(--text-primary)", fontSize: "14px" }}
          >
            Potret
          </span>
        </div>

        {/* Section label */}
        <div className="px-5 pt-5 pb-2">
          <span
            style={{
              fontSize: "10px",
              fontWeight: 600,
              textTransform: "uppercase",
              letterSpacing: "0.1em",
              color: "var(--text-muted)",
            }}
          >
            Capture
          </span>
        </div>

        {/* Capture mode buttons */}
        <div className="flex flex-col gap-0.5 px-2">
          {modes.map(({ key, icon: Icon, label, desc, shortcut }) => (
            <CaptureModeButton
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

        {/* Status feedback */}
        {(loading || error) && (
          <div
            className="mx-4 mt-3 px-3 py-2.5 rounded-lg"
            style={{
              background: "rgba(255,255,255,0.04)",
              border: "1px solid rgba(255,255,255,0.07)",
            }}
          >
            {loading && (
              <div className="flex items-center gap-2" style={{ color: "#8b5cf6" }}>
                <Loader2 className="w-3 h-3 animate-spin shrink-0" />
                <span style={{ fontSize: "11.5px" }}>{loading}</span>
              </div>
            )}
            {error && !loading && (
              <p style={{ fontSize: "11.5px", color: "var(--accent-red)" }}>{error}</p>
            )}
          </div>
        )}

        {/* Push footer to bottom */}
        <div className="flex-1" />

        {/* Footer */}
        <div
          className="px-5 py-3 flex items-center justify-between"
          style={{ borderTop: "1px solid var(--border-subtle)" }}
        >
          <span style={{ fontSize: "10px", color: "var(--text-muted)" }}>v0.1.0</span>
          <a
            href="https://github.com/aditpradipta/potret"
            target="_blank"
            rel="noreferrer"
            style={{
              fontSize: "10px",
              color: "var(--text-muted)",
              textDecoration: "none",
            }}
            className="hover:underline"
          >
            GitHub
          </a>
        </div>
      </aside>

      {/* ── RIGHT PANEL — history ── */}
      <main
        className="flex-1 flex flex-col overflow-hidden"
        style={{ background: "var(--bg-base)" }}
      >
        <HistoryPanel
          items={history}
          onSelect={onSelectHistory}
          onDelete={onDeleteHistory}
          onCopy={onCopyHistory}
          loading={false}
        />
      </main>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* CaptureModeButton                                                     */
/* ------------------------------------------------------------------ */

interface CaptureModeButtonProps {
  Icon: React.ComponentType<{ className?: string }>;
  label: string;
  desc: string;
  shortcut: string;
  disabled: boolean;
  onClick: () => void;
}

function CaptureModeButton({
  Icon,
  label,
  desc,
  shortcut,
  disabled,
  onClick,
}: CaptureModeButtonProps) {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      className="group relative flex items-start gap-3 w-full rounded-lg text-left
                 transition-colors duration-150 cursor-pointer
                 disabled:opacity-40 disabled:cursor-not-allowed
                 hover:bg-[rgba(124,58,237,0.15)]"
      style={{
        padding: "9px 12px",
        background: "transparent",
        border: "none",
      }}
    >
      {/* Violet left-border accent on hover */}
      <div
        className="absolute left-0 top-2 bottom-2 w-[2px] rounded-full
                   opacity-0 group-hover:opacity-100 transition-opacity duration-150"
        style={{ background: "var(--accent-violet)" }}
      />

      {/* Icon container */}
      <div
        className="flex items-center justify-center rounded-md shrink-0 mt-[1px]"
        style={{
          width: "26px",
          height: "26px",
          background: "rgba(255,255,255,0.06)",
          border: "1px solid rgba(255,255,255,0.08)",
        }}
      >
        <Icon className="w-3.5 h-3.5 text-white/50" />
      </div>

      {/* Label + description */}
      <div className="flex-1 min-w-0">
        <div
          className="font-medium leading-none mb-[5px]"
          style={{ fontSize: "12.5px", color: "var(--text-primary)" }}
        >
          {label}
        </div>
        <div
          className="leading-none truncate"
          style={{ fontSize: "11px", color: "var(--text-tertiary)" }}
        >
          {desc}
        </div>
      </div>

      {/* Shortcut badge */}
      <span
        className="shrink-0 font-mono"
        style={{
          fontSize: "9px",
          color: "var(--text-muted)",
          background: "rgba(255,255,255,0.05)",
          border: "1px solid rgba(255,255,255,0.08)",
          borderRadius: "4px",
          padding: "2px 4px",
          marginTop: "1px",
          lineHeight: 1.4,
        }}
      >
        {shortcut}
      </span>
    </button>
  );
}
