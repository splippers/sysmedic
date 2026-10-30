<#
.SYNOPSIS
  SysMedic evidence collector for a running Windows installation. Read-only. Offline. Not a repair tool.

.DESCRIPTION
  Gathers diagnostic evidence, bundles it with provenance into a portable snapshot (a zip), encrypts it with `age`
  to the public key of the SysMedic drive this script runs from, and writes only the encrypted file (plus a small
  plaintext envelope) to that drive's INBOX folder. Nothing is changed on this computer, nothing is sent anywhere,
  and the unencrypted evidence is held in memory only: it is never written to this computer's disk.

  It lists what it will gather and waits for you to type YES. -ListOnly shows the list and stops.
  It never collects documents, photos, browser data, passwords, Wi-Fi keys, BitLocker recovery keys or user folders.

  Format and design: docs/EXCHANGE.md in the SysMedic repository.

.PARAMETER ListOnly   Show what would be collected and exit.
.PARAMETER EventDays  How many days of System/Application errors to include (default 7).
#>
[CmdletBinding()]
param(
    [switch]$ListOnly,
    [ValidateRange(1, 90)][int]$EventDays = 7
)
$ErrorActionPreference = 'Stop'
$Script:Name = 'SysMedic-Collect'
$Script:Version = '0.1.0'
$Script:Format = 'sysmedic-snapshot/1'

# ---------------------------------------------------------------------------------------------------------------
# Where am I? The exchange drive is wherever this script lives: no drive letter is assumed.
# ---------------------------------------------------------------------------------------------------------------
$ExchangeRoot = Split-Path -Parent $PSScriptRoot
$IdFile = Join-Path $ExchangeRoot 'SYSMEDIC.ID'
if (-not (Test-Path -LiteralPath $IdFile)) {
    throw "SYSMEDIC.ID not found next to the collector folder ($ExchangeRoot). Run this from the SysMedic exchange drive."
}
$Id = @{}
Get-Content -LiteralPath $IdFile | ForEach-Object { if ($_ -match '^([a-z_]+)=(.*)$') { $Id[$Matches[1]] = $Matches[2].Trim() } }
if ($Id['format'] -ne 'sysmedic-exchange/1') { throw "Unknown exchange format '$($Id['format'])'." }
$Recipient = $Id['recipient']
$AgeExe = Join-Path $PSScriptRoot 'age.exe'

