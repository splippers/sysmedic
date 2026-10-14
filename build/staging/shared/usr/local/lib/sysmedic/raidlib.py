"""raidlib — Linux software RAID (mdadm, Intel/IMSM firmware RAID) and LVM on the machine being repaired.

Everything here is read-only for the customer's data: arrays are started with `--readonly` (a degraded array is
started too, so a RAID 1 with one dead disk still gives its data), the md and LVM devices are marked read-only, and
nothing is ever written to a member disk (not even a resync). Stale members (a disk that dropped out earlier and
holds older data) are left out, as mdadm does by default.
"""
import glob
import json
import os
import re
import subprocess
import tempfile

RAID_FS = ("linux_raid_member", "isw_raid_member", "ddf_raid_member")
RUN = "/run/sysmedic/raid"


def run(cmd, timeout=120):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout, p.stderr
    except (OSError, subprocess.TimeoutExpired) as e:
        return 127, "", str(e)


def audit(msg):
    try:
        import session
        session.audit("raid", msg)
    except Exception:  # noqa: BLE001  (no session yet: the record is a courtesy)
        pass


def own_disk():
    """The disk SysMedic itself runs from (never touched)."""
    src = run(["findmnt", "-no", "SOURCE", "/cdrom"])[1].strip() or run(["findmnt", "-no", "SOURCE", "/"])[1].strip()
    if not src.startswith("/dev/"):
        return None
    return (run(["lsblk", "-no", "PKNAME", src])[1].split() or [None])[0]


def _flatten(nodes, parent_disk=None, out=None):
    out = [] if out is None else out
    for n in nodes:
        disk = parent_disk or (n["name"] if n.get("type") == "disk" else None)
        out.append(dict(n, disk=disk))
        _flatten(n.get("children") or [], disk, out)
    return out


def members():
    run(["udevadm", "settle", "--timeout=5"])
    """Disks and partitions carrying RAID metadata, except SysMedic's own drive."""
    rc, out, _ = run(["lsblk", "-J", "-p", "-o", "NAME,KNAME,TYPE,FSTYPE,SIZE,MODEL"])
    if rc != 0:
        return []
    skip = own_disk()
    seen, res = set(), []
    for n in _flatten(json.loads(out).get("blockdevices", [])):
        if n.get("fstype") not in RAID_FS or n["name"] in seen:
            continue
        if skip and os.path.basename(n["disk"] or "") == skip:
            continue
        seen.add(n["name"])
        res.append(n)
    return res


def _hex(s):
    return re.sub(r"[^0-9a-f]", "", s.lower())


def examine(dev):
    rc, out, err = run(["mdadm", "--examine", dev], timeout=30)
    if rc != 0:
        lines = (err or out).strip().splitlines()
        return {"dev": dev, "error": lines[-1] if lines else "unreadable"}
    f = {}
    for key, rx in [("uuid", r"^\s*Array UUID\s*:\s*(\S+)"), ("uuid2", r"^\s*UUID\s*:\s*(\S+)"),
                    ("name", r"^\s*Name\s*:\s*(\S+)"), ("level", r"^\s*Raid Level\s*:\s*(\S+)"),
                    ("expected", r"^\s*Raid Devices\s*:\s*(\d+)"), ("expected2", r"^\s*Disks\s*:\s*(\d+)"),
                    ("events", r"^\s*Events\s*:\s*(\d+)"), ("role", r"^\s*Device Role\s*:\s*(.+)"),
                    ("state", r"^\s*State\s*:\s*(.+)"), ("magic", r"^\s*Magic\s*:\s*(.+)"),
                    ("version", r"^\s*Version\s*:\s*(\S+)"), ("array_state", r"^\s*Array State\s*:\s*(\S+)")]:
        m = re.search(rx, out, re.M | re.I)
        f[key] = m.group(1).strip() if m else ""
    imsm = "matrix" in f["magic"].lower() or "intel" in f["magic"].lower()
    level = f["level"] or ""
    if not level:
        m = re.search(r"^\s*RAID Level\s*:\s*(\S+)", out, re.M)
        level = m.group(1) if m else ""
    if level.isdigit():
        level = "raid" + level
    name = f["name"].split(":", 1)[-1] if f["name"] else ""
    return {"dev": dev, "uuid": _hex(f["uuid"] or f["uuid2"]), "name": name, "level": level or ("imsm" if imsm else "?"),
            "meta": "imsm" if imsm else f["version"], "expected": int(f["expected"] or f["expected2"] or 0),
            "events": int(f["events"] or 0), "role": f["role"], "state": f["state"], "array_state": f["array_state"]}


