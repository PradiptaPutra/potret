use base64::{engine::general_purpose, Engine as _};
use image::imageops::FilterType;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::process::Command;
use std::sync::Mutex;
use tauri::{
    image::Image,
    menu::{Menu, MenuItem, PredefinedMenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Emitter, Manager,
};
use uuid::Uuid;

// ---------------------------------------------------------------------------
// Shared state structs
// ---------------------------------------------------------------------------

pub struct AnnotationData {
    pub data: Mutex<String>,
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
    let base = app
        .path()
        .app_data_dir()
        .map_err(|e| e.to_string())?;
    let dir = base.join("history");
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    Ok(dir)
}

fn make_thumbnail(bytes: &[u8]) -> Result<String, String> {
    let img = image::load_from_memory(bytes).map_err(|e| e.to_string())?;
    let thumb = img.resize(200, u32::MAX, FilterType::Lanczos3);
    let mut buf: Vec<u8> = Vec::new();
    thumb
        .write_to(
            &mut std::io::Cursor::new(&mut buf),
            image::ImageFormat::Png,
        )
        .map_err(|e| e.to_string())?;
    Ok(general_purpose::STANDARD.encode(&buf))
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
    let thumbnail = make_thumbnail(bytes)?;

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
    capture_with_args(&app, &["-x"])
}

#[tauri::command]
async fn capture_area(app: AppHandle) -> CaptureResult {
    capture_with_args(&app, &["-x", "-s"])
}

#[tauri::command]
async fn capture_window(app: AppHandle) -> CaptureResult {
    capture_with_args(&app, &["-x", "-w"])
}

fn capture_with_args(app: &AppHandle, extra_args: &[&str]) -> CaptureResult {
    let tmp = std::env::temp_dir().join("potret_capture.png");
    let tmp_str = tmp.to_string_lossy().to_string();

    let mut args: Vec<&str> = extra_args.to_vec();
    args.push(tmp_str.as_str());

    let status = Command::new("screencapture").args(&args).status();

    match status {
        Ok(s) if s.success() => {
            if !tmp.exists() {
                return CaptureResult {
                    success: false,
                    screenshot: None,
                    error: Some("Capture cancelled".into()),
                };
            }
            match std::fs::read(&tmp) {
                Ok(bytes) => {
                    let _ = std::fs::remove_file(&tmp);

                    // Save to history (best-effort; don't fail the capture if it fails)
                    let _ = save_to_history(app, &bytes);

                    let data = general_purpose::STANDARD.encode(&bytes);
                    let (w, h) = image_dimensions(&bytes).unwrap_or((0, 0));
                    CaptureResult {
                        success: true,
                        screenshot: Some(Screenshot {
                            data,
                            width: w,
                            height: h,
                        }),
                        error: None,
                    }
                }
                Err(e) => CaptureResult {
                    success: false,
                    screenshot: None,
                    error: Some(e.to_string()),
                },
            }
        }
        Ok(_) => {
            // Non-zero exit — if the file was still written (e.g. partial), use it.
            // If there's no file, the user cancelled (Escape); treat silently.
            if tmp.exists() {
                if let Ok(bytes) = std::fs::read(&tmp) {
                    let _ = std::fs::remove_file(&tmp);
                    let _ = save_to_history(app, &bytes);
                    let data = general_purpose::STANDARD.encode(&bytes);
                    let (w, h) = image_dimensions(&bytes).unwrap_or((0, 0));
                    return CaptureResult {
                        success: true,
                        screenshot: Some(Screenshot { data, width: w, height: h }),
                        error: None,
                    };
                }
            }
            CaptureResult {
                success: false,
                screenshot: None,
                error: None, // silent — user pressed Escape
            }
        },
        Err(e) => CaptureResult {
            success: false,
            screenshot: None,
            error: Some(e.to_string()),
        },
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

// ---------------------------------------------------------------------------
// History commands
// ---------------------------------------------------------------------------

#[tauri::command]
async fn get_history(app: AppHandle) -> Result<Vec<HistoryItem>, String> {
    let dir = history_dir(&app)?;

    let mut items: Vec<HistoryItem> = Vec::new();

    let entries = std::fs::read_dir(&dir).map_err(|e| e.to_string())?;
    for entry in entries.flatten() {
        let path = entry.path();
        if path.extension().and_then(|e| e.to_str()) != Some("json") {
            continue;
        }

        let meta_str = match std::fs::read_to_string(&path) {
            Ok(s) => s,
            Err(_) => continue,
        };
        let meta: HistoryMeta = match serde_json::from_str(&meta_str) {
            Ok(m) => m,
            Err(_) => continue,
        };

        let png_path = dir.join(format!("{}.png", meta.id));
        if !png_path.exists() {
            continue;
        }

        // Build thumbnail from saved PNG
        let thumbnail = std::fs::read(&png_path)
            .ok()
            .and_then(|b| make_thumbnail(&b).ok())
            .unwrap_or_default();

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

    // Sort newest first and limit to 50
    items.sort_by(|a, b| b.timestamp.cmp(&a.timestamp));
    items.truncate(50);

    Ok(items)
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

    if png_path.exists() {
        std::fs::remove_file(&png_path).map_err(|e| e.to_string())?;
    }
    if meta_path.exists() {
        std::fs::remove_file(&meta_path).map_err(|e| e.to_string())?;
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
// Save / clipboard / annotation commands
// ---------------------------------------------------------------------------

#[tauri::command]
async fn save_image(data: String, path: String) -> Result<(), String> {
    let bytes = general_purpose::STANDARD
        .decode(&data)
        .map_err(|e| e.to_string())?;
    std::fs::write(&path, &bytes).map_err(|e| e.to_string())
}

#[tauri::command]
async fn copy_to_clipboard(data: String) -> Result<(), String> {
    let bytes = general_purpose::STANDARD
        .decode(&data)
        .map_err(|e| e.to_string())?;

    let tmp = std::env::temp_dir().join("potret_clipboard.png");
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

#[tauri::command]
async fn open_annotation_window(app: AppHandle, data: String) -> Result<(), String> {
    app.manage(AnnotationData {
        data: Mutex::new(data),
    });

    if let Some(win) = app.get_webview_window("annotation") {
        win.show().map_err(|e| e.to_string())?;
        win.set_focus().map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
async fn get_annotation_data(
    state: tauri::State<'_, AnnotationData>,
) -> Result<String, String> {
    let data = state.data.lock().map_err(|e| e.to_string())?;
    Ok(data.clone())
}

// ---------------------------------------------------------------------------
// Tray setup
// ---------------------------------------------------------------------------

fn setup_tray(app: &AppHandle) -> tauri::Result<()> {
    let capture_area = MenuItem::with_id(app, "capture_area", "Capture Area", true, None::<&str>)?;
    let capture_window = MenuItem::with_id(app, "capture_window", "Capture Window", true, None::<&str>)?;
    let capture_fullscreen = MenuItem::with_id(app, "capture_fullscreen", "Capture Fullscreen", true, None::<&str>)?;
    let separator = PredefinedMenuItem::separator(app)?;
    let show = MenuItem::with_id(app, "show", "Show Potret", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;

    let menu = Menu::with_items(
        app,
        &[
            &capture_area,
            &capture_window,
            &capture_fullscreen,
            &separator,
            &show,
            &quit,
        ],
    )?;

    let icon = Image::from_path(
        app.path()
            .resource_dir()
            .unwrap_or_default()
            .join("icons/icon.png"),
    )
    .or_else(|_| {
        // Fallback: try loading from the bundle icons directory
        let fallback = app
            .path()
            .resource_dir()
            .unwrap_or_default()
            .join("icons/32x32.png");
        Image::from_path(fallback)
    });

    let mut tray_builder = TrayIconBuilder::new()
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_menu_event(|app, event| {
            let app = app.clone();
            match event.id().as_ref() {
                "capture_fullscreen" => {
                    let _ = app.emit("tray-capture-fullscreen", ());
                }
                "capture_area" => {
                    let _ = app.emit("tray-capture-area", ());
                }
                "capture_window" => {
                    let _ = app.emit("tray-capture-window", ());
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
                    let _ = win.show();
                    let _ = win.set_focus();
                }
            }
        });

    if let Ok(img) = icon {
        tray_builder = tray_builder.icon(img);
    }

    tray_builder.build(app)?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Global shortcut setup
// ---------------------------------------------------------------------------

fn setup_global_shortcuts(app: &AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    use tauri_plugin_global_shortcut::{Code, GlobalShortcutExt, Modifiers, Shortcut, ShortcutState};

    // Cmd+Shift+3 → fullscreen
    let shortcut_fullscreen = Shortcut::new(Some(Modifiers::META | Modifiers::SHIFT), Code::Digit3);
    // Cmd+Shift+4 → area
    let shortcut_area = Shortcut::new(Some(Modifiers::META | Modifiers::SHIFT), Code::Digit4);
    // Cmd+Shift+5 → window
    let shortcut_window = Shortcut::new(Some(Modifiers::META | Modifiers::SHIFT), Code::Digit5);

    app.global_shortcut().on_shortcuts(
        [shortcut_fullscreen, shortcut_area, shortcut_window],
        {
            let app = app.clone();
            move |_app, shortcut, event| {
                if event.state != ShortcutState::Pressed {
                    return;
                }
                if shortcut.key == Code::Digit3 {
                    let _ = app.emit("global-shortcut-fullscreen", ());
                } else if shortcut.key == Code::Digit4 {
                    let _ = app.emit("global-shortcut-area", ());
                } else if shortcut.key == Code::Digit5 {
                    let _ = app.emit("global-shortcut-window", ());
                }
            }
        },
    )?;

    Ok(())
}

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
        .setup(|app| {
            // System tray
            setup_tray(app.handle())?;

            // Global shortcuts
            if let Err(e) = setup_global_shortcuts(app.handle()) {
                eprintln!("[potret] Failed to register global shortcuts: {e}");
            }

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            capture_fullscreen,
            capture_area,
            capture_window,
            save_image,
            copy_to_clipboard,
            open_annotation_window,
            get_annotation_data,
            get_history,
            delete_history_item,
            clear_history,
        ])
        .run(tauri::generate_context!())
        .expect("error while running potret");
}
