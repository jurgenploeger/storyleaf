#!/usr/bin/env python3
"""Checks content/*.json and art/assets.json for broken references, without Xcode.

The Swift tests (StoryleafTests) check the same things, but they need a Mac. This runs
anywhere with Python 3 — handy from a cloud session or a phone — so a push that Xcode Cloud
will build doesn't fail on a typo in the game data.

    python3 tools/check_content.py
"""

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
errors: list[str] = []


def load(path: str) -> dict:
    def no_duplicates(pairs):
        # A key twice in one object is easy to miss after a merge, and only one of them counts.
        keys = [key for key, _ in pairs]
        for key in {key for key in keys if keys.count(key) > 1}:
            errors.append(f"{path}: \"{key}\" appears twice in one object ({dict(pairs).get('id', '?')})")
        return dict(pairs)
    try:
        return json.loads((ROOT / path).read_text(), object_pairs_hook=no_duplicates)
    except json.JSONDecodeError as error:
        sys.exit(f"{path}: invalid JSON ({error})")


def check(condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)


classes = load("content/classes.json")
skills = {s["id"]: s for s in load("content/skills.json")["skills"]}
# The stats spells raise and lower in battle (BattleStat in Storyleaf/Battle/BattleEngine.swift).
BATTLE_STATS = {"attack", "defense", "magic", "speed"}
monsters = {m["id"]: m for m in load("content/monsters.json")["monsters"]}
items = {i["id"]: i for i in load("content/items.json")["items"]}
quests = {q["id"]: q for q in load("content/quests.json")["quests"]}
maps_file = load("content/maps.json")
maps = {m["id"]: m for m in maps_file["maps"]}
music = load("content/music.json")
songs = {s["id"] for s in music["songs"]}
instruments = {i["id"]: i for i in music.get("instruments", [])}
appearance = load("content/appearance.json")
art = {a["id"]: a for a in load("art/assets.json")["assets"]}
npcs = {n["id"]: n for m in maps.values() for n in m.get("npcs", [])}

# Icons are the GameIcon cases: what tools/icons.py put in the asset catalog (Iconaut's and our own).
icon_names = {path.name.removeprefix("icon-").removesuffix(".imageset")
              for path in (ROOT / "Storyleaf/Resources/Assets.xcassets/Icons").glob("icon-*.imageset")
              if not path.name.endswith("-16.imageset")}

for cls in classes["classes"]:
    for unlock in cls["skills"]:
        check(unlock["skill"] in skills, f"class {cls['id']} → unknown skill {unlock['skill']}")
gender_ids = {g["id"] for g in appearance.get("genders", [])}
check(bool(gender_ids), "appearance.json needs a genders list")
for race in classes["races"]:
    check(race.get("art", "player_walk") in art, f"race {race['id']} → unknown art {race.get('art')}")
    for gender, sheet in (race.get("sheets") or {}).items():
        check(gender in gender_ids, f"race {race['id']} → unknown gender {gender}")
        check(sheet in art, f"race {race['id']} ({gender}) → unknown art {sheet}")
# Every style fits every race and gender; a sheet's own hair (a gender's) is the one it starts with.
shared = {style["id"] for style in appearance["styles"] if not style.get("sheet")}
every_style = sorted(style["id"] for style in appearance["styles"])
own_style = {style["sheet"]: style["id"] for style in appearance["styles"] if style.get("sheet")}
hero_sheets = {race.get("art", "player_walk") for race in classes["races"]} | {
    sheet for race in classes["races"] for sheet in (race.get("sheets") or {}).values()}
for style in appearance["styles"]:
    if style.get("sheet"):
        check(style["sheet"] in hero_sheets, f"hairstyle {style['id']} → sheet {style['sheet']} isn't a race's walk sheet")
check(len(own_style) == sum(1 for style in appearance["styles"] if style.get("sheet")),
      "appearance styles → one style of its own per walk sheet at most")
for race in classes["races"]:
    check(race.get("hair") in shared, f"race {race['id']} → hairstyle {race.get('hair')} must be one anyone can wear")
    # The paper-doll layers the hero is stacked from (GameSession.layers): one set per walk sheet,
    # the race's own plus one for each gender with its own sheet.
    bodies = [(race["id"], race.get("art", "player_walk"))] + [
        (f"{race['id']}_{gender}", sheet) for gender, sheet in (race.get("sheets") or {}).items()]
    for body, sheet in bodies:
        layers = [f"body_{body}", f"locks_{body}", f"hood_{body}", f"helmet_{body}"] + [f"hair_{style}_{body}" for style in every_style]
        for layer in layers:
            check((ROOT / "art" / "sprites" / f"{layer}.png").exists(),
                  f"race {race['id']} → art/sprites/{layer}.png is missing (python3 tools/hero_layers.py)")

for monster in monsters.values():
    for drop in monster.get("drops", []):
        check(drop.get("item") in items and 0 < drop.get("chance", 0) <= 1,
              f"monster {monster['id']} → drop {drop} needs a known item and a chance in (0, 1]")

for skill in skills.values():
    check(skill.get("icon") in icon_names, f"skill {skill['id']} → unknown icon {skill.get('icon')}")
    if skill.get("art"):
        check(skill["art"] in art, f"skill {skill['id']} → unknown art {skill['art']}")
        check((ROOT / "art" / "sprites" / f"{skill['art']}.png").exists(),
              f"skill {skill['id']} → art/sprites/{skill['art']}.png is missing (python3 tools/skill_art.py)")
    check(skill["kind"] in ("physical", "magic", "heal", "revive", "buff", "curse", "field"),
          f"skill {skill['id']} → unknown kind {skill['kind']}")
    # Poison and curses: what a skill leaves on the foes it reaches.
    inflicts = skill.get("inflicts")
    if skill["kind"] == "curse":
        check(inflicts is not None, f"skill {skill['id']} → a curse needs `inflicts` (what it leaves on its target)")
    if inflicts is not None:
        where = f"skill {skill['id']} → inflicts"
        check(isinstance(inflicts, dict) and set(inflicts) <= {"effect", "rounds", "power", "chance", "stats"}, f"{where} has unknown keys")
        effect = inflicts.get("effect") if isinstance(inflicts, dict) else None
        check(effect in ("poison", "curse", "freeze"), f"{where} → effect must be poison, curse or freeze")
        if isinstance(inflicts, dict):
            check(isinstance(inflicts.get("rounds"), int) and 1 <= inflicts["rounds"] <= 6, f"{where} → rounds must be 1 to 6")
            top = 2 if effect == "poison" else 0.5   # a curse never takes more than half (BattleEngine.maxCurse)
            power = inflicts.get("power")
            if effect == "freeze":   # a frozen turn is lost whole: there's nothing to scale
                check(power == 0, f"{where} → a freeze's power must be 0")
            else:
                check(isinstance(power, (int, float)) and 0 < power <= top, f"{where} → power must be above 0 and at most {top}")
            chance = inflicts.get("chance", 1)
            check(isinstance(chance, (int, float)) and 0 < chance <= 1, f"{where} → chance must be in (0, 1]")
            if "stats" in inflicts:
                stats = inflicts["stats"]
                check(effect == "curse", f"{where} → only a curse lowers `stats`")
                check(isinstance(stats, list) and stats and set(stats) <= BATTLE_STATS,
                      f"{where} → stats must be some of {sorted(BATTLE_STATS)}")
        check(skill["kind"] in ("physical", "magic", "curse") and skill["target"] in ("enemy", "allEnemies"),
              f"{where} → only skills aimed at foes leave a poison or curse")
    # Buffs: the stats they raise (and any they lower in return) for a few rounds (BattleEngine.statChanges).
    where = f"skill {skill['id']}"
    if skill["kind"] == "buff":
        raises = skill.get("raises")
        check(isinstance(raises, dict) and raises, f"{where} → a buff needs `raises` (stat → share, 0.25 = +25%)")
        for key, changes in (("raises", raises), ("lowers", skill.get("lowers"))):
            if changes is None:
                continue
            check(isinstance(changes, dict) and set(changes) <= BATTLE_STATS, f"{where} → {key} must name some of {sorted(BATTLE_STATS)}")
            if isinstance(changes, dict):
                for stat, amount in changes.items():
                    check(isinstance(amount, (int, float)) and 0 < amount <= (1 if key == "raises" else 0.5),
                          f"{where} → {key} {stat} must be above 0 and at most {1 if key == 'raises' else 0.5}")
        if isinstance(raises, dict) and isinstance(skill.get("lowers"), dict):
            check(not set(raises) & set(skill["lowers"]), f"{where} → raises and lowers the same stat")
        rounds = skill.get("rounds", 3)
        check(isinstance(rounds, int) and 1 <= rounds <= 6, f"{where} → rounds must be 1 to 6")
        check(skill["target"] in ("ally", "allAllies"), f"{where} → a buff is for your own side (ally or allAllies)")
    else:
        check(not {"raises", "lowers", "rounds"} & set(skill), f"{where} → only buffs have raises, lowers or rounds")

# Every skill used in battle looks like no other (a playtest rule): its own `animation`, one the
# scene knows (BattleScene.castSkill and SkillEffects in Storyleaf/Battle).
ANIMATIONS = {
    "slash", "smash", "whirlwind", "fire", "embers", "stone", "mud", "boulder", "leaves", "vine", "water", "bubbles", "frost",
    "wild", "roar", "needles", "web", "bounce", "bite", "shadow_bite", "venom_bite", "gold_spin", "gust", "flash",
    "curse", "glare", "poison", "mist", "first_aid", "heart", "paw", "rain", "revive",
    "bless", "shield", "glow", "ward", "spur", "boost", "rage",
}
seen = {}
for skill in skills.values():
    if skill["kind"] == "field":
        continue
    animation = skill.get("animation")
    check(animation in ANIMATIONS, f"skill {skill['id']} → animation must be one the battle draws: {animation}")
    if animation in seen:
        check(False, f"skill {skill['id']} → animation {animation} is {seen[animation]}'s already: every skill needs its own look")
    seen.setdefault(animation, skill["id"])

for monster in monsters.values():
    check(monster["art"] in art, f"monster {monster['id']} → unknown art {monster['art']}")
    check(isinstance(monster.get("lore"), str) and monster["lore"].strip(), f"monster {monster['id']} needs lore for the Monster Book")
    for skill in monster["skills"]:
        check(skill in skills, f"monster {monster['id']} → unknown skill {skill}")
    if "variantOf" in monster:
        check(monster["variantOf"] in monsters, f"monster {monster['id']} → unknown base {monster['variantOf']}")

materials = {i["id"]: i for i in items.values() if i["type"] == "material"}
for item in items.values():
    check(item.get("icon") in icon_names, f"item {item['id']} → unknown icon {item.get('icon')}")
    if item.get("capture"):
        # Seal Stones: thrown in battle, used up either way (BattleEngine.captureStatus).
        check(item["type"] == "consumable", f"seal stone {item['id']} → must be a consumable")
        power = item.get("sealPower", 1)
        check(isinstance(power, (int, float)) and 1 <= power <= 5, f"seal stone {item['id']} → sealPower between 1 and 5")
    else:
        check("sealPower" not in item and "sure" not in item, f"item {item['id']} → only Seal Stones (capture) have sealPower or sure")
    if item.get("toy"):
        # Companion toys raise a companion's stats for good (GameSession.giveToy).
        check(item["type"] == "consumable", f"toy {item['id']} → must be a consumable")
        check(isinstance(item.get("stats"), dict) and any(v > 0 for v in item["stats"].values()),
              f"toy {item['id']} → needs the stats it raises")
    if item["type"] == "material":
        check(item.get("material") in ("wood", "metal", "gem", "hide", "quest"), f"material {item['id']} → unknown kind {item.get('material')}")
        check(isinstance(item.get("level"), int), f"material {item['id']} needs a level (when monsters start dropping it)")
    for material, count in (item.get("recipe") or {}).items():
        check(material in materials, f"recipe for {item['id']} → {material} isn't a material")
        check(isinstance(count, int) and count > 0, f"recipe for {item['id']} → bad count {count} of {material}")
        if material in materials:
            # Every ingredient has to be droppable by monsters no stronger than the item's own level.
            check(materials[material]["level"] <= max(item.get("level", 1), 1),
                  f"recipe for {item['id']} (Lv {item.get('level', 1)}) → {material} only drops from Lv {materials[material]['level']}")

