"""session — the current SysMedic visit: its folder, job details, notes and audit trail.

One session per boot (see sysmedic-scan). Shared by sysmedic-report,
sysmedic-dash and sysmedic-note.
"""
import datetime
import json
import os
import re
from pathlib import Path

RUN = Path("/run/sysmedic")
PRIVATE_DIRS = [Path("/mnt/persist/private"), RUN / "private"]


def session_dir():
    for link in (RUN / "session", RUN / "latest"):
        if link.exists():
            return link.resolve()
    RUN.mkdir(parents=True, exist_ok=True)
    return RUN


def now():
    return datetime.datetime.now().astimezone().isoformat(timespec="seconds")


def audit(source, msg):
    with open(session_dir() / "audit.log", "a") as f:
        f.write(f"{now()} [{source}] {msg}\n")


def load_job():
    try:
        return json.loads((session_dir() / "job.json").read_text())
    except (OSError, json.JSONDecodeError):
        return {"engineer": "", "customer": "", "job_ref": "", "contact": "", "complaint": "", "notes": []}


def save_job(job):
    p = session_dir() / "job.json"
    tmp = p.with_suffix(".tmp")
    tmp.write_text(json.dumps(job, indent=2))
    os.replace(tmp, p)


def add_note(text, author):
    text = text.strip()[:2000]
    if not text:
        return
    job = load_job()
    job.setdefault("notes", []).append({"time": now(), "author": author, "text": text})
    save_job(job)
    audit(author, "NOTE " + re.sub(r"\s+", " ", text)[:200])


def scans():
    """All scan reports of this session, oldest first."""
    d = session_dir() / "scans"
    out = []
    for f in sorted(d.glob("scan-*.json")) if d.is_dir() else []:
        try:
            out.append(json.loads(f.read_text()))
        except (OSError, json.JSONDecodeError):
            pass
    if not out:
        try:
            out.append(json.loads((session_dir() / "scan.json").read_text()))
        except (OSError, json.JSONDecodeError):
            pass
    return out


def private_ids():
    for d in PRIVATE_DIRS:
        f = d / f"{session_dir().name}.json"
        if f.exists():
            try:
                return json.loads(f.read_text())
            except (OSError, json.JSONDecodeError):
                pass
    return {}


def audit_lines():
    try:
        return (session_dir() / "audit.log").read_text(errors="replace").splitlines()
    except OSError:
        return []


def _root_disk():
    src = os.popen("findmnt -no SOURCE / 2>/dev/null").read().strip()
    return os.popen(f"lsblk -no PKNAME {src} 2>/dev/null").read().split("\n")[0].strip() if src.startswith("/dev/") else ""


def guard_state():
    """Live write-protection state of customer disks: {device: 'locked'|'WRITABLE'}."""
    state = {}
    for dev in sorted(Path("/sys/class/block").iterdir()):
        name = dev.name
        if re.match(r"(loop|ram|zram|sr|dm-|md|fd|nbd)", name):
            continue
        try:
            labels = os.popen(f"lsblk -nro LABEL /dev/{name} 2>/dev/null").read()
        except OSError:
            labels = ""
        parent = dev.resolve().parent.name if (dev / "partition").exists() else name
        plabels = os.popen(f"lsblk -nro LABEL /dev/{parent} 2>/dev/null").read()
        if "SYSMEDIC_2404" in plabels or "FOG_AMB_PERSIST" in plabels or "SYSMEDIC_2404" in labels or parent == _root_disk():
            continue
        try:
            state[f"/dev/{name}"] = "locked" if (dev / "ro").read_text().strip() == "1" else "WRITABLE"
        except OSError:
            pass
    return state


def backups():
    d = session_dir() / "backups"
    out = []
    for f in sorted(d.rglob("*")) if d.is_dir() else []:
        if f.is_file():
            out.append({"path": str(f.relative_to(d)), "bytes": f.stat().st_size})
    return out
