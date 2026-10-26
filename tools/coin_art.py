#!/usr/bin/env python3
"""The coins in your bag (`CoinsTile`): RuneScape's coin piles, a bigger one the more you carry, drawn
with tools/pixel_kit.py in the item icons' clean look (64 × 64, RD's Potion: docs/pixel-style.md, *Item
icons*):

    item_coins_1   one coin            (under 5)
    item_coins_2   a few, scattered    (under 100)
    item_coins_3   a stack and a few   (under 10,000)
    item_coins_4   a heap              (from 10,000)

Each coin is a gold disc seen from above and a little in front: its edge a deeper gold under its face, the
face a raised rim round a sunken field with a star struck in it, lit on the upper left, with a streak of
shine along the rim there. Coins lie back to front, so the nearer ones cover the farther. Playtesting
2026-10-26 ("items like the coins don't look nice"): at 32 pixels in the grained finish and the house
outline they read as lumps of brass in a thick dark border.

    python3 tools/coin_art.py                 # all four → art/sprites/item_coins_<n>.png
    python3 tools/coin_art.py --sheet out.png # a contact sheet at 4×
"""

import math
import random
import pathlib
import sys

from PIL import Image

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from pixel_kit import Material, Sprite  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPRITES = ROOT / "art" / "sprites"


def gold(base, shades=7, gloss=0.0, relief=1.0):
    return Material(base, shades=shades, texture=0, variety=0, gloss=gloss, relief=relief, wide=True)


EDGE = gold("#b8741a", shades=6)      # the coin's milled edge, under its face
RIM = gold("#f2bf3a")                 # the raised rim round the face
FIELD = gold("#dc9e26")               # the sunken field inside it
SUNK = gold("#c4861e", shades=4, relief=0.0)   # the rim's shadow on the field, on its upper left
STAMP = gold("#f6cc4c", shades=5)     # the star struck in the field, standing up from it
MOUND = gold("#c88a22", shades=6)      # the heap's body, under the coins strewn on it
SHINE = gold("#fff3c4", shades=3, relief=0.0)


def coin(s, cx, cy, r=10.0, tilt=0.55, thick=3.0):
    """One coin lying flat at (cx, cy), `r` across its face, seen at `tilt` (its depth over its width)."""
    s.part()
    s.ellipse(cx, cy + thick, r, r * tilt, EDGE, profile="flat")
    s.ellipse(cx, cy, r, r * tilt, RIM)
    rim = max(1.4, r * 0.16)
    if r >= 5:
        # Sunken: the rim shades the field's upper left, so a crescent of shadow shows there.
        s.ellipse(cx, cy, r - rim, (r - rim) * tilt, SUNK, profile="flat")
        lip = max(0.8, r * 0.05)
        s.ellipse(cx + lip, cy + lip * tilt, r - rim - lip * 0.6, (r - rim - lip * 0.6) * tilt, FIELD, bulge=0.4)
    if r >= 8:
        k = 0.5 * r
        star = [(cx + k * math.cos(math.pi / 2 + i * math.pi / 5) * (1 if i % 2 == 0 else 0.45),
                 cy - k * tilt * math.sin(math.pi / 2 + i * math.pi / 5) * (1 if i % 2 == 0 else 0.45)) for i in range(10)]
        s.poly(star, STAMP, bulge=0.5)
    # The shine: a short streak along the rim's upper left, where it faces the light.
    a0, a1 = math.radians(195), math.radians(250)
    mid = r - rim / 2
    pts = [(cx + mid * math.cos(a0 + (a1 - a0) * t / 8), cy + mid * tilt * math.sin(a0 + (a1 - a0) * t / 8))
           for t in range(9)]
    if r >= 5:
        s.stroke(pts, max(1.1, rim * 0.55), SHINE, profile="flat")


def stack(s, cx, base, count, r=10.0):
    """A stack of `count` coins, the bottom one at `base`: only the top one's face shows, the rest are edges."""
    for k in range(count):
        x, y = cx + (0.8 if k % 2 else -0.6), base - k * 3.2
        if k < count - 1:
            s.part()
            s.ellipse(x, y + 3, r, r * 0.55, EDGE, profile="flat")
            s.ellipse(x, y, r, r * 0.55, EDGE, bulge=0.3)
        else:
            coin(s, x, y, r)


def drawings():
    def one():
        s = Sprite.clean(64)
        coin(s, 32, 29, r=26, tilt=0.62, thick=6)
        return s

    def few():
        s = Sprite.clean(64)
        for cx, cy in ((21, 22), (43, 25), (25, 39), (45, 44)):
            coin(s, cx, cy, r=12.5, thick=3.5)
        return s

    def stacked():
        s = Sprite.clean(64)
        stack(s, 21, 52, 7, r=14)
        coin(s, 48, 32, r=11, thick=3)
        coin(s, 47, 50, r=11.5, thick=3)
        return s

    def heap():
        # A mound of gold, coins strewn over it at odd angles and a few spilt at its foot, so it reads as
        # a heap of coins (a wall of rows read as bricks, 2026-10-26; packed tight, as cracked rock).
        s = Sprite.clean(64)
        s.ellipse(32, 42, 27, 19, MOUND, bulge=1.4)
        rng = random.Random(5)
        for x, y in ((32, 27), (22, 32), (42, 33), (14, 41), (31, 39), (50, 42), (22, 47), (41, 48)):
            coin(s, x + rng.uniform(-1, 1), y + rng.uniform(-1, 1), r=rng.uniform(6.6, 7.6),
                 tilt=rng.uniform(0.48, 0.66), thick=1.8)
        for cx, cy, r in ((13, 54, 7.0), (51, 55, 7.4), (31, 56, 8.0)):
            coin(s, cx, cy, r=r, thick=2.4)
        return s

    return {"item_coins_1": one, "item_coins_2": few, "item_coins_3": stacked, "item_coins_4": heap}


def main(argv):
    sheet = None
    if "--sheet" in argv:
        i = argv.index("--sheet")
        sheet = argv[i + 1]
    out = {}
    for name, draw in drawings().items():
        img = draw().render(outline="deep")
        img.save(SPRITES / f"{name}.png")
        out[name] = img
    print(f"wrote {len(out)} coin piles to art/sprites/")
    if sheet:
        k = 4
        board = Image.new("RGBA", (len(out) * 66 * k, 66 * k), (74, 60, 46, 255))
        for n, img in enumerate(out.values()):
            board.alpha_composite(img.resize((64 * k, 64 * k), Image.NEAREST), (n * 66 * k + k, k))
        board.save(sheet)
        print(f"sheet in {sheet}")


if __name__ == "__main__":
    main(sys.argv[1:])
