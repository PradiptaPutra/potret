import { Copy, Trash2, Pencil, Camera } from "lucide-react";
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

/* ── Skeleton card — shimmer per ui-ux-pro-max §3 progressive loading ── */
function SkeletonCard() {
  return (
    <div className="rounded-xl overflow-hidden" style={{ background: "var(--bg-elevated)", border: "1px solid var(--border-default)" }}>
      <div className="w-full skeleton" style={{ aspectRatio: "16/10" }} />
      <div className="p-2.5 space-y-2">
        <div className="h-2.5 rounded-full skeleton" style={{ width: "70%" }} />
        <div className="h-2 rounded-full skeleton" style={{ width: "45%" }} />
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
        height: 44,
        borderBottom: "1px solid var(--border-default)",
        backdropFilter: "blur(12px)",
        background: "rgba(10,13,24,0.6)",
      }}
    >
      <div className="flex items-center gap-2">
        <div style={{ width: 5, height: 5, borderRadius: "50%", background: "var(--accent)", opacity: 0.85 }} />
        <span style={{ fontSize: 10.5, fontWeight: 600, textTransform: "uppercase", letterSpacing: "0.08em", color: "var(--text-muted)" }}>
          Recent Captures
        </span>
        {items.length > 0 && (
          <span
            style={{
              fontSize: 10,
              fontFamily: "'SF Mono', monospace",
              color: "var(--text-muted)",
              background: "rgba(255,255,255,0.06)",
              border: "1px solid var(--border-default)",
              borderRadius: 4,
              padding: "0px 5px",
              lineHeight: 1.7,
            }}
          >
            {items.length}
          </span>
        )}
      </div>
      {items.length > 0 && (
        <button
          onClick={onClear}
          className="cursor-pointer"
          style={{ fontSize: 10.5, color: "var(--text-muted)", background: "none", border: "none", padding: 0, transition: "color 0.15s" }}
          onMouseEnter={e => (e.currentTarget.style.color = "var(--accent-red)")}
          onMouseLeave={e => (e.currentTarget.style.color = "var(--text-muted)")}
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
          <div className="grid gap-2.5" style={{ gridTemplateColumns: "1fr 1fr" }}>
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
        <div className="flex-1 flex flex-col items-center justify-center gap-3">
          {/* Subtle camera ring */}
          <div
            style={{
              width: 40, height: 40,
              borderRadius: "50%",
              border: "1px solid var(--border-default)",
              display: "flex", alignItems: "center", justifyContent: "center",
              background: "rgba(255,255,255,0.02)",
            }}
          >
            <Camera style={{ width: 16, height: 16, color: "var(--text-muted)" }} />
          </div>
          <div style={{ textAlign: "center" }}>
            <p style={{ fontSize: 12, fontWeight: 500, color: "var(--text-tertiary)" }}>No captures yet</p>
            <p style={{ fontSize: 10.5, color: "var(--text-muted)", marginTop: 4, lineHeight: 1.5 }}>
              Use a capture mode to get started
            </p>
          </div>
        </div>
      </div>
    );
  }

  /* ── Grid ── */
  return (
    <div className="flex-1 flex flex-col overflow-hidden">
      {header}
      <div className="flex-1 overflow-y-auto p-3">
        <div className="grid gap-2.5" style={{ gridTemplateColumns: "1fr 1fr" }}>
          {items.map(item => (
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

/* ── History card ─────────────────────────────────────────────────── */
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
      className="group relative rounded-xl overflow-hidden cursor-pointer"
      style={{
        background: "var(--bg-card)",
        border: "1px solid var(--border-default)",
        transition: "border-color 0.18s, transform 0.18s, box-shadow 0.18s",
      }}
      onClick={() => onSelect(item)}
      onMouseEnter={e => {
        const el = e.currentTarget as HTMLElement;
        el.style.borderColor = "rgba(245,158,11,0.30)";
        el.style.transform = "translateY(-2px)";
        el.style.boxShadow = "0 10px 36px rgba(0,0,0,0.55), 0 0 0 1px rgba(245,158,11,0.10)";
      }}
      onMouseLeave={e => {
        const el = e.currentTarget as HTMLElement;
        el.style.borderColor = "var(--border-default)";
        el.style.transform = "";
        el.style.boxShadow = "";
      }}
    >
      {/* Thumbnail */}
      <div style={{ aspectRatio: "16/10", background: "#080C18", overflow: "hidden" }}>
        {item.thumbnail ? (
          <img
            src={`data:image/png;base64,${item.thumbnail}`}
            alt="Screenshot"
            style={{ width: "100%", height: "100%", objectFit: "cover", display: "block" }}
          />
        ) : (
          <div style={{ width: "100%", height: "100%", display: "flex", alignItems: "center", justifyContent: "center" }}>
            <Camera style={{ width: 16, height: 16, color: "rgba(255,255,255,0.06)" }} />
          </div>
        )}
      </div>

      {/* Hover action buttons — appear top-right */}
      <div
        className="absolute flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity duration-150"
        style={{ top: 7, right: 7 }}
      >
        {([
          { title: "Copy",   Icon: Copy,   action: () => onCopy(item),      danger: false },
          { title: "Edit",   Icon: Pencil, action: () => onSelect(item),    danger: false },
          { title: "Delete", Icon: Trash2, action: () => onDelete(item.id), danger: true  },
        ] as const).map(({ title, Icon, action, danger }) => (
          <button
            key={title}
            title={title}
            onClick={e => { e.stopPropagation(); action(); }}
            className="flex items-center justify-center rounded-lg cursor-pointer"
            style={{
              width: 24, height: 24,
              background: "rgba(6, 8, 18, 0.80)",
              border: "1px solid rgba(255,255,255,0.10)",
              color: "rgba(255,255,255,0.75)",
              backdropFilter: "blur(8px)",
              transition: "background 0.12s, color 0.12s, border-color 0.12s",
            }}
            onMouseEnter={e => {
              const el = e.currentTarget;
              if (danger) {
                el.style.background = "rgba(239,68,68,0.80)";
                el.style.borderColor = "rgba(239,68,68,0.5)";
                el.style.color = "#fff";
              } else {
                el.style.background = "rgba(245,158,11,0.80)";
                el.style.borderColor = "rgba(245,158,11,0.5)";
                el.style.color = "#0B0E1C";
              }
            }}
            onMouseLeave={e => {
              const el = e.currentTarget;
              el.style.background = "rgba(6, 8, 18, 0.80)";
              el.style.borderColor = "rgba(255,255,255,0.10)";
              el.style.color = "rgba(255,255,255,0.75)";
            }}
          >
            <Icon size={10} />
          </button>
        ))}
      </div>

      {/* Metadata */}
      <div style={{ padding: "9px 11px 11px" }}>
        <p style={{
          fontSize: 11,
          fontWeight: 500,
          fontFamily: "'SF Mono', 'Menlo', monospace",
          color: "var(--text-secondary)",
          lineHeight: 1,
          marginBottom: 5,
        }}>
          {new Date(item.timestamp).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" })}
        </p>
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
          <span style={{ fontSize: 10, color: "var(--text-muted)" }}>
            {formatRelativeTime(item.timestamp)}
          </span>
          <span style={{ fontSize: 9.5, fontFamily: "'SF Mono', monospace", color: "var(--text-muted)" }}>
            {item.width}×{item.height}{size ? ` · ${size}` : ""}
          </span>
        </div>
      </div>
    </div>
  );
}
