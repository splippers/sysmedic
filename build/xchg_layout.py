#!/usr/bin/env python3
"""xchg_layout.py — the SysMedic exchange partition: what Windows sees, and what goes on it.

  xchg_layout.py check DEV [--expect-exchange]   list the partitions Windows would give a drive letter; non-zero if any is
                                                 not the exchange partition (or, with --expect-exchange, if it is missing)
  xchg_layout.py hide DEV                        set the GPT "hidden" + "no drive letter" attributes (bits 62, 63) on every
                                                 basic-data partition that is not the exchange partition
  xchg_layout.py populate MOUNTPOINT --edition E [--version V] [--collector DIR]
                                                 write SYSMEDIC.ID, README.txt, collector/, INBOX/ and EXPORT/

DEV is a block device or a disk image file. Reading it needs root for a real device (sfdisk/sgdisk), not for an image.
Nothing here changes a partition's type, start, size or number, so UEFI, Secure Boot and legacy BIOS boot are untouched:
only attribute bits 62 and 63 are ever set, and only on basic-data partitions. See docs/EXCHANGE.md.
"""
import argparse
import datetime
import json
import subprocess
import sys
import uuid
from pathlib import Path

LABEL = "SM_EXCHANGE"                                   # exFAT labels hold 11 characters
BASIC_DATA = "EBD0A0A2-B9E5-4433-87C0-68B6B72699C7"     # the one GPT type Windows mounts and offers to format
BIT_HIDDEN, BIT_NO_LETTER = 62, 63


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"{' '.join(cmd)}: {r.stderr.strip() or r.stdout.strip()}")
    return r.stdout


def entries(dev):
    """Walk the GPT entries with sgdisk -p / -i so numbers match what sgdisk edits."""
    listing = run(["sgdisk", "-p", str(dev)]).splitlines()
    nums = []
    seen = False
    for line in listing:
        if line.startswith("Number"):
            seen = True
            continue
        if seen and line.strip():
            nums.append(int(line.split()[0]))
    out = []
    for n in nums:
        info = run(["sgdisk", "-i", str(n), str(dev)])
        e = {"number": n, "type": "", "name": "", "attrs": 0}
        for line in info.splitlines():
            if line.startswith("Partition GUID code:"):
                e["type"] = line.split(":", 1)[1].split()[0].upper()
            elif line.startswith("Partition name:"):
                e["name"] = line.split(":", 1)[1].strip().strip("'")
            elif line.startswith("Attribute flags:"):
                e["attrs"] = int(line.split(":", 1)[1].strip(), 16)
        out.append(e)
    return out


def windows_visible(parts):
    """Partitions Windows gives a drive letter: basic data, not flagged 'no drive letter'."""
    return [p for p in parts if p["type"] == BASIC_DATA and not p["attrs"] >> BIT_NO_LETTER & 1]


def cmd_check(a):
    parts = entries(a.dev)
    vis = windows_visible(parts)
    for p in parts:
        shown = p in vis
        print(f"  partition {p['number']}  {p['name'] or '-':<18} {p['type'][:8]}  {'VISIBLE to Windows' if shown else 'hidden from Windows'}")
    stray = [p for p in vis if p["name"] != LABEL]
    if stray:
        print(f"FAIL: Windows would offer a drive for partition(s) {', '.join(str(p['number']) for p in stray)} (not the exchange partition).")
        return 1
    if a.expect_exchange and not any(p["name"] == LABEL for p in vis):
        print(f"FAIL: no visible {LABEL} partition.")
        return 1
    print("OK: " + (f"Windows sees only the {LABEL} partition." if vis else "Windows sees no partition (no exchange partition on this drive)."))
    return 0


def cmd_hide(a):
    todo = [p for p in windows_visible(entries(a.dev)) if p["name"] != LABEL]
    for p in todo:
        run(["sgdisk", "-A", f"{p['number']}:set:{BIT_HIDDEN}", "-A", f"{p['number']}:set:{BIT_NO_LETTER}", str(a.dev)])
    print(f"hid {len(todo)} partition(s) from Windows: {', '.join(str(p['number']) for p in todo) or 'none'}")
    return 0


