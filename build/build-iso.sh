#!/bin/bash
# Rebuild sysmedic-v2.iso from ./root (the live root filesystem) and ./iso (a mounted base image: the original
# v1 SysMedic ISO, or for a from-scratch kit the stock Ubuntu 24.04 live-server ISO; see build/bootstrap.sh).
set -euo pipefail
cd "$(dirname "$0")"
I=$PWD/iso
# ./iso is the base image, loop-mounted read-only; mount it if it isn't (e.g. after a reboot)
BASE=$( [ -f sysmedic-v1-hybrid.iso ] && echo sysmedic-v1-hybrid.iso || ls downloads/ubuntu-24.04*-live-server-amd64.iso 2>/dev/null | tail -1 )
if [ ! -f "$I/boot/grub/i386-pc/eltorito.img" ]; then
    [ -n "$BASE" ] || { echo "ERROR: ./iso isn't mounted and there's no base ISO (run bootstrap.sh fetch)" >&2; exit 1; }
    mkdir -p "$I" && sudo mount -o loop,ro "$BASE" "$I"
fi
# The UEFI boot image: a file in the v1 tree; for the stock ISO, extracted by bootstrap.sh into ./efi.img
EFI_IMG=$( [ -f "$I/efi.img" ] && echo "$I/efi.img" || echo "$PWD/efi.img" )
[ -f "$EFI_IMG" ] || { echo "ERROR: no efi.img (run bootstrap.sh stick-base)" >&2; exit 1; }
EXCL="boot.catalog md5sum.txt pool dists casper/initrd.new casper/ubuntu-server-minimal.squashfs.bak
      casper/ubuntu-server-minimal.squashfs.gpg casper/ubuntu-server-minimal.squashfs boot/grub/grub.cfg.orig
      casper/vmlinuz casper/initrd boot/grub/grub.cfg boot/memtest86+x64.bin
      casper/ubuntu-server-minimal.ubuntu-server.squashfs casper/ubuntu-server-minimal.ubuntu-server.squashfs.gpg"
# The stock ISO's installer layers (and their manifests): without them casper boots SysMedic, not the installer
EXCL="$EXCL $(cd "$I" && { ls -d casper/*installer* casper/hwe-* 2>/dev/null || true; } | tr '\n' ' ')"

sudo mksquashfs root newiso-ubuntu-server-minimal.squashfs -comp zstd -b 1M -noappend -quiet
# casper stacks the stock ubuntu-server layer ON TOP of ./root. Our root already contains everything in it,
# and its stale copies hid ours (e.g. /etc/group without netdev, so wpa_supplicant never started), so it
# ships empty.
mkdir -p empty-layer && rm -f empty-layer.squashfs
mksquashfs empty-layer empty-layer.squashfs -noappend -quiet >/dev/null

build() {
    xorriso -as mkisofs -r -V SYSMEDIC_2404 -o sysmedic-v2.iso \
      --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img -partition_offset 16 --mbr-force-bootable \
      -append_partition 2 28732ac11ff8d211ba4b00a0c93ec93b "$EFI_IMG" -appended_part_as_gpt \
      -iso_mbr_part_type a2a0d0ebe5b9334487c068b6b72699c7 \
      -c /boot.catalog -b /boot/grub/i386-pc/eltorito.img -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info \
      -eltorito-alt-boot -e '--interval:appended_partition_2:::' -no-emul-boot \
      $(for e in $EXCL; do printf -- '-m %s/%s ' "$I" "$e"; done) \
      -graft-points /="$I" /md5sum.txt="$PWD/md5sum.txt" \
      /casper/ubuntu-server-minimal.squashfs="$PWD/newiso-ubuntu-server-minimal.squashfs" \
      /casper/ubuntu-server-minimal.ubuntu-server.squashfs="$PWD/empty-layer.squashfs" \
      /casper/vmlinuz="$PWD/kernel/vmlinuz" /casper/initrd="$PWD/kernel/initrd" \
      /boot/grub/grub.cfg="$PWD/staging/iso/boot/grub/grub.cfg" \
      /boot/memtest86+x64.bin="$PWD/root/boot/memtest86+x64.bin" /boot/memtest86+x64.efi="$PWD/root/boot/memtest86+x64.efi" > xorriso.log 2>&1 || true
    # Fail loudly: a failed xorriso used to leave the previous ISO in place, unnoticed
    grep -q 'produced' xorriso.log || { grep -E 'FAILURE|SORRY|aborting' xorriso.log >&2; echo "ERROR: ISO build failed (xorriso.log)" >&2; exit 1; }
    grep -E 'produced' xorriso.log
}

# Two passes: build, checksum the result's own contents, rebuild with that md5sum.txt
touch md5sum.txt
build
mkdir -p v2mnt
sudo mount -o loop,ro sysmedic-v2.iso v2mnt
(cd v2mnt && find . -type f ! -name md5sum.txt ! -name boot.catalog -print0 | sort -z | xargs -0 md5sum) > md5sum.txt
sudo umount v2mnt
build
sudo mount -o loop,ro sysmedic-v2.iso v2mnt
(cd v2mnt && md5sum -c --quiet md5sum.txt) && echo "md5 all OK"
sudo umount v2mnt
ls -lh sysmedic-v2.iso
