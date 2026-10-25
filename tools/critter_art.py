#!/usr/bin/env python3
"""The critters (`ambience.critters`: bunnies, frogs, songbirds...), the birds crossing the sky and the
butterflies (`ambience.butterflies`), in the game's pixel style (docs/pixel-style.md): each drawing
`Storyleaf/World/Critters.swift` made pixel by pixel, flat, in one near-black outline, redrawn here with
tools/pixel_kit.py as the same shapes at the same size, lit from the top left (a lighter edge there, a
hue-shifted shade at the bottom right), outlined in a deep shade of each part instead of one near-black.
The butterflies are drawn anew at the critters' size (`Ambience.swift` drew them 7 × 5, three times as big).

    python3 tools/critter_art.py                 # all → art/sprites/critter_<name>.png
    python3 tools/critter_art.py --sheet out.png # a contact sheet at 6×

`CritterArt.drawn` loads them by name (`bunny_brown_sit`, `songbird_robin_peck`, `flock_gulls_up`,
`butterfly_pink_open`...); one that's missing is drawn as before, in code. Each faces right, one pixel of
room round the drawing for its outline.
"""

import colorsys
import pathlib
import sys

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPRITES = ROOT / "art" / "sprites"
INK = "#3b2a22"


def hexc(v):
    return v if isinstance(v, str) else "#%06x" % v


def _hsv(c):
    return colorsys.rgb_to_hsv(*(np.array(c[:3]) / 255))


def _rgb(h, s, v):
    return [int(round(x * 255)) for x in colorsys.hsv_to_rgb(h % 1, min(1, max(0, s)), min(1, max(0, v)))]


def _turn(h, s, degrees):
    """Hue `h` turned `degrees` away from yellow (toward it, negative), the short way round; a grey
    (low saturation) leans toward blue instead, as RD's whites shade."""
    if s < 0.12:
        return 0.6
    away = 1 if ((h * 360 - 50) % 360) < 180 else -1
    return h + away * degrees / 360


def shade(c, k):
    """`c` darker (k < 1: deeper, richer, turned from yellow) or lighter (k > 1: paler, toward yellow)."""
    h, s, v = _hsv(c)
    if k < 1:
        return _rgb(_turn(h, s, 14 * (1 - k) / 0.25), max(s * 1.12 + 0.04, 0.18 if s < 0.12 else 0), v * k)
    return _rgb(_turn(h, s, -10 * (k - 1) / 0.15), s * 0.82, v * k)


