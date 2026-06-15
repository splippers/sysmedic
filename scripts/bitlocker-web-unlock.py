#!/usr/bin/env python3
"""
SysMedic BitLocker Web Unlock Portal
Spins up a LAN-accessible web server so you can paste a 48-digit recovery key
from your phone/laptop instead of typing it on the framebuffer console.

After unlock, runs diagnostics and exposes deep system insights.
"""

import http.server
import json
import os
import subprocess
import sys
import socket
import urllib.parse
import html
import threading
import time
import re
from pathlib import Path

# === Config ===
PORT = 8080
HTML_TITLE = "SysMedic — BitLocker Unlock Portal"
MOUNT_BASE = "/mnt"
BITLOCKER_DIR = "/mnt/bitlocker"
WINDOWS_MOUNT = "/mnt/windows"
REPORT_DIR = "/root/reports/windows"
TEMPLATE_DIR = "/opt/sysmedic/web-templates"

# === Globals (set during init) ===
g_state = {
    "blk_devs": [],          # detected BitLocker devices
    "hostname": socket.gethostname(),
    "lan_ip": "0.0.0.0",
    "disk_info": [],         # list of dicts
    "computer_name": "Unknown",
    "windows_version": "Unknown",
    "unlock_status": "none",  # none | unlocking | success | failed
    "unlock_message": "",
    "diagnostics": {},
    "recovery_key_hint": "",
    "has_run_diag": False,
}

# ============================================================
#  UTILITY FUNCTIONS
# ============================================================

def run_cmd(cmd, timeout=30):
    """Run a shell command and return (rc, stdout, stderr)."""
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout.strip(), r.stderr.strip()
    except subprocess.TimeoutExpired:
        return -1, "", "TIMEOUT"
    except Exception as e:
        return -1, "", str(e)


