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

**Us** (since 0.3.50): the game is called **Storyleaf** for players (the App Store name, the logo and
every in-game line); the code, project and repo keep "Fairyland". The goddess Liora binds the world's tales
into one book, and its pages are the land. Names taken from FO were replaced with our own, and this file
keeps the FO names when it describes the original:

| FO name | Ours |
|---|---|
| Rainbow City, Bluebird, Goldburg (and Goldburg Lake) | Prismhaven, Larkspur, Ingothold (Ingothold Lake) |
| Northern Grassland, Slime Cave, Candy Mountain, Puppet Hill | Windswept Downs, Gooey Grotto, Gumdrop Peaks, Marionette Rise |
| Sleepy Town, Secret Plain, Hachoo Island, Rosen Lake | Dozywick, Hidden Steppe, Sneezle Isle, Briarmere |
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

**Us:** 30 maps and 4 towns (Meadowbrook, Prismhaven, Larkspur, Ingothold).
- Towns are planned from maps.json `town` (streets, a plaza, terraces, shops along the streets, street
  furniture) plus hand-placed `buildings`; scenery only grows inside a town's fence with a `within` radius.
  Since 0.3.65 the planner keeps each townsperson's spot and the cells just in front of it clear, so no
  house, lamp or tree hides them (before, every town's healer and shop stood inside or behind a house), and
  Larkspur, which had felt empty in playtesting (2026-10-07), has two rings of streets like the others.
- Everyone starts in Meadowbrook, and all three guild masters are there.
- Travel: you walk between maps; your checkpoint is the last town you entered (since 0.3.54; before, the
  last map, which could leave you fainting at the edge of a zone too hard for you, over and over). You wake
  up there after fainting. Mages learn Bridge of Light (Lv 20, 10 MP) to go back to it, and since 0.3.53
  anyone can buy a Homeward Feather (50 gold, every town shop) that does the same once; since 0.3.54 won
  fights drop one now and then (8%), and a beaten boss always does. How FO itself moved players between towns isn't in any source reachable
  from a cloud session (2026-10-05); this is our own design.
- Fairy-tale fields echo the lands: Genie Desert, Lotus Land (with Thumbelina), Gumdrop Peaks, Snow White
  Forest, Emerald Road.
- Gumdrop Peaks is our nod to the Candy House land (Hansel and Gretel's Grasha Village): a sugar path,
  chocolate ponds, lollipops, cotton-candy trees and presents (palette swaps), and candy canes, gumdrops,
  cupcakes and gingerbread houses. Other fields nod to their lands too: flying carpets and genie lamps in
  the Genie Desert (1001 Nights), poppy fields on Emerald Road (Wizard of Oz), giant ladybugs in Lotus Land
  (Thumbelina), and apples in the Snow White Forest.
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
- One equipment drop in three is a trinket (gloves, necklace, boots or accessory), any up to the monster's
  level (`GameSession.accessoryShare`): there are only a few of each next to dozens of weapons and armours, so
  by level alone they'd hardly drop.
- Turn order: your side goes first, in the order its moves were chosen, as players locking in their commands
  would. You go when you chose (how far into the time to choose), each friend (a bot) at a random moment of
  its own, every companion right after whoever it came with. Then the monsters, shuffled every round and
  weighted by SPD (each draws u^(1/SPD), the highest first; twice the SPD goes first two rounds in three).
  Our decision, 2026-10-10, at the playtester's request; before that the whole field was shuffled by SPD
  (2026-10-09), and before that it was SPD + a random 0–3.
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
    ATK +20% and SPD +30%). Raises grow with the skill's level like damage, ×1.8 when mastered.
  - Monsters and companions: Boost (ATK +20%; golden hamsters, wood hogs, blaze bulls, earth lions) and Berserk
    (ATK +30% but DEF −25%; werewolves, fire bears, black kongs), FO's pet skills. They cast them on
    themselves now and then; friends cast theirs on whoever they'd help most.
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

**Us:** monsters drop wood, metal, hide and gems, and three town smiths forge weapons from them. There's no
gathering and no crafting level, and forging always works. Monsters also drop equipment from up to their own
level (6% a monster at your level, up to 16% above it, 2% well below; rares 35%, bosses always), mostly for
your class (`GameSession.equipmentDrop`).

## Titles, fame and PvP

- **Titles (H):** collectable, e.g. Rose Queen, War Hero, PK Master, crafting maestros, seasonal and
  anniversary titles.
- **Dolls (H):** collectable too.
- **Fame (M):** quests are the main way to earn it.
- **Kingdom Wars (H):** guild-vs-guild PvP.

**Us:** titles, but no fame. 35 titles (content/titles.json, our own names) are earned for levels, lands
visited, the Monster Book, monster cards, quests, bosses, companions, friends, rebirths, daily bounties and
days played, and one is worn over your name; computer-run adventurers wear the level titles that fit them.
Duels are with computer-run adventurers in 9 danger zones; a beaten adventurer drops everything they carry
(the goods they'd sell you that day). The red-named troublemakers only pick a fight with a side about as
strong as theirs or weaker: their level plus their companion's at least nine tenths of yours, your companion's
and your party's (`GameSession.dares`; our decision, 2026-10-11, at the playtester's request). Bosses never
start a fight: you talk to them. Quests pay at least a bit more than a daily bounty for your level when
you hand them in (`quests` in content/rewards.json; our decision, 2026-10-06, at the playtester's request).

**Cards (since 0.3.69):** FO's card collection, our own way, since no source we could reach says what FO's
cards did. Every monster has one. A beaten monster leaves its card 3% of the time (rare 15%, boss 25%;
`cards` in content/rewards.json). The first of each goes in the Monster Book and raises a stat for good, by
element: Fire and Metal attack, Dark magic, Earth defence, Water speed, Wood HP, Light MP. It gives a step, and
another for every 25 levels of where the monster lives, twice that for a rare card and three times for a
boss's. The whole set adds about +107 ATK, +127 MAG, +44 DEF, +27 SPD, +375 HP and +154 MP. Spares sell on the
spot. Tilly the Toymaker in Prismhaven has five quests for 5 to 100 kinds of card, paid in toys, and three
titles count cards. FO's dolls aren't in yet.

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
- **Level cap 200; rebirth from level 101** (+5 levels per earlier rebirth) for 20,000 gold × (rebirths + 1),
  keeping 8 levels of growth per rebirth, plus a fifth more battle EXP for each rebirth (up to double), the
  rebirth titles and a new colour for the hero's name. FO does have rebirth (the 2026 video); the numbers are ours.
- **Capture rules:** at 20% HP or less, on the last monster standing. Ours until 0.3.65; since 0.3.66 any
  monster at any HP, the odds best below 20% (see Pets).
- **Party size:** more than two people, each bringing their pet, from a playtester's memory (2026-10-04).
  Not found in any source reachable from a cloud session.
  - Us: you and up to four friends, each with a companion.
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
  - Us (since 0.3.44): `Sky` multiplies each map by the hour's light (warm at dawn and dusk, deep blue from
    about 19:30 to 04:30) and fades the sun's flare and sunbeams with it. Weather (`Weather`) changes every
    6 in-game hours, picked from the map's `ambience.weather` weights: clear, cloudy, rain, storm, fog, snow.
    Caves have neither. The battle backdrop is the map without the sky.
  - Us (since 0.3.65, asked for in playtesting 2026-10-07): night was too long at twelve real minutes, and
    showers lasted their whole six-minute spell. By day an in-game hour is still a real minute; from 18hr to
    6hr the clock runs at `GameClock.nightPace` (1.5×), so night takes eight minutes of a twenty-minute day.
    Rain and storms stop after a real minute and leave the rest of their spell cloudy. Settings has a switch
    for each (asked for the same day): with night and day off the light stays at midday, the HUD shows the
    sun and there are no dawn or dusk notices (the calendar still runs); with the weather off it's always
    clear. A debug `weather=` still wins, for screenshots.
  - Our setting is called Storyleaf in every in-game text (Fairyland until 0.3.50; see Names). In FO the
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
  - The minimap shows everyone else on the map as dots (since 0.3.55, asked for in playtesting 2026-10-06):
    blue adventurers, white friends, red hostile ones, green party friends; on dark maps only on cells you've
    seen. Whether FO's minimap showed other players isn't in any source reachable from a cloud session.
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
- Finishing `new_friend` lets you walk to all 30 maps (frog_swamp → goldburg_lake → goldburg), so the other
  quest gates can be walked round.
- No gear above level 105, while levels run to 200.

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
