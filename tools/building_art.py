#!/usr/bin/env python3
"""Town houses and shops drawn in code with tools/pixel_kit.py, so the towns have more than the few
Retro Diffusion buildings (and their recolours) to build with. Each is a 96 × 96 sprite seen as RD's are,
from the front and a little above and to the right: a front wall, the right side wall going back, the
roof over both, and the things that make it a home or a shop (a door, lit windows, a chimney, a sign,
an awning, flower boxes) on a stone footing.

Walls and roofs are surfaces with a building material's own pattern at the sprite's pixels (stone
blocks, plaster, planks, timber framing, clay tiles, thatch, slate), lit flat from the top left and a
step darker on the side going back. Each drawing writes art/sprites/<id>.png; art/assets.json lists
them (kind `building`) and maps.json's town `lots` place them. Scored against RD's buildings:
`python3 tools/pixel_style.py check --kind building art/sprites/<id>.png`. `--sheet out.png` previews
them beside RD's `house` and `item_shop`; `ids...` redraws only those. Needs pillow + numpy;
docs/pixel-style.md has the rules.
"""

import math
import pathlib
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from pixel_kit import SS, Material, Sprite  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPRITES = ROOT / "art" / "sprites"

SIZE = 96
GROUND = 86                      # the front wall's foot (RD's buildings stand on rows 75 to 87)
DX, DY = 12, -7                  # a wall's depth going back, as the view shows it: up and to the right
LIGHT = np.array([-0.45, -0.55, 0.7]) / np.linalg.norm([-0.45, -0.55, 0.7])


# --------------------------------------------------------------------------------- materials' patterns
# Each: light and shade (about −0.5 … 0.4) at the sprite's own pixels, given the region's 1× mask and
# its bounds, so blocks, planks and tiles land crisp.

def _bounds(region):
    ys, xs = np.nonzero(region)
    return ys.min(), xs.min(), ys.max(), xs.max()