# Made by hand from the bag (items.json `make`): a quest's piece, from its recipe.
for item in items.values():
    if "make" in item:
        check(item["make"] in ("carve", "join"), f"item {item['id']} → make is carve or join")
        check(bool(item.get("recipe")), f"item {item['id']} → made by hand from what? (needs a recipe)")
        check(item.get("material") == "quest", f"item {item['id']} → only a quest's piece is made by hand")

# Where a quest's pieces come from: its monsters (`drops`), a chest it opens, a shop, a boss, the
# monsters' own materials, or made by hand from those.
quest_drops = {drop["item"] for quest in quests.values() for drop in quest.get("drops", [])}
chest_gifts = {npc.get("gives") for npc in npcs.values() if npc["role"] == "chest"}
in_shops = {item for npc in npcs.values() for item in npc.get("stock", [])}
monster_drops = {drop["item"] for monster in monsters.values() for drop in monster.get("drops", [])}


def obtainable(item_id, depth=0):
    item = items.get(item_id)
    if item is None:
        return False
    if item_id in quest_drops | chest_gifts | in_shops | monster_drops:
        return True
    if item["type"] == "material" and item.get("material") in ("wood", "metal", "gem", "hide"):
        return True
    return depth < 2 and "make" in item and all(obtainable(part, depth + 1) for part in item.get("recipe", {}))


wanted = set()
for quest in quests.values():
    check(quest["giver"] in npcs, f"quest {quest['id']} → unknown giver {quest['giver']}")
    objective = quest["objective"]
    check(objective["type"] in ("defeat", "capture", "reachLevel", "chooseClass", "collect", "hatch", "cards", "bring", "deliver"),
          f"quest {quest['id']} → unknown objective type {objective['type']}")
    check(quest.get("difficulty", 1) in (1, 2, 3, 4), f"quest {quest['id']} → difficulty 1 (easy) to 4 (elite)")
    if objective["type"] == "deliver":
        # A favour for someone else (`GameSession.deliver`): something handed to you when you
        # accept, taken to someone you can talk to, and maybe something of theirs brought back.
        where = f"quest {quest['id']}"
        target = npcs.get(objective.get("target"))
        check(target is not None and target["role"] not in ("chest", "stairs", "waystone", "boss"),
              f"{where} → deliver to whom? {objective.get('target')} isn't someone you can talk to")
        check(objective.get("target") != quest["giver"], f"{where} → a favour is for someone other than the one who asks")
        check(objective.get("item") in items and objective.get("item") in quest.get("starterItems", []),
              f"{where} → what it takes ({objective.get('item')}) is handed over when you accept (starterItems)")
        check("returns" not in objective or objective["returns"] in items, f"{where} → unknown item {objective.get('returns')}")
        check("count" not in objective, f"{where} → a favour is done once (no count)")
        wanted |= {objective.get("item"), objective.get("returns")} - {None}
    if objective["type"] == "bring":
        # Something in the bag, handed over: there has to be a way to get it.
        target = objective.get("target")
        check(target in items, f"quest {quest['id']} → bring what? unknown item {target}")
        check(isinstance(objective.get("count"), int) and objective["count"] >= 1, f"quest {quest['id']} → bring how many?")
        check(obtainable(target), f"quest {quest['id']} → nothing gives {target} (a quest's drops, a chest, a shop, or made by hand)")
        wanted |= {target} | set(items.get(target, {}).get("recipe", {}))
    for drop in quest.get("drops", []):
        where = f"quest {quest['id']} drop {drop.get('item')}"
        check(drop.get("item") in items, f"{where} → unknown item")
        check(objective["type"] == "bring" and drop.get("item") in {objective.get("target")} | set(items.get(objective.get("target"), {}).get("recipe", {})),
              f"{where} → a quest's monsters only drop what it asks you to bring, or a piece of it")
        check(isinstance(drop.get("chance"), (int, float)) and 0 < drop["chance"] <= 1, f"{where} → chance between 0 and 1")
        check("upTo" not in drop or (isinstance(drop["upTo"], int) and drop["upTo"] >= 1), f"{where} → upTo is a count")
        for species in drop.get("from", []):
            check(species in monsters, f"{where} → unknown monster {species}")
            check(any(species in (m.get("encounters") or {}).get("monsters", {}) for m in maps_file["maps"]),
                  f"{where} → {species} isn't met on any map")
        check(bool(drop.get("from")), f"{where} → dropped by whom?")
    if objective["type"] == "defeat" and objective.get("target"):
        check(objective["target"] in monsters, f"quest {quest['id']} → unknown monster {objective['target']}")
    if objective["type"] == "cards":
        # Kinds of monster card in the Book: there are only as many as there are monsters.
        check(isinstance(objective.get("count"), int) and 0 < objective["count"] <= len(monsters),
              f"quest {quest['id']} → a cards quest needs a count between 1 and {len(monsters)}")
    for answer in (quest.get("question") or {}).get("answers", []):
        check(answer["egg"] in monsters, f"quest {quest['id']} → unknown egg {answer['egg']}")
    for item in quest["reward"].get("items", []) + quest.get("starterItems", []):
        check(item in items, f"quest {quest['id']} → unknown item {item}")
    for required in quest.get("requires", []):
        check(required in quests, f"quest {quest['id']} → unknown quest {required}")
for npc in npcs.values():
    if npc["role"] == "chest" and npc.get("quest"):
        check(npc["quest"] in quests, f"chest {npc['id']} → unknown quest {npc['quest']}")
        if npc.get("gives") in items and items[npc["gives"]].get("material") == "quest":
            wanted.add(npc["gives"])
for item in items.values():
    if item.get("material") == "quest":
        check(item["id"] in wanted, f"item {item['id']} → a quest's piece no quest asks for")
        check(item.get("price", 0) == 0, f"item {item['id']} → a quest's piece isn't for sale (price 0)")

# The top level (GameSession.levelCap) is as high as anyone climbs: there's no rebirth, so it has gear
# of its own to show for it, a piece for every slot but the cape (capes are the weaver's) and a weapon
# for every guild.
LEVEL_CAP = 200
top = [item for item in items.values() if item.get("level") == LEVEL_CAP]
for slot in ("weapon", "armor", "gloves", "boots", "necklace", "accessory"):
    check(any(item["type"] == slot for item in top), f"level {LEVEL_CAP} → no {slot} for a hero at the top level")
for cls in classes["classes"]:
    if cls["id"] != "novice":
        check(any(item["type"] == "weapon" and cls["id"] in item.get("classes", []) for item in top),
              f"level {LEVEL_CAP} → no weapon for the {cls['id']} guild")
check(all(item.get("level", 1) <= LEVEL_CAP for item in items.values()), f"items → none above level {LEVEL_CAP}")

# Armour tiers (items.json `tier`, RuneScape-style): every tier a full set (a fighter's plate, a
# mage's robe, a tamer's hide cloak, gauntlets and boots) of one level and one colour, every tier's
# colour its own, so the colour tells the level.
tiers = {}
for item in items.values():
    if "tier" in item:
        tiers.setdefault(item["tier"], []).append(item)
for tier, set_ in tiers.items():
    kinds = sorted((i["type"], tuple(i.get("classes", []))) for i in set_)
    check(kinds == sorted([("armor", ("fighter",)), ("armor", ("mage",)), ("armor", ("tamer",)), ("boots", ()), ("gloves", ()),
                           ("head", ("fighter",)), ("head", ("mage",)), ("head", ("tamer",))]),
          f"armour tier {tier} → needs a fighter's, a mage's and a tamer's armour and hat, gauntlets and boots (has {kinds})")
    check(len({i.get("level") for i in set_}) == 1 and len({i.get("color") for i in set_}) == 1,
          f"armour tier {tier} → every piece the same level and colour")
colours = [set_[0].get("color") for set_ in tiers.values()]
check(len(colours) == len(set(colours)), "armour tiers → each tier a colour of its own")

# Quest treasures (Content.questGiving): gear a quest gives that no shop sells. Only that quest gives
# it (no boss drops it, no smith forges it, no other quest), and you can wear it the moment it's yours.
GEAR = {"weapon", "armor", "gloves", "boots", "necklace", "accessory"}
stocked = {item for npc in npcs.values() for item in npc.get("stock", [])}
givers = {}
for quest in quests.values():
    for item in set(quest["reward"].get("items", [])):
        if item in items and items[item]["type"] in GEAR and item not in stocked:
            givers.setdefault(item, []).append(quest["id"])
boss_drops = {drop["item"] for monster in monsters.values() for drop in monster.get("drops", [])}
for item, given_by in givers.items():
    check(len(given_by) == 1, f"quest treasure {item} → given by more than one quest: {', '.join(sorted(given_by))}")
    check(item not in boss_drops, f"quest treasure {item} → a boss drops it too")
    check("recipe" not in items[item], f"quest treasure {item} → a smith forges it too")
    quest = quests[given_by[0]]
    check(items[item].get("level", 1) <= quest.get("minLevel", 1),
          f"quest treasure {item} (Lv {items[item].get('level', 1)}) → above its quest {quest['id']}'s level {quest.get('minLevel', 1)}")

# Chest treasures (Content.chestHolding): gear a chest holds that no shop sells. Like a quest's,
# only that chest has it: no other chest, no quest, no monster's drop and no smith.
quest_rewards = {item for quest in quests.values() for item in quest["reward"].get("items", [])}
# An armour's hat (`headpiece`) is had wherever the armour is: in the same shops, from the same
# monsters at the same chance, from the same quests.
for armour in (i for i in items.values() if "headpiece" in i):
    hat = armour["headpiece"]
    for npc in npcs.values():
        stock = npc.get("stock", [])
        check((armour["id"] in stock) == (hat in stock), f"npc {npc['id']} → sells {armour['id']} and {hat} together")
    for monster in monsters.values():
        chances = {d["item"]: d.get("chance") for d in monster.get("drops") or []}
        check(chances.get(armour["id"]) == chances.get(hat), f"monster {monster['id']} → drops {armour['id']} and {hat} alike")
    for quest in quests.values():
        given = quest["reward"].get("items", [])
        check((armour["id"] in given) == (hat in given), f"quest {quest['id']} → gives {armour['id']} and {hat} together")
holders = {}
# The lands where a road or trail crosses one of the continent's rivers (a bridge, for the "bridge"
# landmark below).
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import world_layout  # noqa: E402
bridged_lands = world_layout.bridged_lands({i: m for i, m in maps.items() if "cave" not in m["theme"]}, load("content/world.json"))

for map_def in maps_file["maps"]:
    for npc in map_def.get("npcs", []):
        item = npc.get("gives")
        if npc["role"] == "chest" and item in items and items[item]["type"] in GEAR and item not in stocked:
            holders.setdefault(item, []).append(npc["id"])
