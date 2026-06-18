use base64::{engine::general_purpose, Engine as _};
use serde::{Deserialize, Serialize};
use std::process::Command;
use tauri::{AppHandle, Manager};

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

/// Capture the full screen using macOS screencapture
#[tauri::command]
async fn capture_fullscreen() -> CaptureResult {
    capture_with_args(&["-x"])
}

/// Capture a selected area (interactive crosshair)
#[tauri::command]
async fn capture_area() -> CaptureResult {
    capture_with_args(&["-x", "-s"])
}

/// Capture the active window
#[tauri::command]
async fn capture_window() -> CaptureResult {
    capture_with_args(&["-x", "-w"])
}

fn capture_with_args(extra_args: &[&str]) -> CaptureResult {
    let tmp = std::env::temp_dir().join("potret_capture.png");
    let tmp_str = tmp.to_string_lossy();

    let mut args: Vec<&str> = extra_args.to_vec();
    args.push(tmp_str.as_ref());

    // screencapture is macOS built-in
    let status = Command::new("screencapture").args(&args).status();

    match status {
        Ok(s) if s.success() => {
            // file might not exist if user cancelled (area/window mode)
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
                    let data = general_purpose::STANDARD.encode(&bytes);
                    // get dimensions
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
        Ok(_) => CaptureResult {
            success: false,
            screenshot: None,
            error: Some("screencapture exited with non-zero status".into()),
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

/// Save annotated image (base64 PNG) to a path chosen by the user
#[tauri::command]
async fn save_image(data: String, path: String) -> Result<(), String> {
    let bytes = general_purpose::STANDARD
        .decode(&data)
        .map_err(|e| e.to_string())?;
    std::fs::write(&path, &bytes).map_err(|e| e.to_string())
}

/// Copy image bytes to clipboard using macOS pbcopy / osascript
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

/// Open annotation window with the given screenshot data
#[tauri::command]
async fn open_annotation_window(app: AppHandle, data: String) -> Result<(), String> {
    // Store data in app state so annotation window can fetch it
    app.manage(AnnotationData {
        data: std::sync::Mutex::new(data),
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

pub struct AnnotationData {
    pub data: std::sync::Mutex<String>,
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_clipboard_manager::init())
        .invoke_handler(tauri::generate_handler![
            capture_fullscreen,
            capture_area,
            capture_window,
            save_image,
            copy_to_clipboard,
            open_annotation_window,
            get_annotation_data,
        ])
        .run(tauri::generate_context!())
        .expect("error while running potret");
}
