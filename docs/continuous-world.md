# One continuous world (design)

Status: being built, 2026-10-14 (see "Where it stands" under Order of work). Playtesting: "Can't we just have one big map instead of this code that
tries to make it work when you cross a border? There shouldn't really be borders, it should be one
continuous big map."

## What it's like to play

- The continent is one place. You walk anywhere on it with no loading card and no line where one land
  ends: the ground, colours, music, weather and monsters change as you go, the way RuneScape's do.
- A land is an area of the map, not a scene: its name, music, palette, light, encounters, NPCs and
  townsfolk belong to the cells it owns (the regions `tools/world_layout.py` already paints).
- Places a quest keeps you out of keep their fence or rocks along the edge, as scenery that blocks
  you until the quest's done. Town walls stay: they're buildings, not borders.
- Caves stay maps of their own behind the loading card ("caves still have a loading screen").

## Why the lands-and-borders design keeps breaking

Every land is its own `WorldScene` with its own `WorldMap` in its own cells. To look like one world,
0.5.0 to 0.6.2 added a layer of code on top:
- building the lands next door in the background as you near them, and moving them into your scene;
- handing you over to the next scene when you cross (`takeOver`), seams and fences along every
  border, and pictures of lands not built yet lying past the border (`placeFarLands`);
- the travel card when you beat the build there, and now waiting at the line (0.6.2).

Most of the bugs reported in playtesting since 0.5.0 have come from that layer, not from the
lands. It also pays twice: the work of
building a land next door is thrown away when you outwalk it.

## Facts this design rests on

From a survey of the code on 2026-10-14:
- **Size.** The continent is 732 × 886 cells, about 307,000 of them land, across 27 lands; caves
  (Rat Cavern, Slime Cave, Mysterious Cave) are off it. A cell is 44 points, drawn as a 2:1 diamond.
  A phone shows about 26 cells across at zoom 1, up to about 55 along the long side in portrait.
- **Layout is whole-land work.** `WorldMap.init` uses one random stream per land (seeded by its id,
  order-dependent), and global searches:
  - hills and lakes are placed by a room map over the land and a shuffle of every cell;
  - lakes check, by flood fill, that nothing's cut off (and roll back if it is);
  - footpaths run from each trail's foot to the nearest road, however far;
  - crags are sealed by a flood fill from the hub.

  None of it can be generated a chunk at a time without changing every land's look. It can run once
  per land, though.
- **Building a scene changes walkability.** Scenery placed in `WorldScene.build` (props by
  `randomFreeCell`, decor, buildings, fairy rings, outcrops and more) calls `map.occupy`, so what you
  can walk on isn't final until the scene's built.
- **Paths use GameplayKit.** Walking uses a `GKGridGraph` per land: the biggest is about 26,500 nodes.
  One for the continent would be 460,000 to 650,000 nodes, likely hundreds of MB, with no bound on a
  search.
- **Some drawing is already chunk-shaped.** Hills and shores are drawn as 16 × 16-cell squares
  (`HillArt`), and their strips sort by absolute diagonal, so squares from anywhere sort together.
  Scenery is already attached and detached in 400-point chunks near the camera. Seam patch noise and
  border boulders are already hashed on world cells.
- **Depth is `-y`.** On the continent `y` reaches about ±25,000 points, which collides with the fixed
  layers: crag fog at 15k, sunbeams at 22k, particles at 30k, the ground at -100k.

## The design

### 1. Each land laid out once, into one continent store

`WorldMap.init` stays the generator, so every land looks as it does now. What's new:
- **A settle step.** Every decision that changes walkability moves out of `WorldScene.build` into the
  layout, as data: props, decor, buildings, lily pads, reeds, fairy rings, outcrops, seam props,
  signposts, NPC spots, locals' homes and critters' homes. Each becomes a `Placement` (what, which
  cell, its offset, sway and so on), drawn later by whichever chunk holds it. After this a land's
  layout is final: its ground, heights, placements and walkability.
- **The store (`World`).** Each land's layout is copied into it at its world origin (world.json
  `lands`), only the cells the land owns (Region codes 1 and 3). The store holds, chunk by chunk:
  - the land that owns each cell;
  - its ground and the tile it shows;
  - its height samples;
  - whether you can walk there;
  - the placements in it.
- **Compact, and the layouts let go.** A laid-out `WorldMap` is several MB with its GameplayKit graph
  and its hills' height grids, so the 27 can't all stay in memory. Each land is laid out, copied into
  the store and let go. What the store keeps:
  - a byte or two a cell for the land and the ground, and a bit for walking: about 1.4 MB for all
    650,000 cells;
  - height samples (4 a cell) only for chunks with hills, shore or terraces, as 16-bit floats: 33 KB a
    chunk, under 21 MB if every chunk had some. On disk, read in for the chunks round you;
  - the placements, and each hill's own drawing data (its heights, trails and outline), saved with
    its land and read in by the chunks it covers.
