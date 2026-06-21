import { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import { X } from "lucide-react";

interface Props {
  windowLabel: string;
}

export default function PinnedView({ windowLabel }: Props) {
  const [imgSrc, setImgSrc] = useState<string | null>(null);

  useEffect(() => {
    // Make body transparent so the window chrome is transparent
    document.body.style.background = "transparent";
    document.body.style.overflow = "hidden";

    invoke<string | null>("get_pinned_data", { windowLabel })
      .then(data => {
        if (data) setImgSrc(`data:image/png;base64,${data}`);
      });

    return () => {
      document.body.style.background = "";
      document.body.style.overflow = "";
    };
  }, [windowLabel]);

  function handleClose() {
    invoke("close_pinned", { windowLabel });
  }

  if (!imgSrc) return null;

  return (
    <div style={{
      width: "100vw",
      height: "100vh",
      display: "flex",
      flexDirection: "column",
      overflow: "hidden",
      borderRadius: 10,
      boxShadow: "0 12px 48px rgba(0,0,0,0.55), 0 2px 8px rgba(0,0,0,0.4)",
      border: "1px solid rgba(255,255,255,0.1)",
      fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
    }}>
      {/* Drag region / header */}
      <div
        data-tauri-drag-region
        style={{
          height: 28,
          flexShrink: 0,
          background: "rgba(20,20,22,0.88)",
          backdropFilter: "blur(20px)",
          WebkitBackdropFilter: "blur(20px)",
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          padding: "0 10px",
          borderRadius: "10px 10px 0 0",
          userSelect: "none",
        }}
      >
        <span style={{
          fontSize: 10,
          fontWeight: 500,
          color: "rgba(255,255,255,0.35)",
          letterSpacing: "0.04em",
        }}>
          📌 Pinned
        </span>
        <button
          onClick={handleClose}
          style={{
            width: 16,
            height: 16,
            borderRadius: "50%",
            background: "rgba(255,69,58,0.85)",
            border: "none",
            cursor: "pointer",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            padding: 0,
          }}
          onMouseEnter={e => (e.currentTarget.style.background = "rgba(255,69,58,1)")}
          onMouseLeave={e => (e.currentTarget.style.background = "rgba(255,69,58,0.85)")}
        >
          <X size={8} color="rgba(255,255,255,0.9)" />
        </button>
      </div>

      {/* Screenshot */}
      <img
        src={imgSrc}
        alt="Pinned screenshot"
        style={{
          flex: 1,
          width: "100%",
          height: "calc(100% - 28px)",
          objectFit: "contain",
          display: "block",
          borderRadius: "0 0 10px 10px",
        }}
      />
    </div>
  );
}
