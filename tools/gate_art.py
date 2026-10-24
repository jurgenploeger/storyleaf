#!/usr/bin/env python3
"""Each town's own gate over the roads through its wall or fence (maps.json town `gate`), drawn in code with
tools/pixel_kit.py in the game's pixel style (docs/pixel-style.md), where every town had RD's one stone
`town_gate` (which quests' gates across borders keep):

- Meadowbrook's: a farm village's lychgate, braced oak posts on stone footings under a little thatched
  roof, roses climbing them, a sign with a rose on it hanging from the beam.
- Prismhaven's: the rainbow city's, pale cut stone, the pillars capped, a crystal set in the keystone, a
  banner in the rainbow's colours under it.
- Ingothold's: the desert miners' city, sandstone banded in gold, red cloth hanging down the pillars, a
  gold medallion with crossed pickaxes over the way in.
- Larkspur's: painted pale blue boards with a white rail and curled brackets, lilac at the posts' feet, a
  bluebird perched on the sign over the way in.

    python3 tools/gate_art.py                   # all → art/sprites/gate_<town>.png
    python3 tools/gate_art.py gate_larkspur     # just these
    python3 tools/gate_art.py --sheet out.png   # at 4×, each as drawn and widened over a wide road

Each is 70 × 51 pixels, laid out as the town gate is, since `TownFence.widened` spans a wide road by its
parts (shares of the picture): a pillar at each side (27 of its 70 pixels), the lintel across rows 2 to
11 (its outline too), and between the pillars whatever hangs from it (rows 0 to 31, its middle 16 pixels), set over a beam
laid from the lintel's stretch at x 14 to 25 repeated. So the lintel is the same all along there (its
joints every 6 pixels), nothing between the pillars hangs below row 31, and the picture's box is all 70 ×
51 (`TownFence.cropped` trims to it). `--sheet` shows each widened as the game does it. Scored against
RD's buildings: `python3 tools/pixel_style.py check --kind building art/sprites/gate_<town>.png`.
"""

import math
import pathlib
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from pixel_kit import Material, Sprite, limit_palette  # noqa: E402
from scenery_art import SIDE_LIGHT, foliage  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPRITES = ROOT / "art" / "sprites"

W, H = 70, 51
# The parts `TownFence.widened` cuts the picture into (its `pillar`, `hangs`, `beam` and `stones`).
PILLAR, HANGS, BEAM, STONES = 27, 32, (2, 12), (14, 26)


def scene():
    s = Sprite(W, H)
    s.light, s.rim, s.seams = SIDE_LIGHT, "lower", False
    return s


def flat(colour, texture=0.0):
    return Material(colour, texture=texture, variety=0)


def joints(s, mat, top, bottom, every=6, start=2):
    """Upright joints down a lintel every `every` pixels, on the same columns all along it (2, 8, 14,
    20, 26, …), so the beam laid from its stretch at 14 to 25 runs on with them."""
    for x in range(start, W, every):
        s.stroke([(x + 0.5, top), (x + 0.5, bottom)], 0.8, mat, profile="flat")


def courses(s, mat, x0, x1, y0, y1, every=5, offset=0):
    """Mortar lines across a pillar of cut stone: a joint every `every` rows, the upright joints between
    blocks staggered from course to course."""
    for k, y in enumerate(range(y0 + every, y1, every)):
        s.stroke([(x0, y + 0.5), (x1, y + 0.5)], 0.7, mat, profile="flat")
    for k, y in enumerate(range(y0, y1 - 1, every)):
        x = x0 + (x1 - x0) * (0.33 if (k + offset) % 2 else 0.66)
        s.stroke([(x, y + 1), (x, min(y1, y + every))], 0.7, mat, profile="flat")


def tufts(s, xs, mats, foot=H - 0.5):
    """Grass at a post's foot: a few blades up from the ground, as the town gate's."""
    for k, x in enumerate(xs):
        tall = (3.5, 2.5, 4.5, 3)[k % 4]
        s.stroke([(x, foot), (x + (0.6 if k % 2 else -0.6), foot - tall)], 0.9, mats[k % len(mats)], profile="flat")


# ------------------------------------------------------------------------------------------ Meadowbrook