- **Seams and shore over the continent.** Seams are worked out by the store as distance to the land
  boundary, with the same patch noise. Shore heights come from one distance field to the sea and the
  lakes over the whole continent: 650,000 cells, a fraction of a second.
- **Laid out once per version.** Lands are laid out off the main thread, one at a time (`MapLayouts`,
  as now). The store is kept on disk per build of the game and its maps, as `WorldOverview`'s
  pictures are. On a version's first launch, your land and the ones round it are laid out before the
  game starts; the rest follow in the background, nearest first. The world map does this already for
  its pictures, so it isn't a new cost.

### 2. The world drawn in chunks (`ContinentScene`)

- **Chunk size.** A chunk is 32 × 32 cells: two `HillArt` squares a side, about 16 seconds' walk
  across.
- **Which are built.** The chunks within 2 of yours are built (5 × 5, 160 cells across, a long way
  past the screen's edge), ahead of you, a few milliseconds a frame as lands next door are now. Those
  more than 3 away are let go.
- **What a chunk holds:**
  - one tile map for its ground, and its share of the colour variation (noise on world cells, so it
    lines up across lands);
  - the hill and shore pictures for its four squares;
  - its sea;
  - the scenery its placements ask for.
- **Hills and shores.** A hill's height texture and shader become per square (that square's samples
  and a cell round them) rather than one per hill. Its strips already sort by absolute diagonal.
- **Colours.** Each cell is graded with the palette of the land that owns it. `ArtLibrary` keeps a
  graded set per land, as `foreignTile` does for a neighbour's ground now; the seam's patches still
  blend two lands' ground into each other.
- **Depth.** The fixed layers move out of `-y`'s range (to ±60,000 and beyond). At those sizes a
  32-bit float is still finer than a hundredth of a point, which the small depth nudges need.

**How step 2 is built (2026-10-14).** The chunks are drawn from the layouts and plans of the lands
near you, kept while you're near (`ContinentScene`), each cell with its own land's code:
- its tile from `GroundTiles` (makeGround's tile choice, moved out unchanged);
- its scenery from the land's plan (`LandPlanner`);
- its hills and shore from `HillArt`, for the squares in the chunk.

A land's points sit in the continent's at a fixed shift, its origin projected, as a land next door's
do today. So the border looks just as it does now, seams and all, with nothing left to stitch.

### 3. Walking, paths and heights from the store

- **Standing.** `canStand` reads the store's walkable bits, plus closed borders and barricades.
- **Tap to walk.** It uses an A* search of our own over the store, in a window round you (about
  128 × 128 cells), instead of a GameplayKit graph per land. Crowd strolls use the same.
- **Heights.** Hills, the shore and terraces come from the store's samples for the chunk under you.
  `Walker.settle` asks the store, not a land.

### 4. Lands as areas

- **The land you're in** is the one that owns your cell, with a few cells' grace at the line so it
  doesn't flicker as you walk along it.
- **When it changes:**
  - music cross-fades, and so do weather, sky and mood (the mood fade by borders is already there);
  - the encounters table, danger zone and battle music switch;
  - "You arrive at…", the chat channel and the minimap's title update;
  - `data.mapID` is set, so quests, bounties, titles, checkpoints, the Homeward Feather and the
    Monster Book carry on as they are.
- **Light.** A land's light on everyone in it (`Walker.light`) blends by where you stand.
- **People and animals.** A land's NPCs, locals, crowd, critters and ambience come in when one of its
  chunks is near and go when none is.

### 5. Saves

- **What's saved.** On the continent the save keeps your position in world points. `mapID` stays: it's
  the land you're in, worked out from that. In a cave, the cave and your place in it, as now.
- **Old saves.** An old save's `mapID` and `position` (points in that land's own box) become a world
  position, from world.json's `lands` origin. Friends' `Spot`s and checkpoints convert the same way.
- **Versioning.** The old fields stay readable, and the save's `version` goes to 3. Tests load a fixture
  from each version, and the repair that moves you off rock or sea to the nearest walkable cell stays.

### 6. Minimap and world map

- **Minimap.** It's drawn from the store round you, no longer a land's picture with its neighbours'
  laid round it. The coordinates on its plate become world cells.
- **World map.** It's the continent's picture straight from the store, with no layout of every land
  just to draw it.

### 7. What goes

- **Coordinator:** building lands next door, and handing over when you cross (`buildNextDoor`,
  `landsNear`, `waiting`, `cross`, `nextDoor`).
