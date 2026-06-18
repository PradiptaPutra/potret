interface Props {
  active: boolean;
}

export default function CaptureOverlay({ active }: Props) {
  return (
    <div
      style={{
        position: "fixed",
        inset: 0,
        zIndex: 99999,
        pointerEvents: "none",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        background: "rgba(255,255,255,0.06)",
        opacity: active ? 1 : 0,
        transition: active
          ? "opacity 0.05s ease"
          : "opacity 0.4s ease 0.1s",
      }}
    >
      {/* Flash vignette */}
      <div
        style={{
          position: "absolute",
          inset: 0,
          background: "rgba(255,255,255,0.12)",
          opacity: active ? 1 : 0,
          transition: active ? "opacity 0.05s ease" : "opacity 0.35s ease",
        }}
      />

      {/* "Capturing..." label */}
      <div
        style={{
          position: "relative",
          display: "flex",
          alignItems: "center",
          gap: "8px",
          padding: "10px 18px",
          borderRadius: "12px",
          background: "rgba(10,10,15,0.85)",
          border: "1px solid rgba(255,255,255,0.10)",
          backdropFilter: "blur(12px)",
          opacity: active ? 1 : 0,
          transform: active ? "scale(1)" : "scale(0.92)",
          transition: active
            ? "opacity 0.1s ease, transform 0.15s cubic-bezier(0.16,1,0.3,1)"
            : "opacity 0.2s ease, transform 0.2s ease",
        }}
      >
        <span
          style={{
            width: "6px",
            height: "6px",
            borderRadius: "50%",
            background: "#7c3aed",
            animation: active ? "pulse 1s ease-in-out infinite" : "none",
          }}
        />
        <span
          style={{
            fontSize: "13px",
            fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif",
            color: "rgba(255,255,255,0.85)",
            fontWeight: 500,
          }}
        >
          Capturing…
        </span>
      </div>

      <style>{`
        @keyframes pulse {
          0%, 100% { opacity: 1; }
          50% { opacity: 0.3; }
        }
      `}</style>
    </div>
  );
}
