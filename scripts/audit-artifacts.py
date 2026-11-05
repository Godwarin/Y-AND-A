"""Inspect release hashes, PE mitigations and archive structure without extraction.

This is a bounded credential-pattern scan, not a malware verdict or proof that
arbitrary secrets cannot exist. Matching file paths only, never matching text.
"""
import datetime
import hashlib
import argparse
import json
import pathlib
import re
import struct
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
RELEASE = ROOT / 'release/Y AND A 0.3.0-hotfix1'
OUT = ROOT / 'docs/security-evidence/artifacts.json'

def pe(path):
    data = path.read_bytes()
    offset = struct.unpack_from('<I', data, 0x3c)[0]
    assert data[offset:offset+4] == b'PE\0\0'
    optional = offset + 24
    flags = struct.unpack_from('<H', data, optional + 70)[0]
    return {'path': str(path.relative_to(RELEASE)), 'sha256': hashlib.sha256(data).hexdigest(),
            'dynamicBase': bool(flags & 0x40), 'highEntropyVA': bool(flags & 0x20),
            'nxCompatible': bool(flags & 0x100), 'controlFlowGuardFlag': bool(flags & 0x4000)}

def archive(path):
    credentials = re.compile(r'(^|/)(\.local/|\.git/|identity\.key$|adbkey(?:\.pub)?$)|\.(?:p12|jks|pfx|dpapi|yanda-backup)$|local-password|(^|/)\.env(?:\.|$)', re.I)
    pem = re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----')
    result = {'path': str(path.relative_to(ROOT)), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'entries': 0,
              'unsafePaths': [], 'credentialFilenames': [], 'privateKeyPatternFiles': [], 'textFilesScanned': 0}
    with zipfile.ZipFile(path) as z:
        names = set()
        for entry in z.infolist():
            name = entry.filename.replace('\\', '/')
            result['entries'] += 1
            if name.startswith('/') or ':' in name or '..' in name.split('/') or name in names:
                result['unsafePaths'].append(name)
            names.add(name)
            if credentials.search(name):
                result['credentialFilenames'].append(name)
            if entry.file_size <= 4*1024*1024 and pathlib.PurePosixPath(name).suffix.lower() in {'.txt', '.md', '.json', '.rs', '.cpp', '.c', '.h', '.hpp', '.java', '.xml', '.ps1', '.py', '.mjs', '.ts', '.tsx', '.pem', '.key', '.yml', '.yaml', '.toml', '.ini', '.cfg', '.conf'}:
                result['textFilesScanned'] += 1
                if pem.search(z.read(entry)):
                    result['privateKeyPatternFiles'].append(name)
    return result

def main():
    global RELEASE,OUT
    parser=argparse.ArgumentParser();parser.add_argument('--version',default='0.3.0-hotfix1');parser.add_argument('--apk-version',default='0.3.0');parser.add_argument('--output',default=str(OUT));args=parser.parse_args()
    if not re.fullmatch(r'(?:BETA-[0-9]+\.[0-9]+|[0-9]+\.[0-9]+\.[0-9]+(?:-[a-zA-Z0-9.]+)?)',args.version):raise ValueError('Invalid version')
    if not re.fullmatch(r'(?:BETA-[0-9]+\.[0-9]+|[0-9]+\.[0-9]+\.[0-9]+(?:-[a-zA-Z0-9.]+)?)',args.apk_version):raise ValueError('Invalid APK version')
    RELEASE=ROOT/'release'/args.version/'Windows' if args.version.startswith('BETA-') else ROOT/('release/Y AND A '+args.version);OUT=pathlib.Path(args.output)
    report = {'date': datetime.date.today().isoformat(), 'pe': [pe(p) for p in RELEASE.rglob('*') if p.suffix.lower() in {'.dll', '.exe'}],
              'archives': [archive((ROOT/'release'/args.version if args.version.startswith('BETA-') else ROOT/'release') / name) for name in [f'Y-AND-A-{args.version}-win64.zip', f'Y-AND-A-{args.version}-source.zip', f'Y-AND-A-{args.apk_version}-android.apk']]}
    OUT.write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps({'peFiles': len(report['pe']), 'missingNx': [p['path'] for p in report['pe'] if not p['nxCompatible']],
                      'missingAslr': [p['path'] for p in report['pe'] if not p['dynamicBase']], 'archives': report['archives']}, indent=2))

if __name__ == '__main__':
    main()
