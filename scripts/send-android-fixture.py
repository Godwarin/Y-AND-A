"""Synthetic TLS sender controlled by native smoke. Offer arrives via stdin, never argv."""
import pathlib,sys,ssl,socket,hashlib,struct,urllib.parse,threading,queue,time
import ctypes
from ctypes import wintypes
root=pathlib.Path(__file__).resolve().parent.parent
uri=sys.stdin.readline().strip();q=urllib.parse.parse_qs(urllib.parse.urlparse(uri).query)
ctx=ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT);ctx.minimum_version=ssl.TLSVersion.TLSv1_3;ctx.check_hostname=False;ctx.verify_mode=ssl.CERT_NONE
s=ctx.wrap_socket(socket.create_connection((q['host'][0],int(q['port'][0])),timeout=8),server_hostname='local-test');s.settimeout(8)
assert hashlib.sha256(s.getpeercert(binary_form=True)).hexdigest()==q['fp'][0], 'Certificate mismatch'
mouse = len(sys.argv) == 3
s.sendall((b'YANDA04\n' if mouse else b'YANDA03\n')+q['token'][0].encode())
def exact(n):
 b=b''
 while len(b)<n:
  part=s.recv(n-len(b))
  if not part:raise EOFError('Receiver closed')
  b+=part
 return b
ack=exact(17);assert ack[:8]==b'YANDAOK\n'
def send(t,b=b''):s.sendall(struct.pack('>BIQ',t,len(b),time.monotonic_ns()//1000)+b)

def mouse_fixture(action):
    """Post input only to the SDL child of the two processes owned by this test."""
    user32 = ctypes.WinDLL("user32", use_last_error=True)
    callback = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    user32.EnumWindows.argtypes = [callback, wintypes.LPARAM]
    user32.EnumChildWindows.argtypes = [wintypes.HWND, callback, wintypes.LPARAM]
    user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
    user32.GetClassNameW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
    user32.GetClientRect.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.RECT)]
    user32.IsWindowEnabled.argtypes = [wintypes.HWND]
    user32.PostMessageW.argtypes = [wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM]
    app_pid, receiver_pid = map(int, sys.argv[1:3])
    targets = []

    @callback
    def child(hwnd, _):
        pid = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        name = ctypes.create_unicode_buffer(128)
        if pid.value == receiver_pid and user32.GetClassNameW(hwnd, name, len(name)) and name.value == "SDL_app":
            targets.append(hwnd)
        return True

    @callback
    def top(hwnd, _):
        pid = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        if pid.value == app_pid:
            user32.EnumChildWindows(hwnd, child, 0)
        return True

    user32.EnumWindows(top, 0)
    assert len(targets) == 1, "SDL child missing"
    target = targets[0]
    if action == "check-disabled":
        assert not user32.IsWindowEnabled(target), "View-only session accepts input"
        print("SYNTHETIC_MOUSE_DISABLED", flush=True)
        return
    assert user32.IsWindowEnabled(target), "Mouse-capable SDL child is disabled"
    if action == "escape":
        assert user32.PostMessageW(target, 0x100, 27, 1)
        assert user32.PostMessageW(target, 0x101, 27, 0xC0000001)
        return
    rect = wintypes.RECT()
    assert user32.GetClientRect(target, ctypes.byref(rect))
    x, y = rect.right // 2, rect.bottom // 2
    end_y = y if action == "click" else y + rect.bottom // 10
    assert user32.PostMessageW(target, 0x200, 0, y << 16 | x)
    assert user32.PostMessageW(target, 0x201, 1, y << 16 | x)
    time.sleep(0.08)
    assert user32.PostMessageW(target, 0x200, 1, end_y << 16 | x)
    assert user32.PostMessageW(target, 0x202, 0, end_y << 16 | x)

commands=queue.Queue()
def input_loop():
 for line in sys.stdin:commands.put(line.strip())
 commands.put('stop')
threading.Thread(target=input_loop,daemon=True).start()
frame=(root/'tests/fixtures/android-portrait.h264').read_bytes()
send(1,frame)
if ack[8]:send(2,b'\0'*19200)
print('SYNTHETIC_SENDER_READY',flush=True)
pending = None
try:
 while True:
  try:command=commands.get(timeout=.3)
  except queue.Empty:command=''
  if command=='stop':send(3);break
  if command=='rotate':frame=(root/'tests/fixtures/android-landscape.h264').read_bytes()
  if command in ('click', 'swipe', 'escape', 'check-disabled'):
   mouse_fixture(command)
   if command in ('click', 'swipe'):pending=command
  send(1,frame);send(5)
  response=exact(1)
  while mouse and response==b'\2':
   w,h,x,y,end_x,end_y,duration=struct.unpack('>7H',exact(14))
   assert (w,h)==(320,640) and abs(x-160)<=4 and abs(y-320)<=4
   assert abs(end_x-x)<=2 and 40<=duration<=3000
   assert (pending=='click' and abs(end_y-y)<=2) or (pending=='swipe' and end_y>y+15), (pending,y,end_y)
   print('SYNTHETIC_MOUSE_'+pending.upper(),flush=True)
   pending=None
   response=exact(1)
  assert response==b'\1'
finally:s.close()
