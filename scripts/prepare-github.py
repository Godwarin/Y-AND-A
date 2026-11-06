"""Prepare an explicit, scanned source snapshot. No git/network/build execution."""
from pathlib import Path
import argparse
import hashlib
import json
import re

ROOT=Path(__file__).resolve().parent.parent
OUTPUT=ROOT/'publish/github'
MANIFEST=ROOT/'publish/github-manifest.json'
DIRECTORIES=['.cargo','config','licenses','android-app','native','public','src','src-tauri/src','src-tauri/capabilities','src-tauri/icons','scripts','tests','vendor/airplay-windows','vendor/42-animation-kit','.github']
ROOT_FILES=['AGENTS.md','CODEX_PROMPT.md','README.md','CONTRIBUTING.md','SECURITY.md','LICENSE','THIRD_PARTY_NOTICES.md','package.json','package-lock.json','tsconfig.json','vite.config.ts','vitest.config.ts','playwright.config.ts','eslint.config.js','.gitignore','.prettierignore','index.html','requirements-tests.txt','src-tauri/Cargo.toml','src-tauri/Cargo.lock','src-tauri/build.rs','src-tauri/tauri.conf.json','toolchain/node-version.txt','toolchain/vcpkg-baseline.txt','ЗАПУСТИТЬ Y AND A.cmd']
DOCS=['SECURITY_REMEDIATION_2026-11-05.md','GITHUB_FIRST_STEPS.md','RELEASE_NOTES_BETA_0.42.md','SECURITY_VALIDATION_BETA_0.42.md','BINARY_RELEASE_CHECK.md','ARCHITECTURE.md','BUILD_FROM_SOURCE.md','CHANGELOG.md','CURATOR_HANDOFF.md','DEVICE_VALIDATION.md','PRIVACY.md','RELEASES.md','RELEASE_PUBLIC_KEY.txt','SECURITY_AUDIT.md','SECURITY_FOLLOWUP_2026-11-04.md','SECURITY_RELEASE_REVIEW.md','TEST_RESULTS.md','USER_GUIDE.md','ISOLATED_STAND_PLAN.md','airplay-yanda.patch','CLOSED_BETA.md','ANDROID_COMPANION.md']
EVIDENCE=['beta-0.42-defender-final.json','project-cleanup-2026-11-05.json','beta-0.42-lightweight.json','beta-0.42-signature-negative.json','beta-0.42-apk-negative.json','beta-0.42-source-structure.json','beta-0.42-powershell-syntax.json','beta-0.42-static-followup.json','beta-0.42-defender.json','beta-0.42-apk-publication-review.json','beta-0.42-binary-inspection.json','beta-0.42-dependency-osv-current.json','native-smoke.json','android-apk.json','android-protocol.json','security-candidate.json','native-runtime-inventory.json','npm-audit-all.json','npm-audit-production.json','dependency-osv.json','beta-0.42-owner-validation.json','artifact-relocation.json','isolated-security-validation.json','release-components.json','owner-release-confirmations.json']
CLEAN_DOCS=['ARCHITECTURE.md','BINARY_RELEASE_CHECK.md','BUILD_FROM_SOURCE.md','CHANGELOG.md','DEVICE_TEST_0.42a.md','PRIVACY.md','RELEASE_PUBLIC_KEY.txt','RELEASES.md','SECURITY_REVIEW_0.42a.md','TEST_RESULTS.md','USER_GUIDE.md','airplay-yanda.patch']
LOCAL_ONLY={'AGENTS.md','CODEX_PROMPT.md','ЗАПУСТИТЬ Y AND A.cmd','scripts/backup-android-signing.ps1','scripts/signing-backup-crypto.ps1','scripts/test-signing-backup.ps1','scripts/protect-build-workspace.ps1'}
LOCAL_NOTES_MARKER='<!-- local-maintainer-notes -->'
PRIVATE_NAME=re.compile(r'(^|/)(\.local|\.git|\.ssh|\.aws|archive|build|downloads|node_modules|publish|release)(/|$)|\.(p12|jks|pfx|p8|key|keytab|kdbx|dpapi|yanda-backup|keystore)$|(^|/)(adbkey(?:\.pub)?|local-password\.txt|\.env(?:\..*)?)$',re.I)
SECRET=re.compile(rb'-----BEGIN (?:RSA |DSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----|PuTTY-User-Key-File-[23]:|\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|sk-proj-[A-Za-z0-9_-]{30,}|(?:AKIA|ASIA)[A-Z0-9]{16}|AIza[A-Za-z0-9_-]{35}|xox[baprs]-[A-Za-z0-9-]{20,})\b')

def digest(path):
    with path.open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()

def safe(path):
    stat=path.lstat()
    if path.resolve()!=path.absolute() or not path.is_relative_to(ROOT) or stat.st_file_attributes&0x400 or stat.st_nlink!=1:raise RuntimeError('Unsafe source/output entry')

