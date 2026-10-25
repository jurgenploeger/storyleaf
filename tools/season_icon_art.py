#!/usr/bin/env python3
"""The seasonal app icons, Halloween, Christmas and Easter, that the game switches to while each festive
season runs (`SeasonalIcon` in Storyleaf/App, the seasons' dates in content/rewards.json `seasons`). The
same picked drawing as the app icon (tools/app_icon_art.py `SOURCE`), cropped a little looser so a hat
fits on the hero's head (`BOX`, 128 pixels at 8×), with only the scenery changed and something festive
on him:

  Halloween  a purple night, a crescent moon, autumn leaves, bats, jack-o'-lanterns, a witch's hat
  Christmas  a pale winter sky, snow on the trees and the ground, snowflakes, a Santa hat
  Easter     a bright spring sky, fresh leaves and blossom, flowers and painted eggs, bunny ears (no band)

Held to docs/pixel-style.md and docs/sprite-acceptance.md:

- **The drawing's own clusters stay.** The scenery is Retro Diffusion's, so it's recoloured, never redrawn:
  each class of colour (sky, leaves, blossom, branches, grass) is a small ramp in the drawing (one to nine
  colours), and each of its colours is swapped for the one of the same rank on the season's ramp, which
  turns its shadows away from yellow and its lights toward it. The light and texture are RD's.
- **Tinted outlines on the scenery:** its dark pixels take a deep shade of what they round, never black.
- **Snow lies where the light does,** on the lit tops of the leaves' clusters, in RD's snow colours
  (scenery_art.SNOW); never a strip along an edge or single pixels as noise.
- **The hats and props are drawn with pixel_kit:** lit from the top left, a few hue-shifted shades with
  texture, a contact shadow, and the dark outline characters and their gear have.
- **A hat sits as a head piece does:** its band on the head's widest row above the eyes (y 72 here, the
  scalp's top at 53 and the eyes at 96), a little wider than the scalp, the hair above it hidden.
- **Nothing in the corners** iOS rounds off (about 29 of the drawing's pixels), so every prop shows.

The hero is left as drawn (`HERO` roughs him out, `hero_mask` cuts him on his own outline, hair and all).
Each also comes at night for Dark Mode (`at_night`, as tools/app_icon_art.py's dark icon: the season's
night sky, moonlight on the hero, and its lights: the moon's halo and the pumpkins' glow, fairy lights in
the snowy trees, fireflies in the spring meadow) and in its greys for Tinted. Written as
AppIcon-<Season>.appiconset, light, dark and tinted, as AppIcon is.

    python3 tools/season_icon_art.py                    # writes the three icon sets
    python3 tools/season_icon_art.py --preview out.png  # all three by day and at night, beside the icon

Needs pillow + numpy.
"""

import argparse
import colorsys
import math
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

import app_icon_art
from pixel_kit import Material, Sprite
from scenery_art import SNOW

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "Storyleaf/Resources/Assets.xcassets"

BOX = (44, 40, 172, 168)
SCALE = 8
# The hero and his sword, in the drawing's pixels: nothing inside is recoloured.
HERO = [(55, 44), (64, 43), (72, 60), (79, 78), (85, 98), (89, 110), (93, 108), (96, 100), (94, 90), (87, 84),
        (84, 76), (90, 66), (98, 56), (108, 51), (122, 51), (136, 53), (146, 59), (151, 70), (153, 84), (151, 98),
        (149, 106), (151, 112), (152, 124), (150, 132), (155, 140), (154, 146), (149, 149), (142, 149), (141, 157), (140, 200), (97, 200),
        (97, 157), (93, 155), (87, 153), (84, 144), (78, 141), (77, 131), (66, 131), (63, 124), (71, 118),
        (79, 117), (71, 96), (62, 72), (55, 50)]
# Below this row the green is the meadow, above it the trees' leaves.
GROUND = 147
# The hair's leftmost column (the lock flicked out to the left): the reds left of it are the apple tree's.
HAIR_LEFT = 82
# The tunic's hem: below it the hero is legs and boots, and green is the grass.
HEM = 159
SKY, LEAVES, BLOSSOM, BRANCHES, GRASS, DARK = 1, 2, 3, 4, 5, 6


def hexrgb(code: str) -> np.ndarray:
    code = code.lstrip("#")
    return np.array([int(code[i:i + 2], 16) for i in (0, 2, 4)], dtype=float) / 255


def ramp(dark: str, light: str, n: int) -> list:
    """`n` shades from `dark` to `light`, the hue turning the short way between them (so a ramp whose
    shadow sits away from yellow and its light toward it keeps doing so), in hard steps."""
    h0, s0, v0 = colorsys.rgb_to_hsv(*hexrgb(dark))
    h1, s1, v1 = colorsys.rgb_to_hsv(*hexrgb(light))
    dh = (h1 - h0 + 0.5) % 1 - 0.5
    out = []
    for i in range(n):
        t = i / max(1, n - 1)
        out.append(np.array(colorsys.hsv_to_rgb((h0 + dh * t) % 1, s0 + (s1 - s0) * t, v0 + (v1 - v0) * t)))
    return out


