#!/usr/bin/env python3
"""Item icons in the clean look (docs/pixel-style.md, *Item icons*): drawn at 64 × 64 with tools/pixel_kit.py
the way RD drew the Potion, lit from the top left on smooth ramps, no grain or dither, a one-pixel outline
in a deep shade of each material, lines inside softer than it, and a streak or speck of shine.

Playtesting 2026-10-26: "A lot of item icons feel too clunky [...] Look at the potion items we created with
retro diffusion, those look nice. The borders shouldn't look so thick and dark either." The drawings here
replace tools/item_art.py's for these items (it skips them); the coins are tools/coin_art.py's.

    python3 tools/clean_icon_art.py                 # all → art/sprites/item_<id>.png
    python3 tools/clean_icon_art.py seal_stone      # just these
    python3 tools/clean_icon_art.py --sheet out.png # a contact sheet at 4×, the Potion first
"""

import math
import pathlib
import sys

from PIL import Image

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from pixel_kit import Material, Sprite  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPRITES = ROOT / "art" / "sprites"


def mat(base, shades=7, relief=1.0, gloss=0.0):
    """A material in the clean finish: no grain, one ramp."""
    return Material(base, shades=shades, texture=0, variety=0, relief=relief, gloss=gloss, wide=True)


# --- Seal Stones: a cut crystal with the white sealing spiral in its table -------------------------

SEAL = [(32, 5), (54, 20), (50, 50), (32, 60), (14, 50), (10, 20)]
SEAL_MIDDLE = (32, 31)
LIGHT_FROM = math.radians(225)          # the top left, in screen angles (y down)


def facet_tone(points):
    """How lit a crown facet is, 0 … 1: by how far its outward side faces the top left."""
    cx = sum(p[0] for p in points) / len(points) - SEAL_MIDDLE[0]
    cy = sum(p[1] for p in points) / len(points) - SEAL_MIDDLE[1]
    facing = math.cos(math.atan2(cy, cx) - LIGHT_FROM)
    return 0.5 + 0.46 * facing


def seal(colours, spiral="#f6fbff", glint="#ffffff"):
    """The crystal: six crown facets round a table, each its own plane lit by the way it faces (the
    lower right deep in shadow, the upper left bright), the spiral glowing in the table. `colours`: one
    base for the whole stone, or one per facet (the Wishing Seal's rainbow), then the table's."""
    s = Sprite.clean(64)
    table = [(SEAL_MIDDLE[0] + (x - SEAL_MIDDLE[0]) * 0.56, SEAL_MIDDLE[1] + (y - SEAL_MIDDLE[1]) * 0.56) for x, y in SEAL]
    bases = colours if isinstance(colours, list) else [colours] * 7
    for i in range(6):
        quad = [SEAL[i], SEAL[(i + 1) % 6], table[(i + 1) % 6], table[i]]
        s.poly(quad, mat(bases[i], shades=7), profile="flat", tone=facet_tone(quad))
    # The table: the flat top, lit a step over the crown round it, so the spiral sits on a face of its own.
    s.poly(table, mat(bases[6], shades=7), profile="flat", tone=0.72)
    # The sealing spiral, three turns out from the middle.
    pts = []
    for k in range(60):
        t = k / 60 * math.pi * 3.2
        r = 0.8 + k * 0.17
        pts.append((SEAL_MIDDLE[0] + 0.5 + r * math.cos(t), SEAL_MIDDLE[1] + 1 + r * math.sin(t) * 0.92))
    s.stroke(pts, 2.2, mat(spiral, shades=3, relief=0.0), profile="flat")
    # Shine along the upper-left edge of the table, where the light catches the cut, and a speck on the crown.
    shine = mat(glint, shades=3, relief=0.0)
    s.stroke([table[5], ((table[5][0] + table[0][0]) / 2, (table[5][1] + table[0][1]) / 2)], 1.8, shine, profile="flat")
    s.stroke([(18.5, 26), (18.5, 29)], 1.6, shine, profile="flat")
    return s


def draw_seal_stone():
    return seal("#2cbcb2")


def draw_moon_seal():
    """Pale moonlight blue."""
    return seal("#86aef0")


def draw_heart_seal():
    """Rose pink."""
    return seal("#ec4a8c")


def draw_star_seal():
    """Starlight gold."""
    return seal("#f0bc30")


def draw_wishing_seal():
    """The rainbow one: each facet a colour of the rainbow, the table pale, the spiral violet so it shows."""
    return seal(["#ff8a9c", "#ffbe78", "#f6e070", "#9ce690", "#8ccaff", "#b49cff", "#fbe8ff"], spiral="#7a52d0")


# --- Lucky clover ----------------------------------------------------------------------------------

def draw_lucky_clover():
    """Four heart-shaped leaves round a middle, each its own (a softer line where one lies on the next),
    a pale vein down each, a curling stem."""
    s = Sprite.clean(64)
    leaf, vein, stem = mat("#3fae46"), mat("#a6e58a", shades=3, relief=0.0), mat("#2e8a36", shades=6)
    s.stroke([(33, 33), (37, 44), (42, 52), (49, 58)], 3.2, stem)
    # Back leaves first, so the front ones lie over them.
    for angle in (-45, 45, 225, 135):
        s.part()
        a = math.radians(angle)
        ux, uy = math.cos(a), math.sin(a)            # out from the middle
        px, py = -uy, ux                             # across the leaf
        lobe = 7.4
        for side in (-1, 1):
            s.ellipse(32 + ux * 15.5 + px * side * 5.8, 31 + uy * 15.5 + py * side * 5.8, lobe, lobe, leaf)
        s.poly([(32 - ux * 1.5, 31 - uy * 1.5), (32 + ux * 16 + px * 12, 31 + uy * 16 + py * 12),
                (32 + ux * 16 - px * 12, 31 + uy * 16 - py * 12)], leaf)
        s.stroke([(32 + ux * 3, 31 + uy * 3), (32 + ux * 18, 31 + uy * 18)], 1.4, vein, profile="flat")
    return s


DRAWINGS = {
    "seal_stone": draw_seal_stone, "moon_seal": draw_moon_seal, "heart_seal": draw_heart_seal,
    "star_seal": draw_star_seal, "wishing_seal": draw_wishing_seal, "lucky_clover": draw_lucky_clover,
}


def main(argv):
    sheet = None
    if "--sheet" in argv:
        i = argv.index("--sheet")
        sheet = argv[i + 1]
        argv = argv[:i] + argv[i + 2:]
    ids = argv or list(DRAWINGS)
    for item_id in ids:
        DRAWINGS[item_id]().render(outline="deep").save(SPRITES / f"item_{item_id}.png")
    print(f"wrote {len(ids)} item icons to art/sprites/")
    if sheet:
        k, names = 4, ["item_potion"] + [f"item_{i}" for i in ids]
        board = Image.new("RGBA", (len(names) * 66 * k, 66 * k), (214, 160, 150, 255))
        for n, name in enumerate(names):
            img = Image.open(SPRITES / f"{name}.png").convert("RGBA")
            board.alpha_composite(img.resize((64 * k, 64 * k), Image.NEAREST), (n * 66 * k + k, k))
        board.save(sheet)
        print(f"sheet in {sheet}")


if __name__ == "__main__":
    main(sys.argv[1:])
