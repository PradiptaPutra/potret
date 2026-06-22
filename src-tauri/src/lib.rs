use base64::{engine::general_purpose, Engine as _};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;
use std::process::Command;
use std::sync::Mutex;
use std::time::Duration;
use tauri::{
    menu::{Menu, MenuItem, PredefinedMenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Emitter, Manager,
};
use uuid::Uuid;

// ---------------------------------------------------------------------------
// Shared state structs
// ---------------------------------------------------------------------------

pub struct PinnedScreenshots {
    pub data: Mutex<HashMap<String, String>>, // window_label → base64 PNG
}

struct CaptureSnapshot {
    capture_id: u64,
    data: String, // base64 PNG thumbnail for the popup preview
    full: Option<Vec<u8>>,
    width: u32,
    height: u32,
}

#[derive(Default)]
struct CapturePopupState {
    latest_requested: u64,
    snapshot: Option<CaptureSnapshot>,
}

pub struct CapturePopupInfo {
    data: Mutex<CapturePopupState>,
}

// ---------------------------------------------------------------------------
// Screenshot / capture types
// ---------------------------------------------------------------------------

#[derive(Debug, Serialize, Deserialize)]
pub struct Screenshot {
    pub data: String, // base64 PNG
    pub width: u32,
    pub height: u32,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct CaptureResult {
    pub success: bool,
    pub screenshot: Option<Screenshot>,
    pub error: Option<String>,
}

// ---------------------------------------------------------------------------
// History types
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HistoryItem {
    pub id: String,
    pub path: String,
    pub thumbnail: String, // base64 PNG ~200px wide
    pub timestamp: u64,    // unix seconds
    pub width: u32,
    pub height: u32,
    pub file_size: u64,
}

#[derive(Debug, Serialize, Deserialize)]
struct HistoryMeta {
    pub id: String,
    pub timestamp: u64,
    pub width: u32,
    pub height: u32,
    pub file_size: u64,
}

// ---------------------------------------------------------------------------
// History helpers
// ---------------------------------------------------------------------------

fn history_dir(app: &AppHandle) -> Result<PathBuf, String> {
    let base = app.path().app_data_dir().map_err(|e| e.to_string())?;
    let dir = base.join("history");
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    Ok(dir)
}

fn make_thumbnail_bytes(bytes: &[u8]) -> Result<Vec<u8>, String> {
    let img = image::load_from_memory(bytes).map_err(|e| e.to_string())?;
    // 640px = pixel-perfect at 2× Retina for ~325px-wide history cards
    let thumb = img.thumbnail(640, u32::MAX);
    let mut buf: Vec<u8> = Vec::new();
    thumb
        .write_to(&mut std::io::Cursor::new(&mut buf), image::ImageFormat::Png)
        .map_err(|e| e.to_string())?;
    Ok(buf)
}

fn popup_temp_dir() -> PathBuf {
    std::env::temp_dir().join("potret_popup")
}

// 640px base64 PNG for the popup preview — inline data URL (reliable in dev + prod, no asset proto)
fn make_popup_thumb(bytes: &[u8]) -> String {
    if let Ok(img) = image::load_from_memory(bytes) {
        let thumb = img.thumbnail(640, u32::MAX);
        let mut buf: Vec<u8> = Vec::new();
        if thumb
            .write_to(&mut std::io::Cursor::new(&mut buf), image::ImageFormat::Png)
            .is_ok()
        {
            return general_purpose::STANDARD.encode(&buf);
        }
    }
    general_purpose::STANDARD.encode(bytes)
}

// Payload sent to the popup window so it can render the preview immediately from the event,
// with no extra IPC round-trip back to the backend.
#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct PopupData {
    capture_id: u64,
    data: String, // base64 PNG thumbnail
    width: u32,
    height: u32,
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct PopupPendingData {
    capture_id: u64,
}

fn begin_capture(app: &AppHandle) -> u64 {
    let Some(state) = app.try_state::<CapturePopupInfo>() else {
        return 0;
    };
    let Ok(mut data) = state.data.lock() else {
        return 0;
    };
    data.latest_requested = data.latest_requested.wrapping_add(1).max(1);
    let capture_id = data.latest_requested;
    drop(data);

    if let Some(popup) = app.get_webview_window("capture-popup") {
        let _ = popup.emit("popup-invalidated", PopupPendingData { capture_id });
        let _ = popup.hide();
    }
    capture_id
}

// Stores the capture in shared state and refreshes the (persistent, hidden) popup window with a
// base64 thumbnail. `capture_id` guards against an older, slower capture clobbering a newer one.
/// Logical bounds (x, y, width, height) of the monitor under the cursor, so the
/// selector overlay and Quick Access popup land on the screen the user is using —
/// not always the primary display. Falls back to the primary monitor, then a default.
fn active_monitor_logical(app: &AppHandle) -> (f64, f64, f64, f64) {
    let monitor = app
        .cursor_position()
        .ok()
        .and_then(|p| app.monitor_from_point(p.x, p.y).ok().flatten())
        .or_else(|| app.primary_monitor().ok().flatten());
    monitor
        .map(|m| {
            let sf = m.scale_factor();
            let pos = m.position();
            let size = m.size();
            (
                pos.x as f64 / sf,
                pos.y as f64 / sf,
                size.width as f64 / sf,
                size.height as f64 / sf,
            )
        })
        .unwrap_or((0.0, 0.0, 1440.0, 900.0))
}

fn store_and_open_popup(
    app: &AppHandle,
    popup_path: PathBuf,
    full_bytes: Option<&[u8]>,
    w: u32,
    h: u32,
    capture_id: u64,
) -> bool {
    use tauri::{WebviewUrl, WebviewWindowBuilder};

    // The temp file was only the screencapture output; the popup renders inline base64, so drop it.
    let _ = std::fs::remove_file(&popup_path);
    let thumb = full_bytes.map(make_popup_thumb).unwrap_or_default();

    if let Some(state) = app.try_state::<CapturePopupInfo>() {
        let Ok(mut data) = state.data.lock() else {
            return false;
        };
        if data.latest_requested != capture_id {
            return false;
        }
        data.snapshot = Some(CaptureSnapshot {
            capture_id,
            data: thumb.clone(),
            full: full_bytes.map(<[u8]>::to_vec),
            width: w,
            height: h,
        });
    }

    let win_w = 320.0_f64;
    // Image fills full width; height clamped to [120, 260] matching the frontend formula
    let img_h = (win_w * h as f64 / w as f64).min(260.0).max(120.0);
    let win_h = img_h + 3.0; // +3px for the progress bar

    let (mon_x, mon_y, _mon_w, mon_h) = active_monitor_logical(app);
    let pos_x = mon_x + 20.0;
    let pos_y = mon_y + mon_h - win_h - 80.0;

    // Reuse the persistent popup window — resize + re-anchor (while hidden), then tell the
    // frontend to load the new capture. The FRONTEND shows the window once it has painted the
    // new content, so the popup never flashes the previous screenshot.
    if let Some(existing) = app.get_webview_window("capture-popup") {
        let _ = existing.set_size(tauri::Size::Logical(tauri::LogicalSize {
            width: win_w,
            height: win_h,
        }));
        let _ = existing.set_position(tauri::Position::Logical(tauri::LogicalPosition {
            x: pos_x,
            y: pos_y,
        }));
        // Send the base64 thumbnail directly — no second get_capture_popup_data round-trip
        let _ = existing.emit(
            "popup-refreshed",
            PopupData {
                capture_id,
                data: thumb,
                width: w,
                height: h,
            },
        );
        return true;
    }

    // Fallback: window somehow missing — create it (should not normally happen).
    let _ = WebviewWindowBuilder::new(app, "capture-popup", WebviewUrl::App("index.html".into()))
        .title("Potret")
        .always_on_top(true)
        .visible_on_all_workspaces(true)
        .decorations(false)
        .transparent(true)
        .shadow(false)
        .resizable(false)
        .inner_size(win_w, win_h)
        .position(pos_x, pos_y)
        .build();
    true
}

fn emit_popup_pending(app: &AppHandle, capture_id: u64) {
    if let Some(state) = app.try_state::<CapturePopupInfo>() {
        if state
            .data
            .lock()
            .map(|data| data.latest_requested != capture_id)
            .unwrap_or(true)
        {
            return;
        }
    }
    let default_h = 203.0_f64;
    let (mon_x, mon_y, _mon_w, mon_h) = active_monitor_logical(app);

    if let Some(existing) = app.get_webview_window("capture-popup") {
        let _ = existing.set_size(tauri::Size::Logical(tauri::LogicalSize {
            width: 320.0,
            height: default_h,
        }));
        let _ = existing.set_position(tauri::Position::Logical(tauri::LogicalPosition {
            x: mon_x + 20.0,
            y: mon_y + mon_h - default_h - 80.0,
        }));
        let _ = existing.emit("popup-pending", PopupPendingData { capture_id });
    }
}

fn prepare_main_window_for_capture(app: &AppHandle, wait_after_hide: Duration) -> bool {
    let main = app.get_webview_window("main");
    let main_was_visible = main
        .as_ref()
        .and_then(|w| w.is_visible().ok())
        .unwrap_or(false);
    if main_was_visible {
        if let Some(w) = &main {
            let _ = w.hide();
        }
        std::thread::sleep(wait_after_hide);
    }
    main_was_visible
}

fn restore_main_window_after_capture(app: &AppHandle, main_was_visible: bool) {
    if !main_was_visible {
        return;
    }
    if let Some(w) = app.get_webview_window("main") {
        let _ = w.show();
    }
}

fn finalize_capture_and_popup(
    app: &AppHandle,
    popup_path: PathBuf,
    bytes: Vec<u8>,
    width: u32,
    height: u32,
    capture_id: u64,
) -> CaptureResult {
    store_and_open_popup(app, popup_path, Some(&bytes), width, height, capture_id);
    queue_capture_persistence(app, bytes);

    CaptureResult {
        success: true,
        screenshot: None,
        error: None,
    }
}

fn queue_capture_persistence(app: &AppHandle, bytes: Vec<u8>) {
    let app_bg = app.clone();
    let config = load_config_sync(app);
    std::thread::spawn(move || {
        if let Err(e) = save_to_history(&app_bg, &bytes) {
            let _ = app_bg.emit("save-error", format!("Couldn't save to history: {e}"));
        } else {
            let _ = app_bg.emit("history-updated", ());
        }
        if let Some(p) = config.save_path.clone() {
            if let Err(e) = auto_save_to_path(&bytes, &p, &config) {
                let _ = app_bg.emit("save-error", format!("Couldn't save to folder: {e}"));
            }
        }
    });
}

// Pre-create the transparent overlay windows once at startup, hidden. They are only ever
// shown/hidden afterwards — never rebuilt. This is what eliminates the macOS transparent-webview
// black flash, the per-capture bundle-reload lag, and the "label already exists" rebuild race.
fn precreate_overlay_windows(app: &AppHandle) {
    use tauri::{WebviewUrl, WebviewWindowBuilder};

    let (screen_w, screen_h) = app
        .primary_monitor()
        .ok()
        .flatten()
        .map(|m| {
            let sf = m.scale_factor();
            let s = m.size();
            (s.width as f64 / sf, s.height as f64 / sf)
        })
        .unwrap_or((1440.0, 900.0));

    // Fullscreen selector overlay
    if app.get_webview_window("capture-selector").is_none() {
        let _ = WebviewWindowBuilder::new(
            app,
            "capture-selector",
            WebviewUrl::App("index.html".into()),
        )
        .always_on_top(true)
        .visible_on_all_workspaces(true) // follow the user to whatever Space/desktop they're on
        .decorations(false)
        .transparent(true)
        .shadow(false)
        .resizable(false)
        .skip_taskbar(true)
        .visible(false)
        .inner_size(screen_w, screen_h)
        .position(0.0, 0.0)
        .build();
    }

    // Bottom-left quick-access popup (default size; resized per capture)
    if app.get_webview_window("capture-popup").is_none() {
        let default_h = 203.0_f64;
        let _ =
            WebviewWindowBuilder::new(app, "capture-popup", WebviewUrl::App("index.html".into()))
                .title("Potret")
                .always_on_top(true)
                .visible_on_all_workspaces(true) // follow the active Space/desktop
                .decorations(false)
                .transparent(true)
                .shadow(false)
                .resizable(false)
                .skip_taskbar(true)
                .visible(false)
                .inner_size(320.0, default_h)
                .position(20.0, screen_h - default_h - 80.0)
                .build();
    }

    // Menubar "Recent Captures" history popup (persistent, hidden, shown from the tray)
    if app.get_webview_window("history").is_none() {
        let hist_w = 380.0_f64;
        let hist_h = 520.0_f64;
        let _ = WebviewWindowBuilder::new(app, "history", WebviewUrl::App("index.html".into()))
            .title("Recent Captures")
            .always_on_top(true)
            .visible_on_all_workspaces(true)
            .decorations(false)
            .transparent(true)
            .shadow(false)
            .resizable(false)
            .skip_taskbar(true)
            .visible(false)
            .inner_size(hist_w, hist_h)
            .position(screen_w - hist_w - 20.0, 40.0)
            .build();
    }
}

fn save_to_history(app: &AppHandle, bytes: &[u8]) -> Result<HistoryItem, String> {
    let dir = history_dir(app)?;

    let id = Uuid::new_v4().to_string();
    let timestamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);

    let png_path = dir.join(format!("{}.png", id));
    let meta_path = dir.join(format!("{}.json", id));

    // Write PNG
    std::fs::write(&png_path, bytes).map_err(|e| e.to_string())?;

    let file_size = bytes.len() as u64;
    let (width, height) = image_dimensions(bytes).unwrap_or((0, 0));

    // Generate the 640px thumbnail once and cache it to disk so get_history never
    // has to re-decode the full-resolution PNG again.
    let thumb_bytes = make_thumbnail_bytes(bytes)?;
    let thumb_path = dir.join(format!("{}.thumb.png", id));
    let _ = std::fs::write(&thumb_path, &thumb_bytes);
    let thumbnail = general_purpose::STANDARD.encode(&thumb_bytes);

    let meta = HistoryMeta {
        id: id.clone(),
        timestamp,
        width,
        height,
        file_size,
    };
    let meta_json = serde_json::to_string(&meta).map_err(|e| e.to_string())?;
    std::fs::write(&meta_path, meta_json).map_err(|e| e.to_string())?;

    Ok(HistoryItem {
        id,
        path: png_path.to_string_lossy().to_string(),
        thumbnail,
        timestamp,
        width,
        height,
        file_size,
    })
}

// ---------------------------------------------------------------------------
// Capture commands
// ---------------------------------------------------------------------------

#[tauri::command]
async fn capture_fullscreen(app: AppHandle) -> CaptureResult {
    let capture_id = begin_capture(&app);
    capture_with_args(&app, &["-x"], capture_id)
}

#[tauri::command]
async fn capture_area(app: AppHandle) -> CaptureResult {
    let capture_id = begin_capture(&app);
    capture_with_args(&app, &["-x", "-s"], capture_id)
}

#[tauri::command]
async fn capture_window(app: AppHandle) -> CaptureResult {
    let capture_id = begin_capture(&app);
    capture_with_args(&app, &["-x", "-w"], capture_id)
}

// Render the template once, then append -1, -2, … until the path is free (no overwrite).
fn unique_save_path(dir: &std::path::Path, template: &str, ext: &str) -> PathBuf {
    let base = render_filename(template, ext, 0);
    let mut path = dir.join(&base);
    let stem = base.trim_end_matches(&format!(".{ext}")).to_string();
    let mut seq = 1u64;
    while path.exists() && seq < 10000 {
        path = dir.join(format!("{stem}-{seq}.{ext}"));
        seq += 1;
    }
    path
}

fn auto_save_to_path(bytes: &[u8], save_path: &str, config: &AppConfig) -> Result<(), String> {
    let dir = PathBuf::from(save_path);
    if !dir.exists() {
        return Err(format!("Save folder not found: {save_path}"));
    }
    let (out, ext) = encode_for_output(bytes, &config.format, config.jpeg_quality);
    let path = unique_save_path(&dir, &config.filename_template, ext);
    std::fs::write(&path, &out).map_err(|e| e.to_string())
}

fn capture_with_args(app: &AppHandle, extra_args: &[&str], capture_id: u64) -> CaptureResult {
    // Unique temp file per capture so two quick captures can't clobber each other.
    let dir = popup_temp_dir();
    let _ = std::fs::create_dir_all(&dir);
    let tmp = dir.join(format!("{}.png", Uuid::new_v4()));
    let tmp_str = tmp.to_string_lossy().to_string();

    // A previous quick-access popup must not appear in the next screenshot.
    if let Some(popup) = app.get_webview_window("capture-popup") {
        let _ = popup.hide();
    }

    // Hide our own main window so it isn't in the screenshot; restore it afterward.
    let main_was_visible = prepare_main_window_for_capture(app, Duration::from_millis(24));

    let mut args: Vec<&str> = extra_args.to_vec();
    args.push(tmp_str.as_str());

    // -s/-w show an interactive picker the user can cancel; -x does not.
    let interactive = extra_args.iter().any(|a| *a == "-s" || *a == "-w");

    // screencapture runs the interactive UI (for -s/-w) and blocks until done.
    let status = Command::new("screencapture")
        .args(&args)
        .stderr(std::process::Stdio::null())
        .status();

    restore_main_window_after_capture(app, main_was_visible);

    if !tmp.exists() {
        // No file produced. Tell a deliberate cancel apart from a real failure so
        // the user gets feedback instead of silence when something actually broke.
        if !check_screen_recording_permission() {
            return CaptureResult {
                success: false,
                screenshot: None,
                error: Some(
                    "Screen Recording permission is required. Enable it in System Settings, then restart Potret."
                        .into(),
                ),
            };
        }
        if interactive {
            return CaptureResult {
                success: false,
                screenshot: None,
                error: None,
            }; // user pressed Esc in the picker — not an error
        }
        let detail = match status {
            Ok(s) if !s.success() => format!("screencapture exited with {s}"),
            Err(e) => format!("could not run screencapture: {e}"),
            _ => "no image was produced".to_string(),
        };
        return CaptureResult {
            success: false,
            screenshot: None,
            error: Some(format!("Capture failed — {detail}.")),
        };
    }

    // The OS has committed the new image, so the loading shell can no longer be captured.
    emit_popup_pending(app, capture_id);

    match std::fs::read(&tmp) {
        Ok(bytes) => {
            let (w, h) = image_dimensions(&bytes).unwrap_or((0, 0));
            finalize_capture_and_popup(app, tmp, bytes, w, h, capture_id)
        }
        Err(e) => {
            let _ = std::fs::remove_file(&tmp);
            CaptureResult {
                success: false,
                screenshot: None,
                error: Some(e.to_string()),
            }
        }
    }
}

fn image_dimensions(bytes: &[u8]) -> Option<(u32, u32)> {
    let cursor = std::io::Cursor::new(bytes);
    image::ImageReader::new(cursor)
        .with_guessed_format()
        .ok()?
        .into_dimensions()
        .ok()
}

fn capture_selected_region(
    app: &AppHandle,
    x: f64,
    y: f64,
    w: f64,
    h: f64,
    _dpr: f64,
    capture_id: u64,
) -> CaptureResult {
    let rx = x.round().max(0.0) as i32;
    let ry = y.round().max(0.0) as i32;
    let rw = w.round().max(1.0) as i32;
    let rh = h.round().max(1.0) as i32;
    let rect = format!("{rx},{ry},{rw},{rh}");

    let dir = popup_temp_dir();
    let _ = std::fs::create_dir_all(&dir);
    let tmp = dir.join(format!("{}.png", Uuid::new_v4()));
    let tmp_str = tmp.to_string_lossy().to_string();

    // -R captures only the selected region (no full-screen decode/crop needed)
    let _ = Command::new("screencapture")
        .args(["-x", "-R", rect.as_str(), tmp_str.as_str()])
        .stderr(std::process::Stdio::null())
        .status();

    if !tmp.exists() {
        let msg = if !check_screen_recording_permission() {
            "Screen Recording permission is required. Enable it in System Settings, then restart Potret."
        } else {
            "Capture failed — no image was produced."
        };
        return CaptureResult {
            success: false,
            screenshot: None,
            error: Some(msg.into()),
        };
    }

    // Reveal only after screencapture has committed the region, avoiding self-capture.
    emit_popup_pending(app, capture_id);

    match std::fs::read(&tmp) {
        Ok(bytes) => {
            let (width, height) = image_dimensions(&bytes).unwrap_or((0, 0));
            finalize_capture_and_popup(app, tmp, bytes, width, height, capture_id)
        }
        Err(e) => {
            let _ = std::fs::remove_file(&tmp);
            CaptureResult {
                success: false,
                screenshot: None,
                error: Some(e.to_string()),
            }
        }
    }
}

// ---------------------------------------------------------------------------
// History commands
// ---------------------------------------------------------------------------

#[tauri::command]
async fn get_history(app: AppHandle) -> Result<Vec<HistoryItem>, String> {
    let dir = history_dir(&app)?;

    // 1) Collect metadata only (cheap — small JSON reads, no image decode)
    let mut metas: Vec<HistoryMeta> = Vec::new();
    for entry in std::fs::read_dir(&dir)
        .map_err(|e| e.to_string())?
        .flatten()
    {
        let path = entry.path();
        if path.extension().and_then(|e| e.to_str()) != Some("json") {
            continue;
        }
        if let Ok(s) = std::fs::read_to_string(&path) {
            if let Ok(m) = serde_json::from_str::<HistoryMeta>(&s) {
                metas.push(m);
            }
        }
    }

    // 2) Newest first, cap at 50 BEFORE doing any thumbnail work
    metas.sort_by(|a, b| b.timestamp.cmp(&a.timestamp));
    metas.truncate(50);

    // 3) Build items using the cached on-disk thumbnail; generate + cache on miss
    let mut items: Vec<HistoryItem> = Vec::with_capacity(metas.len());
    for meta in metas {
        let png_path = dir.join(format!("{}.png", meta.id));
        if !png_path.exists() {
            continue;
        }

        let thumb_path = dir.join(format!("{}.thumb.png", meta.id));
        let thumbnail = if let Ok(tb) = std::fs::read(&thumb_path) {
            general_purpose::STANDARD.encode(&tb)
        } else {
            // Cache miss (older item): decode the full PNG once, then cache it
            match std::fs::read(&png_path)
                .ok()
                .and_then(|b| make_thumbnail_bytes(&b).ok())
            {
                Some(tb) => {
                    let _ = std::fs::write(&thumb_path, &tb);
                    general_purpose::STANDARD.encode(&tb)
                }
                None => String::new(),
            }
        };

        items.push(HistoryItem {
            id: meta.id,
            path: png_path.to_string_lossy().to_string(),
            thumbnail,
            timestamp: meta.timestamp,
            width: meta.width,
            height: meta.height,
            file_size: meta.file_size,
        });
    }

    Ok(items)
}

// Persist an (annotated) PNG into history. Used after the annotation editor saves.
#[tauri::command]
async fn add_to_history(app: AppHandle, data: String) -> Result<(), String> {
    let bytes = general_purpose::STANDARD
        .decode(&data)
        .map_err(|e| e.to_string())?;
    save_to_history(&app, &bytes)?;
    Ok(())
}

// Load the full-resolution PNG for a history item as base64 (for copy / edit / pin / background)
#[tauri::command]
async fn get_history_full(app: AppHandle, id: String) -> Result<String, String> {
    if !id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-') {
        return Err("Invalid id".into());
    }
    let dir = history_dir(&app)?;
    let png_path = dir.join(format!("{}.png", id));
    let bytes = std::fs::read(&png_path).map_err(|e| e.to_string())?;
    Ok(general_purpose::STANDARD.encode(&bytes))
}

