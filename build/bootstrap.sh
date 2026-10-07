#!/bin/bash
# bootstrap.sh — build SysMedic from scratch: stock Ubuntu 24.04 + this repo. No existing drive needed.
#
#   build/bootstrap.sh kit ~/sysmedic-kit     make a build folder (kit) linked to this repo; then cd into it
#   ./bootstrap.sh fetch                      Ubuntu ISO (checksum-verified), OpenCode, Ollama + Qwen models
#   ./bootstrap.sh stick-base                 the stick's system (root/), kernel/, boot image (efi.img)
#   ./sysmedic-deploy --stick-image           → sysmedic-v2.iso + stick-test.img (test in QEMU, docs/BUILDING.md)
#   ./sysmedic-deploy --stick /dev/sdX        write a stick
#   ./bootstrap.sh caddy /dev/sdX | FILE.img  build a caddy (an external SSD, or a disk image to test first)
#
# Everything is downloaded into the kit; nothing is installed on the build PC except via apt prerequisites
# (see docs/BUILDING.md). Versions are pinned below so builds are repeatable.
set -euo pipefail

UBUNTU_RELEASE=24.04
UBUNTU_ISO=ubuntu-24.04.5-live-server-amd64.iso
UBUNTU_URL=https://releases.ubuntu.com/$UBUNTU_RELEASE
OPENCODE_VERSION=1.18.34
OLLAMA_VERSION=0.23.4
MODELS="qwen2.5:3b qwen2.5:7b"
KERNEL=linux-generic-hwe-24.04         # kernel 7.0 on 24.04.5: current Wi-Fi/GPU support
CADDY_IMAGE_SIZE=40G                   # when building a caddy into an image file

REPO=$(cd "$(dirname "$(realpath "$0")")/.." && pwd)
say()  { echo -e "\033[1m==>\033[0m $*"; }
die()  { echo -e "\033[1;31mERROR:\033[0m $*" >&2; exit 1; }
need() { for c in "$@"; do command -v "$c" >/dev/null || die "missing '$c' on the build PC (see docs/BUILDING.md: prerequisites)"; done; }