def gate_meadowbrook():
    s, o = scene(), scene()               # its frame (posts, braces, lintel) and what goes over the lintel
    oak, oak_dark = Material("#94603a", texture=0.06), flat("#5e3a22")
    stone = Material("#9a968e", texture=0.05)
    leaf, rose, rose_lit = foliage("#4f8a34"), Material("#e05a7a", texture=0.0), Material("#f6a0b4", texture=0.0)
    grass = [flat("#3f7a2a"), flat("#5a9a38")]
    for x0, inner in ((3, 1), (58, -1)):                         # the posts, on stone footings
        s.poly([(x0 - 2, H), (x0 + 11, H), (x0 + 10, H - 5), (x0 - 1, H - 5)], stone, bulge=1.4)
        s.poly([(x0, H - 5), (x0 + 9, H - 5), (x0 + 9, 11), (x0, 11)], oak, profile="cylinder", bulge=1.6)
        s.stroke([(x0 + 6.5, H - 7), (x0 + 6.5, 14)], 0.7, oak_dark, profile="flat")       # a split down the grain
        # A knee brace from the post up to the beam, on the side toward the road.
        xi = x0 + 9 if inner > 0 else x0
        s.stroke([(xi - inner * 0.5, 22), (xi + inner * 9, 12)], 2.2, oak)
    # The lintel, rows 3 … 10 (its outline on 2 and 11): the thatch combed down in bundles, its eave in
    # shadow, the beam under it.
    s.poly([(0, 3), (W, 3), (W, 7.5), (0, 7.5)], Material("#d8b25e", texture=0.06, variety=0), profile="flat", tone=0.66)
    s.poly([(0, 3), (W, 3), (W, 4), (0, 4)], flat("#ecd28a"), profile="flat", tone=0.8)
    for x in range(0, W, 3):
        s.stroke([(x + 1.5, 4.2), (x + 1.5, 6.6)], 0.8, flat("#9a7030"), profile="flat")
    s.poly([(0, 6.8), (W, 6.8), (W, 7.6), (0, 7.6)], flat("#7a5a2a"), profile="flat")
    s.poly([(0, 7.6), (W, 7.6), (W, 11), (0, 11)], Material("#94603a", texture=0.06, variety=0), profile="flat", tone=0.52)
    s.poly([(0, 7.6), (W, 7.6), (W, 8.4), (0, 8.4)], flat("#5e3a22"), profile="flat")      # the eave's shadow on it
    joints(s, oak_dark, 8.6, 10.4)
    # Over it: the thatch's ends rounded over the posts, roses up the posts and along the beam's ends.
    straw = Material("#d8b25e", texture=0.03)
    for x0 in (0, W - 7):
        o.poly([(x0, 2), (x0 + 7, 2), (x0 + 7, 7.6), (x0, 7.6)], straw, bulge=1.2)
    for x0 in (3, 58):
        o.ellipse(x0 + 4.5, 1.6, 2.2, 1.6, straw)                    # the ridge's knob over each post
        for k, y in enumerate(range(16, 46, 4)):
            x = x0 + (1.0 if k % 2 else 8.0)
            o.ellipse(x, y, 2.0, 1.6, leaf[k % 3])
            if k % 2 == 0:
                o.ellipse(x + 0.3, y - 0.5, 1.2, 1.0, rose if k % 4 else rose_lit)
    for x in (3, 7, 62, 66):
        o.ellipse(x, 11.5, 1.6, 1.3, leaf[1])
        o.ellipse(x + 0.4, 11, 1.0, 0.9, rose)
    # In the middle: the sign, hung on two short chains, a painted rose on it.
    chain = flat("#4a4048")
    for x in (30.5, 39.5):
        o.stroke([(x, 12), (x, 16)], 0.7, chain, profile="flat")
    o.poly([(28.5, 16), (41.5, 16), (41.5, 26), (28.5, 26)], Material("#c8945a", texture=0.04), bulge=0.8)
    o.poly([(28.5, 25), (41.5, 25), (41.5, 26), (28.5, 26)], oak_dark, profile="flat")
    for k in range(5):
        ang = k * 2 * math.pi / 5 - math.pi / 2
        o.ellipse(35 + 2.3 * math.cos(ang), 20.8 + 2.0 * math.sin(ang), 1.4, 1.3, rose)
    o.ellipse(35, 20.8, 1.1, 1.1, Material("#f2d050", texture=0.0))
    tufts(o, (1, 4, 12, 14, 56, 58, 66, 68), grass)
    return s, o


