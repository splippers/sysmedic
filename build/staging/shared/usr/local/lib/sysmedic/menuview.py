#!/usr/bin/env python3
"""menuview — the rescue menu's screen: a machine summary, then the options as grouped cards.

The menu (opt/sysmedic/rescue-menu.sh) keeps the actions; this only draws. Options are numbered in reading order
(card by card); the guides and messages quote these numbers ("menu 2" = tests), so change them together.
"""
import json
import os
import re
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ui import UI, MARK  # noqa: E402

EDITION = open("/etc/sysmedic/edition").read().strip() if os.path.exists("/etc/sysmedic/edition") else "dev"
VERSION = open("/etc/sysmedic/version").read().strip() if os.path.exists("/etc/sysmedic/version") else "dev"

CARDS = [
    ("Diagnose & test", [("1", "Triage scan (read-only)"), ("2", "Tests: hardware & software"),
                         ("3", "Job report for the customer"), ("4", "Phone dashboard (QR code)")]),
    ("AI", [("5", "AI rescue assistant (OpenCode)"), ("6", "Repair the AI assistant"),
            ("R", "Remote AI in the phone dashboard: " + ("ON (changes confirmed here)" if os.path.exists("/run/sysmedic/remote-ai.on") else "off"))]),
    ("Windows & disks", [("7", "Windows tools: BitLocker, crashes…"), ("8", "Unlock a partition for repair"),
                         ("9", "Write-protect all disks again"), ("10", "Back up data")]),
    ("Other systems", [("11", "Fix Linux boot (GRUB/initramfs)"), ("12", "Fix macOS (HFS+/APFS)")]),
    ("Connect & save", [("13", "Wi-Fi"), ("14", "Save extra logs to this session")]
     + ([("U", "Update SysMedic (from GitHub)")] if EDITION == "caddy" else [])),
    ("Desktop & tools", ([("G", "Graphical desktop (windows & mouse)")] if shutil.which("labwc") else [])
     + [("15", "Advanced toolkit"), ("16", "Shell (type exit to return)"), ("17", "Reboot"), ("0", "Shut down")]),
]


def visible_len(s):
    return len(re.sub(r"\033\[[0-9;]*m", "", s))


def pad(s, width):
    return s + " " * max(0, width - visible_len(s))


def summary(ui):
    lines = []
    try:
        scan = json.load(open("/run/sysmedic/latest/scan.json"))
    except (OSError, ValueError):
        scan = None
    net = ""
    try:
        net = subprocess.run(["/usr/local/bin/sysmedic-connect", "--status"], capture_output=True, text=True, timeout=4).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        pass
    ai = ""
    try:
        st = json.load(open("/run/sysmedic/ai-device.json"))
        ai = f"AI on {st['device']}" if st.get("mode") == "gpu" else "AI on CPU"
    except (OSError, ValueError, KeyError):
        pass
    if scan:
        s = scan["system"]
        model = f"{s.get('manufacturer', '')} {s.get('model', '')}".replace("Inc. ", "").strip()
        bits = [model] + ([f"network: {net}"] if net else []) + ([ai] if ai else [])
        lines.append("  " + ui.c("dim", " · ".join(b for b in bits if b)))
        counts = {sev: sum(f["severity"] == sev for f in scan["findings"]) for sev in ("critical", "warning", "info", "ok")}
        oses = [f.get("os") for f in scan.get("filesystems", []) if f.get("os")]
        bl = [f["device"] for f in scan.get("filesystems", []) if f.get("fstype") == "BitLocker"]
        extra = []
        if oses:
            extra.append(oses[0][:40])
        for d in bl:
            unlocked = os.path.exists(f"/dev/mapper/bitlocker-{os.path.basename(d)}")
            extra.append(f"BitLocker {os.path.basename(d)}: " + (ui.c("ok", "unlocked (read-only)") if unlocked else ui.c("warning", "locked")))
        lines.append(ui.chips(counts) + ("   " + ui.c("dim", "·") + "   " + "   ".join(extra) if extra else ""))
    else:
        lines.append("  " + ui.c("dim", f"{EDITION} v{VERSION}" + (f" · network: {net}" if net else "") + " · no scan yet: press 4"))
    try:
        up = json.load(open("/run/sysmedic/update.json"))
        if up.get("state") == "available" and EDITION == "caddy":
            lines.append(ui.item("warning", f"Update available: v{up.get('latest')}", "press U to see what changed and install it"))
    except (OSError, ValueError):
        pass
    return lines


def hud():
    """CPU temperature · memory · load · clock: the live strip under the logo."""
    import glob
    import time
    bits = []
    temps = []
    for h in glob.glob("/sys/class/hwmon/hwmon*"):
        try:
            if open(f"{h}/name").read().strip() in ("coretemp", "k10temp", "zenpower"):
                temps += [int(open(f).read()) / 1000 for f in glob.glob(f"{h}/temp*_input")]
        except (OSError, ValueError):
            pass
    if temps:
        bits.append(f"CPU {max(temps):.0f}°C")
    try:
        mem = {l.split(":")[0]: int(l.split()[1]) for l in open("/proc/meminfo")}
        bits.append(f"RAM {(mem['MemTotal'] - mem['MemAvailable']) / 2**20:.1f}/{mem['MemTotal'] / 2**20:.0f} GB")
    except (OSError, KeyError, ValueError):
        pass
    try:
        bits.append("load " + open("/proc/loadavg").read().split()[0])
    except OSError:
        pass
    bits.append(time.strftime("%H:%M"))
    return " · ".join(bits)


def logo(tagline):
    import importlib.util
    spec = importlib.util.spec_from_file_location("logo", os.path.join(os.path.dirname(os.path.abspath(__file__)), "logo.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m.render(tagline, color=sys.stdout.isatty() and not os.environ.get("NO_COLOR"))


def card(ui, title, items, width):
    out = [ui.c("bold", title) + " " + ui.c("dim", "─" * max(2, width - len(title) - 2))]
    for key, label in items:
        out.append(ui.c("accent", key.rjust(3)) + "  " + label[: width - 6])
    return out


def main():
    ui = UI()
    width = ui.width
    print()
    for line in logo([ui.c("bold", "RESCUE MENU"), ui.c("dim", f"{EDITION} edition · v{VERSION}"), ui.c("accent", hud())]):
        print(line)
    print(ui.rule())
    for line in summary(ui):
        print(line)
    print()
    cols = 2 if width >= 90 else 1
    colw = (width - 4 - 4 * (cols - 1)) // cols
    blocks = [card(ui, t, items, colw) for t, items in CARDS]
    if cols == 1:
        for b in blocks:
            for line in b:
                print("  " + line)
            print()
        return
    # two columns: fill left then right, keeping cards whole and the columns about even
    total = sum(len(b) + 1 for b in blocks)
    left, right, n = [], [], 0
    for b in blocks:
        (left if n + len(b) / 2 < total / 2 else right).append(b)
        n += len(b) + 1
    lrows = [line for b in left for line in b + [""]]
    rrows = [line for b in right for line in b + [""]]
    for i in range(max(len(lrows), len(rrows))):
        l = lrows[i] if i < len(lrows) else ""
        r = rrows[i] if i < len(rrows) else ""
        print("  " + pad(l, colw) + "    " + r)


if __name__ == "__main__":
    main()
