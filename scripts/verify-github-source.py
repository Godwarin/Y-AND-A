"""Read-only publication checks for the generated source snapshot.

Does not import project modules, execute the app, read signing secrets, or use
the network. The JSON receipt is local and is not part of the source snapshot.
"""
from pathlib import Path
import hashlib
import json
import re
import sys
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parent.parent
SNAPSHOT = ROOT / 'publish/github'
MANIFEST = ROOT / 'publish/github-manifest.json'
REPORT = ROOT / 'publish/github-security-review.json'
SECRET = re.compile(
    rb'-----BEGIN (?:RSA |DSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----'
    rb'|PuTTY-User-Key-File-[23]:'
    rb'|\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}'
    rb'|sk-proj-[A-Za-z0-9_-]{30,}|(?:AKIA|ASIA)[A-Z0-9]{16}'
    rb'|AIza[A-Za-z0-9_-]{35}|xox[baprs]-[A-Za-z0-9-]{20,})\b'
    rb'|https?://[^\s/\x22\x27:]+:[^\s/@\x22\x27]+@', re.I
)
PRIVATE_DIRS = {'.git', '.local', '.ssh', '.aws', 'node_modules', '__pycache__',
                'archive', 'build', 'downloads', 'publish', 'release', 'runtime'}
PRIVATE_SUFFIXES = {'.key', '.keytab', '.p8', '.p12', '.pfx', '.jks', '.keystore',
                    '.kdbx', '.dpapi', '.yanda-backup', '.exe', '.dll', '.apk',
                    '.pdb', '.obj', '.lib', '.pyc', '.zip', '.crate', '.tgz'}
REQUIRED = ['README.md', 'CONTRIBUTING.md', 'docs/GITHUB_FIRST_STEPS.md', 'docs/RELEASE_NOTES_BETA_0.42.md', '.github/ISSUE_TEMPLATE/bug_report.md', 'SECURITY.md', 'LICENSE', 'THIRD_PARTY_NOTICES.md',
            'docs/BUILD_FROM_SOURCE.md', 'docs/USER_GUIDE.md', 'docs/PRIVACY.md',
            'docs/CURATOR_HANDOFF.md', 'docs/TEST_RESULTS.md',
            'licenses/Apache-2.0.txt', 'vendor/airplay-windows/LICENSE',
            'vendor/airplay-windows/THIRD_PARTY_NOTICES.md',
            'vendor/airplay-windows/CMakeLists.txt', 'native/android-receiver/main.cpp',
            'android-app/src/local/yanda/companion/StreamService.java',
            'src-tauri/src/engine/companion.rs', 'src-tauri/Cargo.lock',
            'package-lock.json', 'public/animation/forty-two.js']


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def inspect():
    if SNAPSHOT.is_symlink() or SNAPSHOT.lstat().st_file_attributes & 0x400:
        raise RuntimeError('Snapshot root must be an ordinary directory')
    manifest = json.loads(MANIFEST.read_text(encoding='utf-8'))
    expected = {r['path']: r for r in manifest['files']}
    problems = []
    if len(expected) != len(manifest['files']):
        problems.append({'path': 'manifest', 'reason': 'duplicate_manifest_paths'})
    seen = {}
    total = 0
    for path in SNAPSHOT.rglob('*'):
        name = path.relative_to(SNAPSHOT).as_posix()
        stat = path.lstat()
        if path.is_symlink() or stat.st_file_attributes & 0x400:
            problems.append({'path': name, 'reason': 'reparse_entry'})
            continue
        if any(p.lower() in PRIVATE_DIRS for p in path.relative_to(SNAPSHOT).parts):
            problems.append({'path': name, 'reason': 'private_directory'})
        if not path.is_file():
            continue
        seen[name] = True
        if name not in expected or stat.st_nlink != 1 or stat.st_size > 4*1024*1024:
            problems.append({'path': name, 'reason': 'unexpected_entry'})
            continue
        row = expected[name]
        if stat.st_size != row['bytes'] or digest(path) != row['sha256']:
            problems.append({'path': name, 'reason': 'snapshot_hash_mismatch'})
        if digest(ROOT / name) != row['sourceSha256']:
            problems.append({'path': name, 'reason': 'source_changed_after_snapshot'})
        if (path.suffix.lower() in PRIVATE_SUFFIXES or path.name.lower().startswith('.env')
                or path.name.lower() in {'local-password.txt', 'id_rsa', 'id_ed25519', 'credentials'}):
            problems.append({'path': name, 'reason': 'private_or_generated_file'})
        data = path.read_bytes()
        total += len(data)
        if SECRET.search(data):
            problems.append({'path': name, 'reason': 'credential_pattern'})
        if path.suffix.lower() in {'.md', '.json', '.toml', '.txt', '.xml', '.yml'}:
            if re.search(rb'(?i)\b[A-Z]:[\\/]Users[\\/][^\s\x22<>]+', data):
                problems.append({'path': name, 'reason': 'personal_absolute_path'})
    for name in set(expected) - set(seen):
        problems.append({'path': name, 'reason': 'missing_snapshot_file'})
    for name in REQUIRED:
        if not (SNAPSHOT / name).is_file():
            problems.append({'path': name, 'reason': 'missing_source_or_notice'})
    links_checked = 0
    maintained = [SNAPSHOT/'README.md', SNAPSHOT/'SECURITY.md']
    maintained.extend((SNAPSHOT/'docs').glob('*.md'))
    for path in maintained:
        source = path.read_text(encoding='utf-8-sig')
        for match in re.finditer(r'!?\[[^\]\r\n]*\]\(([^)\r\n]+)\)', source):
            target = match.group(1).strip().strip('<>')
            if re.match(r'(?i)^(?:https?://|mailto:|#)', target):
                continue
            target = unquote(target.split('#', 1)[0])
            resolved = (path.parent / target).resolve()
            links_checked += 1
            if not resolved.is_relative_to(SNAPSHOT.resolve()) or not resolved.exists():
                problems.append({'path': path.relative_to(SNAPSHOT).as_posix(),
                                 'reason': 'broken_local_link', 'target': target})
    if digest(SNAPSHOT/'public/animation/forty-two.js') != '2496f79b8c416b1ff33d404a67d887b3460083f00e47c8b1e548669b2edc2b03':
        problems.append({'path': 'public/animation/forty-two.js', 'reason': 'original_asset_changed'})
    return {'status': 'PASS_PRIVATE_SOURCE_PREPARATION' if not problems else 'NEEDS_REVIEW',
            'scope': 'Local source publication hygiene, integrity and documentation',
            'files': len(seen), 'bytes': total, 'localMarkdownLinksChecked': links_checked,
            'snapshotSha256': manifest['snapshotSha256'], 'problems': problems,
            'binarySecurityValidation': 'NOT_ASSESSED_BY_SOURCE_CHECK', 'productTestsRun': 0,
            'vmStarted': False, 'publicationPerformed': False,
            'limitations': ['Pattern scan cannot prove absence of every possible secret',
                            'This receipt does not certify application or binary security']}


if __name__ == '__main__':
    result = inspect()
    REPORT.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(result, ensure_ascii=False, indent=2))
    sys.exit(0 if not result['problems'] else 2)
