#!/usr/bin/env python3
"""Draws every skill's icon in code, as light: the glows, flares, sparks and trails its battle
animation is made of (`TalesOfDorlune/Battle/SkillStyles.swift`, `ElementEffects.swift`), in its colours,
on a dark backdrop of its own tile's colour. Not pixel art (playtesting 2026-10-23: "the spell icons
don't have to be pixel art, but could be more like their animations, with flares and glows"): drawn
smooth at 512 pixels and shrunk to 128, shown smoothed by the game (`IconTile`, `BattleScene.skillTile`).

    python3 tools/skill_art.py                 # all skills → art/sprites/skill_<id>.png
    python3 tools/skill_art.py fire_bolt flash # just these
    python3 tools/skill_art.py --sheet out.png # a contact sheet, each on its tile's colour

The icons sit on the coloured tile of the skill's element or kind, which frames them.
"""

import math
import pathlib
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPRITES = ROOT / "art" / "sprites"
N = 512                      # drawn at
OUT = 128                    # shipped at


def rgb(hexcode):
    h = hexcode.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], float) / 255


# Each element's light, as `ElementEffects.ElementLight` has it (deep, main, bright, core), and the
# same four for what has no element: healing's green, a buff's sky blue, a curse's and Dark's violet,
# Light's gold, Metal's silver-gold, a blow's white-hot orange.
LIGHTS = {
    "fire": ["#fa4d0a", "#ff801f", "#ffcc66", "#fff5cc"],
    "water": ["#0d61f2", "#4d9eff", "#99d9ff", "#e6faff"],
    "wood": ["#1a991f", "#66e047", "#b8ff80", "#ebffcc"],
    "earth": ["#80470f", "#cc802e", "#f2b359", "#ffe09e"],
    "light": ["#f2a30d", "#ffd640", "#fff08c", "#fffde6"],
    "dark": ["#4a1a8c", "#8a4ae0", "#c69aff", "#f0e6ff"],
    "metal": ["#a6801a", "#e6c24a", "#fff0a0", "#fffef0"],
    "heal": ["#14904a", "#3cd77a", "#a6ffc4", "#effff4"],
    "buff": ["#1a5ec8", "#4a9cff", "#a8d8ff", "#f0fbff"],
    "poison": ["#3a8a14", "#86d42a", "#d0ff70", "#f6ffd8"],
    "blow": ["#e0401a", "#ff9a3a", "#ffe08a", "#fffbe8"],
    "white": ["#8aa0c0", "#d0e0f4", "#f4f8ff", "#ffffff"],
}
LIGHTS = {k: [rgb(c) for c in v] for k, v in LIGHTS.items()}

# The tile behind each icon (SkillDef.tileColor): its element's colour, else its kind's.
TILES = {"fire": "#ff8033", "water": "#59a6ff", "wood": "#73d959", "earth": "#bf8c4d", "metal": "#d9d9e6",
         "light": "#fff28c", "dark": "#9966d9", "heal": "#4db873", "revive": "#4db873", "buff": "#4d8cd9",
         "curse": "#73479e", "field": "#d9a640", "magic": "#8c6be6", "physical": "#d96b52"}