for item, held_by in holders.items():
    check(len(held_by) == 1, f"chest treasure {item} → in more than one chest: {', '.join(sorted(held_by))}")
    check(item not in quest_rewards, f"chest treasure {item} → a quest gives it too")
    check(item not in boss_drops, f"chest treasure {item} → a monster drops it too")
    check("recipe" not in items[item], f"chest treasure {item} → a smith forges it too")

check(maps_file["start"] in maps, f"start map {maps_file['start']} doesn't exist")
opposite = {"north": "south", "south": "north", "east": "west", "west": "east"}
world_roads = load("content/world.json").get("roads", {})


def back_side(map_def, exit):
    """The side the road back from `exit`'s map leaves by: the other side from the one it left by,
    but where a road leads into a cave's mouth inland, the cave's leaves by the other side from the
    way you walk in (world.json `into`, playtesting 2026-10-16: inside you come in on the side you
    walked in from), and the land's by any (it names the side the mouth is toward)."""
    into = world_roads.get(map_def["id"], {}).get(exit["to"], {}).get("into")
    if into:
        return opposite[into]
    if world_roads.get(exit["to"], {}).get(map_def["id"], {}).get("into"):
        return None
    return opposite[exit["edge"]]


for map_def in maps.values():
    edges = [exit["edge"] for exit in map_def["exits"]]
    check(len(edges) == len(set(edges)), f"map {map_def['id']} has two exits on one edge")
    for exit in map_def["exits"]:
        destination = maps.get(exit["to"])
        check(destination is not None, f"map {map_def['id']} → unknown map {exit['to']}")
        if destination:
            side = back_side(map_def, exit)
            back = any(e["to"] == map_def["id"] and side in (None, e["edge"]) for e in destination["exits"])
            check(back, f"map {exit['to']} has no {side or ''} exit back to {map_def['id']}".replace("  ", " "))
        if "requires" in exit:
            check(exit["requires"] in quests, f"map {map_def['id']} road → unknown quest {exit['requires']}")
        if "ship" in exit:
            # By ship from a harbor to a land over the sea and back (`WorldMap.harbor`).
            check(exit["ship"] is True, f"map {map_def['id']} exit to {exit['to']}: ship is true or left out")
            check(destination is not None and "cave" not in destination["theme"] and "cave" not in map_def["theme"],
                  f"map {map_def['id']} exit to {exit['to']}: a ship sails between two lands, never a cave")
            check(destination is None or any(e["to"] == map_def["id"] and e.get("ship") for e in destination["exits"]),
                  f"map {exit['to']} has no ship back to {map_def['id']}")
            check(destination is None or not any(e["to"] == map_def["id"] and e.get("requires") for e in destination["exits"]) or "requires" not in exit,
                  f"map {map_def['id']} exit to {exit['to']}: a quest can ready the ship one way, never both, or you'd be stranded")
    for monster in (map_def.get("encounters") or {}).get("monsters", {}):
        check(monster in monsters, f"map {map_def['id']} → unknown monster {monster}")
    if map_def.get("music"):
        check(map_def["music"] in songs, f"map {map_def['id']} → unknown song {map_def['music']}")
    if map_def.get("battleMusic"):
        check(map_def["battleMusic"] in songs, f"map {map_def['id']} → unknown battle song {map_def['battleMusic']}")
    theme = map_def["theme"]
    town = map_def.get("town") or {}
    # The quest that charts a dark map (`MapDef.chart`): its minimap shows all of it once that's done.
    if "chart" in map_def:
        check(map_def["chart"] in quests, f"map {map_def['id']} → chart: unknown quest {map_def['chart']}")
        check(bool((map_def.get("ambience") or {}).get("darkness")), f"map {map_def['id']} → only a dark map has a chart (it shows all of it once)")
    # A cave's level under it (`MapDef.depth`): reached only by stairs, from the level over it.
    if "depth" in map_def:
        depth = map_def["depth"]
        check(isinstance(depth, int) and not isinstance(depth, bool) and depth >= 1 and "cave" in theme,
              f"map {map_def['id']} → depth is a cave level's, 1 or more")
        check(not map_def["exits"], f"map {map_def['id']} → a cave's deeper level has no roads out, only stairs")
        check(any(n["role"] == "stairs" and (maps.get(n.get("to")) or {}).get("depth", 0) == depth - 1 for n in map_def.get("npcs", [])),
              f"map {map_def['id']} → no stairs up to the level over it")
    if map_def.get("fence") is True:
        # A town's walled square (`WorldMap.townSquare`), its countryside painted round it on the continent.
        size = town.get("size")
        check(isinstance(size, list) and len(size) == 2 and all(isinstance(v, int) and v >= 20 for v in size),
              f"map {map_def['id']} town → size must be [width, height] of its walled square, 20 or more each")
        check(town.get("walls") in (None, "stone"), f"map {map_def['id']} town → walls must be \"stone\" (a city's) or left out (a fence)")
    tiles = [theme["ground"], theme["path"]] + [theme[k] for k in ("accent", "border", "water") if theme.get(k)]
    if "cave" in theme:
        cave = theme["cave"]
        where = f"map {map_def['id']} cave"
        check(set(cave) <= {"rock", "height", "width", "chambers", "branches", "zigzags", "maze"}, f"{where} → unknown keys {set(cave) - {'rock', 'height', 'width', 'chambers', 'branches', 'zigzags', 'maze'}}")
        check("rock" in cave, f"{where} → needs a rock tile")
        tiles.append(cave.get("rock", ""))
        check(isinstance(cave.get("height", 40), (int, float)) and 10 <= cave.get("height", 40) <= 120, f"{where} → height must be 10 to 120")
        check(isinstance(cave.get("width", 3), (int, float)) and 0.5 <= cave.get("width", 3) <= 8, f"{where} → width must be 0.5 to 8")
        for key in ("chambers", "branches", "zigzags"):
            check(isinstance(cave.get(key, 0), int) and 0 <= cave.get(key, 0) <= 40, f"{where} → {key} must be a whole number from 0 to 40")
        check(isinstance(cave.get("maze", 8), int) and 4 <= cave.get("maze", 8) <= 30, f"{where} → maze must be a junction spacing from 4 to 30")
        check(map_def["width"] >= 24 and map_def["height"] >= 24, f"{where} → cave maps must be at least 24×24")
    if "hills" in theme:
        hills = theme["hills"]
        where = f"map {map_def['id']} hills"
        known = {"count", "size", "chain", "height", "mountains", "rocky", "bank"}
        check(set(hills) <= known, f"{where} → unknown keys {set(hills) - known}")
        check(not map_def.get("town") and "cave" not in theme, f"{where} → only out in the fields (not towns or caves)")
        check(isinstance(hills.get("count"), int) and 1 <= hills["count"] <= 20, f"{where} → count must be a whole number from 1 to 20")
        size = hills.get("size", [3, 6])
        check(isinstance(size, list) and len(size) == 2 and all(isinstance(v, int) for v in size) and 2 <= size[0] <= size[1] <= 12,
              f"{where} → size must be [smallest, biggest] radius in cells, 2 to 12")
        check(isinstance(hills.get("height", 70), (int, float)) and 16 <= hills.get("height", 70) <= 100, f"{where} → height must be 16 to 100 points")
        check(isinstance(hills.get("rocky", 0), (int, float)) and 0 <= hills.get("rocky", 0) <= 1, f"{where} → rocky must be 0 to 1")
        chain = hills.get("chain", [2, 4])
        check(isinstance(chain, list) and len(chain) == 2 and all(isinstance(v, int) for v in chain) and 1 <= chain[0] <= chain[1] <= 6,
              f"{where} → chain must be [fewest, most] summits a range, 1 to 6")
        if "mountains" in hills:
            mountains = hills["mountains"]
            check(isinstance(mountains, dict) and set(mountains) == {"count", "height"}, f"{where} → mountains must be {{count, height}}")
            if isinstance(mountains, dict):
                check(isinstance(mountains.get("count"), int) and 1 <= mountains.get("count", 0) <= 4, f"{where} → mountains count must be 1 to 4")
                height = mountains.get("height")
                check(isinstance(height, (int, float)) and max(100, hills.get("height", 70)) < height <= 300,
                      f"{where} → a mountain's height must be over the hills' and over 100, up to 300 points")
        if "bank" in hills:
            tiles.append(hills["bank"])
    if "lakes" in theme:
        lakes = theme["lakes"]
        where = f"map {map_def['id']} lakes"
        check(isinstance(lakes, dict) and set(lakes) <= {"count", "size", "islands"}, f"{where} → must be {{count, size, islands}}")
        check(not map_def.get("town") and "cave" not in theme, f"{where} → only out in the fields (not towns or caves)")
        check("water" in theme, f"{where} → needs the map's water tile")
        check(isinstance(lakes.get("count"), int) and 1 <= lakes.get("count", 0) <= 4, f"{where} → count must be 1 to 4")
        size = lakes.get("size")
        check(isinstance(size, list) and len(size) == 2 and all(isinstance(v, (int, float)) for v in size) and 5 <= size[0] <= size[1] <= 24,
              f"{where} → size must be [smallest, biggest] reach in cells, 5 to 24")
        islands = lakes.get("islands", 0)
        check(isinstance(islands, int) and 0 <= islands <= lakes.get("count", 0), f"{where} → islands must be 0 to count")
    if "roadside" in theme:
        # What lines stretches of the roads (`LandPlanner.planRoadsides`).
        lines = theme["roadside"]
        where = f"map {map_def['id']} roadside"
        check("cave" not in theme, f"{where} → not in a cave")
        check(isinstance(lines, list) and len(lines) > 0, f"{where} → must be a list of what lines the roads")
        own = {p["art"] for p in theme["props"]}
        for line in lines if isinstance(lines, list) else []:
            if not isinstance(line, dict):
                check(False, f"{where} → each must be {{kind, art, every, weight}}")
                continue
            check(set(line) <= {"kind", "art", "every", "weight"}, f"{where} → unknown keys {set(line) - {'kind', 'art', 'every', 'weight'}}")
            kind = line.get("kind")
            check(kind in ("fence", "wall", "row"), f"{where} → kind must be fence, wall or row, not {kind}")
            if kind == "row":
                check(line.get("art") in own, f"{where} → a row's art must be one of the map's own props, not {line.get('art')}")
                every = line.get("every", 1)
                check(isinstance(every, int) and not isinstance(every, bool) and 1 <= every <= 8, f"{where} → every must be 1 to 8 cells")
            else:
                check("art" not in line and "every" not in line, f"{where} → only a row has art and every")
            weight = line.get("weight", 1)
            check(isinstance(weight, (int, float)) and not isinstance(weight, bool) and weight > 0, f"{where} → weight must be over 0")
    props = [p["art"] for p in theme["props"]] + town.get("lots", []) + list(town.get("streetDecor", {}))
    props += [b["art"] for b in map_def.get("buildings", [])] + [d["art"] for d in map_def.get("decor", [])]
    for art_id in tiles + props:
        check(art_id in art, f"map {map_def['id']} → unknown art {art_id}")
    for npc in map_def.get("npcs", []):
        check(npc["art"] in art, f"npc {npc['id']} → unknown art {npc['art']}")
        # A boss's lair (LandPlanner.planLair): pieces round it, its way in to the south kept clear.
        if "lair" in npc:
            where = f"npc {npc['id']} lair"
            check(npc["role"] == "boss", f"{where} → only a boss has a lair")
            for piece in npc["lair"]:
                check(set(piece) <= {"art", "x", "y", "blocking"} and piece.get("art") in art,
                      f"{where} → a piece is art (known), x, y and maybe blocking: {piece}")
                x, y = piece.get("x"), piece.get("y")
                check(isinstance(x, int) and isinstance(y, int) and max(abs(x), abs(y)) <= 7 and (x, y) != (0, 0),
                      f"{where} → {piece.get('art')} at {x}, {y}: within 7 cells of the boss, not on it")
                check(not (x == 0 and -4 <= y < 0) or piece.get("blocking") is False,
                      f"{where} → {piece.get('art')} at {x}, {y} blocks the way in (straight south of the boss)")
        check(npc["role"] in ("healer", "shop", "quests", "guild", "chest", "boss", "smith", "weaver", "stairs", "barber", "waystone"), f"npc {npc['id']} → unknown role {npc['role']}")
        # A waystone (`NPCRole.waystone`): out in a wild land on the continent (you arrive in front of
        # it, `WorldMap.waystoneArrival`), one to a land, woken by a quest someone in that land gives.
        if npc["role"] == "waystone":
            where = f"waystone {npc['id']}"
            quest = quests.get(npc.get("quest"))
            check(quest is not None, f"{where} → unknown quest {npc.get('quest')}")
            check(not map_def.get("fence") and "cave" not in theme, f"{where} → waystones stand in wild lands, not towns or caves")
            check(sum(1 for n in map_def.get("npcs", []) if n["role"] == "waystone") == 1, f"{where} → one waystone to a land")
            check(npc["id"] not in maps, f"{where} → its id is a map's too (travel tells them apart by id)")
            if quest is not None:
                check(any(n["id"] == quest["giver"] for n in map_def.get("npcs", [])),
                      f"{where} → its quest's giver {quest['giver']} lives in another land")
        # A cave's stairs (`NPCRole.stairs`): one level down or up, to another level of the same cave,
        # and stairs there that lead back (you come out in front of them, `WorldMap.stairsArrival`).
        if npc["role"] == "stairs" or "to" in npc:
            where = f"stairs {npc['id']}"
            other = maps.get(npc.get("to"))
            check(npc["role"] == "stairs", f"npc {npc['id']} → only stairs lead somewhere (to)")
            check(other is not None, f"{where} → unknown map {npc.get('to')}")
            check("cave" in theme and other is not None and "cave" in other["theme"], f"{where} → stairs join two levels of a cave")
            if other is not None:
                check(abs(other.get("depth", 0) - map_def.get("depth", 0)) == 1, f"{where} → stairs go one level down or up (depth)")
                back = [n for n in other.get("npcs", []) if n["role"] == "stairs" and n.get("to") == map_def["id"]]
                check(len(back) == 1, f"{where} → {npc.get('to')} needs one stairs back to {map_def['id']}")
            check(sum(1 for n in map_def.get("npcs", []) if n.get("to") == npc.get("to")) == 1,
                  f"{where} → two stairs to {npc.get('to')}")
        for item in npc.get("stock", []):
            check(item in items, f"shop {npc['id']} → unknown item {item}")
        if npc["role"] == "chest":
            check(npc.get("gives") in items, f"chest {npc['id']} → unknown item {npc.get('gives')}")
        if npc["role"] == "boss":
            check(monsters.get(npc.get("monster"), {}).get("boss") is True, f"boss {npc['id']} → unknown boss {npc.get('monster')}")
            # Its minions come from the map's encounter table.
            if npc.get("minions", 9) > 0:
                check(bool((map_def.get("encounters") or {}).get("monsters")), f"boss {npc['id']} → minions need the map's encounters")
        if "minions" in npc:
            check(npc["role"] == "boss" and isinstance(npc["minions"], int) and 0 <= npc["minions"] <= 9,
                  f"npc {npc['id']} → minions is for bosses, 0 to 9")
        # A boss fight comes in waves (3 unless set): the map's monsters first, the boss last.
        if npc["role"] == "boss" and npc.get("waves", 3) > 1:
            check(bool((map_def.get("encounters") or {}).get("monsters")), f"boss {npc['id']} → waves need the map's encounters")
        if "waves" in npc:
            check(npc["role"] == "boss" and isinstance(npc["waves"], int) and 1 <= npc["waves"] <= 5,
                  f"npc {npc['id']} → waves is for bosses, 1 to 5")
        # What beating a boss means: told the first time you win, and kept in the Monster Book.
        if npc["role"] == "boss":
            check("victory" in npc, f"boss {npc['id']} → needs a victory story (title and story)")
        if "victory" in npc:
            victory = npc["victory"]
            where = f"npc {npc['id']} → victory"
            check(npc["role"] == "boss", f"{where} is for bosses")
            check(isinstance(victory, dict) and set(victory) <= {"title", "story"}, f"{where} has only a title and a story")
            title = victory.get("title") if isinstance(victory, dict) else None
            check(isinstance(title, str) and 0 < len(title.strip()) <= 32, f"{where} → title must be 1 to 32 characters")
            story = victory.get("story") if isinstance(victory, dict) else None
            check(isinstance(story, list) and 1 <= len(story) <= 3
                  and all(isinstance(p, str) and 0 < len(p.strip()) <= 220 for p in story),
                  f"{where} → story must be 1 to 3 paragraphs of up to 220 characters (it fits one card)")

    # Up on a summit (WorldMap.summits, the tallest first): only where hills are raised, and a
    # summit past the first only where there are that many mountains.
    hills = theme.get("hills")
    tall = (hills or {}).get("mountains", {}).get("count", 0) if hills else 0
    for thing in map_def.get("npcs", []) + map_def.get("decor", []):
        if "summit" not in thing:
            continue
        name = thing.get("id", thing.get("art"))
        summit = thing["summit"]
        check(isinstance(summit, int) and summit >= 0, f"map {map_def['id']} → {name}'s summit must be a whole number from 0")
        check(bool(hills) and "town" not in map_def and "cave" not in theme,
              f"map {map_def['id']} → {name} stands on a summit, but no hills are raised there")
        if isinstance(summit, int) and summit > 0:
            check(summit < tall, f"map {map_def['id']} → {name} stands on summit {summit}, but there are only {tall} mountains")

    # The people who live here (MapDef.Local): a look from appearance.json, a home and maybe an errand
    # (MapDef.Place) by a landmark the map has, on a summit or out from the middle, and a story.
    place_keys = {"at", "which", "summit", "x", "y"}
    local_keys = {"name", "race", "gender", "hair", "outfit", "skin", "style", "walk", "roam", "face", "pet", "hold", "wear",
                  "props", "lines"} | place_keys
    lakes = theme.get("lakes") or {}
    landmarks = {
        "jetty": bool(lakes),
        "shore": bool(lakes),
        "island": lakes.get("islands", 0) > 0,
        "bridge": map_def["id"] in bridged_lands,
        "mouth": any("cave" in (maps.get(exit["to"]) or {}).get("theme", {}) for exit in map_def["exits"]) and "cave" not in theme,
        "harbor": any(exit.get("ship") for exit in map_def["exits"]),
    }
    for npc in map_def.get("npcs", []):
        if "at" in npc:
            check(landmarks.get(npc["at"]) is True, f"npc {npc['id']} → at a {npc['at']} the map {map_def['id']} hasn't got")
            check("summit" not in npc, f"npc {npc['id']} → at a landmark or on a summit, not both")
    for local in map_def.get("locals", []):
        where = f"map {map_def['id']} local {local.get('name', '?')}"
        check(set(local) <= local_keys, f"{where} → unknown keys {set(local) - local_keys}")
        check(isinstance(local.get("name"), str) and 0 < len(local["name"].strip()) <= 24, f"{where} → name must be 1 to 24 characters")
        lines = local.get("lines")
        check(isinstance(lines, list) and 1 <= len(lines) <= 8 and all(isinstance(l, str) and 0 < len(l.strip()) <= 80 for l in lines),
              f"{where} → lines must be 1 to 8 lines of up to 80 characters (a speech bubble)")
        check("race" not in local or local["race"] in {r["id"] for r in classes["races"]}, f"{where} → unknown race {local.get('race')}")
        check("gender" not in local or local["gender"] in gender_ids, f"{where} → unknown gender {local.get('gender')}")
        for key, kind in (("hair", "hair"), ("outfit", "outfits"), ("skin", "skin"), ("style", "styles")):
            check(key not in local or local[key] in {o["id"] for o in appearance[kind]}, f"{where} → unknown {key} {local.get(key)}")
        check(isinstance(local.get("roam", 0), int) and 0 <= local.get("roam", 0) <= 12, f"{where} → roam must be 0 to 12 cells")
        check(local.get("face", "down") in ("up", "down", "left", "right"), f"{where} → face must be up, down, left or right")
        check("pet" not in local or local["pet"] in monsters, f"{where} → unknown pet {local.get('pet')}")
        # In hand and worn: everyday gear, never a treasure that's yours alone.
        for key, kind in (("hold", "weapon"), ("wear", "armor")):
            if key in local:
                item = local[key]
                check(items.get(item, {}).get("type") == kind, f"{where} → {key} must be a {kind} from items.json, not {item}")
                check(item not in givers and item not in holders, f"{where} → {item} is a treasure, not for a local to {key}")
        for prop in local.get("props", []):
            check(prop.get("art") in art and isinstance(prop.get("x"), int) and isinstance(prop.get("y"), int)
                  and max(abs(prop.get("x", 0)), abs(prop.get("y", 0))) <= 4,
                  f"{where} → props need known art and x, y within 4 steps of home")
        for spot, label in ((local, "home"), (local.get("walk"), "walk")):
            if spot is None:
                continue
            check(isinstance(spot, dict) and (label == "home" or set(spot) <= place_keys), f"{where} → {label} must be a place {place_keys}")
            if not isinstance(spot, dict):
                continue
            if "at" in spot:
                check(landmarks.get(spot["at"]) is True,
                      f"{where} → {label} is at a {spot['at']}, which the map hasn't (jetty, shore, island, bridge or mouth)")
                check("summit" not in spot, f"{where} → {label} is at a landmark or on a summit, not both")
            if "summit" in spot:
                check(spot["summit"] == 0 or (isinstance(spot["summit"], int) and 0 < spot["summit"] < tall),
                      f"{where} → {label} is on summit {spot['summit']}, but there are only {tall} mountains")
                check(bool(hills) and "town" not in map_def and "cave" not in theme, f"{where} → {label} is on a summit, but no hills are raised there")