class Critter:
    """A drawing in the Swift canvas's coordinates (a pixel's middle at +0.5), a pixel of room added
    round it: `ell` and `rect` are shapes, `dot` a pixel laid on after (an eye, a foot), `cut` a pixel
    cleared (a pincer's notch). At 10 to 15 pixels pixel_kit's finish turned them muddy (most of a tiny
    sprite is edge), so each shape keeps its colour and is lit as RD lights a small sprite: its edge
    toward the top left a shade lighter, toward the bottom right a shade darker and turned from yellow,
    a shade darker again under a shape lying on it, and an outline in a deep shade of what it rounds."""

    def __init__(self, w, h, outline="tinted"):
        self.w, self.h, self.outline = w + 2, h + 2, outline
        self.shapes, self.dots, self.cuts = [], [], []

    def _grid(self):
        ys, xs = np.mgrid[0:self.h, 0:self.w]
        return xs + 0.5, ys + 0.5

    def ell(self, cx, cy, rx, ry, colour):
        x, y = self._grid()
        self.shapes.append((((x - cx - 1) / rx) ** 2 + ((y - cy - 1) / ry) ** 2 <= 1, colour))

    def rect(self, x, y, w, h, colour):
        m = np.zeros((self.h, self.w), bool)
        m[y + 1:y + 1 + h, x + 1:x + 1 + w] = True
        self.shapes.append((m, colour))

    def dot(self, x, y, colour):
        self.dots.append((x + 1, y + 1, colour))

    def cut(self, x, y):
        self.cuts.append((x + 1, y + 1))

    def render(self):
        def rgb(c):
            c = hexc(c)
            return [int(c[k:k + 2], 16) for k in (1, 3, 5)]
        idx = np.full((self.h, self.w), -1)
        for n, (m, _) in enumerate(self.shapes):
            idx[m] = n
        img = np.zeros((self.h, self.w, 4), np.uint8)
        H, W = idx.shape

        colour = np.full((H, W), -1)
        for n, (m, c) in enumerate(self.shapes):
            colour[m] = int(hexc(c)[1:], 16)

        def out(y, x):
            return not (0 <= y < H and 0 <= x < W) or idx[y, x] < 0
        for y in range(H):
            for x in range(W):
                n = idx[y, x]
                if n < 0:
                    continue
                base = rgb(self.shapes[n][1])
                # Lit where the animal's top or left meets the air, shaded where its bottom or right
                # does, and under a part of another colour lying over it (above and left of it).
                lit = out(y - 1, x) or out(y, x - 1)
                dim = out(y + 1, x) or out(y, x + 1)
                over = idx[y - 1, x - 1] if y and x else -1
                under = over > n and colour[y - 1, x - 1] != colour[y, x]
                k = 0.84 if dim or under else 1.1 if lit else 1.0
                img[y, x, :3] = shade(base, k) if k != 1.0 else base
                img[y, x, 3] = 255
        if self.outline:
            solid = img[..., 3] > 0
            for y in range(H):
                for x in range(W):
                    if solid[y, x]:
                        continue
                    inside = [(y + dy, x + dx) for dy, dx in ((1, 0), (0, 1), (-1, 0), (0, -1))
                              if 0 <= y + dy < H and 0 <= x + dx < W and solid[y + dy, x + dx]]
                    if inside:
                        yy, xx = inside[0]
                        base = rgb(self.shapes[idx[yy, xx]][1])
                        lit = (yy, xx) in ((y + 1, x), (y, x + 1))   # the top or left of the shape
                        img[y, x, :3] = shade(base, 0.5 if lit else 0.4)
                        img[y, x, 3] = 255
        for x, y, c in self.dots:
            if 0 <= x < W and 0 <= y < H:
                img[y, x] = rgb(c) + [255]
        for x, y in self.cuts:
            img[y, x] = 0
        return Image.fromarray(img, "RGBA")


# --------------------------------------------------------------------------------------- the critters

def songbird(pose, back, breast, wing, beak=0xF2B33D, eye=None, long_beak=False):
    leg = beak if long_beak else 0xC08A50
    eye = eye or INK
    c = Critter(11, 10)
    if pose == "fly":
        c.ell(5.5, 6.2, 3.0, 1.6, back)
        c.ell(6.8, 6.8, 1.6, 1.0, breast)
        c.ell(8.4, 5.0, 1.8, 1.7, back)
        for y, a, b in ((1, 4, 5), (2, 3, 6), (3, 3, 6), (4, 4, 6)):
            c.rect(a, y, b - a + 1, 1, wing)
        c.rect(0, 6, 3, 1, wing)
        c.dot(9, 4, eye)
        c.dot(10, 5, beak)
    elif pose == "peck":
        c.ell(4.6, 5.6, 3.4, 2.5, back)
        c.ell(6.4, 6.4, 1.8, 1.7, breast)
        c.ell(3.8, 5.2, 2.2, 1.3, wing)
        c.ell(8.2, 6.8, 2.1, 2.0, back)
        c.rect(0, 3, 2, 2, wing)
        c.dot(8, 6, eye)
        c.dot(10, 8, beak)
        c.dot(5, 9, leg)
        c.dot(7, 9, leg)
    else:
        c.ell(4.8, 6.2, 3.4, 2.6, back)
        c.ell(6.6, 6.4, 1.8, 1.9, breast)
        c.ell(8.2, 5.0, 1.2, 1.0, breast)
        c.ell(7.6, 3.6, 2.3, 2.2, back)
        c.ell(4.0, 5.8, 2.2, 1.3, wing)
        c.rect(0, 4, 2, 2, wing)
        c.dot(8, 3, eye)
        c.dot(10, 4, beak)
        if long_beak:
            c.dot(9, 4, beak)
        if pose == "sit":
            c.dot(5, 9, leg)
            c.dot(7, 9, leg)
    return c


