#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod engine;
mod native;
mod presentation;

use engine::{Backend, CompanionOffer, ConnectRequest, Snapshot};
use serde::Deserialize;
use std::sync::{Arc, Mutex};
use tauri::{Manager, State};

type Shared = Arc<Mutex<Backend>>;
#[tauri::command]
async fn approve_airplay(
    request_id: String,
    allow: bool,
    backend: State<'_, Shared>,
) -> Result<(), String> {
    backend
        .lock()
        .map_err(|_| "Блокировка backend".to_string())?
        .approve_airplay(request_id, allow)
}

#[tauri::command]
async fn presentation_set(
    window: tauri::WebviewWindow,
    request: presentation::Request,
    state: State<'_, presentation::SharedPresentation>,
) -> Result<bool, String> {
    // This mutex is separate from media/ADB; slow pairing never blocks window resizing.
    state
        .lock()
        .map_err(|_| "Блокировка окна".to_string())?
        .apply(&window, request)
        .map_err(|e| e.to_string())
}

#[tauri::command]
async fn companion_offer(backend: State<'_, Shared>) -> Result<CompanionOffer, String> {
    backend
        .lock()
        .map_err(|_| "Блокировка backend".to_string())?
        .companion_offer()
}
#[tauri::command]
async fn open_android_apk(backend: State<'_, Shared>) -> Result<(), String> {
    backend
        .lock()
        .map_err(|_| "Блокировка backend".to_string())?
        .open_android_apk()
}

#[tauri::command]
async fn connect(request: ConnectRequest, backend: State<'_, Shared>) -> Result<Snapshot, String> {
    let b = backend.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        b.lock()
            .map_err(|_| "Блокировка backend".to_string())?
            .start(request)
    })
    .await
    .map_err(|e| e.to_string())?
}

#[tauri::command]
async fn disconnect(backend: State<'_, Shared>) -> Result<Snapshot, String> {
    let b = backend.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        let mut b = b.lock().map_err(|_| "Блокировка backend".to_string())?;
        b.stop();
        Ok(b.snapshot())
    })
    .await
    .map_err(|e| e.to_string())?
}

#[tauri::command]
async fn status(backend: State<'_, Shared>) -> Result<Snapshot, String> {
    let b = backend.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        Ok(b.lock()
            .map_err(|_| "Блокировка backend".to_string())?
            .snapshot())
    })
    .await
    .map_err(|e| e.to_string())?
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Bounds {
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    scale: f64,
    fill: bool,
    #[serde(default)]
    top_limit: i32,
}

#[tauri::command]
async fn viewer_bounds(bounds: Bounds, backend: State<'_, Shared>) -> Result<(), String> {
    if !bounds.scale.is_finite() || !(0.5..=8.0).contains(&bounds.scale) {
        return Err("Некорректный DPI".into());
    }
    let shared = backend.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        let mut b = shared
            .lock()
            .map_err(|_| "Блокировка backend".to_string())?;
        b.bounds = native::Rect {
            x: (bounds.x as f64 * bounds.scale) as i32,
            y: (bounds.y as f64 * bounds.scale) as i32,
            w: (bounds.width.clamp(1, 16000) as f64 * bounds.scale) as i32,
            h: (bounds.height.clamp(1, 16000) as f64 * bounds.scale) as i32,
        };
        b.fill = bounds.fill;
        b.top_limit = (bounds.top_limit.max(0) as f64 * bounds.scale) as i32;
        b.layout();
        Ok(())
    })
    .await
    .map_err(|e| e.to_string())?
}

#[tauri::command]
async fn set_volume(volume: f32, muted: bool, backend: State<'_, Shared>) -> Result<bool, String> {
    if !volume.is_finite() {
        return Err("Некорректная громкость".into());
    }
    let b = backend.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        b.lock()
            .map_err(|_| "Блокировка backend".to_string())?
            .volume(volume.clamp(0., 1.), muted)
    })
    .await
    .map_err(|e| e.to_string())?
}

fn main() {
    if std::env::args().any(|s| s == "--bridge-self-test") {
        match native::self_test() {
            Ok(report) => {
                println!("{report}");
                std::process::exit(0);
            }
            Err(e) => {
                eprintln!("{e}");
                std::process::exit(1);
            }
        }
    }
    tauri::Builder::default()
        .setup(|app| {
            let window = app.get_webview_window("main").ok_or("Нет главного окна")?;
            let hwnd = window.hwnd()?.0 as isize;
            let root = if cfg!(debug_assertions) {
                std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
                    .parent()
                    .unwrap()
                    .to_path_buf()
            } else {
                std::env::current_exe()?.parent().unwrap().to_path_buf()
            };
            let data = app.path().app_local_data_dir()?;
            std::fs::create_dir_all(&data)?;
            let state = Arc::new(Mutex::new(Backend::new(root, data, hwnd)?));
            app.manage(state.clone());
            app.manage(presentation::SharedPresentation::default());
            std::thread::spawn(move || loop {
                std::thread::sleep(std::time::Duration::from_millis(150));
                let Ok(mut b) = state.lock() else {
                    break;
                };
                if b.closed {
                    break;
                }
                b.poll();
            });
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            connect,
            disconnect,
            status,
            viewer_bounds,
            presentation_set,
            companion_offer,
            open_android_apk,
            set_volume,
            approve_airplay
        ])
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                api.prevent_close();
                let target = window.clone();
                let state = window.state::<Shared>().inner().clone();
                std::thread::spawn(move || {
                    if let Ok(mut b) = state.lock() {
                        b.shutdown();
                    }
                    let _ = target.destroy();
                });
            }
        })
        .run(tauri::generate_context!())
        .expect("Ошибка запуска Y AND A");
}
