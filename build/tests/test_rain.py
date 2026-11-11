import os, pty, subprocess, sys, unittest
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "../staging/shared/usr/local/lib/sysmedic"))
import rain


class RainTests(unittest.TestCase):
    def test_deterministic_and_bounded(self):
        a, b = rain.Rain(40, 12, seed=1), rain.Rain(40, 12, seed=1)
        for _ in range(30):
            a.step(); b.step()
        self.assertEqual(a.frame(), b.frame())
        self.assertTrue(all(0 <= lv <= 5 for row in a.frame() for _, lv in row))
        self.assertTrue(any(lv for row in a.frame() for _, lv in row))

    def test_text_box_is_clear_of_rain(self):
        r = rain.Rain(80, 24, seed=3)
        box = rain.make_box(80, 24, ["Scanning"])
        fr = r.frame(box)
        r0, c0, lines = box
        w = max(len(l) for l in lines)
        for dr in range(len(lines)):
            for dc in range(w):
                ch, lv = fr[r0 + dr][c0 + dc]
                self.assertIn(lv, (0, 6, 7, 8))

    def test_runs_on_a_terminal_and_restores_it(self):
        m, s = pty.openpty()
        p = subprocess.Popen([sys.executable, rain.__file__, "--seconds", "0.5", "--palette"], stdin=s, stdout=s, stderr=s,
                             env=dict(os.environ, SYSMEDIC_VTRGB="/nonexistent"))
        os.close(s)
        buf = b""
        while True:                           # drain the terminal or the child blocks on a full buffer
            try:
                chunk = os.read(m, 65536)
            except OSError:
                break
            if not chunk:
                break
            buf += chunk
        p.wait(timeout=20)
        out = buf.decode(errors="replace")
        self.assertEqual(p.returncode, 0)
        self.assertIn("\033]R", out)          # palette put back
        self.assertIn("\033[?25h", out)       # cursor back

    def test_until_file_stops_once_the_file_exists(self):
        import tempfile, time
        with tempfile.TemporaryDirectory() as d:
            flag = os.path.join(d, "done")
            open(flag, "w").close()
            m, s = pty.openpty()
            t0 = time.time()
            p = subprocess.Popen([sys.executable, rain.__file__, "--until-file", flag, "--min", "0.6", "--palette"],
                                 stdin=s, stdout=s, stderr=s, env=dict(os.environ, SYSMEDIC_VTRGB="/nonexistent"))
            os.close(s)
            while True:                          # drain until the child closes the terminal
                try:
                    if not os.read(m, 65536):
                        break
                except OSError:
                    break
            p.wait(timeout=20)
            took = time.time() - t0
            self.assertEqual(p.returncode, 0)
            self.assertGreaterEqual(took, 0.55)  # honours --min even though the file is already there
            self.assertLess(took, 8)

    def _with_rain(self, extra_env=None, keys=None):
        import tempfile
        wrapper = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../staging/shared/usr/local/bin/sysmedic-with-rain")
        with tempfile.TemporaryDirectory() as d:
            job = os.path.join(d, "job.sh")
            with open(job, "w") as f:
                f.write("#!/bin/bash\nsleep 1\nprintf 'FINDING one\\nFINDING two\\n'\nexit 3\n")
            os.chmod(job, 0o755)
            env = dict(os.environ, SYSMEDIC_RAIN=rain.__file__, SYSMEDIC_RAIN_STATE=d, SYSMEDIC_RAIN_MIN="1",
                       SYSMEDIC_VTRGB="/nonexistent", SYSMEDIC_NO_RAIN=os.path.join(d, "off"), TERM="linux")
            env.update(extra_env or {})
            m, s = pty.openpty()
            p = subprocess.Popen([wrapper, "--status", "Scanning", "--", job], stdin=s, stdout=s, stderr=s, env=env)
            os.close(s)
            buf = b""
            while True:
                try:
                    chunk = os.read(m, 65536)
                except OSError:
                    break
                if not chunk:
                    break
                buf += chunk
            p.wait(timeout=30)
            return p.returncode, buf.decode(errors="replace"), d

    def test_with_rain_shows_rain_then_the_jobs_output_and_keeps_its_exit_code(self):
        rc, out, _ = self._with_rain()
        self.assertEqual(rc, 3)
        self.assertIn("\033]P", out)                    # the rain drew
        self.assertTrue(out.rstrip().endswith("FINDING two"), out[-80:])   # and the findings are what is left on screen

    def test_with_rain_can_be_turned_off(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            off = os.path.join(d, "off")
            open(off, "w").close()
            rc, out, _ = self._with_rain({"SYSMEDIC_NO_RAIN": off})
        self.assertEqual(rc, 3)
        self.assertNotIn("\033]P", out)
        self.assertIn("FINDING one", out)

    def test_refuses_without_terminal(self):
        p = subprocess.run([sys.executable, rain.__file__], stdin=subprocess.DEVNULL, capture_output=True)
        self.assertNotEqual(p.returncode, 0)


if __name__ == "__main__":
    unittest.main()