def running():
    """Arrays the kernel is running now: [{md, level, state, degraded, disks, members}]."""
    res = []
    for p in sorted(glob.glob("/sys/block/md*")):
        name = os.path.basename(p)
        rd = lambda f: open(f"{p}/md/{f}").read().strip() if os.path.exists(f"{p}/md/{f}") else ""  # noqa: E731
        if not rd("level") or rd("array_state") in ("", "clear"):
            continue
        mem = [os.path.basename(os.path.realpath(b)) for b in glob.glob(f"{p}/md/dev-*/block")]
        res.append({"md": f"/dev/{name}", "level": rd("level"), "state": rd("array_state"),
                    "degraded": int(rd("degraded") or 0), "disks": int(rd("raid_disks") or 0), "members": sorted(mem),
                    "container": rd("level") == "container", "sync": rd("sync_action")})
    return res


def status():
    mem = members()
    ex = [examine(m["name"]) for m in mem]
    live = running()
    live_members = {x for a in live for x in a["members"]}
    groups = {}
    for e in ex:
        if e.get("error") or e["dev"] in ("",):
            continue
        base = os.path.basename(e["dev"])
        if base in live_members:
            continue
        g = groups.setdefault(e["uuid"], {"uuid": e["uuid"], "name": e["name"], "level": e["level"], "meta": e["meta"],
                                          "expected": e["expected"], "members": []})
        g["members"].append({"dev": e["dev"], "events": e["events"], "role": e["role"], "state": e["state"]})
    # disks of a running array that mdadm left out (they dropped out earlier and hold older data)
    live_uuid = {e["uuid"]: a for e in ex if not e.get("error") and os.path.basename(e["dev"]) in live_members
                 for a in live if os.path.basename(e["dev"]) in a["members"]}
    for u, g in list(groups.items()):
        if u in live_uuid:
            live_uuid[u].setdefault("left_out", []).extend(m["dev"] for m in g["members"])
            del groups[u]
    unstarted = []
    for g in groups.values():
        top = max((m["events"] for m in g["members"]), default=0)
        for m in g["members"]:
            m["stale"] = bool(top and m["events"] < top)
        fresh = [m for m in g["members"] if not m["stale"]]
        g["present"], g["fresh"] = len(g["members"]), len(fresh)
        unstarted.append(g)
    return {"members": [m["name"] for m in mem], "running": live, "unstarted": unstarted,
            "unreadable": [e["dev"] for e in ex if e.get("error")]}


