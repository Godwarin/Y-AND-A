"""Synthetic TLS sender controlled by native smoke. Offer arrives via stdin, never argv."""
import pathlib,sys,ssl,socket,hashlib,struct,urllib.parse,threading,queue,time
root=pathlib.Path(__file__).resolve().parent.parent
uri=sys.stdin.readline().strip();q=urllib.parse.parse_qs(urllib.parse.urlparse(uri).query)
ctx=ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT);ctx.minimum_version=ssl.TLSVersion.TLSv1_3;ctx.check_hostname=False;ctx.verify_mode=ssl.CERT_NONE
s=ctx.wrap_socket(socket.create_connection((q['host'][0],int(q['port'][0])),timeout=8),server_hostname='local-test');s.settimeout(8)
assert hashlib.sha256(s.getpeercert(binary_form=True)).hexdigest()==q['fp'][0], 'Certificate mismatch'
s.sendall(b'YANDA03\n'+q['token'][0].encode())
def exact(n):
 b=b''
 while len(b)<n:
  part=s.recv(n-len(b))
  if not part:raise EOFError('Receiver closed')
  b+=part
 return b
ack=exact(17);assert ack[:8]==b'YANDAOK\n'
def send(t,b=b''):s.sendall(struct.pack('>BIQ',t,len(b),time.monotonic_ns()//1000)+b)
commands=queue.Queue()
def input_loop():
 for line in sys.stdin:commands.put(line.strip())
 commands.put('stop')
threading.Thread(target=input_loop,daemon=True).start()
frame=(root/'tests/fixtures/android-portrait.h264').read_bytes()
send(1,frame)
if ack[8]:send(2,b'\0'*19200)
print('SYNTHETIC_SENDER_READY',flush=True)
try:
 while True:
  try:command=commands.get(timeout=.3)
  except queue.Empty:command=''
  if command=='stop':send(3);break
  if command=='rotate':frame=(root/'tests/fixtures/android-landscape.h264').read_bytes()
  send(1,frame);send(5);assert exact(1)==b'\1'
finally:s.close()
