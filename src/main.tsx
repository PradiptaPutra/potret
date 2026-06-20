import ReactDOM from "react-dom/client";
import App from "./App";
import "./index.css";

// NOTE: StrictMode intentionally removed. Its dev-only double-mount/double-effect behavior
// breaks this app's Tauri event listeners + window show/hide (cleanup runs before listen()
// resolves → stale/duplicate listeners), which broke area capture in `tauri dev`. No prod impact.
ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(<App />);
