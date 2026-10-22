#!/usr/bin/env python3
"""Weapons from Retro Diffusion: a picked 64-pixel RD drawing (art-variants/) made into the game's
two sprites, by the same rules as tools/item_art.py's drawn weapons:

- art/sprites/item_<id>.png, 32 × 32: the icon in bags, shops and the Character tab;
- art/sprites/held_<id>.png, 24 × 24: the weapon in hand (GearArt.weapon), one of its pixels to one
  of the hero's.

Both are shrunk from the RD drawing with its own outline taken off, each pixel the colour that
covers most of it (a thin blade wins over the air beside it), then outlined afresh in the items'
outline colour, so an RD weapon sits among the drawn ones. The game holds a weapon by the solid
pixel nearest the bottom-left corner and points it up and away (GearArt.held), so a drawing must lie
diagonally, grip bottom-left; one that doesn't can be turned (`turn`, degrees anticlockwise) before
it's shrunk. A magic weapon's glow (items.json `glow`) goes round its tip, found here.

    python3 tools/weapon_art.py                       # every weapon in PICKED
    python3 tools/weapon_art.py --out DIR bronze_sword=art-variants/rdw_bronze_sword/x_1.png
                                                       # a candidate, written to DIR instead
Check in hand with `python3 tools/gear_preview.py --weapons out.png <id> [held sprite]`.
"""

import json
import math
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import item_art as ia   # noqa: E402

ROOT = ia.ROOT
VARIANTS = ROOT / "art-variants"

ICON_INNER, HELD_INNER = 27, 20   # as big as the drawn weapons (tools/item_art.py), outline aside

# item id → (the picked RD drawing under art-variants/, degrees to turn it anticlockwise).
PICKED = {}


def load(path, turn=0):
    """The RD drawing as a Canvas, cropped to the weapon, its own dark outline taken off."""
    from PIL import Image
    img = Image.open(path).convert("RGBA")
    if turn:
        img = img.rotate(turn, resample=Image.NEAREST, expand=True)
    box = img.getbbox()
    img = img.crop(box)
    w, h = img.size
    side = max(w, h)
    c = ia.Canvas(side)
    for y in range(h):
        for x in range(w):
            r, g, b, a = img.getpixel((x, y))
            if a >= 128:
                c.px[y + (side - h)][x] = (r, g, b, 255)   # squared up, along the bottom and left
    # Its outline, if it drew one (most of its edge dark): the dark pixels next to the air, peeled
    # once. Without one, a dark grip at the edge is the weapon's own.
    edge = [(x, y) for y in range(side) for x in range(side)
            if c.px[y][x] and any(c.get(x + dx, y + dy) is None for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))]
    dark = [(x, y) for x, y in edge if max(c.px[y][x][:3]) < 80]
    if len(dark) > 0.7 * len(edge):
        for x, y in dark:
            c.px[y][x] = None
    return c


def shrink(src, size, inner):
    """`src` fitted into an `inner`-pixel square of a `size` canvas, along its bottom and across its
    middle, as big as the drawn weapons are (their median: 27 of 32 on the icon, 20 of 24 held, before
    the outline), with room above for a glow: each pixel the colour covering most of it, kept if the
    weapon covers enough of it."""
    out = ia.Canvas(size)
    left, top = (size - inner) // 2, size - 1 - inner
    k = src.size / inner
    for y in range(inner):
        for x in range(inner):
            cover = {}
            for sy in range(int(y * k), min(src.size, int(math.ceil((y + 1) * k)))):
                for sx in range(int(x * k), min(src.size, int(math.ceil((x + 1) * k)))):
                    share = (min(sx + 1, (x + 1) * k) - max(sx, x * k)) * (min(sy + 1, (y + 1) * k) - max(sy, y * k))
                    colour = src.px[sy][sx]
                    cover[colour] = cover.get(colour, 0) + share
            air = cover.pop(None, 0)
            if cover:
                colour, _ = max(cover.items(), key=lambda kv: kv[1])
                if sum(cover.values()) >= air * 0.6:
                    out.px[y + top][x + left] = colour
    out.outline()
    return out


def tip(c):
    """Where a magic weapon's glow goes: its solid pixel nearest the top-right corner, a pixel and a
    half in from it (items.json `glowAt`, in the icon's pixels)."""
    best = min(((x, y) for y in range(c.size) for x in range(c.size) if c.px[y][x] and c.px[y][x] != ia.OUTLINE),
               key=lambda p: (c.size - p[0]) + p[1])
    return [round((best[0] - 1.5) * 2) / 2, round((best[1] + 1.5) * 2) / 2]


def make(item_id, path, turn=0, out=None):
    """Writes item_<id>.png and held_<id>.png (to art/sprites/, or `out`); returns the glow spot."""
    items = {i["id"]: i for i in json.loads((ROOT / "content" / "items.json").read_text())["items"]}
    src = load(path, turn)
    icon, held = shrink(src, ia.SIZE, ICON_INNER), shrink(src, ia.HELD, HELD_INNER)
    spot = None
    if items[item_id].get("glow"):
        spot = tip(icon)
        ia.halo(icon, spot[0], spot[1], 10, ia.hexc(items[item_id]["glow"].lstrip("#")))
    folder = pathlib.Path(out) if out else ia.SPRITES
    folder.mkdir(parents=True, exist_ok=True)
    (folder / f"item_{item_id}.png").write_bytes(icon.png())
    (folder / f"held_{item_id}.png").write_bytes(held.png())
    return spot


def main(argv):
    out = None
    if "--out" in argv:
        i = argv.index("--out")
        out, argv = argv[i + 1], argv[:i] + argv[i + 2:]
    picks = {a.split("=")[0]: (a.split("=")[1], 0) for a in argv} if argv else {k: (VARIANTS / v[0], v[1]) for k, v in PICKED.items()}
    for item_id, (path, turn) in picks.items():
        spot = make(item_id, path, turn, out)
        print(f"{item_id}: from {path}" + (f", glowAt {spot}" if spot else ""))


if __name__ == "__main__":
    main(sys.argv[1:])
