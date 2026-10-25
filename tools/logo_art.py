#!/usr/bin/env python3
"""The logo (Logo.png): TALES OF over DORLUNE, in the style of the logo the user pointed to (Neopets' "Tales
of Dacardia"): chunky capitals in Luckiest Guy (tools/fonts/, Apache 2.0), set tight so their outlines run
into one, each letter tipped a few degrees one way or the other and lifted or dropped a little, so the word
bounces; TALES OF a little over half the world's name's size, a small gap above it. All gold, each line in
one smooth gradient from pale gold at the top to deep amber at the foot, a thin light rim along the letters'
top edges, inside one thick dark outline that drops into a deep block shadow underneath. No second colour,
no bands, no emblem, tagline or rays (the brand in the Figma file, 02 Logo; the titles on the store slides
use the same face and gold, tools/store_slides.py).

Drawn `SS` times as big, the outline measured from the letters' true edges (round), then shrunk, so the
edges are smooth. The tilts and lifts come from a fixed seed, so every run draws the same logo.

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
FONT = ROOT / "tools/fonts/LuckiestGuy-Regular.ttf"

# The lines, top to bottom: the words and their size as a share of the world's name's (`PX`, in Logo.png's
# pixels). Then, as shares of `PX`: the space between letters (less than none: they touch), how far each
# letter tips (degrees) and lifts, the gap between TALES OF and the name, the outline round the letters, how
# deep the block shadow drops, and the light rim along their tops. Letters are drawn left to right, each in
# a thin outline of its own (`SEAM`), so ones that touch stay apart.
LINES = [("TALES OF", 0.6), ("DORLUNE", 1.0)]
PX = 230
TRACK, TIP, LIFT = -0.02, 3.0, 0.035
# A small gap, wider than the letters lift, so the two lines never touch; their outlines still join.
GAP = 0.08
OUTLINE, DEPTH, RIM = 0.075, 0.07, 0.03
# The thin outline each letter keeps of its own where it overlaps the one before it.
SEAM = 0.022
SEED = 2
# Round capitals, drawn a little taller than the flat ones so they look the same size.
ROUND, OVERSHOOT = "OCGQS", 1.03
SS = 3

INK = (34, 22, 14)
# The gold, top to bottom of each line's capitals: where each colour sits (a share of their height).
GOLD = [(0.0, (255, 246, 190)), (0.42, (255, 208, 74)), (1.0, (226, 124, 22))]

SKY = [(111, 192, 245), (169, 220, 250), (227, 245, 255)]
FOREST = [(29, 74, 55), (15, 42, 32)]


def gold(height: int) -> np.ndarray:
    """One colour per row: the gold's stops from the top of a line's capitals to their foot."""
    t = np.linspace(0, 1, height)
    stops = np.array([s for s, _ in GOLD])
    colours = np.array([c for _, c in GOLD], dtype=float)
    return np.stack([np.interp(t, stops, colours[:, k]) for k in range(3)], axis=1)


def glyph(font: ImageFont.FreeTypeFont, ch: str, angle: float) -> np.ndarray:
    """One capital, tipped `angle` degrees, cut to it."""
    left, top, right, bottom = font.getbbox(ch)
    pad = 20 * SS
    image = Image.new("L", (right - left + 2 * pad, bottom - top + 2 * pad))
    ImageDraw.Draw(image).text((pad - left, pad - top), ch, font=font, fill=255)
    letters = np.asarray(image.rotate(angle, resample=Image.BICUBIC, expand=True)) >= 128
    rows, cols = np.flatnonzero(letters.any(axis=1)), np.flatnonzero(letters.any(axis=0))
    return letters[rows[0]:rows[-1] + 1, cols[0]:cols[-1] + 1]


def line(word: str, px: int, rng: np.random.Generator) -> list:
    """One line's capitals, `SS` times as big: each tipped the other way from the last, give or take, and
    lifted or dropped a little, set `TRACK` apart. Each its own mask on the line's canvas, left to right."""
    font = ImageFont.truetype(str(FONT), px * SS)
    cap = font.getbbox("H")[3] - font.getbbox("H")[1]
    placed, x = [], 0.0
    for index, ch in enumerate(word):
        if ch == " ":
            x += px * SS * 0.28 + TRACK * px * SS
            continue
        angle = TIP * (1 if index % 2 else -1) + rng.uniform(-TIP / 2, TIP / 2)
        # Every capital as tall as the H, a round one a touch taller (it would look short otherwise):
        # Luckiest Guy draws its O and D small, and beside the R and N they read a size down.
        top, bottom = font.getbbox(ch)[1], font.getbbox(ch)[3]
        size = px * SS * cap / max(1, bottom - top) * (OVERSHOOT if ch in ROUND else 1.0)
        shape = glyph(ImageFont.truetype(str(FONT), round(size)), ch, angle)
        placed.append((shape, x, rng.uniform(-LIFT, LIFT) * px * SS))
        x += shape.shape[1] + TRACK * px * SS
    tall = max(shape.shape[0] for shape, _, _ in placed)
    wide = max(int(left) + shape.shape[1] for shape, left, _ in placed)
    middle = int(tall * 0.6)
    masks = []
    for shape, left, lift in placed:
        canvas = np.zeros((int(tall * 1.2) + 4, wide + 4), bool)
        # Each letter centred on the line (then lifted or dropped): a tipped letter's corner hangs below
        # its foot, and lining up the corners left the tipped ones riding high and looking small.
        y = int(middle - shape.shape[0] / 2 + lift)
        canvas[y:y + shape.shape[0], int(left):int(left) + shape.shape[1]] = shape
        masks.append(canvas)
    union = np.any(masks, axis=0)
    rows, cols = np.flatnonzero(union.any(axis=1)), np.flatnonzero(union.any(axis=0))
    return [mask[rows[0]:rows[-1] + 1, cols[0]:cols[-1] + 1] for mask in masks]


