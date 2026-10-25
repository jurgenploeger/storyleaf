# Fairyland Online: how the original worked, and where we differ

What Fairyland Online (FO) actually did, collected so we stay faithful and "check before inventing new
systems" (CLAUDE.md). Each fact carries a confidence and its sources are listed at the end. When you verify
something new, add it here with its source. When we build or change a system, update its **Us** line.

- **H**: the official LagerNet wiki, or several sources agree.
- **M**: one fan guide or review.
- **?**: unverified. Our own README and PRs are public and turn up in web searches, so they never count as a
  source.

First collected on 2026-10-03 from search-engine snippets of the pages listed under Sources. The cloud
environment couldn't open the pages themselves, so a session that can should re-check anything marked M or ?.

## Names

**Us** (since 0.8.7, 2026-10-25): the game is called **Tales of Fabelia** for players (the App Store name and the
logo; the Home Screen, where a longer name is cut short, shows Fabelia), and the land is **Fabelia** in every
in-game line. It was Talewild from 0.8.1 to 0.8.6, Storyleaf from 0.3.50, and the code, project and repo still are
(renamed from Fairyland on 2026-10-22) until a follow-up renames them; only the bundle ID and the save files keep
"Fairyland" for good. The goddess Liora binds the world's tales
into one book, and its pages are the land. Names taken from FO were replaced with our own, and this file
keeps the FO names when it describes the original:

