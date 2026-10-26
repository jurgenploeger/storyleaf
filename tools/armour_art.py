#!/usr/bin/env python3
"""Armour icons from Retro Diffusion: one picked 64-pixel RD drawing per armour shape (art-variants/
rda_<shape>/), made into every armour's 64 × 64 icon (art/sprites/item_<id>.png) the way
tools/weapon_art.py makes a weapon's: its own outline taken off, kept at its own size, outlined afresh
in a deep shade of what it rounds (`weapon_art.icon`, 2026-10-26: the item icons' clean look).

Coloured as the armour is worn, so the icon and the hero match (playtesting 2026-10-23: the drawn
icons "look quite bad now, while we have the RD version"): an armour with walk sheets (items.json
`sheets`) has its main material brought to the sheets' colour (wear_art.py MATERIAL) and then its
`tint`; a hide cloak takes its hood's (`headpiece`), which is drawn in the same blue. Shapes with
no sheets keep the drawing's colours, and their recoloured kin (assets.json `derive`, the mossy
and autumn vests and the like) recolour this icon in the game.

    python3 tools/armour_art.py                  # every armour icon
    python3 tools/armour_art.py --sheet out.png  # and a contact sheet of them
"""

import io
import json
import pathlib
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import item_art as ia  # noqa: E402
import weapon_art as wa  # noqa: E402
from palette_preview import recolor  # noqa: E402
from wear_art import MATERIAL, material  # noqa: E402

ROOT = ia.ROOT
VARIANTS = ROOT / "art-variants"

# Armour shape → the picked RD drawing under art-variants/ (rd_plus__topdown_item, 64 × 64).
PICKED = {
    "cloth_tunic": "rda_cloth_tunic/20261023-115537_2.png",
    "leather_vest": "rda_leather_vest/20261023-115606_0.png",
    "chain_mail": "rda_chain_mail/20261023-115630_1.png",
    "iron_plate": "rda_iron_plate/20261023-115653_1.png",
    "dragon_mail": "rda_dragon_mail/20261023-115731_0.png",
    "mage_robe": "rda_mage_robe/20261023-115755_2.png",
    "ranger_cloak": "rda_ranger_cloak/20261023-115815_0.png",
    "snow_cloak": "rda_snow_cloak/20261023-115840_2.png",
    "tamer_jacket": "rda_tamer_jacket/20261023-115902_1.png",
    "hide_cloak": "rda_hide_cloak/20261023-115933_0.png",
}


def items():
    return {i["id"]: i for i in json.loads((ROOT / "content" / "items.json").read_text())["items"]}


def plan():
    """Each armour this tool draws → (its shape, the MATERIAL to bring it to, the tint on top)."""
    all_items = items()
    out = {}
    for item in all_items.values():
        if item["type"] != "armor":
            continue
        if item.get("sheets"):
            shape = item["sheets"]["human"][len("armor_"):-len("_human")]
            out[item["id"]] = (shape, MATERIAL[shape], item.get("tint") or [])
        elif item.get("wear") == "cloak":
            hood = all_items[item["headpiece"]]
            out[item["id"]] = ("hide_cloak", MATERIAL["hide_hood"], hood.get("tint") or [])
        elif item["id"] in PICKED:
            out[item["id"]] = (item["id"], None, [])
    return out


def icon(shape, mat, tint, small=False):
    """The icon: the picked drawing coloured as worn, then made as a weapon's is (`weapon_art.icon`).
    `small`: as it was till 2026-10-26, shrunk to 32 and centred, the reference of pixel_style's `icon`
    bands (`pixel_style.reference`)."""
    img = np.asarray(Image.open(VARIANTS / PICKED[shape]).convert("RGBA")).astype(float) / 255
    if mat:
        img = material(img, **mat)
    if tint:
        img = recolor(img, tint)
    buf = io.BytesIO()
    Image.fromarray((np.clip(img, 0, 1) * 255).round().astype(np.uint8), "RGBA").save(buf, "PNG")
    buf.seek(0)
    if small:
        return centred(wa.shrink(wa.load(buf), ia.SIZE, wa.ICON_INNER))
    return wa.icon(wa.load(buf))


def centred(c):
    """The icon moved to the middle of its canvas by what's drawn: shrink() sits a weapon on the
    bottom edge, and keeps whatever margin the RD drawing had, so robes and cloaks came out low and
    to the left in the inventory's tiles (playtest 2026-10-23)."""
    drawn = [(x, y) for y in range(c.size) for x in range(c.size) if c.px[y][x]]
    xs, ys = [x for x, _ in drawn], [y for _, y in drawn]
    dx = (c.size - (max(xs) - min(xs) + 1)) // 2 - min(xs)
    dy = (c.size - (max(ys) - min(ys) + 1)) // 2 - min(ys)
    out = ia.Canvas(c.size)
    for x, y in drawn:
        out.px[y + dy][x + dx] = c.px[y][x]
    return out


def main(argv):
    sheet = None
    if "--sheet" in argv:
        sheet = argv[argv.index("--sheet") + 1]
    made = []
    for item_id, (shape, mat, tint) in plan().items():
        c = icon(shape, mat, tint)
        (ia.SPRITES / f"item_{item_id}.png").write_bytes(c.png())
        made.append(item_id)
    print(f"wrote {len(made)} armour icons to art/sprites/")
    if sheet:
        cols, scale = 8, 4
        cell = ia.SIZE * scale + 4
        out = Image.new("RGB", (cols * cell, -(-len(made) // cols) * cell), (58, 58, 70))
        for n, item_id in enumerate(made):
            im = Image.open(ia.SPRITES / f"item_{item_id}.png").convert("RGBA")
            im = im.resize((ia.SIZE * scale, ia.SIZE * scale), Image.NEAREST)
            out.paste(im, ((n % cols) * cell + 2, (n // cols) * cell + 2), im)
        out.save(sheet)
        print(f"wrote {sheet}")


if __name__ == "__main__":
    main(sys.argv[1:])
