# The exchange partition and portable snapshots

How a SysMedic drive talks to a **running** Windows machine without booting it, and how evidence comes back safely.

```
running Windows ─▶ SysMedic collector ─▶ portable snapshot ─▶ exchange partition (INBOX)
                    (read-only, YES)       (encrypted, age)       (the one thing Windows can see)
                                                                          │
                      job report ◀─ findings ◀─ analysis ◀─ sysmedic-snapshot import   (on SysMedic, later)
                                                                          │
                                                           (future, deliberate) export for Virtual Network Admin
```

Two ideas to keep apart:

> **exchange filesystem ≠ encryption.** The exchange partition is plain exFAT so any Windows machine can read it.
> **portable snapshot encryption ≠ SysMedic storage encryption.** Snapshots are encrypted with `age` for the trip
> between a customer's Windows and the engineer's SysMedic. SysMedic's own storage (sessions, backups, transcripts)
> is protected by the LUKS vault (`sysmedic-vault`), a different mechanism with a different key.

## 1. What Windows sees

Only one partition: **`SM_EXCHANGE`**. Everything else on the drive is hidden from Windows so it never gets a drive letter and never offers to "format the disk".

How: a GPT partition is given a drive letter by Windows only if its type is *Microsoft basic data* and its attributes do not say otherwise. On a stick the xorriso-built ISO partition (1) and its 300 KiB gap partition (3) are basic-data, so `build/xchg_layout.py hide` sets GPT attribute bits **62 (hidden)** and **63 (no drive letter)** on them. The other partitions are not basic-data (ESP `EF00`, persistence Linux `8300`, caddy root `8300`), which Windows does not mount. `hide` touches attribute bits only, never a partition's type, start, size or number, so UEFI (Secure Boot), legacy BIOS and Linux boot are unaffected. `xchg_layout.py check` lists what Windows would mount and fails if it is anything other than the exchange partition; `make-stick.sh` applies `hide` and `sysmedic-deploy` runs `check` after every stick write.

| Edition | Layout (after this change) |
|---|---|
| Stick | 1 ISO9660 (hidden) · 2 EFI (`EF00`) · 3 gap (hidden) · 4 `FOG_AMB_PERSIST` ext4 · **5 `SM_EXCHANGE` exFAT, last, 512 MiB** |
| Stick Lite | the same, exchange **256 MiB** (a 4 GB stick has little to spare; `XCHG_MIB=` overrides, `0` = none) |
| Caddy (new builds) | 1 ESP `SYSMEDIC` · 2 `sysmedic-root` ext4 · **3 `SM_EXCHANGE` exFAT, last, 1 GiB** |

Partitions 1–4 (stick) and 1–2 (caddy) keep their numbers, types and contents: the exchange partition is added **after** them, so nothing that finds `FOG_AMB_PERSIST` or the root by number or label changes.

