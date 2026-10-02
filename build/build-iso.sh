#!/bin/bash
# Rebuild sysmedic-v2.iso from ./root (the live root filesystem) and ./iso (the mounted v1 image).
set -euo pipefail
cd "$(dirname "$0")"
I=$PWD/iso
EXCL="boot.catalog md5sum.txt pool dists casper/initrd.new casper/ubuntu-server-minimal.squashfs.bak
      casper/ubuntu-server-minimal.squashfs.gpg casper/ubuntu-server-minimal.squashfs boot/grub/grub.cfg.orig
      casper/vmlinuz casper/initrd boot/grub/grub.cfg boot/memtest86+x64.bin"

sudo mksquashfs root newiso-ubuntu-server-minimal.squashfs -comp zstd -b 1M -noappend -quiet

build() {
    xorriso -as mkisofs -r -V SYSMEDIC_2404 -o sysmedic-v2.iso \
      --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img -partition_offset 16 --mbr-force-bootable \
      -append_partition 2 28732ac11ff8d211ba4b00a0c93ec93b "$I/efi.img" -appended_part_as_gpt \
      -iso_mbr_part_type a2a0d0ebe5b9334487c068b6b72699c7 \
      -c /boot.catalog -b /boot/grub/i386-pc/eltorito.img -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info \
      -eltorito-alt-boot -e '--interval:appended_partition_2:::' -no-emul-boot \
      $(for e in $EXCL; do printf -- '-m %s/%s ' "$I" "$e"; done) \
      -graft-points /="$I" /md5sum.txt="$PWD/md5sum.txt" \
      /casper/ubuntu-server-minimal.squashfs="$PWD/newiso-ubuntu-server-minimal.squashfs" \
      /casper/vmlinuz="$PWD/kernel/vmlinuz" /casper/initrd="$PWD/kernel/initrd" \
      /boot/grub/grub.cfg="$PWD/staging/iso/boot/grub/grub.cfg" \
      /boot/memtest86+x64.bin="$PWD/root/boot/memtest86+x64.bin" /boot/memtest86+x64.efi="$PWD/root/boot/memtest86+x64.efi" 2>&1 | grep -E 'produced|FAIL' || true
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
