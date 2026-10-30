#!/usr/bin/env python3
"""The exchange partition, the Windows-visible layout and the portable snapshot: python3 build/tests/test_exchange.py

Needs sgdisk/sfdisk (image files, no root), mkfs.exfat, and `age`/`age-keygen` for the snapshot round trip
(those tests skip with a message if a tool is missing). The Windows behaviour itself can't be tested here:
see docs/HARDWARE-TESTING.md, "Exchange partition on real Windows".
"""
import hashlib
import io
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
XCHG = REPO / "build/xchg_layout.py"
SNAP = REPO / "build/staging/shared/usr/local/sbin/sysmedic-snapshot"
MAKE_STICK = REPO / "build/make-stick.sh"
COLLECTOR = REPO / "tools/windows-collector"
BASIC = "EBD0A0A2-B9E5-4433-87C0-68B6B72699C7"


def need(*tools):
    missing = [t for t in tools if not shutil.which(t)]
    return unittest.skipIf(missing, f"needs {', '.join(missing)}")


def run(*cmd, **kw):
    return subprocess.run([str(c) for c in cmd], capture_output=True, text=True, **kw)


def isolike_image(path, exchange=True, mib=700):
    """A disk laid out the way make-stick.sh leaves a stick: the xorriso ISO partitions, then persistence, then exchange."""
    with open(path, "wb") as f:
        f.truncate(mib << 20)
    s = ["sgdisk", "-a", "2048", "-n", "1:64:+300M", "-t", "1:0700", "-c", "1:ISO9660", "-A", "1:set:0", "-A", "1:set:60",
         "-n", "2:0:+4M", "-t", "2:ef00", "-c", "2:Appended2",
         "-n", "3:0:+300K", "-t", "3:0700", "-c", "3:Gap1", "-A", "3:set:0", "-A", "3:set:60"]
    if exchange:
        s += ["-n", "4:0:-64M", "-t", "4:8300", "-c", "4:FOG_AMB_PERSIST", "-n", "5:0:0", "-t", "5:0700", "-c", "5:SM_EXCHANGE"]
    else:
        s += ["-n", "4:0:0", "-t", "4:8300", "-c", "4:FOG_AMB_PERSIST"]
    r = run(*s, path)
    assert r.returncode == 0, r.stderr


def table(path):
    return [l for l in run("sfdisk", "-d", path).stdout.splitlines() if l.startswith(str(path))]


def strip_volatile(lines):
    return [re.sub(r', attrs="[^"]*"', "", re.sub(r"uuid=[0-9A-F-]+, ", "", l)) for l in lines]


class WindowsView(unittest.TestCase):
    @need("sgdisk", "sfdisk")
    def setUp(self):
        self.d = tempfile.mkdtemp()
        self.img = Path(self.d) / "stick.img"

    def tearDown(self):
        shutil.rmtree(self.d, ignore_errors=True)

    def test_unhidden_iso_partitions_would_be_offered_to_windows(self):
        isolike_image(self.img)
        r = run("python3", XCHG, "check", self.img)
        self.assertEqual(r.returncode, 1, r.stdout)
        self.assertIn("partition(s) 1, 3", r.stdout)

    def test_hide_leaves_only_the_exchange_partition_visible(self):
        isolike_image(self.img)
        self.assertEqual(run("python3", XCHG, "hide", self.img).returncode, 0)
        r = run("python3", XCHG, "check", self.img, "--expect-exchange")
        self.assertEqual(r.returncode, 0, r.stdout)
        self.assertIn("Windows sees only the SM_EXCHANGE partition", r.stdout)

    def test_hide_changes_attributes_only(self):
        """Types, starts, sizes and numbers (everything UEFI/BIOS/Linux boot look at) are byte-for-byte as they were."""
        isolike_image(self.img)
        before = strip_volatile(table(self.img))
        run("python3", XCHG, "hide", self.img)
        self.assertEqual(strip_volatile(table(self.img)), before)
        for n, bits in ((1, "1000000000000001"), (3, "1000000000000001")):      # RequiredPartition + read-only kept ...
            flags = int(re.search(r"Attribute flags: (\w+)", run("sgdisk", "-i", n, self.img).stdout).group(1), 16)
            self.assertEqual(flags & int(bits, 16), int(bits, 16))
            self.assertTrue(flags >> 62 & 1 and flags >> 63 & 1)                  # ... plus hidden and no-drive-letter
        # the ESP, the persistence partition and the exchange partition are untouched
        for n in (2, 4, 5):
            flags = int(re.search(r"Attribute flags: (\w+)", run("sgdisk", "-i", n, self.img).stdout).group(1), 16)
            self.assertEqual(flags, 0, f"partition {n} attributes changed")

    def test_hide_is_idempotent(self):
        isolike_image(self.img)
        run("python3", XCHG, "hide", self.img)
        once = run("sgdisk", "-p", self.img).stdout
        self.assertIn("hid 0 partition", run("python3", XCHG, "hide", self.img).stdout)
        self.assertEqual(run("sgdisk", "-p", self.img).stdout, once)

    def test_drive_without_exchange_shows_nothing_to_windows(self):
        isolike_image(self.img, exchange=False)
        run("python3", XCHG, "hide", self.img)
        r = run("python3", XCHG, "check", self.img)
        self.assertEqual(r.returncode, 0)
        self.assertIn("no exchange partition", r.stdout)
        self.assertEqual(run("python3", XCHG, "check", self.img, "--expect-exchange").returncode, 1)

    def test_another_visible_basic_data_partition_fails_the_check(self):
        isolike_image(self.img)
        run("python3", XCHG, "hide", self.img)
        run("sgdisk", "-A", "3:clear:63", self.img)
        self.assertEqual(run("python3", XCHG, "check", self.img).returncode, 1)


