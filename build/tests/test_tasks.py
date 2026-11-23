"""Guided jobs (sysmedic-task): each job is complete, runs only safe commands, and is reachable from the menu."""
import importlib.machinery
import importlib.util
import os
import re
import subprocess
import sys
import unittest

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
TASKS = os.path.join(REPO, "docs/tasks")
SHARED = os.path.join(REPO, "build/staging/shared")
TOOL = os.path.join(SHARED, "usr/local/bin/sysmedic-task")
sys.path.insert(0, os.path.join(SHARED, "usr/local/lib/sysmedic"))
import lessons  # noqa: E402

_loader = importlib.machinery.SourceFileLoader("sysmedic_task", TOOL)
task = importlib.util.module_from_spec(importlib.util.spec_from_loader("sysmedic_task", _loader))
_loader.exec_module(task)


class Jobs(unittest.TestCase):
    def setUp(self):
        self.cat = task.catalogue(TASKS)

    def test_jobs_are_complete(self):
        self.assertGreaterEqual(len(self.cat), 3)
        for t in self.cat:
            for key in ("title", "summary", "when"):
                self.assertTrue(t.get(key), f"{t['path']}: no {key}")
            self.assertIn(t["risk"], task.RISK, t["path"])
            self.assertGreaterEqual(len(t["steps"]), 3, t["path"])
            for s in t["steps"]:
                self.assertTrue("".join(s["body"]).strip(), f"{t['id']}: empty step {s['title']}")

    def test_run_blocks_are_safe_and_real(self):
        tools = set(os.listdir(os.path.join(SHARED, "usr/local/bin"))) | set(os.listdir(os.path.join(SHARED, "usr/local/sbin")))
        tools |= {"lsblk", "sysmedic-lock", "sysmedic-unlock"}
        for t in self.cat:
            for s in t["steps"]:
                for kind, text in s["blocks"]:
                    self.assertIn(kind, ("run", "cmd"))
                    if kind == "run":
                        self.assertTrue(lessons.run_allowed(text.strip()), f"{t['id']}: {text!r} is not on the safe list")
                    self.assertIn(text.split()[0], tools, f"{t['id']}: {text.split()[0]} is not a SysMedic tool")

    def test_read_only_jobs_never_show_write_commands(self):
        for t in self.cat:
            if t["risk"] == "read-only":
                self.assertEqual([k for s in t["steps"] for k, _ in s["blocks"] if k == "cmd"], [], t["id"])

    def test_menu_numbers_quoted_in_jobs_exist(self):
        menu = open(os.path.join(SHARED, "usr/local/lib/sysmedic/menuview.py")).read()
        keys = set(re.findall(r'\("([0-9A-Z]+)",', menu))
        for t in self.cat:
            for s in t["steps"]:
                for n in re.findall(r"menu \*\*([0-9A-Z]+)\*\*", " ".join(s["body"])):
                    self.assertIn(n, keys, f"{t['id']}: menu {n} does not exist")

    def test_menu_starts_jobs(self):
        self.assertIn("sysmedic-task", open(os.path.join(SHARED, "opt/sysmedic/rescue-menu.sh")).read())
        self.assertIn('("S",', open(os.path.join(SHARED, "usr/local/lib/sysmedic/menuview.py")).read())

    def test_print_mode_reads_every_job(self):
        r = subprocess.run([sys.executable, "-I", TOOL, "--print"], capture_output=True, text=True,
                           env={"SYSMEDIC_TASKS": TASKS, "PATH": os.environ["PATH"]})
        self.assertEqual(r.returncode, 0, r.stderr)
        for t in self.cat:
            self.assertIn(t["title"], r.stdout)

    def test_unknown_job_is_refused(self):
        r = subprocess.run([sys.executable, "-I", TOOL, "nonsense"], capture_output=True, text=True,
                           env={"SYSMEDIC_TASKS": TASKS, "PATH": os.environ["PATH"]})
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("No job matching", r.stderr)


if __name__ == "__main__":
    unittest.main()
