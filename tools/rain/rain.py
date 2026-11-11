#!/usr/bin/env python3
"""rain — SysMedic's green text rain (prototype), for idle and boot screens.

  rain.py [--status LINE]... [--seconds N] [--calm] [--palette]

Draws falling green glyphs with the SYSMEDIC logo and your status lines in a clear box on top: the rain never runs
behind text you need to read. Any key stops it. --calm slows it right down and thins it. Needs only Python; on the
Linux console (16 colours) it remaps a few palette slots for the greens and puts them back on exit (--palette forces
that on a terminal emulator too, which otherwise gets 24-bit colour).

The engine (Rain) knows nothing about terminals: preview.py draws its frames to PNG so it can be reviewed without a screen.
"""
import argparse
import os
import random
import select
import shutil
import sys
import termios
import time
import tty

GLYPHS = "0123456789ABCDEFXZ:<>=+*#$%&"
# Levels, dim to bright: 1 faint tail, 2 dark green, 3 green, 4 bright green, 5 head (near white)
RGB = {1: (0, 64, 28), 2: (0, 120, 48), 3: (0, 190, 70), 4: (60, 255, 110), 5: (215, 255, 225)}
# Console slots remapped for the rain (slot, level); the SysMedic Night palette's own greens are mint, not rain green
SLOTS = {1: 8, 2: 2, 3: 10, 4: 12, 5: 15}   # 16-colour fallback: only 5 usable levels, bright ones use bold-less slots


class Rain:
    def __init__(self, cols, rows, seed=None, calm=False):
        self.cols, self.rows, self.calm = cols, rows, calm
        self.rng = random.Random(seed)
        self.drops = [None] * cols
        self.glyph = [[self.rng.choice(GLYPHS) for _ in range(cols)] for _ in range(rows)]
        for _ in range(rows * 2):            # run it in so the first frame is already raining
            self.step()

    def _spawn(self, c):
        r = self.rng
        n = r.randint(6, max(7, self.rows - 2))
        return {"y": float(-r.randint(0, self.rows)), "v": r.uniform(0.25, 0.6) if self.calm else r.uniform(0.5, 1.4), "n": n}

    def step(self):
        for c in range(self.cols):
            d = self.drops[c]
            if d is None:
                if self.rng.random() < (0.01 if self.calm else 0.03):
                    self.drops[c] = self._spawn(c)
                continue
            d["y"] += d["v"]
            if d["y"] - d["n"] > self.rows:
                self.drops[c] = None
        for _ in range(max(1, self.cols * self.rows // (400 if self.calm else 120))):   # glyphs flicker
            self.glyph[self.rng.randrange(self.rows)][self.rng.randrange(self.cols)] = self.rng.choice(GLYPHS)

    def level(self, r, c):
        d = self.drops[c]
        if d is None:
            return 0
        back = d["y"] - r                    # rows behind the head
        if back < 0 or back > d["n"]:
            return 0
        if back < 1:
            return 5
        f = back / d["n"]
        return 4 if f < 0.15 else 3 if f < 0.45 else 2 if f < 0.8 else 1

    def frame(self, box=None):
        """rows × cols of (char, level); a box (r0, c0, lines) is cleared and drawn over the rain at level 6 (text)."""
        out = [[(self.glyph[r][c], self.level(r, c)) if self.level(r, c) else (" ", 0) for c in range(self.cols)]
               for r in range(self.rows)]
        if box:
            r0, c0, lines = box
            w = max(len(l) for l in lines)
            for dr in range(-1, len(lines) + 1):
                for dc in range(-3, w + 3):
                    if 0 <= r0 + dr < self.rows and 0 <= c0 + dc < self.cols:
                        out[r0 + dr][c0 + dc] = (" ", 0)
            for i, l in enumerate(lines):
                for j, ch in enumerate(l):
                    if ch != " " and 0 <= r0 + i < self.rows and 0 <= c0 + j < self.cols:
                        out[r0 + i][c0 + j] = (ch, 6)
        return out


def logo_lines():
    """The three-row SYSMEDIC from logo.py (half blocks)."""
    here = os.path.dirname(os.path.abspath(__file__))
    sys.path.insert(0, os.path.join(here, "../../build/staging/shared/usr/local/lib/sysmedic"))
    import logo
    cells, width = logo.cells()
    rows = [[" "] * width for _ in range(3)]
    for r, c, ch, _ in cells:
        rows[r][c] = ch
    return ["".join(r) for r in rows]


def make_box(cols, rows, status):
    lines = logo_lines() + [""] + list(status)
    w = max(len(l) for l in lines)
    lines = [l.center(w) for l in lines]
    return (max(1, (rows - len(lines)) // 2), max(0, (cols - w) // 2), lines)


def paint(fr, truecolor):
    s = ["\033[H"]
    for row in fr:
        cur = None
        for ch, lv in row:
            if lv != cur:
                cur = lv
                if lv == 0:
                    s.append("\033[0m")
                elif lv == 6:
                    s.append("\033[1;97m" if truecolor else "\033[1;37m")
                elif truecolor:
                    s.append("\033[38;2;%d;%d;%dm" % RGB[lv])
                else:
                    s.append("\033[38;5;%dm" % SLOTS[lv])
            s.append(ch)
        s.append("\033[0m\n")
    return "".join(s[:-1])


def set_palette(on):
    if on:
        for lv, slot in SLOTS.items():
            sys.stdout.write("\033]P%X%02X%02X%02X" % ((slot,) + RGB[lv]))
    else:
        sys.stdout.write("\033]R")     # reset to the system palette (SysMedic's own set again at next setvtrgb)
    sys.stdout.flush()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--status", action="append", default=[])
    ap.add_argument("--seconds", type=float, default=0)
    ap.add_argument("--calm", action="store_true")
    ap.add_argument("--palette", action="store_true")
    a = ap.parse_args()
    if not sys.stdout.isatty():
        sys.exit("rain: needs a terminal")
    truecolor = os.environ.get("COLORTERM") in ("truecolor", "24bit") and not a.palette and os.environ.get("TERM") != "linux"
    size = shutil.get_terminal_size((100, 30))
    cols, rows = size.columns, size.lines - 1
    rain = Rain(cols, rows, calm=a.calm)
    box = make_box(cols, rows, a.status or ["Starting up…"])
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    try:
        tty.setcbreak(fd)
        sys.stdout.write("\033[?25l\033[2J")
        if not truecolor:
            set_palette(True)
        end = time.time() + a.seconds if a.seconds else None
        while end is None or time.time() < end:
            rain.step()
            sys.stdout.write(paint(rain.frame(box), truecolor))
            sys.stdout.flush()
            if select.select([sys.stdin], [], [], 0.09 if not a.calm else 0.16)[0]:
                break
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)
        if not truecolor:
            set_palette(False)
        sys.stdout.write("\033[0m\033[?25h\033[2J\033[H")


if __name__ == "__main__":
    main()
