#!/usr/bin/env python3
"""python3 scripts/test-configure.py"""
import base64
import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("configure", Path(__file__).with_name("configure.py"))
configure = importlib.util.module_from_spec(spec)
spec.loader.exec_module(configure)

KEY = base64.b64encode(bytes(range(32))).decode()
FEED = "https://porto.example/updates/appcast.xml"


class ConfigureTests(unittest.TestCase):
    def run_with(self, **env):
        return configure.configure({"CFBundleShortVersionString": "1.0", "CFBundleVersion": "1"}, env)

    def test_local_builds_need_nothing(self):
        self.assertEqual(self.run_with(), {"CFBundleShortVersionString": "1.0", "CFBundleVersion": "1"})

    def test_release_requires_a_feed_and_key(self):
        with self.assertRaises(ValueError):
            self.run_with(REQUIRE_UPDATES="--release")
        info = self.run_with(REQUIRE_UPDATES="--release", SPARKLE_FEED_URL=FEED, SPARKLE_PUBLIC_KEY=KEY)
        self.assertEqual((info["SUFeedURL"], info["SUPublicEDKey"]), (FEED, KEY))

    def test_partial_or_unsafe_update_settings_fail(self):
        for env in [dict(SPARKLE_FEED_URL=FEED), dict(SPARKLE_PUBLIC_KEY=KEY),
                    dict(SPARKLE_FEED_URL="http://porto.example/updates/appcast.xml", SPARKLE_PUBLIC_KEY=KEY),
                    dict(SPARKLE_FEED_URL="http://localhost/appcast.xml", SPARKLE_PUBLIC_KEY=KEY),
                    dict(SPARKLE_FEED_URL=FEED + "?v=1", SPARKLE_PUBLIC_KEY=KEY),
                    dict(SPARKLE_FEED_URL="https://user:pw@porto.example/appcast.xml", SPARKLE_PUBLIC_KEY=KEY),
                    dict(SPARKLE_FEED_URL="https://porto.example/feed.xml", SPARKLE_PUBLIC_KEY=KEY),
                    dict(SPARKLE_FEED_URL=FEED, SPARKLE_PUBLIC_KEY="not base64!"),
                    dict(SPARKLE_FEED_URL=FEED, SPARKLE_PUBLIC_KEY=base64.b64encode(b"short").decode())]:
            with self.subTest(env=env), self.assertRaises(ValueError):
                self.run_with(**env)

    def test_versions_are_numeric(self):
        info = self.run_with(PORTO_VERSION="1.2.3", PORTO_BUILD="42")
        self.assertEqual((info["CFBundleShortVersionString"], info["CFBundleVersion"]), ("1.2.3", "42"))
        for bad in ["1.2-beta", "v1", "1..2", "1.2.3.4"]:
            with self.subTest(version=bad), self.assertRaises(ValueError):
                self.run_with(PORTO_VERSION=bad)

    def test_links(self):
        info = self.run_with(PORTO_REPOSITORY="https://github.com/me/porto/", PORTO_WEBSITE="http://localhost:8186")
        self.assertEqual(info["PortoRepository"], "https://github.com/me/porto")
        self.assertEqual(info["PortoWebsite"], "http://localhost:8186")
        for bad in ["http://porto.example", "ftp://porto.example", "https://porto.example/?ref=1", "porto.example"]:
            with self.subTest(website=bad), self.assertRaises(ValueError):
                self.run_with(PORTO_WEBSITE=bad)


if __name__ == "__main__":
    unittest.main(verbosity=1)
