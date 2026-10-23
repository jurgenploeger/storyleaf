#!/usr/bin/env python3
"""Scenery of its own kind, drawn in code with tools/pixel_kit.py, where the game had palette swaps of one
sprite: every tree a recolour of RD's round `tree`, every bush of its `berry_bush`. Each species here has a
shape of its own (a willow droops, a cherry spreads, a birch stands tall and pale, a dead tree twists),
so the lands look different by more than their colours.

Each drawing writes art/sprites/<id>.png, which wins over the asset's `derive` in the game
(ArtLibrary.sourceImage), and its big version (`big_<id>`, derived from it at a larger `scale`) follows.
Scored against RD's scenery: `python3 tools/pixel_style.py check --kind scenery art/sprites/<id>.png`.
`--sheet out.png` previews them beside RD's `tree` and `berry_bush`; `ids...` redraws only those.
Needs pillow + numpy. docs/pixel-style.md has the rules.
"""

import math
import pathlib
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from pixel_kit import Material, Sprite  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPRITES = ROOT / "art" / "sprites"


def rng(seed):
    return np.random.default_rng(seed)


def shade_of(hexcode, k):
    """`hexcode` k times as light (k < 1 darker, a touch more saturated and cooler)."""
    import colorsys
    r, g, b = (int(hexcode.lstrip("#")[i:i + 2], 16) / 255 for i in (0, 2, 4))
    h, sat, v = colorsys.rgb_to_hsv(r, g, b)
    if k < 1:
        sat, h = min(1, sat * (1 + (1 - k) * 0.5)), h + (1 - k) * 0.04 * (1 if (h * 360 - 50) % 360 < 180 else -1)
    else:
        sat = sat * (1 - (k - 1) * 0.6)
    r, g, b = colorsys.hsv_to_rgb(h % 1, sat, min(1, v * k))
    return "#%02x%02x%02x" % tuple(int(c * 255) for c in (r, g, b))


def foliage(hexcode, texture=0.03):
    """A leaf colour's three materials: in the light (top left of a canopy), middle, and in its shadow."""
    return [Material(shade_of(hexcode, k), texture=texture, shades=6, variety=1.5) for k in (1.2, 1.0, 0.78, 1.42)]


def puffs(s, cx, cy, rx, ry, mats, count, size, seed, flat=1.0, skip=None, bulge=3.0):
    """A canopy as RD paints one: clusters of leaves, each a small dome lit on its own, scattered over an
    ellipse from the back (top) to the front (bottom), so each lower cluster overlaps the one behind it
    and casts its shadow on it. Clusters toward the canopy's lower right take its shadow material
    (`mats`: light, middle, shadow, sheen; foliage()); a cluster in the light gets a paler patch toward
    its top left, as RD's do. `flat` squashes the clusters; `skip(x, y)` leaves a gap."""
    # On a jittered grid a cluster apart, so the crown is full and even, never lopsided; at most `count`,
    # the nearest the middle.
    r = rng(seed)
    step = size * 1.1
    spots = []
    for j, gy in enumerate(np.arange(cy - ry, cy + ry + 0.01, step * 0.8 * flat)):
        for gx in np.arange(cx - rx + (j % 2) * step / 2, cx + rx + 0.01, step):
            if ((gx - cx) / max(1, rx)) ** 2 + ((gy - cy) / max(1, ry)) ** 2 > 1.05:
                continue
            x, y = gx + r.uniform(-0.25, 0.25) * size, gy + r.uniform(-0.2, 0.2) * size
            if not (skip and skip(x, y)):
                spots.append((x, y))
    if not spots:
        spots = [(cx, cy)]
    spots = sorted(spots, key=lambda p: ((p[0] - cx) / max(1, rx)) ** 2 + ((p[1] - cy) / max(1, ry)) ** 2)[:count]
    for x, y in sorted(spots, key=lambda p: p[1]):
        k = r.uniform(0.8, 1.15)
        side = ((x - cx) / max(1, rx) + (y - cy) / max(1, ry)) / 2
        mat = mats[0] if side < -0.2 else mats[2] if side > 0.3 else mats[1]
        s.ellipse(x, y, size * k, size * k * 0.82 * flat, mat, bulge=bulge)
        if side < 0.3 and len(mats) > 3:
            rr = size * k * 0.42
            s.ellipse(x - rr * 0.7, y - rr * 0.7 * flat, rr, rr * 0.8 * flat, mats[3], profile="flat")
    return s


