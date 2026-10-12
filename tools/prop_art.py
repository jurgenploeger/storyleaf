#!/usr/bin/env python3
"""Props drawn in code where a generated sprite came out wrong: writes art/sprites/<id>.png.

Like tools/item_art.py: flat colours with a light and a dark shade and the game's dark outline, no
image libraries needed. Edit a drawing below and rerun:

    python3 tools/prop_art.py                   # all of them
    python3 tools/prop_art.py candy_cane        # just these
    python3 tools/prop_art.py --sheet out.png   # also a 6× contact sheet on the meadow's green
"""

import math
import pathlib
import sys

from item_art import OUTLINE, encode_png, hexc

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPRITES = ROOT / "art" / "sprites"


class Canvas:
    """A width × height grid of RGBA pixels (None is clear)."""

    def __init__(self, width, height):
        self.width, self.height = width, height
        self.px = [[None] * width for _ in range(height)]

    def get(self, x, y):
        return self.px[y][x] if 0 <= x < self.width and 0 <= y < self.height else None

    def outline(self, color=OUTLINE):
        grow = [(x, y) for y in range(self.height) for x in range(self.width)
                if self.px[y][x] is None and any(self.get(x + dx, y + dy) not in (None, color)
                                                 for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))]
        for x, y in grow:
            self.px[y][x] = color

    def png(self):
        raw = b"".join(b"\x00" + b"".join(bytes(c or (0, 0, 0, 0)) for c in row) for row in self.px)
        return encode_png(self.width, self.height, raw)


def nearest_on_path(path, x, y):
    """The closest point to (x, y) on a path of straight pieces and arcs: (distance, how far along
    the path, the unit vector out from it to the point)."""
    best = None
    start = 0.0
    for piece in path:
        if piece[0] == "line":
            _, (ax, ay), (bx, by) = piece
            length = math.hypot(bx - ax, by - ay)
            t = max(0.0, min(1.0, ((x - ax) * (bx - ax) + (y - ay) * (by - ay)) / (length * length)))
            px, py, along = ax + (bx - ax) * t, ay + (by - ay) * t, start + t * length
        else:
            # An arc round (cx, cy) of radius r from angle a0 to a1 (radians, y up on screen).
            _, (cx, cy), r, a0, a1 = piece
            length = abs(a1 - a0) * r
            angle = math.atan2(-(y - cy), x - cx)
            lo, hi = min(a0, a1), max(a0, a1)
            while angle < lo - math.pi:
                angle += 2 * math.pi
            while angle > hi + math.pi:
                angle -= 2 * math.pi
            angle = max(lo, min(hi, angle))
            px, py = cx + r * math.cos(angle), cy - r * math.sin(angle)
            along = start + abs(angle - a0) * r
        d = math.hypot(x - px, y - py)
        normal = ((x - px) / d, (y - py) / d) if d > 1e-6 else (0.0, 0.0)
        if best is None or d < best[0]:
            best = (d, along, normal)
        start += length
    return best


def draw_candy_cane():
    """A giant candy cane stuck in the ground: a straight shaft with its hook curling over to the
    left, red stripes winding round the white, lit from the top left like the other sprites."""
    c = Canvas(32, 48)
    # The shaft stands in the middle, where the game sets a prop down on its cell.
    shaft_x, top, bottom, bend = 16.5, 13.0, 47.0, 5.0
    path = [
        ("line", (shaft_x, bottom), (shaft_x, top)),
        ("arc", (shaft_x - bend, top), bend, 0.0, math.pi),
        ("line", (shaft_x - 2 * bend, top), (shaft_x - 2 * bend, top + 4.5)),
    ]
    half = 3.0
    reds = [hexc("9b1a2e"), hexc("d8324a"), hexc("f27a86")]
    whites = [hexc("cdbcc4"), hexc("f6eef1"), hexc("ffffff")]
    light = (-0.6, -0.8)
    for y in range(c.height):
        for x in range(c.width):
            d, along, (nx, ny) = nearest_on_path(path, x + 0.5, y + 0.5)
            if d > half:
                continue
            # Which side of the path it's on, so the stripes run round the cane on a slant.
            side = d if (nx * light[0] + ny * light[1]) >= 0 else -d
            stripe = (along + 1.0 * side) % 8.0 < 3.5
            lit = (nx * light[0] + ny * light[1]) * d / half
            tone = 2 if lit > 0.45 else 0 if lit < -0.3 else 1
            c.px[y][x] = (reds if stripe else whites)[tone]
    # Outlined in the candy's own darkest red, as the generated sweets are, not the items' ink.
    c.outline(hexc("5c1424"))
    return c


DRAWINGS = {
    "candy_cane": draw_candy_cane,
}


def main(argv):
    sheet_path = None
    if "--sheet" in argv:
        index = argv.index("--sheet")
        sheet_path = argv[index + 1]
        argv = argv[:index] + argv[index + 2:]
    ids = argv or sorted(DRAWINGS)
    drawn = {prop: DRAWINGS[prop]() for prop in ids}
    for prop, art in drawn.items():
        (SPRITES / f"{prop}.png").write_bytes(art.png())
    print(f"wrote {len(ids)} prop sprites to art/sprites/")
    if sheet_path:
        scale, pad = 6, 6
        width = sum(art.width * scale + pad for art in drawn.values()) + pad
        height = max(art.height for art in drawn.values()) * scale + 2 * pad
        pixels = [[(110, 160, 90, 255)] * width for _ in range(height)]
        ox = pad
        for art in drawn.values():
            for y in range(art.height * scale):
                for x in range(art.width * scale):
                    color = art.px[y // scale][x // scale]
                    if color:
                        pixels[pad + y][ox + x] = color
            ox += art.width * scale + pad
        raw = b"".join(b"\x00" + b"".join(bytes(p) for p in row) for row in pixels)
        pathlib.Path(sheet_path).write_bytes(encode_png(width, height, raw))
        print(f"contact sheet: {sheet_path}")


if __name__ == "__main__":
    main(sys.argv[1:])