| FO name | Ours |
|---|---|
| Rainbow City, Bluebird, Goldburg (and Goldburg Lake) | Prismhaven, Larkspur, Ingothold (Ingothold Lake) |
| Northern Grassland, Slime Cave, Candy Mountain, Puppet Hill | Windswept Downs, Gooey Grotto, Gumdrop Peaks, Marionette Rise |
| Sleepy Town, Secret Plain, Hachoo Island, Rosen Lake | Dozywick, Hidden Steppe, Sneezle Sands (Sneezle Isle till 0.7.22: it's a sandy coast, not an island), Briarmere |
| Water Temple, Mysterious Cave, Valley of Fear, Moonglow | Tidewater Shrine, Whispering Hollow, Shiverdell, Moonwhisper |
| Shiria, Linns the Tailor, Hermit Will, Hamini the Wise, Thomas, Sophia | Liora, Nella the Tailor, Hermit Orrin, Ambrose the Wise, Jory, Rosalind |
| Diviner Guild, Journeyman Guild (the Warrior Guild stays) | Arcane Circle, Wildfolk Lodge |
| Idreus, Grunt of the Golden God, Lieutenant of the Silver Demon | Morvane, Gilded Brute (of the Gilded King), Silverfang Warden (of the Silver Wraith) |
| Puppet King, Wolf Leader, Rock Monster, Tide Dragon, Black Kong | Marionette King, Howlmaster, Craghulk, Wavecrest Dragon, Shadow Ape |
| Fantasy Ore, Dragon God (weapons) | Dreamstone, Wyrmking |
| Lambs In Distress, Fine Woolen Cloth, Some Love and Happiness, Animal's Home, Wishes of an Ugly Duck | The Wandering Flock, Soft as a Cloud, A Little Kindness, A Place to Belong, An Ugly Duckling's Wish |
| Sky-Ending, Dragon God, Red Cloud, Purple Star, Ghost, Blood Cypress, Armorbreaker, Ironcrusher staffs | Skyreach, Wyrmking, Crimson Mist, Violet Comet, Wraithwood, Dusk Cypress, Shellsplitter, Anvil |

Content ids (`rainbow_city`, `linns`, `dragon_god_staff`…) keep the old words, so saves carry over. Generic
names (Fire Bolt, Potion, Seal Stone), Meadowbrook, and public-domain fairy tales (Snow White, Thumbelina,
Oz) stay.

**Name check (2026-10-06):** the App Store already has *Story Leaf - English Readers*, a picture-book
reader in Education by Nobuaki Kuwabara. It comes up first when you search "Storyleaf". We keep Storyleaf as
one word, with a game subtitle (e.g. "Storyleaf: Cozy Pixel RPG"). Before launch: reserve the name in App
Store Connect, and search STORYLEAF / STORY LEAF on the USPTO and EUIPO registers. No app, game or trademark
turned up under these exact names, kept in case a rename is ever needed: Lanternvale, Talewood, Talehaven,
Pagewild, Inkmeadow, Dandelore, Briarbell, Plumleaf, Fayrewood, Lumelle, and Taleland (mockups of its icon and logo
are in the Figma file). Ruled out for clashing with an
existing game or mark: Fablemoor (FABLEMOON), Leafbound, Fairhollow, Wispwood, Thimblewood, Pixiehaven, Faeland,
Pixel Tales (an existing App Store app), and any "Tales of …" title (Bandai Namco's Tales series, which also has
Tales of the Heroes and Tales of Legendia).

**Name check (2026-10-25), the rename to Tales of Fabelia:** the user first took Avalune (below), then wanted
the name to end in -ia, like Neopets' *Tales of Dacardia* (World of Neopia, iOS and Android, 2024), which shows
another publisher already using "Tales of X-ia" beside Bandai Namco. Kept clear of -eria/-iria (Mysteria, FO's
own relaunch; Vesperia, Zestiria) and of names near an existing one. Screened by web search only.
- **Fabelia** (fuh-BEL-ee-uh; *Fabel* is "fable" in German, Dutch and Danish): chosen. Nothing found under the
  name; near only Fablies (a kids' app) and Fabelab (a kids' brand). It shares "-elia" with Bandai's unused
  Orfellia, and Portuguese and Spanish ears may faintly hear *favela*. Before launch: reserve Tales of Fabelia in
  App Store Connect and search it (and FABELIA) on the USPTO, EUIPO and J-PlatPat registers, classes 9 and 41.
- Also clear: Faelunia, Celandia, Talunia, Fernavia, Clovania (echoes Castlevania), Fayrelia, Bramblia.
- Ruled out: Avalunia (one letter from *Avalonia Online RPG* on the App Store, and the .NET framework), Lioria
  (*Tales of Liria*, and our goddess Liora), Elunia (WoW's Elune), Avandria (D&D's Avandra, Critical Role's
  Exandria), Emerlia (reads as Emilia), Lunavia (*Lunavania* on Steam).

**Name check (2026-10-25), the rename to Tales of Avalune** (replaced by Fabelia the same day): the user wanted "Tales of …" and a made-up,
pronounceable name for the world (their example: Emerit). Screened by web search only (USPTO, EUIPO, J-PlatPat and
the App Store weren't reachable from here). The pattern: Bandai Namco registers each of its titles as TALES OF + a
word (TALES OF VESPERIA, US Reg. 3607384) and files names ahead; no stand-alone TALES OF mark or action against
another "Tales of X" game turned up, and others ship under it (EA's *Tales of Kenzera: ZAU*, *Tales of the Shire*,
*Tales of Wind* on the App Store). So the world's name must not look like theirs (Phantasia, Symphonia, Vesperia,
Zestiria, Berseria, Luminaria...: no -ia, no Lumi-), and the logo isn't styled like theirs. Before launch: reserve
Tales of Avalune in App Store Connect and search it (and AVALUNE) on the USPTO, EUIPO and J-PlatPat registers,
classes 9 and 41. This reverses the "any Tales of … title" rule above, by the user's choice.
- **Avalune** (AV-a-loon, Avalon and French *lune*, the moon): chosen. Nothing found under the name.
- Also clear: Orlune, Faelora (a small fan-art species shares it), Emerra, Orlavel, Elmerin, Avelith.
- Ruled out: Emerit (reads as "emeritus"; in Italian *emerito* also means "utter", as in "an utter fool"),
  Elvarin (an indie RPG's continent), Aveloria and Eloria (-ia, crowded; Eloria begins with エロ in katakana),
  Lumera (too near *Tales of Luminaria*), Ameris (a US bank), Solvane (a solvent), Elandor (crowded, Tolkien-ish).

**Name check (2026-10-25), the rename to Talewild** (replaced by Avalune the same day): wanted a name whose `.app` domain and social handles are
free. This environment couldn't reach domain registries or social sites, so names were screened by web search
(no app, game, brand or channel under the name); the user confirmed talewild.app and the handles by hand.
Before launch: reserve Talewild in App Store Connect, and search TALEWILD on the USPTO and EUIPO registers.
- **Talewild**: chosen. Nothing found under the name.
- Also clear: Pagewild, Inkmeadow, Dandelore, Lanternvale, Briarbell, Talewick, Talebrook, Talemere,
  Pagemere, Inkwild, Pagebloom, Fablefern, Petalore, Talehaven, Leaflore.
- **Taleland is taken now** (it was clear on 2026-10-06): the iOS app *TaleLand - Talk to Tale*
  (apps.apple.com id6749757166), a Google Play *TaleLand* of AI fairy tales for children
  (com.talelandapp.taleland), and Roblox's *Taleland Railway* games (taleland-railway.fandom.com).
- Ruled out too: Talebloom (a *TaleBloom Kids* YouTube channel), Taleweave (Nexon's MMORPG *TalesWeaver*,
  and several Taleweaver products), Talewood (reads as the *Tanglewood* games), Taleshire (reads as *Tales
  of the Shire*), Fablewild (*Fablewood: Farm Adventure* on mobile, and Xbox's *Fable*), Lorewild (the
  *Wilderlore* books).

## Tales of Mysteria (2026)

FO is back under LagerNet as **Tales of Mysteria** (ToM). Its account sign-up page is on LagerNet's own
domain (fairyland.lagernet.com/register), its wiki is at talesofmysteria.com/wiki, and Mysteria is the
continent FO is set on. History:
- FO started in Taiwan in 2003.
- The English version ran from 2007 until LagerNet shut it down on 30 December 2019.
- A video from about May 2026, "Fairyland Online 2026 - How to getting reborn in game", shows it running again.

Not to be confused with **Fairyland Journey**, Lager's new 3D game on Steam (2026, turn-based, "Eudemons").

**The ToM wiki hasn't been read yet** (the domain was blocked in the cloud environment). Check these first:
- The `#character` section: the attribute list, points per level, each race's starting spread, the level cap,
  and the rebirth rules (level, cost, what you keep).
- Class list and advanced-class level.
- Pet modes, intimacy thresholds and capture items.
- Anything ToM changed from the 2007–2019 game.

## World

The continent of Mysteria (H):

| Kingdom | Race | Capital | Land |
|---|---|---|---|
| Faerore (north) | elves | Bluebird | forests and lakes |
| Lucca (centre) | humans | Rainbow City | rich plains |
| Graf | dwarves | Goldburg | hills and mines |

The rest of the world map is fairy-tale lands (H):
- 1001 Nights (Baghdad)
- King's New Clothes
- Little Mermaid (Port Pebbles)
- Thumbelina (Dreamland)
- Alice
- Beauty and the Beast (Sheep Horn Village)
- Wizard of Oz (Emerald City)
- Candy House (Grasha Village)
- Island (Cannibal Island)

A second "levels map" shades areas in 20-level bands (1–20, 21–40, …), used to pick the right capture
capsule (H). Mining spots include Ilium, Kars Mountain and Siwa Oasis (H).

**Us:** 31 maps and 4 towns (Meadowbrook, Prismhaven, Larkspur, Ingothold).
- Towns are planned from maps.json `town` (streets, a plaza, terraces, shops along the streets, street
  furniture) plus hand-placed `buildings`; scenery only grows inside a town's fence with a `within` radius.
  Since 0.3.65 the planner keeps each townsperson's spot and the cells just in front of it clear, so no
  house, lamp or tree hides them (before, every town's healer and shop stood inside or behind a house), and
  Larkspur, which had felt empty in playtesting (2026-10-07), has two rings of streets like the others.
- Raised ground (since 0.3.97, asked for in playtesting 2026-10-11): a town's terraces and hills out in the
  fields really stand up, and whoever walks up rises with them (`WorldMap.height(at:)`, `Walker.settle`), trees
  on top too. A terrace's top is drawn its height higher over a stone wall, with stairs up its front and side.
  Hills (`theme.hills`: count, size, height, bank tile) were blocks with a ramp in 0.3.97–0.3.99, which
  playtesting found too square. Since 0.4.1 they're heightfield hills, as isometric games draw terrain: a few
  ellipses melted together (`WorldMap.Hill`), rising on a smoothstep from foot to top, drawn as one picture of
  the map's own ground lit from the upper left and lifted by its heights in a small shader (`HillArt`; a warp
  grid crashed SpriteKit at that size). Since 0.4.7 the shader lights it too, by the sun of the hour (`Sun`). Since 0.4.3 the light is matte, as pixel art shades a hill: a few
  steps of 6% with a 4×4 ordered dither between them, sides away from the sun a few shades darker (leaning to
  the palette's shadow colour) and sides facing it only one lighter; the first smooth, brighter gradient
  read as gloss in playtesting. Never steeper than 13 points a cell halfway up (15 before 0.4.4), so ground
  facing away never leans out of sight and a tap finds one spot. Scenery grows on them like anywhere
  (since 0.4.3; tree shadows lie on the hill), and since 0.4.7 it's darker on the shaded side with the
  ground (`HillArt.sunlight`, playtesting 2026-10-12): by 60% of the ground's shade where the sun only grazes
  the slope (a tree stands up into the light, so it isn't as dark as the ground under it), and by all of it
  where the slope is steeper than the sun is high, in the hill's own shadow. Since 0.4.5 you can walk up them anywhere, straight up the
  side too (asked for in playtesting 2026-10-11; 0.4.1 to 0.4.4 kept the steep sides blocked but for the
  trail); a trail cut into the slope (a shadow above, a lip below) is the easy way up, kept clear a cell
  either side. Since 0.7.54 a tall mountain is the exception (playtesting 2026-10-20: "with tall mountains,
  only the roads can be walked to go up/down. With hills it's fine the way it is"): from a little way up its
  foot (`WorldMap.mountainFoot`) to its top (`mountainCrest`, 0.6 of the way up, where a summit's chest or
  boss stands), only its trail and a cell either side are walkable; its foothills, and its top once you're
  up, you walk anywhere. A mountain with no trail of its own (where none fitted) stays open all over. Since 0.4.5 it winds up round the side as a path would (asked for in playtesting 2026-10-11:
  not necessarily zig-zag, more like RuneScape's): from its foot on the side facing you, round one way,
  climbing evenly and far enough round that halfway up it climbs about 5 points a cell, bending gently in
  and out; a curve up a low hill, a sweep half round a mountain, and a single hairpin where it would go
  most of the way round. Each range has its own aim, way round, stretch and bends (`Hill.traceTrail`);
  0.4.1 to 0.4.4 zig-zagged in switchbacks. Since 0.7.7 not every range has one (playtesting 2026-10-15:
  hills don't always need a path winding up them): a mountain's range and each land's first do, about two
  in five of the rest (`WorldMap.trailShare`), so fewer footpaths lead off into the fields too. Since 0.4.5 it's drawn worn in (asked for in playtesting
  2026-10-11: more natural, not so smooth): stamped along its line every eighth of a cell, wandering a
  little either side and narrowing and widening as it goes, with a ragged edge two pixels at a time, a tuft
  of grass here and there, and the shadow and lip only where it's cut into a slope (`HillArt.stamps`,
  `wear`); 0.4.1 to 0.4.4 stroked it as a smooth band of even width. A `bank` tile shows through in ragged
  patches where they're steepest.
- Rocky or grassy by danger (ours, since 0.4.5, asked for in playtesting 2026-10-11: rocky mountains on
  dangerous maps, slopes on easy ones): `WorldMap.rockiness`, 0 to 1 from the middle of the map's
  encounter levels ((mid − 15) / 70; Sunny Meadow 0, Swan Lake 0.3, Crystal Mountain 0.9, Hidden Steppe
  1), or `theme.hills.rocky`. It sets how steep summits get halfway up (13 points a cell on grassy hills,
  18 on rocky ones, so gentle maps' hills spread wider for their height; 10 and 14 before 0.4.14, when
  playtesting 2026-10-12 found the hills, slopes and mountains hardly noticeable: since then a summit can also
  rise 0.85 of its narrower reach at that steepness, not 0.75, maps ask for 1.6 times the height (70 when not
  given) and mountains 1.25 times, at least 17 points a cell steep; the caves' walls kept 14), how far the bank shows down the
  slopes and how solid (from 0.2 up scree when the map names none), how deep the shade, and boulders on
  the steeper slopes from 0.3 up (the map's own boulder and rock props, 8% of steep cells at the rockiest).
- Ranges and mountains (ours, since 0.4.4, asked for in playtesting 2026-10-11: hills should stretch across
  the land and some rise to a mountain): each hill is a range, a chain of summits (`chain`, 2 to 4 by default)
  along a wandering line, each with its own height, blended so where two meet stands a little fuller (the
  fourth root of their heights' fourth powers) and their tops often join into a ridge you can walk along.
  `mountains` (count, height up to 300 since 0.4.14, 240 before) adds ranges with one summit far taller and wider
  than the rest, at least 17 points a cell steep whatever the land (13 before 0.4.14); a summit is only as tall as its width lets it be at that
  steepness, so a mountain is as tall as asked where there's room, else as tall as the roomiest place allows.
  Since 0.4.9 a mountain faces you (asked for in playtesting 2026-10-12: "some maps really need mountains
  taller", more like RuneScape's): only ground facing away has to stay as gentle as the view (it would fold
  over and hide itself past about 31 points a cell going up the screen), so its reach back climbs at that
  pace while its sides are 1.6 times shorter and its face toward you 2.4 times shorter, much steeper
  (`Hill.Lobe.front`), with a small top. Spurs fan down the face, sharp ridges with gullies between, unevenly
  spaced and sized, gone at the sides, the summit and the foot (`Lobe.Spurs`); with a smooth face, a mountain
  twice as tall still read as a gentle mound on a phone's screen, its base wider than the screen. Where a
  spur's far side would still fold, the samples are raised the least that keeps it in sight
  (`Hill.unfold`). Its range has bare layered rock from 40% of its height up, in deeper shade and brighter sun,
  like a cave's (`HillArt.Look.rockFrom`), and the minimap shows its heights lighter still. Heights since 0.4.9:
  Crystal Mountain 200 (two), Snow White Forest 170, Gumdrop Peaks 160 (grown to 140×100 for the room, its
  scenery half again as much), Marionette Rise 150; 88 to 112 before. 0.4.9 lost both of Crystal Mountain's: a
  range is kept in from the map's edge by a box round its summits, which still reached a mountain's full reach
  back toward you, so the spot its round was given near the map's lower or left edge was turned down on every
  try; since 0.4.10 a mountain's box is round its round (`shapeHill`).
- Hills on every land (since 0.4.10, asked for in playtesting 2026-10-12: every map should have slopes,
  hills or mountains): every map outside the towns and caves has `theme.hills`, dunes on Pineapple Shore, low
  rises in the swamps (28 to 30 points), rolling hills in the woods and round the lakes (40 to 44), and a
  mountain each in Shiverdell and Moonwhisper (160), on Emerald Road (140), in Big Bad Wolf's Lair and on
  Sneezle Sands (130). Towns have their terraces; a cave's tunnels (3 cells wide, chambers up to 5 across)
  have no room for a hill. Their bare slopes are the scree every rocky land shows: a first try gave
  Moonwhisper and Tidewater Shrine the caves' dark cobbles (`bank` tile_cave_rock), and since a range where a
  road leads into a cave takes its rock from the hills' bank, Moonwhisper's cave range went dark and
  cobbled too, which playtesting called strange (2026-10-12).
- Summits worth the climb (ours, since 0.4.10, asked for in playtesting 2026-10-12: more to explore, "maybe
  on top of the mountain is a boss or quest"): an NPC or a decoration can stand up on a summit
  (`NPCDef.summit`, `Decor.summit`: 0 the tallest of all the map's summits, `WorldMap.summits`; its `x` and
  `y` then step from that summit's top), since ranges land wherever there's room. Their spot and the ground
  in front stay clear of scenery once the hills are raised (`keepInView`). The Moon Rabbit Queen, the
  Howlmaster and the Marionette King moved up onto their mountains (the Emerald Dragon stays at the end of
  its road, Shiverdell's Great Wisp in its hollow), Pebble onto Crystal Mountain's second peak and Mister
  Frost onto Snow White Forest's, and a treasure chest stands at the top of Gumdrop Peaks, Shiverdell,
  Crystal Mountain, Snow White Forest, Sneezle Sands and Emerald Road, lanterns, crystals, lollipops or a
  statue beside it. Each holds a summit treasure: gear only that chest has (`Content.chestHolding`, like a
  quest treasure: no shop, monster, smith or adventurer has one, gold-framed, its card saying where it's
  from), around the map's level: Gumdrop Star Charm 24, Shiverpeak Gloves 42, Crystal Crown Pendant 80,
  Frostpeak Boots 84, Firepeak Ring 132, Emerald Crest Gauntlets 192, their art palette swaps of other gear's.
  Since 0.7.1 (ours, asked for in playtesting 2026-10-15: a chest should always have something, and
  something new a while after you've opened it) a chest fills again `refillHours` (1; 4 until 0.7.20,
  when playtesting found them "always empty") after you last
  opened it (rewards.json `chests`, `GameSession.openChest`): gold for its level (its own treasure's) and
  a piece of gear around that level (`equipmentDrop`) or a potion, ether, Seal Stone or Homeward Feather.
  It stands faded while it's empty and says to come back later (the hours left until 0.7.20); one opened
  before 0.7.1 is full.
  Since 0.4.5 ranges go where every summit has room round it (`clearance`: how far each cell is from a road,
  water, a building or another hill), picked at random among the places they fit; before, random spots
  tried 120 times often found nowhere on crowded maps (Gumdrop Peaks had no mountain). The first trail climbs from the ground in
  front; the mountain gets one of its own where there's room, never steeper than a comfortable walk and
  clear of the other. Too big
  to draw or sort as one picture, a range is drawn in squares of 16 cells, each shown in strips two cells
  deep up the screen, sorted just behind their back edge (`HillArt.strip(at:)`), so trees and walkers behind
  a summit are hidden by it; tree shadows are split where each of the two strips in front begins.
- Footpaths (ours, since 0.4.3, asked for in playtesting 2026-10-11: the trails as new ways to explore):
  from each trail that starts on the ground a cell-wide road winds across the fields to the nearest road or
  footpath, the cheapest way round what's in the way with a little seeded unevenness so it wanders
  (`WorldMap.layFootpaths`); over a hill only where it must, dearer the higher (a trail can start in a nook
  between two summits, which shut some footpaths in before 0.4.5). The minimap shows them like roads, the hills' trails, and the hills as raised
  ground in flat tones (since 0.4.5; the height gradient read as a staircase of shades at a pixel a cell):
  a lighter tint, the edge facing the light lit and the far edge shaded, a cell of shadow on the ground past
  it, and a mountain's upper slopes lighter still.
- Roadsides (ours, since 0.7.7, asked for in playtesting 2026-10-15: roads with fences, walls or other
  scenery along them; nothing here records what lined FO's roads): here and there along the edge of a
  road wider than a footpath, a picket fence, a low wall of field stones (`BorderArt.lowWallPicture`) or a
  row of one of the land's own props, a hedge of bushes, an avenue of trees or lanterns every few cells,
  on the cells beside it (`theme.roadside` in maps.json, `LandPlanner.planRoadsides`), about half of
  what could be. A row follows the edge, a cell out or in where the road shifts; a fence or a wall runs
  straight, and where the edge steps it ends and starts again a cell on, a gap in it (one that jogged
  with the edge zigzagged in the screenshots); along a road that runs corner to corner (all of Frog
  Swamp's) only a row fits, and reads as an avenue on screen. The first try lined straight edges only
  and found next to nothing on most lands (counted per land, 🚧 in the tests job's log), their roads
  wander; the second kept every kind straight three cells between steps and lined nothing on Frog
  Swamp. Each land has its own mix: walls on the downs and the rocky
  lands, palms on the shores, lanterns in the woods and the spooky lands, lollipops on Gumdrop Peaks,
  lamp posts on the roads into the cities (a prop with a count of 0 only lines the roads). In a town
  only out in its countryside, three cells off its wall; off the hills and the shore, and well in from the
  lands next door; a cell's kept clear at either end, so you can always step off the road.
- Lakes and rivers (ours, since 0.4.8, asked for in playtesting 2026-10-12: "more like RuneScape, with large
  lakes and interesting pathways and landscapes"); nothing here records whether FO's fields had them.
  Since 0.6.0 the rivers are the continent's (playtesting 2026-10-14: "there should still be rivers running
  through the lands"), painted with it by `tools/world_layout.py` from world.json `rivers`: each from a
  spring (a pool a little wider than the river) out to the sea, or where it has no way to the sea into a
  lake of its own (`lake`), through the turns of its `course`, meandering a little and widening as it
  goes; two run on over a border into the next land, as RuneScape's rivers run through its regions (the
  Snow White Forest into Swan Lake's lake, Sunny Meadow through Frog Swamp to the west coast), and the
  Smiling Forest, Briarmere and the Twilight Woods have one of their own. The tool keeps them clear of
  towns, the roads' crossings, the middles and everything set down by hand, crosses roads square on where a
  river's narrow and away from the sea, and checks nothing is cut off with no road over; the game lays them
  where they're painted (`WorldMap.layRivers`, region codes 3 and 4), and no fence stands across one where it
  runs over a border. 0.4.8 to 0.5.x drew one per map (`theme.river`: in over one edge and out over another,
  `carveRiver`), which stopped at the line wherever it ran into another land. Where one crosses a road, a
  bridge three lanes wide straight over it along whichever way the tiles run crosses it more squarely, the
  road on either bank bent to meet it (`bridge(over:along:)`, `meetRoad`). `theme.lakes` (count, size, islands) digs big lakes (`digLakes`): a wobbly round
  (three waves round its shore, squashed and turned), where there's room (`clearance`), cut back to keep two and
  a half cells off roads and anything else, so a road passing near runs along its shore; a footbridge two
  lanes wide out to an island in the middle of as many as asked, and on each a jetty out into it from the shore
  nearest a road, a footpath from both to the road (`layFootpaths`). Bridges are decks of planks drawn in code
  a pixel at a time in the ground's layer, with posts and rails standing along their sides, the near side
  sorted in front of you and the far side behind (`BridgeArt`). Since 0.4.14 (playtesting 2026-10-12: Sunny
  Meadow's bridge "is not fully connected to the land") each end lands on a bank: the water beside it is filled
  in two cells deep and a lane past either side of the deck (`WorldMap.bank`), and the deck reaches 0.6 of a
  cell onto it (was 0.35), its end posts on land. Before, where the shore ran right along a bridge's end, the
  water came up to its corner posts and it only touched the land. Nothing grows on a bridge or on the bank right
  beside its deck (since 0.4.13: playtesting 2026-10-12 found a fern standing on Smiling Forest's bridge, on a
  bank cell beside the deck that only the cells off its ends were kept clear of); reeds grow here and there along the shores,
  more lily pads on a lake than a pond, and the minimap shows the bridges. Lakes: Swan Lake, Ingothold Lake and Briarmere (each grown about 1.3× each way for room: 140×104,
  130×96, 130×104), Frog Swamp, Lotus Land and Sunny Meadow. A lake that should have an island and comes out
  without one (no room for it well out in the water, or no footbridge out to it) is dug again while a try
  could still be big enough for one (since 0.4.9; Lotus Land's lake had none in 0.4.8).
- Cave entrances (ours, since 0.4.5, asked for in playtesting 2026-10-11: a map's way into a cave should
  show from afar, a mountain or rock formation on that side). Since 0.7.8 (playtesting 2026-10-16: "the
  caves shouldn't be at the edge of the world maps, because it goes into the sea. It can be somewhere in
  the middle of the maps so it's just a gate to the cave maps. Maybe at the edge of a hill/mountain") a
  road into a cave (Shiverdell and Lotus Land into the Rat Cavern, Windswept Downs into Gooey Grotto,
  Moonwhisper and Emerald Road into Whispering Hollow) ends inland at a rocky hill (`WorldMap.raiseGate`),
  the mouth in a wall of rock at the foot of its face. `tools/world_layout.py` (`cave_gates`) finds it
  room 16 to 70 cells out from the hub toward the side the exit names, clear of the coast and the lands
  next door, the rivers, the other roads and everything set down by hand, and the cheapest way there,
  the road running straight at the mouth for its last 7 cells (world.json's road: `at` the cell in front
  of the mouth, `into` the way in). Its face is always turned toward you, so you walk north or east into
  it, the other way from the cave's own road back out (`gate_into`, since 0.7.13, playtesting 2026-10-16:
  "inside it should have the correct entrance/exit side depending on the location of the cave
  entrance"), so inside you come in on the side you walked in from and a cave's ways out leave by its
  south or west side; you arrive by the destination's own road back (`GameCoordinator.travel`). The Rat
  Cavern's two ways in both went east, so Shiverdell's mouth turned to be walked into north: a face turned away can't show (on the south and west edges 0.4.5 put a crag beside the road's end
  for that reason). Its main summit is a mountain turned to face you (since 0.7.13, playtesting
  2026-10-16: "the front of the cave is a bit too flat now and the land that goes up is a bit too
  small"; 0.7.8's stood 6 cells in, too small to reach its top, about 75 points): its face climbs 5
  cells from the mouth's foot, ridges down it as a mountain's have (`Hill.Lobe.spurs`), its back 12
  cells on and 11 either way along the face, 110 to 116 points high; smaller summits at its shoulders
  and one behind where they keep clear of what's there, drawn as the ranges below were, boulders strewn
  on its rock. Where a road passes close it stands narrower, down to 6 cells either way (since 0.7.17), and a road
  that comes from behind the mouth or beside it goes round the mountain's side, 18 cells along the face,
  and across in front of it to its straight last stretch (`WorldMap.aroundGate`; playtesting 2026-10-16:
  Lotus Land's road to the Rat Cavern ran up over its flank). The wall the mouth is in rises 60 points and falls back into the slopes behind (before
  0.7.13 it left a ledge at the mouth's height behind it, ending in a cliff), and its road shows only up
  to the mouth's foot (the cells it's carved on past it showed the land's ground over the doorway). Its rock is painted as it shows on the screen (`HillArt.Look.upright`): a hill's picture lies on the map and is lifted onto
  the screen, so up a sheer face each of its pixels stood several times as tall as on the flat and the rock
  streaked up the wall (playtesting 2026-10-16); each pixel's rock now comes from where it rises to, over
  all it covers there, its ledges by its own height. You come out two cells in front of
  it, and its signpost points up the road at it. The coasts the ranges needed (straight for 16 cells
  either side of the road, open sea past them) are the lands' own again. Before 0.7.8, where a road led
  into a cave a range of rocky hills rose along that side of the map (`WorldMap.raiseCrags`, still there
  for a land with no gate, a
  `Hill` with a `mouth`): summits of all sizes (65 to 125 points) every 3 to 10 cells along the edge,
  their feet 2 to 4 cells in, and one round the road whose side the cave's mouth is in, the road climbing
  to it about 40 to 55 points up. Their sides facing you climb faster, up to 2.8 times at the foot
  (`Hill.Lobe.steepSide`; ground facing you can be as steep as you like, ground facing away no steeper
  than the view, so the folds stay at about -0.51 against -0.65). On the north and east that's the side
  toward the map: a mountain face over the mouth, taller summits (110 to 150) behind it. On the south and
  west it's the far side: a ridge whose face you see beyond it, its back rising gently from the map to
  the mouth (5.5 cells of climb), with no taller row (it would stand in front of the ridge). It's drawn
  like the hills (`HillArt`, past the map's edge too): scree from a fifth of the way up (`Look.rockAbove`),
  its foot grassy, deeper shade (`Look.ambient` 0.25) and sunny slopes up to 30% brighter than the flat
  (`Look.brightest`; other hills go only 6%, or a ridge's sunlit side looked like the flat rock past it),
  ledges across its steep rock every 14 points up (`Look.strata`), stones strewn over it but not its
  mouth, and the ground past that edge rock as well. Mist thickens over it from 14 cells out (13 past a
  ridge) to all mist 8 further, at about the ground's height there, so no grass shows past it. The mouth
  is a doorway (`HillArt.doorway`) cut into a wall of rock facing you (`Hill.Wall`, part of the range's
  ground, so lit, shaded and ledged like the rest): it climbs 50 to 55 points in under a cell, then
  falls back 8 to 10 points a cell into the slopes behind, full height a cell past the doorway either
  side, then tapering away (quickly at the end toward you, slowly at the end away, which like the back
  can be no steeper than the view). On the north and east it's a cliff where the road meets the edge,
  at the foot of the mountain's face, level with the mouth all along. On the south and west the range's
  side toward the map faces away from you, where nothing steep can show, so it's a crag beside the
  road's end in the map, standing on the ground there, its face turned back along the edge toward you
  and the road; the road runs on along its foot, and you step into the mouth from the side, walking
  away from you like on the other edges (playtesting 2026-10-12: the doorway alone looked stuck on, and
  asked for the wall to be taller there). The doorway is upright on the screen like a door in an
  isometric wall, its sides straight up and its arched top leaning along the face, 30 points tall and
  14 more for each cell of its half-width (as wide as the road at the road's end, 2.6 cells beside
  it), black inside, a shadow round its edge and light on the rock over its top. It's painted into the
  ground, each point where the ground shows that far up the screen, so it stays upright however the
  face leans (0.4.6 painted it leaning with the slope, a skewed dark patch that playtesting called
  weird). You can walk its foot in the map; nothing grows there; and the only way out on that side is
  through the mouth (`WorldMap.exit(at:)`, since 0.4.7: before, any cell along that edge led into the
  cave, even on the mountain's foot). Since 0.4.10 its rock is a wall (playtesting 2026-10-12: you
  shouldn't get past the edge's mountains, but you could walk up onto the range and along the map's edge
  behind it): from 12 points up (`WorldMap.cragFoot`), and its last three rows along the edge, only its
  road walks on, up to the mouth; a dip between its summits shut in behind their rock is walled off too
  (`sealCrags`). Since 0.4.11 its rock's ledges (`Look.strata`, a mountain's too) show only on rock facing
  you: on the slopes turned away behind a cave's range the view squeezed each band into a thin dark line,
  which playtesting took for a crack in the ground (2026-10-12). You come out of the cave on the road in front of it. 0.4.5 drew
  it as the cave's own rock in flat-topped walls (`CaveWalls`) with a dark arch in the face, or on the
  south and west a cleft under an arch; playtesting (2026-10-11) asked for a slope instead of flat tops
  and walls, and for no grass past it. How FO showed its cave entrances isn't in any source reachable
  from a cloud session.
- Harbors and a ship (ours, since 0.7.9; playtesting 2026-10-16: "Add another magical/mystical map now, an
  island. To get to an island there should be a ship and harbor to get on"): Starfall Isle (levels 128 to
  148, after Sneezle Sands' 120 to 140) lies out at sea about 65 cells east of Sneezle Sands, a land of its
  own with no land next door: lilac and blossom trees, glowing crystals and fairy rings, a lake with an
  island, wisps and pegasi, its own song (`starfall`, a music box over harp and pad). A road with
  `"ship": true` (maps.json exit) ends at a harbor instead of a border: `tools/world_layout.py` (`harbors`)
  finds it a cell on the coast the exit's side faces with open sea straight out (14 cells, 3 to one side
  and 6 to the other), its own land straight behind for the road's last stretch, clear of the rivers,
  nearest the land it sails to (world.json's road: `at` the last cell of the coast, `pier` the way out).
  Its pier runs 6 cells out over the sea, 3 wide (`Region.Road.pierCells`), a deck of planks on posts 5
  points over the water (`WorldMap.pierHeight`, `LandStage.placeHarbors`); the world lets you walk on it
  though no land owns it (`World.pier`), with no monsters out there. A ship lies alongside, up the screen
  from it so you on the pier are in front (`tools/prop_art.py` draws it: one mast, a square sail with a
  gold star, lit stern windows, a gangplank down to the pier), rocking gently; walk out past its
  gangplank (`Region.Road.boarding`) and you sail, behind the card, to the other harbor, coming ashore by
  the foot of its pier. A captain stands by each (`at: "harbor"`). FO had an island zone too (Cannibal
  Island, above); this one isn't it.
- Glimmerbough (ours, since 0.7.22; playtesting 2026-10-16: "There should be something worthy to do on
  Starfall Isle, like new monsters, quests, armor/items to earn etc. There should be like a small mystical
  fairy tree village"): a fairy village round the fallen star's crystals at Starfall Isle's heart, where
  its road from the harbor ends. Its houses are hollow trees with round doors in lilac, rose and moonlit
  silver leaves, and Mother Lumen's great pale tree behind her (free palette swaps of `hollow_tree`,
  maps.json `buildings`; each has a Retro Diffusion `request` for a later upgrade of its own). Wisp
  lanterns, paper lanterns, fairy rings and moonflowers grow round it (props with `within`). Its fairy
  folk are elves drawn small (`scale` 0.8): Mother Lumen with three quests, Dewdrop the healer, Thistle's
  shop, and Pip the Lamplighter, a wisp, with two; Bramble the Gardener and Little Wren live there. Four
  new monsters live on the island (free palette swaps): Starmoths (and the rare Dawn Starmoth), Nebula
  Puffs and Crystal Quills. The quests: The Lanterns of Glimmerbough (6 Starlight Dust from the Starmoths,
  136), The Sleeping Moonflowers (12 Nebula Puffs, 140), The Crystal Garden (10 Crystal Quills, 140), A
  Lantern for the Stargazer (a Starfall Shard from a Crystal Quill joined to 3 Starlight Dust, 144) and The
  Fallen Star (148), the island's boss: the star that fell, awake and lonely on top of the island's
  mountain (level 150, the Starcatcher title; the island has a mountain since, like every land with a boss
  on a summit). Each quest gives a treasure (Glimmerwing Boots, the Starweave Robe,
  Starpetal Gauntlets, the Stargazer's Band, the Fallen Star Pendant, levels 136 to 148, drawn in
  `tools/item_art.py`), filling the gap between the Temple Bell Amulet (135) and the Wavecrest Scale Mail
  (155), and the Fallen Star drops a level-150 weapon for each class now and then (Starfall Staff, Blade,
  Axe and Whip; the smiths' lines stop at 105). Whether FO had a village like it isn't in any source
  reachable from a cloud session; it's ours.
- The Glimmerdeep's crystal (since 0.7.39; playtesting 2026-10-19: "The cave should have more crystal looking
  scenery"): its three levels have violet crystal walls and a glinting blue crystal floor (`tile_crystal_rock`,
  `tile_crystal_floor`), icy and amethyst spires instead of stalagmites and geodes instead of boulders, all drawn
  from the caves' own rock by `tools/crystal_art.py`, and its crystal clusters grown bigger.
- A map of the deep (ours, since 0.7.40; playtesting 2026-10-19: "Maybe the glimmerdeep caves you're not
  able to see the full map from the mini map, unless you completed a quest that gives you the ability to
  remember or have a map"): on a dark map the minimap and the cave's map show only where you've been, and
  the Glimmerdeep's three levels name a quest that charts them (maps.json `chart`, `GameSession.isCharted`):
  Pip the Lamplighter's A Map of the Deep (12 Floating Geodes, their light for ink, from level 152 after Into
  the Glimmerdeep). Once it's done, every level shows in full. Its reward says so.
- Cave depths (ours, since 0.7.38; playtesting 2026-10-18: "In caves, you should be able to go deeper in
  a cave, so a deeper level, similar to runescape", then "Only the new land should have 2 deeper cave levels
  with the drake in the deepest cave level"): the Glimmerdeep goes two levels down (maps.json `depth` 1 and
  2: the Glimmerdeep Depths, 160 to 172, with a treasure chest of a Heart Seal, and the Heart of the
  Glimmerdeep, 168 to 180, where the Prism Drake sleeps now, level 180, its quest from 172). Each level down
  is a step stronger than the one over it, so going deeper pays (playtesting 2026-10-20: "make sure the
  monsters go progressively stronger in the caves, so it's worth it to go deeper to fight stronger monsters
  for more xp"): a fight's EXP grows with its monsters' level, about 30% more a monster at the bottom
  than at the top (150 to 162), and the drake is the strongest thing in the cave. Each level is
  reached only by a ladder down into a pit in the floor and left only by a knotted rope back up through a
  hole in the roof (`cave_rope`, since 0.7.51; playtesting 2026-10-20: "instead of a staircase to go up in
  the caves, it should be a rope going up"; stone stairs before), as RuneScape's dungeons are by their ladders (NPCs with role `stairs` and `to`, tapped or Talked to like a
  chest; you come out in front of the stairs that lead back, `WorldMap.stairsArrival`), and each is smaller
  and darker than the one over it. The minimap marks the ladders and stairs with a grey arrow down or up.
  Whether FO's caves had floors under them isn't in any source reachable from a cloud session.
- The Glimmerdeep (ours, since 0.7.26; playtesting 2026-10-17: "Add a crystal cave to the starfall isle you
  can explore (a new map) with new boss"): a crystal cave under Starfall Isle, its road leaving Glimmerbough
  south to a mouth in a rocky hill (world.json `roads`, the cave's own exit west, so you come in on its
  west side). Inside, crystals in cyan, violet, gold and rose glow in the dark (props with `glow`, the
  cave's palette colder and bluer than Gooey Grotto's), with three underground pools, side chambers off
  its winding galleries and Crystal-Singer Opaline by the crossing. Three new monsters live there (free
  palette swaps): Prism Crabs, Floating Geodes and Crystal Serpents, with the island's Crystal Quills and
  Nebula Puffs (levels 150 to 162). At its bottom (since 0.7.38 two levels down, see Cave depths) sleeps the Prism Drake (level 160, a palette swap of
  the black lizard drawn 1.7 times its size), which drank the starlight the Fallen Star left behind. The
  quests: Into the Glimmerdeep (10 Prism Crabs, Pip, 150), Lanterns That Never Go Out (5 Glimmerstone from
  Floating Geodes, Mother Lumen, 154) and The Prism Drake (158), which gives Prismscale Mail (158), plate
  between the Wavecrest Scale Mail (155) and the Emerald Dragon Mail (190). Ours.
- Everyone starts in Meadowbrook, and all three guild masters are there.
- Travel: you walk between maps; your checkpoint is the last town you entered (since 0.3.54; before, the
  last map, which could leave you fainting at the edge of a zone too hard for you, over and over). You wake
  up there after fainting. Mages learn Bridge of Light (Lv 20, 10 MP) to go back to it, and since 0.3.53
  anyone can buy a Homeward Feather (50 gold, every town shop) that does the same once; since 0.4.7 both
  let you choose any town you've been to instead (`TravelPicker`, the checkpoint first; playtesting
  2026-10-12), going straight there when there's only one, nothing spent until you pick; since 0.3.54 won
  fights drop one now and then (8%), and a beaten boss always does. Arriving by feather, you float down
  in a column of light as feathers spiral down round you; leaving is the same played backward
  (`WorldScene.Feather`, one timeline for both, since 0.4.7: playtesting 2026-10-12 asked for them to match). How FO itself moved players between towns isn't in any source reachable
  from a cloud session (2026-10-05); this is our own design.
- Waystones (ours, since 0.7.63; playtesting 2026-10-22: "There should be quests that you can eventually
  teleport to other keypoints in lands"): seven standing stones out in wild lands (NPC role `waystone`,
  maps.json), one each in the Twilight Woods, Shiverdell, Genie Desert, Dozywick, the Hidden Steppe,
  Briarmere and the Emerald Road (levels 22 to 186). Each sleeps, faded, till a quest from someone in its
  land is done (its `quest`: beat 8 or 10 of a local monster), then it's a stop for Bridge of Light and
  Homeward Feathers as the towns are (`GameSession.travelDestinations`, after the towns), and touching it
  takes you to any of them free (`GameCoordinator.Travel.waystone`). You arrive in front of it
  (`WorldMap.waystoneArrival`). RuneScape's lodestones and fairy rings are the idea; FO had nothing like it
  that we know of. The stone's sprite is drawn in code (`tools/prop_art.py waystone`).
- One continent (ours, since 0.5.0, asked for in playtesting 2026-10-13: "instead of the maps being
  separated and there being loading screens whenever you go to a new land, one big continuous landscape,
  the changes in colour and area natural and subtle, similar to RuneScape; areas that are locked or
  blocked should have fences or rocks; caves still have a loading screen"). FO itself was separate maps
  you walked between (above), so this is a deliberate departure, like the RuneScape-style trails and
  minimap icons. RuneScape isn't one loaded map either: it keeps a 104x104-tile area round you and reloads
  as you near its edge; we do the same per land.
  - Shapes (since 0.6.0, playtesting 2026-10-14: "the lands should have more interesting shapes, not
    just squares that have the edges done. Look at the map shape of runescape and make something
    resembling it ... up north can be more cold with snow and ice, and further south can be the warmer
    landscapes like the desert"): every land is a shape of its own (`Region`), painted by
    `tools/world_layout.py` from world.json's `design`: each land's middle and lobes round it (ellipses),
    the lands pushing against each other where they meet, the whole continent bent by noise so coasts and
    borders wander; scaled so each comes out about as big as its map was. Since then (playtesting
    2026-10-14: "the shape of the whole maps needs to be one uniform shape, now it still looks like parts
    go inward or outward at the edges with the map environments") it's one landmass: the lands' shapes
    blurred together and cut again a little raggedly (`BODY_BLUR`), so the gaps and notches where two
    lands met fill in, no sea lies inland, and one coast runs on past every border; only Emerald Road
    stands off it, an island, as it's reached through a cave, and since 0.7.9 Starfall Isle, out at sea,
    reached by ship (below). And (the same playtest: "the towns should
    have lands around them, not be a square in the world") a town is a land like any other, its walled
    square (maps.json `town.size`) in the middle of its own countryside, its roads out through its gates
    and on across the fields; a city (Prismhaven, Ingothold, `town.walls`) is walled in stone with
    towers, a village keeps its picket fence (`TownFence`). Since 0.7.7 its countryside is as full of
    scenery as the lands round it (playtesting 2026-10-15: "there should be more scenery around the
    cities"): 0.6.0 to 0.7.6 kept the few props its old border ring had, 2 to 4 that block a hundred
    cells against 10 to 35 out in the fields; Ingothold's are the desert's and the mines', rocks,
    cacti and dry bushes, on desert sand (its countryside was gravel, its roads' own ground, so they
    didn't show). A land's map is the box round its shape; the boxes overlap where the shapes fit into each
    other, and each land lays out and draws only its own cells (the rest of its box is the sea's, or the
    land next door's, `Ground.away`). Where a road crosses, the border runs straight for 8 cells either
    side and the painting gives the crossing and the road's turns through the middle of the land; a road
    into a cave ends inland at its hill (since 0.7.8; before, it left by a straight stretch of coast with
    open sea past it for the cave's mountains). The
    tool checks everything set down by hand stands on its land and every road keeps 3 cells off its edge.
    The layout follows the climate, roughly RuneScape's Gielinor turned on its side: snow and ice in the
    north (Snow White Forest, Moonwhisper, Briarmere, Tidewater Shrine, like Fremennik and Trollheim),
    desert in the south-east (Ingothold, Genie Desert, Hidden Steppe, like the Kharidian Desert) with
    Sneezle Sands on a sand spit and Pineapple Shore's beaches on the south coast (Karamja's place), the dark
    woods to the east (Morytania's), Gumdrop Peaks and the wolves' lair to the west, Meadowbrook's fields in
    the middle. Since 0.7.21 each land says which (maps.json `climate`: cold for the four northern lands, hot for the desert and the south coast; none for the mild lands between, and caves), frost and snow monsters live only where it's cold (`check_content.py`; playtesting 2026-10-16 found a frost-maned lion on the Hidden Steppe and frost puffs on Pineapple Shore's beach), and the adventurers about walk companions at home in a land of the same climate where one fits (`Crowd.companion`). Changing the order moved some roads: Pineapple Shore is reached from
    Meadowbrook now (still behind "Jelly Trouble"), the Smiling Forest from Gumdrop Peaks and Prismhaven,
    and Moonwhisper from the Snow White Forest, opened by beating the Big Bad Wolf
    ("Who's Afraid of the Big Bad Wolf?", which fits its levels, 82, better than "Crystal Hearts", 71,
    did); Briarmere and Tidewater Shrine lie past Moonwhisper, and Crystal Mountain stays south of
    Ingothold, a warm rocky peak now (no snow). 0.5.x laid rectangles side by side (an integer program)
    and carved coasts into them (`Coast`): "squares with the edges done".
  - The lands next door (`Continent.neighbours`) are laid out off the main thread and built a few
    milliseconds a frame (`WorldScene.Pace.background`) once you're within 48 cells of their border, then
    shown past it (their layer moved into the scene you're in, `WorldScene.show(_:as:)`); let go past 64.
    Until then (since 0.5.2, playtesting 2026-10-13: "the maps are broken and still not one big
    continuous map", from a screenshot of nothing past the border at night) every land within 64 cells
    lies flat on the ground as its world map picture (`WorldScene.placeFarLands`), so there's never a
    gap. Since 0.5.3 (playtesting 2026-10-14, the same border still empty and no way over it), that
    picture doesn't wait its turn: the lands you share a border with are drawn first
    (`WorldOverview.prepare(first:)`), one next door hands its own over as soon as it's laid out, and
    a land with none yet lies there in its ground's colour, on the minimap too (it showed open sea).
    Tapping past a border walks you over even before that land is built (it only worked once it was
    shown; the stick always did). The tests print a background build's longest holds and where they
    are (`WorldScene.longestSlices`): a range of hills held the frame for seconds in a debug build and
    SpriteKit takes a fifth of a millisecond over each tile, so hills are drawn a piece at a time
    (`HillArt.sprites`' `pause`) and tiles set 32 at a time. Movement goes by the time that's passed up
    to an eighth of a second a frame (it was a twentieth), so a frame the background build makes late
    doesn't slow your walking ("walking around feels slower").
    Walking over hands the scene over with no card (`takeOver`): the hero, companion, party and camera
    carry on where they were, the land you left shows next door in its turn. Not built yet when you step
    over: behind the card as before, where you crossed.
  - Borders (since 0.5.1, playtesting 2026-10-13: "with lands I should be able to walk freely from one
    to the other, not just one opening"): you walk over anywhere along the border two lands share, once
    you can. A road a quest opens crosses a fence through a stone arch, barred and signed "Closed" until
    the quest is done (the quest from either side's exit), then the whole fence comes down. Where no road
    crosses, a fence (boulders where either land's ground is sand, snow, scree or desert) stands until
    the roads you can take join the two lands some other way (`Continent.joined`), then comes down too:
    opening those borders outright would have let you round quests (Twilight Woods into Frog Swamp
    without "new_friend", Valley of Fear into Genie Desert without "dragon_hangover"; the test
    `openBordersNeverSkipAQuest` holds it). 0.5.0 opened only a road's border and kept the rest walled.
    `BorderArt` draws them the same from both lands, on the line between them, a piece along each side
    of a cell where the two meet, so they wind as the border does (since 0.6.0). 0.5.x stood a stone
    city wall with towers round each town on its border (playtesting 2026-10-13: "if a city has blocked
    path, there should be a city wall"); since 0.6.0 a city's wall stands round its own square instead,
    out in its countryside, and the borders round a town are fenced and opened as any are.
  - Seams (since 0.5.2; playtesting 2026-10-13: "the different lands still look too squared, it needs
    to blend together more naturally and in different shapes", then "you shouldn't see a hard line,
    but the environment should change into the other naturally, so the ground slowly shows more of
    the other area, same for the scenery"): two lands give way to each other across a band 14 cells
    either side of their border, measured from it as it winds (`Seam`: how far each cell is from the
    other land, so both lands draw the same band; a test checks the cells). 0.5.x measured from a
    middle line wandering about a straight border. Across it the other land's ground comes in
    patches, by patchy noise over the continent against the other land's share (none 14 cells in,
    half on the line, all 14 past),
    graded with that land's palette and drawn as soft rounded blobs, as an accent's patches are
    (`ArtLibrary.GroundLayer.from`). The other land's scenery grows on its patches as thickly as it
    grows there, this land's on its own (`placeSeamProps`), the land's accent keeps out of the band,
    and the minimap and the world map show the patches (`WorldMap.foreign`). Only drawn: whose cells
    they are still stops at the border. In a town only out in its countryside, not inside its wall. 0.5.1 drew
    one winding line instead, each side all one land's: a hard edge, if a curved one.
    A wash of the two lands' colours, mixed as their ground is, lies over the band, strongest on the
    border, so the patches' colours run into each other (`WorldScene.blendBand`, as RuneScape
    blends its ground's colours; 0.5.0's first draft scattered the next land's own ground tiles one
    by one, which read as a checkerboard where the two differ); the tint, haze, sun flare,
    particles and weather fade out over the last 10 cells toward a border you can cross and in again past it
    (`mood`), and the light and cloud shade carry on across.
  - The sea (playtesting 2026-10-13: "everything outside of the land should be sea"): all round the
    lands and in the gaps between them, the same blue whichever land you're in (`raw:tile_water`, not
    graded by a palette), a river that reaches a coast running out into it, and haze thickening with
    distance from any land (each cell drawn by the nearest land only, `Region.drawsSea`). Till 0.7.8 a
    cave's range rose out of it on rock. 0.5.0's first draft had wilds there (a thicket along the edge, then mist).
  - Coasts (since 0.5.1, playtesting 2026-10-13: "the maps shouldn't be squares any more but natural
    landscape areas with natural curves; the sea part should be lower than the land; I shouldn't be able to
    walk here", from a screenshot of the hero out on the sea): since 0.6.0 the coast is the land's shape
    itself (above); 0.5.x let the sea in over each rectangle's coast round whatever stood on the land. It
    lies `WorldMap.seaDrop` (14 points) below the land, the land's edge cut clear along it (`ArtLibrary`
    style `cut`), foam at its foot. Since 0.6.0 the land slopes down to it (playtesting 2026-10-14: "when
    there is a sea or lake there needs to be a slope"): the shore is ground sunk below the land round it
    (`WorldMap.shore`), the cell beside the water at the water's level and rising evenly over 4 cells to
    the land's own, drawn as a hill is but sunk and lit by how it slopes (`HillArt`, `Hill.sunken`), so you
    walk down to the water. The lakes sink 9 points the same way, over 3 cells, their bridges and lily pads
    with them. Never under a hill (it rises to meet one). Before, the land stopped at a bank of earth
    over the sea (its outline again in layers darkening toward the water, `bank`, kept for a map with no
    shore). `tools/world_layout.py --check --preview out.png` draws the continent. The hero had walked out onto the sea by tapping it: a tap past the edge clamped to the edge
    cell, which counted as the spot itself (`WorldMap.path`).
  - The world map (since 0.5.1, playtesting 2026-10-13: "the mini map should also open the bigger world
    map, similar to RuneScape"): tapping the minimap opens the continent as it really looks, every land's
    minimap laid where it lies (`WorldAtlas`, `WorldOverview`: drawn in the background the first time and
    kept on disk), turned like the game, dragged and pinched like RuneScape's. Places you haven't been to
    are faded and named "???", a dark land shows only where you've seen, a quest's shut gate shows its
    lock, caves show where they open. It was a diagram of badges on the roads between places before.
- Fairy-tale fields echo the lands: Genie Desert, Lotus Land (with Thumbelina), Gumdrop Peaks, Snow White
  Forest, Emerald Road.
- Gumdrop Peaks is our nod to the Candy House land (Hansel and Gretel's Grasha Village): a sugar path,
  chocolate ponds, lollipops, cotton-candy trees and presents (palette swaps), and candy canes, gumdrops,
  cupcakes and gingerbread houses. Other fields nod to their lands too: flying carpets and genie lamps in
  the Genie Desert (1001 Nights), poppy fields on Emerald Road (Wizard of Oz), giant ladybugs in Lotus Land
  (Thumbelina), and apples in the Snow White Forest.
- Each land has homes of its own (ours, since 0.7.65; asked for 2026-10-22: the same cottages stood in every
  land): adobe houses and tents in the desert lands, and Ingothold's two kinds of adobe house (with stone huts for its miners), beach huts
  and fisher shacks on the coasts, snowy cabins, an igloo and the dwarves' cottages in the north, stilt huts and
  lily cottages in the swamps, crooked houses and witch huts in the dark lands, a puppet theatre on Marionette
  Rise, a moon pagoda, a water shrine, a candy cottage, forest lodges and Dozywick's nightcap cottages
  (Retro Diffusion, maps.json `buildings`). The meadows and the green towns keep their cottages.
- The animals about the maps (bunnies, frogs, crabs, birds, gulls, bats, and since 0.3.58 songbirds that fly off
  when you come close, chicks, squirrels, lizards and mice; crows, spiders, rats, scorpions and will-o'-wisps
  on the harder, darker maps) and particles such as lanterns,
  bubbles and Z's are our own whimsy. No source we could reach describes ambient animals in Fairyland Online.
- The light and depth on the maps (pools of light, sunbeams, the sun's flare, haze, and the soft blur at the
  top and bottom of the screen) are ours too, from each map's `ambience` (`Lighting`, `DepthOfField`). Big
  blurred trees drifting in front of the camera were tried on nine maps (2026-09-30) and taken out in 0.3.65:
  in playtesting (2026-10-07) one sat in the middle of the screen and read as a smudge, since everything else
  is crisp pixel art. The checker now rejects a `foreground` key.
- None of the other towns exist yet: Baghdad, Port Pebbles, Dreamland, Sheep Horn Village, Emerald City,
  Grasha Village.

## Races

Human, Elf and Dwarf (H). Each race has its own spread of the six attributes, which suits it to one of the
three guilds (M): humans are balanced, elves lean to magic and dwarves to attack.

**Us:** the same three. Each has base HP/MP/ATK/DEF/MAG/SPD (`content/classes.json`) and no home capital.

**Genders and hairstyles (our decision, 2026-10-05, replacing 2026-10-04's):**
- Two genders, male and female, each with its own walk sheet per race. A third, "Other", was dropped at the
  playtester's request; its sheets (`*_other_walk`) stay only as the source of the Bob, Shoulder and Messy styles.
- Every hairstyle fits every race and gender, so a girl can wear a boy's hair and the other way round
  (`tools/hero_layers.py` fits each style to every head).
- A gender's own hair is the one it starts with and comes first in the picker: Ponytail (human female), Swept
  (elf male), Braids (dwarf female). The race's default sheet starts with the race's `hair`.
- This reverses 2026-10-04's rule that each gender sheet's hair stayed with that sheet.
- Since 0.7.60 a barber in every town (NPC role `barber`, playtesting 2026-10-21: "You should be able to
  change your hair style and color somewhere in the game, at a barber in a town") changes the hairstyle and
  hair colour for their `price` (1000 gold); gender, skin and outfit stay as the hero was made. Our own idea:
  nothing in the sources says Fairyland Online had one.

## Attributes

- **Six attributes: STR, CON, DEX, INT, LUK, CHA (H).** Monsters have them too, e.g. the Puppet (wood) has
  Str 15, Con 15, Dex 16, Int 16, Luk 13, Cha 15.
- **Attribute points (AP) to spend at every level-up (M).** One guild guide's early advice: all into CON up to
  level 10. A blademan guide aims for about 60 CON and 30 INT, then balances STR and DEX.
- **What they do (H, from the pet fusion rules below):** STR adds weapon damage, DEX accuracy, CON defence,
  LUK evasion, INT magic power. CHA's effect isn't documented yet.
- **DEX also sets turn speed (M).** A mage guide says mages need 250+ DEX to act before certain monsters.
- **Skill speed (H).** Every skill has a speed order ("Skill Penalty Priority"): orders 1 to 10 add DEX for
  that turn, 11 is neutral, and 12 to 21 subtract more and more. Warrior's Charge is order 1.

**Us:** no attributes and no points.
- HP/MP/ATK/DEF/MAG/SPD = race base + class growth × (level − 1) + gear (`GameSession.swift`).
- HP and MP carry over from fight to fight (our decision, 2026-10-05, at the playtester's request), except
  that a new level fills them to the new maximums, the hero's and the companion's (asked for the same day,
  0.3.52). Otherwise potions, healing skills and the healer heal.
  Friends in your party carry theirs over too (`Adventurer.hp`/`mp`); one who faints wakes at half.
- Frost Breath freezes: whoever it catches loses their next turn (`Ailment.freeze`, our decision, 2026-10-05).
- Six equipment slots: weapon, armour, gloves, necklace, boots and accessory (rings, charms, bands). Gloves,
  necklace and boots are ours (2026-10-09, asked for in playtesting); FO's own slots aren't in any source
  reachable from a cloud session (see Unverified). Gloves add attack, necklaces magic, MP and HP, boots speed and
  defence, each in five tiers from level 1 to 92 for every class. Speed Boots moved from accessory to boots, and
  saves that wore them as an accessory move them on load (`GameSession.moveGearToItsSlot`). The Character
  screen shows the hero in the middle with the slots around them like a paper doll.
- Gloves, boots and necklaces show on the hero (ours, since 0.7.28, playtesting 2026-10-17: "Gauntlets, boots
  and necklaces should also change the appearance"), each in its `color` (a necklace's chain its `accent`), at
  the brightness of what was there (`GearOverlay.trinkets`): the hands are the skin below the chin on the
  plain body (its biggest patch of skin is the face; the last three rows of each other patch are a hand), the
  boots its brown near the feet, the necklace a V of chain under the chin with the stone hanging from it, seen
  from the front. Armour with a walk sheet of its own is drawn on its race's poses, so they land on its
  gauntlets and greaves too. Other adventurers wear gloves, boots and necklaces for their level and class, a
  third of them without each (`GameSession.trinkets(for:)`). The speed boots' sky blue is now their colour.
  `tools/gear_preview.py --trinkets` previews them on every body.
- Armour tiers like RuneScape's metals (ours, since 0.7.29, playtesting 2026-10-17: "There should be all kinds
  of colors for different armor levels, just like in runescape"): nine tiers, each a level and a colour of its
  own, so the colour tells the level: Copper (10), Silver (25), Onyx (45), Sapphire (60), Jade (80), Aquamarine
  (100), Ruby (125), Amethyst (150) and Topaz (175), under the Goldleaf gear at 200 (items.json `tier`). Each is
  a full set: a fighter's plate (the iron plate's own sheet in the tier's colour, `tint`), a mage's robe with
  runes, a tamer's hooded hide cloak lined with fur, and gauntlets and boots for anyone, which show on the hero
  in the same colour. So a fighter, a mage and a tamer of the same level wear the same colour in the cut of their
  guild. Meadowbrook sells Copper, Prismhaven Silver and Onyx, Ingothold Sapphire, Jade and Aquamarine; Ruby,
  Amethyst and Topaz only drop from monsters, like RuneScape's rune and dragon armour. Their stats sit a little
  under the quest treasures of the same level. Other adventurers wear them too (`GameSession.armor(for:)` picks
  their guild's best), so the crowd shows every colour. `check_content.py` insists every tier is a full set of
  one level and one colour, each tier's colour its own; tools/item_art.py draws the icons from `color`.
- Festive seasons and hats, like RuneScape's holiday events (ours, since 0.7.30, playtesting 2026-10-17: "Also
  add festive items like party, halloween, Christmas and Easter"): Halloween (October 15 to November 7),
  Christmas (December 1 to 30), the New Year's party (December 31 to January 7) and Easter (a week either side
  of Easter Sunday), in rewards.json `seasons`. The first daily gift of a season brings one of its hats (one you
  haven't got) with a greeting; till it ends, won fights leave its treats (pumpkin pie, gingerbread, cake,
  chocolate eggs: HP and MP) and, once in a long while, another of its hats; and about half the crowd wears
  them. The hats go in a slot of their own (type `head`), with no stats, like RuneScape's: paper party crowns in
  six colours (RuneScape's party hats), three Halloween masks, a Santa hat and bunny ears. GearOverlay draws
  them on the head (`hat`: crown, santa, ears or mask), measured on the plain body, in place of a helmet or
  hood; `tools/gear_preview.py --hats` previews them. No shop, quest or monster has them out of season.
- Armour with a walk sheet of its own (iron plate, dragon mail, the ranger and snow cloaks) keeps the hero's
  hair (since 0.7.28, playtesting 2026-10-17: "The armors and colours should be more distinct for every
  gender, race and fighter type"): it's drawn over their hairstyle from a fifth of the way down the head
  (`nape_<style>_<body>`, tools/hero_layers.py), dyed their colour, so long hair, a ponytail or braids show
  below the helmet or hood and a woman in plate isn't the same figure as a man.
- Better gear (ours, since 0.4.0, asked for in playtesting 2026-10-11): a slot whose bag holds something better
  that the hero can put on now gets a gold arrow, as does the piece in the Bag and the slot's list. Better means
  worth more to the hero's class (`GameSession.gearValue`): each bonus weighted by the class's growth in that
  stat next to a novice's, and by how big that stat's numbers run. The Bag and the slot's list have search,
  sort (best for you, level, name, price, how many) and filters (the Bag's kinds; only what you can wear).
- The bag and the bank (ours, since 0.8.0, asked for in playtesting 2026-10-25: "I want to add a bank to the
  game [...] so the item limit is 50 items you can hold"), as RuneScape has them; whether Fairyland Online had
  a warehouse isn't verified here. The bag holds 50 slots: each kind of item one slot however many you carry,
  the coins one more (`GameSession.bagSlots`). What doesn't fit is left behind, loot and rewards too (the
  playtester's choice); a chest stays shut till there's room. The coins are a slot in the Bag with a pile
  that grows with them (`CoinsTile`, tools/coin_art.py), RuneScape's way, not a count on the HUD. A bank
  (tools/building_art.py `bank`) with a banker (NPC role `bank`, a coin on the minimap and the world map)
  stands in Meadowbrook, Prismhaven, Ingothold, Larkspur and Glimmerbough; what's in it, coins too, is never
  lost. Beaten by monsters you lose what you carry, coins and all; beaten in a duel, what you wear too
  (`loseBelongings`). What a quest you're on needs stays with you (`questKeepsakes`). What's lost is left
  where you fell (asked for in playtesting 2026-10-25: "anything that was lost will be shown on the map
  and for other players to grab"), RuneScape's way: a pile (`LostPile`, tools/prop_art.py `lost_pile`)
  on the ground, the minimap and the world map, yours alone for 5 minutes, then anyone's: an adventurer
  passing picks it up some minutes later (5 on average, rolled as it's dropped), and it's gone after 20
  at most (`GameSession+LostPiles.swift`). Walk up to it and Pick up takes what the bag has room for. A game begun before
  0.8.0 had its bag and coins moved into the bank once, on first load (`stockBankOnce`).
- The weapon in hand (`GearArt.pose`, since 0.4.8, asked for in playtesting 2026-10-12: "when they're wearing a
  weapon, it should look good"): the item's own art, held at the hand as each walk frame has it (beside the
  body, at the side facing you or away or the near hand walking sideways, and part way down that frame's own
  figure, so it sits lower on a dwarf and bobs a pixel as the walk does, frame by frame in step with it), and
  just behind the body so the hand closes over the grip. Before, it hung at one fixed spot per direction about
  four pixels out from the hand, and in front of the body facing you, so it floated beside the hero like a
  pasted-on icon. Shrinking the 32-pixel art to the walk sheets' pixel size (three quarters) was tried and
  dropped: it thinned the outlines and broke up whips and blades.
- Armour drawn with Retro Diffusion (in progress, 2026-10-12): inpainting (`/v2/edit/tools/inpainting`, $0.18)
  repaints a masked part of a 192×192 walk sheet in place, so armour drawn over a body sheet's torso and legs
  stays lined up with its frames and sits between the body and the player's chosen hair. A freshly generated
  walk sheet draws a whole new character (the unused `armor_*` sheets from before the paper doll are that), so
  it can't be layered. Its results come back as CloudFront links that the cloud session's network may need
  allowing.
- One equipment drop in three is a trinket (gloves, necklace, boots or accessory), any up to the monster's
  level (`GameSession.accessoryShare`): there are only a few of each next to dozens of weapons and armours, so
  by level alone they'd hardly drop.
- Turn order: your side goes first, in the order its moves were chosen, as players locking in their commands
  would. You go when you chose (how far into the time to choose), each friend (a bot) at a random moment of
  its own, every companion right after whoever it came with. Then the monsters, shuffled every round and
  weighted by SPD (each draws u^(1/SPD), the highest first; twice the SPD goes first two rounds in three).
  Our decision, 2026-10-10, at the playtester's request; before that the whole field was shuffled by SPD
  (2026-10-09), and before that it was SPD + a random 0–3. Since 0.8.7 each friend's moment is rolled as
  the time to choose begins (`BattleEngine.rollLockIns`), so the party's faces bottom left tick off as
  they lock in.
- The battle's look, not FO's, borrowed from Pixel Squad (Zitga, 2024) on 2026-10-25 at the user's
  request (0.8.7): a boss drawn at 3× (everyone else 2×), stepping out in front of its wave with its name
  across the field and its HP in a long bar along the top; names hidden under the fighters till you hold
  one (a crowd's piled up), a pick landing when you let go; your side's ground circles blue; skills as
  tiles in battle; a rune circle under everyone an area skill will reach; and the top skills' grand stroke
  (skills.json `grand`: a crescent of light, or a pillar of it from the top of the screen).
- Nothing misses and nothing dodges.
- Crits are a flat 8% for ×1.5, physical only.

## Guilds and classes

You join a guild at level 10 and can't leave it (H). Each guild has three classes, and each class becomes an
advanced class at level 60 (H).

| Guild | Home | Classes (level 10) | Advanced (level 60) |
|---|---|---|---|
| Warrior (also called Soldier) | Goldburg | Blademan, Swordman, Axeman | BladeMaster, SwordSage, Berserker |
| Journeyman | Rainbow City | Martial Artist, Beast Master, Trader | Kung Fu Master, Beast Lord, Merchant Prince |
| Diviner | Bluebird | Mage, Acolyte of Light, Acolyte of Dark | ArchMage, Architect of Light, Schemer of Darkness |

What each class does (H unless marked):
- **Blademan:** blade skills that hit a whole row of targets.
- **Swordman:** enhanced damage.
- **Axeman:** damages the target's armour.
- **Martial Artist:** fights bare-handed (gloves as Kung Fu Master), fast hits and damage boosts.
- **Beast Master:** whips and beast lore.
- **Trader:** a weak fighter but good at making money; loots extra gold from defeated enemies and is good at
  crafting.
- **Acolyte of Light** casts light spells; **Acolyte of Dark** casts curses.

**Us:** one class per guild, chosen from the guild masters in Meadowbrook at level 10, and permanent:
- Fighter (Warrior Guild)
- Mage (Arcane Circle)
- Beast Tamer (Wildfolk Lodge): ×1.6 capture, full EXP share for the companion

No advanced classes.

## Class skills (M)

- **Warrior:** Charge, Rush, Protection, Impact, Double Combo.
- **Mage:** Fireball, Dancing Fountain, Combustion, Spiritual Lance, Flame Hail, Inferno, Meteor Blast.
- **Acolyte of Light (H, from the wiki's skill list):** Recovery, Revive, Bless, Holy Light, Holy Glow,
  Guardianship, Holy Blast, Rain of Grace.
- **Acolyte of Dark:**
  - Curse (level 1, 10 MP): lowers the target's attack, both its damage and its hit rate.
  - Poison (5, 10 MP): the target's HP drops a little every turn. Lethal Poison (20) drops it faster.
  - Fear (10): enemies flee in terror.
  - Vampirism
  - Life Altar
- **Beast Master:** Beast Lore (Observe at lore level 15), Dodge Whip, Animal Training.
- **Beast Lord:** God of Beast Impact.
- **Trader:** Dodge, Hide, Invisible, bribery and collection.

**Us:**
- 20 hero skills.
- Skill levels (ours): a skill point a level, one to learn a skill and one for each step up; ten steps to
  Mastered (×1.8 damage, ×1 when learned, a point of MP a step). Since 0.7.72 your hero's skills keep growing
  past it, to level 50 (playtesting 2026-10-23: "you should be able to continuously improve these skills,
  every level it becomes stronger and at certain milestones the animation in battles becomes grander"):
  1.5% of a fresh skill's strength a level (×2.4 at 50), a point of MP every five, and a milestone every ten
  (`GameSession.skillRank`): Heroic at 20, Epic at 30, Mythic at 40, Legendary at 50. Each opens the mastered
  show wider (bigger magic circles, a second ring, more rays and motes, the milestone's name under the
  skill's), the ground shakes from Epic, the finale strikes twice from Mythic, and Legendary comes in every
  colour. Monsters', companions' and friends' skills stop at mastery.
- Our Mage carries Recovery, Revive, Bless, Holy Glow and Guardianship, which FO gives the Acolyte of Light,
  and Curse (level 12) and Poison (level 25), the Acolyte of Dark's.
- Like FO's Mage, whose list starts with Fireball, ours learns Fire Bolt on joining the guild at level 10
  (since 0.3.17).
- Status effects (since 0.3.14): Guard, Poison and spells that raise or lower stats (since 0.3.41).
  - Poison: HP lost at the end of each round, 3 times, shown as a purple number marked "Poison".
  - Raised or lowered stats (ATK, DEF, MAG, SPD) last the round they land in and 3 more. Each change pops
    up over the fighter with its amount ("DEF +40%"), and a blue arrow up or a crimson arrow down by the HP
    bar shows it's in effect (no round count since 0.3.57, asked for in playtesting; poison keeps its count). A second spell on a stat doesn't stack; the stronger one counts.
  - Buffs, FO's skill names with our own effects (FO's aren't in any source reachable from a cloud session):
    Protection (Fighter 12, one ally DEF +40%), Holy Glow (Mage 40, one ally MAG +30%), Bless (Mage 45, ATK
    and DEF +25%), Guardianship (Mage 60, the whole party DEF +20%) and Animal Training (Beast Tamer 25,
    ATK +20% and SPD +30%). Raises grow with the skill's level like damage, ×1.8 when mastered, then
    gentler past it (0.5% a level, ×2 at 50).
  - Monsters and companions: Boost (ATK +20%; golden hamsters, wood hogs, blaze bulls, earth lions) and Berserk
    (ATK +30% but DEF −25%; werewolves, fire bears, black kongs), FO's pet skills. They cast them on
    themselves now and then; friends cast theirs on whoever they'd help most.
  - Monsters that heal: FO's light pets healed and pets learned Heal (see Pets). A few of ours know Recovery
    (wisps, lotus sprites, pegasi, star moths, temple jellies and three light bosses: the Great Wisp, the
    Moon Rabbit Queen and the Fallen Star). Below 35% HP they cast it on themselves half the time, once a
    fight, and a monster's heal (a companion's too) gives back at most a fifth of the HP it goes to
    (`BattleEngine.selfHeal`, `monsterHealCap`): uncapped, a level-40 wisp healed itself to full.
  - Curse: lowers ATK and MAG by 20% (up to 36% as the skill grows), so hits and heals both weaken. FO's
    Curse lowers attack and its hit rate; we have no hit rate.
  - No Lethal Poison, Fear or cures yet. Every status ends with the battle.
- Monsters use them too: Venom Bite (snakes and widows, 40% chance to poison), Poison Mist (the Poison
  Skeleton, the whole party) and Evil Eye (phantoms and Morvane, a curse).

## Elements

Seven elements: metal, wood, water, fire, earth, dark and light. A matchup changes damage by up to 50% (H).

**Us:** the same seven plus neutral.
- The five-element cycle runs water > fire > metal > wood > earth > water, at ×1.5 (×0.75 the other way).
- Light and dark hit each other for ×1.5.
- Only magic uses elements.
- The hero is always neutral.
- The calendar's months are named after the five elements.

FO's exact chart (the reverse multiplier, light and dark) is still **?**.

## Pets

**Modes (H):**
- Normal: resting in its capsule.
- Combat: fights beside you.
- Walk: follows you around.

**Fusions, unlocked by intimacy (H):**

| Mode | Intimacy | Effect |
|---|---|---|
| Arms | 30 | Fuses into your weapon: damage from the pet's STR, accuracy from its DEX, and your attacks take its element |
| Armor | 50 | Fuses into your armour: defence from its CON, evasion from its LUK, and your defence takes its element |
| Magic | 60 | Fuses with your mind: magic power from its INT, more again for spells of its element |
| Soul | 80 | Fuses with your soul: magic defence and HP/MP regeneration. Temporary; once the pet is exhausted, Soul can't be used for about 10 minutes |

**Upkeep and intimacy (H):**
- The pet you take along feeds on your MP. If you can't spare it, the pet won't come.
- Intimacy grows with feeding and walks, and drops when the pet wanders off screen.

**In battle (H):** you command your pet each round: whom it attacks and which skill it uses. How well it
obeys depends on intimacy:
- At 30, it doesn't always attack the one you pick, and telling it to use a skill can make it attack you or
  a party member.
- At 50, it always does as it's told.

**EXP (H):** only pets in a mode other than Normal or Walk share battle EXP.

**Growth (H):** 7 stat points per level.
- Mostly by element (M): fire leans STR, water DEX, earth CON, metal INT; light pets heal.
- Dark pets grow with INT (H).
- Then by species.

**Skills (M):** learned by species and element as they level, e.g. Boost, Super Boost, Berserk, Heal and
Full Heal.

**Extras (H):**
- **Pet Toys:** 105 toys that add up to 50 points to a stat you choose. Made by Timmy in Baghdad's toy store.
- **Pet Carts:** pets with Push Cart pull a cart you ride in. The cart lowers the encounter rate, raises HP/MP
  regen and adds pet stats. Made by Sole, also in Baghdad.
- **Collections:** every pet has a number in the pet collection and the card collection, and monsters drop
  cards and dolls (the Puppet drops a Puppet Card and a Puppet Doll).

**Getting pets:**
- The first one hatches from an egg in the tutorial quest (H).
- Higher-level and higher-rank pets are harder to capture, so beginners are told to hatch eggs (H).
- Capture uses capsules in level tiers (M): level 1 catches pets of level 1–20 and is sold in the three
  capitals' pet shops; level 2 catches pets up to level 40 and comes from Baghdad's pet shop or quests.

**Us:**
- Up to 5 companions; only the one you bring along follows you, fights and earns EXP (50%, or 100% for a
  Beast Tamer).
- A companion drawn as one picture (most monsters) is mirrored to face the way it walks, left or right
  (since 0.4.5, asked for in playtesting 2026-10-11; `WalkCycle.mirrors`). Most pictures look left or at
  you; the few that look right say so in art/assets.json (`faces`), and palette swaps inherit it.
- Seal Stones are thrown with Capture (the plainest one you have) or from Items (any kind). Since 0.3.70
  (asked for in playtesting, 2026-10-07) there are five, the same crystal in five colours, and every throw
  uses the stone up, held or not (before, only when it worked): the teal Seal Stone (60 gold), the blue Moon
  Seal (odds ×1.5, 200 gold in Prismhaven and Larkspur), the pink Heart Seal (×2, 500 gold in Larkspur and
  Ingothold), the gold Star Seal (×3; bosses drop one 25% of the time) and the rainbow Wishing Seal, which
  never fails (Elder Oak's quest Wish Upon a Star, bosses 5%, the Monster Book's last reward). A stronger
  stone also lifts the odds' 75% ceiling, up to 95%, and while you aim, each monster shows your odds. FO's
  capture capsules came in level tiers instead (M, above). Since 0.3.66 (asked for in playtesting, 2026-10-07)
  it works on any wild monster at any HP: the odds climb as it weakens (×0.25 at full HP, ×1 at 20%, up to ×3
  near 0, before level, fight length and the Beast Tamer's bonus), your side leaves the monster you're sealing
  alone, and a sealed monster is yours however the fight ends. A full party can take one newcomer a fight (you
  pick who stays behind). Until 0.3.65, only the last monster standing at 20% HP or less.
- Friends at your side without a companion catch their own (ours, since 0.3.97, asked for in playtesting
  2026-10-11; FO's other players caught pets like you did): each carries plain Seal Stones (0–3 when met, 2
  for friends made before), and throws one at the monster most likely to hold once it's at 20% HP or less (40%
  for the last one standing), never at the one you're sealing. Their level and class set the odds; a catch is
  their companion from then on, and a stone is used up either way.
- Companions grow as species base + growth × (level − 1) and have a fixed skill list.
- Each round, after your own choice, you pick your companion's: Attack, one of its skills, Guard, or Auto (it
  decides itself). It always obeys, since there's no intimacy. A Settings switch leaves it to fight on its own.
- Toys (since 0.3.69, asked for in playtesting 2026-10-07: "more items that really add value and you want to
  collect"): six, each raising one stat for good, +5 ATK, DEF, MAG or SPD, +25 HP or +10 MP, up to ten a
  companion, so one stat can take FO's 50 points (`GameSession.giveToy`). Prismhaven's market sells them
  (1,200 gold), every boss drops one 30% of the time, adventurers carry them, and Tilly the Toymaker's quests
  pay in them. FO's toy maker was in Baghdad, a town we don't have; ours is in Prismhaven.
- None of the modes, fusions, intimacy, upkeep or carts exist.

## Work skills and crafting (H)

- Working gathers raw materials to sell or craft with.
- Work skills: woodcutting, fishing, hunting, farming and mining. They're learned from quests and level up the
  more you work, and higher levels give better goods.
- Mining needs a Pickaxe and yields coal, copper, bronze, crystal and amethyst ore, among others. Ore feeds
  Metal Working and Gem Cutting, which make equipment.

**Us:** monsters drop wood, metal, hide and gems, and three town smiths forge weapons from them, and since
0.8.2 armour too (playtesting 2026-10-25: "I should be able to create armor with metals I have found [...]
so I can trade it and earn coins"): the metal and gem sets, copper to topaz, as plate, robe and hide, each
from the metals, gems and hides that drop round its level (the smith shows those from 15 levels below you to
10 above). Sold, a piece fetches half its price, far more than its materials would. There's no
gathering and no crafting level, and forging always works. Monsters also drop equipment from up to their own
level (6% a monster at your level, up to 16% above it, 2% well below; rares 35%, bosses always), mostly for
your class (`GameSession.equipmentDrop`), never a boss's own rare drop or a quest treasure.

## Titles, fame and PvP

- **Titles (H):** collectable, e.g. Rose Queen, War Hero, PK Master, crafting maestros, seasonal and
  anniversary titles.
- **Dolls (H):** collectable too.
- **Fame (M):** quests are the main way to earn it.
- **Kingdom Wars (H):** guild-vs-guild PvP.

**Us:** titles, but no fame. 33 titles (content/titles.json, our own names) are earned for levels, lands
visited, the Monster Book, monster cards, quests, bosses, companions, friends, daily bounties and days
played (the three rebirth titles went with rebirth in 0.7.27), and one is worn over your name; computer-run adventurers wear the level titles that fit them.
Duels are with computer-run adventurers in 9 danger zones; a beaten adventurer drops everything they carry
(the goods they'd sell you that day), and their companion can be sealed in the fight like a wild monster,
joining you (ours, playtesting 2026-10-24). The red-named troublemakers only pick a fight with a side about as
strong as theirs or weaker: their level plus their companion's at least nine tenths of yours, your companion's
and your party's (`GameSession.dares`; our decision, 2026-10-11, at the playtester's request). Bosses never
start a fight: you talk to them. A quest pays its own fixed reward, whatever your level (since 0.7.56,
playtesting 2026-10-20: "the xp you can win from a quest should be fixed [...] not based on my current
level"; from 2026-10-06, also at the playtester's request, it paid at least a bit more than a daily bounty
for your level, `quests` in content/rewards.json, gone now). Its fights are fixed too: its monsters at their
land's levels, its boss at its own.
A quest giver talks a page at a time and about one quest at a time (since 0.7.89, playtesting 2026-10-25:
"it needs to be conversational, with next and back buttons [...] One should be completed first with
storytelling"): its story told in the sentences of its description with Back and Next, the quest and
Accept on the last page; while you're on one of theirs they offer no other and show no "!", and handing it
in leads into the next one's story (`GameSession.currentQuest`, `QuestConversation`).
A quest giver with nothing for you says why (a level to reach, someone else's quest first, or all done) and
points to the quest open to you that suits your level best, or the next to open (`GameSession.questGiverNote`,
since 0.4.0, at the playtester's request, 2026-10-11: a level-103 hero was told to come back stronger). The
same day closed a gap with nothing new between levels 96 and 109: the Old Ox on the Hidden Steppe (Aesop's
four oxen and the lion; 100, 106, 114) and the Little Crab on Sneezle Sands (the Japanese tale of the monkey
and the crab; 124, 130), both ours.
Since 0.7.11 a quest can ask you to bring something, not only to beat monsters (playtesting 2026-10-16:
"Maybe to get to the islands you need to complete a quest. The quests shouldn't only be about defeating
monsters, but maybe also obtaining an item or carving one. Check the runescape quests for inspiration"),
ours, after RuneScape's: Sheep Shearer and Imp Catcher (things won from the monsters about), Lost City (a
Dramen branch won from the tree's guardian spirit and carved into a staff with a knife) and Dragon Slayer
(a ship to buy and patch with planks and nails, a map of Crandor in three pieces from three places, a
captain to sail it) ([RuneScape Classic Wiki](https://classic.runescape.wiki/w/Dragon_Slayer),
[RuneScape Wiki](https://runescape.wiki/w/Dramen_Staff)). A `bring` quest wants `count` of an item in the
bag and takes them when you hand it in; while you're on it, its monsters drop them (quests.json `drops`,
a chance a beaten monster, up to what it wants, none once you have it), a chest opens for it (maps.json
chest `quest`), or you make it by hand from the bag (items.json `make`: carve or join, from its `recipe`,
the Carve and Piece together buttons on a piece's card, `GameSession.make`). A quest's pieces are materials
of their own (`material: quest`), never sold or dropped otherwise. Captain Brine at Sneezle Sands' harbor
(an NPC at a landmark, `NPCDef.at`) readies the ship to Starfall Isle in three: A Spare Sail (4 Sailcloth
Scraps from the fire crabs, 122), A Figurehead for the Gull (Starwood from the wood monkeys, carved with 3
Red Yew, 124) and The Star Chart (three pieces: in an old chest on Sneezle Sands, from the Hidden Steppe's
Earth Lions and from a Mint Shadow Ape; pieced together, 126). Its ship stays moored till then (the exit's
`requires`), saying which quest it waits on as you step up to it; the ship back never does. Two early ones
show the same: Wool for the Lambs (Mother Sheep, 5 Tufts of Wool from the golden hamsters, 5) and A Flute
for Shelly (Old Shelly, a Piece of Driftwood from the wood crabs carved with 2 White Poplar, 10).
Since 0.7.64 a quest can be a favour for someone else (playtesting 2026-10-22: "Some quests should also
tie to other characters, that you have to do them a favor and give another character something and then
have to come back"), ours, after RuneScape's errands (Romeo & Juliet has you carry Juliet's message to
Romeo): a `deliver` quest hands you its `item` when you accept (`starterItems`); its `target`, anyone
you can talk to in any land, has a button for it in their window (`ErrandPanel`) and a "?" over them
till you hand it over, says its `text`, and may give you `returns` to take back, which the giver takes
when you report back (`GameSession.deliver`). Six: Miller Rosie's letter to Mayor Poppy and her reply
(14), Barnaby's honey for Tilly (14), Fenwick's lantern oil for Mabbott's Everlasting Wick (30), Samira's
well water for Mungo's camel tonic (58), Bastian's coffee for the dwarfs' kettle (76) and Sigrun's ice
rose for Blanche (136). The same day added six elite quests, long hunts or rare monsters for about twice
a land's usual pay (The Werewolf Pack, 20 Werewolves, 27; The Amber Werewolf, 46; Violet in the Dunes,
72; No More Nightmares, 30 Dream Phantoms, 86; The Lion in the Frost, 155; Shadow Apes on the Road, 25
Mint Shadow Apes, 196), and a difficulty on every quest, shown as a pill with pips in the Quests list (only
there since 0.7.89, playtesting 2026-10-25; by its giver too before), and a "Hardest" sort (`QuestDifficulty`, RuneScape's Novice to Grandmaster in four:
Easy, Normal, Hard, Elite). A quest says its own (`difficulty`, 1 to 4; the elite ones do); otherwise
`GameSession.difficulty(of:)` works it out: a boss or 12 or more monsters is Hard, 8 or more, something
made by hand, a scarce drop or 5 or more things to bring is Normal, and the rest (an errand, a level, a
class, a handful of monsters) Easy.
Quest treasures (ours, since 0.4.2, asked for in playtesting 2026-10-11: quests should give rare items and
armour you don't get from fights; no source we could reach says what FO's quests paid in gear): 33 pieces of
armour, boots, gloves, necklaces and rings, each from one story quest between levels 14 and 190 and themed on
it (Oxhide Mail from the Old Ox, the Woodcutter's Coat for the Big Bad Wolf, Liora's Veil from her ruins). A
treasure is gear a quest gives that no shop sells (`Content.questGiving`); no monster drops one, no trader
carries one and no adventurer wears one, and tools/check_content.py keeps each to one quest, off the bosses'
drops and the smiths' recipes, and wearable at the quest's own level. They sit about a quarter above shop
gear of their level (by `GameSession.gearValue`'s weights) with a stat mix of their own, and carry armour
past the shops' last at level 78. Icons are free palette swaps with a gold frame and a sparkle; the item card
names the quest, and the quest list shows each one's stats before you start. A save that finished a quest
before it gave its treasure gets it by post once (`GameSession.deliverQuestTreasures`).

**Cards (since 0.3.69):** FO's card collection, our own way, since no source we could reach says what FO's
cards did. Every monster has one. A beaten monster leaves its card 3% of the time (rare 15%, boss 25%;
`cards` in content/rewards.json). The first of each goes in the Monster Book and raises a stat for good, by
element: Fire and Metal attack, Dark magic, Earth defence, Water speed, Wood HP, Light MP. It gives a step, and
another for every 25 levels of where the monster lives, twice that for a rare card and three times for a
boss's. The whole set adds about +107 ATK, +127 MAG, +44 DEF, +27 SPD, +375 HP and +154 MP. Since 0.7.20 a
monster whose card is in the Book leaves no other (playtesting 2026-10-16: "Spare cards shouldn't be
automatically sold. Duplicates shouldn't be rewarded at all"); before, spares sold on the spot. Tilly the Toymaker in Prismhaven has five quests for 5 to 100 kinds of card, paid in toys, and three
titles count cards. FO's dolls aren't in yet.

**Capes (since 0.7.16), ours, after RuneScape's:** asked for in playtesting (2026-10-16: "If I have all
the monsters from a land or in the whole world, or the monster cards, I should be able to collect a very
special armor prize from a character, just like the lvl 99 capes in runescape, to show status. Same for
completing number of quests or other milestones"). RuneScape sells a cape of accomplishment for each skill
at level 99 (99,000 coins, from that skill's master, with a hood; each has its own emote, and the capes
of a player with two or more 99s are trimmed), and a quest point cape once every quest is done
([OSRS Wiki](https://oldschool.runescape.wiki/w/Capes_of_Accomplishment),
[RuneScape Wiki](https://runescape.fandom.com/wiki/Farming_cape_(t)),
[RuneScape Wiki](https://runescape.wiki/w/Quest_points)). Ours: Orla the Weaver in Meadowbrook weaves a
cape for each of the 27 lands with monsters, once every monster living there (its wilds and its bosses,
as the Monster Book lists homes) is beaten, in that land's colours; and six for the world: the Monster
Book (every monster beaten), cards (every card), quests (every quest), bosses (every boss), lands (every
land visited) and the Talewild Cape (every other cape) (rewards.json `prizes`). Free, worn in a slot of
their own (so they never cost you your armour) and drawn on your back (`GearOverlay.drape`: from behind
hung from the shoulders with a diamond emblem and a trimmed hem, the hair over it; from the front and
side past your outline), a small bonus to stats; never sold or dropped, and woven again if lost. No
emotes or trims yet.

**Ours, not FO's (content/rewards.json):** a gift each day you play, in a round of seven; three daily
bounties scaled to your level, with a bonus for all three; and rewards as the Monster Book fills (10, 25, 50,
75 and every kind). They're built on FO's own calendar idea, but FO didn't have them as such.
Hard wins leave Seal Stones (`seals`, ours, 2026-10-09, asked for in playtesting): when the strongest beaten
monster stood 5+ levels over you (when the tougher battle theme plays), 30% a Seal Stone or Moon Seal; 10+,
50% mostly Moon Seals; 15+, 70% mostly Heart Seals; 25+, 90% mostly Star Seals; a boss fight always one. Never
the Wishing Seal, which stays the Monster Book's last reward.

## Unverified, or only our own repo says so

- **Equipment drops:** monsters drop equipment, and stronger fights drop better gear. From a playtester's
  memory (2026-10-04); check the rates on the ToM wiki.
- **PK drops:** a player beaten in PvP drops their items. From a playtester's memory (2026-10-04);
  not in any source reachable from a cloud session. Check on the ToM wiki.
- **Level cap 200, and no rebirth.** FO does have rebirth (the 2026 video), and we had it too until 0.7.26
  (from level 101, back to level 1 with some strength kept). Since 0.7.27 it's gone (ours, playtesting
  2026-10-17: "Remove the thing that you reborn. The limit is just level 200. There should be armor and
  other wearable items for level 200 for prestige"): level 200 is the top, and the prize there is the
  Goldleaf gear, ivory and gold, a piece for every slot and a weapon for every guild, all level 200. Elder Oak
  gives it in three quests: Living Legend (on reaching 200: the ring and pendant), The Warden, Once More
  (beat the Silverfang Warden again: gauntlets, boots and the four weapons) and The Dragon at the Top (beat
  the Emerald Dragon again: the plate and robe). The hero's name turns gold at 200, as it once did for a third
  rebirth. A hero reborn before then goes back to the level their last rebirth began at, 101 and 5 more
  for each earlier one (`GameSession.retireRebirthsIfNeeded`), and their rebirth titles go.
  `check_content.py` insists the top level keeps a piece for every slot and every guild.
- **Capture rules:** at 20% HP or less, on the last monster standing. Ours until 0.3.65; since 0.3.66 any
  monster at any HP, the odds best below 20% (see Pets).
- **Party size:** more than two people, each bringing their pet, from a playtester's memory (2026-10-04).
  Not found in any source reachable from a cloud session.
  - Us: you and up to four friends, each with a companion. Since 0.7.15 the computer-run adventurers
    travel together too (ours, asked for in playtesting 2026-10-16: "other bots in the game can also be with a
    group"): now and then two to four of about the same level, one leading and the rest in single file
    behind with their companions at their sides, as your party walks (crowd.json `groupChance`,
    `groupSize`; `Crowd`). They stop together as you walk up to any of them; their card says how many.
  - Since 0.7.18 partying up works both ways, and not for ever (ours, asked for in playtesting 2026-10-16:
    "bots should also decline to follow you in your party. You can also join bots' parties and follow them.
    Bots can also decide to leave a party again after a while"). FO's parties were other players, who could
    say no and leave as they liked. An invite is a yes `acceptChance` of the time (crowd.json), a quarter
    as often over 20 levels apart, half as often to one travelling with friends, and a no holds for three
    minutes (`GameSession.askAlong`). Ask whoever leads a group and you can join it with room for you and
    your party's friends, five in all (`askToJoin`): you walk at the back of their line as they lead you
    about (`Crowd.lead(you:)`) and they fight beside you; you leave once you're far from whoever leads, or
    from the plate under your party. Anyone in a party with you heads off after `stayMinutes` on the
    clock (`passPartyTime`), and a friend who did won't come along again for half an hour
    (`restAfterStay`), so you meet others (since 0.7.92, playtesting 2026-10-25: "members who joined my
    party are staying forever"; counted only while walking about, the time stood still through every
    fight and started afresh at every launch, so nobody ever left). Among themselves adventurers leave their group or join one near them every
    `groupMinutes` (`Crowd.mingle`).
  - Past five, the battle line splits: people in front, companions in a row behind.
  - Without a friend (since 0.3.83), you and your companion stand side by side in one line, as a
    playtester asked (2026-10-08); with friends, companions stand a row behind whoever they came with.
- **Battle layout:** battle rows (the Blademan's row attack suggests there were rows), equipment slots, and
  the full list of status effects.
- **Boss fights in waves:** ours, asked for in playtesting (2026-10-04); whether FO's bosses came in waves
  isn't in any source reachable from a cloud session.
  - Us (since 0.3.18): two waves of the map's monsters, then the boss with its minions. HP and MP carry
    over, each wave stands a few levels closer to the boss's, and the boss always has the highest level.
  - Since 0.3.45 every wave is 10 strong: ten of the map's monsters, and in the last wave the boss with nine
    minions, standing in the middle of the back row (furthest from you). Asked for in playtesting (2026-10-04). The earlier
    waves stand 6 levels lower per wave (7 to 14 below the boss, then 13 to 20), within the map's range.
  - `waves` and `minions` on the boss NPC (content/maps.json) tune it per boss.
- **Fainting in a party:** ours, asked for in playtesting (2026-10-04). How FO handled a player fainting
  mid-fight (whether the others fought on, and where everyone woke up) isn't in any source reachable from a
  cloud session.
  - Us (since 0.3.21): the fight goes on while a friend stands, and a friend who knows Revive wakes you
    first. Whoever is down at the end wakes at their own checkpoint (you get no EXP if your friends won it),
    and friends still standing when you fell wait where the fight was. Waiting friends stay in the party but
    sit out fights until you walk up to them.
- **Day, night and weather:** FO's calendar line ("1001/Fire/12/13hr") and its dawn/dusk are what we built
  the clock on. Whether FO's maps visibly darkened at night or had weather isn't in any source reachable from a
  cloud session (a 2026-10-04 web search found nothing); asked for in playtesting (2026-10-04). Check the ToM
  wiki.
  - Where the date shows: FO kept its calendar line on screen; ours sat on a plate under the faces top-left
    until 0.8.4, and is now on the map's "you are here" row with your coordinates (`MapOverlay`;
    playtesting 2026-10-25: "Remove the day/time bar in the top left and incorporate that in the map modal").
  - Us (since 0.3.44): `Sky` multiplies each map by the hour's light (warm at dawn and dusk, deep blue from
    about 19:30 to 04:30) and fades the sun's flare and sunbeams with it. On the continent the land's air
    (butterflies, clouds' shadows, drifting particles, the sparkles over fairy rings and fountains) hung
    over that shade until 0.7.8, as bright at night as by day (playtesting 2026-10-16: "when it's night,
    the butterflies are too light"); it's lifted only past what stands now (`LandStage.airLift`). Weather (`Weather`) changes every
    6 in-game hours, picked from the map's `ambience.weather` weights: clear, cloudy, rain, storm, fog, snow.
    Caves have neither. The battle backdrop is the map without the sky.
  - Us (since 0.3.65, asked for in playtesting 2026-10-07): night was too long at twelve real minutes, and
    showers lasted their whole six-minute spell. By day an in-game hour is still a real minute; from 18hr to
    6hr the clock runs at `GameClock.nightPace` (1.5×), so night takes eight minutes of a twenty-minute day.
    Rain and storms stop after a real minute and leave the rest of their spell cloudy. Settings has a switch
    for each (asked for the same day): with night and day off the light stays at midday, the HUD shows the
    sun and there are no dawn or dusk notices (the calendar still runs); with the weather off it's always
    clear. A debug `weather=` still wins, for screenshots.
  - Us (since 0.4.7, asked for in playtesting 2026-10-12: "the shadows and sun should follow over the
    landscape"): the sun crosses the sky (`Sun`, from `Sky`'s hour). It rises in the east-north-east (up the
    screen) at 6hr, is where the art's light always was at midday (up the map and to the left, 36° up) and
    sets in the west-south-west (behind you, to the left) at 18hr: half a turn, low at either end (8° at
    least) and highest at midday. The moon takes the same path by night, at 60% strength. For the first and
    last game hour the light turns soft and comes from overhead, so nothing jumps when one gives way to the
    other. The hills' slopes are lit by it in their shader (`HillArt.lifting`; scenery on them with them):
    as the sun gets lower, slopes facing it get brighter next to the flat and more of the others fall into
    the hill's shadow, while the shade's depth stays midday's (the sky's light fades with the sun's). Trees'
    and rocks' shadows (`Lighting.Shadow`) are a round under them stretched away from the sun along the ground,
    a quarter of their width at midday (as they were) and up to 1.4 widths at sunrise and sunset. Since 0.4.13
    (playtesting 2026-10-12: the characters' shadows should follow too) everyone who walks casts the same
    shadow (`Walker.cast`, `Lighting.Shadow.shape`) instead of a fixed dark ellipse under their feet, so
    at night they're as faint as the trees'. Until 0.4.14 a shadow on a hill (split by its strips, so it
    has a shader) came out white: `SKDefaultShading()` leaves out a sprite's colour, so its clip shader
    paints black from the glow's alpha (playtesting 2026-10-12: long streaks of light down Gumdrop
    Peaks' shaded slope at 7hr). The sun's
    flare comes in along the top of the screen toward it through the morning and sits in the top-left corner
    from midday on, and the sunbeams lean their tops toward it. Before 0.4.7 the beams leaned to the upper
    right, against the flare in the top-left corner. In 0.4.7 the flare went on down the left side in the
    afternoon, where half its glow was on screen and washed out the middle of the map (left of the screen
    half again as bright at 16hr in the screenshots, 2026-10-12); since 0.4.8 it stays in the corner. Whether FO's light moved
    with its clock isn't in any source we've found; this is ours. Clouds don't soften the shadows yet.
  - Our setting is called Fabelia in every in-game text (Fairyland until 0.3.50, Storyleaf until 0.8.1, Talewild until 0.8.7; see Names). In FO the
    continent itself is Mysteria (above), which is also the relaunch's name.
- **Bots, moderators and announcements:** ours, asked for in playtesting (2026-10-04). FO's chat channels,
  GM notices and player stalls (players selling under a sign in town) aren't in any source reachable from a
  cloud session; check the ToM wiki.
  - Us (since 0.3.22): computer-run adventurers wear a BOT tag. A moderator (switched on per device with a
    code typed in the chat, `Moderation`) wears MOD and has a World channel that every map's chat shows.
  - Announcements (content/announcements.json) cover dawn and dusk, arrivals, other adventurers' news, and
    rare sightings that really raise a rare monster's odds on its map for 20 minutes.
  - Goldburg's square has market traders under signs, selling their real deals of the day
    (`crowd.traders`). `botDensity` in content/crowd.json thins out every map's bots.
  - Your own wares (since 0.8.3, asked for in playtesting 2026-10-25: "I should be able to set items up for
    trade, and then when a bot goes up to me, they can trade with me and then I can decide if I accept the
    offer or decline"), something like FO's player stalls: put up to 8 kinds of thing up for trade from the
    Bag (a coin on its slot), and every half minute to minute and a half an adventurer on their own nearby
    walks over (`Crowd.seekBuyer`) and offers for one of them, from 0.8 to 2 times what a shop pays
    (`GameSession+TradeList`): accept or decline. And trading with an adventurer, they want one thing of
    each of up to three kinds you carry (gear, potions, materials...), not materials first as before.
  - Us (since 0.4.12, asked for in playtesting 2026-10-12: "characters walking/standing around that give the
    place more character and a story"): every map has locals (maps.json `locals`, `MapDef.Local`), two or
    three out in the fields and one in each cave and town, and two more in each village (below), 109 in all.
    Each has a look of their own (race, gender, hair, outfit; the rest drawn from their place in the list, so
    they look the same on every visit), a home by a landmark (a jetty's end, a road's bridge, a lake's island
    or shore, a cave's mouth), on a summit or out from the middle, and stands there, strolls about it or walks
    an errand there and back (`walk`). Some carry something (`hold`, a weapon from items.json, never a
    treasure), wear armour, lead an animal (`pet`) or have their things set down round them (`props`). They
    tell a short story a line at a time, in order, starting as you come within 160 points and going on every 9
    to 14 seconds while you stay (a tap brings the next line at once), in white like the villagers. Some
    stories cross maps: Little Lou in Meadowbrook, Tess at Sunny Meadow's bridge and her brother Wil lost in
    Twilight Woods; Odile the Mapmaker on five maps, drawing the pages of Liora's book. Fairy-tale folk
    (Hansel and Gretel, Bo-Peep, Odette, the Tin Woodman) are public domain. Whether FO had people like this
    out in its fields isn't in any source reachable from a cloud session; they're ours.
  - Us (since 0.4.12, playtesting 2026-10-12: "near the temple keeper and other guilds there should
    actually be something like a temple or building"): whoever works somewhere has it at their back, a
    step right and two rows behind them (maps.json `buildings`), so they stand at its door.
    - Briarmere's Temple Keeper keeps a lakeside shrine (`lake_shrine`, drawn in code by tools/building_art.py, 2026-10-24):
      a little snowbound temple of pale stone on three steps, Liora's statue between its columns, a silver bell in its
      pediment. It had been RD's town gate arch with her statue behind it, which read as a gateway, not a temple.
    - Ambrose the Wise has a tower, Hermit Orrin a mushroom hut, the Old Swan Keeper and Little Pig
      cottages, Mother Sheep a windmill, and Dozywick some houses.
    - In Meadowbrook each guild has its own: the Warrior Guild a grand stone hall between two crenellated
      towers with red banners, spears and a training dummy (`warrior_guild`), the Wildfolk Lodge a great log
      lodge with antlers on its gable, a porch, a stable wing and a totem (`wildfolk_lodge`, Ranger Pip moved
      across the lane to it), both drawn bigger than a house and standing on 5 × 3 cells; the Arcane Circle
      RD's wizard tower. The
      other towns' healers and shops stand at an inn's and a shop's door, and Prismhaven's toymaker at a toy
      shop's.
    - New sprites for them were priced at $0.06 each in RD and turned down (2026-10-12); since 2026-10-24
      they're drawn in code by tools/building_art.py and held to docs/pixel-style.md's acceptance check:
      the two guilds, Briarmere's shrine, a bell tower for Valley of Fear's Bell-Ringer and a gem workshop
      for Crystal Mountain's Gemcutter (both had stood at the wizard tower), and Shrine-Keeper Ondine
      moved from a wizard tower to the Tidewater Shrine's own water shrine.
  - Us (since 0.7.23, playtesting 2026-10-17: "in every map, create little villages or communities with
    characters and their own stories or quests, similar to runescape"): each land out in the fields has a
    village of its own a little way off its roads, the way RuneScape's lands have their hamlets. Two quest
    givers stand at their houses' doors with two more houses round them, and two villagers (locals) live
    there, one by the village well or its middle and one by their things (crates, a haystack, a market
    stall). Their three quests tell one story and end in a treasure (`fieldsHaveVillages`); a cave has a
    camp instead, one quest giver with a local beside them and two quests. The early lands came first:
    Cloverdale (Sunny Meadow), Thistledown (Windswept Downs), Driftwood Cove (Pineapple Shore), the
    prospectors' camp in Gooey Grotto, Duskhollow (Twilight Woods), Hollyhock (Smiling Forest), Peppermint
    Row (Gumdrop Peaks), Bogbottom (Frog Swamp) and Woodsend (Big Bad Wolf's Lair, with Little Red and her
    grandmother, public domain). The middle lands followed in 0.7.24: Reedwater (Swan Lake, its lacemaker
    sewing a veil for the swan girl on the island), Candlewick (Shiverdell), the ratcatchers' camp in the Rat
    Cavern, Lilypad Landing (Lotus Land: tiny folk, their quest givers drawn at 0.7 like Thumbelina),
    Stringwood (Marionette Rise), Mirage Wells (Genie Desert), Emberwharf (Ingothold Lake), Geode Hollow
    (Crystal Mountain), Wakewell (the folk next to Dozywick who can't sleep) and Seven Hearths (Snow White
    Forest's seven dwarfs, our own names, not any film's). The late lands came last, in 0.7.25: Silvermoon
    Steps (Moonwhisper's Moon-Viewing Night), Tallgrass (Hidden Steppe), Pepperpot Bay (Sneezle Sands),
    Icemoor (Briarmere), Pilgrim's Rest (Tidewater Shrine), the silk-spinners' camp in Whispering Hollow and
    Greenglass (Emerald Road), so every land out in the fields has one. The quest givers are drawn from the
    heroes' paper-doll layers (free; their hair on a layer of its own, one colour from root to tip), their
    houses the buildings the towns use, graded by each land's palette.
  - The minimap shows everyone else on the map as dots (since 0.3.55, asked for in playtesting 2026-10-06):
    blue adventurers, white friends, red hostile ones, green party friends; on dark maps only on cells you've
    seen. Whether FO's minimap showed other players isn't in any source reachable from a cloud session.
  - Us (since 0.4.14, playtesting 2026-10-12: "on the mini map it should show other characters in the game and
    have an icon for quests, healing etc (similar to runescape)"): the folk who live on a map (villagers and
    locals) are smaller yellow dots, as RuneScape's people are, and whoever has a job is a round icon in their
    own colour (`GameSession.MinimapMark`, `MinimapIcon`): a gold "!" or "?" over a quest giver with a quest
    for you (as over their head), a book over the others, a heart for the healer, coins for the shop, a hammer
    for the smith, a shield for a guild, a gift for a chest still shut and a sword for a boss still to beat.
    The world map showed only the world, so the area you're in stayed yours to explore, until 0.5.1 drew
    every land on it as it looks (below, One continent); a dark land still shows only where you've seen.
- **Selling products:** Logistics Trading Officers in the three capitals pay more for products than ordinary
  shops.

## Languages

FO started in Taiwan in 2003, in Traditional Chinese, and ran in English from 2007 (above). Which other
languages it was published in isn't in any source reachable from a cloud session.

**Us** (since 0.3.46): eleven languages, asked for in playtesting (2026-10-05): English, Spanish,
Portuguese (Brazil), French, German, Italian, Russian, Japanese, Korean, Simplified Chinese and
Traditional Chinese (Taiwan usage, as a nod to FO's home). Everything is translated, the changelog
included; the translations were made with AI and haven't had a native speaker's review yet.

## Design questions on our side

- Monster skills with an element but physical damage (Golden Spin, Vine Whip, Web Shot, Rock Throw) ignore
  their element. FO lets physical attacks carry one (Arms fusion).
- Boss lairs (2026-10-23, maps.json `lair`): no source says how FO staged its field bosses, so their lairs
  follow what similar games do (a place of its own round the boss, a way in marked by braziers, a warning on
  the approach, something tall to find it by), not FO. Our own design. 2026-10-24 (playtesting: a sign
  post and an empty space, the boss in the open): each stands where a boss would, as RuneScape's do (the
  Kalphite Queen and the Giant Mole underground, the King Black Dragon past the Wilderness's edge, Barrows'
  crypts on a mound): at its land's far edge or on the coast at a trail's end, on a hilltop, or in a cave;
  ringed by its land's own scenery (`lairRing`: dead trees round the wolf's den, a stone circle on the
  wolf leader's peak, pillars round a ruin), its way in lined with what tells its story (`lairApproach`:
  felled stumps to the angry oak, bones to the wolf, a drunk dragon's barrels), a warning where its
  trail starts (`lairSign`).
- Finishing `new_friend` lets you walk to all 30 maps (frog_swamp → goldburg_lake → goldburg), so the other
  quest gates can be walked round.

## Roadmap

Each step is its own PR, after a pass over the ToM wiki:
1. The six attributes with points per level, race spreads, hit and dodge from DEX and LUK, and skill speed.
2. FO's nine classes (three per guild), then the advanced classes at level 60. Recovery, Revive and Bless move
   to the Acolyte of Light.
3. Pet modes, intimacy, MP upkeep and the Arms/Armor/Magic/Soul fusions.
4. Capture capsules by level tier and pet shops; a home capital per race, with its guild hall there.
5. Work skills feeding the smith; dolls (titles since 0.3.61, cards since 0.3.69).

## Sources

Read through search-engine snippets on 2026-10-03:
- LagerNet wiki (fairyland.lagernet.com/wiki):
  - [Pet System](http://fairyland.lagernet.com/wiki/index.php/Pet_System)
  - [Pet List](http://fairyland.lagernet.com/wiki/index.php/Pet_List)
  - [Pet Toys](http://fairyland.lagernet.com/wiki/index.php/Pet_Toys)
  - [Pet Carts](http://fairyland.lagernet.com/wiki/index.php/Pet_Carts)
  - [Dark pets](http://fairyland.lagernet.com/wiki/index.php/Dark_pets)
  - [Puppet](http://fairyland.lagernet.com/wiki/index.php/Puppet)
  - [World Map](http://fairyland.lagernet.com/wiki/index.php/World_Map)
  - [Mining](http://fairyland.lagernet.com/wiki/index.php/Mining)
  - [Skill Penalty Priority](http://fairyland.lagernet.com/wiki/index.php/Skill_Penalty_Priority)
- The whole old wiki was archived by WikiTeam: [Internet Archive](https://archive.org/details/wiki-fairylandlagernetcom_wiki).
- Silent Gaming FairyLand info site:
  - [background story](https://info.fairyland.online/?pg=bgstory)
  - [titles](https://info.fairyland.online/?pg=titles)
  - [work skills](https://info.fairyland.online/?pg=work&sub=mining)
- Ironwolves guild guides:
  - [classes](https://wmomusic.org/fl1/Ironwolves2020/Html_Pages/characterclass.php)
  - [new players](https://wmomusic.org/fl1/Ironwolves2020/Html_Pages/newplayers.php)
  - [intro to pets](https://wmomusic.org/fl1/Ironwolves2020/Html_Pages/introtopets.php)
  - [blademan](https://wmomusic.org/fl1/Ironwolves2020/Guides/bladesmanguide.php)
  - [mage](https://www.wmomusic.org/fl1/Ironwolves2020/Guides/mageguide.php)
  - [beastmaster](https://wmomusic.org/fl1/Ironwolves2020/Guides/oldbeastmasterguide.php)
  - [trader](https://wmomusic.org/fl1/Ironwolves2020/Guides/oldtraderguide.php)
- Fairyland Fansite: [Diviner skills](http://flguide.blogspot.com/2007/11/diviner-skills.html)
- Ironwolves [Diviner skill list](https://wmomusic.org/fl1/Ironwolves2020/Skill_Pages/skills-diviner.php) (Curse and Poison, read 2026-10-04)
- Overviews and reviews:
  - [MMORPG.com](https://www.mmorpg.com/fairyland-online)
  - [MMO Reviews](https://www.mmoreviews.com/fairyland-online/)
  - [MMO Game Base](http://mmogamebase.blogspot.com/2011/03/fairyland-online.html)
  - [Free Web Game 360](https://freewebgame360.blogspot.com/2013/07/fairyland-online-review.html)
  - [HexMojo](https://www.hexmojo.com/2019/09/a-walk-down-memory-lane-with-fairyland.html)
- Tales of Mysteria:
  - [sign-up page](https://fairyland.lagernet.com/register)
  - [wiki](https://talesofmysteria.com/wiki)
  - [2026 rebirth video](https://www.youtube.com/watch?v=4Fy55bf7a9w)
- [Fairyland Journey on Steam](https://store.steampowered.com/app/4144910/Fairyland_Journey/) (a different game)