README = """\
SYSMEDIC EXCHANGE DRIVE
=======================

This is the part of a SysMedic repair drive that Windows can read. SysMedic is a
rescue system for repairing computers; the rest of the drive is hidden on purpose,
so Windows will not ask you to format it. If it does, say NO / Cancel.

  collector\\   a read-only evidence collector for Windows (see below)
  INBOX\\       snapshots made by the collector are written here (encrypted)
  EXPORT\\      reports and files SysMedic hands back to you
  SYSMEDIC.ID  identifies this drive (not a secret, nothing about you)

Nothing happens when you plug this in. Nothing is collected unless a person
starts the collector and agrees to it. Nothing is sent anywhere: the collector
works completely offline and only writes to this drive.

TO COLLECT EVIDENCE FROM THIS WINDOWS COMPUTER (optional, by the engineer)
  1. Open the "collector" folder on this drive.
  2. Double-click  Run-SysMedic-Collector.cmd  (Windows may ask for administrator
     permission: it needs it to read event logs, disk health and BitLocker status).
  3. Read what it lists, and type YES only if you agree. Type anything else to stop.
  4. When it finishes, leave the drive plugged in until it says "Done".

What it collects: system and hardware details, disk health, installed updates and
programs, services, startup entries, recent event-log errors, network settings,
BitLocker status. What it never collects: documents, photos, browsing history,
passwords, Wi-Fi keys, BitLocker recovery keys, or the contents of any user folder.
It does not change anything on this computer.

The result is ENCRYPTED to this SysMedic drive's key, so a lost drive or a copied
file reveals nothing. Only the SysMedic engineer's drive can open it.

More: docs/EXCHANGE.md in the SysMedic repository.
"""


def cmd_populate(a):
    root = Path(a.mountpoint)
    if not root.is_dir():
        sys.exit(f"{root}: not a directory")
    for d in ("collector", "INBOX", "EXPORT"):
        (root / d).mkdir(exist_ok=True)
    ident = root / "SYSMEDIC.ID"
    if not ident.exists():                                   # a drive keeps its identity across updates
        now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        ident.write_bytes(f"format=sysmedic-exchange/1\r\nvolume_id={uuid.uuid4()}\r\ncreated={now}\r\n".encode())
    lines = [l for l in ident.read_text().splitlines() if not l.startswith(("build=", "edition="))]
    lines += [f"edition={a.edition}", f"build={a.version or 'unknown'}"]
    ident.write_bytes(("\r\n".join(lines) + "\r\n").encode())
    (root / "README.txt").write_bytes(README.replace("\n", "\r\n").encode())
    src = Path(a.collector) if a.collector else None
    missing = []
    if src and src.is_dir():
        for f in sorted(src.iterdir()):
            if f.is_file() and f.suffix in (".ps1", ".cmd", ".txt", ".md", ".exe"):
                data = f.read_bytes()
                if f.suffix in (".ps1", ".cmd"):             # Windows tools want CRLF; keep the repo copies LF
                    data = data.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
                (root / "collector" / f.name).write_bytes(data)
        if not (root / "collector" / "age.exe").exists():
            missing.append("age.exe")
    else:
        missing.append("collector sources")
    if missing:
        print(f"warning: collector is incomplete (missing {', '.join(missing)}); run tools/windows-collector/fetch-age.sh", file=sys.stderr)
    print(f"exchange populated: {root}")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("check"); c.add_argument("dev"); c.add_argument("--expect-exchange", action="store_true"); c.set_defaults(f=cmd_check)
    h = sub.add_parser("hide"); h.add_argument("dev"); h.set_defaults(f=cmd_hide)
    p = sub.add_parser("populate"); p.add_argument("mountpoint"); p.add_argument("--edition", required=True)
    p.add_argument("--version", default=""); p.add_argument("--collector", default=""); p.set_defaults(f=cmd_populate)
    a = ap.parse_args()
    return a.f(a)


if __name__ == "__main__":
    sys.exit(main())