# ------------------------------------------------------------------------------------------ Prismhaven

RAINBOW = ("#e04848", "#f08a30", "#f2cc40", "#5cb84c", "#3c8ae0", "#8a56d0")


def gate_prismhaven():
    s, o = scene(), scene()
    stone, mortar = Material("#bdb2da", texture=0.07), flat("#685c8c")
    cap = Material("#a89cc8", texture=0.04)
    gold = Material("#e8c048", texture=0.0, gloss=0.6)
    grass = [flat("#3f7a2a"), flat("#5a9a38")]
    for x0 in (2, 57):                                           # the pillars, cut stone in courses
        s.poly([(x0 - 2, H), (x0 + 13, H), (x0 + 12, H - 5), (x0 - 1, H - 5)], cap, bulge=1.3)    # the plinth
        s.poly([(x0, H - 5), (x0 + 11, H - 5), (x0 + 11, 15), (x0, 15)], stone, profile="cylinder", bulge=1.6)
        courses(s, mortar, x0 + 0.5, x0 + 10.5, 15, H - 5, offset=x0 // 5)
        s.poly([(x0 - 1.5, 15.5), (x0 + 12.5, 15.5), (x0 + 12.5, 12), (x0 - 1.5, 12)], cap, bulge=1.2)     # its capital
    # The lintel, rows 3 … 10 (its outline on 2 and 11): a lit moulding along its top, a frieze of blocks,
    # a dentil row under it.
    s.poly([(0, 3), (W, 3), (W, 4.6), (0, 4.6)], flat("#f4eefc"), profile="flat", tone=0.9)
    s.poly([(0, 4.6), (W, 4.6), (W, 11), (0, 11)], Material("#bdb2da", texture=0.06, variety=0), profile="flat", tone=0.6)
    s.poly([(0, 4.6), (W, 4.6), (W, 5.3), (0, 5.3)], mortar, profile="flat")
    joints(s, mortar, 5.5, 8.4)
    s.poly([(0, 8.5), (W, 8.5), (W, 9.2), (0, 9.2)], mortar, profile="flat")
    for x in range(2, W, 3):                                     # the dentils: little blocks in a row
        s.poly([(x, 9.2), (x + 1.9, 9.2), (x + 1.9, 11), (x, 11)], flat("#a89cc8"), profile="flat", tone=0.5)
    # Over it: each pillar's cap rising above the lintel, a gold knob on it.
    for x0 in (2, 57):
        o.poly([(x0 - 0.5, 3.5), (x0 + 11.5, 3.5), (x0 + 9, 0), (x0 + 2, 0)], cap, bulge=1.2)
        o.ellipse(x0 + 5.5, 1.0, 1.4, 1.0, gold)
    # In the middle: the keystone, a crystal set in it, and a banner in the rainbow's colours under it.
    o.poly([(29.5, 0), (40.5, 0), (39, 15), (31, 15)], cap, bulge=1.5)
    crystal = [Material(c, texture=0.0, gloss=0.9) for c in ("#8ad8ff", "#e8c8ff")]
    o.poly([(35, 1), (38.6, 6.5), (35, 12.5), (31.4, 6.5)], crystal[0], profile="facet")
    o.poly([(35, 1), (38.6, 6.5), (35, 7)], crystal[1], profile="flat", tone=0.86)
    for k, colour in enumerate(RAINBOW):
        x = 30 + k * 10 / len(RAINBOW)
        foot = 30.5 - abs(k - 2.5) * 1.2                     # a point at its foot
        o.poly([(x, 16), (x + 10 / len(RAINBOW) + 0.05, 16), (x + 10 / len(RAINBOW) + 0.05, foot), (x, foot)],
               Material(colour, texture=0.0), profile="flat", tone=0.64)
    o.stroke([(29, 16), (41, 16)], 1.4, gold, profile="cylinder")
    tufts(o, (1, 4, 14, 15, 55, 56, 68, 69), grass)
    return s, o


# ------------------------------------------------------------------------------------------ Ingothold

def gate_ingothold():
    s, o = scene(), scene()
    sand, sand_dark = Material("#dcae72", texture=0.05), flat("#a87848")
    gold = Material("#ecc244", texture=0.0, gloss=0.6)
    cloth, cloth_dark = Material("#c03a32", texture=0.03), flat("#80241e")
    scrub = [flat("#7a8a3a"), flat("#9aa04a")]
    for x0 in (1, 57):                                           # sandstone pillars, banded in gold
        s.poly([(x0 - 1, H), (x0 + 13, H), (x0 + 13, H - 4), (x0 - 1, H - 4)], sand, bulge=1.3)
        s.poly([(x0, H - 4), (x0 + 12, H - 4), (x0 + 12, 12), (x0, 12)], sand, profile="cylinder", bulge=1.6)
        courses(s, sand_dark, x0 + 0.5, x0 + 11.5, 12, H - 4, every=6, offset=x0 // 5)
        for y in (14, 41):
            s.poly([(x0 - 0.5, y), (x0 + 12.5, y), (x0 + 12.5, y + 1.8), (x0 - 0.5, y + 1.8)], gold, profile="cylinder")
    # The lintel, rows 3 … 10 (its outline on 2 and 11): sandstone blocks between two gold trims, joints
    # every 6.
    s.poly([(0, 3), (W, 3), (W, 11), (0, 11)], Material("#dcae72", texture=0.06, variety=0), profile="flat", tone=0.62)
    s.poly([(0, 3), (W, 3), (W, 4.3), (0, 4.3)], flat("#ecc244"), profile="flat", tone=0.82)
    s.poly([(0, 9.7), (W, 9.7), (W, 11), (0, 11)], flat("#ecc244"), profile="flat", tone=0.5)
    joints(s, sand_dark, 4.6, 9.4)
    # Over it: a stepped crown on each pillar, red cloth hanging down its face.
    for x0 in (1, 57):
        o.poly([(x0, 3.5), (x0 + 12, 3.5), (x0 + 12, 1.5), (x0 + 10, 1.5), (x0 + 10, 0), (x0 + 2, 0), (x0 + 2, 1.5),
                (x0, 1.5)], sand, bulge=1.2)
        o.poly([(x0 + 3, 12), (x0 + 9, 12), (x0 + 9, 32), (x0 + 6, 35.5), (x0 + 3, 32)], cloth, bulge=0.7)
        o.stroke([(x0 + 3.6, 13), (x0 + 3.6, 31)], 0.6, cloth_dark, profile="flat")
        o.stroke([(x0 + 2.5, 12.6), (x0 + 9.5, 12.6)], 1.2, gold, profile="cylinder")
        o.ellipse(x0 + 6, 22, 1.7, 1.7, gold)
    # In the middle: a gold medallion over the way in, two dark pickaxes crossed on it.
    o.ellipse(35, 8, 6.6, 6.6, gold)
    o.ellipse(35, 8, 5.0, 5.0, Material("#f4d870", texture=0.0), profile="flat")
    handle, head = flat("#5a3a22"), flat("#3e3c48")
    for a_, b_ in (((31.5, 11.5), (38.5, 4.5)), ((38.5, 11.5), (31.5, 4.5))):
        o.stroke([a_, b_], 1.1, handle, profile="flat")
    o.stroke([(36.4, 3.0), (39.2, 3.6), (40.4, 6.2)], 1.2, head, profile="flat")         # the heads, curved picks
    o.stroke([(33.6, 3.0), (30.8, 3.6), (29.6, 6.2)], 1.2, head, profile="flat")
    tufts(o, (0, 3, 14, 55, 59, 69), scrub)
    return s, o


# ------------------------------------------------------------------------------------------ Larkspur

def gate_larkspur():
    s, o = scene(), scene()
    paint, paint_dark = Material("#8cbce4", texture=0.03), flat("#4c78a8")
    white, white_dark = Material("#f2f0ea", texture=0.0), flat("#a8b0c0")
    lilac, lilac_lit = Material("#a07ad8", texture=0.0), Material("#d0b4f4", texture=0.0)
    leaf = foliage("#5a9a3e")
    grass = [flat("#3f7a2a"), flat("#5a9a38")]
    for x0, inner in ((3, 1), (59, -1)):                         # painted posts on white feet, braced
        s.poly([(x0 - 1.5, H), (x0 + 9.5, H), (x0 + 9.5, H - 3), (x0 - 1.5, H - 3)], white, bulge=1.0)
        s.poly([(x0, H - 3), (x0 + 8, H - 3), (x0 + 8, 11), (x0, 11)], paint, profile="cylinder", bulge=1.6)
        s.stroke([(x0 + 2.5, H - 5), (x0 + 2.5, 14)], 0.6, paint_dark, profile="flat")             # a groove
        xi = x0 + 8 if inner > 0 else x0
        # A white bracket with a curl, from the post up under the beam.
        s.stroke([(xi, 20), (xi + inner * 3.5, 14.5), (xi + inner * 9, 12)], 1.6, white)
    # The lintel, rows 3 … 10 (its outline on 2 and 11): a white rail along its top, blue boards with joints
    # every 6, a white trim under them.
    s.poly([(0, 3), (W, 3), (W, 4.6), (0, 4.6)], flat("#f2f0ea"), profile="flat", tone=0.86)
    s.poly([(0, 4.6), (W, 4.6), (W, 9.6), (0, 9.6)], Material("#8cbce4", texture=0.06, variety=0), profile="flat", tone=0.6)
    s.poly([(0, 9.6), (W, 9.6), (W, 11), (0, 11)], flat("#f2f0ea"), profile="flat", tone=0.55)
    s.poly([(0, 4.6), (W, 4.6), (W, 5.3), (0, 5.3)], white_dark, profile="flat")
    joints(s, paint_dark, 5.5, 9.2)
    # Over it: a little white point on each post, lilac at the posts' feet.
    for x0 in (3, 59):
        o.poly([(x0 + 1, 3), (x0 + 7, 3), (x0 + 4, 0)], white)
        for k, (dx, y) in enumerate(((-1.5, 46), (9.5, 45), (-1, 41), (10, 40), (-0.5, 36))):
            o.ellipse(x0 + dx, y, 2.2, 1.7, leaf[k % 3])
            o.ellipse(x0 + dx + 0.3, y - 1.3, 1.2, 1.7, lilac if k % 2 else lilac_lit)
    # In the middle: a white board hung from the lintel, a blue panel on it, a bluebird perched on top.
    for x in (30.5, 39.5):
        o.stroke([(x, 12), (x, 17)], 0.7, white_dark, profile="flat")
    o.poly([(28.5, 17), (41.5, 17), (41.5, 26), (28.5, 26)], white, bulge=0.8)
    o.poly([(28.5, 25), (41.5, 25), (41.5, 26), (28.5, 26)], white_dark, profile="flat")
    o.poly([(30, 18.5), (40, 18.5), (40, 24), (30, 24)], paint, profile="flat", tone=0.6)        # a blue panel on it
    bird, breast = Material("#3a72d8", texture=0.0), Material("#f08a48", texture=0.0)
    o.ellipse(33.8, 13.6, 4.2, 3.0, bird)                        # its body, sat on the board's top edge
    o.ellipse(34.4, 14.6, 2.6, 1.8, breast)                      # its rusty breast
    o.ellipse(37.6, 11.0, 2.2, 2.0, bird)                        # its head
    o.ellipse(38.2, 10.6, 0.5, 0.5, flat("#1a1a24"), profile="flat")
    o.poly([(39.6, 10.8), (41.6, 11.4), (39.6, 12.0)], flat("#e8b040"))
    o.poly([(30.2, 13.2), (27.6, 11.0), (28.4, 14.8)], bird, profile="flat", tone=0.45)          # its tail
    o.stroke([(32.6, 12.6), (35.8, 12.2)], 0.8, flat("#2a52a8"), profile="flat")                 # a wing's edge
    tufts(o, (0, 4, 13, 57, 61, 69), grass)
    return s, o


GATES = {"gate_meadowbrook": gate_meadowbrook, "gate_prismhaven": gate_prismhaven,
         "gate_ingothold": gate_ingothold, "gate_larkspur": gate_larkspur}


def compose(parts):
    """The gate from its frame and what goes over it, each rendered on its own: the frame's lintel laid
    afresh from its stretch at x 14 to 25, repeated all along (its two end columns, the outline, kept), as
    the beam is when it's widened (the kit's dither and grain differ a little along it); then what goes
    over it, kept off that stretch: the pillars' caps and dress at its ends, the middle's ornament."""
    frame, front = (part.render(outline="tinted") for part in parts)
    a = np.asarray(frame).copy()
    tile = a[BEAM[0]:BEAM[1], STONES[0]:STONES[1]].copy()
    for x in range(1, W - 1):
        a[BEAM[0]:BEAM[1], x] = tile[:, (x - STONES[0]) % tile.shape[1]]
    img = Image.fromarray(a, "RGBA")
    img.alpha_composite(front)
    # A palette of RD's buildings' size (`pixel_style.py check --kind building`: at most 1.4 colours a 100 pixels).
    return limit_palette(img, int((np.asarray(img)[..., 3] > 0).sum() * 1.35 / 100))


def fitted(img):
    """The picture checked against `TownFence.widened`'s layout: all 70 × 51 of its box used, so the shares
    fall where they're drawn, and the lintel the same at both ends of the stretch the beam's laid from."""
    a = np.asarray(img)
    box = img.getbbox()
    assert box == (0, 0, W, H), f"its box is {box}, not the whole {W} × {H}"
    left, right = a[BEAM[0]:BEAM[1], STONES[0]], a[BEAM[0]:BEAM[1], STONES[1]]
    differ = int((left != right).any(axis=1).sum())
    assert differ == 0, f"the lintel differs in {differ} rows where the beam's stretch starts and ends"
    # What hangs in the middle stays in it (between the pillars' parts, above row 32), as it's all of it
    # that's kept when the gate's widened.
    alpha = a[..., 3] > 0
    assert not alpha[BEAM[1]:HANGS, [PILLAR - 1, W - PILLAR]].any(), "what hangs in the middle spills into the pillars"
    assert not alpha[HANGS:, PILLAR:W - PILLAR].any(), "something hangs below row 32 between the pillars"
    return img


def widened(img, width):
    """As `TownFence.widened` spans a road `width` pixels wide (in the picture's pixels): its pillars at
    either end, the beam laid from the lintel's stretch across between, what hangs in the middle over it."""
    w, h = img.size
    if width <= w:
        return img
    out = Image.new("RGBA", (width, h), (0, 0, 0, 0))
    block = img.crop((STONES[0], BEAM[0], STONES[1], BEAM[1]))
    for x in range(PILLAR - 2, width - PILLAR + 2, block.width):
        piece = block.crop((0, 0, min(block.width, width - PILLAR + 2 - x), block.height))
        out.alpha_composite(piece, (x, BEAM[0]))
    out.alpha_composite(img.crop((0, 0, PILLAR, h)), (0, 0))
    out.alpha_composite(img.crop((w - PILLAR, 0, w, h)), (width - PILLAR, 0))
    banner = img.crop((PILLAR, 0, w - PILLAR, HANGS))
    out.alpha_composite(banner, ((width - banner.width) // 2, 0))
    return out


def main(argv):
    sheet = None
    if "--sheet" in argv:
        i = argv.index("--sheet")
        sheet = argv[i + 1]
        argv = argv[:i] + argv[i + 2:]
    out = {}
    for name in argv or list(GATES):
        img = fitted(compose(GATES[name]()))
        img.save(SPRITES / f"{name}.png")
        out[name] = img
    print(f"wrote {', '.join(out)} to art/sprites/")
    if sheet:
        k = 4
        town = Image.open(SPRITES / "town_gate.png").convert("RGBA")
        rows = [(town.crop(town.getbbox()), widened(town.crop(town.getbbox()), 120))]
        rows += [(img, widened(img, 120)) for img in out.values()]
        board = Image.new("RGBA", ((W + 120 + 24) * k, len(rows) * (H + 8) * k + 8 * k), (106, 150, 86, 255))
        for n, (img, wide) in enumerate(rows):
            y = (8 + n * (H + 8)) * k
            board.alpha_composite(img.resize((img.width * k, img.height * k), Image.NEAREST), (8 * k, y))
            board.alpha_composite(wide.resize((wide.width * k, wide.height * k), Image.NEAREST), ((W + 16) * k, y))
        board.save(sheet)
        print(f"sheet in {sheet}")


if __name__ == "__main__":
    main(sys.argv[1:])
