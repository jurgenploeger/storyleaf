---
name: sprite-creation
description: How every sprite in Tales of Dorlune is made (a monster, boss, pet, townsperson, hero sheet, armour, worn piece, weapon, item, prop, tree, building, tile or critter), which of the four routes to take (a free palette swap, layers from the hero's paper doll, a drawing in code, or paid Retro Diffusion art), the steps for each, and the gate every new or changed sprite must pass before it ships. Use it whenever someone asks for a new creature, NPC, item, prop, building or any other art; to recolour, regenerate, fix, replace or restyle a sprite; to add a variant ("a rare blue version", "an ice slime"); when art looks off beside the rest; or when art/assets.json, art/sprites, a tools/*_art.py drawing or tools/rd.py comes up, even if the word "sprite" is never said.
---

# Sprite creation

Every sprite in the game is made one of four ways, and each way has its own steps, costs and
pitfalls. The rules for the look live in two long documents; this skill is the way in. It says which
route to take, what to do, which parts of the documents apply, and what has to pass before the sprite
counts as done. Done means it looks like it was always in the game.

Read these when the route calls for them. They are the source of truth, and they grow:
- [`docs/pixel-style.md`](../../../docs/pixel-style.md): the house look, measured (`tools/pixel_style.py`),
  and how to draw in code with `tools/pixel_kit.py`.
- [`docs/sprite-acceptance.md`](../../../docs/sprite-acceptance.md): what character art and worn gear must
  pass on every body, direction, armour and skin tone, and what Retro Diffusion taught us.
- The `sprite-idle-animation` skill: a sprite with eyes needs them boxed so it blinks.

## Pick the route

Go down this list and take the first that fits. The cheaper route is also the more consistent one,
because it reuses pixels that already look right.

1. **A palette swap (`derive`, free).** A variant of something that exists: a rare colour, an ice or
   fire version, a townsperson's outfit colour. Most monsters are this: 61 of the 124 are swaps.
2. **Paper-doll layers (`derive` with `layers`, free).** Any townsperson or quest giver who looks like a
   hero. Never swap a whole hero sheet, because hair shares its shades with skin and boots.
   `check_content.py` insists.
3. **Drawn in code (free).** Only what Retro Diffusion never made, or what it got wrong and the user
   asked to have fixed. That covers items, trees and bushes, buildings, lair pieces, gates, walls,
   critters, coins, ships and the like, each with its own `tools/*_art.py` (the list is in CLAUDE.md).
   **Never redraw Retro Diffusion's art in code.** An asset with a `request` is RD's, and so is what's
   derived from it.
4. **Retro Diffusion (paid).** A creature, boss or character that's new in shape, or a regeneration
   the user asked for. Dry-run first, tell the user the cost, and wait for their OK. It goes in
   `art/spend-log.jsonl`.

If two routes would do, say which you'd take and why in one line, and take the cheaper one unless the
user wants otherwise.

## Steps, by route

### 1. Palette swap
- Add the asset with `derive: {from, recolor}`. Recolour a whole colour family with one `to` and
  `spread` rule, so the hue-shifted shading survives. A bare `shift` lands on a different colour for
  every base, and a hue window that cuts a ramp splits it in two (CLAUDE.md, `RecolorRule`).
- Tune the rules before they go in: `sprite_check.py swap OUT <base> rules.json` draws each candidate
  set beside its base, recoloured as the game does it. Once written, `check` scores the swap in its own
  colours and `review` shows it beside its family (the colours, not the base's). Map art:
  `tools/palette_preview.py`.
- How a variant should look (the user's calls, 2026-10-31, on the Pegasus and skeleton colours):
  - **Light body, deep accent ("the Rosy and Emerald way").** Split each colour family by value with
    two rules on the same hue window: the lighter pixels (`minValue` about 0.6; about 0.42 for a
    darker sprite such as the frog) get a pale tint of the colour (saturation about 0.25 to 0.45,
    value 1.05 to 1.35), and the rest a deep, saturated shade of it (saturation 0.85 to 1.2, value 0.6
    to 0.85). Never body and accent in the same hue at the same strength: that's a blob of one colour
    ("doesn't look right").
  - **Keep the body light.** A coloured variant darkens only its accents. The first Midnight Pegasus
    darkened the whole coat ("the body pixels look too dark"); a pale periwinkle coat and a deep
    midnight mane fixed it.
  - **A dark variant (black with red) keeps its value steps.** Darken the light family by about half
    and the shading under it to nearly black, so the inner lines (ribs, joints) still part from the
    body. Darkening both by the same amount lost the skeleton's ribs in one dark blob. Make the
    "black" a cool slate (hue about 225, value about 0.65) over a clean near-black, not a warm,
    greyed red: a dull maroon-brown reads as mud ("too dark and becomes muddy"). Keep the accent
    colour (the red) to the aura, eyes and magic.
  - **The eyes stay visible.** Dark irises read against a light body and vanish against a dark one:
    give them a rule of their own (the Crimson Skeleton's dark-red irises, hue 325 to 15, at value ×2.4
    glow red). Look at the eyes at 4× on every candidate.
  - **One rule per colour family.** Find the families first (print the base's pixels in HSV: the
    skeleton has warm-white bone, lavender shading, purple sockets, red irises, green magic) and give
    each its own rule; anything no rule matches keeps its old colour. The first matching rule wins, so
    narrow rules (eyes) go first. The default `minSaturation` is 0.15, so greys and whites need
    `"minSaturation": 0` and a `maxSaturation`.
- A variant named for an element or a climate (Frost, Ember, Snow) lives in a land of that climate:
  `check_content.py` rejects a Frost monster in a hot land.
- A swap can't redraw its base: an outline or inner lines its base misses are inherited, and `check`
  says so instead of failing. Its colour is its own, so a pale, white or black variant can miss the
  saturation band: say so, it's the subject.
- A rare variant's stats (monsters.json, `rare` and `variantOf`): the base's ×1.3, growth
  max(v, round(v×1.2)), exp and gold ×1.6, capture rate ×0.6; its lore and name translated.
- Edit art/assets.json as text (insert the entry), never by loading and dumping the whole file: its
  layout isn't `json.dumps`', and a dump rewrites every line.
- A swapped monster blinks with its base's eyes. Nothing to add to `art/eyes.json`.

### 2. Townsperson from layers
- `derive: {from: <race sheet>, recolor, layers: [body, locks, hair...]}`, copying an existing quest
  giver's entry. The hair's rules widen to appearance.json `hairLayer`.
- Check it with the hairstyle stacked, from all four sides (`sprite_check.py review`, and
  `eyes.py zoom` for the face).

### 3. Drawn in code
- Use the tool for its family, or start a new `tools/<family>_art.py` built on `tools/pixel_kit.py`.
  Keep the drawing in the tool, so a rerun rebuilds it byte for byte.
- Follow *Making a sprite in code* in pixel-style.md, and that family's own section (trees, small
  sprites, snow, buildings, the ship, item icons).
- Register it in `art/assets.json` with no `request`. The tool's PNG wins over any `derive`.
- Score it: `tools/pixel_style.py check --kind <kind>` must pass for something new
  (`sprite_check.py check --new` runs it for you).

### 4. Retro Diffusion
- Write the asset's `request`, using the prompt patterns and styles in `references/rd-prompts.md`.
- `python3 tools/rd.py generate <id> --variants 3 --dry-run`, then tell the user what it will cost.
- After their OK, run the same command without `--dry-run`. All variants land in
  `art-variants/<id>/`, and **the first is also written to `art/sprites/<id>.png`**. It isn't picked
  yet, so look at all of them.
- Pick one by eye, `sprite_check.py review` beside its neighbours, then
  `python3 tools/rd.py use <id> <file>`. For worn gear, name the pick in `tools/wear_art.py` so a
  rerun rebuilds the same sprites.
- Fix in code only what the user asked to have fixed (a slab under a building: `tools/deslab.py`;
  armour colour: `wear_art.MATERIAL`).

### Wiring it into the game
A sprite nobody uses isn't done.
- A monster: `content/monsters.json` (`art`, `motion`), plus eyes or a `skipped` reason in
  `art/eyes.json`.
- A townsperson or prop: `content/maps.json`.
- An item: `content/items.json`.
- Run `python3 tools/check_content.py`, and add a screenshot scene in `tools/screenshots.txt` if none
  shows it.

## The gate

A sprite ships when all of these hold. Run `python3 .claude/skills/sprite-creation/scripts/sprite_check.py
check <ids> --new` for the first six (a palette swap scored in its own colours); the rest need eyes.

1. **Registered and made by its route.** In art/assets.json with the right kind, and made by its
   `request`, its `derive` or a tool that draws it. Nothing hand-edited that a rerun would undo.
2. **Its kind's size.** Monsters 40 or 64, walk sheets 192 (48 a frame), tiles 32, items 64,
   buildings 96 (160 or 192 for a grand one), props at their family's size. One art pixel to one of
   the world's, never scaled by a fraction.
3. **Hard pixels on a clear background.** No half-transparent pixel (a light-drawn icon aside), and no
   ground or slab under it unless it's a tile.
4. **The house look**, by number: `pixel_style.py check --kind <kind>` within the bands RD's own art
   sets.
5. **Characters and creatures look like Pixel Heroes:**
   - a dark outline all round (median light ≤ 0.25, half its pixels darker than that);
   - dark lines inside (≥ 20% of pixels darker than 0.2);
   - bright colour (median saturation ≥ 0.45, unless it's a white, grey or black subject);
   - chibi proportions, big eyes with a catchlight.
6. **Eyes boxed or skipped** for a monster, picture or sheet, by the `sprite-idle-animation` skill.
7. **It reads at 1×:** you can tell what it is from its silhouette alone, at the size it's drawn.
8. **It belongs beside its neighbours:** on `sprite_check.py review`'s sheet, at 1× and 4×, on the
   map's green and on the dark battle field, it looks like the same game. Detail on a par, the
   outline the same weight, colours from the same families.
9. **Every case, not one:** worn gear on all six bodies, four directions, every armour and every skin
   tone (`tools/gear_preview.py`, sprite-acceptance.md); a recolour on every base it's applied to.
10. **Seen in the game** before calling it done: CI's screenshot of a scene that shows it. If CI
    can't run, say plainly that it hasn't been seen in the game.

The style bands are calibrated on RD's own art, and some of RD's sprites fall outside them. That's
why `sprite_check.py check` only warns on existing art and fails on new art (`--new`). Never loosen a
band to get a new sprite through. Fix the sprite, or tell the user why it misses and let them decide.

## Showing the user

Show before and after, or the sprite beside its neighbours, side by side at a size where the pixels
show (4× or more), and say which route made it and what it cost. For paid art, show every variant and
say which you'd pick and why. The user's eye is the final judge, and what they say is worth more than
any number.

## Improving this skill

Each sprite made should leave the next one easier:
1. When something surprises you (a prompt that misfires, a check that passed something that looked
   wrong, a size or rule this skill doesn't know), write it down where it belongs, dated, with the case
   and what to do instead. Retro Diffusion goes in `references/rd-prompts.md`. The look goes in
   pixel-style.md *Learned*. Worn gear and characters go in sprite-acceptance.md *Learnings*.
2. If a script could have caught it, add the check: to `scripts/sprite_check.py` if it needs an image
   library, to `tools/check_content.py` if not, or as a band in `tools/pixel_style.py`. Then make sure
   the check fails on the bad case and passes on the fix.
3. If it changes the steps or the gate, update them here, with the reason, so the next case that's a
   little different is still covered.
