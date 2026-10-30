#!/bin/bash
# Write sysmedic-v2.iso to TARGET (a block device or an image file), then add and
# populate the FOG_AMB_PERSIST persistence partition in the remaining space.
#   ./make-stick.sh /dev/sdX      — DESTROYS everything on /dev/sdX
#   ./make-stick.sh stick-test.img
set -euo pipefail
cd "$(dirname "$0")"
TARGET=$1
ISO=${ISO:-sysmedic-v2.iso}
LITE=${LITE:-0}                    # Stick Lite: cloud AI only, so no Ollama runtime or models on the persistence partition
HERE=$(dirname "$(readlink -f "$0")")                      # the repo's build/ (the kit's copy is a symlink to it)
XCHG_MIB=${XCHG_MIB:-$( [ "$LITE" = 1 ] && echo 256 || echo 512 )}    # exchange partition size (the Windows-readable one); 0 = none
XCHG_COLLECTOR=${XCHG_COLLECTOR:-$HERE/../tools/windows-collector}
# Ollama runtime and models: from the kit if bootstrap.sh fetched them, else this PC's own Ollama install
OLLAMA_SRC_MODELS=$( [ -d ollama-models/manifests ] && echo "$PWD/ollama-models" || echo /usr/share/ollama/.ollama/models )
OLLAMA_BIN=$( [ -x downloads/ollama/bin/ollama ] && echo downloads/ollama/bin/ollama || echo /usr/local/bin/ollama )
OLLAMA_LIB=$( [ -d downloads/ollama/lib/ollama ] && echo downloads/ollama/lib/ollama || echo /usr/local/lib/ollama )
# The stick always runs the 3B model (sysmedic-ask's pick_model), so the 7B (4.7 GB) only goes on drives with room to spare:
# an 8 GB stick gets the 3B alone and keeps about 3 GB for the vault. Override with SYSMEDIC_MODELS="...".
tsize=$( [ -b "$TARGET" ] && sudo blockdev --getsize64 "$TARGET" || stat -c %s "$TARGET" )
if [ "$LITE" = 1 ]; then MODELS=""
elif [ -n "${SYSMEDIC_MODELS:-}" ]; then MODELS=$SYSMEDIC_MODELS
elif [ "$tsize" -lt 14000000000 ]; then MODELS="qwen2.5:3b"
else MODELS="qwen2.5:3b qwen2.5:7b"; fi
echo "Models on this drive: ${MODELS:-none (Lite: cloud AI only)} ($((tsize / 1000000000)) GB drive)"

sudo dd if="$ISO" of="$TARGET" bs=4M conv=fsync,notrunc status=none
sync

# Keep xorriso's hybrid MBR entries (protective 0xEE + boot flag) — sgdisk rewrites them
sudo dd if="$TARGET" of=mbr-parts.bin bs=1 skip=446 count=66 status=none
sudo sgdisk -e "$TARGET" >/dev/null                          # move backup GPT to the real end of disk
if [ "$XCHG_MIB" -gt 0 ]; then
    # Persistence stops short of the end; the last partition is the exchange partition, the only one Windows will show
    sudo sgdisk -a 2048 -n 4:0:-${XCHG_MIB}M -t 4:8300 -c 4:FOG_AMB_PERSIST "$TARGET" >/dev/null
    sudo sgdisk -a 2048 -n 5:0:0 -t 5:0700 -c 5:SM_EXCHANGE "$TARGET" >/dev/null
else
    sudo sgdisk -a 2048 -n 4:0:0 -t 4:8300 -c 4:FOG_AMB_PERSIST "$TARGET" >/dev/null
fi
sudo python3 "$HERE/xchg_layout.py" hide "$TARGET"          # the ISO and gap partitions are "basic data": hide them from Windows
sudo dd if=mbr-parts.bin of="$TARGET" bs=1 seek=446 conv=notrunc,fsync status=none
sudo sgdisk -v "$TARGET" | grep -q 'No problems found' || { echo "GPT verify failed"; exit 1; }

if [ -b "$TARGET" ]; then
    sudo partprobe "$TARGET"; sudo udevadm settle
    PART=$(lsblk -lnpo NAME "$TARGET" | sed -n 5p)            # disk + 4 partitions → 4th partition
    XPART=$(lsblk -lnpo NAME "$TARGET" | sed -n 6p)
    for p in $(lsblk -lnpo NAME "$TARGET" | tail -n +2); do   # the desktop may automount after partprobe
        findmnt -rno TARGET -S "$p" >/dev/null && sudo umount "$p"
    done
    LOOP=
