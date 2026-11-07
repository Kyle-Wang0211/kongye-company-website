#!/usr/bin/env python3
"""Stage website loading glue and verify every release artifact byte, offline."""
import argparse
import hashlib
import json
import re
from pathlib import Path


def file_hashes(root):
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(root.rglob('*')) if p.is_file() and p != root / 'BUNDLE_MANIFEST.json'}


def verify(root):
    manifest = json.loads((root / 'BUNDLE_MANIFEST.json').read_text())
    files = file_hashes(root)
    identity = hashlib.sha256(json.dumps(files, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    if (manifest.get('schema') != 'PW_SHARED_VIEWER_BUNDLE_V1' or
            manifest.get('engine') != 'three' or manifest.get('engine_version') != '0.186.1' or
            manifest.get('upstream_commit') != '9b4a2ac29c63ccb43fd51c5661f2f873ac2c39b8' or
            manifest.get('files') != files or manifest.get('bundle_sha256') != identity):
        raise ValueError('Browser release artifact differs from manifest')
    return manifest


def browser_html(source):
    replacements = {
        'import { verifyLocalBundle }': 'import { readReleaseIdentity }',
        'pwSharedViewerReady = verifyLocalBundle()': 'pwSharedViewerReady = readReleaseIdentity()',
        "bundleIdentityScope: 'runtime-bundle', runtimeBundleBytesVerified: true":
            "bundleIdentityScope: 'release-manifest', runtimeBundleBytesVerified: false",
    }
    for old, new in replacements.items():
        if source.count(old) != 1:
            raise ValueError('Expected default viewer startup declaration is missing or ambiguous')
        source = source.replace(old, new)
    source, count = re.subn(r"import \{ create \} from './viewer\.mjs(?:\?[^']*)?';",
                            "import { create } from './viewer.mjs?v=web-release-startup-20261107-v1';", source)
    if count != 1:
        raise ValueError('Expected viewer module import is missing or ambiguous')
    return source.replace("from './bundle_identity.mjs';",
                          "from './bundle_identity.mjs?v=web-release-startup-20261107-v1';")


def stage(root):
    manifest = verify(root)
    entry = root / 'index.html'
    entry.write_text(browser_html(entry.read_text()))
    manifest['files'] = file_hashes(root)
    manifest['bundle_sha256'] = hashlib.sha256(json.dumps(manifest['files'], sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    (root / 'BUNDLE_MANIFEST.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return verify(root)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stage', action='store_true')
    parser.add_argument('root', type=Path)
    args = parser.parse_args()
    manifest = stage(args.root) if args.stage else verify(args.root)
    if "bundleIdentityScope: 'release-manifest', runtimeBundleBytesVerified: false" not in (args.root / 'index.html').read_text():
        raise ValueError('Expected website release identity declaration is missing')
    print(json.dumps({'bundle_sha256': manifest['bundle_sha256'], 'resources':len(manifest['files']), 'artifact_bytes_verified':True, 'runtime_bytes_verified':False}))


if __name__ == '__main__':
    main()