def trunk(s, base_x, base_y, top_y, width, mat, lean=0.0, roots=2):
    """A trunk from the ground up, wider at its foot, with a few roots splayed along the ground."""
    s.stroke([(base_x, base_y), (base_x + lean * 0.5, (base_y + top_y) / 2), (base_x + lean, top_y)], width, mat)
    for k in range(roots):
        side = -1 if k % 2 == 0 else 1
        reach = 3 + k // 2 * 2
        s.stroke([(base_x, base_y - 2), (base_x + side * reach, base_y + 0.5)], width * 0.55, mat)
    return s


def branch(s, points, width, mat):
    s.stroke(points, width, mat)
    return s


# ------------------------------------------------------------------------------------------- trees

BARK = "#6b4a32"
SIDE_LIGHT = np.array([-0.45, -0.55, 0.7]) / np.linalg.norm([-0.45, -0.55, 0.7])


def scene(size=64):
    """A sprite lit as scenery is: from the top left, lower than the icons' light, so each cluster of
    leaves is a ball lit on one side; edges darken only where they turn from it."""
    s = Sprite(size)
    s.light, s.rim = SIDE_LIGHT, "lower"
    s.seams = False         # clusters part by their shadows, not by drawn lines (RD's have none)
    return s


def cherry():
    """blossom_tree: a cherry, wider than tall, its blossom in layered drifts on dark, forking limbs."""
    s = scene()
    bark, pink = Material("#6a4640", texture=0.07), foliage("#ec74ae")
    trunk(s, 32, 60, 40, 6, bark, lean=-1, roots=3)
    branch(s, [(31, 44), (23, 36), (12, 32)], 3.4, bark)
    branch(s, [(31, 44), (41, 35), (52, 31)], 3.4, bark)
    branch(s, [(31, 42), (33, 30)], 3, bark)
    # Drifts of blossom in tiers, the widest at the bottom, gaps between them showing the limbs.
    for (cx, cy, rx, ry, n, seed) in ((32, 15, 13, 4, 5, 1), (15, 29, 8, 3, 4, 2), (49, 28, 8, 3, 4, 3),
                                      (32, 26, 12, 3, 5, 4)):
        puffs(s, cx, cy, rx, ry, pink, n, 6.5, seed, flat=0.8)
    return s


def gnarled():
    """dark_tree: a dead-looking crooked tree, its trunk twisting and leaning, bare twigs clawing out of
    a few sparse clumps of dusky purple leaves."""
    s = scene()
    bark, leaves = Material("#4a3c4e", texture=0.08), foliage("#7a52b0")
    trunk(s, 30, 60, 46, 7, bark, lean=4, roots=4)
    branch(s, [(33, 47), (28, 38), (34, 30), (31, 20)], 5, bark)
    branch(s, [(32, 42), (20, 36), (14, 26), (8, 23)], 3, bark)
    branch(s, [(33, 38), (44, 33), (50, 24), (57, 21)], 3, bark)
    branch(s, [(14, 27), (17, 19)], 2, bark)
    branch(s, [(50, 25), (47, 16)], 2, bark)
    branch(s, [(31, 22), (25, 13)], 2, bark)
    for (cx, cy, rx, ry, n, seed) in ((31, 15, 8, 5, 6, 11), (11, 24, 6, 4, 4, 12), (52, 20, 6, 4, 4, 13)):
        puffs(s, cx, cy, rx, ry, leaves, n, 4.0, seed, flat=0.75)
    return s


def oak(colour, seed=21, ragged=False):
    """A broad oak: a short thick trunk and a wide crown in two rows of clusters; `ragged` leaves gaps
    in it, as an autumn tree has lost some of its leaves."""
    s = scene()
    bark, leaves = Material(BARK, texture=0.07), foliage(colour)
    trunk(s, 32, 60, 36, 8, bark, roots=4)
    branch(s, [(32, 42), (22, 32)], 3.5, bark)
    branch(s, [(32, 40), (43, 31)], 3.5, bark)
    gap = (lambda x, y: (x - 22) ** 2 + (y - 30) ** 2 < 20 or (x - 44) ** 2 + (y - 22) ** 2 < 16) if ragged else None
    puffs(s, 32, 16, 18, 7, leaves, 7, 7.0, seed, skip=gap)
    puffs(s, 32, 28, 20, 4, leaves, 6, 6.5, seed + 1, flat=0.85, skip=gap)
    return s