class MakeStickLayout(unittest.TestCase):
    """Static guards on the stick build: the existing four partitions are made exactly as before."""

    def setUp(self):
        self.s = MAKE_STICK.read_text()

    def test_existing_partitions_unchanged(self):
        self.assertIn("-t 4:8300 -c 4:FOG_AMB_PERSIST", self.s)
        self.assertIn("dd if=\"$ISO\" of=\"$TARGET\"", self.s)
        self.assertIn("mkfs.ext4 -q -F -L FOG_AMB_PERSIST -m 0", self.s)
        self.assertIn("sgdisk -e", self.s)

    def test_mbr_restored_after_every_sgdisk_run(self):
        """sgdisk rewrites the hybrid MBR; make-stick puts xorriso's back, so every partition change must precede that."""
        restore = self.s.index("of=\"$TARGET\" bs=1 seek=446")
        self.assertNotIn("sgdisk", self.s[restore:].replace("sgdisk -v", ""))
        self.assertLess(self.s.index("xchg_layout.py\" hide"), restore)
        self.assertLess(self.s.index("5:SM_EXCHANGE"), restore)

    def test_exchange_partition_is_last_and_exfat(self):
        self.assertIn("-n 5:0:0 -t 5:0700 -c 5:SM_EXCHANGE", self.s)
        self.assertIn("mkfs.exfat -L SM_EXCHANGE", self.s)
        self.assertIn("-n 4:0:-${XCHG_MIB}M", self.s)

    def test_deploy_verification_skips_the_partition_entries(self):
        d = (REPO / "build/sysmedic-deploy").read_text()
        self.assertIn("cmp -s -n $((size - 2048)) -i 2048", d)       # entry 5 lives in LBA 3
        self.assertIn("xchg_layout.py", d)

    def test_exfat_label_fits(self):
        self.assertLessEqual(len("SM_EXCHANGE"), 11)

    @need("mkfs.exfat", "exfatlabel")
    def test_exfat_volume_takes_the_label(self):
        with tempfile.TemporaryDirectory() as d:
            img = Path(d) / "x.img"
            img.write_bytes(b"")
            os.truncate(img, 64 << 20)
            self.assertEqual(run("mkfs.exfat", "-L", "SM_EXCHANGE", img).returncode, 0)
            self.assertIn("label: SM_EXCHANGE", run("exfatlabel", img).stdout)


