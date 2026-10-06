"""winevidence — deep, read-only Windows troubleshooting evidence.

Three sources, each usable on a mounted Windows volume or on files handed over by the engineer:
  evtx      every event log (.evtx): curated rules for the logs that explain problems, plus an
            error sweep of all the others
  registry  problems the registry proves: services/drivers whose files are missing, broken
            device filter drivers, hijacks, policies that switch protection or updates off,
            crash-dump settings, recent installs
  cbs       Windows servicing: CBS.log (+ archived CbsPersist logs), dism.log, Windows Update's
            ReportingEvents.log and the Panther upgrade logs: failing updates, error meanings,
            component-store corruption and SFC results

Nothing here writes to the Windows volume. Credentials are never extracted: event fields and
registry values whose names suggest secrets are dropped, and SAM/SECURITY are not read.
"""
import datetime
import time
import sys
import json
import os
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

import winlib
from winlib import ci_path, control_set, open_hive, Hive, hivex

SECRETISH = re.compile(r"pass|pwd|token|secret|credential|hash|key$|apikey|cookie", re.I)
NS = {"e": "http://schemas.microsoft.com/win/2004/08/events/event"}


def _when(s):
    return s[:16].replace("T", " ") if s else ""


def _cutoff(days):
    return (datetime.datetime.utcnow() - datetime.timedelta(days=days)).strftime("%Y-%m-%d %H:%M") if days else ""


# ═══ Event logs ════════════════════════════════════════════════════════════════
#
# (log file stem, provider substring or "", event id) → (category, severity, meaning)
# Log stems are the .evtx names with "%4" for "/" (as Windows stores them), lower-cased.

R = {}


def rule(log, provider, ids, category, severity, meaning):
    for i in (ids if isinstance(ids, (list, tuple)) else [ids]):
        R[(log, provider, i)] = (category, severity, meaning)


S, A, SEC, SETUP = "system", "application", "security", "setup"
# System
rule(S, "kernel-power", 41, "power", "critical", "Unexpected shutdown or power loss (Kernel-Power 41)")
rule(S, "eventlog", 6008, "power", "warning", "The previous shutdown was unexpected")
rule(S, "user32", 1074, "power", "info", "Restart/shutdown requested (who and why)")
rule(S, "bugcheck", 1001, "crash", "critical", "Blue screen (bugcheck) recorded")
rule(S, "wer-systemerrorreporting", 1001, "crash", "critical", "Blue screen (bugcheck) recorded")
rule(S, "whea-logger", [17, 19, 47], "hardware", "warning", "Corrected hardware error (CPU, memory or PCIe)")
rule(S, "whea-logger", [18, 20, 46], "hardware", "critical", "Fatal hardware error (CPU, memory or PCIe)")
rule(S, "disk", [7, 11, 52, 153, 154], "disk", "critical", "Disk error: bad block, controller error or retried I/O")
rule(S, "disk", 51, "disk", "warning", "Disk paging error (I/O failed during paging)")
rule(S, "ntfs", [55, 98, 130, 137, 140], "disk", "critical", "NTFS file system corruption or repair")
rule(S, "stornvme", [11, 129], "disk", "critical", "NVMe controller error or reset")
rule(S, "storahci", [11, 129], "disk", "critical", "SATA controller error or reset")
rule(S, "volmgr", [46, 49, 161], "disk", "warning", "Volume manager: crash dump/paging file problem")
rule(S, "volsnap", [25, 33, 36], "disk", "warning", "Shadow copies (restore points) deleted or failed")
rule(S, "hal", 15, "hardware", "warning", "HAL/firmware fault")
rule(S, "kernel-processor-power", 37, "power", "warning", "CPU speed limited by firmware (heat or power supply)")
rule(S, "kernel-pnp", [219], "driver", "warning", "A driver failed to load for a device")
rule(S, "service control manager", 7000, "service", "warning", "A service failed to start")
rule(S, "service control manager", 7001, "service", "warning", "A service didn't start because one it depends on failed")
rule(S, "service control manager", 7009, "service", "warning", "A service timed out starting")
rule(S, "service control manager", 7011, "service", "warning", "A service didn't respond in time")
rule(S, "service control manager", [7023, 7024], "service", "warning", "A service stopped with an error")
rule(S, "service control manager", 7026, "driver", "critical", "A boot or system driver failed to load")
rule(S, "service control manager", [7031, 7034], "service", "warning", "A service crashed (terminated unexpectedly)")
rule(S, "service control manager", 7043, "service", "warning", "A service didn't shut down properly")
rule(S, "service control manager", 7045, "persistence", "warning", "A new service was installed")
rule(S, "eventlog", 104, "security", "warning", "An event log was cleared")
rule(S, "display", 4101, "driver", "warning", "Graphics driver stopped responding and recovered")
rule(S, "nvlddmkm", [13, 14, 153], "driver", "warning", "NVIDIA graphics driver error")
rule(S, "resource-exhaustion-detector", 2004, "performance", "warning", "Windows ran low on memory")
rule(S, "tpm-wmi", [1796, 1801, 1808], "security", "warning", "Secure Boot certificate/update problem (TPM-WMI)")
rule(S, "time-service", [36, 129, 134], "network", "warning", "Clock couldn't synchronise (time service)")
rule(S, "netlogon", [5719, 3210], "network", "warning", "Couldn't reach the domain controller")
rule(S, "grouppolicy", [1129, 1053, 1055, 1058, 1096], "policy", "warning", "Group Policy failed to apply")
rule(S, "tcpip", 4199, "network", "warning", "IP address conflict on the network")
rule(S, "dhcp-client", [1001, 1002], "network", "warning", "Couldn't get an IP address (DHCP)")
rule(S, "windowsupdateclient", [20, 25, 31], "update", "warning", "A Windows update failed")
rule(S, "bitlocker-driver", [24620, 24635], "bitlocker", "warning", "BitLocker driver problem")
# Application
rule(A, "application error", 1000, "app", "warning", "Application crash")
rule(A, "application hang", 1002, "app", "warning", "Application stopped responding")
rule(A, ".net runtime", 1026, "app", "warning", ".NET application crash")
rule(A, "sidebyside", [33, 35, 59, 80], "app", "warning", "A program couldn't start: missing or broken runtime (Visual C++)")
rule(A, "msiinstaller", [11708, 1023], "update", "warning", "An installation failed (Windows Installer)")
rule(A, "msiinstaller", 1033, "change", "info", "Software installed (Windows Installer)")
rule(A, "msiinstaller", 1034, "change", "info", "Software removed (Windows Installer)")
rule(A, "esent", [454, 455, 465, 467, 490, 507, 508], "app", "warning", "Database error or corruption (ESENT: Search, Update or Store database)")
rule(A, "security-spp", [8198, 8200, 1058], "activation", "warning", "Windows activation (licensing) failed")
rule(A, "vss", [8193, 12289, 13, 8194], "disk", "warning", "Volume Shadow Copy error (backups/restore points)")
rule(A, "wininit", 1015, "crash", "critical", "A critical system process died")
rule(A, "winlogon", [4005, 6004], "crash", "warning", "Windows logon process problem")
# Security (summary only; nothing credential-bearing is printed)
rule(SEC, "security-auditing", 4625, "security", "warning", "Failed logon attempts")
rule(SEC, "security-auditing", 4740, "security", "warning", "Account locked out")
rule(SEC, "eventlog", 1102, "security", "critical", "The Security log was cleared")
rule(SEC, "eventlog", 1104, "security", "warning", "The Security log is full: events are being lost")
rule(SEC, "security-auditing", 4720, "security", "warning", "A user account was created")
rule(SEC, "security-auditing", [4728, 4732, 4756], "security", "warning", "An account was added to a security group (e.g. Administrators)")
rule(SEC, "security-auditing", 4697, "persistence", "warning", "A service was installed")
rule(SEC, "security-auditing", 4698, "persistence", "warning", "A scheduled task was created")
rule(SEC, "security-auditing", 4719, "policy", "info", "Audit policy changed")
rule(SEC, "security-auditing", 5038, "security", "warning", "Code integrity: a file's signature/hash is invalid")
rule(SEC, "eventlog", 1100, "power", "info", "Event logging service shut down")
# Setup (servicing results)
rule(SETUP, "servicing", 4, "update", "info", "A Windows package needs a restart to finish")
# Operational logs
WU = "microsoft-windows-windowsupdateclient%4operational"
rule(WU, "windowsupdateclient", [20, 25, 31], "update", "warning", "A Windows update failed")
rule(WU, "windowsupdateclient", 19, "update", "info", "A Windows update installed successfully")
PNP = "microsoft-windows-kernel-pnp%4configuration"
rule(PNP, "kernel-pnp", 411, "driver", "warning", "A device had a problem starting (driver)")
rule(PNP, "kernel-pnp", 441, "driver", "warning", "A device's driver wasn't migrated in an upgrade")
DP = "microsoft-windows-diagnostics-performance%4operational"
rule(DP, "diagnostics-performance", 100, "performance", "info", "Boot time measured")
rule(DP, "diagnostics-performance", list(range(101, 111)), "performance", "warning", "Slow boot: something delayed startup")
rule(DP, "diagnostics-performance", 200, "performance", "info", "Shutdown time measured")
rule(DP, "diagnostics-performance", list(range(201, 211)), "performance", "warning", "Slow shutdown: something delayed it")
DEF = "microsoft-windows-windows defender%4operational"
rule(DEF, "defender", [1116, 1117, 1006, 1007, 1015], "malware", "critical", "Defender detected malware")
rule(DEF, "defender", [1118, 1119], "malware", "critical", "Defender couldn't remove malware")
rule(DEF, "defender", [5001, 5010, 5012], "security", "critical", "Defender protection was turned off")
rule(DEF, "defender", 5007, "security", "info", "Defender settings changed")
rule(DEF, "defender", [2001, 2003, 2004], "security", "warning", "Defender couldn't update its definitions")
rule(DEF, "defender", 3002, "security", "warning", "Defender real-time protection failed")
SP = "microsoft-windows-storage-storport%4operational"
rule(SP, "storport", 524, "disk", "critical", "Storage command error or timeout (Storport)")
CP = "microsoft-windows-storage-classpnp%4operational"
rule(CP, "classpnp", 507, "disk", "warning", "Storage request failed (ClassPnP)")
rule(CP, "classpnp", 509, "disk", "info", "Storage device reset or surprise-removed (ClassPnP)")
CI = "microsoft-windows-codeintegrity%4operational"
rule(CI, "codeintegrity", [3033, 3063, 3077], "driver", "warning", "Windows blocked a driver or DLL that isn't properly signed")
TS = "microsoft-windows-taskscheduler%4operational"
rule(TS, "taskscheduler", 106, "persistence", "info", "A scheduled task was registered")
rule(TS, "taskscheduler", [101, 103, 203], "service", "warning", "A scheduled task failed to start")
WLAN = "microsoft-windows-wlan-autoconfig%4operational"
rule(WLAN, "wlan-autoconfig", 8002, "network", "warning", "Wi-Fi connection failed")
RDP = "microsoft-windows-terminalservices-remoteconnectionmanager%4operational"
rule(RDP, "remoteconnectionmanager", 1149, "security", "info", "Remote Desktop login accepted (network authentication)")
PS = "microsoft-windows-powershell%4operational"
rule(PS, "powershell", 4104, "persistence", "info", "PowerShell script block logged")

