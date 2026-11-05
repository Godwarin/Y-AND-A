"""Security regressions on owned runtime helpers, loopback and public fixtures.

Never tests against a foreign listener, never reads/captures a real phone.
"""
import hashlib, importlib.util, json, os, pathlib, queue, re, socket, ssl, struct, subprocess, threading, time
ROOT=pathlib.Path(__file__).resolve().parent.parent
OUT=ROOT/'docs/evidence/security-candidate.json'
def module(name,path):
    spec=importlib.util.spec_from_file_location(name,ROOT/path);value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value
android=module('android_protocol','scripts/test-android-protocol.py')
air=module('air_protocol','vendor/airplay-windows/tools/test_pair_verify.py')
checks=[]
def passed(name):checks.append(name);print('PASS',name,flush=True)

def tcp_listener_owners(port, expected_pid):
    """Query the real IPv4 listener table without PowerShell/CLR or WMI.

    Used only in the isolated guest. Bounds and native errors fail closed.
    https://learn.microsoft.com/windows/win32/api/iphlpapi/nf-iphlpapi-getextendedtcptable
    """
    proof=os.environ.get('YANDA_LISTENER_PROOF_DIR')
    if proof:
        folder=pathlib.Path(proof)
        if not re.fullmatch(r'C:\\YandaTools\\ownership-[0-9a-f]{32}',str(folder)):
            raise RuntimeError('Invalid trusted ownership directory')
        path=folder/(str(expected_pid)+'.json')
        deadline=time.monotonic()+5
        while not path.exists() and time.monotonic()<deadline:time.sleep(.05)
        if path.stat().st_size>1024:raise RuntimeError('Ownership proof size bound')
        data=json.loads(path.read_text(encoding='utf-8-sig'))
        if data!={'pid':expected_pid,'port':port,'image':'airplay-windows.exe','jobVerified':True}:
            raise RuntimeError('Listener ownership proof mismatch')
        return {expected_pid}
    import ctypes
    api=ctypes.WinDLL('iphlpapi.dll').GetExtendedTcpTable
    api.argtypes=[ctypes.c_void_p,ctypes.POINTER(ctypes.c_uint32),ctypes.c_int,
                  ctypes.c_uint32,ctypes.c_int,ctypes.c_uint32]
    api.restype=ctypes.c_uint32
    size=ctypes.c_uint32()
    result=api(None,ctypes.byref(size),False,socket.AF_INET,3,0)
    if result not in (0,122):raise OSError(result,'TCP owner query failed')
    for _ in range(3):
        if not 4 <= size.value <= 1048576:raise RuntimeError('TCP table size bound')
        data=ctypes.create_string_buffer(size.value)
        result=api(data,ctypes.byref(size),False,socket.AF_INET,3,0)
        if result==122:continue
        if result:raise OSError(result,'TCP owner query failed')
        count=struct.unpack_from('<I',data)[0]
        if count>4096 or 4+count*24>min(size.value,len(data)):raise RuntimeError('TCP row bound')
        owners=set()
        for i in range(count):
            state,_,local_port,_,_,pid=struct.unpack_from('<6I',data,4+i*24)
            if state==2 and socket.ntohs(local_port&0xffff)==port:owners.add(pid)
        return owners
    raise RuntimeError('TCP table changed too often')

