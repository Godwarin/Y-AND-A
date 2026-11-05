"""Trusted parent-side, bounded metadata inspection. Never executes release code.

Streams archive entries (64 KiB), reads at most one 32 MiB PE at a time, uses
only the standard library, and never extracts archives or opens signing keys.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import struct
import zipfile

ROOT = Path(__file__).resolve().parent.parent
RELEASE = ROOT / 'release/BETA-0.42'
WINDOWS = RELEASE / 'Windows'
OUT = ROOT / 'docs/evidence/beta-0.42-lightweight.json'
BLOCK = 65536
MAX_ENTRY = 64 * 1024 * 1024
MAX_TOTAL = 1024 * 1024 * 1024
SECRET = re.compile(
    rb'-----BEGIN (?:RSA |DSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----'
    rb'|PuTTY-User-Key-File-[23]:'
    rb'|\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}'
    rb'|sk-proj-[A-Za-z0-9_-]{30,}|(?:AKIA|ASIA)[A-Z0-9]{16}'
    rb'|AIza[A-Za-z0-9_-]{35}|xox[baprs]-[A-Za-z0-9-]{20,})\b'
    rb'|https?://[^\s/\x22\x27:]+:[^\s/@\x22\x27]+@', re.I)
PRIVATE = re.compile(
    r'(^|/)(\.local|\.git|\.ssh|\.aws)(/|$)|'
    r'\.(?:p12|jks|pfx|p8|dpapi|yanda-backup|keystore|kdbx)$|'
    r'(^|/)(?:adbkey(?:\.pub)?|identity\.key|local-password(?:\.txt)?|\.env(?:\..*)?)$', re.I)
TEXT = {'.txt', '.md', '.json', '.rs', '.cpp', '.c', '.h', '.hpp', '.java',
        '.xml', '.ps1', '.py', '.mjs', '.ts', '.tsx', '.pem', '.key', '.yml',
        '.yaml', '.toml', '.ini', '.cfg', '.conf'}
CRT = re.compile(r'^(?:vcruntime|msvcp|concrt|vcomp)\d+(?:_\d+)?\.dll$', re.I)


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def safe_zip_path(name):
    if not name or '\\' in name or name.startswith('/'):
        return False
    parts = name.removesuffix('/').split('/')
    for part in parts:
        if not part or part in {'.', '..'} or part[-1] in ' .':
            return False
        if any(ord(c) < 32 or c in '<>:"|?*' for c in part):
            return False
        stem = part.split('.')[0].upper()
        if stem in {'CON', 'PRN', 'AUX', 'NUL', 'CONIN$', 'CONOUT$'} or re.fullmatch(r'(?:COM|LPT)[1-9]', stem):
            return False
    return True


def archive(path):
    result = {'path': path.name, 'sha256': digest(path), 'entries': 0,
              'bytesRead': 0, 'textEntriesScanned': 0, 'problems': []}
    hashes = {}
    with zipfile.ZipFile(path) as z:
        entries = z.infolist()
        if len(entries) > 2048:
            raise ValueError('ARCHIVE_ENTRY_BOUND')
        seen = set()
        for entry in entries:
            name = entry.filename
            result['entries'] += 1
            normalized = name.casefold()
            mode = (entry.external_attr >> 16) & 0o170000
            if (not safe_zip_path(name) or normalized in seen or
                    mode not in {0, 0o040000, 0o100000} or
                    entry.flag_bits & 1 or entry.external_attr & 0x400):
                result['problems'].append({'path': name, 'reason': 'unsafe_zip_metadata'})
            seen.add(normalized)
            if PRIVATE.search(name):
                result['problems'].append({'path': name, 'reason': 'private_filename'})
            if entry.is_dir():
                continue
            if entry.file_size > MAX_ENTRY or result['bytesRead'] + entry.file_size > MAX_TOTAL:
                raise ValueError('ARCHIVE_BYTE_BOUND')
            scan = PurePosixPath(name).suffix.lower() in TEXT and entry.file_size <= 4 * 1024 * 1024
            h = hashlib.sha256()
            tail = b''
            match = False
            size = 0
            with z.open(entry) as stream:
                while block := stream.read(BLOCK):
                    size += len(block)
                    if size > entry.file_size or size > MAX_ENTRY:
                        raise ValueError('ARCHIVE_EXPANSION_BOUND')
                    h.update(block)
                    if scan:
                        match = match or bool(SECRET.search(tail + block))
                        tail = block[-512:]
            if size != entry.file_size:
                raise ValueError('ARCHIVE_SIZE_MISMATCH')
            hashes[name] = h.hexdigest()
            result['bytesRead'] += size
            if scan:
                result['textEntriesScanned'] += 1
            if match:
                result['problems'].append({'path': name, 'reason': 'credential_pattern'})
    result['crcAndFullReadVerified'] = True
    return result, hashes


def pe_imports(path):
    if path.stat().st_size > 32 * 1024 * 1024:
        raise ValueError('PE_SIZE_BOUND')
    data = path.read_bytes()
    if data[:2] != b'MZ':
        raise ValueError('PE_DOS_SIGNATURE')
    offset = struct.unpack_from('<I', data, 0x3c)[0]
    if data[offset:offset + 4] != b'PE\0\0':
        raise ValueError('PE_SIGNATURE')
    machine, sections = struct.unpack_from('<HH', data, offset + 4)
    optional_size = struct.unpack_from('<H', data, offset + 20)[0]
    opt = offset + 24
    if machine != 0x8664 or struct.unpack_from('<H', data, opt)[0] != 0x20b:
        raise ValueError('PE_EXPECTED_X64')
    table = opt + optional_size
    if not 1 <= sections <= 96 or table + sections * 40 > len(data):
        raise ValueError('PE_SECTIONS_BOUND')
    mappings = []
    for i in range(sections):
        virtual_size, virtual, raw_size, raw = struct.unpack_from('<IIII', data, table + i * 40 + 8)
        mappings.append((virtual, max(virtual_size, raw_size), raw, raw_size))

    def address(rva):
        for virtual, size, raw, raw_size in mappings:
            if virtual <= rva < virtual + size and rva - virtual < raw_size:
                at = raw + rva - virtual
                if at < len(data):
                    return at
        raise ValueError('PE_RVA_BOUND')

    def text_at(rva):
        at = address(rva)
        end = data.find(b'\0', at, min(at + 260, len(data)))
        if end < 0:
            raise ValueError('PE_DLL_NAME_BOUND')
        value = data[at:end].decode('ascii').lower()
        if not re.fullmatch(r'[a-z0-9_.-]+\.dll', value):
            raise ValueError('PE_DLL_NAME')
        return value

    imports = set()
    for directory, width, name_at in [(1, 20, 12), (13, 32, 4)]:
        rva, size = struct.unpack_from('<II', data, opt + 112 + directory * 8)
        if not rva:
            continue
        if size > 65536:
            raise ValueError('PE_IMPORT_DIRECTORY_BOUND')
        at = address(rva)
        for i in range(1024):
            record = data[at + i * width:at + (i + 1) * width]
            if len(record) != width:
                raise ValueError('PE_IMPORT_DESCRIPTOR_BOUND')
            if not any(record):
                break
            name_rva = struct.unpack_from('<I', record, name_at)[0]
            if directory == 13 and not struct.unpack_from('<I', record)[0] & 1:
                raise ValueError('PE_LEGACY_DELAY_IMPORT_NOT_COVERED')
            imports.add(text_at(name_rva))
        else:
            raise ValueError('PE_IMPORT_COUNT_BOUND')
    own = {p.name.lower() for p in path.parent.iterdir() if p.is_file()}
    system = Path(os.environ.get('SystemRoot', r'C:\Windows')) / 'System32'
    unresolved = []
    local_crt_missing = []
    for name in sorted(imports):
        if CRT.fullmatch(name) and name not in own:
            local_crt_missing.append(name)
        if name not in own and not name.startswith(('api-ms-', 'ext-ms-')) and not (system / name).is_file():
            unresolved.append(name)
    return {'path': path.relative_to(WINDOWS).as_posix(), 'imports': sorted(imports),
            'unresolvedOnThisWindows': unresolved, 'crtNotBesideImage': local_crt_missing}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', default=str(OUT))
    args = parser.parse_args()
    destination = Path(args.output).resolve()
    if destination.parent not in {(ROOT / 'docs/evidence').resolve(), (ROOT / 'publish').resolve()} or destination.suffix != '.json':
        raise ValueError('REPORT_PATH_NOT_ALLOWED')
    # Public path fixtures exercise only this trusted metadata validator.
    negatives = ['../x', '/x', 'C:/x', 'a\\b', 'a/../b', 'NUL.txt', 'COM1/a',
                 'a/file:stream', 'a./b', 'a//b', 'a/ x ', 'a/\x00b']
    if not all(not safe_zip_path(n) for n in negatives) or not safe_zip_path('Windows/Y AND A.exe'):
        raise ValueError('PATH_VALIDATOR_SELF_CHECK')
    report = {'date': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'artifactVersion': 'BETA-0.42', 'status': 'PASS_METADATA_CHECKS',
              'productCodeExecuted': False, 'vmStarted': False,
              'pathNegativeFixturesRejected': len(negatives),
              'archives': [], 'peImports': [], 'problems': [],
              'memoryDesign': {'archiveReadBlockBytes': BLOCK, 'maxPeReadBytes': 32 * 1024 * 1024},
              'limitations': ['Not a runtime, malware or exhaustive secret audit',
                             'Nested dependency archives and binary string secrets are not recursively scanned',
                             'API-set imports are recognized by prefix; this host is not a fresh Windows installation']}
    manifests = {}
    for name in ['Y-AND-A-BETA-0.42-win64.zip', 'Y-AND-A-BETA-0.42-source.zip', 'Y-AND-A-BETA-0.42-android.apk']:
        item, hashes = archive(RELEASE / name)
        report['archives'].append(item)
        report['problems'].extend(item['problems'])
        manifests[name] = hashes
    frozen = json.loads((ROOT / 'docs/evidence/artifact-relocation.json').read_text(encoding='utf-8-sig'))['applicationFilesSha256']
    win_zip = manifests['Y-AND-A-BETA-0.42-win64.zip']
    for name, expected in frozen.items():
        path = WINDOWS / name
        if path.is_symlink() or path.stat().st_file_attributes & 0x400 or digest(path) != expected or win_zip.get('Windows/' + name) != expected:
            report['problems'].append({'path': name, 'reason': 'frozen_file_changed'})
        if path.suffix.lower() in {'.exe', '.dll'}:
            entry = pe_imports(path)
            report['peImports'].append(entry)
            if entry['unresolvedOnThisWindows'] or entry['crtNotBesideImage']:
                report['problems'].append({'path': name, 'reason': 'dependency_review_needed'})
    report['frozenApplicationFilesChecked'] = len(frozen)
    snapshot = json.loads((ROOT / 'publish/github-manifest.json').read_text(encoding='utf-8'))
    source = manifests['Y-AND-A-BETA-0.42-source.zip']
    drift = [v['path'] for v in snapshot['files'] if source.get(v['path']) != v['sha256']]
    runtime_prefixes = ('src/', 'src-tauri/src/', 'src-tauri/capabilities/', 'android-app/', 'native/', 'public/', 'vendor/airplay-windows/src/', 'vendor/airplay-windows/include/')
    runtime_files = {'src-tauri/Cargo.toml', 'src-tauri/Cargo.lock', 'src-tauri/build.rs', 'src-tauri/tauri.conf.json', 'package.json', 'package-lock.json'}
    code_drift = [p for p in drift if p.startswith(runtime_prefixes) or p in runtime_files]
    report['sourceArchiveDrift'] = {'currentSnapshotDifferentFiles': drift,
                                  'applicationCodeDifferentFiles': code_drift,
                                  'reviewedSnapshotSha256': snapshot['snapshotSha256'],
                                  'refreshNeededBeforePublication': bool(drift)}
    if code_drift:
        report['problems'].append({'reason': 'source_archive_application_code_drift'})
    if report['problems']:
        report['status'] = 'NEEDS_REVIEW'
    if os.name == 'nt':
        import ctypes
        class Memory(ctypes.Structure):
            _fields_ = [('cb', ctypes.c_uint32), ('faults', ctypes.c_uint32)] + [
                (name, ctypes.c_size_t) for name in
                ['peakWorkingSet', 'workingSet', 'peakPaged', 'paged',
                 'peakNonPaged', 'nonPaged', 'pagefile', 'peakPagefile']]
        kernel = ctypes.WinDLL('kernel32', use_last_error=True)
        kernel.GetCurrentProcess.restype = ctypes.c_void_p
        kernel.K32GetProcessMemoryInfo.argtypes = [ctypes.c_void_p, ctypes.POINTER(Memory), ctypes.c_uint32]
        memory = Memory(cb=ctypes.sizeof(Memory))
        if not kernel.K32GetProcessMemoryInfo(kernel.GetCurrentProcess(), ctypes.byref(memory), memory.cb):
            raise ValueError('OWN_PROCESS_MEMORY_QUERY_FAILED')
        report['observedOwnPeakWorkingSetMiB'] = round(memory.peakWorkingSet / 1048576, 1)
    destination.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding='utf-8')
    print(json.dumps({'status': report['status'], 'archives': len(report['archives']),
                      'frozenFiles': len(frozen), 'peFiles': len(report['peImports']),
                      'sourceArchiveChangedFiles': len(drift), 'applicationCodeDrift': code_drift,
                      'observedOwnPeakWorkingSetMiB': report.get('observedOwnPeakWorkingSetMiB'),
                      'problems': report['problems'], 'productCodeExecuted': False}, ensure_ascii=False))
    return 0 if not report['problems'] else 2


if __name__ == '__main__':
    raise SystemExit(main())
