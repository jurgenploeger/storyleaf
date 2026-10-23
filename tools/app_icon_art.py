#!/usr/bin/env python3
"""The app icon's dark and tinted versions, made from the light one (AppIcon.png), so the icon on
the Home Screen follows the phone's look (iOS 18 and later; older ones show the light icon).

Dark: the leaf-book stays as it is and its sky turns to night: lavender, sky blue and mint
become deep indigo, navy and teal, the rays fainter, the clouds moonlit, and the white sparkles
stay bright as stars. Tinted: the dark icon in greys, which iOS colours with the tint chosen.

The leaf-book is everything inside its dark outline (the forest green round the leaf and the
book, the deep red round the ribbon): flood-filled from the corner, whatever the fill doesn't
reach is the book. Rerun after changing AppIcon.png; `--preview out.png` shows all three side
by side. Needs pillow + numpy.
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

# The night sky, top to bottom, where the day's lavender, sky blue and mint were.
NIGHT = [(0.17, 0.12, 0.38), (0.07, 0.13, 0.33), (0.04, 0.2, 0.25)]


def book_mask(rgb: np.ndarray) -> np.ndarray:
    """True on the leaf-book: what a flood fill from the corner over everything lighter than its
    outline doesn't reach."""
    luma = rgb @ np.array([0.299, 0.587, 0.114])
    # A copy: Pillow doesn't flood-fill an image still sharing numpy's memory.
    walls = Image.fromarray(np.where(luma < 0.36, 0, 255).astype(np.uint8)).copy()
    ImageDraw.floodfill(walls, (0, 0), 128)
    return np.asarray(walls) != 128


def cloud_mask(rgb: np.ndarray) -> np.ndarray:
    """True on the clouds: the near-white banks a flood fill reaches from the bottom edge."""
    near_white = Image.fromarray(np.where(rgb.min(axis=2) > 0.88, 255, 0).astype(np.uint8)).copy()
    height, width = near_white.height, near_white.width
    for x in range(width):
        if near_white.getpixel((x, height - 1)) == 255:
            ImageDraw.floodfill(near_white, (x, height - 1), 128)
    return np.asarray(near_white) == 128


def night_gradient(height: int) -> np.ndarray:
    """The night's colour on each row, top to bottom."""
    stops = np.array(NIGHT)
    t = np.linspace(0, 1, height) * (len(stops) - 1)
    low = np.minimum(t.astype(int), len(stops) - 2)
    frac = (t - low)[:, None]
    return stops[low] * (1 - frac) + stops[low + 1] * frac


def darken(rgb: np.ndarray) -> np.ndarray:
    height, width, _ = rgb.shape
    sky = night_gradient(height)[:, None, :].repeat(width, axis=1)
    # How far each pixel is from the day sky's pastel towards white: 0 on the plain sky, more on
    # a ray, near 1 on a cloud or a sparkle. The day sky's saturation is about a quarter.
    sat = rgb.max(axis=2) - rgb.min(axis=2)
    light = np.clip(1 - sat / 0.26, 0, 1)[..., None]
    # Rays and clouds: the night lit up a little, towards a cool moonlight.
    moon = np.array([0.55, 0.62, 0.8])
    out = sky + (moon - sky) * (light ** 2) * 0.5
    # The clouds, shaded by how bright they are (their saturation is mostly dither, which drew stripes).
    clouds = cloud_mask(rgb)
    luma = (rgb @ np.array([0.299, 0.587, 0.114]))[..., None]
    lit = sky + (moon - sky) * (0.38 + np.clip((luma - 0.9) / 0.1, 0, 1) * 0.14)
    out = np.where(clouds[..., None], lit, out)
    # Sparkles (pure white, their soft edges nearly) stay bright: stars. Not the clouds, as
    # white at their tops.
    star = np.clip((rgb.min(axis=2) - 0.955) / 0.045, 0, 1)
    star = np.where(clouds, 0, star)[..., None]
    return out + (1 - out) * star


def dark_icon(light: Image.Image) -> Image.Image:
    rgb = np.asarray(light.convert("RGB"), dtype=float) / 255
    book = book_mask(rgb)[..., None]
    out = np.where(book, rgb, darken(rgb))
    return Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB")


def tinted_icon(dark: Image.Image) -> Image.Image:
    """Greys for iOS to tint: the book bright, the night sky near black."""
    return dark.convert("L").convert("RGB")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--preview", type=Path, help="write the light, dark and tinted icons side by side here")
    args = parser.parse_args()

    light = Image.open(LIGHT)
    dark = dark_icon(light)
    tinted = tinted_icon(dark)
    dark.save(DARK, optimize=True)
    tinted.save(TINTED, optimize=True)
    print(f"wrote {DARK.relative_to(ROOT)} and {TINTED.relative_to(ROOT)}")

    if args.preview:
        side = 384
        sheet = Image.new("RGB", (side * 3 + 40, side + 20), (40, 40, 40))
        for index, image in enumerate([light.convert("RGB"), dark, tinted]):
            sheet.paste(image.resize((side, side), Image.LANCZOS), (10 + index * (side + 10), 10))
        sheet.save(args.preview)
        print(f"preview in {args.preview}")


if __name__ == "__main__":
    main()