def chick(pose):
    body, wing, beak = 0xFFD84A, 0xF0B830, 0xF08A30
    c = Critter(9, 9)
    if pose == "peck":
        c.ell(3.6, 4.6, 3.2, 2.6, body)
        c.ell(6.0, 5.6, 1.8, 1.6, body)
        c.ell(2.8, 4.6, 1.6, 1.0, wing)
        c.dot(6, 5, INK)
        c.dot(8, 6, beak)
        c.dot(3, 8, beak)
        c.dot(5, 8, beak)
    else:
        c.ell(3.8, 5.0, 3.2, 2.8, body)
        c.ell(5.4, 3.0, 1.9, 1.8, body)
        c.ell(3.0, 5.2, 1.6, 1.0, wing)
        c.dot(5, 2, INK)
        c.dot(7, 3, beak)
        if pose == "sit":
            c.dot(3, 8, beak)
            c.dot(5, 8, beak)
    return c


def squirrel(hop):
    fur, tail, tip, belly, dark = 0xB5652F, 0xC0703A, 0xE39C5E, 0xF0D2A8, 0x7A3F1C
    c = Critter(15, 13)
    if hop:
        c.ell(3.0, 7.0, 3.2, 2.6, tail)
        c.ell(1.8, 6.0, 1.6, 1.4, tip)
        c.ell(8.0, 8.4, 3.8, 2.4, fur)
        c.ell(9.0, 9.4, 2.0, 1.2, belly)
        c.ell(11.8, 6.0, 2.4, 2.1, fur)
        c.rect(11, 2, 2, 2, fur)
        c.dot(12, 5, INK)
        c.dot(14, 6, dark)
        c.rect(4, 11, 2, 1, dark)
        c.rect(12, 10, 2, 1, dark)
    else:
        c.ell(3.2, 5.0, 3.0, 4.2, tail)
        c.ell(2.4, 3.2, 1.8, 2.0, tip)
        c.ell(8.2, 9.0, 3.4, 3.0, fur)
        c.ell(9.4, 9.8, 1.6, 1.8, belly)
        c.ell(10.8, 5.6, 2.4, 2.2, fur)
        c.rect(10, 2, 2, 2, fur)
        c.dot(11, 5, INK)
        c.dot(13, 6, dark)
        c.rect(7, 12, 2, 1, dark)
        c.rect(10, 12, 2, 1, dark)
    return c


def lizard(step):
    body, spot = 0xD2A85A, 0x9A6A30
    c = Critter(17, 9)
    c.ell(8.5, 4.5, 4.0, 1.8, body)
    c.ell(13.6, 4.2, 2.4, 1.6, body)
    c.rect(3, 4, 2, 2, body)
    c.rect(1, 5, 2, 1, body)
    c.rect(0, 6, 1, 1, body)
    for x, y in ((7, 4), (9, 3), (10, 5)):
        c.dot(x, y, spot)
    c.dot(14, 3, INK)
    legs = ((11, 2), (12, 1), (6, 6), (5, 7), (11, 6), (12, 7), (6, 2), (5, 1)) if step else \
        ((11, 2), (10, 1), (6, 6), (7, 7), (11, 6), (10, 7), (6, 2), (7, 1))
    for x, y in legs:
        c.rect(x, y, 1, 1, spot)
    return c


def spider(step):
    body, sheen, leg, eye = 0x2A2233, 0x5A3F78, 0x1C1724, 0xFF4040
    c = Critter(16, 12)
    c.ell(6.2, 5.6, 3.4, 2.6, body)
    c.ell(5.4, 4.6, 1.6, 0.9, sheen)
    c.ell(10.6, 5.8, 2.0, 1.8, body)
    for x, y in ((11, 5), (12, 5), (12, 6)):
        c.dot(x, y, eye)
    # Legs after the outline, so they stay thin: hip, a step out, knee, foot.
    for index, (x, dx) in enumerate(((5, -2), (7, -1), (9, 1), (11, 2))):
        lift = 1 if (index % 2 == 0) == step else 0
        sgn = 1 if dx > 0 else -1
        for sign, hip in ((-1, 4), (1, 7)):
            for px, py in ((x, hip), (x + sgn, hip + sign), (x + dx, hip + sign * (3 - lift)),
                           (x + 2 * dx, hip + sign * (2 - lift) + sign * 2)):
                c.dot(px, py, leg)
    return c


