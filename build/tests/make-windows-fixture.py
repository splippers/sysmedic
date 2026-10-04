#!/usr/bin/env python3
"""Build realistic Windows registry hives for testing sysmedic-win.

Starts from hivex's minimal hive (a genuine, empty NT registry file) and adds
the keys sysmedic-win reads, with planted problems:
  SOFTWARE  Windows 11 Pro 24H2; a Run-key autostart of "svchost.exe" from AppData
            (classic malware masquerade); two user profiles
  SYSTEM    Fast Startup on; a pending file rename; a service whose binary
            lives in ProgramData; computer name; last shutdown time;
            for sysmedic-win registry: a service whose program is missing (KDService),
            Windows Update disabled, a keyboard filter driver that isn't installed,
            crash dumps off
  SOFTWARE  (also) sethc.exe hijacked, Defender off by policy with an AppData
            exclusion, an app installed recently
  NTUSER    (alice) a web proxy
Usage (inside the image chroot, which has python3-hivex):
  make-windows-fixture.py MINIMAL_HIVE OUTDIR
"""
import shutil
import struct
import sys

import hivex

REG_SZ, REG_EXPAND_SZ, REG_BINARY, REG_DWORD, REG_MULTI_SZ = 1, 2, 3, 4, 7


def sz(s):
    return (s + "\0").encode("utf-16-le")


def multi(*items):
    return ("\0".join(items) + "\0\0").encode("utf-16-le")


def path(h, keypath):
    node = h.root()
    for part in keypath.split("\\"):
        child = h.node_get_child(node, part)
        node = child if child else h.node_add_child(node, part)
    return node


def setv(h, keypath, name, typ, value):
    node = path(h, keypath)
    existing = [{"key": h.value_key(v), "t": h.value_type(v)[0], "value": h.value_value(v)[1]}
                for v in h.node_values(node) if h.value_key(v) != name]
    h.node_set_values(node, existing + [{"key": name, "t": typ, "value": value}])


def build(minimal, out, fill):
    shutil.copy(minimal, out)
    h = hivex.Hivex(out, write=True)
    fill(h)
    h.commit(out)


def software(h):
    cv = r"Microsoft\Windows NT\CurrentVersion"
    setv(h, cv, "ProductName", REG_SZ, sz("Windows 10 Pro"))       # Windows 11 really reports this
    setv(h, cv, "DisplayVersion", REG_SZ, sz("24H2"))
    setv(h, cv, "CurrentBuild", REG_SZ, sz("26100"))
    setv(h, cv, "EditionID", REG_SZ, sz("Professional"))
    setv(h, cv, "InstallDate", REG_DWORD, struct.pack("<I", 1735689600))   # 2025-01-01
    run = r"Microsoft\Windows\CurrentVersion\Run"
    setv(h, run, "SecurityHealth", REG_EXPAND_SZ, sz(r"%windir%\system32\SecurityHealthSystray.exe"))
    setv(h, run, "WindowsUpdater", REG_SZ, sz(r"C:\Users\alice\AppData\Roaming\upd\svchost.exe -silent"))
    pl = cv + r"\ProfileList"
    setv(h, pl + r"\S-1-5-18", "ProfileImagePath", REG_EXPAND_SZ, sz(r"%systemroot%\system32\config\systemprofile"))
    setv(h, pl + r"\S-1-5-21-1111111111-2222222222-3333333333-1001", "ProfileImagePath", REG_EXPAND_SZ, sz(r"C:\Users\alice"))
    setv(h, pl + r"\S-1-5-21-1111111111-2222222222-3333333333-1002", "ProfileImagePath", REG_EXPAND_SZ, sz(r"C:\Users\bob"))
    ifeo = r"Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
    setv(h, ifeo + r"\sethc.exe", "Debugger", REG_SZ, sz(r"C:\Windows\System32\cmd.exe"))
    setv(h, r"Policies\Microsoft\Windows Defender", "DisableAntiSpyware", REG_DWORD, struct.pack("<I", 1))
    setv(h, r"Policies\Microsoft\Windows Defender\Exclusions\Paths", "C:\\Users\\alice\\AppData\\", REG_DWORD, struct.pack("<I", 0))
    import datetime
    recent = (datetime.date.today() - datetime.timedelta(days=3)).strftime("%Y%m%d")
    un = r"Microsoft\Windows\CurrentVersion\Uninstall\{6F1C0A2E-5B7D-4E3A-9C1F-2D8B7A6E5F40}"
    setv(h, un, "DisplayName", REG_SZ, sz("PDF Converter Pro"))
    setv(h, un, "Publisher", REG_SZ, sz("FreeTools Ltd"))
    setv(h, un, "InstallDate", REG_SZ, sz(recent))