# ── chroot with network; services can't start inside it ──────────────────────
CHROOT_MOUNTS=()
chroot_enter() {
    local r=$1 d
    for d in dev dev/pts proc sys; do sudo mount --bind "/$d" "$r/$d"; CHROOT_MOUNTS+=("$r/$d"); done
    sudo cp -P "$r/etc/resolv.conf" "$r/etc/resolv.conf.bootstrap" 2>/dev/null || true
    sudo rm -f "$r/etc/resolv.conf"; sudo cp -L /etc/resolv.conf "$r/etc/resolv.conf"
    printf '#!/bin/sh\nexit 101\n' | sudo tee "$r/usr/sbin/policy-rc.d" >/dev/null; sudo chmod 755 "$r/usr/sbin/policy-rc.d"
}
chroot_leave() {
    local r=$1 i
    sudo rm -f "$r/usr/sbin/policy-rc.d" "$r/etc/resolv.conf"
    [ -e "$r/etc/resolv.conf.bootstrap" ] || [ -L "$r/etc/resolv.conf.bootstrap" ] && sudo mv "$r/etc/resolv.conf.bootstrap" "$r/etc/resolv.conf"
    mountpoint -q "$r/sys/firmware/efi/efivars" && sudo umount "$r/sys/firmware/efi/efivars"
    for ((i = ${#CHROOT_MOUNTS[@]} - 1; i >= 0; i--)); do sudo umount "${CHROOT_MOUNTS[$i]}" 2>/dev/null || true; done
    CHROOT_MOUNTS=()
}
in_chroot() { local r=$1; shift; sudo chroot "$r" /usr/bin/env DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8 "$@"; }

iso_path() { echo "$PWD/downloads/$UBUNTU_ISO"; }
mount_iso() {
    [ -f iso/casper/ubuntu-server-minimal.squashfs ] && return
    mkdir -p iso; sudo mount -o loop,ro "$(iso_path)" iso
}

# Ubuntu's server system = the "minimal" layer with the "ubuntu-server" layer on top (as the installer lays it)
unpack_base() {
    local dst=$1 up=$PWD/.upper-layer c d
    mount_iso
    say "Unpacking Ubuntu $UBUNTU_RELEASE server into $dst (2–5 minutes)"
    sudo unsquashfs -f -q -d "$dst" iso/casper/ubuntu-server-minimal.squashfs >/dev/null
    sudo rm -rf "$up"
    sudo unsquashfs -q -d "$up" iso/casper/ubuntu-server-minimal.ubuntu-server.squashfs >/dev/null
    # Apply the upper layer the way overlayfs does: whiteouts (0:0 character devices) delete the lower
    # entry, opaque directories hide the lower directory's contents; then copy the upper layer over.
    while read -r c; do
        sudo rm -rf "$dst/${c#$up/}"; sudo rm -f "$c"
    done < <(sudo find "$up" -type c -printf '%p %r\n' 2>/dev/null | awk '$2 == "0:0" {print $1}')
    while read -r d; do
        sudo rm -rf "$dst/${d#$up/}"
    done < <(sudo getfattr -R --absolute-names -n trusted.overlay.opaque "$up" 2>/dev/null | sed -n 's/^# file: //p')
    sudo rsync -aHX --force "$up/" "$dst/"
    sudo rm -rf "$up"
}

base_packages() {     # kernel + firmware + whatever the edition needs to boot
    local r=$1; shift
    say "Installing kernel ($KERNEL), firmware and $* (downloads ~1 GB)"
    in_chroot "$r" apt-get update -qq
    in_chroot "$r" apt-get install -y -q --no-install-recommends "$KERNEL" linux-firmware memtest86+ "$@" 2>&1 | grep -E '^E:|newly installed' || true
    in_chroot "$r" apt-get clean
}

install_opencode() {   # pinned OpenCode release into ROOT/usr/local/bin
    sudo install -D -m 755 downloads/opencode/opencode "$1/usr/local/bin/opencode"
}

copy_ollama() {        # DEST/ollama: CPU + Vulkan runtime + Qwen models (the layout start-ollama expects)
    local dest=$1/ollama m name tag man d
    sudo mkdir -p "$dest/bin" "$dest/lib/ollama" "$dest/models/blobs"
    sudo cp downloads/ollama/bin/ollama "$dest/bin/"
    sudo cp -a downloads/ollama/lib/ollama/libggml-*.so* "$dest/lib/ollama/"
    [ -d downloads/ollama/lib/ollama/vulkan ] && sudo cp -a downloads/ollama/lib/ollama/vulkan "$dest/lib/ollama/"
    for m in $MODELS; do
        name=${m%:*} tag=${m#*:}; man=ollama-models/manifests/registry.ollama.ai/library/$name/$tag
        sudo install -D -m 644 "$man" "$dest/models/manifests/registry.ollama.ai/library/$name/$tag"
        for d in $(python3 -c "import json;m=json.load(open('$man'));print(' '.join([m['config']['digest']]+[l['digest'] for l in m['layers']]))"); do
            sudo cp --update=none "ollama-models/blobs/${d/:/-}" "$dest/models/blobs/"
        done
    done
}

# ── commands ──────────────────────────────────────────────────────────────────

cmd_kit() {
    local k=${1:?usage: bootstrap.sh kit DIR}
    mkdir -p "$k"; k=$(cd "$k" && pwd)
    for f in staging sysmedic-deploy build-iso.sh make-stick.sh vm.py bootstrap.sh; do ln -sfn "$REPO/build/$f" "$k/$f"; done
    say "Kit ready: $k  (scripts link to $REPO/build)"
    echo "    cd $k && ./bootstrap.sh fetch"
}

cmd_fetch() {
    need curl sha256sum tar zstd python3
    mkdir -p downloads
    say "Ubuntu $UBUNTU_RELEASE live-server ISO"
    curl -fsSL -o downloads/SHA256SUMS "$UBUNTU_URL/SHA256SUMS"
    iso_ok() { (cd downloads && grep " \*$UBUNTU_ISO\$" SHA256SUMS | sha256sum -c --quiet >/dev/null 2>&1); }
    if iso_ok; then
        echo "  already downloaded and verified"
    else
        curl -fL --progress-bar -o "downloads/$UBUNTU_ISO" "$UBUNTU_URL/$UBUNTU_ISO"
        iso_ok || die "ISO checksum mismatch (delete downloads/$UBUNTU_ISO and retry)"
        echo "  checksum OK"
    fi

    say "OpenCode $OPENCODE_VERSION"
    mkdir -p downloads/opencode
    curl -fsSL "https://github.com/anomalyco/opencode/releases/download/v$OPENCODE_VERSION/opencode-linux-x64.tar.gz" | tar -xz -C downloads/opencode
    downloads/opencode/opencode --version

    say "Ollama $OLLAMA_VERSION"
    rm -rf downloads/ollama; mkdir -p downloads/ollama
    curl -fsSL "https://github.com/ollama/ollama/releases/download/v$OLLAMA_VERSION/ollama-linux-amd64.tar.zst" | zstd -dc | tar -x -C downloads/ollama
    rm -rf downloads/ollama/lib/ollama/cuda_* downloads/ollama/lib/ollama/rocm* 2>/dev/null || true   # CPU only

    say "Offline models: $MODELS (about 6.6 GB, into ./ollama-models)"
    mkdir -p ollama-models
    OLLAMA_MODELS=$PWD/ollama-models OLLAMA_HOST=127.0.0.1:11499 downloads/ollama/bin/ollama serve >ollama-fetch.log 2>&1 &
    local pid=$!; trap 'kill $pid 2>/dev/null' EXIT
    for _ in $(seq 1 30); do curl -sf http://127.0.0.1:11499/api/version >/dev/null && break; sleep 1; done
    for m in $MODELS; do OLLAMA_HOST=127.0.0.1:11499 downloads/ollama/bin/ollama pull "$m"; done
    kill $pid; trap - EXIT
    say "Fetched. Next: ./bootstrap.sh stick-base   (and/or ./bootstrap.sh caddy TARGET)"
}

cmd_stick_base() {
    need unsquashfs sfdisk xorriso python3
    [ -f "$(iso_path)" ] || die "no $UBUNTU_ISO (run ./bootstrap.sh fetch)"
    [ -e root ] && die "./root already exists; move it away to rebuild the stick system from scratch"
    mount_iso
    say "UEFI boot image (efi.img) from the ISO's EFI partition"
    local start size
    read -r start size < <(sfdisk -J "$(iso_path)" | python3 -c "import json,sys;p=[x for x in json.load(sys.stdin)['partitiontable']['partitions'] if x['type'].upper().startswith('C12A7328')][0];print(p['start'],p['size'])")
    dd if="$(iso_path)" of=efi.img bs=512 skip="$start" count="$size" status=none
    unpack_base root
    chroot_enter root
    trap 'chroot_leave root' EXIT
    base_packages root casper clamav-freshclam
    say "ClamAV signatures (for offline malware scans)"
    mkdir -p clamav
    in_chroot root sh -c 'mkdir -p /tmp/cvd && chown clamav /tmp/cvd && freshclam --quiet --datadir=/tmp/cvd 2>/tmp/fc.err; rc=$?; grep -v NotifyClamd /tmp/fc.err >&2; rm -f /tmp/fc.err; exit $rc' || say "  (freshclam failed: the stick will fetch signatures when online)"
    sudo sh -c 'cp root/tmp/cvd/*.c[vl]d clamav/ 2>/dev/null; rm -rf root/tmp/cvd' || true
    chroot_leave root; trap - EXIT
    say "Kernel and initrd for the boot menu"
    local kv; kv=$(ls root/usr/lib/modules | sort -V | tail -1)
    mkdir -p kernel
    sudo cp "root/boot/vmlinuz-$kv" kernel/vmlinuz; sudo cp "root/boot/initrd.img-$kv" kernel/initrd
    sudo chmod 644 kernel/vmlinuz kernel/initrd
    sudo rm -f root/boot/vmlinuz* root/boot/initrd.img*      # the live system boots kernel/ from the ISO
    install_opencode root
    say "Stick system ready ($kv). Next: ./sysmedic-deploy --stick-image, then test in QEMU (docs/BUILDING.md)"
}

cmd_caddy() {
    local target=${1:?usage: bootstrap.sh caddy /dev/sdX | FILE.img} dev loop= m=caddy-root
    need sgdisk mkfs.vfat mkfs.ext4 unsquashfs rsync
    [ -f "$(iso_path)" ] && [ -d ollama-models ] || die "run ./bootstrap.sh fetch first"
    if [ -b "$target" ]; then
        dev=$target
        local host; host=$(lsblk -no PKNAME "$(findmnt -no SOURCE /)" | head -1)
        [ "${dev#/dev/}" != "$host" ] || die "$dev is this PC's own disk"
        echo "  This ERASES $dev: $(lsblk -dno SIZE,TRAN,MODEL,SERIAL "$dev" | xargs)"
        lsblk -o NAME,SIZE,FSTYPE,LABEL "$dev" | sed 's/^/    /'
        read -r -p "  Type the device name ($dev) to continue: " ok; [ "$ok" = "$dev" ] || die "cancelled"
        for p in $(lsblk -lnpo NAME "$dev" | tail -n +2); do findmnt -rno TARGET -S "$p" >/dev/null && sudo umount "$p"; done
    else
        [ -e "$target" ] && die "$target exists; remove it first"
        truncate -s "$CADDY_IMAGE_SIZE" "$target"
        loop=$(sudo losetup -fP --show "$target"); dev=$loop
    fi
    say "Partitioning $dev: EFI system partition + SysMedic root"
    sudo wipefs -aq "$dev"
    sudo sgdisk -Z -n1:0:+512M -t1:ef00 -c1:ESP -n2:0:0 -t2:8300 -c2:primary "$dev" >/dev/null
    sudo partprobe "$dev" 2>/dev/null || true; sudo udevadm settle
    local p1 p2; p1=$(lsblk -lnpo NAME "$dev" | sed -n 2p); p2=$(lsblk -lnpo NAME "$dev" | sed -n 3p)
    sudo mkfs.vfat -F 32 -n SYSMEDIC "$p1" >/dev/null
    sudo mkfs.ext4 -q -F -L sysmedic-root "$p2"
    mkdir -p "$m"; sudo mount "$p2" "$m"
    trap 'chroot_leave "$m"; sudo umount "$m/boot/efi" "$m" 2>/dev/null; [ -n "$loop" ] && sudo losetup -d "$loop"' EXIT
    unpack_base "$m"
    sudo mkdir -p "$m/boot/efi"; sudo mount "$p1" "$m/boot/efi"
    say "Machine setup: disks, hostname, fresh identity"
    sudo tee "$m/etc/fstab" >/dev/null <<EOF
UUID=$(sudo blkid -s UUID -o value "$p2") / ext4 rw,errors=remount-ro 0 1
UUID=$(sudo blkid -s UUID -o value "$p1") /boot/efi vfat umask=0077 0 2
/srv/sysmedic /mnt/persist none bind 0 0
EOF
    echo sysmedic | sudo tee "$m/etc/hostname" >/dev/null
    printf '127.0.0.1 localhost\n127.0.1.1 sysmedic\n' | sudo tee "$m/etc/hosts" >/dev/null
    sudo truncate -s 0 "$m/etc/machine-id"
    sudo mkdir -p "$m"/srv/sysmedic/{sessions,transcripts,claude-review,private,backups,logs,clamav} "$m/mnt/persist"
    sudo chmod 700 "$m/srv/sysmedic/private"
    chroot_enter "$m"
    base_packages "$m" grub-efi-amd64-signed shim-signed efibootmgr openssh-client
    in_chroot "$m" ssh-keygen -A >/dev/null 2>&1 || true
    say "Boot loader (Secure Boot shim; boots on any UEFI PC, no NVRAM entry needed)"
    in_chroot "$m" grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu --uefi-secure-boot --no-nvram >/dev/null
    in_chroot "$m" grub-install --target=x86_64-efi --efi-directory=/boot/efi --uefi-secure-boot --removable --no-nvram >/dev/null
    in_chroot "$m" update-grub 2>&1 | grep -E '^Found linux' || true
    chroot_leave "$m"
    say "Offline AI (Ollama + Qwen), ClamAV signatures, OpenCode"
    copy_ollama "$m/srv/sysmedic"
    sudo cp clamav/*.c[vl]d "$m/srv/sysmedic/clamav/" 2>/dev/null || true
    install_opencode "$m"
    sync; sudo umount "$m/boot/efi" "$m"; trap - EXIT
    say "Installing SysMedic onto it (sysmedic-deploy --caddy)"
    ./sysmedic-deploy --caddy "$dev"
    [ -n "$loop" ] && sudo losetup -d "$loop"
    say "Caddy built on $target. Test it in QEMU before use (docs/BUILDING.md)."
}

case "${1:-}" in
    kit)        cmd_kit "${2:-}" ;;
    fetch)      cmd_fetch ;;
    stick-base) cmd_stick_base ;;
    caddy)      cmd_caddy "${2:-}" ;;
    *)          sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