CURATED_LOGS = sorted({k[0] for k in R})
INDEX = {}
for (_log, _prov, _id), _v in R.items():
    INDEX.setdefault((_log, _id), []).append((_prov, _v))
NOISE = {("system", "distributedcom", 10016), ("system", "distributedcom", 10010),
         ("application", "perflib", 1008), ("application", "perflib", 1023)}
SHADY = re.compile(r"(-enc(odedcommand)?\s|frombase64string|downloadstring|invoke-expression|iex\s*\(|"
                   r"net\.webclient|mimikatz|invoke-shellcode|bypass\s+-|hidden\s+-)", re.I)


def evtx_files(target):
    """All .evtx files for a target: a Windows mount point, a folder of exported logs, or files."""
    paths = target if isinstance(target, (list, tuple)) else [target]
    out = []
    for p in map(Path, paths):
        if p.is_file() and p.suffix.lower() == ".evtx":
            out.append(p)
        elif p.is_dir():
            logs = ci_path(p, "Windows/System32/winevt/Logs")
            base = logs if logs and logs.is_dir() else p
            out += sorted(f for f in base.rglob("*") if f.suffix.lower() == ".evtx")
    return out


def _stem(path):
    return path.stem.lower().replace("/", "%4")


def _parse(block):
    try:
        ev = ET.fromstring(block)
    except ET.ParseError:
        return None
    sysel = ev.find("e:System", NS)
    if sysel is None:
        return None
    prov = sysel.find("e:Provider", NS)
    tc = sysel.find("e:TimeCreated", NS)
    data = {}
    for d in ev.iter():
        if d.tag.endswith("}Data") and d.text and d.text.strip():
            name = d.get("Name") or f"d{len(data)}"
            if not SECRETISH.search(name):
                data[name] = d.text.strip()[:300]
    try:
        eid = int((sysel.findtext("e:EventID", "0", NS) or "0").strip())
        level = int((sysel.findtext("e:Level", "4", NS) or "4").strip() or 4)
    except ValueError:
        return None
    return {"provider": prov.get("Name", "") if prov is not None else "", "id": eid, "level": level,
            "time": _when(tc.get("SystemTime", "") if tc is not None else ""), "data": data}


def read_evtx(path, timeout=300):
    """Parsed events from one .evtx file (evtxexport does the binary parsing). Returns (events, problem or "")."""
    try:
        p = subprocess.run(["evtxexport", "-f", "xml", str(path)], capture_output=True, text=True,
                           errors="replace", timeout=timeout)
    except FileNotFoundError:
        raise RuntimeError("evtxexport is not installed (package libevtx-utils)")
    except subprocess.TimeoutExpired:
        return [], f"timed out after {timeout} s"
    evs = [ev for ev in (_parse(b) for b in re.findall(r"<Event [^>]*>.*?</Event>", p.stdout, re.S)) if ev]
    if p.returncode != 0 and not evs:
        return [], (p.stderr.strip().splitlines() or ["unreadable"])[-1][:120]
    return evs, ""


