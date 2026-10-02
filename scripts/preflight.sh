#!/bin/bash
# SysMedic Preflight — Hardware detection + context gathering
# Runs on boot before launching the AI agent.
# Outputs structured JSON to /tmp/sysmedic-context.json

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'; BOLD='\033[1m'
info()  { echo -e "  ${CYAN}[PREFLIGHT]${NC} $1"; }
ok()    { echo -e "  ${GREEN}[PREFLIGHT]${NC} $1"; }
warn()  { echo -e "  ${YELLOW}[PREFLIGHT]${NC} $1"; }

CONTEXT_FILE="/tmp/sysmedic-context.json"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
mkdir -p /tmp/sysmedic-preflight

echo ""
echo -e "${BOLD}  ╔══════════════════════════════════════╗${NC}"
echo -e "${BOLD}  ║   🔍  SysMedic Preflight             ║${NC}"
echo -e "${BOLD}  ║   Detecting hardware & gathering     ║${NC}"
echo -e "${BOLD}  ║   context from the mesh...           ║${NC}"
echo -e "${BOLD}  ╚══════════════════════════════════════╝${NC}"
echo ""
# ──────────────────────────────────────────────
# Set up persistence (session save/restore)
# ──────────────────────────────────────────────
if [ -x "$(dirname "$0")/sysmedic-persist.sh" ]; then
    bash "$(dirname "$0")/sysmedic-persist.sh" setup
fi

# ──────────────────────────────────────────────
# Check for updates (non-blocking, background)
# ──────────────────────────────────────────────
if [ -x "$(dirname "$0")/sysmedic-update.sh" ]; then
    bash "$(dirname "$0")/sysmedic-update.sh" check &
fi

info "Collecting hardware data..."

# ──────────────────────────────────────────────
# Build JSON via Python (handles escaping properly)
# ──────────────────────────────────────────────
python3 << PYEOF 2>/dev/null
import json, subprocess, os, re

def read_cmd(cmd):
    try:
        return subprocess.check_output(cmd, shell=True, stderr=subprocess.DEVNULL, timeout=5).decode('utf-8', errors='replace').strip()
    except:
        return ""

def read_lines(cmd):
    try:
        out = subprocess.check_output(cmd, shell=True, stderr=subprocess.DEVNULL, timeout=5).decode('utf-8', errors='replace')
        return [l.strip() for l in out.split('\n') if l.strip()]
    except:
        return []

context = {
    "timestamp": "$TIMESTAMP",
    "hostname": read_cmd("hostname 2>/dev/null") or "sysmedic",
    "kernel": read_cmd("uname -a 2>/dev/null"),
}

# System
dmipairs = [
    ("vendor", "system-manufacturer"),
    ("product", "system-product-name"),
    ("serial", "system-serial-number"),
    ("bios_vendor", "bios-vendor"),
    ("bios_version", "bios-version"),
    ("bios_date", "bios-release-date"),
]
system = {}
for key, dmi_key in dmipairs:
    system[key] = read_cmd(f"dmidecode -s {dmi_key} 2>/dev/null") or "Unknown"
context["system"] = system

# CPU
cpuinfo = read_cmd("cat /proc/cpuinfo 2>/dev/null")
context["cpu"] = {
    "model": re.search(r'model name\s*:\s*(.+)', cpuinfo).group(1).strip() if re.search(r'model name\s*:\s*(.+)', cpuinfo) else "Unknown",
    "cores": int((re.search(r'cpu cores\s*:\s*(\d+)', cpuinfo).group(1))) if re.search(r'cpu cores\s*:\s*(\d+)', cpuinfo) else 0,
    "threads": int((re.search(r'siblings\s*:\s*(\d+)', cpuinfo).group(1))) if re.search(r'siblings\s*:\s*(\d+)', cpuinfo) else 0,
    "arch": read_cmd("uname -m") or "unknown",
}

# Memory
mem_total_kb = read_cmd("grep MemTotal /proc/meminfo 2>/dev/null | awk '{print \$2}'")
mem_total_gb = round(int(mem_total_kb) / 1024 / 1024, 1) if mem_total_kb else 0

dimm_lines = read_lines("dmidecode -t memory 2>/dev/null | grep -E 'Manufacturer:|Type:|Speed:|Size:|Part Number:'")
dimm_info = "\n".join(dimm_lines) if dimm_lines else ""

context["memory"] = {
    "total_kb": int(mem_total_kb) if mem_total_kb else 0,
    "total_gb": mem_total_gb,
    "details": dimm_info,
}

# Disks
disks = []
disk_lines = read_lines("lsblk -d -o NAME,SIZE,MODEL,ROTA 2>/dev/null | grep -v loop")
for line in disk_lines[1:]:  # skip header
    parts = line.split(None, 3)
    if len(parts) < 4:
        continue
    name, size, model, rota = parts
    dtype = "HDD" if rota == "1" else "SSD"
    smart = "unknown"
    smart_out = read_cmd(f"smartctl -H /dev/{name} 2>/dev/null | grep -E 'SMART overall-health|PASSED|FAILED'")
    if "PASSED" in smart_out:
        smart = "PASSED"
    elif "FAILED" in smart_out:
        smart = "FAILED"
    disks.append({"device": f"/dev/{name}", "size": size, "model": model, "type": dtype, "smart": smart})
context["disks"] = disks

# GPU
gpu = read_cmd("lspci 2>/dev/null | grep -iE 'vga|3d|display' | sed 's/.*: //' | head -5 | paste -sd '; '")
context["gpu"] = gpu

# Network
try:
    ip_out = subprocess.check_output("ip -json addr show 2>/dev/null", shell=True, timeout=5).decode()
    ifaces = json.loads(ip_out)
    net_ifaces = []
    for iface in ifaces:
        if iface.get("name") == "lo":
            continue
        addrs = [a.get("local", "") for a in iface.get("addr_info", []) if a.get("family") == "inet"]
        net_ifaces.append({
            "name": iface.get("ifname", iface.get("name", "")),
            "mac": iface.get("address", ""),
            "ipv4": addrs,
        })
except:
    net_ifaces = []

ssid = read_cmd("iwgetid -r 2>/dev/null")
context["network"] = {"interfaces": net_ifaces, "wifi_ssid": ssid}

# Battery
bat_info = {}
for bat in os.listdir("/sys/class/power_supply/"):
    if bat.startswith("BAT"):
        base = f"/sys/class/power_supply/{bat}"
        def read_bat(f):
            try:
                with open(f"{base}/{f}") as fh:
                    return fh.read().strip()
            except:
                return None
        ef = read_bat("energy_full")
        efd = read_bat("energy_full_design")
        wear = 0.0
        if ef and efd and int(efd) > 0:
            wear = round((1 - int(ef) / int(efd)) * 100, 1)
        bat_info = {
            "name": bat,
            "status": read_bat("status") or "unknown",
            "capacity": int(read_bat("capacity") or 0),
            "wear_pct": wear,
        }
        break
context["battery"] = bat_info

# Secure Boot
sb_mokutil = read_cmd("mokutil --sb-state 2>/dev/null")
sb_cctk = "not_available"
if os.path.exists("/opt/dell/dcc/cctk"):
    sb_cctk = read_cmd("/opt/dell/dcc/cctk --SecureBoot 2>/dev/null") or "unknown"
context["secure_boot"] = {"mokutil": sb_mokutil, "cctk": sb_cctk}

# dmesg errors
dmesg_lines = read_lines("dmesg 2>/dev/null | grep -iE 'error|fail|panic|oops|hung|blocked' | tail -20")
context["dmesg_errors"] = dmesg_lines

# Detected OSes
oses = []
for line in read_lines("lsblk -nr -o NAME,FSTYPE 2>/dev/null | grep -E 'ext4|ntfs|hfsplus|apfs|xfs|btrfs'"):
    parts = line.split()
    if len(parts) < 2:
        continue
    dev_name, fstype = parts[0], parts[1]
    dev = f"/dev/{dev_name}"
    mp = "/tmp/sysmedic-preflight/mount_test"
    os.makedirs(mp, exist_ok=True)
    try:
        rc = subprocess.call(f"mount {dev} {mp} 2>/dev/null", shell=True, timeout=5)
        if rc == 0:
            os_type = None
            os_name = None
            if os.path.isfile(f"{mp}/etc/os-release"):
                os_type = "linux"
                with open(f"{mp}/etc/os-release") as f:
                    for ln in f:
                        if ln.startswith("PRETTY_NAME="):
                            os_name = ln.split("=", 1)[1].strip().strip('"')
                            break
                if not os_name:
                    os_name = f"Linux ({fstype})"
            elif os.path.isdir(f"{mp}/Windows/System32"):
                os_type = "windows"
                os_name = "Windows"
            elif os.path.isdir(f"{mp}/System/Library/CoreServices"):
                os_type = "macos"
                os_name = "macOS"
            if os_type:
                oses.append({"device": dev, "type": os_type, "name": os_name or fstype})
            subprocess.call(f"umount {mp} 2>/dev/null", shell=True)
    except:
        pass
context["detected_oses"] = oses

# (CraicKen mesh sync removed: the service has been shut down)

# Git sync (async — best effort)
git_status = "offline"
try:
    rc = subprocess.call("ping -c1 -W2 github.com >/dev/null 2>&1", shell=True, timeout=5)
    if rc == 0:
        rc2 = subprocess.call("cd /opt/sysmedic && git pull origin master 2>/dev/null", shell=True, timeout=15)
        git_status = "synced" if rc2 == 0 else "failed"
except:
    git_status = "unreachable"
context["git_sync"] = git_status

context["sysmedic_version"] = "2.1"

# Write context file
with open("$CONTEXT_FILE", "w") as f:
    json.dump(context, f, indent=2, default=str)

# Print summary
print()
sys_data = context.get("system", {})
print(f'  System:  {sys_data.get("vendor")} {sys_data.get("product")}')
cpu = context.get("cpu", {})
print(f'  CPU:     {cpu.get("model", "?")[:60]}')
mem = context.get("memory", {})
print(f'  RAM:     {mem.get("total_gb")} GB')
for disk in context.get("disks", []):
    print(f'  Disk:    {disk.get("device")} — {disk.get("size")} {disk.get("type")} ({disk.get("smart")})')
sb = context.get("secure_boot", {})
print(f'  Secure Boot: {sb.get("mokutil")} (cctk: {sb.get("cctk")})')
for os_item in context.get("detected_oses", []):
    print(f'  OS:      {os_item.get("name")} on {os_item.get("device")}')
print(f'  Git:     {context.get("git_sync")}')
PYEOF

# Check result
if [ -f "$CONTEXT_FILE" ] && python3 -c "import json; json.load(open('$CONTEXT_FILE'))" 2>/dev/null; then
    ok "Context snapshot written to $CONTEXT_FILE"
    echo ""
    ok "Preflight complete. AI will boot with full hardware context."
else
    warn "JSON generation failed — check $CONTEXT_FILE"
    cat "$CONTEXT_FILE" 2>/dev/null | head -10
fi

# Save session to persistent storage
if [ -x "$(dirname "$0")/sysmedic-persist.sh" ]; then
    bash "$(dirname "$0")/sysmedic-persist.sh" save "preflight"
fi
