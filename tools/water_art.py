#!/usr/bin/env python3
"""The water, drawn in code like tools/item_art.py (free): the sea round the lands and the water of
their lakes, rivers and ponds. The generated tile it replaces repeated every 16 pixels, four times in
each tile, so the sea was one small square over and over, and its shifted versions
(`ArtLibrary.tileVariant`) came out the same as itself.

Writes:
- art/sprites/sea.png: the sea, 16 × 16 cells of 32 pixels that tile seamlessly as a whole; each
  world cell takes the one at its place in it (`ContinentScene.seaGroups`), so the sea repeats only
  every 16 cells, more than a screen across.
- art/sprites/tile_water.png: a land's water, one 32-pixel cell in the same style that tiles with
  itself, its shifted versions now each different.

The ripples run level on screen: the ground is turned 45° and squashed to half height
(`WorldMap.project`), so they're drawn along the tiles' diagonal, where the screen's level lies, and
long and thin across it. Everything is periodic, so the pictures tile; and the same every run.

    python3 tools/water_art.py                    # both pictures
    python3 tools/water_art.py --preview out.png  # also the sea and a lake as the game shows them
"""

import math
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from item_art import encode_png, hexc  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPRITES = ROOT / "art" / "sprites"

# Deep to shallow, then the ripples' light and the odd glint. Their mean stays the old tile's
# (#40aff5), which the minimap and the haze over the sea are worked out from.
BODY = [hexc(c) for c in ("2b8ae6", "3097ec", "35a2f1", "3cacf4", "43b6f8", "4cc0fc")]
LIGHT = [hexc("7ccffd"), hexc("aee3ff")]
GLINT = hexc("eefaff")
# The sea's cells a side (`ContinentScene.seaCells` reads the picture's size).
SEA_CELLS = 16


class Lattice:
    """Smooth noise that repeats every `period` pixels both ways, in the screen's own directions:
    `a` (along the tiles' diagonal, level on screen) and `b` (across it), with features `along`
    pixels long and `across` wide (both dividing `period`)."""

    def __init__(self, period, along, across, seed):
        self.na, self.nb = period // along, period // across
        self.along, self.across = along, across
        self.period = period
        rng = random.Random(seed)
        self.values = [[rng.random() for _ in range(self.nb)] for _ in range(self.na)]

    def at(self, a, b):
        fa, fb = a / self.along, b / self.across
        ia, ib = math.floor(fa), math.floor(fb)
        ta, tb = fa - ia, fb - ib
        ta, tb = ta * ta * (3 - 2 * ta), tb * tb * (3 - 2 * tb)

        def v(i, j):
            return self.values[i % self.na][j % self.nb]

        top = v(ia, ib) * (1 - ta) + v(ia + 1, ib) * ta
        bottom = v(ia, ib + 1) * (1 - ta) + v(ia + 1, ib + 1) * ta
        return top * (1 - tb) + bottom * tb


def grain(x, y, period, seed):
    """A pixel's own small jitter, -0.5 to 0.5, the same for the pixel a period over."""
    h = ((x % period) * 73856093) ^ ((y % period) * 19349663) ^ (seed * 83492791)
    h = (h ^ (h >> 13)) * 1274126177 & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFF) / 0xFFFF - 0.5


