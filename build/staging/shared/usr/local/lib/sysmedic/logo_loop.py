#!/usr/bin/env python3
"""logo_loop — continuously animating SYSMEDIC logo for splash screen.

   logo_loop.py [--tagline LINE]...     up to three tagline lines
   Runs until SIGTERM/SIGINT.
"""

import os
import sys
import time
import signal

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
GRADIENT = ["1;36", "1;36", "0;36", "0;36", "1;34", "1;34", "0;34", "0;34"]

running = True
def signal_handler(signum, frame):
    global running
    running = False

signal.signal(signal.SIGTERM, signal_handler)
signal.signal(signal.SIGINT, signal_handler)


def cells():
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


def render(tagline, color=True, scan=None):
    grid, width = cells()
    rows = [[" "] * width for _ in range(3)]
    for r, c, ch, colour in grid:
        if color and ch != " ":
            rows[r][c] = f"\033[{colour}m{ch}\033[0m"
        else:
            rows[r][c] = ch
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

    print("\n\n")  # Space for animation
    sys.stdout.write("\033[?25l")  # Hide cursor
    sys.stdout.flush()

    frame = 0
    scan_pos = 0
    direction = 1

    while running:
        # Bouncing scan line animation
        scan_pos += direction * 3
        if scan_pos >= width + 10:
            scan_pos = width + 10
            direction = -1
        elif scan_pos <= -10:
            scan_pos = -10
            direction = 1

        lines = render(tagline, color, scan=scan_pos if 0 <= scan_pos < width else None)
        sys.stdout.write("\033[3A\r" + "\n".join(lines) + "\n")
        sys.stdout.flush()
        time.sleep(0.05)
        frame += 1

    sys.stdout.write("\033[?25h")  # Show cursor
    sys.stdout.write("\033[3A\r" + "\n".join(render(tagline, color)) + "\n")
    sys.stdout.flush()


if __name__ == "__main__":
    main()