def main(artifact_version=None, clean=False):
    if clean and artifact_version != '0.42a':
        raise ValueError('Clean snapshot requires artifact version 0.42a')
    suffix='-clean' if clean else ''
    output=ROOT/'publish'/f'github-{artifact_version}{suffix}' if artifact_version else OUTPUT
    manifest_path=ROOT/'publish'/f'github-{artifact_version}{suffix}-manifest.json' if artifact_version else MANIFEST
    if output.resolve()!=output.absolute() or not output.absolute().is_relative_to(ROOT/'publish'):
        raise RuntimeError('Snapshot output must be an ordinary workspace directory')
    rows={}
    def add(path):
        name=path.relative_to(ROOT).as_posix()
        if clean and name in LOCAL_ONLY:return
        safe(path)
        if PRIVATE_NAME.search(name):raise RuntimeError('Private source name refused: '+name)
        if path.stat().st_size>4*1024*1024:raise RuntimeError('Unexpected large source file: '+name)
        if path.suffix.lower() in {'.exe','.dll','.pdb','.obj','.lib','.zip','.tgz','.crate','.pyc'}:return
        rows[name]=path
    for name in DIRECTORIES:
        folder=ROOT/name
        if not folder.exists():continue
        for p in folder.rglob('*'):
            if any(part in {'.git','__pycache__'} for part in p.relative_to(folder).parts):continue
            if p.is_file():add(p)
    for name in ROOT_FILES:add(ROOT/name)
    for name in CLEAN_DOCS if clean else [*DOCS, 'SECURITY_REVIEW_0.42a.md', 'DEVICE_TEST_0.42a.md']:
        add(ROOT/'docs'/name)
    if not clean:
        for name in EVIDENCE:add(ROOT/'docs/evidence'/name)
        for name in ('local-build','owner-validation','isolated-validation'):
            add(ROOT/'docs/evidence'/f'0.42a-{name}.json')
    # Internal handoff history and disposable-machine experiments stay local.
    prepared=[];sanitized=[]
    for name,source in sorted(rows.items()):
        data=source.read_bytes()
        if source.suffix.lower()=='.md':
            text=data.decode('utf-8-sig')
            if clean and LOCAL_NOTES_MARKER in text:
                text=text.split(LOCAL_NOTES_MARKER,1)[0].rstrip()+'\n'
            for spelling in (str(ROOT), ROOT.as_posix()):
                text=text.replace(spelling,'<workspace>')
            text=re.sub(r'(?i)\b[A-Z]:[\\/]Users[\\/][^\\/\s\x22<>]+','<user-profile>',text)
            text=re.sub(r'(?i)\b[A-Z]:[\\/]virtualka\b','<VirtualBox-installation>',text)
            data=text.encode('utf-8')
            if data!=source.read_bytes():sanitized.append(name)
        if SECRET.search(data):raise RuntimeError('Secret-like content; review required: '+name)
        prepared.append((name,source,data))
    # Clean only our prior unmodified generated snapshot, never a checkout or edits.
    if output.exists() and any(output.iterdir()):
        if (output/'.git').exists():raise RuntimeError('Refusing to replace a Git checkout')
        prior=json.loads(manifest_path.read_text(encoding='utf-8'))
        expected={v['path']:v['sha256'] for v in prior['files']}
        actual={p.relative_to(output).as_posix():p for p in output.rglob('*') if p.is_file()}
        if set(expected)!=set(actual):raise RuntimeError('Snapshot contains unrecognized files; preserving it')
        for name,p in actual.items():
            safe(p)
            if digest(p)!=expected[name]:raise RuntimeError('Snapshot edited; preserving it')
        for p in actual.values():p.unlink()
    output.mkdir(parents=True,exist_ok=True)
    records=[]
    for name,source,data in prepared:
        target=output/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
        records.append({'path':name,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'sourceSha256':digest(source),'binary':b'\0' in data})
    fingerprint=hashlib.sha256(('\n'.join(v['path']+' '+v['sha256'] for v in records)).encode()).hexdigest()
    report={'status':'PASS_SOURCE_ALLOWLIST_AND_BOUNDED_SECRET_SCAN','output':output.relative_to(ROOT).as_posix(),'artifactVersion':artifact_version,'files':records,'sanitizedDocumentation':sanitized,'snapshotSha256':fingerprint,'applicationExecuted':False,'networkUsed':False,'pushed':False,'scope':'Private GitHub source preparation','binarySecurityValidation':'NOT_ASSESSED_BY_SOURCE_CHECK','secretScanLimit':'Known filenames/private PEM/PAT/API token patterns; not proof of absence of every possible secret'}
    if clean:report['profile']='CLEAN_GITHUB'
    manifest_path.write_text(json.dumps(report,indent=2),encoding='utf-8')
    print('PASS clean source snapshot:',len(records),'files,',sum(v['bytes'] for v in records),'bytes; no keys/backups/generated runtime; no upload')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--artifact-version',choices=('0.42a',))
    parser.add_argument('--clean',action='store_true')
    args=parser.parse_args()
    main(args.artifact_version,args.clean)