STORAGE = re.compile(r"storport|classpnp|stordiag|stornvme|storahci|\bdisk\b|partmgr|volmgr", re.I)
SECURITY_PRODUCTS = re.compile(r"forti|amsi|crowdstrike|csagent|sentinel|sophos|eset|kaspersky|symantec|norton|mcafee|"
                               r"trend ?micro|tmamsi|carbon ?black|cylance|bitdefender|malwarebytes|webroot|cisco|cortex|"
                               r"windows defender|mpoav|mpclient", re.I)


def storage_device(data):
    """'Vendor Model (…1234)' from a storage event's fields, so the internal disk can be told from a USB stick."""
    pick = lambda *names: next((v.strip() for k, v in data.items() for n in names if k.lower() == n and v.strip()), "")
    vendor, model = pick("vendor", "vendorid"), pick("model", "productid", "product")
    serial = pick("serialnumber", "serial")
    name = " ".join(x for x in (vendor, model) if x and not x.startswith("0x0"))
    if not name:
        dev = pick("devicename", "device", "classdeviceguid", "diskid", "disknumber")
        name = dev and f"device {dev}"
    return (name + (f" (…{serial[-4:]})" if serial and name else "")).strip()


def ci_file(data):
    """(file name, full path) of the file a code-integrity event is about."""
    f = next((v for k, v in data.items() if k.lower() in ("filenamebuffer", "file name", "filename", "param1", "processnamebuffer")), "")
    return (f.split("\\")[-1][:80], f) if f else ("", "")


def _match(stem, ev):
    prov = ev["provider"].lower()
    return next((v for p, v in INDEX.get((stem, ev["id"]), []) if p in prov), None)


def _example(stem, ev):
    d = ev["data"]
    if stem == "security":                     # who/where only, never anything credential-like
        keep = ("TargetUserName", "TargetDomainName", "LogonType", "IpAddress", "WorkstationName",
                "ServiceName", "TaskName", "SubjectUserName", "MemberName", "Status", "SubStatus")
        d = {k: v for k, v in d.items() if k in keep}
    if stem == "microsoft-windows-powershell%4operational":
        txt = d.get("ScriptBlockText", "")
        d = {"suspicious": "yes" if SHADY.search(txt) else "no", "path": d.get("Path", "")}
    return {"time": ev["time"], **dict(list(d.items())[:5])}


def scan_evtx(target, days=30, sweep=True, progress=None):
    """Group notable events from every log. Returns {"findings": [...], "boot": [...], "logs": n, "errors": [...]}."""
    files, cutoff = evtx_files(target), _cutoff(days)
    groups, boots, problems, seen, empty, failed, skipped = {}, [], [], 0, 0, [], 0
    for f in files:
        stem = _stem(f)
        curated = stem in CURATED_LOGS
        if not curated and not sweep:
            skipped += 1
            continue
        if progress:
            progress(f.name)
        try:
            evs, problem = read_evtx(f)
            if problem:
                failed.append(f"{f.name}: {problem}")
                continue
            seen += 1
            if not evs:
                empty += 1
            for ev in evs:
                if cutoff and ev["time"] and ev["time"] < cutoff:
                    continue
                hit = _match(stem, ev) if curated else None
                if (stem, ev["provider"].lower(), ev["id"]) in NOISE:
                    continue
                if stem == SETUP and ev["id"] == 2 and ev["data"].get("ErrorCode", "0x0").lower() not in ("0x0", "0x00000000", "0"):
                    hit = ("update", "warning", "A Windows package failed to install")
                if not hit:
                    if ev["level"] not in (1, 2):
                        continue
                    hit = ("error", "critical" if ev["level"] == 1 else "warning",
                           f"{ev['provider'] or 'unknown'} error {ev['id']}")
                cat, sev, meaning = hit
                if stem == "microsoft-windows-powershell%4operational":
                    if not SHADY.search(ev["data"].get("ScriptBlockText", "")):
                        continue
                    cat, sev, meaning = "malware", "critical", "PowerShell ran obfuscated or download-and-run code"
                if stem == DP and ev["id"] == 100:
                    try:
                        boots.append((ev["time"], int(ev["data"].get("BootTime", "0")) / 1000))
                    except ValueError:
                        pass
                sub = ""
                if cat == "disk" or STORAGE.search(ev["provider"]) or "storage" in stem:
                    sub = storage_device(ev["data"])
                    if sub:
                        meaning = f"{meaning} — {sub}"
                if stem == CI or (stem == SEC and ev["id"] == 5038):
                    sub, full = ci_file(ev["data"])
                    if sub:
                        meaning = f"{meaning}: {sub}"
                        if SECURITY_PRODUCTS.search(full):
                            sev, meaning = "info", meaning + " (a security product's component: usually benign)"
                g = groups.setdefault((f.name, ev["provider"], ev["id"], sub), {
                    "log": f.name, "provider": ev["provider"], "id": ev["id"], "category": cat, "severity": sev,
                    "meaning": meaning, "count": 0, "first": ev["time"], "last": ev["time"], "examples": []})
                g["count"] += 1
                if ev["time"]:
                    g["first"] = min(g["first"] or ev["time"], ev["time"])
                    g["last"] = max(g["last"] or ev["time"], ev["time"])
                if len(g["examples"]) < 3 and (ev["data"] or cat != "error"):
                    g["examples"].append(_example(stem, ev))
        except RuntimeError as e:
            problems.append(str(e))
            break
    order = {"critical": 0, "warning": 1, "info": 2}
    found = sorted(groups.values(), key=lambda g: (order[g["severity"]], g["category"] == "error", -g["count"]))
    return {"findings": found, "boot": sorted(boots)[-10:], "logs": seen, "files": len(files), "errors": problems,
            "empty": empty, "failed": failed, "skipped": skipped}


# ═══ ETW traces (.etl) ═════════════════════════════════════════════════════════
#
# Windows Update, waasmedic, SIH, NetSetup and other components keep their detailed logs as ETW traces, not
# event logs. etl_dump.py decodes them with the vendored etl-parser; here failure codes are pulled out of the
# decoded text and grouped.

ETL_DIRS = ("Windows/Logs", "Windows/System32/LogFiles", "Windows/SoftwareDistribution", "Windows/Panther",
            "ProgramData/Microsoft/Windows/WER")
CODE = re.compile(r"(?<![0-9A-Fa-fx])(?:0x)?([89Cc][0-9A-Fa-f]{7})(?![0-9A-Fa-f])")
FAILWORD = re.compile(r"fail|error|unable|cannot|could not|denied|timeout|timed out", re.I)
CODEFIELD = re.compile(r"^(hr|hresult|error|errorcode|status|result|win32error|code)$", re.I)


def etl_files(target, days):
    paths = target if isinstance(target, (list, tuple)) else [target]
    out, cutoff = [], (time.time() - days * 86400) if days else 0
    for p in map(Path, paths):
        if p.is_file() and p.suffix.lower() == ".etl":
            out.append(p)
            continue
        bases = [b for b in (ci_path(p, d) for d in ETL_DIRS) if b and b.is_dir()] or ([p] if p.is_dir() else [])
        for b in bases:
            for f in b.rglob("*"):
                try:
                    if f.suffix.lower() == ".etl" and f.is_file() and f.stat().st_mtime >= cutoff:
                        out.append(f)
                except OSError:
                    continue
    return sorted(set(out))


