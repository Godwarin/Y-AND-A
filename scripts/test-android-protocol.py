"""Real TLS/FFmpeg/SDL receiver tests with synthetic media, never a phone test."""
import hashlib, pathlib, queue, re, socket, ssl, struct, subprocess, threading, time, json
ROOT=pathlib.Path(__file__).resolve().parent.parent
EXE=ROOT/'runtime/android-yanda/yanda-android.exe'
checks=[]
def passed(name): checks.append(name); print('PASS',name,flush=True)
class Receiver:
    def __init__(self,*args):
        self.token='ab'*32  # public synthetic fixture, not a pairing credential from UI
        self.q=queue.Queue();self.lines=[]
        self.p=subprocess.Popen([str(EXE),*args],cwd=EXE.parent,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True,creationflags=subprocess.CREATE_NO_WINDOW)
        self.p.stdin.write(self.token+'\n');self.p.stdin.close()
        def read():
            for line in self.p.stdout:
                line=line.strip();self.lines.append(line);self.q.put(line)
        threading.Thread(target=read,daemon=True).start()
        ready=self.wait('YANDA_COMPANION_READY ')
        p=ready.split();self.port=int(p[1]);self.fp=p[2]
    def wait(self,prefix,timeout=12):
        deadline=time.monotonic()+timeout
        while time.monotonic()<deadline:
            try: line=self.q.get(timeout=.2)
            except queue.Empty: continue
            if line.startswith(prefix):return line
        raise AssertionError('Missing marker: '+prefix)
    def tls(self,version=ssl.TLSVersion.TLSv1_3):
        ctx=ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT);ctx.check_hostname=False;ctx.verify_mode=ssl.CERT_NONE;ctx.minimum_version=version;ctx.maximum_version=version
        raw=socket.create_connection(('127.0.0.1',self.port),timeout=6)
        s=ctx.wrap_socket(raw,server_hostname='local-test');s.settimeout(8)
        assert hashlib.sha256(s.getpeercert(binary_form=True)).hexdigest()==self.fp
        return s
    def auth(self,s,token=None):
        s.sendall(b'YANDA03\n'+(token or self.token).encode());return exact(s,17)
    def close(self):
        if self.p.poll() is None:self.p.kill()
        self.p.wait(timeout=10)
def exact(s,n):
    data=b''
    while len(data)<n:
        part=s.recv(n-len(data))
        if not part:break
        data+=part
    return data
def packet(s,t,b=b'',pts=0):s.sendall(struct.pack('>BIQ',t,len(b),pts)+b)
def fixture(w,h,name):
    path=ROOT/'build'/name
    subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-f','lavfi','-i',f'testsrc2=size={w}x{h}:rate=30','-frames:v','1','-c:v','libx264','-preset','ultrafast','-tune','zerolatency','-f','h264','-y',str(path)],check=True)
    return path.read_bytes()
def main():
    before=set(p.name for p in EXE.parent.iterdir())
    portrait=(ROOT/'tests/fixtures/android-portrait.h264').read_bytes();landscape=(ROOT/'tests/fixtures/android-landscape.h264').read_bytes()
    r=Receiver()
    try:
        try:s=r.tls(ssl.TLSVersion.TLSv1_2);s.close();raise AssertionError('TLS1.2 accepted')
        except ssl.SSLError:passed('TLS 1.2 refused; TLS 1.3 required')
        s=r.tls();assert r.auth(s,'00'*32)==b'';s.close();passed('Wrong token refused without consuming valid QR')
        s=r.tls();ack=r.auth(s);assert ack[:8]==b'YANDAOK\n' and ack[8]==1 and struct.unpack('>II',ack[9:])==(1920,30);passed('Pinned certificate and real authenticated session')
        packet(s,5);assert exact(s,1)==b'\1';passed('Heartbeat roundtrip')
        # Android may send SPS/PPS in standalone codec-config buffers.
        units=[u for u in re.split(b'(?=\x00\x00\x00\x01|(?<!\x00)\x00\x00\x01)',portrait) if u]
        video=b''
        for unit in units:
            offset=4 if unit.startswith(b'\0\0\0\1') else 3
            if unit[offset]&31 in (7,8):packet(s,1,unit)
            else:video+=unit
        packet(s,1,video,1000000);assert r.wait('YANDA_VIDEO ')=='YANDA_VIDEO 320x640';passed('Real H264 decoder: Android-style separate SPS/PPS and portrait frame')
        packet(s,2,b'\0'*19200,1000000);r.wait('YANDA_AUDIO');passed('Real SDL audio output accepts synthetic silent PCM (no audible phone claim)')
        packet(s,1,landscape,1033333);assert r.wait('YANDA_VIDEO ')=='YANDA_VIDEO 640x320';passed('Real H264 resolution/orientation switch')
        packet(s,4);r.wait('YANDA_AUDIO_UNAVAILABLE');passed('Explicit audio-unavailable status')
        packet(s,3);s.close();r.p.wait(timeout=10);assert r.p.returncode==0;passed('Sender end closes receiver cleanly')
        try:socket.create_connection(('127.0.0.1',r.port),timeout=.3).close();raise AssertionError('Listener survived')
        except OSError:passed('Single-use session cannot be replayed after disconnect')
    finally:r.close()
    r=Receiver('--no-audio')
    try:
        s=r.tls();assert r.auth(s)[8]==0;packet(s,1,portrait);r.wait('YANDA_VIDEO ');packet(s,2,b'\0'*19200);packet(s,3);s.close();r.p.wait(timeout=10);assert 'YANDA_AUDIO' not in r.lines;passed('Audio-disabled mode never opens SDL audio device')
    finally:r.close()
    r=Receiver()
    try:
        s=r.tls();r.auth(s);s.sendall(struct.pack('>BIQ',1,9*1024*1024,0));r.wait('YANDA_ERROR');s.close();r.p.wait(timeout=10);assert not any(l.startswith('YANDA_VIDEO') for l in r.lines);passed('Oversized packet rejected before allocation/false stream')
    finally:r.close()
    assert before==set(p.name for p in EXE.parent.iterdir());passed('No media, certificate or identity dumps in runtime')
    report={'kind':'real TLS/FFmpeg/SDL with synthetic H264 and silent PCM; no Android device','checks':checks,'receiverSha256':hashlib.sha256(EXE.read_bytes()).hexdigest()}
    (ROOT/'docs/evidence/android-protocol.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
if __name__=='__main__':main()
