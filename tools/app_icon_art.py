#!/usr/bin/env python3
"""The app icon, light, dark and tinted (iOS 18 and later; older ones show the light icon), from
one picked Retro Diffusion drawing: the game's own hero (player_walk) with a golden sword before
the apple and blossom trees, built from the game's sprites and redrawn by RD
(art-variants/app_icon_sprite/, docs/sprite-acceptance.md → Retro Diffusion).

Light: the drawing cropped in close on the hero, clipped by the edges (`CROP`), so he reads on a
small Home Screen icon, scaled by a whole number (`SCALE`, nearest neighbour) and its edge pixels
repeated out to 1024. Dark: the same scene at dusk, its sky the night `StoryleafSky` draws in Dark
Mode, the rest darkened and cooled, moonlight on the hero's face keeping him brighter than the
trees, the gold still warm, and the evening's lights: fireflies, sparkles in the blossom, stars,
a glint on the sword (`light_up`). Tinted: the dark icon in greys, its contrast stretched, which iOS colours with the tint chosen.
Every grade is worked out on the drawing's own pixels before scaling, so the pixels stay crisp.

Rerun after changing the source or the crop; `--preview out.png` shows all three at Home Screen
sizes, beside the looser crop (`ALT_CROP`). Needs pillow + numpy.
"""

import argparse
import colorsys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
ICONSET = ROOT / "Storyleaf/Resources/Assets.xcassets/AppIcon.appiconset"
LIGHT = ICONSET / "AppIcon.png"
DARK = ICONSET / "AppIcon-Dark.png"
TINTED = ICONSET / "AppIcon-Tinted.png"

SOURCE = ROOT / "art-variants/app_icon_sprite/20261025-103956_rd_pro_2.png"
# The hero big, clipped by the edges: his hair and the sword's tip at the top, his hands at the
# bottom (the drawing is 192 pixels; the hero spans x 62 to 156, y 50 to 182). 102 × 10 = 1020,
# the rest repeated edge.
CROP, SCALE = (58, 50, 160, 152), 10
# The looser crop before it, hair to hips: shown in the preview only.
ALT_CROP, ALT_SCALE = (56, 44, 168, 156), 9
SIZE = 1024
# Where the moonlight falls, in the drawing's pixels: the hero's face.
FACE = (115, 103)

# Lights at dusk, in the drawing's pixels: fireflies in the dark branches and grass, sparkles
# in the blossom, stars in the gaps of night sky, and a glint on the sword's blade.
FIREFLIES = [(61, 101), (152, 124), (158, 141), (64, 141), (99, 149), (148, 98), (94, 84), (156, 108)]
PETALS = [(150, 62), (157, 79), (141, 88), (155, 55)]
STARS = [(98, 51), (107, 56), (124, 52)]
GLINT = (67, 60)
FIREFLY, FIREFLY_GLOW = (1.0, 0.97, 0.75), (0.88, 0.93, 0.5)
PETAL, STAR = (1.0, 0.86, 0.95), (0.95, 0.96, 1.0)

# The night sky, top to bottom, where the day's blue was.
NIGHT = [(0.17, 0.12, 0.38), (0.07, 0.13, 0.33), (0.04, 0.2, 0.25)]


def crop(box: tuple[int, int, int, int]) -> np.ndarray:
    """The source cut to `box`, as floats 0 to 1."""
    return np.asarray(Image.open(SOURCE).convert("RGB").crop(box), dtype=float) / 255


