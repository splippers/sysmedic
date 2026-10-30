#!/usr/bin/env python3
"""The stick's boot is quiet: python3 build/tests/test_quietboot.py

zz-sysmedic-quiet-boot edits Ubuntu's casper scripts inside the initramfs; here it runs on copies of the lines it
targets (as casper 1.4xx ships them) and must change exactly those, leave unknown text alone and be idempotent.
Whether the real boot is quiet is checked by booting the image (docs/EDITIONS-AND-DEPLOY.md, "Test before writing").
"""
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
HOOK = REPO / "build/staging/shared/etc/initramfs-tools/hooks/zz-sysmedic-quiet-boot"
GRUB = REPO / "build/staging/iso/boot/grub/grub.cfg"

FILES = {
    "casper": "x\n        if /lib/udev/cdrom_id ${devname} > /dev/null; then\n        fi\n",
    "casper-premount/10driver_updates": "        if /lib/udev/cdrom_id ${devname} > /dev/null; then\n",
    "casper-helpers": "get_fstype() {\n    local FSTYPE\n    eval $(fstype < $1)\n    echo $FSTYPE\n}\n",
    "casper-bottom/25adduser": "if [ ! -f /root/usr/bin/sddm ]; then\n    chroot /root passwd -d \"$USERNAME\"\nfi\n",
    "casper-bottom/52gnome_initial_setup": "chroot /root chown -R $USERNAME.$USERNAME /home/$USERNAME/.config\n",
    "casper-bottom/59disable_mozc_autosetup": "chroot /root chown -R $USERNAME.$USERNAME /home/$USERNAME/.config\n",
    "casper-bottom/41apt_cdrom": "#! /bin/sh\nchroot /root apt-cdrom -m add\n",
}


def run_hook(dest):
    return subprocess.run(["sh", str(HOOK)], env={**os.environ, "DESTDIR": str(dest)}, capture_output=True, text=True)


class QuietBoot(unittest.TestCase):
    def setUp(self):
        self.d = Path(tempfile.mkdtemp())
        for name, text in FILES.items():
            p = self.d / "scripts" / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(text)

    def tearDown(self):
        shutil.rmtree(self.d, ignore_errors=True)

    def read(self, name):
        return (self.d / "scripts" / name).read_text()

    def test_hook_is_executable_and_syntax_ok(self):
        self.assertTrue(os.access(HOOK, os.X_OK))
        self.assertEqual(subprocess.run(["sh", "-n", str(HOOK)]).returncode, 0)

    def test_messages_are_silenced(self):
        r = run_hook(self.d)
        self.assertEqual(r.returncode, 0, r.stderr)
        for f in ("casper", "casper-premount/10driver_updates"):
            self.assertIn("cdrom_id ${devname} > /dev/null 2>&1; then", self.read(f))
        self.assertIn("{ eval $(fstype < $1); } 2>/dev/null", self.read("casper-helpers"))
        self.assertIn('passwd -d "$USERNAME" >/dev/null 2>&1', self.read("casper-bottom/25adduser"))
        for f in ("casper-bottom/52gnome_initial_setup", "casper-bottom/59disable_mozc_autosetup"):
            self.assertIn("chown -R $USERNAME:$USERNAME", self.read(f))
        self.assertNotIn("apt-cdrom", self.read("casper-bottom/41apt_cdrom"))
        self.assertTrue(os.access(self.d / "scripts/casper-bottom/41apt_cdrom", os.X_OK))
        self.assertEqual(subprocess.run(["sh", "-n", str(self.d / "scripts/casper-bottom/41apt_cdrom")]).returncode, 0)

    def test_apt_cdrom_stub_still_answers_prereqs(self):
        run_hook(self.d)
        r = subprocess.run(["sh", str(self.d / "scripts/casper-bottom/41apt_cdrom"), "prereqs"], capture_output=True, text=True)
        self.assertEqual((r.returncode, r.stdout.strip()), (0, ""))

    def test_idempotent_and_leaves_other_text_alone(self):
        run_hook(self.d)
        once = {f: self.read(f) for f in FILES}
        run_hook(self.d)
        self.assertEqual({f: self.read(f) for f in FILES}, once)

    def test_unknown_casper_is_left_alone(self):
        for f in FILES:
            (self.d / "scripts" / f).write_text("# something else entirely\n")
        run_hook(self.d)
        for f in FILES:
            if f != "casper-bottom/41apt_cdrom":
                self.assertEqual(self.read(f), "# something else entirely\n", f)

    def test_missing_scripts_dir_is_not_an_error(self):
        shutil.rmtree(self.d / "scripts")
        self.assertEqual(run_hook(self.d).returncode, 0)

    def test_quieted_redirect_really_hides_the_shell_error(self):
        out = subprocess.run(["sh", "-c", 'f(){ { eval $(cat < "$1"); } 2>/dev/null; }; f /nonexistent'], capture_output=True, text=True)
        self.assertEqual(out.stderr, "")

    def test_failures_still_show(self):
        """Only the listed noise is hidden: a real mount failure in casper is not touched."""
        run_hook(self.d)
        self.assertNotIn("2>/dev/null", self.read("casper").replace("> /dev/null 2>&1", ""))


class GrubEntries(unittest.TestCase):
    def test_casper_never_edits_the_sticks_partition_table(self):
        lines = [l for l in GRUB.read_text().splitlines() if "/casper/vmlinuz" in l]
        self.assertEqual(len(lines), 3)
        for l in lines:
            self.assertRegex(l, r"\bnopersistent\b.*---")          # before the --- (casper's own options)

    def test_other_options_unchanged(self):
        for l in [l for l in GRUB.read_text().splitlines() if "/casper/vmlinuz" in l]:
            self.assertIn("hostname=sysmedic md_mod.start_ro=1", l)


if __name__ == "__main__":
    unittest.main(verbosity=1)
