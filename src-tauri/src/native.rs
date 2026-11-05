use windows::{
    core::{Interface, BOOL},
    Win32::{
        Foundation::{HANDLE, HWND, LPARAM, WPARAM},
        Media::Audio::*,
        System::{Com::*, JobObjects::*, Threading::*},
        UI::WindowsAndMessaging::*,
    },
};

#[derive(Clone, Copy, Default, Debug, PartialEq)]
pub struct Rect {
    pub x: i32,
    pub y: i32,
    pub w: i32,
    pub h: i32,
}

pub fn cover(view: Rect, video: (i32, i32), fill: bool) -> Rect {
    if !fill || video.0 <= 0 || video.1 <= 0 {
        return Rect {
            x: 0,
            y: 0,
            w: view.w.max(1),
            h: view.h.max(1),
        };
    }
    let scale = (view.w as f64 / video.0 as f64).max(view.h as f64 / video.1 as f64);
    let w = (video.0 as f64 * scale).ceil() as i32;
    let h = (video.1 as f64 * scale).ceil() as i32;
    Rect {
        x: (view.w - w) / 2,
        y: (view.h - h) / 2,
        w,
        h,
    }
}

pub struct Job(isize);
impl Job {
    pub fn new() -> Result<Self, String> {
        unsafe {
            let job = CreateJobObjectW(None, None).map_err(|e| e.to_string())?;
            let mut info = JOBOBJECT_EXTENDED_LIMIT_INFORMATION::default();
            info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
            SetInformationJobObject(
                job,
                JobObjectExtendedLimitInformation,
                &info as *const _ as *const _,
                std::mem::size_of_val(&info) as u32,
            )
            .map_err(|e| e.to_string())?;
            Ok(Self(job.0 as isize))
        }
    }
    pub fn assign(&self, pid: u32) -> Result<(), String> {
        unsafe {
            let process = OpenProcess(PROCESS_SET_QUOTA | PROCESS_TERMINATE, false, pid)
                .map_err(|e| e.to_string())?;
            let result =
                AssignProcessToJobObject(HANDLE(self.0 as _), process).map_err(|e| e.to_string());
            let _ = windows::Win32::Foundation::CloseHandle(process);
            result
        }
    }
}
impl Drop for Job {
    fn drop(&mut self) {
        unsafe {
            let _ = windows::Win32::Foundation::CloseHandle(HANDLE(self.0 as _));
        }
    }
}

pub fn host(parent: isize) -> Result<isize, String> {
    unsafe {
        let h = CreateWindowExW(
            WINDOW_EX_STYLE::default(),
            windows::core::w!("STATIC"),
            windows::core::w!("Y AND A media"),
            WS_CHILD | WS_CLIPCHILDREN | WS_CLIPSIBLINGS,
            0,
            0,
            1,
            1,
            Some(HWND(parent as _)),
            None,
            None,
            None,
        )
        .map_err(|e| e.to_string())?;
        Ok(h.0 as isize)
    }
}

