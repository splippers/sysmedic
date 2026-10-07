"""winlib — read-only analysis of an offline Windows installation.

Used by sysmedic-win and sysmedic-scan. Every function takes the mount point
of a Windows system volume (mounted read-only) and only reads from it.
"""
import datetime
import re
import struct
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

try:
    import hivex
except ImportError:          # scan still works without it, with less detail
    hivex = None

# ── Paths ──────────────────────────────────────────────────────────────────

def ci_path(root, rel):
    """Resolve a relative path case-insensitively (NTFS paths vary in case)."""
    cur = Path(root)
    for part in Path(rel.replace("\\", "/")).parts:
        try:
            match = next((c for c in cur.iterdir() if c.name.lower() == part.lower()), None)
        except OSError:
            return None
        if match is None:
            return None
        cur = match
    return cur


def win_to_local(root, winpath, users=()):
    """Map a Windows path (C:\\..., %SystemRoot%\\..., \\??\\C:\\...) onto the mounted volume."""
    p = winpath.strip().strip('"')
    p = re.split(r'\.exe\b', p, maxsplit=1, flags=re.I)[0] + (".exe" if re.search(r'\.exe\b', p, re.I) else "")
    p = re.sub(r'^\\\?\?\\', '', p)
    p = re.sub(r'(?i)^%(systemroot|windir)%', r'C:\\Windows', p)
    p = re.sub(r'(?i)^\\systemroot', r'C:\\Windows', p)
    p = re.sub(r'(?i)^system32\\', r'C:\\Windows\\System32\\', p)
    p = re.sub(r'(?i)^%programfiles%', r'C:\\Program Files', p)
    p = re.sub(r'(?i)^%programdata%', r'C:\\ProgramData', p)
    p = re.sub(r'^[A-Za-z]:', '', p)
    return ci_path(root, p.lstrip("\\")) if p else None


# ── Registry ───────────────────────────────────────────────────────────────

class Hive:
    def __init__(self, path):
        with open(path, "rb") as f:
            if f.read(4) != b"regf":
                raise OSError(f"{path}: not a registry hive")
        self.h = hivex.Hivex(str(path))

    def node(self, keypath):
        n = self.h.root()
        for part in [p for p in keypath.split("\\") if p]:
            n = self.h.node_get_child(n, part)
            if not n:
                return None
        return n

    def _decode(self, v):
        t, data = self.h.value_value(v)
        if t in (1, 2):
            return data.decode("utf-16-le", "replace").rstrip("\0")
        if t == 4 and len(data) >= 4:
            return struct.unpack("<I", data[:4])[0]
        if t == 11 and len(data) >= 8:
            return struct.unpack("<Q", data[:8])[0]
        if t == 7:
            return [s for s in data.decode("utf-16-le", "replace").split("\0") if s]
        return data

    def get(self, keypath, name, default=None):
        n = self.node(keypath)
        if not n:
            return default
        for v in self.h.node_values(n):
            if self.h.value_key(v).lower() == name.lower():
                return self._decode(v)
        return default

    def values(self, keypath):
        n = self.node(keypath)
        return {self.h.value_key(v): self._decode(v) for v in self.h.node_values(n)} if n else {}

    def subkeys(self, keypath):
        n = self.node(keypath)
        return [self.h.node_name(c) for c in self.h.node_children(n)] if n else []


def open_hive(root, rel):
    if hivex is None:
        return None
    f = ci_path(root, rel)
    if not f:
        return None
    try:
        return Hive(f)
    except (RuntimeError, OSError):
        return None


def control_set(system):
    cur = system.get("Select", "Current", 1) if system else 1
    return f"ControlSet{int(cur):03d}"