class Populate(unittest.TestCase):
    def setUp(self):
        self.d = Path(tempfile.mkdtemp())
        self.coll = self.d / "src"
        self.coll.mkdir()
        (self.coll / "a.ps1").write_bytes(b"line1\nline2\n")
        (self.coll / "b.cmd").write_bytes(b"@echo off\n")
        (self.coll / "age.exe").write_bytes(b"MZ")
        (self.coll / "secret.key").write_bytes(b"not copied")
        self.mnt = self.d / "mnt"
        self.mnt.mkdir()

    def tearDown(self):
        shutil.rmtree(self.d, ignore_errors=True)

    def populate(self, **kw):
        a = ["python3", XCHG, "populate", self.mnt, "--edition", kw.get("edition", "stick"), "--version", kw.get("version", "1.2.3"),
             "--collector", self.coll]
        return run(*a)

    def test_layout_and_contents(self):
        self.assertEqual(self.populate().returncode, 0)
        for p in ("SYSMEDIC.ID", "README.txt", "collector/a.ps1", "collector/b.cmd", "collector/age.exe", "INBOX", "EXPORT"):
            self.assertTrue((self.mnt / p).exists(), p)
        self.assertFalse((self.mnt / "collector/secret.key").exists())
        self.assertEqual((self.mnt / "collector/a.ps1").read_bytes(), b"line1\r\nline2\r\n")       # Windows line endings
        self.assertEqual((self.mnt / "collector/age.exe").read_bytes(), b"MZ")                      # binaries untouched
        ident = (self.mnt / "SYSMEDIC.ID").read_text()
        self.assertIn("format=sysmedic-exchange/1", ident)
        self.assertIn("edition=stick", ident)
        self.assertIn("build=1.2.3", ident)
        self.assertRegex(ident, r"volume_id=[0-9a-f-]{36}")

    def test_identity_and_key_survive_an_update(self):
        self.populate()
        (self.mnt / "SYSMEDIC.ID").write_bytes((self.mnt / "SYSMEDIC.ID").read_bytes() + b"recipient=age1abc\r\n")
        before = dict(l.split("=", 1) for l in (self.mnt / "SYSMEDIC.ID").read_text().split())
        self.populate(version="9.9.9")
        after = dict(l.split("=", 1) for l in (self.mnt / "SYSMEDIC.ID").read_text().split())
        self.assertEqual(after["volume_id"], before["volume_id"])
        self.assertEqual(after["recipient"], "age1abc")
        self.assertEqual(after["build"], "9.9.9")

    def test_warns_when_age_is_missing(self):
        (self.coll / "age.exe").unlink()
        r = self.populate()
        self.assertEqual(r.returncode, 0)
        self.assertIn("age.exe", r.stderr)

    def test_readme_makes_the_promises(self):
        self.populate()
        t = (self.mnt / "README.txt").read_text()
        for phrase in ("Nothing happens when you plug this in", "Nothing is sent anywhere", "ENCRYPTED", "does not change anything"):
            self.assertIn(phrase, t)


class CollectorScript(unittest.TestCase):
    """The collector is evidence-only and read-only: guard its text, since Windows can't be run here."""

    def setUp(self):
        self.t = (COLLECTOR / "SysMedic-Collect.ps1").read_text()
        self.code = "\n".join(l for l in self.t.splitlines() if not l.strip().startswith("#"))

    def test_no_commands_that_change_windows(self):
        bad = (r"\b(Set-|Stop-|Start-Service|Restart-|Disable-|Enable-|Clear-|Install-|Uninstall-|Add-Content|Out-File|Set-Content|"
               r"Register-|Unregister-|New-Service|Format-Volume|Repair-|sc\.exe|netsh|bcdedit|wmic|taskkill|schtasks)")
        self.assertEqual(re.findall(bad, self.code), [])
        self.assertIsNone(re.search(r"reg(\.exe)? +(add|delete|import)", self.code))
        # the only deletion is the half-written output on the exchange drive; the only creation is its INBOX folder
        self.assertTrue(all("$tmp" in r for r in re.findall(r"Remove-Item[^\n]*", self.code)))
        self.assertEqual(len(re.findall(r"New-Item", self.code)), 1)
        self.assertIn("New-Item -ItemType Directory -Path $inbox", self.code)

    def test_no_network(self):
        for word in ("Invoke-WebRequest", "Invoke-RestMethod", "WebClient", "System.Net.Http", "Test-NetConnection", "ping"):
            self.assertNotIn(word, self.code, word)

    def test_never_collects_secrets(self):
        for word in ("RecoveryPassword", "-protectors", "key=clear", "wlan", "Login Data", "Cookies", "Get-Credential", "ConvertTo-SecureString"):
            self.assertNotIn(word, self.code, word)

    def test_consent_comes_before_any_collection(self):
        self.assertLess(self.t.index("Type YES"), self.t.index("foreach ($i in $Items) {\n    Write-Host ('  collecting"))
        self.assertIn("-cne 'YES'", self.t)
        self.assertLess(self.t.index("if ($ListOnly) { return }"), self.t.index("Type YES"))

    def test_plaintext_is_never_written_to_disk(self):
        self.assertNotIn("WriteAllBytes($plain", self.code)
        self.assertNotIn("$env:TEMP", self.code)
        self.assertIn("StandardInput.BaseStream.Write($plain", self.code)
        self.assertIn("age.exe", self.code)
        self.assertLess(self.t.index("no snapshot key yet"), self.t.index("collecting"))     # refuses without a recipient

    def test_no_drive_letter_assumed(self):
        self.assertIn("$PSScriptRoot", self.code)
        self.assertNotRegex(self.code, r"['\"][D-Z]:\\")

    def test_manifest_carries_provenance(self):
        for field in ("snapshot_id", "collector", "created_utc", "finished_utc", "consent", "source", "configuration", "evidence",
                      "failures", "omissions", "integrity", "sha256", "kind"):
            self.assertIn(field, self.t, field)

    @need("pwsh")
    def test_parses(self):
        r = run("pwsh", "-NoProfile", "-Command",
                f"$e=$null;[void][System.Management.Automation.Language.Parser]::ParseFile('{COLLECTOR / 'SysMedic-Collect.ps1'}',[ref]$null,[ref]$e);$e.Count")
        self.assertEqual(r.stdout.strip(), "0", r.stdout + r.stderr)


