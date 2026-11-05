"""Fetch exact official vcpkg FFmpeg 8.1.2#3 overlay, verifying every Git blob.

Allows a shallow vcpkg checkout to use the maintained 8.1 ABI branch instead
of silently upgrading to FFmpeg 9. Downloaded upstream tarball SHA512 is then
verified by this official port during vcpkg build.
"""
import base64, hashlib, json, pathlib, urllib.request
ROOT=pathlib.Path(__file__).resolve().parent.parent
TREE='c40aaa40e075d25ef1e812daa7333778890b6b0d'
DEST=ROOT/'native/media-ports/ffmpeg'
def get(url):
    request=urllib.request.Request(url,headers={'User-Agent':'YANDA-release-build','Accept':'application/vnd.github+json'})
    with urllib.request.urlopen(request,timeout=30) as response:return json.load(response)
def main():
    data=get(f'https://api.github.com/repos/microsoft/vcpkg/git/trees/{TREE}?recursive=1')
    assert not data.get('truncated')
    records=[]
    for entry in data['tree']:
        if entry['type']!='blob':continue
        name=pathlib.PurePosixPath(entry['path'])
        assert not name.is_absolute() and '..' not in name.parts
        target=DEST.joinpath(*name.parts)
        content=target.read_bytes() if target.exists() else b''
        digest=lambda b:hashlib.sha1(b'blob '+str(len(b)).encode()+b'\0'+b).hexdigest()
        if digest(content)!=entry['sha']:
            blob=get(entry['url']);content=base64.b64decode(blob['content'])
        assert digest(content)==entry['sha']
        target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(content)
        records.append({'path':entry['path'],'gitBlob':entry['sha'],'sha256':hashlib.sha256(content).hexdigest()})
    (DEST.parent/'ffmpeg-provenance.json').write_text(json.dumps({'upstream':'https://github.com/microsoft/vcpkg','gitTree':TREE,'files':records},indent=2))
    print('PASS official FFmpeg 8.1.2#3 overlay:',len(records),'verified files')
if __name__=='__main__':main()