#[tauri::command]
async fn delete_history_item(app: AppHandle, id: String) -> Result<(), String> {
    // Validate id is a valid UUID to prevent path traversal
    if !id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-') {
        return Err("Invalid id".into());
    }

    let dir = history_dir(&app)?;
    let png_path = dir.join(format!("{}.png", id));
    let meta_path = dir.join(format!("{}.json", id));
    let thumb_path = dir.join(format!("{}.thumb.png", id));

    if png_path.exists() {
        std::fs::remove_file(&png_path).map_err(|e| e.to_string())?;
    }
    if meta_path.exists() {
        std::fs::remove_file(&meta_path).map_err(|e| e.to_string())?;
    }
    if thumb_path.exists() {
        let _ = std::fs::remove_file(&thumb_path);
    }

    Ok(())
}

#[tauri::command]
async fn clear_history(app: AppHandle) -> Result<(), String> {
    let dir = history_dir(&app)?;
    let entries = std::fs::read_dir(&dir).map_err(|e| e.to_string())?;
    for entry in entries.flatten() {
        let path = entry.path();
        if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
            if ext == "png" || ext == "json" {
                let _ = std::fs::remove_file(path);
            }
        }
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Config types and commands
// ---------------------------------------------------------------------------

fn default_format() -> String {
    "png".into()
}
fn default_jpeg_quality() -> u8 {
    90
}
fn default_filename_template() -> String {
    "Screenshot {date} at {time}".into()
}
fn default_shortcut_history() -> String {
    "CommandOrControl+Shift+H".into()
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppConfig {
    pub shortcut_area: String,
    pub shortcut_window: String,
    pub shortcut_fullscreen: String,
    pub save_path: Option<String>,
    // Output options — #[serde(default = ...)] keeps old config.json files loading
    #[serde(default = "default_format")]
    pub format: String, // "png" | "jpg"
    #[serde(default = "default_jpeg_quality")]
    pub jpeg_quality: u8, // 1–100, JPG only
    #[serde(default = "default_filename_template")]
    pub filename_template: String,
    #[serde(default = "default_shortcut_history")]
    pub shortcut_history: String,
}

impl Default for AppConfig {
    fn default() -> Self {
        Self {
            shortcut_area: "CommandOrControl+Shift+4".into(),
            shortcut_window: "CommandOrControl+Shift+5".into(),
            shortcut_fullscreen: "CommandOrControl+Shift+3".into(),
            save_path: None,
            format: default_format(),
            jpeg_quality: default_jpeg_quality(),
            filename_template: default_filename_template(),
            shortcut_history: default_shortcut_history(),
        }
    }
}

// Render a filename from a template, substituting {date} {time} {unix} {seq} and sanitizing.
fn render_filename(template: &str, ext: &str, seq: u64) -> String {
    let now = chrono::Local::now();
    let date = now.format("%Y-%m-%d").to_string();
    let time = now.format("%H-%M-%S").to_string();
    let unix = now.timestamp().to_string();
    let mut name = template
        .replace("{date}", &date)
        .replace("{time}", &time)
        .replace("{unix}", &unix)
        .replace("{seq}", &seq.to_string());
    // Strip characters illegal in filenames
    name = name
        .chars()
        .map(|c| if "/\\:*?\"<>|".contains(c) { '-' } else { c })
        .collect();
    if name.trim().is_empty() {
        name = format!("Screenshot {}", unix);
    }
    format!("{}.{}", name.trim(), ext)
}

// Encode PNG bytes into the configured output format. Returns (bytes, extension).
fn encode_for_output(png_bytes: &[u8], format: &str, quality: u8) -> (Vec<u8>, &'static str) {
    if format.eq_ignore_ascii_case("jpg") || format.eq_ignore_ascii_case("jpeg") {
        if let Ok(img) = image::load_from_memory(png_bytes) {
            let rgb = img.to_rgb8(); // JPEG has no alpha
            let mut buf: Vec<u8> = Vec::new();
            let mut enc =
                image::codecs::jpeg::JpegEncoder::new_with_quality(&mut buf, quality.clamp(1, 100));
            if enc.encode_image(&rgb).is_ok() {
                return (buf, "jpg");
            }
        }
    }
    (png_bytes.to_vec(), "png")
}

fn config_path(app: &AppHandle) -> Result<std::path::PathBuf, String> {
    let base = app.path().app_data_dir().map_err(|e| e.to_string())?;
    std::fs::create_dir_all(&base).map_err(|e| e.to_string())?;
    Ok(base.join("config.json"))
}

#[tauri::command]
async fn get_config(app: AppHandle) -> Result<AppConfig, String> {
    let path = config_path(&app)?;
    if !path.exists() {
        return Ok(AppConfig::default());
    }
    let s = std::fs::read_to_string(&path).map_err(|e| e.to_string())?;
    serde_json::from_str(&s).map_err(|e| e.to_string())
}

#[tauri::command]
async fn save_config(app: AppHandle, config: AppConfig) -> Result<(), String> {
    let path = config_path(&app)?;
    let s = serde_json::to_string_pretty(&config).map_err(|e| e.to_string())?;
    std::fs::write(&path, s).map_err(|e| e.to_string())?;
    // Re-register global shortcuts immediately with the new config
    register_shortcuts_from_config(&app, &config);
    Ok(())
}

fn load_config_sync(app: &AppHandle) -> AppConfig {
    let path = match config_path(app) {
        Ok(p) => p,
        Err(_) => return AppConfig::default(),
    };
    if !path.exists() {
        return AppConfig::default();
    }
    std::fs::read_to_string(&path)
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

fn parse_shortcut_str(s: &str) -> Result<tauri_plugin_global_shortcut::Shortcut, String> {
    use tauri_plugin_global_shortcut::{Code, Modifiers, Shortcut};

    let mut mods = Modifiers::empty();
    let mut code: Option<Code> = None;

    for part in s.split('+') {
        match part.trim() {
            "CommandOrControl" | "CmdOrCtrl" | "Command" => {
                #[cfg(target_os = "macos")]
                {
                    mods |= Modifiers::META;
                }
                #[cfg(not(target_os = "macos"))]
                {
                    mods |= Modifiers::CONTROL;
                }
            }
            "Shift" => mods |= Modifiers::SHIFT,
            "Alt" | "Option" => mods |= Modifiers::ALT,
            "Control" | "Ctrl" => mods |= Modifiers::CONTROL,
            "Meta" | "Super" => mods |= Modifiers::META,
            k => {
                code = Some(match k {
                    "0" => Code::Digit0,
                    "1" => Code::Digit1,
                    "2" => Code::Digit2,
                    "3" => Code::Digit3,
                    "4" => Code::Digit4,
                    "5" => Code::Digit5,
                    "6" => Code::Digit6,
                    "7" => Code::Digit7,
                    "8" => Code::Digit8,
                    "9" => Code::Digit9,
                    "A" => Code::KeyA,
                    "B" => Code::KeyB,
                    "C" => Code::KeyC,
                    "D" => Code::KeyD,
                    "E" => Code::KeyE,
                    "F" => Code::KeyF,
                    "G" => Code::KeyG,
                    "H" => Code::KeyH,
                    "I" => Code::KeyI,
                    "J" => Code::KeyJ,
                    "K" => Code::KeyK,
                    "L" => Code::KeyL,
                    "M" => Code::KeyM,
                    "N" => Code::KeyN,
                    "O" => Code::KeyO,
                    "P" => Code::KeyP,
                    "Q" => Code::KeyQ,
                    "R" => Code::KeyR,
                    "S" => Code::KeyS,
                    "T" => Code::KeyT,
                    "U" => Code::KeyU,
                    "V" => Code::KeyV,
                    "W" => Code::KeyW,
                    "X" => Code::KeyX,
                    "Y" => Code::KeyY,
                    "Z" => Code::KeyZ,
                    "F1" => Code::F1,
                    "F2" => Code::F2,
                    "F3" => Code::F3,
                    "F4" => Code::F4,
                    "F5" => Code::F5,
                    "F6" => Code::F6,
                    "F7" => Code::F7,
                    "F8" => Code::F8,
                    "F9" => Code::F9,
                    "F10" => Code::F10,
                    "F11" => Code::F11,
                    "F12" => Code::F12,
                    _ => return Err(format!("Unknown key: {k}")),
                });
            }
        }
    }

    let code = code.ok_or_else(|| format!("No key code in shortcut string: {s}"))?;
    let mods_opt = if mods.is_empty() { None } else { Some(mods) };
    Ok(Shortcut::new(mods_opt, code))
}

fn register_shortcuts_from_config(app: &AppHandle, config: &AppConfig) {
    use tauri_plugin_global_shortcut::{GlobalShortcutExt, ShortcutState};

    let _ = app.global_shortcut().unregister_all();

    let sc_area = match parse_shortcut_str(&config.shortcut_area) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("[potret] Invalid area shortcut: {e}");
            return;
        }
    };
    let sc_window = match parse_shortcut_str(&config.shortcut_window) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("[potret] Invalid window shortcut: {e}");
            return;
        }
    };
    let sc_fullscreen = match parse_shortcut_str(&config.shortcut_fullscreen) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("[potret] Invalid fullscreen shortcut: {e}");
            return;
        }
    };

    // History shortcut is optional — if it's invalid we still register the captures.
    let sc_history = parse_shortcut_str(&config.shortcut_history).ok();

    let area_code = sc_area.key;
    let window_code = sc_window.key;
    let fullscreen_code = sc_fullscreen.key;
    let history_code = sc_history.as_ref().map(|s| s.key);
    let app2 = app.clone();

    let mut shortcuts = vec![sc_fullscreen, sc_area, sc_window];
    if let Some(h) = sc_history {
        shortcuts.push(h);
    }

    let _ = app.global_shortcut().on_shortcuts(
        shortcuts,
        move |_app, shortcut, event| {
            if event.state != ShortcutState::Pressed {
                return;
            }
            if history_code == Some(shortcut.key) {
                show_history_window(&app2); // open the Recent Captures popup
                return;
            }
            let mode = if shortcut.key == fullscreen_code {
                "fullscreen"
            } else if shortcut.key == area_code {
                "area"
            } else if shortcut.key == window_code {
                "window"
            } else {
                return;
            };
            let _ = app2.emit("shortcut-triggered", serde_json::json!({ "mode": mode }));
        },
    );
}

