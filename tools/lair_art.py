#!/usr/bin/env python3
"""The pieces of the bosses' lairs (maps.json, a boss's `lair`) that no sprite had: a standing stone,
a brazier, a gold hoard, a warning post and a junk throne, drawn in code with tools/pixel_kit.py in the
game's pixel style (docs/pixel-style.md), lit from the top left and outlined in a deep shade of each.

    python3 tools/lair_art.py                   # all → art/sprites/<id>.png
    python3 tools/lair_art.py brazier           # just these
    python3 tools/lair_art.py --sheet out.png   # a contact sheet at 4× on the meadow's green

Scored against RD's scenery: `python3 tools/pixel_style.py check --kind scenery art/sprites/<id>.png`.
"""

import math
import pathlib
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from pixel_kit import Material, Sprite  # noqa: E402
from scenery_art import SIDE_LIGHT, foliage, grounded, rng  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPRITES = ROOT / "art" / "sprites"


def scene(w=32, h=32):
    s = Sprite(w, h)
    s.light, s.rim, s.seams = SIDE_LIGHT, "lower", False
    return s


def standing_stone():
    """A tall grey standing stone, leaning a touch, a weathered rune cut in its face, moss at its foot."""
    s = scene(32, 48)
    stone, cut = Material("#8e8c96", texture=0.06), Material("#5a5866", texture=0.0)
    moss = foliage("#6a9a3e")
    s.poly([(10, 45), (9, 22), (11, 9), (16, 4), (21, 6), (23, 18), (24, 45)], stone, bulge=2.0)
    s.poly([(20, 45), (21, 22), (22, 12), (23, 18), (24, 45)], stone, profile="flat", tone=0.3)   # its shaded side
    for a, b in (((15, 16), (15, 26)), ((15, 21), (18, 18)), ((15, 21), (18, 24))):
        s.stroke([a, b], 1.0, cut, profile="flat")
    for x, y, r in ((11, 44, 3.2), (16, 45, 2.6), (22, 44.5, 2.8), (9, 41, 1.8)):
        s.ellipse(x, y, r, r * 0.6, moss[1 if x < 18 else 2])
    return s


def brazier():
    """A lit brazier: an iron bowl on three legs, a fire in it, burning at a lair's way in."""
    s = scene(32, 32)
    iron, rim = Material("#4e4a56", texture=0.03, gloss=0.4), Material("#6e6a78", texture=0.02)
    for a, b in (((12, 29), (14, 19)), ((20, 29), (18, 19)), ((16, 30), (16, 19))):
        s.stroke([a, b], 1.6, iron)
    s.ellipse(16, 18, 8, 4, iron)
    s.ellipse(16, 15.5, 8.5, 2.2, rim)
    s.ellipse(16, 15.5, 6.8, 1.5, Material("#2e2228", texture=0.0), profile="flat")
    flames = [Material(c, texture=0.0, relief=0.0) for c in ("#e8502a", "#ff9a30", "#ffe070")]
    for scale, mat in zip((1.0, 0.68, 0.38), flames):
        h, w = 12 * scale, 6.2 * scale
        s.poly([(16, 15 - h), (16 + w * 0.6, 15 - h * 0.5), (16 + w, 15), (16 - w, 15), (16 - w * 0.6, 15 - h * 0.55)], mat,
               profile="flat", tone=0.6)
    s.overlay = np.zeros((32, 32, 4), np.uint8)
    for x, y in ((12, 4), (20, 6), (16, 1)):
        s.overlay[y, x] = (255, 214, 96, 255)                       # sparks
    return s


def gold_hoard():
    """A heap of gold coins, a goblet and gems in it: a dragon's, or a greedy brute's. Coins lie on it
    in rows of flat discs, each lit along its top, so it reads as coins, not a lump of gold."""
    s = scene(32, 32)
    gold, deep = Material("#e8b630", texture=0.03, gloss=0.5), Material("#b8801a", texture=0.03)
    coin, coin_dark = Material("#f6d258", texture=0.0), Material("#c8901e", texture=0.0)
    s.ellipse(15, 25, 12, 5, deep)
    s.ellipse(14, 22.5, 9.5, 5.5, gold, bulge=1.4)
    r = rng(5)
    for y in (18.5, 21, 23.5, 26):
        half = 9 - abs(y - 21) * 1.2
        for x in np.arange(14 - half + r.uniform(0, 1.5), 14 + half, 2.6):
            s.ellipse(x, y, 1.3, 0.7, coin if x < 15 else coin_dark, profile="flat")
    for x, y in ((25, 27), (28, 28), (4, 28)):                       # coins spilled on the ground
        s.ellipse(x, y, 1.4, 0.8, coin, profile="flat")
    s.stroke([(24, 26), (24, 20)], 1.2, gold)                          # a goblet beside it
    s.poly([(21, 14), (27, 14), (26, 19), (22, 19)], gold)
    s.ellipse(24, 14, 3, 0.9, Material("#6a3e10", texture=0.0), profile="flat")
    s.ellipse(22.5, 26.5, 3, 0.9, gold, profile="flat")
    s.ellipse(9, 20, 1.6, 1.6, Material("#d8304a", texture=0.0, gloss=0.8))
    s.ellipse(17, 18, 1.5, 1.5, Material("#3ab0e0", texture=0.0, gloss=0.8))
    s.ellipse(13, 24.5, 1.4, 1.4, Material("#5ad070", texture=0.0, gloss=0.8))
    return s