def maple():
    """red_maple: wider than tall, a crown of flat, overlapping tiers like the lobes of its leaves."""
    s = scene()
    bark, leaves = Material("#5e3e30", texture=0.07), foliage("#d0383c")
    trunk(s, 32, 60, 40, 6, bark, roots=3)
    branch(s, [(32, 44), (18, 36)], 3, bark)
    branch(s, [(32, 44), (46, 36)], 3, bark)
    for (cx, cy, rx, ry, n, seed, size) in ((32, 12, 8, 3, 3, 31, 6.0), (32, 22, 16, 3, 5, 32, 6.5),
                                            (32, 32, 24, 3, 7, 33, 6.0)):
        puffs(s, cx, cy, rx, ry, leaves, n, size, seed, flat=0.7)
    return s


def birch():
    """golden_tree: a tall, narrow aspen: a pale trunk marked with dark bands, golden leaves in a high
    oval crown."""
    s = scene()
    bark, marks, leaves = Material("#e6e0d0", texture=0.04), Material("#3a3436", texture=0.0), foliage("#f2b822")
    trunk(s, 32, 60, 30, 5, bark, roots=2)
    for y in (54, 47, 41, 36):
        s.stroke([(30.2, y), (32.2, y + 0.6)], 1.2, marks, profile="flat")
    puffs(s, 32, 20, 9, 15, leaves, 9, 5.5, 41, flat=1.1)
    return s


def frosted():
    """frost_tree: a bare winter tree, every limb capped with snow, icicles hanging under the lowest."""
    s = scene()
    bark, snow, ice = Material("#5a5468", texture=0.06), Material("#eef6ff", texture=0.02), Material("#a8dcf4", texture=0.0, gloss=0.6)
    trunk(s, 32, 60, 40, 6, bark, roots=3)
    limbs = [[(32, 44), (20, 34), (10, 30)], [(32, 44), (44, 34), (55, 31)], [(32, 40), (30, 26), (24, 14)],
             [(31, 34), (38, 22), (42, 10)], [(21, 35), (17, 24)], [(44, 34), (49, 22)], [(30, 26), (36, 16)]]
    for limb in limbs:
        branch(s, limb, 2.6, bark)
    for limb in limbs:   # snow along the top of each limb
        for (x0, y0), (x1, y1) in zip(limb, limb[1:]):
            s.stroke([(x0, y0 - 1.3), (x1, y1 - 1.3)], 1.8, snow)
    for (x, y) in ((14, 33), (19, 35), (47, 35), (52, 33)):
        s.poly([(x - 0.9, y), (x + 0.9, y), (x, y + 4)], ice, profile="flat")
    s.ellipse(32, 60, 9, 2.2, snow, profile="flat")
    return s


def willow():
    """swamp_tree: a weeping willow: a dome of leaves with long strands hanging from it nearly to the
    ground, the trunk showing between them."""
    s = scene()
    bark, leaves = Material("#5a4a36", texture=0.07), foliage("#3e9a6a")
    trunk(s, 32, 60, 30, 6, bark, roots=4)
    puffs(s, 32, 18, 16, 6, leaves, 7, 6.5, 51, flat=0.8)
    r = rng(52)
    for x in np.linspace(12, 52, 11):
        if 27 < x < 37:
            continue
        top = 20 + abs(x - 32) * 0.15
        length = 26 + r.uniform(-4, 6) - abs(x - 32) * 0.3
        s.stroke([(x, top), (x + r.uniform(-1, 1), top + length / 2), (x + r.uniform(-1.5, 1.5), top + length)], 3.0,
                 leaves[1 if x < 32 else 2])
    return s


def jacaranda():
    """lilac_tree: a round lilac crown, panicles of blossom hanging from its rim like cones."""
    s = scene()
    bark, bloom = Material(BARK, texture=0.07), foliage("#a678e0")
    trunk(s, 32, 60, 38, 6, bark, roots=3)
    branch(s, [(32, 44), (22, 36)], 3, bark)
    branch(s, [(32, 42), (42, 35)], 3, bark)
    for x in (14, 21, 28, 36, 43, 50):
        y = 30 - abs(x - 32) * 0.25
        s.poly([(x - 2.6, y - 3), (x + 2.6, y - 3), (x + 0.4, y + 6)], bloom[1 if x < 40 else 2])
    puffs(s, 32, 19, 17, 10, bloom, 12, 6.0, 61)
    return s