class Icon:
    """A 512-pixel picture built up in layers, composited "over" in premultiplied colour. Coordinates
    are 0 to 1 across the picture, (0, 0) at the top left."""

    def __init__(self, backdrop):
        self.rgb = np.zeros((N, N, 3))
        self.a = np.zeros((N, N))
        y, x = (np.mgrid[0:N, 0:N] + 0.5) / N
        self.x, self.y = x, y
        if backdrop is not None:
            # The dark of the tile's own colour, lit a little in the middle, so light reads on it.
            d = np.hypot(x - 0.5, y - 0.45)
            centre, edge = backdrop * 0.42, backdrop * 0.13
            self.over(centre * (1 - np.clip(d / 0.75, 0, 1))[..., None] + edge * np.clip(d / 0.75, 0, 1)[..., None],
                      np.ones((N, N)))

    # --- compositing ----------------------------------------------------------------------------

    def over(self, colour, alpha):
        """`colour` (an RGB triple, or an N × N × 3 field) laid over what's there with `alpha` (0 to 1)."""
        alpha = np.clip(alpha, 0, 1)
        c = np.broadcast_to(np.asarray(colour, float), (N, N, 3))
        self.rgb = c * alpha[..., None] + self.rgb * (1 - alpha[..., None])
        self.a = alpha + self.a * (1 - alpha)

    def add(self, colour, amount):
        """Light added on top: brightens toward `colour` and white where it piles up, as a glow does."""
        amount = np.clip(amount, 0, None)
        c = np.broadcast_to(np.asarray(colour, float), (N, N, 3))
        self.rgb = 1 - (1 - self.rgb) * (1 - np.clip(c * amount[..., None], 0, 1))    # screen
        self.a = np.clip(self.a + amount * (1 - self.a), 0, 1)

    # --- masks ----------------------------------------------------------------------------------

    @staticmethod
    def _canvas():
        return Image.new("L", (N, N), 0)

    @staticmethod
    def _px(points):
        return [(px * N, py * N) for px, py in points]

    def poly(self, points, blur=0.0):
        img = self._canvas()
        ImageDraw.Draw(img).polygon(self._px(points), fill=255)
        return self._done(img, blur)

    def ellipse(self, cx, cy, rx, ry=None, blur=0.0):
        ry = rx if ry is None else ry
        img = self._canvas()
        ImageDraw.Draw(img).ellipse([(cx - rx) * N, (cy - ry) * N, (cx + rx) * N, (cy + ry) * N], fill=255)
        return self._done(img, blur)

    def line(self, points, width, blur=0.0):
        img = self._canvas()
        d = ImageDraw.Draw(img)
        px = self._px(points)
        d.line(px, fill=255, width=max(1, int(width * N)), joint="curve")
        r = width * N / 2
        for x, y in (px[0], px[-1]):
            d.ellipse([x - r, y - r, x + r, y + r], fill=255)
        return self._done(img, blur)

    def ring(self, cx, cy, r, width, blur=0.0):
        img = self._canvas()
        ImageDraw.Draw(img).ellipse([(cx - r) * N, (cy - r) * N, (cx + r) * N, (cy + r) * N], outline=255,
                                    width=max(1, int(width * N)))
        return self._done(img, blur)

    def arc(self, cx, cy, r, start, end, width, blur=0.0):
        img = self._canvas()
        ImageDraw.Draw(img).arc([(cx - r) * N, (cy - r) * N, (cx + r) * N, (cy + r) * N], start, end, fill=255,
                                width=max(1, int(width * N)))
        return self._done(img, blur)

    @staticmethod
    def _done(img, blur):
        if blur:
            img = img.filter(ImageFilter.GaussianBlur(blur * N))
        return np.asarray(img, float) / 255

    # --- fields ---------------------------------------------------------------------------------

    def radial(self, cx, cy, r, inner, outer, power=1.0):
        """A colour field from `inner` at (cx, cy) to `outer` at `r` and beyond."""
        t = np.clip(np.hypot(self.x - cx, self.y - cy) / r, 0, 1) ** power
        return inner * (1 - t)[..., None] + outer * t[..., None]

    def linear(self, x0, y0, x1, y1, start, end):
        dx, dy = x1 - x0, y1 - y0
        t = np.clip(((self.x - x0) * dx + (self.y - y0) * dy) / (dx * dx + dy * dy), 0, 1)
        return start * (1 - t)[..., None] + end * t[..., None]

    # --- light ----------------------------------------------------------------------------------

    def glow(self, cx, cy, r, colour, strength=1.0, ry=None):
        """A soft round of light, falling off as a Gaussian."""
        ry = r if ry is None else ry
        d2 = ((self.x - cx) / r) ** 2 + ((self.y - cy) / ry) ** 2
        self.add(colour, strength * np.exp(-d2 * 2.2))

    def flare(self, cx, cy, size, light, rays=4, turn=0.0, strength=1.0):
        """A lens flare: a white-hot core, its glow, and thin rays of light crossing it."""
        deep, main, bright, core = light
        self.glow(cx, cy, size * 0.55, main, 0.75 * strength)
        for k in range(rays):
            a = turn + math.pi * k / rays
            long = size * (1.0 if k % 2 == 0 else 0.6)
            dx, dy = math.cos(a), math.sin(a)
            # A ray: a thin diamond, blurred a touch, brightest at the middle.
            w = size * 0.05
            pts = [(cx - dx * long, cy - dy * long), (cx - dy * w, cy + dx * w), (cx + dx * long, cy + dy * long),
                   (cx + dy * w, cy - dx * w)]
            self.add(bright, self.poly(pts, blur=0.004) * strength)
        self.glow(cx, cy, size * 0.2, core, 1.0 * strength)

    def sparkle(self, cx, cy, size, light, strength=1.0):
        """A small four-pointed star of light."""
        deep, main, bright, core = light
        self.glow(cx, cy, size * 0.8, main, 0.5 * strength)
        w = size * 0.18
        star = [(cx, cy - size), (cx + w, cy - w), (cx + size, cy), (cx + w, cy + w), (cx, cy + size),
                (cx - w, cy + w), (cx - size, cy), (cx - w, cy - w)]
        self.add(core, self.poly(star, blur=0.002) * strength)

    def body(self, mask, light, cx, cy, r, rim=True, shadow=True):
        """A solid made of light: deep at its rim, bright toward (cx, cy), its core white, a glow round it
        and (`shadow`) a soft dark under it so it stands off the backdrop."""
        deep, main, bright, core = light
        if shadow:
            self.over(np.zeros(3), self._soft(mask, 0.02) * 0.45)
        self.glow(cx, cy, r * 1.5, main, 0.55)
        field = self.radial(cx, cy, r, core, deep, power=0.8)
        field = self.radial(cx, cy, r * 0.55, core, bright, power=1.2) * (np.hypot(self.x - cx, self.y - cy) < r * 0.55)[..., None] + \
            field * (np.hypot(self.x - cx, self.y - cy) >= r * 0.55)[..., None]
        self.over(field, mask)
        if rim:
            self.add(bright, np.clip(mask - Icon._erode(mask), 0, 1) * 0.5)

    @staticmethod
    def _soft(mask, blur):
        img = Image.fromarray((np.clip(mask, 0, 1) * 255).astype(np.uint8))
        return np.asarray(img.filter(ImageFilter.GaussianBlur(blur * N)), float) / 255

    @staticmethod
    def _erode(mask, px=6):
        img = Image.fromarray((np.clip(mask, 0, 1) * 255).astype(np.uint8))
        return np.asarray(img.filter(ImageFilter.MinFilter(px * 2 + 1)), float) / 255

    def trail(self, points, width, light, strength=1.0):
        """Light streaming behind something along `points` (oldest first): thin and faint at its end,
        full where it meets the thing."""
        deep, main, bright, core = light
        n = len(points) - 1
        for k in range(n):
            t = (k + 1) / n
            seg = self.line(points[k:k + 2], width * (0.25 + 0.75 * t), blur=0.01)
            self.add(main, seg * strength * (0.25 + 0.75 * t) * 0.8)
            self.add(bright, self.line(points[k:k + 2], width * 0.35 * (0.25 + 0.75 * t), blur=0.004) * strength * t)

    def finish(self):
        """The picture at 128 pixels, its corners rounded like the tile it sits in."""
        corner = self._canvas()
        ImageDraw.Draw(corner).rounded_rectangle([0, 0, N - 1, N - 1], radius=int(N * 0.2), fill=255)
        cut = np.asarray(corner, float) / 255
        a = self.a * cut
        rgba = np.dstack([np.clip(self.rgb, 0, 1) * cut[..., None], a])       # premultiplied
        img = Image.fromarray((rgba * 255).round().astype(np.uint8), "RGBa")
        return img.resize((OUT, OUT), Image.LANCZOS).convert("RGBA")


# ------------------------------------------------------------------------------------- the skills
# Each draws on an Icon, from its battle animation: what flies, what bursts, what rises, in its colours.

def bolt(ic, light, angle=-0.6, r=0.17, cx=0.6, cy=0.42, tail=0.42):
    """A ball of light flying up and right, its trail behind it (fire bolt, jelly splash, mud shot)."""
    dx, dy = math.cos(angle), math.sin(angle)
    pts = [(cx - dx * tail * (1 - k / 6), cy - dy * tail * (1 - k / 6)) for k in range(7)]
    ic.trail(pts, r * 1.3, light)
    ic.body(ic.ellipse(cx, cy, r), light, cx - r * 0.25, cy - r * 0.25, r)


