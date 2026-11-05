"""Bounded loopback checks of owned latest-release helper processes only.

No real phone, recording, port flood, OOM payload or external host is used.
Existing listeners/processes are never stopped. Public synthetic token only.
"""
import hashlib
import importlib.util
import json
import os
import pathlib
import socket
import ssl
import struct
import subprocess
import threading
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
RELEASE = ROOT / 'release/Y AND A 0.3.0-hotfix1'
OUT = ROOT / 'docs/security-evidence/network.json'
spec = importlib.util.spec_from_file_location('protocol', ROOT / 'scripts/test-android-protocol.py')
protocol = importlib.util.module_from_spec(spec)
spec.loader.exec_module(protocol)
protocol.EXE = RELEASE / 'runtime/android-yanda/yanda-android.exe'
checks, findings, skipped = [], [], []

def check(name):
    checks.append(name)
    print('PASS', name, flush=True)

def android():
    r = protocol.Receiver()
    try:
        raw = socket.create_connection(('127.0.0.1', r.port), timeout=8)
        raw.settimeout(9)
        start = time.monotonic()
        try:
            result = raw.recv(1)
            assert result == b''
        except ConnectionResetError:
            pass
        assert time.monotonic() - start < 8
        raw.close()
        s = r.tls()
        assert r.auth(s)[:8] == b'YANDAOK\n'
        protocol.packet(s, 3)
        s.close()
        r.p.wait(timeout=8)
        check('Silent unauthenticated TCP client times out; legitimate authentication recovers')
    finally:
        r.close()
    for name, kind, count in [('unknown packet', 99, 0), ('unaligned PCM', 2, 3), ('zero-length H264', 1, 0), ('oversized PCM', 2, 192004)]:
        r = protocol.Receiver()
        try:
            s = r.tls()
            assert r.auth(s)[:8] == b'YANDAOK\n'
            s.sendall(struct.pack('>BIQ', kind, count, 0))
            r.wait('YANDA_ERROR')
            s.close()
            r.p.wait(timeout=8)
            assert not any(l.startswith('YANDA_VIDEO') for l in r.lines)
            check(name + ' rejected before false streaming')
        finally:
            r.close()
    r = protocol.Receiver()
    try:
        s = r.tls()
        # A byte each second resets the per-recv timeout without authenticating.
        start = time.monotonic()
        for byte in b'YANDA03\n':
            s.sendall(bytes([byte]))
            time.sleep(1)
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        ctx.minimum_version = ssl.TLSVersion.TLSv1_3
        raw = socket.create_connection(('127.0.0.1', r.port), timeout=2)
        try:
            other = ctx.wrap_socket(raw, server_hostname='synthetic-test')
            other.close()
            raise AssertionError('Second handshake unexpectedly completed')
        except (TimeoutError, ssl.SSLError):
            raw.close()
        held = round(time.monotonic() - start, 2)
        assert held > 8
        findings.append({'id': 'YA-03', 'observed': 'Unauthenticated slow sender held the single accept loop beyond the 5s socket timeout; second client TLS handshake timed out', 'seconds': held})
        print('CONFIRMED YA-03 slow authentication blocks next client', flush=True)
        s.close()
    finally:
        r.close()

def request(wire):
    with socket.create_connection(('127.0.0.1', 7000), timeout=4) as s:
        s.settimeout(4)
        s.sendall(wire)
        data = b''
        while b'\r\n\r\n' not in data:
            more = s.recv(4096)
            if not more:
                break
            data += more
        return data.split(b'\r\n', 1)[0].decode('ascii', errors='replace')

def airplay():
    try:
        with socket.create_connection(('127.0.0.1', 7000), timeout=.3):
            skipped.append('AirPlay: port 7000 already occupied; foreign listener untouched')
            return
    except OSError:
        pass
    exe = RELEASE / 'runtime/airplay-yanda/airplay-windows.exe'
    state = ROOT / 'build/security-audit/airplay-state'
    state.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, YANDA_EMBEDDED='1', YANDA_AIRPLAY_STATE_DIR=str(state))
    p = subprocess.Popen([str(exe), '--log'], cwd=state, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, creationflags=subprocess.CREATE_NO_WINDOW)
    logs = []
    def drain(stream):
        for line in iter(stream.readline, b''):
            if b'YANDA_READY' in line:
                logs.append('READY')
    for stream in [p.stdout, p.stderr]:
        threading.Thread(target=drain, args=(stream,), daemon=True).start()
    idle = []
    try:
        for _ in range(100):
            if logs or p.poll() is not None:
                break
            time.sleep(.1)
        if p.poll() is not None or not logs:
            skipped.append('AirPlay owned helper did not become ready (possible existing single-instance owner)')
            return
        # Verify the listener PID before sending even synthetic control requests.
        ownership = subprocess.check_output(['powershell', '-NoProfile', '-Command', '(Get-NetTCPConnection -State Listen -LocalPort 7000).OwningProcess | Sort-Object -Unique'], text=True, creationflags=subprocess.CREATE_NO_WINDOW)
        assert set(ownership.split()) == {str(p.pid)}, 'Listener is not exclusively owned by this audit'
        status = request(b'POST /stop HTTP/1.1\r\nContent-Length: 0\r\n\r\n')
        assert ' 200 ' in status
        findings.append({'id': 'YA-01', 'observed': 'POST /stop accepted without pairing or credentials on owned receiver', 'response': status})
        print('CONFIRMED YA-01 unauthenticated AirPlay control', flush=True)
        # At most 1 MiB, not an exhaustion payload; static review supplies the
        # missing upper limit, this probe only confirms non-rejection behavior.
        body = b'\0' * (1024 * 1024)
        status = request(b'POST /audit-synthetic HTTP/1.1\r\nContent-Length: 1048576\r\n\r\n' + body)
        assert ' 413 ' not in status
        for _ in range(12):
            idle.append(socket.create_connection(('127.0.0.1', 7000), timeout=2))
        time.sleep(1)
        assert p.poll() is None
        findings.append({'id': 'YA-02', 'observed': '1 MiB unauthenticated body processed without 413; 12 idle connections simultaneously accepted. Unbounded growth is established by source review, not an OOM/flood test.', 'response': status})
        print('CONFIRMED YA-02 bounded resource-limit probes', flush=True)
        check('Owned AirPlay helper remains alive after bounded probes')
    finally:
        for s in idle:
            s.close()
        if p.poll() is None:
            # Close only the process object created above, never image-name kill.
            p.terminate()
        p.wait(timeout=10)
        check('Owned AirPlay helper terminated after audit; no foreign process stopped')

def main():
    report = {'date': '2026-11-03', 'scope': 'exact hotfix1 release helpers; loopback, synthetic inputs only', 'hashes': {str(p.relative_to(RELEASE)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [protocol.EXE, RELEASE / 'runtime/airplay-yanda/airplay-windows.exe']}, 'checks': checks, 'confirmedFindings': findings, 'skipped': skipped}
    try:
        android()
        airplay()
        report['auditExecution'] = 'COMPLETE'
    except Exception as error:
        report['auditExecution'] = 'FAILED'
        report['error'] = str(error)
        raise
    finally:
        OUT.write_text(json.dumps(report, indent=2), encoding='utf-8')

if __name__ == '__main__':
    main()
