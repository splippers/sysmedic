# Editions, the build kit and deploying

## The two editions

| | Caddy: the workshop | Stick: the grab-bag |
|---|---|---|
| Medium | Samsung NVMe in a Realtek RTL9210 USB 3 enclosure | 14 GB USB 2.0 stick |
| System | Installed Ubuntu 24.04 (ext4, writable; `apt install` persists) | Live ISO: compressed read-only squashfs, changes in RAM, clean every boot |
| Data | `/srv/sysmedic` (bind-mounted at `/mnt/persist`) | Persistence partition `FOG_AMB_PERSIST`, mounted at `/mnt/persist` |
| Extras | Deep recovery (safecopy, foremost, scalpel, ext4magic…), imaging (partclone, fsarchiver), nwipe, APFS read-only, yara/rkhunter/chkrootkit, comfort tools, **advanced toolkit** (menu 15), **stick-session collector** | Lean on purpose; hands imaging/burn-in/macOS jobs to the caddy |
| Kernel fallback | 6.8 under *Advanced options* | — |

Shared on both: the triage scan, guard, audit, assistants, Windows toolkit, hardware tests, network toolkit, reports, dashboard, transcripts and docs.

## Source of truth

```
build/staging/shared/         installed identically on both (root-relative paths)
build/staging/editions/caddy  caddy-only files (sysmedic-collect + udev rule + service)
build/staging/editions/stick  stick-only files (none at present)
build/staging/agent/          AI instructions: core.md + caddy.md / stick.md toolkit section
build/staging/packages/       shared.txt, caddy.txt, stick.txt, mask.txt
build/staging/iso/            the stick's GRUB menu (adds MemTest86+ for UEFI)
docs/, README.md              installed on both at /usr/local/share/doc/sysmedic (sysmedic-help)
```

**Change these, then deploy. Don't edit the drives directly.**

## `build/sysmedic-deploy`

```
./sysmedic-deploy --version          the version the shared core would get
./sysmedic-deploy --caddy [/dev/sdX] update the caddy in place (autodetected)
./sysmedic-deploy --stick-image      rebuild the stick image only (sysmedic-v2.iso + stick-test.img)
./sysmedic-deploy --stick [/dev/sdX] rebuild, back up the stick's data, write, verify, restore
```

Each deploy:
1. Copies `shared/` and the edition's files.
2. Assembles the AI instructions and installs the docs.
3. Installs any missing packages from the lists (in a chroot) and masks the listed services.
4. Writes `/etc/sysmedic/edition` and `/etc/sysmedic/version`.
5. Rebuilds the initramfs if a hook changed.

The stick deploy then builds the ISO and the test image, backs up the persistence partition to `stick-sessions-backup/`, writes the stick, checks it against the tested image, and restores the data. Run it and check its exit code; don't filter its output.

**Version** = date + the first 8 hex digits of the SHA-256 of `shared/`. Both drives show the same version when their shared core matches: in the boot banner, the scan header, the menu, reports and review bundles.

## The build directory

`~/sysmedic-build` holds the large artifacts and links its sources to this repo:
- `root/` (the stick's live root filesystem)
- `iso/` (the original v1 ISO tree, mounted read-only)
- `kernel/` (the stick's vmlinuz + initrd)
- `clamav/` (signatures)
- `sysmedic-v2.iso`, `stick-test.img`
- `tests/` (patient disk images)

Rebuilding from scratch needs the Ubuntu Server 24.04.3 live ISO and a pass through the original remaster steps; `root/` is the maintained state.

Offline AI models (Ollama runtime + qwen2.5 3b/7b + jonotron) are copied from the build PC's Ollama store by `make-stick.sh` (stick) or once onto the caddy's `/srv/sysmedic/ollama`.

## Testing (QEMU)

- **Stick:** boot `stick-test.img` as a USB disk (`-device usb-storage`), with `snapshot=on`.
- **Caddy:** boot the real drive read-only via `sudo qemu … file=/dev/sdX,snapshot=on`.
- **Secure Boot:** `OVMF_CODE_4M.secboot.fd` + `OVMF_VARS_4M.ms.fd`, `-machine q35,smm=on`. **BIOS:** `-machine pc`.
- **Use `-cpu host`:** OpenCode (Bun) crashes without AVX.
- **Patient disks:** `tests/make-windows-tree.sh` + `make-windows-fixture.py`, from fixtures fetched by `tests/fetch-fixtures.sh` (cryptsetup BitLocker volumes, a hivex minimal hive, python-evtx event logs). A "writable patient disk unchanged" hash check proves the scan is read-only.
- **`build/vm.py`** drives QEMU's monitor (screenshots, typing). The caddy uses a UK keymap, so avoid `|` and `"` in typed text.

## Collecting stick sessions on the caddy

Plug the stick into a running caddy. A udev rule starts `sysmedic-collect`, which checks it's a SysMedic stick (persistence label plus SysMedic ISO on the same disk), mounts it read-only, and copies across only new sessions, transcripts, review bundles and private files into `/srv/sysmedic`. It reports on console 2. Manual: `sysmedic-collect`.