# Every monster can be met somewhere: on a map's encounter table, or standing there as a boss.
met = {monster for m in maps.values() for monster in (m.get("encounters") or {}).get("monsters", {})}
# Climate (maps.json `climate`): the snowy north is cold, the desert south-east hot, the rest mild.
# Frost and snow monsters live only where it's cold (playtesting 2026-10-16: a frost-maned lion
# roamed the desert steppe, frost puffs a tropical beach).
for m in maps.values():
    check(m.get("climate") in (None, "cold", "hot"), f"map {m['id']} climate → cold or hot (or none, for a mild land)")
    for species in (m.get("encounters") or {}).get("monsters", {}):
        name = monsters.get(species, {}).get("name", "")
        if re.search(r"\b(frost|frosted|snow|snowman|ice|icy)\b", name, re.I):
            check(m.get("climate") == "cold", f"map {m['id']} → {name} lives only where it's cold (climate cold)")
met |= {npc["monster"] for npc in npcs.values() if npc["role"] == "boss" and npc.get("monster")}
for monster_id in monsters:
    check(monster_id in met, f"monster {monster_id} → on no map's encounter table and not a boss, so it can never be met")

for item in items.values():
    if item.get("art"):
        check(item["art"] in art, f"item {item['id']} → unknown art {item['art']}")
        check((ROOT / "art" / "sprites" / f"{item['art']}.png").exists() or "derive" in art.get(item["art"], {}),
              f"item {item['id']} → art/sprites/{item['art']}.png is missing (python3 tools/item_art.py)")

