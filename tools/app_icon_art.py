#!/usr/bin/env python3
"""The app icon, light, dark and tinted (iOS 18 and later; older ones show the light icon), from
one picked Retro Diffusion drawing: the game's own hero (player_walk) with a golden sword before
the apple and blossom trees, built from the game's sprites and redrawn by RD
(art-variants/app_icon_sprite/, docs/sprite-acceptance.md → Retro Diffusion).

Light: the drawing cropped in on the hero, head to hips (`CROP`), so he reads on a small Home
Screen icon, scaled by a whole number (`SCALE`, nearest neighbour) and its edge pixels repeated
out to 1024. Dark: the same scene at dusk, its sky the night `StoryleafSky` draws in Dark Mode,
the rest darkened and cooled, moonlight on the hero's face keeping him brighter than the trees.
Tinted: the dark icon in greys, its contrast stretched, which iOS colours with the tint chosen.
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
# The hero from his hair to his hips, the sword's tip just inside the top left (the drawing is
# 192 pixels; the hero spans x 62 to 156, y 50 to 182). 112 × 9 = 1008, the rest repeated edge.
CROP, SCALE = (56, 44, 168, 156), 9
# Head to knees, filling 1024 exactly: shown in the preview only.
ALT_CROP, ALT_SCALE = (48, 40, 176, 168), 8
SIZE = 1024
# Where the moonlight falls in the crop: the hero's face.
FACE = (59, 56)

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


def dusk(rgb: np.ndarray) -> np.ndarray:
    """The scene at dusk: the sky turned to night, the rest darker and cooler, moonlight on the hero."""
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
    near = np.exp(-(((xs - FACE[0]) ** 2 + (ys - FACE[1]) ** 2) / (2 * (width * 0.32) ** 2)))[..., None]
    near = np.round(near * 2) / 2
    cool = np.array([0.62, 0.68, 0.92])
    rest = rgb * cool * (0.42 + 0.48 * near)
    return np.where(sky_mask(rgb)[..., None], sky, rest)


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
    night = dusk(rgb)
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
