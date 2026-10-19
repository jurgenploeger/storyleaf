#!/usr/bin/env python3
"""The Glimmerdeep's crystal scenery, made from the caves' own rock in code (free): writes
art/sprites/<id>.png for each drawing below.

The caves' rock and floor tiles are pure grey, so a palette swap (`derive` in art/assets.json, which
multiplies a colour that's there) can't tint them. Here each pixel's brightness is laid on a ramp of
crystal colours instead, darkest to brightest, the shading kept, with a few facets catching the light
(playtesting 2026-10-19: "The cave should have more crystal looking scenery"). Edit a ramp and rerun:

    pip install pillow numpy
    python3 tools/crystal_art.py                   # all of them
    python3 tools/crystal_art.py --sheet out.png   # also a 6× contact sheet on the cave's dark
"""

import pathlib
import sys

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPRITES = ROOT / "art" / "sprites"


def hexes(*colors):
    return np.array([[int(c[i:i + 2], 16) / 255 for i in (0, 2, 4)] for c in colors])


# Darkest to brightest.
ICE = hexes("0b1440", "1d3f8a", "2f86c9", "6fd6f0", "e8fbff")
AMETHYST = hexes("140a33", "3a1d78", "6b3dbb", "b48cf0", "f4e9ff")
WALL = hexes("0a0a1e", "1b1840", "2c2a66", "4b4a9a", "8e8fd6")
FLOOR = hexes("0d0d22", "1d1f45", "2f3369", "4c5394", "8d97d4")
SPARKLE = np.array([0.85, 0.97, 1.0])


def on_ramp(level, ramp):
    """Colours for brightness levels 0…1, between the ramp's stops."""
    at = np.clip(level, 0, 1) * (len(ramp) - 1)
    low = np.floor(at).astype(int).clip(0, len(ramp) - 2)
    t = (at - low)[..., None]
    return ramp[low] * (1 - t) + ramp[low + 1] * t


def crystallize(source, ramp, sparkles=0.0, lift=0.0):
    """`source`'s pixels on `ramp` by brightness (stretched to fill it, `lift` brighter), and a few
    of its brightest (`sparkles` of them, chosen by place so a rerun draws the same) set glinting."""
    image = np.asarray(Image.open(SPRITES / f"{source}.png").convert("RGBA")).astype(float) / 255
    rgb, alpha = image[..., :3], image[..., 3]
    level = rgb @ np.array([0.299, 0.587, 0.114])
    seen = alpha > 0.5
    low, high = np.percentile(level[seen], 3), np.percentile(level[seen], 97)
    level = (level - low) / max(1e-6, high - low) + lift
    out = on_ramp(level, ramp)
    if sparkles > 0:
        h, w = level.shape
        ys, xs = np.mgrid[0:h, 0:w]
        # A fixed scatter (a hash of the place), only on the brighter half.
        hashed = ((xs * 73856093) ^ (ys * 19349663)) % 1000 / 1000
        glint = seen & (level > 0.55) & (hashed < sparkles)
        out[glint] = SPARKLE
    return Image.fromarray((np.dstack([out.clip(0, 1), alpha]) * 255).round().astype(np.uint8), "RGBA")


DRAWINGS = {
    # The walls and the patches of crystal floor between the galleries' cobbles.
    "tile_crystal_rock": lambda: crystallize("tile_cave_rock", WALL, sparkles=0.035),
    "tile_crystal_floor": lambda: crystallize("tile_cave_floor", FLOOR, sparkles=0.02, lift=0.05),
    # Stalagmites grown into crystal spires, and boulders into geodes.
    "crystal_spire": lambda: crystallize("stalagmite", ICE, sparkles=0.04, lift=0.08),
    "amethyst_spire": lambda: crystallize("stalagmite", AMETHYST, sparkles=0.04, lift=0.08),
    "crystal_geode": lambda: crystallize("boulder", AMETHYST, sparkles=0.03),
}


def main(argv):
    sheet_path = None
    if "--sheet" in argv:
        index = argv.index("--sheet")
        sheet_path = argv[index + 1]
        argv = argv[:index] + argv[index + 2:]
    ids = argv or list(DRAWINGS)
    drawn = {art: DRAWINGS[art]() for art in ids}
    for art, image in drawn.items():
        image.save(SPRITES / f"{art}.png", optimize=True)
    print(f"wrote {len(drawn)} crystal sprites to art/sprites/")
    if sheet_path:
        scale, pad = 6, 6
        width = sum(image.width * scale + pad for image in drawn.values()) + pad
        height = max(image.height for image in drawn.values()) * scale + 2 * pad
        sheet = Image.new("RGBA", (width, height), (18, 16, 34, 255))
        x = pad
        for image in drawn.values():
            big = image.resize((image.width * scale, image.height * scale), Image.NEAREST)
            sheet.paste(big, (x, pad), big)
            x += big.width + pad
        sheet.save(sheet_path)
        print(f"contact sheet: {sheet_path}")


if __name__ == "__main__":
    main(sys.argv[1:])