ITEM_TYPES = {"consumable", "weapon", "armor", "head", "gloves", "necklace", "boots", "accessory", "material", "cape"}
for item in items.values():
    check(item["type"] in ITEM_TYPES, f"item {item['id']} → unknown type {item['type']!r} ({sorted(ITEM_TYPES)})")
# Gloves, boots and necklaces show on the hero (GearOverlay.trinkets) in their `color`; a necklace's
# chain is its `accent`.
HEX = re.compile(r"#[0-9A-Fa-f]{6}")
for item in items.values():
    if item["type"] in ("gloves", "boots", "necklace"):
        check(isinstance(item.get("color"), str) and HEX.fullmatch(item["color"]) is not None,
              f"item {item['id']} → color must be #RRGGBB: how the {item['type']} look when worn")
        check(item.get("accent") is None or HEX.fullmatch(item["accent"]) is not None,
              f"item {item['id']} → accent must be #RRGGBB")

# Festive hats (type head) are drawn on the hero's head (GearOverlay.hat) as their `hat` in their
# `color` (bunny ears pink inside, their `accent`); no one buys or sells one (the seasons give them).
HATS = {"crown", "santa", "ears", "mask"}
# The hats that go with an armour (items.json `headgear`: what that armour drew on the head before it
# went to the hat slot, playtesting 2026-10-21): the cut-off head of its sheets (art/sprites/
# hat_<kind>_<race>.png, tools/wear_art.py BARE_HEADED) or a hide cloak's hood (hood_<body>.png, in the
# hat's `color`). Each armour names its own (`headpiece`), of its level, classes, tier and colour
# variant, given wherever the armour is, and the two together are worth what the armour was.
HEADGEAR = {f"{kind}" for kind in ("chain_mail", "iron_plate", "dragon_mail", "mage_robe", "ranger_cloak", "snow_cloak")}
# Hats cut from a sheet drawn only for its hat (wear_art.py HAT_ONLY), worn with a hide cloak, which has
# no sheet of its own: each its own colour by its `tint` (the cloak is drawn in its `color`).
CLOAK_HEADGEAR = {"hide_hood"}
races_ids = [r["id"] for r in classes["races"]]
for item in items.values():
    if item["type"] == "head" and "headgear" in item:
        kind = item["headgear"]
        check(kind in HEADGEAR | CLOAK_HEADGEAR | {"hood"}, f"item {item['id']} → headgear must be one of {sorted(HEADGEAR | CLOAK_HEADGEAR | {'hood'})}")
        if kind in HEADGEAR | CLOAK_HEADGEAR:
            for race_id in races_ids:
                check((ROOT / "art" / "sprites" / f"hat_{kind}_{race_id}.png").exists(),
                      f"item {item['id']} → art/sprites/hat_{kind}_{race_id}.png is missing (tools/wear_art.py)")
        check(isinstance(item.get("color"), str) and HEX.fullmatch(item["color"]) is not None,
              f"item {item['id']} → color must be #RRGGBB: its icon's colour (and a hood's on the hero)")
        check("hat" not in item, f"item {item['id']} → a hat that goes with an armour has headgear, not a festive hat")
        owners = [a for a in items.values() if a.get("headpiece") == item["id"]]
        check(len(owners) == 1, f"item {item['id']} → exactly one armour names it as its headpiece (has {len(owners)})")
        for armour in owners:
            check(all(item.get(k) == armour.get(k) for k in ("level", "classes", "tier") + (("tint",) if kind in HEADGEAR else ())),
                  f"item {item['id']} → the same level, classes, tier and tint as {armour['id']}")
            wears = (list(armour.get("sheets", {}).values()) or [""])[0]
            check(wears.startswith(f"armor_{kind}_") if kind in HEADGEAR else (not armour.get("sheets") and armour.get("wear") == "cloak"),
                  f"item {item['id']} → its headgear {kind!r} isn't what {armour['id']} wears")
    elif item["type"] == "head":
        check(item.get("hat") in HATS, f"item {item['id']} → hat must be one of {sorted(HATS)}: how it's drawn on the head")
        check((ROOT / "art" / "sprites" / f"wear_{item.get('hat')}.png").exists(),
              f"item {item['id']} → art/sprites/wear_{item.get('hat')}.png is missing (tools/wear_art.py cuts it out)")
        check(isinstance(item.get("color"), str) and HEX.fullmatch(item["color"]) is not None,
              f"item {item['id']} → color must be #RRGGBB: the hat's colour on the hero")
        check(item.get("price") == 0, f"item {item['id']} → price 0 (only the festive seasons give hats)")
    else:
        check("hat" not in item, f"item {item['id']} → only a hat (type head) has a hat")
    if "headpiece" in item:
        hat = items.get(item["headpiece"], {})
        check(item["type"] == "armor" and hat.get("type") == "head" and "headgear" in hat,
              f"item {item['id']} → headpiece {item['headpiece']!r} must be a hat with headgear")
        check(not item.get("sheets") or item.get("bareHead") is True,
              f"item {item['id']} → its sheets' head is its hat now: bareHead")
for item in items.values():
    # Any armour that still draws something on the head needs a hat for it instead.
    if item["type"] == "armor" and (item.get("sheets") or item.get("wear") in ("plate", "cloak")):
        check("headpiece" in item, f"item {item['id']} → it draws a helmet or hood: that's a hat item of its own (headpiece)")

# A festive scarf is a necklace that wears `scarf` (GearOverlay.scarf, art/sprites/wear_scarf.png).
WEARS = {"armor": {"vest", "mail", "plate", "robe", "cloak"}, "necklace": {"scarf"}}
# The sheets bareHead armour wears: their head is cut off (tools/wear_art.py BARE_HEADED).
bare_sheets = {sheet for i in items.values() if i.get("bareHead") for sheet in i.get("sheets", {}).values()}
for item in items.values():
    if item["type"] == "weapon":
        for view in ("side", "front"):
            check((ROOT / "art" / "sprites" / f"held_{item['id']}_{view}.png").exists(),
                  f"item {item['id']} → art/sprites/held_{item['id']}_{view}.png is missing (the weapon held: tools/item_art.py {item['id']})")
    if "wear" in item:
        check(item["wear"] in WEARS.get(item["type"], set()),
              f"item {item['id']} → wear {item['wear']!r} doesn't fit a {item['type']} ({sorted(WEARS.get(item['type'], []))})")
    if item.get("wear") == "scarf":
        check(item.get("price") == 0 and (ROOT / "art" / "sprites" / "wear_scarf.png").exists(),
              f"item {item['id']} → a festive scarf: price 0 (only the seasons give one) and art/sprites/wear_scarf.png")
    for race_id, sheet in item.get("sheets", {}).items():
        check(item["type"] == "armor" and race_id in {r["id"] for r in classes["races"]},
              f"item {item['id']} → sheets: {race_id!r} isn't a race (or the item isn't armour)")
        check((ROOT / "art" / "sprites" / f"{sheet}.png").exists(), f"item {item['id']} → art/sprites/{sheet}.png is missing")
    if item.get("bareHead") or any(sheet in bare_sheets for sheet in item.get("sheets", {}).values()):
        check(item.get("bareHead") is True and all(sheet in bare_sheets for sheet in item.get("sheets", {}).values()),
              f"item {item['id']} → wears a sheet with its head cut off along with a bareHead item: both need bareHead, "
              "or the hero walks about with no head")
    if item.get("bareHead"):
        # Its sheets have their head cut off (tools/wear_art.py BARE_HEADED): every body needs its
        # own head to draw over them.
        check(item["type"] == "armor" and "sheets" in item,
              f"item {item['id']} → bareHead is for armour with sheets of its own")
        for body in (p.stem[len("body_"):] for p in (ROOT / "art" / "sprites").glob("body_*.png") if not p.stem.endswith("_npc")):
            check((ROOT / "art" / "sprites" / f"head_{body}.png").exists(),
                  f"item {item['id']} → art/sprites/head_{body}.png is missing (tools/wear_art.py)")
    for rule in item.get("tint", []):
        check(("sheets" in item or item.get("headgear") not in (None, "hood")) and isinstance(rule.get("hue"), list) and len(rule["hue"]) == 2,
              f"item {item['id']} → tint rules need a hue: [from, to] (and the item needs sheets, or a hat their head)")
    if "pattern" in item:
        check((item["type"] == "armor" and item["pattern"] in {"engraved", "scales", "fur", "runes", "pockets"})
              or (item.get("headgear") == "hood" and item["pattern"] == "fur"),
              f"item {item['id']} → pattern {item['pattern']!r} must be engraved | scales | fur | runes | pockets, on armour (or fur on a hood)")
    if "glow" in item:
        check(item["type"] == "weapon" and re.fullmatch(r"#[0-9A-Fa-f]{6}", str(item["glow"])) is not None,
              f"item {item['id']} → glow must be a #RRGGBB colour on a weapon")
        at = item.get("glowAt")
        check(isinstance(at, list) and len(at) == 2 and all(isinstance(v, (int, float)) and 0 <= v <= 32 for v in at),
              f"item {item['id']} → glow needs glowAt: [x, y] inside its 32×32 art")
    if "accent" in item:
        check(isinstance(item["accent"], str) and re.fullmatch(r"#[0-9A-Fa-f]{6}", item["accent"]) is not None,
              f"item {item['id']} → accent must be #RRGGBB")

hex_colour = re.compile(r"^#[0-9A-Fa-f]{6}$")
for map_def in maps.values():
    for prop in map_def["theme"].get("props", []):
        check(prop["art"] in art, f"map {map_def['id']} prop → unknown art {prop['art']}")
        # Required by the app's PropPlacement: a missing one stops maps.json loading and crashes at launch.
        check(isinstance(prop.get("count"), int) and not isinstance(prop.get("count"), bool), f"map {map_def['id']} prop {prop['art']} → needs a whole-number count")
        check(isinstance(prop.get("blocking"), bool), f"map {map_def['id']} prop {prop['art']} → needs blocking: true or false")
        within = prop.get("within", 1)
        check(isinstance(within, int) and within > 0, f"map {map_def['id']} prop {prop['art']} → within must be a positive whole number")
        size = prop.get("size", [1, 1])
        check(isinstance(size, list) and len(size) == 2 and all(isinstance(v, (int, float)) and 0.2 <= v <= 3 for v in size) and size[0] <= size[1],
              f"map {map_def['id']} prop {prop['art']} → size must be [smallest, biggest] between 0.2 and 3")
        if "glow" in prop:
            check(bool(hex_colour.match(prop["glow"])), f"map {map_def['id']} prop {prop['art']} → glow must be a #RRGGBB colour")
        check(isinstance(prop.get("shadow", False), bool), f"map {map_def['id']} prop {prop['art']} → shadow must be true or false")
        for key in ("sway", "bob"):
            check(isinstance(prop.get(key, False), bool), f"map {map_def['id']} prop {prop['art']} → {key} must be true or false")
        spread = prop.get("spread", 1)
        check(isinstance(spread, int) and spread > 0, f"map {map_def['id']} prop {prop['art']} → spread must be a positive whole number")