# ---------------------------------------------------------------------------------------------------------------
# What it can collect. Each item is a read; the Plan text is what the person is shown before agreeing.
# ---------------------------------------------------------------------------------------------------------------
function Json($o) { $o | ConvertTo-Json -Depth 6 }
$Items = @(
    @{ Id = 'system'; Plan = 'Computer model, serial number, BIOS, CPU, memory size, Windows edition/version/build, install and boot dates, machine identifiers'
       Run = {
            $os = Get-CimInstance Win32_OperatingSystem
            $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
            Json ([ordered]@{
                computer_system = Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer, Model, SystemType, TotalPhysicalMemory, NumberOfLogicalProcessors, PartOfDomain, Domain
                product_uuid    = (Get-CimInstance Win32_ComputerSystemProduct).UUID
                bios            = Get-CimInstance Win32_BIOS | Select-Object Manufacturer, SMBIOSBIOSVersion, ReleaseDate, SerialNumber
                baseboard       = Get-CimInstance Win32_BaseBoard | Select-Object Manufacturer, Product, SerialNumber
                processor       = Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, MaxClockSpeed
                os              = $os | Select-Object Caption, Version, BuildNumber, OSArchitecture, InstallDate, LastBootUpTime, SystemDrive, WindowsDirectory
                os_release      = [ordered]@{ DisplayVersion = $cv.DisplayVersion; UBR = $cv.UBR; EditionID = $cv.EditionID }
                machine_guid    = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Cryptography').MachineGuid
            }) } }
    @{ Id = 'disks'; Plan = 'Physical disks, partitions and volumes: model, size, health status, reliability counters (wear, temperature, error counts), free space'
       Run = {
            Json ([ordered]@{
                physical    = Get-PhysicalDisk | Select-Object FriendlyName, MediaType, BusType, Size, HealthStatus, OperationalStatus, SerialNumber
                reliability = Get-PhysicalDisk | ForEach-Object { $r = $_ | Get-StorageReliabilityCounter; [ordered]@{ disk = $_.FriendlyName; temperature = $r.Temperature; wear = $r.Wear; read_errors = $r.ReadErrorsTotal; write_errors = $r.WriteErrorsTotal; power_on_hours = $r.PowerOnHours } }
                disks       = Get-Disk | Select-Object Number, FriendlyName, PartitionStyle, Size, IsBoot, IsSystem, HealthStatus
                partitions  = Get-Partition | Select-Object DiskNumber, PartitionNumber, Type, Size, DriveLetter, IsBoot, IsSystem
                volumes     = Get-Volume | Select-Object DriveLetter, FileSystemLabel, FileSystem, Size, SizeRemaining, HealthStatus
            }) } }
    @{ Id = 'bitlocker'; Plan = 'BitLocker status of each volume (on/off, locked/unlocked, method). NOT the recovery keys or passwords'
       Run = { (& manage-bde.exe -status 2>&1 | Out-String) } }
    @{ Id = 'updates'; Plan = 'Installed Windows updates (hotfix list), update-related services, and whether a restart is pending'
       Run = {
            $pending = [ordered]@{
                component_servicing = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
                windows_update      = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
                file_rename         = $null -ne (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue)
            }
            Json ([ordered]@{
                hotfixes        = Get-HotFix | Select-Object HotFixID, Description, InstalledOn
                services        = Get-Service wuauserv, bits, TrustedInstaller, cryptsvc -ErrorAction SilentlyContinue | Select-Object Name, Status, StartType
                reboot_pending  = $pending
            }) } }
    @{ Id = 'software'; Plan = 'Names, versions and publishers of installed programs (from the uninstall registry keys)'
       Run = {
            $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
            Json (Get-ItemProperty $keys -ErrorAction SilentlyContinue | Where-Object DisplayName | Sort-Object DisplayName |
                  Select-Object DisplayName, DisplayVersion, Publisher, InstallDate) } }
    @{ Id = 'services'; Plan = 'Every Windows service: name, state, start mode and the account it runs as'
       Run = { Json (Get-CimInstance Win32_Service | Select-Object Name, DisplayName, State, StartMode, StartName, PathName) } }
    @{ Id = 'startup'; Plan = 'Programs that start at sign-in (Run keys, startup folders) and the names of scheduled tasks'
       Run = {
            Json ([ordered]@{
                startup_commands = Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location, User
                scheduled_tasks  = Get-ScheduledTask -ErrorAction SilentlyContinue | Select-Object TaskName, TaskPath, State, Author
            }) } }
    @{ Id = 'events'; Plan = "Error and critical events from the System and Application logs for the last $EventDays days (message text, up to 500 events)"
       Run = {
            $since = (Get-Date).AddDays(-$EventDays)
            $ev = Get-WinEvent -FilterHashtable @{ LogName = 'System', 'Application'; Level = 1, 2; StartTime = $since } -MaxEvents 500 -ErrorAction SilentlyContinue
            Json ($ev | Select-Object TimeCreated, LogName, Id, ProviderName, LevelDisplayName,
                  @{ n = 'Message'; e = { if ($_.Message) { $_.Message.Substring(0, [Math]::Min(500, $_.Message.Length)) } } }) } }
    @{ Id = 'devices'; Plan = 'Hardware devices that report a problem (name, status, error code) and the display, network and storage drivers in use'
       Run = {
            Json ([ordered]@{
                problem_devices = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object Status -ne 'OK' | Select-Object FriendlyName, Class, Status, Problem, InstanceId
                drivers         = Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceClass -in 'DISPLAY', 'NET', 'SCSIADAPTER', 'HDC', 'BLUETOOTH' } |
                                  Select-Object DeviceName, DeviceClass, Manufacturer, DriverVersion, DriverDate
            }) } }
    @{ Id = 'network'; Plan = 'Network adapters, IP addresses, gateways and DNS servers. NOT saved Wi-Fi networks or their passwords'
       Run = {
            Json ([ordered]@{
                adapters = Get-NetAdapter -ErrorAction SilentlyContinue | Select-Object Name, InterfaceDescription, Status, LinkSpeed, MacAddress
                ip       = Get-NetIPConfiguration -ErrorAction SilentlyContinue | Select-Object InterfaceAlias, IPv4Address, IPv6Address, IPv4DefaultGateway, DNSServer
            }) } }
    @{ Id = 'security'; Plan = 'Windows Defender status and signature age, firewall on/off per profile'
       Run = {
            Json ([ordered]@{
                defender = Get-MpComputerStatus -ErrorAction SilentlyContinue | Select-Object AMServiceEnabled, AntivirusEnabled, RealTimeProtectionEnabled, AntivirusSignatureLastUpdated, AntivirusSignatureAge
                firewall = Get-NetFirewallProfile -ErrorAction SilentlyContinue | Select-Object Name, Enabled
            }) } }
    @{ Id = 'crashes'; Plan = 'The names, sizes and dates of crash dump files (not their contents) and battery summary'
       Run = {
            $d = @('C:\Windows\Minidump\*', 'C:\Windows\MEMORY.DMP', 'C:\Windows\LiveKernelReports\*\*.dmp')
            Json ([ordered]@{
                dumps   = Get-ChildItem $d -ErrorAction SilentlyContinue | Select-Object FullName, Length, LastWriteTime
                battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object Name, EstimatedChargeRemaining, BatteryStatus, DesignCapacity, FullChargeCapacity
            }) } }
)