def candy(colour, stripe):
    """A candy tree: a cotton-candy crown of round puffs on a striped candy stick."""
    s = scene()
    stick, band, fluff = Material("#fff4ec", texture=0.02), Material(stripe, texture=0.02), foliage(colour, 0.02)
    s.stroke([(32, 60), (32, 38)], 5, stick)
    for y in np.arange(58, 38, -4.5):
        s.stroke([(29.6, y), (34.4, y - 2.2)], 1.8, band)
    puffs(s, 32, 24, 14, 11, fluff, 10, 7.0, 71, bulge=4.0)
    return s


# ------------------------------------------------------------------------------------------- bushes
# 32 pixels, like RD's `berry_bush`, standing on the bottom row.

def mound(colour, seed, flowers=None, bloom_count=6):
    """A low leafy bush, wider than tall; `flowers` (a colour) dots blossoms over its lit side."""
    s = scene(32)
    leaves = foliage(colour)
    puffs(s, 16, 17, 11, 8, leaves, 40, 3.4, seed, flat=0.9, bulge=2.0)
    if flowers:
        petal, eye = Material(flowers, texture=0.0), Material("#f8d84a", texture=0.0)
        r = rng(seed + 1)
        for _ in range(bloom_count):
            x, y = 16 + r.uniform(-10, 9), 17 + r.uniform(-8, 6)
            s.ellipse(x, y, 1.6, 1.4, petal, profile="flat")
            s.ellipse(x, y, 0.6, 0.6, eye, profile="flat")
    return s


def tumbleweed():
    """dry_bush: a dry tangle of twigs, a ball of them, bleached tan."""
    s = scene(32)
    twig = Material("#b89a62", texture=0.05)
    r = rng(81)
    for _ in range(16):
        a = r.uniform(0, 2 * math.pi)
        x0, y0 = 16 + math.cos(a) * 12, 16 + math.sin(a) * 10
        b = a + math.pi + r.uniform(-0.9, 0.9)
        x1, y1 = 16 + math.cos(b) * 12, 16 + math.sin(b) * 10
        s.stroke([(x0, y0), ((x0 + x1) / 2 + r.uniform(-2, 2), (y0 + y1) / 2 + r.uniform(-2, 2)), (x1, y1)], 1.3, twig)
    return s


def hummock():
    """moss_bush: a mossy hummock over a grey stone, the stone's face showing in front."""
    s = scene(32)
    stone, moss = Material("#8a8a86", texture=0.08), foliage("#6a8a2e")
    s.ellipse(17, 21, 13, 8, stone)
    puffs(s, 15, 14, 11, 5, moss, 30, 3.2, 91, flat=0.8, bulge=2.0)
    return s


def bramble():
    """dark_bush: a thorny bramble: a dusky violet clump with thorned canes arching out over it."""
    s = scene(32)
    stem, leaves, thorn = Material("#4a3058", texture=0.04), foliage("#5e3e80"), Material("#a88cc0", texture=0.0)
    puffs(s, 16, 19, 12, 7, leaves, 40, 3.2, 101, flat=0.9, bulge=2.0)
    for pts in ([(11, 17), (6, 9), (2, 13)], [(18, 15), (23, 6), (30, 10)]):
        s.stroke(pts, 1.6, stem)
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            t = 0.55
            s.ellipse(x0 + (x1 - x0) * t + 1.0, y0 + (y1 - y0) * t - 0.5, 0.6, 0.6, thorn, profile="flat")
    return s


def conifer():
    """pine_sapling: a young fir, three tiers of needles stacked on a short stem."""
    s = scene(32)
    stem, needles = Material(BARK, texture=0.05), foliage("#2e7a4e")
    s.stroke([(16, 31), (16, 25)], 2.6, stem)
    for (top, bottom, half, mat) in ((1, 12, 6, needles[0]), (6, 20, 9, needles[1]), (12, 28, 12.5, needles[2])):
        s.poly([(16, top), (16 + half, bottom), (16 + half * 0.4, bottom - 1.2), (16, bottom + 0.6),
                (16 - half * 0.4, bottom - 1.2), (16 - half, bottom)], mat)
    return s


