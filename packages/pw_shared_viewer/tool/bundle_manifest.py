#!/usr/bin/env python3
"""Content identity for offline shared renderer assets; no dependency resolution."""
import argparse
import hashlib
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent / 'web'
target = root / 'BUNDLE_MANIFEST.json'
manifest = json.loads(target.read_text())
files = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
         for p in sorted(root.rglob('*')) if p.is_file() and p != target}
manifest['files'] = files
manifest['bundle_sha256'] = hashlib.sha256(json.dumps(files, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
encoded = json.dumps(manifest, indent=2) + '\n'
if args.check:
    if target.read_text() != encoded:
        raise SystemExit('FAIL: renderer resources differ from bundle manifest')
else:
    target.write_text(encoded)
print(json.dumps({'bundle_sha256': manifest['bundle_sha256'], 'resources': len(files)}))