def logo() -> Image.Image:
    rng = np.random.default_rng(SEED)
    lines = [line(word, round(PX * share), rng) for word, share in LINES]
    pad = int(PX * SS * 0.3)
    gap = int(PX * SS * GAP)
    width = max(part[0].shape[1] for part in lines) + 2 * pad
    height = sum(part[0].shape[0] for part in lines) + gap * (len(lines) - 1) + 2 * pad
    # Every letter on the logo's canvas, top line first, each with its line's gradient.
    placed = []
    y = pad
    for part in lines:
        h, w = part[0].shape
        x = (width - w) // 2
        colours = np.broadcast_to(gold(h)[:, None, :], (h, w, 3))
        for mask in part:
            letter = np.zeros((height, width), bool)
            letter[y:y + h, x:x + w] = mask
            face = np.zeros((height, width, 3))
            face[y:y + h, x:x + w][mask] = colours[mask]
            placed.append((letter, face))
        y += h + gap
    letters = np.any([letter for letter, _ in placed], axis=0)

    # The outline round them all, then the block shadow: the outline dragged straight down, row by row.
    outline = distance_transform_edt(~letters) <= OUTLINE * PX * SS
    shadow = outline.copy()
    for step in range(1, int(DEPTH * PX * SS) + 1):
        shadow[step:] |= outline[:-step]
    art = np.zeros((height, width, 4), np.uint8)
    art[shadow] = INK + (255,)
    # Then each letter in turn, in a thin outline of its own over the ones before, so letters that touch
    # stay apart; and the light rim along its top edge.
    seam = SEAM * PX * SS
    reach = max(1, int(RIM * PX * SS))
    for letter, face in placed:
        art[(distance_transform_edt(~letter) <= seam) & ~letter] = INK + (255,)
        art[letter, :3] = face[letter].round().astype(np.uint8)
        rim = letter & ~np.roll(letter, reach, axis=0) & (distance_transform_edt(letter) <= reach)
        art[rim, :3] = (face[rim] * 0.35 + 255 * 0.65).round().astype(np.uint8)

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
        tile = gradient((240, 140), SKY)
        thumb = art.resize((180, round(art.height * 180 / art.width)), Image.LANCZOS)
        tile.alpha_composite(thumb, (30, (140 - thumb.height) // 2))
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
