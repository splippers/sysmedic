#!/bin/bash
# Build a fake-but-realistic Windows system tree at $1 from tests/fixtures (run as root)
set -e
W=$1; F=$(dirname "$0")/fixtures
mkdir -p "$W"/Windows/System32/{config,winevt/Logs,Recovery,Tasks/Updates} "$W"/Windows/{Minidump,WinSxS,Temp} \
         "$W"/Users/alice/AppData/Roaming/upd "$W"/Users/alice/Downloads "$W"/Users/bob "$W"/ProgramData/SysHelper
cp "$F"/SOFTWARE "$F"/SYSTEM "$W"/Windows/System32/config/
cp "$F"/system.evtx "$W"/Windows/System32/winevt/Logs/System.evtx
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
echo fake > "$W/ProgramData/SysHelper/helper.exe"; touch "$W/Users/alice/NTUSER.DAT"
printf '<?xml version="1.0"?><Task><Actions><Exec><Command>powershell.exe</Command><Arguments>-w hidden -enc SQBFAFgAIAAoAE4AZQB3AC0ATwBiAGoA</Arguments></Exec></Actions></Task>' > "$W/Windows/System32/Tasks/Updates/ChromeUpdateCheck"
