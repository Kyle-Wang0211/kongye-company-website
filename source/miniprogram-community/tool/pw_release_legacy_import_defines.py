"""Forward an explicit private legacy-owner grant through the fixed recipe.

Only opaque hashes are accepted. No email, user ID, token or arbitrary Dart
define is accepted, and neither config values nor paths enter diagnostics.
"""

import hashlib
import json
import os
from pathlib import Path
import re
import sys

DEFINE_NAMES = ("PW_LEGACY_OWNER_NAMESPACE", "PW_LEGACY_INDEX_SHA256")


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate key")
        result[key] = value
    return result


def load_config(filename):
    with Path(filename).open("rb") as source:
        raw = source.read(4097)
    if len(raw) > 4096:
        raise ValueError("Oversize config")
    config = json.loads(raw.decode("utf-8"), object_pairs_hook=unique_object)
    if not isinstance(config, dict) or set(config) != set(DEFINE_NAMES):
        raise ValueError("Invalid defines")
    if any(not isinstance(value, str) or not re.fullmatch(r"[a-f0-9]{64}", value)
           for value in config.values()):
        raise ValueError("Invalid hashes")
    return config, hashlib.sha256(raw).hexdigest()


def main(args):
    validate_only = len(args) == 2 and args[0] == "--validate-only"
    if not validate_only and (len(args) < 3 or args[1] != "--"):
        print("Invalid legacy import helper invocation", file=sys.stderr)
        return 64
    try:
        config, digest = load_config(args[1] if validate_only else args[0])
    except (OSError, ValueError, UnicodeError, RecursionError):
        print("Invalid legacy import configuration: require exactly two opaque hashes", file=sys.stderr)
        return 64
    if validate_only:
        return 0
    command = args[2:] + ["--dart-define=" + key + "=" + config[key] for key in DEFINE_NAMES]
    print("PW_RELEASE_LEGACY_IMPORT_CONFIG sha256=" + digest, flush=True)
    try:
        os.execvp(command[0], command)
    except OSError:
        print("Unable to execute legacy import build command", file=sys.stderr)
        return 69


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