def rat(step):
    fur, belly, pink, eye = 0x6E5E54, 0x9A8A7C, 0xD99AA4, 0xFF3A3A
    c = Critter(17, 8)
    c.ell(7.0, 4.6, 4.4, 2.6, fur)
    c.ell(11.4, 4.4, 2.6, 2.0, fur)
    c.ell(7.6, 5.6, 2.6, 1.2, belly)
    c.ell(10.0, 2.0, 1.5, 1.4, fur)
    c.rect(14, 4, 1, 1, fur)
    for x, y in ((0, 2), (1, 3), (1, 4), (2, 5), (3, 5)):
        c.dot(x, y, pink)
    c.dot(10, 1, pink)
    c.dot(12, 3, eye)
    c.dot(15, 5, pink)
    for x, y in (((5, 7), (9, 7)) if step else ((4, 7), (8, 7))):
        c.dot(x, y, 0x4A3E36)
    return c


def scorpion(step):
    body, light, dark = 0x8A3A2A, 0xB85A3E, 0x5A2218
    c = Critter(16, 11)
    c.ell(7.5, 7.0, 4.0, 2.0, body)
    c.ell(7.0, 6.4, 2.2, 0.8, light)
    for x, y in ((3, 6), (2, 5), (2, 4), (2, 3), (3, 2), (4, 1), (5, 1), (6, 2)):
        c.rect(x, y, 1, 1, body)
    c.ell(13.4, 5.8, 1.8, 1.5, body)
    c.rect(12, 7, 1, 1, body)
    c.rect(11, 6, 1, 1, body)
    c.dot(7, 3, dark)
    c.dot(6, 3, dark)
    c.dot(10, 6, 0x1A0A08)
    c.cut(15, 6)
    c.cut(14, 6)
    for x, y in (((5, 9), (7, 9), (9, 9), (10, 9)) if step else ((4, 9), (6, 9), (8, 9), (10, 9))):
        c.dot(x, y, dark)
    return c


def wisp(flicker):
    """A will-o'-wisp is light: no outline, its colours laid flat from the rim in to a white core."""
    core, mid, edge, eye = 0xF2FFFF, 0xA8ECFF, 0x5EC4F0, 0x1E3A5A
    c = Critter(11, 13, outline=None)
    c.ell(5.5, 8.0, 4.2, 4.2, edge)
    tip = ((5, 0), (4, 1), (5, 1), (6, 2), (3, 2), (4, 2), (5, 2), (3, 3)) if flicker else \
        ((5, 0), (6, 1), (5, 1), (4, 2), (5, 2), (6, 2), (7, 3))
    for x, y in tip:
        c.rect(x, y, 1, 1, edge)
    c.rect(3, 3, 5, 2, edge)
    c.ell(5.5, 8.4, 3.0, 3.0, mid)
    c.ell(5.5, 9.0, 1.8, 1.8, core)
    for x, y in ((4, 8), (7, 8), (4, 7), (7, 7)):
        c.dot(x, y, eye)
    return c


def mouse(step):
    fur, ear, pink, feet = 0x9A9AA6, 0xB8B8C4, 0xE7A6B0, 0x6A6A76
    c = Critter(12, 7)
    c.ell(5.4, 4.4, 3.6, 2.3, fur)
    c.ell(8.6, 4.0, 2.0, 1.7, fur)
    c.ell(7.4, 1.8, 1.6, 1.5, ear)
    c.dot(7, 1, pink)
    c.dot(9, 3, INK)
    c.dot(11, 4, pink)
    for x, y in ((0, 3), (0, 4), (1, 5), (2, 5)):
        c.dot(x, y, pink)
    for x, y in (((4, 6), (7, 6)) if step else ((3, 6), (6, 6))):
        c.dot(x, y, feet)
    return c


