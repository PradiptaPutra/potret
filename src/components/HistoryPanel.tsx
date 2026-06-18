import { Copy, Trash2, ExternalLink, Camera } from "lucide-react";
import { HistoryItem } from "../App";

interface Props {
  items: HistoryItem[];
  onSelect: (item: HistoryItem) => void;
  onDelete: (id: string) => void;
  onCopy: (item: HistoryItem) => void;
  loading: boolean;
}

function relativeTime(timestamp: number): string {
  const diff = Date.now() - timestamp;
  const seconds = Math.floor(diff / 1000);
  const minutes = Math.floor(seconds / 60);
  const hours = Math.floor(minutes / 60);
  const days = Math.floor(hours / 24);

  if (seconds < 60) return "Just now";
  if (minutes < 60) return `${minutes}m ago`;
  if (hours < 24) return `${hours}h ago`;
  if (days === 1) return "Yesterday";
  return `${days}d ago`;
}

function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes}B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)}KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)}MB`;
}

function SkeletonCard() {
  return (
    <div className="rounded-xl overflow-hidden border border-white/5 bg-white/[0.03] animate-pulse">
      <div className="aspect-video bg-white/5" />
      <div className="p-2.5 space-y-1.5">
        <div className="h-2.5 bg-white/8 rounded w-16" />
        <div className="h-2 bg-white/5 rounded w-10" />
      </div>
    </div>
  );
}

export default function HistoryPanel({ items, onSelect, onDelete, onCopy, loading }: Props) {
  if (loading) {
    return (
      <div className="flex-1 flex flex-col overflow-hidden">
        <div className="px-4 py-3 border-b border-white/[0.06] shrink-0">
          <span className="text-xs font-semibold text-white/30 uppercase tracking-widest">Recent Captures</span>
        </div>
        <div className="flex-1 overflow-y-auto p-3">
          <div className="grid grid-cols-2 gap-2.5">
            {Array.from({ length: 6 }).map((_, i) => (
              <SkeletonCard key={i} />
            ))}
          </div>
        </div>
      </div>
    );
  }

  if (items.length === 0) {
    return (
      <div className="flex-1 flex flex-col overflow-hidden">
        <div className="px-4 py-3 border-b border-white/[0.06] shrink-0">
          <span className="text-xs font-semibold text-white/30 uppercase tracking-widest">Recent Captures</span>
        </div>
        <div className="flex-1 flex flex-col items-center justify-center gap-3 p-8">
          <div className="w-12 h-12 rounded-2xl bg-white/[0.04] border border-white/[0.07] flex items-center justify-center">
            <Camera className="w-5 h-5 text-white/20" />
          </div>
          <div className="text-center">
            <p className="text-sm font-medium text-white/30">No captures yet</p>
            <p className="text-xs text-white/15 mt-1">Screenshots will appear here</p>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="flex-1 flex flex-col overflow-hidden">
      <div className="px-4 py-3 border-b border-white/[0.06] shrink-0 flex items-center justify-between">
        <span className="text-xs font-semibold text-white/30 uppercase tracking-widest">Recent Captures</span>
        <span className="text-xs text-white/20 tabular-nums">{items.length}</span>
      </div>
      <div className="flex-1 overflow-y-auto p-3">
        <div className="grid grid-cols-2 gap-2.5">
          {items.map((item) => (
            <div
              key={item.id}
              className="group relative rounded-xl overflow-hidden border border-white/[0.07] bg-white/[0.03]
                         hover:border-white/[0.15] hover:bg-white/[0.05] transition-all duration-150 cursor-pointer"
              onClick={() => onSelect(item)}
            >
              {/* Thumbnail */}
              <div className="aspect-video bg-[#0d0d14] overflow-hidden">
                {item.thumbnail ? (
                  <img
                    src={`data:image/png;base64,${item.thumbnail}`}
                    alt="Screenshot"
                    className="w-full h-full object-cover"
                  />
                ) : (
                  <div className="w-full h-full flex items-center justify-center">
                    <Camera className="w-4 h-4 text-white/10" />
                  </div>
                )}
              </div>

              {/* Hover action bar */}
              <div className="absolute top-1.5 right-1.5 flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity duration-100">
                <button
                  onClick={(e) => { e.stopPropagation(); onCopy(item); }}
                  className="w-6 h-6 rounded-md bg-black/70 backdrop-blur-sm border border-white/10
                             flex items-center justify-center hover:bg-violet-600/80 transition-colors cursor-pointer"
                  title="Copy to clipboard"
                >
                  <Copy className="w-3 h-3 text-white" />
                </button>
                <button
                  onClick={(e) => { e.stopPropagation(); onSelect(item); }}
                  className="w-6 h-6 rounded-md bg-black/70 backdrop-blur-sm border border-white/10
                             flex items-center justify-center hover:bg-white/20 transition-colors cursor-pointer"
                  title="Open in editor"
                >
                  <ExternalLink className="w-3 h-3 text-white" />
                </button>
                <button
                  onClick={(e) => { e.stopPropagation(); onDelete(item.id); }}
                  className="w-6 h-6 rounded-md bg-black/70 backdrop-blur-sm border border-white/10
                             flex items-center justify-center hover:bg-red-600/80 transition-colors cursor-pointer"
                  title="Delete"
                >
                  <Trash2 className="w-3 h-3 text-white" />
                </button>
              </div>

              {/* Metadata */}
              <div className="px-2.5 py-2">
                <p className="text-xs font-medium text-white/60 leading-none">{relativeTime(item.timestamp)}</p>
                <p className="text-[10px] text-white/25 mt-1 font-mono leading-none">
                  {item.width}×{item.height}
                  {item.fileSize > 0 && <span className="ml-1.5">{formatSize(item.fileSize)}</span>}
                </p>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