def flames(ic, light, cx, cy, h, w, lean=0.0):
    """A tongue of fire: three flames in one, deep to white-hot."""
    deep, main, bright, core = light
    for scale, colour, alpha in ((1.0, deep, 0.95), (0.74, main, 1.0), (0.48, bright, 1.0), (0.26, core, 1.0)):
        hh, ww = h * scale, w * scale
        base = cy
        pts = [(cx + lean * hh, base - hh), (cx + ww * 0.55, base - hh * 0.45), (cx + ww * 0.5, base - hh * 0.05),
               (cx + ww * 0.25, base + ww * 0.3), (cx - ww * 0.25, base + ww * 0.3), (cx - ww * 0.5, base - hh * 0.05),
               (cx - ww * 0.45, base - hh * 0.5)]
        ic.over(colour, ic.poly(pts, blur=0.006) * alpha)


def draw_fire_bolt(ic):
    L = LIGHTS["fire"]
    dx, dy = math.cos(-0.65), math.sin(-0.65)
    pts = [(0.62 - dx * 0.5 * (1 - k / 7), 0.4 - dy * 0.5 * (1 - k / 7)) for k in range(8)]
    ic.trail(pts, 0.24, L)
    for k, (ox, oy, s) in enumerate(((-0.2, 0.26, 0.04), (-0.08, 0.3, 0.03), (-0.28, 0.14, 0.025))):
        ic.sparkle(0.62 + ox, 0.4 + oy, s * 1.6, L, 0.8)
    ic.glow(0.62, 0.4, 0.3, L[1], 0.6)
    ic.body(ic.ellipse(0.62, 0.4, 0.16), L, 0.58, 0.36, 0.16)
    flames(ic, L, 0.63, 0.47, 0.32, 0.26, lean=0.18)
    ic.flare(0.6, 0.38, 0.22, L, strength=0.7)


def draw_ember(ic):
    L = LIGHTS["fire"]
    ic.glow(0.5, 0.78, 0.4, L[0], 0.5, ry=0.15)
    flames(ic, L, 0.5, 0.8, 0.5, 0.36)
    for (x, y, s) in ((0.26, 0.42, 0.05), (0.74, 0.34, 0.06), (0.36, 0.2, 0.04), (0.66, 0.6, 0.035), (0.2, 0.66, 0.03),
                      (0.82, 0.56, 0.04)):
        ic.glow(x, y, s * 1.6, L[1], 0.7)
        ic.over(L[2], ic.ellipse(x, y, s * 0.5, blur=0.003))
        ic.add(L[3], ic.ellipse(x, y, s * 0.25))


def draw_flash(ic):
    L = LIGHTS["light"]
    ic.glow(0.5, 0.5, 0.42, L[0], 0.6)
    ic.flare(0.5, 0.5, 0.46, L, rays=8, turn=0.0, strength=1.0)
    ic.flare(0.5, 0.5, 0.3, L, rays=4, turn=math.pi / 4, strength=0.6)
    ic.over(L[3], ic.ellipse(0.5, 0.5, 0.08, blur=0.01))


def draw_holy_glow(ic):
    L = LIGHTS["light"]
    ic.glow(0.5, 0.86, 0.45, L[0], 0.6, ry=0.12)
    for a in np.linspace(-2.6, -0.54, 7):                   # rays fanning up round the hero
        ic.add(L[1], ic.poly([(0.5, 0.9), (0.5 + math.cos(a - 0.08) * 0.7, 0.9 + math.sin(a - 0.08) * 0.7),
                              (0.5 + math.cos(a + 0.08) * 0.7, 0.9 + math.sin(a + 0.08) * 0.7)], blur=0.03) * 0.35)
    ic.body(ic.ellipse(0.5, 0.42, 0.13), L, 0.5, 0.4, 0.13, shadow=False)
    ic.flare(0.5, 0.42, 0.34, L, rays=8, strength=0.9)
    for (x, y) in ((0.24, 0.3), (0.78, 0.24), (0.7, 0.66)):
        ic.sparkle(x, y, 0.05, L)


def draw_frost_breath(ic):
    L = LIGHTS["water"]
    # A cone of frost from the lower left, crystals of ice in it.
    ic.add(L[1], ic.poly([(0.08, 0.86), (0.92, 0.22), (0.94, 0.62)], blur=0.05) * 0.6)
    ic.add(L[2], ic.poly([(0.1, 0.84), (0.9, 0.34), (0.9, 0.52)], blur=0.03) * 0.7)
    for (x, y, s, a) in ((0.7, 0.4, 0.13, 0.2), (0.48, 0.58, 0.1, -0.3), (0.82, 0.58, 0.08, 0.6), (0.3, 0.7, 0.06, 0.1)):
        for k in range(3):
            t = a + k * math.pi / 3
            dx, dy = math.cos(t) * s, math.sin(t) * s
            ic.over(L[3], ic.line([(x - dx, y - dy), (x + dx, y + dy)], 0.018, blur=0.002))
        ic.glow(x, y, s * 0.8, L[2], 0.5)
    for (x, y) in ((0.6, 0.24), (0.9, 0.82), (0.38, 0.42)):
        ic.sparkle(x, y, 0.04, L)


def draw_jelly_splash(ic):
    L = LIGHTS["water"]
    ic.glow(0.5, 0.62, 0.38, L[0], 0.5)
    drop = [(0.5, 0.12)] + [(0.5 + 0.24 * math.sin(t), 0.56 - 0.24 * math.cos(t)) for t in np.linspace(0.5, 2 * math.pi - 0.5, 24)]
    ic.body(ic.poly(drop, blur=0.003), L, 0.44, 0.5, 0.26)
    ic.over(L[3], ic.ellipse(0.42, 0.46, 0.05, 0.08, blur=0.006) * 0.9)
    for (x, y, r) in ((0.16, 0.72, 0.05), (0.84, 0.66, 0.06), (0.24, 0.3, 0.035), (0.8, 0.3, 0.04), (0.5, 0.92, 0.03)):
        ic.body(ic.ellipse(x, y, r), L, x - r * 0.3, y - r * 0.3, r, shadow=False)


def draw_bubble(ic):
    L = LIGHTS["water"]
    for (x, y, r) in ((0.42, 0.56, 0.24), (0.74, 0.3, 0.13), (0.78, 0.7, 0.09), (0.24, 0.24, 0.08)):
        ic.glow(x, y, r * 1.3, L[1], 0.35)
        ic.over(L[0], ic.ellipse(x, y, r) * 0.25)
        ic.add(L[2], ic.ring(x, y, r, r * 0.16, blur=0.004) * 0.9)
        ic.over(L[3], ic.arc(x, y, r * 0.72, 200, 250, r * 0.14, blur=0.003))
        ic.over(L[3], ic.ellipse(x - r * 0.38, y - r * 0.4, r * 0.12))