def bunny(fur, light, dark, hop):
    pink, nose = 0xF2A7B5, 0xE58A9A
    c = Critter(15, 13)
    if hop:
        c.ell(6.5, 7.4, 5.4, 3.0, fur)
        c.ell(7.5, 8.4, 2.8, 1.5, light)
        c.ell(11.2, 4.9, 2.7, 2.4, fur)
        c.rect(8, 0, 2, 3, fur)
        c.rect(10, 0, 2, 3, fur)
        c.ell(1.6, 6.6, 1.5, 1.5, 0xFFFFFF)
        c.rect(0, 9, 4, 1, dark)
        c.rect(11, 9, 3, 1, dark)
        c.dot(8, 1, pink)
        c.dot(12, 4, INK)
        c.dot(14, 5, nose)
    else:
        c.ell(6.2, 8.6, 4.8, 3.6, fur)
        c.ell(7.2, 9.6, 2.6, 1.9, light)
        c.ell(10.6, 5.6, 2.8, 2.5, fur)
        c.rect(9, 0, 2, 4, fur)
        c.rect(12, 1, 2, 3, fur)
        c.ell(1.8, 7.8, 1.5, 1.5, 0xFFFFFF)
        c.rect(3, 12, 3, 1, dark)
        c.rect(8, 12, 2, 1, dark)
        c.dot(9, 1, pink)
        c.dot(9, 2, pink)
        c.dot(11, 5, INK)
        c.dot(13, 6, nose)
    return c


def frog(hop):
    green, light, dark, belly = 0x6DBE45, 0x9BD86A, 0x3F8A2A, 0xD8EE9A
    c = Critter(13, 10)
    if hop:
        c.ell(6.2, 5.2, 5.2, 2.6, green)
        c.ell(7.2, 6.2, 2.8, 1.3, belly)
        c.ell(8.2, 2.4, 1.6, 1.6, green)
        c.ell(10.8, 2.8, 1.6, 1.6, green)
        c.rect(0, 6, 3, 1, dark)
        c.rect(0, 7, 2, 1, dark)
        c.rect(10, 7, 3, 1, dark)
        for x, y, col in ((8, 1, 0xFFFFFF), (9, 1, INK), (11, 2, 0xFFFFFF), (12, 2, INK)):
            c.dot(x, y, col)
    else:
        c.ell(5.6, 6.6, 4.8, 3.0, green)
        c.ell(6.8, 7.6, 2.8, 1.6, belly)
        c.ell(3.2, 3.9, 1.8, 0.9, light)
        c.ell(2.4, 8.2, 2.2, 1.4, dark)
        c.ell(7.5, 3.2, 1.7, 1.7, green)
        c.ell(10.4, 3.5, 1.7, 1.7, green)
        c.rect(9, 6, 3, 1, dark)
        c.rect(1, 9, 3, 1, dark)
        c.rect(8, 9, 2, 1, dark)
        for x, y, col in ((7, 2, 0xFFFFFF), (8, 2, INK), (10, 3, 0xFFFFFF), (11, 3, INK)):
            c.dot(x, y, col)
    return c


def crab(up):
    red, light, dark = 0xE8603C, 0xF89A6E, 0xA73A24
    c = Critter(15, 10)
    lift = 1 if up else 0
    for x, y in (((3, 8), (2, 9), (4, 9), (11, 8), (12, 9), (10, 9)) if up else
                 ((3, 8), (3, 9), (5, 9), (11, 8), (11, 9), (9, 9))):
        c.rect(x, y, 1, 1, dark)
    c.ell(7.5, 6.6, 4.1, 2.5, red)
    c.ell(7.5, 5.8, 2.4, 0.9, light)
    c.rect(3, 6 - lift, 1, 1, dark)
    c.rect(11, 6 - lift, 1, 1, dark)
    c.ell(1.9, 5.0 - lift, 1.7, 1.6, red)
    c.ell(13.1, 5.0 - lift, 1.7, 1.6, red)
    c.cut(1, 4 - lift)
    c.cut(13, 4 - lift)
    c.rect(6, 3, 1, 1, dark)
    c.rect(9, 3, 1, 1, dark)
    c.dot(6, 2, INK)
    c.dot(9, 2, INK)
    return c