def need_disks(level, expected, present):
    """How many members the array needs to start."""
    if level == "raid1":
        return 1
    if level in ("raid4", "raid5"):
        return max(expected - 1, 1)
    if level == "raid6":
        return max(expected - 2, 1)
    if level == "raid10":
        return max(expected // 2 + 1, 1)         # at least one copy of every stripe (a guess: mdadm decides)
    return expected                               # raid0, linear: all of them


def _devnames(conf_text):
    """Number the arrays (md100…): names from other hosts can't be used as device names."""
    out, n = [], 100
    for line in conf_text.splitlines():
        if not line.startswith("ARRAY"):
            continue
        parts = line.split()
        rest = [x for x in parts[1:] if not x.startswith("/dev/")]
        out.append("ARRAY /dev/md%d %s" % (n, " ".join(rest)))
        n += 1
    return "\n".join(out) + "\n"


def lvm(*args, timeout=120):
    return run(["lvm", *args], timeout=timeout)


def activate_lvm():
    """Activate volume groups, then mark every logical volume read-only. Returns the VG names found."""
    rc, out, _ = lvm("vgs", "--noheadings", "-o", "vg_name")
    vgs = out.split() if rc == 0 else []
    for vg in vgs:
        lvm("vgchange", "-ay", "--noudevsync", vg)
    run(["udevadm", "settle", "--timeout=10"])
    for dm in glob.glob("/sys/block/dm-*"):
        try:
            uuid = open(f"{dm}/dm/uuid").read()
        except OSError:
            continue
        if uuid.startswith("LVM-"):
            run(["blockdev", "--setro", f"/dev/{os.path.basename(dm)}"])
    return vgs


def assemble():
    """Start every RAID array read-only (degraded ones too), then LVM on top. Returns a result dict."""
    res = {"started": [], "readonly_forced": [], "vgs": [], "messages": []}
    before = {a["md"] for a in running()}
    if members():
        os.makedirs(RUN, mode=0o700, exist_ok=True)
        rc, scan, _ = run(["mdadm", "--examine", "--scan"], timeout=60)
        conf = os.path.join(RUN, "mdadm.conf")
        with open(conf, "w") as f:
            f.write("MAILADDR root\n" + _devnames(scan))
        rc, out, err = run(["mdadm", "--assemble", "--scan", "--readonly", "--run", f"--config={conf}"], timeout=180)
        res["messages"] = [l.strip() for l in (out + err).splitlines() if l.strip()][-8:]
    # udev may have started an array on its own the moment its disks appeared: make sure none can write
    for a in running():
        if a["md"] not in before:
            res["started"].append(a["md"])
        if a["container"]:
            continue
        if a["state"] not in ("readonly", "inactive"):
            run(["mdadm", "--readonly", a["md"]])
            res["readonly_forced"].append(a["md"])
        run(["blockdev", "--setro", a["md"]])
    res["vgs"] = activate_lvm()
    audit(f"RAID: {len(res['started'])} array(s) started read-only, {len(res['readonly_forced'])} already running set read-only, "
          f"{len(res['vgs'])} LVM group(s) activated read-only")
    return res


def mounted_from(devs):
    out = run(["findmnt", "-rno", "SOURCE,TARGET"])[1]
    return [l.split(None, 1) for l in out.splitlines() if l.split(None, 1)[0] in devs]


def _is_lvm(dm_path):
    try:
        return open(dm_path + "/dm/uuid").read().startswith("LVM-")
    except OSError:
        return False


def stop():
    """Deactivate LVM and stop the arrays on the machine's disks. Refuses while any of them is mounted."""
    arrays = sorted(running(), key=lambda a: a["container"])      # volumes first, then their containers
    devs = {a["md"] for a in arrays}
    lvm_dm = [p for p in glob.glob("/sys/block/dm-*") if _is_lvm(p)]       # not SysMedic's own vault or a customer's LUKS
    dm = {f"/dev/{os.path.basename(p)}" for p in lvm_dm}
    names = {f"/dev/mapper/{open(p + '/dm/name').read().strip()}" for p in lvm_dm if os.path.exists(p + "/dm/name")}
    busy = mounted_from(devs | dm | names)
    if busy:
        return False, [f"{s} is mounted at {t.strip()}: unmount it first" for s, t in busy]
    msgs = []
    rc, out, _ = lvm("vgs", "--noheadings", "-o", "vg_name")
    for vg in out.split() if rc == 0 else []:
        if lvm("vgchange", "-an", "--noudevsync", vg)[0] != 0:
            msgs.append(f"volume group {vg} is still in use")
    for a in arrays:
        rc, out, err = run(["mdadm", "--stop", a["md"]])
        if rc != 0:
            msgs.append((err or out).strip())
    audit("RAID: arrays and LVM groups stopped")
    return not msgs, msgs