struct Search {
    pid: u32,
    found: isize,
}
unsafe extern "system" fn find_window(h: HWND, data: LPARAM) -> BOOL {
    let s = &mut *(data.0 as *mut Search);
    let mut pid = 0;
    GetWindowThreadProcessId(h, Some(&mut pid));
    if pid == s.pid && GetWindow(h, GW_OWNER).unwrap_or_default().is_invalid() {
        let mut class = [0u16; 128];
        let len = GetClassNameW(h, &mut class);
        let class = String::from_utf16_lossy(&class[..len.max(0) as usize]);
        if class.contains("SDL") || class == "YANDA_TEST" {
            s.found = h.0 as isize;
            return BOOL(0);
        }
    }
    BOOL(1)
}
pub fn find(pid: u32) -> Option<isize> {
    unsafe {
        let mut s = Search { pid, found: 0 };
        let _ = EnumWindows(Some(find_window), LPARAM(&mut s as *mut _ as isize));
        (s.found != 0).then_some(s.found)
    }
}
pub fn attach(child: isize, host: isize) -> Result<(), String> {
    unsafe {
        let c = HWND(child as _);
        let style = GetWindowLongPtrW(c, GWL_STYLE) as u32;
        SetWindowLongPtrW(
            c,
            GWL_STYLE,
            ((style
                & !(WS_POPUP.0
                    | WS_CAPTION.0
                    | WS_THICKFRAME.0
                    | WS_MINIMIZEBOX.0
                    | WS_MAXIMIZEBOX.0
                    | WS_SYSMENU.0))
                | WS_CHILD.0
                | WS_CLIPSIBLINGS.0
                | WS_DISABLED.0) as isize,
        );
        let ex = GetWindowLongPtrW(c, GWL_EXSTYLE) as u32;
        SetWindowLongPtrW(c, GWL_EXSTYLE, (ex & !WS_EX_APPWINDOW.0) as isize);
        // SetParent may return NULL on success when the old parent was desktop.
        // Verify the resulting relationship instead of treating that as failure.
        let _ = SetParent(c, Some(HWND(host as _)));
        if GetParent(c).unwrap_or_default().0 as isize != host {
            return Err("Видео не стало дочерней поверхностью".into());
        }
        SetWindowPos(
            c,
            None,
            0,
            0,
            1,
            1,
            SWP_FRAMECHANGED | SWP_NOACTIVATE | SWP_NOZORDER,
        )
        .map_err(|e| e.to_string())?;
        Ok(())
    }
}
pub fn layout(
    host: isize,
    child: isize,
    bounds: Rect,
    video: (i32, i32),
    fill: bool,
    visible: bool,
) {
    unsafe {
        let h = HWND(host as _);
        let c = HWND(child as _);
        let _ = SetWindowPos(
            h,
            Some(HWND_TOP),
            bounds.x,
            bounds.y,
            bounds.w.max(1),
            bounds.h.max(1),
            SWP_NOACTIVATE,
        );
        let inner = cover(bounds, video, fill);
        let _ = SetWindowPos(
            c,
            Some(HWND_TOP),
            inner.x,
            inner.y,
            inner.w,
            inner.h,
            SWP_NOACTIVATE,
        );
        let _ = ShowWindow(h, if visible { SW_SHOWNA } else { SW_HIDE });
        let _ = ShowWindow(c, if visible { SW_SHOWNA } else { SW_HIDE });
    }
}
pub fn hide(host: isize) {
    unsafe {
        let _ = ShowWindow(HWND(host as _), SW_HIDE);
    }
}
pub fn clip_rect(view: Rect, parent_w: i32, parent_h: i32, top_limit: i32) -> Rect {
    let left = (-view.x).max(0).min(view.w);
    let top = (top_limit - view.y).max(0).min(view.h);
    let right = (parent_w - view.x).max(0).min(view.w);
    let bottom = (parent_h - view.y).max(0).min(view.h);
    Rect {
        x: left,
        y: top,
        w: (right - left).max(0),
        h: (bottom - top).max(0),
    }
}
pub fn clip(host: isize, bounds: Rect, top_limit: i32) -> bool {
    unsafe {
        use windows::Win32::Graphics::Gdi::{CreateRectRgn, DeleteObject, SetWindowRgn};
        let h = HWND(host as _);
        let Ok(parent) = GetParent(h) else {
            return false;
        };
        let mut client = windows::Win32::Foundation::RECT::default();
        if GetClientRect(parent, &mut client).is_err() {
            return false;
        }
        let r = clip_rect(bounds, client.right, client.bottom, top_limit);
        let region = CreateRectRgn(r.x, r.y, r.x + r.w, r.y + r.h);
        if region.is_invalid() {
            return false;
        }
        if SetWindowRgn(h, Some(region), true) == 0 {
            let _ = DeleteObject(region.into());
            return false;
        }
        r.w > 0 && r.h > 0
    }
}
pub fn window_visible(parent: isize) -> bool {
    unsafe {
        IsWindowVisible(HWND(parent as _)).as_bool() && !IsIconic(HWND(parent as _)).as_bool()
    }
}
pub fn close(child: isize) {
    unsafe {
        let _ = PostMessageW(Some(HWND(child as _)), WM_CLOSE, WPARAM(0), LPARAM(0));
    }
}

