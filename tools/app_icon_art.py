#!/usr/bin/env python3
"""The app icon, light, dark and tinted (iOS 18 and later; older ones show the light icon), from
one picked Retro Diffusion drawing: the game's own hero (player_walk) with a golden sword before
the apple and blossom trees, built from the game's sprites and redrawn by RD
(art-variants/app_icon_sprite/, docs/sprite-acceptance.md → Retro Diffusion).

Light: the drawing cropped in close on the hero, hair to knees over a band of meadow (`CROP`), so he reads on a
small Home Screen icon, its flat sky graded from deep blue overhead to a pale haze (`day_sky`), scaled by a whole number (`SCALE`, nearest neighbour) and its edge pixels
repeated out to 1024. Dark: the same scene at dusk, its sky the night `StoryleafSky` draws in Dark
Mode, the rest darkened and cooled, moonlight on the hero's face keeping him brighter than the
trees, the gold still warm, and the evening's lights: fireflies, sparkles in the blossom, stars,
a glint on the sword (`light_up`). Tinted: greys iOS colours with the tint chosen (and its Clear look):
the hero bright, cut on his own outline (season_icon_art.hero_mask), on the dark icon's scene pushed dim (`tint`).
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
# The hero big, clipped by the edges (the tips of his hair and the sword at the top), down to his
# knees, so a band of meadow shows below him and less sky and tree above (the drawing is 192
# pixels; the hero spans x 62 to 156, y 50 to 182). 112 × 9 = 1008, the rest repeated edge.
CROP, SCALE = (52, 62, 164, 174), 9
# The crop before it, hair to hands, mostly sky and trees: shown in the preview only.
ALT_CROP, ALT_SCALE = (58, 50, 160, 152), 10
SIZE = 1024
# Where the moonlight falls, in the drawing's pixels: the hero's face.
FACE = (115, 103)

# Lights at dusk, in the drawing's pixels: fireflies in the dark branches and grass, sparkles
# in the blossom, stars in the gaps of night sky, and a glint on the sword's blade.
FIREFLIES = [(61, 101), (152, 124), (158, 141), (64, 141), (148, 98), (94, 84), (60, 163), (153, 168), (74, 171), (140, 158)]
PETALS = [(150, 62), (157, 79), (141, 88), (155, 55)]
STARS = [(54, 108), (57, 124), (161, 112), (158, 119)]
GLINT = (68, 71)
FIREFLY, FIREFLY_GLOW = (1.0, 0.97, 0.75), (0.88, 0.93, 0.5)
PETAL, STAR = (1.0, 0.86, 0.95), (0.95, 0.96, 1.0)

# The night sky, top to bottom, where the day's blue was.
NIGHT = [(0.17, 0.12, 0.38), (0.07, 0.13, 0.33), (0.04, 0.2, 0.25)]
# The day sky, top to bottom, in the drawing's pixels: RD painted it one flat blue, so it's graded from a
# deeper blue overhead to a pale haze at the horizon, the hue turning from a touch of violet to a touch of
# cyan as it pales (docs/pixel-style.md: hue-shifted ramps), in hard bands with a dithered seam (`day_sky`).
DAY = ["#4f98e4", "#68acec", "#82bff2", "#9ccff5", "#b6def8", "#cfeafb"]
SKY_ROWS = (62, 160)


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


def day_sky(rgb: np.ndarray, box: tuple[int, int, int, int]) -> np.ndarray:
    """The sky graded in `DAY`'s bands down `SKY_ROWS`, each seam dithered in a checkerboard two pixels
    deep, so it has depth; where RD's sky was its deeper blue, a band deeper still."""
    out = rgb.copy()
    sky = sky_mask(rgb)
    pale = rgb.sum(axis=2) >= rgb[sky].sum(axis=1).max() - 0.02 if sky.any() else sky
    bands = np.array([[int(c[i:i + 2], 16) / 255 for i in (1, 3, 5)] for c in DAY])
    top, bottom = SKY_ROWS
    for y, x in np.argwhere(sky):
        t = np.clip((y + box[1] - top) / (bottom - top), 0, 0.999) * len(DAY)
        band = int(t)
        # The seam: the last two rows of a band checker into the next.
        if t - band > 1 - 2 * len(DAY) / (bottom - top) and (x + y) % 2 and band < len(DAY) - 1:
            band += 1
        if not pale[y, x]:
            band = max(0, band - 1)
        out[y, x] = bands[band]
    return out


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


def tint(rgb: np.ndarray, hero: np.ndarray = None, day: np.ndarray = None, lights: np.ndarray = None) -> np.ndarray:
    """Greys for iOS to tint (its Tinted and Clear Home Screens): a light figure on a dark field, as the
    system's own icons are. The hero (`hero`, and what he wears) in his daylight greys (`day`), stretched
    to the full range so his face and gold read; the scene behind him from the dark icon, pushed down to a
    dim backdrop, only its lights (fireflies, stars, sparkles, and `lights`: a season's moon and pumpkins)
    left bright. Stretched evenly instead, the
    whole picture sat in the middle greys and looked washed out beside the other icons."""
    weights = np.array([0.299, 0.587, 0.114])
    luma = rgb @ weights
    if hero is None:
        low, high = np.percentile(luma, [2, 98])
        grey = np.clip((luma - low) / max(high - low, 1e-6), 0, 1)
        return np.repeat(grey[..., None], 3, axis=2)
    face = (rgb if day is None else day) @ weights
    low, high = np.percentile(face[hero], [3, 99])
    figure = np.clip((face - low) / max(high - low, 1e-6), 0, 1) ** 0.85
    low, high = np.percentile(luma[~hero], [2, 99.5])
    scene = np.clip((luma - low) / max(high - low, 1e-6), 0, 1)
    # Only the small lights stay bright; a pale patch of snow or blossom goes down with the rest.
    from scipy import ndimage
    bright = (scene > 0.8) & ~hero
    parts, count = ndimage.label(bright, np.ones((3, 3)))
    sizes = ndimage.sum(bright, parts, range(1, count + 1))
    sparks = np.isin(parts, 1 + np.flatnonzero(sizes <= 6))
    if lights is not None:
        sparks |= lights
    backdrop = np.where(sparks, scene, 0.34 * scene ** 1.4)
    grey = np.where(hero, figure, backdrop)
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
    import season_icon_art  # it imports this module, so only once both are loaded
    hero = season_icon_art.hero_mask(CROP)
    day = day_sky(rgb, CROP)
    light, dark, tinted = scaled(day, SCALE), scaled(night, SCALE), scaled(tint(night, hero, day), SCALE)
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