# Each season: for every class, the dark and light ends of its ramp (shadows turned away from yellow,
# lights toward it), and the sky in three bands down the icon.
SEASONS = {
    "Halloween": {
        "sky": [("#26163f", "#3a2257"), ("#4a2462", "#62307a"), ("#8a3a5e", "#b4544e")],
        LEAVES: ("#4a1430", "#ffb84a"), BLOSSOM: ("#1a0e2e", "#a45cae"),
        BRANCHES: ("#2e1a26", "#4a2c30"), GRASS: ("#24221a", "#b8923a"),
    },
    "Christmas": {
        "sky": [("#86a8d4", "#9cbade"), ("#a8c4e4", "#bcd2ec"), ("#c8dcf0", "#dce9f6")],
        LEAVES: ("#0c2a2e", "#3e8a5c"), BLOSSOM: (SNOW[0], SNOW[4]),
        BRANCHES: ("#2a2232", "#4a3c48"), GRASS: (SNOW[1], SNOW[4]),
    },
    "Easter": {
        "sky": [("#62b4f0", "#78c4f6"), ("#8cd0f8", "#a4dcfa"), ("#bce8fc", "#d6f2ff")],
        LEAVES: ("#1e5a3a", "#d4f07a"), BLOSSOM: ("#7a2a62", "#ffe2ee"),
        BRANCHES: ("#4a2a2a", "#8a5a3e"), GRASS: ("#1e6a3a", "#dcf28a"),
    },
}


def hero_mask(box: tuple = BOX) -> np.ndarray:
    """The hero exactly, outline and all. `HERO` only roughs him out: the background is flooded in from
    outside it through everything but dark pixels, as far as a band 5 pixels inside it, so it stops at his
    own outline (and where that has a gap, leaks a few pixels at most); his gold (the sword's lit edge,
    which has no dark line) and his hair's oranges and reds (the lock flicked out to the left and the
    deep red hair behind it, too thin for the band, and the sword's orange edge) are never background,
    and sky never his. Then his outline is the dark pixels within 2 of what's left. Cut from the polygon
    alone, his outline came out half his and half the scenery's, recoloured, and looked chewed. `box` is
    the part of the drawing to cut him from (the app icon's `CROP` runs lower, to his knees). The grass
    between his legs is flooded in from the icon's bottom edge, where the legs run off it."""
    w, h = box[2] - box[0], box[3] - box[1]
    image = Image.new("L", (w, h))
    ImageDraw.Draw(image).polygon([(x - box[0], y - box[1]) for x, y in HERO], fill=255)
    rough = np.asarray(image) > 0
    rgb = app_icon_art.crop(box)
    dark = rgb.max(axis=2) <= 0.2
    four = ndimage.generate_binary_structure(2, 1)
    outer = ndimage.binary_dilation(rough, four, iterations=5)
    # He runs on past the icon's edges (the legs off its foot): erode from the polygon only, not from them,
    # or the band at the edge would let the flood into his boots.
    inner = ndimage.binary_erosion(rough, four, iterations=5, border_value=1)
    gold = app_icon_art.is_gold(rgb) & outer
    hsv = np.array([[colorsys.rgb_to_hsv(*p) for p in row] for row in rgb])
    hue, sat, val = hsv[..., 0] * 360, hsv[..., 1], hsv[..., 2]
    hair = ((hue < 40) | (hue > 350)) & (sat > 0.55) & (val > 0.3) & outer
    # The deep red of his hair is also the apples' red: left of his hair (HAIR_LEFT), by the blade, it's apples.
    apples = ((hue < 12) | (hue > 350)) & (np.arange(w)[None, :] + box[0] < HAIR_LEFT)
    gold |= hair & ~apples
    sky = app_icon_art.sky_mask(rgb)
    # Also the grass showing between his legs, where they run off the bottom: the polygon spans the gap.
    green = (hue > 60) & (hue < 170) & (sat > 0.18)
    foot = np.zeros_like(dark)
    foot[-1] = green[-1] & ~dark[-1]
    seeds = (~outer & ~dark) | sky | foot
    back = ndimage.binary_propagation(seeds & ~foot, structure=four, mask=(~dark & ~inner & ~gold) | sky)
    # The grass between his legs, flooded up from the bottom edge through green alone (not into his boots).
    back |= ndimage.binary_propagation(foot, structure=four, mask=green & ~dark & ~gold)
    light = ~dark & ~back & outer
    near = ndimage.distance_transform_cdt(~light, metric="chessboard") <= 2
    hero = ndimage.binary_fill_holes(light | (dark & near & outer)) & ~sky
    # Below his tunic's hem (HEM) nothing of his is green: what is, is grass.
    below = np.arange(h)[:, None] + box[1] >= HEM
    hero &= ~(green & below)
    # His boots are dark all through, not just at their outline: below the hem, the dark inside him is his.
    hero |= dark & below & ndimage.binary_erosion(rough, four, iterations=1, border_value=1) & ~back
    # Only the hero himself: a bit of bush or a few tree pixels cut off from him go back to the scenery.
    parts, count = ndimage.label(hero, np.ones((3, 3)))
    return parts == 1 + np.argmax(ndimage.sum(hero, parts, range(1, count + 1)))