def draw(period, seed, swells=1.0, ripples=0.93):
    """`period` × `period` pixels of water that tile with themselves. `swells`: how much the deeper
    and lighter swells show, and `ripples` how high a ripple's ridge must be to catch the light
    (fewer the nearer 1): a single cell's tile is too small for many of either, which would come
    back every cell in a grid."""
    # Long slow swells of deeper and lighter water, a few cells across, in two sizes so they don't
    # line up in a grid; and finer chop on them.
    swell = [Lattice(period, max(8, min(128, period // 2)), max(4, min(64, period // 4)), seed + 1),
             Lattice(period, max(8, min(64, period // 4)), max(4, min(32, period // 8)), seed + 2)]
    chop = Lattice(period, 16, 8, seed + 3)
    # The ripples: ridges of a noise, long along the level and thin across it, broken into dashes.
    ripple = Lattice(period, 16, 4, seed + 4)
    breaks = Lattice(period, 8, 8, seed + 5)
    rng = random.Random(seed + 6)
    # The odd glint out at sea; none in a single cell's tile, where it'd come back every cell.
    glints = {(rng.randrange(period), rng.randrange(period)) for _ in range(period * period // 700 if period >= 128 else 0)}
    rows = []
    for y in range(period):
        row = []
        for x in range(period):
            # The screen's level runs along x + y (down-right in the picture), its up along x - y.
            a, b = x + y, x - y
            tone = 0.6 * swell[0].at(a, b) + 0.4 * swell[1].at(a, b)
            tone = 0.5 + swells * (tone - 0.5)
            tone = 0.75 * tone + 0.25 * chop.at(a, b) + 0.12 * grain(x, y, period, seed) + 0.1
            body = BODY[max(0, min(len(BODY) - 1, int(tone * len(BODY) - 0.5)))]
            ridge = 1 - abs(2 * ripple.at(a, b) - 1)
            dash = breaks.at(a, b)
            if (x, y) in glints:
                color = GLINT
            elif ridge > ripples and dash > 0.58:
                # The brightest only out at sea: in a cell's tile it'd make a dot every cell.
                color = LIGHT[1] if period >= 128 and ridge > 0.98 and dash > 0.72 else LIGHT[0]
            else:
                color = body
            row.append(color)
        rows.append(row)
    return rows


def png(rows):
    data = b"".join(bytes([0]) + b"".join(bytes(c) for c in row) for row in rows)
    return encode_png(len(rows[0]), len(rows), data)


def preview(sea, lake, path):
    """The sea and a lake of the old tile and the new, turned and squashed as the game draws them."""
    from PIL import Image  # only for the preview

    def tiled(rows, cells, cell=32):
        n = len(rows)
        img = Image.new("RGB", (cells * cell, cells * cell))
        px = img.load()
        for y in range(cells * cell):
            for x in range(cells * cell):
                px[x, y] = tuple(rows[y % n][x % n][:3])
        return img

    def onscreen(img):
        big = img.resize((img.width * 44 // 32, img.height * 44 // 32), Image.NEAREST)
        turned = big.rotate(45, resample=Image.NEAREST, expand=True)
        return turned.resize((turned.width, turned.height // 2), Image.NEAREST)

    def versions(rows, cells, cell=32):
        """A land's water as GroundTiles lays it: each cell one of the tile's four versions
        (`ArtLibrary.variantPixels`: shifted and mirrored inside a soft frame of the tile)."""
        shifts = [(0, 0, False, False), (16, 16, False, False), (8, 20, True, False), (20, 8, False, True)]
        img = Image.new("RGB", (cells * cell, cells * cell))
        px = img.load()
        band = cell / 5
        for cy in range(cells):
            for cx in range(cells):
                h = (cx * 0x9E3779B1 ^ cy * 0x85EBCA77) & 0xFFFFFFFF
                dx, dy, mx, my = shifts[(h >> 7) % 4]
                for y in range(cell):
                    for x in range(cell):
                        sx, sy = (x + dx) % cell, (y + dy) % cell
                        if mx:
                            sx = cell - 1 - sx
                        if my:
                            sy = cell - 1 - sy
                        edge = min(x, y, cell - 1 - x, cell - 1 - y)
                        t = max(0.0, min(1.0, (edge - 1) / band))
                        inside = t * t * (3 - 2 * t)
                        a, b = rows[y][x], rows[sy][sx]
                        px[cx * cell + x, cy * cell + y] = tuple(round(a[i] * (1 - inside) + b[i] * inside) for i in range(3))
        return img

    old = Image.open(SPRITES / "tile_water.png").convert("RGB")
    old_rows = [[old.getpixel((x, y)) for x in range(old.width)] for y in range(old.height)]
    shots = [onscreen(tiled(old_rows, 16)), onscreen(tiled(sea, 16)), onscreen(versions(lake, 16))]
    w = sum(s.width for s in shots) + 20 * (len(shots) - 1)
    out = Image.new("RGB", (w, max(s.height for s in shots)), (20, 20, 20))
    x = 0
    for s in shots:
        out.paste(s, (x, 0))
        x += s.width + 20
    out.save(path)


def main():
    args = sys.argv[1:]
    sea = draw(SEA_CELLS * 32, 11)
    lake = draw(32, 23, swells=0.25, ripples=0.97)
    if "--preview" in args:
        preview(sea, lake, args[args.index("--preview") + 1])
    (SPRITES / "sea.png").write_bytes(png(sea))
    (SPRITES / "tile_water.png").write_bytes(png(lake))
    side = SEA_CELLS * 32
    mean = [sum(c[i] for row in sea for c in row) / (side * side) for i in range(3)]
    print(f"sea.png {side}×{side}, tile_water.png 32×32; the sea's mean #%02x%02x%02x" % tuple(round(v) for v in mean))


if __name__ == "__main__":
    main()
