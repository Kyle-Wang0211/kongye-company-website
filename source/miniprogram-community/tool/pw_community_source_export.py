"""Export the shared community source to a new derived tree, or check its identity.

Example: python3 tool/pw_community_source_export.py --destination /tmp/community
Append --check to verify the manifest, source bytes and complete output file set.
The Git working tree is read only. Ignored files are never included.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import subprocess
import sys


MANIFEST = 'COMMUNITY_SOURCE_MANIFEST.json'
EXACT_FILES = frozenset({
    'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', 'l10n.yaml',
    'tool/pw_community_source_export.py', 'tool/pw_community_web_build.py',
    'tool/community_build_features.py', 'tool/community_features.json',
    'tool/pw_release_regional_defines.py', 'tool/pw_release_legacy_import_defines.py',
    'ios/Vendor/Zpaq/Zpaq-LICENSE.txt',
})
TREE_PREFIXES = (
    'web/', 'assets/', 'packages/pw_shared_viewer/',
    'vendor/generated_avatar/licenses/', 'vendor/cloud_library/licenses/',
    'vendor/lepton_jpeg/licenses/', 'third_party/libphonenumber/',
    'ios/Vendor/JXL/licenses/', 'ios/Vendor/NativeCore/licenses/',
)
LOCAL_PACKAGES = ('aether_capture_services', 'official_capture_services', 'pw_hevc')
EXCLUDED_PARTS = frozenset({
    '.git', '.dart_tool', 'node_modules', '__pycache__', '.pub-cache', '.pub',
    'artifacts', 'experiments', 'private', 'secrets', 'credentials',
})
EXCLUDED_SUFFIXES = ('.log', '.pyc', '.pem', '.key', '.p12', '.pfx', '.keystore')


def safe_path(path):
    parts = PurePosixPath(path).parts
    if (not path or path.startswith('/') or '\\' in path or
            any(ord(char) < 32 for char in path) or
            any(part in ('', '.', '..') for part in path.split('/')) or not parts):
        raise ValueError('Unsafe relative path')
    return parts


def selected(path):
    parts = safe_path(path)
    lowered = [part.lower() for part in parts]
    if (any(part in EXCLUDED_PARTS or part.startswith('.env') for part in lowered)
            or path.lower().endswith(EXCLUDED_SUFFIXES)):
        return False
    # Three.js's audited browser runtime lives in a directory named build.
    if 'build' in lowered and not path.startswith(
            'packages/pw_shared_viewer/web/vendor/three/build/'):
        return False
    if path in EXACT_FILES or path.startswith(TREE_PREFIXES):
        return True
    if path.startswith('lib/') and Path(path).suffix in ('.dart', '.arb'):
        return True
    return any(
        path in (f'packages/{name}/pubspec.yaml', f'packages/{name}/pubspec.lock')
        or path.startswith(f'packages/{name}/lib/')
        for name in LOCAL_PACKAGES
    )


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args])


def regular_file(root, relative):
    current = root
    for part in safe_path(relative):
        current = current / part
        if current.is_symlink():
            raise ValueError(f'Symlink is forbidden: {relative}')
    if not current.is_file():
        raise ValueError(f'Missing regular file: {relative}')
    return current


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            result.update(block)
    return result.hexdigest()


def manifest(root):
    root = root.resolve()
    top = Path(os.fsdecode(git(root, 'rev-parse', '--show-toplevel')).strip()).resolve()
    if top != root:
        raise ValueError('Source must be the Git working-tree root')
    names = {
        os.fsdecode(name)
        for name in git(root, 'ls-files', '--cached', '--others', '--exclude-standard', '-z').split(b'\0')
        if name
    }
    files = []
    for name in sorted(names):
        if selected(name):
            source = regular_file(root, name)
            files.append({'path': name, 'sha256': digest(source), 'size': source.stat().st_size})
    if not files:
        raise ValueError('No exportable source files')
    return {
        'schema': 'pw.community-source-export.v1',
        'source_revision': git(root, 'rev-parse', 'HEAD').decode('ascii').strip(),
        'policy': {
            'exact_files': sorted(EXACT_FILES),
            'tree_prefixes': list(TREE_PREFIXES),
            'shared_lib_suffixes': ['.dart', '.arb'],
            'local_packages_pubspec_and_lib': list(LOCAL_PACKAGES),
            'excluded_parts': sorted(EXCLUDED_PARTS),
            'excluded_suffixes': list(EXCLUDED_SUFFIXES),
            'build_exception': 'packages/pw_shared_viewer/web/vendor/three/build/',
        },
        'files': files,
    }


def encoded(value):
    return (json.dumps(value, ensure_ascii=True, indent=2, sort_keys=True) + '\n').encode('utf-8')


def validate_destination(root, destination):
    # Refuse either direction of overlap, including paths redirected by symlinks.
    resolved = destination.resolve()
    if resolved.is_relative_to(root) or root.is_relative_to(resolved):
        raise ValueError('Source and destination must be disjoint')
    if destination.is_symlink():
        raise ValueError('Destination must not be a symlink')


def output_files(destination):
    result = set()
    for directory, directories, filenames in os.walk(destination, followlinks=False):
        for name in directories + filenames:
            path = Path(directory) / name
            if path.is_symlink():
                raise ValueError('Export contains a symlink')
        for name in filenames:
            path = Path(directory) / name
            relative = path.relative_to(destination).as_posix()
            regular_file(destination, relative)
            result.add(relative)
    return result


def check(root, destination, expected=None):
    root = root.resolve()
    validate_destination(root, destination)
    expected = expected if expected is not None else manifest(root)
    if not destination.is_dir():
        raise ValueError('Export directory does not exist')
    expected_names = {entry['path'] for entry in expected['files']} | {MANIFEST}
    if output_files(destination) != expected_names:
        raise ValueError('Export file set differs (missing or additional files)')
    if regular_file(destination, MANIFEST).read_bytes() != encoded(expected):
        raise ValueError('Export manifest differs from the source manifest')
    for entry in expected['files']:
        target = regular_file(destination, entry['path'])
        if target.stat().st_size != entry['size'] or digest(target) != entry['sha256']:
            raise ValueError(f"Export bytes differ: {entry['path']}")
    return expected


def export(root, destination):
    root = root.resolve()
    validate_destination(root, destination)
    if destination.exists():
        raise ValueError('Export requires a new output directory')
    expected = manifest(root)
    destination.mkdir()  # Exclusive creation also rejects a concurrent export.
    for entry in expected['files']:
        source = regular_file(root, entry['path'])
        target = destination / entry['path']
        target.parent.mkdir(parents=True, exist_ok=True)
        with source.open('rb') as incoming, target.open('xb') as outgoing:
            for block in iter(lambda: incoming.read(1024 * 1024), b''):
                outgoing.write(block)
    # Refuse to certify a working tree that changed during copying.
    if manifest(root) != expected:
        raise ValueError('Source changed during export; incomplete output retained')
    with (destination / MANIFEST).open('xb') as output:
        output.write(encoded(expected))
    return check(root, destination, expected)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root', '--source', type=Path,
                        default=Path(__file__).resolve().parent.parent)
    parser.add_argument('--destination', '--output', type=Path, required=True)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    root = args.source_root.resolve()
    destination = args.destination.absolute()
    try:
        result = check(root, destination) if args.check else export(root, destination)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'Export failed: {error}\n')
    print(json.dumps({'status': 'checked' if args.check else 'exported',
                      'file_count': len(result['files']),
                      'manifest_sha256': hashlib.sha256(encoded(result)).hexdigest()}))


if __name__ == '__main__':
    main()