def scaled(rgb: np.ndarray, scale: int) -> Image.Image:
    """Each pixel `scale` times as big, the edge pixels repeated out to SIZE."""
    big = np.repeat(np.repeat(rgb, scale, axis=0), scale, axis=1)
    pad = SIZE - big.shape[0]
    big = np.pad(big, ((pad // 2, pad - pad // 2), (pad // 2, pad - pad // 2), (0, 0)), mode="edge")
    return Image.fromarray((np.clip(big, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB")


def sky_mask(rgb: np.ndarray) -> np.ndarray:
    """True on the day sky between the leaves: pale, light blue."""
    hsv = np.array([[colorsys.rgb_to_hsv(*p) for p in row] for row in rgb])
    hue, sat, val = hsv[..., 0] * 360, hsv[..., 1], hsv[..., 2]
    return (hue > 180) & (hue < 220) & (sat > 0.12) & (sat < 0.6) & (val > 0.75)


def is_gold(rgb: np.ndarray) -> np.ndarray:
    """True on the gold: the sword, the pauldron, the buckle (warm, saturated, bright), and the
    pale warm shine along the blade, which went grey graded with the rest."""
    hsv = np.array([[colorsys.rgb_to_hsv(*p) for p in row] for row in rgb])
    hue, sat, val = hsv[..., 0] * 360, hsv[..., 1], hsv[..., 2]
    gold = (hue > 33) & (hue < 58) & (sat > 0.45) & (val > 0.7)
    shine = (hue > 30) & (hue < 65) & (sat > 0.12) & (val > 0.9)
    return gold | shine


def light_up(out: np.ndarray, box: tuple[int, int, int, int]) -> np.ndarray:
    """The evening's lights, each a bright pixel and a step of glow round it, in hard steps."""
    out = out.copy()
    height, width, _ = out.shape

    def put(x: int, y: int, colour, mix: float = 1.0) -> None:
        x, y = x - box[0], y - box[1]
        if 0 <= x < width and 0 <= y < height:
            out[y, x] = out[y, x] * (1 - mix) + np.array(colour) * mix

    # A firefly: a bright pixel, a step of glow on each side and a fainter one on the diagonals,
    # so it still shows as a spark of light on a 60-point icon.
    for x, y in FIREFLIES:
        for dx, dy in ((1, 1), (1, -1), (-1, 1), (-1, -1)):
            put(x + dx, y + dy, FIREFLY_GLOW, 0.3)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            put(x + dx, y + dy, FIREFLY_GLOW, 0.65)
        put(x, y, FIREFLY)
    for x, y in PETALS:
        put(x, y, PETAL)
        put(x + 1, y, PETAL, 0.4)
    for x, y in STARS:
        put(x, y, STAR)
    gx, gy = GLINT
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (2, 0), (-2, 0), (0, 2), (0, -2)):
        put(gx + dx, gy + dy, STAR, 0.7 if abs(dx) + abs(dy) == 1 else 0.35)
    put(gx, gy, (1.0, 1.0, 1.0))
    return out


def dusk(rgb: np.ndarray, box: tuple[int, int, int, int]) -> np.ndarray:
    """The scene at dusk: the sky turned to night, the rest darker and cooler, moonlight on the hero,
    the gold still catching the light, and the evening's lights: fireflies, sparkles, stars."""
    height, width, _ = rgb.shape
    luma = rgb @ np.array([0.299, 0.587, 0.114])
    # In hard steps, as pixel art shades: a smooth grade gave every pixel a colour of its own
    # (1,272 where the light icon has 26). The sky: the night's three colours in three bands
    # down the icon, each pixel a step lighter or darker as its day shade was.
    band = np.minimum((np.arange(height) * 3) // height, 2)
    night = np.array(NIGHT)[band][:, None, :].repeat(width, axis=1)
    sky = night * (1 + 0.2 * np.round(np.clip((luma[..., None] - 0.85) / 0.1, -1, 1)))
    # Moonlight: brightest on the face, falling off to the trees at the edges, in three steps.
    ys, xs = np.mgrid[0:height, 0:width]
    fx, fy = FACE[0] - box[0], FACE[1] - box[1]
    near = np.exp(-(((xs - fx) ** 2 + (ys - fy) ** 2) / (2 * (width * 0.32) ** 2)))[..., None]
    near = np.round(near * 2) / 2
    # Cool at the edges, warmer where the light falls on the hero: cool moonlight on his face
    # turned it grey.
    cool, warm = np.array([0.62, 0.68, 0.92]), np.array([0.95, 0.86, 0.78])
    tone = cool * (1 - 0.6 * near) + warm * (0.6 * near)
    rest = rgb * tone * (0.42 + 0.48 * near)
    # The gold glimmers: it keeps most of its warm light where the rest goes cool and dim.
    rest = np.where(is_gold(rgb)[..., None], rgb * np.array([0.92, 0.82, 0.62]), rest)
    return light_up(np.where(sky_mask(rgb)[..., None], sky, rest), box)


def tint(rgb: np.ndarray) -> np.ndarray:
    """Greys for iOS to tint: the dark icon's light, stretched to fill the range."""
    luma = rgb @ np.array([0.299, 0.587, 0.114])
    low, high = np.percentile(luma, [2, 98])
    grey = np.clip((luma - low) / max(high - low, 1e-6), 0, 1)
    return np.repeat(grey[..., None], 3, axis=2)


def rounded(image: Image.Image, side: int) -> Image.Image:
    """`image` at `side` pixels, its corners rounded as the Home Screen draws it."""
    small = image.resize((side, side), Image.LANCZOS)
    mask = Image.new("L", (side, side), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, side - 1, side - 1], radius=round(side * 0.225), fill=255)
    tile = Image.new("RGB", (side, side), (242, 242, 247))
    tile.paste(small, (0, 0), mask)
    return tile


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--preview", type=Path, help="write the icons at Home Screen sizes here")
    args = parser.parse_args()

    rgb = crop(CROP)
    night = dusk(rgb, CROP)
    light, dark, tinted = scaled(rgb, SCALE), scaled(night, SCALE), scaled(tint(night), SCALE)
    light.save(LIGHT, optimize=True)
    dark.save(DARK, optimize=True)
    tinted.save(TINTED, optimize=True)
    print(f"wrote {LIGHT.relative_to(ROOT)}, {DARK.relative_to(ROOT)} and {TINTED.relative_to(ROOT)}")

    if args.preview:
        alt = scaled(crop(ALT_CROP), ALT_SCALE)
        sizes = [300, 180, 120, 60]
        row = sum(sizes) + 10 * (len(sizes) + 1)
        sheet = Image.new("RGB", (row, 4 * 320), (242, 242, 247))
        for index, image in enumerate([light, dark, tinted, alt]):
            x = 10
            for side in sizes:
                sheet.paste(rounded(image, side), (x, 10 + index * 320))
                x += side + 10
        sheet.save(args.preview)
        print(f"preview in {args.preview}: light, dark, tinted, then the looser crop")


if __name__ == "__main__":
    main()