**Filesystem: exFAT.** Windows (Vista SP1+/7+/10/11) and macOS read and write it natively; Linux has a kernel driver (`exfat`, in the stock kernel; `exfatprogs` is already installed); no 4 GB file limit (FAT32's) and no proprietary or FUSE code (NTFS would need `ntfs-3g`, and Windows would write a recycle bin and indexing metadata to it). It has no journal, so unplug cleanly; the collector writes a `.partial` file and renames it when complete. Label `SM_EXCHANGE` (11 characters, the exFAT maximum).

## 2. Contents

```
SYSMEDIC.ID      format, volume_id (random, per drive), edition, build, recipient (this drive's snapshot public key)
README.txt       for whoever finds the drive in Windows: what it is, what the collector does and never does
collector/       SysMedic-Collect.ps1, Run-SysMedic-Collector.cmd, age.exe (+ licence)
INBOX/           snapshots written by the collector (encrypted) and their envelopes
EXPORT/          files SysMedic hands back (reports); nothing writes here automatically yet
```

No drive letter is assumed anywhere: the collector finds the exchange root from its own location (`$PSScriptRoot\..`) and checks for `SYSMEDIC.ID`; SysMedic finds the partition by label **and** requires it to be on the disk it booted from (as `mount-persist` does for the persistence partition); `volume_id` in `SYSMEDIC.ID` names the volume. SysMedic mounts it `noexec,nosuid,nodev`, read-only except in `init`.

`SYSMEDIC.ID` holds only a random id and the public key: nothing about any customer. It survives a stick update (see below).

## 3. The Windows evidence collector (`tools/windows-collector/`)

Evidence only, **read-only** with respect to Windows, **not a repair tool**. Windows PowerShell 5.1 (every Windows 10/11); nothing to install. Launched deliberately: `Run-SysMedic-Collector.cmd` (right-click → run as administrator for full detail).

- **Inserting the drive collects nothing.** No autorun.
- **It says what it will gather** (`-ListOnly` shows the list and stops), then waits for the person to type `YES`. Anything else cancels; there is no unattended switch.
- **Offline, no call-home.** The script has no network code; the tests guard that. It only writes to the exchange drive's `INBOX`.
- **No plaintext on the customer's disk.** Evidence is built in memory, zipped in memory, encrypted by `age.exe` fed through a pipe, and only the ciphertext is written (to the exchange drive).
- **Refuses to run unencrypted:** no recipient in `SYSMEDIC.ID` or no `age.exe` → it stops before collecting anything.
- **Collects:** system/hardware identity, disk and SMART-style health, BitLocker *status*, installed updates and programs, services, startup entries, recent System/Application error events (7 days, 500 max), problem devices and key drivers, network adapters and addresses, Defender/firewall state, crash-dump file *names*.
- **Never collects:** documents, photos, browser data, passwords, saved Wi-Fi networks or keys, BitLocker recovery keys or protector details, user folders, file contents of any kind.
- Each item is a separate small read wrapped so one failure doesn't stop the rest; failures and empty results are recorded, not hidden.

Collection and diagnosis are separate by construction: the collector produces evidence and knows nothing about what is "wrong".

## 4. The portable snapshot

Two files in `INBOX/` per collection:

| File | Contents |
|---|---|
| `SM-<UTC time>-<8 hex>.smsnap.age` | the **container**: a zip encrypted with `age` |
| `SM-….envelope.json` | a small plaintext envelope: snapshot id, collector name/version, UTC time, container SHA-256 and size, a short fingerprint of the recipient key, the exchange `volume_id`. **No hostname, no evidence.** It lets SysMedic spot a damaged or substituted file before asking for the passphrase |

Inside the container (all of it encrypted):

```
manifest.json          provenance (below)
evidence/<item>.json   one file per item collected (bitlocker status is .txt)
```

### Provenance (`manifest.json`, `format: sysmedic-snapshot/1`)

| Field | |
|---|---|
| `snapshot_id`, `kind: raw-evidence` | the collection ID; says this is evidence, not findings |
| `collector` | name, version, SHA-256 of the script that ran, PowerShell version |
| `created_utc`, `finished_utc` | when |
| `consent` | the list was shown and confirmed, when, whether elevated, who ran it |
| `source` | hostname, manufacturer, model, OS (more identity — serial, machine GUID, product UUID — is in `evidence/system.json`) |
| `configuration` | options used (event days) and the items available |
| `evidence[]` | every file: item, path, SHA-256, size, the plain-English description the person agreed to |
| `failures[]`, `omissions[]` | what failed (with the error) and what returned nothing (e.g. needs administrator): absence is never silent |
| `integrity` | SHA-256 over every evidence file; and a note that this proves integrity, not who made it |

**Raw evidence, findings and conclusions stay apart.** On import (`sysmedic-snapshot import`) the evidence is written once, read-only, to `<visit>/snapshots/<id>/raw/`, with `import.json` recording when, by which SysMedic build, the container hash, the envelope check and the per-file hash check. Analysis writes to `<id>/findings/` (not built yet). The engineer's conclusions go in the job report. Nothing in `raw/` is ever edited. The import goes into the visit's own folder, so it is covered by the vault like the rest of the visit.

## 5. Encryption of snapshots: `age`

Chosen: **[age](https://age-encryption.org)** (filippo.io/age; X25519 key agreement, ChaCha20-Poly1305 streaming AEAD, HKDF; published specification; a single static Go binary for Windows; packaged in Ubuntu as `age`). No new cryptography is written here: SysMedic only calls the tools.

Why it fits: it can be created on Windows with one `age.exe` and no driver, installer or admin rights; the **customer's machine only ever holds the public key**, so it cannot decrypt what it just made; and it opens on SysMedic with the same tool. Alternatives rejected: BitLocker To Go / VeraCrypt volumes (need a Windows kernel driver or admin install on the customer's machine, and Linux support is a FUSE/proprietary-ish dance); password-protected zip or 7z (zip "ZipCrypto" is broken, AES zips depend on the unzip tool, a shared password has to be typed on the customer's machine); PowerShell/.NET hand-built AES (would mean inventing a construction: .NET Framework 4.x on PS 5.1 has no AES-GCM).

**Key model.** `sysmedic-snapshot init`, once per drive, on a SysMedic console: makes an X25519 key pair, keeps the private key only as an **age file encrypted with a passphrase you choose** (`/mnt/persist/private/snapshot-identity.age`, never stored bare, the bare key only ever exists in RAM during `init`), and writes the public key (`recipient=`) into `SYSMEDIC.ID` on the exchange partition. The collector encrypts to that public key. `import`/`verify` run `age -d`, which asks for the passphrase on the terminal. A drive with no key refuses collection; a second `init` refuses to replace the key (that would orphan existing snapshots).

**What this does and doesn't give you.**
- A lost or copied exchange partition or snapshot file reveals nothing without the SysMedic drive's private key *and* its passphrase.
- Tampering is detected (age authenticates the container; evidence hashes are checked; the envelope's hash catches a swapped file). It does **not** prove who made a snapshot: anyone with the public key (which is on the exchange partition) can create one, so treat a snapshot as evidence from whoever held the drive, not as signed testimony. Signing collectors is possible later.
- The public key, the volume id, snapshot ids, sizes and times, and the collector version are visible in plaintext. Hostnames and all evidence are not.
- If the passphrase is forgotten the snapshots are unrecoverable by design.
- `age.exe` is not stored in git. `tools/windows-collector/fetch-age.sh` downloads a pinned release (v1.2.1) and checks the SHA-256 pinned in the script. That pin was taken from the release at the time it was added; it stops a changed or corrupted download but does not itself prove authenticity (build age from source at the tag to cross-check). Change version and hash together, in one reviewed commit.

## 6. Privacy and consent (unchanged principles)

SysMedic still never calls home; this adds no network code, no telemetry and no cloud or VNA dependency, and the whole flow works offline. Nothing is collected on insertion. Each collection is started by a person, shown a list in plain English, and confirmed by typing YES. Import is also deliberate (`sysmedic-snapshot import`, console only) and audited in the visit's audit log. The AI never sees the snapshot unless the engineer chooses to show it something, and the usual consent and redaction rules for the cloud AI apply.

## 7. Direction: Virtual Network Admin

A snapshot is plain files plus a manifest, and import produces a self-describing directory (`raw/`, `import.json`). A future deliberate "export to VNA" would read from there; the boundary already exists, so no VNA code is added now. The sequence stays: evidence → snapshot → SysMedic analysis → findings → human-readable job report → (optional, deliberate) VNA export.

## 8. Existing drives

The caddies and sticks already in use have no exchange partition. A normal stick update (`sysmedic-deploy --stick`) rewrites the stick and creates one; the update saves and puts back `INBOX/`, `EXPORT/` and `SYSMEDIC.ID` of an existing exchange partition. For an existing caddy there is no automatic migration, because it would mean shrinking its customer-bearing root filesystem: until then, rebuild it (`bootstrap.sh caddy`) or add the partition offline by hand (shrink `sysmedic-root` with `e2fsck -f` + `resize2fs` from another machine, `sgdisk -n 3:0:0 -t 3:0700 -c 3:SM_EXCHANGE`, `mkfs.exfat -L SM_EXCHANGE`, `xchg_layout.py populate`). Nothing has been run against any existing drive.

## 9. Testing

`python3 build/tests/test_exchange.py` (42 tests): the Windows-visible layout on synthetic GPT images (only `SM_EXCHANGE` visible; types, starts, sizes, numbers unchanged by `hide`; ESP, persistence and exchange attributes untouched; idempotent), static guards on `make-stick.sh` and `sysmedic-deploy` (existing partitions made as before, MBR restored after every `sgdisk`, verification skips the new GPT entries), exFAT labelling, populate (contents, CRLF, identity and key survive updates), the collector's text (no write/network/secret commands, consent before collection, no plaintext to disk, no drive letter), and the snapshot round trip with real `age`: wrong key, damaged file, mismatched hash, unlisted file, path traversal, links, not-a-snapshot, double import, and the passphrase flow through a pseudo-terminal. A built Lite image was also booted in QEMU under UEFI with Secure Boot and under legacy BIOS.

**Needs real hardware (cannot be tested automatically):** see *Exchange partition on real Windows* in [HARDWARE-TESTING](HARDWARE-TESTING.md). In particular that Windows 10/11 shows only `SM_EXCHANGE` and never offers to format anything, and that `SysMedic-Collect.ps1` runs on real Windows 10 and 11 (it has been read, text-checked and not yet executed: no PowerShell was available where it was written).
