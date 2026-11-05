use serde::Deserialize;
use std::sync::Mutex;
use tauri::{LogicalSize, PhysicalPosition, PhysicalSize, WebviewWindow};

#[derive(Default)]
pub struct Presentation {
    saved: Option<Saved>,
    last: Option<(u32, u32)>,
    compact: bool,
}
struct Saved {
    size: PhysicalSize<u32>,
    position: PhysicalPosition<i32>,
    maximized: bool,
    fullscreen: bool,
}
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Request {
    active: bool,
    compact: bool,
    width: u32,
    height: u32,
}
pub type SharedPresentation = Mutex<Presentation>;

impl Presentation {
    pub fn apply(&mut self, w: &WebviewWindow, r: Request) -> tauri::Result<bool> {
        if !r.active || !r.compact {
            if self.compact || (!r.active && self.saved.is_some()) {
                self.restore(w)?;
                self.compact = false;
                self.last = None;
            }
            if !r.active {
                self.saved = None;
            }
            return w.is_fullscreen();
        }
        if !(1..=16384).contains(&r.width) || !(1..=16384).contains(&r.height) {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                "Некорректное разрешение телефона",
            )
            .into());
        }
        if self.saved.is_none() {
            // Capture the normal restore rectangle, not the maximized client area.
            let fullscreen = w.is_fullscreen()?;
            if fullscreen {
                w.set_fullscreen(false)?;
            }
            let maximized = w.is_maximized()?;
            if maximized {
                w.unmaximize()?;
            }
            self.saved = Some(Saved {
                size: w.inner_size()?,
                position: w.outer_position()?,
                maximized,
                fullscreen,
            });
        }
        // The owner's fullscreen command temporarily takes precedence.
        if self.compact && w.is_fullscreen()? {
            return Ok(true);
        }
        if self.compact && self.last == Some((r.width, r.height)) {
            return w.is_fullscreen();
        }
        let monitor = w.current_monitor()?.or(w.primary_monitor()?);
        if let Some(m) = monitor {
            let scale = m.scale_factor();
            let area = m.work_area();
            let (width, height) = phone_size(
                r.width,
                r.height,
                area.size.width as f64 / scale,
                area.size.height as f64 / scale,
            );
            let size = PhysicalSize::new(
                (width * scale).round() as u32,
                (height * scale).round() as u32,
            );
            let old_size = w.inner_size()?;
            let old_pos = w.outer_position()?;
            w.set_fullscreen(false)?;
            w.unmaximize()?;
            w.set_min_size(Some(LogicalSize::new(320., 320.)))?;
            w.set_size(size)?;
            let x = centered(
                old_pos.x,
                old_size.width,
                size.width,
                area.position.x,
                area.size.width,
            );
            let y = centered(
                old_pos.y,
                old_size.height,
                size.height,
                area.position.y,
                area.size.height,
            );
            w.set_position(PhysicalPosition::new(x, y))?;
            self.compact = true;
            self.last = Some((r.width, r.height));
        }
        w.is_fullscreen()
    }
    fn restore(&self, w: &WebviewWindow) -> tauri::Result<()> {
        if let Some(s) = &self.saved {
            w.set_fullscreen(false)?;
            w.unmaximize()?;
            w.set_min_size(Some(LogicalSize::new(900., 650.)))?;
            w.set_size(s.size)?;
            w.set_position(s.position)?;
            if s.maximized {
                w.maximize()?;
            }
            if s.fullscreen {
                w.set_fullscreen(true)?;
            }
        }
        Ok(())
    }
}
fn phone_size(w: u32, h: u32, work_w: f64, work_h: f64) -> (f64, f64) {
    let chrome = 186.; // titlebar 60 + stream heading 36 + controls 48 + session bar 42
    let max_w = (work_w - 32.).max(320.);
    let max_h = (work_h - 32.).max(320.);
    let ratio = w as f64 / h as f64;
    let video_h = 760_f64.min(max_h - chrome).min(1100_f64.min(max_w) / ratio);
    (
        (video_h * ratio).max(340.).min(max_w),
        (video_h + chrome).min(max_h),
    )
}
fn centered(pos: i32, old: u32, new: u32, origin: i32, extent: u32) -> i32 {
    (pos + (old as i32 - new as i32) / 2).clamp(origin, origin + extent.saturating_sub(new) as i32)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn portrait_and_landscape_fit_work_area() {
        let (w, h) = phone_size(1178, 2560, 1536., 864.);
        assert!(w >= 340. && h <= 832.);
        assert!((w / (h - 186.) - 1178. / 2560.).abs() < 0.08);
        let (w, h) = phone_size(2560, 1178, 1536., 864.);
        assert!((w / (h - 186.) - 2560. / 1178.).abs() < 0.001);
        assert!(w <= 1100. && h <= 832.);
    }
    #[test]
    fn negative_monitor_coordinates_and_hidpi() {
        assert_eq!(centered(-1800, 1440, 360, -1920, 1920), -1260);
        assert_eq!(centered(-10, 1440, 360, -1920, 1920), -360);
        let (w, h) = phone_size(1080, 2400, 1920. / 1.5, 1080. / 1.5);
        assert!(w <= 1280. && h <= 688.);
    }
}
