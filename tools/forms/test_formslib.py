import json
import os
import tempfile
import unittest

import formslib as F

HERE = os.path.dirname(os.path.abspath(__file__))
LSBLK = json.dumps({"blockdevices": [
    {"path": "/dev/sda", "model": "Samsung SSD 870 ", "size": "500107862016", "ro": True, "rm": False, "tran": "sata", "type": "disk", "serial": "S1"},
    {"path": "/dev/sdb", "model": None, "size": "15376318464", "ro": False, "rm": True, "tran": "usb", "type": "disk", "serial": None},
    {"path": "/dev/zram0", "model": None, "size": "4000000000", "ro": False, "rm": False, "tran": None, "type": "disk", "serial": None},
    {"path": "/dev/loop0", "model": None, "size": "1000", "ro": True, "rm": False, "tran": None, "type": "loop", "serial": None}]})


class Specs(unittest.TestCase):
    def test_every_shipped_spec_loads(self):
        specs, errors = F.load_all(os.path.join(HERE, "specs"))
        self.assertEqual(errors, [])
        self.assertGreaterEqual(len(specs), 5)

    def test_command_uses_arguments_not_a_shell(self):
        s = F.load_spec(os.path.join(HERE, "specs", "ddrescue.toml"))
        v = F.defaults(s)
        v.update(disk="/dev/sdb", dest="/tmp/a b; rm -rf /")
        cmd = F.build_command(s, v, as_root=True)
        self.assertEqual(cmd[:4], ["ddrescue", "-f", "-d", "/dev/sdb"])
        self.assertEqual(cmd[4], "/tmp/a b; rm -rf //rescue.img")      # one argument, untouched
        self.assertEqual(len(cmd), 6)

    def test_if_items(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "t.toml")
            with open(p, "w") as f:
                f.write('title="t"\nsummary="s"\ncommand=["x",{if="a",args=["-a"]},{if="m",equals="fast",args=["--fast"]},{if="m",equals="slow",args=["--slow"]}]\n'
                        '[[field]]\nid="a"\nlabel="A"\ntype="bool"\n[[field]]\nid="m"\nlabel="M"\ntype="choice"\noptions=["fast","slow"]\n')
            s = F.load_spec(p)
            self.assertEqual(F.build_command(s, {"a": False, "m": "fast"}, as_root=True), ["x", "--fast"])
            self.assertEqual(F.build_command(s, {"a": True, "m": "slow"}, as_root=True), ["x", "-a", "--slow"])

    def test_photorec_command(self):
        s = F.load_spec(os.path.join(HERE, "specs", "photorec.toml"))
        c = F.build_command(s, {"disk": "/dev/sdb", "dest": "/mnt/x"}, as_root=True)
        self.assertEqual(c[:6], ["photorec", "/log", "/d", "/mnt/x/recovered", "/cmd", "/dev/sdb"])
        self.assertIn("wholespace", c[6])
        self.assertIn("/mnt/x", F.finish_text(s, {"dest": "/mnt/x"}) + "/mnt/x")

    def test_terminal_codes_are_removed(self):
        raw = "\x1b[?1049h\x1b[22;0;0t\x1b[1;24r\x1b(B\x1b[m\x1b[39;49mPhotoRec 7.1\x1b[2dline\x1b[?25h\x1b[23;0;0t"
        self.assertEqual(F.clean(raw), "PhotoRec 7.1line")

    def test_sudo_added_only_when_needed(self):
        s = F.load_spec(os.path.join(HERE, "specs", "photorec.toml"))
        self.assertEqual(F.build_command(s, F.defaults(s), as_root=False)[:2], ["sudo", "-n"])
        self.assertNotEqual(F.build_command(s, F.defaults(s), as_root=True)[0], "sudo")
        n = F.load_spec(os.path.join(HERE, "specs", "speed-test.toml"))
        self.assertEqual(F.build_command(n, F.defaults(n), as_root=False)[0], "speedtest-cli")

    def test_problems(self):
        s = F.load_spec(os.path.join(HERE, "specs", "photorec.toml"))
        self.assertEqual(len(F.problems(s, F.defaults(s))), 2)           # no disk, no folder
        with tempfile.TemporaryDirectory() as d:
            ok = F.defaults(s) | {"disk": "/dev/sdb", "dest": d}
            self.assertEqual(F.problems(s, ok), [])
            self.assertEqual(len(F.problems(s, ok | {"dest": d + "/nope"})), 1)
            self.assertEqual(len(F.problems(s, ok | {"disk": "sdb"})), 1)

    def test_a_typed_value_cannot_become_an_option(self):
        spec = {"field": [{"id": "host", "label": "Host", "type": "text"}]}
        self.assertEqual(len(F.problems(spec, {"host": "--output=/etc/passwd"})), 1)
        self.assertEqual(F.problems(spec, {"host": "example.com"}), [])

    def test_bad_specs_are_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "x.toml")
            open(p, "w").write('title="t"\nsummary="s"\ncommand=["x","{nope}"]\n')
            with self.assertRaises(F.SpecError):
                F.load_spec(p)
            open(p, "w").write('title="t"\nsummary="s"\nrisk="yolo"\ncommand=["x"]\n')
            with self.assertRaises(F.SpecError):
                F.load_spec(p)

    def test_progress(self):
        s = F.load_spec(os.path.join(HERE, "specs", "ddrescue.toml"))
        self.assertEqual(F.progress_of(s, "pct rescued:   12.5%, read errors: 0\r pct rescued:   13.0%"), 13.0)
        self.assertIsNone(F.progress_of(s, "nothing yet"))

    def test_disks(self):
        d = F.disks(LSBLK)
        self.assertEqual([x["path"] for x in d], ["/dev/sda", "/dev/sdb"])         # no zram, no loop
        self.assertIn("Samsung SSD 870 · 500 GB", d[0]["label"])
        self.assertTrue(d[0]["ro"])
        self.assertIn("USB", d[1]["label"])
        self.assertIn("Unnamed drive", d[1]["label"])

    def test_launcher_and_quoting(self):
        s = F.load_spec(os.path.join(HERE, "specs", "speed-test.toml"))
        self.assertIn("Exec=sysmedic-forms speed-test", F.launcher(s))
        self.assertIn("X-SysMedic-NetworkandWiFi", F.launcher(s))
        self.assertEqual(F.shown(["a", "b c", "d'e"]), "a 'b c' 'd'\\''e'")


if __name__ == "__main__":
    unittest.main()