else
    LOOP=$(sudo losetup -fP --show "$TARGET"); PART=${LOOP}p4; XPART=${LOOP}p5
fi
sudo mkfs.ext4 -q -F -L FOG_AMB_PERSIST -m 0 "$PART"

mkdir -p pmnt
sudo mount "$PART" pmnt
P=pmnt
sudo mkdir -p $P/{logs,backups,sessions}
if [ "$LITE" != 1 ]; then
sudo mkdir -p $P/ollama/{bin,lib/ollama} $P/ollama/models/blobs
sudo cp "$OLLAMA_BIN" $P/ollama/bin/
sudo cp -a "$OLLAMA_LIB"/libggml-*.so* $P/ollama/lib/ollama/   # CPU backends
[ -d "$OLLAMA_LIB/vulkan" ] && sudo cp -a "$OLLAMA_LIB/vulkan" $P/ollama/lib/ollama/   # discrete GPUs (sysmedic-ai-device decides)
fi

for m in $MODELS; do
    name=${m%:*} tag=${m#*:}
    man=$OLLAMA_SRC_MODELS/manifests/registry.ollama.ai/library/$name/$tag
    sudo mkdir -p $P/ollama/models/manifests/registry.ollama.ai/library/$name
    sudo cp "$man" $P/ollama/models/manifests/registry.ollama.ai/library/$name/
    for d in $(sudo python3 -c "import json;m=json.load(open('$man'));print(' '.join([m['config']['digest']]+[l['digest'] for l in m['layers']]))"); do
        sudo cp --update=none "$OLLAMA_SRC_MODELS/blobs/${d/:/-}" $P/ollama/models/blobs/
    done
done

# Virus signatures for offline malware scans (owned by the image's clamav user so freshclam can update them)
sudo mkdir -p $P/clamav
sudo cp clamav/*.cvd clamav/*.sign $P/clamav/ 2>/dev/null || true
sudo chown -R 104:107 $P/clamav

sudo tee $P/README.txt >/dev/null <<'EOF'
SysMedic persistence partition (label FOG_AMB_PERSIST)

logs/      SysMedic and Ollama logs
backups/   data rescued from machines being repaired
sessions/  repair session records saved with menu option 3 (sync-back)
ollama/    offline AI: Ollama runtime (CPU) + the qwen2.5 model(s) listed in ollama/models (not on Stick Lite)
clamav/    ClamAV virus signatures (updated automatically when online)
private/   serial numbers from scans — kept away from the AI

SysMedic only mounts this partition when it is on the same USB stick it booted from.
EOF
sync
[ "$LITE" = 1 ] || sudo du -sh $P/ollama
df -h $P | tail -1
sudo umount pmnt

if [ "$XCHG_MIB" -gt 0 ]; then
    # The exchange partition: exFAT (Windows reads and writes it natively, Linux has a kernel driver, no 4 GB file limit)
    sudo mkfs.exfat -L SM_EXCHANGE "$XPART" >/dev/null
    mkdir -p xmnt
    sudo mount -o rw,uid="$(id -u)",gid="$(id -g)" "$XPART" xmnt
    [ -n "${XCHG_RESTORE:-}" ] && [ -f "$XCHG_RESTORE/SYSMEDIC.ID" ] && cp "$XCHG_RESTORE/SYSMEDIC.ID" xmnt/   # the drive keeps its identity
    python3 "$HERE/xchg_layout.py" populate xmnt --edition "$( [ "$LITE" = 1 ] && echo stick-lite || echo stick )" \
        --version "${SYSMEDIC_VERSION:-}" --collector "$XCHG_COLLECTOR"
    for d in INBOX EXPORT; do     # what an earlier exchange held (snapshots, reports) is put back; collector/ and README are fresh
        [ -n "${XCHG_RESTORE:-}" ] && [ -d "$XCHG_RESTORE/$d" ] && cp -a "$XCHG_RESTORE/$d"/. "xmnt/$d/"
    done
    sync
    sudo umount xmnt
fi
[ -n "$LOOP" ] && sudo losetup -d "$LOOP"
echo "done: $TARGET"
