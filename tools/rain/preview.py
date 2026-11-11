#!/usr/bin/env python3
"""preview.py OUT.png [--calm] [--seed N] — one rain frame as a PNG (for review without a screen)."""
import sys
from PIL import Image, ImageDraw, ImageFont
import rain

FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
COLS, ROWS, CW, CH = 100, 34, 12, 22


def main():
    out = sys.argv[1]
    seed = int(sys.argv[sys.argv.index("--seed") + 1]) if "--seed" in sys.argv else 7
    r = rain.Rain(COLS, ROWS, seed=seed, calm="--calm" in sys.argv)
    for _ in range(40):
        r.step()
    box = rain.make_box(COLS, ROWS, ["Scanning this PC…", "Customer disks are write-protected."])
    img = Image.new("RGB", (COLS * CW, ROWS * CH), (3, 8, 5))
    d = ImageDraw.Draw(img)
    f = ImageFont.truetype(FONT, 18)
    for y, row in enumerate(r.frame(box)):
        for x, (ch, lv) in enumerate(row):
            if ch != " ":
                d.text((x * CW, y * CH), ch, font=f, fill=(235, 255, 240) if lv == 6 else rain.RGB[lv])
    img.save(out)


main()
