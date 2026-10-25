#!/usr/bin/env python3
"""Town houses and shops drawn in code with tools/pixel_kit.py, so the towns have more than the few
Retro Diffusion buildings (and their recolours) to build with. Each is a 96 × 96 sprite seen as RD's are,
from the front and a little above and to the right: a front wall, the right side wall going back, the
roof over both, and the things that make it a home or a shop (a door, lit windows, a chimney, a sign,
an awning, flower boxes) on a stone footing. And the places people work: Briarmere's lakeside shrine to
Liora (`lake_shrine`), Meadowbrook's Warrior Guild hall and Wildfolk Lodge, a bell tower and a gem workshop.

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
from pixel_kit import SS, Material, Sprite, limit_palette  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPRITES = ROOT / "art" / "sprites"

SIZE = 96
GROUND = 86                      # the front wall's foot (RD's buildings stand on rows 75 to 87)
DX, DY = 12, -7                  # a wall's depth going back, as the view shows it: up and to the right
LIGHT = np.array([-0.45, -0.55, 0.7]) / np.linalg.norm([-0.45, -0.55, 0.7])
# RD's finish: light and shade in broad areas, not a grain on every pixel (the materials' own texture
# toned down to this share, no second ramp to flick between), shadows turned well toward blue and
# lights toward yellow (`shift`), and a palette of about RD's size (`PALETTE`, pixel_kit.limit_palette),
# fewer on a smaller house.
TEXTURE, SHIFT, PALETTE = 0.35, 1.8, 40
DENSITY = 1.1                    # colours per 100 pixels at most, as RD's (about 0.55 to 1.3)


# --------------------------------------------------------------------------------- materials' patterns
# Each: light and shade (about −0.5 … 0.4) at the sprite's own pixels, given the face's 1× mask and every
# pixel's place on the face: `a` along it (a roof's eave, a wall's courses) and `d` down it (a roof's
# slope, a wall's height), in pixels from its top corner. On a face running back into the picture the
# two lean as the face does, so tiles and courses follow its edges instead of the screen's rows.

def _grid(region, a, d):
    A, D = np.floor(a).astype(int), np.floor(d).astype(int)
    return A - A[region].min(), D - D[region].min()


def _table(seed, rows=64, cols=64):
    return np.random.default_rng(seed).random((rows, cols))


def blocks(region, a, d, w=6, h=4, seed=1):
    """Stone or brick in courses: dark mortar lines, each block lit along its top, a few flecks."""
    A, D = _grid(region, a, d)
    row = D // h
    off = (row % 2) * (w // 2) + (row * 7 % 3)
    joint = (D % h == h - 1) | ((A + off) % w == 0)
    lit = D % h == 0
    shade = _table(seed)[row % 64, ((A + off) // w) % 64]
    fleck = _table(seed + 1, region.shape[0], region.shape[1]) < 0.05
    return np.where(joint, -0.4, np.where(lit, 0.2, 0.0)) + (shade - 0.5) * 0.12 + np.where(fleck & ~joint, 0.15, 0)


def plaster(region, a, d, seed=2):
    """Lime plaster: soft patches, never flat."""
    A, D = _grid(region, a, d)
    return (_table(seed)[(D // 5) % 64, (A // 5) % 64] - 0.5) * 0.1


def planks(region, a, d, h=3, seed=3, vertical=False):
    """Boards: a dark seam between each, grain along them, an end joint here and there."""
    A, D = _grid(region, a, d)
    along, across = (D, A) if vertical else (A, D)
    board = across // h
    seam = across % h == h - 1
    rng = np.random.default_rng(seed)
    joints = rng.integers(5, 22, size=64)
    joint = (along + board * 7) % (joints[board % 64] + 9) == 0
    grain = (np.sin(along * 0.9 + board * 2.1) > 0.85) * -0.12
    tone = (rng.random(64)[board % 64] - 0.5) * 0.16
    return np.where(seam | joint, -0.36, grain + tone)


def tiles(region, a, d, w=5, h=4, seed=4):
    """Clay roof tiles in rows along the eave, each rounded: lit on its upper left, its foot in the
    shadow of the next row down's overlap."""
    A, D = _grid(region, a, d)
    row = D // h
    xo = (A + (row % 2) * (w // 2)) % w
    yo = D % h
    tone = (_table(seed)[row % 64, ((A + (row % 2) * (w // 2)) // w) % 64] - 0.5) * 0.14
    return np.where(yo == h - 1, -0.45, np.where(xo == w - 1, -0.28, np.where((yo == 0) & (xo < 3), 0.36, 0.08))) + tone


def thatch(region, a, d, seed=5):
    """Straw thatch: short strands combed down the slope, in layered bands with a shadowed lip."""
    A, D = _grid(region, a, d)
    jitter = np.random.default_rng(seed).integers(0, 3, size=256)[A % 256]
    strand = (A * 3 + jitter) % 4
    band = (D + jitter) % 7
    return np.where(band == 6, -0.42, np.where(strand == 0, -0.2, np.where(strand == 2, 0.18, 0.0)))


def slate(region, a, d, w=7, h=3, seed=6):
    """Slate: flat, long, overlapping in rows; a hard dark line under each row, a pale edge on top."""
    A, D = _grid(region, a, d)
    row = D // h
    xo = (A + (row % 2) * 3) % w
    yo = D % h
    tone = (_table(seed)[row % 64, ((A + (row % 2) * 3) // w) % 64] - 0.5) * 0.2
    return np.where(yo == h - 1, -0.45, np.where(xo == 0, -0.25, np.where(yo == 0, 0.2, 0.0))) + tone


def rubble(region, a, d, h=5, seed=7):
    """Rough stones as RD lays them: courses about 5 high of stones 4 to 8 long, each a rounded lump lit on
    its upper left and deep on its lower right, its corners worn into the joints, every other stone a pixel
    taller or shorter so no joint runs straight across the face (ruled mortar is what read as a grid)."""
    A, D = _grid(region, a, d)
    rng = np.random.default_rng(seed)
    widths = rng.integers(4, 9, size=(64, 24))
    ends = np.cumsum(widths, axis=1)
    offset = rng.integers(0, 8, size=64)
    lift = rng.integers(0, 2, size=(64, 24))
    tones = rng.normal(0, 0.06, size=(64, 24))
    row = (D // h) % 64
    pos = (A + offset[row]) % ends[row, -1]
    idx = np.minimum((pos[..., None] >= ends[row]).sum(-1), 23)
    start = np.where(idx > 0, ends[row, np.maximum(idx - 1, 0)], 0)
    width = widths[row, idx]
    p = pos - start
    dy = D % h - lift[row, idx]                     # a stone a pixel up: its joint a row higher
    tall = h - 1
    joint = (dy == tall) | (dy == -1) | (p == width - 1)
    corner = ((dy == 0) | (dy == tall - 1)) & ((p == 0) | (p == width - 2))
    fx, fy = (p + 0.5) / np.maximum(width - 1, 1), (np.clip(dy, 0, tall - 1) + 0.5) / tall
    lump = 0.34 * (0.5 - fy) + 0.16 * (0.5 - fx) + tones[row, idx]
    return np.where(joint, -0.42, np.where(corner, -0.24, lump))


def shingles(region, a, d, w=8, h=5, seed=8):
    """Roof shingles as RD draws them: rows of rounded tongues, each lit along its top and curling at its
    foot into the shadow between it and the next, so the rows read as scallops, not ruled lines."""
    A, D = _grid(region, a, d)
    row = D // h
    xo = (A + (row % 2) * (w // 2)) % w
    yo = D % h
    u = np.abs((xo + 0.5) / w * 2 - 1)
    foot = ((yo == h - 1) & (u > 0.35)) | ((yo == h - 2) & (u > 0.8))
    tone = (_table(seed)[row % 64, ((A + (row % 2) * (w // 2)) // w) % 64] - 0.5) * 0.16
    return np.where(foot, -0.42, 0.32 * (0.5 - (yo + 0.5) / h) + 0.06 - 0.2 * u ** 2) + tone


PATTERNS = {"blocks": blocks, "rubble": rubble, "shingles": shingles, "plaster": plaster, "planks": planks,
            "boards": lambda r, a, d: planks(r, a, d, vertical=True),
            "tiles": tiles, "thatch": thatch, "slate": slate, "bricks": lambda r, a, d: blocks(r, a, d, w=5, h=3)}


def unit(x, y):
    n = math.hypot(x, y)
    return (x / n, y / n)


def shade(hexcode, k):
    """`hexcode` k times as light (darker a touch more saturated)."""
    import colorsys
    r, g, b_ = (int(hexcode.lstrip("#")[i:i + 2], 16) / 255 for i in (0, 2, 4))
    h, sat, v = colorsys.rgb_to_hsv(r, g, b_)
    sat = min(1, sat * (1 + (1 - k) * 0.4)) if k < 1 else sat * (1 - (k - 1) * 0.5)
    r, g, b_ = colorsys.hsv_to_rgb(h, sat, min(1, v * k))
    return "#%02x%02x%02x" % tuple(int(c * 255) for c in (r, g, b_))


SIDEWAYS = unit(DX, DY)        # along a wall or an eave going back into the picture
DOWN = (0.0, 1.0)


# ------------------------------------------------------------------------------------------ the kit

class Build:
    """A building being drawn: pixel_kit shapes, back to front, plus surfaces with a pattern. Drawn in a
    96-pixel frame's coordinates, then (`fit`) scaled about its foot to fill the frame as RD's do; the
    materials' patterns stay at the sprite's own pixels, so a bigger house has more blocks, not bigger."""

    def __init__(self, k=1.0, cx=SIZE / 2, organic=0.0, size=SIZE):
        # Its canvas, `size` pixels square: a house's 96, a grand building's more (its drawing, in the
        # 96-pixel frame's coordinates, scaled up to fill it; its materials stay at the sprite's pixels).
        self.size = size
        self.foot = GROUND + size - SIZE
        self.s = Sprite(size)
        self.s.light, self.s.rim = LIGHT, "lower"
        self.k, self.cx = k, cx
        # How far its edges wander off the ruler, in pixels (0: drawn straight; `bend`).
        self.organic = organic

    def t(self, points, closed=True, straight=False):
        pts = [(self.size / 2 + (x - self.cx) * self.k, self.foot + (y - GROUND) * self.k) for x, y in points]
        return self.bend(pts, closed) if self.organic and len(pts) > 1 and not straight else pts

    def bend(self, pts, closed):
        """The outline drawn by hand, as RD's houses are (2026-10-24: ours came out "a bit too squared"):
        each edge cut every couple of pixels and every point moved by one smooth field of small offsets, the
        same wherever two faces share an edge, so they still meet; a wall leans and bulges a little, a
        roofline sags."""
        out, n = [], len(pts)
        for i in range(n if closed else n - 1):
            (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % n]
            steps = max(1, int(math.hypot(x1 - x0, y1 - y0) / 2.5))
            out += [(x0 + (x1 - x0) * k / steps, y0 + (y1 - y0) * k / steps) for k in range(steps)]
        if not closed:
            out.append(pts[-1])
        a = self.organic
        return [(x + a * (0.5 * math.sin(0.61 * x + 0.43 * y + 0.7) + 0.5 * math.sin(0.29 * x - 0.71 * y + 2.1)),
                 y + a * (0.5 * math.sin(0.57 * y - 0.67 * x + 1.9) + 0.5 * math.sin(0.31 * y + 0.73 * x + 4.0)))
                for x, y in out]

    def _mask(self, points):
        self.s.poly(self.t(points), Material("#808080"))
        return self.s.shapes.pop()[0]

    def surface(self, points, colour, pattern=None, tone=0.0, slope=(0.0, 0.0), texture=0.03, shades=7,
                gloss=0.0, mask=None, axes=((1.0, 0.0), DOWN), eave=0, foot=0, curve=0.0):
        """A flat face (a wall, a roof plane) in `colour` with a material's `pattern` laid along `axes`
        (the face's along and down, as unit vectors: a face running back leans them); `tone` lightens or
        darkens it (a side wall going back is a step darker), `slope` (per pixel, x and y) grades it;
        `eave` pixels at its top lie in the shadow of the roof over it, `foot` pixels at its bottom in
        the ground's. `curve` shades it round across, as a drum or a cone is (lit a little left of its
        middle, deep at its right edge, a touch dark at its left): RD models every big form, where a face lit
        in one tone reads flat (2026-10-24)."""
        m = self._mask(points) if mask is None else mask
        n = self.size
        region = m.reshape(n, SS, n, SS).mean(axis=(1, 3)) >= 0.5
        if not region.any():
            return
        ys, xs = np.nonzero(region)
        yy, xx = np.mgrid[0:n, 0:n]
        (ux, uy), (vx, vy) = axes
        det = ux * vy - uy * vx
        px, py = xx + 0.5, yy + 0.5
        a_ = (px * vy - py * vx) / det
        d_ = (py * ux - px * uy) / det
        detail = tone + slope[0] * (xx - xs.mean()) + slope[1] * (yy - ys.mean())
        if curve:
            # Across each row of the face, from its left edge (−1) to its right (1).
            left = np.where(region, xx, n).min(axis=1, keepdims=True)
            right = np.where(region, xx, -1).max(axis=1, keepdims=True)
            u = np.clip((xx - left) / np.maximum(right - left, 1) * 2 - 1, -1, 1)
            detail = detail + curve * (0.35 - 0.75 * ((u + 0.3) / 1.3) ** 2)
        if pattern:
            detail = detail + np.where(region, PATTERNS[pattern](region, a_, d_), 0.0)
        if eave or foot:
            depth = d_ - d_[region].min()
            height = d_[region].max() - d_[region].min()
            if eave:
                detail = detail - 0.6 * np.clip(1 - depth / eave, 0, 1) ** 0.7
            if foot:
                detail = detail - 0.22 * np.clip(1 - (height - depth) / foot, 0, 1)
        detail = np.kron(detail, np.ones((SS, SS)))
        mat = Material(colour, texture=texture * TEXTURE, shades=shades, gloss=gloss, variety=0, shift=SHIFT)
        self.s.mask(m, mat, height=np.zeros(m.shape), detail=detail)

    def poly(self, points, colour, texture=0.02, profile="flat", tone=None, shades=6, gloss=0.0, straight=False):
        """`straight`: kept off the hand-drawn bend (a telescope, a pole: made, not grown)."""
        self.s.poly(self.t(points, straight=straight), Material(colour, texture=texture * TEXTURE, shades=shades, gloss=gloss, variety=0,
                                             shift=SHIFT), profile=profile,
                    tone=tone)

    def rect(self, x0, y0, x1, y1, colour, **kw):
        self.poly([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], colour, **kw)

    def ellipse(self, cx, cy, rx, ry, colour, texture=0.02, profile="dome", gloss=0.0):
        (x, y), = self.t([(cx, cy)])
        self.s.ellipse(x, y, rx * self.k, ry * self.k, Material(colour, texture=texture * TEXTURE, gloss=gloss, variety=0,
                                                                         shift=SHIFT), profile=profile)

    def stroke(self, points, width, colour, texture=0.02, straight=False):
        self.s.stroke(self.t(points, closed=False, straight=straight), width * self.k, Material(colour, texture=texture * TEXTURE, variety=0, shift=SHIFT))

    def extent(self):
        """The drawing's bounds so far, in the frame's pixels: (left, top, right, bottom)."""
        union = np.zeros(self.s.shapes[0][0].shape, bool)
        for m, *_ in self.s.shapes:
            union |= m
        ys, xs = np.nonzero(union)
        return xs.min() / SS, ys.min() / SS, xs.max() / SS, ys.max() / SS

    def render(self):
        img = self.s.render(outline="tinted")
        size = int((np.asarray(img)[..., 3] > 0).sum())
        # The palette's cap grows with the canvas: a grand building's 160 pixels hold nearly three houses.
        cap = int(PALETTE * (self.size / SIZE) ** 2)
        return limit_palette(img, max(16, min(cap, int(size * DENSITY / 100))))


def box(b, x0, x1, height, wall, side=None, pattern="plaster", side_pattern=None, ground=GROUND, depth=1.0, curve=0.0):
    """The walls: a front from x0 to x1, `height` tall, and the right side going back `depth` of a
    wall's depth; `curve` shades the front round (a tower). Returns the wall's top."""
    top = ground - height
    dx, dy = DX * depth, DY * depth
    # The side going back, turned from the light; the front lit from the upper left, both in the roof's
    # shadow under the eaves and the ground's at their foot.
    b.surface([(x1, ground), (x1 + dx, ground + dy), (x1 + dx, top + dy), (x1, top)], side or wall,
              side_pattern or pattern, tone=-0.4, slope=(-0.004, -0.006), axes=(SIDEWAYS, DOWN), eave=6, foot=4)
    b.surface([(x0, ground), (x1, ground), (x1, top), (x0, top)], wall, pattern, slope=(-0.008, -0.006),
              eave=6, foot=4, curve=curve)
    b.stroke([(x1, ground - 3), (x1, top + 4)], 0.9, shade(wall, 1.12))          # the corner catches the light
    return top


def footing(b, x0, x1, ground=GROUND, depth=1.0, colour="#8f8a86"):
    """A course of stone along the foot of the walls, front and side."""
    dx, dy = DX * depth, DY * depth
    b.surface([(x1, ground + 1), (x1 + dx, ground + 1 + dy), (x1 + dx, ground - 3 + dy), (x1, ground - 3)],
              colour, "blocks", tone=-0.38, axes=(SIDEWAYS, DOWN))
    b.surface([(x0 - 1, ground + 1), (x1, ground + 1), (x1, ground - 3), (x0 - 1, ground - 3)], colour, "blocks")


def gable_roof(b, x0, x1, top, colour, pattern="tiles", rise=20, over=3, depth=1.0):
    """A roof with its gable to the front: the gable wall's triangle (in the wall's own colour, drawn by
    the caller) under a roof whose right plane runs back, and an edge of the left plane."""
    mid = (x0 + x1) / 2
    dx, dy = DX * depth, DY * depth
    apex = (mid, top - rise)
    right_eave = (x1 + over, top + 2)
    # The right plane, its tiles in rows along its eave (running back) and down its slope; it faces
    # right, from the light, so a shade under the front's; lighter toward its ridge.
    down = unit(right_eave[0] - apex[0], right_eave[1] - apex[1])
    b.surface([apex, right_eave, (right_eave[0] + dx, right_eave[1] + dy), (apex[0] + dx, apex[1] + dy)],
              colour, pattern, tone=-0.2, slope=(0.0, -0.006), axes=(SIDEWAYS, down))
    # The barge boards along the gable's two slopes, so the roof's edge reads.
    left_eave = (x0 - over, top + 2)
    b.stroke([left_eave, apex, right_eave], 2.6, colour)
    return apex


def gable(b, x0, x1, top, wall, pattern="plaster", rise=20):
    """The gable end's triangle of wall, over a front wall from x0 to x1."""
    mid = (x0 + x1) / 2
    b.surface([(x0, top + 0.5), (x1, top + 0.5), (mid, top - rise + 1)], wall, pattern, tone=0.04, eave=3)


def eaves_roof(b, x0, x1, top, colour, pattern="tiles", rise=16, over=3, depth=1.0, wall=None, wall_pattern=None):
    """A roof with its eaves to the front: the front plane sloping up and back to the ridge, the gable
    end on the right (in `wall`)."""
    dx, dy = DX * depth, DY * depth
    ridge_l = (x0 - over + dx / 2, top + dy / 2 - rise)
    ridge_r = (x1 + dx / 2, top + dy / 2 - rise)
    if wall:
        b.surface([(x1, top), (x1 + dx, top + dy), ridge_r], wall, wall_pattern or "plaster", tone=-0.38,
                  axes=(SIDEWAYS, DOWN), eave=3)
    # The front plane faces up toward the light: its rows along the eave, its seams down the slope
    # leaning back with it, a little lighter toward the ridge.
    down = unit((x0 - over) - ridge_l[0], (top + 3) - ridge_l[1])
    b.surface([(x0 - over, top + 3), (x1 + over, top + 3), (ridge_r[0] + over, ridge_r[1]), ridge_l],
              colour, pattern, tone=0.14, slope=(-0.004, -0.006), axes=((1.0, 0.0), down))
    # The roof's right edge, down the gable.
    b.stroke([(ridge_r[0] + over * 0.6, ridge_r[1]), (x1 + dx + over * 0.6, top + dy + 2)], 2.4, colour)
    b.stroke([(ridge_l[0], ridge_l[1]), (ridge_r[0] + over, ridge_r[1])], 2.4, shade(colour, 1.1))   # the ridge
    # The roof's thickness along its eave, the edge of the tiles seen from the front, in their shadow.
    b.surface([(x0 - over, top + 3), (x1 + over, top + 3), (x1 + over, top + 5), (x0 - over, top + 5)],
              shade(colour, 0.62), None, tone=-0.1)
    return ridge_l, ridge_r


def window(b, cx, cy, w=8, h=9, frame="#6b4a32", glass="#ffd27a", arched=False, shutters=None, box=None, deep=False):
    """A lit window: frame, warm glass with a cross of glazing bars, a sill; `shutters` a colour,
    `box` a flower box's flowers' colour; `deep`, set back in the wall: the reveal's shadow along its top
    and right inside the frame, and the sill's on the wall under it."""
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
    if deep:
        reveal = shade(frame, 0.55)
        b.poly([(x0, y0 + (2 if arched else 0)), (x1, y0 + (2 if arched else 0)), (x1, y1), (x1 - 1.4, y1),
                (x1 - 1.4, y0 + (3.4 if arched else 1.4)), (x0, y0 + (3.4 if arched else 1.4))], reveal, texture=0.0, profile="flat")
        b.rect(x0 - 1.5, y1 + 2.2, x1 + 2.5, y1 + 3.4, shade(frame, 0.4), texture=0.0, profile="flat")
    b.rect(x0 - 2, y1 + 0.5, x1 + 2, y1 + 2.2, frame, texture=0.03)            # the sill
    if box:
        b.rect(x0 - 1, y1 + 2, x1 + 1, y1 + 5, "#7a5236", texture=0.05)
        for k, x in enumerate(np.linspace(x0, x1, 4)):
            b.ellipse(x, y1 + 1.6, 1.5, 1.3, "#4e9a3a" if k % 2 else box)


def door(b, cx, w=10, h=15, colour="#7a4e2e", ground=GROUND, frame="#5a3a24", arched=True, knob="#e8c050", deep=False):
    """A plank door, arched or square, in a frame, with a step before it; `deep`, set back in the wall,
    the reveal's shadow down its right and under its head."""
    x0, x1, y0 = cx - w / 2, cx + w / 2, ground - h
    if arched:
        arc = [(cx + (w / 2 + 1.2) * math.cos(a), y0 + w / 2 - (w / 2 + 1.2) * math.sin(a)) for a in np.linspace(0, math.pi, 11)]
        b.poly([(x1 + 1.2, ground)] + arc + [(x0 - 1.2, ground)], frame, texture=0.03)
        arc = [(cx + w / 2 * math.cos(a), y0 + w / 2 - w / 2 * math.sin(a)) for a in np.linspace(0, math.pi, 11)]
        b.surface([(x1, ground)] + arc + [(x0, ground)], colour, "boards", texture=0.04, shades=6)
    else:
        b.rect(x0 - 1.2, y0 - 1.2, x1 + 1.2, ground, frame, texture=0.03)
        b.surface([(x0, ground), (x1, ground), (x1, y0), (x0, y0)], colour, "boards", texture=0.04, shades=6)
    if deep:
        reveal = shade(colour, 0.45)
        b.rect(x1 - 2, y0 + (w / 2 if arched else 0), x1, ground, reveal, texture=0.0, profile="flat")
        if arched:
            arc = [(cx + w / 2 * math.cos(a), y0 + w / 2 - w / 2 * math.sin(a)) for a in np.linspace(0, math.pi, 11)]
            inner = [(cx + (w / 2 - 1.8) * math.cos(a), y0 + w / 2 + 0.6 - (w / 2 - 1.8) * math.sin(a)) for a in np.linspace(math.pi, 0, 11)]
            b.poly(arc + inner, reveal, texture=0.0, profile="flat")
        else:
            b.rect(x0, y0, x1, y0 + 1.8, reveal, texture=0.0, profile="flat")
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


def paw_emblem(b, cx, cy):
    b.ellipse(cx, cy + 1.5, 2.6, 2.1, "#5a3a24", profile="flat")
    for dx, dy in ((-2.8, -1.2), (-1, -3), (1, -3), (2.8, -1.2)):
        b.ellipse(cx + dx, cy + dy, 1.0, 1.1, "#5a3a24", profile="flat")


def gem_emblem(b, cx, cy):
    b.poly([(cx - 4, cy - 1), (cx - 2, cy - 3.5), (cx + 2, cy - 3.5), (cx + 4, cy - 1), (cx, cy + 4)], "#5ac8e8", texture=0.0,
           gloss=0.8)
    b.poly([(cx - 2, cy - 3.5), (cx + 2, cy - 3.5), (cx + 1, cy - 1), (cx - 1, cy - 1)], "#bff0ff", texture=0.0, profile="flat")


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
    """A house in a teapot, shaped as one: a squat round body on a foot ring, a painted band round its
    shoulder, a lid with a knob, a spout tapering out and up from low on the body, a looped handle on
    the other side; a door and round windows in the body, steam from the spout."""
    cx, cy = 46, GROUND - 19
    pot, paint, deep = "#f2eee8", "#4a72c8", "#d8d0c4"
    # The handle behind the body: a loop out from the shoulder and back in near the foot.
    loop = [(cx - 19, cy - 9), (cx - 28, cy - 10), (cx - 33, cy - 3), (cx - 31, cy + 6), (cx - 22, cy + 9)]
    b.stroke(loop, 5, deep)
    b.stroke(loop[1:-1], 2.2, pot)
    # The spout, thick at the body and narrowing to its lip, out and up to the right.
    path = [(cx + 17, cy + 6), (cx + 25, cy + 1), (cx + 30, cy - 8), (cx + 34, cy - 19)]
    for (p0, p1), w in zip(zip(path, path[1:]), (8, 6, 4.5)):
        b.stroke([p0, p1], w, pot)
    b.ellipse(cx + 34.5, cy - 19.5, 3, 1.6, deep, profile="flat")                  # its lip
    # The foot ring and the body, round and lit from the upper left, glazed.
    b.ellipse(cx, GROUND - 2, 15, 3, deep)
    b.ellipse(cx, cy, 24, 18, pot, gloss=0.5)
    # A painted band round the shoulder, curving with it, flowers on the belly.
    band = [(cx + 23 * math.cos(t), cy - 6 + 6 * math.sin(t)) for t in np.linspace(math.pi, 0, 17)]
    band += [(cx + 22 * math.cos(t), cy - 3 + 6 * math.sin(t)) for t in np.linspace(0, math.pi, 17)]
    b.poly(band, paint, texture=0.0, tone=0.55)
    for (x, y) in ((cx - 13, cy + 4), (cx + 14, cy + 3)):
        for j in range(5):
            t = j / 5 * 2 * math.pi
            b.ellipse(x + math.cos(t) * 2, y + math.sin(t) * 1.8, 1.4, 1.3, paint, profile="flat")
        b.ellipse(x, y, 1.0, 1.0, "#f8d84a", profile="flat")
    # The lid: a low dome on a rim, and its knob.
    b.ellipse(cx, cy - 16, 13, 4, deep)
    b.ellipse(cx, cy - 18, 11, 6, pot, gloss=0.5)
    b.ellipse(cx, cy - 25, 3, 2.6, paint, gloss=0.6)
    door(b, cx - 1, w=10, h=15, colour="#4a6ab0", frame="#3a5aa0")
    for (x, y) in ((cx - 13, cy - 8), (cx + 12, cy - 9)):                             # round windows
        b.ellipse(x, y, 3.2, 3.2, "#3a5aa0", profile="flat")
        b.ellipse(x, y, 2.2, 2.2, "#ffd27a", profile="flat")
    for (x, y, r) in ((cx + 36, cy - 25, 2.4), (cx + 38, cy - 30, 1.9), (cx + 36, cy - 34, 1.4)):
        b.ellipse(x, y, r, r * 0.8, "#eef0f6", profile="flat")                       # steam


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


# ------------------------------------------------------------------- buildings that belong to a land

def canopy(b, cx, cy, rx, ry, colour, size=7.0, seed=1):
    """Leaves in clusters on a jittered grid, as tools/scenery_art.py's crowns: lighter to the upper left,
    in shadow to the lower right, a paler patch on each lit cluster."""
    rng = np.random.default_rng(seed)
    step = size * 1.1
    spots = []
    for j, gy in enumerate(np.arange(cy - ry, cy + ry + 0.01, step * 0.8)):
        for gx in np.arange(cx - rx + (j % 2) * step / 2, cx + rx + 0.01, step):
            if ((gx - cx) / rx) ** 2 + ((gy - cy) / ry) ** 2 <= 1.05:
                spots.append((gx + rng.uniform(-0.25, 0.25) * size, gy + rng.uniform(-0.2, 0.2) * size))
    for x, y in sorted(spots, key=lambda p: p[1]):
        side = ((x - cx) / rx + (y - cy) / ry) / 2
        k = 1.15 if side < -0.2 else 0.75 if side > 0.3 else 0.95
        r = size * rng.uniform(0.85, 1.1)
        b.ellipse(x, y, r, r * 0.82, shade(colour, k), texture=0.01)
        if side < 0.3:
            b.ellipse(x - r * 0.3, y - r * 0.3, r * 0.45, r * 0.36, shade(colour, k * 1.15), texture=0.0, profile="flat")


def gores(b, apex, base_l, base_r, colours, n=8, bulge=4.0):
    """A tent's cloth from its peak to the ground, in `n` gores of alternating colour, each bellying out."""
    (ax, ay), (lx, ly), (rx, ry) = apex, base_l, base_r
    for k in range(n):
        t0, t1 = k / n, (k + 1) / n
        x0, x1 = lx + (rx - lx) * t0, lx + (rx - lx) * t1
        y0, y1 = ly + (ry - ly) * t0, ly + (ry - ly) * t1
        mid = (t0 + t1) / 2
        # A gore's hem sags between its seams; the side away from the light a step darker.
        sag = [(x0 + (x1 - x0) * u, y0 + (y1 - y0) * u + math.sin(u * math.pi) * 1.5) for u in np.linspace(0, 1, 5)]
        colour = colours[k % len(colours)]
        b.surface([(ax, ay)] + sag, colour, "plaster", tone=0.08 - 0.3 * mid, texture=0.02, shades=6)
        # the seam
        b.stroke([(ax, ay), (x1, y1)], 0.9, shade(colours[0], 0.6))


def pavilion_tent(b):
    """A big striped desert pavilion: gores from a gilded peak, the flap tied open on a dark inside, a
    rug laid out before it, guy ropes to pegs."""
    apex, left, right = (48, 22), (12, GROUND - 2), (84, GROUND - 2)
    for (x, y) in ((6, GROUND), (90, GROUND)):
        b.stroke([(x, y), (apex[0] + (x - apex[0]) * 0.5, apex[1] + 22)], 0.7, "#c8b088")
        b.ellipse(x, y, 1.2, 0.9, "#6a4a2e")
    gores(b, apex, left, right, ["#e8a23a", "#f2e6c8"], n=9)
    # A valance of scallops round the eave line.
    for k in range(10):
        x = 18 + k * 6.4
        b.ellipse(x, 44 + abs(x - 48) * 0.36, 3.6, 2.4, "#c8423a" if k % 2 else "#2e8a8a", profile="flat")
    # The open flap: a dark inside, its two flaps tied back.
    b.poly([(48, 50), (58, GROUND - 1), (38, GROUND - 1)], "#3a2420", texture=0.0)
    b.poly([(48, 50), (38, GROUND - 1), (34, GROUND - 1), (44, 56)], "#f2e6c8", texture=0.02)
    b.poly([(48, 50), (58, GROUND - 1), (62, GROUND - 1), (52, 56)], "#e8a23a", texture=0.02)
    b.ellipse(48, 19, 2.6, 3.4, "#f0c040", gloss=0.8)
    b.stroke([(48, 16), (48, 10)], 0.8, "#c89a2a")
    b.poly([(48, 10), (55, 12), (48, 14)], "#c8423a", texture=0.0)                        # a pennant
    b.surface([(30, GROUND + 4), (66, GROUND + 4), (62, GROUND - 1), (34, GROUND - 1)], "#a8322e", "blocks", tone=0.0)


def yurt(b):
    """A round felt yurt for the steppe: cream walls banded in red, a low cone roof roped down, a painted
    door, smoke from the crown."""
    cx, r = 48, 30
    wall = [(cx - r, 58)] + [(cx + r * math.cos(a), GROUND - 4 + 5 * math.sin(a)) for a in np.linspace(math.pi, 0, 17)] + [(cx + r, 58)]
    b.surface(wall, "#e8dcc0", "plaster", slope=(-0.009, 0.0))
    for y in (64, 76):                                                                      # felt bands
        band = [(cx - r, y)] + [(cx + r * math.cos(a), y + 5 * math.sin(a)) for a in np.linspace(math.pi, 0, 17)]
        band += [(cx + r * math.cos(a), y + 3 + 5 * math.sin(a)) for a in np.linspace(0, math.pi, 17)]
        b.poly(band, "#b83a32", texture=0.02, tone=0.55)
    roof = [(cx + (r + 3) * math.cos(a), 58 + 6 * math.sin(a)) for a in np.linspace(0, math.pi, 17)]
    b.surface([(cx + 6, 30), (cx - 6, 30)] + roof[::-1], "#d8c8a4", "thatch", slope=(-0.01, 0.006))
    for a in np.linspace(0.15, math.pi - 0.15, 7):                                         # the roof's ropes
        b.stroke([(cx + 6 * math.cos(a), 30 + 1), (cx + (r + 2) * math.cos(a), 58 + 6 * math.sin(a))], 0.8, "#7a5a3a")
    b.ellipse(cx, 30, 7, 2.2, "#7a5a3a", profile="flat")
    b.rect(cx - 6, GROUND - 22, cx + 6, GROUND, "#c8642a", texture=0.03)                   # the door
    b.rect(cx - 4.5, GROUND - 20, cx + 4.5, GROUND - 1, "#e88a3a", texture=0.02)
    b.stroke([(cx, GROUND - 20), (cx, GROUND - 1)], 0.8, "#a84a2a")
    for (x, y, rr) in ((cx + 2, 24, 2.6), (cx + 5, 18, 2.0), (cx + 9, 13, 1.5)):
        b.ellipse(x, y, rr, rr * 0.8, "#e8e8f0", profile="flat")


def dome_house(b):
    """A sandstone house with an onion dome: a gilt spire, an arched door and lattice windows."""
    x0, x1 = 22, 62
    top = box(b, x0, x1, 34, "#e2c69a", pattern="blocks", depth=0.9)
    b.surface([(x0 - 2, top), (x1 + 2, top), (x1 + 2 + DX * 0.9, top + DY * 0.9), (x0 - 2 + DX * 0.9, top + DY * 0.9)],
              "#d8b888", "blocks", tone=0.1)                                              # the flat roof
    cx = (x0 + x1) / 2 + DX * 0.45
    b.surface([(cx - 10, top - 2), (cx + 10, top - 2), (cx + 10, top - 7), (cx - 10, top - 7)], "#e2c69a", "blocks")
    base = top - 7
    half = [(10, 0), (13, 4), (14, 9), (12, 14), (7.5, 19), (3.5, 23), (0, 27)]          # the onion's profile
    dome = [(cx - w, base - h) for w, h in half] + [(cx + w, base - h) for w, h in half[::-1]]
    b.surface(dome, "#2e9a9a", "tiles", slope=(-0.016, 0.0))
    b.stroke([(cx, top - 26), (cx, top - 34)], 1.2, "#e8c050")
    b.ellipse(cx, top - 35, 1.6, 1.6, "#f0c040", gloss=0.8)
    door(b, x0 + 13, w=10, h=17, colour="#2e7a8a", frame="#a8885a")
    for x in (x1 - 8,):
        window(b, x, top + 12, w=7, h=10, frame="#a8885a", glass="#f8c86a", arched=True)
    window(b, x0 + 13, top + 6, w=6, h=5, frame="#a8885a", glass="#f8c86a", arched=True)
    for x in (x0 + 2, x1 - 2):                                                             # pots by the walls
        b.ellipse(x, GROUND - 2, 2.6, 3, "#c86a3a")


def market_tent(b):
    """A bazaar stall: a striped canopy on four poles over a counter of pots, rugs and fruit."""
    for x in (20, 70):
        b.stroke([(x, GROUND), (x, 42)], 1.6, "#6a4a2e")
    for x in (28, 78):
        b.stroke([(x, GROUND - 7), (x, 37)], 1.4, "#5a3e26")
    b.surface([(18, 64), (72, 64), (80, 58), (26, 58)], "#b07a4a", "planks", tone=0.04)          # the counter top
    b.surface([(18, 64), (72, 64), (72, GROUND), (18, GROUND)], "#8a5a34", "boards")
    b.surface([(72, 64), (80, 58), (80, GROUND - 6), (72, GROUND)], "#8a5a34", "boards", tone=-0.36)
    for k, (x, c) in enumerate(((24, "#c86a3a"), (31, "#2e8a8a"), (38, "#c86a3a"))):          # pots
        b.ellipse(x, 58, 3, 3.4, c)
        b.ellipse(x, 54.6, 1.6, 0.8, shade(c, 0.6), profile="flat")
    for k, x in enumerate(np.arange(46, 66, 3.2)):                                           # fruit
        b.ellipse(x, 59, 1.7, 1.6, "#f0a020" if k % 2 else "#d83a3a")
    b.rect(52, 64, 66, 78, "#a8322e", texture=0.02, profile="flat")                        # a rug hung over it
    for y in (67, 71, 75):
        b.stroke([(52, y), (66, y)], 0.9, "#f0c040")
    # The canopy, striped, sloping down to the front with a scalloped hem.
    n = 9
    for k in range(n):
        a, c = 16 + 58 * k / n, 16 + 58 * (k + 1) / n
        col = "#f2e6c8" if k % 2 else "#2e8a8a"
        b.poly([(a + 12, 30), (c + 12, 30), (c, 44), (a, 44)], col, tone=0.62)
        b.ellipse((a + c) / 2, 44, (c - a) / 2, 1.8, col, profile="flat")
    b.poly([(74, 44), (86, 30), (86, 33), (75, 46)], "#d8cfb4", tone=0.4)


def tree_house(b):
    """A fairy tree house: a great trunk with roots, a cottage on a platform in its branches under the
    leaves, a ladder up to it and a lantern."""
    bark = "#7a5a46"
    b.stroke([(48, GROUND), (49, 60), (47, 40)], 13, bark)
    for (x, y) in ((34, GROUND + 1), (62, GROUND + 1), (40, GROUND + 2), (57, GROUND + 2)):
        b.stroke([(48, GROUND - 6), (x, y)], 5, bark)
    b.stroke([(47, 44), (30, 34), (20, 30)], 5, bark)
    b.stroke([(48, 42), (66, 33), (76, 30)], 5, bark)
    canopy(b, 48, 18, 34, 13, "#5aa86a", size=7.5, seed=8)
    b.surface([(24, 46), (72, 46), (72, 49), (24, 49)], "#9a6a44", "planks")                  # the platform
    top = box(b, 32, 60, 15, "#c8945a", pattern="planks", ground=46, depth=0.6)
    eaves_roof(b, 32, 60, top, "#b85a8a", "tiles", rise=9, over=3, depth=0.6)
    door(b, 40, w=6, h=10, colour="#5a7a3a", ground=46)
    window(b, 52, top + 7, w=5, h=5, arched=True)
    for (x, c) in ((24, "#3a2a20"), (72, "#3a2a20")):
        b.stroke([(x, 49), (x, 58)], 1.0, c)
    b.stroke([(26, 49), (24, 57), (72, 57), (70, 49)], 1.1, "#c8b088")                       # a rope rail
    for x in (27, 32):                                                                      # the ladder
        b.stroke([(x, 49), (x - 3, GROUND)], 1.4, "#8a6a4a")
    for y in np.arange(54, GROUND, 6.5):
        t = (y - 49) / (GROUND - 49)
        b.stroke([(27 - 3 * t, y), (32 - 3 * t, y)], 1.3, "#8a6a4a")
    b.stroke([(66, 46), (66, 52)], 0.6, "#3a3036")
    b.ellipse(66, 54, 1.8, 2.2, "#ffd06a", profile="flat")                                  # a lantern


def bluebell_house(b):
    """A house in a bluebell: the flower's bell standing on the ground, flaring to a scalloped rim, its
    stalk arching up over it from behind; a door under the rim, leaves at its foot."""
    b.stroke([(66, GROUND), (72, 44), (64, 16), (50, 12)], 3.4, "#4e8a3a")                   # the stalk
    side = [(0, 0), (6, 3), (11, 10), (14, 22), (16, 36), (19, 50), (24, 60), (26, 64)]       # the bell's profile
    top, cx = 18, 48
    bell = [(cx - w, top + h) for w, h in side[::-1]] + [(cx + w, top + h) for w, h in side]
    b.surface(bell[len(side):] + bell[:len(side)], "#6a7ae0", "plaster", slope=(-0.014, 0.002))
    for k in range(7):                                                                      # the scalloped rim
        x = cx - 24 + k * 8
        b.ellipse(x, top + 64, 4.4, 2.6, "#8a9af0" if x < cx else "#5a6ad0", profile="flat")
    for x in (-10, -4, 4, 10):                                                              # its veins
        b.stroke([(cx + x * 0.3, top + 6), (cx + x * 1.6, top + 58)], 0.9, "#4a5ac0")
    b.ellipse(cx, top - 1, 2.6, 2, "#4e8a3a")
    door(b, cx, w=10, h=14, colour="#f0d8a0", frame="#4a5ac0")
    window(b, cx - 9, top + 34, w=5, h=6, arched=True, frame="#4a5ac0")
    window(b, cx + 8, top + 30, w=5, h=6, arched=True, frame="#4a5ac0")
    for (x, lean) in ((26, -1), (70, 1)):                                                   # leaves at its foot
        b.poly([(x - 7, GROUND), (x + lean * 6, GROUND - 16), (x + 7, GROUND)], "#5aa84a", profile="dome")


def crystal_cottage(b):
    """A little stone cottage the star's crystals have grown through: spires out of its roof and wall,
    glowing windows."""
    x0, x1 = 24, 60
    top = box(b, x0, x1, 24, "#a8a0b8", pattern="blocks")
    footing(b, x0, x1, colour="#7a7488")
    eaves_roof(b, x0, x1, top, "#5a4a8a", "slate", rise=14, over=3, wall="#a8a0b8", wall_pattern="blocks")
    def spire(x, y, h, w, colour):
        b.poly([(x - w, y), (x, y - h), (x + w * 0.2, y)], shade(colour, 1.2), tone=0.85)
        b.poly([(x + w * 0.2, y), (x, y - h), (x + w, y)], shade(colour, 0.85), tone=0.45)
    spire(38, top - 6, 22, 4.5, "#8ad8f0")
    spire(46, top - 9, 15, 3.4, "#c8a0f0")
    spire(70, GROUND - 2, 26, 5, "#8ad8f0")
    spire(76, GROUND - 1, 14, 3.4, "#c8a0f0")
    spire(18, GROUND, 12, 3.2, "#8ad8f0")
    door(b, x0 + 10, w=9, h=14, colour="#4a6ab0")
    window(b, x1 - 9, top + 10, w=7, h=8, glass="#a8f0ff", frame="#5a4a8a")



def by_hand(draw):
    """Marks a drawing to be drawn with its edges off the ruler (`Build.bend`), as RD's houses are."""
    draw.organic = 1.2
    return draw


def grounds(b, x0, x1, colour="#6a9a40", stone="#9a948a", path=None, earth="#c8a878", seed=3):
    """The patch of ground a building stands on, as RD's do: a rounded spread of ground a little wider than
    its walls, tufts round its edge, a few stones, and a path of trodden earth from its door (`path`, the
    door's x)."""
    rng = np.random.default_rng(seed)
    cx, rx = (x0 + x1) / 2 + 3, (x1 - x0) / 2 + 9
    b.poly([(cx + rx * math.cos(t), GROUND + 1 + 5 * math.sin(t)) for t in np.linspace(0, 2 * math.pi, 28)[:-1]], colour,
           texture=0.05, profile="flat", tone=0.55)
    if path is not None:
        b.poly([(path - 4, GROUND), (path + 4, GROUND), (path + 6, GROUND + 5.5), (path - 6, GROUND + 5.5)], earth,
               texture=0.04, profile="flat", tone=0.6)
    for t in np.linspace(0.15, 2 * math.pi - 0.15, 9):
        if math.sin(t) < -0.2:
            continue
        x, y = cx + (rx - 1) * math.cos(t), GROUND + 1 + 4.5 * math.sin(t)
        b.stroke([(x, y), (x + rng.uniform(-1, 1), y - rng.uniform(2, 3.5))], 1.0, shade(colour, 0.8))
    for k in range(3):
        t = rng.uniform(0.3, math.pi - 0.3)
        b.ellipse(cx + (rx - 3) * math.cos(t) * rng.choice([-1, 1]), GROUND + 2 + 2.5 * math.sin(t), 1.6, 1.1, stone)


@by_hand
def acorn_cottage(b):
    """A cottage in an acorn, modelled as RD would (2026-10-25, the user: the first "looks too 2
    dimensional"): the nut an egg shaded round, its staves curving with it, its foot curving into its
    patch of ground; the cap a dome of scales, lit on top, its rolled rim curving down in front and
    throwing its shadow on the nut; a twig and a leaf on top, a little stovepipe and a round dormer in
    the cap, a deep arched door and a round window, its shadow on the grass."""
    cx, nut, cap = 48, "#c07a42", "#9a7a4a"
    top, rim = 42, 47
    grounds(b, 14, 80, colour="#6a9a40", path=cx - 5)
    ground_shadow(b, 36, 62, 26)

    def porthole(x, y, rx, ry):
        """A round window set deep: its wooden frame, warm lamplit glass with a cross of bars, the
        frame's shadow along its top inside."""
        b.ellipse(x, y, rx + 1.6, ry + 1.5, "#5a3a24", texture=0.02)
        # Lamplight a deep amber, held at one bright tone: a pale yellow on the ramp came out tan and
        # merged into the cap's colours when the palette was cut down.
        b.poly(oval(x, y, rx, ry, 0, 2 * math.pi, 21), "#ffb830", texture=0.0, profile="flat", tone=0.72)
        b.poly(oval(x, y, rx, ry, math.pi * 1.15, math.pi * 1.85) + oval(x, y + 1.2, rx * 0.9, ry * 0.75, math.pi * 1.85, math.pi * 1.15),
               "#b06a20", texture=0.0, profile="flat", tone=0.5)
        b.rect(x - 0.45, y - ry + 1, x + 0.45, y + ry, "#5a3a24", texture=0.0)
        b.rect(x - rx, y - 0.45, x + rx, y + 0.45, "#5a3a24", texture=0.0)

    def half(t):
        """The nut's half-width from its top (0) to its foot (1): an egg, widest a third of the way down."""
        return 26 * math.sqrt(max(0.0, 1 - ((t - 0.3) / 0.85) ** 2))

    foot_r = half(1.0)
    ts = np.linspace(0, 1, 15)
    left = [(cx - half(t), top + t * (GROUND - top)) for t in ts]
    right = [(cx + half(t), top + t * (GROUND - top)) for t in ts[::-1]]
    body = left + oval(cx, GROUND, foot_r, foot_r * TILT, math.pi, 0)[1:-1] + right
    b.surface(body, nut, "plaster", curve=1.2, slope=(-0.004, -0.009), foot=7, gloss=0.25)
    # Its staves, curving round it as it rounds (the middle ones straight, the outer ones bowed).
    for k in (-0.78, -0.45, -0.12, 0.22, 0.55, 0.85):
        pts = [(cx + k * half(t), top + t * (GROUND - top) + 3.2 * TILT * math.sqrt(max(0.0, 1 - k * k)) * t)
               for t in np.linspace(0.12, 0.97, 9)]
        b.stroke(pts, 0.8, shade(nut, 0.78 if k > 0 else 0.86))
    # The cap's shadow on the nut, under its rim: a band curving with it.
    r0 = half((rim - top) / (GROUND - top)) + 1
    b.poly(oval(cx, rim + 5.5, r0, r0 * TILT, math.pi, 0) + oval(cx, rim + 1, r0, r0 * TILT, 0, math.pi), shade(nut, 0.5),
           texture=0.0, profile="flat")
    # The cap: a dome of scales, lit on top, darker down to its rim.
    R, rise = 30, 23
    b.surface(oval(cx, rim, R, R * TILT, 0, math.pi) + oval(cx, rim, R, rise, math.pi, 2 * math.pi, 25)[1:-1], cap, "shingles",
              curve=1.0, slope=(-0.004, -0.012))
    b.stroke(oval(cx, rim + 0.5, R + 0.5, R * TILT + 0.3, 0.05, math.pi - 0.05, 23), 3.2, shade(cap, 0.92))   # the rolled rim
    porthole(cx - 13, rim - 11, 3.8, 3.4)                                         # a dormer in the cap
    # A little stovepipe out of the cap, made, so straight.
    px = cx + 15
    b.poly([(px - 2, rim - 8), (px + 2, rim - 8), (px + 2, rim - 22), (px - 2, rim - 22)], "#6e6a78", texture=0.0, profile="cylinder",
           straight=True)
    b.poly([(px - 3.2, rim - 22), (px + 3.2, rim - 22), (px + 2.4, rim - 25), (px - 2.4, rim - 25)], "#5a5664", texture=0.0,
           profile="cylinder", straight=True)
    # The twig on top, and its leaf.
    peak = rim - rise
    b.stroke([(cx + 1, peak + 3), (cx + 2, peak - 3), (cx + 6, peak - 8)], 3.0, "#6a4a2e")
    b.poly([(cx + 6, peak - 8), (cx + 11, peak - 12.5), (cx + 17, peak - 11), (cx + 12, peak - 7.5)], "#6aa84a", texture=0.02)
    b.stroke([(cx + 6.5, peak - 8.2), (cx + 15, peak - 10.8)], 0.7, "#4e8a3a")
    door(b, cx - 5, w=11, h=18, colour="#6a8a3a", frame="#5a3a24", ground=GROUND + 3, deep=True)
    porthole(cx + 10, 63, 4.6, 4.8)
    flowers(b, cx + 16, cx + 26, GROUND + 2, ["#f8d84a", "#b88ae0"], seed=5)
    flowers(b, cx - 26, cx - 18, GROUND + 1.5, ["#f0a0c8", "#f8d84a"], seed=8)


@by_hand
def lake_shrine(b):
    """Liora's shrine on Briarmere's shore, the Temple Keeper's, all that's left above the ice of the
    Tidewater Shrine: a little temple of pale stone on two broad steps, four stout columns under a deep
    pediment with a silver bell in its round, a slate roof heaped with snow, icicles along its eave,
    Liora's statue in the dark between its columns, a blue lantern at each front corner, all on a patch
    of snow."""
    stone, marble, slate, snow = "#b8bac2", "#d6dae2", "#4a5a7a", "#eef3fc"
    grounds(b, 14, 74, colour="#e4ecf6", stone="#a8acb8", path=44, earth="#ccd6e4")
    for k, (x0, x1) in enumerate(((14, 74), (19, 69))):
        g = GROUND - 4 * k
        b.surface([(x1, g), (x1 + DX * 0.6, g + DY * 0.6), (x1 + DX * 0.6, g - 4 + DY * 0.6), (x1, g - 4)], stone, "rubble",
                  tone=-0.4, axes=(SIDEWAYS, DOWN))
        b.surface([(x0, g), (x1, g), (x1, g - 4), (x0, g - 4)], stone, "rubble", slope=(-0.006, 0.0))
        b.poly([(x0, g - 4), (x1, g - 4), (x1 + DX * 0.6, g - 4 + DY * 0.6), (x0 + DX * 0.6, g - 4 + DY * 0.6)], snow,
               texture=0.02, profile="flat", tone=0.8)
    floor = GROUND - 8
    top = box(b, 24, 64, 26, stone, pattern="rubble", ground=floor, depth=0.6)
    b.rect(26, top + 3, 62, floor, "#2e3448", texture=0.0, profile="flat", tone=0.3)
    b.ellipse(44, floor - 11, 6, 8, "#4a6a9a", texture=0.0, profile="flat")
    b.rect(40.5, floor - 5, 47.5, floor, marble, texture=0.04)
    b.poly([(44, floor - 17), (47.5, floor - 6), (40.5, floor - 6)], "#d8dce6", texture=0.03)
    b.poly([(43, floor - 14), (38, floor - 18), (39.5, floor - 10)], "#d8dce6", texture=0.02)
    b.poly([(45, floor - 14), (50, floor - 18), (48.5, floor - 10)], "#d8dce6", texture=0.02)
    b.ellipse(44, floor - 18, 2.0, 2.0, "#e4e8f0", texture=0.0)
    for x in (25.5, 36.5, 47, 57.5):                                    # stout columns, a base and a capital each
        b.poly([(x, floor - 1.5), (x + 5, floor - 1.5), (x + 5, top + 4), (x, top + 4)], marble, texture=0.03,
               profile="cylinder")
        b.rect(x - 1.2, floor - 2.5, x + 6.2, floor, stone, texture=0.03)
        b.rect(x - 1.2, top + 2, x + 6.2, top + 5, stone, texture=0.03)
    b.surface([(20, top + 3), (68, top + 3), (68, top - 3), (20, top - 3)], marble, "rubble", tone=0.06)
    b.surface([(68, top + 3), (68 + DX * 0.6, top + 3 + DY * 0.6), (68 + DX * 0.6, top - 3 + DY * 0.6), (68, top - 3)], stone,
              "rubble", tone=-0.38, axes=(SIDEWAYS, DOWN))
    for x, length in ((23, 3), (30, 2), (39, 3.5), (51, 2.5), (60, 3), (66, 2)):
        b.stroke([(x, top + 3.5), (x, top + 3.5 + length)], 1.1, "#d8f0ff", texture=0.0)
    gable(b, 20, 68, top - 3, marble, "rubble", rise=17)
    gable_roof(b, 20, 68, top - 3, slate, "shingles", rise=17, over=5, depth=0.6)
    apex = (44, top - 20)
    b.ellipse(44, top - 10, 4.6, 4.0, "#9aa8c0", texture=0.0)
    b.ellipse(44, top - 10, 3.5, 3.0, "#5a6a8a", texture=0.0, profile="flat")
    b.poly([(44, top - 12.8), (46.2, top - 8.2), (41.8, top - 8.2)], "#e0e6f0", gloss=0.7)
    b.ellipse(44, top - 7.4, 0.9, 0.8, "#e8c050", gloss=0.6)
    right_eave = (68 + 5, top - 1)
    lip = (apex[0] + (right_eave[0] - apex[0]) * 0.85, apex[1] + (right_eave[1] - apex[1]) * 0.85)
    b.poly([apex, (apex[0] + DX * 0.6, apex[1] + DY * 0.6), (lip[0] + DX * 0.6, lip[1] + DY * 0.6 + 1.5),
            (lip[0] + DX * 0.3, lip[1] + DY * 0.3 + 0.4), (lip[0], lip[1] + 1.8)], snow, texture=0.03, tone=0.62)
    b.stroke([(20 - 5, top - 1.5), apex, right_eave], 2.2, snow, texture=0.0)
    b.ellipse(apex[0], apex[1] - 0.8, 3.4, 1.8, snow, texture=0.0)
    for x in (12, 76):
        b.stroke([(x, GROUND + 1), (x, GROUND - 11)], 1.6, "#4a4250")
        b.ellipse(x, GROUND - 14.5, 2.8, 3.4, "#3a3a48", texture=0.0)
        b.ellipse(x, GROUND - 14.5, 1.7, 2.3, "#8ad8ff", texture=0.0, profile="flat")
        b.ellipse(x, GROUND - 18.2, 3.0, 1.4, snow, texture=0.0)
    return b


def grand(size):
    """Marks a drawing as a grand building, drawn on a `size`-pixel canvas (a house's is 96): a guild hall
    that should stand over the town's cottages. maps.json gives it the room (its building's `size`)."""
    def mark(draw):
        draw.size = size
        return draw
    return mark


def crenels(b, x0, x1, top, colour, every=4.0):
    """Battlements along a tower's or a wall's top: merlons `every` pixels with gaps between."""
    x = x0
    while x + every * 0.6 <= x1 + 0.01:
        b.rect(x, top - 3.5, x + every * 0.6, top + 0.5, colour, texture=0.04)
        x += every


def pennant(b, x, top, colour, length=9):
    """A pennant on a pole standing up from `top` at `x`, flying to the right."""
    b.stroke([(x, top), (x, top - 12)], 1.0, "#5a4a3e")
    b.poly([(x, top - 12), (x + length, top - 10), (x, top - 7.5)], colour, texture=0.02)


@by_hand
@grand(160)
def warrior_guild(b):
    """The Warrior Guild's hall, Captain Brann's, the grandest thing in Meadowbrook: a tall hall of rough
    stone, two storeys under a steep red gable with the guild's shield on crossed swords in it, flanked
    by two crenellated towers flying red pennants, a great arched double door in a stone surround up two
    steps, tall arched windows and red banners, a rack of spears and a training dummy on its forecourt."""
    stone, red = "#b4aca4", "#b8443a"
    grounds(b, 8, 86, path=47)
    b.surface([(36, GROUND + 4), (58, GROUND + 4), (55, GROUND - 1), (39, GROUND - 1)], "#b8b0a4", "rubble", tone=0.1)
    for x0, x1 in ((8, 24), (70, 86)):                                          # the towers, behind the hall
        top = box(b, x0, x1, 48, stone, pattern="rubble", depth=0.5)
        crenels(b, x0 - 0.5, x1 + 0.5, top, stone)
        b.rect((x0 + x1) / 2 - 0.8, top + 12, (x0 + x1) / 2 + 0.8, top + 19, "#2a2630", texture=0.0)
        b.rect((x0 + x1) / 2 - 0.8, top + 28, (x0 + x1) / 2 + 0.8, top + 34, "#2a2630", texture=0.0)
        pennant(b, (x0 + x1) / 2, top - 3.5, red)
    x0, x1 = 24, 70
    cx = (x0 + x1) / 2
    top = box(b, x0, x1, 32, stone, pattern="rubble", depth=0.6)
    footing(b, x0, x1, colour="#7e7872", depth=0.6)
    gable(b, x0, x1, top, stone, "rubble", rise=26)
    gable_roof(b, x0, x1, top, red, "shingles", rise=26, over=5, depth=0.6)
    for a, c in (((cx - 8, top - 4), (cx + 8, top - 18)), ((cx + 8, top - 4), (cx - 8, top - 18))):
        b.stroke([a, c], 1.8, "#d8dee8")                                         # the crest: swords and shield
    b.poly([(cx - 6, top - 17), (cx + 6, top - 17), (cx + 6, top - 10), (cx, top - 3.5), (cx - 6, top - 10)], "#b8302c",
           texture=0.0)
    b.stroke([(cx, top - 16), (cx, top - 5.5)], 1.2, "#e8c050")
    b.stroke([(cx - 4.5, top - 12.5), (cx + 4.5, top - 12.5)], 1.2, "#e8c050")
    b.rect(x0 - 1, top + 13, x1 + 1, top + 15, "#c8c0b4", texture=0.03)          # a string course between storeys
    for x in (x0 + 8, x1 - 8):                                                    # tall arched windows upstairs
        window(b, x, top + 7, w=6, h=9, frame="#5a4a40", arched=True)
    arc = [(cx + 11 * math.cos(a), GROUND - 22 + 11 - 11 * math.sin(a)) for a in np.linspace(0, math.pi, 13)]
    b.poly([(cx + 11, GROUND - 2)] + arc + [(cx - 11, GROUND - 2)], "#c8c0b4", texture=0.04)    # the stone surround
    door(b, cx, w=16, h=20, colour="#6a3e24", frame="#4a3a34", ground=GROUND - 2)
    b.stroke([(cx, GROUND - 3), (cx, GROUND - 18)], 0.9, "#3a2418")
    for k, (a_, c_) in enumerate(((cx - 13, cx + 13), (cx - 15, cx + 15))):         # two steps up to it
        b.rect(a_, GROUND - 2 + k * 2, c_, GROUND + k * 2, "#9a948c", texture=0.04)
    for x in (x0 + 7, x1 - 7):                                                    # banners down the walls
        b.poly([(x - 3.5, top + 17), (x + 3.5, top + 17), (x + 3.5, top + 30), (x, top + 33), (x - 3.5, top + 30)], "#b8302c",
               texture=0.03)
        b.stroke([(x - 4.5, top + 17), (x + 4.5, top + 17)], 1.4, "#e8c050")
        b.ellipse(x, top + 23, 1.9, 1.9, "#e8c050", gloss=0.5)
    for x in (13, 16, 19):                                                        # a rack of spears
        b.stroke([(x, GROUND + 2), (x, GROUND - 20)], 1.3, "#8a5a2a")
        b.poly([(x - 1.5, GROUND - 20), (x + 1.5, GROUND - 20), (x, GROUND - 24.5)], "#d8dee8", texture=0.0)
    b.stroke([(11, GROUND - 8), (21, GROUND - 8)], 1.6, "#6a4a2e")
    dx = 80                                                                       # the training dummy
    b.stroke([(dx, GROUND + 3), (dx, GROUND - 15)], 1.6, "#6a4a2e")
    b.stroke([(dx - 5.5, GROUND - 11), (dx + 5.5, GROUND - 11)], 1.4, "#6a4a2e")
    b.ellipse(dx, GROUND - 8, 3.8, 5.4, "#d8b860", texture=0.06)
    b.ellipse(dx, GROUND - 16, 2.7, 2.7, "#d8b860")
    return b


@by_hand
@grand(160)
def wildfolk_lodge(b):
    """The Wildfolk Lodge, the tamers' guild, Ranger Pip's: a great lodge of round logs under a steep mossy
    roof, a great pair of antlers on its gable over a round window with a paw on it, a porch on log posts
    before its door, a stable wing on its side with hay in its door, a carved totem of beasts beside it and
    a little pen, on a patch of grass with a path to the porch."""
    log, moss = "#b88250", "#6a8a3e"
    grounds(b, 10, 86, path=38)
    wx0, wx1 = 58, 82                                                             # the stable wing, behind
    wtop = box(b, wx0, wx1, 16, log, pattern="planks", depth=0.6)
    gable_roof(b, wx0, wx1, wtop, moss, "shingles", rise=13, over=3, depth=0.6)
    gable(b, wx0, wx1, wtop, log, "planks", rise=13)
    b.rect(wx0 + 7, GROUND - 13, wx1 - 7, GROUND, "#5a3a22", texture=0.0)
    b.surface([(wx0 + 8, GROUND), (wx1 - 8, GROUND), (wx1 - 8, GROUND - 12), (wx0 + 8, GROUND - 12)], "#8a5a34", "boards")
    b.ellipse((wx0 + wx1) / 2, GROUND - 2, 4.5, 2.4, "#e0c060", texture=0.06)
    x0, x1 = 18, 58
    cx = (x0 + x1) / 2
    top = box(b, x0, x1, 24, log, pattern="planks", depth=0.6)
    for y in np.arange(top + 2, GROUND - 2, 3):                                   # the logs' ends at its corners
        b.ellipse(x0, y, 2.0, 1.6, "#d8a46a", profile="flat")
        b.ellipse(x1 + 0.5, y, 2.0, 1.6, "#d8a46a", profile="flat")
    footing(b, x0, x1, colour="#857e74", depth=0.6)
    gable(b, x0, x1, top, log, "planks", rise=32)
    gable_roof(b, x0, x1, top, moss, "shingles", rise=32, over=6, depth=0.6)
    b.ellipse(cx, top - 11, 5.5, 5.5, "#7a5232", texture=0.03)                    # the round window, a paw on it
    b.ellipse(cx, top - 11, 4.2, 4.2, "#ffd27a", texture=0.0, profile="flat")
    paw_emblem(b, cx, top - 11)
    antler = "#efe2c4"
    for side in (-1, 1):                                                          # the great antlers over it
        b.stroke([(cx + side * 2, top - 22), (cx + side * 9, top - 28), (cx + side * 11, top - 35)], 1.6, antler)
        b.stroke([(cx + side * 5.5, top - 25), (cx + side * 5, top - 31)], 1.3, antler)
        b.stroke([(cx + side * 9, top - 28), (cx + side * 14, top - 30)], 1.3, antler)
        b.stroke([(cx + side * 10.5, top - 32), (cx + side * 15, top - 35)], 1.2, antler)
    b.ellipse(cx, top - 22, 2.8, 2.4, "#8a6a4a")
    window(b, x0 + 7, top + 9, w=6, h=7, frame="#4a3020", box="#f0c040")
    window(b, x1 - 7, top + 9, w=6, h=7, frame="#4a3020", box="#e05a7a")
    door(b, cx, w=11, h=15, colour="#6a4426", frame="#4a3020")
    for x in (cx - 10, cx + 10):                                                  # the porch on log posts
        b.stroke([(x, GROUND), (x, GROUND - 19)], 2.2, "#9a6a3e")
    b.poly([(cx - 13, GROUND - 18), (cx + 13, GROUND - 18), (cx + 11, GROUND - 24), (cx - 11, GROUND - 24)], moss, texture=0.03)
    sign(b, cx + 12, GROUND - 17, paw_emblem, board="#c8945a")
    totem = [("#8a5a34", "#e8c050"), ("#5a7aa8", "#f0f0e8"), ("#a8483a", "#f0f0e8")]  # a totem: owl, wolf, bear
    for k, (wood, eye) in enumerate(totem):
        y = GROUND - 7 - k * 7
        b.rect(7, y - 6.5, 15, y, wood, texture=0.03)
        for ex in (9.3, 12.7):
            b.ellipse(ex, y - 4, 1.0, 1.0, eye, profile="flat")
        b.rect(9.5, y - 2.2, 12.5, y - 1.2, "#2a1e18", texture=0.0)
    b.poly([(4, GROUND - 26), (11, GROUND - 23), (18, GROUND - 26), (11, GROUND - 21)], "#e8c050", texture=0.02)   # its wings
    for x in (68, 74, 80, 86):                                                    # the pen
        b.stroke([(x, GROUND + 4), (x, GROUND - 3)], 1.3, "#7a5232")
    for y in (GROUND + 1.5, GROUND - 1.5):
        b.stroke([(67, y), (87, y)], 1.0, "#9a6a3e")
    return b


@by_hand
def bell_tower(b):
    """A bell tower, the Bell-Ringer's: a stout tower of rough grey stone, a deep belfry at its top with a
    bronze bell hanging in it, a cornice under that, a slate spire flaring at its foot with a weathervane,
    a slit window and an arched door, on a patch of ground with a path to the door."""
    x0, x1 = 35, 57
    stone = "#a8a4a0"
    cx = (x0 + x1) / 2
    grounds(b, x0 - 6, x1 + 6, path=cx)
    top = box(b, x0, x1, 40, stone, pattern="rubble", depth=0.5)
    footing(b, x0, x1, depth=0.5, colour="#7a7672")
    oy0, oy1 = top + 3, top + 16
    arc = [(cx + 6.5 * math.cos(a), oy0 + 6.5 - 6.5 * math.sin(a)) for a in np.linspace(0, math.pi, 11)]
    b.poly([(cx + 6.5, oy1)] + arc + [(cx - 6.5, oy1)], "#2a2630", texture=0.0, profile="flat", tone=0.3)
    b.stroke([(cx - 6.5, oy0 + 3.5), (cx + 6.5, oy0 + 3.5)], 1.4, "#5a3a24")
    b.poly([(cx - 1.8, oy0 + 4), (cx + 1.8, oy0 + 4), (cx + 4, oy0 + 10), (cx + 4.8, oy0 + 11.8), (cx - 4.8, oy0 + 11.8),
            (cx - 4, oy0 + 10)], "#c8902a", texture=0.0, gloss=0.7)
    b.ellipse(cx, oy0 + 12.6, 1.2, 1.0, "#8a5a1a")
    b.rect(x0 - 2, oy1, x1 + 2, oy1 + 3, "#c8c4be", texture=0.03)
    b.rect(cx - 1, top + 23, cx + 1, top + 29, "#2a2630", texture=0.0)
    apex = (cx + 2, top - 24)
    b.surface([(x0 - 4, top + 2), (x1 + 4, top + 2), (cx + 6, top - 6), apex, (cx - 3, top - 6)], "#5c6684", "shingles",
              tone=0.12, axes=((1.0, 0.0), DOWN))
    b.surface([(x1 + 4, top + 2), (x1 + 4 + DX * 0.5, top + 2 + DY * 0.5), apex, (cx + 6, top - 6)], "#5c6684", "shingles",
              tone=-0.3, axes=(SIDEWAYS, DOWN))
    b.stroke([apex, (apex[0], apex[1] - 6)], 1.0, "#3a3a44")
    b.poly([(apex[0] - 3.5, apex[1] - 4.6), (apex[0] + 3.5, apex[1] - 4.6), (apex[0] + 4.5, apex[1] - 3.6),
            (apex[0] - 3.5, apex[1] - 3.6)], "#3a3a44", texture=0.0)
    door(b, cx, w=9, h=13, colour="#5a3a2a")
    return b


@by_hand
def gem_workshop(b):
    """A gemcutter's workshop, Iolanthe's: a squat cottage of rough stone under a big slate shingle roof, a
    wide lit window of cut gems, crystals grown up by its wall, a grinding wheel on a bench out front and a
    sign with a faceted gem, on a patch of gravel."""
    gems = ["#5ac8e8", "#c86ae8", "#e8486a", "#6ae890", "#f0c040"]
    def display(b, x0, y0, x1, y1):
        for k, c in enumerate(gems):
            x = x0 + (x1 - x0) * (k + 0.5) / len(gems)
            y = y1 - 3 - (k % 2) * 2.5
            b.poly([(x - 1.8, y), (x, y - 2.4), (x + 1.8, y), (x, y + 2.4)], c, texture=0.0, gloss=0.8)
    grounds(b, 20, 60, colour="#a8a294", stone="#7a7488", path=29, earth="#c8bca8")
    shop(b, "#a8a2b8", "rubble", "#3e4e72", "shingles", gem_emblem, board="#c8b8e0", display=display,
         door_colour="#4a3a6a", height=23, rise=22)
    for x, h, w, colour in ((13, 20, 4.2, "#8ad8f0"), (18, 12, 3.0, "#c8a0f0"), (9, 10, 2.8, "#c8a0f0")):
        b.poly([(x - w, GROUND), (x, GROUND - h), (x + w * 0.2, GROUND)], shade(colour, 1.2), tone=0.85)
        b.poly([(x + w * 0.2, GROUND), (x, GROUND - h), (x + w, GROUND)], shade(colour, 0.85), tone=0.45)
    b.rect(66, GROUND - 6, 76, GROUND - 3.5, "#7a5232", texture=0.04)
    for x in (67.5, 74.5):
        b.stroke([(x, GROUND - 4), (x, GROUND + 2)], 1.4, "#5a3a24")
    b.ellipse(71, GROUND - 10.5, 5.0, 5.0, "#8a8890", texture=0.06)
    b.ellipse(71, GROUND - 10.5, 1.3, 1.3, "#4a4850", profile="flat")
    return b

def ledge(b, x0, x1, y, colour, wall, h=3.0, depth=0.5, over=1.5):
    """A band, cornice or string course standing out from a wall at `y` (its top): its top lit, going
    back; its front; and the shadow it casts on the `wall` under it, as RD draws every ledge (2026-10-24:
    a band painted flat on a wall reads as a stripe, not a ledge)."""
    dx, dy = DX * depth * 0.25, DY * depth * 0.25
    b.poly([(x0 - over, y + h), (x1 + over, y + h), (x1 + over, y + h + 2.2), (x0 - over + 1, y + h + 2.2)], shade(wall, 0.58),
           texture=0.0, profile="flat")
    b.poly([(x0 - over, y), (x1 + over, y), (x1 + over + dx, y + dy), (x0 - over + dx, y + dy)], shade(colour, 1.18), texture=0.02,
           profile="flat", tone=0.8)
    b.rect(x0 - over, y, x1 + over, y + h, colour, texture=0.03, profile="cylinder")


def ground_shadow(b, x0, x1, height, depth=0.6):
    """The shadow a building casts on its ground, down and to the right of its foot, away from the light
    at the top left: a soft dark patch, longer the taller it is."""
    reach = min(18.0, 4 + height * 0.18)
    b.poly([(x0 + 3, GROUND + 0.5), (x1 + DX * depth, GROUND + DY * depth + 0.5), (x1 + DX * depth + reach, GROUND + DY * depth + 3.5),
            (x0 + 3 + reach * 0.6, GROUND + 4.5)], "#2e3a24", texture=0.0, profile="flat", tone=0.25)


def steps(b, spans, stone, rise=4, depth=0.6, top=None):
    """Broad steps or a plinth, front and side, each `rise` high, one per span (x0, x1), widest first;
    `top` a colour for their treads (snow, moss), else their own stone."""
    for k, (x0, x1) in enumerate(spans):
        g = GROUND - rise * k
        b.surface([(x1, g), (x1 + DX * depth, g + DY * depth), (x1 + DX * depth, g - rise + DY * depth), (x1, g - rise)], stone,
                  "rubble", tone=-0.4, axes=(SIDEWAYS, DOWN))
        b.surface([(x0, g), (x1, g), (x1, g - rise), (x0, g - rise)], stone, "rubble", slope=(-0.006, 0.0))
        b.poly([(x0, g - rise), (x1, g - rise), (x1 + DX * depth, g - rise + DY * depth), (x0 + DX * depth, g - rise + DY * depth)],
               top or shade(stone, 1.15), texture=0.02, profile="flat", tone=0.8)
    return GROUND - rise * len(spans)


def facet_spire(b, x0, x1, base, height, light, dark, side, depth=0.45):
    """A faceted crystal spire on a base from x0 to x1: its lit facet, its shaded one and its side going
    back, meeting at a point a little right of its middle. Returns the point."""
    cx = (x0 + x1) / 2
    apex = (cx + 1, base - height)
    b.poly([(x0, base), apex, (cx + 1.5, base)], light, tone=0.85, gloss=0.4)
    b.poly([(cx + 1.5, base), apex, (x1, base)], dark, tone=0.45, gloss=0.3)
    b.poly([(x1, base), apex, (x1 + DX * depth, base + DY * depth)], shade(dark, 0.8), tone=0.3)
    return apex


@by_hand
@grand(192)
def emerald_spire(b):
    """The Emerald Spire, the wonder of the Emerald Road: a tall tower of green stone on a broad jade
    plinth, banded in gold, a narrower tier over it and over that a great faceted emerald spire with a
    glowing emerald orb at its point; two turrets with green conical roofs behind it, a gold door, lit
    windows the green of the spectacles everyone here wears, poppies along its foot."""
    jade, green, gold, glow = "#8ccfa6", "#3a9a62", "#e8c050", "#c8ffb0"
    grounds(b, 10, 82, colour="#5f9a44", path=47)
    ground_shadow(b, 14, 80, 90)
    for x0, x1 in ((14, 28), (66, 80)):                                          # the turrets, behind: round
        cx = (x0 + x1) / 2
        top = box(b, x0, x1, 36, jade, pattern="blocks", depth=0.45, curve=0.9)
        apex = (cx + 1, top - 20)
        b.surface([(x0 - 2.5, top + 1), (x1 + 2.5, top + 1), apex], green, "shingles", tone=0.1, curve=0.9)
        b.surface([(x1 + 2.5, top + 1), (x1 + 2.5 + DX * 0.45, top + 1 + DY * 0.45), apex], green, "shingles", tone=-0.3,
                  axes=(SIDEWAYS, DOWN))
        b.stroke([apex, (apex[0], apex[1] - 5)], 1.0, gold)
        b.ellipse(apex[0], apex[1] - 6, 1.5, 1.5, gold, gloss=0.6)
        window(b, cx, top + 13, w=5, h=8, frame="#2e6a46", glass=glow, arched=True, deep=True)
    floor = steps(b, ((24, 70), (29, 65)), jade, top=shade(jade, 1.04))
    x0, x1 = 33, 61
    cx = (x0 + x1) / 2
    top = box(b, x0, x1, 46, green, pattern="blocks", ground=floor, depth=0.5, curve=0.6)
    ledge(b, x0, x1, top - 1, gold, green, h=3.5)                                 # gold bands, standing out
    ledge(b, x0, x1, floor - 26, gold, green, h=2.2, over=1)
    for x in (x0 + 7, x1 - 7):
        window(b, x, top + 12, w=5, h=9, frame="#2e6a46", glass=glow, arched=True, deep=True)
    arc = [(cx + 9 * math.cos(a), floor - 18 + 9 - 9 * math.sin(a)) for a in np.linspace(0, math.pi, 13)]
    b.poly([(cx + 9, floor)] + arc + [(cx - 9, floor)], jade, texture=0.04, profile="dome")
    door(b, cx, w=13, h=17, colour="#c8962c", frame="#8a6a1e", ground=floor, knob="#fff0a0", deep=True)
    ux0, ux1 = 37, 57                                                             # the upper tier
    utop = box(b, ux0, ux1, 16, jade, pattern="blocks", ground=top - 1, depth=0.45, curve=0.7)
    window(b, (ux0 + ux1) / 2, utop + 8, w=6, h=7, frame="#2e6a46", glass=glow, deep=True)
    ledge(b, ux0, ux1, utop - 1, gold, jade, h=3)
    apex = facet_spire(b, ux0 - 1, ux1 + 1, utop - 1, 40, "#6ae896", "#1f8a4a", "#17703c")
    b.stroke([(ux0 + 2, utop - 3), (apex[0] - 0.5, apex[1] + 4)], 1.0, "#d8ffe0")   # a gleam up its edge
    b.stroke([apex, (apex[0], apex[1] - 3)], 1.2, gold)
    b.ellipse(apex[0], apex[1] - 6.5, 3.8, 3.8, "#8affb0", gloss=0.85)
    b.ellipse(apex[0] - 1.2, apex[1] - 7.8, 1.1, 1.1, "#f0fff4", texture=0.0, profile="flat")
    for side in (-1, 1):                                                          # green banners down the plinth
        x = cx + side * 18
        b.poly([(x - 3, floor - 16), (x + 3, floor - 16), (x + 3, floor - 5), (x, floor - 2.5), (x - 3, floor - 5)],
               "#2e8a56", texture=0.03)
        b.stroke([(x - 4, floor - 16), (x + 4, floor - 16)], 1.3, gold)
    flowers(b, 12, 28, GROUND + 2.5, ["#e8343a", "#f0503a", "#d82838"], seed=4)   # poppies
    flowers(b, 68, 84, GROUND + 1.5, ["#e8343a", "#f0503a", "#d82838"], seed=7)
    return b


TILT = 0.34      # how round a drum's top and foot look from this height: an ellipse ry = r × TILT


def oval(cx, cy, rx, ry, a0, a1, n=17):
    """Points along an ellipse from angle a0 to a1 (0 is to the right, π/2 down)."""
    return [(cx + rx * math.cos(a), cy + ry * math.sin(a)) for a in np.linspace(a0, a1, n)]


def drum(b, cx, base, r, height, colour, pattern="rubble", curve=1.0):
    """A round tower or hall seen from a little above, as RD draws one: its wall shaded round, its foot
    and top curving with it (a box with a dome on it read flat and wrong, 2026-10-24). Returns its top."""
    top = base - height
    ry = r * TILT
    pts = [(cx - r, top), (cx - r, base)] + oval(cx, base, r, ry, math.pi, 0)[1:] + [(cx + r, top)] + oval(cx, top, r, ry, 0, math.pi)[1:]
    b.surface(pts, colour, pattern, curve=curve, eave=4, foot=3)
    return top


def ring(b, cx, y, r, colour, wall, h=3.0):
    """A ledge round a drum at `y`: its top seen from above, its rounded front, its shadow on the wall."""
    ry = r * TILT
    b.poly(oval(cx, y + h + 1.6, r + 0.5, ry, math.pi, 0) + oval(cx, y + h, r + 0.5, ry, 0, math.pi), shade(wall, 0.55),
           texture=0.0, profile="flat")
    b.poly(oval(cx, y, r + 1.6, ry + 0.6, 0, 2 * math.pi, 33), shade(wall, 1.05), texture=0.02, profile="flat", tone=0.6)
    b.poly(oval(cx, y, r + 1.6, ry + 0.6, math.pi, 0) + oval(cx, y + h, r + 1.6, ry + 0.6, 0, math.pi), colour, texture=0.03,
           profile="cylinder")


def dome(b, cx, top, r, colour, rise=None, stars=True, slit=True):
    """A dome on a drum's top, shaded round: gold stars on it and its slit open, an observatory's.
    Returns its peak's height."""
    rise = rise or r * 0.95
    ry = r * TILT
    b.poly(oval(cx, top, r + 1, ry, 0, math.pi) + oval(cx, top, r + 1, rise, math.pi, 2 * math.pi, 25)[1:-1], colour,
           profile="dome", texture=0.06)
    if stars:
        for a, f in ((3.6, 0.55), (4.0, 0.8), (4.4, 0.45), (4.9, 0.75), (5.4, 0.5), (3.9, 0.3), (5.7, 0.7)):
            b.ellipse(cx + r * f * math.cos(a), top + rise * f * math.sin(a), 0.9, 0.9, "#ffe08a", texture=0.0, profile="flat")
    if slit:
        b.poly([(cx + 2, top - rise + 1), (cx + 6, top - rise + 2), (cx + 11, top - rise * 0.35), (cx + 7, top - rise * 0.25)],
               "#141638", texture=0.0, profile="flat")
    return top - rise


def telescope(b, x, y, length=18, angle=-50, brass="#d8a840"):
    """A brass telescope from (x, y) up to the sky at `angle` degrees: a straight tube, kept off the
    hand-drawn bend (bent, it looked wavy, 2026-10-24), widening a little to its end, shaded round, two
    darker bands round it and its lens catching the light."""
    a = math.radians(angle)
    ux, uy = math.cos(a), math.sin(a)
    nx, ny = -uy, ux
    def tube(t0, t1, w0, w1, colour, profile="cylinder"):
        p0, p1 = (x + ux * t0, y + uy * t0), (x + ux * t1, y + uy * t1)
        b.poly([(p0[0] + nx * w0, p0[1] + ny * w0), (p1[0] + nx * w1, p1[1] + ny * w1),
                (p1[0] - nx * w1, p1[1] - ny * w1), (p0[0] - nx * w0, p0[1] - ny * w0)], colour, texture=0.0,
               profile=profile, straight=True)
    tube(0, length, 1.7, 2.3, brass)
    for t in (length * 0.35, length * 0.8):
        tube(t, t + 1.3, 2.0, 2.3, shade(brass, 0.7))
    ex, ey = x + ux * length, y + uy * length
    b.ellipse(ex, ey, 2.6, 2.6, "#8a6a2a", texture=0.0)
    b.ellipse(ex, ey, 1.7, 1.7, "#a8e8ff", texture=0.0, profile="flat", gloss=0.6)


@by_hand
@grand(160)
def star_observatory(b):
    """The Star Observatory on Starfall Isle, where Glimmerbough watches for falling stars: a slender round
    tower of pale violet stone on a low step, a balcony ring with a railing up its side, a midnight-blue
    dome scattered with gold stars on its top, its slit open and a brass telescope reaching out of it, a
    crescent moon over all; arched windows and a door set deep, star crystals grown up round its foot.
    (Picked from four, 2026-10-24: a box with a dome and a wing beside it looked wrong.)"""
    stone, ledge_stone, night = "#b8b0cc", "#c6bed8", "#2a2e6e"
    grounds(b, 22, 70, colour="#6a9a5a", stone="#a8a4c0", path=46)
    ground_shadow(b, 34, 58, 70)
    base = steps(b, ((30, 62),), stone, rise=3, depth=0.4, top=shade(stone, 1.02))
    cx = 46
    top = drum(b, cx, base, 11, 44, stone)
    for y in (top + 14, top + 28):
        window(b, cx - 2, y, w=4, h=7, frame="#4a3a5e", glass="#ffe6a0", arched=True, deep=True)
    door(b, cx - 1, w=9, h=14, colour="#4a3a6e", frame="#3a2e52", ground=base, deep=True)
    ring(b, cx, top + 8, 11, ledge_stone, stone, h=2.5)                           # the balcony, its railing
    for x in (cx - 12.5, cx - 6.5, cx, cx + 6.5, cx + 12.5):
        b.stroke([(x, top + 8 + 11 * TILT * math.sin(math.acos(max(-1, min(1, (x - cx) / 12.6))))), (x, top + 3.5)], 0.9, "#4a4262")
    b.stroke(oval(cx, top + 3.5, 12.6, 12.6 * TILT, 0, math.pi), 1.1, "#5a5274")
    ring(b, cx, top - 1, 11, ledge_stone, stone, h=2.5)                           # the parapet under the dome
    peak = dome(b, cx, top - 1, 12, night)
    telescope(b, cx + 5, top - 9, 17, -48)
    b.stroke([(cx, peak), (cx, peak - 4)], 1.0, "#5a5470")                        # the crescent over it all
    b.ellipse(cx, peak - 8, 3.4, 3.4, "#ffe08a", texture=0.0, profile="flat")
    b.ellipse(cx + 1.6, peak - 8.8, 2.9, 2.9, "#3a3e7e", texture=0.0, profile="flat")
    for x, h, w, colour in ((24, 16, 3.8, "#8ad8f0"), (29, 9, 2.6, "#c8a0f0"), (67, 12, 3.0, "#8ad8f0"), (71, 7, 2.2, "#c8a0f0")):
        b.poly([(x - w, GROUND + 1), (x, GROUND + 1 - h), (x + w * 0.2, GROUND + 1)], shade(colour, 1.2), tone=0.85, gloss=0.3)
        b.poly([(x + w * 0.2, GROUND + 1), (x, GROUND + 1 - h), (x + w, GROUND + 1)], shade(colour, 0.85), tone=0.45)
    return b


@by_hand
@grand(160)
def moonwell(b):
    """The Moonwell on Starfall Isle: a round pool of glowing water in a basin of pale moonstone, under
    three arches of moonstone, the middle one tallest with a gold crescent on it; crystals floating over
    the water and a wisp lantern at each side, on a patch of grass with stones round it."""
    moon, deep, water = "#dadcf0", "#8a8eb8", "#78e0f0"
    grounds(b, 8, 84, colour="#6a9a5a", stone="#a8acc8")
    ground_shadow(b, 14, 80, 50)
    for x, h, w in ((22, 30, 11), (72, 30, 11), (47, 46, 16)):                    # the arches, behind the pool
        top = GROUND - 6 - h
        shadow = [(x + 1.6 + (w / 2) * math.cos(a), top + 1.4 + w / 2 - (w / 2) * math.sin(a)) for a in np.linspace(0, math.pi, 15)]
        b.stroke(shadow, 3.6, shade(deep, 0.6))                                    # its shadow, behind
        for px in (x - w / 2, x + w / 2):
            b.poly([(px - 2, GROUND - 4), (px + 2, GROUND - 4), (px + 2, top + w / 2), (px - 2, top + w / 2)], moon,
                   texture=0.03, profile="cylinder")
            b.rect(px - 2.8, GROUND - 6, px + 2.8, GROUND - 3, deep, texture=0.03)
        arc = [(x + (w / 2) * math.cos(a), top + w / 2 - (w / 2) * math.sin(a)) for a in np.linspace(0, math.pi, 15)]
        b.stroke(arc, 3.6, moon)
        b.ellipse(x, top - 0.5, 1.8, 1.6, "#a8f0ff", gloss=0.7)
        if w > 12:
            b.ellipse(x, top - 9, 4.4, 4.4, "#ffd860", texture=0.0, profile="flat")   # the crescent
            b.ellipse(x + 2.2, top - 10, 3.8, 3.8, "#6a9a5a", texture=0.0, profile="flat")
    b.ellipse(47, GROUND - 1, 30, 9.5, deep, texture=0.04)                        # the basin and its pool
    b.ellipse(47, GROUND - 2.5, 27.5, 8, moon, texture=0.04)
    b.ellipse(47, GROUND - 3, 24, 6.4, shade(deep, 0.62), texture=0.0, profile="flat")   # its far wall, inside, in shadow
    b.ellipse(47, GROUND - 2.2, 23.5, 5.6, "#3ab8d0", texture=0.0, profile="flat")
    b.ellipse(46, GROUND - 3.6, 18, 4.4, water, texture=0.0, profile="flat", gloss=0.5)
    b.ellipse(43, GROUND - 4.4, 7, 1.6, "#e8ffff", texture=0.0, profile="flat")
    for x, y, h, colour in ((36, GROUND - 22, 9, "#8ad8f0"), (58, GROUND - 26, 8, "#c8a0f0"), (47, GROUND - 16, 6, "#a8f0ff")):
        b.poly([(x, y - h), (x + 2.6, y), (x, y + h * 0.5), (x - 2.6, y)], colour, texture=0.0, gloss=0.8)
        b.poly([(x, y - h), (x + 2.6, y), (x, y + h * 0.5)], shade(colour, 0.8), texture=0.0)
    for x in (8, 86):                                                             # wisp lanterns
        b.stroke([(x, GROUND + 1), (x, GROUND - 13)], 1.5, "#5a5470")
        b.ellipse(x, GROUND - 16, 3.0, 3.4, "#b8f0ff", gloss=0.7)
        b.ellipse(x, GROUND - 16, 1.6, 1.8, "#f0ffff", texture=0.0, profile="flat")
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
    "pavilion_tent": pavilion_tent,
    "yurt": yurt,
    "dome_house": dome_house,
    "market_tent": market_tent,
    "tree_house": tree_house,
    "acorn_cottage": acorn_cottage,
    "bluebell_house": bluebell_house,
    "crystal_cottage": crystal_cottage,
    "lake_shrine": lake_shrine,
    "warrior_guild": warrior_guild,
    "wildfolk_lodge": wildfolk_lodge,
    "bell_tower": bell_tower,
    "gem_workshop": gem_workshop,
    "emerald_spire": emerald_spire,
    "star_observatory": star_observatory,
    "moonwell": moonwell,
}


def fit(draw, width=76, height=76):
    """`draw` (a function of a Build) redrawn scaled about its foot so it fills `width` × `height` of the
    frame, centred, as RD's buildings fill theirs (about 70 to 80 pixels each way)."""
    organic, size = getattr(draw, "organic", 0.0), getattr(draw, "size", SIZE)
    first = Build(organic=organic)
    draw(first)
    left, top, right, bottom = first.extent()
    if left <= 0 or top <= 0 or right >= SIZE - 1:
        # Past the frame's own 96 pixels (a spire) it was cut off there and measured short: measured
        # again on a canvas with room all round, in the frame's coordinates.
        room = SIZE * 3
        first = Build(organic=organic, size=room)
        draw(first)
        left, top, right, bottom = first.extent()
        left, right, top = left - (room - SIZE) / 2, right - (room - SIZE) / 2, top - (room - SIZE)
    grow = size / SIZE
    k = min(width * grow / (right - left), height * grow / (GROUND - top), 1.6 * grow)
    b = Build(k, (left + right) / 2, organic, size)
    draw(b)
    return b


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
        c = 2 * max(img.width for img in tiles_)          # each at 2×, a grand building as big beside the rest
        cols = 5
        board = Image.new("RGBA", (c * cols, c * math.ceil(len(tiles_) / cols)), (106, 150, 86, 255))
        for n, img in enumerate(tiles_):
            big = img.resize((img.width * 2, img.height * 2), Image.NEAREST)
            board.alpha_composite(big, ((n % cols) * c + (c - big.width) // 2, (n // cols) * c + c - big.height))
        board.save(sheet)
        print(f"sheet in {sheet}")


if __name__ == "__main__":
    main(sys.argv[1:])
