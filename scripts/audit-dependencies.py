"""Read-only version inventory and OSV checks. Sends only public names/versions.

No source code, credentials, signing files or media are uploaded. Unknown OSV
coverage and network failures are reported separately from zero advisories.
"""
import argparse
import datetime
import hashlib
import json
import pathlib
import tomllib
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / 'docs/security-evidence'

def inventory():
    items = {}
    cargo = tomllib.loads((ROOT / 'src-tauri/Cargo.lock').read_text())
    for p in cargo['package']:
        if p.get('source', '').startswith('registry+'):
            items[('crates.io', p['name'], p['version'])] = {'ecosystem': 'crates.io', 'name': p['name'], 'version': p['version']}
    lock = json.loads((ROOT / 'package-lock.json').read_text())
    for path, p in lock['packages'].items():
        if not path or 'version' not in p:
            continue
        name = p.get('name') or path.rsplit('node_modules/', 1)[-1]
        key = ('npm', name, p['version'])
        item = items.setdefault(key, {'ecosystem': 'npm', 'name': name, 'version': p['version'], 'devOnly': True})
        item['devOnly'] = item['devOnly'] and bool(p.get('dev', False))
    items[('Maven', 'com.google.zxing:core', '3.5.4')] = {'ecosystem': 'Maven', 'name': 'com.google.zxing:core', 'version': '3.5.4'}
    return list(items.values())

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--query', action='store_true')
    parser.add_argument('--output', default=str(OUT / 'dependency-osv.json'))
    args = parser.parse_args()
    OUT.mkdir(exist_ok=True)
    packages = inventory()
    report = {'date': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'source': 'https://osv.dev / https://api.osv.dev/v1/querybatch',
              'attribution': 'OSV.dev and source databases (RustSec, GitHub Advisory Database); see advisory links for licences.',
              'lockfiles': {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in ['package-lock.json', 'src-tauri/Cargo.lock']},
              'packages': packages, 'status': 'INVENTORY_ONLY', 'advisories': [], 'errors': []}
    if args.query:
        for i in range(0, len(packages), 100):
            batch = packages[i:i+100]
            queries = [{'package': {'ecosystem': p['ecosystem'], 'name': p['name']}, 'version': p['version']} for p in batch]
            try:
                request = urllib.request.Request('https://api.osv.dev/v1/querybatch', data=json.dumps({'queries': queries}).encode(), headers={'Content-Type': 'application/json'})
                with urllib.request.urlopen(request, timeout=35) as response:
                    results = json.load(response)['results']
                if len(results) != len(batch):
                    raise ValueError('Incomplete OSV batch')
                for p, result in zip(batch, results):
                    for v in result.get('vulns', []):
                        report['advisories'].append({'package': p, 'id': v['id'], 'url': 'https://osv.dev/vulnerability/' + v['id'], 'modified': v.get('modified')})
                    if result.get('next_page_token'):
                        report['errors'].append({'package': p, 'reason': 'OSV pagination requires further coverage'})
                print('Queried', min(i+100, len(packages)), '/', len(packages), flush=True)
            except Exception as error:
                report['errors'].append({'offset': i, 'error': str(error)})
                break
        report['status'] = 'PARTIAL' if report['errors'] else 'COMPLETE_KNOWN_ADVISORY_QUERY'
    destination=pathlib.Path(args.output);destination.parent.mkdir(parents=True,exist_ok=True)
    destination.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding='utf-8')
    print(json.dumps({'status': report['status'], 'packages': len(packages), 'advisories': report['advisories'], 'errors': report['errors']}, ensure_ascii=False))

if __name__ == '__main__':
    main()