def shrub(colour, seed):
    """golden_bush: a tall rounded shrub, taller than wide, in tufts."""
    s = scene(32)
    leaves = foliage(colour)
    puffs(s, 16, 16, 10, 10, leaves, 40, 3.4, seed, bulge=2.0)
    return s


def lilac():
    """lilac_bush: green leaves with lilac flower spikes standing up out of them."""
    s = scene(32)
    leaves, bloom = foliage("#4e8a3a"), foliage("#b08ae6")
    for (x, h) in ((7, 13), (13, 19), (19, 21), (25, 15)):
        s.poly([(x - 3, 20), (x + 3, 20), (x + 0.3, 20 - h)], bloom[0 if x < 16 else 1])
    puffs(s, 16, 22, 12, 5, leaves, 30, 3.2, 111, flat=0.85, bulge=2.0)
    return s


def sapling():
    """sapling: a young tree, a thin stem and a small round crown."""
    s = scene(32)
    stem, leaves = Material(BARK, texture=0.05), foliage("#58b03e")
    s.stroke([(16, 31), (16.5, 16)], 2.6, stem)
    s.stroke([(16.3, 21), (21, 16)], 1.4, stem)
    puffs(s, 16, 10, 9, 7, leaves, 30, 3.4, 121, bulge=2.0)
    return s


BUSHES = {
    "bush": lambda: mound("#4aa63a", 131),
    "flowering_bush": lambda: mound("#4e9e3e", 132, flowers="#fff4f8", bloom_count=7),
    "autumn_bush": lambda: mound("#d8641e", 133),
    "dry_bush": tumbleweed,
    "moss_bush": hummock,
    "dark_bush": bramble,
    "pine_sapling": conifer,
    "golden_bush": lambda: shrub("#eab42a", 134),
    "lilac_bush": lilac,
    "sapling": sapling,
}


TREES = {
    "blossom_tree": cherry,
    "dark_tree": gnarled,
    "autumn_tree": lambda: oak("#e4822a", 22, ragged=True),
    "red_maple": maple,
    "golden_tree": birch,
    "frost_tree": frosted,
    "swamp_tree": willow,
    "lilac_tree": jacaranda,
    "candy_tree_lemon": lambda: candy("#f6e070", "#e8b020"),
    "candy_tree_peach": lambda: candy("#f8b49a", "#e86a5a"),
    "candy_tree_sky": lambda: candy("#a6dcf6", "#5a9ae6"),
}



def grounded(img):
    """Moved up or down so its lowest pixel sits where RD's own tree and bush stand (rows 59 of 64 and
    28 of 32), so it sits on the map as they do."""
    a = np.asarray(img)[..., 3] > 0
    rows = np.nonzero(a.any(axis=1))[0]
    ground = 59 if img.height == 64 else 28
    shift = ground - rows.max()
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.paste(img, (0, int(shift)))
    return out


def main(argv):
    sheet = None
    if "--sheet" in argv:
        i = argv.index("--sheet")
        sheet = pathlib.Path(argv[i + 1])
        argv = argv[:i] + argv[i + 2:]
    drawings = {**TREES, **BUSHES}
    ids = argv or sorted(drawings)
    out = {}
    for item in ids:
        img = grounded(drawings[item]().render(outline="tinted"))
        img.save(SPRITES / f"{item}.png")
        out[item] = img
    print(f"wrote {len(out)} scenery sprites to art/sprites/")
    if sheet:
        refs = [Image.open(SPRITES / "tree.png").convert("RGBA"), Image.open(SPRITES / "berry_bush.png").convert("RGBA")]
        tiles = refs + list(out.values())
        c = 64 * 3
        board = Image.new("RGBA", (c * min(6, len(tiles)), c * math.ceil(len(tiles) / 6)), (106, 150, 86, 255))
        for n, img in enumerate(tiles):
            k = c // 64
            board.alpha_composite(img.resize((img.width * k, img.height * k), Image.NEAREST), ((n % 6) * c, (n // 6) * c))
        board.save(sheet)
        print(f"sheet in {sheet}")


if __name__ == "__main__":
    main(sys.argv[1:])
