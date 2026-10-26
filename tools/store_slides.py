#!/usr/bin/env python3
"""App Store slides from the landscape store scenes (`store_land_*` in tools/screenshots.txt).

Each slide is a screenshot with a caption in the logo's style (tools/logo_art.py): the title in capitals in
Luckiest Guy, its gold gradient on every line, in the logo's thick dark outline with a block shadow under it;
under it, a dark plate for the tag, in Open Sans ExtraBold, semi-condensed (easier to read small),
exported at both iPhone sizes App Store Connect takes, as PNG with
no alpha channel (it refuses screenshots that have one):
  2622×1206  iPhone with Dynamic Island (medium display), the required one
  2868×1320  iPhone with Dynamic Island (large display), so the 6.5" set isn't needed

Captions, their places and the order of the carousel are in tools/store_slides.json. The simulator draws the
Dynamic Island into its screenshots, so each shot is cropped clear of it first (a zoom of a few percent).

    python3 tools/store_slides.py <shots-dir> <out-dir> [--sheet contact-sheet.png]

Shots come from CI: `git fetch origin screenshots`, then the PNGs under <branch>/. Needs pillow.
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

TOOLS = Path(__file__).resolve().parent
ROOT = TOOLS.parent
FONT = TOOLS / "fonts" / "OpenSans-SemiCondensedExtraBold.ttf"
TITLE_FONT = TOOLS / "fonts" / "LuckiestGuy-Regular.ttf"
LOGO = ROOT / "TalesOfDorlune" / "Resources" / "Assets.xcassets" / "Logo.imageset" / "Logo.png"

# The base size the layout is measured in, and the sizes exported.
BASE = (2622, 1206)
SIZES = [(2622, 1206), (2868, 1320)]

# The logo's colours (tools/logo_art.py): its ink, for the outline and the hard shadow under it, and its
# gold for the titles; the tag's words are cream on a plate of the ink.
INK = (34, 22, 14)
GOLD = [(0.0, (255, 246, 190)), (0.42, (255, 208, 74)), (1.0, (226, 124, 22))]
CREAM = (255, 248, 222)
PLATE = (34, 22, 14)


def font(size, path=FONT):
    return ImageFont.truetype(str(path), max(8, round(size)))


def solid(size, color, mask, alpha=1.0):
    layer = Image.new("RGBA", size, color + (0,))
    layer.putalpha(mask.point(lambda v: round(v * alpha)))
    return layer


def golden(letters):
    """The title's face: the logo's gold, top to bottom of every line of `letters` (a mask)."""
    rows = [y for y in range(letters.height) if letters.crop((0, y, letters.width, y + 1)).getbbox()]
    runs, start = [], None
    for index, y in enumerate(rows):
        if start is None:
            start = y
        if index + 1 == len(rows) or rows[index + 1] != y + 1:
            runs.append((start, y + 1))
            start = None
    column = Image.new("RGBA", (1, letters.height), GOLD[0][1] + (255,))
    for y0, y1 in runs:
        for y in range(y0, y1):
            t = (y - y0) / max(1, y1 - y0 - 1)
            for (a, ca), (b, cb) in zip(GOLD, GOLD[1:]):
                if a <= t <= b:
                    f = (t - a) / (b - a)
                    column.putpixel((0, y), tuple(round(p + (q - p) * f) for p, q in zip(ca, cb)) + (255,))
                    break
    face = column.resize(letters.size)
    face.putalpha(letters)
    return face


def lettering(canvas, text, at, size, align):
    """The logo's lettering: a block shadow, the dark outline, then the letters in its gold, in capitals.
    `at` is the top-left (or top-centre/right, by `align`) of the text block."""
    text = text.upper()
    face = font(size, TITLE_FONT)
    stroke = max(2, round(size * 0.075))
    spacing = round(size * -0.08)
    probe = ImageDraw.Draw(Image.new("L", canvas.size))
    box = probe.multiline_textbbox((0, 0), text, font=face, spacing=spacing, align=align, stroke_width=stroke)
    width = box[2] - box[0]
    x = {"left": at[0], "center": at[0] - width / 2, "right": at[0] - width}[align] - box[0]
    origin = (x, at[1] - box[1])

    def mask(stroke_width, offset=(0, 0)):
        layer = Image.new("L", canvas.size, 0)
        ImageDraw.Draw(layer).multiline_text((origin[0] + offset[0], origin[1] + offset[1]), text, font=face, fill=255,
                                             spacing=spacing, align=align, stroke_width=stroke_width, stroke_fill=255)
        return layer

    for step in range(1, round(size * 0.07) + 1, max(1, round(size * 0.01))):
        canvas.alpha_composite(solid(canvas.size, INK, mask(stroke, (0, step))))
    canvas.alpha_composite(solid(canvas.size, INK, mask(stroke)))
    canvas.alpha_composite(golden(mask(0)))
    return (origin[0] + box[0], origin[1] + box[1], origin[0] + box[2], origin[1] + box[3])


def pill(canvas, text, at, size, align):
    """The tag: cream words on a dark plate in the logo's ink, with no blur or rim. Returns its box."""
    face = font(size)
    probe = ImageDraw.Draw(Image.new("L", (1, 1)))
    box = probe.textbbox((0, 0), text, font=face)
    pad_x, pad_y = size * 0.62, size * 0.32
    width = box[2] - box[0] + 2 * pad_x
    height = box[3] - box[1] + 2 * pad_y
    left = {"left": at[0], "center": at[0] - width / 2, "right": at[0] - width}[align]
    rect = (left, at[1], left + width, at[1] + height)
    plate = Image.new("L", canvas.size, 0)
    ImageDraw.Draw(plate).rounded_rectangle(rect, radius=size * 0.3, fill=255)
    canvas.alpha_composite(solid(canvas.size, PLATE, plate, 0.86))
    ImageDraw.Draw(canvas).text((left + pad_x - box[0], at[1] + pad_y - box[1]), text, font=face, fill=CREAM + (255,))
    return rect


