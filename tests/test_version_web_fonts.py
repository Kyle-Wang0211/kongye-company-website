import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('web_fonts', Path(__file__).parents[1] / 'source/community_app/tool/pw_version_web_fonts.py')
fonts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fonts)


class FontCacheIdentityTests(unittest.TestCase):
    def test_changed_subset_gets_new_url_and_old_asset_is_retained(self):
        with tempfile.TemporaryDirectory(dir=Path.cwd()) as tmp:
            site = Path(tmp)
            assets = site / 'assets'
            assets.mkdir()
            original = assets / 'icons.otf'
            original.write_bytes(b'first subset')
            manifest = assets / 'FontManifest.json'
            initial = [{'family': 'MaterialIcons', 'fonts': [{'asset': 'icons.otf'}]}]
            manifest.write_text(json.dumps(initial))
            first = fonts.version_font_assets(site)[0]['asset']
            before = manifest.read_bytes()
            fonts.version_font_assets(site)
            self.assertEqual(manifest.read_bytes(), before)
            self.assertEqual((assets / first).read_bytes(), b'first subset')
            original.write_bytes(b'next subset with new glyphs')
            manifest.write_text(json.dumps(initial))
            second = fonts.version_font_assets(site)[0]['asset']
            self.assertNotEqual(first, second)
            self.assertEqual((assets / first).read_bytes(), b'first subset')
            self.assertEqual((assets / second).read_bytes(), original.read_bytes())

    def test_unsafe_assets_are_rejected(self):
        with tempfile.TemporaryDirectory(dir=Path.cwd()) as tmp:
            site = Path(tmp)
            assets = site / 'assets'
            assets.mkdir()
            for name in ['../outside.ttf', '/outside.otf', 'not-a-font.js']:
                (assets / 'FontManifest.json').write_text(json.dumps([{'fonts': [{'asset': name}]}]))
                with self.assertRaises(ValueError):
                    fonts.version_font_assets(site)


if __name__ == '__main__':
    unittest.main()