rule_keys = {"hue", "minSaturation", "maxSaturation", "minValue", "maxValue", "to", "shift", "spread", "saturation", "value"}
def check_rules(rules, where):
    """Recolour rules (Recolor.swift): known keys, a hue window in degrees, and `spread` only with
    `to` and a window narrow enough to have a middle."""
    for rule in rules:
        check(set(rule) <= rule_keys, f"{where} → unknown recolor keys {set(rule) - rule_keys}")
        hue = rule.get("hue")
        check(hue is None or (isinstance(hue, list) and len(hue) == 2 and all(0 <= h <= 360 for h in hue)),
              f"{where} → hue must be [from, to] in degrees")
        check(not ("to" in rule and "shift" in rule), f"{where} → a rule sets the hue (to) or turns it (shift), not both")
        if "spread" in rule and hue:
            width = hue[1] - hue[0] if hue[0] <= hue[1] else hue[1] + 360 - hue[0]
            check("to" in rule and width <= 180 and -1.5 <= rule["spread"] <= 1.5,
                  f"{where} → spread needs `to`, a hue window up to 180 degrees wide and a value from -1.5 to 1.5")
        else:
            check("spread" not in rule, f"{where} → spread needs a hue window to find the middle of")

for map_def in maps.values():
    palette = map_def["theme"].get("palette")
    if not palette:
        continue
    where = f"map {map_def['id']} palette"
    palette_keys = {"recolor", "saturation", "shadow", "highlight", "tone", "glow", "light", "lightStrength", "variation"}
    check(set(palette) <= palette_keys, f"{where} → unknown keys {set(palette) - palette_keys}")
    for key in ("shadow", "highlight", "light"):
        if key in palette:
            check(bool(hex_colour.match(palette[key])), f"{where} → {key} must be a #RRGGBB colour")
    for key in ("saturation", "tone", "glow"):
        if key in palette:
            check(isinstance(palette[key], (int, float)) and 0 <= palette[key] <= 2, f"{where} → {key} must be between 0 and 2")
    for key in ("lightStrength", "variation"):
        if key in palette:
            check(isinstance(palette[key], (int, float)) and 0 <= palette[key] <= 1, f"{where} → {key} must be between 0 and 1")
    check_rules(palette.get("recolor", []), where)

# The kinds `Critters.make` (Storyleaf/World/Critters.swift) knows how to draw.
CRITTER_KINDS = {"bunny", "frog", "crab", "songbird", "chick", "squirrel", "lizard", "mouse",
                 "crow", "spider", "rat", "scorpion", "wisp"}
ambience_keys = {"particles", "butterflies", "critters", "birds", "clouds", "tint", "tintAlpha", "vignette", "lightPatches", "sunbeams", "sun", "haze", "hazeAlpha", "focus", "darkness", "weather"}
weather_kinds = {"clear", "cloudy", "rain", "storm", "fog", "snow"}
for map_def in maps.values():
    ambience = map_def.get("ambience") or {}
    where = f"map {map_def['id']} ambience"
    check(set(ambience) <= ambience_keys, f"{where} → unknown keys {set(ambience) - ambience_keys}")
    for key in ("tint", "sun", "haze"):
        if key in ambience:
            check(bool(hex_colour.match(ambience[key])), f"{where} → {key} must be a #RRGGBB colour")
    for key in ("lightPatches", "sunbeams"):
        if key in ambience:
            lights = ambience[key]
            check(bool(hex_colour.match(lights.get("color", ""))) and isinstance(lights.get("count"), int), f"{where} → {key} needs a colour and a count")
    for kind in (ambience.get("particles") or "").split("+") if ambience.get("particles") else []:
        check(kind in {"petals", "leaves", "fireflies", "sparkles", "snow", "dust", "motes", "bubbles", "dandelions", "sprinkles", "lanterns", "zzz", "notes"},
              f"{where} → unknown particles {kind}")
    # Required by the app's Ambience.Critter: a missing kind or count stops maps.json loading.
    for critter in ambience.get("critters", []):
        check(critter.get("kind") in CRITTER_KINDS, f"{where} critters → kind must be one of {sorted(CRITTER_KINDS)}: {critter.get('kind')}")
        count = critter.get("count")
        check(isinstance(count, int) and not isinstance(count, bool) and 1 <= count <= 30, f"{where} critters → count must be 1 to 30")
    if "birds" in ambience:
        check(ambience["birds"] in {"songbirds", "gulls", "bats"}, f"{where} → birds must be songbirds, gulls or bats")
    if "focus" in ambience:
        focus = ambience["focus"]
        check(set(focus) <= {"blur", "band", "near"}, f"{where} focus → unknown keys {set(focus) - {'blur', 'band', 'near'}}")
        check(0 <= focus.get("blur", 1.5) <= 6, f"{where} focus → blur should be 0...6 points")
        check(0 <= focus.get("band", 0.4) <= 0.9, f"{where} focus → band should be 0...0.9")
        check(0 <= focus.get("near", 0.5) <= 1, f"{where} focus → near should be 0...1")
    if "darkness" in ambience:
        dark = ambience["darkness"]
        check(set(dark) <= {"radius", "alpha", "color", "light"}, f"{where} darkness → unknown keys {set(dark) - {'radius', 'alpha', 'color', 'light'}}")
        check(80 <= dark.get("radius", 190) <= 500, f"{where} darkness → radius should be 80...500 points")
        check(0 < dark.get("alpha", 0.9) <= 1, f"{where} darkness → alpha should be above 0, up to 1")
        for key in ("color", "light"):
            if key in dark:
                check(bool(hex_colour.match(dark[key])), f"{where} darkness → {key} must be a #RRGGBB colour")
    if "weather" in ambience:
        weather = ambience["weather"]
        check(isinstance(weather, dict) and set(weather) <= weather_kinds,
              f"{where} weather → keys must be {', '.join(sorted(weather_kinds))}")
        check(all(isinstance(w, (int, float)) and not isinstance(w, bool) and w >= 0 for w in weather.values()),
              f"{where} weather → weights must be numbers, 0 or more")
        check(not weather or sum(weather.values()) > 0, f"{where} weather → some weight above 0 (or {{}} for no sky)")
        check(not (weather and "darkness" in ambience), f"{where} weather → a dark map has no sky")

for kind in ("hair", "outfits", "skin"):
    for preset in appearance[kind]:
        check_rules(preset["recolor"], f"look {preset['id']}")
        # Every look is open when a hero is made, the only time looks are chosen.
        check("unlock" not in preset, f"look {preset['id']} → looks can't be locked (they're only chosen at a new game)")
# The window hair colours widen to on the hero's hair and locks layers (GameSession.hairLayerRules).
window = appearance.get("hairLayer")
if window is not None:
    hue = window.get("hue")
    check(set(window) <= {"hue", "minSaturation", "maxSaturation", "minValue", "maxValue"},
          f"appearance hairLayer → only a window (hue, saturations, values): {set(window)}")
    check(hue is None or (isinstance(hue, list) and len(hue) == 2 and all(0 <= h <= 360 for h in hue)),
          "appearance hairLayer → hue must be [from, to] in degrees")
    check(all(0 <= window[k] <= 1 for k in window if k != "hue"), "appearance hairLayer → saturations and values are 0...1")

# Road routes: hubs, exit waypoints and trails stay inside the map (offsets from the centre, y north).
for map_def in maps.values():
    half_w, half_h = map_def["width"] // 2, map_def["height"] // 2
    def inside(point, what):
        ok = isinstance(point, list) and len(point) == 2 and abs(point[0]) <= half_w - 5 and abs(point[1]) <= half_h - 5
        check(ok, f"map {map_def['id']} {what} {point} should be [x, y] within {half_w - 5}×{half_h - 5} of the centre")
    if "hub" in map_def: inside(map_def["hub"], "hub")
    for exit in map_def["exits"]:
        for point in exit.get("via", []): inside(point, f"road to {exit['to']} waypoint")
        for key in ("at", "meets"):
            if key in exit:
                limit = (half_h if exit["edge"] in ("east", "west") else half_w) - 5
                check(isinstance(exit[key], int) and abs(exit[key]) <= limit,
                      f"map {map_def['id']} exit to {exit['to']}: {key} {exit[key]} is off the edge")
        if "meets" in exit:
            check("cave" not in (maps.get(exit["to"]) or {}).get("theme", {}),
                  f"map {map_def['id']} exit to {exit['to']}: a road into a cave meets no land (no `meets`)")
    for trail in map_def.get("trails", []):
        inside(trail.get("to"), "trail end")
        for point in trail.get("via", []) + ([trail["from"]] if "from" in trail else []): inside(point, "trail waypoint")

for asset in art.values():
    check(asset.get("faces", "left") in ("left", "right"), f"art {asset['id']} → faces must be left or right")
    if "derive" in asset:
        check(asset["derive"]["from"] in art, f"art {asset['id']} → unknown base {asset['derive']['from']}")
        check_rules(asset["derive"]["recolor"], f"art {asset['id']} derive")
        for layer in asset["derive"].get("layers", []):
            check(set(layer) <= {"id", "recolor"} and (ROOT / "art" / "sprites" / f"{layer.get('id')}.png").exists(),
                  f"art {asset['id']} → derive layer {layer.get('id')} isn't an art/sprites PNG (python3 tools/hero_layers.py)")
            check_rules(layer.get("recolor", []), f"art {asset['id']} derive layer {layer.get('id')}")
# Townsfolk drawn from a hero's walk sheet stack its paper-doll layers, the hair on a layer of its
# own: a palette swap of the whole sheet can't reach every shade of hair (orange tufts are left).
townsfolk_sheets = hero_sheets | {"dwarf_npc_walk"}
def derived_root(art_id, depth=0):
    base = (art.get(art_id, {}).get("derive") or {}).get("from")
    return art_id if not base or art_id in townsfolk_sheets or depth > 4 else derived_root(base, depth + 1)
for map_def in maps.values():
    for npc in map_def.get("npcs", []):
        derive = art.get(npc["art"], {}).get("derive") or {}
        root = derived_root(npc["art"])
        check(root not in townsfolk_sheets or (derive.get("from") == root and bool(derive.get("layers"))),
              f"npc {npc['id']} → art {npc['art']} recolours all of {root}: derive it from {root} with `layers`")
for item in items.values():
    check_rules((item.get("recolor") or []) + (item.get("tint") or []), f"item {item['id']}")

# Crowds and announcements: whole-number counts, and only placeholders the game fills in.
crowd = load("content/crowd.json")
check(0 <= crowd.get("botDensity", 1) <= 1, "crowd botDensity → between 0 and 1")
check(0 <= crowd.get("groupChance", 0) <= 1, "crowd groupChance → between 0 and 1")
size = crowd.get("groupSize", [2, 2])
check(isinstance(size, list) and len(size) == 2 and all(isinstance(n, int) for n in size) and 2 <= size[0] <= size[1] <= 5,
      "crowd groupSize → [fewest, most], whole numbers from 2 to 5 (a leader and up to four behind, like your party)")
check(0 < crowd.get("acceptChance", 0.75) <= 1, "crowd acceptChance → above 0 and at most 1 (how often an adventurer says yes to partying up)")
for key in ("stayMinutes", "groupMinutes"):
    span = crowd.get(key, [1, 1])
    check(isinstance(span, list) and len(span) == 2 and all(isinstance(n, (int, float)) for n in span) and 0 < span[0] <= span[1],
          f"crowd {key} → [fewest, most] minutes, above 0")
for line in crowd.get("traderLines", []):
    check(("{item}" in line) != ("{buy}" in line), f"crowd traderLines → \"{line}\" needs {{item}} or {{buy}} (one of them)")
    check(set(re.findall(r"\{(\w+)\}", line)) <= {"item", "buy", "price"}, f"crowd traderLines → unknown placeholder in \"{line}\"")
villager_placeholders = {"town", "healer"}
for line in crowd.get("villagerLines", []):
    check(set(re.findall(r"\{(\w+)\}", line)) <= villager_placeholders, f"crowd villagerLines → unknown placeholder in \"{line}\"")
