# Building SysMedic from scratch

How to make a SysMedic **stick** or **caddy** starting from nothing but a build PC, the internet and this repo: the stock Ubuntu 24.04 ISO is downloaded, turned into SysMedic's system, and written to a drive. Once a drive exists, keep it current with `sysmedic-deploy` ([EDITIONS-AND-DEPLOY](EDITIONS-AND-DEPLOY.md)).

| | Stick | Caddy |
|---|---|---|
| Result | Live USB (read-only system + persistence partition) | Ubuntu installed on an external SSD (writable) |
| Drive | 16 GB+ USB stick (USB 3 recommended: [why](CAPABILITIES.md)) | 128 GB+ SSD in a USB 3 enclosure |
| Build time | ~45 min (+ ~20 min to write a USB 2.0 stick) | ~30 min |
| Downloads | ~4 GB ISO, ~7 GB AI models, ~2 GB packages (shared by both) | same kit |

## 1. Build PC prerequisites

An Ubuntu 24.04 (or newer) PC with **80 GB free**, internet and `sudo`:

```bash
sudo apt install git curl zstd python3 squashfs-tools xorriso grub-pc-bin gdisk parted \
                 dosfstools e2fsprogs rsync util-linux qemu-system-x86 ovmf
```

`grub-pc-bin` provides the hybrid MBR the stick boots from on BIOS PCs; `qemu-system-x86` and `ovmf` are for testing before you write a drive. Nothing else is installed on the PC: Ollama, OpenCode and the models are downloaded into the kit.

## 2. Get the repo and make a kit

```bash
git clone git@github.com:splippers/sysmedic.git ~/sysmedic-repo
~/sysmedic-repo/build/bootstrap.sh kit ~/sysmedic-kit
cd ~/sysmedic-kit
```

A **kit** is a working folder whose scripts link back to the repo (`staging`, `sysmedic-deploy`, `build-iso.sh`, `make-stick.sh`, `vm.py`, `bootstrap.sh`). Edit the repo, build from the kit.

## 3. Fetch (both editions)

```bash
./bootstrap.sh fetch
```

Downloads, with the versions pinned at the top of `build/bootstrap.sh`:
- **Ubuntu 24.04.5 live-server ISO**, verified against Ubuntu's `SHA256SUMS`
- **OpenCode 1.18.34** (the latest public release; SysMedic brands it at deploy time)
- **Ollama 0.23.4** (CPU runtime) and the offline models **qwen2.5:3b** and **qwen2.5:7b**, pulled into `./ollama-models` by a temporary Ollama run from the kit

Run it again any time; finished downloads are kept.

## 4a. Build a stick

```bash
./bootstrap.sh stick-base            # SysMedic's live system: root/, kernel/, efi.img (~15 min)
./sysmedic-deploy --stick-image      # SysMedic itself + packages → sysmedic-v2.iso, stick-test.img
```

What `stick-base` does:
1. Unpacks Ubuntu's server system from the ISO (the `minimal` layer with the `ubuntu-server` layer on top) into `root/`.
2. Installs, in a chroot: the **HWE kernel** (7.0), `linux-firmware`, `casper` (live boot), `memtest86+`, and fetches **ClamAV signatures** into `clamav/`.
3. Copies the kernel and initrd to `kernel/`, extracts the ISO's **UEFI boot image** to `efi.img`, and installs OpenCode.

Then `sysmedic-deploy --stick-image` adds everything SysMedic (scripts, AI instructions, docs, ~120 packages, the Wi-Fi initramfs fix, OpenCode branding) and builds the ISO from the stock Ubuntu ISO's boot files, without its installer layers.