def draw_leaf_storm(ic):
    L = LIGHTS["wood"]
    ic.add(L[1], ic.arc(0.5, 0.5, 0.36, 200, 520, 0.03, blur=0.015) * 0.7)
    ic.add(L[2], ic.arc(0.5, 0.5, 0.22, 20, 300, 0.025, blur=0.012) * 0.6)
    for k, (x, y, a, s) in enumerate(((0.3, 0.3, -0.6, 0.11), (0.72, 0.28, 0.5, 0.1), (0.78, 0.66, 2.0, 0.12),
                                      (0.32, 0.72, 2.6, 0.1), (0.52, 0.5, 0.9, 0.14))):
        dx, dy = math.cos(a) * s, math.sin(a) * s
        nx, ny = -dy * 0.45, dx * 0.45
        pts = [(x - dx, y - dy), (x + nx, y + ny), (x + dx, y + dy), (x - nx, y - ny)]
        ic.glow(x, y, s * 1.1, L[1], 0.4)
        ic.body(ic.poly(pts, blur=0.002), L, x - nx * 0.4, y - ny * 0.4, s, shadow=True)
        ic.over(L[0], ic.line([(x - dx, y - dy), (x + dx, y + dy)], 0.008))
    ic.sparkle(0.84, 0.44, 0.04, L)
    ic.sparkle(0.18, 0.5, 0.035, L)


def draw_vine_whip(ic):
    L = LIGHTS["wood"]
    pts = [(0.14 + 0.72 * t, 0.84 - 0.66 * t + 0.16 * math.sin(t * 7)) for t in np.linspace(0, 1, 30)]
    ic.add(L[1], ic.line(pts, 0.1, blur=0.03) * 0.6)
    ic.over(L[0], ic.line(pts, 0.06))
    ic.over(L[1], ic.line(pts, 0.035))
    ic.add(L[2], ic.line(pts, 0.012) * 0.8)
    for k in (6, 13, 20, 26):
        x, y = pts[k]
        ic.over(L[1], ic.poly([(x, y), (x + 0.08, y - 0.06), (x + 0.12, y + 0.01)], blur=0.003))
    ic.flare(0.86, 0.2, 0.16, L, strength=0.8)


def draw_pine_needles(ic):
    L = LIGHTS["wood"]
    a = -0.7
    dx, dy = math.cos(a), math.sin(a)
    for (x, y) in ((0.36, 0.74), (0.56, 0.7), (0.72, 0.52), (0.44, 0.52), (0.62, 0.32), (0.3, 0.38)):
        ic.trail([(x - dx * 0.26, y - dy * 0.26), (x - dx * 0.13, y - dy * 0.13), (x, y)], 0.07, L, 0.6)
        needle = [(x - dx * 0.02 - dy * 0.03, y - dy * 0.02 + dx * 0.03), (x + dx * 0.2, y + dy * 0.2),
                  (x - dx * 0.02 + dy * 0.03, y - dy * 0.02 - dx * 0.03)]
        ic.over(np.zeros(3), ic.poly(needle, blur=0.01) * 0.4)
        ic.over(ic.linear(x, y, x + dx * 0.2, y + dy * 0.2, L[0], L[2]), ic.poly(needle, blur=0.002))
        ic.add(L[3], ic.line([(x + dx * 0.05, y + dy * 0.05), (x + dx * 0.17, y + dy * 0.17)], 0.008, blur=0.002) * 0.8)
    ic.sparkle(0.86, 0.18, 0.05, L)


def draw_stone_spike(ic):
    L = LIGHTS["earth"]
    ic.glow(0.5, 0.84, 0.44, L[1], 0.5, ry=0.12)
    for (x, h, w) in ((0.3, 0.42, 0.13), (0.7, 0.36, 0.12), (0.5, 0.66, 0.17)):
        pts = [(x - w, 0.86), (x - w * 0.15, 0.86 - h), (x + w * 0.2, 0.86 - h * 0.92), (x + w, 0.86)]
        ic.over(np.zeros(3), ic.poly(pts, blur=0.02) * 0.4)
        ic.over(ic.linear(x - w, 0.86 - h, x + w, 0.86, L[2], L[0]), ic.poly(pts, blur=0.002))
        ic.add(L[3], ic.line([(x - w * 0.15, 0.86 - h), (x - w * 0.6, 0.86)], 0.012, blur=0.003) * 0.7)
    for (x, y, s) in ((0.2, 0.5, 0.025), (0.84, 0.44, 0.03), (0.62, 0.18, 0.02)):
        ic.over(L[1], ic.ellipse(x, y, s, blur=0.003))
    ic.flare(0.5, 0.2, 0.18, L, strength=0.7)


def draw_mud_shot(ic):
    L = LIGHTS["earth"]
    bolt(ic, L, r=0.16)
    for (x, y, r) in ((0.3, 0.74, 0.04), (0.2, 0.62, 0.03), (0.4, 0.86, 0.025)):
        ic.over(L[0], ic.ellipse(x, y, r, blur=0.004))


def draw_rock_throw(ic):
    L = LIGHTS["earth"]
    dx, dy = math.cos(-0.5), math.sin(-0.5)
    ic.trail([(0.6 - dx * 0.46 * (1 - k / 5), 0.44 - dy * 0.46 * (1 - k / 5)) for k in range(6)], 0.22, L, 0.6)
    rock = [(0.44, 0.34), (0.6, 0.24), (0.76, 0.3), (0.82, 0.48), (0.7, 0.62), (0.5, 0.62), (0.4, 0.5)]
    ic.over(np.zeros(3), ic.poly(rock, blur=0.025) * 0.45)
    ic.over(ic.linear(0.44, 0.26, 0.78, 0.62, L[2], L[0] * 0.7), ic.poly(rock, blur=0.002))
    ic.over(L[0] * 0.6, ic.line([(0.56, 0.38), (0.66, 0.46), (0.62, 0.56)], 0.012))
    ic.add(L[3], ic.line([(0.46, 0.34), (0.6, 0.26)], 0.014, blur=0.004) * 0.7)
    ic.flare(0.84, 0.62, 0.16, L, strength=0.6)


