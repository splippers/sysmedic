#!/usr/bin/env python3
"""rain — SysMedic's green text rain (prototype), for idle and boot screens.

  rain.py [--status LINE]... [--seconds N] [--until-file FILE [--min N] [--hold]] [--calm] [--palette]

With --until-file it plays until that file exists (at least --min seconds), for covering a job that takes a
while; a key press stops it early. Draws falling green glyphs with the SYSMEDIC logo and your status lines in a clear box on top: the rain never runs
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
import subprocess
import sys
import termios
import time
import tty

LOGO_ROWS = 3
GLYPHS = "0123456789ABCDEFXZ:<>=+*#$%&"
# Levels, dim to bright: 1 faint tail, 2 dark green, 3 green, 4 bright green, 5 head (near white);
# in a frame 6 is status text, 7 the logo (bright green), 8 the logo highlight
RGB = {1: (0, 64, 28), 2: (0, 120, 48), 3: (0, 190, 70), 4: (60, 255, 110), 5: (215, 255, 225)}
# Console slots remapped for the rain (slot, level); the SysMedic Night palette's own greens are mint, not rain green
SLOTS = {1: 8, 2: 2, 3: 10, 4: 12, 5: 15}   # 16-colour fallback: only 5 usable levels, bright ones use bold-less slots


class Rain:
    def __init__(self, cols, rows, seed=None, calm=False):
        self.cols, self.rows, self.calm = cols, rows, calm
        self.rng = random.Random(seed)
        self.drops = [None] * cols
        self.t = 0
        self.glyph = [[self.rng.choice(GLYPHS) for _ in range(cols)] for _ in range(rows)]
        for _ in range(rows * 2):            # run it in so the first frame is already raining
            self.step()

    def _spawn(self, c):
        r = self.rng
        n = r.randint(8, max(9, self.rows))
        return {"y": float(-r.randint(0, self.rows)), "v": r.uniform(0.25, 0.6) if self.calm else r.uniform(0.5, 1.4), "n": n}

    def step(self):
        self.t += 1
        for c in range(self.cols):
            d = self.drops[c]
            if d is None:
                if self.rng.random() < (0.012 if self.calm else 0.045):
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
            top, bot, left, right = r0 - 1, r0 + len(lines), c0 - 3, c0 + w + 2
            for r in range(top, bot + 1):                    # clear the box, then draw its frame
                for c in range(left, right + 1):
                    if 0 <= r < self.rows and 0 <= c < self.cols:
                        edge_r, edge_c = r in (top, bot), c in (left, right)
                        ch = " "
                        if edge_r or edge_c:
                            ch = {(True, True): "┌┐└┘"[(r == bot) * 2 + (c == right)]}.get((edge_r, edge_c), "─" if edge_r else "│")
                        out[r][c] = (ch, 3 if ch != " " else 0)
            sweep = (self.t * 2) % (w + 24) - 12             # a highlight crossing the logo every few seconds
            for i, l in enumerate(lines):
                for j, ch in enumerate(l):
                    if ch != " " and 0 <= r0 + i < self.rows and 0 <= c0 + j < self.cols:
                        if i < LOGO_ROWS:
                            lv = 8 if abs(j - sweep) < 3 else 7
                        else:
                            lv = 6
                        out[r0 + i][c0 + j] = (ch, lv)
        return out


def logo_lines():
    """The three-row SYSMEDIC from logo.py (half blocks)."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
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


def sgr(lv, truecolor):
    if lv == 0:
        return "\033[0m"
    if lv == 6:
        return "\033[1;97m" if truecolor else "\033[1;37m"
    lv = {7: 4, 8: 5}.get(lv, lv)
    return ("\033[1;38;2;%d;%d;%dm" % RGB[lv]) if truecolor else "\033[1;38;5;%dm" % SLOTS[lv]


def paint(fr, truecolor, prev=None):
    """The frame as terminal output. With the previous frame only the cells that changed are sent: the console
    records its output (the visit transcript), so a full redraw every tenth of a second would fill it with rain."""
    s = []
    for r, row in enumerate(fr):
        cur, c = None, 0
        while c < len(row):
            if prev is not None and prev[r][c] == row[c]:
                c += 1
                continue
            s.append("\033[%d;%dH" % (r + 1, c + 1))
            while c < len(row) and (prev is None or prev[r][c] != row[c]):
                ch, lv = row[c]
                if lv != cur:
                    cur = lv
                    s.append(sgr(lv, truecolor))
                s.append(ch)
                c += 1
    s.append("\033[0m")
    return "".join(s)


def set_palette(on):
    if on:
        for lv, slot in SLOTS.items():
            sys.stdout.write("\033]P%X%02X%02X%02X" % ((slot,) + RGB[lv]))
    else:
        sys.stdout.write("\033]R")     # back to the default palette, then SysMedic Night if this drive has it
        sys.stdout.flush()
        vt = os.environ.get("SYSMEDIC_VTRGB", "/etc/sysmedic/vtrgb")
        if os.path.exists(vt) and shutil.which("setvtrgb"):
            subprocess.run(["setvtrgb", vt], stderr=subprocess.DEVNULL)
    sys.stdout.flush()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--status", action="append", default=[])
    ap.add_argument("--seconds", type=float, default=0)
    ap.add_argument("--until-file")
    ap.add_argument("--min", type=float, default=3)
    ap.add_argument("--max", type=float, default=25)      # with --until-file: give up waiting (the job hung) after this long
    ap.add_argument("--hold", action="store_true")        # with --until-file: once the job is done, wait for a key press
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
        start = time.time()
        end = start + (a.seconds or (a.max if a.until_file else 0)) or None
        prev = None
        holding = False
        while True:
            now = time.time()
            ready = bool(a.until_file and os.path.exists(a.until_file) and now - start >= a.min)
            if ready and a.hold and not holding:
                holding = True                     # job finished: keep the rain and ask for a key
                box = make_box(cols, rows, list(a.status or []) + ["", "Press any key to continue"])
            if ready and not a.hold:
                break
            if end is not None and now >= end and not holding:
                break
            rain.step()
            frame = rain.frame(box)
            sys.stdout.write(paint(frame, truecolor, prev))
            prev = frame
            sys.stdout.flush()
            if select.select([sys.stdin], [], [], 0.09 if not a.calm else 0.16)[0]:
                try:
                    os.read(fd, 1024)              # eat the key so it does not reach the next prompt
                except OSError:
                    pass
                if holding or not a.hold:          # in hold mode a key before the job ends is ignored
                    break
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)
        if not truecolor:
            set_palette(False)
        sys.stdout.write("\033[0m\033[?25h\033[2J\033[H")


if __name__ == "__main__":
    main()
