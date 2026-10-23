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
3. **Ramps, not fills.** Each material is a ramp of 5 to 8 shades. Shadows go deeper, more saturated and
   lean toward blue-violet; highlights go paler and lean toward yellow (hue-shifting). Greys (steel, stone)
   get a cool tint in shadow and a warm one in the light, never dead grey.
4. **Texture everywhere.** No interior pixel sits in a field of its own colour: surfaces carry small
   clusters of near-duplicate shades (one to three pixels), and the clusters follow the light rather than
   scattering as noise.
5. **Outlines.** Item icons: one dark outline all round, the house colour `#231834` (`item_art.OUTLINE`).
   Creatures and scenery: a broken, tinted outline (a deep shade of what it rounds), lighter or gone where
   the light hits.
6. **A few highlights.** A speck or two of the lightest shade on what's glossy (metal, gems, eyes), not
   a wash.
7. **Size and placement.** Icons fill 80% or more of their 32 × 32 tile and sit in its middle (armour; a
   weapon sits on the bottom edge with room above for its glow). Creatures and scenery at their kind's size
   (`art/assets.json`: monsters 40 or 64, props 32 to 96, buildings 96, tiles 32).

## The acceptance criteria

`tools/pixel_style.py check` measures 14 criteria. Each one's band is the reference's 5th to 95th
percentile for its kind (icon, creature, scenery), recalibrated from the shipped art; a few are fixed
house rules. **A sprite passes with every hard criterion and 80% of the soft ones.**

| criterion | what it measures | kind | icon | creature | scenery |
|---|---|---|---|---|---|
| `colour_density` | colours per 100 opaque pixels (ramps and texture) | hard, min | ≥ 2.6 | ≥ 1.7 | ≥ 0.6 |
| `flat` | share of inner pixels whose 8 neighbours are all their colour | hard, max | ≤ 0.02 | ≤ 0.14 | ≤ 0.14 |
| `outline_dark` | share of edge pixels darker than the inside | hard, min | ≥ 0.98 | ≥ 0.18 | – |
| `fill` | the sprite's longer side over the canvas (icons only) | hard, rule | ≥ 0.78 | – | – |
| `cluster_size` | mean size of same-colour patches inside: noise is 1, flat fills are big | soft | 1.4 – 3.3 | 1.6 – 4.8 | 1.3 – 4.9 |
| `outline_sat`, `outline_value` | the outline's colour: tinted, deep | soft | the house colour | 0.18+ / 0.11 – 0.57 | – |
| `orphans` | single pixels unlike all four neighbours | soft, max | ≤ 0.56 | ≤ 0.40 | ≤ 0.61 |
| `shades_per_ramp` | shades in each material's ramp | soft, min | ≥ 1 | ≥ 4 | ≥ 2 |
| `hue_shift` | degrees the dark shades sit further from yellow than the light ones | soft, min | ≥ −1.9 | ≥ 0.6 | ≥ −3.9 |
| `value_range` | luma from the 5th to the 95th percentile | soft, min | ≥ 0.35 | ≥ 0.37 | ≥ 0.19 |
| `light_top_left` | correlation of brightness with nearness to the top left | soft, min | ≥ −0.09 | ≥ −0.06 | ≥ −0.17 |
| `highlight_share` | share of inner pixels far brighter than the median | soft | ≤ 0.29 | ≤ 0.18 | ≤ 0.25 |
| `semi_alpha` | partly transparent pixels (light effects only) | soft, max | 0 | 0 | 0 |

The numbers above are from the 2026-10-23 calibration; `tools/pixel_style.json` holds the current ones.

### What the criteria have to do themselves

The criteria are only trusted while they tell the two kinds of art apart. Rerun `compare` after any change
to a metric or band:

- **The reference passes:** at least 80% of RD's own sprites of each kind (the bands are 5th to 95th
  percentiles, so a few of RD's own always fall outside one). 2026-10-23: icons 91% (126 / 138), scenery
  84% (112 / 133), creatures 82% (53 / 65).
- **The flat look fails:** the code-drawn icons (`tools/item_art.py`) pass at most 10%. 2026-10-23: 4%
  (14 / 323), failing on `cluster_size` (99%), `flat` (90%) and `colour_density` (89%).

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

## Making a sprite in code

1. Describe it with `pixel_kit.Sprite`: shapes back to front, one `Material` per surface (base colour,
   `texture`, `gloss`; `profile="facet"` or flat planes with a `tone` for cut stone). Give it the detail RD
   would: seams, rivets, straps, folds, as their own shapes.
2. Render and score: `python3 tools/pixel_style.py check --kind icon <png>`.
3. Review by eye as above.
4. Keep the description in a tool (like `tools/prop_art.py` keeps its drawings), so a rerun rebuilds it.

## Where it stands (2026-10-23)

![As drawn now, the kit, and RD's own](pixel-style-demo.png)

- The kit's first six icons (`pixel_kit.py --demo`: amber, agate, the amethyst boots and helm, the amber
  amulet, the alloy shortsword) all pass; as drawn now by `item_art.py`, one of them does. Beside RD's they
  read as the same game but plainer: less designed material detail, and RD's metals have more contrast.
- **Next, in order:**
  1. Material presets with their own texture (plate metal with seams and a hard specular band; chain
     links; scales; woven cloth with folds; leather with stitching; wood grain; stone; fur), so detail
     comes from the material instead of each drawing.
  2. Tighten the loose bands with house rules once the kit meets them: `hue_shift` ≥ 3°,
     `light_top_left` ≥ 0, `shades_per_ramp` ≥ 4 (now set by RD's spread, which allows almost anything).
  3. Creatures and scenery: the tinted, broken outline (`render(outline="tinted")`) and eyes, then a
     redraw of a few monsters measured against RD's.
  4. Animation: walk cycles stay RD's for now (`sprite-acceptance.md`).

## Learned

- **2026-10-23:** RD's icons have almost no flat area (median `flat` 0) and small colour patches (median
  cluster 1.9 pixels): the texture is fine-grained, not blotchy. Code-drawn icons fail on exactly that.
- **2026-10-23:** Texture added before shrinking averages away; it has to be added at the sprite's own
  pixels, in 2-pixel clusters (per-pixel noise reads as salt-and-pepper).
- **2026-10-23:** One clean ramp per material looks plastic: RD's surfaces carry near-duplicate colours. A
  second ramp a few degrees round the wheel, picked in 2 × 2 patches, brought the kit up to RD's colour
  density.
- **2026-10-23:** Cut gems read best as explicit planes, each with its own tone (lit crown on the left, the
  pavilion stepping into shade to the right), not as a dome.
