#!/bin/bash
# Write sysmedic-v2.iso to TARGET (a block device or an image file), then add and
# populate the FOG_AMB_PERSIST persistence partition in the remaining space.
#   ./make-stick.sh /dev/sdX      — DESTROYS everything on /dev/sdX
#   ./make-stick.sh stick-test.img
set -euo pipefail
cd "$(dirname "$0")"
TARGET=$1
ISO=sysmedic-v2.iso
# Ollama runtime and models: from the kit if bootstrap.sh fetched them, else this PC's own Ollama install
OLLAMA_SRC_MODELS=$( [ -d ollama-models/manifests ] && echo "$PWD/ollama-models" || echo /usr/share/ollama/.ollama/models )
OLLAMA_BIN=$( [ -x downloads/ollama/bin/ollama ] && echo downloads/ollama/bin/ollama || echo /usr/local/bin/ollama )
OLLAMA_LIB=$( [ -d downloads/ollama/lib/ollama ] && echo downloads/ollama/lib/ollama || echo /usr/local/lib/ollama )
# The stick always runs the 3B model (sysmedic-ask's pick_model), so the 7B (4.7 GB) only goes on drives with room to spare:
# an 8 GB stick gets the 3B alone and keeps about 3 GB for the vault. Override with SYSMEDIC_MODELS="...".
tsize=$( [ -b "$TARGET" ] && sudo blockdev --getsize64 "$TARGET" || stat -c %s "$TARGET" )
if [ -n "${SYSMEDIC_MODELS:-}" ]; then MODELS=$SYSMEDIC_MODELS
elif [ "$tsize" -lt 14000000000 ]; then MODELS="qwen2.5:3b"
else MODELS="qwen2.5:3b qwen2.5:7b"; fi
echo "Models on this drive: $MODELS ($((tsize / 1000000000)) GB drive)"

sudo dd if="$ISO" of="$TARGET" bs=4M conv=fsync,notrunc status=none
sync

# Keep xorriso's hybrid MBR entries (protective 0xEE + boot flag) — sgdisk rewrites them
sudo dd if="$TARGET" of=mbr-parts.bin bs=1 skip=446 count=66 status=none
sudo sgdisk -e "$TARGET" >/dev/null                          # move backup GPT to the real end of disk
sudo sgdisk -a 2048 -n 4:0:0 -t 4:8300 -c 4:FOG_AMB_PERSIST "$TARGET" >/dev/null
sudo dd if=mbr-parts.bin of="$TARGET" bs=1 seek=446 conv=notrunc,fsync status=none
sudo sgdisk -v "$TARGET" | grep -q 'No problems found' || { echo "GPT verify failed"; exit 1; }

if [ -b "$TARGET" ]; then
    sudo partprobe "$TARGET"; sudo udevadm settle
    PART=$(lsblk -lnpo NAME "$TARGET" | sed -n 5p)            # disk + 4 partitions → 4th partition
    for p in $(lsblk -lnpo NAME "$TARGET" | tail -n +2); do   # the desktop may automount after partprobe
        findmnt -rno TARGET -S "$p" >/dev/null && sudo umount "$p"
    done
    LOOP=
else
    LOOP=$(sudo losetup -fP --show "$TARGET"); PART=${LOOP}p4
fi
sudo mkfs.ext4 -q -F -L FOG_AMB_PERSIST -m 0 "$PART"

mkdir -p pmnt
sudo mount "$PART" pmnt
P=pmnt
sudo mkdir -p $P/{logs,backups,sessions} $P/ollama/{bin,lib/ollama} $P/ollama/models/blobs
sudo cp "$OLLAMA_BIN" $P/ollama/bin/
sudo cp -a "$OLLAMA_LIB"/libggml-*.so* $P/ollama/lib/ollama/   # CPU backends
[ -d "$OLLAMA_LIB/vulkan" ] && sudo cp -a "$OLLAMA_LIB/vulkan" $P/ollama/lib/ollama/   # discrete GPUs (sysmedic-ai-device decides)

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
ollama/    offline AI: Ollama runtime (CPU) + the qwen2.5 model(s) listed in ollama/models
clamav/    ClamAV virus signatures (updated automatically when online)
private/   serial numbers from scans — kept away from the AI

SysMedic only mounts this partition when it is on the same USB stick it booted from.
EOF
sync
sudo du -sh $P/ollama
df -h $P | tail -1
sudo umount pmnt
[ -n "$LOOP" ] && sudo losetup -d "$LOOP"
echo "done: $TARGET"
