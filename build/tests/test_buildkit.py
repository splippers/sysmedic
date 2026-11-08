#!/usr/bin/env python3
"""A stranger can build from a clean clone: python3 build/tests/test_buildkit.py

Guards the things that only worked on the main build PC: the kit links everything the deploy reads from it, the
plugin library can be rebuilt from the repo, and every file the build scripts name from the repo is tracked.
"""
import json
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
B = REPO / "build"


class Kit(unittest.TestCase):
    def test_kit_links_what_the_deploy_reads(self):
        d = tempfile.mkdtemp()
        r = subprocess.run([B / "bootstrap.sh", "kit", d], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        for name in ("staging", "lite", "sysmedic-deploy", "build-iso.sh", "make-stick.sh", "vm.py", "bootstrap.sh"):
            self.assertTrue((Path(d) / name).exists(), f"kit lacks {name}")
        deploy = (B / "sysmedic-deploy").read_text()
        for used in set(re.findall(r'\$KIT/([A-Za-z0-9_.-]+)/', deploy)):
            if used in ("staging", "lite"):
                self.assertTrue((Path(d) / used).exists(), used)

    def test_plugin_library_is_reproducible_from_the_repo(self):
        lock = json.loads((B / "opencode-plugin/package-lock.json").read_text())
        plug = lock["packages"]["node_modules/@opencode-ai/plugin"]
        boot = (B / "bootstrap.sh").read_text()
        self.assertEqual(re.search(r"^OPENCODE_VERSION=(\S+)", boot, re.M).group(1), plug["version"],
                         "OPENCODE_VERSION and the plugin lock must move together")
        for key, meta in lock["packages"].items():
            if key:
                self.assertTrue(meta.get("integrity", "").startswith("sha512-"), key)
                self.assertTrue(meta["resolved"].startswith("https://registry.npmjs.org/"), key)
        self.assertIn("fetch-opencode-plugin.py", boot)

    def test_files_the_builds_need_are_tracked(self):
        tracked = set(subprocess.run(["git", "ls-files"], cwd=REPO, capture_output=True, text=True).stdout.split())
        for f in ("build/lite/purge-packages.txt", "build/lite/purge-firmware.txt", "build/opencode-plugin/package.json",
                  "build/opencode-plugin/package-lock.json", "build/fetch-opencode-plugin.py", "build/ensure-age.sh",
                  "tools/windows-collector/fetch-age.sh", "build/staging/iso/boot/grub/grub.cfg"):
            self.assertIn(f, tracked, f"{f} is not tracked in git")


if __name__ == "__main__":
    unittest.main()