**Test before writing** (UEFI with Secure Boot):
```bash
cp /usr/share/OVMF/OVMF_VARS_4M.ms.fd vars.fd
qemu-system-x86_64 -enable-kvm -cpu host -m 8G -smp 4 -machine q35,smm=on \
  -global driver=cfi.pflash01,property=secure,value=on \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.secboot.fd \
  -drive if=pflash,format=raw,file=vars.fd \
  -device qemu-xhci -drive if=none,id=usb,format=raw,file=stick-test.img,snapshot=on \
  -device usb-storage,drive=usb,bootindex=0
```
You should see the network screen, then the banner with the version and "Secure Boot on", the scan, and the assistant prompt. `-cpu host` matters: OpenCode needs AVX.

**Write it:**
```bash
./sysmedic-deploy --stick /dev/sdX   # checks it's a USB disk, writes, verifies byte-for-byte; ~20 min on USB 2.0
```
A stick that already has SysMedic gets its sessions backed up and restored around the write.

## 4b. Build a caddy

Put the SSD in a USB enclosure and plug it in. **It will be erased.** Check which `/dev/sdX` it is with `lsblk -o NAME,SIZE,MODEL,SERIAL`.

```bash
./bootstrap.sh caddy /dev/sdX        # asks you to type the device name to confirm
```

What it does:
1. Partitions the drive: a 512 MB EFI system partition (`SYSMEDIC`) and an ext4 root (`sysmedic-root`).
2. Unpacks Ubuntu's server system onto it, then sets up `fstab` (with the `/srv/sysmedic` → `/mnt/persist` bind), the hostname `sysmedic`, an empty machine ID (filled at first boot) and new SSH host keys.
3. Installs the HWE kernel, firmware and the **Secure Boot** boot loader (shim + signed GRUB) in the *removable* location, so it boots on any UEFI PC without a boot entry.
4. Copies the offline AI (Ollama + Qwen) and ClamAV signatures to `/srv/sysmedic`, installs OpenCode.
5. Runs `sysmedic-deploy --caddy` on it: SysMedic, the full toolkit in `/opt/sysmedic`, ~150 packages, the SysMedic boot menu.

To try it without a drive first, build into an image file and boot it in QEMU:
```bash
./bootstrap.sh caddy caddy-test.img  # a 40 GB sparse file
# then the QEMU command above with file=caddy-test.img
```

## 5. After building

- **Keep drives current:** edit the repo, then `./sysmedic-deploy --caddy` / `--stick` (see [EDITIONS-AND-DEPLOY](EDITIONS-AND-DEPLOY.md)). Both drives carry the same version stamp when their core matches (`/etc/sysmedic/version`).
- **Copying a caddy** instead of building one: an existing caddy can be cloned to a new SSD (partition with new IDs, `rsync -aHAXx` the system minus `/srv/sysmedic` customer data, fix `fstab` and the EFI `grub.cfg` UUIDs, `ssh-keygen -A`, empty `/etc/machine-id`, `update-grub`, then `sysmedic-deploy --caddy`). Building from scratch gives the same result.
- **Changing versions:** edit `OPENCODE_VERSION`, `OLLAMA_VERSION`, `UBUNTU_ISO` or `MODELS` at the top of `build/bootstrap.sh`, re-run `fetch`, rebuild, and test in QEMU before writing drives. OpenCode's branding patch (`build/opencode-brand.py`) is matched to the 1.18 and 2.0 layouts and says so if a new version changes them.

## Troubleshooting

| Problem | Fix |
|---|---|
| `missing 'xorriso'` (or another tool) | Install the prerequisites (section 1) |
| `ISO checksum mismatch` | Delete `downloads/*.iso` and run `fetch` again |
| `./root already exists` | `stick-base` won't overwrite a system you've built on; move `root/` away to start over |
| Package install failed during deploy | A temporary mirror problem: run the deploy again. If it persists, `sudo chroot root apt-get check` shows why |
| The stick boots the Ubuntu installer | The ISO was built with the installer layers in; rebuild with the current `build-iso.sh` |
| QEMU: OpenCode crashes immediately | Use `-cpu host` (it needs AVX) |