# ---------------------------------------------------------------------------------------------------------------
# Say what will happen, and wait for a person to agree
# ---------------------------------------------------------------------------------------------------------------
Write-Host ''
Write-Host "  SysMedic evidence collector $Script:Version" -ForegroundColor Cyan
Write-Host '  Read-only: nothing on this computer is changed. Nothing leaves it: the result is encrypted and'
Write-Host "  saved to the SysMedic drive this program is running from ($ExchangeRoot)."
Write-Host ''
Write-Host '  It would collect:'
foreach ($i in $Items) { Write-Host ('   - {0}' -f $i.Plan) }
Write-Host '  It does NOT collect documents, photos, browser data, passwords, Wi-Fi keys, BitLocker recovery keys or user folders.'
Write-Host ''
if ($ListOnly) { return }

if (-not $Recipient -or $Recipient -notmatch '^age1[a-z0-9]+$') {
    throw 'This SysMedic drive has no snapshot key yet. Boot SysMedic once and run:  sysmedic-snapshot init  (nothing is collected without it, because the result must be encrypted).'
}
if (-not (Test-Path -LiteralPath $AgeExe)) {
    throw "age.exe is missing from the collector folder, so the result cannot be encrypted. Nothing was collected. (Build step: tools/windows-collector/fetch-age.sh)"
}
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Host '  Note: not running as administrator; event logs, disk health and BitLocker status may be incomplete.' -ForegroundColor Yellow }
$answer = Read-Host '  Type YES to collect this and write the encrypted snapshot to the SysMedic drive (anything else cancels)'
if ($answer -cne 'YES') { Write-Host '  Cancelled. Nothing was collected.'; return }
$consentAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

# ---------------------------------------------------------------------------------------------------------------
# Collect into memory, with provenance
# ---------------------------------------------------------------------------------------------------------------
Add-Type -AssemblyName System.IO.Compression
$utf8 = New-Object System.Text.UTF8Encoding($false)
$sha = [System.Security.Cryptography.SHA256]::Create()
function Sha256Hex([byte[]]$b) { ([BitConverter]::ToString($sha.ComputeHash($b))).Replace('-', '').ToLower() }