#[tauri::command]
async fn pick_folder(app: AppHandle) -> Result<Option<String>, String> {
    use tauri_plugin_dialog::DialogExt;
    let path = app.dialog().file().blocking_pick_folder();
    Ok(path.map(|p| p.to_string()))
}

#[tauri::command]
async fn pin_screenshot(
    app: AppHandle,
    state: tauri::State<'_, PinnedScreenshots>,
    data: String,
    img_width: u32,
    img_height: u32,
) -> Result<(), String> {
    use tauri::{WebviewUrl, WebviewWindowBuilder};

    let short_id = Uuid::new_v4()
        .to_string()
        .replace('-', "")
        .chars()
        .take(8)
        .collect::<String>();
    let label = format!("pinned-{short_id}");

    state
        .data
        .lock()
        .map_err(|e| e.to_string())?
        .insert(label.clone(), data);

    // Scale down if too large, keeping aspect ratio
    let max_w = 560_f64;
    let scale = if img_width as f64 > max_w {
        max_w / img_width as f64
    } else {
        1.0_f64
    };
    let win_w = (img_width as f64 * scale).round();
    let win_h = (img_height as f64 * scale).round() + 28.0; // +28 for drag header

    let win = WebviewWindowBuilder::new(&app, &label, WebviewUrl::App("index.html".into()))
        .title("Pinned — Potret")
        .always_on_top(true)
        .decorations(false)
        .transparent(true)
        .shadow(true)
        .resizable(true)
        .inner_size(win_w, win_h)
        .build()
        .map_err(|e| e.to_string())?;

    // Free the stored image when the window is closed by ANY means (OS close, ⌘W, etc.),
    // not just via the close_pinned command — otherwise the base64 leaks for the session.
    let app_evt = app.clone();
    let label_evt = label.clone();
    win.on_window_event(move |event| {
        if matches!(event, tauri::WindowEvent::Destroyed) {
            if let Some(state) = app_evt.try_state::<PinnedScreenshots>() {
                if let Ok(mut map) = state.data.lock() {
                    map.remove(&label_evt);
                }
            }
        }
    });

    Ok(())
}

