"""Tutorials: every lesson parses, teaches only real commands, and can never make the runner start a repair."""
import os
import pty
import re
import select
import subprocess
import sys
import unittest

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
LESSONS = os.path.join(REPO, "docs/tutorials")
SHARED = os.path.join(REPO, "build/staging/shared")
TOOL = os.path.join(SHARED, "usr/local/bin/sysmedic-learn")
sys.path.insert(0, os.path.join(SHARED, "usr/local/lib/sysmedic"))
import lessons  # noqa: E402

ALIASES = {"sysmedic-unlock", "sysmedic-lock"}        # symlinks to sysmedic-guard, made by sysmedic-deploy


def installed_tools():
    names = set(ALIASES)
    for d in ("usr/local/bin", "usr/local/sbin"):
        names.update(os.listdir(os.path.join(SHARED, d)))
    return names


class Lessons(unittest.TestCase):
    def setUp(self):
        self.cat = lessons.catalogue(LESSONS)

    def test_there_are_lessons_and_each_is_complete(self):
        self.assertGreaterEqual(len(self.cat), 7)
        for l in self.cat:
            for key in ("title", "summary", "time", "level"):
                self.assertTrue(l.get(key), f"{l['path']}: no {key}")
            self.assertIn(l["level"], ("beginner", "standard", "engineer"))
            self.assertGreaterEqual(len(l["steps"]), 3, l["path"])
            for s in l["steps"]:
                self.assertTrue("".join(s["body"]).strip(), f"{l['id']}: empty step {s['title']}")

    def test_run_blocks_are_read_only(self):
        for l in self.cat:
            for s in l["steps"]:
                for kind, text in s["blocks"]:
                    self.assertIn(kind, ("run", "cmd"), f"{l['id']}: unknown block kind {kind}")
                    if kind == "run":
                        self.assertTrue(lessons.run_allowed(text.strip()), f"{l['id']}: `{text}` is not allowed to run")

    def test_the_run_list_itself_is_read_only(self):
        for cmd in lessons.RUN_ALLOWED:
            self.assertNotIn(cmd[0], ("sysmedic-unlock", "sysmedic-win", "ddrescue", "sysmedic-guard", "sysmedic-note"))

    def test_lessons_name_only_real_tools(self):
        have = installed_tools()
        for l in self.cat:
            for s in l["steps"]:
                texts = [t for _, t in s["blocks"]] + [x for x in re.findall(r"`([^`]+)`", " ".join(s["body"]))]
                for t in texts:
                    for line in t.splitlines():
                        words = line.split()
                        if words and words[0].startswith("sysmedic-"):
                            self.assertIn(words[0], have, f"{l['id']}: `{words[0]}` is not a SysMedic tool")

    def test_ids_are_unique_and_numbered_in_order(self):
        ids = [l["id"] for l in self.cat]
        self.assertEqual(len(ids), len(set(ids)))
        nums = [int(os.path.basename(l["path"]).split("-")[0]) for l in self.cat]
        self.assertEqual(nums, sorted(nums))


class Runner(unittest.TestCase):
    def run_tool(self, *args, **kw):
        env = dict(os.environ, SYSMEDIC_LESSONS=LESSONS)
        return subprocess.run([sys.executable, TOOL, *args], capture_output=True, text=True, env=env, timeout=30,
                              stdin=subprocess.DEVNULL, **kw)

    def test_print_is_plain_text_without_markup(self):
        out = self.run_tool("--print", "bitlocker").stdout
        self.assertIn("Step 1 of", out)
        self.assertNotIn("**", out)
        self.assertNotIn("\033", out)
        self.assertNotIn("\0", out)

    def test_unknown_lesson_is_an_error(self):
        self.assertNotEqual(self.run_tool("--print", "no-such-lesson").returncode, 0)

    def test_needs_a_terminal(self):
        self.assertNotEqual(self.run_tool("first").returncode, 0)

    def test_only_run_blocks_are_offered_for_running(self):
        text = self.run_tool("--print", "repair").stdout
        self.assertEqual(text.count("safe to run"), 2)          # the two scans
        unlock = text.index("sysmedic-unlock")
        self.assertIn("type it yourself", text[unlock - 120:unlock])

    def test_walks_a_lesson_on_a_terminal(self):
        m, s = pty.openpty()
        env = dict(os.environ, SYSMEDIC_LESSONS=LESSONS, TERM="xterm")
        p = subprocess.Popen([sys.executable, TOOL, "get-online"], stdin=s, stdout=s, stderr=s, env=env)
        os.close(s)
        buf = b""

        def until(marker):                         # keys only go in once the screen they answer has been drawn
            nonlocal buf
            while marker.encode() not in buf:
                if not select.select([m], [], [], 15)[0]:
                    self.fail(f"never saw {marker!r}")
                buf += os.read(m, 65536)

        until("Step 1 of")
        os.write(m, b"\r")                         # next step
        until("Step 2 of")
        os.write(m, b"b")                          # back
        until("Step 1 of")
        os.write(m, b"q")                          # quit
        p.wait(timeout=20)
        self.assertEqual(p.returncode, 0)
        out = buf.decode(errors="replace")
        self.assertIn("Step 1 of", out)
        self.assertIn("Step 2 of", out)


if __name__ == "__main__":
    unittest.main()
