"""Collect public exact dependency source inputs, never local credentials.

vcpkg archives are rechecked against pinned upstream SHA512 values. Cargo
archives are checked against Cargo.lock; npm archives against lockfile SRI.
No build directories other than the explicit public ImGui source are copied.
"""
import argparse, base64, hashlib, json, os, pathlib, re, tomllib, urllib.parse, urllib.request
ROOT=pathlib.Path(__file__).resolve().parent.parent
LEGACY_INPUTS=ROOT/'build/source-inputs'
def main(artifact_version=None):
    offline=artifact_version is not None
    OUT=ROOT/'build'/f'source-inputs-{artifact_version}' if offline else LEGACY_INPUTS
    if OUT.resolve()!=OUT.absolute():
        raise RuntimeError('Unsafe dependency output directory')
    OUT.mkdir(exist_ok=True);records=[]
    def record(source,target,kind,*,expected=None,algorithm='sha256'):
        if source.resolve()!=source.absolute() or not source.is_file() or source.stat().st_nlink!=1:
            raise RuntimeError('Unsafe dependency source: '+source.name)
        if target.resolve()!=target.absolute() or (target.exists() and target.stat().st_nlink!=1):
            raise RuntimeError('Unsafe dependency output: '+target.name)
        with source.open('rb') as stream:
            data=stream.read(64*1024*1024+1)
        if len(data)>64*1024*1024 or (expected and hashlib.new(algorithm,data).hexdigest()!=expected):
            raise RuntimeError('Pinned dependency digest or size mismatch: '+source.name)
        target.parent.mkdir(parents=True,exist_ok=True)
        target.write_bytes(data)
        records.append({'path':str(target.relative_to(OUT)).replace('\\','/'),'kind':kind,'sha256':hashlib.sha256(data).hexdigest()})
    downloads=LEGACY_INPUTS/'native' if offline else ROOT/'vendor/vcpkg/downloads'
    native=json.loads((ROOT/'config/native-source-digests.json').read_text(encoding='utf-8'))
    for name,digest in native['sha512'].items():
        record(downloads/name,OUT/'native'/name,'vcpkg pinned upstream SHA512 verified source',expected=digest,algorithm='sha512')
    maven=OUT/'maven';maven.mkdir(exist_ok=True)
    sourcejar=maven/'zxing-core-3.5.4-sources.jar'
    sourceurl='https://repo.maven.apache.org/maven2/com/google/zxing/core/3.5.4/core-3.5.4-sources.jar'
    # Maven Central publishes SHA1 for this artifact, not SHA512. Pin the
    # SHA256 of the official source JAR verified against that published digest.
    expected='a611e3b63b661aeb2a81b8b4f4bde2daace1e2976adbb37917a674a0019c8fac'
    if offline:
        record(LEGACY_INPUTS/'maven'/sourcejar.name,sourcejar,'official Maven Central ZXing3.5.4 source JAR, pinned SHA256 verified',expected=expected)
    elif sourcejar.exists():data=sourcejar.read_bytes()
    else:
        with urllib.request.urlopen(sourceurl,timeout=30) as response:data=response.read(4*1024*1024+1)
    if not offline:
        if len(data)>4*1024*1024 or hashlib.sha256(data).hexdigest()!=expected:raise RuntimeError('ZXing sources integrity mismatch')
        sourcejar.write_bytes(data);records.append({'path':'maven/'+sourcejar.name,'kind':'official Maven Central ZXing3.5.4 source JAR, pinned SHA256 verified','sha256':expected})
    cache=LEGACY_INPUTS/'cargo' if offline else pathlib.Path(os.environ.get('CARGO_HOME',pathlib.Path.home()/'.cargo'))/'registry/cache'
    for package in tomllib.loads((ROOT/'src-tauri/Cargo.lock').read_text())['package']:
        if 'checksum' not in package:continue
        name=package['name']+'-'+package['version']+'.crate'
        candidates=list(cache.glob(name if offline else '*/'+name))
        if not candidates:continue # non-Windows lockfile targets need not be cached
        source=candidates[0]
        record(source,OUT/'cargo'/name,'Cargo.lock SHA256 verified registry source',expected=package['checksum'])
    for path,package in json.loads((ROOT/'package-lock.json').read_text())['packages'].items():
        if not path or package.get('dev') or not package.get('resolved'):continue
        url=package['resolved'];parsed=urllib.parse.urlparse(url)
        if parsed.scheme!='https' or parsed.hostname!='registry.npmjs.org':raise RuntimeError('Unexpected npm source host')
        name=path.rsplit('node_modules/',1)[-1].replace('/','-').replace('@','')+'-'+package['version']+'.tgz'
        target=OUT/'npm'/name;target.parent.mkdir(exist_ok=True)
        if offline:
            source=LEGACY_INPUTS/'npm'/name
            if source.resolve()!=source.absolute() or not source.is_file() or source.stat().st_nlink!=1 or source.stat().st_size>32*1024*1024:
                raise RuntimeError('Missing or unsafe cached npm source: '+name)
            data=source.read_bytes()
        elif target.exists():data=target.read_bytes()
        else:
            with urllib.request.urlopen(url,timeout=30) as response:data=response.read(32*1024*1024+1)
        if len(data)>32*1024*1024:raise RuntimeError('Source archive too large')
        algorithm,expected=package['integrity'].split('-',1)
        if algorithm not in ('sha512','sha256','sha1') or base64.b64encode(hashlib.new(algorithm,data).digest()).decode()!=expected:raise RuntimeError('npm integrity mismatch: '+name)
        if target.resolve()!=target.absolute() or (target.exists() and target.stat().st_nlink!=1):
            raise RuntimeError('Unsafe npm output: '+name)
        target.write_bytes(data);records.append({'path':str(target.relative_to(OUT)).replace('\\','/'),'kind':'npm lockfile SRI verified source package','sha256':hashlib.sha256(data).hexdigest()})
    imgui=ROOT/'build/airplay/_deps/imgui-pinned-src'
    imgui_manifest=json.loads((ROOT/'vendor/airplay-windows/cmake/imgui-source.json').read_text(encoding='utf-8'))
    for name,digest in imgui_manifest['files'].items():
        record(imgui/name,OUT/'imgui'/name,'pinned ImGui SHA256 verified source',expected=digest)
    unique={}
    for row in records:
        if row['path'] in unique and unique[row['path']]['sha256']!=row['sha256']:raise RuntimeError('Conflicting source package path')
        unique[row['path']]=row
    records=list(unique.values())
    (OUT/'SOURCE_INPUTS.json').write_text(json.dumps({'nativeRegistryCommit':native['vcpkgCommit'],'imguiCommit':imgui_manifest['commit'],'files':records},indent=2))
    print('PASS public dependency source inputs:',len(records),'files; no signing/runtime state directories copied')
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--artifact-version',choices=('0.42a',),help='Prepare a separate versioned input set offline')
    main(parser.parse_args().artifact_version)
