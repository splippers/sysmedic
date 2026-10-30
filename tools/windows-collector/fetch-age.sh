#!/bin/bash
# fetch-age.sh — put age.exe (the Windows build of age, https://age-encryption.org) next to the collector.
# Downloads the pinned release, checks it against the SHA-256 pinned below, and leaves age.exe in this folder
# (git-ignored); xchg_layout.py copies it onto every exchange partition it builds.
#
# The pin was taken from the v1.2.1 release zip at the time it was added. It stops a changed or corrupted download
# from being used; it does not by itself prove the release was genuine. To check independently, build age from
# source at the same tag (go build filippo.io/age/cmd/age) and compare, or compare with your distro's `age` package
# source. When you move to a newer age, change VERSION and SHA256 together, in one reviewed commit.
set -euo pipefail
cd "$(dirname "$0")"
VERSION=1.2.1
SHA256=46db0db71f146061f7c8fffa912cb806aef1bc8450e27a3abc1744f0591b89fb
URL=https://github.com/FiloSottile/age/releases/download/v$VERSION/age-v$VERSION-windows-amd64.zip
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/age.zip" "$URL"
echo "$SHA256  $tmp/age.zip" | sha256sum -c - >/dev/null || { echo "ERROR: age $VERSION download does not match the pinned SHA-256" >&2; exit 1; }
unzip -q -j "$tmp/age.zip" age/age.exe age/LICENSE -d "$tmp/x"
install -m 0644 "$tmp/x/age.exe" age.exe
install -m 0644 "$tmp/x/LICENSE" age-LICENSE.txt
echo "age.exe $VERSION is in $(pwd)"