def blocks(region, w=6, h=4, seed=1):
    """Stone or brick in courses: dark mortar lines, each block lit along its top, a few flecks."""
    top, left, _, _ = _bounds(region)
    ys, xs = np.mgrid[0:region.shape[0], 0:region.shape[1]]
    row = (ys - top) // h
    off = (row % 2) * (w // 2) + (row * 7 % 3)
    joint = ((ys - top) % h == h - 1) | ((xs - left + off) % w == 0)
    lit = (ys - top) % h == 0
    rng = np.random.default_rng(seed)
    fleck = rng.random(region.shape) < 0.05
    shade = rng.random((region.shape[0] // h + 2, region.shape[1] // w + 2))[(ys - top) // h, (xs - left + off) // w]
    return np.where(joint, -0.5, np.where(lit, 0.22, 0.0)) + (shade - 0.5) * 0.18 + np.where(fleck & ~joint, 0.15, 0)


def plaster(region, seed=2):
    """Lime plaster: soft patches, a crack or two, never flat."""
    rng = np.random.default_rng(seed)
    coarse = rng.random((region.shape[0] // 3 + 2, region.shape[1] // 3 + 2))
    ys, xs = np.mgrid[0:region.shape[0], 0:region.shape[1]]
    return (coarse[ys // 3, xs // 3] - 0.5) * 0.16


def planks(region, h=3, seed=3, vertical=False):
    """Boards: a dark seam between each, grain along them, an end joint here and there."""
    top, left, _, _ = _bounds(region)
    ys, xs = np.mgrid[0:region.shape[0], 0:region.shape[1]]
    along, across = (ys - top, xs - left) if vertical else (xs - left, ys - top)
    board = across // h
    seam = across % h == h - 1
    rng = np.random.default_rng(seed)
    joints = rng.integers(5, 22, size=64)
    joint = (along + board * 7) % (joints[board % 64] + 9) == 0
    grain = (np.sin(along * 0.9 + board * 2.1) > 0.85) * -0.12
    tone = (rng.random(64)[board % 64] - 0.5) * 0.16
    return np.where(seam | joint, -0.45, grain + tone)


def tiles(region, w=5, h=4, seed=4):
    """Clay roof tiles in rows, each rounded: lit on its upper left, its foot in the shadow of the row
    below's overlap."""
    top, left, _, _ = _bounds(region)
    ys, xs = np.mgrid[0:region.shape[0], 0:region.shape[1]]
    row = (ys - top) // h
    xo = (xs - left + (row % 2) * (w // 2)) % w
    yo = (ys - top) % h
    rng = np.random.default_rng(seed)
    tone = (rng.random((region.shape[0] // h + 2, region.shape[1] // w + 2))
            [row, (xs - left + (row % 2) * (w // 2)) // w] - 0.5) * 0.14
    return np.where(yo == h - 1, -0.45, np.where(xo == w - 1, -0.28, np.where((yo == 0) & (xo < 2), 0.3, 0.05))) + tone


def thatch(region, seed=5):
    """Straw thatch: short strands combed down, in layered bands with a shadowed lip."""
    top, left, _, _ = _bounds(region)
    ys, xs = np.mgrid[0:region.shape[0], 0:region.shape[1]]
    rng = np.random.default_rng(seed)
    jitter = rng.integers(0, 3, size=region.shape[1] + 2)[xs]
    strand = (xs * 3 + jitter) % 4
    band = (ys - top + jitter) % 7
    return np.where(band == 6, -0.42, np.where(strand == 0, -0.2, np.where(strand == 2, 0.18, 0.0)))


def slate(region, w=7, h=3, seed=6):
    """Slate: flat, long, overlapping in rows; a hard dark line under each row, a pale edge on top."""
    top, left, _, _ = _bounds(region)
    ys, xs = np.mgrid[0:region.shape[0], 0:region.shape[1]]
    row = (ys - top) // h
    xo = (xs - left + (row % 2) * 3) % w
    yo = (ys - top) % h
    rng = np.random.default_rng(seed)
    tone = (rng.random((region.shape[0] // h + 2, region.shape[1] // w + 2))[row, (xs - left + (row % 2) * 3) // w]
            - 0.5) * 0.2
    return np.where(yo == h - 1, -0.45, np.where(xo == 0, -0.25, np.where(yo == 0, 0.2, 0.0))) + tone


PATTERNS = {"blocks": blocks, "plaster": plaster, "planks": planks, "boards": lambda r: planks(r, vertical=True),
            "tiles": tiles, "thatch": thatch, "slate": slate, "bricks": lambda r: blocks(r, w=5, h=3)}


# ------------------------------------------------------------------------------------------ the kit

class Build:
    """A building being drawn: pixel_kit shapes, back to front, plus surfaces with a pattern. Drawn in a
    96-pixel frame's coordinates, then (`fit`) scaled about its foot to fill the frame as RD's do; the
    materials' patterns stay at the sprite's own pixels, so a bigger house has more blocks, not bigger."""

    def __init__(self, k=1.0, cx=SIZE / 2):
        self.s = Sprite(SIZE)
        self.s.light, self.s.rim = LIGHT, "lower"
        self.k, self.cx = k, cx

    def t(self, points):
        return [(SIZE / 2 + (x - self.cx) * self.k, GROUND + (y - GROUND) * self.k) for x, y in points]

    def _mask(self, points):
        self.s.poly(self.t(points), Material("#808080"))
        return self.s.shapes.pop()[0]

    def surface(self, points, colour, pattern=None, tone=0.0, slope=(0.0, 0.0), texture=0.03, shades=7,
                gloss=0.0, mask=None):
        """A flat face (a wall, a roof plane) in `colour` with a material's `pattern`; `tone` lightens or
        darkens it (a side wall going back is a step darker), `slope` (per pixel, x and y) grades it."""
        m = self._mask(points) if mask is None else mask
        region = m.reshape(SIZE, SS, SIZE, SS).mean(axis=(1, 3)) >= 0.5
        if not region.any():
            return
        ys, xs = np.nonzero(region)
        yy, xx = np.mgrid[0:SIZE, 0:SIZE]
        detail = tone + slope[0] * (xx - xs.mean()) + slope[1] * (yy - ys.mean())
        if pattern:
            detail = detail + np.where(region, PATTERNS[pattern](region), 0.0)
        detail = np.kron(detail, np.ones((SS, SS)))
        mat = Material(colour, texture=texture, shades=shades, gloss=gloss, variety=2.0)
        self.s.mask(m, mat, height=np.zeros(m.shape), detail=detail)

    def poly(self, points, colour, texture=0.02, profile="flat", tone=None, shades=6, gloss=0.0):
        self.s.poly(self.t(points), Material(colour, texture=texture, shades=shades, gloss=gloss), profile=profile,
                    tone=tone)

    def rect(self, x0, y0, x1, y1, colour, **kw):
        self.poly([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], colour, **kw)

    def ellipse(self, cx, cy, rx, ry, colour, texture=0.02, profile="dome", gloss=0.0):
        (x, y), = self.t([(cx, cy)])
        self.s.ellipse(x, y, rx * self.k, ry * self.k, Material(colour, texture=texture, gloss=gloss), profile=profile)

    def stroke(self, points, width, colour, texture=0.02):
        self.s.stroke(self.t(points), width * self.k, Material(colour, texture=texture))

    def extent(self):
        """The drawing's bounds so far, in the frame's pixels: (left, top, right, bottom)."""
        union = np.zeros(self.s.shapes[0][0].shape, bool)
        for m, *_ in self.s.shapes:
            union |= m
        ys, xs = np.nonzero(union)
        return xs.min() / SS, ys.min() / SS, xs.max() / SS, ys.max() / SS

    def render(self):
        return self.s.render(outline="tinted")


def box(b, x0, x1, height, wall, side=None, pattern="plaster", side_pattern=None, ground=GROUND, depth=1.0):
    """The walls: a front from x0 to x1, `height` tall, and the right side going back `depth` of a
    wall's depth. Returns the wall's top-left and top-right corners and the far corner's top."""
    top = ground - height
    dx, dy = DX * depth, DY * depth
    b.surface([(x1, ground), (x1 + dx, ground + dy), (x1 + dx, top + dy), (x1, top)], side or wall,
              side_pattern or pattern, tone=-0.22, slope=(0.0, 0.004))
    b.surface([(x0, ground), (x1, ground), (x1, top), (x0, top)], wall, pattern, slope=(-0.003, 0.004))
    return top


def footing(b, x0, x1, ground=GROUND, depth=1.0, colour="#8f8a86"):
    """A course of stone along the foot of the walls, front and side."""
    dx, dy = DX * depth, DY * depth
    b.surface([(x1, ground + 1), (x1 + dx, ground + 1 + dy), (x1 + dx, ground - 3 + dy), (x1, ground - 3)],
              colour, "blocks", tone=-0.2)
    b.surface([(x0 - 1, ground + 1), (x1, ground + 1), (x1, ground - 3), (x0 - 1, ground - 3)], colour, "blocks")


def gable_roof(b, x0, x1, top, colour, pattern="tiles", rise=20, over=3, depth=1.0):
    """A roof with its gable to the front: the gable wall's triangle (in the wall's own colour, drawn by
    the caller) under a roof whose right plane runs back, and an edge of the left plane."""
    mid = (x0 + x1) / 2
    dx, dy = DX * depth, DY * depth
    apex = (mid, top - rise)
    right_eave = (x1 + over, top + 2)
    b.surface([apex, right_eave, (right_eave[0] + dx, right_eave[1] + dy), (apex[0] + dx, apex[1] + dy)],
              colour, pattern, tone=0.02, slope=(0.004, 0.006))
    # The barge boards along the gable's two slopes, so the roof's edge reads.
    left_eave = (x0 - over, top + 2)
    b.stroke([left_eave, apex, right_eave], 2.6, colour)
    return apex


def gable(b, x0, x1, top, wall, pattern="plaster", rise=20):
    """The gable end's triangle of wall, over a front wall from x0 to x1."""
    mid = (x0 + x1) / 2
    b.surface([(x0, top + 0.5), (x1, top + 0.5), (mid, top - rise + 1)], wall, pattern, tone=0.04)


def eaves_roof(b, x0, x1, top, colour, pattern="tiles", rise=16, over=3, depth=1.0, wall=None, wall_pattern=None):
    """A roof with its eaves to the front: the front plane sloping up and back to the ridge, the gable
    end on the right (in `wall`)."""
    dx, dy = DX * depth, DY * depth
    ridge_l = (x0 - over + dx / 2, top + dy / 2 - rise)
    ridge_r = (x1 + dx / 2, top + dy / 2 - rise)
    if wall:
        b.surface([(x1, top), (x1 + dx, top + dy), ridge_r], wall, wall_pattern or "plaster", tone=-0.18)
    b.surface([(x0 - over, top + 3), (x1 + over, top + 3), (ridge_r[0] + over, ridge_r[1]), ridge_l],
              colour, pattern, tone=0.04, slope=(0.0, 0.006))
    # The roof's right edge, down the gable.
    b.stroke([(ridge_r[0] + over * 0.6, ridge_r[1]), (x1 + dx + over * 0.6, top + dy + 2)], 2.4, colour)
    b.stroke([(ridge_l[0], ridge_l[1]), (ridge_r[0] + over, ridge_r[1])], 2.4, colour)       # the ridge
    return ridge_l, ridge_r


def window(b, cx, cy, w=8, h=9, frame="#6b4a32", glass="#ffd27a", arched=False, shutters=None, box=None):
    """A lit window: frame, warm glass with a cross of glazing bars, a sill; `shutters` a colour,
    `box` a flower box's flowers' colour."""
    x0, x1, y0, y1 = cx - w / 2, cx + w / 2, cy - h / 2, cy + h / 2
    if shutters:
        b.rect(x0 - 3.5, y0, x0 - 0.5, y1, shutters, texture=0.04)
        b.rect(x1 + 0.5, y0, x1 + 3.5, y1, shutters, texture=0.04)
    pts = [(x0 - 1, y1 + 1), (x1 + 1, y1 + 1), (x1 + 1, y0 + (2 if arched else -1))]
    if arched:
        pts += [(cx + (w / 2 + 1) * math.cos(a), y0 + 2 - (w / 2 + 1) * math.sin(a)) for a in np.linspace(0, math.pi, 9)]
    pts += [(x0 - 1, y0 + (2 if arched else -1))]
    b.poly(pts, frame, texture=0.03)
    gpts = [(x0, y1), (x1, y1), (x1, y0 + (2 if arched else 0))]
    if arched:
        gpts += [(cx + w / 2 * math.cos(a), y0 + 2 - w / 2 * math.sin(a)) for a in np.linspace(0, math.pi, 9)]
    gpts += [(x0, y0 + (2 if arched else 0))]
    b.poly(gpts, glass, texture=0.0, profile="flat")
    b.rect(cx - 0.5, y0, cx + 0.5, y1, frame, texture=0.0)
    b.rect(x0, cy - 0.5, x1, cy + 0.5, frame, texture=0.0)
    b.rect(x0 - 2, y1 + 0.5, x1 + 2, y1 + 2.2, frame, texture=0.03)            # the sill
    if box:
        b.rect(x0 - 1, y1 + 2, x1 + 1, y1 + 5, "#7a5236", texture=0.05)
        for k, x in enumerate(np.linspace(x0, x1, 4)):
            b.ellipse(x, y1 + 1.6, 1.5, 1.3, "#4e9a3a" if k % 2 else box)


def door(b, cx, w=10, h=15, colour="#7a4e2e", ground=GROUND, frame="#5a3a24", arched=True, knob="#e8c050"):
    """A plank door, arched or square, in a frame, with a step before it."""
    x0, x1, y0 = cx - w / 2, cx + w / 2, ground - h
    if arched:
        arc = [(cx + (w / 2 + 1.2) * math.cos(a), y0 + w / 2 - (w / 2 + 1.2) * math.sin(a)) for a in np.linspace(0, math.pi, 11)]
        b.poly([(x1 + 1.2, ground)] + arc + [(x0 - 1.2, ground)], frame, texture=0.03)
        arc = [(cx + w / 2 * math.cos(a), y0 + w / 2 - w / 2 * math.sin(a)) for a in np.linspace(0, math.pi, 11)]
        b.surface([(x1, ground)] + arc + [(x0, ground)], colour, "boards", texture=0.04, shades=6)
    else:
        b.rect(x0 - 1.2, y0 - 1.2, x1 + 1.2, ground, frame, texture=0.03)
        b.surface([(x0, ground), (x1, ground), (x1, y0), (x0, y0)], colour, "boards", texture=0.04, shades=6)
    b.ellipse(x1 - 2, ground - h * 0.42, 0.9, 0.9, knob, gloss=0.6)
    b.rect(x0 - 2.5, ground, x1 + 2.5, ground + 2.4, "#9a948e", texture=0.05)    # the step


def chimney(b, x, base, h=12, w=6, colour="#8f6a5a"):
    b.surface([(x, base), (x + w, base), (x + w, base - h), (x, base - h)], colour, "bricks")
    b.surface([(x + w, base), (x + w + 2.5, base - 1.5), (x + w + 2.5, base - h - 1.5), (x + w, base - h)], colour,
              "bricks", tone=-0.22)
    b.rect(x - 1, base - h - 2, x + w + 3, base - h + 0.5, "#6a6a72", texture=0.03)


def sign(b, x, y, emblem, board="#c8945a", bracket="#3a3036"):
    """A hanging shop sign on an iron bracket out from the wall at (x, y), showing `emblem(b, cx, cy)`."""
    b.stroke([(x, y), (x + 12, y)], 1.4, bracket)
    b.stroke([(x + 1, y + 3), (x + 4, y)], 1.0, bracket)
    b.stroke([(x + 3, y), (x + 3, y + 2)], 0.8, bracket)
    b.stroke([(x + 10, y), (x + 10, y + 2)], 0.8, bracket)
    b.poly([(x + 1, y + 2), (x + 12, y + 2), (x + 12, y + 12), (x + 1, y + 12)], board, texture=0.05, shades=6)
    emblem(b, x + 6.5, y + 7)


def awning(b, x0, x1, y, colours, drop=7, depth=4):
    """A striped awning over a shop front, its scalloped edge hanging."""
    n = max(4, int((x1 - x0) / 4))
    for k in range(n):
        a, c = x0 + (x1 - x0) * k / n, x0 + (x1 - x0) * (k + 1) / n
        col = colours[k % len(colours)]
        b.poly([(a, y), (c, y), (c + 1, y + drop), (a + 1, y + drop)], col, texture=0.02, tone=0.55 - 0.15 * (k % 2))
        b.ellipse((a + c) / 2 + 1, y + drop, (c - a) / 2, 1.6, col, profile="flat")
    b.stroke([(x0, y - depth * 0.2), (x1, y - depth * 0.2)], 1.5, "#5a4a46")


def flowers(b, x0, x1, y, colours, seed=1):
    """A bed of flowers along the foot of a wall."""
    rng = np.random.default_rng(seed)
    for x in np.arange(x0, x1, 2.6):
        b.ellipse(x, y, 2.0, 1.6, "#4e9a3a")
    for x in np.arange(x0 + 1, x1, 3.1):
        b.ellipse(x + rng.uniform(-0.6, 0.6), y - 1.5 + rng.uniform(-0.5, 0.5), 1.1, 1.0,
                  colours[int(rng.integers(len(colours)))], profile="flat")


# --------------------------------------------------------------------------------------- the emblems

def sword_emblem(b, cx, cy):
    b.stroke([(cx - 3.5, cy + 3.5), (cx + 3.5, cy - 3.5)], 1.4, "#d8dee8")
    b.stroke([(cx + 3.5, cy + 3.5), (cx - 3.5, cy - 3.5)], 1.4, "#d8dee8")
    b.stroke([(cx - 3, cy + 1), (cx - 1, cy + 3)], 1.2, "#8a5a2a")
    b.stroke([(cx + 3, cy + 1), (cx + 1, cy + 3)], 1.2, "#8a5a2a")


def shield_emblem(b, cx, cy):
    b.poly([(cx - 3.5, cy - 4), (cx + 3.5, cy - 4), (cx + 3.5, cy), (cx, cy + 4.5), (cx - 3.5, cy)], "#3a6ab8", texture=0.0)
    b.stroke([(cx, cy - 3.5), (cx, cy + 3.5)], 1.0, "#e8c050")


def thread_emblem(b, cx, cy):
    b.ellipse(cx - 1, cy, 2.6, 3.2, "#c86aa8")
    b.stroke([(cx + 1, cy + 3.5), (cx + 4, cy - 4)], 0.9, "#d8dee8")


def flower_emblem(b, cx, cy):
    for k in range(5):
        a = k / 5 * 2 * math.pi
        b.ellipse(cx + math.cos(a) * 2.2, cy + math.sin(a) * 2.2, 1.5, 1.5, "#f07aa8", profile="flat")
    b.ellipse(cx, cy, 1.2, 1.2, "#f8d84a", profile="flat")


def cup_emblem(b, cx, cy):
    b.poly([(cx - 3.5, cy - 1.5), (cx + 2.5, cy - 1.5), (cx + 1.5, cy + 2.5), (cx - 2.5, cy + 2.5)], "#f4f0ea", texture=0.0)
    b.stroke([(cx + 2.5, cy - 0.5), (cx + 4, cy), (cx + 2, cy + 1.5)], 0.9, "#f4f0ea")
    b.stroke([(cx - 1.5, cy - 3), (cx - 1, cy - 4.5)], 0.7, "#e8e8f0")
    b.stroke([(cx + 0.5, cy - 3), (cx + 1, cy - 4.5)], 0.7, "#e8e8f0")


def book_emblem(b, cx, cy):
    b.poly([(cx, cy - 2), (cx - 4.5, cy - 3.5), (cx - 4.5, cy + 2.5), (cx, cy + 4)], "#f4ecd8", texture=0.0)
    b.poly([(cx, cy - 2), (cx + 4.5, cy - 3.5), (cx + 4.5, cy + 2.5), (cx, cy + 4)], "#e4d8bc", texture=0.0)
    b.stroke([(cx, cy - 2), (cx, cy + 4)], 0.8, "#8a3a3a")


# ---------------------------------------------------------------------------------------- the homes

def thatched_cottage(b):
    x0, x1 = 20, 66
    top = box(b, x0, x1, 22, "#ead2a8", pattern="plaster")
    footing(b, x0, x1)
    eaves_roof(b, x0, x1, top, "#d8a84a", "thatch", rise=22, over=5, wall="#ead2a8")
    chimney(b, 56, top - 12, h=10, colour="#9a7a6a")
    door(b, 35, colour="#5a7ab0", frame="#4a3424")
    window(b, 55, top + 10, shutters="#5a7ab0", box="#f07aa8")
    window(b, 25.5, top + 10, w=6, shutters="#5a7ab0")
    flowers(b, 44, 50, GROUND - 1, ["#f8d84a", "#f07aa8", "#ffffff"], seed=3)
    return b


def timber_house(b):
    x0, x1 = 24, 62
    top = box(b, x0, x1, 36, "#ecd8b4", pattern="plaster")
    footing(b, x0, x1)
    # The timber frame: posts, a rail between the floors, braces.
    beam = "#4e3426"
    for x in (x0 + 1, (x0 + x1) / 2, x1 - 1):
        b.stroke([(x, GROUND - 3), (x, top)], 2.2, beam)
    b.stroke([(x0, top + 17), (x1, top + 17)], 2.2, beam)
    b.stroke([(x0, top + 1), (x1, top + 1)], 2.2, beam)
    b.stroke([(x0 + 1, top + 16), (x0 + 8, top + 2)], 1.8, beam)
    b.stroke([(x1 - 1, top + 16), (x1 - 8, top + 2)], 1.8, beam)
    for xs in ((x1 + 1, x1 + DX - 1),):
        b.stroke([(x1 + 2, top + 16 - 1), (x1 + DX - 1, top + 16 + DY + 1)], 1.8, beam)
    apex = (x0 + x1) / 2
    gable(b, x0, x1, top, "#ecd8b4", rise=20)
    b.stroke([(apex, top - 18), (apex, top)], 1.8, beam)
    gable_roof(b, x0, x1, top, "#d0663a", "tiles", rise=20)
    window(b, apex, top - 6, w=6, h=6, frame=beam)
    window(b, x0 + 9.5, top + 9, w=7, h=8, frame=beam, box="#f04a4a")
    window(b, x1 - 9.5, top + 9, w=7, h=8, frame=beam, box="#f8d84a")
    door(b, x0 + 10, w=9, colour="#3a6a4a", frame=beam, arched=False)
    window(b, x1 - 9.5, GROUND - 11, w=7, h=8, frame=beam)
    chimney(b, x1 + 3, top - 5, h=12, colour="#8a5a4a")
    return b


def stone_townhouse(b):
    x0, x1 = 28, 60
    top = box(b, x0, x1, 44, "#b8b2aa", pattern="blocks", depth=0.9)
    eaves_roof(b, x0, x1, top, "#4a5a7a", "slate", rise=16, over=3, depth=0.9, wall="#b8b2aa", wall_pattern="blocks")
    chimney(b, x0 + 2, top - 6, h=10, colour="#8a7a72")
    chimney(b, x1 + 4, top - 10, h=9, colour="#8a7a72")
    for row, y in enumerate((top + 9, top + 23)):
        window(b, x0 + 8, y, w=7, h=9, frame="#e8e2d8", arched=row == 0)
        window(b, x1 - 8, y, w=7, h=9, frame="#e8e2d8", arched=row == 0)
    door(b, (x0 + x1) / 2, w=9, h=14, colour="#2e7a4e", frame="#e8e2d8")
    b.ellipse((x0 + x1) / 2, GROUND - 17, 1.4, 1.4, "#e8c050", gloss=0.6)          # a lamp over the door
    return b


def round_cottage(b):
    cx, r = 44, 21
    wall, roof = "#d8d0c0", "#2e9a92"
    # The tower's wall: a rectangle with a curved foot, shaded round (lit left, dark right).
    pts = [(cx - r, GROUND - 26)] + [(cx + r * math.cos(a), GROUND - 4 + 5 * math.sin(a))
                                     for a in np.linspace(math.pi, 0, 17)] + [(cx + r, GROUND - 26)]
    b.surface(pts, wall, "blocks", slope=(-0.012, 0.0))
    # The cone roof, its eave a curve, its tip off to the side a little.
    eave = [(cx + (r + 4) * math.cos(a), GROUND - 27 + 6 * math.sin(a)) for a in np.linspace(0, math.pi, 17)]
    b.surface([(cx + 2, GROUND - 66)] + eave, roof, "tiles", slope=(-0.014, 0.004))
    b.ellipse(cx + 2, GROUND - 66, 1.6, 1.6, "#e8c050", gloss=0.6)                 # a finial
    door(b, cx - 4, w=10, h=16, colour="#7a4e2e")
    window(b, cx + 11, GROUND - 16, w=6, h=7, arched=True)
    b.ellipse(cx + 3, GROUND - 36, 3.4, 3.4, "#6b4a32")                             # a round dormer window
    b.ellipse(cx + 3, GROUND - 36, 2.4, 2.4, "#ffd27a", profile="flat")
    for (x, y) in ((cx - 18, GROUND - 20), (cx - 16, GROUND - 14), (cx - 19, GROUND - 9), (cx - 14, GROUND - 24)):
        b.ellipse(x, y, 2.4, 2.0, "#4e8a3a")                                        # ivy
    return b


def teapot_house(b):
    cx = 46
    pot, paint = "#f4f0ea", "#4a7ad0"
    b.stroke([(cx + 20, GROUND - 22), (cx + 28, GROUND - 32), (cx + 31, GROUND - 42)], 6, pot)    # the spout
    b.ellipse(cx - 21, GROUND - 26, 6, 9, pot)                                                    # the handle
    b.ellipse(cx - 21, GROUND - 26, 2.6, 5.2, "#5e8a4e", profile="flat")
    b.ellipse(cx, GROUND - 22, 23, 21, pot, gloss=0.4)                                             # the body
    b.ellipse(cx, GROUND - 41, 12, 4, "#e8e2d8")                                                   # the lid
    b.ellipse(cx, GROUND - 46, 7, 5, pot, gloss=0.4)
    b.ellipse(cx, GROUND - 52, 2.6, 2.6, paint, gloss=0.5)                                        # its knob
    for k, (x, y) in enumerate(((cx - 13, GROUND - 30), (cx + 12, GROUND - 28), (cx - 4, GROUND - 12), (cx + 14, GROUND - 12))):
        for j in range(5):
            a = j / 5 * 2 * math.pi
            b.ellipse(x + math.cos(a) * 2, y + math.sin(a) * 2, 1.4, 1.4, paint, profile="flat")
        b.ellipse(x, y, 1.0, 1.0, "#f8d84a", profile="flat")
    door(b, cx - 1, w=10, h=14, colour="#4a6ab0")
    window(b, cx + 11, GROUND - 21, w=6, h=6, arched=True, frame="#4a6ab0")
    b.ellipse(cx + 31, GROUND - 45, 2.4, 1.6, "#e8e8f0", profile="flat")                          # steam
    b.ellipse(cx + 33, GROUND - 49, 1.8, 1.4, "#e8e8f0", profile="flat")
    return b


def garden_cottage(b):
    x0, x1 = 34, 66
    top = box(b, x0, x1, 21, "#f0cfb0", pattern="plaster", depth=0.9)
    footing(b, x0, x1, depth=0.9)
    gable(b, x0, x1, top, "#f0cfb0", rise=16)
    gable_roof(b, x0, x1, top, "#e07a9a", "tiles", rise=16, depth=0.9)
    window(b, (x0 + x1) / 2, top - 5, w=5, h=5, arched=True)
    door(b, x0 + 9, w=9, h=14, colour="#6a9a5a")
    window(b, x1 - 8, top + 10, w=7, h=7, box="#f8d84a")
    # The garden: a bed of rows before a picket fence, a watering can.
    b.surface([(6, GROUND + 2), (32, GROUND + 2), (32, GROUND - 12), (6, GROUND - 12)], "#7a5a3e", "planks", tone=-0.05)
    for y in (GROUND - 9, GROUND - 4):
        for x in np.arange(9, 31, 4):
            b.ellipse(x, y, 1.8, 1.5, "#5aa83e")
    for x in np.arange(5, 33, 3.5):
        b.poly([(x, GROUND + 4), (x + 2, GROUND + 4), (x + 2, GROUND - 3), (x + 1, GROUND - 4.5), (x, GROUND - 3)], "#f4f0ea")
    b.stroke([(4, GROUND), (33, GROUND)], 1.4, "#f4f0ea")
    b.ellipse(x0 + 2, GROUND - 2, 3, 2.6, "#7a9ab8", gloss=0.5)                                    # the watering can
    b.stroke([(x0 + 4, GROUND - 3), (x0 + 7, GROUND - 6)], 1.0, "#7a9ab8")
    return b


# ---------------------------------------------------------------------------------------- the shops

def shop(b, wall, wall_pattern, roof, roof_pattern, emblem, board="#c8945a", awning_colours=None, x0=20, x1=60,
         height=30, door_colour="#7a4e2e", rise=18, display=None, gabled=False, upper=0, frame=None):
    """A shop: its front a big display window beside the door, a sign hanging out, maybe an awning; its
    roof `gabled` to the front or eaves to the front, `upper` windows on a floor above the shop, its
    wall timber-framed in `frame`."""
    top = box(b, x0, x1, height, wall, pattern=wall_pattern)
    footing(b, x0, x1)
    if frame:
        for x in (x0 + 1, x1 - 1):
            b.stroke([(x, GROUND - 3), (x, top)], 2.2, frame)
        b.stroke([(x0, top + 1), (x1, top + 1)], 2.2, frame)
        if upper:
            b.stroke([(x0, GROUND - 24), (x1, GROUND - 24)], 2.2, frame)
    if gabled:
        gable(b, x0, x1, top, wall, wall_pattern, rise=rise)
        gable_roof(b, x0, x1, top, roof, roof_pattern, rise=rise)
        window(b, (x0 + x1) / 2, top - rise / 3, w=6, h=6, arched=True)
    else:
        eaves_roof(b, x0, x1, top, roof, roof_pattern, rise=rise, over=4, wall=wall, wall_pattern=wall_pattern)
    for k in range(upper):
        window(b, x0 + (x1 - x0) * (k + 0.5) / upper, top + 8, w=7, h=8, frame=frame or "#6b4a32",
               box="#f07aa8" if k % 2 else None)
    door(b, x0 + 9, w=9, h=15, colour=door_colour, arched=False)
    # The display window, with what the shop sells in it.
    wx0, wx1, wy0, wy1 = x0 + 17, x1 - 4, GROUND - 19, GROUND - 6
    b.rect(wx0 - 1.2, wy0 - 1.2, wx1 + 1.2, wy1 + 1.2, "#5a3a24", texture=0.03)
    b.rect(wx0, wy0, wx1, wy1, "#ffe0a0", texture=0.0)
    if display:
        display(b, wx0, wy0, wx1, wy1)
    b.rect(wx0 - 2, wy1 + 0.5, wx1 + 2, wy1 + 2.4, "#5a3a24", texture=0.03)
    if not upper and not gabled:
        window(b, (x0 + x1) / 2, top + 7, w=8, h=6)
    if awning_colours:
        awning(b, wx0 - 3, wx1 + 3, wy0 - 6, awning_colours)
    sign(b, x1 + DX - 2, top + 2, emblem, board=board)
    return b


def wares(colours, shape="round"):
    def draw(b, x0, y0, x1, y1):
        n = len(colours)
        for k, c in enumerate(colours):
            x = x0 + (x1 - x0) * (k + 0.5) / n
            if shape == "round":
                b.ellipse(x, y1 - 3, 2.2, 2.4, c)
            elif shape == "tall":
                b.rect(x - 1.6, y1 - 9 + (k % 2) * 2, x + 1.6, y1, c, texture=0.02)
            elif shape == "blade":
                b.stroke([(x, y1 - 1), (x, y0 + 2)], 1.4, c)
                b.stroke([(x - 2, y1 - 3), (x + 2, y1 - 3)], 1.2, "#8a5a2a")
    return draw


def weapon_shop(b):
    shop(b, "#c8beb2", "blocks", "#b8423a", "tiles", sword_emblem, board="#d8b070", gabled=True, rise=22,
             display=wares(["#d8dee8", "#c0c8d4", "#d8dee8", "#e0c070"], "blade"))
    # A rack of spears by the door.
    for x in (8, 11, 14):
        b.stroke([(x, GROUND), (x, GROUND - 26)], 1.2, "#8a5a2a")
        b.poly([(x - 1.4, GROUND - 26), (x + 1.4, GROUND - 26), (x, GROUND - 31)], "#d8dee8", texture=0.0)
    b.stroke([(6, GROUND - 12), (16, GROUND - 12)], 1.6, "#6a4a2e")
    return b


def armour_shop(b):
    shop(b, "#a8a4a0", "blocks", "#3a5a9a", "slate", shield_emblem, board="#c8945a", height=46, upper=2, rise=14,
             display=wares(["#7a8aa0", "#b0b8c8", "#7a8aa0"], "round"))
    # A suit of armour on a stand by the door.
    b.stroke([(11, GROUND), (11, GROUND - 6)], 1.4, "#6a4a2e")
    b.rect(7, GROUND - 18, 15, GROUND - 6, "#b0b8c8", texture=0.02, profile="dome", gloss=0.8)
    b.ellipse(11, GROUND - 22, 3.6, 4, "#c0c8d4", gloss=0.8)
    b.rect(9, GROUND - 22.5, 13, GROUND - 21.5, "#2a2a36", texture=0.0)
    return b


def tailor_shop(b):
    shop(b, "#eccad8", "plaster", "#9a6ac8", "tiles", thread_emblem, board="#e8d0b0", height=44, upper=3,
         frame="#5a3a4a", x0=18, x1=62,
             awning_colours=["#b88ae0", "#f4f0ea"], door_colour="#6a4a8a",
             display=wares(["#e85a7a", "#5a8ae8", "#f8d84a", "#5ab87a"], "tall"))
    # A dress on a mannequin by the door.
    b.stroke([(11, GROUND), (11, GROUND - 4)], 1.2, "#6a4a2e")
    b.poly([(8.5, GROUND - 4), (13.5, GROUND - 4), (12.5, GROUND - 13), (11, GROUND - 14), (9.5, GROUND - 13)], "#e85a7a", texture=0.03)
    b.ellipse(11, GROUND - 16, 1.6, 1.8, "#d8c0a8")
    return b


def flower_shop(b):
    shop(b, "#ecd6b0", "plaster", "#6a9a4a", "thatch", flower_emblem, board="#f4f0ea", height=26, x0=18, x1=64,
             awning_colours=["#f07aa8", "#f4f0ea"], door_colour="#4a7a5a",
             display=wares(["#f07aa8", "#f8d84a", "#b88ae0", "#f04a4a", "#ffffff"], "round"))
    # Buckets of flowers out front.
    for k, (x, c) in enumerate(((6, "#f04a4a"), (11, "#f8d84a"), (16, "#b88ae0"))):
        b.rect(x - 2, GROUND - 4, x + 2, GROUND + 1, "#8a9aa8", texture=0.02)
        for j in range(3):
            b.ellipse(x - 1.5 + j * 1.5, GROUND - 6 - (j % 2), 1.4, 1.3, c, profile="flat")
    return b


def tea_house(b):
    shop(b, "#e8cfa4", "plaster", "#4a8a5a", "tiles", cup_emblem, board="#d8b070", door_colour="#8a4a3a",
         gabled=True, rise=16, frame="#6a4a3a",
             display=wares(["#f4f0ea", "#e8b0a0", "#f4f0ea"], "round"))
    # A little table with two chairs and a lantern.
    b.stroke([(10, GROUND + 1), (10, GROUND - 6)], 1.2, "#6a4a2e")
    b.ellipse(10, GROUND - 7, 5, 1.6, "#f4f0ea")
    b.ellipse(10, GROUND - 8.5, 1.2, 1.0, "#e8b0a0")
    for x in (3.5, 16.5):
        b.rect(x - 1.5, GROUND - 5, x + 1.5, GROUND - 3, "#8a5a3a", texture=0.02)
        b.stroke([(x, GROUND - 3), (x, GROUND + 1)], 1.0, "#6a4a2e")
    b.stroke([(4, GROUND - 26), (16, GROUND - 26)], 0.8, "#3a3036")
    for x in (7, 13):
        b.ellipse(x, GROUND - 23, 1.8, 2.2, "#f08a3a", profile="flat")
    return b


def book_shop(b):
    shop(b, "#c8a888", "planks", "#7a4a2e", "slate", book_emblem, board="#e8d8b8", door_colour="#4a3a6a",
         height=48, upper=2, x0=24, x1=58, rise=20,
             display=wares(["#a83a3a", "#3a6aa8", "#4a8a4a", "#d8a83a", "#7a4aa8", "#a83a3a"], "tall"))
    # A reading bench by the door.
    b.rect(3, GROUND - 6, 17, GROUND - 4, "#8a5a3a", texture=0.03)
    for x in (5, 15):
        b.stroke([(x, GROUND - 4), (x, GROUND + 1)], 1.0, "#6a4a2e")
    b.rect(8, GROUND - 8, 12, GROUND - 6, "#3a6aa8", texture=0.0)
    return b


BUILDINGS = {
    "thatched_cottage": thatched_cottage,
    "timber_house": timber_house,
    "stone_townhouse": stone_townhouse,
    "round_cottage": round_cottage,
    "teapot_house": teapot_house,
    "garden_cottage": garden_cottage,
    "weapon_shop": weapon_shop,
    "armour_shop": armour_shop,
    "tailor_shop": tailor_shop,
    "flower_shop": flower_shop,
    "tea_house": tea_house,
    "book_shop": book_shop,
}


def fit(draw, width=76, height=76):
    """`draw` (a function of a Build) redrawn scaled about its foot so it fills `width` × `height` of the
    frame, centred, as RD's buildings fill theirs (about 70 to 80 pixels each way)."""
    left, top, right, bottom = draw(Build()).extent()
    k = min(width / (right - left), height / (GROUND - top), 1.6)
    return draw(Build(k, (left + right) / 2))


def main(argv):
    sheet = None
    if "--sheet" in argv:
        i = argv.index("--sheet")
        sheet = pathlib.Path(argv[i + 1])
        argv = argv[:i] + argv[i + 2:]
    ids = argv or list(BUILDINGS)
    out = {}
    for item in ids:
        img = fit(BUILDINGS[item]).render()
        img.save(SPRITES / f"{item}.png")
        out[item] = img
    print(f"wrote {len(out)} buildings to art/sprites/")
    if sheet:
        tiles_ = [Image.open(SPRITES / "house.png").convert("RGBA"), Image.open(SPRITES / "item_shop.png").convert("RGBA")]
        tiles_ += list(out.values())
        c = SIZE * 2
        cols = 5
        board = Image.new("RGBA", (c * cols, c * math.ceil(len(tiles_) / cols)), (106, 150, 86, 255))
        for n, img in enumerate(tiles_):
            board.alpha_composite(img.resize((c, c), Image.NEAREST), ((n % cols) * c, (n // cols) * c))
        board.save(sheet)
        print(f"sheet in {sheet}")


if __name__ == "__main__":
    main(sys.argv[1:])
