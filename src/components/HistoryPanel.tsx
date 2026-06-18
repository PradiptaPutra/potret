import { Copy, Trash2, ExternalLink, Camera } from "lucide-react";
import { HistoryItem } from "../App";
import { formatRelativeTime } from "../utils/time";

interface Props {
  items: HistoryItem[];
  onSelect: (item: HistoryItem) => void;
  onDelete: (id: string) => void;
  onCopy: (item: HistoryItem) => void;
  onClear: () => void;
  loading: boolean;
}

function formatSize(bytes: number): string {
  if (bytes <= 0) return "";
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function SkeletonCard() {
  return (
    <div
      className="rounded-lg overflow-hidden animate-pulse"
      style={{ background: "var(--bg-elevated)", border: "1px solid var(--border-default)" }}
    >
      <div className="w-full bg-white/[0.04]" style={{ aspectRatio: "16/10" }} />
      <div className="p-2.5 space-y-2">
        <div className="h-2.5 rounded bg-white/[0.06] w-3/4" />
        <div className="h-2 rounded bg-white/[0.04] w-1/2" />
      </div>
    </div>
  );
}

export default function HistoryPanel({ items, onSelect, onDelete, onCopy, onClear, loading }: Props) {
  /* ── Header ── */
  const header = (
    <div
      className="flex items-center justify-between px-4 shrink-0"
      style={{
        height: 40,
        borderBottom: "1px solid var(--border-default)",
      }}
    >
      <div className="flex items-center gap-2">
        <div style={{ width: 5, height: 5, borderRadius: "50%", background: "var(--accent)", opacity: 0.8 }} />
        <span style={{ fontSize: 11, fontWeight: 600, textTransform: "uppercase", letterSpacing: "0.06em", color: "var(--text-muted)" }}>
          Recent Captures
        </span>
        {items.length > 0 && (
          <span style={{ fontSize: 10, fontFamily: "'SF Mono', monospace", color: "var(--text-muted)" }}>
            {items.length}
          </span>
        )}
      </div>
      {items.length > 0 && (
        <button
          onClick={onClear}
          className="cursor-pointer transition-colors"
          style={{ fontSize: 10.5, color: "var(--text-tertiary)", background: "none", border: "none", padding: 0 }}
          onMouseEnter={e => (e.currentTarget.style.color = "var(--accent-red)")}
          onMouseLeave={e => (e.currentTarget.style.color = "var(--text-tertiary)")}
        >
          Clear all
        </button>
      )}
    </div>
  );

  /* ── Loading ── */
  if (loading) {
    return (
      <div className="flex-1 flex flex-col overflow-hidden">
        {header}
        <div className="flex-1 overflow-y-auto p-3">
          <div className="grid grid-cols-2 gap-2.5">
            {Array.from({ length: 6 }).map((_, i) => <SkeletonCard key={i} />)}
          </div>
        </div>
      </div>
    );
  }

  /* ── Empty ── */
  if (items.length === 0) {
    return (
      <div className="flex-1 flex flex-col overflow-hidden">
        {header}
        <div className="flex-1 flex flex-col items-center justify-center gap-4">
          <div
            className="flex items-center justify-center rounded-xl"
            style={{
              width: 48, height: 48,
              background: "var(--bg-elevated)",
              border: "1px solid var(--border-default)",
            }}
          >
            <Camera style={{ width: 20, height: 20, color: "var(--text-muted)" }} />
          </div>
          <div className="text-center">
            <p style={{ fontSize: 13, fontWeight: 500, color: "var(--text-tertiary)" }}>No captures yet</p>
            <p style={{ fontSize: 11, color: "var(--text-muted)", marginTop: 4 }}>
              Use a capture mode on the left to get started
            </p>
          </div>
        </div>
      </div>
    );
  }

  /* ── Grid (Studio-style cards, Design A colours) ── */
  return (
    <div className="flex-1 flex flex-col overflow-hidden">
      {header}
      <div className="flex-1 overflow-y-auto p-3">
        <div className="grid grid-cols-2 gap-2.5">
          {items.map((item) => (
            <HistoryCard
              key={item.id}
              item={item}
              onSelect={onSelect}
              onDelete={onDelete}
              onCopy={onCopy}
            />
          ))}
        </div>
      </div>
    </div>
  );
}

/* ── Single card ── */
function HistoryCard({
  item,
  onSelect,
  onDelete,
  onCopy,
}: {
  item: HistoryItem;
  onSelect: (i: HistoryItem) => void;
  onDelete: (id: string) => void;
  onCopy: (i: HistoryItem) => void;
}) {
  const size = formatSize(item.fileSize);

  return (
    <div
      className="group relative rounded-lg overflow-hidden cursor-pointer transition-all duration-150"
      style={{
        background: "var(--bg-elevated)",
        border: "1px solid var(--border-default)",
      }}
      onClick={() => onSelect(item)}
      onMouseEnter={e => {
        (e.currentTarget as HTMLElement).style.borderColor = "rgba(245,158,11,0.28)";
        (e.currentTarget as HTMLElement).style.transform = "translateY(-1px)";
        (e.currentTarget as HTMLElement).style.boxShadow = "0 6px 20px rgba(0,0,0,0.4)";
      }}
      onMouseLeave={e => {
        (e.currentTarget as HTMLElement).style.borderColor = "var(--border-default)";
        (e.currentTarget as HTMLElement).style.transform = "translateY(0)";
        (e.currentTarget as HTMLElement).style.boxShadow = "none";
      }}
    >
      {/* Thumbnail */}
      <div
        className="w-full overflow-hidden"
        style={{ aspectRatio: "16/10", background: "#0f0f12" }}
      >
        {item.thumbnail ? (
          <img
            src={`data:image/png;base64,${item.thumbnail}`}
            alt="Screenshot"
            className="w-full h-full object-cover"
          />
        ) : (
          <div className="w-full h-full flex items-center justify-center">
            <Camera style={{ width: 18, height: 18, color: "rgba(255,255,255,0.08)" }} />
          </div>
        )}
      </div>

      {/* Hover action buttons */}
      <div
        className="absolute top-1.5 right-1.5 flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity duration-100"
      >
        {[
          { label: "Copy", icon: <Copy size={11} />, onClick: () => onCopy(item), hoverBg: "rgba(245,158,11,0.8)" },
          { label: "Edit", icon: <ExternalLink size={11} />, onClick: () => onSelect(item), hoverBg: "rgba(255,255,255,0.25)" },
          { label: "Delete", icon: <Trash2 size={11} />, onClick: () => onDelete(item.id), hoverBg: "rgba(239,68,68,0.8)" },
        ].map(({ label, icon, onClick, hoverBg }) => (
          <button
            key={label}
            title={label}
            onClick={e => { e.stopPropagation(); onClick(); }}
            className="flex items-center justify-center rounded cursor-pointer transition-colors"
            style={{
              width: 22, height: 22,
              background: "rgba(0,0,0,0.65)",
              border: "1px solid rgba(255,255,255,0.1)",
              color: "rgba(255,255,255,0.85)",
              backdropFilter: "blur(6px)",
            }}
            onMouseEnter={e => (e.currentTarget.style.background = hoverBg)}
            onMouseLeave={e => (e.currentTarget.style.background = "rgba(0,0,0,0.65)")}
          >
            {icon}
          </button>
        ))}
      </div>

      {/* Metadata — Studio card style */}
      <div className="px-2.5 pt-2 pb-2.5">
        <p
          className="font-mono truncate"
          style={{ fontSize: 10.5, fontWeight: 500, color: "var(--text-secondary)", lineHeight: 1 }}
        >
          {new Date(item.timestamp).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" })}
        </p>
        <div className="flex items-center justify-between mt-1.5">
          <span style={{ fontSize: 10, color: "var(--text-tertiary)" }}>
            {formatRelativeTime(item.timestamp)}
          </span>
          <span className="font-mono" style={{ fontSize: 9.5, color: "var(--text-muted)" }}>
            {item.width}×{item.height}{size ? ` · ${size}` : ""}
          </span>
        </div>
      </div>
    </div>
  );
}