def scan_etl(target, days=7, per_file_timeout=90, max_mb=64, progress=None):
    dump = Path(__file__).with_name("etl_dump.py")
    groups, coverage = {}, []
    for f in etl_files(target, days):
        rel = "/".join(f.parts[-3:])
        size = f.stat().st_size
        if size > max_mb * 2**20:
            coverage.append({"file": rel, "events": 0, "note": f"skipped: {size // 2**20} MB (over {max_mb} MB)"})
            continue
        if progress:
            progress(rel)
        try:
            p = subprocess.run([sys.executable, str(dump), str(f)], capture_output=True, text=True, errors="replace",
                               timeout=per_file_timeout)
            lines = p.stdout.splitlines()
        except subprocess.TimeoutExpired:
            coverage.append({"file": rel, "events": 0, "note": f"timed out after {per_file_timeout} s"})
            continue
        summary = {}
        for line in lines:
            try:
                ev = json.loads(line)
            except ValueError:
                continue
            if "summary" in ev:
                summary = ev["summary"]
                continue
            fields = ev.get("f", {})
            blob = " ".join(str(v) for v in fields.values())
            codes = {m.group(1).lower() for k, v in fields.items() if CODEFIELD.match(k) for m in CODE.finditer(str(v))}
            if FAILWORD.search(blob) or FAILWORD.search(ev.get("p", "")):
                codes |= {m.group(1).lower() for m in CODE.finditer(blob)}
            for c in codes:
                code = "0x" + c
                if code in ("0x80000000", "0xc0000000"):
                    continue
                src = f"{f.parent.name}/{ev.get('p', '')}"[:60]
                g = groups.setdefault((code, src), {"code": code, "source": src, "count": 0, "first": ev.get("t", ""),
                                                    "last": ev.get("t", ""), "example": blob[:180], "meaning": HRESULTS.get(code, "")})
                g["count"] += 1
                t = ev.get("t", "")
                if t:
                    g["first"] = min(g["first"] or t, t)
                    g["last"] = max(g["last"] or t, t)
        note = summary.get("error", "") or ("no decodable events (providers without embedded metadata, or kernel-only trace)"
                                           if not summary.get("events") else "")
        coverage.append({"file": rel, "events": summary.get("events", 0), "undecoded": summary.get("undecoded", 0), "note": note})
    found = sorted(groups.values(), key=lambda g: (-g["count"], g["code"]))
    return {"findings": found, "coverage": coverage,
            "events": sum(c["events"] for c in coverage), "files": len(coverage),
            "decoded_files": sum(1 for c in coverage if c["events"])}


# ═══ Registry ══════════════════════════════════════════════════════════════════

CORE_SERVICES = {   # service: what breaks if it's disabled (Start=4)
    "wuauserv": "Windows Update", "bits": "Windows Update downloads (BITS)", "cryptsvc": "Windows Update and signatures",
    "trustedinstaller": "installing updates (Windows Modules Installer)", "mpssvc": "Windows Firewall",
    "windefend": "Microsoft Defender", "wscsvc": "Windows Security Center", "eventlog": "event logging",
    "winmgmt": "WMI (management tools)", "dhcp": "getting an IP address", "dnscache": "DNS name lookups",
    "nlasvc": "network detection", "schedule": "scheduled tasks", "audiosrv": "sound", "rpcss": "almost everything (RPC)",
    "lanmanworkstation": "file sharing / mapped drives", "wlansvc": "Wi-Fi", "netman": "network connections",
    "usosvc": "Windows Update orchestration", "appxsvc": "Store apps", "spooler": "printing",
    "vss": "Volume Shadow Copy (restore points, backups, some updates)",
}
LSA_DEFAULTS = {"msv1_0", "scecli", "rassfm", "kerberos", "schannel", "wdigest", "tspkg", "pku2u", "cloudap",
                "negoexts", "livessp", "", '""'}


def _driver_file(root, name, vals):
    img = str(vals.get("ImagePath") or "")
    t = vals.get("Type")
    if not img:
        if t in (1, 2):                                      # kernel/fs drivers default to drivers\<name>.sys
            return f"System32\\drivers\\{name}.sys", winlib.ci_path(root, f"Windows/System32/drivers/{name}.sys")
        return "", None
    if "svchost.exe" in img.lower():
        return img, True
    return img, winlib.win_to_local(root, img) if img else None


def _ft_days(ts):
    if not ts:
        return None
    dt = winlib.filetime(ts)
    return (datetime.datetime.utcnow() - dt).days if dt else None