def system(h):
    setv(h, "Select", "Current", REG_DWORD, struct.pack("<I", 1))
    cs = "ControlSet001"
    setv(h, cs + r"\Control\ComputerName\ComputerName", "ComputerName", REG_SZ, sz("DESKTOP-SM7TEST"))
    # FILETIME for 2026-09-29 18:42 UTC
    ft = int((1790707320 + 11644473600) * 10_000_000)
    setv(h, cs + r"\Control\Windows", "ShutdownTime", REG_BINARY, struct.pack("<Q", ft))
    setv(h, cs + r"\Control\Session Manager\Power", "HiberbootEnabled", REG_DWORD, struct.pack("<I", 1))
    setv(h, cs + r"\Control\Session Manager", "PendingFileRenameOperations", REG_MULTI_SZ,
         multi(r"\??\C:\Windows\System32\drivers\netwtw10.sys", r"!\??\C:\Windows\System32\drivers\netwtw10.sys.new"))
    svc = cs + r"\Services"
    setv(h, svc + r"\Dnscache", "ImagePath", REG_EXPAND_SZ, sz(r"%SystemRoot%\system32\svchost.exe -k NetworkService"))
    setv(h, svc + r"\Dnscache", "Start", REG_DWORD, struct.pack("<I", 2))
    setv(h, svc + r"\WinSysHelper", "ImagePath", REG_EXPAND_SZ, sz(r"C:\ProgramData\SysHelper\helper.exe"))
    setv(h, svc + r"\WinSysHelper", "Start", REG_DWORD, struct.pack("<I", 2))
    setv(h, svc + r"\WinSysHelper", "DisplayName", REG_SZ, sz("Windows System Helper"))
    setv(h, svc + r"\KDService", "ImagePath", REG_EXPAND_SZ, sz('"C:\\Program Files\\KD\\KDService.exe"'))
    setv(h, svc + r"\KDService", "Start", REG_DWORD, struct.pack("<I", 2))
    setv(h, svc + r"\KDService", "Type", REG_DWORD, struct.pack("<I", 16))
    setv(h, svc + r"\wuauserv", "ImagePath", REG_EXPAND_SZ, sz(r"%systemroot%\system32\svchost.exe -k netsvcs -p"))
    setv(h, svc + r"\wuauserv", "Start", REG_DWORD, struct.pack("<I", 4))
    setv(h, svc + r"\kbdclass", "Start", REG_DWORD, struct.pack("<I", 1))
    setv(h, svc + r"\kbdclass", "Type", REG_DWORD, struct.pack("<I", 1))
    kbd = cs + r"\Control\Class\{4d36e96b-e325-11ce-bfc1-08002be10318}"
    setv(h, kbd, "Class", REG_SZ, sz("Keyboard"))
    setv(h, kbd, "UpperFilters", REG_MULTI_SZ, multi("kbdclass", "kbfiltr"))
    setv(h, cs + r"\Control\CrashControl", "CrashDumpEnabled", REG_DWORD, struct.pack("<I", 0))
    setv(h, cs + r"\Control\Session Manager", "BootExecute", REG_MULTI_SZ, multi("autocheck autochk *"))


def ntuser(h):
    inet = r"Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    setv(h, inet, "ProxyEnable", REG_DWORD, struct.pack("<I", 1))
    setv(h, inet, "ProxyServer", REG_SZ, sz("127.0.0.1:8888"))


if __name__ == "__main__":
    minimal, outdir = sys.argv[1], sys.argv[2]
    build(minimal, f"{outdir}/SOFTWARE", software)
    build(minimal, f"{outdir}/SYSTEM", system)
    build(minimal, f"{outdir}/NTUSER.DAT", ntuser)
    print("built SOFTWARE, SYSTEM and NTUSER.DAT in", outdir)
