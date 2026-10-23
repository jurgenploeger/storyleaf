# Pixel style: Storyleaf's look, without Retro Diffusion

What makes a sprite look like the rest of Storyleaf, measured, so art drawn in code can be held to it. The
reference is every sprite Retro Diffusion (RD) drew that the game ships; the goal is new sprites nobody can
tell apart from them, made for free and rebuilt from source. Read it before drawing a sprite in code; read
[sprite-acceptance.md](sprite-acceptance.md) too for anything worn by a hero. Add what you learn, with the
date: this is meant to get stricter as we go.

## The tools

- `tools/pixel_style.py`: the measurements. `calibrate` measures the reference and writes each criterion's
  accepted band to `tools/pixel_style.json`; `check [--kind icon|creature|scenery] <png>...` scores sprites
  (exit 1 on a fail); `compare` scores the RD icons against the code-drawn ones, the criteria's own test.
- `tools/pixel_kit.py`: a renderer for the look. A sprite is shapes (ellipses, polygons, thick strokes) in
  the sprite's own pixels, back to front, each of a `Material`; the kit lights, textures and quantises them
  into pixel art with the outline, rim light, contact shadows and highlights described below.
  `--demo out.png` redraws six code-drawn icons with it: as drawn now, the kit, and an RD icon, side by side,
  each with its score.

## The look, in words

These are the rules the numbers measure. A sprite that keeps them looks like Storyleaf.

