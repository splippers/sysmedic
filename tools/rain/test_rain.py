import os, pty, subprocess, sys, unittest
sys.path.insert(0, os.path.dirname(__file__))
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
                self.assertIn(lv, (0, 6))

    def test_runs_on_a_terminal_and_restores_it(self):
        m, s = pty.openpty()
        p = subprocess.Popen([sys.executable, rain.__file__, "--seconds", "0.5", "--palette"], stdin=s, stdout=s, stderr=s)
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

    def test_refuses_without_terminal(self):
        p = subprocess.run([sys.executable, rain.__file__], stdin=subprocess.DEVNULL, capture_output=True)
        self.assertNotEqual(p.returncode, 0)


if __name__ == "__main__":
    unittest.main()