def test_android():
    r=android.Receiver()
    try:
        s=r.tls();start=time.monotonic()
        for _ in range(7):
            try:s.sendall(b'Y');time.sleep(1)
            except OSError:break
        s.settimeout(2)
        try:assert s.recv(1)==b''
        except (ConnectionResetError,ssl.SSLError):pass
        assert time.monotonic()-start<9
        s.close();passed('Android absolute 4s pre-auth deadline rejects trickled bytes')
        good=r.tls();assert r.auth(good)[:8]==b'YANDAOK\n'
        passed('Android remains connectable with valid QR after slow sender')
        good.sendall(struct.pack('>BIQ',1,1024,0)+b'\0');time.sleep(11)
        good.settimeout(2)
        try:assert good.recv(1)==b''
        except (ConnectionResetError,ssl.SSLError):pass
        good.close();r.p.wait(timeout=5)
        passed('Android incomplete authenticated packet has absolute deadline and closes session')
    finally:r.close()
    r=android.Receiver()
    try:
        slow=r.tls();slow.sendall(b'Y')
        raw=socket.socket();raw.bind(('127.0.0.2',0));raw.settimeout(3);start=time.monotonic();raw.connect(('127.0.0.1',r.port))
        ctx=ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT);ctx.check_hostname=False;ctx.verify_mode=ssl.CERT_NONE;ctx.minimum_version=ssl.TLSVersion.TLSv1_3
        good=ctx.wrap_socket(raw,server_hostname='public-synthetic-fixture')
        assert hashlib.sha256(good.getpeercert(binary_form=True)).hexdigest()==r.fp
        assert r.auth(good)[:8]==b'YANDAOK\n' and time.monotonic()-start<2
        android.packet(good,3);good.close();slow.close();r.p.wait(timeout=5)
        passed('Android slow peer does not block another address: bounded concurrent pre-auth and per-IP quota')
    finally:r.close()

class AirReceiver:
    def __init__(self):
        with socket.socket(socket.AF_INET,socket.SOCK_STREAM) as probe:
            probe.setsockopt(socket.SOL_SOCKET,socket.SO_EXCLUSIVEADDRUSE,1)
            try:probe.bind(('127.0.0.1',7000))
            except OSError as error:raise RuntimeError('Port 7000 occupied: existing receiver left untouched') from error
        self.exe=ROOT/'runtime/airplay-yanda/airplay-windows.exe';self.q=queue.Queue();self.approvals=queue.Queue();self.video_events=[]
        state=ROOT/'build/security-candidate-airplay';state.mkdir(exist_ok=True)
        env=dict(os.environ,YANDA_EMBEDDED='1',YANDA_AIRPLAY_STATE_DIR=str(state))
        self.p=subprocess.Popen([str(self.exe),'--log'],cwd=state,env=env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,creationflags=subprocess.CREATE_NO_WINDOW)
        def drain(stream):
            for line in stream:
                if 'YANDA_READY' in line:self.q.put('READY')
                if line.startswith('YANDA_APPROVAL '):self.approvals.put(line.split()[1:])
                if 'YANDA_VIDEO ' in line:self.video_events.append(line)
        for stream in [self.p.stdout,self.p.stderr]:threading.Thread(target=drain,args=(stream,),daemon=True).start()
        assert self.q.get(timeout=15)=='READY'
        assert tcp_listener_owners(7000,self.p.pid)=={self.p.pid},'Listener ownership mismatch'
    def command(self,action,request_id):self.p.stdin.write(action+' '+request_id+'\n');self.p.stdin.flush()
    def close(self):
        if self.p.poll() is None:self.p.terminate()
        self.p.wait(timeout=10)

def pair_async(receiver,other=False):
    c=air.Conn('127.0.0.1',7000);c.sock.settimeout(25);crypto=air.ClientCrypto()
    if other:
        from cryptography.hazmat.primitives.asymmetric import ed25519
        from cryptography.hazmat.primitives import serialization
        crypto.ed_priv=ed25519.Ed25519PrivateKey.from_private_bytes(bytes.fromhex('24'*32))
        crypto.ed_pub=crypto.ed_priv.public_key().public_bytes(serialization.Encoding.Raw,serialization.PublicFormat.Raw)
    identity=air.get_server_identity_pub(c);result=queue.Queue()
    def run():
        try:result.put(air.do_pair_verify(c,crypto,identity))
        except Exception as e:result.put(e)
    worker=threading.Thread(target=run,daemon=True);worker.start()
    return c,result,worker

