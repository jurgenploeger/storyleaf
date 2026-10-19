#!/usr/bin/env python3
"""Worn gear from Retro Diffusion sheets (art-variants/), made ready for the game in code.

    python3 tools/wear_art.py                  # writes the PNGs below
    python3 tools/wear_art.py --sheet out.png  # also a contact sheet to look at

Armour that wears a whole walk sheet of its own (items.json `sheets`, like Iron Plate's) is a sheet
Retro Diffusion drew per race, copied from the variant picked below: the robe's blue brought to one
royal blue on every race (Retro Diffusion drew the human's a little teal), so a tier's `tint` lands
on the same colour everywhere.

    art/sprites/armor_mage_robe_<race>.png    the blue hooded robe and pointed hood
    art/sprites/armor_chain_mail_<race>.png   chain mail with its coif over the hair

Needs pillow + numpy.
"""
import argparse
import pathlib
import sys

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from palette_preview import recolor, rgb2hsv  # noqa: E402  (the game's RecolorRule, in Python)

VARIANTS = ROOT / "art-variants"
SPRITES = ROOT / "art" / "sprites"
RACES = ("human", "elf", "dwarf")

# The variant each sheet is made from (2026-10-19). The robe was rerolled until the kid had no
# beard: a prompt with "wizard" in it drew one every time.
ARMOUR = {
    "armor_mage_robe_human": "pilot_mage_robe_human_v4/20261019-115504_0.png",
    "armor_mage_robe_elf": "pilot_mage_robe_elf_v3/20261019-115524_0.png",
    "armor_mage_robe_dwarf": "pilot_mage_robe_dwarf/20261019-115017_0.png",
    "armor_chain_mail_human": "pilot_chain_mail_human/20261019-113735_0.png",
    "armor_chain_mail_elf": "pilot_chain_mail_elf/20261019-115042_0.png",
    "armor_chain_mail_dwarf": "pilot_chain_mail_dwarf/20261019-115104_0.png",
}
# The robes' blue, whatever shade Retro Diffusion drew, turned so its middle lands on one hue, every
# shade turned alike so the hue-shifted shading stays.
ROBE_BLUES = [170, 260]
ROBE_BLUE = 222


def load(path):
    return np.asarray(Image.open(path).convert("RGBA")).astype(float) / 255


def save(img, name):
    Image.fromarray((np.clip(img, 0, 1) * 255).round().astype(np.uint8), "RGBA").save(SPRITES / f"{name}.png")


def blue(img):
    """The middle hue of the robe's blue pixels."""
    h, s, _ = rgb2hsv(img[..., :3])
    robe = (img[..., 3] > 0) & (s >= 0.2) & (h >= ROBE_BLUES[0]) & (h <= ROBE_BLUES[1])
    return float(np.median(h[robe]))


def armour():
    made = {}
    for name, source in ARMOUR.items():
        img = load(VARIANTS / source)
        if name.startswith("armor_mage_robe"):
            img = recolor(img, [{"hue": ROBE_BLUES, "minSaturation": 0.2, "shift": ROBE_BLUE - blue(img)}])
        save(img, name)
        made[name] = img
        print(f"art/sprites/{name}.png  from art-variants/{source}")
    return made


def contact(made, out):
    zoom = 3
    sheet = Image.new("RGBA", (4 * 48 * zoom, len(made) * 48 * zoom), (92, 128, 92, 255))
    for i, img in enumerate(made.values()):
        im = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "RGBA")
        for j, row in enumerate((2, 1, 0, 3)):
            frame = im.crop((0, row * 48, 48, row * 48 + 48)).resize((48 * zoom, 48 * zoom), Image.NEAREST)
            sheet.alpha_composite(frame, (j * 48 * zoom, i * 48 * zoom))
    sheet.save(out)
    print(out)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--sheet", help="also write a contact sheet here")
    args = parser.parse_args()
    made = armour()
    if args.sheet:
        contact(made, args.sheet)


if __name__ == "__main__":
    main()
