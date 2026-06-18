import { Camera, Crosshair, AppWindow, Loader2 } from "lucide-react";

interface Props {
  onCapture: (mode: "fullscreen" | "area" | "window") => void;
  loading: string | null;
  error: string | null;
}

const modes = [
  {
    key: "area" as const,
    icon: Crosshair,
    label: "Area",
    desc: "Select a region",
    shortcut: "⌘⇧4",
  },
  {
    key: "window" as const,
    icon: AppWindow,
    label: "Window",
    desc: "Click any window",
    shortcut: "⌘⇧5",
  },
  {
    key: "fullscreen" as const,
    icon: Camera,
    label: "Fullscreen",
    desc: "Entire display",
    shortcut: "⌘⇧3",
  },
];

export default function CaptureHome({ onCapture, loading, error }: Props) {
  return (
    <div className="flex flex-col h-full">
      {/* Header */}
      <div className="flex items-center justify-between px-6 py-4 border-b border-white/10">
        <div className="flex items-center gap-2">
          <div className="w-7 h-7 rounded-lg bg-violet-500 flex items-center justify-center">
            <Camera className="w-4 h-4 text-white" />
          </div>
          <span className="font-semibold text-white tracking-tight">Potret</span>
        </div>
        <span className="text-xs text-white/30">v0.1.0</span>
      </div>

      {/* Content */}
      <div className="flex-1 flex flex-col items-center justify-center px-8 gap-8">
        <div className="text-center">
          <h1 className="text-2xl font-bold text-white mb-1">
            Take a screenshot
          </h1>
          <p className="text-sm text-white/40">
            Choose a capture mode to get started
          </p>
        </div>

        {/* Capture mode cards */}
        <div className="grid grid-cols-3 gap-3 w-full max-w-md">
          {modes.map(({ key, icon: Icon, label, desc, shortcut }) => (
            <button
              key={key}
              onClick={() => !loading && onCapture(key)}
              disabled={!!loading}
              className="group flex flex-col items-center gap-3 p-5 rounded-xl
                         bg-white/5 border border-white/10 hover:bg-violet-500/20
                         hover:border-violet-500/50 transition-all duration-150
                         disabled:opacity-40 disabled:cursor-not-allowed cursor-pointer"
            >
              <div className="w-10 h-10 rounded-lg bg-white/10 group-hover:bg-violet-500/30
                              flex items-center justify-center transition-colors">
                <Icon className="w-5 h-5 text-white/70 group-hover:text-violet-300" />
              </div>
              <div className="text-center">
                <div className="text-sm font-medium text-white">{label}</div>
                <div className="text-xs text-white/40 mt-0.5">{desc}</div>
              </div>
              <span className="text-[10px] text-white/20 font-mono">{shortcut}</span>
            </button>
          ))}
        </div>

        {/* Status */}
        {loading && (
          <div className="flex items-center gap-2 text-violet-300 text-sm">
            <Loader2 className="w-4 h-4 animate-spin" />
            {loading}
          </div>
        )}
        {error && !loading && (
          <div className="text-red-400 text-sm text-center max-w-sm">
            {error}
          </div>
        )}
      </div>

      {/* Footer */}
      <div className="px-6 py-3 border-t border-white/10 flex items-center justify-center">
        <span className="text-xs text-white/20">
          Open source · MIT License ·{" "}
          <a
            className="underline text-white/30 hover:text-white/50"
            href="https://github.com/aditpradipta/potret"
            target="_blank"
            rel="noreferrer"
          >
            GitHub
          </a>
        </span>
      </div>
    </div>
  );
}
