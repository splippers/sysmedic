#!/bin/bash
# Build a fake-but-realistic Windows system tree at $1 from tests/fixtures (run as root)
set -e
W=$1; F=$(dirname "$0")/fixtures
mkdir -p "$W"/Windows/System32/{config,winevt/Logs,Recovery,Tasks/Updates} "$W"/Windows/{Minidump,WinSxS,Temp} \
         "$W"/Users/alice/AppData/Roaming/upd "$W"/Users/alice/Downloads "$W"/Users/bob "$W"/ProgramData/SysHelper
cp "$F"/SOFTWARE "$F"/SYSTEM "$W"/Windows/System32/config/
cp "$F"/system.evtx "$W"/Windows/System32/winevt/Logs/System.evtx
cp "$F"/security.evtx "$W"/Windows/System32/winevt/Logs/Security.evtx
dump() { python3 - "$1" "$2" <<'PY'
import struct, sys
code = int(sys.argv[2], 16)
hdr = b"PAGEDU64" + b"\0" * (0x38 - 8) + struct.pack("<I", code) + b"\0" * 4 + struct.pack("<4Q", 0, 0xfffff80123456789, 0xb2000000, 0x10005)
open(sys.argv[1], "wb").write(hdr + b"\0" * 4000)
PY
}
dump "$W/Windows/Minidump/092826-11234-01.dmp" 124; dump "$W/Windows/Minidump/092926-10187-01.dmp" 124; dump "$W/Windows/Minidump/093026-12000-01.dmp" 7E
touch -d '2026-09-28 10:12' "$W/Windows/Minidump/092826-11234-01.dmp"; touch -d '2026-09-29 16:40' "$W/Windows/Minidump/092926-10187-01.dmp"; touch -d '2026-09-30 09:05' "$W/Windows/Minidump/093026-12000-01.dmp"
echo '<?xml version="1.0"?><pending/>' > "$W/Windows/WinSxS/pending.xml"
printf 'HIBR' > "$W/hiberfil.sys"
echo '<WindowsRE version="2.0"><WinreBCD id="{a1b2}"/><WinreLocation path="\Recovery\WindowsRE" id="0" offset="1048576"/></WindowsRE>' > "$W/Windows/System32/Recovery/ReAgent.xml"
# EICAR antivirus test string (harmless, detected by every scanner) disguised as svchost.exe in AppData
printf 'X5O!P%%@AP[4\\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*' > "$W/Users/alice/AppData/Roaming/upd/svchost.exe"
echo fake > "$W/ProgramData/SysHelper/helper.exe"; cp "$F"/NTUSER.DAT "$W/Users/alice/NTUSER.DAT"
mkdir -p "$W"/Windows/System32/drivers/etc "$W"/Windows/System32/drivers "$W"/Windows/Logs/CBS "$W"/Windows/Logs/DISM \
         "$W"/Windows/SoftwareDistribution "$W"/Windows/Panther