def filetime(ft):
    if not ft:
        return None
    if isinstance(ft, bytes):
        if len(ft) < 8:
            return None
        ft = struct.unpack("<Q", ft[:8])[0]
    try:
        return datetime.datetime(1601, 1, 1) + datetime.timedelta(microseconds=ft // 10)
    except OverflowError:
        return None


# ── Facts about the installation ────────────────────────────────────────────

def info(root):
    sw, sysh = open_hive(root, "Windows/System32/config/SOFTWARE"), open_hive(root, "Windows/System32/config/SYSTEM")
    cv = r"Microsoft\Windows NT\CurrentVersion"
    r = {"product": "Windows", "build": "", "display_version": "", "edition": ""}
    if sw:
        r["product"] = sw.get(cv, "ProductName", "Windows")
        r["build"] = str(sw.get(cv, "CurrentBuild", "") or "")
        r["display_version"] = sw.get(cv, "DisplayVersion", "") or sw.get(cv, "ReleaseId", "") or ""
        r["edition"] = sw.get(cv, "EditionID", "") or ""
        if r["build"].isdigit() and int(r["build"]) >= 22000:
            r["product"] = r["product"].replace("Windows 10", "Windows 11")
        r["profiles"] = []
        for sid in sw.subkeys(cv + r"\ProfileList"):
            if re.match(r"S-1-5-21-.*-\d{4,}$", sid):
                path = sw.get(cv + r"\ProfileList\\" + sid, "ProfileImagePath", "")
                name = path.split("\\")[-1] if path else sid
                ntuser = ci_path(root, f"Users/{name}/NTUSER.DAT")
                last = datetime.datetime.fromtimestamp(ntuser.stat().st_mtime) if ntuser else None
                r["profiles"].append({"name": name, "sid": sid, "last_used": last.isoformat(" ", "minutes") if last else None})
        r["reboot_pending_cbs"] = sw.node(r"Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") is not None
    r["name"] = " ".join(x for x in [r["product"], r["display_version"], f"(build {r['build']})" if r["build"] else ""] if x)
    if sysh:
        cs = control_set(sysh)
        r["computer_name"] = sysh.get(cs + r"\Control\ComputerName\ComputerName", "ComputerName", "")
        st = filetime(sysh.get(cs + r"\Control\Windows", "ShutdownTime"))
        r["last_shutdown"] = st.isoformat(" ", "minutes") + " UTC" if st else None
        r["fast_startup"] = sysh.get(cs + r"\Control\Session Manager\Power", "HiberbootEnabled", 1) == 1
        pfro = sysh.get(cs + r"\Control\Session Manager", "PendingFileRenameOperations", []) or []
        r["pending_renames"] = len([x for x in pfro if x and not x.startswith("!")]) if isinstance(pfro, list) else 0
    hib = ci_path(root, "hiberfil.sys")
    try:
        r["hibernated"] = bool(hib) and hib.open("rb").read(4).lower() == b"hibr"
    except OSError:
        r["hibernated"] = False
    r["pending_xml"] = bool(ci_path(root, "Windows/WinSxS/pending.xml"))
    reagent = ci_path(root, "Windows/System32/Recovery/ReAgent.xml")
    if reagent:
        txt = reagent.read_text(errors="replace")
        loc = re.search(r'<WinreLocation[^>]*path="([^"]*)"', txt)
        r["winre"] = "configured" if loc and loc.group(1) else "disabled"
    else:
        r["winre"] = "unknown"
    return r


# ── Crashes ────────────────────────────────────────────────────────────────

BUGCHECKS = {
    0x00020001: ("HYPERVISOR_ERROR", "the Hyper-V hypervisor failed: check BIOS virtualisation settings (VT-x/VT-d), firmware and chipset drivers, and VBS/Credential Guard (sysmedic-win bcd shows hypervisorlaunchtype)"),
    0x00000141: ("VIDEO_ENGINE_TIMEOUT_DETECTED", "the graphics engine hung and was reset (no blue screen): graphics driver or GPU"),
    0x00000117: ("VIDEO_TDR_TIMEOUT_DETECTED", "the graphics driver stopped responding and was reset: update or roll back the graphics driver"),
    0x00000144: ("BUGCODE_USB3_DRIVER", "a USB 3 controller or device misbehaved: chipset/USB drivers, a faulty dock or device"),
    0x00000193: ("VIDEO_DXGKRNL_LIVEDUMP", "Windows captured a graphics diagnostic dump: graphics driver"),
    0x0A: ("IRQL_NOT_LESS_OR_EQUAL", "usually a faulty driver"),
    0x19: ("BAD_POOL_HEADER", "driver memory corruption"),
    0x1A: ("MEMORY_MANAGEMENT", "often faulty RAM: run the memory test"),
    0x1E: ("KMODE_EXCEPTION_NOT_HANDLED", "a driver crashed"),
    0x24: ("NTFS_FILE_SYSTEM", "disk or filesystem damage"),
    0x3B: ("SYSTEM_SERVICE_EXCEPTION", "driver or system file fault"),
    0x50: ("PAGE_FAULT_IN_NONPAGED_AREA", "driver, RAM, or antivirus"),
    0x77: ("KERNEL_STACK_INPAGE_ERROR", "couldn't read from disk: check disk health"),
    0x7A: ("KERNEL_DATA_INPAGE_ERROR", "couldn't read from disk: check disk health"),
    0x7B: ("INACCESSIBLE_BOOT_DEVICE", "storage driver/controller mode (AHCI/RAID/VMD) or a dying disk"),
    0x7E: ("SYSTEM_THREAD_EXCEPTION_NOT_HANDLED", "a driver crashed"),
    0x9F: ("DRIVER_POWER_STATE_FAILURE", "a driver failed during sleep/wake"),
    0xA0: ("INTERNAL_POWER_ERROR", "power management / hibernation file problem"),
    0xC2: ("BAD_POOL_CALLER", "driver memory misuse"),
    0xD1: ("DRIVER_IRQL_NOT_LESS_OR_EQUAL", "faulty driver (often network or storage)"),
    0xEF: ("CRITICAL_PROCESS_DIED", "system files damaged: sfc/DISM from WinRE"),
    0xF4: ("CRITICAL_OBJECT_TERMINATION", "often disk or storage-driver failure"),
    0x101: ("CLOCK_WATCHDOG_TIMEOUT", "CPU hang: overheating, BIOS, or CPU fault"),
    0x116: ("VIDEO_TDR_FAILURE", "graphics driver or GPU"),
    0x119: ("VIDEO_SCHEDULER_INTERNAL_ERROR", "graphics driver"),
    0x124: ("WHEA_UNCORRECTABLE_ERROR", "hardware: CPU, RAM, overheating or overclock"),
    0x133: ("DPC_WATCHDOG_VIOLATION", "storage driver or SSD firmware"),
    0x139: ("KERNEL_SECURITY_CHECK_FAILURE", "driver corruption or incompatible software"),
    0x154: ("UNEXPECTED_STORE_EXCEPTION", "disk/SSD problem"),
    0x1D8: ("ATTEMPTED_SWITCH_FROM_DPC", "driver bug"),
    0xC000021A: ("STATUS_SYSTEM_PROCESS_TERMINATED", "system files or a bad update"),
}


def read_dump_header(path):
    """Return (bugcheck_code, params) from a Windows crash dump header, or None."""
    try:
        with open(path, "rb") as f:
            head = f.read(0x60)
    except OSError:
        return None
    if head[:8] == b"PAGEDU64":
        code = struct.unpack_from("<I", head, 0x38)[0]
        params = struct.unpack_from("<4Q", head, 0x40)
    elif head[:8] == b"PAGEDUMP":
        code = struct.unpack_from("<I", head, 0x20)[0]
        params = struct.unpack_from("<4I", head, 0x24)
    else:
        return None
    return code, params


def crashes(root):
    out = []
    files = []
    md = ci_path(root, "Windows/Minidump")
    if md and md.is_dir():
        files += sorted(md.glob("*.dmp"))
    full = ci_path(root, "Windows/MEMORY.DMP")
    if full:
        files.append(full)
    for f in files:
        hdr = read_dump_header(f)
        when = datetime.datetime.fromtimestamp(f.stat().st_mtime)
        if hdr:
            code, params = hdr
            name, hint = BUGCHECKS.get(code, ("unknown stop code", "look the code up, or analyse the dump in WinDbg"))
            out.append({"file": f.name, "time": when.isoformat(" ", "minutes"), "code": f"0x{code:08X}",
                        "name": name, "hint": hint, "params": [f"0x{p:X}" for p in params]})
        else:
            out.append({"file": f.name, "time": when.isoformat(" ", "minutes"), "code": None,
                        "name": "unreadable dump", "hint": "file is truncated or not a crash dump"})
    return out


WER_KINDS = ("BlueScreen", "LiveKernelEvent", "Kernel", "WHEA", "Critical")


def wer_reports(root, limit=60):
    """Kernel-level crash reports Windows Error Reporting kept (they often survive when dumps don't)."""
    out = []
    for sub in ("ProgramData/Microsoft/Windows/WER/ReportArchive", "ProgramData/Microsoft/Windows/WER/ReportQueue"):
        base = ci_path(root, sub)
        if not base or not base.is_dir():
            continue
        for d in base.iterdir():
            f = ci_path(d, "Report.wer")
            if not f:
                continue
            try:
                raw = f.read_bytes()
                txt = raw.decode("utf-16-le" if raw[:2] == b"\xff\xfe" or raw[1:2] == b"\0" else "utf-8", "replace")
            except OSError:
                continue
            kv = dict(l.split("=", 1) for l in txt.splitlines() if "=" in l)
            etype = kv.get("EventType", "")
            if not any(k.lower() in etype.lower() for k in WER_KINDS):
                continue
            sig = {kv.get(f"Sig[{i}].Name", ""): kv.get(f"Sig[{i}].Value", "") for i in range(10) if f"Sig[{i}].Name" in kv}
            code = next((v for k, v in sig.items() if k.lower() in ("bccode", "code", "bugcheck code", "bug check code")), "")
            try:
                code = f"0x{int(code, 16):08X}" if code else ""
            except ValueError:
                pass
            t = filetime(int(kv["EventTime"])) if kv.get("EventTime", "").isdigit() else None
            name = BUGCHECKS.get(int(code, 16), ("", ""))[0] if code.startswith("0x") else ""
            out.append({"time": t.isoformat(" ", "minutes") if hasattr(t, "isoformat") else str(t or "?"), "type": etype,
                        "code": code, "name": name, "folder": d.name[:60],
                        "detail": ", ".join(f"{k}={v}" for k, v in sig.items() if v and k.lower() not in ("bccode", "code"))[:140]})
    lkr = ci_path(root, "Windows/LiveKernelReports")
    if lkr and lkr.is_dir():
        for f in lkr.rglob("*.dmp"):
            out.append({"time": datetime.datetime.fromtimestamp(f.stat().st_mtime).isoformat(" ", "minutes"), "type": "LiveKernelReport dump",
                        "code": "", "name": "", "folder": str(f.relative_to(lkr)), "detail": f"{f.stat().st_size // 1024} KB"})
    return sorted(out, key=lambda r: r["time"], reverse=True)[:limit]


# ── Event logs ─────────────────────────────────────────────────────────────

# (provider substring, event id) → (category, plain-English meaning)
NOTABLE = {
    ("kernel-power", 41): ("power", "Unexpected restart: power loss, hard reset, or a crash"),
    ("eventlog", 6008): ("power", "The previous shutdown was unexpected"),
    ("bugcheck", 1001): ("crash", "Blue-screen crash (BugCheck)"),
    ("wer-systemerrorreporting", 1001): ("crash", "Blue-screen crash (BugCheck)"),
    ("disk", 7): ("disk", "Disk has bad blocks"),
    ("disk", 51): ("disk", "Error during a disk paging operation"),
    ("disk", 153): ("disk", "Disk I/O retried"),
    ("stornvme", 11): ("disk", "NVMe controller error"),
    ("storahci", 129): ("disk", "Storage controller reset"),
    ("ntfs", 55): ("disk", "NTFS corruption detected"),
    ("ntfs", 98): ("disk", "Volume needs chkdsk"),
    ("ntfs", 137): ("disk", "NTFS transaction log error"),
    ("whea-logger", 17): ("hardware", "Corrected hardware error (PCIe/CPU)"),
    ("whea-logger", 18): ("hardware", "Fatal hardware error"),
    ("whea-logger", 19): ("hardware", "Corrected machine-check error"),
    ("whea-logger", 47): ("hardware", "Corrected memory error"),
    ("volmgr", 161): ("crash", "Crash dump could not be written"),
    ("windowsupdateclient", 20): ("update", "A Windows update failed to install"),
    ("service control manager", 7000): ("service", "A service failed to start"),
    ("service control manager", 7001): ("service", "A service didn't start because a dependency failed"),
    ("service control manager", 7009): ("service", "A service timed out starting"),
    ("service control manager", 7023): ("service", "A service stopped with an error"),
    ("service control manager", 7031): ("service", "A service crashed"),
    ("service control manager", 7034): ("service", "A service terminated unexpectedly"),
    ("service control manager", 7045): ("persistence", "A new service was installed"),
}


def _event_fields(ev):
    ns = {"e": "http://schemas.microsoft.com/win/2004/08/events/event"}
    sysel = ev.find("e:System", ns)
    prov = sysel.find("e:Provider", ns)
    eid = sysel.find("e:EventID", ns)
    tc = sysel.find("e:TimeCreated", ns)
    data = {}
    for d in ev.iter():
        if d.tag.endswith("}Data") and d.text:
            data[d.get("Name") or f"d{len(data)}"] = d.text.strip()
    return {"provider": prov.get("Name", "") if prov is not None else "",
            "id": int((eid.text or "0").strip()) if eid is not None else 0,
            "level": int((sysel.findtext("e:Level", "4", ns) or "4").strip() or 4),
            "time": (tc.get("SystemTime", "")[:16].replace("T", " ") if tc is not None else ""),
            "data": data}


def events(root, logname="System", since_days=None, timeout=120):
    log = ci_path(root, f"Windows/System32/winevt/Logs/{logname}.evtx")
    if not log:
        return None
    try:
        p = subprocess.run(["evtxexport", "-f", "xml", str(log)], capture_output=True, text=True,
                           errors="replace", timeout=timeout)
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None
    cutoff = None
    if since_days:
        cutoff = (datetime.datetime.utcnow() - datetime.timedelta(days=since_days)).strftime("%Y-%m-%d %H:%M")
    found = {}
    for block in re.findall(r"<Event [^>]*>.*?</Event>", p.stdout, re.S):
        try:
            ev = _event_fields(ET.fromstring(block))
        except ET.ParseError:
            continue
        if cutoff and ev["time"] < cutoff:
            continue
        key = next(((cat, meaning) for (prov, eid), (cat, meaning) in NOTABLE.items()
                    if eid == ev["id"] and prov in ev["provider"].lower()), None)
        if not key and ev["level"] in (1, 2) and ev["provider"] != "Service Control Manager":
            key = ("error", f"{ev['provider']} event {ev['id']}")
        if not key:
            continue
        g = found.setdefault((ev["provider"], ev["id"]), {"provider": ev["provider"], "id": ev["id"], "category": key[0],
                                                          "meaning": key[1], "count": 0, "first": ev["time"], "last": ev["time"],
                                                          "examples": []})
        g["count"] += 1
        g["first"], g["last"] = min(g["first"], ev["time"]), max(g["last"], ev["time"])
        if len(g["examples"]) < 3 and ev["data"]:
            g["examples"].append({"time": ev["time"], **{k: v for k, v in list(ev["data"].items())[:4]}})
    return sorted(found.values(), key=lambda g: g["last"], reverse=True)


# ── Autostart / persistence ─────────────────────────────────────────────────

SYSTEM_NAMES = {"svchost.exe", "csrss.exe", "lsass.exe", "services.exe", "winlogon.exe", "explorer.exe",
                "smss.exe", "wininit.exe", "spoolsv.exe", "taskhostw.exe", "dllhost.exe", "conhost.exe"}
USER_WRITABLE = re.compile(r"\\(users\\[^\\]+\\appdata|appdata|temp|programdata|users\\public|\$recycle\.bin)\\", re.I)
# Inside ProgramData but admin-only by default (Defender and Defender for Endpoint): not user-writable
PROTECTED_PROGRAMDATA = re.compile(r"\\programdata\\microsoft\\(windows defender|windows defender advanced threat protection)\\", re.I)
SHADY_ARGS = re.compile(r"(-enc(odedcommand)?\s|frombase64string|downloadstring|iex\s*\(|mshta\s+https?:|regsvr32\s.*\/i:https?:|bitsadmin\s.*\/transfer)", re.I)


def judge(command):
    """Return a reason string if an autostart command looks suspicious, else ''."""
    c = command or ""
    exe = re.split(r'\.exe\b', c.strip('"'), maxsplit=1, flags=re.I)[0].split("\\")[-1].lower() + ".exe" if ".exe" in c.lower() else ""
    reasons = []
    if exe in SYSTEM_NAMES and "\\windows\\system32\\" not in c.lower() and "%windir%\\system32" not in c.lower() \
            and "%systemroot%\\system32" not in c.lower():
        reasons.append(f"'{exe}' is a Windows system name, but this copy is not in System32")
    if USER_WRITABLE.search(c.replace("/", "\\") + "\\") and not PROTECTED_PROGRAMDATA.search(c.replace("/", "\\")):
        reasons.append("runs from a user-writable folder")
    if SHADY_ARGS.search(c):
        reasons.append("downloads or runs encoded/remote code")
    return "; ".join(reasons)


def autoruns(root):
    items = []

    def add(where, name, command):
        items.append({"where": where, "name": name, "command": command, "suspicious": judge(command),
                      "exists": bool(win_to_local(root, command)) if command else None})

    sw = open_hive(root, "Windows/System32/config/SOFTWARE")
    if sw:
        for key in [r"Microsoft\Windows\CurrentVersion\Run", r"Microsoft\Windows\CurrentVersion\RunOnce",
                    r"WOW6432Node\Microsoft\Windows\CurrentVersion\Run"]:
            for n, v in sw.values(key).items():
                add("HKLM\\" + key.split("\\")[-1], n, str(v))
    users = ci_path(root, "Users")
    for u in (sorted(users.iterdir()) if users and users.is_dir() else []):
        nt = ci_path(u, "NTUSER.DAT")
        if nt and hivex:
            try:
                h = Hive(nt)
            except (RuntimeError, OSError):
                continue
            for key in [r"Software\Microsoft\Windows\CurrentVersion\Run", r"Software\Microsoft\Windows\CurrentVersion\RunOnce"]:
                for n, v in h.values(key).items():
                    add(f"HKCU({u.name})\\" + key.split("\\")[-1], n, str(v))
        st = ci_path(u, "AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Startup")
        for f in (st.iterdir() if st and st.is_dir() else []):
            if f.name.lower() != "desktop.ini":
                add(f"Startup folder ({u.name})", f.name, f"C:\\Users\\{u.name}\\AppData\\Roaming\\Microsoft\\Windows\\Start Menu\\Programs\\Startup\\{f.name}")
    sysh = open_hive(root, "Windows/System32/config/SYSTEM")
    if sysh:
        base = control_set(sysh) + r"\Services"
        for svc in sysh.subkeys(base):
            vals = sysh.values(base + "\\" + svc)
            img, start = vals.get("ImagePath"), vals.get("Start")
            if not img or start not in (0, 1, 2):
                continue
            low = str(img).lower()
            if any(s in low for s in ("\\windows\\", "%systemroot%", "%windir%", "system32\\")) and not judge(str(img)):
                continue                       # stock Windows services
            dn = str(vals.get("DisplayName") or "")
            dn = "" if dn.startswith("@") else dn          # "@C:\\…\\x.dll,-245" is a resource reference, not a name
            add("Service (auto-start)", f"{svc} ({dn})".replace(" ()", ""), str(img))
    tasks = ci_path(root, "Windows/System32/Tasks")
    if tasks and tasks.is_dir():
        for t in tasks.rglob("*"):
            if t.is_file() and not str(t.relative_to(tasks)).lower().startswith("microsoft"):
                try:
                    txt = t.read_bytes().decode("utf-16", "replace") if t.read_bytes()[:2] in (b"\xff\xfe", b"\xfe\xff") else t.read_text(errors="replace")
                except OSError:
                    continue
                cmd = re.search(r"<Command>([^<]+)</Command>", txt)
                args = re.search(r"<Arguments>([^<]+)</Arguments>", txt)
                if cmd:
                    add("Scheduled task", str(t.relative_to(tasks)), cmd.group(1) + (" " + args.group(1) if args else ""))
    return items
