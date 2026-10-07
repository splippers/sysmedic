#!/usr/bin/env python3
"""logo — SYSMEDIC in block letters (half blocks, 3 text rows), cyan→blue, with a tagline beside it.

  logo.py [--animate] [--tagline LINE]...     up to three tagline lines, printed to the right of the logo

--animate reveals it left to right behind a bright scan line (about half a second). Needs SysMedic's console
font for ▀ ▄ █ and the SysMedic Night palette for the colours (/etc/sysmedic/vtrgb).
"""
import os
import sys
import time

LETTERS = {
    "S": [".####", "#....", ".###.", "....#", "....#", "####."],
    "Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#.."],
    "M": ["#...#", "##.##", "#.#.#", "#...#", "#...#", "#...#"],
    "E": ["#####", "#....", "####.", "#....", "#....", "#####"],
    "D": ["####.", "#...#", "#...#", "#...#", "#...#", "####."],
    "I": ["#####", "..#..", "..#..", "..#..", "..#..", "#####"],
    "C": [".####", "#....", "#....", "#....", "#....", ".####"],
}
WORD = "SYSMEDIC"
# bright cyan → cyan → bright blue → blue (palette 14, 6, 12, 4)
GRADIENT = ["1;36", "1;36", "0;36", "0;36", "1;34", "1;34", "0;34", "0;34"]


def cells():
    """[(row, col, char, colour)] for the 3 text rows of the logo."""
    out = []
    col = 0
    for i, ch in enumerate(WORD):
        g = LETTERS[ch]
        for x in range(5):
            for r in range(3):
                top, bot = g[2 * r][x] == "#", g[2 * r + 1][x] == "#"
                c = "█" if top and bot else "▀" if top else "▄" if bot else " "
                out.append((r, col + x, c, GRADIENT[i]))
        col += 6
    return out, col - 1


def render(tagline, color=True, upto=None, scan=None):
    grid, width = cells()
    rows = [[" "] * width for _ in range(3)]
    for r, c, ch, colour in grid:
        if upto is not None and c > upto:
            continue
        rows[r][c] = (f"\033[{colour}m{ch}\033[0m" if color and ch != " " else ch)
    if scan is not None and scan < width:
        for r in range(3):
            rows[r][scan] = "\033[1;37m▐\033[0m" if color else "|"
    lines = []
    for r in range(3):
        tag = tagline[r] if r < len(tagline) else ""
        lines.append("  " + "".join(rows[r]) + "   " + tag)
    return lines


def main():
    args = sys.argv[1:]
    tagline = [args[i + 1] for i, a in enumerate(args) if a == "--tagline" and i + 1 < len(args)]
    color = sys.stdout.isatty() and not os.environ.get("NO_COLOR")
    _, width = cells()
    if "--animate" in args and color:
        print("\n\n")
        for x in range(0, width + 3, 2):
            sys.stdout.write("\033[3A\r" + "\n".join(render(tagline if x >= width else [], color, upto=x, scan=x + 1)) + "\n")
            sys.stdout.flush()
            time.sleep(0.018)
        sys.stdout.write("\033[3A\r" + "\n".join(render(tagline, color)) + "\n")
    else:
        print("\n".join(render(tagline, color)))


if __name__ == "__main__":
    main()