def scan_registry(root, days=30):
    """Registry evidence of problems on a mounted Windows volume. Returns findings + recent changes."""
    out, recent = [], []

    def add(sev, area, title, detail="", fix=""):
        out.append({"severity": sev, "area": area, "title": title, "detail": detail, "fix": fix})

    if hivex is None:
        add("warning", "registry", "Registry tools missing (python3-hivex)")
        return {"findings": out, "recent": recent}
    sysh = open_hive(root, "Windows/System32/config/SYSTEM")
    sw = open_hive(root, "Windows/System32/config/SOFTWARE")
    if not sysh or not sw:
        add("warning", "registry", "SYSTEM or SOFTWARE hive missing or unreadable",
            "Windows can't boot without them.", "Check Windows/System32/config and its RegBack folder")
        if not sysh:
            return {"findings": out, "recent": recent}
    cs = control_set(sysh)
    svcs = cs + r"\Services"
    names = {s.lower(): s for s in sysh.subkeys(svcs)}

    # Services and drivers set to start, whose program/driver/DLL is missing
    for low, svc in names.items():
        vals = sysh.values(f"{svcs}\\{svc}")
        start, typ = vals.get("Start"), vals.get("Type")
        if start == 4 and low in CORE_SERVICES:
            add("warning", "services", f"{svc} is disabled: {CORE_SERVICES[low]} won't work",
                fix=f"Set it back in Windows (services.msc), or Start=2/3 under {svcs}\\{svc}")
        if start not in (0, 1, 2):
            continue
        img, local = _driver_file(root, svc, vals)
        if img and local is None and not img.lower().startswith(("\\??\\globalroot", "\\device")):
            boot = start in (0, 1) and typ in (1, 2)
            add("critical" if boot else "warning", "services",
                f"{'Boot driver' if boot else 'Service'} {svc} is set to start, but its file is missing",
                f"{img}" + (" — Windows may fail to boot (INACCESSIBLE_BOOT_DEVICE or a boot loop)" if boot else ""),
                "Reinstall the software/driver that owns it, or disable it (Start=4) if it was removed")
        dll = sysh.get(f"{svcs}\\{svc}\\Parameters", "ServiceDll")
        if dll and "svchost.exe" in str(vals.get("ImagePath", "")).lower() and winlib.win_to_local(root, str(dll)) is None:
            add("warning", "services", f"Service {svc} points at a DLL that's missing", str(dll),
                "Repair Windows (DISM /RestoreHealth, sfc /scannow) or reinstall the owning software")
        # Third-party services/drivers added or changed recently (Windows touches its own constantly)
        n = sysh.node(f"{svcs}\\{svc}")
        d = _ft_days(sysh.h.node_timestamp(n)) if n else None
        third_party = img and not re.search(r"(?i)(^|\\)(systemroot|%systemroot%|%windir%|windows)\\|^system32\\", img)
        if d is not None and d <= days and third_party:
            recent.append({"when_days": d, "what": f"service/driver {svc}", "detail": img[:120]})

    # Device class filter drivers that don't exist (classic: no keyboard, no DVD, no disk after uninstalling software)
    classes = cs + r"\Control\Class"
    for guid in sysh.subkeys(classes):
        vals = sysh.values(f"{classes}\\{guid}")
        cname = vals.get("Class", guid)
        for kind in ("UpperFilters", "LowerFilters"):
            for f in (vals.get(kind) or []) if isinstance(vals.get(kind), list) else []:
                if f.lower() not in names:
                    add("critical" if cname.lower() in ("diskdrive", "scsiadapter", "hdc", "volume", "keyboard") else "warning",
                        "drivers", f"{cname} devices use a filter driver that isn't installed: {f}",
                        f"{kind} of {guid}. Every {cname} device will fail to start.",
                        f"Remove '{f}' from {kind} under {classes}\\{guid} (after backing up the hive)")

    # Boot-time programs
    sm = cs + r"\Control\Session Manager"
    be = sysh.get(sm, "BootExecute") or []
    extra = [x for x in (be if isinstance(be, list) else [be]) if x.strip() and not x.strip().lower().startswith("autocheck autochk")]
    if extra:
        add("warning", "boot", "Extra programs run before Windows starts (BootExecute)", "; ".join(extra),
            "Usually disk checkers or cleanup tools; malware also uses this")
    # Crash dumps and paging file
    cc = sysh.values(cs + r"\Control\CrashControl")
    if cc.get("CrashDumpEnabled") == 0:
        add("warning", "crashes", "Crash dumps are switched off", "Blue screens leave no evidence (no minidumps).",
            "Re-enable in System Properties > Advanced > Startup and Recovery")
    pf = sysh.get(sm + r"\Memory Management", "PagingFiles")
    if pf is not None and not [x for x in (pf if isinstance(pf, list) else [pf]) if x.strip()]:
        add("warning", "performance", "No paging file", "Low-memory errors are likely and crash dumps can't be written.")
    # LSA packages (credential theft / broken logon)
    lsa = sysh.values(cs + r"\Control\Lsa")
    for k in ("Authentication Packages", "Notification Packages", "Security Packages"):
        v = lsa.get(k) or []
        odd = [x for x in (v if isinstance(v, list) else [v]) if x.strip().lower() not in LSA_DEFAULTS]
        if odd:
            add("warning", "security", f"Non-standard LSA {k.lower()}: {', '.join(odd)}",
                "These load into the logon process. Legitimate for some security/VPN software; also a credential-theft technique.")
    if sysh.get(cs + r"\Control\SecurityProviders\WDigest", "UseLogonCredential") == 1:
        add("warning", "security", "WDigest stores logon passwords in memory in clear text (UseLogonCredential=1)",
            fix="Set UseLogonCredential to 0 (or delete it)")
    # RAID/RST boot mode (switching the BIOS to AHCI would stop Windows booting)
    for drv in ("iaStorAVC", "iaStorVD", "iaStorAC", "iaStorV"):
        if sysh.get(f"{svcs}\\{drv}", "Start") == 0:
            add("info", "boot", f"Windows boots through Intel RST/RAID ({drv})",
                "Changing the BIOS storage mode to AHCI will stop Windows booting (INACCESSIBLE_BOOT_DEVICE) unless prepared first.")
            break

    if sw:
        wl = sw.values(r"Microsoft\Windows NT\CurrentVersion\Winlogon")
        if str(wl.get("Shell", "explorer.exe")).strip().lower() not in ("explorer.exe", ""):
            add("critical", "persistence", "Windows' shell has been replaced", f"Shell = {wl.get('Shell')}",
                "Set Winlogon\\Shell back to explorer.exe")
        ui = str(wl.get("Userinit", "")).strip().lower().rstrip(",")
        if ui and not re.fullmatch(r"(c:\\windows\\system32\\)?userinit(\.exe)?", ui):
            add("critical", "persistence", "Extra program runs at every logon (Winlogon Userinit)", f"Userinit = {wl.get('Userinit')}",
                "Set it back to C:\\Windows\\system32\\userinit.exe,")
        if wl.get("AutoAdminLogon") in ("1", 1):
            add("info", "security", "Windows logs on automatically (AutoAdminLogon=1)")
        ifeo = r"Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
        for exe in sw.subkeys(ifeo):
            dbg = sw.get(f"{ifeo}\\{exe}", "Debugger")
            if dbg:
                access = exe.lower() in ("sethc.exe", "utilman.exe", "osk.exe", "narrator.exe", "magnify.exe", "displayswitch.exe")
                add("critical", "persistence", f"{exe} is hijacked: starting it runs something else" +
                    (" (logon-screen backdoor)" if access else ""), f"Debugger = {dbg}", f"Delete the Debugger value under {ifeo}\\{exe}")
        wn = sw.values(r"Microsoft\Windows NT\CurrentVersion\Windows")
        if wn.get("LoadAppInit_DLLs") == 1 and str(wn.get("AppInit_DLLs", "")).strip():
            add("critical", "persistence", "DLLs are injected into every program (AppInit_DLLs)", str(wn.get("AppInit_DLLs")))
        # Policies that switch protection or updates off
        dp = r"Policies\Microsoft\Windows Defender"
        if sw.get(dp, "DisableAntiSpyware") == 1 or sw.get(dp, "DisableAntiVirus") == 1:
            add("critical", "security", "Microsoft Defender is disabled by policy",
                "Malware does this; so does installing another antivirus. Check what's installed.")
        if sw.get(dp + r"\Real-Time Protection", "DisableRealtimeMonitoring") == 1:
            add("critical", "security", "Defender real-time protection is disabled by policy")
        for kind in ("Paths", "Processes", "Extensions"):
            ex = list(sw.values(f"{dp}\\Exclusions\\{kind}").keys()) + list(sw.values(f"Microsoft\\Windows Defender\\Exclusions\\{kind}").keys())
            broad = [e for e in ex if re.fullmatch(r"(?i)[a-z]:\\?|\*|\.?(exe|dll|ps1|bat|js|vbs)|.*\\(temp|appdata|users|downloads)\\?", e)]
            if broad:
                add("critical", "security", f"Defender ignores broad {kind.lower()}: {', '.join(broad[:5])}",
                    "Anything there is never scanned. Malware adds exclusions like these.")
            elif len(ex) > 0:
                add("info", "security", f"Defender {kind.lower()} exclusions: {len(ex)}", ", ".join(ex[:6]))
        au = r"Policies\Microsoft\Windows\WindowsUpdate"
        if sw.get(au + r"\AU", "NoAutoUpdate") == 1:
            add("warning", "update", "Automatic updates are switched off by policy")
        if sw.get(au, "WUServer"):
            add("info", "update", f"Updates come from a company server (WSUS): {sw.get(au, 'WUServer')}",
                "If that server is unreachable, Windows Update fails off the company network.")
        if sw.get(au, "DisableWindowsUpdateAccess") == 1 or sw.get(au, "DoNotConnectToWindowsUpdateInternetLocations") == 1:
            add("warning", "update", "Windows Update access is restricted by policy")
        sysp = r"Microsoft\Windows\CurrentVersion\Policies\System"
        sr = r"Microsoft\Windows NT\CurrentVersion\SystemRestore"
        if sw.get(sr, "RPSessionInterval") == 0 or sw.get(sr, "DisableSR") == 1 or \
                sw.get(r"Policies\Microsoft\Windows NT\SystemRestore", "DisableSR") == 1:
            add("info", "update", "System Restore is off", "No restore points; some installers and updates report 0x80070422 because of it.")
        if sw.get(sysp, "EnableLUA") == 0:
            add("warning", "security", "User Account Control is off (EnableLUA=0)")
        # Pending servicing
        cbs = r"Microsoft\Windows\CurrentVersion\Component Based Servicing"
        if "RebootPending" in sw.subkeys(cbs):
            add("warning", "update", "Windows servicing is waiting for a restart (RebootPending)")
        if "SessionsPending" in sw.subkeys(cbs) and sw.get(cbs + r"\SessionsPending", "Exclusive"):
            add("warning", "update", "An exclusive servicing session is pending", "Updates may be stuck mid-install.",
                "Restart once; if it loops: dism /image:C:\\ /cleanup-image /revertpendingactions from WinRE")
        if "RebootRequired" in sw.subkeys(r"Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update"):
            add("info", "update", "Windows Update wants a restart")
        # Recently installed software
        for base in (r"Microsoft\Windows\CurrentVersion\Uninstall", r"WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"):
            for k in sw.subkeys(base):
                v = sw.values(f"{base}\\{k}")
                name, date = v.get("DisplayName"), str(v.get("InstallDate") or "")
                if not name or v.get("SystemComponent") == 1:
                    continue
                try:
                    age = (datetime.datetime.utcnow() - datetime.datetime.strptime(date[:8], "%Y%m%d")).days if date else None
                except ValueError:
                    age = None
                if age is None:
                    n = sw.node(f"{base}\\{k}")
                    age = _ft_days(sw.h.node_timestamp(n)) if n else None
                if age is not None and age <= days:
                    recent.append({"when_days": age, "what": f"software {name}", "detail": str(v.get("Publisher") or "")})

    # Per-user: proxy, lockdown policies, shell
    users = ci_path(root, "Users")
    for u in (sorted(users.iterdir()) if users and users.is_dir() else []):
        nt = ci_path(u, "NTUSER.DAT")
        if not nt:
            continue
        try:
            h = Hive(nt)
        except (RuntimeError, OSError):
            continue
        inet = h.values(r"Software\Microsoft\Windows\CurrentVersion\Internet Settings")
        if inet.get("ProxyEnable") == 1 and inet.get("ProxyServer"):
            add("warning", "network", f"{u.name}: web traffic goes through a proxy: {inet.get('ProxyServer')}",
                "If it's not the company's, it breaks browsing (or intercepts it).", "Internet Options > Connections > LAN settings")
        if inet.get("AutoConfigURL"):
            add("info", "network", f"{u.name}: proxy auto-config script: {inet.get('AutoConfigURL')}")
        pol = h.values(r"Software\Microsoft\Windows\CurrentVersion\Policies\System")
        locks = [k for k in ("DisableTaskMgr", "DisableRegistryTools", "DisableCMD") if pol.get(k) in (1, 2)]
        if locks:
            add("warning", "persistence", f"{u.name}: {', '.join(locks)} set", "Malware blocks these tools; so do some company policies.")
        sh = h.get(r"Software\Microsoft\Windows NT\CurrentVersion\Winlogon", "Shell")
        if sh:
            add("critical", "persistence", f"{u.name}: a per-user shell replaces Explorer", f"Shell = {sh}")
        for kind in ("Run", "RunOnce"):
            n = h.node(f"Software\\Microsoft\\Windows\\CurrentVersion\\{kind}")
            dd = _ft_days(h.h.node_timestamp(n)) if n else None
            if dd is not None and dd <= days and h.values(f"Software\\Microsoft\\Windows\\CurrentVersion\\{kind}"):
                recent.append({"when_days": dd, "what": f"{u.name}'s {kind} autostart key changed", "detail": ""})

    # hosts file redirects (network evidence, not registry, but the same question)
    hosts = ci_path(root, "Windows/System32/drivers/etc/hosts")
    if hosts:
        try:
            lines = [l.split("#")[0].split() for l in hosts.read_text(errors="replace").splitlines()]
            entries = [l for l in lines if len(l) >= 2 and l[1].lower() not in ("localhost",)]
            if entries:
                bad = [e for e in entries if re.search(r"microsoft|windowsupdate|defender|google|bank|paypal|apple", e[1], re.I)]
                add("critical" if bad else "info", "network", f"hosts file redirects {len(entries)} name(s)",
                    ", ".join(f"{e[1]}→{e[0]}" for e in (bad or entries)[:6]),
                    "Redirecting security/update sites blocks updates and antivirus" if bad else "")
        except OSError:
            pass
    order = {"critical": 0, "warning": 1, "info": 2}
    return {"findings": sorted(out, key=lambda f: order[f["severity"]]), "recent": sorted(recent, key=lambda r: r["when_days"])}


