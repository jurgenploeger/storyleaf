#!/usr/bin/env python3
"""Talewild's social media assets, made from the game's own art: the app icon's drawing for the
profile pictures, the logo (Logo.png) for the logo files, and the HUD-free landscape screenshot
scenes (`store_land_*` in tools/screenshots.txt, from CI's `screenshots` branch) behind the logo on
every cover and banner.

    python3 tools/social_art.py --shots DIR      # DIR holds store_land_*.png; writes marketing/social/
    python3 tools/social_art.py --shots DIR --preview out.png

Fetch the shots from the newest CI run first, e.g.
    git fetch origin screenshots && git show origin/screenshots:claude/<branch>/store_land_town.png > DIR/...

Covers keep the logo inside each platform's safe area (`SPECS`): clear of the round profile picture
that X and Bluesky lay over a header's bottom left, and inside YouTube's 1546 × 423 middle, the part
every device shows. Profile pictures centre the hero's face so a round crop never cuts it. No
taglines, rays or sparkles: the logo, the art and a soft vignette. Needs pillow + numpy.
"""

import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

import app_icon_art
import store_slides

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "marketing" / "social"
LOGO = ROOT / "Storyleaf" / "Resources" / "Assets.xcassets" / "Logo.imageset" / "Logo.png"

# The profile picture: the icon's drawing around the hero's face (115, 103), 96 pixels across.
PROFILE_CROP = (67, 52, 163, 148)

# Covers: name, size, scene, the logo's height as a share of the cover's, where its middle goes
# (shares of width and height), and where the hero lands across the cover (share of its width):
# the game's camera keeps him in the middle of every shot, so the crop moves him out from under
# the logo. Where the shot is narrower than the cover (X, Bluesky, Facebook) it can't move him, so
# the logo sits to the right of the middle instead; on the tall ones, above it.
SPECS = [
    ("x_header", (1500, 500), "store_land_companion", 0.62, (0.78, 0.47), 0.3),
    ("bluesky_banner", (3000, 1000), "store_land_companion", 0.62, (0.78, 0.47), 0.3),
    ("facebook_cover", (1640, 624), "store_land_explore", 0.56, (0.76, 0.5), 0.26),
    ("youtube_banner", (2560, 1440), "store_land_anywhere", 0.26, (0.56, 0.5), 0.36),
    ("discord_banner", (960, 540), "store_land_anywhere", 0.5, (0.64, 0.5), 0.26),
    ("link_preview", (1200, 630), "store_land_explore", 0.5, (0.64, 0.5), 0.26),
    ("instagram_post", (1080, 1350), "store_land_companion", 0.24, (0.5, 0.17), 0.5),
    ("instagram_story", (1080, 1920), "store_land_anywhere", 0.17, (0.5, 0.21), 0.5),
]

SKY = [(111, 192, 245), (169, 220, 250), (227, 245, 255)]
FOREST = [(29, 74, 55), (15, 42, 32)]


def gradient(size: tuple[int, int], stops: list[tuple[int, int, int]]) -> Image.Image:
    """A smooth top-to-bottom gradient through `stops`."""
    width, height = size
    t = np.linspace(0, 1, height) * (len(stops) - 1)
    low = np.minimum(t.astype(int), len(stops) - 2)
    frac = (t - low)[:, None]
    colours = np.array(stops, dtype=float)
    rows = colours[low] * (1 - frac) + colours[low + 1] * frac
    return Image.fromarray(np.repeat(rows[:, None, :], width, axis=1).round().astype(np.uint8), "RGB").convert("RGBA")


def fill(shot: Image.Image, size: tuple[int, int], hero_x: float) -> Image.Image:
    """The shot, clear of the Dynamic Island, scaled to cover `size`, cropped so its middle (where
    the camera keeps the hero) lands at `hero_x` across it, as near as the shot's width allows."""
    shot = store_slides.trim_island(shot).convert("RGBA")
    scale = max(size[0] / shot.width, size[1] / shot.height)
    big = shot.resize((round(shot.width * scale), round(shot.height * scale)), Image.LANCZOS)
    x = min(max(round(big.width / 2 - size[0] * hero_x), 0), big.width - size[0])
    y = (big.height - size[1]) // 2
    return big.crop((x, y, x + size[0], y + size[1]))


