import { useState } from "react";

/**
 * The Homebrew one-liner, with a copy button. The second install path gets a
 * quiet inset field rather than a second filled button — there is only ever
 * one filled action on this page.
 */
export default function CopyLine({ command }: { command: string }) {
  const [copied, setCopied] = useState(false);

  async function copy() {
    try {
      await navigator.clipboard.writeText(command);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1600);
    } catch {
      // A clipboard the browser refuses is not worth an error state — the
      // command is visible and selectable either way.
    }
  }

  return (
    <div className="flex items-center gap-2 rounded-md border border-fog bg-mist px-3 py-2">
      <span aria-hidden="true" className="font-mono text-[12px] text-steel">
        $
      </span>
      {/* min-w-0 lets the code shrink inside the flex row instead of forcing
          the field wider than its column and clipping the last word. */}
      <code className="min-w-0 flex-1 overflow-x-auto whitespace-nowrap font-mono text-[12px] text-slate">
        {command}
      </code>
      <button
        type="button"
        onClick={copy}
        className="shrink-0 rounded px-2 py-1 text-[12px] font-medium text-graphite transition-colors hover:bg-fog hover:text-ink"
        aria-label="Copy the Homebrew command"
      >
        {copied ? "Copied" : "Copy"}
      </button>
    </div>
  );
}
