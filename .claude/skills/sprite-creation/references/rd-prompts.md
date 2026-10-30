# Retro Diffusion: styles, prices and prompts that work

Everything here comes from runs the game paid for (`art/spend-log.jsonl`, 411 runs, $43.66 to
2026-10-29) and from `docs/sprite-acceptance.md` *Learnings*. Add to it, dated, after every run that
teaches something.

## Styles and what they cost (per image, measured from the spend log)

| for | `prompt_style` | size | per image |
|---|---|---|---|
| a monster or boss | `rd_plus__low_res` | 40 × 40 (64 × 64 for a boss) | $0.04 ($0.05) |
| a walk sheet (hero, armour) | `rd_animation__four_angle_walking`, `return_spritesheet: true` | 48 × 48 → a 192 × 192 sheet | $0.07 |
| a weapon or an item drawing | `rd_plus__topdown_item` | 64 × 64 (costs what 32 does) | $0.06 |
| a prop or scenery | `rd_tile__tile_object` | 32 to 96 | $0.03 to $0.05 |
| a building | `rd_tile__tile_object` | 96 × 96 | $0.05 |
| a ground tile | `rd_tile__single_tile` | 32 × 32 | $0.03 |
| a detailed scene (app icon, art) | `rd_pro__fantasy` | 192 × 192 | $0.18 |
| inpainting a sheet (`rd.py edit`) | `edit:inpainting` | 192 × 192 | $0.18 (and a dead end: below) |

Everything except tiles and walk sheets sets `remove_bg: true`. Ask for three variants of anything that
matters. Each costs the same as one more run, and about one in four comes out wrong (upright instead of
diagonal, the wrong animal).

`rd.py generate` writes the first variant straight into `art/sprites/<id>.png`. That isn't a pick:
look at all of them, then `rd.py use`.

## The prompt pattern

The look the game wants is Pixel Heroes' (sprite-acceptance.md, *Characters and creatures*). A prompt
gets there with:

- **The subject first, concretely:** what it is, its colours by name, its one distinctive part (a crown,
  a lantern, crystal spikes), what it's holding.
- **"cute ... chibi"** for every character and creature. "big head, big eyes, thick dark outline" pushes
  toward the target. Without "chibi", "young adventurer hero" came out grown-up and realistic.
- **The full extent of anything worn:** "down to the knees", "covering all the hair and neck", or it
  comes out short or leaves things out.
- **Colours nothing else in the picture shares** for anything that will be cut out (a hat, a cape):
  "short black hair, plain green tunic, brown belt and boots" keeps a red hat easy to find by colour.
- **The pose the game holds**, for weapons: "lying diagonally, handle at the bottom left, tip pointing to
  the top right".

Examples that shipped (art/assets.json):
- `monster_jelly`: "cute round pink jelly blob monster with big shiny eyes, chibi" (`rd_plus__low_res`, 40).
- `player_walk`: "cute chibi adventurer kid with spiky orange hair, green tunic, brown belt and boots".
- `house`: "cozy fairytale cottage with a red tiled roof and round wooden door" (`rd_tile__tile_object`, 96).

## What misfires

- **"wizard" draws a beard, every time,** even on a "kid". What worked instead: "cute chibi child
  adventurer, a smooth round young face with rosy cheeks, wearing a long blue hooded robe down to the feet
  with gold trim and a tall pointed blue hat over the hood, brown boots".
- **A plain hatchet comes out a hammer** in two of three. No whip ever coiled: whips are drawn in code.
- **It draws each race a shade apart** (the dwarf's robe brighter, the elf's mail bluer). Never trust it to
  match: normalise in `tools/wear_art.py` (`MATERIAL`).
- **It draws more than asked:** a scarf as a muffler over the mouth, a cape half behind the arm. Cut to what
  the game needs.
- **`num_images` is ignored for walk sheets:** one sheet a call.
- **Inpainting walk sheets is a dead end:** faces come out muddy at about 10 px wide, armour too bulky,
  side and back views that don't match.
- **Small details vanish when shrunk:** a ghost's eyes on a staff, a thin blade's crossguard at 24 px held.
  Put the detail where it will be seen at its size.
- **Many existing creatures miss the outline target** (33 of 65 on 2026-10-25: pale tinted outlines on the
  Comet Hare, the Wisp, the frost bear, the Prism Drake, the Big Bad Wolf...). They're the first to
  regenerate when the user OKs the cost. Ask for "thick dark outline" in the prompt.
