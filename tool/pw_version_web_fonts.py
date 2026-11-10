"""Give Flutter's subset fonts immutable content names in FontManifest.json.

Keep original asset paths for older clients. Only the manifest and additional
font copies change; compiled code, viewer assets and dependencies stay intact.
"""
from pathlib import Path, PurePosixPath
import hashlib
import json
import re
import shutil


def version_font_assets(site):
    site = Path(site)
    assets = site / 'assets'
    manifest = assets / 'FontManifest.json'
    rows = json.loads(manifest.read_text())
    changes = []
    for family in rows:
        for font in family['fonts']:
            rel = PurePosixPath(font['asset'])
            if rel.is_absolute() or '..' in rel.parts or rel.suffix not in {'.otf', '.ttf', '.woff', '.woff2'}:
                raise ValueError('Unsafe font asset path')
            path = assets.joinpath(*rel.parts)
            if not path.is_file() or any(p.is_symlink() for p in [path, *path.parents] if p != site.parent):
                raise ValueError('Font asset must be a regular local file')
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            stem = re.sub(r'\.[a-f0-9]{16}$', '', rel.stem)
            target = rel.with_name(stem + '.' + digest[:16] + rel.suffix)
            dest = assets.joinpath(*target.parts)
            if dest.exists():
                if dest.is_symlink() or dest.read_bytes() != path.read_bytes():
                    raise ValueError('Versioned font identity conflict')
            else:
                shutil.copyfile(path, dest)
            font['asset'] = target.as_posix()
            changes.append({'original': rel.as_posix(), 'asset': target.as_posix(), 'sha256': digest})
    manifest.write_text(json.dumps(rows, separators=(',', ':')) + '\n')
    return changes


if __name__ == '__main__':
    import sys
    print(json.dumps(version_font_assets(sys.argv[1]), indent=2))
