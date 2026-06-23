import { useEffect, useRef, useState } from "react";

/**
 * ApertureShader — the signature Hero background.
 *
 * A full-bleed raw-WebGL fragment-shader canvas: a slow, flowing amber-on-
 * near-black field evoking an aperture/iris glow. Soft fbm fluid domains in the
 * amber palette over warm ink, animated film grain, a center/upper glow that
 * fades to near-black edges (vignette), and a gentle mouse-reactive warp.
 *
 * Robustness:
 *  - caps devicePixelRatio at 2
 *  - rAF loop, paused when the tab is hidden or the canvas is offscreen
 *  - handles resize
 *  - cleans up (cancels rAF, loses the GL context) on unmount
 *  - prefers-reduced-motion → renders ONE static frame (no loop)
 *  - if `getContext('webgl')` fails → CSS radial-gradient fallback (never blank)
 */

const VERT = `
attribute vec2 aPos;
void main() {
  gl_Position = vec4(aPos, 0.0, 1.0);
}
`;

// Amber aperture-glow field. fbm domains warped toward the cursor, a central
// iris bloom, animated grain, and a soft vignette to near-black at the edges.
const FRAG = `
precision highp float;

uniform vec2  uRes;
uniform float uTime;
uniform vec2  uMouse;   // normalized 0..1, y down
uniform float uDpr;

// palette
const vec3 INK    = vec3(0.043, 0.039, 0.047); // #0b0a0c
const vec3 AMBER  = vec3(1.000, 0.624, 0.039); // #ff9f0a
const vec3 HOT    = vec3(1.000, 0.478, 0.102); // #ff7a1a
const vec3 EMBER  = vec3(0.949, 0.361, 0.020); // #f25c05
const vec3 GLOW   = vec3(1.000, 0.816, 0.541); // #ffd08a

// hash / value noise / fbm
float hash(vec2 p) {
  p = fract(p * vec2(123.34, 345.45));
  p += dot(p, p + 34.345);
  return fract(p.x * p.y);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  float a = hash(i + vec2(0.0, 0.0));
  float b = hash(i + vec2(1.0, 0.0));
  float c = hash(i + vec2(0.0, 1.0));
  float d = hash(i + vec2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
  float v = 0.0;
  float amp = 0.5;
  mat2 rot = mat2(0.80, 0.60, -0.60, 0.80);
  for (int i = 0; i < 5; i++) {
    v += amp * noise(p);
    p = rot * p * 2.0 + 7.3;
    amp *= 0.5;
  }
  return v;
}

void main() {
  // aspect-correct coords, centered, y up
  vec2 uv = gl_FragCoord.xy / uRes.xy;
  vec2 p = (gl_FragCoord.xy - 0.5 * uRes.xy) / uRes.y;

  float t = uTime * 0.045;

  // cursor in the same centered space; warp the field gently toward it
  vec2 m = (uMouse - 0.5);
  m.x *= uRes.x / uRes.y;
  vec2 toM = p - m;
  float md = length(toM);
  // parallax-style pull: field drifts subtly toward the cursor
  p -= m * 0.10 * exp(-md * 1.4);

  // glow concentrated toward center / upper area
  vec2 core = vec2(0.0, 0.16);
  float dCore = length((p - core) * vec2(1.0, 1.15));

  // domain-warped fbm for the fluid amber domains
  vec2 q = vec2(
    fbm(p * 1.6 + vec2(0.0, t * 1.4)),
    fbm(p * 1.6 + vec2(5.2, -t * 1.1) + 1.7)
  );
  vec2 r = vec2(
    fbm(p * 1.6 + 3.0 * q + vec2(1.7, 9.2) + t * 0.6),
    fbm(p * 1.6 + 3.0 * q + vec2(8.3, 2.8) - t * 0.5)
  );
  float f = fbm(p * 1.7 + 2.4 * r + t);

  // iris bloom: tight amber core with a quick radial falloff (kept dim)
  float iris = exp(-dCore * dCore * 5.0);
  float halo = exp(-dCore * 2.2);

  // mouse adds a faint local lift to the glow
  float mouseGlow = 0.10 * exp(-md * md * 4.0);

  // build a DARK amber haze through the flow field — amber is an accent here,
  // not the whole field. Most of the frame stays near ink.
  vec3 col = INK;
  float flow = smoothstep(0.32, 1.0, f);
  col = mix(col, EMBER * 0.30, flow * halo * 0.55);
  col = mix(col, HOT * 0.55, smoothstep(0.58, 1.0, f) * halo * 0.40);
  // amber core, capped well below white so it never blows out to neon yellow
  col = mix(col, AMBER * 0.72, iris * (0.45 + 0.30 * f));
  // a whisper of warm highlight only at the very center
  col += GLOW * iris * iris * (0.10 + mouseGlow);
  col += HOT * mouseGlow * 0.30;

  // pull everything toward ink away from the core for depth
  float depth = smoothstep(1.15, 0.04, dCore);
  col = mix(INK, col, depth);

  // strong vignette to near-black at the frame edges
  float vig = smoothstep(1.32, 0.24, length(p * vec2(0.82, 1.0)));
  col *= 0.08 + 0.92 * vig;

  // overall cinematic dim
  col *= 0.9;

  // animated film grain
  float g = hash(uv * uRes.xy / uDpr + fract(uTime) * 91.7);
  col += (g - 0.5) * 0.04;

  // keep blacks deep — floor at the page ink so the hero blends into the page
  col = max(col, INK * 0.95);

  gl_FragColor = vec4(col, 1.0);
}
`;

function compile(gl: WebGLRenderingContext, type: number, src: string) {
  const sh = gl.createShader(type);
  if (!sh) return null;
  gl.shaderSource(sh, src);
  gl.compileShader(sh);
  if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) {
    gl.deleteShader(sh);
    return null;
  }
  return sh;
}

