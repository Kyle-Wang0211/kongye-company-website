"""Build the web entry from the complete shared product source, offline."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from community_build_features import community_defines
from pw_version_web_fonts import version_font_assets
from pw_release_regional_defines import load_config
from pw_community_source_export import encoded, manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--regional-config", required=True)
    parser.add_argument("--export-to", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    config, _ = load_config(args.regional_config)
    config.update(community_defines())
    flutter = shutil.which("flutter")
    if flutter is None:
        raise SystemExit("Pinned Flutter is unavailable")
    sdk = Path(flutter).resolve().parent.parent
    version = json.loads((sdk / "bin/cache/flutter.version.json").read_text())
    if version.get("frameworkRevision") != "6655482ec06e547f90abf8ae7590466f4415978d":
        raise SystemExit("Pinned Flutter revision differs")
    if args.export_to and args.export_to.exists():
        raise SystemExit("Export requires a new output directory")
    source = manifest(root)

    graph_path = root / ".dart_tool/package_graph.json"
    original_graph = graph_path.read_bytes()
    graph = json.loads(original_graph)
    for package in graph["packages"]:
        if package["name"] == "pocketworld_flutter":
            # Reuse the existing web asset recipe. This unused mobile shader
            # package cannot compile to SkSL on the pinned browser backend.
            package["dependencies"] = [
                name for name in package["dependencies"] if name != "liquid_glass_renderer"
            ]
    descriptor, filename = tempfile.mkstemp(prefix="pw-community-public-defines-", suffix=".json")
    try:
        with os.fdopen(descriptor, "w") as output:
            json.dump(config, output)
        graph_path.write_text(json.dumps(graph, indent=2) + "\n")
        result = subprocess.run(
            [flutter, "build", "web", "--release", "--no-pub",
             "--target", "lib/main_community_web.dart", "--base-href", "/community/",
             "--dart-define-from-file=" + filename],
            cwd=root,
            check=False,
        )
    finally:
        graph_path.write_bytes(original_graph)
        Path(filename).unlink(missing_ok=True)
    if result.returncode:
        raise SystemExit(result.returncode)
    if source != manifest(root):
        raise SystemExit("Source changed during the web build")
    build = root / "build/web"
    viewer = build / 'assets/packages/pw_shared_viewer/web'
    subprocess.run([
        'python3', str(root / 'packages/pw_shared_viewer/tool/browser_bundle.py'),
        '--stage', str(viewer),
    ], check=True)
    font_cache_identity = version_font_assets(build)
    receipt = {
        "font_cache_identity": font_cache_identity,
        "entrypoint": "lib/main_community_web.dart",
        "native_entrypoint": "lib/main.dart",
        "capabilities": community_defines(),
        "viewer_bundle_sha256": json.loads(
            (viewer / "BUNDLE_MANIFEST.json").read_text()
        )["bundle_sha256"],
        "main_js_sha256": hashlib.sha256((build / "main.dart.js").read_bytes()).hexdigest(),
        "status": "built-local-not-deployed",
        "source_revision": source["source_revision"],
        "source_manifest_sha256": hashlib.sha256(encoded(source)).hexdigest(),
    }
    (build / "shared-source-build.json").write_text(json.dumps(receipt, indent=2) + "\n")
    if args.export_to:
        shutil.copytree(build, args.export_to)
    print(json.dumps(receipt, indent=2))


if __name__ == "__main__":
    main()