for map_def in maps.values():
    for key, value in (map_def.get("crowd") or {}).items():
        if key == "villagerLines":
            # A town's own lines: about its own places and people, so towns with villagers only.
            check(isinstance(value, list) and all(isinstance(line, str) for line in value),
                  f"map {map_def['id']} crowd → villagerLines: a list of lines")
            check((map_def.get("crowd") or {}).get("villagers", 0) > 0, f"map {map_def['id']} crowd → villagerLines with no villagers to say them")
            for line in value if isinstance(value, list) else []:
                check(set(re.findall(r"\{(\w+)\}", str(line))) <= villager_placeholders, f"map {map_def['id']} crowd → unknown placeholder in \"{line}\"")
            continue
        check(key in ("adventurers", "villagers", "traders") and isinstance(value, int) and value >= 0,
              f"map {map_def['id']} crowd → {key}: {value} (adventurers, villagers or traders: a whole number)")
    if (map_def.get("crowd") or {}).get("traders"):
        check(map_def.get("fence") is True, f"map {map_def['id']} crowd → traders stand about a town's main square: towns only")
notices = load("content/announcements.json")
every = notices.get("every", [])
check(len(every) == 2 and 0 < every[0] <= every[1], "announcements every → [shortest, longest] real seconds")
for key in ("dawn", "dusk", "community"):
    check(bool(notices.get(key)), f"announcements → needs some {key} lines")
for map_id, lines in notices.get("arrival", {}).items():
    check(map_id in maps, f"announcements arrival → unknown map {map_id}")
    check(bool(lines), f"announcements arrival {map_id} → needs a line")
placeholders = {"dawn": set(), "dusk": set(), "bossNearby": {"boss", "map"},
                "community": {"bot", "level", "boss", "rare", "item", "map"}}
for key, allowed in placeholders.items():
    for line in notices.get(key, []):
        unknown = set(re.findall(r"\{(\w+)\}", line)) - allowed
        check(not unknown, f"announcements {key} → unknown placeholder {sorted(unknown)} in \"{line}\"")
sighting = notices.get("sighting")
if sighting:
    for field in ("text", "end", "minutes", "boost", "chance"):
        check(field in sighting, f"announcements sighting → needs {field}")
    check(0 <= sighting.get("chance", 0) <= 1, "announcements sighting chance → between 0 and 1")
    check(sighting.get("boost", 1) >= 1 and sighting.get("minutes", 1) >= 1, "announcements sighting → boost and minutes at least 1")

changelog = load("content/changelog.json")["releases"]
versions = [r["version"] for r in changelog]
check(len(versions) == len(set(versions)), "changelog → duplicate version")
for release in changelog:
    check(re.fullmatch(r"\d+\.\d+\.\d+", release["version"]) is not None, f"changelog {release['version']} → not x.y.z")
    check(re.fullmatch(r"\d{4}-\d{2}-\d{2}", release["date"]) is not None, f"changelog {release['version']} → date not YYYY-MM-DD")
    check(bool(release.get("title")) and bool(release.get("notes")), f"changelog {release['version']} → needs a title and notes")
    # What's new sums up each big update; small changes fold into the top entry instead of adding lines.
    check(len(release.get("notes", [])) <= 5, f"changelog {release['version']} → {len(release['notes'])} notes, at most 5: sum it up")
as_tuple = [tuple(int(n) for n in v.split(".")) for v in versions if re.fullmatch(r"\d+\.\d+\.\d+", v)]
check(as_tuple == sorted(as_tuple, reverse=True), "changelog → releases must be newest first")
marketing = re.search(r'MARKETING_VERSION:\s*"([^"]+)"', (ROOT / "project.yml").read_text())
check(bool(changelog) and marketing is not None and marketing.group(1) == versions[0],
      f"changelog top version {versions[0] if versions else None} ≠ MARKETING_VERSION {marketing.group(1) if marketing else None} in project.yml")
# Music: every track names a known instrument (or an old chiptune wave), and every note token parses.
NOTE_TOKEN = re.compile(r"^(-|[A-G][#b]?-?\d(\+[A-G][#b]?-?\d)*|[KSHTCRN](\+[KSHTCRN])*):\d+$")
for inst in instruments.values():
    for partial in inst.get("partials", []):
        check(len(partial) == 3, f"instrument {inst['id']}: partial {partial} needs [ratio, level, decay]")
    check(len(inst.get("partials", [])) <= 8, f"instrument {inst['id']}: at most 8 partials")
    check(len(inst.get("vibrato", [0, 0, 0])) == 3, f"instrument {inst['id']}: vibrato is [depth, rate, delay]")
for song in music["songs"]:
    for index, track in enumerate(song["tracks"]):
        where = f"song {song['id']} track {index}"
        if "instrument" in track:
            check(track["instrument"] in instruments, f"{where} → unknown instrument {track['instrument']}")
        else:
            check(track.get("wave") in ("square", "triangle", "noise"), f"{where}: needs an instrument or a wave")
        for token in track["notes"].split():
            if token != "|":
                check(bool(NOTE_TOKEN.match(token)), f"{where}: bad note {token}")
# A cave's road out comes back in where it left: the way out of a cave is the other side of the
# way in (`GameCoordinator`: you arrive through the edge opposite the one you left by).
OPPOSITE = {"east": "west", "west": "east", "north": "south", "south": "north"}
for map_def in maps.values():
    for exit_def in map_def["exits"]:
        back = [e for e in maps.get(exit_def["to"], {}).get("exits", []) if e["to"] == map_def["id"]]
        check(len(back) == 1, f"map {map_def['id']} → {exit_def['to']} has no single road back")
        if back and ("cave" in map_def["theme"] or "cave" in maps[exit_def["to"]]["theme"]):
            side = back_side(map_def, exit_def)
            check(side in (None, back[0]["edge"]),
                  f"map {map_def['id']} {exit_def['edge']} → {exit_def['to']}: its road back should leave by the {side}")
    edges = [e["edge"] for e in map_def["exits"]]
    check(len(edges) == len(set(edges)), f"map {map_def['id']} → two roads leave by the same side")

# The continent (content/world.json, tools/world_layout.py): every outdoor land has its shape, none
# overlap, a road crosses where the land it leads to takes it on, and what's set down by hand stands on its land.
outdoor = {i: m for i, m in maps.items() if "cave" not in m["theme"]}
errors += world_layout.verify(maps, outdoor, load("content/world.json"))

# Titles (content/titles.json): unique ids, a kind GameSession+Rewards knows, a count above 0 where
# one's needed (lands and book may leave it out: every one), and a boss's NPC id for `boss`.
TITLE_KINDS = {"level", "lands", "book", "quests", "bosses", "boss", "companions", "friends", "bounties", "days", "cards"}
titles = load("content/titles.json")["titles"]
check(len({t.get("id") for t in titles}) == len(titles), "titles → duplicate id")
for title in titles:
    # Its badge (TitleBadge): 1 bronze, 2 silver, 3 gold, 4 ruby, 5 prismatic.
    check(title.get("rank") in (1, 2, 3, 4, 5), f"title {title.get('id')} → rank must be 1 to 5 (its badge's metal)")
    where = f"title {title.get('id')}"
    kind = title.get("kind")
    check(bool(title.get("name")), f"{where} → needs a name")
    check(kind in TITLE_KINDS, f"{where} → unknown kind {kind} (one of {sorted(TITLE_KINDS)})")
    if kind == "boss":
        target = npcs.get(title.get("target"), {})
        check(target.get("role") == "boss", f"{where} → target must be a boss's NPC id, not {title.get('target')}")
    elif kind in ("lands", "book", "cards"):
        top = len(maps) if kind == "lands" else len(monsters)
        count = title.get("count")
        check(count is None or (isinstance(count, int) and 0 < count <= top), f"{where} → count between 1 and {top}, or none for every one")
    elif kind in TITLE_KINDS:
        check(isinstance(title.get("count"), int) and title["count"] > 0, f"{where} → needs a count above 0")

# Rewards (content/rewards.json): real items, whole positive numbers, the bounty kinds the game knows
# (Bounty.Kind), and the Book's milestones in order.
BOUNTY_KINDS = {"defeatOnMap", "defeatElement", "wins", "rare", "seal"}
rewards = load("content/rewards.json")
def check_items(ids, where):
    for item_id in ids or []:
        check(item_id in items, f"{where} → unknown item {item_id}")
check(bool(rewards.get("dailyGifts")), "rewards → needs dailyGifts")
for index, gift in enumerate(rewards.get("dailyGifts", []), start=1):
    check(gift.get("goldPerLevel", 0) >= 0 and (gift.get("goldPerLevel") or gift.get("items")), f"rewards daily gift {index} → needs gold or items")
    check_items(gift.get("items"), f"rewards daily gift {index}")
bounty_rules = rewards.get("bounties", {})
kinds = bounty_rules.get("kinds", {})
check(set(kinds) <= BOUNTY_KINDS, f"rewards bounties → unknown kinds {sorted(set(kinds) - BOUNTY_KINDS)}")
check(1 <= bounty_rules.get("perDay", 0) <= len(kinds), "rewards bounties perDay → between 1 and the number of kinds")
for kind, span in kinds.items():
    check(isinstance(span, list) and len(span) == 2 and 1 <= span[0] <= span[1], f"rewards bounties {kind} → [low, high] with 1 ≤ low ≤ high")
check(bounty_rules.get("exp", 0) > 0 and bounty_rules.get("goldPerLevel", -1) >= 0, "rewards bounties → exp above 0 and goldPerLevel at least 0")
check(bounty_rules.get("bonus", {}).get("exp", 0) > 0, "rewards bounties bonus → exp above 0")
check_items(bounty_rules.get("bonus", {}).get("items"), "rewards bounties bonus")
milestones = rewards.get("bookMilestones", [])
counts = [m.get("count", len(monsters)) for m in milestones]
check(counts == sorted(set(counts)), "rewards bookMilestones → counts rising, each once (the one without a count is every monster)")
check(all(0 < count <= len(monsters) for count in counts), f"rewards bookMilestones → counts between 1 and {len(monsters)}")
for milestone in milestones:
    check(milestone.get("gold", -1) >= 0, f"rewards bookMilestone {milestone.get('count', 'all')} → gold at least 0")
    check_items(milestone.get("items"), f"rewards bookMilestone {milestone.get('count', 'all')}")

# Status capes (rewards.json `prizes`, GameSession+Rewards.swift): each a cape the weaver alone gives
# (price 0, no shop, quest, chest, smith or monster has one), with a colour and a trim, for a milestone
# that can be met: a land's own monsters, or the whole world's. One weaver weaves them.
prizes = rewards.get("prizes", [])
PRIZE_KINDS = {"land", "book", "cards", "quests", "bosses", "lands", "companion", "capes"}
capes = {item_id for item_id, item in items.items() if item["type"] == "cape"}
prized = [prize.get("item") for prize in prizes]
check(len(prized) == len(set(prized)), "rewards prizes → a cape is the prize for one milestone only")
check(set(prized) == capes, f"rewards prizes → every cape is a prize and every prize a cape (capes not prizes: {sorted(capes - set(prized))}, "
                            f"prizes not capes: {sorted(set(prized) - capes)})")
for prize in prizes:
    where = f"rewards prize {prize.get('item')}"
    check(prize.get("kind") in PRIZE_KINDS, f"{where} → kind must be one of {sorted(PRIZE_KINDS)}")
    if prize.get("kind") == "land":
        land = maps.get(prize.get("land"), {})
        homes = set((land.get("encounters") or {}).get("monsters", {})) | {n["monster"] for n in land.get("npcs", []) if n["role"] == "boss" and n.get("monster")}
        check(bool(homes), f"{where} → land {prize.get('land')} has no monsters to beat")
    else:
        check("land" not in prize, f"{where} → only a land prize names a land")
    if prize.get("kind") == "companion":
        check(isinstance(prize.get("level"), int) and 1 < prize["level"] <= 200,
              f"{where} → a companion prize names the `level` to raise one to (2 to 200, the level cap)")
