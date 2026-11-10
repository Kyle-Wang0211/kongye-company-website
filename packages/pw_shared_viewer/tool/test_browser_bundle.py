import shutil
import tempfile
import unittest
from pathlib import Path

from browser_bundle import browser_html, stage, verify

SOURCE = Path(__file__).resolve().parent.parent / 'web'


class BrowserBundleTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'web'
        shutil.copytree(SOURCE, self.root)

    def test_stage_preserves_resources_and_full_native_default(self):
        original = verify(self.root)
        source_entry = (SOURCE / 'index.html').read_bytes()
        staged = stage(self.root)
        self.assertNotEqual(staged['bundle_sha256'], original['bundle_sha256'])
        self.assertEqual(staged['files'].keys(), original['files'].keys())
        for path in original['files']:
            if path != 'index.html':
                self.assertEqual(staged['files'][path], original['files'][path], path)
        entry = (self.root / 'index.html').read_text()
        self.assertIn('pwSharedViewerReady = readReleaseIdentity()', entry)
        self.assertNotIn('verifyLocalBundle', entry)
        self.assertIn("bundleIdentityScope: 'release-manifest', runtimeBundleBytesVerified: false", entry)
        self.assertEqual((SOURCE / 'index.html').read_bytes(), source_entry)
        self.assertIn('pwSharedViewerReady = verifyLocalBundle()', source_entry.decode())

    def test_stale_manifest_or_mixed_revision_is_rejected(self):
        for name in ['index.html', 'vendor/three/build/three.core.js']:
            with self.subTest(name=name):
                artifact = self.root / name
                original = artifact.read_bytes()
                artifact.write_bytes(original + b'\nchanged')
                with self.assertRaisesRegex(ValueError, 'differs from manifest'):
                    stage(self.root)
                artifact.write_bytes(original)

    def test_staged_tampering_is_rejected(self):
        stage(self.root)
        (self.root / 'viewer.mjs').write_text('wrong revision')
        with self.assertRaisesRegex(ValueError, 'differs from manifest'):
            verify(self.root)

    def test_ambiguous_transform_fails(self):
        with self.assertRaises(ValueError):
            browser_html('already transformed or unknown entry')


if __name__ == '__main__':
    unittest.main()