def make_container(sid="SM-20261030T120000Z-abcd1234", evidence=None, tamper=None, extra=None, manifest_extra=None):
    """The same container the collector builds: a zip of manifest.json + evidence/*."""
    evidence = evidence if evidence is not None else {"evidence/system.json": b'{"os": "Windows 11"}', "evidence/disks.json": b"[]"}
    man = {"format": "sysmedic-snapshot/1", "snapshot_id": sid, "kind": "raw-evidence",
           "collector": {"name": "SysMedic-Collect", "version": "0.1.0"}, "created_utc": "2026-10-30T12:00:00Z",
           "evidence": [{"item": p.split("/")[1].split(".")[0], "path": p, "sha256": hashlib.sha256(b).hexdigest(), "bytes": len(b)}
                        for p, b in evidence.items()],
           "failures": [{"item": "bitlocker", "error": "access denied"}], "omissions": []}
    man.update(manifest_extra or {})
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("manifest.json", json.dumps(man))
        for p, b in evidence.items():
            z.writestr(p, tamper.get(p, b) if tamper else b)
        for name, data in (extra or {}).items():
            z.writestr(name, data)
    return buf.getvalue()


class Snapshot(unittest.TestCase):
    @need("age", "age-keygen")
    def setUp(self):
        self.d = Path(tempfile.mkdtemp())
        self.ident = self.d / "id.txt"
        run("age-keygen", "-o", self.ident)
        self.recipient = run("age-keygen", "-y", self.ident).stdout.strip()
        self.inbox = self.d / "INBOX"
        self.inbox.mkdir()
        self.dest = self.d / "snapshots"

    def tearDown(self):
        for p in self.d.rglob("*"):
            if p.is_dir():
                p.chmod(0o755)
        shutil.rmtree(self.d, ignore_errors=True)

    def put(self, container, sid="SM-20261030T120000Z-abcd1234", recipient=None, envelope=True):
        ct = subprocess.run(["age", "-r", recipient or self.recipient], input=container, capture_output=True).stdout
        (self.inbox / f"{sid}.smsnap.age").write_bytes(ct)
        if envelope:
            (self.inbox / f"{sid}.envelope.json").write_text(json.dumps({
                "format": "sysmedic-snapshot-envelope/1", "snapshot_id": sid,
                "container": {"file": f"{sid}.smsnap.age", "sha256": hashlib.sha256(ct).hexdigest(), "bytes": len(ct)}}))
        return ct

    def snap(self, *args):
        return run("python3", SNAP, "--inbox", self.inbox, "--identity", self.ident, "--dest", self.dest, *args)

    def test_round_trip_keeps_evidence_and_provenance_apart_from_findings(self):
        self.put(make_container())
        r = self.snap("import")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        root = self.dest / "SM-20261030T120000Z-abcd1234"
        self.assertEqual((root / "raw/evidence/system.json").read_bytes(), b'{"os": "Windows 11"}')
        self.assertEqual(json.loads((root / "raw/manifest.json").read_text())["failures"][0]["item"], "bitlocker")
        rec = json.loads((root / "import.json").read_text())
        self.assertTrue(rec["integrity"]["ok"])
        self.assertEqual(rec["collection_failures"], 1)
        self.assertFalse((root / "findings").exists())                       # analysis hasn't run: nothing pretends to be a finding
        self.assertEqual(stat.S_IMODE((root / "raw/evidence/system.json").stat().st_mode), 0o444)

    def test_cannot_open_without_the_right_key(self):
        other = self.d / "other.txt"
        run("age-keygen", "-o", other)
        self.put(make_container(), recipient=run("age-keygen", "-y", other).stdout.strip())
        r = self.snap("import")
        self.assertEqual(r.returncode, 1)
        self.assertIn("Couldn't decrypt", r.stdout)
        self.assertFalse(self.dest.exists())

    def test_ciphertext_is_not_plaintext(self):
        ct = self.put(make_container())
        self.assertNotIn(b"Windows 11", ct)
        self.assertNotIn(b"manifest.json", ct)
        self.assertNotIn(b"PK\x03\x04", ct[:8])

    def test_damaged_ciphertext_is_caught_by_the_envelope(self):
        ct = self.put(make_container())
        (self.inbox / "SM-20261030T120000Z-abcd1234.smsnap.age").write_bytes(ct[:-5] + b"XXXXX")
        r = self.snap("import")
        self.assertEqual(r.returncode, 1)
        self.assertIn("doesn't match its envelope", r.stdout)

    def test_damaged_ciphertext_without_envelope_fails_decryption(self):
        ct = self.put(make_container(), envelope=False)
        (self.inbox / "SM-20261030T120000Z-abcd1234.smsnap.age").write_bytes(ct[:-5] + b"XXXXX")
        self.assertEqual(self.snap("import").returncode, 1)

    def test_evidence_that_does_not_match_its_hash_is_reported(self):
        self.put(make_container(tamper={"evidence/system.json": b'{"os": "changed"}'}))
        r = self.snap("import")
        self.assertEqual(r.returncode, 1)
        self.assertIn("evidence/system.json", r.stdout)
        rec = json.loads((self.dest / "SM-20261030T120000Z-abcd1234/import.json").read_text())
        self.assertFalse(rec["integrity"]["ok"])

    def test_unlisted_files_are_noted(self):
        self.put(make_container(extra={"evidence/extra.txt": b"x"}))
        self.snap("import")
        rec = json.loads((self.dest / "SM-20261030T120000Z-abcd1234/import.json").read_text())
        self.assertEqual(rec["integrity"]["unlisted"], ["evidence/extra.txt"])

    def test_path_traversal_is_refused(self):
        for bad in ("../escape.txt", "/abs.txt", "evidence/../../x", "C:\\x.txt", "a\\b.txt"):
            self.setUp()
            self.put(make_container(extra={bad: b"x"}))
            r = self.snap("import")
            self.assertEqual(r.returncode, 1, bad)
            self.assertIn("Unsafe path", r.stdout, bad)
            self.assertFalse((self.d / "escape.txt").exists())

    def test_links_are_refused(self):
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w") as z:
            z.writestr("manifest.json", make_container() and json.dumps({"format": "sysmedic-snapshot/1", "snapshot_id": "SM-20261030T120000Z-abcd1234", "evidence": []}))
            i = zipfile.ZipInfo("evidence/link")
            i.external_attr = (stat.S_IFLNK | 0o777) << 16
            z.writestr(i, "/etc/passwd")
        self.put(buf.getvalue())
        r = self.snap("import")
        self.assertEqual(r.returncode, 1)
        self.assertIn("Link in snapshot", r.stdout)

    def test_not_a_snapshot(self):
        self.put(b"just some text, not a zip")
        self.assertEqual(self.snap("import").returncode, 1)
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w") as z:
            z.writestr("manifest.json", json.dumps({"format": "something-else/9", "snapshot_id": "SM-20261030T120000Z-abcd1234"}))
        self.setUp()
        self.put(buf.getvalue())
        self.assertIn("Unknown snapshot format", self.snap("import").stdout)

    def test_importing_twice_is_refused_not_overwritten(self):
        self.put(make_container())
        self.assertEqual(self.snap("import").returncode, 0)
        r = self.snap("import")
        self.assertEqual(r.returncode, 1)
        self.assertIn("already imported", r.stdout)

    def test_verify_does_not_import(self):
        self.put(make_container())
        r = self.snap("verify", self.inbox / "SM-20261030T120000Z-abcd1234.smsnap.age")
        self.assertEqual(r.returncode, 0, r.stdout)
        self.assertEqual(json.loads(r.stdout)["integrity"]["ok"], True)
        self.assertFalse(self.dest.exists())

    def test_list(self):
        self.put(make_container())
        self.assertIn("waiting", self.snap("list").stdout)
        self.snap("import")
        self.assertIn("imported this visit", self.snap("list").stdout)


