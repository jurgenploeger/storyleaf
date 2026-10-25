#!/usr/bin/env python3
"""Talewild's logo (Logo.png): the one word in Lilita One, the store slides' face (tools/fonts/),
with a leaf for the dot of its i. "Tale" gold and "wild" leaf green, inside one dark outline with a
hard shadow under it; each part has a darker rim inside, and its face is shaded in hard bands, top
to bottom, like the game's sprites. The type's edges stay smooth: cut into pixels it read as ugly.
No emblem, tagline, gloss or rays (the brand in the Figma file, 02 Logo).

Drawn `SS` times as big, every layer measured from the shapes' true edges (a round outline), then
shrunk, so the edges are smooth and the bands stay hard.

    python3 tools/logo_art.py                    # writes Logo.png
    python3 tools/logo_art.py --preview out.png  # on the sky, on the forest, and small

Needs pillow, numpy and scipy.
"""

import argparse
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.ndimage import distance_transform_edt

ROOT = Path(__file__).resolve().parent.parent
LOGO = ROOT / "Storyleaf/Resources/Assets.xcassets/Logo.imageset/Logo.png"
FONT = ROOT / "tools/fonts/LilitaOne-Regular.ttf"

WORD, SPLIT = "Talewild", 4
# Sizes in Logo.png's pixels: the type, the space between letters, the outline round the word, how
# far the shadow drops, and the rim inside each part.
PX, TRACKING = 270, 5
OUTLINE, SHADOW, RIM = 15, 11, 5
SS = 4
# The leaf for the i's dot, as shares of the i's stem width: its length, width, the gap under it,
# and how far it leans (degrees up from the right).
LEAF_LENGTH, LEAF_WIDTH, LEAF_GAP, LEAF_TILT = 1.9, 1.0, 0.3, 52

INK = (34, 22, 14)
# Each part's face, top to bottom, where each band starts (a share of the letters' height), and its rim.
BANDS = [0.0, 0.22, 0.5, 0.78]
GOLD = [(255, 244, 184), (255, 213, 79), (240, 165, 48), (196, 110, 30)]
GOLD_RIM = (138, 74, 18)
GREEN = [(220, 250, 170), (150, 222, 100), (66, 176, 92), (32, 124, 76)]
GREEN_RIM = (22, 92, 56)

SKY = [(111, 192, 245), (169, 220, 250), (227, 245, 255)]
FOREST = [(29, 74, 55), (15, 42, 32)]


def leaf(size: tuple[int, int], base: tuple[float, float], stem: float) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """The leaf's shape, its upper half (lit) and its midrib, from its base, leaning up and to the right."""
    length, half = LEAF_LENGTH * stem, LEAF_WIDTH * stem / 2
    angle = math.radians(LEAF_TILT)
    along, across = (math.cos(angle), -math.sin(angle)), (math.sin(angle), math.cos(angle))

    def at(a: float, c: float) -> tuple[float, float]:
        return base[0] + a * along[0] + c * across[0], base[1] + a * along[1] + c * across[1]

    steps = [i / 48 for i in range(49)]
    # Fuller towards the base, coming to a point at the tip.
    lower = [at(u * length, half * math.sin(math.pi * u ** 0.8)) for u in steps]
    upper = [at(u * length, -half * math.sin(math.pi * u ** 0.8)) for u in steps]
    shape, lit = Image.new("L", size), Image.new("L", size)
    ImageDraw.Draw(shape).polygon(lower + upper[::-1], fill=255)
    ImageDraw.Draw(lit).polygon(upper, fill=255)
    rib = Image.new("L", size)
    ImageDraw.Draw(rib).line([at(0.08 * length, 0), at(0.72 * length, 0)], fill=255, width=max(1, round(0.12 * stem)))
    return np.asarray(shape) >= 128, np.asarray(lit) >= 128, np.asarray(rib) >= 128


