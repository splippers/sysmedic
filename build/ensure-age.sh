#!/bin/bash
# ensure-age.sh COLLECTOR_DIR — make sure age.exe is in the collector folder before a drive is written.
# age.exe is git-ignored (a third-party binary; see tools/windows-collector/fetch-age.sh), so a fresh clone
# lacks it. This fetches the pinned, SHA-256-checked release once, and fails the build if that is impossible
# (offline, bad checksum) rather than writing a drive whose collector cannot run. ALLOW_NO_AGE=1 builds anyway.
set -euo pipefail
DIR=${1:?usage: ensure-age.sh COLLECTOR_DIR}
[ -s "$DIR/age.exe" ] && exit 0
if [ -x "$DIR/fetch-age.sh" ] && "$DIR/fetch-age.sh" >&2 && [ -s "$DIR/age.exe" ]; then exit 0; fi
if [ "${ALLOW_NO_AGE:-0}" = 1 ]; then
    echo "warning: no age.exe in $DIR; the Windows collector on this drive will refuse to run (ALLOW_NO_AGE=1)" >&2
    exit 0
fi
echo "ERROR: $DIR/age.exe is missing and could not be fetched (offline?). Run $DIR/fetch-age.sh with network access," >&2
echo "       or set ALLOW_NO_AGE=1 to build a drive without it." >&2
exit 1
