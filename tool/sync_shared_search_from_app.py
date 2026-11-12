"""Run the App-owned bounded search sync into the mini-program H5 host."""

import argparse
import json
from pathlib import Path
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source-root', required=True, type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
source = args.source_root.resolve()
result = subprocess.run(
    [sys.executable, str(source / 'tool/sync_shared_search.py'),
     str(root / 'source/miniprogram-community'), '--apply'],
    check=True, capture_output=True, text=True,
)
record = json.loads(result.stdout)
record['source'] = 'App canonical product source'
record['destination'] = 'source/miniprogram-community'
record['source_revision'] = subprocess.check_output(
    ['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True,
).strip()
(root / 'tool/shared_search_components.json').write_text(
    json.dumps(record, indent=2) + '\n'
)
print(json.dumps(record, indent=2))