#[tauri::command]
async fn get_pinned_data(
    state: tauri::State<'_, PinnedScreenshots>,
    window_label: String,
) -> Result<Option<String>, String> {
    Ok(state
        .data
        .lock()
        .map_err(|e| e.to_string())?
        .get(&window_label)
        .cloned())
}

#[tauri::command]
async fn close_pinned(
    app: AppHandle,
    state: tauri::State<'_, PinnedScreenshots>,
    window_label: String,
) -> Result<(), String> {
    state
        .data
        .lock()
        .map_err(|e| e.to_string())?
        .remove(&window_label);
    if let Some(win) = app.get_webview_window(&window_label) {
        win.close().map_err(|e| e.to_string())?;
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Save / clipboard / annotation commands
// ---------------------------------------------------------------------------

#[tauri::command]
async fn save_image(data: String, path: String) -> Result<(), String> {
    // The path comes from the native Save dialog (user-chosen), but harden anyway:
    // only ever write image files, so a compromised webview can't use this command
    // to overwrite a shell rc / LaunchAgent / config file.
    let ext_ok = std::path::Path::new(&path)
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| matches!(e.to_ascii_lowercase().as_str(), "png" | "jpg" | "jpeg"))
        .unwrap_or(false);
    if !ext_ok {
        return Err("Refusing to save: path must end in .png, .jpg, or .jpeg".into());
    }
    let bytes = general_purpose::STANDARD
        .decode(&data)
        .map_err(|e| e.to_string())?;
    std::fs::write(&path, &bytes).map_err(|e| e.to_string())
}

// Save an edited image to the user's configured folder, applying the filename
// template and output format (PNG/JPG) — the same path a direct capture takes.
#[tauri::command]
async fn save_image_with_config(app: AppHandle, data: String) -> Result<String, String> {
    let bytes = general_purpose::STANDARD
        .decode(&data)
        .map_err(|e| e.to_string())?;
    let config = load_config_sync(&app);
    let dir = config
        .save_path
        .clone()
        .ok_or_else(|| "No save folder configured".to_string())?;
    let dir = PathBuf::from(dir);
    if !dir.exists() {
        std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    }
    let (out, ext) = encode_for_output(&bytes, &config.format, config.jpeg_quality);
    let path = unique_save_path(&dir, &config.filename_template, ext);
    std::fs::write(&path, &out).map_err(|e| e.to_string())?;
    Ok(path.to_string_lossy().to_string())
}

#[tauri::command]
async fn copy_to_clipboard(data: String) -> Result<(), String> {
    let bytes = general_purpose::STANDARD
        .decode(&data)
        .map_err(|e| e.to_string())?;

    // Unique temp file so concurrent copies don't clobber / delete each other's file.
    let tmp = std::env::temp_dir().join(format!("potret_clipboard_{}.png", Uuid::new_v4()));
    std::fs::write(&tmp, &bytes).map_err(|e| e.to_string())?;

    let status = Command::new("osascript")
        .arg("-e")
        .arg(format!(
            "set the clipboard to (read (POSIX file \"{}\") as «class PNGf»)",
            tmp.to_string_lossy()
        ))
        .status()
        .map_err(|e| e.to_string())?;

    let _ = std::fs::remove_file(&tmp);

    if status.success() {
        Ok(())
    } else {
        Err("Failed to copy to clipboard".into())
    }
}

// ---------------------------------------------------------------------------
// macOS permission helpers
// ---------------------------------------------------------------------------

#[cfg(target_os = "macos")]
#[link(name = "CoreGraphics", kind = "framework")]
extern "C" {
    fn CGPreflightScreenCaptureAccess() -> bool;
    fn CGRequestScreenCaptureAccess() -> bool;
}

#[tauri::command]
fn check_screen_recording_permission() -> bool {
    #[cfg(target_os = "macos")]
    unsafe {
        CGPreflightScreenCaptureAccess()
    }
    #[cfg(not(target_os = "macos"))]
    {
        true
    }
}

#[tauri::command]
async fn request_screen_recording_permission() -> bool {
    #[cfg(target_os = "macos")]
    unsafe {
        CGRequestScreenCaptureAccess()
    }
    #[cfg(not(target_os = "macos"))]
    {
        true
    }
}

#[tauri::command]
async fn open_system_settings_permissions() {
    #[cfg(target_os = "macos")]
    {
        // Works on macOS 13 Ventura and later
        let _ = Command::new("open")
            .arg("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
            .status();
    }
}

// Screen Recording permission only takes effect after a full relaunch, so the UI offers this.
#[tauri::command]
fn restart_app(app: AppHandle) {
    app.restart();
}

// ---------------------------------------------------------------------------
// Custom capture selector overlay
// ---------------------------------------------------------------------------

#[tauri::command]
async fn open_capture_selector(app: AppHandle) -> Result<(), String> {
    let capture_id = begin_capture(&app);
    // The selector is pre-created hidden at startup. Re-fit it to the current screen and tell
    // the frontend to reset its drag state. The FRONTEND shows the window after it clears the
    // previous selection, so the selector never flashes a stale rectangle (mirrors the popup).
    let (mon_x, mon_y, sw, sh) = active_monitor_logical(&app);

    // Safety net: if the persistent window is gone, recreate it hidden first.
    if app.get_webview_window("capture-selector").is_none() {
        precreate_overlay_windows(&app);
    }

    let win = app
        .get_webview_window("capture-selector")
        .ok_or_else(|| "Selector window unavailable".to_string())?;

    let _ = win.set_size(tauri::Size::Logical(tauri::LogicalSize {
        width: sw,
        height: sh,
    }));
    let _ = win.set_position(tauri::Position::Logical(tauri::LogicalPosition {
        x: mon_x,
        y: mon_y,
    }));
    // Frontend resets state then shows the window — do NOT show() here (avoids stale-selection flash).
    // Pre-set the native crosshair so it's ready the instant the frontend shows the window
    // (CSS `cursor` alone only repaints on the next mouse move — often absent on the shortcut path).
    let _ = win.set_cursor_icon(tauri::CursorIcon::Crosshair);
    let _ = win.emit("selector-activate", PopupPendingData { capture_id });
    Ok(())
}

#[tauri::command]
async fn capture_region_and_crop(
    app: AppHandle,
    capture_id: u64,
    x: f64,
    y: f64,
    w: f64,
    h: f64,
    dpr: f64,
) -> CaptureResult {
    // Hide (not close) the persistent selector window; reset its cursor first so the
    // crosshair doesn't stay stuck on screen after the overlay disappears.
    if let Some(win) = app.get_webview_window("capture-selector") {
        let _ = win.set_cursor_icon(tauri::CursorIcon::Default);
        let _ = win.hide();
    }
    // Let the overlay clear the compositor before screenshotting
    tokio::time::sleep(Duration::from_millis(10)).await;

    let result = capture_selected_region(&app, x, y, w, h, dpr, capture_id);
    if !result.success {
        // Surface real failures (the selector is fire-and-forget, so the returned
        // error would otherwise vanish). A plain cancel carries no error message.
        if let Some(err) = &result.error {
            let _ = app.emit("save-error", err.clone());
        }
        return result;
    }

    // Tell the main window to reload history
    let _ = app.emit("capture-completed", ());
    result
}

// ---------------------------------------------------------------------------
// Capture popup window
// ---------------------------------------------------------------------------

// Returns the popup preview path + dimensions (used only for the cold-mount case; the hot path
// gets this directly in the popup-refreshed event payload).
#[tauri::command]
async fn get_capture_popup_data(
    state: tauri::State<'_, CapturePopupInfo>,
) -> Result<Option<PopupData>, String> {
    let data = state.data.lock().map_err(|e| e.to_string())?;
    Ok(data.snapshot.as_ref().map(|snapshot| PopupData {
        capture_id: snapshot.capture_id,
        data: snapshot.data.clone(),
        width: snapshot.width,
        height: snapshot.height,
    }))
}

// Returns the full-resolution base64 PNG (slower, only fetched when user edits)
async fn wait_for_capture_bytes(
    state: &CapturePopupInfo,
    capture_id: u64,
) -> Result<Vec<u8>, String> {
    for _ in 0..100 {
        {
            let data = state.data.lock().map_err(|e| e.to_string())?;
            if data.latest_requested != capture_id {
                return Err("Capture is no longer current".to_string());
            }
            if let Some(full) = data
                .snapshot
                .as_ref()
                .filter(|snapshot| snapshot.capture_id == capture_id)
                .and_then(|snapshot| snapshot.full.clone())
            {
                return Ok(full);
            }
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    Err("Capture is still processing".to_string())
}

#[tauri::command]
async fn get_capture_full_data(
    state: tauri::State<'_, CapturePopupInfo>,
    capture_id: u64,
) -> Result<Option<String>, String> {
    match wait_for_capture_bytes(&state, capture_id).await {
        Ok(full) => Ok(Some(general_purpose::STANDARD.encode(full))),
        Err(error) if error == "Capture is no longer current" => Ok(None),
        Err(error) => Err(error),
    }
}

#[tauri::command]
async fn close_capture_popup(
    app: AppHandle,
    state: tauri::State<'_, CapturePopupInfo>,
    capture_id: u64,
) -> Result<(), String> {
    {
        let mut data = state.data.lock().map_err(|e| e.to_string())?;
        if data.latest_requested != capture_id {
            return Ok(());
        }
        let _ = data
            .snapshot
            .take()
            .filter(|snapshot| snapshot.capture_id == capture_id);
    }
    // Hide (not close) — the window is kept alive for reuse on the next capture
    if let Some(win) = app.get_webview_window("capture-popup") {
        let _ = win.hide();
    }
    Ok(())
}

// Save the full-res capture to the configured save path, or ~/Desktop if not set
#[tauri::command]
async fn quick_save_capture(
    app: AppHandle,
    state: tauri::State<'_, CapturePopupInfo>,
    capture_id: u64,
) -> Result<String, String> {
    let bytes = wait_for_capture_bytes(&state, capture_id).await?;

    let config = load_config_sync(&app);

    let dir = config
        .save_path
        .clone()
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
            PathBuf::from(home).join("Desktop")
        });

    if !dir.exists() {
        std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    }

    let (out, ext) = encode_for_output(&bytes, &config.format, config.jpeg_quality);
    let path = unique_save_path(&dir, &config.filename_template, ext);
    std::fs::write(&path, &out).map_err(|e| e.to_string())?;
    Ok(path.to_string_lossy().to_string())
}

#[tauri::command]
async fn open_main_for_edit(app: AppHandle) -> Result<(), String> {
    if let Some(win) = app.get_webview_window("main") {
        win.show().map_err(|e| e.to_string())?;
        win.set_focus().map_err(|e| e.to_string())?;
    }
    Ok(())
}

// Write the current capture to a temp file (with a clean name) for native drag-out, return its path.
#[tauri::command]
async fn stage_capture_for_drag(
    app: AppHandle,
    state: tauri::State<'_, CapturePopupInfo>,
    capture_id: u64,
) -> Result<String, String> {
    let bytes = wait_for_capture_bytes(&state, capture_id).await?;

    let config = load_config_sync(&app);
    let (out, ext) = encode_for_output(&bytes, &config.format, config.jpeg_quality);

    // Dedicated temp dir, cleared each drag so the dropped file keeps a clean name
    let drag_dir = std::env::temp_dir().join("potret_drag");
    let _ = std::fs::remove_dir_all(&drag_dir);
    std::fs::create_dir_all(&drag_dir).map_err(|e| e.to_string())?;

    let path = drag_dir.join(render_filename(&config.filename_template, ext, 0));
    std::fs::write(&path, &out).map_err(|e| e.to_string())?;
    Ok(path.to_string_lossy().to_string())
}

// Write a history item's full-res image to a temp file (clean name) for native drag-out.
#[tauri::command]
async fn stage_history_for_drag(app: AppHandle, id: String) -> Result<String, String> {
    // Same id guard as get_history_full / delete_history_item (prevents path traversal).
    if !id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-') {
        return Err("Invalid id".into());
    }
    let dir = history_dir(&app)?;
    let bytes = std::fs::read(dir.join(format!("{id}.png"))).map_err(|e| e.to_string())?;

    let config = load_config_sync(&app);
    let (out, ext) = encode_for_output(&bytes, &config.format, config.jpeg_quality);

    let drag_dir = std::env::temp_dir().join("potret_drag");
    let _ = std::fs::remove_dir_all(&drag_dir);
    std::fs::create_dir_all(&drag_dir).map_err(|e| e.to_string())?;

    let path = drag_dir.join(render_filename(&config.filename_template, ext, 0));
    std::fs::write(&path, &out).map_err(|e| e.to_string())?;
    Ok(path.to_string_lossy().to_string())
}

// ---------------------------------------------------------------------------
// Tray setup
// ---------------------------------------------------------------------------

// Show (or toggle) the menubar "Recent Captures" popup, anchored to the top-right
// of the monitor the user is currently on (so it lands on the active Space).
fn show_history_window(app: &AppHandle) {
    if app.get_webview_window("history").is_none() {
        precreate_overlay_windows(app);
    }
    let Some(win) = app.get_webview_window("history") else {
        return;
    };
    if win.is_visible().unwrap_or(false) {
        let _ = win.hide();
        return;
    }
    let (mon_x, mon_y, mon_w, _mon_h) = active_monitor_logical(app);
    let win_w = 380.0_f64;
    let _ = win.set_position(tauri::Position::Logical(tauri::LogicalPosition {
        x: mon_x + mon_w - win_w - 20.0,
        y: mon_y + 40.0,
    }));
    let _ = win.show();
    let _ = win.set_focus();
}

fn setup_tray(app: &AppHandle) -> tauri::Result<()> {
    let capture_area = MenuItem::with_id(app, "capture_area", "Capture Area", true, None::<&str>)?;
    let capture_window =
        MenuItem::with_id(app, "capture_window", "Capture Window", true, None::<&str>)?;
    let capture_fullscreen = MenuItem::with_id(
        app,
        "capture_fullscreen",
        "Capture Fullscreen",
        true,
        None::<&str>,
    )?;
    let separator = PredefinedMenuItem::separator(app)?;
    let recent =
        MenuItem::with_id(app, "recent_captures", "Recent Captures", true, None::<&str>)?;
    let show = MenuItem::with_id(app, "show", "Show Potret", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;

    let menu = Menu::with_items(
        app,
        &[
            &capture_area,
            &capture_window,
            &capture_fullscreen,
            &separator,
            &recent,
            &show,
            &quit,
        ],
    )?;

    let tray_builder = TrayIconBuilder::new()
        .menu(&menu)
        .icon(tauri::include_image!("icons/tray-icon.png"))
        .icon_as_template(true)
        .tooltip("Potret")
        .show_menu_on_left_click(false)
        .on_menu_event(|app, event| {
            let app = app.clone();
            match event.id().as_ref() {
                "capture_fullscreen" => {
                    let _ = app.emit(
                        "shortcut-triggered",
                        serde_json::json!({ "mode": "fullscreen" }),
                    );
                }
                "capture_area" => {
                    let _ = app.emit("shortcut-triggered", serde_json::json!({ "mode": "area" }));
                }
                "capture_window" => {
                    let _ = app.emit(
                        "shortcut-triggered",
                        serde_json::json!({ "mode": "window" }),
                    );
                }
                "recent_captures" => {
                    show_history_window(&app);
                }
                "show" => {
                    if let Some(win) = app.get_webview_window("main") {
                        let _ = win.show();
                        let _ = win.set_focus();
                    }
                }
                "quit" => {
                    app.exit(0);
                }
                _ => {}
            }
        })
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Up,
                ..
            } = event
            {
                let app = tray.app_handle();
                if let Some(win) = app.get_webview_window("main") {
                    if win.is_visible().unwrap_or(false) {
                        let _ = win.hide();
                    } else {
                        let _ = win.show();
                        let _ = win.set_focus();
                    }
                }
            }
        });

    tray_builder.build(app)?;
    Ok(())
}