def get_lan_ip():
    """Get the primary LAN IP address."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
    except Exception:
        ip = "127.0.0.1"
    finally:
        s.close()
    return ip


def get_disk_info(dev_path):
    """Get disk model and serial for a block device."""
    base = os.path.basename(dev_path)
    # Get parent disk
    disk = re.sub(r'p?\d+$', '', base)
    dev = f"/dev/{disk}"
    
    info = {"device": dev_path, "model": "Unknown", "serial": "Unknown", "size": "Unknown"}
    
    rc, out, _ = run_cmd(["lsblk", "-dnro", "MODEL,SERIAL,SIZE", dev])
    if rc == 0 and out:
        parts = out.split(None, 2)
        info["model"] = parts[0] if len(parts) > 0 else "Unknown"
        info["serial"] = parts[1] if len(parts) > 1 else "Unknown"
        info["size"] = parts[2] if len(parts) > 2 else "Unknown"
    
    # Try smartctl for better serial
    rc, out, _ = run_cmd(["smartctl", "-i", dev])
    if rc == 0:
        for line in out.split('\n'):
            if 'Serial Number' in line:
                info["serial"] = line.split(':')[-1].strip()
            if 'Model Family' in line:
                info["model_family"] = line.split(':')[-1].strip()
            if 'Device Model' in line:
                info["model"] = line.split(':')[-1].strip()
    return info


def detect_bitlocker_volumes():
    """Find BitLocker-protected partitions."""
    volumes = []
    rc, out, _ = run_cmd(["lsblk", "-nro", "NAME"])
    if rc != 0:
        return volumes
    
    for line in out.split('\n'):
        dev = f"/dev/{line.strip()}"
        if not os.path.exists(dev):
            continue
        # Check with dislocker
        rc2, out2, _ = run_cmd(["dislocker", "-V", dev])
        if rc2 == 0 and ('BitLocker' in out2 or 'bitlocker' in out2.lower()):
            size = ""
            rc3, out3, _ = run_cmd(["lsblk", "-nro", "SIZE", dev])
            if rc3 == 0:
                size = out3
            volumes.append({"device": dev, "size": size})
    
    return volumes


def try_read_windows_info():
    """Try to read computer name and Windows version from registry."""
    reg_software = f"{WINDOWS_MOUNT}/Windows/System32/config/SOFTWARE"
    reg_system = f"{WINDOWS_MOUNT}/Windows/System32/config/SYSTEM"
    
    # Computer name from SYSTEM hive
    if os.path.exists(reg_system):
        rc, out, _ = run_cmd(["chntpw", "-e", reg_system])
        if rc == 0:
            for line in out.split('\n'):
                if 'ComputerName' in line and 'DNSHostName' not in line:
                    g_state["computer_name"] = line.split()[-1].strip()
                    break
    
    # Windows version from SOFTWARE hive
    if os.path.exists(reg_software):
        rc, out, _ = run_cmd(["chntpw", "-e", reg_software])
        if rc == 0:
            for line in out.split('\n'):
                if 'ProductName' in line:
                    parts = line.split()
                    if len(parts) >= 2:
                        g_state["windows_version"] = parts[-1].strip()
                if 'CurrentBuild' in line and len(line.split()) >= 2:
                    build = line.split()[-1].strip()
                    g_state["windows_version"] += f" (Build {build})"


def read_diagnostics():
    """Run the Windows diagnostic collection on the unlocked volume."""
    results = {}
    
    if not os.path.ismount(WINDOWS_MOUNT) or not os.path.exists(f"{WINDOWS_MOUNT}/Windows"):
        return {"error": "Windows volume not mounted or not a valid Windows installation"}
    
    win_dir = f"{WINDOWS_MOUNT}/Windows"
    sys32 = f"{win_dir}/System32"
    evtx_dir = f"{sys32}/winevt/Logs"
    
    # 1. CBS error count
    cbs_log = f"{win_dir}/Logs/CBS/CBS.log"
    if os.path.exists(cbs_log):
        rc, out, _ = run_cmd(["grep", "-ci", "error", cbs_log])
        cbs_errors = int(out) if out else 0
        rc, out, _ = run_cmd(["grep", "-ci", "failed", cbs_log])
        cbs_fails = int(out) if out else 0
        
        # Extract top error codes
        rc, out, _ = run_cmd(["grep", "-oE", "0x[0-9A-Fa-f]{8}", cbs_log])
        codes = out.split('\n') if out else []
        from collections import Counter
        top_codes = Counter(codes).most_common(10) if codes else []
        
        results["cbs"] = {
            "errors": cbs_errors,
            "failures": cbs_fails,
            "top_error_codes": [f"{c[0]} ({c[1]}x)" for c in top_codes],
            "log_size": os.path.getsize(cbs_log),
        }
    
    # 2. Minidumps
    minidump_dir = f"{win_dir}/Minidump"
    if os.path.isdir(minidump_dir):
        dmps = list(Path(minidump_dir).glob("*.dmp"))
        if dmps:
            dump_info = []
            for dmp in dmps:
                mtime = os.path.getmtime(dmp)
                size = os.path.getsize(dmp)
                # Extract bugcheck codes via strings
                rc, out, _ = run_cmd(["strings", str(dmp)])
                bugchecks = []
                if rc == 0:
                    for line in out.split('\n'):
                        if any(kw in line.upper() for kw in ['BUGCHECK', 'DRIVER_', 'IRQL', 'KMODE', 'SYSTEM_SERVICE', 'DPC_WATCHDOG', 'KERNEL_SECURITY', 'PAGE_FAULT', 'PFN_LIST', 'BAD_POOL', 'CRITICAL', 'NTFS', 'VIDEO_TDR', 'THREAD_STUCK']):
                            bugchecks.append(line.strip())
                
                dump_info.append({
                    "name": dmp.name,
                    "size": size,
                    "date": time.strftime('%Y-%m-%d %H:%M', time.localtime(mtime)),
                    "bugchecks": bugchecks[:10],
                })
            results["minidumps"] = dump_info
        else:
            results["minidumps"] = []
    
    # 3. MEMORY.DMP
    mem_dmp = f"{win_dir}/MEMORY.DMP"
    if os.path.exists(mem_dmp):
        size = os.path.getsize(mem_dmp)
        mtime = os.path.getmtime(mem_dmp)
        rc, out, _ = run_cmd(["strings", mem_dmp])
        bugchecks = []
        if rc == 0:
            for line in out.split('\n'):
                if any(kw in line.upper() for kw in ['BUGCHECK', 'DRIVER_IRQL', 'KMODE_EXCEPTION', 'DPC_WATCHDOG', 'KERNEL_SECURITY', 'PFN_LIST', 'BAD_POOL', '0x00000']):
                    bugchecks.append(line.strip())
        results["memory_dump"] = {
            "size": size,
            "date": time.strftime('%Y-%m-%d %H:%M', time.localtime(mtime)),
            "bugchecks": bugchecks[:20],
        }
    
    # 4. System event log — BugCheck events
    sys_evtx = f"{evtx_dir}/System.evtx"
    if os.path.exists(sys_evtx):
        rc, out, _ = run_cmd(["evtxexport", sys_evtx])
        if rc == 0:
            # Extract BugCheck events
            bugcheck_events = []
            for line in out.split('\n'):
                if 'BugCheck' in line or '0x000000' in line:
                    bugcheck_events.append(line.strip()[:200])
            results["system_events_bugcheck"] = bugcheck_events[:30]
    
    # 5. Windows Update client events
    wu_evtx = f"{evtx_dir}/Microsoft-Windows-WindowsUpdateClient%4Operational.evtx"
    if os.path.exists(wu_evtx):
        rc, out, _ = run_cmd(["evtxexport", wu_evtx])
        if rc == 0:
            wu_errors = []
            wu_success = []
            for line in out.split('\n'):
                if 'error' in line.lower() or 'failed' in line.lower() or '0x8' in line:
                    wu_errors.append(line.strip()[:200])
                if 'installed successfully' in line.lower() or 'installation success' in line.lower():
                    wu_success.append(line.strip()[:200])
            results["windows_update"] = {
                "errors": wu_errors[:30],
                "successes": wu_success[:10],
            }
    
    # 6. Driver store — check for problematic drivers
    drv_store = f"{sys32}/DriverStore/FileRepository"
    if os.path.isdir(drv_store):
        rc, out, _ = run_cmd(["ls", drv_store])
        drv_count = len(out.split('\n')) if out else 0
        results["driver_store"] = {"package_count": drv_count}
    
    # 7. Problematic driver check
    problem_drivers = [
        "nvlddmkm.sys", "dxgkrnl.sys", "igdkmd64.sys", "atikmdag.sys",
        "rtwlan.sys", "e1d65x64.sys", "netwlv64.sys", "bcmwl63a.sys",
        "tcpip.sys", "ntoskrnl.exe",
    ]
    found_problematic = []
    for drv in problem_drivers:
        rc, out, _ = run_cmd(["find", win_dir, "-name", drv, "-maxdepth", "5"])
        if out:
            found_problematic.append(drv)
    results["problematic_drivers_present"] = found_problematic
    
    # 8. SoftwareDistribution cache
    sd = f"{win_dir}/SoftwareDistribution"
    if os.path.isdir(sd):
        rc, out, _ = run_cmd(["du", "-sh", sd])
        sd_size = out if rc == 0 else "Unknown"
        dl_dir = f"{sd}/Download"
        dl_count = 0
        if os.path.isdir(dl_dir):
            dl_count = len(list(Path(dl_dir).iterdir())) if any(Path(dl_dir).iterdir()) else 0
        results["update_cache"] = {
            "size": sd_size,
            "pending_downloads": dl_count,
        }
    
    # 9. Pending reboot check
    pending_xml = f"{win_dir}/WinSxS/pending.xml"
    results["pending_reboot"] = os.path.exists(pending_xml)
    
    # 10. Error code frequency (all logs)
    all_errors = {}
    for log_path in [cbs_log, f"{win_dir}/Logs/DISM/DISM.log", f"{win_dir}/Panther/setupact.log"]:
        if os.path.exists(log_path):
            rc, out, _ = run_cmd(["grep", "-oE", "0x[0-9A-Fa-f]{8}", log_path])
            if rc == 0 and out:
                for code in out.split('\n'):
                    code = code.strip()
                    if code:
                        all_errors[code] = all_errors.get(code, 0) + 1
    
    top_all = sorted(all_errors.items(), key=lambda x: -x[1])[:15]
    results["top_error_codes_all"] = [f"{c} ({n}x)" for c, n in top_all]
    
    return results


def unlock_bitlocker(dev_path, recovery_key):
    """Attempt to unlock a BitLocker volume with the given recovery key."""
    # Clean the key
    clean_key = re.sub(r'[^0-9A-Fa-f]', '', recovery_key)
    
    os.makedirs(BITLOCKER_DIR, exist_ok=True)
    
    # First unmount if anything is there
    run_cmd(["umount", WINDOWS_MOUNT])
    run_cmd(["umount", BITLOCKER_DIR])
    
    # Run dislocker
    rc, out, err = run_cmd(["dislocker", "-V", dev_path, "-p", clean_key, "-r", "--", BITLOCKER_DIR], timeout=60)
    
    if rc != 0:
        return False, f"dislocker failed (rc={rc}): {err[:200] if err else out[:200]}"
    
    # Check if the dislocker file was created
    dislocker_file = f"{BITLOCKER_DIR}/dislocker-file"
    if not os.path.exists(dislocker_file):
        return False, "dislocker ran but no dislocker-file created — key may be wrong"
    
    # Mount the decrypted volume
    os.makedirs(WINDOWS_MOUNT, exist_ok=True)
    rc2, out2, err2 = run_cmd(["mount", "-o", "loop,ro", dislocker_file, WINDOWS_MOUNT], timeout=30)
    
    if rc2 != 0:
        return False, f"Decrypted but mount failed: {err2[:200]}"
    
    return True, "BitLocker unlocked and volume mounted successfully!"


# ============================================================
#  ERROR CODE DECODER
# ============================================================

ERROR_CODE_DECODER = {
    "0x80070002": "File not found — corrupt update cache or missing system file",
    "0x80070005": "Access denied — permissions issue, try running as SYSTEM",
    "0x80070020": "File in use — another process holds a lock",
    "0x80070422": "Windows Update service not running or disabled",
    "0x80070643": "Windows corruption — run DISM /RestoreHealth",
    "0x80073701": "Component store corrupt — run DISM /RestoreHealth",
    "0x800f081f": "CBS corrupt — run SFC + DISM",
    "0x800f0906": "DISM source files not available — use /Source with install.wim",
    "0x8024401c": "WU cannot connect — check firewall/proxy/WSUS",
    "0x80246008": "BITS service issue — restart BITS service",
    "0x80248007": "WU database corrupt — reset SoftwareDistribution",
    "0x8024efff": "Windows Update generic failure — reset WU components",
    "0x80d02002": "WSUS server unavailable — check connectivity to WSUS server",
    "0xc1900101": "Feature update rollback — usually a driver incompatibility",
    "0xc1900200": "Not enough free disk space for update",
    "0xc190020e": "Incompatible driver blocked the update",
    "0x800f0922": "DISM failed — component store corruption, check CBS.log",
    "0x800f0954": "DISM can't find source — specify /Source with correct path",
    "0x8024200b": "WU download failed — corrupt update file, reset SoftwareDistribution",
    "0x800b0100": "Certificate validation failure — corrupt trust store, run DISM",
}

BSOD_CODE_DECODER = {
    "0x00000001": "APC_INDEX_MISMATCH — usually a bad driver or file system filter",
    "0x0000000a": "IRQL_NOT_LESS_OR_EQUAL — faulty driver (graphics, network, storage most common)",
    "0x0000001e": "KMODE_EXCEPTION_NOT_HANDLED — bad driver or incompatible software",
    "0x00000024": "NTFS_FILE_SYSTEM — disk corruption or failing drive",
    "0x0000002e": "DATA_BUS_ERROR — hardware failure (RAM or motherboard)",
    "0x0000003b": "SYSTEM_SERVICE_EXCEPTION — bad driver, especially graphics",
    "0x00000044": "MULTIPLE_IRP_COMPLETE_REQUESTS — driver bug",
    "0x0000004e": "PFN_LIST_CORRUPT — RAM corruption or bad driver",
    "0x00000050": "PAGE_FAULT_IN_NONPAGED_AREA — faulty hardware or driver",
    "0x0000007a": "KERNEL_DATA_INPAGE_ERROR — disk failure or RAM issue",
    "0x0000007b": "INACCESSIBLE_BOOT_DEVICE — drive controller or boot config issue",
    "0x0000007e": "SYSTEM_THREAD_EXCEPTION_NOT_HANDLED — driver crash",
    "0x0000008e": "KERNEL_MODE_EXCEPTION_NOT_HANDLED — driver failure",
    "0x0000009f": "DRIVER_POWER_STATE_FAILURE — power management driver bug",
    "0x000000c4": "DRIVER_VERIFIER_DETECTED_VIOLATION — run Driver Verifier to find culprit",
    "0x000000c5": "DRIVER_CORRUPTED_EXPOOL — driver corrupted memory pool",
    "0x000000d1": "DRIVER_IRQL_NOT_LESS_OR_EQUAL — network or storage driver most likely",
    "0x000000d5": "DRIVER_PAGE_FAULT_IN_FREED_SPECIAL_POOL — driver accessing freed memory",
    "0x000000dc": "DRIVER_FAULT_IN_NONPAGED_AREA — driver causes page fault",
    "0x000000e3": "RESOURCE_NOT_OWNED — file system filter driver bug",
    "0x000000f4": "CRITICAL_OBJECT_TERMINATION — disk failure or rootkit",
    "0x00000101": "CLOCK_WATCHDOG_TIMEOUT — CPU core stuck, overclocking or thermal issue",
    "0x00000109": "CRITICAL_STRUCTURE_CORRUPTION — kernel modified, possible rootkit or hardware",
    "0x00000113": "VIDEO_DXGKRNL_FATAL_ERROR — graphics driver crash (NVIDIA/AMD/Intel)",
    "0x00000116": "VIDEO_TDR_FAILURE — graphics driver timeout and recovery failed",
    "0x00000124": "MACHINE_CHECK_EXCEPTION — hardware failure (CPU, cache, memory, GPU)",
    "0x00000133": "DPC_WATCHDOG_VIOLATION — storage driver (NVMe, SATA) not responding",
    "0x00000139": "KERNEL_SECURITY_CHECK_FAILURE — driver corruption or hardware",
    "0x00000141": "VIDEO_ENGINE_TIMEOUT_DETECTED — GPU not responding (TDR)",
    "0x0000019a": "CRITICAL_PROCESS_DIED — system process crashed, possible disk corruption",
    "0x000001ca": "SYNTHETIC_WATCHDOG_TIMEOUT — Hyper-V or virtualized environment issue",
}

# ============================================================
#  HTTP REQUEST HANDLER
# ============================================================

class BLUnlockHandler(http.server.BaseHTTPRequestHandler):
    
    def log_message(self, format, *args):
        """Suppress default logging to stderr, use our own."""
        msg = format % args
        print(f"  [WEB] {self.client_address[0]} - {msg}")
    
    def send_html(self, content, code=200, extra_headers=None):
        """Send an HTML response."""
        body = content.encode('utf-8')
        self.send_response(code)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        if extra_headers:
            for k, v in extra_headers.items():
                self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)
    
    def send_json(self, data, code=200):
        """Send a JSON response."""
        body = json.dumps(data).encode('utf-8')
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    
    def get_page_html(self):
        """Build the main portal page."""
        s = g_state
        
        # Status badge
        if s["unlock_status"] == "success":
            status_badge = '<div class="badge badge-success">✅ Unlocked</div>'
        elif s["unlock_status"] == "failed":
            status_badge = f'<div class="badge badge-fail">❌ Failed</div>'
        elif s["unlock_status"] == "unlocking":
            status_badge = '<div class="badge badge-warn">⏳ Unlocking...</div>'
        else:
            status_badge = '<div class="badge badge-idle">⏸ Locked</div>'
        
        # Unlock message
        unlock_msg = ""
        if s["unlock_message"]:
            if s["unlock_status"] == "success":
                unlock_msg = f'<div class="msg-success">{html.escape(s["unlock_message"])}</div>'
            elif s["unlock_status"] == "failed":
                unlock_msg = f'<div class="msg-error">{html.escape(s["unlock_message"])}</div>'
        
        # Disk info cards
        disk_cards = ""
        for i, dev in enumerate(s["blk_devs"]):
            disk_cards += f'''
            <div class="disk-card">
                <div class="disk-icon">💾</div>
                <div class="disk-details">
                    <strong>{html.escape(dev.get("model", "Unknown"))}</strong><br>
                    <span class="dim">Device:</span> {dev["device"]}<br>
                    <span class="dim">Size:</span> {dev.get("size", "Unknown")}<br>
                    <span class="dim">Serial:</span> {html.escape(dev.get("serial", "Unknown"))}
                </div>
            </div>'''
        
        if not disk_cards:
            disk_cards = '<div class="disk-card"><div class="disk-details dim">No BitLocker volumes detected. Start the server after connecting the target drive.</div></div>'
        
        # Machine info
        machine_info = f'''
        <div class="info-grid">
            <div class="info-item"><span class="info-label">Hostname</span><span class="info-value">{html.escape(s["hostname"])}</span></div>
            <div class="info-item"><span class="info-label">Windows Computer</span><span class="info-value">{html.escape(s["computer_name"])}</span></div>
            <div class="info-item"><span class="info-label">Windows Version</span><span class="info-value">{html.escape(s["windows_version"])}</span></div>
            <div class="info-item"><span class="info-label">Server IP</span><span class="info-value">{s["lan_ip"]}:{PORT}</span></div>
        </div>'''
        
        # Diagnostics section (shown after unlock)
        diag_html = ""
        if s["unlock_status"] == "success" and s["has_run_diag"]:
            diag = s["diagnostics"]
            diag_sections = ""
            
            # BSOD section
            if "minidumps" in diag and diag["minidumps"]:
                dmp_lines = ""
                for dmp in diag["minidumps"]:
                    bug_str = ""
                    if dmp.get("bugchecks"):
                        for bc in dmp["bugchecks"][:5]:
                            decoded = BSOD_CODE_DECODER.get(bc.split()[0].upper(), "")
                            bug_str += f'<li><code>{html.escape(bc)}</code>'
                            if decoded:
                                bug_str += f'<br><span class="decoder">{html.escape(decoded)}</span>'
                            bug_str += '</li>'
                    dmp_lines += f'''
                    <div class="dmp-entry">
                        <strong>{html.escape(dmp["name"])}</strong> — {dmp["date"]} ({dmp["size"]//1024} KB)
                        <ul>{bug_str}</ul>
                    </div>'''
                
                diag_sections += f'''
                <div class="diag-section">
                    <h3>🔴 BSOD Crash Dumps ({len(diag["minidumps"])} found)</h3>
                    {dmp_lines}
                </div>'''
            
            # MEMORY.DMP
            if "memory_dump" in diag:
                md = diag["memory_dump"]
                bug_str = ""
                if md.get("bugchecks"):
                    for bc in md["bugchecks"][:10]:
                        decoded = BSOD_CODE_DECODER.get(bc.split()[0].upper(), "")
                        bug_str += f'<li><code>{html.escape(bc)}</code>'
                        if decoded:
                            bug_str += f'<br><span class="decoder">{html.escape(decoded)}</span>'
                        bug_str += '</li>'
                diag_sections += f'''
                <div class="diag-section">
                    <h3>🔴 Full Memory Dump ({md["size"]//1024//1024} MB — {md["date"]})</h3>
                    <ul>{bug_str}</ul>
                </div>'''
            
            # CBS errors
            if "cbs" in diag:
                cbs = diag["cbs"]
                codes_html = ""
                for c in cbs.get("top_error_codes", []):
                    code_only = c.split()[0] if c else ""
                    decoded = ERROR_CODE_DECODER.get(code_only.upper(), "")
                    codes_html += f'<li><code>{html.escape(c)}</code>'
                    if decoded:
                        codes_html += f'<br><span class="decoder">{html.escape(decoded)}</span>'
                    codes_html += '</li>'
                diag_sections += f'''
                <div class="diag-section">
                    <h3>🟡 Windows Update (CBS): {cbs["errors"]} errors, {cbs["failures"]} failures</h3>
                    <h4>Top error codes:</h4>
                    <ul>{codes_html}</ul>
                </div>'''
            
            # Windows Update events
            if "windows_update" in diag and diag["windows_update"].get("errors"):
                wu_errors = diag["windows_update"]["errors"]
                err_lines = ""
                for e in wu_errors[:10]:
                    err_lines += f'<li>{html.escape(e[:150])}</li>'
                diag_sections += f'''
                <div class="diag-section">
                    <h3>🟡 Windows Update Events ({len(wu_errors)} errors)</h3>
                    <ul>{err_lines}</ul>
                </div>'''
            
            # Pending reboot
            if diag.get("pending_reboot"):
                diag_sections += '''
                <div class="diag-section">
                    <h3>🟡 Pending Reboot Required</h3>
                    <p>Updates are staged but a reboot is needed to complete installation.</p>
                </div>'''
            
            # Top error codes all sources
            if diag.get("top_error_codes_all"):
                codes_html = ""
                for c in diag["top_error_codes_all"][:10]:
                    code_only = c.split()[0] if c else ""
                    decoded = ERROR_CODE_DECODER.get(code_only.upper(), "")
                    codes_html += f'<li><code>{html.escape(c)}</code>'
                    if decoded:
                        codes_html += f'<br><span class="decoder">{html.escape(decoded)}</span>'
                    codes_html += '</li>'
                diag_sections += f'''
                <div class="diag-section">
                    <h3>📊 Most Frequent Error Codes (all sources)</h3>
                    <ul>{codes_html}</ul>
                </div>'''
            
            # Problematic drivers
            if diag.get("problematic_drivers_present"):
                drv_html = ""
                for d in diag["problematic_drivers_present"]:
                    drv_html += f'<li><code>{html.escape(d)}</code></li>'
                diag_sections += f'''
                <div class="diag-section">
                    <h3>⚠ Known Problematic Drivers Found</h3>
                    <ul>{drv_html}</ul>
                </div>'''
            
            if diag_sections:
                diag_html = f'''
                <div class="card diagnostics">
                    <h2>🔍 Deep System Insights</h2>
                    {diag_sections}
                </div>'''
            else:
                diag_html = '''
                <div class="card diagnostics">
                    <h2>🔍 Deep System Insights</h2>
                    <p class="dim">No significant issues detected. System appears healthy.</p>
                </div>'''
        
        # Build recovery key form (only if not yet unlocked)
        key_form = ""
        if s["unlock_status"] != "success":
            dev_options = ""
            for i, dev in enumerate(s["blk_devs"]):
                selected = " selected" if i == 0 else ""
                dev_options += f'<option value="{dev["device"]}"{selected}>{dev["device"]} — {html.escape(dev.get("model", ""))}</option>'
            if not dev_options:
                dev_options = '<option value="">No BitLocker devices detected</option>'
            
            key_form = f'''
            <div class="card unlock-form">
                <h2>🔐 Unlock BitLocker Drive</h2>
                {unlock_msg}
                <form id="unlockForm" method="POST" action="/unlock">
                    <div class="form-group">
                        <label for="device">Target Drive:</label>
                        <select name="device" id="device">{dev_options}</select>
                    </div>
                    <div class="form-group">
                        <label for="key">48-digit Recovery Key:</label>
                        <input type="text" name="key" id="key" placeholder="XXXXXX-XXXXXX-XXXXXX-XXXXXX-XXXXXX-XXXXXX-XXXXXX-XXXXXX" autocomplete="off" spellcheck="false" style="font-family:monospace;font-size:16px;width:100%;padding:12px;box-sizing:border-box">
                        <div class="key-hint">Paste the full 48-digit key (with or without dashes)</div>
                    </div>
                    <button type="submit" class="btn-unlock">🔓 Unlock Drive</button>
                </form>
                <div id="status"></div>
            </div>'''
        else:
            key_form = f'''
            <div class="card unlock-form">
                <h2>🔓 Drive Unlocked</h2>
                {unlock_msg}
                <div class="button-row">
                    <a href="/diagnostics" class="btn-diag">🔍 Run/Refresh Diagnostics</a>
                    <a href="/reset" class="btn-reset">🔄 Reset & Lock</a>
                </div>
            </div>'''
        
        # Assemble full page
        html_content = f'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{HTML_TITLE}</title>
<style>
* {{ margin: 0; padding: 0; box-sizing: border-box; }}
body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #0d1117; color: #c9d1d9; padding: 20px; }}
.container {{ max-width: 900px; margin: 0 auto; }}
h1 {{ font-size: 1.6em; margin-bottom: 5px; color: #58a6ff; }}
h2 {{ font-size: 1.2em; margin-bottom: 15px; color: #c9d1d9; }}
h3 {{ font-size: 1em; color: #f0883e; margin: 15px 0 8px; }}
h4 {{ font-size: 0.9em; color: #8b949e; margin: 10px 0 5px; }}
.subtitle {{ color: #8b949e; font-size: 0.9em; margin-bottom: 20px; }}
.card {{ background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 20px; margin-bottom: 16px; }}
.header {{ display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; }}
.badge {{ padding: 4px 12px; border-radius: 12px; font-size: 0.85em; font-weight: bold; }}
.badge-success {{ background: #1b3a2d; color: #3fb950; border: 1px solid #3fb950; }}
.badge-fail {{ background: #3d1c1c; color: #f85149; border: 1px solid #f85149; }}
.badge-warn {{ background: #3d2e1c; color: #d29922; border: 1px solid #d29922; }}
.badge-idle {{ background: #1c2128; color: #8b949e; border: 1px solid #30363d; }}
.info-grid {{ display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }}
.info-item {{ padding: 8px 12px; background: #0d1117; border-radius: 6px; }}
.info-label {{ display: block; font-size: 0.75em; color: #8b949e; text-transform: uppercase; }}
.info-value {{ font-size: 0.95em; color: #c9d1d9; }}
.dim {{ color: #8b949e; }}
.disk-card {{ display: flex; align-items: center; gap: 12px; padding: 10px; background: #0d1117; border-radius: 6px; margin-bottom: 8px; }}
.disk-icon {{ font-size: 1.5em; }}
.disk-details {{ font-size: 0.9em; line-height: 1.5; }}
.form-group {{ margin-bottom: 15px; }}
.form-group label {{ display: block; margin-bottom: 5px; font-weight: bold; color: #c9d1d9; }}
.form-group select {{ width: 100%; padding: 10px; background: #0d1117; border: 1px solid #30363d; border-radius: 6px; color: #c9d1d9; font-size: 14px; }}
.key-hint {{ font-size: 0.8em; color: #8b949e; margin-top: 4px; }}
.btn-unlock {{ background: #238636; color: white; border: none; padding: 12px 24px; border-radius: 6px; font-size: 16px; font-weight: bold; cursor: pointer; width: 100%; }}
.btn-unlock:hover {{ background: #2ea043; }}
.btn-unlock:disabled {{ background: #1b3a2d; color: #8b949e; cursor: not-allowed; }}
.btn-diag {{ display: inline-block; background: #1f6feb; color: white; padding: 10px 20px; border-radius: 6px; text-decoration: none; margin-right: 8px; }}
.btn-reset {{ display: inline-block; background: #30363d; color: #c9d1d9; padding: 10px 20px; border-radius: 6px; text-decoration: none; }}
.button-row {{ margin-top: 10px; }}
.msg-success {{ background: #1b3a2d; border: 1px solid #3fb950; color: #7ee787; padding: 12px; border-radius: 6px; margin-bottom: 12px; }}
.msg-error {{ background: #3d1c1c; border: 1px solid #f85149; color: #f85149; padding: 12px; border-radius: 6px; margin-bottom: 12px; }}
.diag-section {{ background: #0d1117; border-radius: 6px; padding: 12px; margin-bottom: 12px; }}
.diag-section ul {{ margin: 8px 0 0 20px; line-height: 1.7; }}
.diag-section li {{ margin-bottom: 6px; }}
.diag-section code {{ background: #1c2128; padding: 2px 6px; border-radius: 3px; font-size: 0.85em; }}
.dmp-entry {{ background: #1c2128; padding: 10px; border-radius: 4px; margin-bottom: 8px; }}
.decoder {{ color: #58a6ff; font-size: 0.85em; }}
.spinner {{ display: none; text-align: center; padding: 20px; }}
.spinner.active {{ display: block; }}
@media (max-width: 600px) {{ .info-grid {{ grid-template-columns: 1fr; }} }}
</style>
</head>
<body>
<div class="container">
    <div class="card header">
        <div>
            <h1>🩺 SysMedic BitLocker Portal</h1>
            <div class="subtitle">Bootable USB recovery environment — LAN access only</div>
        </div>
        {status_badge}
    </div>
    
    <div class="card">
        <h2>💻 Machine Information</h2>
        {machine_info}
    </div>
    
    <div class="card">
        <h2>💾 Encrypted Drives</h2>
        {disk_cards}
    </div>
    
    {key_form}
    
    {diag_html}
    
    <div class="card" style="text-align:center;font-size:0.8em;color:#8b949e;">
        SysMedic Recovery System — <a href="http://{s["lan_ip"]}:{PORT}" style="color:#58a6ff;">http://{s["lan_ip"]}:{PORT}</a>
    </div>
</div>
<script>
document.getElementById('unlockForm')?.addEventListener('submit', function(e) {{
    e.preventDefault();
    var btn = this.querySelector('.btn-unlock');
    var status = document.getElementById('status');
    btn.disabled = true;
    btn.textContent = '⏳ Unlocking...';
    status.innerHTML = '<div class="spinner active">⏳ Unlocking drive... This may take up to 30 seconds.</div>';
    
    var formData = new FormData(this);
    fetch('/unlock', {{ method: 'POST', body: formData }})
        .then(r => r.json())
        .then(data => {{
            if (data.success) {{
                status.innerHTML = '<div class="msg-success">' + data.message + '</div>';
                setTimeout(function() {{ location.reload(); }}, 1500);
            }} else {{
                status.innerHTML = '<div class="msg-error">' + data.message + '</div>';
                btn.disabled = false;
                btn.textContent = '🔓 Try Again';
            }}
        }})
        .catch(err => {{
            status.innerHTML = '<div class="msg-error">Network error: ' + err + '</div>';
            btn.disabled = false;
            btn.textContent = '🔓 Unlock Drive';
        }});
}});
</script>
</body>
</html>'''
        return html_content
    
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        
        if path == '/' or path == '/index.html':
            self.send_html(self.get_page_html())
        elif path == '/diagnostics':
            # Re-run diagnostics
            g_state["has_run_diag"] = False
            if os.path.ismount(WINDOWS_MOUNT):
                def run_diag():
                    g_state["diagnostics"] = read_diagnostics()
                    g_state["has_run_diag"] = True
                threading.Thread(target=run_diag, daemon=True).start()
                self.send_html("<!DOCTYPE html><html><body><h1>Diagnostics running...</h1><p>Please wait, then <a href='/'>go back</a>.</p><script>setTimeout(function(){location.href='/';},3000);</script></body></html>")
            else:
                self.send_html("<!DOCTYPE html><html><body><h1>Drive not mounted</h1><p>Unlock the drive first.</p><a href='/'>Back</a></body></html>")
        elif path == '/reset':
            # Lock everything
            run_cmd(["umount", WINDOWS_MOUNT])
            run_cmd(["umount", BITLOCKER_DIR])
            g_state["unlock_status"] = "none"
            g_state["unlock_message"] = ""
            g_state["diagnostics"] = {}
            g_state["has_run_diag"] = False
            self.send_html("<!DOCTYPE html><html><body><h1>🔒 Drive locked</h1><p>Volume has been unmounted and locked.</p><script>setTimeout(function(){location.href='/';},1500);</script></body></html>")
        elif path == '/status':
            self.send_json({
                "status": g_state["unlock_status"],
                "message": g_state["unlock_message"],
                "mounted": os.path.ismount(WINDOWS_MOUNT),
                "has_diag": g_state["has_run_diag"],
            })
        else:
            self.send_html(f"<h1>404</h1><p>Not found: {html.escape(path)}</p>", code=404)
    
    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        
        if path == '/unlock':
            content_len = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_len).decode('utf-8')
            params = urllib.parse.parse_qs(body)
            
            device = params.get('device', [''])[0]
            key = params.get('key', [''])[0]
            
            if not device or not key:
                self.send_json({"success": False, "message": "Missing device or recovery key"}, 400)
                return
            
            if not os.path.exists(device):
                self.send_json({"success": False, "message": f"Device {device} not found"}, 404)
                return
            
            g_state["unlock_status"] = "unlocking"
            g_state["unlock_message"] = "Unlocking..."
            
            def do_unlock():
                success, msg = unlock_bitlocker(device, key)
                g_state["unlock_status"] = "success" if success else "failed"
                g_state["unlock_message"] = msg
                
                if success:
                    # Read Windows info
                    try_read_windows_info()
                    # Run diagnostics in background
                    def bg_diag():
                        g_state["diagnostics"] = read_diagnostics()
                        g_state["has_run_diag"] = True
                    threading.Thread(target=bg_diag, daemon=True).start()
            
            # Run unlock in background thread, return immediately
            threading.Thread(target=do_unlock, daemon=True).start()
            time.sleep(2)  # brief wait to get initial result
            
            # Return current status
            self.send_json({
                "success": g_state["unlock_status"] == "success",
                "message": g_state["unlock_message"],
            })
        else:
            self.send_json({"error": "not found"}, 404)


# ============================================================
#  MAIN
# ============================================================

def main():
    print()
    print("=" * 60)
    print("  🩺 SysMedic — BitLocker Web Unlock Portal")
    print("=" * 60)
    print()
    
    # Detect LAN IP
    g_state["lan_ip"] = get_lan_ip()
    print(f"  🌐 LAN IP: {g_state['lan_ip']}")
    print()
    
    # Detect BitLocker volumes
    print("  🔍 Scanning for BitLocker volumes...")
    volumes = detect_bitlocker_volumes()
    
    if volumes:
        print(f"  ✅ Found {len(volumes)} BitLocker volume(s):")
        for v in volumes:
            disk_info = get_disk_info(v["device"])
            v.update(disk_info)
            g_state["disk_info"].append(disk_info)
            print(f"     • {v['device']}  ({v.get('model', 'Unknown')} / S/N: {v.get('serial', 'Unknown')})")
    else:
        print("  ⚠  No BitLocker volumes detected yet.")
        print("     Connect the target drive and restart this server.")
    print()
    
    # Try to read Windows info (if already mounted somehow)
    if os.path.ismount(WINDOWS_MOUNT) and os.path.exists(f"{WINDOWS_MOUNT}/Windows"):
        try_read_windows_info()
        print(f"  💻 Windows: {g_state['computer_name']} — {g_state['windows_version']}")
    else:
        print("  💻 Windows info will appear after unlock.")
    print()
    
    g_state["blk_devs"] = volumes
    
    # Start server — bind to LAN IP for security (not 0.0.0.0)
    server = http.server.HTTPServer((g_state["lan_ip"], PORT), BLUnlockHandler)
    
    print(f"  🚀 Server running at:")
    print(f"")
    print(f"      http://{g_state['lan_ip']}:{PORT}")
    print(f"      http://localhost:{PORT}")
    print(f"")
    print(f"  📱 Open this URL on your phone or laptop to paste the")
    print(f"     BitLocker recovery key and unlock the drive.")
    print(f"")
    print(f"  ⚠  This server is accessible to ANYONE on the local network.")
    print(f"     Keep your network secure.")
    print(f"")
    print(f"  Press Ctrl+C to stop the server.")
    print()
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print()
        print("  Shutting down...")
        server.shutdown()
        print("  Done.")
    
    # Cleanup on exit
    run_cmd(["umount", WINDOWS_MOUNT])
    run_cmd(["umount", BITLOCKER_DIR])
    print("  Cleaned up mounts.")


if __name__ == "__main__":
    main()
