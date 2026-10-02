#!/bin/bash
# Download the third-party test fixtures used by the QEMU tests (not stored in this repo).
#   cryptsetup BitLocker test volumes (recovery keys in bitlk-images/images.conf)
#   hivex's minimal registry hive (base for make-windows-fixture.py)
#   python-evtx sample System/Security event logs
set -euo pipefail
cd "$(dirname "$0")"; mkdir -p fixtures; cd fixtures
get() { curl -fsSL --retry 3 -o "$1" "$2" && echo "  got $1"; }
get bitlk-images.tar.xz "https://gitlab.com/cryptsetup/cryptsetup/-/raw/main/tests/bitlk-images.tar.xz" && tar xf bitlk-images.tar.xz
get hivex-minimal "https://raw.githubusercontent.com/libguestfs/hivex/master/images/minimal"
get system.evtx "https://raw.githubusercontent.com/williballenthin/python-evtx/master/tests/data/system.evtx"
get security.evtx "https://raw.githubusercontent.com/williballenthin/python-evtx/master/tests/data/security.evtx"
echo "Next: build registry hives with make-windows-fixture.py (inside the image chroot), then make-windows-tree.sh"