def classes(rgb: np.ndarray) -> np.ndarray:
    """Each pixel's class: 0 keep, SKY, LEAVES, BLOSSOM, BRANCHES, GRASS or DARK (outline and deep shade)."""
    hsv = np.array([[colorsys.rgb_to_hsv(*p) for p in row] for row in rgb])
    hue, sat, val = hsv[..., 0] * 360, hsv[..., 1], hsv[..., 2]
    rows = np.arange(rgb.shape[0])[:, None] + BOX[1]
    out = np.zeros(rgb.shape[:2], int)
    out[app_icon_art.sky_mask(rgb)] = SKY
    green = (hue > 60) & (hue < 170) & (sat > 0.18) & (val > 0.18)
    out[green & (rows < GROUND)] = LEAVES
    out[green & (rows >= GROUND)] = GRASS
    out[((hue > 270) | (hue < 8)) & (sat > 0.15) & (val > 0.2) & ~green] = BLOSSOM
    out[(hue >= 8) & (hue < 45) & (sat > 0.15) & (val > 0.15) & (val < 0.62)] = BRANCHES
    out[val <= 0.18] = DARK
    out[(hue >= 45) & (hue <= 60) & (rows >= GROUND)] = GRASS
    out[hero_mask()] = 0
    return out


def luma(c) -> float:
    return float(np.dot(c, [0.299, 0.587, 0.114]))