# ═══ Servicing (CBS, DISM, Windows Update, Panther) ═══════════════════════════

HRESULTS = {
    "0x800f081f": "CBS_E_SOURCE_MISSING: repair/feature files not found. DISM needs a source (Windows Update or matching install media)",
    "0x800f0831": "CBS_E_STORE_CORRUPTION: the component store is missing a previous update's files",
    "0x80073712": "ERROR_SXS_COMPONENT_STORE_CORRUPT: the component store is damaged",
    "0x800f0922": "CBS_E_INSTALLERS_FAILED: an update's installer failed (often the System Reserved/EFI partition is too small, or a VPN/.NET problem)",
    "0x800f0988": "PSFX_E_INVALID_DELTA_COMBINATION: update cleanup needed (dism /online /cleanup-image /startcomponentcleanup)",
    "0x800f0982": "PSFX_E_MATCHING_COMPONENT_NOT_FOUND: often a language pack mismatch",
    "0x800f0986": "PSFX_E_APPLY_FORWARD_DELTA_FAILED: the update's differential files didn't apply",
    "0x800f0823": "CBS_E_NEW_SERVICING_STACK_REQUIRED: install the latest servicing stack update first",
    "0x800f0900": "CBS_E_XML_PARSER_FAILURE: a damaged update manifest",
    "0x800f0920": "CBS_E_HANG_DETECTED: servicing hung (often antivirus or a slow/failing disk)",
    "0x8007000d": "ERROR_INVALID_DATA: a damaged file",
    "0x80070002": "ERROR_FILE_NOT_FOUND", "0x80070003": "ERROR_PATH_NOT_FOUND",
    "0x80070005": "E_ACCESSDENIED: access denied (permissions, or antivirus interfering)",
    "0x80070020": "ERROR_SHARING_VIOLATION: a file was in use (often antivirus)",
    "0x80070070": "ERROR_DISK_FULL: not enough disk space",
    "0x80070570": "ERROR_FILE_CORRUPT: a file or the disk is corrupt (run chkdsk)",
    "0x800705b9": "ERROR_XML_PARSE_ERROR: a damaged XML file",
    "0x8007371b": "ERROR_SXS_TRANSACTION_CLOSURE_INCOMPLETE: a dependency is missing",
    "0x80073701": "ERROR_SXS_ASSEMBLY_MISSING: a component is missing (often a language pack)",
    "0x80070643": "ERROR_INSTALL_FAILURE: an installer failed (KB5034441 does this when the recovery partition is too small)",
    "0x80070422": "ERROR_SERVICE_DISABLED: a service the operation needed is disabled",
    "0x8024401c": "WU_E_PT_HTTP_STATUS_REQUEST_TIMEOUT: the update server didn't answer in time (network; usually transient)",
    "0x80072ee6": "WinHTTP 12006: the update address or proxy setting isn't usable (often a proxy/policy problem)",
    "0x8024000c": "WU_E_NOOP: nothing needed doing (harmless)",
    "0x80070057": "E_INVALIDARG: an invalid parameter (often a damaged setting or registry value)",
    "0x800704cf": "ERROR_NETWORK_UNREACHABLE: the network couldn't be reached",
    "0x80070652": "ERROR_INSTALL_ALREADY_RUNNING: another installation was running",
    "0x8007001f": "ERROR_GEN_FAILURE: a device isn't working",
    "0x80240017": "WU_E_NOT_APPLICABLE: the update doesn't apply to this machine",
    "0x8024200b": "WU_E_UH_INSTALLERFAILURE: the update's installer failed (driver/firmware updates)",
    "0x80240016": "WU_E_INSTALL_NOT_ALLOWED: another install was running or a restart was pending",
    "0x8024402c": "WU_E_PT_WINHTTP_NAME_NOT_RESOLVED: couldn't resolve the update server (DNS/proxy)",
    "0x80244022": "WU_E_PT_HTTP_STATUS_SERVICE_UNAVAIL: the update server was unavailable",
    "0x8000ffff": "E_UNEXPECTED: catastrophic failure (often the servicing stack)",
    "0x80004005": "E_FAIL: unspecified failure",
    "0xc1900101": "Feature update rolled back: usually a driver (check setuperr.log for the driver)",
    "0xc1900208": "Feature update blocked by an incompatible app",
    "0xc1900200": "The PC doesn't meet the upgrade's requirements", "0xc1900202": "The PC doesn't meet the upgrade's requirements",
    "0xc190020e": "Not enough disk space for the feature update",
}
CBS_LINE = re.compile(r"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d), (\w+)\s+(\w+)\s+(.*)$")
HR = re.compile(r"(?:HRESULT\s*=\s*|hr\s*[:=]\s*|error\s+|\[|\b)(0x[0-9a-fA-F]{8})\b")
KB = re.compile(r"\b(KB\d{6,8})\b", re.I)
PKG = re.compile(r"Package_(?:for_)?([A-Za-z0-9_]+?)~31bf3856ad364e35~\w+~~([\d.]+)")
CORRUPT = re.compile(r"CSI (Payload|Manifest|Store) Corrupt|Hashes for file member .* do not match|"
                     r"\[SR\] Cannot repair member file|Corrupt File:|corrupt(ion)? detected|Store corruption", re.I)