1. **Hard pixels.** No anti-aliasing, no partial transparency, except a light effect (a magic staff's glow).
   Shrinking is done offline, each pixel the colour covering most of it, never by the game.
2. **One light, from the top left.** Every form is rounded by it: a lit rim on its top-left edge, a core
   shadow along its bottom right, and a contact shadow under anything lying on top of it.
3. **Ramps, not fills.** Each material is a ramp of shades: 3 to 5 on a 32-pixel icon, more on a bigger
   sprite (RD's icons have a median of 4 per ramp, its creatures 9). Shadows go deeper, more saturated and
   turn away from yellow round the colour wheel (a red's toward crimson, a blue's toward violet); highlights
   go paler and turn toward yellow (hue-shifting). Greys (steel, stone) get a cool tint in shadow and a warm
   one in the light, never dead grey.
4. **Texture everywhere.** No interior pixel sits in a field of its own colour: surfaces carry small
   clusters of near-duplicate shades (one to three pixels), and the clusters follow the light rather than
   scattering as noise. Dithering only to soften a step between two shades, never as a checkerboard field:
   on a sprite this small it reads as noise.
5. **Light from one side, not from the outline in.** Shading that darkens every edge evenly and brightens
   the middle ("pillow shading") flattens a form; RD's shade a form on its side away from the light.
6. **Clean lines.** Along a slope the steps of the outline grow or shrink steadily (1, 1, 2, 2, 3), never
   jump about (1, 3, 1, 3: "jaggies"); no lone pixel stuck out of an edge, no doubled corner.
7. **Outlines.** Item icons: one dark outline all round, the house colour `#231834` (`item_art.OUTLINE`).
   On something darker than it (a navy lash), the kit deepens it to half the light of what it rounds, so it
   still reads as the edge. Creatures, scenery and buildings: a broken, tinted outline, a deep shade of
   what it rounds and close to its colour, never near-black: a green tree's is dark green, a red roof's
   dark red (about 0.6 to 0.85 of the light inside it, `outline_rel`; the kit's `outline="tinted"` takes
   it from the shape's own ramp), lighter or gone where the light hits.
8. **A few highlights.** A speck or two of the lightest shade on what's glossy (gems, eyes), not a
   wash. Polished metal and cut stone get RD's glint: a small cross of near-white (`pixel_kit.GLINT`,
   `#f1f5f3`, one white for every metal) where the form faces the light, on its upper left, ringed by the
   lightest shade, and a speck more on another bulge; helms the same as the armour they go with.
9. **Size and placement.** Icons fill 80% or more of their 32 × 32 tile and sit in its middle (armour; a
   weapon sits on the bottom edge with room above for its glow). Creatures and scenery at their kind's size
   (`art/assets.json`: monsters 40 or 64, props 32 to 96, buildings 96, tiles 32).
10. **Light in broad areas, a palette kept small (buildings).** RD lights a house as a few big areas: a lit
    front, the side going back well into shadow, a dark band under the eaves, the lit roof plane bright at
    each tile's top, shadows turned toward blue and lights toward yellow. Detail sits on top of that, never
    instead of it (`light_masses`), and the whole house holds about 18 to 35 colours (`colour_density`
    capped as well as floored): every face its own seven shades made ours a hundred colours of grain.

## What the craft says (sources)

Read 2026-10-23, from search results (the network policy blocked fetching the pages themselves, so these
are their summaries, checked against each other). What each taught, and where it went:

- **Pillow shading and banding** are the two mistakes the craft names first: shading from the outline
  inward instead of from a light, and parallel bands of shades that follow the outline and reveal the
  sprite's pixel grid. A 2025 TU Delft thesis on detecting pixel-art mistakes automatically ("Pixel Fixer",
  [repository.tudelft.nl](https://repository.tudelft.nl/record/uuid:b3c91b18-d9e8-48e0-91ce-8afafd2439d8))
  measures them from the image, as `pixel_style.py` does: its `pillow` metric (reported).
- **Jaggies:** along a line or curve the run lengths should change steadily; an odd run breaks the slope
  ([Pixel Parmesan, anti-aliasing fundamentals](https://pixelparmesan.com/anti-aliasing-fundamentals-for-pixel-artists),
  [saint11's tutorials](https://saint11.art/blog/pixel-art-tutorials/)). Became the `jaggies` criterion,
  and the kit's cleanup of notches and spurs after shrinking.
- **Hue shifting:** shadows move round the wheel away from the light's colour, highlights toward it,
  rather than only darkening ([pixnote, shading](https://pixnote.net/en/learn/shading),
  [Slynyrd's Pixelblog](https://www.slynyrd.com/pixelblog-catalogue)). The kit turns shadows away from
  yellow (it had leaned every ramp toward blue, which turned a blue's shadow *toward* yellow: `hue_shift`
  negative on every blue item).
- **Outlines and selout:** a coloured outline, a deep shade of what it rounds, reads softer than black;
  lighter where the light hits ([Lospec, outlines part 2](https://lospec.com/articles/pixel-art-outlines-part-2-using-color)).
  Our icons keep one house outline (the game's choice for the bag); creatures and scenery are measured on
  tinted ones (`outline_sat`, `outline_value`).
- **Dithering restraint:** on a small sprite, dither only a narrow band between two shades; a field of it
  is noise ([pixnote, dithering](https://pixnote.net/en/learn/dithering),
  [Pixel Parmesan, dithering](https://pixelparmesan.com/dithering-for-pixel-artists)). The kit dithers only
  near a step; `checker` reports any field of it.
- **Shades per ramp:** a 16 to 32 pixel sprite needs 3 to 5 shades a material; more muddies it. RD's icons
  have a median of 4; ours had 6 (see the armour study below).
- **Scenery:** foliage in clusters of light and shade, never per-leaf noise; a top-down object lit from one
  side with its own shadow on the ground; a repeated prop varied by shape, not only by colour
  ([Slynyrd, top-down objects](https://www.slynyrd.com/blog/2019/9/18/pixelblog-21-top-down-objects)).

## RD's armour, studied (2026-10-23)

RD's 57 armour icons are the closest reference for everything worn, so the hats, gloves, boots and capes
drawn in code were measured against them (medians):

| | light from the top left | value range | colours / 100 px | highlight share | shades per ramp | hue shift | pass |
|---|---|---|---|---|---|---|---|
| RD's armour (57) | 0.12 | 0.59 | 3.8 | 0.06 | 4 | 9.1° | 84% |
| ours, worn pieces (143) | 0.31 | 0.61 | 4.2 | 0.10 | 6 | 12.3° | 84% |

What was changed to get there: the light comes more from the front (`pixel_kit.LIGHT`), so a form is lit
across its face and turns dark only at its edges, as RD's are; the ramps' ends are compressed (deep, rich
shadows, a pale top never white) and pivot lower, as RD's colours sit darker than a flat design's;
shadows turn away from yellow; a set piece takes its armour's colour. What's still different: our
light falls off more from the top left (0.31 against 0.12), which comes from the designs' own shading,
not the kit (softening the kit's light moved it by 0.01); and our ramps carry 6 shades to RD's 4.

`tools/pixel_style.py check` measures 15 criteria, and reports two more. Each one's band is the reference's 5th to 95th
percentile for its kind (icon, creature, scenery), recalibrated from the shipped art; a few are fixed
house rules, and three have house-rule floors under them (`pixel_style.FLOORS`, marked *floor*), set where
about 85% or more of RD's own sprites of that kind meet them. **A sprite passes with every hard criterion
and 80% of the soft ones.**

| criterion | what it measures | kind | icon | creature | scenery |
|---|---|---|---|---|---|
| `colour_density` | colours per 100 opaque pixels (ramps and texture) | hard, min | ≥ 2.4 | ≥ 1.7 | ≥ 0.6 |
| `flat` | share of inner pixels whose 8 neighbours are all their colour | hard, max | ≤ 0.02 | ≤ 0.14 | ≤ 0.14 |
| `outline_dark` | share of edge pixels darker than the inside | hard, min | ≥ 0.98 | ≥ 0.18 | – |
| `fill` | the sprite's longer side over the canvas (icons only) | hard, rule | ≥ 0.78 | – | – |
| `cluster_size` | mean size of same-colour patches inside: noise is 1, flat fills are big | soft | 1.4 – 3.3 | 1.6 – 4.8 | 1.3 – 4.9 |
| `outline_sat`, `outline_value` | the outline's colour: tinted, deep | soft | the house colour | 0.18+ / 0.11 – 0.57 | – |
| `orphans` | single pixels unlike all four neighbours | soft, max | ≤ 0.56 | ≤ 0.40 | ≤ 0.61 |
| `shades_per_ramp` | brightness levels in each ramp (colours chained by hue, greys one ramp) | soft, min | ≥ 3 *floor* | ≥ 5 *floor* | ≥ 4 *floor* |
| `hue_shift` | degrees a ramp's dark third sits further from yellow than its light third | soft, min | ≥ 0° *floor* | ≥ 6.1° | ≥ 2° *floor* |
| `value_range` | luma from the 5th to the 95th percentile | soft, min | ≥ 0.35 | ≥ 0.37 | ≥ 0.19 |
| `light_top_left` | correlation of brightness with nearness to the top left | soft, min | ≥ 0 *floor* | ≥ 0 *floor* | ≥ −0.05 *floor* |
| `highlight_share` | share of inner pixels far brighter than the median | soft | ≤ 0.29 | ≤ 0.18 | ≤ 0.25 |
| `semi_alpha` | partly transparent pixels (light effects only) | soft, max | 0 | 0 | 0 |
| `jaggies` | runs along one slope of the outline 2 or more longer, or shorter, than both neighbours | soft, max | ≤ 0.08 | ≤ 0.12 | ≤ 0.14 |
| `outline_rel` | the outline's light over the inside's within 2 pixels (median): deep, not black | hard (scenery, buildings), soft, min | ≥ 0.27 | ≥ 0.49 | ≥ 0.61 |
| `light_masses` | share of the inside's spread of light left after a 5 × 5 blur (buildings only) | soft, min | – | – | – |
| `pillow` | how much more the inside's light follows the distance in from the edge than the light | reported | – | – | – |
| `checker` | share of the inside in 2 × 2 checkerboards of two colours (dithering) | reported | – | – | – |

`pillow` and `checker` measure two classic mistakes the sources below warn about, but neither catches
anything yet: RD's icons have a median `pillow` of 0.10 and `checker` of 0.009, ours 0.09 and 0.008, and
the flat designs score lower still on both (−0.33, 0). So they describe and don't judge; promote one to a
criterion once a sprite fails it by eye.

The numbers above are from the 2026-10-23 calibration; `tools/pixel_style.json` holds the current ones.

### What the criteria have to do themselves

The criteria are only trusted while they tell the two kinds of art apart. Rerun `compare` after any change
to a metric or band:

- **The reference passes:** at least 80% of RD's own sprites of each kind (the bands are 5th to 95th
  percentiles, so a few of RD's own always fall outside one). 2026-10-23, with the floors, `jaggies` and
  `outline_rel`: icons 87% (122 / 140), scenery 82% (109 / 133), creatures 78% (51 / 65), buildings 69%
  (20 / 29, below).
- **The flat look fails:** `tools/item_art.py`'s designs, unfinished, pass at most 10%. 2026-10-23: 7%
  (22 / 322), failing on `cluster_size` (91%), `flat` (90%), `colour_density` (82%) and `shades_per_ramp`
  (79%). The same items as shipped, finished by the kit, pass 84% (289 / 343).

### Review by eye: what the numbers can't see

Numbers are necessary, not sufficient: a sprite can pass them all and still look off (2026-10-23: the kit's
first texture passed as salt-and-pepper noise, which is what added `cluster_size`). Before a sprite ships:

- Look at it **beside RD sprites of its kind**, at 1× and at 4× (`pixel_kit.py --demo` makes that sheet for
  icons; a contact sheet for the rest), and **in the game** (a CI screenshot: `tools/screenshots.txt`).
- **It reads at 1×:** you can tell what it is at the size it's drawn, from its silhouette alone.
- **Its detail matches its neighbours':** RD invents material detail (chain links, overlapping plates,
  scales, folds, seams). A sprite with less looks cheaper beside them, however well it's shaded.
- **The texture follows the form:** clusters run along the light, never as noise or a checkerboard.
- **Colours belong to the game:** the material's colour matches its family elsewhere (an armour's icon and
  its walk sheet: `wear_art.MATERIAL`).

When the eye catches something the numbers passed, write it down under *Learned* below and add or tighten
a criterion so it can't pass again. That is how the criteria get stricter.

### Buildings

RD's buildings have a band set of their own (`--kind building`, the 29 RD drew): a 96-pixel house holds
fewer colours to its size than a bush, and a third of RD's own failed the general scenery bands. Their
`outline_dark` is soft, not hard: RD draws buildings with a broken, tinted outline that a lit roof edge
goes without; but `outline_rel` is hard, so what outline there is stays a deep shade of the wall or roof.
Three more rules are theirs alone (playtesting 2026-10-23, "more and better shading and lighting, like
RD's"): `colour_density` is capped as well as floored (0.54 to 1.4 colours per 100 pixels, the cap a
house rule, `pixel_style.CEILINGS`, over all of RD's but its fence), `light_masses` at least 0.55 (a
floor met by 86% of RD's), and `outline_rel` at least 0.55. `tools/building_art.py` meets them with
quiet textures (`TEXTURE`), a stronger hue shift (`SHIFT`), faces lit by the way they turn (the side
going back 0.4 darker, the lit roof plane 0.14 lighter, the eave's shadow 0.6) and a palette cut to
about 1.1 colours per 100 pixels (`pixel_kit.limit_palette`, which merges the closest pair into the
commoner over and over, so a lit window or a flower keeps its colour). RD's buildings pass their own bands
69% (20 / 29), under the 80% the criteria aim for: in a sample of 29 every new band cuts one or two of
RD's own. Widen one before adding another.

## Restyle: how every item icon is finished

`tools/item_art.py` designs each item in flat three-tone fills (shapes, colours, details) and
`pixel_kit.restyle` finishes it: each region of colour becomes a material on a hue-shifted ramp, the
silhouette loses its square corners (never its notches or thin lines), the whole is lit from the top left
as one form with each region swelling a little on it, the drawing's own light and dark are kept as detail
(drawn dark lines count double), openings drawn in the outline colour become the inside of the thing in
the item's own colour (darkest at the back under the brim, the lower inner wall a few steps lighter where
the light comes in, its lip lightest; no dither), shiny things go smooth and glossy, a small drawing is scaled up to fill its tile from
4×, and sparkles and glows are kept as drawn. Items that are palette swaps of one (`derive` in
art/assets.json) are swapped on the flat drawing first, where their hue windows were tuned, and finished
the same way. Per-item options live in `item_art.RESTYLE` (smooth paper: less texture).

**Material presets** (`pixel_kit.PRESETS`) bring the detail RD invents and a design doesn't describe: a
pattern of light and shade at the sprite's own pixels, laid on the item's main (biggest) region, with the
finish that goes with it. `plate`: two or three overlapping plates to a piece, lit along their top edges
and shadowed under the next, rivets at their ends, a hard shine. `chain`: rings with dark holes, rows
offset. `scales`: offset rows, each lit on top and shadowed along its round foot. `cloth`: long soft folds
and a faint weave. `leather`: grain and a seam stitched two pixels in. `wood`: grain along its length.
`stone`: cracks and flecks. `fur`: short combed strands. `crystal`: facets, each its own tone, the ridges
lit. `metal`: polished, one hard streak. `item_art.preset_for` picks one per item: set hats by their kind
(plate helms, mail coifs, cloth hats and hoods), gauntlets and set boots plate, gloves and boots leather,
capes cloth, whips leather (scales for a dragon's, crocodile's or snake's), materials by name
(`MATERIAL_PRESETS`).

**Colour from the set.** A hat, gloves or boots that belong to an armour (`item_art.set_armour`) take
its colour from that armour's RD icon (`pixel_kit.dominant_colour`: the median colour of its commonest
hue), so a set reads as one set in the bag; every other region is deepened a little (`_deepen`), as RD's
colours sit lower and richer than a flat design's.

Families share their shapes, so fix a family's helper, not its items: `boot`, `glove`, `cape` and
`hat_piece` (helm, wizard's hat, coif, hood) in tools/item_art.py, drawn with curves (a calf and heel, a
rounded toe, fingers of different lengths with shadow between them, a domed helm with cheek guards, a hat
with its tip bent over, a hood with a soft peak), never boxes. Whips (`whip_line`) hang from the hand:
the handle up and to the right from the pommel, the lash out of its tip, over the top and down the right
in a loose arc, its end trailing off thin along the bottom; never coiled.

## Making a sprite in code

1. Describe it with `pixel_kit.Sprite`: shapes back to front, one `Material` per surface (base colour,
   `texture`, `gloss`; `profile="facet"` or flat planes with a `tone` for cut stone). Give it the detail RD
   would: seams, rivets, straps, folds, as their own shapes.
2. Render and score: `python3 tools/pixel_style.py check --kind icon <png>`.
3. Review by eye as above.
4. Keep the description in a tool (like `tools/prop_art.py` keeps its drawings), so a rerun rebuilds it.

## Where it stands (2026-10-23)

- **Every item icon drawn in code is finished by the kit** (322 of them, and the 21 palette swaps of
  them), most with a material preset: 84% pass (289 / 343), against 8% as designed; RD's own icons pass
  88%. Most of the rest fail on `cluster_size`, `hue_shift` (pale colours near yellow, whose shift has
  nowhere to go) or `jaggies`.
- **Monsters are all RD's** (checked 2026-10-23): 63 of the 124 drawn by RD, the other 61 palette swaps of
  them. Nothing to redraw there; the criteria's `creature` bands guard any added in code later.

![As drawn before, the kit, and RD's own](pixel-style-demo.png)

- The kit's first six icons (`pixel_kit.py --demo`: amber, agate, the amethyst boots and helm, the amber
  amulet, the alloy shortsword) all pass; as drawn now by `item_art.py`, one of them does. Beside RD's they
  read as the same game but plainer: less designed material detail, and RD's metals have more contrast.
- **Done 2026-10-23:** material presets; the three loose criteria tightened (`shades_per_ramp`,
  `hue_shift`, `light_top_left`, measured afresh: see *Learned*); `jaggies` added, `pillow` and `checker`
  reported; the kit tuned on RD's armour (above); whips redrawn hanging, as held.
- **UI icons (2026-10-23):** finished by the kit as the items are: 17 of 20 pass (2 did as drawn); three
  stay flat (`ui_icon_art.KEEP_FLAT`), as the finish ran their small parts together at button size.
- **Skill icons (2026-10-23): not pixel art.** Finished by the kit they passed 34 of 41, but read as
  objects, not as the spells they cast (playtesting: "more like their animations, with flares and
  glows"). `tools/skill_art.py` now draws each as light (glows, flares, sparks, trails in its element's
  colours) on a dark backdrop at 128 pixels, shown smoothed; these criteria don't apply to them.
- **Buildings (2026-10-23):** 20 drawn by `tools/building_art.py` (homes, shops, and buildings for the
  deserts, the steppe and Starfall Isle), all passing the building bands.
- **Scenery (2026-10-23):** the 21 trees and bushes that were palette swaps of RD's `tree` and
  `berry_bush` are drawn in code by `tools/scenery_art.py`, a species each; all 21 pass the scenery
  criteria. Lit from lower down than the icons (`Sprite.light`), edges darkened only where they turn
  from the light (`rim="lower"`), no seams between clusters, and a crown laid as clusters of leaves on a
  jittered grid (`puffs`), each lit on its own with a paler patch toward its top left. Beside RD's own
  `tree` they read as the same game but softer, with less contrast in the leaves.
- **Whips:** the shape and finish were picked by eye (2026-10-23); a three-pixel braided lash fails
  `cluster_size` and `orphans` by nature, so not every whip passes.
- **Next, in order:**
  1. Ramps of 4 to 5 shades on icons (RD's 4, ours 6), and less of the designs' own top-left falloff.
  2. Presets on more than the main region (a gauntlet's plate *and* its leather cuff), and per-region
     choice in the designs.
  3. A criterion for designed detail (how much of the inside is a deliberate line or edge, not texture),
     calibrated on RD, so a sprite with less detail than its neighbours fails by number, not only by eye.
  4. More scenery through the kit: the rest of the recoloured families (`crystal` ×6, `mushroom`,
     `giant_flower`, `gift_box`, the lollipops recoloured from a beach umbrella, three houses).
  5. Animation: walk cycles stay RD's for now (`sprite-acceptance.md`).

## Learned

- **2026-10-23 (critters):** At 10 to 15 pixels the kit's finish turns a sprite muddy: most of it is edge,
  so its rim shadows and ramps darken nearly every pixel (a white bunny came out grey, a chick olive).
  `tools/critter_art.py` keeps each part's colour and lights only the silhouette: its top and left a
  shade lighter, its bottom and right a shade darker and turned from yellow, a shade under a part of
  another colour lying on it, and an outline in a deep shade of each part.

- **2026-10-23 (frost tree):** The bare winter tree drawn as kit strokes looked out of place among RD's
  snow scenery: limbs of one width like pipes, a thin strip of snow, icicles. RD's snow is soft clumps in
  its own colours (`scenery_art.SNOW`, from its `snow_tree`); a near-white base on a ramp turns grey, so
  snow is drawn in a key blue and laid on RD's colours after. Twigs drawn by the kit get an outline each
  and run together into a dark mass at 64 pixels: they're single pixel lines (`pixel_lines`), as RD's.

- **2026-10-23 (outlines):** The tinted outline at 0.6 of each shape's darkest shade came out near-black
  (`outline_rel` 0.37 on our trees and houses, against RD's 0.6 to 0.85), the stark black line round
  everything we drew. It's now the shape's own ramp at the shade of the body within two pixels, about
  0.74 of its light (0.9 on the lit top and left), a touch richer: our trees 0.81, houses 0.77. Taken
  from each pixel it touched, it doubled the colour count; from the ramp a material's outline holds a
  handful. Taken from the darkened rim alone, pale bushes still came out too dark.
- **2026-10-23 (buildings):** Seven shades for every face, a second ramp to flick between and texture on
  every pixel gave our houses 115 to 180 colours against RD's 18 to 35, and light that lived in grain
  instead of areas. Fewer, broader: quieter textures, one ramp, the palette merged to about RD's size,
  and the faces' light set by how they turn.

- **2026-10-23 (buildings):** Patterns laid in the screen's rows put a receding roof's tiles at the wrong
  angle; each face now carries its own axes (`building_art.surface(axes=...)`: along its eave, down its
  slope or wall), so tiles run along the eave and their seams down the slope. Evenly lit faces looked
  flat: walls now lie in the eave's shadow at the top and the ground's at the foot, the side going back
  a step darker, a lit corner, the roof's edge thick, its planes lit by the way they face.

- **2026-10-23 (icons):** A design's halves in a colour's mid and light leave the light the commonest, and
  the finish ramps the whole shape from it: an orange arrow came out beige. Draw in the mid and the
  shadow; the finish brings the light. Small parts closer than about three pixels (a paw's toes, three
  dots) run together once rounded and outlined: space them, or keep the drawing flat.

- **2026-10-23 (buildings):** Pale plaster on a ramp turns cold grey (its shadows turned away from yellow),
  as fur did: a wall's colour is drawn a little deeper and warmer (`#ead2a8`, not `#efe4d0`) so its middle
  stays cream. Drawn at a guessed size, the houses filled half their frame beside RD's; each is now scaled
  to fill it, its materials' patterns kept at the sprite's own pixels.

- **2026-10-23 (scenery):** A crown of leaf clusters placed at random came out lopsided; on a jittered grid
  it's full and even. Big clusters on a 32-pixel bush read as a smooth lump: RD's bushes are leafy, so
  bushes use many small clusters (3 pixels across) and trees fewer, bigger ones. Seams between clusters
  read as cracks: RD parts them by shadow alone.

- **2026-10-23 (hue shift):** "Shadows toward blue" is a shortcut that only works for warm colours: on a
  blue it turns the shadow toward cyan and yellow, the wrong way, and every blue item measured a negative
  `hue_shift`. The rule is relative to the light: shadows away from yellow, round the short way.
- **2026-10-23 (outline):** The house outline is no darker than a navy or shadow-violet item, and those
  failed `outline_dark`; it's now deepened to half the light of what it rounds.
- **2026-10-23 (whips):** Four shapes tried; the one picked is the lash arching from the handle's tip over
  the top and down the right, its end flicked along the bottom. A coil read as a rope, an S from a
  diagonal handle as a hook, a closed D loop as a lasso. Its tip trailing off into a few specks was
  liked as it is: thickening it to one line made a heavy foot.
- **2026-10-23 (hoods):** A hood's opening as one flat dark shade read as a black hole: the inside needs
  its own light, darkest under the brim and lighter down the lower inner wall.
- **2026-10-23 (fur):** A hood's fur drawn as a thin even cream ring read as a white border, nothing
  like the fur on the cloak it goes with; a thick tufted one read as overdone. As on the cloak's collar:
  about 3 pixels, a smooth edge, shaded cream, beige and a warm taupe (`item_art.FUR`), a few flecks;
  kept in its drawn colours
  (`restyle(trim=...)`), as re-ramped its shadows turned a cold grey. A trim can outsize the cloth it
  edges, so it's never the region that takes the set's colour.
- **2026-10-23 (coif):** A face painted in a coif's opening read as a skin-coloured stain at icon size;
  the opening is the inside, in shadow, like a hood's.
- **2026-10-23 (restyle):** The outline colour (a deep violet) grouped with a purple hood by hue, so the
  whole hood was shaded as its own opening. The outline colour is now a region of its own.
- **2026-10-23 (glints):** RD's armour has a near-white glint on each plate; our helms had only a
  lightest-shade speck, so beside their armour they looked dull. A plate's lit lower edges can outshine
  its dome, so the main glint is looked for on the upper left.
- **2026-10-23 (restyle):** Colour families group by hue (within 22°): a yellow paw and a yellow-brown grip
  became one region and the paw turned brown. Give parts that must stay apart hues that are apart.

- **2026-10-23 (criteria):** `shades_per_ramp` and `hue_shift` first grouped colours in fixed 30° hue
  bins; a hue-shifted ramp crosses bins by design, so it was split and counted short (RD's own icons scored
  a median of 3 shades, and a shift could never exceed 30°). Ramps are now chained by hue (a gap over 25°
  starts a new one), greys one ramp, shades counted as brightness levels: RD's icons median 4, creatures
  9, the flat designs 2. Fix the measurement before tightening a band on it.
- **2026-10-23 (presets):** A preset must add to the design's own shading, never replace it: replaced, a
  silver ingot lost its lit top and shaded side and went flat.
- **2026-10-23 (presets):** Plate bands every 5 pixels made helms look like hamburgers; RD draws two or
  three overlapping plates to a piece, so the band spacing follows the piece's height.
- **2026-10-23 (ramps):** A base drawn in pure white leaves the ramp nowhere to go but white: the base is
  capped at 0.88 brightness, and a pale colour sits lower on its ramp.

- **2026-10-23:** RD's icons have almost no flat area (median `flat` 0) and small colour patches (median
  cluster 1.9 pixels): the texture is fine-grained, not blotchy. Code-drawn icons fail on exactly that.
- **2026-10-23:** Texture added before shrinking averages away; it has to be added at the sprite's own
  pixels, in 2-pixel clusters (per-pixel noise reads as salt-and-pepper).
- **2026-10-23:** One clean ramp per material looks plastic: RD's surfaces carry near-duplicate colours. A
  second ramp a few degrees round the wheel, picked in 2 × 2 patches, brought the kit up to RD's colour
  density.
- **2026-10-23 (restyle):** Blur-and-threshold rounding fills notches as readily as it cuts corners: a
  glove's fingers merged into a mitten. Rounding may only remove pixels, and a thin line (body neighbours
  on opposite sides) is kept while a one-pixel spur (one neighbour) is cut.
- **2026-10-23 (restyle):** A hood's opening drawn in black came out as a flat black hole; RD shades the
  inside of a hood as a deep shadow of the hood's own colour.
- **2026-10-23 (restyle):** Palette swaps tuned on flat fills miss hue-shifted ramps (shadows lean blue,
  highlights yellow): swap the design, then finish it, never the other way round.
- **2026-10-23 (restyle):** Pale materials need a higher shadow floor, or a pearl's shade drops to navy.
- **2026-10-23:** Cut gems read best as explicit planes, each with its own tone (lit crown on the left, the
  pavilion stepping into shade to the right), not as a dome.
