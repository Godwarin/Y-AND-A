"""Send one Escape to the foreground window of an owned smoke-test process."""
import ctypes
import sys
import time
from ctypes import wintypes

user32 = ctypes.WinDLL("user32", use_last_error=True)
user32.GetForegroundWindow.restype = wintypes.HWND
user32.GetAncestor.argtypes = [wintypes.HWND, wintypes.UINT]
user32.GetAncestor.restype = wintypes.HWND
user32.GetWindowThreadProcessId.argtypes = [
    wintypes.HWND, ctypes.POINTER(wintypes.DWORD)
]
user32.SetForegroundWindow.argtypes = [wintypes.HWND]
user32.IsWindowVisible.argtypes = [wintypes.HWND]
user32.keybd_event.argtypes = [
    wintypes.BYTE, wintypes.BYTE, wintypes.DWORD, wintypes.WPARAM
]

def process_id(hwnd):
    pid = wintypes.DWORD()
    user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
    return pid.value

def foreground_is_owned():
    root = user32.GetAncestor(user32.GetForegroundWindow(), 2)
    return process_id(root) == app_pid

app_pid = int(sys.argv[1])
if not foreground_is_owned():
    enum_proc = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    user32.EnumWindows.argtypes = [enum_proc, wintypes.LPARAM]

    @enum_proc
    def activate_owned_window(hwnd, _):
        if process_id(hwnd) != app_pid or not user32.IsWindowVisible(hwnd):
            return True
        user32.SetForegroundWindow(hwnd)
        return False

    user32.EnumWindows(activate_owned_window, 0)
    time.sleep(0.18)

if len(sys.argv) == 3 and sys.argv[2] == "--wait-for-focus":
    deadline = time.monotonic() + 40
    while not foreground_is_owned() and time.monotonic() < deadline:
        time.sleep(0.1)

if not foreground_is_owned():
    sys.exit("Escape smoke requires the test window in the foreground")

escape = 0x1B
user32.keybd_event(escape, 0, 0, 0)
try:
    time.sleep(0.12)
finally:
    user32.keybd_event(escape, 0, 2, 0)
