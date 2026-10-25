#!/usr/bin/env python3
"""Talewild's logo (Logo.png): the one word in Lilita One, the store slides' face (tools/fonts/),
drawn as pixel art. "Tale" gold and "wild" leaf green, in one dark outline round the whole word with
a hard shadow under it, each part a darker rim inside and its face shaded in hard bands, top to
bottom. No emblem, tagline, gloss or rays (the brand in the Figma file, 02 Logo).

The word is set small (`PX`), each glyph's edge cut hard at half cover, so every layer is whole
pixels, then scaled up by a whole number (`SCALE`, nearest neighbour), as the game's sprites are.

    python3 tools/logo_art.py                    # writes Logo.png
    python3 tools/logo_art.py --preview out.png  # on the sky, on the forest, and small

Needs pillow + numpy.
"""

import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
LOGO = ROOT / "Storyleaf/Resources/Assets.xcassets/Logo.imageset/Logo.png"
FONT = ROOT / "tools/fonts/LilitaOne-Regular.ttf"

WORD, SPLIT = "Talewild", 4
PX, TRACKING, SCALE = 56, 1, 5
OUTLINE, SHADOW, RIM = 3, 2, 1
INK = (34, 22, 14)
# Each part's face, top to bottom, where each band starts (a share of the word's height), and its rim.
BANDS = [0.0, 0.22, 0.5, 0.78]
GOLD = [(255, 244, 184), (255, 213, 79), (240, 165, 48), (196, 110, 30)]
GOLD_RIM = (138, 74, 18)
GREEN = [(220, 250, 170), (150, 222, 100), (66, 176, 92), (32, 124, 76)]
GREEN_RIM = (22, 92, 56)

SKY = [(111, 192, 245), (169, 220, 250), (227, 245, 255)]
FOREST = [(29, 74, 55), (15, 42, 32)]


def glyph(ch: str, font: ImageFont.FreeTypeFont, at: tuple[float, float], size: tuple[int, int]) -> Image.Image:
    """One letter's shape, cut hard at half cover."""
    mask = Image.new("L", size)
    ImageDraw.Draw(mask).text(at, ch, font=font, fill=255)
    return mask.point(lambda v: 255 if v >= 128 else 0)


def bands(size: tuple[int, int], top: int, height: int, colours: list) -> Image.Image:
    image = Image.new("RGBA", size)
    draw = ImageDraw.Draw(image)
    for index, colour in enumerate(colours):
        y0 = 0 if index == 0 else top + round(height * BANDS[index])
        y1 = size[1] if index == len(colours) - 1 else top + round(height * BANDS[index + 1])
        draw.rectangle([0, y0, size[0], y1], fill=colour + (255,))
    return image


def logo() -> Image.Image:
    """The logo at one pixel per pixel."""
    font = ImageFont.truetype(str(FONT), PX)
    size = (PX * len(WORD), PX * 2)
    word, first = Image.new("L", size), Image.new("L", size)
    x = PX // 2
    for index, ch in enumerate(WORD):
        shape = glyph(ch, font, (x, PX // 2), size)
        word = ImageChops.lighter(word, shape)
        if index < SPLIT:
            first = ImageChops.lighter(first, shape)
        x += font.getlength(ch) + TRACKING
    second = ImageChops.subtract(word, first)
    box = word.getbbox()
    top, height = box[1], box[3] - box[1]

    canvas = Image.new("RGBA", size)
    outline = word.filter(ImageFilter.MaxFilter(2 * OUTLINE + 1))
    canvas.paste(Image.new("RGBA", size, INK + (255,)), (0, 0), ImageChops.lighter(outline, ImageChops.offset(outline, 0, SHADOW)))
    for part, colours, rim in ((first, GOLD, GOLD_RIM), (second, GREEN, GREEN_RIM)):
        canvas.paste(Image.new("RGBA", size, rim + (255,)), (0, 0), part)
        canvas.paste(bands(size, top, height, colours), (0, 0), part.filter(ImageFilter.MinFilter(2 * RIM + 1)))
    return canvas.crop(canvas.getbbox())


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

    small = logo()
    big = small.resize((small.width * SCALE, small.height * SCALE), Image.NEAREST)
    big.save(LOGO, optimize=True)
    print(f"wrote {LOGO.relative_to(ROOT)}  {big.width}×{big.height}, {len(small.getcolors())} colours")

    if args.preview:
        tiles = []
        for stops in (SKY, FOREST):
            tile = gradient((big.width + 120, big.height + 120), stops)
            tile.alpha_composite(big, (60, 60))
            tiles.append(tile)
        tile = gradient((240, 120), SKY)
        thumb = big.resize((180, round(big.height * 180 / big.width)), Image.LANCZOS)
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