def warning_post():
    """A warning on the way into a lair: a crooked stake, a cross-piece, a skull on top and a torn red
    rag hanging from it."""
    s = scene(32, 48)
    wood, bone, rag = Material("#7a5232", texture=0.07), Material("#e8e0cc", texture=0.03), Material("#b03030", texture=0.04)
    s.stroke([(16, 46), (15.5, 26), (16.5, 14)], 2.6, wood)
    s.stroke([(9, 22), (23, 20)], 2.0, wood)
    s.poly([(18, 21), (23, 20.5), (24, 30), (21, 27), (19, 31)], rag, bulge=0.8)
    s.ellipse(16.5, 10, 4.6, 4.0, bone)
    s.poly([(13.5, 12), (19.5, 12), (19, 15.5), (14, 15.5)], bone)
    dark = Material("#2a2026", texture=0.0)
    for x in (14.6, 18.4):
        s.ellipse(x, 10.4, 1.2, 1.3, dark, profile="flat")
    s.stroke([(15, 14.6), (18, 14.6)], 0.8, dark, profile="flat")
    return s


def junk_throne():
    """The Rat King's throne: a tall back of odd boards nailed together, a crate for a seat with a rag
    of a cushion, barrels for its arms, a dented pot for a crown on top, bones about its foot."""
    s = scene(32, 48)
    board, crate, barrel = Material("#9a6a3a", texture=0.07), Material("#8a5a30", texture=0.07), Material("#6e4428", texture=0.06)
    iron, cloth, bone = Material("#7a7884", texture=0.03, gloss=0.4), Material("#7a3a8a", texture=0.05), Material("#e2d8c2", texture=0.03)
    s.poly([(9.5, 36), (9.5, 16), (25, 17), (25, 36)], Material("#3a2a22", texture=0.0), profile="flat")
    for x, top, tone in ((9, 14, 0.62), (13, 8, 0.7), (17, 10, 0.58), (21, 15, 0.42)):    # the back, odd boards
        s.poly([(x, 36), (x, top + 1), (x + 1.6, top), (x + 3.2, top + 1.5), (x + 3.2, 36)], board, profile="flat", tone=tone)
    s.stroke([(8, 22), (26, 21)], 1.4, barrel, profile="flat")         # a crosspiece nailing them
    s.poly([(12, 8), (20, 8), (19, 3), (13, 3)], iron)                 # a dented pot for a crown
    s.ellipse(16, 8, 4.4, 1.2, iron)
    s.poly([(8, 46), (8, 35), (24, 35), (24, 46)], crate, profile="flat", tone=0.5)          # the seat
    s.stroke([(9, 40.5), (23, 40.5)], 0.9, barrel, profile="flat")
    s.ellipse(16, 35, 8.5, 2.4, cloth)                                 # a rag of a cushion
    for x in (6, 26):                                                  # barrels for its arms
        s.ellipse(x, 38, 3.6, 6.5, barrel)
        s.stroke([(x - 3.4, 36), (x + 3.4, 36)], 0.8, iron, profile="flat")
    for x, y in ((5, 47), (12, 47), (24, 47)):
        s.stroke([(x - 2, y), (x + 2, y - 1)], 1.1, bone)
        s.ellipse(x - 2.3, y, 0.9, 0.9, bone)
    return s


PROPS = {"standing_stone": standing_stone, "brazier": brazier, "gold_hoard": gold_hoard, "warning_post": warning_post,
         "junk_throne": junk_throne}


def main(argv):
    sheet = None
    if "--sheet" in argv:
        i = argv.index("--sheet")
        sheet = argv[i + 1]
        argv = argv[:i] + argv[i + 2:]
    ids = argv or list(PROPS)
    out = {}
    for name in ids:
        img = PROPS[name]().render(outline="tinted")
        img = grounded(img) if img.height in (32, 64) else img
        img.save(SPRITES / f"{name}.png")
        out[name] = img
    print(f"wrote {len(out)} lair props to art/sprites/")
    if sheet:
        k = 4
        board = Image.new("RGBA", (sum(i.width * k + 16 for i in out.values()) + 16, 48 * k + 32), (106, 150, 86, 255))
        x = 16
        for img in out.values():
            big = img.resize((img.width * k, img.height * k), Image.NEAREST)
            board.alpha_composite(big, (x, board.height - 16 - big.height))
            x += big.width + 16
        board.save(sheet)
        print(f"sheet in {sheet}")


if __name__ == "__main__":
    main(sys.argv[1:])