def recolour(rgb: np.ndarray, kind: np.ndarray, season: dict) -> tuple:
    """RD's colours swapped class by class, rank for rank, onto the season's ramps; the sky in its bands;
    the dark pixels a deep shade of the class they round. Returns the image and each class's new ramp."""
    out = rgb.copy()
    key = (rgb * 255 + 0.5).astype(int)
    ramps = {}
    for code in (LEAVES, BLOSSOM, BRANCHES, GRASS):
        where = kind == code
        colours = sorted({tuple(c) for c in key[where]}, key=lambda c: luma(np.array(c)))
        if not colours:
            continue
        ramps[code] = ramp(*season[code], max(2, len(colours)))
        swap = {c: ramps[code][round(i * (len(ramps[code]) - 1) / max(1, len(colours) - 1))] for i, c in enumerate(colours)}
        for y, x in np.argwhere(where):
            out[y, x] = swap[tuple(key[y, x])]
    # The sky: a band per third of the icon, its lighter shade where RD's sky was lighter.
    sky = kind == SKY
    lights = sorted({tuple(c) for c in key[sky]}, key=lambda c: luma(np.array(c)))
    for y, x in np.argwhere(sky):
        band = season["sky"][min(2, y * 3 // rgb.shape[0])]
        out[y, x] = hexrgb(band[1] if tuple(key[y, x]) == lights[-1] and len(lights) > 1 else band[0])
    # The dark pixels: the deepest shade of the class most round them, darker still.
    h, w = kind.shape
    for y, x in np.argwhere(kind == DARK):
        near = kind[max(0, y - 2):y + 3, max(0, x - 2):x + 3].ravel()
        near = near[(near != DARK) & (near != 0) & (near != SKY)]
        code = np.bincount(near).argmax() if len(near) else LEAVES
        deep = ramps.get(code, ramps.get(LEAVES))[0]
        out[y, x] = deep * 0.72
    return out, ramps


def place(out: np.ndarray, sprite: Image.Image, x: int, y: int, behind: np.ndarray = None) -> np.ndarray:
    """A rendered sprite with its top left at the drawing's (x, y); where `behind` is True it doesn't cover.
    Returns where it went."""
    art = np.asarray(sprite.convert("RGBA"), dtype=float) / 255
    covered = np.zeros(out.shape[:2], bool)
    for dy in range(art.shape[0]):
        for dx in range(art.shape[1]):
            if art[dy, dx, 3] < 0.5:
                continue
            ox, oy = x + dx - BOX[0], y + dy - BOX[1]
            if 0 <= ox < out.shape[1] and 0 <= oy < out.shape[0] and (behind is None or not behind[oy, ox]):
                out[oy, ox] = art[dy, dx, :3]
                covered[oy, ox] = True
    return covered


def hat(out: np.ndarray, sprite: Image.Image, x: int, y: int) -> np.ndarray:
    """A hat put on: first the hair above its brim or band is cleared (sprite-acceptance.md, *Head pieces*:
    no hair poking up round it), each hair pixel taking the colour of the nearest scenery in its row, then
    the hat itself."""
    alpha = np.asarray(sprite.convert("RGBA"))[..., 3] >= 128
    cover = np.zeros(out.shape[:2], bool)
    for dy, dx in np.argwhere(alpha):
        oy, ox = y + dy - BOX[1], x + dx - BOX[0]
        if 0 <= ox < out.shape[1] and 0 <= oy < out.shape[0]:
            cover[oy, ox] = True
    hero = hero_mask()
    for col in np.flatnonzero(cover.any(axis=0)):
        bottom = np.flatnonzero(cover[:, col]).max()
        for row in range(bottom):
            if hero[row, col] and not cover[row, col]:
                for reach in range(1, out.shape[1]):
                    for side in (col - reach, col + reach):
                        if 0 <= side < out.shape[1] and not hero[row, side] and not cover[row, side]:
                            out[row, col] = out[row, side]
                            break
                    else:
                        continue
                    break
    return place(out, sprite, x, y)


def shadow(out, kind, x0, x1, y, depth=0.62) -> None:
    """A contact shadow on the ground under something set on it: a flat oval, the ground's shades darker."""
    for x in range(x0, x1 + 1):
        for dy in (0, 1):
            ox, oy = x - BOX[0], y + dy - BOX[1]
            inset = (x - x0 < 2 or x1 - x < 2) and dy == 1
            if 0 <= ox < out.shape[1] and 0 <= oy < out.shape[0] and kind[oy, ox] in (GRASS, DARK) and not inset:
                out[oy, ox] = out[oy, ox] * depth


def pixels(out, kind, points, colours, allowed) -> None:
    """Small marks (a flower, a snowflake, a bat) at the drawing's points, only on `allowed` classes."""
    for (x, y), colour in zip(points, colours):
        ox, oy = x - BOX[0], y - BOX[1]
        if 0 <= ox < out.shape[1] and 0 <= oy < out.shape[0] and kind[oy, ox] in allowed:
            out[oy, ox] = colour


# --- the hats --------------------------------------------------------------------------------------------
# Each is drawn so its band's middle lands on the head's widest row above the eyes, (120, 72).

def rounded(sprite: Sprite, points: list, mat: Material, across: str, depth: float = 0.9) -> None:
    """A shape whose surface curves as a cloth one does: each run of it across `across` ("x", side to side,
    for a cone or a cap; "y", top to bottom, for a brim or a band) a half cylinder, so the light turns all
    the way over it and its shadow side shows where it curves. pixel_kit's own dome only rounds a shape near
    its edge, which left a big hat one flat colour under the near-frontal light."""
    sprite.poly(points, mat)
    mask = sprite.shapes.pop()[0]
    height = np.zeros(mask.shape)
    lines = mask if across == "x" else mask.T
    out = height if across == "x" else height.T
    for row in range(lines.shape[0]):
        on = np.flatnonzero(lines[row])
        if not len(on):
            continue
        # Each run of the row on its own (a hook beside its crown is a second run).
        for run in np.split(on, np.flatnonzero(np.diff(on) > 1) + 1):
            mid, half = (run[0] + run[-1]) / 2, max(1.0, (run[-1] - run[0] + 1) / 2)
            t = (run - mid) / half
            out[row, run] = np.sqrt(np.clip(1 - t * t, 0, 1)) * half * depth
    # Smoothed along the shape, so a run a pixel wider than the one beside it doesn't light as a ridge.
    height = ndimage.gaussian_filter1d(height, sigma=6.0, axis=0 if across == "x" else 1) * mask
    sprite.mask(mask, mat, height=height)


def sweep(p: list, half, steps: int = 16) -> tuple:
    """The two sides of a tapering shape along a cubic curve through `p` (four points): `half(t)` is its half
    width at t from 0 to 1. Returns the left side and the right side, base to tip."""
    def at(t):
        a, b, c, d = (1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t * t, t ** 3
        return a * p[0][0] + b * p[1][0] + c * p[2][0] + d * p[3][0], a * p[0][1] + b * p[1][1] + c * p[2][1] + d * p[3][1]

    left, right = [], []
    for i in range(steps + 1):
        t = i / steps
        x, y = at(t)
        (x1, y1), (x2, y2) = at(max(0, t - 0.02)), at(min(1, t + 0.02))
        n = math.hypot(x2 - x1, y2 - y1) or 1
        w = half(t)
        left.append((x + (y2 - y1) / n * w, y - (x2 - x1) / n * w))
        right.append((x - (y2 - y1) / n * w, y + (x2 - x1) / n * w))
    return left, right


def witch_hat() -> tuple:
    """A witch's hat: a wide, soft brim (`brim`), a tall cone with hollow sides that bends over near the top
    (the icon's edge clips its crown), its tip hanging off to the right, and a gold band. The cone is one
    shape: up its sides, then along a tapering curve (`sweep`)."""
    s = Sprite(92, 60)
    purple = Material("#5a3a8c", shades=5, texture=0.05)
    rounded(s, [(x, y + 8) for x, y in brim()], purple, "y")
    def cone_width(t):
        # Wide at the band, tapering slowly, and rounded off at the tip rather than coming to a point.
        end = math.sqrt(max(0.0, 1 - ((t - 0.86) / 0.14) ** 2)) if t > 0.86 else 1.0
        return 13.0 * (1 - t) ** 1.05 + 3.0 * end

    left, right = sweep([(42, 35), (40, 12), (56, 8), (75, 29)], cone_width, steps=32)
    cone = [(18, 46), (22, 42), (26, 38), (29, 36)] + left + right[::-1] + [(55, 36), (59, 39), (63, 43), (67, 46)]
    rounded(s, cone, purple, "x")
    s.poly([(17, 46), (68, 46), (66, 42), (19, 42)], Material("#e8a838", shades=4, texture=0.03, gloss=0.4), profile="cylinder")
    return s.render(), (78, 22)


def brim() -> list:
    """A witch's hat's brim as a soft felt one sits: an oval as the Santa hat's fur band is, its ends rounded,
    curving a little lower at the sides than over the brow, its right tip flicking back up, thicker in front,
    where its lip dips over the brow, the edge a little wavy."""
    top, bottom = [], []
    for i in range(41):
        u = i / 20 - 1                              # -1 at the left tip, 1 at the right
        x = 42 + 40 * u
        middle = 39 + 3.5 * u * u - (3.5 * u ** 6 if u > 0 else 0) + 0.5 * math.sin(u * 8)
        front = math.sqrt(max(0.0, 1 - u * u)) ** 0.7
        top.append((x, middle - 0.4 - 3.6 * front))
        bottom.append((x, middle + 0.4 + 5.2 * front))
    return top + bottom[::-1]


def santa_hat() -> tuple:
    """A Santa hat: a soft red cap, not much taller than the head's crown, flopping over to the right, its
    bobble hanging, and a fluffy fur band that
    curves round the head (lower over the brow than at the sides), its edges in tufts, not a smooth oval."""
    s = Sprite(86, 52)
    fur = Material("#f2f0f6", shades=4, texture=0.12, grain=1.0)
    rounded(s, [(16, 36), (19, 26), (27, 18), (39, 14), (51, 14), (62, 18), (71, 25), (78, 33), (81, 41),
                (73, 42), (67, 35), (62, 37)], Material("#cc2e3e", shades=5, texture=0.05), "x")
    top, bottom = [], []
    for i in range(37):
        u = i / 18 - 1
        x = 41 + 32 * u
        mid = 37 + 4.0 * (1 - u * u)                # the band's middle, lowest over the brow
        tuft = 0.9 * abs(math.sin(u * 11))
        half = 5.6 * math.sqrt(max(0.0, 1 - u ** 6)) + tuft
        top.append((x, mid - half))
        bottom.append((x, mid + half))
    rounded(s, top + bottom[::-1], fur, "y")
    s.ellipse(78, 45, 7, 7, fur)
    return s.render(), (79, 35)


def bunny_ears() -> tuple:
    """Just the ears, no band: two soft ears standing on the top of the head, in front of the hair, a little
    back from the brow, wide at the middle and tapering to a round tip, and soft: each is one curve, up out
    of the hair and over at the top, its tip hanging down forward and out, the pink inside only on the part
    that stands. The icon's top edge may clip them. Each casts a small shadow on the hair round its foot
    (`ear_shadow`)."""
    s = Sprite(56, 44)
    white = Material("#f4f0f8", shades=4, texture=0.04)
    pink = Material("#ff9cc0", shades=4, texture=0.03)

    def width(t):
        # Narrow at the foot, widening up to the bend; the hanging flap stays full and ends in a round,
        # oval tip (its last fifth a half ellipse) instead of a cut-off end.
        if t < 0.5:
            full = 1.8 + 4.8 * math.sin(math.pi / 2 * t / 0.5) ** 0.75
        else:
            full = 6.6 - 1.0 * (t - 0.5) / 0.5
        cap = math.sqrt(max(0.0, 1 - ((t - 0.78) / 0.22) ** 2)) if t > 0.78 else 1.0
        return full * cap

    steps = 32
    stand = slice(int(0.1 * steps), int(0.55 * steps) + 1)
    for x, flop in ((15, -1), (41, 1)):
        # One curve: up out of the hair, over at the top, and the tip hanging down forward and out.
        ear = [(x, 34), (x + 1 * flop, 14), (x + 5 * flop, 6), (x + 13 * flop, 26)]
        left, right = sweep(ear, width, steps=steps)
        s.poly(left + right[::-1], white)
        # The pink inside shows on the part that stands; past the bend it's the ear's white back.
        inner_left, inner_right = sweep(ear, lambda t: width(t) * 0.45, steps=steps)
        s.poly(inner_left[stand] + inner_right[stand][::-1], pink, profile="flat")
    return s.render(), (92, 33)


def ear_shadow(out: np.ndarray, kind: np.ndarray, covered: np.ndarray) -> None:
    """The ears' contact shadow: the hair just below and beside each ear's foot a step darker."""
    hero = kind == 0
    below = np.zeros_like(covered)
    for col in np.flatnonzero(covered.any(axis=0)):
        bottom = np.flatnonzero(covered[:, col]).max()
        below[bottom + 1:bottom + 3, max(0, col - 1):col + 2] = True
    shade = below & hero & ~covered
    out[shade] = out[shade] * 0.72

# --- the props -------------------------------------------------------------------------------------------

def pumpkin() -> Image.Image:
    s = Sprite(20, 17)
    orange = Material("#e8781e", shades=5, texture=0.05)
    s.ellipse(5.5, 11, 5, 5.5, orange)
    s.ellipse(14.5, 11, 5, 5.5, orange)
    s.ellipse(10, 10.5, 6, 6, orange)
    s.stroke([(10, 5), (11, 1.5)], 2.6, Material("#5c7a2a", shades=3, texture=0.02))
    img = s.render()
    glow, deep = (255, 228, 120, 255), (255, 168, 52, 255)
    for x, y, c in [(6, 9, glow), (7, 9, glow), (7, 10, deep), (12, 9, glow), (13, 9, glow), (12, 10, deep),
                    (6, 13, deep), (7, 13, glow), (8, 13, glow), (9, 14, glow), (10, 13, glow), (11, 14, glow),
                    (12, 13, glow), (13, 13, deep)]:
        img.putpixel((x, y), c)
    return img


def egg(base: str, stripe: str) -> Image.Image:
    s = Sprite(11, 13)
    s.ellipse(5.5, 6.8, 4.3, 5.8, Material(base, shades=4, texture=0.03, gloss=0.3))
    s.ellipse(5.5, 7.4, 4.0, 1.3, Material(stripe, shades=3, texture=0.0), profile="flat")
    return s.render()


def moon() -> Image.Image:
    """A crescent moon, horns to the right. A full one with two craters read as a face with two eyes."""
    s = Sprite(17, 17)
    x, y = s._grid()
    crescent = ((x - 8.5) ** 2 + (y - 8.5) ** 2 <= 7.5 ** 2) & ((x - 12.2) ** 2 + (y - 6.6) ** 2 > 6.4 ** 2)
    s.mask(crescent, Material("#f6e2a2", shades=4, texture=0.08, grain=2.0))
    return s.render(outline="tinted")


BAT = ["k.......k",
       "kkk.k.kkk",
       ".kkkkkkk.",
       "..kk.kk.."]


def bat(out, kind, x, y, colour) -> None:
    for dy, row in enumerate(BAT):
        for dx, ch in enumerate(row):
            if ch == "k":
                pixels(out, kind, [(x + dx, y + dy)], [colour], (SKY, BLOSSOM, LEAVES))


def plus(x, y):
    return [(x, y), (x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]


# --- the seasons -----------------------------------------------------------------------------------------
# Each draws its props on the recoloured scene and returns what in it gives light (the moon, the pumpkins'
# faces), which the dark icon leaves bright, and what the hero wears, which it lights as his face is lit.

def halloween(out, kind, ramps):
    lit = place(out, moon(), 82, 40, behind=kind == 0)
    deep = hexrgb("#1a0c26")
    for x, y in ((52, 112), (66, 121), (156, 97)):
        bat(out, kind, x, y, deep)
    shadow(out, kind, 70, 90, 166)
    place(out, pumpkin(), 70, 150)
    small = pumpkin().resize((14, 12), Image.NEAREST)
    shadow(out, kind, 148, 161, 166)
    place(out, small, 148, 155)
    sprite, at = witch_hat()
    worn = hat(out, sprite, *at)
    faces = [np.array(c[:3]) / 255 for c in ((255, 228, 120), (255, 168, 52))]
    return lit | np.any([np.all(np.abs(out - c) < 1e-6, axis=2) for c in faces], axis=0), worn


def christmas(out, kind, ramps):
    snow = [hexrgb(c) for c in SNOW]
    # Snow on the lit tops of the leaves' clusters: their lightest colour turns to snow, the next to its shadow.
    leaves = ramps[LEAVES]
    for y, x in np.argwhere(kind == LEAVES):
        c = out[y, x]
        if np.allclose(c, leaves[-1]):
            out[y, x] = snow[4]
        elif len(leaves) > 2 and np.allclose(c, leaves[-2]):
            out[y, x] = snow[2]
    flakes = [(90, 46), (62, 108), (54, 124), (160, 96), (74, 126), (160, 126)]
    for x, y in flakes:
        pixels(out, kind, plus(x, y), [snow[4]] * 5, (SKY, BLOSSOM, LEAVES, BRANCHES))
    sprite, at = santa_hat()
    return np.zeros(kind.shape, bool), hat(out, sprite, *at)


def easter(out, kind, ramps):
    # Flowers in the meadow: a cross of petals round a gold centre, clear of the eggs.
    petals = [hexrgb("#ffffff"), hexrgb("#ffd6ea"), hexrgb("#e6d4ff")]
    for i, (x, y) in enumerate([(52, 150), (95, 160), (158, 150), (66, 162)]):
        pixels(out, kind, plus(x, y), [hexrgb("#ffc83a")] + [petals[i % 3]] * 4, (GRASS, DARK))
    for (base, stripe), x, y in ((("#ff9cc4", "#7cc8ff"), 69, 153), (("#9ce08a", "#ffd25a"), 79, 156),
                                 (("#b8a4ff", "#ff9c9c"), 149, 154)):
        shadow(out, kind, x + 1, x + 9, y + 12)
        place(out, egg(base, stripe), x, y)
    sprite, at = bunny_ears()
    worn = place(out, sprite, *at)
    ear_shadow(out, kind, worn)
    return np.zeros(kind.shape, bool), worn


DRAW = {"Halloween": halloween, "Christmas": christmas, "Easter": easter}

# --- at night --------------------------------------------------------------------------------------------
# The dark icons (iOS 18's Dark Mode Home Screen), made as the app icon's dark one is (app_icon_art.dusk):
# the season's sky at night in three bands, the rest darker and cooler, moonlight on the hero's face, his
# gold still warm, pale things (snow, the ears) catching the moon, and the season's lights in hard steps.

NIGHTS = {
    "Halloween": [("#120a22", "#1a0f30"), ("#221238", "#2c1846"), ("#3e1636", "#4e1e40")],
    "Christmas": [("#0c1634", "#122044"), ("#142650", "#1a305e"), ("#1c3a62", "#244872")],
    "Easter": [("#2b1f61", "#352872"), ("#122154", "#1a2c66"), ("#0a3340", "#10404e")],
}
WARM, EMBER = (1.0, 0.86, 0.5), (1.0, 0.6, 0.2)
FAIRY = [(1.0, 0.84, 0.36), (1.0, 0.42, 0.38), (0.5, 0.86, 1.0), (1.0, 0.84, 0.36)]


def cornered(ox: int, oy: int, size: int = 128, r: int = 29) -> bool:
    """True where iOS rounds the icon's corner off."""
    cx, cy = min(max(ox, r), size - 1 - r), min(max(oy, r), size - 1 - r)
    return (ox - cx) ** 2 + (oy - cy) ** 2 > r * r


def spark(out, x, y, colour, size=1) -> None:
    """A light: a bright pixel, a step of glow on each side and a fainter one on the diagonals (a firefly,
    a fairy light); `size` 0 is the pixel alone (a star)."""
    def put(px, py, mix):
        ox, oy = px - BOX[0], py - BOX[1]
        if 0 <= ox < out.shape[1] and 0 <= oy < out.shape[0]:
            out[oy, ox] = out[oy, ox] * (1 - mix) + np.array(colour) * mix
    if size:
        for dx, dy in ((1, 1), (1, -1), (-1, 1), (-1, -1)):
            put(x + dx, y + dy, 0.3)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            put(x + dx, y + dy, 0.6)
    put(x, y, 1.0)


def halo(out, keep, x, y, colour, radius) -> None:
    """Light thrown round something bright, in two hard steps, on all but `keep`."""
    ys, xs = np.mgrid[0:out.shape[0], 0:out.shape[1]]
    far = np.hypot(xs - (x - BOX[0]), ys - (y - BOX[1]))
    for reach, mix in ((radius, 0.14), (radius * 0.55, 0.16)):
        ring = (far <= reach) & ~keep
        out[ring] = out[ring] * (1 - mix) + np.array(colour) * mix


def spots(kind, cover, allowed, count, seed, gap=9) -> list:
    """`count` places on `allowed` classes, none on a prop or in a rounded corner, at least `gap` apart,
    the same every run."""
    rng = np.random.default_rng(seed)
    ys, xs = np.nonzero(np.isin(kind, allowed) & ~cover)
    chosen = []
    for i in rng.permutation(len(xs)):
        ox, oy = xs[i], ys[i]
        if cornered(ox, oy) or ox < 3 or oy < 3 or ox > 124 or oy > 124:
            continue
        if all((ox - a) ** 2 + (oy - b) ** 2 >= gap * gap for a, b in chosen):
            chosen.append((ox, oy))
        if len(chosen) == count:
            break
    return [(a + BOX[0], b + BOX[1]) for a, b in chosen]


def at_night(season, rgb, kind, day, out, lit, worn) -> np.ndarray:
    h, w = kind.shape
    ys, xs = np.mgrid[0:h, 0:w]
    # The sky, where it still shows: each day band's colour to the night's, its light shade to the light.
    sky = np.zeros((h, w), bool)
    night = out.copy()
    for band, (dark, light) in enumerate(SEASONS[season]["sky"]):
        rows = np.minimum(ys * 3 // h, 2) == band
        for shade, to in ((dark, NIGHTS[season][band][0]), (light, NIGHTS[season][band][1])):
            hit = rows & (kind == SKY) & np.all(np.abs(out - hexrgb(shade)) < 1e-6, axis=2)
            night[hit], sky = hexrgb(to), sky | hit
    # The rest by moonlight, brightest on the face and in three steps out from it.
    fx, fy = app_icon_art.FACE[0] - BOX[0], app_icon_art.FACE[1] - BOX[1]
    near = np.exp(-(((xs - fx) ** 2 + (ys - fy) ** 2) / (2 * (w * 0.32) ** 2)))[..., None]
    near = np.round(near * 2) / 2
    cool, warm = np.array([0.62, 0.68, 0.92]), np.array([0.95, 0.86, 0.78])
    tone = cool * (1 - 0.6 * near) + warm * (0.6 * near)
    rest = out * tone * (0.42 + 0.48 * near)
    # Pale things catch the moon: snow, fur, the ears stay a pale moonlit blue.
    luma = out @ np.array([0.299, 0.587, 0.114])
    pale = (luma > 0.78) & (out.max(axis=2) - out.min(axis=2) < 0.2)
    rest = np.where(pale[..., None], out * np.array([0.66, 0.74, 0.96]) * 0.86, rest)
    gold = app_icon_art.is_gold(rgb) & (kind == 0) & np.all(np.abs(out - rgb) < 1e-6, axis=2)
    rest = np.where(gold[..., None], out * np.array([0.92, 0.82, 0.62]), rest)
    # What he wears catches the light as his face does, a little brighter than his hair, so it still reads.
    rest = np.where(worn[..., None], out * np.array([0.9, 0.86, 0.92]), rest)
    night = np.where((sky | lit)[..., None], night, rest)
    night[lit] = out[lit]
    keep = (kind == 0) | lit
    cover = np.any(np.abs(out - day) > 1e-6, axis=2)
    if season == "Halloween":
        halo(night, keep | ~sky, 90, 48, WARM, 13)
        for x, y, r in ((80, 160, 12), (155, 161, 9)):
            halo(night, keep, x, y, EMBER, r)
        night[lit] = out[lit]
        for x, y in spots(kind, cover | ~sky, (SKY,), 6, 31):
            spark(night, x, y, (0.95, 0.9, 1.0), 0)
    elif season == "Christmas":
        for x, y in spots(kind, cover | ~sky, (SKY,), 6, 7):
            spark(night, x, y, (0.95, 0.96, 1.0), 0)
        for i, (x, y) in enumerate(spots(kind, cover, (LEAVES, BLOSSOM), 9, 12, gap=12)):
            spark(night, x, y, FAIRY[i % len(FAIRY)])
    else:
        for x, y in spots(kind, cover | ~sky, (SKY,), 5, 3):
            spark(night, x, y, (0.95, 0.96, 1.0), 0)
        for x, y in spots(kind, cover, (LEAVES, BLOSSOM, GRASS, BRANCHES), 9, 5, gap=13):
            spark(night, x, y, app_icon_art.FIREFLY)
    return night


def icon(season: str) -> tuple:
    """The season's icon by day and at night, and the night's greys for the tinted icon."""
    rgb = app_icon_art.crop(BOX)
    kind = classes(rgb)
    day, ramps = recolour(rgb, kind, SEASONS[season])
    out = day.copy()
    lit, worn = DRAW[season](out, kind, ramps)
    dark = at_night(season, rgb, kind, day, out, lit, worn)
    tinted = app_icon_art.tint(dark, (kind == 0) | worn, out, lit)
    return tuple(scale(image) for image in (out, dark, tinted))


def scale(rgb: np.ndarray) -> Image.Image:
    big = np.repeat(np.repeat(rgb, SCALE, axis=0), SCALE, axis=1)
    return Image.fromarray((np.clip(big, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB")


def write(season: str, images: tuple) -> Path:
    """The icon set: by day (every iOS), at night (Dark Mode, iOS 18) and in greys (Tinted), as AppIcon's."""
    folder = ASSETS / f"AppIcon-{season}.appiconset"
    folder.mkdir(exist_ok=True)
    entries = []
    for image, suffix, look in zip(images, ("", "-Dark", "-Tinted"), (None, "dark", "tinted")):
        name = f"AppIcon-{season}{suffix}.png"
        image.save(folder / name, optimize=True)
        entry = {"filename": name, "idiom": "universal", "platform": "ios", "size": "1024x1024"}
        if look:
            entry = {"appearances": [{"appearance": "luminosity", "value": look}], **entry}
        entries.append(entry)
    (folder / "Contents.json").write_text(json.dumps({"images": entries, "info": {"author": "xcode", "version": 1}},
                                                     indent=2) + "\n")
    return folder


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--preview", type=Path, help="write each by day and at night at Home Screen sizes here, beside the app icon")
    args = parser.parse_args()
    made = {}
    for season in SEASONS:
        made[season] = icon(season)
        print(f"wrote {write(season, made[season]).relative_to(ROOT)}")
    if args.preview:
        sizes = [300, 120, 60]
        rows = [Image.open(app_icon_art.LIGHT).convert("RGB"), Image.open(app_icon_art.DARK).convert("RGB")]
        rows += [image for day, dark, _ in made.values() for image in (day, dark)]
        half = sum(sizes) + 10 * (len(sizes) + 1)
        sheet = Image.new("RGB", (2 * half, (len(rows) // 2) * 320), (242, 242, 247))
        for index, image in enumerate(rows):
            x = 10 + (index % 2) * half
            if index % 2:
                sheet.paste((28, 28, 30), (half, (index // 2) * 320, 2 * half, (index // 2 + 1) * 320))
            for side in sizes:
                sheet.paste(app_icon_art.rounded(image, side), (x, 10 + (index // 2) * 320))
                x += side + 10
        sheet.save(args.preview)
        print(f"preview in {args.preview}: the app icon, then {', '.join(made)}; by day left, at night right")


if __name__ == "__main__":
    main()
