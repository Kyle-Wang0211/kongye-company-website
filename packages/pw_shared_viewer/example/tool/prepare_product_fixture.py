#!/usr/bin/python3
"""Stage exact production embedding sources for the isolated phone fixture."""
import hashlib
import json
from pathlib import Path
example = Path(__file__).resolve().parents[1]
product = Path(__file__).resolve().parents[4]
files = [
 'ui/shared/product_model_view.dart', 'ui/shared/product_point_view.dart',
 'community/shared_viewer_model_path.dart',
 'community/shared_viewer_model_path_native.dart',
 'community/shared_viewer_model_path_web.dart',
 'community/glb_cache.dart', 'official_util/device_log.dart',
]
destination = example / 'lib/production_fixture'
manifest = {}
for relative in files:
 data = (product/'lib'/relative).read_bytes()
 target = destination/relative
 target.parent.mkdir(parents=True, exist_ok=True)
 target.write_bytes(data)
 manifest[relative] = hashlib.sha256(data).hexdigest()
assert all(hashlib.sha256((destination/k).read_bytes()).hexdigest()==v for k,v in manifest.items())
(destination/'SOURCE_MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({'files':len(files),'all_exact_production_source_bytes':True,'manifest_sha256':hashlib.sha256(json.dumps(manifest,sort_keys=True).encode()).hexdigest()}))
