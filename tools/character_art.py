#!/usr/bin/env python3
"""Masks for redrawing parts of the heroes' walk sheets with Retro Diffusion's inpainting, so new
art keeps the sheets' own poses, proportions and faces (`tools/rd.py edit … --mask`).

    python3 tools/character_art.py masks dwarf_walk:dwarf dwarf_female_walk:dwarf
    python3 tools/character_art.py masks dwarf_walk:dwarf --kind body
    python3 tools/character_art.py preview out.png dwarf_walk:dwarf

Each sheet is named with its race (hero_layers.py finds the heads the same way it does for the
paper-doll layers). Masks go to art-variants/_masks/<sheet>_<kind>.png (outside art/, so they never ship), white where the art is redrawn:

    face   the face from the hairline to the chin (the eyes, brows and forehead), every frame but
           the back views. The hair, the body and the walk stay exactly as they are.
    body   everything below the chin, a little wider than the body so armour can stand out from
           it; the head is kept, so every armour is worn by the same character.
    helmet like body, with the hair and the top of the head too: a helmet or a hood, the face kept.

Needs pillow + numpy.
"""
import argparse
import pathlib
import sys

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import hero_layers as hl  # noqa: E402

MASKS = ROOT / "art-variants" / "_masks"
F = hl.F


def grow(mask, steps):
    return hl.grow(mask, steps) if steps else mask


def frame_masks(race, row, col, kind):
    """One frame's mask (F × F) for `kind`."""
    f = hl.frame(race.sheet, row, col)
    solid = np.array([[hl.opaque(f[y, x]) for x in range(F)] for y in range(F)])
    head = race.heads[row, col]
    face = race.faces.get((row, col), np.zeros((F, F), bool))
    if kind == "face":
        if head.facing == "up" or not face.any():
            return np.zeros((F, F), bool)
        # The forehead too: the skin above the brow inside the skull, where the eyes should rise to.
        brow = np.zeros((F, F), bool)
        for y in range(head.top, head.brow + 1):
            for x in range(F):
                brow[y, x] = head.inside(x, y) and hl.is_skin(f[y, x])
        return grow(face | brow, 1) & grow(solid, 1)
    chin = max([y for y in range(F) if face[y].any()], default=head.brow + 6)
    below = np.zeros((F, F), bool)
    below[chin + 1:] = True
    if kind == "body":
        return grow(solid & below, 2)
    if kind == "helmet":
        keep = grow(face, 0) if head.facing != "up" else np.zeros((F, F), bool)
        return grow(solid, 2) & ~keep
    raise SystemExit(f"unknown kind {kind}")


def sheet_mask(race, kind):
    rows, cols = race.sheet.shape[0] // F, race.sheet.shape[1] // F
    out = np.zeros(race.sheet.shape[:2], bool)
    for row in range(rows):
        for col in range(cols):
            out[row * F:(row + 1) * F, col * F:(col + 1) * F] = frame_masks(race, row, col, kind)
    return out


def races(specs):
    for spec in specs:
        sheet, _, race_id = spec.partition(":")
        yield sheet, hl.Race(race_id or "human", sheet)


def write(mask, path):
    rgba = np.zeros(mask.shape + (4,), np.uint8)
    rgba[mask] = (255, 255, 255, 255)
    Image.fromarray(rgba, "RGBA").save(path)


def cmd_masks(args):
    MASKS.mkdir(parents=True, exist_ok=True)
    for sheet, race in races(args.sheets):
        mask = sheet_mask(race, args.kind)
        path = MASKS / f"{sheet}_{args.kind}.png"
        write(mask, path)
        print(f"{path.relative_to(ROOT)}: {int(mask.sum())} pixels to redraw")


def cmd_preview(args):
    tiles = []
    for sheet, race in races(args.sheets):
        image = (np.clip(race.sheet, 0, 1) * 255).astype(np.uint8)
        marked = image.copy()
        mask = sheet_mask(race, args.kind)
        marked[mask] = (marked[mask] * 0.4 + np.array([255, 0, 255, 255]) * 0.6).astype(np.uint8)
        tiles.append(np.concatenate([image, marked], 1))
    big = np.concatenate(tiles, 0)
    picture = Image.fromarray(big, "RGBA").resize((big.shape[1] * 3, big.shape[0] * 3), Image.NEAREST)
    background = Image.new("RGBA", picture.size, (90, 110, 90, 255))
    background.alpha_composite(picture)
    background.save(args.out)
    print(args.out)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    commands = parser.add_subparsers(dest="command", required=True)
    masks = commands.add_parser("masks")
    masks.add_argument("sheets", nargs="+", help="sheet:race, e.g. dwarf_walk:dwarf")
    masks.add_argument("--kind", default="face", choices=["face", "body", "helmet"])
    masks.set_defaults(run=cmd_masks)
    preview = commands.add_parser("preview")
    preview.add_argument("out")
    preview.add_argument("sheets", nargs="+")
    preview.add_argument("--kind", default="face", choices=["face", "body", "helmet"])
    preview.set_defaults(run=cmd_preview)
    args = parser.parse_args()
    args.run(args)


if __name__ == "__main__":
    main()
