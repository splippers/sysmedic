#!/usr/bin/env python3
"""fetch-opencode-plugin.py DEST — rebuild the OpenCode plugin library (what `npm ci` would make) without npm.

Reads opencode-plugin/package-lock.json (next to this script), downloads every package it lists from the npm
registry, checks each against the lock's sha512 integrity value, and unpacks it to DEST/node_modules. Packages
for other operating systems or CPUs are skipped. DEST also gets package.json and package-lock.json, which
`sysmedic-deploy` copies onto the drive along with node_modules. The library has no install scripts to run.
"""
import base64
import hashlib
import io
import json
import shutil
import sys
import tarfile
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent / "opencode-plugin"


def wanted(meta):
    return ("linux" in meta.get("os", ["linux"])) and ("x64" in meta.get("cpu", ["x64"]))


def main():
    dest = Path(sys.argv[1]).resolve()
    lock = json.loads((HERE / "package-lock.json").read_text())
    nm = dest / "node_modules"
    if nm.exists():
        shutil.rmtree(nm)
    n = 0
    for key, meta in lock["packages"].items():
        if not key or not wanted(meta):
            continue
        algo, _, b64 = meta["integrity"].partition("-")
        if algo != "sha512":
            sys.exit(f"{key}: unexpected integrity type {algo}")
        data = urllib.request.urlopen(meta["resolved"], timeout=120).read()
        if base64.b64encode(hashlib.sha512(data).digest()).decode() != b64:
            sys.exit(f"{key}: download does not match the lock's integrity value")
        target = dest / key
        with tarfile.open(fileobj=io.BytesIO(data)) as tf:
            for m in tf.getmembers():
                name = m.name.split("/", 1)[1] if "/" in m.name else ""
                if not name:
                    continue
                if m.issym() or m.islnk() or name.startswith("/") or ".." in Path(name).parts:
                    continue                      # packages here are plain files; anything else is not unpacked
                if m.isdir():
                    (target / name).mkdir(parents=True, exist_ok=True)
                elif m.isfile():
                    out = target / name
                    out.parent.mkdir(parents=True, exist_ok=True)
                    out.write_bytes(tf.extractfile(m).read())
                    out.chmod(0o755 if m.mode & 0o100 else 0o644)
        n += 1
    for f in ("package.json", "package-lock.json"):
        shutil.copy(HERE / f, dest / f)
    print(f"opencode plugin library: {n} packages in {nm}")


if __name__ == "__main__":
    main()