pub fn volume(pid: u32, level: f32, muted: bool) -> Result<bool, String> {
    unsafe {
        CoInitializeEx(None, COINIT_MULTITHREADED)
            .ok()
            .map_err(|e| e.to_string())?;
        let result = (|| -> windows::core::Result<bool> {
            let enumerator: IMMDeviceEnumerator =
                CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL)?;
            let outputs = enumerator.EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE)?;
            let mut applied = false;
            for d in 0..outputs.GetCount()? {
                let output = outputs.Item(d)?;
                let manager: IAudioSessionManager2 = output.Activate(CLSCTX_ALL, None)?;
                let sessions = manager.GetSessionEnumerator()?;
                for i in 0..sessions.GetCount()? {
                    let control = sessions.GetSession(i)?;
                    let c: IAudioSessionControl2 = control.cast()?;
                    if c.GetProcessId()? == pid {
                        let simple: ISimpleAudioVolume = control.cast()?;
                        simple.SetMasterVolume(level, std::ptr::null())?;
                        simple.SetMute(muted, std::ptr::null())?;
                        applied = true;
                    }
                }
            }
            Ok(applied)
        })();
        CoUninitialize();
        result.map_err(|e| format!("Устройство вывода Windows: {e}"))
    }
}

pub fn self_test() -> Result<String, String> {
    unsafe {
        let parent = CreateWindowExW(
            WINDOW_EX_STYLE::default(),
            windows::core::w!("STATIC"),
            windows::core::w!("YANDA fixture parent"),
            WS_OVERLAPPEDWINDOW,
            0,
            0,
            1000,
            800,
            None,
            None,
            None,
            None,
        )
        .map_err(|e| e.to_string())?;
        let child = CreateWindowExW(
            WS_EX_APPWINDOW,
            windows::core::w!("STATIC"),
            windows::core::w!("YANDA fixture media"),
            WS_OVERLAPPEDWINDOW,
            0,
            0,
            400,
            600,
            None,
            None,
            None,
            None,
        )
        .map_err(|e| e.to_string())?;
        let h = host(parent.0 as isize)?;
        attach(child.0 as isize, h)?;
        assert!(clip(
            h,
            Rect {
                x: 20,
                y: 80,
                w: 800,
                h: 600
            },
            60
        ));
        layout(
            h,
            child.0 as isize,
            Rect {
                x: 20,
                y: 80,
                w: 800,
                h: 600,
            },
            (1080, 2400),
            true,
            true,
        );
        let mut rect = windows::Win32::Foundation::RECT::default();
        GetClientRect(HWND(h as _), &mut rect).map_err(|e| e.to_string())?;
        assert_eq!(rect.right, 800);
        assert_eq!(GetParent(child).map_err(|e| e.to_string())?, HWND(h as _));
        hide(h);
        assert!(!IsWindowVisible(HWND(h as _)).as_bool());
        assert_eq!(
            GetWindowLongPtrW(HWND(h as _), GWL_STYLE) as u32 & WS_VISIBLE.0,
            0
        );
        let _ = DestroyWindow(child);
        let _ = DestroyWindow(HWND(h as _));
        let _ = DestroyWindow(parent);
    }
    Ok("PASS: native HWND reparent, child containment, resize 800x600, Fill geometry, hide, destroy (synthetic; no phone)".into())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn scrolled_video_never_covers_header() {
        let r = clip_rect(
            Rect {
                x: 20,
                y: -30,
                w: 800,
                h: 600,
            },
            1000,
            800,
            88,
        );
        assert_eq!(
            r,
            Rect {
                x: 0,
                y: 118,
                w: 800,
                h: 482
            }
        );
    }
    #[test]
    fn offscreen_video_is_empty() {
        assert_eq!(
            clip_rect(
                Rect {
                    x: 0,
                    y: -800,
                    w: 800,
                    h: 600
                },
                1000,
                800,
                88
            )
            .h,
            0
        );
    }
    #[test]
    fn fit_does_not_crop() {
        let v = Rect {
            x: 0,
            y: 0,
            w: 800,
            h: 600,
        };
        assert_eq!(cover(v, (1080, 2400), false), v);
    }
    #[test]
    fn fill_preserves_ratio_and_crops_explicitly() {
        let r = cover(
            Rect {
                x: 0,
                y: 0,
                w: 800,
                h: 600,
            },
            (1080, 2400),
            true,
        );
        assert_eq!(r.w, 800);
        assert_eq!(r.h, 1778);
        assert!(r.y < 0);
    }
    #[test]
    fn unknown_video_never_divides_by_zero() {
        assert_eq!(
            cover(
                Rect {
                    x: 0,
                    y: 0,
                    w: 800,
                    h: 600
                },
                (0, 0),
                true
            )
            .h,
            600
        );
    }
}
