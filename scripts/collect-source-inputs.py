"""Collect public exact dependency source inputs, never local credentials.

vcpkg sources have already passed pinned upstream SHA512 verification. Cargo
archives are checked against Cargo.lock; npm archives against lockfile SRI.
No build directories other than the explicit public ImGui source are copied.
"""
import base64, hashlib, json, os, pathlib, re, shutil, tomllib, urllib.parse, urllib.request
ROOT=pathlib.Path(__file__).resolve().parent.parent
OUT=ROOT/'build/source-inputs'
def main():
    OUT.mkdir(exist_ok=True);records=[]
    def record(source,target,kind):
        target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,target)
        records.append({'path':str(target.relative_to(OUT)).replace('\\','/'),'kind':kind,'sha256':hashlib.sha256(target.read_bytes()).hexdigest()})
    downloads=ROOT/'vendor/vcpkg/downloads'
    names=['bzip2-1.0.8.tar.gz','ffmpeg-ffmpeg-n8.1.2.tar.gz','freetype-freetype-VER-2-15-0.tar.gz','google-brotli-v1.2.1.tar.gz','libimobiledevice-libplist-2.8.0.tar.gz','libsdl-org-SDL-release-2.32.10.tar.gz','libsdl-org-SDL_ttf-release-2.24.0.tar.gz','madler-zlib-v1.3.2.tar.gz','pnggroup-libpng-v1.6.59.tar.gz','openssl-openssl-openssl-3.6.5.tar.gz']
    for name in names:
        source=downloads/name
        if not source.is_file():raise RuntimeError('Missing pinned native source: '+name)
        record(source,OUT/'native'/name,'vcpkg downloaded upstream source; pinned port verification')
    record(downloads/'FFmpeg-nv-codec-headers-n13.1.15.0.tar.gz',OUT/'native/FFmpeg-nv-codec-headers-n13.1.15.0.tar.gz','pinned FFmpeg GPU interface headers source')
    maven=OUT/'maven';maven.mkdir(exist_ok=True)
    sourcejar=maven/'zxing-core-3.5.4-sources.jar'
    sourceurl='https://repo.maven.apache.org/maven2/com/google/zxing/core/3.5.4/core-3.5.4-sources.jar'
    # Maven Central publishes SHA1 for this artifact, not SHA512. Pin the
    # SHA256 of the official source JAR verified against that published digest.
    expected='a611e3b63b661aeb2a81b8b4f4bde2daace1e2976adbb37917a674a0019c8fac'
    if sourcejar.exists():data=sourcejar.read_bytes()
    else:
        with urllib.request.urlopen(sourceurl,timeout=30) as response:data=response.read(4*1024*1024+1)
    if len(data)>4*1024*1024 or hashlib.sha256(data).hexdigest()!=expected:raise RuntimeError('ZXing sources integrity mismatch')
    sourcejar.write_bytes(data);records.append({'path':'maven/'+sourcejar.name,'kind':'official Maven Central ZXing3.5.4 source JAR, pinned SHA256 verified','sha256':expected})
    cache=pathlib.Path(os.environ.get('CARGO_HOME',pathlib.Path.home()/'.cargo'))/'registry/cache'
    for package in tomllib.loads((ROOT/'src-tauri/Cargo.lock').read_text())['package']:
        if 'checksum' not in package:continue
        name=package['name']+'-'+package['version']+'.crate'
        candidates=list(cache.glob('*/'+name))
        if not candidates:continue # non-Windows lockfile targets need not be cached
        source=candidates[0]
        if hashlib.sha256(source.read_bytes()).hexdigest()!=package['checksum']:raise RuntimeError('Cargo integrity mismatch: '+name)
        record(source,OUT/'cargo'/name,'Cargo.lock SHA256 verified registry source')
    for path,package in json.loads((ROOT/'package-lock.json').read_text())['packages'].items():
        if not path or package.get('dev') or not package.get('resolved'):continue
        url=package['resolved'];parsed=urllib.parse.urlparse(url)
        if parsed.scheme!='https' or parsed.hostname!='registry.npmjs.org':raise RuntimeError('Unexpected npm source host')
        name=path.rsplit('node_modules/',1)[-1].replace('/','-').replace('@','')+'-'+package['version']+'.tgz'
        target=OUT/'npm'/name;target.parent.mkdir(exist_ok=True)
        if target.exists():data=target.read_bytes()
        else:
            with urllib.request.urlopen(url,timeout=30) as response:data=response.read(32*1024*1024+1)
        if len(data)>32*1024*1024:raise RuntimeError('Source archive too large')
        algorithm,expected=package['integrity'].split('-',1)
        if algorithm not in ('sha512','sha256','sha1') or base64.b64encode(hashlib.new(algorithm,data).digest()).decode()!=expected:raise RuntimeError('npm integrity mismatch: '+name)
        target.write_bytes(data);records.append({'path':str(target.relative_to(OUT)).replace('\\','/'),'kind':'npm lockfile SRI verified source package','sha256':hashlib.sha256(data).hexdigest()})
    imgui=ROOT/'build/airplay/_deps/imgui-src'
    for source in imgui.rglob('*'):
        if source.is_file() and '.git' not in source.relative_to(imgui).parts:record(source,OUT/'imgui'/source.relative_to(imgui),'pinned CMake ImGui source')
    unique={}
    for row in records:
        if row['path'] in unique and unique[row['path']]['sha256']!=row['sha256']:raise RuntimeError('Conflicting source package path')
        unique[row['path']]=row
    records=list(unique.values())
    (OUT/'SOURCE_INPUTS.json').write_text(json.dumps({'nativeRegistryCommit':'afa249f12f52ed8a3b919f195495ba8b330288d1','files':records},indent=2))
    print('PASS public dependency source inputs:',len(records),'files; no signing/runtime state directories copied')
if __name__=='__main__':main()