lands_prized = [prize.get("land") for prize in prizes if prize.get("kind") == "land"]
check(len(lands_prized) == len(set(lands_prized)), "rewards prizes → one cape a land")
elsewhere = stocked | quest_rewards | boss_drops | {npc.get("gives") for npc in npcs.values()}
for cape in capes:
    item = items[cape]
    check(item.get("price") == 0, f"cape {cape} → price 0 (the weaver gives it; no one buys or sells one)")
    check(cape not in elsewhere and "recipe" not in item, f"cape {cape} → only the weaver gives it (no shop, quest, chest, smith or drop)")
    for key in ("color", "accent"):
        check(isinstance(item.get(key), str) and re.fullmatch(r"#[0-9A-Fa-f]{6}", item[key]) is not None, f"cape {cape} → {key} must be #RRGGBB")
# Festive seasons (rewards.json `seasons`, like RuneScape's holiday events): each on its days ("MM-DD"
# to "MM-DD", round the new year when `to` comes first, or `easter`: days either side of Easter
# Sunday), never two at once; its `hats` hats (every hat a season's), its `treats` things to eat
# that heal; no shop, quest, chest, smith or monster has either.
import datetime


def easter_sunday(year):
    """Easter Sunday in the Gregorian calendar (the anonymous algorithm, as GameSession.easter)."""
    a, b, c = year % 19, year // 100, year % 100
    d, e = b // 4, b % 4
    f = (b + 8) // 25
    g = (b - f + 1) // 3
    h = (19 * a + b - d - g + 15) % 30
    i, k = c // 4, c % 4
    l = (32 + 2 * e + 2 * i - h - k) % 7
    m = (a + 11 * h + 22 * l) // 451
    month = (h + l - 7 * m + 114) // 31
    return datetime.date(year, month, (h + l - 7 * m + 114) % 31 + 1)


def month_day(text):
    try:
        month, day = (int(v) for v in str(text).split("-"))
        datetime.date(2024, month, day)
        return month, day
    except (ValueError, TypeError):
        return None


def in_season(season, date):
    if "easter" in season:
        first, last = season["easter"]
        return first <= (date - easter_sunday(date.year)).days <= last
    start, end, today = month_day(season["from"]), month_day(season["to"]), (date.month, date.day)
    return start <= today <= end if start <= end else today >= start or today <= end


seasons = rewards.get("seasons", [])
check(len({season.get("id") for season in seasons}) == len(seasons), "rewards seasons → each needs an id of its own")
hats_given, treats_given = set(), set()
for season in seasons:
    where = f"rewards season {season.get('id')}"
    if "easter" in season:
        days = season["easter"]
        check("from" not in season and "to" not in season and isinstance(days, list) and len(days) == 2
              and all(isinstance(v, int) for v in days) and -30 <= days[0] <= days[1] <= 60,
              f"{where} → easter must be [first, last] days from Easter Sunday (and no from or to)")
    else:
        check(month_day(season.get("from")) is not None and month_day(season.get("to")) is not None,
              f"{where} → from and to must be \"MM-DD\" days (or easter: [first, last])")
    for hat in season.get("hats", []):
        festive = items.get(hat, {})
        check(festive.get("type") == "head" or (festive.get("type") == "necklace" and festive.get("wear") == "scarf"),
              f"{where} → hat {hat} must be an item of type head (or a necklace that wears a scarf)")
    for treat in season.get("treats", []):
        item = items.get(treat, {})
        check(item.get("type") == "consumable" and ((item.get("heal") or 0) > 0 or (item.get("mp") or 0) > 0),
              f"{where} → treat {treat} must be a consumable that heals")
    check(bool(season.get("hats")) and bool(season.get("treats")), f"{where} → needs hats and treats")
    check(isinstance(season.get("chance"), (int, float)) and 0 < season["chance"] <= 1, f"{where} → chance in (0, 1]")
    check(isinstance(season.get("hatChance"), (int, float)) and 0 <= season["hatChance"] <= 1, f"{where} → hatChance in [0, 1]")
    check(isinstance(season.get("greeting"), str) and season["greeting"].strip() != "", f"{where} → needs a greeting")
    hats_given |= set(season.get("hats", []))
    treats_given |= set(season.get("treats", []))
if all(month_day(s.get("from")) or "easter" in s for s in seasons):
    for year in (2026, 2027, 2028, 2029):
        day = datetime.date(year, 1, 1)
        while day.year == year:
            on = [s["id"] for s in seasons if ("easter" in s or (month_day(s.get("from")) and month_day(s.get("to")))) and in_season(s, day)]
            check(len(on) <= 1, f"rewards seasons → {', '.join(on)} both on {day}")
            day += datetime.timedelta(days=1)
hats = {item_id for item_id, item in items.items() if (item["type"] == "head" and "headgear" not in item) or item.get("wear") == "scarf"}
check(hats == hats_given, f"rewards seasons → every hat is a season's (hats no season gives: {sorted(hats - hats_given)})")
handed = elsewhere | set((rewards.get("chests") or {}).get("items", [])) | {i for gift in rewards.get("dailyGifts", []) for i in gift.get("items") or []}
for item_id in sorted(hats_given | treats_given):
    check(item_id not in handed and "recipe" not in items.get(item_id, {}),
          f"item {item_id} → only its season gives it (no shop, quest, chest, smith or drop)")

# A barber in every town (playtesting 2026-10-21): a new hairstyle and hair colour for their `price` in gold.
for town in (m for m in load("content/maps.json")["maps"] if m.get("town")):
    barbers = [n for n in town.get("npcs", []) if n["role"] == "barber"]
    check(len(barbers) == 1, f"map {town['id']} → a town needs one barber (has {len(barbers)})")
for npc in npcs.values():
    if npc["role"] == "barber":
        check(isinstance(npc.get("price"), int) and npc["price"] >= 0, f"npc {npc['id']} → a barber needs a price in gold")
    else:
        check("price" not in npc, f"npc {npc['id']} → only a barber has a price")
weavers = [npc for npc in npcs.values() if npc["role"] == "weaver"]
check(len(weavers) == (1 if prizes else 0), f"rewards prizes → one weaver to weave them (found {len(weavers)})")

# Monster cards (rewards.json `cards`): chances in (0, 1], a gain for every element a monster can
# have (so every card is worth something), each a stat the hero has.
cards = rewards.get("cards", {})
check(bool(cards), "rewards → needs cards (the monster cards' rules)")
for key in ("chance", "rareChance", "bossChance"):
    check(isinstance(cards.get(key), (int, float)) and 0 < cards[key] <= 1, f"rewards cards {key} → in (0, 1]")
check(isinstance(cards.get("levelsPerStep"), int) and cards["levelsPerStep"] > 0, "rewards cards levelsPerStep → a whole number above 0")
for key in ("rare", "boss"):
    check(isinstance(cards.get(key), (int, float)) and cards[key] >= 1, f"rewards cards {key} → at least 1")

# Seal Stones from hard fights (rewards.json `seals`): tiers climbing in `above`, chances in (0, 1],
# and only Seal Stones (items with `capture`).
seals = rewards.get("seals", {})
check(bool(seals.get("tiers")) and isinstance(seals.get("boss"), dict), "rewards → needs seals (tiers and boss)")
aboves = [tier.get("above") for tier in seals.get("tiers", [])]
check(all(isinstance(a, int) and a >= 1 for a in aboves) and aboves == sorted(set(aboves)),
      "rewards seals tiers → whole `above` levels from 1 up, each higher than the last")
for index, rule in enumerate(seals.get("tiers", []) + [seals.get("boss", {})], start=1):
    where = "rewards seals boss" if index > len(seals.get("tiers", [])) else f"rewards seals tier {index}"
    check(isinstance(rule.get("chance"), (int, float)) and 0 < rule["chance"] <= 1, f"{where} → chance in (0, 1]")
    check(bool(rule.get("items")), f"{where} → needs items")
    check_items(rule.get("items"), where)
    for item_id in rule.get("items") or []:
        check(items.get(item_id, {}).get("capture") is True, f"{where} → {item_id} isn't a Seal Stone")

# Treasure chests filled again (rewards.json `chests`): a while after you open one, gold for its
# level and gear or one of its items.
chest_rules = rewards.get("chests", {})
check(isinstance(chest_rules.get("refillHours"), (int, float)) and chest_rules["refillHours"] > 0, "rewards chests refillHours → above 0")
check(isinstance(chest_rules.get("goldPerLevel"), int) and chest_rules["goldPerLevel"] >= 0, "rewards chests goldPerLevel → a whole number, at least 0")
check(isinstance(chest_rules.get("gearChance"), (int, float)) and 0 <= chest_rules["gearChance"] <= 1, "rewards chests gearChance → in [0, 1]")
check(bool(chest_rules.get("items")), "rewards chests → needs items (what a chest holds when it's no gear)")
check_items(chest_rules.get("items"), "rewards chests")

gains = cards.get("gains", {})
for element in sorted({m["element"] for m in monsters.values()}):
    check(element in gains, f"rewards cards gains → nothing for {element} monsters' cards")
for element, gain in gains.items():
    check(isinstance(gain, dict) and gain.get("stat") in ("hp", "mp", "attack", "defense", "magic", "speed"),
          f"rewards cards gains {element} → stat must be hp, mp, attack, defense, magic or speed")
    check(isinstance(gain, dict) and isinstance(gain.get("perStep"), (int, float)) and gain["perStep"] > 0,
          f"rewards cards gains {element} → perStep above 0")

# Every sound the game plays (SoundEffects.Sound's raw values) has its file in sound/, made by
# tools/make_sounds.py: a missing one would just stay silent. And every file there is one of them.
sound_enum = (ROOT / "Storyleaf/Audio/SoundEffects.swift").read_text().split("enum Sound: String, CaseIterable {", 1)[-1].split("func ", 1)[0]
sounds = [raw.strip().strip('"') or name.strip()
          for line in sound_enum.splitlines() if line.strip().startswith("case ")
          for name, _, raw in (part.partition("=") for part in line.strip()[5:].split(","))]
sound_files = {path.stem for path in (ROOT / "sound").glob("*.wav")}
check(bool(sounds), "SoundEffects.Sound → no cases found in Storyleaf/Audio/SoundEffects.swift")
for sound in sounds:
    check(sound in sound_files, f"sound {sound} → no sound/{sound}.wav (python3 tools/make_sounds.py {sound})")
for stray in sorted(sound_files - set(sounds)):
    errors.append(f"sound/{stray}.wav → not a SoundEffects.Sound, so the game never plays it")

# Translations (content/i18n): every listed language has a table, placeholders survive, and every
# L() in the code has a literal key. Missing translations only show in English, so they're reported
# by `python3 tools/i18n.py status`, not here.
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import i18n  # noqa: E402
errors += i18n.check()
check(json.loads((ROOT / "content" / "i18n" / "languages.json").read_text())["languages"][0]["code"] == "en",
      "content/i18n/languages.json → English comes first (it's the fallback)")

if errors:
    print(f"✗ {len(errors)} problem(s):")
    for error in errors:
        print("  •", error)
    sys.exit(1)
print(f"✓ Content OK: {len(maps)} maps, {len(monsters)} monsters, {len(skills)} skills, {len(items)} items, {len(quests)} quests")
