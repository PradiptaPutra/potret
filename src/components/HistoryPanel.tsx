import { Copy, Trash2, Pencil, Camera, Pin, ImageIcon } from "lucide-react";
import { invoke } from "@tauri-apps/api/core";
import { startDrag } from "@crabnebula/tauri-plugin-drag";
import { HistoryItem } from "../App";
import { formatRelativeTime } from "../utils/time";

interface Props {
  items: HistoryItem[];
  onSelect: (item: HistoryItem) => void;
  onDelete: (id: string) => void;
  onCopy: (item: HistoryItem) => void;
  onClear: () => void;
  onPin: (item: HistoryItem) => void;
  onBackground: (item: HistoryItem) => void;
  loading: boolean;
  onDragComplete?: () => void;
  hideClearAll?: boolean;
}

function formatSize(bytes: number): string {
  if (bytes <= 0) return "";
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

/* ── Skeleton card ── */
function SkeletonCard() {
  return (
    <div
      style={{
        borderRadius: 8,
        overflow: "hidden",
        background: "var(--bg-card)",
        border: "1px solid var(--border)",
      }}
    >
      <div className="w-full skeleton" style={{ aspectRatio: "16/10" }} />
      <div style={{ padding: "8px 10px", display: "flex", flexDirection: "column", gap: 6 }}>
        <div className="skeleton" style={{ height: 10, borderRadius: 4, width: "70%" }} />
        <div className="skeleton" style={{ height: 8, borderRadius: 4, width: "45%" }} />
      </div>
    </div>
  );
}

export default function HistoryPanel({ items, onSelect, onDelete, onCopy, onClear, onPin, onBackground, loading, onDragComplete, hideClearAll }: Props) {

  /* ── Header ── */
  const header = (
    <div
      style={{
        height: 48,
        padding: "0 16px",
        display: "flex", alignItems: "center", justifyContent: "space-between",
        borderBottom: "1px solid var(--border)",
        flexShrink: 0,
      }}
    >
      <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
        {/* Amber dot */}
        <div style={{ width: 6, height: 6, borderRadius: "50%", background: "var(--accent)" }} />
        <span style={{
          fontSize: 10,
          fontWeight: 600,
          textTransform: "uppercase",
          letterSpacing: "0.08em",
          color: "var(--text-secondary)",
        }}>
          Recent Captures
        </span>
        {items.length > 0 && (
          <span style={{
            fontSize: 10,
            color: "var(--text-tertiary)",
            background: "rgba(255,255,255,0.06)",
            border: "1px solid var(--border)",
            borderRadius: 4,
            padding: "0px 5px",
            lineHeight: 1.7,
          }}>
            {items.length}
          </span>
        )}
      </div>
      {items.length > 0 && !hideClearAll && (
        <button
          onClick={onClear}
          style={{
            fontSize: 10.5,
            color: "var(--text-tertiary)",
            background: "none",
            border: "none",
            padding: 0,
            cursor: "pointer",
            transition: "color 0.12s",
          }}
          onMouseEnter={e => (e.currentTarget.style.color = "var(--red)")}
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
        <div className="flex-1 overflow-y-auto" style={{ padding: 12 }}>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10 }}>
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
        <div className="flex-1 flex flex-col items-center justify-center" style={{ gap: 10 }}>
          {/* Bare camera icon — no surrounding box */}
          <Camera style={{ width: 20, height: 20, color: "var(--text-tertiary)" }} />
          <div style={{ textAlign: "center" }}>
            <p style={{ fontSize: 12, fontWeight: 500, color: "var(--text-secondary)" }}>No captures yet</p>
            <p style={{ fontSize: 10.5, color: "var(--text-tertiary)", marginTop: 4, lineHeight: 1.5 }}>
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
      <div className="flex-1 overflow-y-auto" style={{ padding: 12 }}>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10 }}>
          {items.map(item => (
            <HistoryCard
              key={item.id}
              item={item}
              onSelect={onSelect}
              onDelete={onDelete}
              onCopy={onCopy}
              onPin={onPin}
              onBackground={onBackground}
              onDragComplete={onDragComplete}
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
  onPin,
  onBackground,
  onDragComplete,
}: {
  item: HistoryItem;
  onSelect: (i: HistoryItem) => void;
  onDelete: (id: string) => void;
  onCopy: (i: HistoryItem) => void;
  onPin: (i: HistoryItem) => void;
  onBackground: (i: HistoryItem) => void;
  onDragComplete?: () => void;
}) {
  const size = formatSize(item.fileSize);

  async function handleDragOut(e: React.DragEvent) {
    e.preventDefault();  // cancel the HTML5 drag; use a native OS file drag instead
    e.stopPropagation(); // don't let the card treat this as a click (edit)
    try {
      const path = await invoke<string>("stage_history_for_drag", { id: item.id });
      await startDrag({ item: [path], icon: path });
      onDragComplete?.();
    } catch (err) {
      console.error(err);
    }
  }

  return (
    <div
      className="group relative cursor-pointer"
      style={{
        background: "var(--bg-card)",
        border: "1px solid var(--border)",
        borderRadius: 8,
        overflow: "hidden",
        transition: "border-color 0.18s, transform 0.18s, box-shadow 0.18s",
      }}
      onClick={() => onSelect(item)}
      onMouseEnter={e => {
        const el = e.currentTarget as HTMLElement;
        el.style.borderColor = "var(--accent-border)";
        el.style.transform = "translateY(-1px)";
        el.style.boxShadow = "0 6px 20px rgba(0,0,0,0.5)";
      }}
      onMouseLeave={e => {
        const el = e.currentTarget as HTMLElement;
        el.style.borderColor = "var(--border)";
        el.style.transform = "";
        el.style.boxShadow = "";
      }}
    >
      {/* Thumbnail */}
      <div style={{ aspectRatio: "16/10", background: "#111", overflow: "hidden" }}>
        {item.thumbnail ? (
          <img
            src={`data:image/png;base64,${item.thumbnail}`}
            alt="Screenshot"
            title="Drag to another app"
            style={{ width: "100%", height: "100%", objectFit: "contain", display: "block", cursor: "grab" }}
            draggable
            onDragStart={handleDragOut}
          />
        ) : (
          <div style={{ width: "100%", height: "100%", display: "flex", alignItems: "center", justifyContent: "center" }}>
            <Camera style={{ width: 16, height: 16, color: "rgba(255,255,255,0.08)" }} />
          </div>
        )}
      </div>

      {/* Hover action buttons — top-right */}
      <div
        className="absolute flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity duration-150"
        style={{ top: 7, right: 7 }}
      >
        {([
          { title: "Background", Icon: ImageIcon, action: () => onBackground(item), danger: false, accent: "#a78bfa" },
          { title: "Pin",        Icon: Pin,        action: () => onPin(item),        danger: false, accent: null },
          { title: "Copy",       Icon: Copy,       action: () => onCopy(item),       danger: false, accent: null },
          { title: "Edit",       Icon: Pencil,     action: () => onSelect(item),     danger: false, accent: null },
          { title: "Delete",     Icon: Trash2,     action: () => onDelete(item.id),  danger: true,  accent: null },
        ] as const).map(({ title, Icon, action, danger, accent }) => (
          <button
            key={title}
            title={title}
            onClick={e => { e.stopPropagation(); action(); }}
            style={{
              display: "flex", alignItems: "center", justifyContent: "center",
              width: 22, height: 22,
              borderRadius: 6,
              background: "rgba(0,0,0,0.72)",
              border: "1px solid rgba(255,255,255,0.12)",
              color: "rgba(255,255,255,0.80)",
              backdropFilter: "blur(8px)",
              cursor: "pointer",
              transition: "background 0.12s, color 0.12s, border-color 0.12s",
            }}
            onMouseEnter={e => {
              const el = e.currentTarget;
              if (danger) {
                el.style.background = "rgba(255,69,58,0.85)";
                el.style.borderColor = "rgba(255,69,58,0.5)";
                el.style.color = "#fff";
              } else if (accent) {
                el.style.background = accent;
                el.style.borderColor = accent;
                el.style.color = "#fff";
              } else {
                el.style.background = "rgba(255,159,10,0.85)";
                el.style.borderColor = "rgba(255,159,10,0.5)";
                el.style.color = "#000";
              }
            }}
            onMouseLeave={e => {
              const el = e.currentTarget;
              el.style.background = "rgba(0,0,0,0.72)";
              el.style.borderColor = "rgba(255,255,255,0.12)";
              el.style.color = "rgba(255,255,255,0.80)";
            }}
          >
            <Icon size={10} />
          </button>
        ))}
      </div>

      {/* Metadata */}
      <div style={{ padding: "8px 10px 10px" }}>
        <p style={{
          fontSize: 11,
          fontWeight: 500,
          fontFamily: "ui-monospace, 'SF Mono', 'Menlo', monospace",
          color: "var(--text-primary)",
          lineHeight: 1,
          marginBottom: 4,
        }}>
          {new Date(item.timestamp).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" })}
        </p>
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
          <span style={{ fontSize: 10, color: "var(--text-tertiary)" }}>
            {formatRelativeTime(item.timestamp)}
          </span>
          <span style={{ fontSize: 10, fontFamily: "ui-monospace, 'SF Mono', monospace", color: "var(--text-tertiary)" }}>
            {item.width}×{item.height}{size ? ` · ${size}` : ""}
          </span>
        </div>
      </div>
    </div>
  );
}
