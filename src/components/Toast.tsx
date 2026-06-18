interface Props {
  message: string;
  type: "success" | "error";
  visible: boolean;
}

export default function Toast({ message, type, visible }: Props) {
  return (
    <div
      style={{
        position: "fixed",
        bottom: "20px",
        right: "20px",
        zIndex: 9999,
        transform: visible ? "translateY(0)" : "translateY(calc(100% + 20px))",
        opacity: visible ? 1 : 0,
        transition: "transform 0.25s cubic-bezier(0.16,1,0.3,1), opacity 0.2s ease",
        pointerEvents: visible ? "auto" : "none",
      }}
    >
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: "8px",
          padding: "10px 14px",
          borderRadius: "10px",
          background: "#16161f",
          border: `1px solid ${type === "success" ? "rgba(16,185,129,0.3)" : "rgba(239,68,68,0.3)"}`,
          boxShadow: "0 8px 32px rgba(0,0,0,0.5)",
          fontSize: "13px",
          fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif",
          color: "rgba(255,255,255,0.9)",
          whiteSpace: "nowrap",
        }}
      >
        <span
          style={{
            width: "6px",
            height: "6px",
            borderRadius: "50%",
            background: type === "success" ? "#10b981" : "#ef4444",
            flexShrink: 0,
          }}
        />
        {message}
      </div>
    </div>
  );
}