// (global shortcut setup is now handled by register_shortcuts_from_config above)

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_clipboard_manager::init())
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            None,
        ))
        .plugin(tauri_plugin_drag::init())
        .setup(|app| {
            // System tray
            setup_tray(app.handle())?;

            // Load config and register global shortcuts from it
            let config = load_config_sync(app.handle());
            register_shortcuts_from_config(app.handle(), &config);

            // Intercept window close → hide instead of destroy.
            // This keeps the frontend alive so global shortcut events are
            // still received and the tray icon can re-show the window.
            if let Some(win) = app.get_webview_window("main") {
                let win_clone = win.clone();
                win.on_window_event(move |event| {
                    if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                        api.prevent_close();
                        let _ = win_clone.hide();
                    }
                });
            }

            // Hide from Dock on macOS — run as a menubar-only app
            #[cfg(target_os = "macos")]
            app.set_activation_policy(tauri::ActivationPolicy::Accessory);

            // Pre-create the transparent overlay windows (hidden) so captures are
            // instant and flash-free — see precreate_overlay_windows for the why.
            precreate_overlay_windows(app.handle());

            Ok(())
        })
        .manage(PinnedScreenshots {
            data: Mutex::new(HashMap::new()),
        })
        .manage(CapturePopupInfo {
            data: Mutex::new(CapturePopupState::default()),
        })
        .invoke_handler(tauri::generate_handler![
            capture_fullscreen,
            capture_area,
            capture_window,
            open_capture_selector,
            capture_region_and_crop,
            save_image,
            save_image_with_config,
            copy_to_clipboard,
            get_history,
            get_history_full,
            add_to_history,
            delete_history_item,
            clear_history,
            get_config,
            save_config,
            pick_folder,
            pin_screenshot,
            get_pinned_data,
            close_pinned,
            check_screen_recording_permission,
            request_screen_recording_permission,
            restart_app,
            open_system_settings_permissions,
            get_capture_popup_data,
            get_capture_full_data,
            close_capture_popup,
            quick_save_capture,
            stage_capture_for_drag,
            stage_history_for_drag,
            open_main_for_edit,
        ])
        .build(tauri::generate_context!())
        .expect("error while building potret")
        .run(|_app_handle, event| {
            // Menu-bar app: don't quit just because the last window was closed/destroyed
            // (e.g. closing a pinned screenshot). Tauri's default is to exit when the last
            // window goes away — block that. The only intended quit is the tray "Quit",
            // which calls app.exit(0): that arrives with code = Some(0) and is NOT blocked.
            if let tauri::RunEvent::ExitRequested { api, code, .. } = event {
                if code.is_none() {
                    api.prevent_exit();
                }
            }
        });
}
