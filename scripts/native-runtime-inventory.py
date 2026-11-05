"""Read versions from the exact trusted runtime DLLs; no network or media."""
import ctypes, hashlib, json, os, pathlib
ROOT=pathlib.Path(__file__).resolve().parent.parent
def main():
    result={}
    for name in ['android-yanda','airplay-yanda']:
        folder=ROOT/'runtime'/name
        with os.add_dll_directory(str(folder)):
            avutil=ctypes.CDLL(str(folder/'avutil-60.dll'));avutil.av_version_info.restype=ctypes.c_char_p
            avcodec=ctypes.CDLL(str(folder/'avcodec-62.dll'));avcodec.avcodec_configuration.restype=ctypes.c_char_p
            crypto=ctypes.CDLL(str(folder/'libcrypto-3-x64.dll'));crypto.OpenSSL_version.restype=ctypes.c_char_p
            config=avcodec.avcodec_configuration().decode()
            info={'ffmpeg':avutil.av_version_info().decode(),'openssl':crypto.OpenSSL_version(0).decode(),'gplCodecBuild':'--enable-gpl' in config,
                  'dllSha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in folder.glob('*.dll')}}
            assert info['ffmpeg']=='8.1.2' and info['openssl'].startswith('OpenSSL 3.6.5 ')
            assert not info['gplCodecBuild']
            result[name]=info
    (ROOT/'docs/evidence/native-runtime-inventory.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print('PASS both receiver DLL graphs: FFmpeg8.1.2, OpenSSL3.6.5, LGPL codec configuration; DLL hashes recorded')
if __name__=='__main__':main()