export default function ApertureShader() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const reduceMotion =
      typeof window.matchMedia === "function" &&
      window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    const gl = (canvas.getContext("webgl", {
      antialias: false,
      alpha: false,
      depth: false,
      stencil: false,
      premultipliedAlpha: false,
      powerPreference: "low-power",
    }) ||
      canvas.getContext("experimental-webgl")) as WebGLRenderingContext | null;

    if (!gl) {
      setFailed(true);
      return;
    }

    const vs = compile(gl, gl.VERTEX_SHADER, VERT);
    const fs = compile(gl, gl.FRAGMENT_SHADER, FRAG);
    if (!vs || !fs) {
      setFailed(true);
      return;
    }

    const prog = gl.createProgram();
    if (!prog) {
      setFailed(true);
      return;
    }
    gl.attachShader(prog, vs);
    gl.attachShader(prog, fs);
    gl.linkProgram(prog);
    if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) {
      setFailed(true);
      return;
    }
    gl.useProgram(prog);

    // fullscreen triangle
    const buf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buf);
    gl.bufferData(
      gl.ARRAY_BUFFER,
      new Float32Array([-1, -1, 3, -1, -1, 3]),
      gl.STATIC_DRAW,
    );
    const aPos = gl.getAttribLocation(prog, "aPos");
    gl.enableVertexAttribArray(aPos);
    gl.vertexAttribPointer(aPos, 2, gl.FLOAT, false, 0, 0);

    const uRes = gl.getUniformLocation(prog, "uRes");
    const uTime = gl.getUniformLocation(prog, "uTime");
    const uMouse = gl.getUniformLocation(prog, "uMouse");
    const uDpr = gl.getUniformLocation(prog, "uDpr");

    let dpr = Math.min(window.devicePixelRatio || 1, 2);
    // soft-target the cursor at center; lerp toward the real pointer
    const mouse = { x: 0.5, y: 0.42 };
    const target = { x: 0.5, y: 0.42 };

    const resize = () => {
      dpr = Math.min(window.devicePixelRatio || 1, 2);
      const w = Math.max(1, Math.floor(canvas.clientWidth * dpr));
      const h = Math.max(1, Math.floor(canvas.clientHeight * dpr));
      if (canvas.width !== w || canvas.height !== h) {
        canvas.width = w;
        canvas.height = h;
      }
      gl.viewport(0, 0, canvas.width, canvas.height);
      gl.uniform2f(uRes, canvas.width, canvas.height);
      gl.uniform1f(uDpr, dpr);
    };

    const onPointer = (e: PointerEvent) => {
      target.x = e.clientX / window.innerWidth;
      target.y = e.clientY / window.innerHeight;
    };

    let raf = 0;
    let running = false;
    let visible = true;
    const start = performance.now();

    const renderFrame = (now: number) => {
      // ease the field toward the pointer for a premium, non-gimmicky feel
      mouse.x += (target.x - mouse.x) * 0.05;
      mouse.y += (target.y - mouse.y) * 0.05;
      gl.uniform1f(uTime, (now - start) / 1000);
      gl.uniform2f(uMouse, mouse.x, mouse.y);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
    };

    const loop = (now: number) => {
      renderFrame(now);
      raf = requestAnimationFrame(loop);
    };

    const startLoop = () => {
      if (running || reduceMotion) return;
      running = true;
      raf = requestAnimationFrame(loop);
    };
    const stopLoop = () => {
      running = false;
      if (raf) cancelAnimationFrame(raf);
      raf = 0;
    };

    const sync = () => {
      if (visible && !document.hidden) startLoop();
      else stopLoop();
    };

    resize();

    // pause when offscreen
    let io: IntersectionObserver | null = null;
    if ("IntersectionObserver" in window) {
      io = new IntersectionObserver(
        (entries) => {
          visible = entries[0]?.isIntersecting ?? true;
          if (reduceMotion) {
            if (visible) renderFrame(performance.now());
          } else {
            sync();
          }
        },
        { threshold: 0 },
      );
      io.observe(canvas);
    }

    const onVisibility = () => sync();
    const onResize = () => {
      resize();
      if (reduceMotion) renderFrame(performance.now());
    };

    window.addEventListener("resize", onResize, { passive: true });
    window.addEventListener("pointermove", onPointer, { passive: true });
    document.addEventListener("visibilitychange", onVisibility);

    if (reduceMotion) {
      // one static frame — no animation loop
      renderFrame(performance.now());
    } else {
      sync();
    }

    return () => {
      stopLoop();
      io?.disconnect();
      window.removeEventListener("resize", onResize);
      window.removeEventListener("pointermove", onPointer);
      document.removeEventListener("visibilitychange", onVisibility);
      gl.deleteProgram(prog);
      gl.deleteShader(vs);
      gl.deleteShader(fs);
      gl.deleteBuffer(buf);
      gl.getExtension("WEBGL_lose_context")?.loseContext();
    };
  }, []);

  // graceful CSS fallback — amber radial-gradient, never a blank/broken canvas
  if (failed) {
    return (
      <div
        aria-hidden
        className="absolute inset-0 -z-10"
        style={{
          background:
            "radial-gradient(95% 70% at 50% 18%, rgba(255,122,26,0.42) 0%, rgba(242,92,5,0.18) 24%, rgba(255,159,10,0.06) 46%, #0b0a0c 70%), #0b0a0c",
        }}
      />
    );
  }

  return (
    <canvas
      ref={canvasRef}
      aria-hidden
      className="absolute inset-0 -z-10 h-full w-full"
      style={{ display: "block" }}
    />
  );
}
