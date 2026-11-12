"""Copy the App-owned suggestion widget to the mini-program Flutter H5 host."""

import argparse
import hashlib
import json
from pathlib import Path


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', required=True, type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
component = args.source.read_bytes()
targets = [
    f'source/{host}/lib/ui/community/search_suggestion_list.dart'
    for host in ('miniprogram-community',)
]
for name in targets:
    destination = root / name
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(component)
record = {
    'canonical_component': 'App/lib/ui/community/search_suggestion_list.dart',
    'sha256': hashlib.sha256(component).hexdigest(),
    'copies': targets,
    'web_renderer': 'docs/community-search.mjs shared by homepage and standalone search',
    'web_source_revision': 'e78362446b006e83549fb576a0ca303e1993e563',
}
(root / 'tool/search_suggestion_component.json').write_text(
    json.dumps(record, indent=2) + '\n'
)
print(json.dumps(record))