- **Scene:** `WorldScene.show`, `hide` and `takeOver`; `placeFarLands`; `canCross`, `wayOver` and
  `waitsBeforeStepping`; the build paces for lands next door.
- **Map:** `WorldMap`'s cells that are another land's (`.away`), and seams worked out per land toward
  each neighbour.
- **Borders:** `BorderArt`'s fences between open lands (the walls round places a quest closes stay),
  and the travel card between lands.

That's most of what 0.5.0 to 0.6.2 added to stitch lands together.

## Order of work

Each step is its own PR and leaves the game playable. The old engine stays the default until step 5.

**Where it stands (2026-10-14).** The PRs stack, each on the one before:
- #152, step 1: the store (`World`) and the plan made before drawing (`LandPlanner`).
- #153, step 2: `ContinentScene` drawing the ground, sea, hills and shore a chunk at a time
  (`GroundTiles`, `HillArt.painter`, `HillLooks`).
- #154, steps 3 and 4: walking (`World.path`, A* in a window), the land you're in and its banner,
  what each land sets down and its people (`LandStage`), talk, battles, duels, closed borders,
  each land's air, your party, the Homeward Feather and the minimap.
- #155, step 5: the switch. The continent is the game and caves keep their own scenes; the
  next-door and handover code is gone; 0.7.0.

Saves didn't need a new version: where you stand is still kept as the land you're in and a spot in
its own points, which the continent turns into its own (a land's shift) both ways.

**Playtesting on a phone (2026-10-15), 0.7.1 and 0.7.2.** Lessons from the first build on a phone:
- A land's air (sky, light, mood) fades as you cross into the next, each part fading itself. The
  sky's shade is multiplied onto the screen, and a multiplied colour faded by alpha goes dark, not
  faint: faded as one layer, the screen dimmed at every crossing. It eases toward white instead.
- A tile map made while the continent is off screen (a battle, a cave) never showed: a land that
  finished laying out during a fight left its ground missing, the sea showing through. Its ground
  waits till the continent is back on screen (`didMove`), and so do the hills', shore's and banks'.
- The coast's bank and foam (`WorldScene.bank`) are drawn per chunk after its shore's squares.
- The slope down to the sea, 14 points over four cells, barely showed by its light alone. Sunk ground
  darkens the lower it lies (`HillArt.wetShade`, in the hills' stepped shade), wet toward the water, and
  the sea is paler in bands along the coast (`ContinentScene.shallows`), palest at the waterline.

1. **Store and settle step, no visible change.** Lands are laid out into the store, and placement
   decisions move into the layout. Tests check that the store matches each land's layout cell for
   cell, that walkability doesn't change, and that two layouts of the same land agree.
2. **`ContinentScene` behind a debug flag (`continent`).** Ground, sea, hills, shore and scenery, chunk
   by chunk. CI screenshots it at the same spots as the old scenes, side by side.
3. **Playing in it, still behind the flag.**
   - walking, paths, heights and the camera;
   - the land you're in (music, light, weather, encounters);
   - NPCs, crowd and critters as you come near.

   With the banner that names the land you walk into.
4. **Saves, minimap, world map.** Saves go to version 3 with the conversion and its fixture tests; the
   minimap and the world map come from the store.
5. **Switch over.** The continent scene becomes the game; caves stay as they are. The border and
   next-door code goes. The tests that work out neighbours per land become tests of the store.
6. **Performance pass on a phone.** First-launch layout time, chunk build time and memory, in
   Instruments.

## Risks, and how we'll know

- **First launch.** It lays out up to 27 lands. CI prints each land's time already (⏱). Your land and
  its neighbours go first, the rest are laid out while you play, and the store's kept on disk after.
- **Memory.** A hill or shore square is a 512 × 512 picture, 1 MB. Twenty-five chunks of up to four
  squares each is about 100 MB of pictures at worst; tile maps are small. Check on a phone in step 6.
- **Determinism.** Each land keeps its own seeds, so it comes out the same every time. If it ever
  doesn't, a save could stand in rock: the repair moves you off it.
- **Nobody can run the app from a cloud session.** Every step lands behind a debug flag with CI
  screenshots first; TestFlight gets it at the switch-over.
- **Hand-placed content.** The `at` and `x`/`y` offsets in maps.json stay offsets from each land's
  middle: the tool, the checker and the content don't change.

## Decided (2026-10-14)

1. Places a quest keeps you out of keep fences or rocks along their edge, which block you until the
   quest's done.
2. Entering a land shows a banner with its name, fading in at the top of the screen, as well as the
   chat line.
3. No switch in Settings: steps 2 to 4 are behind a debug flag for CI's screenshots only, and step 5
   switches the game over once they look right.