def jaws(ic, gum, tooth, gap_light, open_=0.1):
    """A bite seen from the front: an upper jaw curving down at its ends and a lower one up, each a band
    of `gum` with fangs (long ones at the corners, small between) pointing in, staggered so they'd
    close between each other, and light in the gap where they snap."""
    ic.add(gap_light[1], ic.ellipse(0.5, 0.5, 0.4, 0.08, blur=0.04) * 0.8)
    ic.add(gap_light[3], ic.ellipse(0.5, 0.5, 0.3, 0.015, blur=0.01) * 0.8)
    for side in (-1, 1):                                   # -1 the upper jaw, 1 the lower
        def edge(x, inset=0.0):
            return 0.5 + side * (open_ + 0.28 - 0.9 * (x - 0.5) ** 2 + inset)
        xs = np.linspace(0.12, 0.88, 24)
        band = [(x, edge(x)) for x in xs] + [(x, edge(x, 0.09)) for x in xs[::-1]]
        ic.over(np.zeros(3), ic.poly(band, blur=0.02) * 0.5)
        ic.over(ic.linear(0.5, edge(0.5, 0.09), 0.5, edge(0.5), gum * 1.25, gum * 0.7), ic.poly(band, blur=0.002))
        for k, x in enumerate(np.linspace(0.24, 0.76, 5) + (0.0 if side < 0 else 0.065)):
            if x > 0.82:
                continue
            long = 0.2 if k in (0, 4) or (side > 0 and k == 3) else 0.11
            w = 0.05 if long > 0.15 else 0.035
            base = edge(x)
            tip = base - side * long
            fang = [(x - w, base + side * 0.01), (x + w, base + side * 0.01), (x + 0.004, tip)]
            ic.over(np.zeros(3), ic.poly(fang, blur=0.01) * 0.35)
            ic.over(ic.linear(x, base, x, tip, tooth * 0.78, np.minimum(tooth * 1.12, 1)), ic.poly(fang, blur=0.002))
            ic.add(np.ones(3), ic.line([(x - w * 0.45, base), (x - w * 0.1, tip + side * 0.03)], 0.008, blur=0.002) * 0.5)


def draw_shadow_bite(ic):
    L = LIGHTS["dark"]
    ic.glow(0.5, 0.5, 0.42, L[0], 0.8)
    jaws(ic, rgb("#3a1a6a"), rgb("#e8dcff"), L)
    ic.sparkle(0.84, 0.16, 0.05, L)
    ic.sparkle(0.16, 0.84, 0.04, L)


def draw_nibble(ic):
    L = LIGHTS["blow"]
    ic.glow(0.5, 0.5, 0.4, L[0], 0.5)
    jaws(ic, rgb("#c04a5a"), rgb("#f4eee0"), L)
    ic.flare(0.5, 0.5, 0.26, L, strength=0.6)


def draw_venom_bite(ic):
    L = LIGHTS["poison"]
    ic.glow(0.5, 0.5, 0.42, L[0], 0.6)
    jaws(ic, rgb("#5a2a4a"), rgb("#f0f4e0"), L, open_=0.08)
    for (x, y) in ((0.24, 0.47), (0.76, 0.47)):              # venom dripping from the upper fangs
        drop = [(x, y - 0.03)] + [(x + 0.035 * math.sin(t), y + 0.035 - 0.035 * math.cos(t)) for t in np.linspace(0.6, 2 * math.pi - 0.6, 12)]
        ic.body(ic.poly(drop, blur=0.002), L, x - 0.01, y, 0.05, shadow=False)


def draw_poison(ic):
    L = LIGHTS["poison"]
    ic.glow(0.5, 0.56, 0.4, L[0], 0.6)
    drop = [(0.5, 0.1)] + [(0.5 + 0.25 * math.sin(t), 0.6 - 0.25 * math.cos(t)) for t in np.linspace(0.55, 2 * math.pi - 0.55, 24)]
    ic.body(ic.poly(drop, blur=0.003), L, 0.44, 0.54, 0.28)
    ic.over(rgb("#1c2a10"), ic.ellipse(0.42, 0.6, 0.035, 0.05))
    ic.over(rgb("#1c2a10"), ic.ellipse(0.58, 0.6, 0.035, 0.05))
    ic.over(rgb("#1c2a10"), ic.arc(0.5, 0.78, 0.07, 200, 340, 0.018))
    for (x, y, r) in ((0.84, 0.24, 0.05), (0.18, 0.3, 0.04), (0.88, 0.5, 0.03)):
        ic.add(L[2], ic.ring(x, y, r, 0.012, blur=0.003))
        ic.glow(x, y, r, L[1], 0.4)


def draw_poison_mist(ic):
    L = LIGHTS["poison"]
    D = LIGHTS["dark"]
    for (x, y, r) in ((0.3, 0.6, 0.2), (0.52, 0.48, 0.24), (0.72, 0.6, 0.2), (0.5, 0.7, 0.2)):
        ic.add(D[1], ic.ellipse(x, y, r, blur=0.04) * 0.5)
        ic.add(L[1], ic.ellipse(x, y - 0.02, r * 0.8, blur=0.05) * 0.6)
    ic.add(L[2], ic.ellipse(0.46, 0.44, 0.12, blur=0.05) * 0.6)
    for (x, y, r) in ((0.2, 0.24, 0.04), (0.82, 0.22, 0.05), (0.64, 0.12, 0.03)):
        ic.add(D[2], ic.ring(x, y, r, 0.012, blur=0.003))


def draw_curse(ic):
    L = LIGHTS["dark"]
    ic.glow(0.5, 0.5, 0.42, L[0], 0.8)
    for k in range(3):
        ic.add(L[1], ic.arc(0.5, 0.5, 0.16 + k * 0.1, k * 70, k * 70 + 250, 0.025, blur=0.01) * (0.9 - k * 0.2))
    moon = np.clip(ic.ellipse(0.5, 0.5, 0.2) - ic.ellipse(0.6, 0.44, 0.17), 0, 1)
    ic.body(moon, L, 0.42, 0.46, 0.2)
    ic.sparkle(0.76, 0.26, 0.05, L)
    ic.sparkle(0.24, 0.76, 0.04, L)