$started = (Get-Date).ToUniversalTime()
$snapId = 'SM-{0}-{1}' -f $started.ToString('yyyyMMddTHHmmssZ'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$mem = New-Object System.IO.MemoryStream
$zip = New-Object System.IO.Compression.ZipArchive($mem, [System.IO.Compression.ZipArchiveMode]::Create, $true)
function AddEntry([string]$path, [byte[]]$bytes) {
    $e = $zip.CreateEntry($path, [System.IO.Compression.CompressionLevel]::Optimal)
    $s = $e.Open(); $s.Write($bytes, 0, $bytes.Length); $s.Dispose()
}

$evidence = @(); $failures = @(); $omissions = @()
foreach ($i in $Items) {
    Write-Host ('  collecting {0} ...' -f $i.Id)
    try {
        $out = & $i.Run
        if ($null -eq $out -or "$out".Trim() -eq '' -or "$out".Trim() -eq 'null') { $omissions += [ordered]@{ item = $i.Id; reason = 'nothing returned (feature absent, or needs administrator)' }; continue }
        $ext = if ($i.Id -eq 'bitlocker') { 'txt' } else { 'json' }
        $bytes = $utf8.GetBytes([string]$out)
        $path = "evidence/$($i.Id).$ext"
        AddEntry $path $bytes
        $evidence += [ordered]@{ item = $i.Id; path = $path; sha256 = (Sha256Hex $bytes); bytes = $bytes.Length; description = $i.Plan }
    } catch {
        $failures += [ordered]@{ item = $i.Id; error = $_.Exception.Message }
    }
}

$cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
$manifest = [ordered]@{
    format        = $Script:Format
    snapshot_id   = $snapId
    kind          = 'raw-evidence'                    # evidence only: findings and conclusions are made later, elsewhere
    collector     = [ordered]@{ name = $Script:Name; version = $Script:Version; script_sha256 = (Sha256Hex ([IO.File]::ReadAllBytes($PSCommandPath))); powershell = $PSVersionTable.PSVersion.ToString() }
    exchange_volume_id = $Id['volume_id']
    created_utc   = $started.ToString('yyyy-MM-ddTHH:mm:ssZ')
    finished_utc  = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    consent       = [ordered]@{ listed_and_confirmed = $true; confirmed_utc = $consentAt; run_as_administrator = $isAdmin; run_by = $env:USERNAME }
    source        = [ordered]@{ hostname = $env:COMPUTERNAME; manufacturer = $cs.Manufacturer; model = $cs.Model; os = (Get-CimInstance Win32_OperatingSystem).Caption }
    configuration = [ordered]@{ event_days = $EventDays; items_available = @($Items | ForEach-Object { $_.Id }) }
    evidence      = $evidence
    failures      = $failures
    omissions     = $omissions
    integrity     = [ordered]@{ algorithm = 'sha256'; covers = 'every file under evidence/ (hashes above)'; note = 'The container is also authenticated by age. This is not proof of who made it.' }
}
AddEntry 'manifest.json' ($utf8.GetBytes(($manifest | ConvertTo-Json -Depth 6)))
$zip.Dispose()
$plain = $mem.ToArray(); $mem.Dispose()

# ---------------------------------------------------------------------------------------------------------------
# Encrypt in memory (age, X25519 + ChaCha20-Poly1305) straight onto the exchange drive. No plaintext touches a disk.
# ---------------------------------------------------------------------------------------------------------------
$inbox = Join-Path $ExchangeRoot 'INBOX'
if (-not (Test-Path -LiteralPath $inbox)) { New-Item -ItemType Directory -Path $inbox | Out-Null }
$dest = Join-Path $inbox "$snapId.smsnap.age"
$tmp = "$dest.partial"
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $AgeExe
$psi.Arguments = '-r ' + $Recipient + ' -o "' + $tmp + '"'
$psi.UseShellExecute = $false; $psi.RedirectStandardInput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
$p = [System.Diagnostics.Process]::Start($psi)
$p.StandardInput.BaseStream.Write($plain, 0, $plain.Length)
$p.StandardInput.Close()
$err = $p.StandardError.ReadToEnd(); $p.WaitForExit()
if ($p.ExitCode -ne 0) { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp }; throw "age failed ($($p.ExitCode)): $err" }
Move-Item -LiteralPath $tmp -Destination $dest

$cipher = [IO.File]::ReadAllBytes($dest)
$envelope = [ordered]@{
    format             = 'sysmedic-snapshot-envelope/1'
    snapshot_id        = $snapId
    collector          = "$Script:Name $Script:Version"
    created_utc        = $started.ToString('yyyy-MM-ddTHH:mm:ssZ')
    container          = [ordered]@{ file = (Split-Path -Leaf $dest); encryption = 'age (X25519, ChaCha20-Poly1305)'; inner = 'zip'; sha256 = (Sha256Hex $cipher); bytes = $cipher.Length }
    recipient_fingerprint = (Sha256Hex ($utf8.GetBytes($Recipient))).Substring(0, 16)
    exchange_volume_id = $Id['volume_id']
}
[IO.File]::WriteAllBytes((Join-Path $inbox "$snapId.envelope.json"), $utf8.GetBytes(($envelope | ConvertTo-Json -Depth 4)))

Write-Host ''
Write-Host "  Done. Snapshot $snapId written to INBOX on the SysMedic drive (encrypted)." -ForegroundColor Green
Write-Host ('  {0} items collected, {1} failed, {2} empty.' -f $evidence.Count, $failures.Count, $omissions.Count)
Write-Host '  You can now close this window and remove the drive.'