def test_airplay():
    r=AirReceiver()
    try:
        for method,path in [('POST','/stop'),('POST','/rate?value=1'),('SETUP','/stream'),('SET_PARAMETER','/stream'),('POST','/action'),('ANNOUNCE','/stream')]:
            c=air.Conn('127.0.0.1',7000)
            try:assert c.rpc(method,path)[0]==470
            finally:c.close()
        passed('AirPlay all six unauthorised control/media routes denied before pairing')
        c=air.Conn('127.0.0.1',7000)
        try:assert c.rpc('YANDA_VIDEO','864x1920')[0]==470
        finally:c.close()
        time.sleep(.2);assert not r.video_events
        passed('Untrusted request text cannot impersonate a native video lifecycle event')
        for headers in [b'Content-Length: -1',b'Content-Length: 18446744073709551615',b'Content-Length: 65537',b'Content-Length: 0\r\nContent-Length: 0',b'Transfer-Encoding: chunked']:
            with socket.create_connection(('127.0.0.1',7000),timeout=3) as s:
                s.settimeout(3);s.sendall(b'POST /pair-setup RTSP/1.0\r\n'+headers+b'\r\n\r\n')
                try:assert s.recv(1024)==b''
                except ConnectionResetError:pass
        passed('AirPlay negative/overflow/oversize/duplicate length and transfer-encoding rejected')
        c,result,worker=pair_async(r);pending=r.approvals.get(timeout=3)
        assert len(pending)==3 and pending[2]=='127.0.0.1'
        r.command('ALLOW','0'*32);time.sleep(.3);assert worker.is_alive()
        r.command('DENY',pending[0]);answer=result.get(timeout=3);assert answer==(200,470,True);c.close()
        passed('Verified AirPlay key requires owner approval; wrong request ID ignored and denial enforced')
        c,result,worker=pair_async(r);pending2=r.approvals.get(timeout=3)
        r.command('ALLOW',pending[0]);time.sleep(.3);assert worker.is_alive()
        r.command('ALLOW',pending2[0]);assert result.get(timeout=3)==(200,200,True)
        assert c.rpc('POST','/stop')[0]==200;c.close()
        passed('Fresh owner approval permits verified sender; stale approval cannot authorise new request')
        c,result,worker=pair_async(r);assert result.get(timeout=3)==(200,200,True);c.close()
        passed('Same approved key may reconnect only after fresh cryptographic proof')
        c,result,worker=pair_async(r,other=True);assert result.get(timeout=3)==(200,470,True);c.close()
        assert r.approvals.empty();passed('Another valid sender key denied while approved receiver session is active')
        time.sleep(1.1);clients=[];closed=0;accepted=0
        try:
            for _ in range(22):
                try:clients.append(socket.create_connection(('127.0.0.1',7000),timeout=1))
                except OSError:closed+=1
            time.sleep(.2)
            for s in clients:
                s.settimeout(1)
                try:
                    s.sendall(b'GET /info RTSP/1.0\r\nContent-Length: 0\r\n\r\n')
                    if s.recv(4096):accepted+=1
                    else:closed+=1
                except OSError:closed+=1
            assert accepted<=16 and closed>=6
        finally:
            for s in clients:s.close()
        passed('AirPlay concurrent client limit rejects excess sockets without crashing helper')
        assert r.p.poll() is None
    finally:r.close()
    r=AirReceiver()
    try:
        c,result,worker=pair_async(r);pending=r.approvals.get(timeout=3)
        assert result.get(timeout=23)==(200,470,True);c.close()
        r.command('ALLOW',pending[0])
        c=air.Conn('127.0.0.1',7000)
        try:assert c.rpc('POST','/stop')[0]==470
        finally:c.close()
        passed('AirPlay approval expires after 20s and cannot be replayed afterwards')
    finally:r.close()

def main():
    report={'version':json.loads((ROOT/'package.json').read_text())['version'],'kind':'real owned helpers, loopback, public synthetic credentials; no physical phone','checks':checks,'hashes':{name:hashlib.sha256((ROOT/'runtime'/name).read_bytes()).hexdigest() for name in ['android-yanda/yanda-android.exe','airplay-yanda/airplay-windows.exe']},'physicalPhoneTested':False,'releaseVerdict':'PENDING_OWNER_DEVICE_VALIDATION_AND_DISTRIBUTION_SETUP'}
    try:test_android();test_airplay();report['status']='PASS'
    except Exception as error:report['status']='FAIL';report['error']=str(error);raise
    finally:OUT.write_text(json.dumps(report,indent=2),encoding='utf-8')
if __name__=='__main__':main()