def vignette(canvas: Image.Image, strength: float = 0.28) -> None:
    """Darkens the corners a little, so the eye goes to the middle."""
    width, height = canvas.size
    ys, xs = np.mgrid[0:height, 0:width]
    d = np.sqrt(((xs - width / 2) / (width / 2)) ** 2 + ((ys - height / 2) / (height / 2)) ** 2) / np.sqrt(2)
    alpha = (np.clip((d - 0.45) / 0.55, 0, 1) ** 1.5 * strength * 255).astype(np.uint8)
    shade = Image.new("RGBA", canvas.size, (8, 22, 18, 0))
    shade.putalpha(Image.fromarray(alpha, "L"))
    canvas.alpha_composite(shade)


def place_logo(canvas: Image.Image, logo: Image.Image, height_share: float, middle: tuple[float, float]) -> None:
    height = round(canvas.height * height_share)
    width = round(logo.width * height / logo.height)
    width = min(width, round(canvas.width * 0.86))
    height = round(logo.height * width / logo.width)
    art = logo.resize((width, height), Image.LANCZOS)
    canvas.alpha_composite(art, (round(canvas.width * middle[0] - width / 2), round(canvas.height * middle[1] - height / 2)))


def profile(side: int) -> Image.Image:
    """The hero's face from the icon's drawing, scaled by whole pixels to fit `side`, its edges repeated out."""
    rgb = app_icon_art.crop(PROFILE_CROP)
    scale = side // rgb.shape[0]
    big = np.repeat(np.repeat(rgb, scale, axis=0), scale, axis=1)
    pad = side - big.shape[0]
    big = np.pad(big, ((pad // 2, pad - pad // 2), (pad // 2, pad - pad // 2), (0, 0)), mode="edge")
    return Image.fromarray((np.clip(big, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--shots", type=Path, required=True, help="a folder holding the store_land_*.png scenes")
    parser.add_argument("--preview", type=Path, help="write a contact sheet of every asset here")
    args = parser.parse_args()

    OUT.mkdir(parents=True, exist_ok=True)
    logo = Image.open(LOGO).convert("RGBA")
    made = {}

    made["profile_1080"] = profile(1080)
    made["discord_server_icon_512"] = profile(512)
    made["logo_transparent"] = logo
    for name, stops in [("logo_on_sky_1080", SKY), ("logo_on_forest_1080", FOREST)]:
        square = gradient((1080, 1080), stops)
        place_logo(square, logo, 0.58, (0.5, 0.5))
        made[name] = square

    for name, size, scene, share, middle, hero_x in SPECS:
        cover = fill(Image.open(args.shots / f"{scene}.png"), size, hero_x)
        vignette(cover)
        place_logo(cover, logo, share, middle)
        made[name] = cover

    for name, image in made.items():
        path = OUT / f"{name}.png"
        (image if name == "logo_transparent" else image.convert("RGB")).save(path, optimize=True)
        print(f"{path.relative_to(ROOT)}  {image.width}×{image.height}")

    if args.preview:
        tiles = [made[name] for name in made if name != "logo_transparent"]
        side = 360
        sheet = Image.new("RGB", (4 * (side + 10) + 10, ((len(tiles) + 3) // 4) * (side + 10) + 10), (242, 242, 247))
        for index, image in enumerate(tiles):
            tile = image.convert("RGB").copy()
            tile.thumbnail((side, side), Image.LANCZOS)
            x, y = 10 + (index % 4) * (side + 10), 10 + (index // 4) * (side + 10)
            sheet.paste(tile, (x + (side - tile.width) // 2, y + (side - tile.height) // 2))
        sheet.save(args.preview)
        print(f"preview in {args.preview}")


if __name__ == "__main__":
    main()