def flock(kind, up):
    """The birds crossing the sky: thin, seen from below, so no outline but their own darkest shade."""
    if kind == "gulls":
        c = Critter(15, 6, outline=None)
        grey, tip = 0xC9D2DA, 0x4A4F57
        wing = ((0, 0), (1, 1), (2, 1), (3, 2), (4, 3), (10, 3), (11, 2), (12, 1), (13, 1), (14, 0)) if up else \
            tuple((x, 3) for x in (0, 1, 2, 3, 4, 10, 11, 12, 13, 14))
        for x, y in wing:
            c.dot(x, y, grey)
        c.dot(*wing[0], tip)
        c.dot(*wing[9], tip)
        c.rect(5, 3, 5, 2, 0xF4F6F8)
        c.dot(10, 4, 0xF2B33D)
        return c
    if kind == "bats":
        c = Critter(13, 6, outline=None)
        wing, body = 0x3A2A4A, 0x261A30
        spans = ((0, 0, 1), (0, 11, 12), (1, 1, 4), (1, 8, 11), (2, 2, 5), (2, 7, 10), (3, 4, 5), (3, 7, 8)) if up else \
            ((2, 0, 4), (2, 8, 12), (3, 1, 4), (3, 8, 11), (4, 1, 1), (4, 3, 3), (4, 9, 9), (4, 11, 11))
        for y, a, b in spans:
            for x in range(a, b + 1):
                c.dot(x, y, wing)
        c.rect(5, 2, 3, 3, body)
        c.dot(5, 1, body)
        c.dot(7, 1, body)
        return c
    c = Critter(9, 5, outline=None)
    body, wing = 0x6B4E3A, 0x8C6A50
    for x, y in (((0, 0), (1, 1), (2, 2), (6, 2), (7, 1), (8, 0)) if up else ((0, 3), (1, 2), (2, 2), (6, 2), (7, 2), (8, 3))):
        c.dot(x, y, wing)
    for x, y in ((3, 2), (4, 2), (5, 2), (5, 1), (4, 3)):
        c.dot(x, y, body)
    return c


def butterfly(colour, pose):
    """A butterfly (`ambience.butterflies`, `Ambience.butterfly`) seen from above as it flutters: wings
    spread (`open`), raised (`half`, seen narrower) or folded up over its back (`closed`); forewings in
    its colour with a deeper tip and a pale spot, a notch at the side, hindwings a shade deeper tapering
    to the tail, a dark body with antennae. Drawn at the critters' size, a pixel to a pixel: the one
    drawn in Swift was 7 × 5, shown three times as big, its pixels three times everyone else's."""
    wing = rgb_of(colour)
    hind, tip, spot = hexc_of(shade(wing, 0.88)), hexc_of(shade(wing, 0.72)), hexc_of(shade(wing, 1.14))
    wing = hexc(colour)
    body = 0x4A3426
    c = Critter(13, 10)
    # The left wings, row by row (y, first x, last x), mirrored round the body's column (x 6).
    rows = {
        "open": ([(1, 1, 4), (2, 0, 5), (3, 0, 5), (4, 1, 5), (5, 3, 5)], [(6, 2, 5), (7, 1, 5), (8, 2, 4), (9, 3, 4)],
                 [(1, 1, 2), (2, 0, 0)], (2, 3)),
        "half": ([(1, 2, 4), (2, 2, 5), (3, 2, 5), (4, 3, 5), (5, 4, 5)], [(6, 3, 5), (7, 3, 5), (8, 4, 5)],
                 [(1, 2, 2), (2, 2, 2)], (3, 3)),
        "closed": ([(0, 5, 5), (1, 4, 5), (2, 4, 5), (3, 4, 5), (4, 5, 5), (5, 5, 5)], [(6, 5, 5)], [(0, 5, 5)], None),
    }[pose]
    fore, back, tips, mark = rows
    for colour_, spans in ((wing, fore), (hind, back), (tip, tips)):
        for y, x0, x1 in spans:
            c.rect(x0, y, x1 - x0 + 1, 1, colour_)
            c.rect(12 - x1, y, x1 - x0 + 1, 1, colour_)
    c.rect(6, 2, 1, 7, body)
    if mark:
        c.dot(mark[0], mark[1], spot)
        c.dot(12 - mark[0], mark[1], spot)
    # The antennae, a pixel each, after the outline so they stay fine.
    for x, y in ((5, 0), (7, 0), (6, 1)):
        c.dot(x, y, body)
    return c


