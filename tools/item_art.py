#!/usr/bin/env python3
"""Hand-drawn pixel art for every item, as code: writes art/sprites/item_<id>.png (32×32).

Each item is drawn in flat colours with a light and a dark shade, then gets the same dark
outline as the game's other sprites. No image libraries needed. Edit a drawing below and rerun:

    python3 tools/item_art.py            # all items
    python3 tools/item_art.py potion     # just these
    python3 tools/item_art.py --sheet out.png   # also a 4× contact sheet to look at
"""

import json
import math
import pathlib
import struct
import sys
import zlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPRITES = ROOT / "art" / "sprites"
SIZE = 32
OUTLINE = (35, 24, 52, 255)


def hexc(value, alpha=255):
    value = value.lstrip("#")
    return (int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16), alpha)


class Canvas:
    def __init__(self, size=SIZE):
        self.size = size
        self.px = [[None] * size for _ in range(size)]

    def set(self, x, y, color):
        x, y = int(round(x)), int(round(y))
        if 0 <= x < self.size and 0 <= y < self.size:
            self.px[y][x] = color

    def get(self, x, y):
        if 0 <= x < self.size and 0 <= y < self.size:
            return self.px[y][x]
        return None

    def rect(self, x0, y0, x1, y1, color):
        for y in range(int(y0), int(y1) + 1):
            for x in range(int(x0), int(x1) + 1):
                self.set(x, y, color)

    def line(self, x0, y0, x1, y1, color, width=1):
        steps = int(max(abs(x1 - x0), abs(y1 - y0))) * 2 + 1
        for i in range(steps + 1):
            t = i / steps
            x, y = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
            if width == 1:
                self.set(x, y, color)
            else:
                self.disc(x, y, width / 2, color)

    def disc(self, cx, cy, r, color):
        for y in range(int(cy - r - 1), int(cy + r + 2)):
            for x in range(int(cx - r - 1), int(cx + r + 2)):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                    self.set(x, y, color)

    def ellipse(self, cx, cy, rx, ry, color):
        for y in range(int(cy - ry - 1), int(cy + ry + 2)):
            for x in range(int(cx - rx - 1), int(cx + rx + 2)):
                if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1:
                    self.set(x, y, color)

    def poly(self, points, color):
        ys = [p[1] for p in points]
        for y in range(int(min(ys)), int(max(ys)) + 1):
            xs = []
            for (x0, y0), (x1, y1) in zip(points, points[1:] + points[:1]):
                if (y0 <= y + 0.5 < y1) or (y1 <= y + 0.5 < y0):
                    xs.append(x0 + (y + 0.5 - y0) * (x1 - x0) / (y1 - y0))
            xs.sort()
            for a, b in zip(xs[::2], xs[1::2]):
                for x in range(int(math.ceil(a - 0.5)), int(math.floor(b - 0.5)) + 1):
                    self.set(x, y, color)

    def ring(self, cx, cy, r_out, r_in, color, ry_scale=1.0):
        for y in range(int(cy - r_out - 1), int(cy + r_out + 2)):
            for x in range(int(cx - r_out - 1), int(cx + r_out + 2)):
                d = (x - cx) ** 2 + ((y - cy) / ry_scale) ** 2
                if r_in * r_in < d <= r_out * r_out:
                    self.set(x, y, color)

    def shade(self, test, color):
        """Recolour the filled pixels where test(x, y, current) is true."""
        for y in range(self.size):
            for x in range(self.size):
                c = self.px[y][x]
                if c is not None and test(x, y, c):
                    self.px[y][x] = color

    def outline(self, color=OUTLINE):
        grow = []
        for y in range(self.size):
            for x in range(self.size):
                if self.px[y][x] is None and any(
                    self.get(x + dx, y + dy) not in (None, color) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
                ):
                    grow.append((x, y))
        for x, y in grow:
            self.px[y][x] = color

    def png(self, scale=1):
        size = self.size * scale
        rows = []
        for y in range(size):
            row = bytearray([0])
            for x in range(size):
                c = self.px[y // scale][x // scale] or (0, 0, 0, 0)
                row += bytes(c)
            rows.append(bytes(row))
        return encode_png(size, size, b"".join(rows))


def encode_png(width, height, raw):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


# ---------------------------------------------------------------- shared shapes

WOOD = [hexc("8a5a2b"), hexc("b67a3c"), hexc("d9a05a")]          # dark, mid, light
STEEL = [hexc("7b8798"), hexc("b9c4d2"), hexc("eef3f8")]
GOLD = [hexc("b07a12"), hexc("e8b62c"), hexc("fff09a")]
WHITE = hexc("ffffff")


def light_top_left(c, colors, cx, cy, r):
    """Three-tone ball shading: light up-left, dark down-right."""
    dark, mid, light = colors
    for y in range(SIZE):
        for x in range(SIZE):
            if c.px[y][x] == mid:
                d = (x - cx) + (y - cy)
                if d > r * 0.55:
                    c.px[y][x] = dark
                elif d < -r * 0.75:
                    c.px[y][x] = light




def sword(c, blade, guard, grip, gem=None, long=True):
    tip, base = ((26, 5), (11, 20)) if long else ((23, 8), (11, 20))
    c.line(base[0], base[1], tip[0], tip[1], blade[1], width=4)
    c.line(base[0] + 1, base[1] - 1, tip[0] - 1, tip[1] + 1, blade[2], width=1)   # edge shine
    c.line(base[0] + 1, base[1] + 1, tip[0], tip[1] + 2, blade[0], width=1)       # shadow side
    c.line(7, 17, 14, 24, guard[1], width=3)                                      # crossguard
    c.line(7, 16, 13, 22, guard[2], width=1)
    c.line(9, 22, 5, 26, grip[1], width=3)                                        # grip
    c.line(9, 23, 5, 27, grip[0], width=1)
    c.disc(4.5, 27.5, 1.8, guard[1])                                              # pommel
    if gem:
        c.disc(10.5, 20.5, 1.3, gem)


def staff(c, shaft, top):
    c.line(7, 28, 21, 9, shaft[1], width=3)
    c.line(8, 28, 22, 10, shaft[0], width=1)
    c.line(6, 27, 20, 8, shaft[2], width=1)
    top(c)


def axe(c, head, handle, double=False):
    c.line(8, 28, 21, 7, handle[1], width=3)
    c.line(9, 28, 22, 8, handle[0], width=1)
    c.poly([(18, 6), (27, 3), (29, 13), (22, 15)], head[1])
    c.shade(lambda x, y, col: col == head[1] and x + y > 36, head[0])
    c.line(27, 4, 29, 12, head[2])
    if double:
        c.poly([(19, 7), (10, 3), (8, 12), (16, 14)], head[1])
        c.shade(lambda x, y, col: col == head[1] and x < 13 and y > 9, head[0])
        c.line(10, 4, 8, 11, head[2])
    c.rect(19, 7, 22, 12, handle[0])


def shirt(c, cloth, sleeves=True, collar=None):
    dark, mid, light = cloth
    c.poly([(9, 7), (23, 7), (25, 28), (7, 28)], mid)
    if sleeves:
        c.poly([(9, 7), (3, 13), (6, 17), (10, 13)], mid)
        c.poly([(23, 7), (29, 13), (26, 17), (22, 13)], mid)
    c.shade(lambda x, y, col: col == mid and x > 19, dark)
    c.shade(lambda x, y, col: col == mid and x < 11 and y > 8, light)
    c.ellipse(16, 7, 4, 2.2, collar or dark)
    c.rect(7, 27, 25, 28, dark)


def robe(c, cloth, trim, star=None):
    dark, mid, light = cloth
    c.poly([(11, 5), (21, 5), (28, 29), (4, 29)], mid)
    c.poly([(11, 6), (3, 15), (6, 18), (11, 12)], mid)
    c.poly([(21, 6), (29, 15), (26, 18), (21, 12)], mid)
    c.shade(lambda x, y, col: col == mid and x > 20, dark)
    c.shade(lambda x, y, col: col == mid and x < 10 and y > 7, light)
    c.line(16, 7, 16, 29, trim[1])
    c.rect(5, 28, 27, 29, trim[1])
    c.ellipse(16, 5.5, 4, 2, trim[0])
    if star:
        star_shape(c, 21, 19, 4.6, star, inner=0.5)


def cloak(c, cloth, clasp, fur=None, hood=False):
    dark, mid, light = cloth
    if hood:
        c.poly([(12, 6), (20, 6), (29, 29), (3, 29)], mid)
    else:   # rounded shoulders, so it reads as a cloak and not a tent
        c.poly([(10, 7), (22, 7), (27, 12), (29, 29), (3, 29), (5, 12)], mid)
    c.shade(lambda x, y, col: col == mid and x > 18, dark)
    c.shade(lambda x, y, col: col == mid and x < 11 and y > 9, light)
    c.line(16, 9, 12, 29, dark)
    c.line(16, 9, 20, 29, dark)
    if hood:
        c.ellipse(16, 7, 7, 5, mid)
        c.ellipse(16, 8, 4, 3, dark)
    if fur:
        c.ellipse(16, 8, 8, 2.8, fur[1])
        for x in range(9, 24, 3):
            c.set(x, 10, fur[0])
    c.disc(16, 11, 1.7, clasp)


def star_shape(c, cx, cy, r, color, inner=0.45, rotation=-math.pi / 2):
    points = []
    for i in range(10):
        radius = r if i % 2 == 0 else r * inner
        angle = rotation + i * math.pi / 5
        points.append((cx + radius * math.cos(angle), cy + radius * math.sin(angle)))
    c.poly(points, color)


def ring(c, band, gem=None, gem_color=None):
    dark, mid, light = band
    c.ring(16, 19, 9, 5.5, mid, ry_scale=0.85)
    c.shade(lambda x, y, col: col == mid and y > 21, dark)
    c.shade(lambda x, y, col: col == mid and y < 16 and x < 15, light)
    if gem:
        c.poly([(12, 9), (20, 9), (22, 12), (16, 17), (10, 12)], gem_color[1])
        c.shade(lambda x, y, col: col == gem_color[1] and x > 16, gem_color[0])
        c.poly([(13, 10), (16, 10), (15, 12), (12, 12)], gem_color[2])


def whip(c, leather, grip, tassel=None):
    # A braided lash: the coil alternates light and dark every few steps.
    for i in range(0, 60):
        t = i / 60 * math.pi * 3.2
        r = 3 + i * 0.13
        c.disc(17 + r * math.cos(t), 14 + r * math.sin(t) * 0.8, 1.1, leather[2] if i % 6 < 2 else leather[1])
    c.line(6, 28, 11, 21, grip[1], width=3)
    c.line(7, 28, 12, 22, grip[0], width=1)
    for (x, y) in ((7, 26), (9, 24)):                       # wrapped handle
        c.line(x - 1, y - 1, x + 1, y + 1, grip[2])
    c.rect(10, 20, 13, 22, GOLD[1])
    c.set(10, 20, GOLD[2])
    if tassel:
        tassel(c)


# ---------------------------------------------------------------- the items

RED = [hexc("a8202e"), hexc("e0384a"), hexc("ff8a8a")]
PINK = [hexc("b0205e"), hexc("ee4c8c"), hexc("ffa4c8")]
BLUE = [hexc("1c4fa8"), hexc("3a86e8"), hexc("9ccaff")]
VIOLET = [hexc("4a2aa0"), hexc("7a5ae6"), hexc("c0aaff")]
GREEN = [hexc("2a7a2e"), hexc("46b848"), hexc("9ee88a")]
TEAL = [hexc("137a78"), hexc("2cc0b5"), hexc("a4f2e6")]
LEATHER = [hexc("6a4020"), hexc("9a6232"), hexc("c88a4e")]
CLOTH = [hexc("9a8a62"), hexc("d8c89a"), hexc("f4ead0")]
ORANGE = [hexc("b0501a"), hexc("ee8a2a"), hexc("ffc070")]
NAVY = [hexc("1a2a6a"), hexc("2e4aa8"), hexc("6a8ae0")]
SNOW = [hexc("5f88b8"), hexc("a9cdef"), hexc("e4f2ff")]
DRAGON = [hexc("8a1a1a"), hexc("d03a2a"), hexc("ff8a5a")]
LILAC = [hexc("8a5ab0"), hexc("c49ae8"), hexc("eedcff")]
COPPER = [hexc("8a4a22"), hexc("c8783a"), hexc("f0b07a")]






# Every kind of Seal Stone is the same crystal with the same white sealing spiral; only its colours
# change.
SEAL_SHAPE = [(16, 4), (26, 11), (24, 25), (16, 29), (8, 25), (6, 11)]
SEAL_FACET = [(16, 5), (8, 11), (12, 14), (16, 9)]


def seal_spiral(c, color=WHITE):
    for i in range(0, 40):       # the sealing spiral
        t = i / 40 * math.pi * 3
        r = 0.6 + i * 0.14
        c.set(16 + r * math.cos(t), 17 + r * math.sin(t), color)


def seal_gem(c, colors, spiral=WHITE):
    """The Seal Stone's crystal in `colors` (dark, mid, light): its right-hand facets in shadow, a
    bright facet up top, and the spiral."""
    dark, mid, light = colors
    c.poly(SEAL_SHAPE, mid)
    c.shade(lambda x, y, col: col == mid and x > 17 and y > 14, dark)
    c.poly(SEAL_FACET, light)
    seal_spiral(c, spiral)


def draw_seal_stone(c):
    seal_gem(c, TEAL)


def draw_moon_seal(c):
    """Pale moonlight blue."""
    seal_gem(c, [hexc("3a58a4"), hexc("8db2ee"), hexc("e2eeff")])


def draw_heart_seal(c):
    """Rose pink."""
    seal_gem(c, PINK)


def draw_star_seal(c):
    """Starlight gold."""
    seal_gem(c, GOLD)


def draw_wishing_seal(c):
    """The rainbow one: the same crystal in soft rainbow bands, the shaded side a little darker, and the
    spiral in violet so it shows on the pale colours."""
    bands = [hexc("ff9aa8"), hexc("ffc88a"), hexc("fff09a"), hexc("aef0a0"), hexc("9fd6ff"), hexc("c8b0ff")]
    c.poly(SEAL_SHAPE, bands[0])
    for y in range(SIZE):
        for x in range(SIZE):
            if c.px[y][x] == bands[0]:
                band = bands[min(len(bands) - 1, max(0, int((y - 4) / 26 * len(bands))))]
                c.px[y][x] = tuple(int(v * 0.8) for v in band[:3]) + (255,) if x > 17 and y > 14 else band
    c.poly(SEAL_FACET, hexc("fffaff"))
    seal_spiral(c, hexc("6a46b8"))


def draw_homeward_feather(c):
    """A soft white feather, gently curved, on a golden quill, with a homeward glint."""
    vane = [hexc("8fa8d0"), hexc("eef4ff"), WHITE]
    gold = [hexc("b07a1a"), hexc("f0c040"), hexc("fff0a0")]
    base, tip = (9, 24), (27, 3)                       # the shaft, bottom left to top right
    dx, dy = tip[0] - base[0], tip[1] - base[1]
    length = math.hypot(dx, dy)
    ux, uy = dx / length, dy / length                  # along the shaft
    nx, ny = -uy, ux                                   # across it, towards the bottom right
    def spine(t):                                      # the shaft bows a little
        bend = 2.2 * math.sin(math.pi * t)
        return base[0] + dx * t - nx * bend, base[1] + dy * t - ny * bend
    def edge(side, widest):
        points = []
        for k in range(13):
            t = k / 12
            width = widest * math.sin(math.pi * t) ** 0.6 if t < 1 else 0
            x, y = spine(t)
            points.append((x + side * nx * width, y + side * ny * width))
        return points
    c.poly(edge(-1, 5.0) + edge(1, 7.5)[::-1], vane[1])
    for k in range(4, 11, 2):                          # barbs: soft grey splits slanting to the tip
        t = k / 12
        x, y = spine(t)
        c.line(x + nx * 1.5, y + ny * 1.5, x + nx * 6 + ux * 2.5, y + ny * 6 + uy * 2.5, vane[0])
        c.line(x - nx * 1.2, y - ny * 1.2, x - nx * 4 + ux * 2, y - ny * 4 + uy * 2, hexc("c8d6ee"))
    for k in range(2, 12):                             # light on the narrow upper side
        x, y = spine(k / 12)
        c.set(x - nx * 2.5, y - ny * 2.5, vane[2])
    for k in range(0, 25):                             # the golden quill along the spine
        x, y = spine(k / 24)
        c.set(x, y, gold[1] if k % 6 else gold[2])
    c.line(base[0], base[1], base[0] - 4, base[1] + 5, gold[0], width=2)
    for (x, y) in ((27, 19), (23, 24)):                # the homeward glint
        c.set(x, y, gold[2])
        for (ox, oy) in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            c.set(x + ox, y + oy, gold[1])

def draw_pet_egg(c):
    shell = [hexc("d8c8a4"), hexc("fbf2dc"), WHITE]
    c.ellipse(16, 17.5, 9, 11.5, shell[1])
    light_top_left(c, shell, 16, 17.5, 10)
    for (x, y, r, col) in ((12, 14, 2.2, hexc("f08aa8")), (20, 19, 2.6, hexc("7ac0f0")), (13, 23, 1.8, hexc("9ad86a")), (19, 11, 1.5, hexc("f6c33b"))):
        c.disc(x, y, r, col)
    c.line(3, 10, 5, 12, OUTLINE)     # wiggle marks
    c.line(28, 10, 26, 12, OUTLINE)


def draw_wooden_sword(c):
    # A practice sword: pale ash blade with grain, a dark guard and a leather-wrapped grip.
    blade = [hexc("a8743c"), hexc("deb070"), hexc("f6dca4")]
    sword(c, blade, [hexc("4a2a14"), hexc("6a3e1e"), hexc("8a5a30")], [hexc("3a2410"), hexc("5a3a1a"), hexc("7a5228")], long=True)
    for (x, y) in ((16, 15), (19, 12), (22, 9)):          # wood grain
        c.set(x, y, blade[0])
    for (x, y) in ((8, 24), (6, 26)):                      # leather wraps
        c.set(x, y, hexc("c89a5a"))


def draw_steel_sword(c):
    sword(c, STEEL, GOLD, [hexc("4a2a6a"), hexc("6a44a0"), hexc("9a7ad0")], gem=hexc("e0384a"))
    c.line(13, 17, 23, 7, STEEL[0])                        # the fuller, a groove down the blade
    c.set(24, 6, STEEL[2]); c.set(25, 5, WHITE)             # glint at the tip
    for (x, y) in ((7, 24), (6, 25)):                       # wrapped grip
        c.set(x, y, hexc("c0a8f0"))


def draw_oak_staff(c):
    def top(c):
        # A leafy crown cradling a small green spirit orb.
        for (cx, cy, r) in ((22, 5.5, 3.2), (25.5, 8.5, 3), (19.5, 8.5, 2.8)):
            c.disc(cx, cy, r, GREEN[1])
        c.shade(lambda x, y, col: col == GREEN[1] and x + y > 31, GREEN[0])
        c.disc(21, 4.5, 1.3, GREEN[2]); c.disc(25, 7.5, 1, GREEN[2])
        c.disc(22.5, 7.5, 1.6, hexc("d8ffb0"))
        c.set(22, 7, WHITE)
    staff(c, WOOD, top)
    c.disc(13.5, 19.5, 1.2, WOOD[0])                       # a knot in the shaft
    for (x, y) in ((17, 15), (15, 18), (11, 22), (9, 25)):  # a vine curling down the shaft
        c.set(x, y, GREEN[1]); c.set(x + 1, y, GREEN[0])


def draw_elder_staff(c):
    def top(c):
        c.ring(22.5, 7.5, 5.2, 3.2, WOOD[1])
        c.shade(lambda x, y, col: col == WOOD[1] and x + y > 31, WOOD[0])
        c.disc(22.5, 7.5, 3, hexc("7af0ff"))
        c.shade(lambda x, y, col: col == hexc("7af0ff") and x + y > 31, hexc("2cb8d8"))
        c.disc(21.5, 6.5, 1.2, WHITE)
    staff(c, [hexc("5a3a1a"), hexc("7a4e24"), hexc("a07040")], top)
    for (x, y) in ((14, 18), (11, 22)):                     # carved bands
        c.line(x - 1, y - 1, x + 1, y + 1, GOLD[1])
    c.set(13, 19, GREEN[1]); c.set(12, 19, GREEN[2]); c.set(16, 15, GREEN[1])


def draw_iron_axe(c):
    axe(c, STEEL, WOOD)
    # A broader blade, with a bright cutting edge and a rivet.
    c.poly([(18, 5), (28, 1), (30, 15), (21, 16)], STEEL[1])
    c.shade(lambda x, y, col: col == STEEL[1] and x + y > 37, STEEL[0])
    c.line(28, 2, 30, 14, STEEL[2])
    c.line(27, 3, 29, 13, WHITE)
    c.rect(19, 7, 22, 13, WOOD[0])
    c.disc(20.5, 10, 1, GOLD[1])


def draw_battle_axe(c):
    steel = [hexc("5a6474"), hexc("8e9aac"), hexc("dde6f0")]
    axe(c, steel, [hexc("4a2a1a"), hexc("6a3e22"), hexc("8a5a34")], double=True)
    # Gold rims along both blades, an engraved line, and a gold cap.
    c.line(27, 3, 29, 13, GOLD[1]); c.line(10, 3, 8, 12, GOLD[1])
    c.line(26, 5, 27, 11, steel[2]); c.line(11, 5, 10, 10, steel[2])
    c.line(23, 8, 26, 11, steel[0]); c.line(15, 8, 12, 11, steel[0])
    c.disc(20.5, 9.5, 1.6, GOLD[1]); c.set(20, 9, GOLD[2])
    c.disc(8.5, 28.5, 1.3, GOLD[1])


def draw_crystal_wand(c):
    c.line(6, 28, 17, 14, WOOD[1], width=3)
    c.line(7, 28, 18, 15, WOOD[0])
    c.line(5, 27, 16, 13, WOOD[2])
    crystal = [hexc("1e98c0"), hexc("62dcf4"), hexc("d4fbff")]
    c.poly([(21, 1), (28, 9), (22, 18), (14, 10)], crystal[1])
    c.shade(lambda x, y, col: col == crystal[1] and x > 21, crystal[0])
    c.poly([(20, 4), (16, 10), (19, 11), (22, 5)], crystal[2])
    c.set(18, 7, WHITE); c.set(26, 2, WHITE); c.set(29, 15, WHITE)
    c.rect(15, 13, 19, 15, GOLD[1])
    c.line(15, 13, 19, 13, GOLD[2])


def draw_star_wand(c):
    c.line(7, 27, 17, 15, GOLD[1], width=2)
    c.line(8, 27, 18, 16, GOLD[0])
    star_shape(c, 20.5, 10.5, 8, hexc("ffd84a"))
    star_shape(c, 19.5, 9.5, 4, hexc("fff4b0"))
    c.set(28, 21, WHITE); c.set(4, 12, WHITE); c.set(27, 3, WHITE)


def draw_tamer_whip(c):
    whip(c, LEATHER, WOOD)


def draw_beast_whip(c):
    def tassel(c):
        c.disc(24, 25, 3, hexc("f6c33b"))                 # paw pad
        for (x, y) in ((21, 21), (24, 20), (27, 21)):
            c.disc(x, y, 1.2, hexc("f6c33b"))
    whip(c, [hexc("7a1a1a"), hexc("b8302a"), hexc("e8604a")], [hexc("3a2a1a"), hexc("5a4028"), hexc("7a5a38")], tassel)


def draw_wild_horn(c):
    horn = [hexc("a07a4a"), hexc("e6cfa0"), hexc("fff4dc")]
    path = []
    for i in range(0, 48):
        t = i / 47
        x = 5 + t * 19
        y = 26 - math.sin(t * math.pi / 2) * 15
        r = 1 + t * 4.2
        path.append((x, y, r))
        c.disc(x, y, r, horn[1])
    # Shade across the curve: the side facing down-right is in shadow, up-left catches light.
    for py in range(SIZE):
        for px in range(SIZE):
            if c.px[py][px] != horn[1]:
                continue
            x, y, r = min(path, key=lambda p: (p[0] - px) ** 2 + (p[1] - py) ** 2)
            across = ((px - x) + (py - y)) / math.sqrt(2)
            if across > 0.35 * r:
                c.px[py][px] = horn[0]
            elif across < -0.45 * r:
                c.px[py][px] = horn[2]
    for t in (0.4, 0.7):                                                      # carved bands
        x, y, r = path[int(t * 47)]
        c.ring(x, y, r + 0.3, r - 1.3, LEATHER[0])
    x, y, r = path[-1]
    c.ellipse(x + 1, y - 0.5, r * 0.55, r * 0.8, hexc("5a3a1a"))           # the bell's opening
    c.disc(6, 25.5, 1.2, GOLD[1])                                             # mouthpiece


def draw_cloth_tunic(c):
    shirt(c, CLOTH, collar=hexc("8a7a52"))
    c.line(16, 8, 16, 14, CLOTH[0])                        # laced neck
    for y in (9, 11, 13):
        c.set(15, y, WOOD[0]); c.set(17, y, WOOD[0])
    c.rect(8, 21, 24, 22, WOOD[1])                         # belt
    c.rect(15, 20, 17, 23, GOLD[1])
    c.set(15, 20, GOLD[2])
    for x in range(9, 24, 3):                              # stitched hem
        c.set(x, 26, CLOTH[0])


def draw_leather_vest(c):
    shirt(c, LEATHER, sleeves=False, collar=hexc("4a2a14"))
    c.poly([(14, 8), (18, 8), (17, 27), (15, 27)], CLOTH[2])   # the shirt underneath
    c.line(14, 8, 15, 27, LEATHER[0]); c.line(18, 8, 17, 27, LEATHER[0])
    for y in (12, 17, 22):                                 # buttons
        c.set(13, y, GOLD[1]); c.set(19, y, GOLD[1])
    c.rect(9, 18, 12, 21, LEATHER[0]); c.rect(20, 18, 23, 21, LEATHER[0])   # pockets
    c.line(9, 18, 12, 18, LEATHER[2]); c.line(20, 18, 23, 18, LEATHER[2])
    for y in range(9, 27, 3):                              # stitching
        c.set(9, y, LEATHER[2])


def draw_chain_mail(c):
    shirt(c, STEEL, collar=hexc("5a6474"))
    c.shade(lambda x, y, col: col in STEEL and (x + y) % 3 == 0 and 8 < y < 27, STEEL[0])


def draw_iron_plate(c):
    plate = [hexc("6a7688"), hexc("aab6c6"), hexc("f0f6ff")]
    c.poly([(8, 6), (24, 6), (26, 12), (23, 28), (9, 28), (6, 12)], plate[1])
    c.disc(6, 9, 3.5, plate[1]); c.disc(26, 9, 3.5, plate[1])
    c.shade(lambda x, y, col: col == plate[1] and x > 18, plate[0])
    c.shade(lambda x, y, col: col == plate[1] and x < 12 and y > 8, plate[2])
    c.line(16, 8, 16, 27, plate[0])
    c.line(9, 17, 23, 17, plate[0])
    c.ellipse(16, 6, 4, 1.8, plate[0])


def draw_dragon_mail(c):
    shirt(c, DRAGON, collar=GOLD[0])
    for y in range(10, 27, 3):
        for x in range(8 + (y // 3) % 2 * 2, 25, 4):
            c.set(x, y, DRAGON[0]); c.set(x + 1, y + 1, DRAGON[0])
    c.line(8, 9, 11, 7, GOLD[1]); c.line(24, 9, 21, 7, GOLD[1])


def draw_silk_robe(c):
    robe(c, LILAC, [hexc("b89ad8"), WHITE, WHITE], star=GOLD[1])


def draw_mage_robe(c):
    robe(c, NAVY, [GOLD[0], GOLD[1], GOLD[2]])
    for (x, y) in ((10, 20), (22, 24), (12, 26), (20, 14)):
        c.set(x, y, GOLD[2])


def draw_snow_cloak(c):
    cloak(c, SNOW, hexc("3a86e8"), fur=[hexc("b8c8dc"), WHITE])
    c.rect(4, 27, 28, 28, WHITE)                     # fur hem
    for (x, y) in ((9, 20), (22, 18), (14, 24), (19, 15)):   # snowflakes
        c.set(x, y, WHITE); c.set(x - 1, y, WHITE); c.set(x + 1, y, WHITE); c.set(x, y - 1, WHITE); c.set(x, y + 1, WHITE)


def draw_ranger_cloak(c):
    cloak(c, GREEN, GOLD[1], hood=True)


def draw_tamer_jacket(c):
    shirt(c, ORANGE, collar=hexc("7a3a10"))
    c.rect(9, 19, 13, 23, ORANGE[0]); c.rect(19, 19, 23, 23, ORANGE[0])   # pockets
    c.rect(10, 20, 12, 20, ORANGE[2]); c.rect(20, 20, 22, 20, ORANGE[2])
    c.line(16, 9, 16, 28, hexc("7a3a10"))


def draw_lucky_clover(c):
    for (cx, cy) in ((11, 10), (21, 10), (11, 20), (21, 20)):
        c.disc(cx, cy, 5.2, GREEN[1])
    c.shade(lambda x, y, col: col == GREEN[1] and (x - 16) + (y - 15) > 6, GREEN[0])
    c.shade(lambda x, y, col: col == GREEN[1] and (x - 16) + (y - 15) < -9, GREEN[2])
    c.line(16, 15, 23, 29, hexc("2a6a2e"), width=2)
    c.set(16, 15, GREEN[0])


def draw_ruby_ring(c):
    ring(c, GOLD, gem=True, gem_color=RED)


def draw_novice_ring(c):
    ring(c, COPPER)
    c.disc(16, 11, 1.8, hexc("9ccaff"))


def draw_star_charm(c):
    c.line(5, 3, 16, 12, GOLD[0])
    c.line(27, 3, 16, 12, GOLD[0])
    c.disc(16, 12, 1.5, GOLD[1])
    star_shape(c, 16, 21, 9, GOLD[1])
    star_shape(c, 15, 20, 4.5, GOLD[2])
    c.set(27, 25, WHITE); c.set(6, 18, WHITE)


def draw_power_band(c):
    band = [hexc("8a1a2a"), hexc("d83a4a"), hexc("ff8a8a")]
    c.ring(16, 16, 11, 6.5, band[1], ry_scale=0.62)
    c.shade(lambda x, y, col: col == band[1] and y > 17, band[0])
    c.shade(lambda x, y, col: col == band[1] and y < 13, band[2])
    for x in (8, 16, 24):
        c.disc(x, 21 if x == 16 else 19, 1.3, STEEL[2])


def draw_speed_boots(c):
    boot = [hexc("1c4fa8"), hexc("3a86e8"), hexc("9ccaff")]
    c.poly([(9, 6), (17, 6), (17, 21), (26, 23), (27, 28), (8, 28)], boot[1])
    c.shade(lambda x, y, col: col == boot[1] and x > 15 and y < 21, boot[0])
    c.shade(lambda x, y, col: col == boot[1] and x < 12, boot[2])
    c.rect(8, 26, 27, 28, hexc("f4ead0"))
    c.rect(9, 6, 17, 8, hexc("f4ead0"))
    for i, (x, y) in enumerate(((5, 10), (4, 14), (5, 18))):   # the wing: three feathers
        c.ellipse(x + 2, y, 3.2, 1.6, WHITE)
        c.line(x, y + 1, x + 4, y + 1, hexc("9ccaff"))
    c.set(21, 25, GOLD[1])


# ---------------------------------------------------------------- gloves, necklaces and boots
# Each has a slot of its own next to the weapon, armour and accessory (rings and charms).

STRAW = [hexc("a8862e"), hexc("dcc060"), hexc("f6e6a0")]
AMBER = [hexc("a8560e"), hexc("f09a28"), hexc("ffd27a")]
SHELL = [hexc("c87a8a"), hexc("f6b8c0"), hexc("fff0f0")]
MOON = [hexc("5f7ab8"), hexc("a8c4f0"), hexc("eef6ff")]


def glove(c, colors, cuff, studs=None, claws=None):
    """A glove seen from the back of the hand: four fingers, a thumb out to the left, a cuff."""
    dark, mid, light = colors
    for i, x in enumerate((10, 14, 18, 22)):
        c.rect(x, 5 if i in (1, 2) else 7, x + 2, 14, mid)
    c.rect(9, 12, 24, 22, mid)
    c.poly([(9, 13), (4, 9), (2, 12), (8, 21)], mid)
    c.shade(lambda x, y, col: col == mid and x > 20, dark)
    c.shade(lambda x, y, col: col == mid and x < 12 and y < 17, light)
    c.rect(8, 22, 25, 28, cuff[1])
    c.rect(8, 22, 25, 22, cuff[2])
    c.rect(8, 28, 25, 28, cuff[0])
    if studs:
        for x in (11, 15, 19, 23):
            c.set(x, 13, studs)
    if claws:
        for x in (11, 15, 19, 23):
            c.set(x, 4 if x in (15, 19) else 6, claws)


def pendant(c, chain, stone, shape="drop", rim=None):
    """A chain hanging in a V from the top corners to a stone: a drop, a round or a star."""
    for i in range(12):
        color = chain[2] if i % 2 else chain[1]
        c.set(5 + i * 0.95, 2 + i * 1.0, color)
        c.set(27 - i * 0.95, 2 + i * 1.0, color)
    c.disc(16, 14, 1.6, chain[1])
    dark, mid, light = stone
    if shape == "round":
        c.disc(16, 22, 7, (rim or chain)[1])
        c.disc(16, 22, 5, mid)
        c.shade(lambda x, y, col: col == mid and (x - 16) + (y - 22) > 2, dark)
        c.disc(14, 20, 1.5, light)
    elif shape == "star":
        star_shape(c, 16, 22, 9, mid)
        c.shade(lambda x, y, col: col == mid and x > 17 and y > 21, dark)
        star_shape(c, 15, 21, 4, light)
    elif shape == "shell":
        c.poly([(16, 16), (24, 22), (22, 28), (10, 28), (8, 22)], mid)
        for x in (12, 16, 20):
            c.line(16, 17, x, 27, dark)
        c.rect(10, 28, 22, 28, dark)
        c.set(14, 21, light); c.set(18, 21, light)
    else:
        c.poly([(16, 15), (22, 21), (20, 27), (16, 29), (12, 27), (10, 21)], mid)
        c.shade(lambda x, y, col: col == mid and x > 16, dark)
        c.poly([(13, 20), (16, 17), (16, 22), (13, 23)], light)


def boot(c, colors, cuff, sole, laces=None):
    """A boot in profile, toe to the right: shaft, foot, a cuff at the top and a sole."""
    dark, mid, light = colors
    c.poly([(9, 6), (17, 6), (17, 21), (26, 23), (27, 28), (8, 28)], mid)
    c.shade(lambda x, y, col: col == mid and x > 15 and y < 21, dark)
    c.shade(lambda x, y, col: col == mid and x < 12, light)
    c.rect(8, 26, 27, 28, sole)
    c.rect(9, 6, 17, 8, cuff)
    if laces:
        for y in (11, 14, 17):
            c.line(11, y, 15, y + 1, laces)


def draw_leather_gloves(c):
    glove(c, LEATHER, CLOTH)


def draw_iron_gauntlets(c):
    glove(c, STEEL, LEATHER, studs=STEEL[2])
    for y in (16, 19):
        c.line(10, y, 23, y, STEEL[0])


def draw_falcon_gloves(c):
    glove(c, ORANGE, LEATHER)
    c.ellipse(5, 24, 3.4, 1.6, WHITE)                      # a falcon feather tucked in the cuff
    c.line(2, 25, 8, 23, CLOTH[0])


def draw_dragonhide_gauntlets(c):
    glove(c, DRAGON, GOLD, studs=GOLD[2], claws=hexc("f4ead0"))


def draw_starforged_gauntlets(c):
    glove(c, NAVY, GOLD, studs=GOLD[2])
    star_shape(c, 16, 25, 3.5, GOLD[2])


def draw_shell_pendant(c):
    pendant(c, LEATHER, SHELL, shape="shell")


def draw_amber_amulet(c):
    pendant(c, GOLD, AMBER, shape="round")


def draw_moonstone_pendant(c):
    pendant(c, STEEL, MOON)


def draw_phoenix_amulet(c):
    pendant(c, GOLD, DRAGON)
    c.line(16, 18, 16, 25, ORANGE[2])                       # a flame inside the stone
    c.set(15, 22, ORANGE[2]); c.set(17, 21, ORANGE[2])


def draw_starlight_necklace(c):
    pendant(c, GOLD, GOLD, shape="star")
    c.set(27, 25, WHITE); c.set(5, 20, WHITE)


def draw_straw_sandals(c):
    c.rect(6, 24, 27, 28, STRAW[1])                        # the sole
    c.rect(6, 28, 27, 28, STRAW[0])
    for x in (7, 11, 15, 19, 23):                           # woven
        c.set(x, 26, STRAW[2])
    c.line(10, 24, 16, 14, LEATHER[1], width=2)              # straps over the foot
    c.line(22, 24, 16, 14, LEATHER[1], width=2)
    c.disc(16, 14, 1.6, LEATHER[0])


def draw_leather_boots(c):
    boot(c, LEATHER, LEATHER[2], hexc("3a2410"), laces=CLOTH[2])


def draw_traveler_boots(c):
    boot(c, GREEN, CLOTH[2], LEATHER[0], laces=GOLD[1])
    c.set(21, 25, GOLD[1])


def draw_cloudstep_boots(c):
    boot(c, SNOW, WHITE, MOON[0])
    for (x, y, r) in ((7, 27, 3), (12, 29, 2.6), (20, 29, 2.8), (26, 28, 2.4)):   # a cloud underfoot
        c.disc(x, y, r, WHITE)


# ---------------------------------------------------------------- companion toys
# Fairyland Online's Pet Toys: a companion who plays with one gains a stat for good.

SKIN = hexc("ffd6b4")
BEAR = [hexc("6e4224"), hexc("a06638"), hexc("d6a06a")]


def draw_toy_soldier(c):
    """A wind-up tin soldier: tall black shako with a gold badge and a red plume, red coat with gold
    buttons, blue trousers, black boots, and the gold key in his back."""
    c.rect(15, 1, 17, 2, RED[1])                       # plume
    c.rect(13, 3, 19, 9, hexc("2a2a3a"))               # shako
    c.rect(13, 3, 14, 9, hexc("4a4a62"))
    c.disc(16, 6, 1.3, GOLD[1])
    c.rect(13, 9, 19, 9, GOLD[0])                      # chin strap line
    c.rect(13, 10, 19, 13, SKIN)                       # face
    c.set(14, 11, OUTLINE); c.set(18, 11, OUTLINE)
    c.set(13, 12, hexc("f4a0a0")); c.set(19, 12, hexc("f4a0a0"))
    c.rect(12, 14, 20, 21, RED[1])                     # coat
    c.rect(19, 14, 20, 21, RED[0])
    c.rect(12, 14, 13, 17, RED[2])
    c.rect(10, 14, 11, 20, RED[1]); c.rect(21, 14, 22, 20, RED[0])   # arms
    c.rect(10, 21, 11, 21, SKIN); c.rect(21, 21, 22, 21, SKIN)
    c.rect(10, 14, 12, 15, GOLD[1]); c.rect(20, 14, 22, 15, GOLD[1])  # epaulettes
    for y in (15, 17, 19):
        c.set(16, y, GOLD[2])
    c.rect(12, 21, 20, 21, WHITE)                      # belt
    c.rect(13, 22, 19, 27, NAVY[1])                    # trousers
    c.rect(18, 22, 19, 27, NAVY[0])
    c.rect(16, 25, 16, 27, NAVY[0])
    c.rect(13, 28, 15, 29, hexc("2a2a3a")); c.rect(17, 28, 19, 29, hexc("2a2a3a"))   # boots
    c.line(9, 17, 6, 17, GOLD[0])                      # the wind-up key
    c.ring(4.5, 17, 2.4, 1.0, GOLD[1])


def draw_toy_blocks(c):
    """Three lettered wooden blocks, two on the floor and one on top: A in red, B in blue, C in yellow."""
    def block(x, y, colors, letter):
        dark, mid, light = colors
        c.poly([(x, y), (x + 3, y - 3), (x + 13, y - 3), (x + 10, y)], light)         # top
        c.poly([(x + 10, y), (x + 13, y - 3), (x + 13, y + 7), (x + 10, y + 10)], dark)  # side
        c.rect(x, y, x + 9, y + 9, mid)                                              # front
        rows = {"A": [" # ", "# #", "###", "# #", "# #"],
                "B": ["## ", "# #", "## ", "# #", "## "],
                "C": [" ##", "#  ", "#  ", "#  ", " ##"]}[letter]
        for dy, row in enumerate(rows):
            for dx, ch in enumerate(row):
                if ch == "#":
                    c.set(x + 3 + dx, y + 2 + dy, WHITE)
    block(1, 19, RED, "A")
    block(15, 19, BLUE, "B")
    block(8, 8, GOLD, "C")


def draw_toy_music_box(c):
    """An open wooden music box: velvet inside, a mirror in the raised lid, a gold keyhole and crank,
    and a note floating out."""
    wood = [hexc("6a3a1c"), hexc("a4602e"), hexc("d89058")]
    c.poly([(9, 14), (11, 4), (28, 4), (26, 14)], wood[1])              # the lid, raised
    c.poly([(11, 13), (12.5, 6), (26, 6), (24.5, 13)], hexc("bfe6ff"))   # its mirror
    c.line(14, 7, 13, 11, WHITE)
    c.poly([(5, 18), (9, 14), (26, 14), (22, 18)], hexc("8a1a3a"))      # velvet inside
    c.rect(5, 18, 22, 28, wood[1])                                       # front
    c.rect(5, 18, 22, 19, wood[2])
    c.poly([(22, 18), (26, 14), (26, 24), (22, 28)], wood[0])           # side
    c.rect(5, 20, 22, 20, GOLD[1])                                       # gold trim
    c.rect(13, 23, 14, 25, OUTLINE)                                      # keyhole
    c.set(13, 22, GOLD[1]); c.set(14, 22, GOLD[1])
    c.line(26, 20, 29, 20, GOLD[1])                                      # crank
    c.line(29, 20, 29, 17, GOLD[1])
    c.disc(29, 16, 1.2, GOLD[2])
    c.disc(4, 11, 1.6, GOLD[1])                                          # a note
    c.line(5.5, 4, 5.5, 11, GOLD[1])
    c.line(5.5, 4, 8, 6, GOLD[1])


def draw_toy_ball(c):
    """A red rubber ball with a yellow band and a white star, bouncing: two little marks below."""
    c.disc(16, 13, 9.6, RED[1])
    c.shade(lambda x, y, col: col == RED[1] and 11 <= y <= 15, GOLD[1])
    light_top_left(c, RED, 16, 13, 10)
    c.shade(lambda x, y, col: col == GOLD[1] and (x - 16) + (y - 13) > 6, GOLD[0])
    star_shape(c, 16, 13, 5, WHITE)
    c.disc(10, 7, 1.4, hexc("ffd0d0"))                                   # shine
    c.line(8, 28, 12, 26, hexc("9ccaff"))                                # bounce marks
    c.line(24, 28, 20, 26, hexc("9ccaff"))


def draw_toy_bear(c):
    """A sitting teddy bear: round ears, a tan muzzle and belly, button eyes and a red bow."""
    dark, mid, light = BEAR
    tan = hexc("eccb96")
    c.disc(9, 6, 3, mid); c.disc(23, 6, 3, mid)                          # ears
    c.disc(9, 6, 1.4, tan); c.disc(23, 6, 1.4, tan)
    c.ellipse(16, 23, 7.5, 6.5, mid)                                     # body
    c.ellipse(8, 21, 2.6, 4, mid); c.ellipse(24, 21, 2.6, 4, dark)       # arms
    c.ellipse(10, 28, 3.6, 2.6, mid); c.ellipse(22, 28, 3.6, 2.6, dark)  # feet
    c.disc(10, 28.5, 1.4, tan); c.disc(22, 28.5, 1.4, tan)
    c.ellipse(16, 24, 4, 3.6, tan)                                       # belly
    c.disc(16, 11, 7, mid)                                               # head
    c.shade(lambda x, y, col: col == mid and (x - 16) + (y - 11) > 7, dark)
    c.shade(lambda x, y, col: col == mid and (x - 16) + (y - 11) < -6, light)
    c.ellipse(16, 14, 3.4, 2.4, tan)                                     # muzzle
    c.rect(15, 13, 17, 13, OUTLINE)                                      # nose
    c.set(16, 14, OUTLINE)
    c.set(12, 10, OUTLINE); c.set(20, 10, OUTLINE)                       # button eyes
    c.poly([(11, 16), (16, 18), (11, 20)], RED[1])                       # bow
    c.poly([(21, 16), (16, 18), (21, 20)], RED[1])
    c.disc(16, 18, 1.2, RED[2])


def draw_toy_bubbles(c):
    """A bubble wand: a thin lilac stick with a knob, a small open ring at its tip, and a big bubble
    floating off it with two little ones, each with a white and a pink shine."""
    film = (205, 232, 255, 70)
    c.line(5, 29, 13, 18, LILAC[1], width=2)                             # the stick
    c.disc(5, 29, 1.8, LILAC[0])                                         # its knob
    c.ring(15, 15, 3.6, 2.2, LILAC[1])                                   # the ring
    c.disc(15, 15, 2.1, film)
    for (x, y, r) in ((23, 8, 6.2), (8, 9, 2.6), (28, 19, 2.2)):         # bubbles
        c.disc(x, y, r - 0.9, film)
        c.ring(x, y, r, r - 1, hexc("9ccaff"))
        c.set(x - r * 0.45, y - r * 0.45, WHITE)
        c.set(x + r * 0.4, y + r * 0.35, hexc("ffb4dc"))
    c.set(21, 6, WHITE); c.set(20, 7, WHITE)                             # the big one's bright shine



# ---------------------------------------------------------------- the staff line
# Fairyland Online's 棒類 (staffs): one every 5 levels. Each is a shaft plus a head.

def staff_line(c, shaft, head, band=None):
    c.line(7, 28, 20, 10, shaft[1], width=3)
    c.line(8, 28, 21, 11, shaft[0])
    c.line(6, 27, 19, 9, shaft[2])
    if band:
        c.line(9, 23, 11, 25, band, width=2)
        c.line(16, 14, 18, 16, band, width=2)
    head(c)


def knob(color):
    def draw(c):
        c.disc(21.5, 8.5, 3.4, color[1])
        c.disc(20.5, 7.5, 1.4, color[2])
    return draw


def gem_head(cap, gem):
    def draw(c):
        c.disc(21.5, 8.5, 4, cap[1])
        c.disc(21.5, 8.5, 2.6, gem[1])
        c.disc(20.8, 7.8, 1, gem[2])
    return draw


def star_head(color):
    def draw(c):
        star_shape(c, 22, 8, 6.5, color[1], inner=0.5)
        star_shape(c, 21.5, 7.5, 3, color[2], inner=0.5)
    return draw


def bamboo(c):
    for t in (0.3, 0.55, 0.8):   # the joints
        x, y = 7 + 13 * t, 28 - 18 * t
        c.line(x - 1.5, y - 1, x + 1.5, y + 1, GREEN[0], width=1)
    c.disc(21, 9, 2.2, GREEN[1])
    c.line(20, 8, 24, 5, GREEN[2])                         # a leaf


def blossom(c):
    for (x, y, col) in ((20, 9, hexc("f06292")), (23.5, 7, hexc("f48fb1")), (23, 11.5, hexc("f8bbd0"))):
        for dx, dy in ((0, -1.6), (1.6, 0), (0, 1.6), (-1.6, 0)):   # four petals
            c.disc(x + dx, y + dy, 1.2, col)
        c.set(x, y, GOLD[1])


def mace(color):
    def draw(c):
        c.disc(21.5, 8.5, 4.2, color[1])
        c.disc(20.5, 7.5, 1.6, color[2])
        for (x, y) in ((21.5, 3.5), (26.5, 8.5), (21.5, 13.5), (16.5, 8.5)):   # studs
            c.disc(x, y, 1.1, color[0])
    return draw


def cloud(c):
    puff = hexc("f4f8ff")
    for (x, y, r) in ((19.5, 9.5, 2.6), (22.5, 7.5, 3.2), (25, 10, 2.4), (22, 10.5, 2.6)):
        c.disc(x, y, r, puff)
    c.shade(lambda x, y, col: col == puff and y >= 11, hexc("b8d0ec"))    # shaded underside
    c.shade(lambda x, y, col: col == puff and y <= 5, WHITE)


def crown(c):
    c.poly([(16, 11), (17, 4), (19.5, 8), (21.5, 3), (23.5, 8), (26, 4), (27, 11)], GOLD[1])
    c.rect(16, 10, 27, 12, GOLD[0])
    c.disc(21.5, 9, 1.4, RED[1])


def aurora(c):
    c.disc(21.5, 8.5, 4.2, hexc("7af0ff"))
    c.shade(lambda x, y, col: col == hexc("7af0ff") and x > 22, hexc("b48cff"))
    c.shade(lambda x, y, col: col == hexc("7af0ff") and y > 10, hexc("8af0a0"))
    c.disc(20, 7, 1.2, WHITE)


def wisp(c):
    c.disc(21.5, 9.5, 3.4, hexc("b48cff"))
    c.poly([(19, 8), (22, 1), (25, 8)], hexc("b48cff"))
    c.disc(20.5, 9.5, 0.8, WHITE); c.disc(23, 9.5, 0.8, WHITE)


def lightning(c):
    c.disc(21.5, 8.5, 4, NAVY[1])
    c.poly([(22, 3), (19, 9), (22, 9), (20, 14), (25, 7), (22, 7)], hexc("ffd84a"))


def crescent(c):
    moon = hexc("fff4b0")
    c.disc(21, 9, 5.5, moon)
    for y in range(SIZE):          # bite out a second circle to leave a crescent
        for x in range(SIZE):
            if c.px[y][x] == moon and (x - 23.8) ** 2 + (y - 6.8) ** 2 <= 4.4 ** 2:
                c.px[y][x] = None
    c.shade(lambda x, y, col: col == moon and x + y > 30, hexc("e8c860"))
    c.set(26, 13, WHITE); c.set(27, 4, WHITE)


def dragon(c):
    c.disc(21.5, 8.5, 3.6, hexc("ff6a3a"))
    c.disc(20.5, 7.5, 1.3, hexc("ffd84a"))
    for (x0, y0, x1, y1) in ((17, 5, 15, 1), (26, 5, 28, 1)):   # horns
        c.line(x0, y0, x1, y1, GOLD[1], width=2)
    c.line(17, 12, 15, 15, GOLD[1], width=2); c.line(26, 12, 28, 15, GOLD[1], width=2)   # claws


BAMBOO = [hexc("3a8a3e"), hexc("6ac25a"), hexc("b8f08a")]
RATTAN = [hexc("9a7040"), hexc("d0a468"), hexc("f0d09a")]
PALE = [hexc("b09060"), hexc("e8cc9a"), hexc("fff0cc")]
BROWN = [hexc("5a3a1a"), hexc("8a5a2b"), hexc("b07a44")]
TEAK = [hexc("8a4a1a"), hexc("c0702a"), hexc("e8a050")]
DARKWOOD = [hexc("3a2616"), hexc("5e3e22"), hexc("86603a")]
REDWOOD = [hexc("8a2a1a"), hexc("c0482a"), hexc("e87a50")]
BLOODWOOD = [hexc("5a1010"), hexc("8e1f22"), hexc("c0443a")]
YEW = [hexc("4a2a5a"), hexc("7a4a8a"), hexc("aa7ac0")]
IRON = [hexc("4a5260"), hexc("7b8798"), hexc("b9c4d2")]
BRONZE = hexc("b0782a")

STAFFS = [  # id, level, name, shaft, head, band, description
    ("bamboo_staff", 1, "Green Bamboo Staff", BAMBOO, bamboo, None, "Cut fresh from the grove behind the village."),
    ("rattan_staff", 5, "Rattan Staff", RATTAN, knob(RATTAN), None, "Bends, but never breaks."),
    ("heavy_rattan_staff", 10, "Heavy Rattan Staff", RATTAN, knob(RATTAN), BRONZE, "Bound with bronze for a proper swing."),
    ("lightwood_staff", 15, "Lightwood Staff", PALE, knob(PALE), None, "Light as a feather, quick as a thought."),
    ("brownwood_staff", 20, "Brownwood Staff", BROWN, knob(BROWN), BRONZE, "Old wood that remembers every spell."),
    ("blossom_staff", 25, "Blossom Staff", BROWN, blossom, None, "Scatters petals with every cast."),
    ("teak_staff", 30, "Teak Staff", TEAK, gem_head(COPPER, TEAL), None, "Polished teak with a sea-green stone."),
    ("heavywood_staff", 35, "Heavywood Staff", DARKWOOD, mace(IRON), None, "Capped in iron. Mages don't only cast."),
    ("red_cypress_staff", 40, "Red Cypress Staff", REDWOOD, knob(REDWOOD), GOLD[1], "Smells of warm forests."),
    ("blood_cypress_staff", 45, "Dusk Cypress Staff", BLOODWOOD, gem_head(GOLD, RED), None, "Its ruby glows before a fight."),
    ("yew_staff", 50, "Yew Staff", YEW, gem_head(STEEL, VIOLET), None, "Purple yew, hard as stone."),
    ("purple_star_staff", 55, "Violet Comet Staff", YEW, star_head(LILAC), None, "A little star is caught at the tip."),
    ("armorbreaker_staff", 60, "Shellsplitter Staff", DARKWOOD, mace(STEEL), None, "Cracks shells and spells alike."),
    ("ironcrusher_staff", 65, "Anvil Staff", IRON, mace(IRON), None, "Heavy iron through and through."),
    ("red_cloud_staff", 70, "Crimson Mist Staff", REDWOOD, cloud, GOLD[1], "A cloud rests on it like a hat."),
    ("titanium_sceptre", 75, "Titanium Sceptre", STEEL, gem_head(STEEL, BLUE), None, "Cold, bright and nearly weightless."),
    ("emperor_sceptre", 80, "Emperor's Sceptre", GOLD, crown, None, "Once held by a fairy-tale king."),
    ("aurora_staff", 85, "Aurora Staff", SNOW, aurora, None, "Holds the northern lights."),
    ("ghost_staff", 90, "Wraithwood Staff", YEW, wisp, None, "Something friendly lives inside. Probably."),
    ("sky_ending_staff", 95, "Skyreach Staff", NAVY, lightning, GOLD[1], "Said to split the sky in two."),
    ("luna_staff", 100, "Luna Staff", STEEL, crescent, None, "Brightest under a full moon."),
    ("dragon_god_staff", 105, "Wyrmking Staff", BLOODWOOD, dragon, GOLD[1], "The staff of the Wyrmking himself."),
]

for _id, _level, _name, _shaft, _head, _band, _desc in STAFFS:
    globals()["draw_" + _id] = (lambda shaft, head, band: lambda c: staff_line(c, shaft, head, band))(_shaft, _head, _band)

# ---------------------------------------------------------------- the sword, axe and whip lines
# Also one every 5 levels, named after the original's 劍類, 斧類 and 鞭類 crafting tables where the
# names are known. Recipes live in content/items.json.

def sword_line(c, blade, guard, grip, length=13, width=4, wavy=False, gem=None, wings=False):
    bx, by = 11, 20
    tx, ty = bx + length, by - length
    if wavy:
        for i in range(0, 41):
            t = i / 40
            wobble = math.sin(t * math.pi * 3) * 1.3 * (1 - t * 0.6)
            c.disc(bx + (tx - bx) * t + wobble * 0.7, by + (ty - by) * t + wobble * 0.7, width / 2, blade[1])
    else:
        c.line(bx, by, tx, ty, blade[1], width=width)
    c.line(bx + 1, by - 1, tx - 1, ty + 1, blade[2])                  # edge shine
    c.line(bx + 1, by + 1, tx, ty + 2, blade[0])                      # shadow side
    if width >= 5:
        c.line(bx + 2, by, tx - 1, ty + 3, blade[0])
    c.line(7, 17, 14, 24, guard[1], width=3)                          # crossguard
    c.line(7, 16, 13, 22, guard[2])
    if wings:
        c.poly([(7, 17), (3, 12), (9, 15)], guard[1])
        c.poly([(14, 24), (19, 28), (16, 22)], guard[1])
    c.line(9, 22, 5, 26, grip[1], width=3)                            # grip
    c.line(9, 23, 5, 27, grip[0])
    c.disc(4.5, 27.5, 1.8, guard[1])                                  # pommel
    if gem:
        c.disc(10.5, 20.5, 1.4, gem[1])
        c.set(10, 20, gem[2])


def axe_line(c, head, handle, style="axe", gem=None):
    top = (23, 4) if style == "halberd" else (21, 7)
    c.line(8, 28, top[0], top[1], handle[1], width=3)
    c.line(9, 28, top[0] + 1, top[1] + 1, handle[0])
    if style == "hatchet":
        c.poly([(19, 6), (24, 2), (30, 6), (29, 14), (22, 12)], head[1])
        c.line(25, 3, 29, 7, head[2]); c.line(29, 8, 29, 13, head[2])
    elif style == "crescent":
        c.poly([(17, 6), (25, 1), (30, 6), (30, 13), (26, 18), (20, 14)], head[1])
        c.line(26, 2, 30, 7, head[2]); c.line(30, 8, 29, 13, head[2])
    else:
        c.poly([(18, 6), (27, 3), (29, 13), (22, 15)], head[1])
        c.line(27, 4, 29, 12, head[2])
    if style in ("double", "crescent"):
        c.poly([(19, 7), (10, 3), (8, 12), (16, 14)], head[1])
        c.line(10, 4, 8, 11, head[2])
    if style == "halberd":
        c.line(23, 4, 26, 0, head[2], width=2)                        # the spike
    edge = 39 if style == "hatchet" else 36
    c.shade(lambda x, y, col: col == head[1] and x + y > edge, head[0])
    c.shade(lambda x, y, col: col == head[1] and x < 13 and y > 9, head[0])
    c.rect(19, 7, 22, 12, handle[0])
    if gem:
        c.disc(20.5, 9.5, 1.5, gem[1])
        c.set(20, 9, gem[2])


def whip_line(c, leather, grip, turns=3.2, tip=None, gem=None, studs=None):
    points = 60
    for i in range(points):
        t = i / points * math.pi * turns
        r = 3 + i * 0.13
        x, y = 17 + r * math.cos(t), 14 + r * math.sin(t) * 0.8
        c.disc(x, y, 1.1, leather[1])
        if studs and i % 9 == 4:
            c.set(x, y, studs)
    c.shade(lambda x, y, col: col == leather[1] and x + y > 34, leather[0])
    c.shade(lambda x, y, col: col == leather[1] and x + y < 22, leather[2])
    if tip:
        c.disc(17 + 3, 14, 1.8, tip)
    c.line(6, 28, 11, 21, grip[1], width=3)
    c.line(7, 28, 12, 22, grip[0])
    c.rect(10, 20, 13, 22, GOLD[1])
    if gem:
        c.disc(5.5, 28.5, 1.7, gem[1])
        c.set(5, 28, gem[2])


# Metals, from the bronze of a first sword to the tungsten of the level-80 dragonslayer.
BRONZE3 = [hexc("7a4a1a"), hexc("b0782a"), hexc("e8b060")]
SILVER = [hexc("8a92a8"), hexc("d0d6e4"), hexc("ffffff")]
ALLOY = [hexc("4e6a66"), hexc("88aaa4"), hexc("d0eee8")]
PLATINUM = [hexc("8a84a8"), hexc("dcd8f0"), hexc("ffffff")]
TITANIUM = [hexc("3e5a84"), hexc("7c9cc8"), hexc("d4e6ff")]
TUNGSTEN = [hexc("3a3448"), hexc("6a6480"), hexc("b0aac8")]
DRAGONSTEEL = [hexc("5a1418"), hexc("a02a2a"), hexc("ff9a6a")]
ICE = [hexc("4a8ab0"), hexc("9ad8f0"), hexc("f0ffff")]
SHADOW = [hexc("2a1e3a"), hexc("4a3a6a"), hexc("9a8ac8")]
AMBER = [hexc("a0600a"), hexc("e8a020"), hexc("ffe08a")]
EMERALD = [hexc("0e6a3a"), hexc("22b060"), hexc("9af0b8")]
DIAMOND = [hexc("7ab0d0"), hexc("d8f4ff"), WHITE]
SHEEP = [hexc("c8b890"), hexc("f0e6cc"), WHITE]
COWHIDE = [hexc("5a3a22"), hexc("8a5a36"), hexc("c09068")]
DEER = [hexc("8a5a2a"), hexc("c08a4a"), hexc("ecc088")]
MARTEN = [hexc("4a3020"), hexc("6e4a30"), hexc("a07a5a")]
CROC = [hexc("2e4a22"), hexc("4e7a36"), hexc("9ac068")]

SWORDS = [  # id, level, name, drawing, description
    ("novice_bronze_sword", 1, "Novice Bronze Sword", dict(blade=BRONZE3, guard=BRONZE3, grip=LEATHER, length=11), "Every hero's first real blade."),
    ("bronze_sword", 5, "Bronze Sword", dict(blade=BRONZE3, guard=BRONZE3, grip=LEATHER, length=12), "Warm-coloured and dependable."),
    ("bronze_broadsword", 10, "Bronze Broadsword", dict(blade=BRONZE3, guard=BRONZE3, grip=LEATHER, width=5), "Wide enough to hide behind. Almost."),
    ("bronze_longsword", 15, "Bronze Longsword", dict(blade=BRONZE3, guard=GOLD, grip=LEATHER, length=15), "A longer reach for a braver fighter."),
    ("copper_sword", 20, "Copper Sword", dict(blade=COPPER, guard=COPPER, grip=LEATHER, length=13), "Polished until it glows like sunset."),
    ("iron_longsword", 25, "Iron Longsword", dict(blade=IRON, guard=IRON, grip=LEATHER, length=15), "Plain iron, honestly forged."),
    ("silver_inlaid_longsword", 30, "Silver-Inlaid Longsword", dict(blade=IRON, guard=SILVER, grip=NAVY, length=15, gem=SILVER), "Iron with a silver thread down the fuller."),
    ("silver_sword", 35, "Silver Sword", dict(blade=SILVER, guard=SILVER, grip=NAVY, length=14), "Ghosts don't like it one bit."),
    ("blue_frost_sword", 40, "Blue Frost Sword", dict(blade=ICE, guard=SILVER, grip=NAVY, length=15, gem=BLUE), "Cold to the touch, even in the desert."),
    ("tempered_steel_sword", 45, "Tempered Steel Sword", dict(blade=STEEL, guard=STEEL, grip=LEATHER, length=15, width=5), "Folded steel, quenched in snowmelt."),
    ("golden_sword", 50, "Golden Sword", dict(blade=GOLD, guard=GOLD, grip=RED, length=14, gem=RED), "Heavy, gaudy and surprisingly sharp."),
    ("silver_steel_sword", 55, "Silver Steel Sword", dict(blade=SILVER, guard=STEEL, grip=NAVY, length=15, width=5, gem=TEAL), "Steel for strength, silver for shine."),
    ("serpent_sword", 60, "Serpent Sword", dict(blade=STEEL, guard=GREEN, grip=GREEN, length=15, wavy=True, gem=EMERALD), "The blade winds like a snake."),
    ("alloy_shortsword", 65, "Alloy Shortsword", dict(blade=ALLOY, guard=ALLOY, grip=LEATHER, length=11, width=5), "Short, light and very quick."),
    ("platinum_longsword", 70, "Platinum Longsword", dict(blade=PLATINUM, guard=GOLD, grip=VIOLET, length=15, gem=VIOLET), "Never rusts, never dulls."),
    ("ironcleaver_sword", 75, "Ironcleaver", dict(blade=TITANIUM, guard=STEEL, grip=NAVY, length=15, width=5, wings=True), "Cuts through iron like bread."),
    ("tungsten_dragonslayer", 80, "Tungsten Dragonslayer", dict(blade=TUNGSTEN, guard=DRAGON, grip=DRAGON, length=15, width=5, wings=True, gem=RED), "Forged for one purpose."),
    ("aurora_blade", 85, "Aurora Blade", dict(blade=ICE, guard=LILAC, grip=VIOLET, length=15, gem=TEAL, wings=True), "Shimmers green and violet when swung."),
    ("phantom_blade", 90, "Phantom Blade", dict(blade=SHADOW, guard=LILAC, grip=SHADOW, length=15, wavy=True, gem=LILAC), "Hard to see, harder to dodge."),
    ("sky_splitter", 95, "Sky Splitter", dict(blade=SNOW, guard=GOLD, grip=NAVY, length=15, width=5, wings=True, gem=BLUE), "Leaves a line of clear sky behind it."),
    ("moonlight_sword", 100, "Moonlight Sword", dict(blade=PLATINUM, guard=SILVER, grip=NAVY, length=15, wings=True, gem=SNOW), "Brightest under a full moon."),
    ("dragon_god_sword", 105, "Wyrmking Sword", dict(blade=DRAGONSTEEL, guard=GOLD, grip=DRAGON, length=15, width=5, wings=True, gem=AMBER), "The sword of the Wyrmking himself."),
]

AXES = [
    ("novice_axe", 1, "Novice Axe", dict(head=BRONZE3, handle=WOOD, style="hatchet"), "Small, but it bites."),
    ("small_hatchet", 5, "Small Hatchet", dict(head=IRON, handle=WOOD, style="hatchet"), "Good for kindling and for goblins."),
    ("wood_axe", 10, "Woodcutter's Axe", dict(head=IRON, handle=WOOD), "Borrowed from the mill. Please return it."),
    ("hand_axe", 15, "Hand Axe", dict(head=BRONZE3, handle=TEAK), "Balanced for one hand."),
    ("copper_plate_axe", 20, "Copper Plate Axe", dict(head=COPPER, handle=TEAK), "A broad copper head riveted on tight."),
    ("light_war_axe", 25, "Light War Axe", dict(head=COPPER, handle=REDWOOD, style="double"), "Two edges, half the weight."),
    ("windchaser_axe", 30, "Windchaser Axe", dict(head=SILVER, handle=REDWOOD, gem=TEAL), "Whistles as it flies."),
    ("iron_bead_axe", 35, "Iron Bead Axe", dict(head=IRON, handle=REDWOOD, gem=IRON), "An iron bead weights the blow."),
    ("curved_war_axe", 40, "Curved War Axe", dict(head=IRON, handle=YEW, style="crescent"), "The long curve bites deep."),
    ("steel_axe", 45, "Steel Axe", dict(head=STEEL, handle=YEW), "Plain, hard and heavy."),
    ("twin_blade_axe", 50, "Twin-Blade Axe", dict(head=STEEL, handle=DARKWOOD, style="double"), "Dwarves swear by it."),
    ("long_war_axe", 55, "Long War Axe", dict(head=GOLD, handle=DARKWOOD, style="halberd"), "Keeps big monsters at arm's length."),
    ("grey_dragon_axe", 60, "Grey Dragon Axe", dict(head=ALLOY, handle=DARKWOOD, style="crescent", gem=RED), "Carved with a sleeping grey dragon."),
    ("overlord_axe", 65, "Overlord Axe", dict(head=ALLOY, handle=IRON, style="double", gem=GOLD), "Made for someone who gives orders."),
    ("alloy_twin_war_axe", 70, "Alloy Twin War Axe", dict(head=PLATINUM, handle=IRON, style="double", gem=VIOLET), "Two alloy heads, both hungry."),
    ("titanium_dwarf_axe", 75, "Titanium Dwarf Axe", dict(head=TITANIUM, handle=BLOODWOOD, style="crescent"), "Dwarf-made. It says so on the handle."),
    ("tungsten_skybreaker", 80, "Tungsten Skybreaker", dict(head=TUNGSTEN, handle=BLOODWOOD, style="halberd", gem=BLUE), "Said to crack the sky itself."),
    ("aurora_axe", 85, "Aurora Axe", dict(head=ICE, handle=SNOW, style="crescent", gem=TEAL), "Holds the northern lights in its edge."),
    ("phantom_axe", 90, "Phantom Axe", dict(head=SHADOW, handle=YEW, style="double", gem=LILAC), "It swings a moment before you do."),
    ("thunder_god_axe", 95, "Thunder God Axe", dict(head=GOLD, handle=NAVY, style="crescent", gem=BLUE), "Every blow comes with a rumble."),
    ("luna_axe", 100, "Luna Axe", dict(head=PLATINUM, handle=STEEL, style="crescent", gem=SNOW), "Its edge is a slice of the moon."),
    ("dragon_god_axe", 105, "Wyrmking Axe", dict(head=DRAGONSTEEL, handle=BLOODWOOD, style="double", gem=AMBER), "The axe of the Wyrmking himself."),
]

WHIPS = [
    ("sheepskin_whip", 1, "Sheepskin Whip", dict(leather=SHEEP, grip=WOOD, turns=2.4), "Soft enough to tickle."),
    ("handy_whip", 5, "Handy Whip", dict(leather=SHEEP, grip=LEATHER, turns=2.8), "Just the right length."),
    ("cowhide_whip", 10, "Cowhide Whip", dict(leather=COWHIDE, grip=WOOD), "Cracks loud enough to startle birds."),
    ("strong_ox_whip", 15, "Strong Ox Whip", dict(leather=COWHIDE, grip=LEATHER, studs=STEEL[1]), "Braided from the toughest hide."),
    ("whitewood_whip", 20, "Whitewood Whip", dict(leather=COWHIDE, grip=PALE, tip=CLOTH[1]), "A pale poplar handle, well worn."),
    ("cactus_whip", 25, "Cactus Whip", dict(leather=GREEN, grip=PALE, studs=GREEN[2]), "Prickly. Hold it by the handle."),
    ("teak_whip", 30, "Teak Whip", dict(leather=DEER, grip=TEAK), "A teak handle and a deerskin lash."),
    ("golden_deer_whip", 35, "Golden Deer Whip", dict(leather=DEER, grip=TEAK, tip=GOLD[1]), "Tipped in gold, like a deer's antler."),
    ("red_cypress_whip", 40, "Red Cypress Whip", dict(leather=DEER, grip=REDWOOD, tip=RED[1]), "Smells of warm forests."),
    ("deerhide_lash", 45, "Deerhide Lash", dict(leather=DEER, grip=YEW, turns=3.6, studs=GOLD[1]), "Long enough to reach the back row."),
    ("blue_sky_whip", 50, "Blue Sky Whip", dict(leather=BLUE, grip=PALE, gem=BLUE), "The colour of a clear morning."),
    ("amber_whip", 55, "Amber Whip", dict(leather=MARTEN, grip=RATTAN, gem=AMBER), "An amber stone set in the pommel."),
    ("power_whip", 60, "Power Whip", dict(leather=MARTEN, grip=TEAK, gem=RED, studs=GOLD[1]), "Hits harder than it has any right to."),
    ("hardened_whip", 65, "Hardened Whip", dict(leather=CROC, grip=DARKWOOD, gem=DIAMOND, studs=STEEL[1]), "Crocodile hide, hard as armour."),
    ("crocodile_whip", 70, "Crocodile Whip", dict(leather=CROC, grip=DARKWOOD, turns=3.6, tip=CROC[2], gem=EMERALD), "Snaps shut like jaws."),
    ("thorn_whip", 75, "Thorn Whip", dict(leather=GREEN, grip=BLOODWOOD, studs=RED[1], gem=RED), "Grown, not braided."),
    ("azure_dragon_whip", 80, "Azure Dragon Whip", dict(leather=TEAL, grip=BLOODWOOD, tip=TEAL[2], gem=BLUE, studs=SNOW[2]), "Scaled like the Azure Dragon of the east."),
    ("aurora_whip", 85, "Aurora Whip", dict(leather=ICE, grip=SNOW, tip=LILAC[2], gem=TEAL), "Trails light when it cracks."),
    ("phantom_whip", 90, "Phantom Whip", dict(leather=SHADOW, grip=YEW, tip=LILAC[1], gem=LILAC), "It cracks without a sound."),
    ("storm_whip", 95, "Storm Whip", dict(leather=NAVY, grip=NAVY, tip=hexc("ffd84a"), gem=GOLD, studs=hexc("ffd84a")), "Lightning follows the lash."),
    ("luna_whip", 100, "Luna Whip", dict(leather=SILVER, grip=STEEL, turns=3.6, tip=hexc("fff4b0"), gem=SNOW), "Silver as moonlight on water."),
    ("dragon_god_whip", 105, "Wyrmking Whip", dict(leather=DRAGON, grip=BLOODWOOD, turns=3.6, tip=GOLD[1], gem=AMBER, studs=GOLD[1]), "The whip of the Wyrmking himself."),
]

for _id, _level, _name, _args, _desc in SWORDS:
    globals()["draw_" + _id] = (lambda a: lambda c: sword_line(c, **a))(_args)
for _id, _level, _name, _args, _desc in AXES:
    globals()["draw_" + _id] = (lambda a: lambda c: axe_line(c, **a))(_args)
for _id, _level, _name, _args, _desc in WHIPS:
    globals()["draw_" + _id] = (lambda a: lambda c: whip_line(c, **a))(_args)


# ---------------------------------------------------------------- crafting materials
# The original's woodcutting (伐木), mining and smelting (挖礦, 冶煉) and hides, dropped by monsters here.

def log(c, bark, core):
    c.line(7, 23, 22, 12, bark[1], width=9)
    c.shade(lambda x, y, col: col == bark[1] and x + y > 32, bark[0])
    c.shade(lambda x, y, col: col == bark[1] and x + y < 26, bark[2])
    for (x0, y0, x1, y1) in ((6, 20, 11, 17), (10, 25, 15, 22), (14, 17, 18, 14)):   # bark grain
        c.line(x0, y0, x1, y1, bark[0])
    c.disc(23, 11.5, 4.3, core[1])                                                     # cut end
    c.ring(23, 11.5, 3, 2.2, core[0])
    c.set(23, 11, core[0])
    c.shade(lambda x, y, col: col == core[1] and x + y < 32, core[2])


def bamboo_bundle(c):
    for dx in (0, 5, 10):
        c.line(6 + dx, 28, 12 + dx, 4, BAMBOO[1], width=3)
        c.line(7 + dx, 28, 13 + dx, 4, BAMBOO[0])
        for t in (0.3, 0.6, 0.85):
            c.line(5 + dx + 6 * t, 28 - 24 * t, 8 + dx + 6 * t, 28 - 24 * t, BAMBOO[0])
    c.line(20, 6, 26, 3, BAMBOO[2], width=2)


def rattan_coil(c):
    c.ring(16, 17, 10, 6.5, RATTAN[1], ry_scale=0.8)
    c.ring(16, 17, 8.2, 7.4, RATTAN[0], ry_scale=0.8)
    c.shade(lambda x, y, col: col == RATTAN[1] and y < 13, RATTAN[2])
    c.line(24, 14, 29, 9, RATTAN[1], width=2)


def ingot(c, metal):
    dark, mid, light = metal
    c.poly([(10, 10), (22, 10), (25, 15), (7, 15)], light)         # top
    c.poly([(7, 15), (25, 15), (28, 25), (4, 25)], mid)           # sloped front
    c.shade(lambda x, y, col: col == mid and x > 22, dark)
    c.rect(4, 24, 28, 25, dark)
    c.line(11, 12, 17, 12, WHITE)
    c.line(8, 17, 7, 22, light)


def gem(c, color):
    dark, mid, light = color
    c.poly([(10, 8), (22, 8), (28, 14), (16, 28), (4, 14)], mid)
    c.poly([(10, 8), (22, 8), (28, 14), (4, 14)], light)
    c.shade(lambda x, y, col: col == mid and x > 17, dark)
    c.line(4, 14, 28, 14, dark)
    c.line(13, 8, 11, 14, mid); c.line(19, 8, 21, 14, mid)
    c.set(11, 10, WHITE); c.set(12, 10, WHITE)


def banded(c, color):
    """A tumbled stone with curved stripes (agate)."""
    dark, mid, light = color
    for y in range(SIZE):
        for x in range(SIZE):
            if ((x - 16) / 11) ** 2 + ((y - 17) / 9) ** 2 <= 1:
                band = int(math.hypot(x - 8, y - 27) / 2.6) % 3
                c.px[y][x] = (mid, light, mid)[band] if x + y < 38 else (dark, mid, dark)[band]
    c.set(11, 11, WHITE); c.set(12, 11, WHITE)


def pearl(c):
    pearl_c = [hexc("c07a3a"), hexc("ffb070"), hexc("fff0d0")]
    c.disc(16, 17, 9, pearl_c[1])
    light_top_left(c, pearl_c, 16, 17, 9)
    c.disc(12.5, 13.5, 2, WHITE)
    for (x0, y0, x1, y1) in ((6, 27, 9, 22), (26, 27, 23, 22)):   # a dragon's claws hold it
        c.line(x0, y0, x1, y1, GOLD[1], width=2)


def hide(c, color, spots=None, scales=False):
    dark, mid, light = color
    c.poly([(9, 5), (23, 5), (26, 9), (24, 15), (28, 23), (22, 28), (16, 25), (10, 28), (4, 23), (8, 15), (6, 9)], mid)
    c.shade(lambda x, y, col: col == mid and x > 20, dark)
    c.shade(lambda x, y, col: col == mid and x < 11 and y < 14, light)
    if spots:
        for (x, y, r) in ((12, 11, 2.2), (19, 17, 2.8), (13, 21, 1.8), (21, 9, 1.4)):
            c.disc(x, y, r, spots)
    if scales:
        for y in range(8, 25, 4):
            for x in range(8 + (y // 4 % 2) * 2, 25, 4):
                if c.get(x, y) in (mid, dark, light):
                    c.set(x, y, dark); c.set(x + 1, y + 1, light)


MATERIALS = [  # id, kind, level, name, drawing, description
    ("bamboo", "wood", 1, "Bamboo", bamboo_bundle, "Green bamboo canes. Wood for beginner weapons."),
    ("rattan", "wood", 5, "Rattan", rattan_coil, "Bendy rattan, good for handles."),
    ("poplar", "wood", 10, "White Poplar", lambda c: log(c, PALE, CLOTH), "Pale, light wood."),
    ("teak", "wood", 20, "Teak", lambda c: log(c, TEAK, RATTAN), "Oily wood that never warps."),
    ("red_cypress", "wood", 30, "Red Cypress", lambda c: log(c, REDWOOD, ORANGE), "Warm red wood with a forest smell."),
    ("yew", "wood", 40, "Yew", lambda c: log(c, YEW, LILAC), "Purple-hearted and hard as stone."),
    ("ebony", "wood", 50, "Ebony", lambda c: log(c, DARKWOOD, BROWN), "Almost black, and very heavy."),
    ("hemlock", "wood", 60, "Iron Hemlock", lambda c: log(c, IRON, PALE), "Grey bark, iron-hard core."),
    ("red_yew", "wood", 70, "Red Yew", lambda c: log(c, BLOODWOOD, REDWOOD), "The rarest wood in the kingdom."),
    ("bronze_ingot", "metal", 1, "Bronze Ingot", lambda c: ingot(c, BRONZE3), "Smelted from copper and tin."),
    ("copper_ingot", "metal", 15, "Copper Ingot", lambda c: ingot(c, COPPER), "Soft and shiny."),
    ("iron_ingot", "metal", 25, "Iron Ingot", lambda c: ingot(c, IRON), "The blacksmith's bread and butter."),
    ("silver_ingot", "metal", 30, "Silver Ingot", lambda c: ingot(c, SILVER), "Bright, and hated by ghosts."),
    ("gold_ingot", "metal", 40, "Gold Ingot", lambda c: ingot(c, GOLD), "Heavy and handsome."),
    ("steel_ingot", "metal", 45, "Steel Ingot", lambda c: ingot(c, STEEL), "Iron, made much tougher."),
    ("alloy_steel", "metal", 60, "Alloy Steel", lambda c: ingot(c, ALLOY), "Steel mixed with something secret."),
    ("platinum_ingot", "metal", 70, "Platinum Ingot", lambda c: ingot(c, PLATINUM), "Never tarnishes."),
    ("titanium_alloy", "metal", 75, "Titanium Alloy", lambda c: ingot(c, TITANIUM), "Light as wood, strong as steel."),
    ("tungsten_alloy", "metal", 80, "Tungsten Alloy", lambda c: ingot(c, TUNGSTEN), "Dense enough to dent an anvil."),
    ("dragon_steel", "metal", 90, "Dragon Steel", lambda c: ingot(c, DRAGONSTEEL), "Forged in dragon fire. Still warm."),
    ("amber", "gem", 10, "Amber", lambda c: gem(c, AMBER), "Honey-coloured and warm."),
    ("cats_eye", "gem", 25, "Cat's Eye", lambda c: gem(c, [hexc("6a7a1a"), hexc("b8c83a"), hexc("f0ff9a")]), "Seems to follow you around the room."),
    ("emerald", "gem", 35, "Emerald", lambda c: gem(c, EMERALD), "Deep forest green."),
    ("azurite", "gem", 45, "Azurite", lambda c: gem(c, BLUE), "The blue of a clear sky."),
    ("topaz", "gem", 50, "Topaz", lambda c: gem(c, [hexc("c0a010"), hexc("ffe84a"), hexc("fffac0")]), "A little piece of sunshine."),
    ("agate", "gem", 55, "Agate", lambda c: banded(c, [hexc("a0304a"), hexc("e06a7a"), hexc("ffc0c8")]), "Banded in orange and cream."),
    ("diamond", "gem", 65, "Diamond", lambda c: gem(c, DIAMOND), "The hardest thing there is."),
    ("chalcedony", "gem", 75, "Chalcedony", lambda c: gem(c, TEAL), "Milky blue-green jade."),
    ("dragon_pearl", "gem", 90, "Dragon Pearl", pearl, "A dragon guarded this for a thousand years."),
    ("sheepskin", "hide", 1, "Sheepskin", lambda c: hide(c, SHEEP), "Soft and woolly."),
    ("cowhide", "hide", 10, "Cowhide", lambda c: hide(c, CLOTH, spots=COWHIDE[1]), "Tough, patchy leather."),
    ("deer_hide", "hide", 30, "Deer Hide", lambda c: hide(c, DEER, spots=CLOTH[2]), "Supple and strong."),
    ("marten_fur", "hide", 50, "Marten Fur", lambda c: hide(c, MARTEN), "Glossy dark fur."),
    ("crocodile_hide", "hide", 60, "Crocodile Hide", lambda c: hide(c, CROC, scales=True), "Hard and scaly."),
    ("dragon_scale", "hide", 75, "Dragon Scale", lambda c: hide(c, DRAGON, scales=True), "Fireproof, and very rare."),
]

for _id, _kind, _level, _name, _draw, _desc in MATERIALS:
    globals()["draw_" + _id] = _draw


# ---------------------------------------------------------------- a quest's pieces
# What a quest asks you to bring (content/quests.json `bring`): won from its monsters, found in a
# chest, carved or pieced together from the bag (items.json `make`).

def draw_tuft_of_wool(c):
    """A soft cloud of lamb's wool, a nibbled bite out of one side."""
    for (x, y, r) in ((12, 18, 7), (19, 15, 7.5), (21, 21, 6), (14, 23, 5.5)):
        c.disc(x, y, r, SHEEP[1])
    for (x, y) in ((7, 22), (8, 23), (7, 23)):          # the bite
        c.set(x, y, None)
    c.shade(lambda x, y, col: col == SHEEP[1] and x + y > 40, SHEEP[0])
    c.shade(lambda x, y, col: col == SHEEP[1] and x + y < 26, SHEEP[2])
    for (x, y) in ((13, 15), (18, 11), (22, 17), (16, 20)):
        c.set(x, y, SHEEP[0])                        # curls


def draw_driftwood_piece(c):
    """A sea-worn branch, silver-grey, a knot in it and a curl of weed."""
    drift = [hexc("8a7e70"), hexc("c4b8a4"), hexc("eee6d4")]
    c.line(5, 23, 27, 10, drift[1], width=5)
    c.line(19, 14, 23, 20, drift[1], width=3)            # a stub of a branch
    c.shade(lambda x, y, col: col == drift[1] and x + y > 31, drift[0])
    c.shade(lambda x, y, col: col == drift[1] and x + y < 27, drift[2])
    c.ring(14, 18, 2.2, 1, drift[0])                      # a knot
    c.line(8, 21, 24, 12, drift[2])                      # grain
    c.line(25, 9, 29, 14, GREEN[0])                      # a curl of seaweed
    c.set(28, 15, GREEN[1])


def draw_driftwood_flute(c):
    """A little flute carved from driftwood, finger holes along it and a cord at its end."""
    drift = [hexc("8a7e70"), hexc("c4b8a4"), hexc("eee6d4")]
    c.line(5, 26, 26, 5, drift[1], width=5)
    c.shade(lambda x, y, col: col == drift[1] and x + y > 31, drift[0])
    c.shade(lambda x, y, col: col == drift[1] and x + y < 30, drift[2])
    c.disc(24.5, 6.5, 1.2, drift[0])                     # the mouthpiece
    for t in (0.3, 0.42, 0.54, 0.66):                    # finger holes
        c.disc(5 + 21 * t, 26 - 21 * t, 0.8, OUTLINE)
    c.line(6, 25, 3, 30, RED[1])                         # a red cord
    c.set(2, 30, RED[2])


def draw_sailcloth_scrap(c):
    """A torn corner of sailcloth, a seam stitched across it and a brass ring at its corner."""
    c.poly([(5, 6), (26, 5), (24, 13), (27, 19), (20, 22), (22, 27), (9, 26), (6, 18), (8, 12)], CLOTH[1])
    c.shade(lambda x, y, col: col == CLOTH[1] and x + y > 36, CLOTH[0])
    c.shade(lambda x, y, col: col == CLOTH[1] and x + y < 20, CLOTH[2])
    for x in range(7, 24, 2):                            # the seam
        c.set(x, 11 + (x % 4 == 1), CLOTH[0])
    c.ring(7.5, 8, 2.6, 1.4, GOLD[1])                   # a grommet
    c.line(14, 16, 20, 15, NAVY[1])                       # a stripe of the old sail's blue
    c.line(13, 17, 19, 16, NAVY[0])


def draw_starwood(c):
    """A pale log that glows: starlight caught in its grain."""
    log(c, [hexc("8a9ab8"), hexc("c4d4ee"), hexc("f2f8ff")], [hexc("8a8ad8"), hexc("c8c8ff"), WHITE])
    for (x, y) in ((9, 21), (14, 19), (12, 16)):         # sparks in the bark
        c.set(x, y, GOLD[2])
    c.set(23, 11, GOLD[2])


def draw_star_figurehead(c):
    """A carved maiden holding a gold star up over her head, her hair streaming back like waves."""
    c.line(17, 9, 25, 15, TEAK[1], width=3)                              # her hair, streaming back
    c.line(18, 12, 26, 21, TEAK[0], width=2)
    c.poly([(9, 28), (13, 15), (19, 15), (22, 28)], RATTAN[1])            # her gown, carved
    c.shade(lambda x, y, col: col == RATTAN[1] and x > 18, RATTAN[0])
    c.shade(lambda x, y, col: col == RATTAN[1] and x < 13, RATTAN[2])
    for y in (19, 23):                                                   # folds
        c.line(12, y, 20, y + 1, RATTAN[0])
    c.disc(16, 11.5, 3.4, PALE[1])                                       # her face, paler wood
    c.set(17, 11, OUTLINE)                                               # an eye
    c.shade(lambda x, y, col: col == PALE[1] and x + y < 25, PALE[2])
    c.line(13, 14, 10.5, 7, PALE[1], width=2)                            # her arm, raised
    for k in range(10):                                                  # the gold star
        r = 4.2 if k % 2 == 0 else 1.9
        a = -math.pi / 2 + k * math.pi / 5
        c.line(10.5, 4.5, 10.5 + r * math.cos(a), 4.5 + r * math.sin(a), GOLD[1])
    c.set(10, 4, GOLD[2])
    c.line(10, 28, 21, 28, TEAK[0], width=2)                             # her plinth


def chart_paper(c, points):
    """A torn piece of old sea chart: parchment with a faint grid."""
    paper = [hexc("b8945a"), hexc("ecd29a"), hexc("fff2cc")]
    c.poly(points, paper[1])
    c.shade(lambda x, y, col: col == paper[1] and x + y > 40, paper[0])
    c.shade(lambda x, y, col: col == paper[1] and x + y < 18, paper[2])
    c.shade(lambda x, y, col: col in paper and (x % 7 == 3 or y % 7 == 3), hexc("d8bc84"))


def draw_chart_piece_compass(c):
    """The chart's corner with a compass rose on it."""
    chart_paper(c, [(4, 4), (27, 4), (24, 11), (28, 18), (21, 22), (25, 28), (4, 28)])
    for (dx, dy) in ((0, -6), (6, 0), (0, 6), (-6, 0)):                 # the rose
        c.line(12, 16, 12 + dx, 16 + dy, NAVY[1])
    c.line(12, 16, 12, 9, RED[1])                                       # north, in red
    c.disc(12, 16, 1.2, GOLD[1])


def draw_chart_piece_reef(c):
    """The chart's middle: a reef, and a dotted way through it."""
    chart_paper(c, [(6, 3), (25, 5), (28, 12), (24, 18), (27, 28), (8, 27), (4, 20), (7, 12)])
    for (x, y, r) in ((11, 10, 2), (15, 13, 1.6), (20, 9, 1.8), (18, 20, 2.2), (10, 21, 1.5)):
        c.disc(x, y, r, TEAL[0])                                       # the rocks
    for t in range(0, 9):                                               # the safe way, dotted
        c.set(7 + t * 2.3, 26 - t * 2.4, RED[1])


def draw_chart_piece_isle(c):
    """The chart's corner with a star-shaped island drawn on it."""
    chart_paper(c, [(5, 4), (28, 4), (28, 28), (9, 28), (5, 21), (9, 15), (4, 9)])
    for k in range(10):                                                 # the island, a star
        r = 6 if k % 2 == 0 else 2.8
        a = -math.pi / 2 + k * math.pi / 5
        c.line(19, 15, 19 + r * math.cos(a), 15 + r * math.sin(a), GREEN[1])
    c.disc(19, 15, 2, GREEN[1])
    c.set(19, 15, GOLD[2])
    c.line(10, 25, 15, 21, RED[1])                                      # an X near it
    c.line(10, 21, 15, 25, RED[1])


def draw_star_chart(c):
    """The whole chart, pieced together, rolled a little at the top, a gold star on the island."""
    chart_paper(c, [(4, 6), (28, 6), (28, 28), (4, 28)])
    c.line(4, 6, 28, 6, hexc("b8945a"), width=3)                       # rolled at the top
    c.line(12, 7, 10, 28, hexc("b8945a"))                                # where the pieces meet
    c.line(20, 7, 22, 28, hexc("b8945a"))
    for (dx, dy) in ((0, -4), (4, 0), (0, 4), (-4, 0)):                  # the rose
        c.line(7, 22, 7 + dx, 22 + dy, NAVY[1])
    for t in range(0, 6):                                                # the way through the reef
        c.set(11 + t * 2, 23 - t * 1.6, RED[1])
    for k in range(10):                                                  # the island
        r = 4 if k % 2 == 0 else 1.8
        a = -math.pi / 2 + k * math.pi / 5
        c.line(24, 13, 24 + r * math.cos(a), 13 + r * math.sin(a), GOLD[1])
    c.set(24, 13, GOLD[2])


# ---------------------------------------------------------------- Starfall Isle
# Glimmerbough's quests (content/quests.json) and the Fallen Star's spoils (its `drops`).

STARLIGHT = [hexc("b89a40"), hexc("fff0a0"), WHITE]
NIGHT = [hexc("1a1e5a"), hexc("2e3a9a"), hexc("6a7ae0")]
MOTH = [hexc("4a2aa0"), hexc("8a5ae8"), hexc("d0b8ff")]
STARGLASS = [hexc("4a8ab8"), hexc("a8e0ff"), WHITE]


def glint(c, x, y, color=WHITE):
    """A four-pointed glint of light."""
    for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
        c.set(x + dx, y + dy, color)


def draw_starlight_dust(c):
    """A little heap of violet dust flecked with gold, a few motes floating up from it."""
    c.ellipse(16, 24, 11, 4.5, MOTH[1])
    c.ellipse(16, 21, 7, 4, MOTH[1])
    c.shade(lambda x, y, col: col == MOTH[1] and x > 19, MOTH[0])
    c.shade(lambda x, y, col: col == MOTH[1] and x < 14 and y < 24, MOTH[2])
    for (x, y) in ((10, 25), (14, 22), (19, 24), (22, 26), (16, 19), (12, 27), (20, 21)):
        c.set(x, y, GOLD[2])
    glint(c, 9, 10, GOLD[2])
    glint(c, 22, 7)
    c.set(15, 13, GOLD[2])
    c.set(26, 14, WHITE)


def draw_starfall_shard(c):
    """A long shard of pale blue star-glass with a little star of light caught inside."""
    c.poly([(16, 3), (23, 12), (20, 29), (11, 27), (9, 13)], STARGLASS[1])
    c.shade(lambda x, y, col: col == STARGLASS[1] and x > 17, STARGLASS[0])
    c.poly([(15, 6), (11, 13), (13, 22), (15, 13)], STARGLASS[2])             # a facet catching the light
    star_shape(c, 17, 18, 3.6, STARLIGHT[1], inner=0.45)
    c.set(17, 18, WHITE)


def draw_star_lantern(c):
    """A little glass lantern with a handle, Starlight Dust glowing gold inside."""
    c.ring(16, 6, 4, 2.6, STEEL[1])                                          # the handle
    c.rect(10, 9, 22, 10, STEEL[0])                                          # its cap
    c.poly([(11, 11), (21, 11), (23, 25), (9, 25)], STARGLASS[1])            # the glass
    c.shade(lambda x, y, col: col == STARGLASS[1] and x > 19, STARGLASS[0])
    c.disc(16, 18, 4.2, STARLIGHT[1])                                        # the glow inside
    c.disc(15.5, 17.5, 2, WHITE)
    for (x, y) in ((13, 21), (19, 15), (18, 22)):
        c.set(x, y, MOTH[2])
    c.rect(8, 25, 24, 27, STEEL[0])                                          # its base
    c.rect(9, 25, 23, 25, STEEL[2])


def draw_glimmerwing_boots(c):
    """Violet boots with a little moth wing at the heel and a gold sole."""
    boot(c, MOTH, STARLIGHT[1], GOLD[0])
    c.poly([(9, 10), (2, 6), (1, 12), (5, 15), (9, 15)], MOTH[2])            # the wing
    c.line(8, 12, 3, 9, MOTH[0])
    c.set(3, 12, WHITE)
    for (x, y) in ((13, 13), (21, 25), (11, 20)):
        c.set(x, y, STARLIGHT[2])


def draw_starweave_robe(c):
    """A night-blue robe with gold trim and stars woven all over it."""
    robe(c, NIGHT, [GOLD[0], GOLD[1], GOLD[2]], star=STARLIGHT[1])
    for (x, y) in ((9, 21), (12, 26), (24, 25), (7, 14), (20, 10), (11, 16)):
        c.set(x, y, STARLIGHT[2])


def draw_starpetal_gauntlets(c):
    """Silver gauntlets with crystal petals set on the back of the hand."""
    glove(c, SILVER, STARGLASS)
    for (x, y) in ((13, 15), (19, 15), (16, 12), (16, 18)):                  # four petals round a gold heart
        c.disc(x, y, 1.8, STARGLASS[1])
    c.disc(16, 15, 1.2, GOLD[1])
    c.set(15, 11, WHITE)


def draw_stargazer_band(c):
    """A band of night-blue silver with a tiny gold star on top."""
    ring(c, NIGHT)
    star_shape(c, 16, 10, 5.2, STARLIGHT[1], inner=0.45)
    c.set(16, 10, WHITE)
    c.set(9, 17, NIGHT[2])


def draw_fallen_star_pendant(c):
    """A white star stone glowing on a silver chain."""
    pendant(c, SILVER, STARLIGHT, shape="star")
    c.set(26, 20, WHITE)
    c.set(6, 25, WHITE)


def draw_starfall_staff(c):
    """A pale wooden staff with a gold band and a star at its tip."""
    staff_line(c, PLATINUM, star_head(STARLIGHT), GOLD[1])


def draw_starfall_blade(c):
    """A long pale blade, gold wings on its guard and a violet stone."""
    sword_line(c, blade=STARGLASS, guard=GOLD, grip=NIGHT, length=15, width=5, wings=True, gem=MOTH)


def draw_starfall_axe(c):
    """A crescent head of star-glass on a night-blue handle, a gold stone set in it."""
    axe_line(c, head=STARGLASS, handle=NIGHT, style="crescent", gem=STARLIGHT)


def draw_starfall_whip(c):
    """A lilac lash with a star of light at its tip."""
    whip_line(c, leather=MOTH, grip=NIGHT, turns=3.6, tip=STARLIGHT[1], gem=GOLD, studs=WHITE)


GEODE = [hexc("4a3e6a"), hexc("7e6ea8"), hexc("b4a6d8")]
GLIMMER = [hexc("1e98c0"), hexc("62dcf4"), hexc("d4fbff")]


def draw_glimmerstone(c):
    """A lavender geode cracked open, its hollow full of cyan crystals glowing from the inside, a
    rose-pink glint among them."""
    c.ellipse(16, 18, 12.5, 10.5, GEODE[1])                                  # the stone shell
    c.shade(lambda x, y, col: col == GEODE[1] and (x - 16) + (y - 18) * 1.2 > 7, GEODE[0])
    c.shade(lambda x, y, col: col == GEODE[1] and (x - 16) + (y - 18) * 1.2 < -9, GEODE[2])
    c.ellipse(16, 18, 8.5, 6.8, GLIMMER[0])                                  # the hollow
    for (tip, a, b) in (((16, 17), (9, 15), (11, 20)), ((16, 17), (13, 12), (18, 12)),
                        ((16, 18), (21, 13), (24, 18)), ((16, 18), (22, 22), (17, 24)),
                        ((16, 18), (10, 21), (14, 24))):                    # crystals pointing in
        c.poly([a, tip, b], GLIMMER[1])
    c.poly([(9, 15), (13, 12), (16, 17)], GLIMMER[2])
    c.poly([(19, 21), (22, 22), (17, 24)], PINK[2])                          # a rose crystal
    c.set(20, 22, PINK[1])
    c.disc(16, 17.5, 1.6, WHITE)                                             # the glow at its heart
    for (x, y) in ((8, 11), (23, 9), (26, 14)):
        c.set(x, y, GLIMMER[2])
    glint(c, 25, 7)


# ---------------------------------------------------------------- Goldleaf (level 200)
# Elder Oak's gift to a hero at the top level (content/quests.json, giver `elder`): ivory and gold, each
# piece with a golden leaf from Meadowbrook's oldest oak on it.

IVORY = [hexc("a8987a"), hexc("ece2c8"), WHITE]
LEAFGOLD = [hexc("9a6a0e"), hexc("f0c030"), hexc("fff4a8")]
HEARTOAK = [hexc("4a2c14"), hexc("7a4a22"), hexc("a8703a")]


def gold_leaf(c, cx, cy, length, angle=-math.pi / 4, colors=LEAFGOLD, broad=0.36):
    """A pointed leaf, `length` from stem to tip along `angle` and `broad` times as wide, lit on
    one side, with a midrib."""
    dx, dy = math.cos(angle), math.sin(angle)
    nx, ny = -dy, dx
    width = length * broad
    points = []
    for i in range(9):
        t = i / 8
        w = math.sin(t * math.pi) * width
        points.append((cx + dx * length * t + nx * w, cy + dy * length * t + ny * w))
    for i in range(7, 0, -1):
        t = i / 8
        w = math.sin(t * math.pi) * width
        points.append((cx + dx * length * t - nx * w, cy + dy * length * t - ny * w))
    c.poly(points, colors[1])
    c.shade(lambda x, y, col: col == colors[1] and (x - cx) * nx + (y - cy) * ny < 0, colors[0])
    c.line(cx, cy, cx + dx * length * 0.85, cy + dy * length * 0.85, colors[2])
    if length >= 12:   # a stem, and veins off the midrib, so a big one reads as a leaf
        c.line(cx, cy, cx - dx * 2, cy - dy * 2, colors[0])
        for t in (0.35, 0.6):
            x0, y0 = cx + dx * length * t, cy + dy * length * t
            for side in (1, -1):
                c.line(x0, y0, x0 + dx * length * 0.15 + side * nx * width * 0.7, y0 + dy * length * 0.15 + side * ny * width * 0.7,
                       colors[2] if side > 0 else colors[1])


def draw_goldleaf_plate(c):
    """Ivory plate with gold edges and a golden leaf on the breast."""
    c.poly([(8, 6), (24, 6), (26, 12), (23, 28), (9, 28), (6, 12)], IVORY[1])
    c.disc(6, 9, 3.5, IVORY[1]); c.disc(26, 9, 3.5, IVORY[1])
    c.shade(lambda x, y, col: col == IVORY[1] and x > 18, IVORY[0])
    c.shade(lambda x, y, col: col == IVORY[1] and x < 12 and y > 8, IVORY[2])
    c.ellipse(16, 6, 4, 1.8, LEAFGOLD[0])
    c.line(6, 12, 9, 28, LEAFGOLD[1]); c.line(26, 12, 23, 28, LEAFGOLD[0])     # gold edges
    c.rect(9, 27, 23, 28, LEAFGOLD[1])
    c.disc(4.5, 8, 1.2, LEAFGOLD[2]); c.disc(27.5, 8, 1.2, LEAFGOLD[1])           # shoulder studs
    gold_leaf(c, 11, 24, 14, broad=0.42)


def draw_goldleaf_robe(c):
    """A white robe trimmed in gold, a golden leaf on its skirt."""
    robe(c, IVORY, LEAFGOLD)
    gold_leaf(c, 18, 25, 8, angle=-math.pi / 3)
    for (x, y) in ((9, 22), (12, 16), (23, 13)):
        c.set(x, y, LEAFGOLD[1])


def draw_goldleaf_gauntlets(c):
    """Ivory gauntlets with a gold cuff and a golden leaf on the back of the hand."""
    glove(c, IVORY, LEAFGOLD, studs=LEAFGOLD[1])
    gold_leaf(c, 12, 20, 9, angle=-math.pi / 5)


def draw_goldleaf_boots(c):
    """An ivory boot with a gold cuff and sole, a golden leaf like a wing at the heel."""
    boot(c, IVORY, LEAFGOLD[1], LEAFGOLD[0], laces=LEAFGOLD[1])
    gold_leaf(c, 9, 16, 9, angle=-math.pi * 0.85)


def draw_goldleaf_pendant(c):
    """A golden leaf hanging from a gold chain."""
    for i in range(12):
        color = LEAFGOLD[2] if i % 2 else LEAFGOLD[1]
        c.set(5 + i * 0.95, 2 + i * 1.0, color)
        c.set(27 - i * 0.95, 2 + i * 1.0, color)
    c.disc(16, 14, 1.6, LEAFGOLD[1])
    gold_leaf(c, 16, 15, 15, angle=math.pi / 2, broad=0.5)
    c.set(26, 22, WHITE)


def draw_goldleaf_ring(c):
    """A gold band with a golden leaf curled over the top."""
    ring(c, LEAFGOLD)
    gold_leaf(c, 10, 13, 13, angle=-math.pi / 9, colors=[hexc("6a8a1e"), hexc("b8d040"), hexc("f4ffb0")])
    c.set(23, 9, WHITE)


def draw_goldleaf_blade(c):
    """A long ivory blade, gold leaves for a guard and a heart-oak grip."""
    sword_line(c, blade=IVORY, guard=LEAFGOLD, grip=HEARTOAK, length=15, width=5, gem=GREEN)
    gold_leaf(c, 9, 19, 6, angle=math.pi * 0.85)
    gold_leaf(c, 12, 22, 6, angle=math.pi * 0.35)


def draw_goldleaf_axe(c):
    """A crescent of ivory steel on a heart-oak handle, a golden leaf on the cheek."""
    axe_line(c, head=IVORY, handle=HEARTOAK, style="crescent", gem=LEAFGOLD)
    gold_leaf(c, 23, 12, 6, angle=-math.pi / 3)


def leaf_crown(c):
    """Golden leaves round a white heart of light: the Goldleaf Staff's head."""
    for angle in (-math.pi * 0.95, -math.pi * 0.6, -math.pi * 0.25, math.pi * 0.1):
        gold_leaf(c, 21.5, 8.5, 6.5, angle=angle)
    c.disc(21.5, 8.5, 2.4, hexc("fff8d0"))
    c.set(21, 8, WHITE)


def draw_goldleaf_staff(c):
    """A heart-oak staff banded in gold, crowned with golden leaves round a light."""
    staff_line(c, HEARTOAK, leaf_crown, LEAFGOLD[1])


def draw_goldleaf_whip(c):
    """A golden lash with a leaf at its tip and a heart-oak grip."""
    whip_line(c, leather=LEAFGOLD, grip=HEARTOAK, turns=3.6, gem=GREEN, studs=WHITE)
    gold_leaf(c, 20, 14, 5, angle=-math.pi / 2, colors=[hexc("6a8a1e"), hexc("b8d040"), hexc("f4ffb0")])


def ramp(colour):
    """A #RRGGBB colour's dark, mid and light."""
    r, g, b, _ = hexc(colour)
    return [(int(r * 0.6), int(g * 0.6), int(b * 0.6), 255), (r, g, b, 255),
            tuple(int(v + (255 - v) * 0.38) for v in (r, g, b)) + (255,)]


def cape(c, cloth, trim):
    """A status cape from behind (items.json type cape, a prize for a milestone): round shoulders and a
    collar in its trim, falling wider to a trimmed hem, its emblem on the back."""
    dark, mid, light = cloth
    # Narrow at the neck, falling wide and long, its hem dipping in the middle.
    c.poly([(12, 4), (20, 4), (23, 8), (27, 27), (21, 29), (16, 30), (11, 29), (5, 27), (9, 8)], mid)
    c.shade(lambda x, y, col: col == mid and x >= 20 + (y - 4) // 4, dark)
    c.shade(lambda x, y, col: col == mid and x <= 11 - (y - 4) // 4 and y > 6, light)
    c.line(13, 10, 10, 27, dark)                     # folds
    c.line(19, 10, 22, 27, dark)
    c.shade(lambda x, y, col: y >= 27 - abs(x - 16) // 4 + (1 if abs(x - 16) < 6 else 0) and y >= 26, trim)   # the hem
    c.rect(12, 3, 20, 4, trim)                       # the collar and its clasps
    c.disc(12, 5, 1.2, trim)
    c.disc(20, 5, 1.2, trim)
    for dy in range(-3, 4):                          # the emblem: a diamond, lit in the middle
        for dx in range(-3 + abs(dy), 4 - abs(dy)):
            c.set(16 + dx, 16 + dy, trim)
    c.set(16, 16, WHITE)
    c.set(15, 15, WHITE)


# ---------------------------------------------------------------- the villages of the early lands
# Each land's village (0.7.23): what its quests ask you to bring, and the treasure each one ends in.

HONEY = [hexc("b8780e"), hexc("f2b632"), hexc("ffe48a")]
SEAGLOW = [hexc("1a7a6e"), hexc("3ad2b8"), hexc("b4fff0")]
MUD = [hexc("4a2e18"), hexc("7a5030"), hexc("a8794e")]
MOSS = [hexc("3a5a24"), hexc("5e8a36"), hexc("9cc070")]
CANDY = [hexc("c0306e"), hexc("ff7ab0"), hexc("ffd0e4")]
BEETLE = [hexc("2a1a4a"), hexc("5a3a9a"), hexc("b090f0")]
TAN = [hexc("8a5e30"), hexc("c49058"), hexc("ecc690")]


def draw_seed_pouch(c):
    """A tied cloth sack with a few seeds spilling out at its foot."""
    c.poly([(11, 11), (21, 11), (26, 26), (6, 26)], CLOTH[1])
    c.ellipse(16, 25, 10, 3, CLOTH[1])
    c.shade(lambda x, y, col: col == CLOTH[1] and x > 20, CLOTH[0])
    c.shade(lambda x, y, col: col == CLOTH[1] and x < 11 and y > 13, CLOTH[2])
    c.poly([(12, 5), (20, 5), (19, 11), (13, 11)], CLOTH[1])                # the gathered neck
    c.line(13, 6, 15, 10, CLOTH[0]); c.line(19, 6, 17, 10, CLOTH[0])
    c.rect(11, 10, 21, 11, LEATHER[1])                                       # the tie, with a bow
    c.disc(9, 11, 1.6, LEATHER[2]); c.disc(23, 11, 1.6, LEATHER[2])
    for (x, y) in ((25, 28), (28, 27), (27, 29), (23, 29), (29, 29)):          # seeds
        c.ellipse(x, y, 1.2, 0.8, STRAW[1])
    c.line(10, 18, 13, 22, CLOTH[0]); c.line(19, 17, 22, 21, CLOTH[0])         # a chewed hole
    c.disc(17, 20, 1, LEATHER[0])


def draw_honeybee_charm(c):
    """Three honeycomb cells of gold wax on a loop, a little bee sitting on them."""
    def cell(cx, cy, color):
        c.poly([(cx - 4, cy - 2), (cx, cy - 5), (cx + 4, cy - 2), (cx + 4, cy + 2), (cx, cy + 5), (cx - 4, cy + 2)], color)
    for (cx, cy) in ((12, 18), (20, 18), (16, 25)):
        cell(cx, cy, HONEY[1])
        c.poly([(cx - 2, cy - 1), (cx, cy - 3), (cx + 2, cy - 1), (cx + 2, cy + 1), (cx, cy + 3), (cx - 2, cy + 1)], HONEY[0])
        c.set(cx - 1, cy - 1, HONEY[2])
    c.ring(16, 7, 3.4, 2, GOLD[1])                                            # the loop
    c.ellipse(22, 12, 3.2, 2.2, hexc("2a2010"))                               # the bee
    c.line(21, 10, 21, 14, HONEY[1]); c.line(23, 10, 23, 14, HONEY[1])
    c.ellipse(21, 9, 1.8, 1.2, hexc("e8f4ff")); c.ellipse(24, 9, 1.8, 1.2, hexc("e8f4ff"))


def draw_stray_sock(c):
    """A striped woollen sock, its foot to the right, with a spiny hole or two."""
    c.poly([(9, 3), (18, 3), (18, 19), (27, 21), (28, 28), (16, 29), (9, 23)], CLOTH[1])
    c.shade(lambda x, y, col: col == CLOTH[1] and (y // 4) % 2 == 0 and y < 22, RED[1])
    c.shade(lambda x, y, col: col in (CLOTH[1], RED[1]) and x > 16 and y < 19, CLOTH[0])
    c.rect(9, 3, 18, 5, RED[0])                                               # the cuff
    c.poly([(23, 21), (28, 22), (28, 28), (23, 28)], RED[1])                   # the toe
    c.ellipse(11, 26, 2.5, 2.5, RED[1])                                        # the heel
    for (x, y) in ((13, 12), (15, 16), (21, 25)):                              # holes from the spines
        c.set(x, y, OUTLINE)


def draw_windstep_sandals(c):
    """Light sandals laced with red kite string, a feather tucked in the strap."""
    c.rect(6, 24, 27, 28, TAN[1])                                            # the sole
    c.rect(6, 28, 27, 28, TAN[0])
    c.rect(6, 24, 27, 24, TAN[2])
    c.line(10, 24, 16, 13, RED[1], width=2)                                  # kite-string straps
    c.line(22, 24, 16, 13, RED[1], width=2)
    c.line(13, 19, 19, 19, RED[0])
    c.disc(16, 13, 1.6, RED[0])
    c.line(17, 12, 28, 3, WHITE, width=2)                                    # the feather
    c.line(18, 11, 27, 3, CLOTH[0])


def draw_silver_fish(c):
    """A fat silver herring, nose to the right."""
    c.ellipse(15, 17, 10, 5.5, STEEL[1])
    c.shade(lambda x, y, col: col == STEEL[1] and y < 15, STEEL[0])
    c.shade(lambda x, y, col: col == STEEL[1] and y > 19, STEEL[2])
    c.poly([(5, 17), (1, 11), (3, 17), (1, 23)], STEEL[0])                    # the tail
    c.poly([(13, 12), (18, 8), (20, 12)], STEEL[0])                           # the fin
    c.disc(22, 16, 1.4, WHITE); c.set(22, 16, OUTLINE)                        # the eye
    c.line(19, 13, 19, 21, STEEL[0])                                          # the gill
    for x in (9, 12, 15):
        c.set(x, 16, STEEL[2])


def draw_glow_shell(c):
    """A spiral shell glowing sea-green."""
    c.disc(15, 18, 9, SEAGLOW[1])
    c.poly([(19, 26), (29, 27), (24, 21)], SEAGLOW[1])                         # its lip
    for i in range(48):
        t = i / 48 * math.pi * 3.4
        r = 1 + i * 0.16
        c.set(15 + r * math.cos(t), 18 + r * math.sin(t), SEAGLOW[0])
    c.shade(lambda x, y, col: col == SEAGLOW[1] and x + y < 26, SEAGLOW[2])
    c.set(15, 18, WHITE)


def draw_shell_lantern(c):
    """A little poplar-wood lantern, three glowing shells inside."""
    c.ring(16, 5, 3.2, 1.8, WOOD[1])                                          # the handle
    c.rect(8, 8, 24, 10, WOOD[1]); c.rect(8, 27, 24, 29, WOOD[1])
    c.rect(8, 8, 24, 8, WOOD[2]); c.rect(8, 29, 24, 29, WOOD[0])
    c.rect(9, 11, 23, 26, hexc("1e4a48"))                                     # the dark inside
    for x in (8, 23):
        c.rect(x, 10, x + 1, 27, WOOD[0])
    for (x, y) in ((13, 15), (19, 17), (15, 22)):
        c.disc(x, y, 3, SEAGLOW[1]); c.disc(x - 1, y - 1, 1, SEAGLOW[2])
    c.set(18, 13, WHITE); c.set(11, 24, WHITE)


def draw_tidecaller_pendant(c):
    """A sea-green drop with a white wave across it, on a cord."""
    pendant(c, LEATHER, SEAGLOW)
    c.line(11, 23, 13, 21, WHITE); c.line(13, 21, 15, 23, WHITE)
    c.line(15, 23, 17, 21, WHITE); c.line(17, 21, 19, 23, WHITE)


def draw_gold_nugget(c):
    """A lumpy nugget of gold."""
    for (x, y, r) in ((14, 18, 7), (20, 16, 5), (11, 22, 5), (20, 22, 5)):
        c.disc(x, y, r, GOLD[1])
    light_top_left(c, GOLD, 16, 19, 9)
    for (x, y) in ((12, 15), (18, 13), (9, 20)):
        c.set(x, y, WHITE)
    c.disc(22, 24, 1.5, GOLD[0]); c.disc(15, 22, 1, GOLD[0])


def draw_prospectors_gloves(c):
    """Thick tan work gloves with brass studs."""
    glove(c, TAN, LEATHER, studs=GOLD[1])
    c.line(10, 18, 23, 18, TAN[0])


def draw_beetle_shell(c):
    """A Dark Beetle's glossy wing case, split down the middle."""
    c.ellipse(16, 17, 9, 12, BEETLE[1])
    c.shade(lambda x, y, col: col == BEETLE[1] and x > 19, BEETLE[0])
    c.line(16, 6, 16, 29, BEETLE[0])
    c.line(11, 9, 9, 16, BEETLE[2]); c.line(12, 9, 10, 14, WHITE)             # gloss
    c.line(20, 10, 21, 14, BEETLE[2])


def draw_owl_eye_amulet(c):
    """A round amber eye with a dark slit, feathers at its sides."""
    pendant(c, BROWN, AMBER, shape="round")
    c.line(16, 18, 16, 26, OUTLINE)                                           # the pupil
    c.set(15, 20, hexc("5a2a08")); c.set(17, 24, hexc("5a2a08"))
    for side in (-1, 1):                                                      # feather tufts
        c.poly([(16 + side * 7, 18), (16 + side * 11, 14), (16 + side * 9, 21)], BROWN[1])


def draw_crisp_apple(c):
    """A shiny red apple with a leaf, and one small bite out of it."""
    c.disc(13, 19, 8, RED[1]); c.disc(19, 19, 8, RED[1])
    light_top_left(c, RED, 16, 19, 9)
    c.disc(10, 15, 1.6, RED[2])
    c.line(16, 11, 17, 6, BROWN[1], width=2)                                  # the stem
    c.ellipse(21, 7, 4, 2, GREEN[1]); c.line(18, 7, 24, 7, GREEN[0])          # the leaf
    for (x, y, r) in ((26, 19, 3), (25, 23, 2.5)):                            # the bite
        c.disc(x, y, r, None)
    c.shade(lambda x, y, col: col in RED and (x - 26) ** 2 + (y - 21) ** 2 < 22, CLOTH[2])


def draw_forest_truffle(c):
    """A knobbly brown truffle."""
    for (x, y, r) in ((15, 19, 8), (21, 17, 5), (10, 15, 4), (19, 24, 5), (9, 22, 4)):
        c.disc(x, y, r, MUD[1])
    light_top_left(c, MUD, 15, 19, 10)
    for (x, y) in ((12, 18), (17, 14), (20, 21), (14, 24), (22, 17), (10, 21)):
        c.set(x, y, MUD[0])
    c.set(9, 13, MUD[2]); c.set(13, 13, MUD[2])


def draw_orchard_gloves(c):
    """Soft green picking gloves, an apple leaf stitched on the back."""
    glove(c, GREEN, CLOTH)
    c.ellipse(16, 16, 3.5, 2, GREEN[2]); c.line(13, 16, 19, 16, GREEN[0])
    c.disc(22, 25, 1.4, RED[1])


def draw_sugar_crystal(c):
    """A cluster of pink sugar crystals, sparkling."""
    c.poly([(9, 28), (11, 12), (15, 8), (17, 28)], CANDY[1])
    c.poly([(15, 28), (19, 5), (23, 10), (25, 28)], CANDY[1])
    c.poly([(5, 28), (6, 19), (9, 17), (11, 28)], CANDY[1])
    c.shade(lambda x, y, col: col == CANDY[1] and (x in (13, 14, 21, 22, 23, 9, 10)), CANDY[0])
    c.line(12, 13, 12, 26, CANDY[2]); c.line(19, 8, 18, 26, CANDY[2])
    for (x, y) in ((26, 6), (6, 12), (28, 18)):
        c.set(x, y, WHITE); c.set(x + 1, y, CANDY[2]); c.set(x - 1, y, CANDY[2]); c.set(x, y + 1, CANDY[2]); c.set(x, y - 1, CANDY[2])


def draw_rock_candy_crown(c):
    """A small crown of pink rock candy with an amber jewel."""
    c.poly([(5, 26), (5, 12), (10, 18), (16, 8), (22, 18), (27, 12), (27, 26)], CANDY[1])
    c.shade(lambda x, y, col: col == CANDY[1] and x > 21, CANDY[0])
    c.shade(lambda x, y, col: col == CANDY[1] and x < 9, CANDY[2])
    c.rect(5, 24, 27, 27, CANDY[0])
    for (x, y) in ((5, 11), (16, 7), (27, 11)):
        c.disc(x, y, 1.6, CANDY[2])
    c.disc(16, 19, 3, AMBER[1]); c.set(15, 18, AMBER[2]); c.set(17, 20, AMBER[0])
    for x in (9, 23):
        c.disc(x, 25, 1, WHITE)


def draw_peppermint_boots(c):
    """Boots striped red and white like a peppermint stick."""
    boot(c, [hexc("e8e8ee"), WHITE, WHITE], RED[1], RED[0])
    c.shade(lambda x, y, col: col == WHITE and ((x + y) // 3) % 2 == 0 and y > 8 and y < 26, RED[1])
    c.shade(lambda x, y, col: col == hexc("e8e8ee") and ((x + y) // 3) % 2 == 0, RED[0])


def draw_healing_mud(c):
    """A clay jar of warm brown mud, a dollop spilling over the rim."""
    c.poly([(9, 11), (23, 11), (25, 28), (7, 28)], TAN[1])
    c.shade(lambda x, y, col: col == TAN[1] and x > 20, TAN[0])
    c.shade(lambda x, y, col: col == TAN[1] and x < 11, TAN[2])
    c.ellipse(16, 11, 8, 2.5, MUD[1])                                         # the mud in its mouth
    c.disc(13, 9, 3, MUD[1]); c.disc(18, 8, 3.5, MUD[1])
    c.disc(22, 13, 1.6, MUD[1]); c.line(22, 13, 22, 17, MUD[1], width=2)       # a drip
    c.set(12, 7, MUD[2]); c.set(17, 6, MUD[2])
    c.rect(7, 18, 25, 19, TAN[0])                                             # a band round the jar


def draw_bogwalker_boots(c):
    """Tall mossy waders with a dark sole."""
    boot(c, MOSS, MOSS[0], MUD[0], laces=MOSS[2])
    c.poly([(9, 3), (17, 3), (17, 7), (9, 7)], MOSS[1])                        # reaching up to the knee
    c.rect(9, 3, 17, 4, MOSS[0])
    c.set(10, 20, MUD[1]); c.set(13, 24, MUD[1]); c.set(20, 25, MUD[1])       # splashes of mud


def draw_honey_muffin(c):
    """A golden muffin in a striped paper case, honey running down its top."""
    c.poly([(8, 18), (24, 18), (22, 29), (10, 29)], CLOTH[1])                 # the case
    for x in (10, 13, 16, 19, 22):
        c.line(x, 19, x - (1 if x < 16 else -1 if x > 16 else 0), 28, CLOTH[0])
    c.ellipse(16, 15, 10, 6, AMBER[1])                                        # the top
    light_top_left(c, AMBER, 16, 14, 8)
    c.ellipse(16, 11, 5, 2, HONEY[2])                                         # honey on top, dripping
    c.line(12, 12, 11, 17, HONEY[1], width=2); c.line(20, 12, 21, 16, HONEY[1], width=2)


def draw_red_hood_ribbon(c):
    """A bright red ribbon tied in a bow."""
    c.poly([(16, 14), (5, 7), (3, 14), (5, 20)], RED[1])                       # the loops
    c.poly([(16, 14), (27, 7), (29, 14), (27, 20)], RED[1])
    c.shade(lambda x, y, col: col == RED[1] and y > 15, RED[0])
    c.line(6, 10, 9, 14, RED[2]); c.line(26, 10, 23, 14, RED[2])
    c.poly([(15, 15), (10, 28), (13, 28), (16, 19)], RED[1])                   # the tails
    c.poly([(17, 15), (22, 28), (19, 28), (16, 19)], RED[0])
    c.disc(16, 14, 2.6, RED[0]); c.set(15, 13, RED[2])                         # the knot


# ---------------------------------------------------------------- the villages of the middle lands
# (0.7.24): what their quests ask you to bring, and the treasure each one ends in.

WISPGLOW = [hexc("4a7ab8"), hexc("a8d8ff"), hexc("f0faff")]
HORN = [hexc("a08a62"), hexc("e0d0a8"), hexc("fff6e0")]
WROUGHT = [hexc("3a3e4a"), hexc("6a7080"), hexc("a8b0c0")]
SCALE = [hexc("5a4a24"), hexc("8a7438"), hexc("c0a860")]
LOTUS = [hexc("c04a7a"), hexc("ff8ab8"), hexc("ffd8ea")]
HEARTWOOD = [hexc("6a3a1a"), hexc("a8642e"), hexc("e0a060")]
ORE = [hexc("2e2a2a"), hexc("5a5250"), hexc("8a807a")]
FORGE = [hexc("b04010"), hexc("ff8a2a"), hexc("ffd080")]
PRISM = [hexc("6a5ab0"), hexc("c0b8ff"), WHITE]
COFFEE = [hexc("2e1a0e"), hexc("5a3418"), hexc("8a5a30")]
DREAMJAR = [hexc("5a6ab8"), hexc("a8b8f0"), hexc("e8eeff")]
SLIPPER = [hexc("8a6ab8"), hexc("c8aaf0"), hexc("f0e4ff")]
FROST = [hexc("8a2a3a"), hexc("d0506a"), hexc("ff9ab0")]


def draw_wisp_silk(c):
    """A small skein of glowing pale-blue thread."""
    c.ellipse(16, 17, 10, 7, WISPGLOW[1])
    for y in range(11, 24, 2):
        c.line(7, y, 25, y + 1, WISPGLOW[2] if y % 4 == 1 else WISPGLOW[0])
    c.rect(14, 9, 18, 25, WISPGLOW[0])                                        # the band round its middle
    c.rect(15, 9, 17, 25, WISPGLOW[2])
    c.line(25, 19, 29, 26, WISPGLOW[1])                                       # a loose end
    for (x, y) in ((5, 8), (27, 7), (4, 25)):
        c.set(x, y, WHITE)


def draw_swan_lace_veil(c):
    """A folded veil of white lace with a green clasp."""
    c.poly([(6, 8), (26, 8), (28, 26), (4, 26)], CLOTH[2])
    for y in range(10, 26, 3):                                                # the lace holes
        for x in range(7 + (y % 2) * 2, 27, 4):
            c.set(x, y, CLOTH[0])
    c.line(5, 26, 27, 26, CLOTH[0])
    c.shade(lambda x, y, col: col == CLOTH[2] and x > 22, CLOTH[1])
    c.disc(16, 9, 3, GREEN[1]); c.set(15, 8, GREEN[2]); c.set(17, 10, GREEN[0])


def draw_swan_feather_brooch(c):
    """A white swan feather pinned with silver."""
    c.poly([(9, 27), (13, 15), (20, 6), (23, 8), (19, 19), (11, 28)], WHITE)
    c.line(10, 27, 21, 7, CLOTH[0])                                           # the quill
    c.shade(lambda x, y, col: col == WHITE and x + y > 33, CLOTH[2])
    c.line(5, 21, 25, 21, SILVER[1], width=2)                                 # the pin
    c.disc(5, 21, 1.6, SILVER[2]); c.disc(26, 21, 1, SILVER[0])


def draw_bull_horn(c):
    """A curved cream horn."""
    for i in range(24):
        t = i / 23
        x, y = 6 + t * 20, 26 - math.sin(t * math.pi * 0.8) * 16 - t * 4
        c.disc(x, y, 4.5 * (1 - t) + 1, HORN[1])
    c.shade(lambda x, y, col: col == HORN[1] and y > 18, HORN[0])
    c.line(8, 20, 18, 9, HORN[2])
    c.disc(6, 26, 3.2, HORN[0])


def draw_bell_clapper(c):
    """The iron tongue of a bell on a short chain."""
    for i in range(4):
        c.ring(16, 4 + i * 3, 1.8, 0.8, WROUGHT[1])
    c.line(16, 15, 16, 22, WROUGHT[1], width=2)
    c.disc(16, 24, 5, WROUGHT[1])
    light_top_left(c, WROUGHT, 16, 24, 5)
    c.set(13, 22, WROUGHT[2])
    c.line(18, 21, 20, 25, hexc("6a4a2a"))                                    # a monkey's tooth marks


def draw_bellringers_gloves(c):
    """Teal gloves with little brass bells on the cuffs."""
    glove(c, TEAL, LEATHER)
    for x in (11, 17, 23):
        c.disc(x, 26, 1.8, GOLD[1]); c.set(x, 27, GOLD[0])


def draw_snake_scale(c):
    """A hard, smooth brown scale."""
    c.poly([(16, 4), (26, 12), (24, 24), (16, 29), (8, 24), (6, 12)], SCALE[1])
    c.shade(lambda x, y, col: col == SCALE[1] and x > 18, SCALE[0])
    c.line(16, 6, 16, 27, SCALE[0])
    c.line(10, 12, 13, 22, SCALE[2]); c.set(11, 10, WHITE)


def draw_ratcatcher_boots(c):
    """Tall brown boots covered in snake scales."""
    boot(c, SCALE, SCALE[0], hexc("3a2410"))
    for y in range(9, 24, 3):
        for x in range(10 + (y % 2), 17, 3):
            c.set(x, y, SCALE[2])


def draw_dew_pearl(c):
    """A dewdrop as round as a pearl."""
    c.disc(16, 18, 9, WISPGLOW[1])
    light_top_left(c, WISPGLOW, 16, 18, 9)
    c.disc(12, 14, 2.4, WHITE)
    c.disc(19, 23, 1.2, WISPGLOW[2])


def draw_lotus_lantern(c):
    """A tiny lotus-flower lantern glowing on a bamboo stick."""
    c.line(6, 29, 16, 15, BAMBOO[1], width=2)                                 # the stick
    for (x, y) in ((9, 25), (13, 19)):
        c.set(x, y, BAMBOO[0])
    for dx, h in ((-7, 6), (7, 6), (-4, 9), (4, 9), (0, 11)):                  # petals round a glow
        c.ellipse(19 + dx * 0.9, 12 - h / 2, 3, h / 1.6, LOTUS[1])
    c.shade(lambda x, y, col: col == LOTUS[1] and x > 22, LOTUS[0])
    c.disc(19, 12, 3, HONEY[2]); c.set(19, 11, WHITE)


def draw_lotus_dew_charm(c):
    """A pink lotus bud with a dew pearl at its heart."""
    c.ring(16, 6, 3, 1.6, SILVER[1])
    c.poly([(16, 9), (24, 18), (16, 29), (8, 18)], LOTUS[1])
    c.poly([(16, 12), (21, 19), (16, 27), (11, 19)], LOTUS[2])
    c.shade(lambda x, y, col: col == LOTUS[1] and x > 17, LOTUS[0])
    c.disc(16, 19, 2.6, WISPGLOW[1]); c.set(15, 18, WHITE)


def draw_golden_string(c):
    """A coil of shining golden string."""
    for i in range(70):
        t = i / 70 * math.pi * 5
        r = 3 + i * 0.12
        c.set(16 + r * math.cos(t), 16 + r * math.sin(t) * 0.8, GOLD[2] if i % 5 == 0 else GOLD[1])
    c.line(25, 20, 29, 29, GOLD[1])
    c.set(16, 16, GOLD[0])


def draw_heartwood_locket(c):
    """A carved wooden heart on a gold chain."""
    pendant(c, GOLD, HEARTWOOD, shape="round")
    c.disc(13, 21, 3.5, HEARTWOOD[1]); c.disc(19, 21, 3.5, HEARTWOOD[1])     # heart-shaped over the round
    c.poly([(9, 22), (23, 22), (16, 29)], HEARTWOOD[1])
    c.shade(lambda x, y, col: col == HEARTWOOD[1] and x > 17, HEARTWOOD[0])
    c.line(16, 20, 16, 26, HEARTWOOD[0]); c.set(12, 19, HEARTWOOD[2])


def draw_sun_quill(c):
    """A Light Hedgehog's quill, glowing like a sunbeam."""
    c.line(6, 27, 25, 6, GOLD[1], width=2)
    c.line(7, 26, 24, 7, GOLD[2])
    c.poly([(24, 4), (28, 4), (27, 8)], WHITE)                                # its bright tip
    for (x, y) in ((27, 12), (20, 3), (30, 7)):
        c.set(x, y, GOLD[2])


def draw_genie_lamp(c):
    """A gold oil lamp with a glowing wick."""
    c.ellipse(15, 21, 10, 5, GOLD[1])
    c.poly([(23, 19), (30, 15), (28, 19), (23, 23)], GOLD[1])                  # the spout
    c.ellipse(4, 20, 2.6, 3.4, GOLD[0]); c.ellipse(4, 20, 1.2, 2, None)       # the handle
    light_top_left(c, GOLD, 15, 21, 9)
    c.ellipse(15, 16, 4, 1.6, GOLD[0]); c.disc(15, 14, 1.4, GOLD[1])          # the lid
    c.rect(9, 25, 21, 27, GOLD[0])                                            # the foot
    c.disc(30, 13, 1.6, HONEY[2]); c.set(30, 11, WHITE)                       # the flame


def draw_genies_ring(c):
    """A gold ring with a swirl of blue smoke in its stone."""
    ring(c, GOLD, gem=True, gem_color=BLUE)
    for (x, y) in ((14, 7), (17, 5), (19, 3), (15, 3)):
        c.set(x, y, BLUE[2])


def draw_raw_ore(c):
    """A dark lump of ore with copper flecks."""
    for (x, y, r) in ((15, 18, 9), (21, 15, 6), (10, 22, 6)):
        c.disc(x, y, r, ORE[1])
    light_top_left(c, ORE, 15, 18, 10)
    for (x, y) in ((13, 15), (18, 20), (21, 13), (9, 21), (16, 24)):
        c.set(x, y, COPPER[1]); c.set(x + 1, y, COPPER[2])


def draw_forgehand_gauntlets(c):
    """Heavy iron gauntlets glowing orange at the knuckles."""
    glove(c, WROUGHT, FORGE)
    for x in (11, 15, 19, 23):
        c.set(x, 12, FORGE[1]); c.set(x, 13, FORGE[2])


def draw_rough_gem(c):
    """A cloudy, uncut violet gem."""
    c.poly([(10, 9), (21, 6), (27, 15), (23, 26), (11, 27), (5, 18)], VIOLET[1])
    c.shade(lambda x, y, col: col == VIOLET[1] and x + y > 36, VIOLET[0])
    c.poly([(11, 11), (17, 9), (15, 16), (9, 17)], VIOLET[2])
    c.set(20, 18, VIOLET[2]); c.set(13, 22, VIOLET[0])


def draw_prism_lamp(c):
    """A lamp of cut crystal on a stand, throwing rainbows."""
    c.rect(12, 26, 20, 28, SILVER[1]); c.rect(15, 21, 17, 26, SILVER[0])
    c.poly([(16, 4), (24, 12), (16, 22), (8, 12)], PRISM[1])
    c.shade(lambda x, y, col: col == PRISM[1] and x > 16, PRISM[0])
    c.poly([(16, 6), (19, 12), (16, 15), (13, 12)], WHITE)
    for (x0, color) in ((26, RED[1]), (27, ORANGE[1]), (28, GOLD[1]), (29, GREEN[1]), (30, BLUE[1])):
        c.line(24, 12, x0 + 1, 20, color)


def draw_prism_pendant(c):
    """A clear prism on a silver chain, with a little rainbow."""
    pendant(c, SILVER, PRISM)
    for i, color in enumerate((RED[1], ORANGE[1], GOLD[1], GREEN[1], BLUE[1])):
        c.set(22 + i, 27, color)


def draw_coffee_beans(c):
    """A small pile of dark roasted beans."""
    for (x, y) in ((8, 24), (16, 26), (24, 24), (12, 18), (20, 18), (16, 11)):
        c.ellipse(x, y, 3.6, 2.6, COFFEE[1])
        c.line(x - 2, y + 1, x + 2, y - 1, COFFEE[0])
        c.set(x - 2, y - 1, COFFEE[2]); c.set(x - 1, y - 2, COFFEE[2])


def draw_sweet_dream(c):
    """A good dream in a little glass jar, glowing like a night light."""
    c.rect(9, 9, 23, 28, DREAMJAR[2])
    c.rect(10, 10, 22, 27, hexc("2a3060"))                                    # the night inside
    c.disc(16, 18, 5, HONEY[2]); c.disc(18, 16, 4.4, hexc("2a3060"))          # a crescent moon
    for (x, y) in ((12, 13), (20, 24), (13, 24)):
        c.set(x, y, WHITE)
    c.rect(8, 5, 24, 8, WOOD[1]); c.rect(8, 5, 24, 5, WOOD[2])                # the cork lid


def draw_dozy_slippers(c):
    """A fluffy lavender slipper with a pompom."""
    c.ellipse(16, 23, 13, 6, SLIPPER[1])
    c.shade(lambda x, y, col: col == SLIPPER[1] and y > 25, SLIPPER[0])
    c.ellipse(11, 20, 6, 2.5, hexc("4a3a6a"))                                 # the opening
    c.disc(24, 17, 4, WHITE); c.disc(23, 16, 1.6, SLIPPER[2])                 # the pompom
    c.rect(4, 28, 28, 29, SLIPPER[0])


def draw_frost_apple(c):
    """A rosy apple with a crust of frost."""
    c.disc(13, 19, 8, FROST[1]); c.disc(19, 19, 8, FROST[1])
    light_top_left(c, FROST, 16, 19, 9)
    c.line(16, 11, 17, 6, BROWN[1], width=2)
    c.ellipse(21, 7, 4, 2, GREEN[1])
    c.shade(lambda x, y, col: col in FROST and y < 16, SNOW[2])               # frost on top
    for (x, y) in ((10, 20), (21, 23), (15, 25), (24, 17)):
        c.set(x, y, WHITE)


def draw_seven_hearths_ring(c):
    """A gold ring set with seven tiny gems."""
    ring(c, GOLD)
    for (x, y), color in zip(((8, 15), (10, 11), (13, 9), (16, 8), (19, 9), (22, 11), (24, 15)),
                             (RED[1], ORANGE[1], GOLD[2], GREEN[1], BLUE[1], VIOLET[1], PINK[1])):
        c.disc(x, y, 1.4, color)


# ---------------------------------------------------------------- the villages of the late lands
# (0.7.25): what their quests ask you to bring, and the treasure each one ends in.

RICE = [hexc("b8b8d0"), hexc("eeeefa"), WHITE]
MANE = [hexc("8a5a20"), hexc("c88a3a"), hexc("f0c070")]
CHILI = [hexc("8a1010"), hexc("e02a1a"), hexc("ff8a6a")]
LAKE_ICE = [hexc("6aa0d0"), hexc("b8e0ff"), WHITE]
SEAPEARL = [hexc("4a9a9a"), hexc("a8f0e8"), WHITE]
SILK = [hexc("9aa0c0"), hexc("e0e6ff"), WHITE]
EMERALDGLASS = [hexc("1a7a3a"), hexc("3ad06a"), hexc("b0ffc8")]


def draw_moon_rice(c):
    """A little cloth sack of rice so white it glows."""
    c.poly([(10, 12), (22, 12), (26, 27), (6, 27)], CLOTH[1])
    c.ellipse(16, 26, 10, 3, CLOTH[1])
    c.shade(lambda x, y, col: col == CLOTH[1] and x > 20, CLOTH[0])
    c.ellipse(16, 12, 7, 3, RICE[1])                                          # the open top, full of rice
    for (x, y) in ((13, 11), (16, 12), (19, 11), (15, 10), (18, 13)):
        c.set(x, y, WHITE)
    star_shape(c, 16, 20, 4, MOON[1], inner=0.5)                               # a moon mark stamped on it
    for (x, y) in ((24, 8), (8, 7)):
        c.set(x, y, WHITE)


def draw_mochi_tray(c):
    """Round white mochi on a bamboo tray, one on top."""
    c.rect(3, 25, 29, 28, BAMBOO[1]); c.rect(3, 25, 29, 25, BAMBOO[2]); c.rect(3, 28, 29, 28, BAMBOO[0])
    for (x, y) in ((8, 21), (16, 21), (24, 21), (12, 14), (20, 14)):
        c.ellipse(x, y, 4.2, 3.6, RICE[0])
        c.ellipse(x - 0.4, y - 0.4, 3.6, 3, RICE[1])
        c.set(x - 2, y - 2, WHITE); c.set(x - 1, y - 2, WHITE)


def draw_moon_rabbit_charm(c):
    """A silver rabbit sitting in a crescent moon."""
    c.disc(16, 17, 11, MOON[1]); c.disc(21, 13, 9, None)                       # the crescent
    light_top_left(c, MOON, 13, 19, 9)
    c.ellipse(19, 20, 3.5, 3, SILVER[2])                                      # the rabbit
    c.disc(21, 16, 2.2, SILVER[2])
    c.ellipse(20, 11, 0.9, 3, SILVER[2]); c.ellipse(22, 11, 0.9, 3, SILVER[2])
    c.set(22, 16, OUTLINE)


def draw_lion_mane(c):
    """A shaggy tawny tuft of mane, wavy strands tied at the root."""
    import random
    rnd = random.Random(7)
    for i in range(14):
        angle = -math.pi / 2 + (i - 6.5) * 0.16 + rnd.uniform(-0.05, 0.05)
        length = rnd.uniform(15, 22)
        color = (MANE[2], MANE[1], MANE[1], MANE[0])[i % 4]
        for step in range(int(length)):
            t = step / length
            wave = math.sin(t * 6 + i) * 1.6
            x = 16 + math.cos(angle) * step + wave * math.sin(angle)
            y = 27 + math.sin(angle) * step
            c.disc(x, y, 1.5 * (1 - t) + 0.5, color)
    c.rect(12, 25, 20, 29, LEATHER[1]); c.rect(12, 25, 20, 25, LEATHER[2])


def draw_great_drum(c):
    """A big round hide drum trimmed with mane."""
    c.rect(6, 12, 26, 26, HEARTWOOD[1])
    c.shade(lambda x, y, col: col == HEARTWOOD[1] and x > 21, HEARTWOOD[0])
    c.ellipse(16, 12, 10, 3.5, CLOTH[2])                                      # the skin on top
    c.ellipse(16, 26, 10, 3.5, HEARTWOOD[0])
    for x in range(8, 26, 3):                                                 # lacing, and mane round the rim
        c.line(x, 14, x + 2, 24, LEATHER[2])
        c.line(x, 15, x - 1, 17, MANE[1])


def draw_steppe_runner_boots(c):
    """Soft tan hide boots with red woven bands."""
    boot(c, TAN, RED[1], LEATHER[0])
    for y in (11, 16):
        c.line(9, y, 17, y, RED[1])
        for x in range(10, 17, 2):
            c.set(x, y, GOLD[1])


def draw_fire_pepper(c):
    """A shiny red chilli pepper."""
    for i in range(18):
        t = i / 17
        c.disc(9 + t * 16, 10 + math.sin(t * math.pi * 0.9) * 10 + t * 6, 4.5 * (1 - t * 0.75), CHILI[1])
    c.shade(lambda x, y, col: col == CHILI[1] and y > 20, CHILI[0])
    c.line(10, 9, 15, 12, CHILI[2])
    c.poly([(5, 6), (10, 5), (11, 9), (6, 10)], GREEN[1])                      # the cap and stalk
    c.line(6, 6, 3, 2, GREEN[0])


def draw_sneezing_powder(c):
    """A bamboo pot of red powder, a cloud of it rising."""
    c.rect(9, 16, 23, 28, BAMBOO[1])
    for y in (20, 25):
        c.line(9, y, 23, y, BAMBOO[0])
    c.shade(lambda x, y, col: col == BAMBOO[1] and x > 20, BAMBOO[0])
    c.ellipse(16, 16, 7, 2, CHILI[1])
    for (x, y, r) in ((12, 11, 2.6), (16, 9, 3), (20, 11, 2.4), (14, 5, 2), (19, 4, 1.8), (10, 6, 1.4), (23, 7, 1.4)):
        c.disc(x, y, r, CHILI[2])
    for (x, y) in ((15, 8), (12, 10), (19, 3)):
        c.set(x, y, WHITE)


def draw_pepperfire_gauntlets(c):
    """Red gauntlets with pepper-shaped studs."""
    glove(c, CHILI, GOLD)
    for x in (11, 15, 19, 23):
        c.ellipse(x, 13, 1, 1.8, GREEN[1])


def draw_frozen_jelly(c):
    """A frozen cube of jelly, still wobbling a little."""
    c.poly([(8, 12), (20, 8), (26, 13), (26, 25), (14, 29), (8, 24)], LAKE_ICE[1])
    c.poly([(8, 12), (20, 8), (26, 13), (14, 17)], LAKE_ICE[2])
    c.shade(lambda x, y, col: col == LAKE_ICE[1] and x > 14, LAKE_ICE[0])
    c.line(14, 17, 14, 29, LAKE_ICE[0])
    c.disc(17, 21, 3, SEAPEARL[1]); c.set(16, 20, WHITE)                      # the jelly inside


def draw_clear_ice(c):
    """A block of ice so clear you can read through it."""
    c.poly([(6, 12), (18, 7), (27, 12), (27, 24), (15, 29), (6, 24)], LAKE_ICE[2])
    c.poly([(6, 12), (18, 7), (27, 12), (15, 17)], WHITE)
    c.shade(lambda x, y, col: col == LAKE_ICE[2] and x > 15, LAKE_ICE[1])
    c.line(15, 17, 15, 29, LAKE_ICE[0])
    c.line(9, 15, 12, 24, LAKE_ICE[1]); c.line(19, 20, 24, 18, LAKE_ICE[1])


def draw_ice_swan(c):
    """A swan carved out of clear ice, wings half open."""
    c.ellipse(16, 22, 10, 5, LAKE_ICE[1])                                          # the body
    c.poly([(9, 20), (6, 9), (14, 16)], LAKE_ICE[2])                                # a wing
    c.poly([(21, 20), (27, 11), (20, 15)], LAKE_ICE[2])
    c.line(10, 21, 8, 14, LAKE_ICE[1], width=2); c.line(8, 14, 9, 8, LAKE_ICE[1], width=2)   # the neck
    c.disc(10, 7, 2, LAKE_ICE[2]); c.poly([(11, 7), (14, 8), (11, 8)], LAKE_ICE[0])     # head and beak
    c.shade(lambda x, y, col: col == LAKE_ICE[1] and y > 23, LAKE_ICE[0])
    c.rect(6, 27, 26, 28, LAKE_ICE[0])


def draw_frostlight_pendant(c):
    """A drop of lake ice with a warm light caught inside."""
    pendant(c, SILVER, LAKE_ICE)
    c.disc(16, 22, 2.4, HONEY[2]); c.set(16, 22, WHITE)


def draw_jelly_pearl(c):
    """A soft-glowing sea-green pearl."""
    c.disc(16, 17, 8, SEAPEARL[1])
    light_top_left(c, SEAPEARL, 16, 17, 8)
    c.disc(13, 14, 2, WHITE)
    for (x, y) in ((27, 9), (5, 24), (26, 26)):
        c.set(x, y, SEAPEARL[2])


def draw_offering_shell(c):
    """An open white scallop shell holding glowing pearls."""
    c.poly([(4, 20), (16, 26), (28, 20), (26, 29), (6, 29)], CLOTH[2])        # the bottom half
    for x in (9, 13, 16, 19, 23):
        c.line(16, 28, x, 21, CLOTH[0])
    c.poly([(5, 18), (9, 6), (16, 3), (23, 6), (27, 18)], CLOTH[2])            # the lid, open behind
    for x in (8, 12, 16, 20, 24):
        c.line(16, 17, x, 6, CLOTH[0])
    for (x, r, colors) in ((10, 2.2, SEAPEARL), (16, 2.8, DRAGON), (22, 2.2, SEAPEARL)):
        c.disc(x, 22, r, colors[1]); c.set(x - 1, 21, WHITE)


def draw_tidesong_ring(c):
    """A sea-green silver ring with a little wave on top."""
    ring(c, SEAPEARL)
    c.line(9, 10, 12, 7, SEAPEARL[2]); c.line(12, 7, 15, 10, SEAPEARL[2])
    c.line(15, 10, 18, 7, SEAPEARL[2]); c.line(18, 7, 21, 10, SEAPEARL[2])
    c.set(22, 8, WHITE)


def draw_crystal_silk(c):
    """A skein of clear, glittering silk."""
    c.ellipse(16, 17, 10, 7, SILK[1])
    for y in range(11, 24, 2):
        c.line(7, y, 25, y + 1, WHITE if y % 4 == 1 else SILK[0])
    c.rect(14, 9, 18, 25, SILK[0]); c.rect(15, 9, 17, 25, WHITE)
    for (x, y) in ((5, 8), (27, 7), (4, 25), (28, 26)):
        c.set(x, y, WHITE); c.set(x + 1, y, SILK[1]); c.set(x, y + 1, SILK[1])


def draw_crystal_silk_gloves(c):
    """Shimmering silver-white woven gloves."""
    glove(c, SILK, SILVER)
    for y in (12, 16, 20):
        c.line(10, y, 23, y + 1, WHITE)


def draw_cloud_glass(c):
    """A round drop of clear golden glass."""
    c.disc(16, 18, 9, GOLD[2])
    c.disc(16, 18, 7, hexc("fff6c8"))
    c.shade(lambda x, y, col: col == hexc("fff6c8") and x + y > 37, GOLD[1])
    c.disc(13, 15, 2.2, WHITE)
    c.poly([(16, 4), (19, 9), (13, 9)], GOLD[2])                                # a drip on top, like a raindrop


def draw_emerald_spectacles(c):
    """Round spectacles with green glass."""
    for x in (9, 23):
        c.ring(x, 18, 6, 4.4, GOLD[1])
        c.disc(x, 18, 4.4, EMERALDGLASS[1])
        c.set(x - 2, 16, EMERALDGLASS[2]); c.set(x - 1, 15, WHITE)
    c.line(15, 17, 17, 17, GOLD[1])                                           # the bridge and arms
    c.line(3, 16, 1, 12, GOLD[1]); c.line(29, 16, 31, 12, GOLD[1])


def draw_emerald_glass_amulet(c):
    """A round green glass lens set in gold."""
    pendant(c, GOLD, EMERALDGLASS, shape="round")
    c.disc(14, 20, 1.6, WHITE)


# Every cape in items.json, in its own colour and trim (`color`, `accent`).
for _item in json.loads((ROOT / "content" / "items.json").read_text())["items"]:
    if _item["type"] == "cape":
        globals()["draw_" + _item["id"]] = (lambda colour, trim: lambda c: cape(c, ramp(colour), hexc(trim)))(_item["color"], _item["accent"])


DRAWINGS = {name[5:]: fn for name, fn in globals().items() if name.startswith("draw_")}
# Not drawn here: the Potion is a Retro Diffusion sprite (rd_pro__fantasy) and the Hi-Potion,
# Ether and Hi-Ether are palette swaps of it (`derive` in art/assets.json).

PROMPTS = {  # for a later Retro Diffusion upgrade (python3 tools/rd.py generate item_<id>)
    "potion": "round red healing potion bottle with a cork",
    "hi_potion": "big pink healing potion bottle with a gold star label",
    "ether": "blue mana potion in a cone flask with a cork",
    "hi_ether": "violet mana potion in a cone flask with a gold star",
    "seal_stone": "teal crystal sealing stone with a white spiral rune",
    "homeward_feather": "white feather with a golden quill and a soft glow",
    "pet_egg": "cream pet egg with colourful spots, wiggling",
    "wooden_sword": "small wooden practice sword",
    "steel_sword": "steel sword with a gold crossguard and a red gem",
    "oak_staff": "oak staff topped with green leaves",
    "elder_staff": "gnarled elder staff holding a glowing cyan orb",
    "iron_axe": "iron axe with a wooden handle",
    "battle_axe": "double-headed dwarven battle axe",
    "crystal_wand": "short wand with a cyan crystal tip",
    "star_wand": "golden wand with a big shining star",
    "tamer_whip": "coiled leather whip",
    "beast_whip": "red coiled whip with a paw-shaped tassel",
    "wild_horn": "curved hunting horn with a leather strap",
    "cloth_tunic": "simple beige cloth tunic with a belt",
    "leather_vest": "brown leather vest",
    "chain_mail": "chain mail shirt",
    "iron_plate": "shiny iron breastplate",
    "dragon_mail": "red dragon scale armor",
    "silk_robe": "lilac silk robe with a gold star",
    "mage_robe": "navy mage robe with gold trim",
    "snow_cloak": "white snow cloak with a fur collar",
    "ranger_cloak": "green hooded ranger cloak",
    "tamer_jacket": "orange jacket with big pockets",
    "lucky_clover": "four-leaf lucky clover",
    "ruby_ring": "gold ring with a red ruby",
    "novice_ring": "simple copper ring with a small blue stone",
    "star_charm": "gold star charm on a necklace",
    "power_band": "red wristband with steel studs",
    "speed_boots": "blue winged speed boots",
    "leather_gloves": "brown leather gloves",
    "iron_gauntlets": "studded iron gauntlets",
    "falcon_gloves": "orange falconer gloves with a white feather",
    "dragonhide_gauntlets": "red dragonhide gauntlets with claws and gold cuffs",
    "starforged_gauntlets": "navy gauntlets with gold cuffs and a gold star",
    "shell_pendant": "pink seashell pendant on a leather cord",
    "amber_amulet": "round amber amulet on a gold chain",
    "moonstone_pendant": "pale blue moonstone drop on a silver chain",
    "phoenix_amulet": "red phoenix stone with a flame inside, on a gold chain",
    "starlight_necklace": "golden star necklace that shines",
    "straw_sandals": "woven straw sandals",
    "leather_boots": "brown laced leather boots",
    "traveler_boots": "green traveller boots with gold laces",
    "cloudstep_boots": "pale blue boots standing on a little cloud",
    "moon_seal": "pale blue hexagonal crystal with a white spiral rune",
    "heart_seal": "rose pink hexagonal crystal with a white spiral rune",
    "star_seal": "golden hexagonal crystal with a white spiral rune",
    "wishing_seal": "rainbow hexagonal crystal with a violet spiral rune",
    "toy_soldier": "tin toy soldier in a red coat with a wind-up key",
    "toy_blocks": "three stacked wooden toy blocks with letters",
    "toy_music_box": "open wooden music box with a golden crank",
    "toy_ball": "bouncy red rubber ball with a yellow band and a star",
    "toy_bear": "brown teddy bear with a red bow",
    "toy_bubbles": "bubble wand blowing shiny bubbles",
    "tuft_of_wool": "soft tuft of white lamb's wool",
    "driftwood_piece": "piece of silver grey driftwood with a curl of seaweed",
    "driftwood_flute": "small flute carved from driftwood with a red cord",
    "sailcloth_scrap": "torn scrap of cream sailcloth with a blue stripe and a brass ring",
    "starwood": "pale glowing log with sparkles in its bark",
    "star_figurehead": "carved wooden ship figurehead of a maiden holding up a gold star",
    "chart_piece_compass": "torn corner of an old sea chart with a compass rose",
    "chart_piece_reef": "torn piece of an old sea chart showing a reef",
    "chart_piece_isle": "torn corner of an old sea chart with a star shaped island",
    "star_chart": "old sea chart pieced together, a gold star island on it",
    "starlight_dust": "a little heap of glittering violet and gold star dust",
    "starfall_shard": "a pale blue crystal shard with a star of light inside",
    "star_lantern": "a small glass lantern with glowing star dust inside",
    "glimmerwing_boots": "violet boots with little moth wings at the heels",
    "starweave_robe": "deep blue robe with gold trim and tiny stars on it",
    "starpetal_gauntlets": "silver gauntlets set with pale blue crystal petals",
    "stargazer_band": "night blue silver ring with a tiny gold star",
    "fallen_star_pendant": "a glowing white star stone on a silver chain",
    "starfall_staff": "white and gold magic staff with a glowing star at the tip",
    "starfall_blade": "sword with a pale star blade, gold wings on the guard",
    "starfall_axe": "axe with a pale crystal crescent head and a gold star",
    "starfall_whip": "lilac whip with a glowing star at its tip",
    "glimmerstone": "a cracked open lavender geode full of glowing cyan crystals",
    "goldleaf_plate": "ivory plate armour with gold edges and a golden leaf on the chest",
    "goldleaf_robe": "white robe trimmed in gold with a golden leaf",
    "goldleaf_gauntlets": "ivory gauntlets with a gold cuff and a golden leaf",
    "goldleaf_boots": "ivory boots with gold cuffs and a golden leaf at the heel",
    "goldleaf_pendant": "a golden leaf pendant on a gold chain",
    "goldleaf_ring": "gold ring with a golden green leaf curled over the top",
    "goldleaf_blade": "long ivory sword with a guard of gold leaves",
    "goldleaf_axe": "ivory crescent axe on a dark oak handle with a gold leaf",
    "goldleaf_staff": "dark oak staff crowned with golden leaves round a white light",
    "goldleaf_whip": "golden whip with a leaf at its tip and a dark oak grip",
    "seed_pouch": "small tied cloth pouch spilling seeds",
    "honeybee_charm": "little golden honeycomb charm with a tiny bee",
    "stray_sock": "striped woollen sock with little holes",
    "windstep_sandals": "light sandals laced with red kite string and a little feather",
    "silver_fish": "shiny silver fish",
    "glow_shell": "small spiral seashell glowing sea green",
    "shell_lantern": "lantern made of glowing seashells on a wooden frame",
    "tidecaller_pendant": "sea green pendant shaped like a wave on a cord",
    "gold_nugget": "shiny lump of gold ore",
    "prospectors_gloves": "thick tan leather work gloves with brass studs",
    "beetle_shell": "glossy dark violet beetle wing shell",
    "owl_eye_amulet": "round amber amulet shaped like an owl's eye",
    "crisp_apple": "shiny red apple with a leaf and a small bite",
    "forest_truffle": "knobbly brown truffle mushroom",
    "orchard_gloves": "soft green gardening gloves with an apple leaf stitched on",
    "sugar_crystal": "sparkly pink sugar crystal",
    "rock_candy_crown": "small crown of pink rock candy with an amber jewel",
    "peppermint_boots": "red and white striped peppermint boots",
    "healing_mud": "jar of warm brown healing mud",
    "bogwalker_boots": "tall mossy green waders boots",
    "honey_muffin": "golden honey muffin in a paper case",
    "red_hood_ribbon": "bright red ribbon tied in a bow",
    "wisp_silk": "small skein of glowing pale blue thread",
    "swan_lace_veil": "folded white lace veil with a green gem clasp",
    "swan_feather_brooch": "white swan feather brooch with a silver pin",
    "bull_horn": "curved cream bull horn",
    "bell_clapper": "iron bell clapper on a short chain",
    "bellringers_gloves": "teal gloves with little brass bells on the cuffs",
    "snake_scale": "hard brown snake scale",
    "ratcatcher_boots": "tall brown boots covered in snake scales",
    "dew_pearl": "clear round water drop pearl",
    "lotus_lantern": "tiny lotus flower lantern glowing on a bamboo stick",
    "lotus_dew_charm": "small pink lotus bud charm with a water drop",
    "golden_string": "coil of shining golden string",
    "heartwood_locket": "carved wooden heart locket on a gold chain",
    "sun_quill": "glowing golden hedgehog quill",
    "genie_lamp": "golden genie oil lamp with a glowing wick",
    "genies_ring": "gold ring with a blue swirling smoke gem",
    "raw_ore": "dark lump of raw iron ore with copper flecks",
    "forgehand_gauntlets": "heavy iron gauntlets glowing orange at the knuckles",
    "rough_gem": "cloudy uncut violet gemstone",
    "prism_lamp": "crystal prism lamp casting rainbows",
    "prism_pendant": "clear prism pendant with rainbow light on a silver chain",
    "coffee_beans": "small pile of dark roasted coffee beans",
    "sweet_dream": "small glass jar holding a glowing crescent moon dream",
    "dozy_slippers": "fluffy lavender slippers with pompoms",
    "frost_apple": "rosy red apple covered in white frost",
    "seven_hearths_ring": "gold ring set with seven tiny colourful gems",
    "moon_rice": "small cloth sack of glowing white rice",
    "mochi_tray": "stack of round white mochi on a bamboo tray",
    "moon_rabbit_charm": "silver charm of a rabbit sitting in a crescent moon",
    "lion_mane": "tawny tuft of lion mane fur",
    "great_drum": "big round hide drum trimmed with tawny mane fur",
    "steppe_runner_boots": "soft tan hide boots with red woven bands",
    "fire_pepper": "shiny red chili pepper",
    "sneezing_powder": "small bamboo pot of red pepper powder with a puff of red dust",
    "pepperfire_gauntlets": "red gauntlets with little pepper shaped studs",
    "frozen_jelly": "frozen pale blue jelly cube",
    "clear_ice": "clear blue block of ice",
    "ice_swan": "small swan carved from clear ice",
    "frostlight_pendant": "pale blue ice drop pendant with a warm light inside",
    "jelly_pearl": "soft glowing pale teal pearl",
    "offering_shell": "open white scallop shell holding glowing pearls",
    "tidesong_ring": "sea green silver ring with a small wave",
    "crystal_silk": "skein of clear glittering crystal silk thread",
    "crystal_silk_gloves": "shimmering silver white woven gloves",
    "cloud_glass": "round drop of clear golden glass",
    "emerald_spectacles": "round spectacles with green emerald glass lenses",
    "emerald_glass_amulet": "round green glass amulet set in gold",
}


for _id, _level, _name, *_rest in STAFFS:
    PROMPTS[_id] = f"{_name.lower()}, a magic staff"


for _table, _what in ((SWORDS, "a sword"), (AXES, "an axe"), (WHIPS, "a whip")):
    for _id, _level, _name, *_rest in _table:
        PROMPTS[_id] = f"{_name.lower()}, {_what}"
for _id, _kind, _level, _name, *_rest in MATERIALS:
    PROMPTS[_id] = f"{_name.lower()}, a crafting material"


# Magic weapons (items.json `glow` + `glowAt`): a small soft halo around the tip, added after the
# outline. The game adds the same glow, gently pulsing, when the weapon is held.
def _glows():
    items = json.loads((pathlib.Path(__file__).resolve().parent.parent / "content" / "items.json").read_text())["items"]
    return {i["id"]: (i["glowAt"][0], i["glowAt"][1], 10, hexc(i["glow"].lstrip("#")))
            for i in items if i.get("glow") and i.get("glowAt")}


GLOWS = _glows()


def halo(c, cx, cy, radius, color):
    """Fills empty pixels near the tip with the glow colour, fading out with distance."""
    r, g, b = color[:3]
    for y in range(SIZE):
        for x in range(SIZE):
            if c.px[y][x] is not None:
                continue
            d = math.hypot(x - cx, y - cy) / radius
            if d < 1:
                alpha = int(185 * (1 - d) ** 1.3)
                if alpha > 12:
                    c.px[y][x] = (r, g, b, alpha)


def render(item_id):
    canvas = Canvas()
    DRAWINGS[item_id](canvas)
    canvas.outline()
    if item_id in GLOWS:
        halo(canvas, *GLOWS[item_id])
    return canvas


def main(argv):
    sheet_path = None
    if "--sheet" in argv:
        index = argv.index("--sheet")
        sheet_path = argv[index + 1]
        argv = argv[:index] + argv[index + 2:]
    ids = argv or sorted(DRAWINGS)
    for item_id in ids:
        (SPRITES / f"item_{item_id}.png").write_bytes(render(item_id).png())
    print(f"wrote {len(ids)} item sprites to art/sprites/")
    if sheet_path:
        columns, scale, pad = 6, 4, 4
        rows = math.ceil(len(ids) / columns)
        cell = SIZE * scale + pad
        width, height = columns * cell + pad, rows * cell + pad
        pixels = [[(238, 245, 251, 255)] * width for _ in range(height)]
        for n, item_id in enumerate(ids):
            art = render(item_id)
            ox, oy = pad + (n % columns) * cell, pad + (n // columns) * cell
            for y in range(SIZE * scale):
                for x in range(SIZE * scale):
                    c = art.px[y // scale][x // scale]
                    if c:   # blend, so soft glows show as they will in the game
                        a = c[3] / 255
                        bg = pixels[oy + y][ox + x]
                        pixels[oy + y][ox + x] = tuple(int(c[i] * a + bg[i] * (1 - a)) for i in range(3)) + (255,)
        raw = b"".join(b"\x00" + b"".join(bytes(p) for p in row) for row in pixels)
        pathlib.Path(sheet_path).write_bytes(encode_png(width, height, raw))
        print(f"contact sheet: {sheet_path} (order: {', '.join(ids)})")


if __name__ == "__main__":
    main(sys.argv[1:])
