#!/usr/bin/env python3
"""Offline source-only bridge build. Never installs, launches, or changes Runner."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys


NAME = "PWSharedWebViewBridge"
MINIMUM_IOS = "15.0"
SOURCE_ROOT = Path(__file__).resolve().parent


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def inventory(root):
    """Freeze every input file, including headers, modules and signature data."""
    result = {}
    for path in sorted(root.rglob("*")):
        if path.is_symlink():
            raise ValueError(f"Symlink not supported in frozen framework: {path}")
        if path.is_file():
            result[str(path.relative_to(root))] = sha256(path)
        elif not path.is_dir():
            raise ValueError(f"Unexpected framework entry: {path}")
    if not result:
        raise ValueError(f"Empty framework: {root}")
    return result


def existing_path(value, *, directory=False, executable=False):
    path = Path(value)
    if not path.is_absolute():
        raise ValueError(f"Explicit absolute path required: {value}")
    path = path.resolve(strict=True)
    if directory and not path.is_dir():
        raise ValueError(f"Directory required: {path}")
    if not directory and not path.is_file():
        raise ValueError(f"File required: {path}")
    if executable and not os.access(path, os.X_OK):
        raise ValueError(f"Executable required: {path}")
    return path


def check_digest(path, expected):
    if not re.fullmatch(r"[a-fA-F0-9]{64}", expected):
        raise ValueError("A complete expected SHA-256 is required")
    actual = sha256(path)
    if actual != expected.lower():
        raise ValueError(f"Input SHA-256 mismatch: {path}")
    return actual


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--flutter-framework", required=True)
    result.add_argument("--plugin-framework", required=True)
    result.add_argument("--expected-flutter-sha256", required=True)
    result.add_argument("--expected-plugin-sha256", required=True)
    result.add_argument("--sdk", required=True, help="Existing iPhoneOS SDK directory")
    result.add_argument("--clang", required=True, help="Existing pinned compiler executable")
    result.add_argument("--codesign", required=True, help="Existing signing executable")
    result.add_argument("--signing-identity", required=True,
                        help="Explicit certificate identity; ad hoc signing is rejected")
    result.add_argument("--output", required=True, help="New absolute output directory")
    return result


def build(args):
    flutter = existing_path(args.flutter_framework, directory=True)
    plugin = existing_path(args.plugin_framework, directory=True)
    if flutter.name != "Flutter.framework" or plugin.name != "webview_flutter_wkwebview.framework":
        raise ValueError("Expected exact Flutter and official WebView framework names")
    for candidate, expected in ((flutter.parent / plugin.name, plugin),
                                (plugin.parent / flutter.name, flutter)):
        if candidate.exists() and candidate.resolve() != expected:
            raise ValueError(f"Ambiguous framework search path: {candidate}")
    existing_path(str(flutter / "Headers/Flutter.h"))
    existing_path(str(plugin / "Headers/webview_flutter_wkwebview-Swift.h"))
    check_digest(flutter / "Flutter", args.expected_flutter_sha256)
    check_digest(plugin / "webview_flutter_wkwebview", args.expected_plugin_sha256)
    sdk = existing_path(args.sdk, directory=True)
    clang = existing_path(args.clang, executable=True)
    codesign = existing_path(args.codesign, executable=True)
    if not args.signing_identity.strip() or args.signing_identity.strip() == "-":
        raise ValueError("Explicit certificate signing identity required")
    output = Path(args.output)
    if not output.is_absolute() or output.exists() or output.is_symlink():
        raise ValueError("Output must be a new absolute directory; overwrite is forbidden")
    existing_path(str(output.parent), directory=True)
    # Prevent compiler/module/signature writes anywhere inside either input.
    for source in (flutter, plugin):
        if output.resolve().is_relative_to(source):
            raise ValueError("Output cannot be inside an input framework")
    frozen = {"flutter": inventory(flutter), "official_plugin": inventory(plugin)}
    source_identity = {
        filename: sha256(SOURCE_ROOT / filename)
        for filename in (f"{NAME}.m", f"{NAME}.h", "build_bridge.py")
    }
    output.mkdir(exist_ok=False)
    framework = output / f"{NAME}.framework"
    framework.mkdir()
    report = {
        "status": "BUILDING", "minimum_ios": MINIMUM_IOS, "architecture": "arm64",
        "source_sha256": source_identity, "inputs": frozen, "commands": [],
        "tools": {"clang": {"path": str(clang), "sha256": sha256(clang)},
                  "codesign": {"path": str(codesign), "sha256": sha256(codesign)}},
        "sdk": str(sdk),
    }
    receipt = output / "build_receipt.json"

    def save():
        receipt.write_text(json.dumps(report, indent=2) + "\n")

    def run(command):
        result = subprocess.run(command, capture_output=True, text=True, check=False)
        report["commands"].append({"argv": command, "exit_code": result.returncode,
                                   "stdout": result.stdout, "stderr": result.stderr})
        save()
        if result.returncode:
            raise RuntimeError(f"Tool failed with exit code {result.returncode}; see receipt")

    try:
        save()
        run([str(clang), "-arch", "arm64", "-isysroot", str(sdk),
             f"-miphoneos-version-min={MINIMUM_IOS}", "-fobjc-arc", "-fmodules",
             f"-fmodules-cache-path={output / 'module-cache'}", "-dynamiclib", "-O2",
             "-fvisibility=hidden", f"-I{SOURCE_ROOT}", f"-F{flutter.parent}",
             f"-F{plugin.parent}", "-framework", "Flutter", "-framework",
             "webview_flutter_wkwebview", "-framework", "UIKit", "-framework", "Foundation",
             "-install_name", f"@rpath/{NAME}.framework/{NAME}",
             "-Wl,-rpath,@loader_path/..", str(SOURCE_ROOT / f"{NAME}.m"),
             "-o", str(framework / NAME)])
        (framework / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": f"dev.pocketworld.viewer.{NAME}",
            "CFBundleExecutable": NAME, "CFBundlePackageType": "FMWK",
            "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0",
            "MinimumOSVersion": MINIMUM_IOS, "CFBundleSupportedPlatforms": ["iPhoneOS"],
        }))
        run([str(codesign), "--sign", args.signing_identity, "--timestamp=none", str(framework)])
        run([str(codesign), "--verify", "--deep", "--strict", str(framework)])
        if inventory(flutter) != frozen["flutter"] or inventory(plugin) != frozen["official_plugin"]:
            raise RuntimeError("Input framework changed during build; candidate rejected")
        if any(sha256(SOURCE_ROOT / name) != digest for name, digest in source_identity.items()):
            raise RuntimeError("Source changed during build; candidate rejected")
        report["output"] = inventory(framework)
        report["bridge_raw_signed_sha256"] = sha256(framework / NAME)
        report["status"] = "SIGNED_CANDIDATE_ONLY"
        save()
    except BaseException as error:
        report["status"] = "FAILED"
        report["error"] = str(error)
        save()
        raise
    return report


def main():
    args = parser().parse_args()
    try:
        report = build(args)
    except (OSError, ValueError, RuntimeError) as error:
        print(f"STOPPED: {error}", file=sys.stderr)
        return 1
    print(report["bridge_raw_signed_sha256"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
