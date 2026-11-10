"""Validate China build config and append the shared community capability profile.

This helper uses only the Python standard library. Config files belong outside
the repository. Key values are never included in our diagnostics; Flutter must
receive the public client key in argv, so do not collect process listings or run
the recipe with shell tracing. JWT inspection checks the public anon role only;
endpoint availability and cryptographic key validity require separate checks.
"""

import base64
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import re
import sys
from urllib.parse import urlsplit

from community_build_features import community_defines


DEFINE_NAMES = (
    "PW_BACKEND_REGION",
    "PW_DEPLOYMENT_ID",
    "PW_CN_SUPABASE_URL",
    "PW_CN_SUPABASE_ANON_KEY",
)
LEGACY_HOST = "tzvwkqmgaourwqrmxbyb.supabase.co"


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate JSON key")
        result[key] = value
    return result


def valid_origin(value):
    # Match the entire wire form first: urlsplit otherwise discards some control
    # characters and accepts empty query/fragment/port delimiters.
    if not re.fullmatch(r"https://(?:\[[0-9a-fA-F:]+\]|[A-Za-z0-9.-]+)(?::443)?/?", value):
        return False
    uri = urlsplit(value)
    host = uri.hostname
    if not host or host.lower() == LEGACY_HOST:
        return False
    if ":" in host:
        return isinstance(ipaddress.ip_address(host), ipaddress.IPv6Address)
    return len(host) <= 253 and all(
        re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?", label)
        for label in host.split(".")
    )


def jwt_object(segment):
    decoded = base64.b64decode(segment + "=" * (-len(segment) % 4), altchars=b"-_", validate=True)
    value = json.loads(decoded, object_pairs_hook=unique_object)
    if not isinstance(value, dict):
        raise ValueError("JWT object required")
    return value


def public_client_key(value):
    if re.fullmatch(r"sb_publishable_[A-Za-z0-9_-]+", value):
        return True
    if not re.fullmatch(r"[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+", value):
        return False
    header, payload, _signature = value.split(".")
    algorithm = jwt_object(header).get("alg")
    return algorithm in ("HS256", "RS256", "ES256") and jwt_object(payload).get("role") == "anon"


def load_config(filename):
    with Path(filename).open("rb") as config_file:
        raw = config_file.read(16 * 1024 + 1)
    if len(raw) > 16 * 1024:
        raise ValueError("Oversize config")
    config = json.loads(raw.decode("utf-8"), object_pairs_hook=unique_object)
    if not isinstance(config, dict) or set(config) != set(DEFINE_NAMES):
        raise ValueError("Exactly the four China defines are required")
    if any(not isinstance(value, str) for value in config.values()):
        raise ValueError("String defines required")
    if config["PW_BACKEND_REGION"] != "china" or config["PW_DEPLOYMENT_ID"] != "cn-primary":
        raise ValueError("China primary required")
    if not valid_origin(config["PW_CN_SUPABASE_URL"]):
        raise ValueError("HTTPS port 443 root required")
    if not public_client_key(config["PW_CN_SUPABASE_ANON_KEY"]):
        raise ValueError("Public client key required")
    return config, hashlib.sha256(raw).hexdigest()


def main(args):
    validate_only = len(args) == 2 and args[0] == "--validate-only"
    if not validate_only and (len(args) < 3 or args[1] != "--"):
        print("Invalid regional configuration helper invocation", file=sys.stderr)
        return 64
    try:
        config, digest = load_config(args[1] if validate_only else args[0])
    except (OSError, ValueError, UnicodeError, RecursionError):
        # Parser errors can contain the input. Keep both values and file paths
        # out of the error; the caller already knows the private config path.
        print("Invalid regional configuration: require exactly four China primary defines, an HTTPS:443 root URL, and a public client key", file=sys.stderr)
        return 64
    if validate_only:
        return 0
    definitions = {**config, **community_defines()}
    command = args[2:] + ["--dart-define=" + name + "=" + value for name, value in definitions.items()]
    print("PW_RELEASE_REGIONAL_CONFIG region=china deployment=cn-primary sha256=" + digest, flush=True)
    try:
        os.execvp(command[0], command)
    except OSError:
        print("Unable to execute regional build command", file=sys.stderr)
        return 69


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