def scrim(canvas, top):
    """A soft dark wash behind the caption's edge of the picture, so the words read over busy scenes."""
    width, height = canvas.size
    column = Image.new("L", (1, height))
    reach = 0.5
    for y in range(height):
        t = y / height if top else 1 - y / height
        column.putpixel((0, y), round(150 * max(0, 1 - t / reach) ** 1.6))
    canvas.alpha_composite(solid(canvas.size, (8, 28, 22), column.resize((width, height))))


def island_edges(shot):
    """How far in from the left and right edges the Dynamic Island's black pill reaches (0: none there). The
    simulator draws it into its screenshots, whatever the mask, and a landscape shot has it at one side."""
    gray = shot.convert("L")
    width, height = gray.size
    top, bottom = round(height * 0.3), round(height * 0.7)

    def solid_black(x):
        return gray.crop((x, top, x + 1, bottom)).histogram()[0] > (bottom - top) * 0.25

    band = round(width * 0.1)
    left = max((x + 1 for x in range(band) if solid_black(x)), default=0)
    right = max((width - x for x in range(width - band, width) if solid_black(x)), default=0)
    return left, right


def trim_island(shot):
    """The shot without the Dynamic Island: cropped clear of it, and as much off the height, so it keeps its
    shape (the slide scales it back up, a few percent)."""
    left, right = island_edges(shot)
    if not (left or right):
        return shot
    margin = round(shot.width * 0.012)
    x0 = left + margin if left else 0
    x1 = shot.width - (right + margin if right else 0)
    height = round((x1 - x0) * shot.height / shot.width)
    y0 = (shot.height - height) // 2
    return shot.crop((x0, y0, x1, y0 + height))