def _norm(msg):
    msg = re.sub(r"\[l:\d+[^\]]*\]|\{[0-9a-f-]{36}\}|\b\d+(_\d+)+\b|@\d{4}/\d+/\d+:\d+:\d+:\d+(\.\d+)?", "…", msg)
    return re.sub(r"\s+", " ", msg)[:160]


def _cbs_logs(root, tmp, archives=12):
    """CBS.log plus the newest archived CbsPersist logs (cab or log), newest first."""
    logs = []
    d = ci_path(root, "Windows/Logs/CBS")
    if not d or not d.is_dir():
        return logs, []
    notes = []
    cur = ci_path(d, "CBS.log")
    if cur:
        logs.append(cur)
    persist = sorted((f for f in d.iterdir() if f.name.lower().startswith("cbspersist_")), key=lambda f: f.name, reverse=True)
    for f in persist[:archives]:
        if f.suffix.lower() == ".log":
            logs.append(f)
        elif f.suffix.lower() == ".cab":
            if not shutil.which("cabextract"):
                notes.append("Archived CBS logs (.cab) skipped: cabextract isn't installed")
                break
            out = Path(tmp) / f.stem
            out.mkdir(exist_ok=True)
            subprocess.run(["cabextract", "-q", "-d", str(out), str(f)], capture_output=True, timeout=120)
            logs += sorted(out.glob("*.log"))
    if len(persist) > archives:
        notes.append(f"Read the {archives} newest of {len(persist)} archived CBS logs")
    return logs, notes


def _read_lines(path):
    with open(path, "rb") as f:
        head = f.read(2)
    enc = "utf-16" if head in (b"\xff\xfe", b"\xfe\xff") else "utf-8"
    with open(path, encoding=enc, errors="replace") as f:
        yield from f