def draw_evil_eye(ic):
    L = LIGHTS["dark"]
    ic.glow(0.5, 0.5, 0.45, L[0], 0.7)
    eye = [(0.08, 0.5), (0.3, 0.32), (0.5, 0.27), (0.7, 0.32), (0.92, 0.5), (0.7, 0.68), (0.5, 0.73), (0.3, 0.68)]
    ic.over(np.zeros(3), ic.poly(eye, blur=0.02) * 0.5)
    ic.over(rgb("#f0e8ff"), ic.poly(eye, blur=0.002))
    ic.over(ic.radial(0.5, 0.5, 0.18, L[2], L[0]), ic.ellipse(0.5, 0.5, 0.18))
    ic.over(rgb("#ff4a7a"), ic.ellipse(0.5, 0.5, 0.035, 0.13))
    ic.add(rgb("#ff9ab8"), ic.ellipse(0.5, 0.5, 0.06, 0.16, blur=0.02) * 0.6)
    ic.over(np.ones(3), ic.ellipse(0.44, 0.43, 0.03))
    for a in np.linspace(0, 2 * math.pi, 9)[:-1]:
        x, y = 0.5 + math.cos(a) * 0.44, 0.5 + math.sin(a) * 0.4
        ic.add(L[2], ic.line([(0.5 + math.cos(a) * 0.36, 0.5 + math.sin(a) * 0.32), (x, y)], 0.015, blur=0.006) * 0.7)


def draw_web_shot(ic):
    L = LIGHTS["white"]
    D = LIGHTS["dark"]
    ic.glow(0.5, 0.5, 0.42, D[0], 0.6)
    for a in np.linspace(0, 2 * math.pi, 9)[:-1]:
        ic.add(L[2], ic.line([(0.5, 0.5), (0.5 + math.cos(a) * 0.42, 0.5 + math.sin(a) * 0.42)], 0.012, blur=0.002))
    for r in (0.12, 0.22, 0.32, 0.4):
        pts = [(0.5 + math.cos(a) * r * (0.92 if k % 2 else 1), 0.5 + math.sin(a) * r * (0.92 if k % 2 else 1))
               for k, a in enumerate(np.linspace(0, 2 * math.pi, 17))]
        ic.add(L[1], ic.line(pts, 0.01, blur=0.002))
    ic.flare(0.5, 0.5, 0.16, D, strength=0.6)


def draw_whirlwind(ic):
    L = LIGHTS["white"]
    for k in range(6):
        y = 0.18 + k * 0.12
        r = 0.36 - k * 0.05
        ic.add(L[1], ic.arc(0.5 + k * 0.01, y, r, 20 + k * 30, 300 + k * 30, 0.03, blur=0.008) * 0.85)
        ic.add(L[3], ic.arc(0.5 + k * 0.01, y, r, 40 + k * 30, 140 + k * 30, 0.012, blur=0.003))
    ic.glow(0.5, 0.5, 0.36, LIGHTS["buff"][1], 0.35)
    for (x, y) in ((0.16, 0.3), (0.84, 0.46), (0.26, 0.84)):
        ic.sparkle(x, y, 0.035, L)


def draw_gust(ic):
    L = LIGHTS["white"]
    for k, (y, x0, x1) in enumerate(((0.3, 0.1, 0.78), (0.5, 0.18, 0.9), (0.7, 0.08, 0.7))):
        pts = [(x0 + (x1 - x0) * t, y + 0.04 * math.sin(t * 6 + k)) for t in np.linspace(0, 1, 20)]
        ic.add(LIGHTS["buff"][1], ic.line(pts, 0.06, blur=0.02) * 0.6)
        ic.add(L[3], ic.line(pts, 0.018, blur=0.003))
        ic.add(L[3], ic.arc(x1 - 0.04, y - 0.06, 0.07, 270, 450, 0.018, blur=0.003))
    ic.sparkle(0.88, 0.22, 0.04, L)


def draw_bash(ic):
    L = LIGHTS["blow"]
    ic.flare(0.5, 0.5, 0.44, L, rays=6, turn=0.2, strength=0.9)
    star = [(0.5 + math.cos(a) * (0.36 if k % 2 == 0 else 0.16), 0.5 + math.sin(a) * (0.36 if k % 2 == 0 else 0.16))
            for k, a in enumerate(np.linspace(-math.pi / 2, 1.5 * math.pi, 15)[:-1])]
    ic.body(ic.poly(star, blur=0.003), L, 0.5, 0.5, 0.3)
    for a in np.linspace(0.3, 2 * math.pi + 0.3, 7)[:-1]:
        ic.add(L[2], ic.line([(0.5 + math.cos(a) * 0.38, 0.5 + math.sin(a) * 0.38),
                              (0.5 + math.cos(a) * 0.47, 0.5 + math.sin(a) * 0.47)], 0.02, blur=0.004))


def draw_power_strike(ic):
    L = LIGHTS["blow"]
    ic.add(L[1], ic.arc(0.1, 0.92, 0.82, 290, 360, 0.09, blur=0.03) * 0.7)
    ic.add(L[2], ic.arc(0.1, 0.92, 0.82, 292, 358, 0.04, blur=0.008))
    ic.add(L[3], ic.arc(0.1, 0.92, 0.82, 300, 352, 0.014, blur=0.002))
    ic.flare(0.62, 0.34, 0.3, L, strength=0.9)


def draw_golden_spin(ic):
    L = LIGHTS["metal"]
    ic.glow(0.5, 0.5, 0.42, L[0], 0.5)
    for k in range(3):
        ic.add(L[1], ic.arc(0.5, 0.5, 0.34 - k * 0.04, k * 120, k * 120 + 200, 0.04, blur=0.012) * 0.8)
        ic.add(L[3], ic.arc(0.5, 0.5, 0.34 - k * 0.04, k * 120 + 120, k * 120 + 200, 0.012, blur=0.002))
    ic.body(ic.ellipse(0.5, 0.5, 0.15), L, 0.45, 0.45, 0.15)
    ic.over(L[0], ic.ring(0.5, 0.5, 0.1, 0.014))
    for (x, y) in ((0.16, 0.22), (0.86, 0.3), (0.8, 0.82), (0.2, 0.78)):
        ic.sparkle(x, y, 0.05, L)


def draw_bounce(ic):
    L = LIGHTS["water"]
    pts = [(0.1 + 0.8 * t, 0.84 - 0.6 * abs(math.sin(t * math.pi * 1.5))) for t in np.linspace(0, 0.66, 30)]
    ic.trail(pts, 0.08, LIGHTS["white"], 0.7)
    ic.body(ic.ellipse(0.66, 0.3, 0.14, 0.12), L, 0.62, 0.26, 0.14)
    ic.glow(0.4, 0.86, 0.14, LIGHTS["white"][2], 0.6, ry=0.04)
    ic.add(LIGHTS["white"][3], ic.arc(0.4, 0.86, 0.12, 190, 350, 0.012, blur=0.003))


