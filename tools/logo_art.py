#!/usr/bin/env python3
"""The logo (Logo.png): TALES OF over AVALUNE, in capitals, in Open Sans ExtraBold at its semi-condensed
width (tools/fonts/), the face of the titles in the pixel RPGs the user pointed to ("FIGHT AGAINST BOSS").
The world's name big, TALES OF small and spaced out above its middle, the two lines' outlines run into
one. All gold, each line in one smooth gradient from pale gold at the top to deep amber at the foot,
inside a dark brown outline with a hard shadow under it. No second colour, no bands, no emblem, tagline
or rays (the brand in the Figma file, 02 Logo; the titles on the store slides use the same face and gold,
tools/store_slides.py).

Drawn `SS` times as big, the outline measured from the letters' true edges (round), then shrunk, so the
edges are smooth.

    python3 tools/logo_art.py                    # writes Logo.png
    python3 tools/logo_art.py --preview out.png  # on the sky, on the forest, and small

Needs pillow, numpy and scipy.
"""

import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.ndimage import distance_transform_edt

ROOT = Path(__file__).resolve().parent.parent
LOGO = ROOT / "Storyleaf/Resources/Assets.xcassets/Logo.imageset/Logo.png"
FONT = ROOT / "tools/fonts/OpenSans-SemiCondensedExtraBold.ttf"

# The lines, top to bottom: the words, their type size and the space between their letters, in Logo.png's
# pixels; then the gap between the lines' letters (the outlines meet across it), the outline round the
# letters and how far the hard shadow drops.
LINES = [("TALES OF", 104, 22), ("AVALUNE", 250, 9)]
GAP = 16
OUTLINE, SHADOW = 10, 8
SS = 4

INK = (34, 22, 14)
# The gold, top to bottom of the capitals: where each colour sits (a share of their height).
GOLD = [(0.0, (255, 243, 176)), (0.45, (255, 205, 74)), (1.0, (232, 134, 28))]

SKY = [(111, 192, 245), (169, 220, 250), (227, 245, 255)]
FOREST = [(29, 74, 55), (15, 42, 32)]


def gold(height: int, top: int, span: int) -> np.ndarray:
    """One colour per row: the gold's stops across the capitals' rows, flat above and below them."""
    t = np.clip((np.arange(height) - top) / max(1, span), 0, 1)
    stops = np.array([s for s, _ in GOLD])
    colours = np.array([c for _, c in GOLD], dtype=float)
    return np.stack([np.interp(t, stops, colours[:, k]) for k in range(3)], axis=1)


def line(word: str, px: int, tracking: int) -> np.ndarray:
    """One line's capitals, `SS` times as big, cut to them."""
    font = ImageFont.truetype(str(FONT), px * SS)
    mask = Image.new("L", (px * SS * (len(word) + 2), px * SS * 2))
    draw = ImageDraw.Draw(mask)
    x = px * SS / 2
    for ch in word:
        draw.text((x, px * SS * 0.4), ch, font=font, fill=255)
        x += font.getlength(ch) + tracking * SS
    letters = np.asarray(mask) >= 128
    rows, cols = np.flatnonzero(letters.any(axis=1)), np.flatnonzero(letters.any(axis=0))
    return letters[rows[0]:rows[-1] + 1, cols[0]:cols[-1] + 1]


def logo() -> Image.Image:
    lines = [line(*spec) for spec in LINES]
    pad = (OUTLINE + SHADOW + 4) * SS
    width = max(part.shape[1] for part in lines) + 2 * pad
    height = sum(part.shape[0] for part in lines) + GAP * SS * (len(lines) - 1) + 2 * pad
    letters = np.zeros((height, width), bool)
    face = np.zeros((height, width, 3))
    y = pad
    for part in lines:
        x = (width - part.shape[1]) // 2
        letters[y:y + part.shape[0], x:x + part.shape[1]] = part
        # Each line's own gradient, top to foot of its capitals.
        face[y:y + part.shape[0]] = gold(part.shape[0], 0, part.shape[0])[:, None, :]
        y += part.shape[0] + GAP * SS
    size = (width, height)

    outline = distance_transform_edt(~letters) <= OUTLINE * SS
    shadow = np.roll(outline, SHADOW * SS, axis=0)
    art = np.zeros(size[::-1] + (4,), np.uint8)
    art[outline | shadow] = INK + (255,)
    art[letters, :3] = face[letters].round().astype(np.uint8)

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
