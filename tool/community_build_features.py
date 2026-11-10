"""One explicit community capability profile for web and native builds."""

import json
from pathlib import Path


def community_defines():
    profile = json.loads(Path(__file__).with_name("community_features.json").read_text())
    expected = {
        "PW_COMMUNITY_FAVORITES_ENABLED",
        "PW_COMMUNITY_MESSAGING_READY",
        "PW_COMMUNITY_PROFILES_ENABLED",
    }
    if set(profile) != expected or any(type(value) is not bool for value in profile.values()):
        raise ValueError("Invalid community capability profile")
    return {name: str(value).lower() for name, value in profile.items()}