def rgb_of(c):
    c = hexc(c)
    return [int(c[k:k + 2], 16) for k in (1, 3, 5)]


def hexc_of(c):
    return "#%02x%02x%02x" % tuple(c)


# The butterflies' colours, as `Ambience.butterfly` picks them.
# Its yellow a touch warmer than the Swift drawing's lemon, whose shades turned green.
WINGS = {"pink": 0xF8BBD0, "yellow": 0xFFEEA0, "blue": 0xB3E5FC, "lilac": 0xE1BEE7, "orange": 0xFFCC80}

COATS = {"brown": (0xB98A62, 0xE2C29F, 0x7D5A3F), "cream": (0xEDDCC2, 0xFFF6E8, 0xB8A386),
         "grey": (0xA9A9B0, 0xD8D8DE, 0x707078), "white": (0xF4F4F4, 0xFFFFFF, 0xC0C0C8)}
PLUMES = {"robin": (0x8A6248, 0xE8834A, 0x6B4A36), "bluebird": (0x4F7FC8, 0xE8A06A, 0x3A5E9A),
          "finch": (0xD9B23A, 0xF4DA74, 0x7A6028)}
POSES = ("sit", "hop", "peck", "fly")


def drawings():
    out = {}
    for name, (fur, light, dark) in COATS.items():
        for hop in (False, True):
            out[f"bunny_{name}_{'hop' if hop else 'sit'}"] = lambda f=fur, l_=light, d=dark, h=hop: bunny(f, l_, d, h)
    for name, (back, breast, wing) in PLUMES.items():
        for pose in POSES:
            out[f"songbird_{name}_{pose}"] = lambda p=pose, b=back, br=breast, w=wing: songbird(p, b, br, w)
    for pose in POSES:
        out[f"crow_{pose}"] = lambda p=pose: songbird(p, 0x2E2C3A, 0x3C3A4C, 0x211F2C, beak=0x6E6A78, eye=0xFF4A4A,
                                                      long_beak=True)
    for pose in ("sit", "hop", "peck"):
        out[f"chick_{pose}"] = lambda p=pose: chick(p)
    out["frog_sit"], out["frog_hop"] = (lambda: frog(False)), (lambda: frog(True))
    out["crab_down"], out["crab_up"] = (lambda: crab(False)), (lambda: crab(True))
    out["squirrel_sit"], out["squirrel_hop"] = (lambda: squirrel(False)), (lambda: squirrel(True))
    for kind, fn in (("spider", spider), ("rat", rat), ("scorpion", scorpion), ("lizard", lizard), ("mouse", mouse),
                     ("wisp", wisp)):
        out[f"{kind}_a"], out[f"{kind}_b"] = (lambda f=fn: f(False)), (lambda f=fn: f(True))
    for name, colour in WINGS.items():
        for pose in ("open", "half", "closed"):
            out[f"butterfly_{name}_{pose}"] = lambda c=colour, p=pose: butterfly(c, p)
    for kind in ("gulls", "bats", "songbirds"):
        out[f"flock_{kind}_up"], out[f"flock_{kind}_down"] = (lambda k=kind: flock(k, True)), (lambda k=kind: flock(k, False))
    return out


def main(argv):
    sheet = None
    if "--sheet" in argv:
        i = argv.index("--sheet")
        sheet = argv[i + 1]
        argv = argv[:i] + argv[i + 2:]
    all_ = drawings()
    ids = argv or list(all_)
    out = {}
    for name in ids:
        img = all_[name]().render()
        img.save(SPRITES / f"critter_{name}.png")
        out[name] = img
    print(f"wrote {len(out)} critters to art/sprites/")
    if sheet:
        k, cell, cols = 6, 20 * 6, 8
        board = Image.new("RGBA", (cols * cell, -(-len(out) // cols) * cell), (106, 150, 86, 255))
        for n, img in enumerate(out.values()):
            big = img.resize((img.width * k, img.height * k), Image.NEAREST)
            board.alpha_composite(big, ((n % cols) * cell + (cell - big.width) // 2, (n // cols) * cell + (cell - big.height) // 2))
        board.save(sheet)
        print(f"sheet in {sheet}")


if __name__ == "__main__":
    main(sys.argv[1:])
