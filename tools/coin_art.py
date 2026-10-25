#!/usr/bin/env python3
"""The coins in your bag (`CoinsTile`): RuneScape's coin piles, a bigger one the more you carry, drawn
with tools/pixel_kit.py as item icons are (32 × 32, the house outline, docs/pixel-style.md):

    item_coins_1   one coin            (under 5)
    item_coins_2   a few, scattered    (under 100)
    item_coins_3   a stack and a few   (under 10,000)
    item_coins_4   a heap              (from 10,000)

Each coin is a gold disc seen from above and a little in front: its rim a deeper gold under its face,
its face lit on the upper left with a stamped star. Coins lie back to front, so the nearer ones cover
the farther.

    python3 tools/coin_art.py                 # all four → art/sprites/item_coins_<n>.png
    python3 tools/coin_art.py --sheet out.png # a contact sheet at 6×
"""

import math
import pathlib
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from pixel_kit import Material, Sprite  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPRITES = ROOT / "art" / "sprites"

FACE = Material("#f2c444", shades=5, texture=0.02, gloss=0.6)
RIM = Material("#b07a1c", shades=5, texture=0.02)
STAMP = Material("#c8902a", shades=4, texture=0.0, relief=0.0)


def coin(s, cx, cy, r=5.0, tilt=0.5, thick=1.6):
    """One coin lying flat at (cx, cy), `r` across its face, seen at `tilt` (its depth over its width)."""
    s.ellipse(cx, cy + thick, r, r * tilt, RIM, profile="flat")
    s.ellipse(cx, cy, r, r * tilt, FACE)
    if r >= 4:
        star = [(cx + 0.45 * r * math.cos(math.pi / 2 + k * math.pi / 5) * (1 if k % 2 == 0 else 0.45),
                 cy - 0.45 * r * tilt * math.sin(math.pi / 2 + k * math.pi / 5) * (1 if k % 2 == 0 else 0.45)) for k in range(10)]
        s.poly(star, STAMP, profile="flat", tone=0.35)


def stack(s, cx, base, count, r=5.0):
    """A stack of `count` coins, the bottom one at `base`."""
    for k in range(count):
        coin(s, cx + (0.5 if k % 2 else -0.3), base - k * 1.8, r)


def drawings():
    def one():
        s = Sprite(32)
        coin(s, 16, 14.5, r=12, tilt=0.6, thick=3)
        return s

    def few():
        s = Sprite(32)
        for cx, cy in ((11, 12), (21, 14), (14, 20), (23, 22)):
            coin(s, cx, cy, r=6)
        return s

    def stacked():
        s = Sprite(32)
        stack(s, 10, 26, 6, r=7)
        coin(s, 25, 17, r=5.5)
        coin(s, 24.5, 26, r=5.5)
        return s

    def heap():
        # A pyramid of coins lying every which way: the widest row at the back of the floor, each row
        # higher and narrower, so it reads as a pile of coins, not a lump of gold.
        s = Sprite(32)
        for row, (y, n) in enumerate(((27, 5), (23.5, 4), (20, 3), (16.5, 2), (13, 1))):
            span = n * 5.6
            for k in range(n):
                coin(s, 16 - span / 2 + (k + 0.5) * span / n + (0.6 if row % 2 else -0.4), y, r=3.6, thick=1.2)
        return s

    return {"item_coins_1": one, "item_coins_2": few, "item_coins_3": stacked, "item_coins_4": heap}


def main(argv):
    sheet = None
    if "--sheet" in argv:
        i = argv.index("--sheet")
        sheet = argv[i + 1]
    out = {}
    for name, draw in drawings().items():
        img = draw().render(outline="house")
        img.save(SPRITES / f"{name}.png")
        out[name] = img
    print(f"wrote {len(out)} coin piles to art/sprites/")
    if sheet:
        k = 6
        board = Image.new("RGBA", (len(out) * 34 * k, 34 * k), (74, 60, 46, 255))
        for n, img in enumerate(out.values()):
            board.alpha_composite(img.resize((32 * k, 32 * k), Image.NEAREST), (n * 34 * k + k, k))
        board.save(sheet)
        print(f"sheet in {sheet}")


if __name__ == "__main__":
    main(sys.argv[1:])