def scan_servicing(target, days=90):
    """Servicing evidence. target: a Windows mount point, or a CBS.log / dism.log / folder of logs."""
    cutoff = _cutoff(days)[:10]
    errors, corrupt, sessions, sfc, notes = {}, [], [], {}, []
    wu = {"failed": {}, "installed": []}
    panther = []
    t = Path(target)
    tmp = tempfile.mkdtemp(prefix="sysmedic-cbs-")
    try:
        if t.is_file():
            cbs_logs = [t] if "dism" not in t.name.lower() else []
            dism = t if "dism" in t.name.lower() else None
            root = None
        else:
            root = t if ci_path(t, "Windows") else None
            if root:
                cbs_logs, notes = _cbs_logs(root, tmp)
                dism = ci_path(root, "Windows/Logs/DISM/dism.log")
            else:
                cbs_logs = sorted(f for f in t.rglob("*") if re.match(r"(?i)(cbs|cbspersist_.*)\.log$", f.name))
                dism = next((f for f in t.rglob("*") if f.name.lower() == "dism.log"), None)
        for src in [*cbs_logs, *([dism] if dism else [])]:
            tool = "DISM" if src == dism else "CBS"
            for line in _read_lines(src):
                m = CBS_LINE.match(line.rstrip())
                if not m:
                    continue
                when, level, comp, msg = m.groups()
                if cutoff and when[:10] < cutoff:
                    continue
                if CORRUPT.search(msg):
                    corrupt.append((when, _norm(msg)))
                if "[SR]" in msg:
                    if "Verify complete" in msg or "Beginning Verify and Repair" in msg:
                        sfc["last_run"] = when
                    if "Repairing corrupted file" in msg or "Repaired file" in msg:
                        sfc["repaired"] = sfc.get("repaired", 0) + 1
                    if "Cannot repair member file" in msg:
                        sfc["unrepaired"] = sfc.get("unrepaired", 0) + 1
                mtot = re.search(r"Total Detected Corruption:\s*(\d+)", msg)
                if mtot:
                    sfc["dism_detected"] = int(mtot.group(1))
                mrep = re.search(r"Total Repaired Corruption:\s*(\d+)", msg)
                if mrep:
                    sfc["dism_repaired"] = int(mrep.group(1))
                if "Exec: Processing complete" in msg:
                    hr = HR.search(msg)
                    pk = PKG.search(msg) or KB.search(msg)
                    sessions.append((when, pk.group(1) if pk else "", hr.group(1).lower() if hr else ""))
                if level.lower() == "error" or ("Failed" in msg and HR.search(msg)):
                    hr = HR.search(msg)
                    code = hr.group(1).lower() if hr else ""
                    if code in ("0x00000000", "0x00000001"):
                        continue
                    key = (tool, code, _norm(re.sub(r"\[HRESULT.*", "", msg)))
                    g = errors.setdefault(key, {"tool": tool, "code": code, "message": key[2], "count": 0,
                                                "first": when, "last": when, "packages": set()})
                    g["count"] += 1
                    g["first"], g["last"] = min(g["first"], when), max(g["last"], when)
                    pk = PKG.search(msg) or KB.search(msg)
                    if pk:
                        g["packages"].add(pk.group(1))
        if root:
            rep = ci_path(root, "Windows/SoftwareDistribution/ReportingEvents.log")
            if rep:
                for line in _read_lines(rep):
                    m = re.search(r"(\d{4}-\d\d-\d\d \d\d:\d\d).*Installation (Failure|Successful): Windows (?:failed to install|"
                                  r"successfully installed) the following update(?: with error (0x[0-9A-Fa-f]{8}))?: (.+)$", line.strip())
                    if not m or (cutoff and m.group(1)[:10] < cutoff):
                        continue
                    when, result, code, title = m.groups()
                    if result == "Failure":
                        g = wu["failed"].setdefault(title.strip()[:140], {"codes": set(), "count": 0, "last": when})
                        g["codes"].add((code or "").lower())
                        g["count"] += 1
                        g["last"] = max(g["last"], when)
                    else:
                        wu["installed"].append((when, title.strip()[:140]))
            for rel in ("Windows/Panther/setuperr.log", "$WINDOWS.~BT/Sources/Panther/setuperr.log",
                        "Windows/Panther/NewOs/Panther/setuperr.log"):
                p = ci_path(root, rel)
                if p:
                    lines = [l.strip() for l in _read_lines(p) if ", Error" in l]
                    if lines:
                        codes = sorted({c.lower() for l in lines for c in re.findall(r"0x[0-9A-Fa-f]{8}", l)})
                        panther.append({"file": rel, "errors": len(lines), "last": lines[-1][:220],
                                        "codes": [c for c in codes if c.startswith("0xc19") or c in HRESULTS][:8]})
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    errs = sorted(errors.values(), key=lambda g: (-g["count"]))
    for g in errs:
        g["packages"] = sorted(g["packages"])[:6]
        g["meaning"] = HRESULTS.get(g["code"], "")
    for g in wu["failed"].values():
        g["codes"] = sorted(c for c in g["codes"] if c)
    return {"errors": errs, "corruption": corrupt[-50:], "corruption_count": len(corrupt), "sessions": sessions[-30:],
            "sfc": sfc, "wu": wu, "panther": panther, "notes": notes, "read": [str(p) for p in cbs_logs] + ([str(dism)] if dism else [])}


def servicing_verdict(s):
    """Plain-English verdict and next steps from scan_servicing()."""
    out = []
    codes = {g["code"] for g in s["errors"]} | {c for g in s["wu"]["failed"].values() for c in g["codes"]}
    unrepaired = s["sfc"].get("unrepaired", 0) or (s["sfc"].get("dism_detected", 0) > s["sfc"].get("dism_repaired", 0))
    if s["corruption_count"] or codes & {"0x800f0831", "0x80073712", "0x800f0900"}:
        out.append(("critical", "Windows' component store is damaged" + (" and repairs have failed" if unrepaired else ""),
                    "In Windows (admin): DISM /Online /Cleanup-Image /RestoreHealth, then sfc /scannow. "
                    "Offline from WinRE: sfc /scannow /offbootdir=C:\\ /offwindir=C:\\Windows. "
                    "If DISM fails with 0x800f081f, give it matching install media (/Source:wim:X:\\sources\\install.wim:1 /LimitAccess) "
                    "or do an in-place repair upgrade (keeps files and apps)."))
    elif "0x800f081f" in codes:
        out.append(("warning", "Repairs couldn't find source files (0x800f081f)",
                    "Run DISM /RestoreHealth with matching install media as /Source, or an in-place repair upgrade."))
    if codes & {"0x80070070", "0xc190020e"}:
        out.append(("warning", "Updates failed for lack of disk space", "Free space on C: (Disk Cleanup > system files)."))
    if "0x800f0922" in codes:
        out.append(("warning", "An update's installer failed (0x800f0922)",
                    "Check the EFI/System Reserved partition has free space, disconnect VPN software, then retry."))
    if "0x80070643" in codes:
        out.append(("warning", "An update failed with 0x80070643",
                    "If it's KB5034441 the recovery partition is too small (Microsoft's KB5028997 explains resizing it)."))
    if codes & {"0x80070005", "0x80070020", "0x800f0920"}:
        out.append(("warning", "Servicing was blocked (access denied, file in use, or a hang)",
                    "Usually third-party antivirus or a failing disk: check the disk's SMART health and retry with AV paused."))
    if "0x80070422" in codes:
        out.append(("warning", "Something needed a service that is disabled (0x80070422)",
                    "Usually Windows Update, BITS or Cryptographic Services (sysmedic-win registry lists disabled core services), "
                    "or System Restore / Volume Shadow Copy being off."))
    if s["panther"]:
        pc = sorted({c for p in s["panther"] for c in p["codes"]})
        upg = {"0xc1900101": "a driver failed during the upgrade: update or remove the driver named in setuperr.log, then retry",
               "0xc1900208": "an incompatible app blocked the upgrade: uninstall it (named in setuperr.log)",
               "0xc190020e": "not enough free space for the upgrade",
               "0xc1900200": "the PC doesn't meet the upgrade's requirements", "0xc1900202": "the PC doesn't meet the upgrade's requirements"}
        hit = [c for c in pc if c in upg]
        if hit:
            out.append(("warning", "A Windows upgrade failed: " + ", ".join(hit), "; ".join(upg[c] for c in hit) + "."))
        else:
            out.append(("info", "Windows Setup logged errors" + (f" ({', '.join(pc)})" if pc else "") + ", but no upgrade failure code",
                        "; ".join(f"{c}: {HRESULTS[c]}" for c in pc if c in HRESULTS) or "Details in setuperr.log (sysmedic-win cbs shows the last line)."))
    repeat = [(t, g) for t, g in s["wu"]["failed"].items() if g["count"] >= 2]
    for t, g in repeat[:3]:
        out.append(("warning", f"Keeps failing: {t} ({g['count']}×, {', '.join(g['codes'])})",
                    "; ".join(HRESULTS.get(c, c) for c in g["codes"][:2])))
    if not out:
        out.append(("ok", "No servicing problems found in the logs", ""))
    return out