def logo() -> Image.Image:
    font = ImageFont.truetype(str(FONT), PX * SS)
    size = (PX * SS * 5, PX * SS * 2)
    first, second = np.zeros(size[::-1], bool), np.zeros(size[::-1], bool)
    x, y = PX * SS / 2, PX * SS * 0.6
    stem = None
    for index, ch in enumerate(WORD):
        mask = Image.new("L", size)
        # The i without its dot: the leaf takes its place.
        ImageDraw.Draw(mask).text((x, y), "ı" if ch == "i" else ch, font=font, fill=255)
        if ch == "i":
            stem = mask.getbbox()
        (first if index < SPLIT else second)[np.asarray(mask) >= 128] = True
        x += font.getlength(ch) + TRACKING * SS
    letters = first | second
    rows = np.flatnonzero(letters.any(axis=1))
    top, height = rows[0], rows[-1] + 1 - rows[0]

    width = stem[2] - stem[0]
    base = ((stem[0] + stem[2]) / 2 - 0.2 * width, stem[1] - LEAF_GAP * width)
    leaf_shape, lit, rib = leaf(size, base, width)
    second |= leaf_shape
    word = first | second

    outline = distance_transform_edt(~word) <= OUTLINE * SS
    shadow = np.roll(outline, SHADOW * SS, axis=0)
    face = distance_transform_edt(word) > RIM * SS

    art = np.zeros(size[::-1] + (4,), np.uint8)
    art[outline | shadow] = INK + (255,)
    band = np.searchsorted([top + height * b for b in BANDS[1:]], np.arange(size[1]), side="right")
    for part, colours, rim in ((first, GOLD, GOLD_RIM), (second, GREEN, GREEN_RIM)):
        art[part] = rim + (255,)
        shades = np.array([c + (255,) for c in colours], np.uint8)[band]
        inside = part & face
        art[inside] = np.broadcast_to(shades[:, None, :], art.shape)[inside]
    # The leaf in two greens either side of its midrib, lit from above.
    art[leaf_shape & face] = GREEN[2] + (255,)
    art[lit & face] = GREEN[1] + (255,)
    art[rib & face] = GREEN_RIM + (255,)

    image = Image.fromarray(art, "RGBA")
    image = image.crop(image.getbbox())
    return image.resize((round(image.width / SS), round(image.height / SS)), Image.LANCZOS)


def gradient(size: tuple[int, int], stops: list) -> Image.Image:
    width, height = size
    t = np.linspace(0, 1, height) * (len(stops) - 1)
    low = np.minimum(t.astype(int), len(stops) - 2)
    frac = (t - low)[:, None]
    colours = np.array(stops, dtype=float)
    rows = colours[low] * (1 - frac) + colours[low + 1] * frac
    return Image.fromarray(np.repeat(rows[:, None, :], width, axis=1).round().astype(np.uint8), "RGB").convert("RGBA")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--preview", type=Path, help="write the logo on the sky, on the forest and small here")
    args = parser.parse_args()

    art = logo()
    art.save(LOGO, optimize=True)
    print(f"wrote {LOGO.relative_to(ROOT)}  {art.width}×{art.height}")

    if args.preview:
        tiles = []
        for stops in (SKY, FOREST):
            tile = gradient((art.width + 120, art.height + 120), stops)
            tile.alpha_composite(art, (60, 60))
            tiles.append(tile)
        tile = gradient((240, 120), SKY)
        thumb = art.resize((180, round(art.height * 180 / art.width)), Image.LANCZOS)
        tile.alpha_composite(thumb, (30, (120 - thumb.height) // 2))
        tiles.append(tile)
        sheet = Image.new("RGB", (max(t.width for t in tiles) + 20, sum(t.height + 10 for t in tiles) + 10), (242, 242, 247))
        y = 10
        for tile in tiles:
            sheet.paste(tile.convert("RGB"), (10, y))
            y += tile.height + 10
        sheet.save(args.preview)
        print(f"preview in {args.preview}")


if __name__ == "__main__":
    main()
