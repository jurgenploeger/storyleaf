# Sprite acceptance: generated art and worn gear

What a sprite must pass before it ships, and everything learned getting the heroes, their armour and the
festive gear right (playtesting 2026-10-18 to 2026-10-19, PR #201). Read it before generating or fitting any
character art, so none of this has to be found again. Add what you learn, with the date.

## The pipeline

1. **Generate** with Retro Diffusion (`tools/rd.py`, or a short script like it), into `art-variants/<name>/`,
   never straight into `art/sprites/`. Dry-run first and get the user's OK: it costs money (CLAUDE.md).
2. **Pick** a variant by eye, and name the picked file in `tools/wear_art.py` (`ARMOUR`, `WEAR`), so a rerun
   rebuilds the same sprites. A sheet with no source kept goes in `art-variants/legacy/` before it's touched.
3. **Fix in code, offline:** `tools/wear_art.py` copies armour sheets and brings their main material to one
   colour per family (`MATERIAL`); it cuts worn pieces out of reference sheets and moves them to fixed anchors
   (`art/sprites/wear_*.png`). `tools/item_art.py` draws items and the held weapons; `tools/hero_layers.py`
   splits hero sheets into paper-doll layers.
4. **Fit in the game:** `Storyleaf/Art/GearOverlay.swift` fits each piece to each frame as drawn.
   `tools/gear_preview.py` is the same algorithm in Python, line for line: change both together, as the
   cloud sessions can't build the app and the preview is the only way to see a change before CI.
5. **Check** with the grids below, `python3 tools/check_content.py`, then the CI screenshots.

## Acceptance criteria

Every criterion holds on **all six bodies** (human, elf and dwarf, each gender), **all four directions**,
**every armour cut and sheet** (`gear_preview.OUTFITS`: none, vest, hide, chain mail, robe, ranger cloak,
snow cloak, plate, dragon mail) and **every skin tone** (fair, rosy, tan, brown, deep). A fix that's right on
one body and wrong on another isn't done.

### Walk sheets (heroes, armour with a sheet of its own)

- 192 × 192, four 48 × 48 frames a row, rows facing up, right, down, left; transparent background, no stray
  pixels, nothing cut off at a frame's edge.
- The same poses as the race's own walk sheet: feet on the same row, head where the body's head is, give or
  take a pixel or two. The game hangs gear off the plain body (`GearLook.body`).
- A face that reads: two eyes with whites from the front, one from the side, none from behind. A child's
  face is clean-shaven (see the prompts below).
- Side and back views match the front: the same garment, the same colours, the same length.
- **Colour:** the main material within 3° of hue and 0.02 of median saturation and value of its family's
  target on every race (`wear_art.MATERIAL`; the numbers come from measuring, never from eyeballing). Skin,
  hair, leather and trim keep their own colours.
- Tier variants (`tint` in items.json) recolour the normalised sheet; a tint tuned on one race must look the
  same on the others. Check them all after any change to a sheet or a `MATERIAL` target.

### Head pieces (crown, Santa hat, bunny ears)

- The band sits on the head's widest row above the eyes, never over them, and never lower than three fifths
  of the way from the scalp's top to the eyes (a cowl or helmet is wide all the way down).
- As wide as the scalp and its outline and a little more, within 3 pixels of as drawn; a pom keeps its shape.
- The hair above the band is cleared: no spiky hair poking up between a crown's points or a bunny's ears.
- On armour with a pointed hat of its own (the robe), the hat replaces its tip. Accepted.

### Masks

- From the front, the eye holes are on the eyes; from the side, the front eye hole on the front eye.
- From the side, the mask's front edge reaches the face's front on every face row: no skin peeking out in
  front of it (it sat a pixel behind on the dwarves).
- Its bottom is at most two rows under the chin, over the top of a dwarf's beard and no more; its top at most
  a row above where the face shows. It was too tall on the dwarves.
- From the front, no wider than the face and its outline: it spilled onto the hair on narrow faces. It's
  narrowed beside its edges, so the eye holes stay on the eyes.
- Every colour (green, blue, red) recolours cleanly: check them all, not just the one the reference was.
- None from behind.
- It shows on every armour: an eye's white may be cream on an armour sheet, not pure white.

### Scarves

- Under the chin as drawn, on every armour: never over the mouth. Armour sheets draw the head higher or
  lower than the plain body, so the plain body's measurements can't place it.
- From behind, the chin found on the front view of the same walk frame.
- It's worn in the necklace slot (a necklace with `wear: scarf`), so it goes with any hat, helmet or hood.
  Festive items never drop from monsters or turn up on other adventurers out of season (`Content.isFestive`).

### Armour that leaves the head bare, and its hat

- No armour draws on the head (playtesting 2026-10-21: "any armor that shows a hat should have that as a
  hat item"): every armour sheet (`BARE_HEADED` in tools/wear_art.py, items.json `bareHead`) is cut at the
  neck, the hero's own head (`head_<body>`), beard and hairstyle drawn over it, and what's cut off is its
  hat (`hat_<kind>_<race>`, a hat item with `headgear`); a hide cloak's hood is its hat too (`hood_<body>`,
  painted in the hat's colour). Check every body, direction and frame: no leftover helmet or hood round
  the face, no gap at the neck; armour and its hat together look as the armour did; a hat over other
  armour, and with none, sits on the head and lets long hair show below it.

### Capes

- No holes: only the cape's own pixels, its gaps closed, a fresh outline round it.
- Its shadows take the cape's colour: no patch of the reference's red left on a blue cape.
- Its trim along the hem, its emblem on the back, its clasp at the collar from the front.
- From behind it hangs over the body, under the hair; from the front and side it shows past the outline.
- Stretched to each body's height and shoulders.
- No gap between it and the body in any frame (playtesting 2026-10-21): every walk frame, every
  direction, every body under every armour. From the front it's one cloth behind the body, its lining
  showing between an arm swung out and the body; from the side it meets the back, and nothing hangs
  between the legs. Check with an enclosed-hole count over `gear_preview.py --wear` (no clear pixel
  the cape closes in that the bare figure didn't), not just by eye.

### Portraits

- The round HUD portrait (`ArtLibrary.face`) is centred on the face in every outfit: a hero's is cut round
  their head as their plain body has it, sized by that body. Measured from the top of the sprite, a pointed
  hat or a hood pushed the face to the bottom of the circle.

### Held weapons and item icons

- Item icons are 32 × 32, drawn in `tools/item_art.py`, outlined.
- A weapon is held from its own sprites (`held_<id>_side.png`, `held_<id>_front.png`), its grip in the middle
  of a 64-pixel canvas, one of its pixels to one of the hero's, shrunk and turned offline before its outline.
  Never scale or turn pixel art by a fraction in the game: at 0.72 nearest-neighbour dropped every third row and
  column and every weapon looked ragged.
- Walking left or right it points up and away from the body, behind it, the hand over its grip.
- Facing you it stands nearly upright at the side, in front of the body, leaning out past the head (2026-10-22:
  held sideways from the front, as on the side, looked wrong). Facing away it's the same, behind the body. No
  blade or axe head over the face, on any body.
- A whip's lash hangs down from a short handle and trails on the ground by the feet (2026-10-22: held up like a
  sword, a whip read as a stick). Its icon keeps the coil.

## How to check

```
python3 tools/wear_art.py --sheet out.png           # the armour sheets and pieces as made
python3 tools/gear_preview.py --wear out.png <ids>  # items (joined by +) on every body under every armour
python3 tools/gear_preview.py --hats out.png        # every festive hat
python3 tools/gear_preview.py --capes out.png       # every status cape
python3 tools/gear_preview.py --weapons out.png <ids> [held sprite]  # weapons in hand on every body
python3 tools/gear_preview.py out.png               # every armour on every race
python3 tools/check_content.py
```

- Look at faces at 8× or 10× with a pixel grid, side views especially. Most of the misfits here were one or
  two pixels, invisible at 2×.
- Measure colours (median hue, saturation and value of the material's pixels), per race, before and after.
- Compare before and after side by side, and show the user both.
- CI's screenshot scenes (`tools/screenshots.txt`, the `wear_*` and `festive_*` ones) are the first look in
  the real game. Read them before calling it done.

## Learnings

### Retro Diffusion

- `rd_animation__four_angle_walking` at 48 × 48 with `return_spritesheet` gives a 192 × 192 walk sheet in our
  layout, $0.07 each. `num_images` is ignored: one image a call.
- Any prompt with "wizard" in it drew a beard, every time, even on a "kid". What worked: "cute chibi child
  adventurer, a smooth round young face with rosy cheeks, wearing a long blue hooded robe down to the feet
  with gold trim and a tall pointed blue hat over the hood, brown boots".
- Describe the garment's full extent ("down to the knees", "covering all the hair and neck") or it comes out
  short or leaves the hair out.
- For a piece to cut out (a hat, a cape), draw it on a plain wearer in colours nothing else shares: "cute
  chibi adventurer kid with short black hair, wearing ..., plain green tunic, brown belt and boots". Black
  hair and a green tunic keep a red hat or cape easy to find by colour.
- It draws each race a shade apart (the dwarf's robe much brighter, its plate greener and darker, the elf's
  mail darker and bluer). Always normalise, never trust it to match.
- It draws more than asked: the scarf came as a muffler up over the mouth, the cape partly hidden behind the
  wearer's arm. Cut to what the game needs.
- Weapons (pilot 2026-10-22, 8 weapons, $1.44): `rd_plus__topdown_item` at 64 × 64 costs what 32 does
  ($0.06 an image), and "lying diagonally, handle at the bottom left, tip pointing to the top right" gives
  the pose the game holds (GearArt.held) in most variants. `tools/weapon_art.py` shrinks a picked one to the
  icon and the held sprite at the drawn weapons' size. Swords, axes and staffs came out well; a plain
  hatchet came out a hammer, and no whip coiled (a stick, or a scaled blade). Held at 24 pixels most of
  RD's shading is gone, and a thin blade loses its crossguard: the gain is mostly on the 32-pixel icon.
  Placement needs nothing new: the held sprite goes on the hand measured on each frame, so it fits every
  body, direction, armour and cape alike (`gear_preview.py --weapons`).
- Inpainting walk sheets (`rd.py edit`) is a dead end: faces come out muddy at about 10 px wide, armour too
  bulky, and side and back views don't match the pose.
- A sheet is per race, not per gender: both genders wear the same armour sheet, over the hero's own hair from
  the nape down (`nape_*`), so long hair still shows.

### Cutting pieces out

- Find the piece by its colours, in the figure's top fifteen rows for a hat, and keep the biggest
  8-connected patch: eye whites, a shoe's shine or a red pixel elsewhere stay out.
- A dark ring round the patch makes a good outline for a small piece, but on a big one it pulls in the
  wearer's clothes. For a cape, keep only its own pixels, close its gaps (grow a pixel, shrink back, fill what
  it encloses, each new pixel the nearest own colour) and outline it afresh in a neutral dark.
- Move every piece to fixed anchors (`HAT_BRIM`, `ANCHOR_X`, `ANCHOR_Y`, `SHOULDER_Y`, `CHIN_Y`), and stretch
  it to standard sizes offline (the cape's `CAPE_DROP` and `CAPE_SPAN`), so the game only fits, never measures
  the reference.
- Measure the reference's face with the same code as the game (`gear_preview.face`), with the piece blanked
  out first: the scarf's white stripes passed for the face.

### Fitting to a hero

- Fit to the frame as drawn, hair and armour and all, not the bald body: a hat sized to the scalp perched on
  the hair like a box.
- Armour sheets have faces of their own, up to 5 rows from the plain body's, so find eyes and chins on the
  drawn frame.
- Eyes: a white pixel with a pupil or lash beside or over it and skin near. A cream white (saturation up to
  0.25) only if no pure one is found. The highest pair is the eyes.
- The skin test (hue under 40° or over 342°, saturation 0.12 to 0.65, value over 0.55) also passes ginger and
  red hair. Keep it to the face's own rows: from the eyes up and down, the rows that show skin.
- It knows only the sheets' own fair skin: on a brown or deep skin tone it finds no face at all. Find faces on
  the sprite before any recolouring (GearOverlay's `base`, the game's `original`), which has the same pixels
  in the same places; draw on the recoloured one. A mask slid off a deep-skinned hero's face (2026-10-19)
  because the preview, which then had no skin tones, never showed it.
- Pixel-art stretching repeats or drops whole rows or columns through the middle, spread a little, never
  scales. Keep a pom or a crown's points out of the stretch.
- Recolour a piece by the shade of each pixel against the piece's median, so every colour variant keeps the
  same shading; leave its white, outline and holes. Choose the floor for "coloured" per piece: a cape's
  deepest shadows are its colour too.
- From behind there's no face: use the front view of the same walk frame.

### Painted-on gear

- A hood's fur (pattern `fur`) goes round its opening only: the hood's pixels next to the face's skin. Laid
  on all its dark pixels it ran down the hood's side as a white wedge that read as a wing.

### Hero layers (`tools/hero_layers.py`)

- Paint the bald skull only inside the sprite as drawn: an ellipse painted past a side-view face stuck out
  like a brow ridge, and joined the left ear into a lump from the front.
- Don't soften brows: it read as a grey smudge and made the dwarf girl look angry.
- Bearded faces need a mouth line in the outline colour (`tools/character_art.py mouth`), which no hair dye
  touches.
- Never swap a whole hero sheet for a townsperson: hair shares its shades with skin and boots.

### Working on it

- Show the user before and after, side by side, at a size where the pixels show.
- The first pass always looks right on the body you tested; check all six bodies and every armour.
- Keep the Python mirror and the Swift in step and say so in both doc comments. Cloud sessions can't build:
  keep Swift edits small, and let Xcode Cloud and the CI tests compile them.