def slide(shot, spec, size):
    """One slide at `size`, laid out in BASE points scaled to it."""
    canvas = trim_island(shot).convert("RGBA").resize(size, Image.LANCZOS)
    scale = size[0] / BASE[0]
    place = spec.get("at", "bottom-left")
    vertical, horizontal = place.split("-")
    align = {"left": "left", "center": "center", "right": "right"}[horizontal]
    margin_x, margin_y = 120 * scale, 90 * scale
    x = {"left": margin_x, "center": size[0] / 2, "right": size[0] - margin_x}[horizontal]
    title_size = spec.get("size", 128) * scale
    tag_size = 50 * scale
    if spec.get("scrim", True):
        scrim(canvas, vertical == "top")

    # Measure the block (title over its pill) to stand it on the bottom margin, or hang it from the top one.
    probe = ImageDraw.Draw(Image.new("L", (1, 1)))
    face = font(title_size, TITLE_FONT)
    stroke = max(2, round(title_size * 0.075))
    box = probe.multiline_textbbox((0, 0), spec["title"].upper(), font=face, spacing=round(title_size * -0.08), align=align, stroke_width=stroke)
    title_height = box[3] - box[1] + title_size * 0.12
    gap = 26 * scale
    tag_height = tag_size * 1.0 + 2 * tag_size * 0.32 if spec.get("tag") else 0
    block = title_height + (gap + tag_height if spec.get("tag") else 0)
    y = margin_y if vertical == "top" else size[1] - margin_y - block

    if spec.get("logo"):
        logo = Image.open(LOGO).convert("RGBA")
        width = round(spec["logo"].get("width", 900) * scale)
        logo = logo.resize((width, round(logo.height * width / logo.width)), Image.LANCZOS)
        logo_place = spec["logo"].get("at", "top-center")
        lv, lh = logo_place.split("-")
        lx = {"left": margin_x, "center": (size[0] - width) / 2, "right": size[0] - margin_x - width}[lh]
        ly = 40 * scale if lv == "top" else size[1] - logo.height - 40 * scale
        canvas.alpha_composite(logo, (round(lx), round(ly)))

    drawn = lettering(canvas, spec["title"], (x, y), title_size, align)
    if spec.get("tag"):
        pill(canvas, spec["tag"], (x, drawn[3] + gap), tag_size, align)
    return canvas.convert("RGB")


def main(args):
    if len(args) < 2:
        print(__doc__)
        return 2
    shots, out = Path(args[0]), Path(args[1])
    sheet_path = Path(args[args.index("--sheet") + 1]) if "--sheet" in args else None
    slides = json.loads((TOOLS / "store_slides.json").read_text())["slides"]
    out.mkdir(parents=True, exist_ok=True)
    previews = []
    for number, spec in enumerate(slides, start=1):
        source = shots / f"{spec['shot']}.png"
        if not source.exists():
            print(f"  ! no {source.name}, skipped")
            continue
        shot = Image.open(source)
        if shot.width < shot.height:
            print(f"  ! {source.name} is portrait ({shot.width}×{shot.height}); the store scenes are landscape")
        for size in SIZES:
            image = slide(shot, spec, size)
            path = out / f"{number:02d}_{spec['shot'].removeprefix('store_land_')}_{size[0]}x{size[1]}.png"
            image.save(path, optimize=True)
            if size == SIZES[0]:
                previews.append(image)
        print(f"  {number:02d} {spec['shot']}: {spec['title']!r}")
    if sheet_path and previews:
        thumb = (874, 402)
        columns = 2
        rows = (len(previews) + columns - 1) // columns
        sheet = Image.new("RGB", (columns * thumb[0] + (columns + 1) * 16, rows * thumb[1] + (rows + 1) * 16), (238, 238, 238))
        for index, image in enumerate(previews):
            sheet.paste(image.resize(thumb, Image.LANCZOS), (16 + (index % columns) * (thumb[0] + 16), 16 + (index // columns) * (thumb[1] + 16)))
        sheet.save(sheet_path)
        print(f"  sheet: {sheet_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