touch "$W"/Windows/System32/drivers/kbdclass.sys
printf '127.0.0.1 localhost\n0.0.0.0 download.windowsupdate.com\n0.0.0.0 update.microsoft.com\n' > "$W/Windows/System32/drivers/etc/hosts"
# Servicing logs with planted problems: store corruption SFC can't fix, a cumulative update failing with
# 0x800f0831, DISM without a repair source, Windows Update failures, and a rolled-back feature update
D=$(date -d '5 days ago' +%Y-%m-%d)
cat > "$W/Windows/Logs/CBS/CBS.log" <<CBS
$D 09:12:01, Info                  CBS    TrustedInstaller service starts successfully.
$D 09:12:40, Info                  CBS    Exec: Processing started.  Session: 31146322_2207785418, Package: Package_for_RollupFix~31bf3856ad364e35~amd64~~26100.4061.1.12
$D 09:14:03, Error                 CBS    Failed to resolve package 'Package_for_RollupFix~31bf3856ad364e35~amd64~~26100.3915.1.7' [HRESULT = 0x800f0831 - CBS_E_STORE_CORRUPTION]
$D 09:14:03, Error                 CBS    Failed to execute execution chain. [HRESULT = 0x800f0831 - CBS_E_STORE_CORRUPTION]
$D 09:14:04, Info                  CBS    Exec: Processing complete.  Session: 31146322_2207785418, Package: Package_for_RollupFix~31bf3856ad364e35~amd64~~26100.4061.1.12, hr: 0x800f0831
$D 10:02:11, Info                  CSI    00000012 [SR] Beginning Verify and Repair transaction
$D 10:05:47, Info                  CSI    00000245 Hashes for file member [l:12]"ntoskrnl.exe" do not match.
$D 10:05:47, Info                  CSI    00000246 [SR] Cannot repair member file [l:12]"ntoskrnl.exe" of Microsoft-Windows-OS-Kernel, version 10.0.26100.3915
$D 10:05:48, Info                  CSI    00000247 [SR] Repairing corrupted file \??\C:\Windows\System32\\drivers\netio.sys from store
$D 10:07:02, Info                  CSI    00000301 [SR] Verify complete
$D 10:07:05, Info                  CBS    Total Detected Corruption:	2, CBS Corrupt: 0, CSI Corrupt: 2
$D 10:07:05, Info                  CBS    Total Repaired Corruption:	1
CBS
cat > "$W/Windows/Logs/DISM/dism.log" <<DISM
$D 10:20:15, Info                  DISM   DISM.EXE: Executing command line: dism /online /cleanup-image /restorehealth
$D 10:31:40, Error                 DISM   DISM Package Manager: PID=4412 TID=4416 Failed processing package changes with session options - CDISMPackageManager::ProcessChangesWithOptions(hr:0x800f081f)
$D 10:31:40, Error                 DISM   DISM.EXE: Image session has been closed. Reboot required=no. hr:0x800f081f
DISM
python3 - "$W/Windows/SoftwareDistribution/ReportingEvents.log" "$D" <<'PY'
import sys
d = sys.argv[2]
rows = [f"{{8F1D2C3B-1111-4A4A-9C9C-000000000001}}\t{d} 03:10:11:101+0100\t1\t182 [AGENT_INSTALLING_FAILED]\t101\t{{0}}\t200\t800f0831\tAutomaticUpdates\tFailure\tContent Install\tInstallation Failure: Windows failed to install the following update with error 0x800f0831: 2026-09 Cumulative Update for Windows 11 Version 24H2 for x64-based Systems (KB5065426).",
        f"{{8F1D2C3B-1111-4A4A-9C9C-000000000002}}\t{d} 21:40:02:550+0100\t1\t182 [AGENT_INSTALLING_FAILED]\t101\t{{0}}\t200\t800f0831\tAutomaticUpdates\tFailure\tContent Install\tInstallation Failure: Windows failed to install the following update with error 0x800f0831: 2026-09 Cumulative Update for Windows 11 Version 24H2 for x64-based Systems (KB5065426).",
        f"{{8F1D2C3B-1111-4A4A-9C9C-000000000003}}\t{d} 21:45:30:010+0100\t1\t183 [AGENT_INSTALLING_SUCCEEDED]\t101\t{{0}}\t200\t0\tAutomaticUpdates\tSuccess\tContent Install\tInstallation Successful: Windows successfully installed the following update: Security Intelligence Update for Microsoft Defender Antivirus - KB2267602 (Version 1.437.120.0)."]
open(sys.argv[1], "w", encoding="utf-16").write("\r\n".join(rows) + "\r\n")
PY
cat > "$W/Windows/Panther/setuperr.log" <<PAN
$D 02:14:11, Error                 SP     Operation failed: Add [1] Driver Package: oem42.inf. Error: 0x80070002
$D 02:31:58, Error                 MOUPG  CSetupManager::Execute(222): Result = 0xC1900101
PAN
printf '<?xml version="1.0"?><Task><Actions><Exec><Command>powershell.exe</Command><Arguments>-w hidden -enc SQBFAFgAIAAoAE4AZQB3AC0ATwBiAGoA</Arguments></Exec></Actions></Task>' > "$W/Windows/System32/Tasks/Updates/ChromeUpdateCheck"