def draw_roar(ic):
    L = LIGHTS["blow"]
    for k in range(4):
        r = 0.14 + k * 0.1
        ic.add(L[1], ic.arc(0.24, 0.5, r, -50, 50, 0.035, blur=0.01) * (1 - k * 0.18))
        ic.add(L[3], ic.arc(0.24, 0.5, r, -40, 40, 0.012, blur=0.002) * (1 - k * 0.2))
    ic.flare(0.24, 0.5, 0.2, L, strength=0.8)


def draw_wild_call(ic):
    L = LIGHTS["wood"]
    ic.glow(0.5, 0.56, 0.38, L[0], 0.6)
    ic.body(ic.ellipse(0.5, 0.64, 0.16, 0.13), L, 0.46, 0.6, 0.16)
    for (x, y, r) in ((0.3, 0.42, 0.065), (0.43, 0.32, 0.07), (0.57, 0.32, 0.07), (0.7, 0.42, 0.065)):
        ic.body(ic.ellipse(x, y, r, r * 1.15), L, x - r * 0.3, y - r * 0.3, r)
    for k in range(2):
        ic.add(L[2], ic.arc(0.5, 0.5, 0.36 + k * 0.08, 200, 340, 0.016, blur=0.005) * (0.8 - k * 0.3))


def paw(ic, light, cx=0.5, cy=0.5, s=1.0):
    ic.body(ic.ellipse(cx, cy + 0.12 * s, 0.15 * s, 0.12 * s), light, cx - 0.03, cy + 0.08 * s, 0.15 * s)
    for (x, y, r) in ((-0.19, -0.04, 0.06), (-0.07, -0.15, 0.065), (0.07, -0.15, 0.065), (0.19, -0.04, 0.06)):
        ic.body(ic.ellipse(cx + x * s, cy + y * s, r * s, r * 1.15 * s), light, cx + x * s - 0.02, cy + y * s - 0.02, r * s)


def heart_shape(ic, cx, cy, r):
    pts = []
    for t in np.linspace(0, 2 * math.pi, 60):
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((cx + x / 17 * r, cy - y / 17 * r))
    return ic.poly(pts, blur=0.002)


def plus(ic, cx, cy, s, w):
    return np.clip(ic.poly([(cx - w, cy - s), (cx + w, cy - s), (cx + w, cy + s), (cx - w, cy + s)]) +
                   ic.poly([(cx - s, cy - w), (cx + s, cy - w), (cx + s, cy + w), (cx - s, cy + w)]), 0, 1)


def rising_motes(ic, light, spots):
    for (x, y, s) in spots:
        ic.add(light[1], ic.line([(x, y + s * 4), (x, y)], s * 0.9, blur=0.01) * 0.5)
        ic.sparkle(x, y, s, light, 0.9)


def draw_first_aid(ic):
    L = LIGHTS["heal"]
    ic.glow(0.5, 0.5, 0.4, L[0], 0.5)
    ic.body(plus(ic, 0.5, 0.5, 0.28, 0.1), L, 0.44, 0.44, 0.3)
    rising_motes(ic, L, ((0.18, 0.3, 0.04), (0.82, 0.24, 0.045), (0.8, 0.74, 0.035)))


def draw_recovery(ic):
    L = LIGHTS["heal"]
    ic.glow(0.5, 0.52, 0.4, L[0], 0.5)
    ic.body(heart_shape(ic, 0.46, 0.52, 0.3), rgb_light("#e0405a", "#ff7a8a", "#ffc0c8", "#fff0f2"), 0.4, 0.44, 0.3)
    ic.body(plus(ic, 0.76, 0.28, 0.1, 0.035), L, 0.74, 0.26, 0.1, shadow=True)
    rising_motes(ic, L, ((0.18, 0.24, 0.035), (0.84, 0.66, 0.04)))


def draw_mend_beast(ic):
    L = LIGHTS["heal"]
    ic.glow(0.5, 0.5, 0.42, L[0], 0.5)
    paw(ic, L, 0.46, 0.54, 1.1)
    ic.body(plus(ic, 0.8, 0.24, 0.09, 0.03), L, 0.78, 0.22, 0.09)
    rising_motes(ic, L, ((0.16, 0.24, 0.035), (0.84, 0.7, 0.035)))


def draw_blessing(ic):
    L = LIGHTS["heal"]
    S = LIGHTS["light"]
    ic.glow(0.5, 0.22, 0.4, S[1], 0.6, ry=0.2)
    ic.flare(0.5, 0.18, 0.22, S, rays=8, strength=0.8)
    for (x, y) in ((0.24, 0.48), (0.4, 0.62), (0.58, 0.52), (0.74, 0.66), (0.32, 0.82), (0.62, 0.84), (0.84, 0.44)):
        drop = [(x, y - 0.06)] + [(x + 0.03 * math.sin(t), y - 0.03 * math.cos(t)) for t in np.linspace(0.6, 2 * math.pi - 0.6, 10)]
        ic.add(L[1], ic.line([(x, y - 0.16), (x, y - 0.04)], 0.015, blur=0.006) * 0.6)
        ic.body(ic.poly(drop, blur=0.002), L, x - 0.008, y - 0.02, 0.04, shadow=False)


def draw_revive(ic):
    L = LIGHTS["light"]
    H = LIGHTS["heal"]
    ic.glow(0.5, 0.6, 0.4, H[0], 0.5)
    ic.add(L[1], ic.poly([(0.36, 0.95), (0.64, 0.95), (0.58, 0.05), (0.42, 0.05)], blur=0.04) * 0.6)
    ic.add(L[2], ic.poly([(0.45, 0.95), (0.55, 0.95), (0.52, 0.05), (0.48, 0.05)], blur=0.02) * 0.7)
    feather = [(0.5, 0.2), (0.62, 0.36), (0.6, 0.62), (0.5, 0.78), (0.42, 0.6), (0.4, 0.36)]
    ic.body(ic.poly(feather, blur=0.003), L, 0.48, 0.38, 0.3)
    ic.over(L[0], ic.line([(0.5, 0.24), (0.5, 0.86)], 0.012))
    rising_motes(ic, L, ((0.22, 0.4, 0.04), (0.78, 0.3, 0.045), (0.74, 0.74, 0.035), (0.26, 0.76, 0.03)))


def shield(ic, light, cx=0.5, cy=0.5, s=1.0):
    pts = [(cx - 0.26 * s, cy - 0.28 * s), (cx, cy - 0.34 * s), (cx + 0.26 * s, cy - 0.28 * s), (cx + 0.24 * s, cy + 0.06 * s),
           (cx, cy + 0.34 * s), (cx - 0.24 * s, cy + 0.06 * s)]
    mask = ic.poly(pts, blur=0.002)
    ic.body(mask, light, cx - 0.08 * s, cy - 0.12 * s, 0.34 * s)
    ic.add(light[3], (mask - Icon._erode(mask, 14)).clip(0, 1) * 0.6)
    return mask


