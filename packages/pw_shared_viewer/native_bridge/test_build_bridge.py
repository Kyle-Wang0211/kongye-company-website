"""Input gate tests only. Never invoke compiler, signing tool, or device tools."""

import argparse
import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import build_bridge


class BuildInputGateTest(unittest.TestCase):
    def test_hash_gate_rejects_wrong_and_incomplete_identities(self):
        with tempfile.TemporaryDirectory() as folder:
            binary = Path(folder) / "binary"
            binary.write_bytes(b"original")
            digest = hashlib.sha256(b"original").hexdigest()
            self.assertEqual(build_bridge.check_digest(binary, digest), digest)
            for wrong in ("bad", "0" * 64):
                with self.assertRaises(ValueError):
                    build_bridge.check_digest(binary, wrong)

    def test_inventory_detects_resource_changes_and_rejects_symlinks(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            resource = root / "Info.plist"
            resource.write_bytes(b"first")
            frozen = build_bridge.inventory(root)
            resource.write_bytes(b"changed")
            self.assertNotEqual(build_bridge.inventory(root), frozen)
            (root / "alias").symlink_to(resource)
            with self.assertRaises(ValueError):
                build_bridge.inventory(root)

    def test_requires_explicit_absolute_existing_tool_paths(self):
        with self.assertRaises(ValueError):
            build_bridge.existing_path("clang", executable=True)
        with tempfile.TemporaryDirectory() as folder:
            tool = Path(folder) / "tool"
            tool.write_text("not executable")
            with self.assertRaises(ValueError):
                build_bridge.existing_path(str(tool), executable=True)

    def test_existing_output_rejected_without_invoking_any_tools(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            flutter = root / "flutter/Flutter.framework"
            plugin = root / "plugin/webview_flutter_wkwebview.framework"
            for framework, executable, header in (
                (flutter, "Flutter", "Flutter.h"),
                (plugin, "webview_flutter_wkwebview", "webview_flutter_wkwebview-Swift.h"),
            ):
                (framework / "Headers").mkdir(parents=True)
                (framework / "Headers" / header).write_text("public header")
                (framework / executable).write_bytes(b"frozen")
            sdk = root / "sdk"
            sdk.mkdir()
            tool = root / "tool"
            tool.write_text("must never run")
            tool.chmod(0o700)
            output = root / "existing"
            output.mkdir()
            marker = output / "keep"
            marker.write_text("untouched")
            digest = hashlib.sha256(b"frozen").hexdigest()
            args = argparse.Namespace(
                flutter_framework=str(flutter), plugin_framework=str(plugin),
                expected_flutter_sha256=digest, expected_plugin_sha256=digest,
                sdk=str(sdk), clang=str(tool), codesign=str(tool),
                signing_identity="explicit-test-certificate", output=str(output),
            )
            with patch("build_bridge.subprocess.run") as command:
                with self.assertRaisesRegex(ValueError, "overwrite is forbidden"):
                    build_bridge.build(args)
                command.assert_not_called()
            self.assertEqual(marker.read_text(), "untouched")


if __name__ == "__main__":
    unittest.main()