def on_terminal(argv, answers, timeout=30):
    """Run argv with a pseudo-terminal (age reads passphrases from the terminal) and type `answers` at its prompts."""
    import pty
    import select
    import time
    pid, fd = pty.fork()
    if pid == 0:
        os.execvp(argv[0], argv)
    out, sent, t0 = b"", 0, time.time()
    while time.time() - t0 < timeout:
        if select.select([fd], [], [], 0.5)[0]:
            try:
                c = os.read(fd, 4096)
            except OSError:
                break
            if not c:
                break
            out += c
            if sent < len(answers) and out.rstrip().endswith(b":"):
                os.write(fd, answers[sent] + b"\n")
                sent += 1
                out += b"<sent>"
    return os.waitstatus_to_exitcode(os.waitpid(pid, 0)[1]), out.decode(errors="replace")


class PassphraseFlow(unittest.TestCase):
    """init makes a passphrase-protected key and publishes only the public key; import needs that passphrase."""

    @need("age", "age-keygen")
    def setUp(self):
        self.d = Path(tempfile.mkdtemp())
        self.root = self.d / "exchange"
        (self.root / "INBOX").mkdir(parents=True)
        (self.root / "SYSMEDIC.ID").write_bytes(b"format=sysmedic-exchange/1\r\nvolume_id=v1\r\n")
        self.ident = self.d / "snapshot-identity.age"

    def tearDown(self):
        for p in self.d.rglob("*"):
            if p.is_dir():
                p.chmod(0o755)
        shutil.rmtree(self.d, ignore_errors=True)

    def init(self):
        return on_terminal(["python3", str(SNAP), "--identity", str(self.ident), "--inbox-root", str(self.root), "init"], [b"hunter2", b"hunter2"])

    def test_init_then_collect_then_import(self):
        rc, out = self.init()
        self.assertEqual(rc, 0, out)
        recipient = dict(l.split("=", 1) for l in (self.root / "SYSMEDIC.ID").read_text().split())["recipient"]
        self.assertRegex(recipient, r"^age1[a-z0-9]+$")
        self.assertNotIn("AGE-SECRET-KEY", self.ident.read_text(errors="replace"))     # the private key is never stored bare
        self.assertEqual(stat.S_IMODE(self.ident.stat().st_mode), 0o600)
        ct = subprocess.run(["age", "-r", recipient], input=make_container(), capture_output=True).stdout
        (self.root / "INBOX/SM-20261030T120000Z-abcd1234.smsnap.age").write_bytes(ct)
        dest = self.d / "snapshots"
        argv = ["python3", str(SNAP), "--inbox", str(self.root / "INBOX"), "--identity", str(self.ident), "--dest", str(dest), "import"]
        rc, out = on_terminal(argv, [b"wrong"])
        self.assertEqual(rc, 1, out)
        self.assertFalse(dest.exists())
        rc, out = on_terminal(argv, [b"hunter2"])
        self.assertEqual(rc, 0, out)
        self.assertTrue((dest / "SM-20261030T120000Z-abcd1234/raw/evidence/system.json").exists())

    def test_second_init_will_not_replace_the_key(self):
        self.assertEqual(self.init()[0], 0)
        first = self.ident.read_bytes()
        rc, out = self.init()
        self.assertEqual(rc, 1)
        self.assertIn("already has a snapshot key", out)
        self.assertEqual(self.ident.read_bytes(), first)


class WholeSetup(unittest.TestCase):
    def test_snapshot_tool_is_executable_and_python_compiles(self):
        self.assertTrue(os.access(SNAP, os.X_OK))
        self.assertTrue(os.access(XCHG, os.X_OK))
        for p in (SNAP, XCHG):
            compile(p.read_text(), str(p), "exec")

    def test_age_is_in_the_shared_packages(self):
        pk = (REPO / "build/staging/packages/shared.txt").read_text().split()
        self.assertIn("age", pk)

    def test_pinned_age_download_is_checked(self):
        f = (COLLECTOR / "fetch-age.sh").read_text()
        self.assertRegex(f, r"SHA256=[0-9a-f]{64}")
        self.assertIn("sha256sum -c", f)


if __name__ == "__main__":
    unittest.main(verbosity=1)