def draw_protection(ic):
    L = LIGHTS["buff"]
    ic.add(L[1], ic.ring(0.5, 0.5, 0.42, 0.03, blur=0.015) * 0.7)
    shield(ic, L)
    ic.flare(0.36, 0.3, 0.16, L, strength=0.7)


def draw_bless(ic):
    L = LIGHTS["buff"]
    S = LIGHTS["light"]
    ic.glow(0.5, 0.5, 0.42, L[0], 0.5)
    shield(ic, L, 0.46, 0.54, 0.9)
    ic.body(plus(ic, 0.46, 0.52, 0.12, 0.04), S, 0.45, 0.5, 0.12, shadow=False)
    ic.flare(0.78, 0.22, 0.18, S, strength=0.8)


def draw_guardianship(ic):
    L = LIGHTS["buff"]
    S = LIGHTS["light"]
    for k in range(3):
        ic.add(L[1], ic.ring(0.5, 0.5, 0.3 + k * 0.07, 0.02, blur=0.008) * (0.8 - k * 0.2))
    shield(ic, L, 0.5, 0.5, 0.85)
    star = [(0.5 + math.cos(a) * (0.13 if k % 2 == 0 else 0.055), 0.47 + math.sin(a) * (0.13 if k % 2 == 0 else 0.055))
            for k, a in enumerate(np.linspace(-math.pi / 2, 1.5 * math.pi, 11)[:-1])]
    ic.body(ic.poly(star, blur=0.002), S, 0.5, 0.46, 0.13, shadow=False)


def draw_boost(ic):
    L = LIGHTS["blow"]
    ic.glow(0.5, 0.5, 0.42, L[0], 0.5)
    arrow = [(0.5, 0.12), (0.8, 0.46), (0.62, 0.46), (0.62, 0.86), (0.38, 0.86), (0.38, 0.46), (0.2, 0.46)]
    ic.body(ic.poly(arrow, blur=0.003), L, 0.46, 0.36, 0.42)
    for x in (0.2, 0.8):
        ic.add(L[2], ic.line([(x, 0.9), (x, 0.62)], 0.02, blur=0.008) * 0.7)
    ic.sparkle(0.5, 0.14, 0.06, L)


def draw_berserk(ic):
    L = LIGHTS["fire"]
    R = rgb_light("#a01020", "#e0303a", "#ff8070", "#ffe0d0")
    ic.glow(0.5, 0.6, 0.44, R[0], 0.7)
    flames(ic, R, 0.3, 0.86, 0.5, 0.3, lean=-0.1)
    flames(ic, R, 0.7, 0.86, 0.5, 0.3, lean=0.1)
    flames(ic, L, 0.5, 0.88, 0.7, 0.4)
    ic.flare(0.5, 0.5, 0.24, L, strength=0.5)


def draw_animal_training(ic):
    L = LIGHTS["light"]
    ic.glow(0.5, 0.5, 0.4, LIGHTS["earth"][0], 0.6)
    paw(ic, LIGHTS["earth"], 0.46, 0.56, 1.05)
    ic.flare(0.78, 0.24, 0.2, L, strength=0.9)
    ic.sparkle(0.2, 0.24, 0.04, L)


def draw_bridge_of_light(ic):
    L = LIGHTS["light"]
    ic.add(L[0], ic.arc(0.5, 0.92, 0.42, 180, 360, 0.12, blur=0.03) * 0.5)
    for k, colour in enumerate((rgb("#ff8aa8"), L[1], rgb("#8ae0a0"), rgb("#8ac4ff"))):
        ic.add(colour, ic.arc(0.5, 0.92, 0.42 - k * 0.04, 180, 360, 0.04, blur=0.006) * 0.9)
    ic.add(L[3], ic.arc(0.5, 0.92, 0.4, 190, 350, 0.012, blur=0.002))
    for (x, y) in ((0.12, 0.84), (0.88, 0.84), (0.5, 0.42)):
        ic.sparkle(x, y, 0.05, L)


def rgb_light(*hexes):
    return [rgb(h) for h in hexes]


SKILLS = {name[5:]: fn for name, fn in dict(globals()).items() if name.startswith("draw_")}


def skill_defs():
    import json
    return {s["id"]: s for s in json.loads((ROOT / "content" / "skills.json").read_text())["skills"]}


def tile_of(skill):
    return rgb(TILES[skill.get("element") or skill["kind"]] if (skill.get("element") or skill["kind"]) in TILES else "#8c6be6")


def render(skill_id):
    ic = Icon(tile_of(skill_defs()[skill_id]))
    SKILLS[skill_id](ic)
    return ic.finish()


def main(argv):
    sheet_path = None
    if "--sheet" in argv:
        index = argv.index("--sheet")
        sheet_path = argv[index + 1]
        argv = argv[:index] + argv[index + 2:]
    defs = skill_defs()
    ids = argv or sorted(s for s in defs if s in SKILLS)
    missing = [s for s in defs if s not in SKILLS]
    if missing:
        print("no drawing for: " + ", ".join(missing))
    out = {}
    for skill_id in ids:
        img = render(skill_id)
        img.save(SPRITES / f"skill_{skill_id}.png")
        out[skill_id] = img
    print(f"wrote {len(ids)} skill icons to art/sprites/")
    if sheet_path:
        cols, cell, pad = 7, 96, 10
        rows = math.ceil(len(out) / cols)
        sheet = Image.new("RGBA", (cols * (cell + pad) + pad, rows * (cell + pad) + pad), (40, 36, 60, 255))
        for n, (skill_id, img) in enumerate(out.items()):
            x, y = pad + (n % cols) * (cell + pad), pad + (n // cols) * (cell + pad)
            tile = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
            ImageDraw.Draw(tile).rounded_rectangle([0, 0, cell - 1, cell - 1], radius=int(cell * 0.26),
                                                   fill=tuple(int(c * 255) for c in tile_of(defs[skill_id])) + (255,))
            inner = int(cell * 0.84)
            tile.alpha_composite(img.resize((inner, inner), Image.LANCZOS), ((cell - inner) // 2, (cell - inner) // 2))
            sheet.alpha_composite(tile, (x, y))
        sheet.save(sheet_path)
        print(f"contact sheet: {sheet_path}")


if __name__ == "__main__":
    main(sys.argv[1:])
