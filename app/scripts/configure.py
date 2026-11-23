#!/usr/bin/env python3
"""Writes the packaged Info.plist from the source one plus release settings.

Settings come from the environment (build-app.sh loads release.env):
  PORTO_VERSION, PORTO_BUILD        numeric version and build, e.g. 1.2 and 7
  SPARKLE_FEED_URL                  https://…/appcast.xml
  SPARKLE_PUBLIC_KEY                Sparkle's Ed25519 public key (base64)
  PORTO_REPOSITORY, PORTO_WEBSITE   links for About, feedback and the tip jar
  REQUIRE_UPDATES=--release         fail unless the update feed is configured

Everything is validated first; the source plist is never edited.
"""
import base64
import plistlib
import re
import sys
from pathlib import Path
from urllib.parse import urlsplit
import os

LOCAL_HOSTS = {"localhost", "127.0.0.1", "::1"}


def check_url(name, value, *, suffix=None):
    url = urlsplit(value)
    secure = url.scheme == "https" or (url.scheme == "http" and url.hostname in LOCAL_HOSTS)
    if not secure or not url.hostname or url.username or url.password or url.query or url.fragment:
        raise ValueError(f"{name} must be an https URL without credentials, query or fragment")
    if suffix and not url.path.endswith(suffix):
        raise ValueError(f"{name} must end in {suffix}")
    return value.rstrip("/") if not suffix else value


def configure(info, env):
    feed, key = env.get("SPARKLE_FEED_URL", ""), env.get("SPARKLE_PUBLIC_KEY", "")
    if feed or key or env.get("REQUIRE_UPDATES") == "--release":
        if urlsplit(feed).scheme != "https":
            raise ValueError("SPARKLE_FEED_URL must be an https URL ending in /appcast.xml")
        info["SUFeedURL"] = check_url("SPARKLE_FEED_URL", feed, suffix="/appcast.xml")
        try:
            decoded = base64.b64decode(key, validate=True)
        except ValueError:
            decoded = b""
        if len(decoded) != 32:
            raise ValueError("SPARKLE_PUBLIC_KEY must be the Ed25519 public key printed by Sparkle's generate_keys")
        info["SUPublicEDKey"] = key

    for variable, plist_key in (("PORTO_VERSION", "CFBundleShortVersionString"), ("PORTO_BUILD", "CFBundleVersion")):
        value = env.get(variable, "")
        if value:
            if not re.fullmatch(r"\d+(\.\d+){0,2}", value):
                raise ValueError(f"{variable} must be numeric, like 1.2 or 1.2.3")
            info[plist_key] = value

    for variable, plist_key in (("PORTO_REPOSITORY", "PortoRepository"), ("PORTO_WEBSITE", "PortoWebsite")):
        value = env.get(variable, "")
        if value:
            info[plist_key] = check_url(variable, value)
    return info


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: configure.py <source Info.plist> <output Info.plist>")
    source, output = map(Path, sys.argv[1:])
    try:
        info = configure(plistlib.loads(source.read_bytes()), os.environ)
    except ValueError as error:
        sys.exit(f"configure.py: {error}")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(plistlib.dumps(info, sort_keys=False))


if __name__ == "__main__":
    main()
