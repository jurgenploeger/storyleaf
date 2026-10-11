import Foundation
import Testing
import UIKit
import SpriteKit
@testable import Fairyland

/// Catches broken references when editing content/*.json or art/assets.json.
@MainActor
struct ContentTests {
    let content = Content.shared

    @Test func changelogMatchesAppVersion() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        #expect(content.releases.first?.version == version, "bump content/changelog.json with MARKETING_VERSION")
    }

    @Test func everyReferenceResolves() {
        for cls in content.classes {
            for unlock in cls.skills {
                #expect(content.skill(unlock.skill) != nil, "class \(cls.id) → unknown skill \(unlock.skill)")
            }
        }
        for monster in content.monsters {
            for skill in monster.skills {
                #expect(content.skill(skill) != nil, "monster \(monster.id) → unknown skill \(skill)")
            }
            #expect(ArtLibrary.shared.asset(monster.art) != nil, "monster \(monster.id) → unknown art \(monster.art)")
        }
        for quest in content.quests {
            #expect(content.npc(quest.giver) != nil, "quest \(quest.id) → unknown giver \(quest.giver)")
            if quest.objective.type == .defeat, let target = quest.objective.target {
                #expect(content.monster(target) != nil, "quest \(quest.id) → unknown monster \(target)")
            }
            if let question = quest.question {
                for answer in question.answers {
                    #expect(content.monster(answer.egg) != nil, "quest \(quest.id) → unknown egg \(answer.egg)")
                }
            }
            for item in quest.reward.items ?? [] {
                #expect(content.item(item) != nil, "quest \(quest.id) → unknown item \(item)")
            }
            for required in quest.requires ?? [] {
                #expect(content.quest(required) != nil, "quest \(quest.id) → unknown quest \(required)")
            }
        }
        #expect(content.map(content.startMap) != nil)
        for map in content.maps {
            for exit in map.exits {
                let destination = content.map(exit.to)
                #expect(destination != nil, "map \(map.id) → unknown map \(exit.to)")
                // Every exit needs a way back, or you'd get stuck.
                #expect(destination?.exits.contains { $0.to == map.id && $0.edge == exit.edge.opposite } == true,
                        "map \(exit.to) has no \(exit.edge.opposite) exit back to \(map.id)")
            }
            for id in map.encounters?.monsters.keys.sorted() ?? [] {
                #expect(content.monster(id) != nil, "map \(map.id) → unknown monster \(id)")
            }
            if let music = map.music {
                #expect(content.song(music) != nil, "map \(map.id) → unknown song \(music)")
            }
            if let music = map.battleMusic {
                #expect(content.song(music) != nil, "map \(map.id) → unknown battle song \(music)")
            }
            for npc in map.npcs ?? [] {
                #expect(ArtLibrary.shared.asset(npc.art) != nil, "npc \(npc.id) → unknown art \(npc.art)")
                for item in npc.stock ?? [] {
                    #expect(content.item(item) != nil, "shop \(npc.id) → unknown item \(item)")
                }
                if npc.role == .chest {
                    #expect(npc.gives.flatMap(content.item) != nil, "chest \(npc.id) → unknown item")
                }
                if npc.role == .guild {
                    #expect(content.classes.contains { $0.id == npc.classId }, "guild \(npc.id) → unknown class")
                }
                if npc.role == .boss {
                    #expect(npc.monster.flatMap(content.monster)?.boss == true, "boss \(npc.id) → unknown boss monster")
                }
            }
            for exit in map.exits {
                if let quest = exit.requires { #expect(content.quest(quest) != nil, "map \(map.id) road → unknown quest \(quest)") }
            }
            let art = map.theme.props.map(\.art) + (map.town?.lots ?? []) + (map.town?.streetDecor?.keys.sorted() ?? [])
                + (map.buildings ?? []).map(\.art) + (map.decor ?? []).map(\.art)
            for id in art {
                #expect(ArtLibrary.shared.asset(id) != nil, "map \(map.id) → unknown art \(id)")
            }
        }
        for item in content.items {
            #expect(item.icon.flatMap(GameIcon.init) != nil, "item \(item.id) → unknown icon \(item.icon ?? "nil")")
        }
        for skill in content.skills {
            #expect(skill.icon.flatMap(GameIcon.init) != nil, "skill \(skill.id) → unknown icon \(skill.icon ?? "nil")")
        }
    }

    @Test func songsParse() {
        for song in content.songs {
            let tune = Tune(song, instruments: content.instruments)
            #expect(!tune.isLegacy, "song \(song.id) still uses chiptune waves")
            for (index, voice) in tune.voices.enumerated() {
                #expect(!voice.notes.isEmpty, "song \(song.id) track \(index) has no notes")
                #expect(voice.instrument != nil, "song \(song.id) track \(index) → unknown instrument")
                if voice.isDrums {
                    #expect(voice.notes.contains { !$0.drums.isEmpty }, "song \(song.id) track \(index) has no drum hits")
                } else {
                    #expect(voice.notes.contains { !$0.frequencies.isEmpty }, "song \(song.id) track \(index) has no pitches")
                }
            }
        }
        #expect(abs((Tune.frequency(of: "A4") ?? 0) - 440) < 0.01)
        #expect(abs((Tune.frequency(of: "C4") ?? 0) - 261.63) < 0.01)
    }

    @Test func theLateGameClimbsSlower() {
        #expect(GameSession.expToNext(level: 100) == 10 + 100 * 100 * 5)
        #expect(GameSession.expToNext(level: 140) == 2 * (10 + 140 * 140 * 5))
        #expect(GameSession.expToNext(level: 199) > 3 * (10 + 199 * 199 * 5))
    }

    @Test func everyZoneLevelHasSomewhereToFight() {
        // From level 1 to 200 there is always a zone whose monsters are within 10 levels of you.
        let bands = content.maps.compactMap(\.encounters).map { ($0.levels.first ?? 1, $0.levels.last ?? 1) }
        for level in 1...200 {
            #expect(bands.contains { $0.0 <= level + 10 && $0.1 >= level - 10 }, "nowhere to fight at level \(level)")
        }
    }

    @Test func everyMapHasRoomToWalk() {
        for def in content.maps {
            let map = WorldMap(def: def)
            for exit in def.exits {
                #expect(map.isWalkable(map.entryCell(from: exit.edge)), "map \(def.id) entry from \(exit.edge) is blocked")
            }
        }
    }

    @Test func hillsStandUpWithAWayUp() {
        for def in content.maps where def.theme.hills != nil {
            let map = WorldMap(def: def)
            let hills = map.plateaus.filter { $0.kind == .hill }
            #expect(!hills.isEmpty, "map \(def.id) has no hills")
            for hill in hills {
                #expect(!hill.ramps.isEmpty, "map \(def.id): a hill with no way up")
                for (cell, ramp) in hill.ramps {
                    let foot = ramp == .south ? GridPoint(col: cell.col, row: cell.row - 1) : GridPoint(col: cell.col - 1, row: cell.row)
                    let head = ramp == .south ? GridPoint(col: cell.col, row: cell.row + 1) : GridPoint(col: cell.col + 1, row: cell.row)
                    // Up from the ground at its foot, over the slope, to the top.
                    #expect(map.isWalkable(foot) && map.isWalkable(cell) && map.isWalkable(head), "map \(def.id): the ramp at \(cell) is blocked")
                    #expect(map.height(at: map.center(of: foot)) == 0)
                    #expect(map.height(at: map.center(of: head)) == hill.height)
                    let halfway = map.height(at: map.center(of: cell))
                    #expect(halfway > 0 && halfway < hill.height)
                }
            }
        }
        // A town's terraces stand up too, their stairs climbing to the top.
        for def in content.maps where def.town?.terraces?.isEmpty == false {
            let map = WorldMap(def: def)
            #expect(map.plateaus.contains { $0.kind == .terrace && $0.height == WorldMap.terraceHeight }, "map \(def.id): terraces lie flat")
        }
    }

    @Test func housesStandOffTheRoads() {
        for def in content.maps {
            let map = WorldMap(def: def)
            #expect(map.buildings.count == (def.buildings ?? []).count, "map \(def.id) lost a building")
            // The map's own buildings and the shops along the streets: on plain ground or a terrace's
            // paved top, never on a road, and never on each other.
            let houses = map.buildings.map { ($0.art, $0.anchor) } + map.lots.map { ($0.art, $0.anchor) }
            var taken: Set<GridPoint> = []
            for (art, anchor) in houses {
                for dc in -1...1 {
                    for dr in 0...1 {
                        let cell = GridPoint(col: anchor.col + dc, row: anchor.row + dr)
                        let ground = map.ground[cell.row][cell.col]
                        #expect(ground == .ground || ground == .accent, "map \(def.id): \(art) stands on \(ground) at \(cell)")
                        #expect(taken.insert(cell).inserted, "map \(def.id): \(art) overlaps another building at \(cell)")
                    }
                }
            }
        }
    }

    @Test func townsfolkStayInView() {
        // No house on a townsperson's spot or just in front of it (lower on screen), where its roof
        // would hide them: WorldMap.planTown keeps the 4×4 cells from two in front to one behind clear.
        for def in content.maps where def.town != nil {
            let map = WorldMap(def: def)
            let houses = map.buildings.map { ($0.art, $0.anchor) } + map.lots.map { ($0.art, $0.anchor) }
            for npc in def.npcs ?? [] {
                let spot = map.offset(npc.x, npc.y)
                for (art, anchor) in houses {
                    let hides = (-3...2).contains(anchor.col - spot.col) && (-3...1).contains(anchor.row - spot.row)
                    #expect(!hides, "map \(def.id): \(art) at \(anchor) hides \(npc.id)")
                }
            }
        }
    }

    @Test func theMinimapWearsItsOwnMapsColours() throws {
        // Arriving from the Big Bad Wolf's Lair, the art library still grades for its palette (golden
        // grass) when the HUD first asks for Larkspur's minimap; it must still come out green.
        let lair = try #require(content.map("wolf_lair"))
        let larkspur = try #require(content.map("bluebird"))
        ArtLibrary.shared.use(palette: lair.theme.palette, for: lair.id)
        let scene = WorldScene(map: larkspur, session: GameSession.newGame(name: "Test", raceID: "human"), input: InputState(), entry: nil)
        let image = try #require(scene.minimap.cgImage)
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var red = 0, green = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            red += Int(pixels[index])
            green += Int(pixels[index + 1])
        }
        #expect(green > red, "Larkspur's minimap came out golden: red \(red / (width * height)), green \(green / (width * height))")
    }

    @Test func announcementsAndTradersHaveSomethingToSay() {
        let notices = content.announcements
        #expect(!notices.dawn.isEmpty && !notices.dusk.isEmpty && !notices.community.isEmpty)
        for id in notices.arrival.keys {
            #expect(content.map(id) != nil, "announcements arrival → unknown map \(id)")
        }
        let lines = content.crowd.traderLines ?? []
        #expect(lines.contains { $0.contains("{item}") } && lines.contains { $0.contains("{buy}") })
    }

    @Test func everyMapHasAPaletteThatGrades() throws {
        let url = try #require(Bundle.main.url(forResource: "tile_grass", withExtension: "png", subdirectory: "art/sprites"))
        let image = try #require(UIImage(contentsOfFile: url.path)?.cgImage)
        for def in content.maps {
            let palette = try #require(def.theme.palette, "map \(def.id) has no palette")
            let graded = try #require(Recolor.grade(palette, image: image), "map \(def.id) palette didn't grade")
            #expect(graded.width == image.width && graded.height == image.height)
        }
    }
}

@MainActor
struct LanguageTests {
    @Test func thePhonesLanguagePicksTheClosestOneWeHave() {
        let codes = Localizer.shared.languages.map(\.code)
        #expect(codes.first == "en" && codes.count == 11)
        #expect(Localizer.preferred(among: codes, preferences: ["de-AT", "en"]) == "de")
        #expect(Localizer.preferred(among: codes, preferences: ["pt-BR"]) == "pt-BR")
        #expect(Localizer.preferred(among: codes, preferences: ["pt-PT"]) == "pt-BR")
        #expect(Localizer.preferred(among: codes, preferences: ["zh-Hant-TW"]) == "zh-Hant")
        #expect(Localizer.preferred(among: codes, preferences: ["zh-TW"]) == "zh-Hant")
        #expect(Localizer.preferred(among: codes, preferences: ["zh-Hans-CN"]) == "zh-Hans")
        #expect(Localizer.preferred(among: codes, preferences: ["nl-NL", "es-MX"]) == "es")
        #expect(Localizer.preferred(among: codes, preferences: ["nl-NL"]) == "en")
    }

    @Test func everyLanguageHasItsTableAndKeepsThePlaceholders() throws {
        let placeholder = try Regex("\\{[A-Za-z_][A-Za-z0-9_]*\\}")
        for language in Localizer.shared.languages where language.code != "en" {
            let table = Localizer.table(for: language.code, bundle: .main)
            #expect(!table.isEmpty, "content/i18n/\(language.code).json is empty or missing")
            for (english, translated) in table {
                let want = english.matches(of: placeholder).map { String(english[$0.range]) }.sorted()
                let got = translated.matches(of: placeholder).map { String(translated[$0.range]) }.sorted()
                #expect(want == got, "\(language.code): \(english) → \(translated)")
            }
        }
    }

    @Test func theGameDataReadsInEveryLanguage() {
        let english = Content(strings: [:])
        for language in Localizer.shared.languages where language.code != "en" {
            let table = Localizer.table(for: language.code, bundle: .main)
            let content = Content(strings: table)
            // Same data, its text swapped: ids and numbers untouched.
            #expect(content.monsters.map(\.id) == english.monsters.map(\.id))
            #expect(content.items.map(\.price) == english.items.map(\.price))
            #expect(content.maps.map(\.id) == english.maps.map(\.id))
            let monster = english.monsters[0]
            #expect(content.monsters[0].name == (table[monster.name] ?? monster.name), "\(language.code)")
            #expect(content.releases.count == english.releases.count)
        }
    }

    @Test func untranslatedTextStaysEnglishWithItsPlaceholdersFilled() {
        // Tests run in English, so this is the English text with the values put in.
        #expect(L("{bot} just reached level {level}!", ["bot": "Momo", "level": 12]) == "Momo just reached level 12!")
        #expect(L("A string no table has") == "A string no table has")
    }
}

@MainActor
struct LookTests {
    init() {
        // Belt and braces: never touch the real save from tests.
        SaveStore.fileName = "fairyland-tests-save.json"
    }

    @Test func derivedSpritesHaveABase() throws {
        let url = try #require(Bundle.main.url(forResource: "assets", withExtension: "json", subdirectory: "art"))
        let manifest = try JSONDecoder().decode(ArtManifest.self, from: Data(contentsOf: url))
        let ids = Set(manifest.assets.map(\.id))
        for asset in manifest.assets {
            if let base = asset.derive?.from {
                #expect(ids.contains(base), "\(asset.id) derives from unknown \(base)")
            }
        }
    }

    @Test func spreadMeasuresFromTheWindowsMiddle() throws {
        // A green ramp (highlights 70, shadows 150) turned brown keeps its shading's hue shift:
        // the middle lands on `to` and each hue stays its distance from the middle times `spread`.
        let green = try JSONDecoder().decode(RecolorRule.self, from: Data(#"{"hue": [70, 150], "to": 25, "spread": -0.3}"#.utf8))
        #expect(green.distanceFromMiddle(of: 110) == 0)
        #expect(green.distanceFromMiddle(of: 150) == 40)
        #expect(green.distanceFromMiddle(of: 70) == -40)
        // A window that wraps round red has its middle at 355.
        let pink = try JSONDecoder().decode(RecolorRule.self, from: Data(#"{"hue": [330, 20], "to": 200}"#.utf8))
        #expect(pink.distanceFromMiddle(of: 10) == 15)
        #expect(pink.distanceFromMiddle(of: 340) == -15)
    }

    @Test func aCompanionsNameGivesWayToYours() {
        // Right behind you (Walker.follow's place), a long name prints over yours; two short ones fit
        // side by side, and a step away there's room for any.
        let cycle = WalkCycle(frames: [:], size: CGSize(width: 48, height: 48))
        let hero = Walker(cycle: cycle, label: "Hero")
        let pet = Walker(cycle: cycle, label: "Pineapple Sprout")
        pet.position = hero.position + CGVector(dx: -34, dy: 6)
        #expect(pet.tagCrowds(hero))
        pet.position = hero.position + CGVector(dx: -160, dy: 6)
        #expect(!pet.tagCrowds(hero))
        let jo = Walker(cycle: cycle, label: "Jo")
        let pip = Walker(cycle: cycle, label: "Pip")
        pip.position = jo.position + CGVector(dx: -34, dy: 6)
        #expect(!pip.tagCrowds(jo))
    }

    @Test func customisingTheHeroAndCompanion() {
        // The look is chosen when the hero is made (any look, from the start) and kept.
        let options = Content.shared.appearance
        #expect(options.hair.first?.id == Look.standard.hair)
        let look = Look(hair: "pink", outfit: "blue", skin: "tan")
        let session = GameSession.newGame(name: "Pip", raceID: "human", look: look)
        #expect(session.data.hero.name == "Pip")
        #expect(session.data.hero.look == look)
        #expect(!GameSession.rules(for: look).isEmpty)

        let pet = session.makePet(species: "jelly", level: 1)!
        session.addPet(pet, countsForQuests: false)
        #expect(session.artID(for: pet) == "monster_jelly")
        session.renamePet(pet.id, to: "Wobble")
        let updated = session.data.pets[0]
        #expect(updated.name == "Wobble")
        // Companions keep their species' colours.
        #expect(session.artID(for: updated) == "monster_jelly")
    }

    @Test func everyGenderHasASheetForEveryRace() {
        let content = Content.shared
        #expect(content.appearance.genders.map(\.id) == ["male", "female"])
        for race in content.races {
            #expect(race.sheet(for: nil) == race.sheet)   // older saves keep their sheet
            for gender in content.appearance.genders {
                let sheet = race.sheet(for: gender.id)
                #expect(ArtLibrary.shared.asset(sheet) != nil, "\(race.id) \(gender.id) → unknown art \(sheet)")
            }
        }
        #expect(content.race("dwarf").sheet(for: "female") != content.race("dwarf").sheet(for: "male"))
        let look = Look(hair: "pink", outfit: "blue", skin: "tan", gender: "female")
        #expect(look.key != Look(hair: "pink", outfit: "blue", skin: "tan").key)
        // A save from when there was a third gender keeps the race's own sheet.
        #expect(content.race("elf").sheet(for: "other") == content.race("elf").sheet)
    }

    @Test func anyoneCanWearTheOtherGendersHair() {
        let content = Content.shared
        let human = content.race("human")
        // A boy in a ponytail, a girl with spiky hair: picks stick across genders.
        #expect(GameSession.style(for: Look(hair: "ginger", outfit: "green", skin: "fair", gender: "male", style: "ponytail"), race: human) == "ponytail")
        #expect(GameSession.style(for: Look(hair: "ginger", outfit: "green", skin: "fair", gender: "female", style: "spiky"), race: human) == "spiky")
        // Without a pick, each starts with their own hair, listed first.
        #expect(GameSession.style(for: Look(hair: "ginger", outfit: "green", skin: "fair", gender: "female"), race: human) == "ponytail")
        #expect(content.appearance.styles(for: human.sheet(for: "female")).first?.id == "ponytail")
        #expect(content.appearance.styles(for: human.sheet(for: "male")).count == content.appearance.styles.count)
    }
}

@MainActor
struct RulesTests {
    init() {
        SaveStore.fileName = "fairyland-tests-save.json"
    }

    @Test func elementChart() {
        #expect(Element.water.multiplier(against: .fire) == 1.5)
        #expect(Element.fire.multiplier(against: .water) == 0.75)
        #expect(Element.earth.multiplier(against: .water) == 1.5)
        #expect(Element.wood.multiplier(against: .earth) == 1.5)
        #expect(Element.light.multiplier(against: .dark) == 1.5)
        #expect(Element.fire.multiplier(against: .fire) == 1)
    }

    @Test func adventurersWalkCompanionsFromNearTheirLevel() {
        let content = Content.shared
        let wild = content.maps.compactMap(\.encounters)
        for level in [5, 60, 150] {
            for _ in 0..<15 {
                guard let id = Crowd.companion(forLevel: level) else {
                    Issue.record("no companion for level \(level)")
                    return
                }
                // Met in the wild no higher than their level and not far below it.
                let lowest = wild.filter { $0.monsters[id] != nil }.compactMap(\.levels.first)
                #expect(lowest.contains { ((level - Crowd.companionReach)...level).contains($0) }, "level \(level) → \(id)")
                #expect(content.monster(id)?.boss != true)
            }
        }
    }

    @Test func theHealerRestsYourFriendsToo() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        var friend = Adventurer(name: "Maple", raceID: "elf", classID: "mage", level: 20, look: .standard)
        friend.hp = 3
        friend.mp = 0
        session.data.friends = [friend]
        session.restParty()
        #expect(session.data.friends?.first?.hp == nil)
        #expect(session.data.friends?.first?.mp == nil)
    }

    @Test func levellingUpRestoresAndGrows() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let before = session.heroStats
        session.data.hero.hp = 1
        session.data.hero.mp = 0
        let levels = session.gainHeroEXP(GameSession.expToNext(level: 1))
        #expect(levels == 1)
        #expect(session.data.hero.level == 2)
        #expect(session.heroStats.hp > before.hp)
        // A new level fills HP and MP to the new maximums.
        #expect(session.data.hero.hp == session.heroStats.hp)
        #expect(session.data.hero.mp == session.heroStats.mp)
        // EXP short of a level heals nothing.
        session.data.hero.hp = 1
        #expect(session.gainHeroEXP(1) == 0)
        #expect(session.data.hero.hp == 1)
        // Reaching Bash's level unlocks it; learning it takes one skill point.
        let bashLevel = Content.shared.classDef("novice").skills.first { $0.skill == "bash" }!.level
        while session.data.hero.level < bashLevel {
            session.gainHeroEXP(GameSession.expToNext(level: session.data.hero.level))
        }
        #expect(session.heroSkills.isEmpty)
        #expect(session.learnableSkills.contains { $0.id == "bash" })
        let points = session.unspentSkillPoints
        session.learnSkill("bash")
        #expect(session.heroSkills.contains { $0.id == "bash" })
        #expect(session.unspentSkillPoints == points - 1)
    }

    @Test func classChoiceNeedsLevel() {
        let session = GameSession.newGame(name: "Test", raceID: "elf")
        session.addItem("wooden_sword")
        session.equip("wooden_sword")
        session.chooseClass("mage")
        #expect(session.data.hero.classID == "novice")
        session.data.hero.level = Content.shared.classChoiceLevel
        session.chooseClass("mage")
        #expect(session.data.hero.classID == "mage")
        // The wooden sword isn't for mages, so it goes back into the bag.
        #expect(session.data.hero.equipment.weapon == nil)
        #expect(session.count(of: "wooden_sword") == 1)
        // Mage skills open up as you level.
        let fireBolt = Content.shared.classDef("mage").skills.first { $0.skill == "fire_bolt" }!
        #expect(!session.learnableSkills.contains { $0.id == "fire_bolt" } || fireBolt.level <= session.data.hero.level)
        session.data.hero.level = fireBolt.level
        #expect(session.learnableSkills.contains { $0.id == "fire_bolt" })
    }

    @Test func firstCompanionHatchesFromTheEldersEgg() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        #expect(session.data.pets.isEmpty)
        let quest = Content.shared.quest("hope_of_meadowbrook")!
        // No gift boxes lying around: the elder hands over the three gifts himself.
        #expect((Content.shared.map("meadowbrook")?.npcs ?? []).allSatisfy { $0.role != .chest })
        session.acceptQuest(quest.id, answer: quest.question?.answers.first { $0.egg == "jelly" })
        #expect(session.count(of: "wooden_sword") == 1)
        #expect(session.count(of: "novice_ring") == 1)
        #expect(session.count(of: "pet_egg") == 1)
        #expect(session.status(of: quest) != .ready)   // hatch the egg first
        let pet = session.hatch("pet_egg")
        #expect(pet?.speciesID == "jelly")
        #expect(session.activePet?.id == pet?.id)
        #expect(session.status(of: quest) == .ready)
        session.turnInQuest(quest.id)
        #expect(session.status(of: Content.shared.quest("jelly_trouble")!) == .available)
    }

    @Test func oldSavesGetTheGiftsTheyMissed() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        session.data.version = 1
        session.data.quests["hope_of_meadowbrook"] = QuestProgress(state: .active, count: 1)
        session.data.openedChests = ["gift_box_1"]   // found the sword box only
        session.handOutMissingStarterGifts()
        #expect(session.count(of: "novice_ring") == 1)
        #expect(session.count(of: "pet_egg") == 1)
        #expect(session.count(of: "wooden_sword") == 0)
        session.handOutMissingStarterGifts()   // only once
        #expect(session.count(of: "pet_egg") == 1)
    }

    @Test func skillPointsRaiseSkills() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let novice = Content.shared.classDef("novice").skills
        let bashLevel = novice.first { $0.skill == "bash" }!.level
        let aidLevel = novice.first { $0.skill == "first_aid" }!.level
        session.data.hero.level = bashLevel
        let points = bashLevel - 1
        #expect(session.unspentSkillPoints == points)
        session.upgradeSkill("bash")   // not learned yet
        #expect(session.unspentSkillPoints == points)
        session.learnSkill("bash")
        session.upgradeSkill("bash")
        #expect(session.skillLevel("bash") == 2)
        #expect(session.unspentSkillPoints == points - 2)
        session.data.hero.level = aidLevel
        #expect(session.learnableSkills.map(\.id) == ["first_aid"])
    }

    @Test func rebirthKeepsSkillsAndStrength() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let bashLevel = Content.shared.classDef("novice").skills.first { $0.skill == "bash" }!.level
        session.data.hero.level = bashLevel
        session.learnSkill("bash")
        session.data.hero.level = session.rebirthLevel
        #expect(!session.canRebirth)   // not enough gold yet
        session.data.gold = session.rebirthCost
        let strengthAtOne = GameSession.newGame(name: "Fresh", raceID: "human").heroStats.attack
        session.rebirth()
        #expect(session.data.hero.level == 1)
        #expect(session.rebirths == 1)
        #expect(session.data.gold == 0)
        #expect(session.heroSkills.contains { $0.id == "bash" })
        #expect(session.heroStats.attack > strengthAtOne)
        #expect(session.rebirthLevel == 106)
    }

    @Test func smithForgesFromMaterials() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let sword = try #require(Content.shared.item("novice_bronze_sword"))
        #expect(!session.canCraft(sword))
        #expect(!session.craft(sword.id))
        for (material, needed) in sword.recipe ?? [:] {
            session.addItem(material, needed + 1)
        }
        #expect(session.canCraft(sword))
        #expect(session.craft(sword.id))
        #expect(session.count(of: sword.id) == 1)
        for (material, _) in sword.recipe ?? [:] {
            #expect(session.count(of: material) == 1)   // one of each left over
        }
        #expect(!session.bagMaterials.isEmpty)
        #expect(!session.bagEquipment.contains { $0.type == .material })
    }

    @Test func recipesUseMaterialsMonstersDrop() {
        for item in Content.shared.items {
            for (id, _) in item.recipe ?? [:] {
                let material = Content.shared.item(id)
                #expect(material?.type == .material, "recipe for \(item.id) → \(id) isn't a material")
                #expect((material?.level ?? 1) <= max(item.level ?? 1, 1), "recipe for \(item.id) → \(id) drops too late")
            }
        }
        let session = GameSession.newGame(name: "Test", raceID: "human")
        for _ in 0..<50 {
            let drop = session.materialDrop(level: 1)
            #expect(drop == nil || (drop?.level ?? 1) <= 1)
        }
    }

    @Test func glovesNecklacesAndBootsHaveSlotsOfTheirOwn() throws {
        // A save from before these slots decodes, with the new ones empty.
        let old = try JSONDecoder().decode(Equipment.self, from: Data(#"{"weapon":"wooden_sword","armor":"cloth_tunic","accessory":"ruby_ring"}"#.utf8))
        #expect(old.weapon == "wooden_sword" && old.accessory == "ruby_ring")
        #expect(old.gloves == nil && old.necklace == nil && old.boots == nil)

        // Speed Boots worn as an accessory (before boots had a slot) move to the boots slot on load.
        let session = GameSession.newGame(name: "Test", raceID: "human")
        var data = session.data
        data.hero.equipment.accessory = "speed_boots"
        let loaded = GameSession(data: data)
        #expect(loaded.data.hero.equipment.boots == "speed_boots")
        #expect(loaded.data.hero.equipment.accessory == nil)
        // With the boots slot taken, they go back in the bag instead.
        data.hero.equipment.boots = "leather_boots"
        let full = GameSession(data: data)
        #expect(full.data.hero.equipment.boots == "leather_boots")
        #expect(full.data.hero.equipment.accessory == nil)
        #expect(full.count(of: "speed_boots") == 1)

        // Each piece goes in its own slot and adds its stats, next to a ring in the accessory slot.
        let hero = GameSession.newGame(name: "Test", raceID: "human")
        let before = hero.heroStats
        for id in ["leather_gloves", "shell_pendant", "straw_sandals", "novice_ring"] {
            hero.addItem(id)
            hero.equip(id)
        }
        #expect(hero.data.hero.equipment.gloves == "leather_gloves")
        #expect(hero.data.hero.equipment.necklace == "shell_pendant")
        #expect(hero.data.hero.equipment.boots == "straw_sandals")
        #expect(hero.data.hero.equipment.accessory == "novice_ring")
        let after = hero.heroStats
        #expect(after.attack == before.attack + 2)
        #expect(after.speed == before.speed + 1)
        #expect(after.mp == before.mp + 6 + 4)
        // Taking one off puts it back in the bag.
        hero.unequip(.gloves)
        #expect(hero.data.hero.equipment.gloves == nil)
        #expect(hero.count(of: "leather_gloves") == 1)
    }

    @Test func hardFightsAndBossesLeaveSealStones() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        // An ordinary fight leaves none; the tougher theme's 5 levels up starts it.
        #expect(session.sealRule(gap: 0, boss: false) == nil)
        #expect(session.sealRule(gap: 4, boss: false) == nil)
        let easiest = try #require(session.sealRule(gap: 5, boss: false))
        #expect(easiest.above == 5)
        // The harder the fight, the likelier and better.
        let harder = try #require(session.sealRule(gap: 12, boss: false))
        #expect(harder.above == 10 && harder.chance > easiest.chance)
        let hardest = try #require(session.sealRule(gap: 60, boss: false))
        #expect(hardest.chance >= harder.chance)
        // A boss always leaves one, however your level compares.
        let boss = try #require(session.sealRule(gap: -10, boss: true))
        #expect(boss.chance == 1)
        #expect(session.sealDrop(gap: -10, boss: true)?.capture == true)
        // Only Seal Stones, and never the Wishing Seal (a reward of its own).
        let rules = Content.shared.rewards.seals.tiers + [Content.shared.rewards.seals.boss]
        for id in rules.flatMap(\.items) {
            #expect(Content.shared.item(id)?.capture == true, "\(id) isn't a Seal Stone")
            #expect(Content.shared.item(id)?.sure != true, "\(id) is the Wishing Seal")
        }
    }

    @Test func monstersDropGearFromUpToTheirLevel() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        session.data.hero.classID = "fighter"
        let bossDrops = Set(Content.shared.monsters.flatMap { $0.drops ?? [] }.map(\.item))
        var usable = 0
        var accessories = 0
        for _ in 0..<400 {
            let gear = try #require(session.equipmentDrop(level: 40))
            #expect(ItemType.equipmentSlots.contains(gear.type))
            #expect(!bossDrops.contains(gear.id), "\(gear.id) is a boss's own drop")
            if gear.type.isTrinket {
                // Any trinket (gloves, necklace, boots or accessory) up to the monster's level.
                accessories += 1
                #expect((gear.level ?? 1) <= 40, "\(gear.id) is level \(gear.level ?? 1)")
            } else {
                #expect((29...40).contains(gear.level ?? 1), "\(gear.id) is level \(gear.level ?? 1)")
                if gear.classes?.contains("fighter") ?? true { usable += 1 }
            }
        }
        // About one drop in three is a trinket (133 of 400 on average).
        #expect((90...180).contains(accessories), "\(accessories) trinkets in 400 drops")
        // The weapons and armour are mostly what your class can use (three in four, plus what the
        // rest happens to hit).
        #expect(Double(usable) > Double(400 - accessories) * 0.6)
        // Trinkets keep dropping from high-level monsters, where none is in the level window.
        let late = (0..<300).compactMap { _ in session.equipmentDrop(level: 150) }.filter { $0.type.isTrinket }
        #expect(late.count > 50)
        for _ in 0..<100 {
            let best = try #require(session.equipmentDrop(level: 40, best: true))
            if !best.type.isTrinket { #expect((35...40).contains(best.level ?? 1)) }
        }
        // Past the best gear there is, weapons and armour come from the top (trinkets from anywhere).
        let top = try #require(Content.shared.items.compactMap(\.level).max())
        let beyond = (0..<30).compactMap { _ in session.equipmentDrop(level: top + 50) }.filter { !$0.type.isTrinket }
        #expect(!beyond.isEmpty)
        for gear in beyond { #expect((gear.level ?? 1) > top - 12, "\(gear.id) is level \(gear.level ?? 1)") }
        // Stronger fights drop gear more often; a rare monster often, a boss always.
        let even = GameSession.equipmentDropChance(level: 30, heroLevel: 30, rare: false, boss: false)
        let above = GameSession.equipmentDropChance(level: 45, heroLevel: 30, rare: false, boss: false)
        let below = GameSession.equipmentDropChance(level: 10, heroLevel: 30, rare: false, boss: false)
        #expect(below < even && even < above)
        #expect(abs(above - 0.16) < 1e-9 && abs(below - 0.02) < 1e-9)
        #expect(GameSession.equipmentDropChance(level: 30, heroLevel: 30, rare: true, boss: false) > above)
        #expect(GameSession.equipmentDropChance(level: 30, heroLevel: 30, rare: false, boss: true) == 1)
    }

    @Test func levelsStopAtTheCap() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        session.data.hero.level = GameSession.levelCap
        #expect(session.gainHeroEXP(1_000_000_000) == 0)
        #expect(session.data.hero.level == GameSession.levelCap)
    }

    @Test func oldSavesGetStretchedLevels() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        session.data.levelsRescaled = nil
        session.data.hero.level = 10
        session.rescaleLevelsIfNeeded()
        #expect(session.data.hero.level == GameSession.stretchedLevel(10))
        #expect(session.data.hero.level == 31)
        session.rescaleLevelsIfNeeded()   // only once
        #expect(session.data.hero.level == 31)
    }

    @Test func everySkillHasIconArt() {
        for skill in Content.shared.skills {
            #expect(skill.art.flatMap(ArtLibrary.shared.asset) != nil, "skill \(skill.id) has no icon art")
        }
    }

    @Test func monsterBookRemembersWhatYouMeet() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        #expect(session.sighting(of: "rat_king") == nil)
        let npc = try #require(Content.shared.maps.flatMap { $0.npcs ?? [] }.first { $0.monster == "rat_king" })
        let level = try #require(npc.level)
        _ = try #require(BattleController.boss(npc, session: session))
        let met = try #require(session.sighting(of: "rat_king"))
        #expect(met.defeated == 0)
        #expect(met.lowestLevel == level && met.highestLevel == level)
        // Beaten below and above the level it was met at, the book widens both ways.
        session.beatMonster("rat_king", level: 2)
        session.beatMonster("rat_king", level: level + 10)
        let beaten = try #require(session.sighting(of: "rat_king"))
        #expect(beaten.defeated == 2)
        #expect(beaten.lowestLevel == 2 && beaten.highestLevel == level + 10)
        #expect(Element.water.strongAgainst == [.fire])
        #expect(Element.water.weakTo == [.earth])
        #expect(Content.shared.monsters.allSatisfy { !($0.lore ?? "").isEmpty })
    }

    @Test func bossesComeInWavesAndOutrankThem() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let map = try #require(Content.shared.maps.first { $0.npcs?.contains { $0.monster == "rat_king" } == true })
        let npc = try #require(map.npcs?.first { $0.monster == "rat_king" })
        let level = try #require(npc.level)
        let waves = try #require(BattleController.bossWaves(npc, encounters: map.encounters, session: session))
        // Two waves of ten of the map's own monsters, then the boss behind nine more (the middle
        // of the first row of five, the one furthest from you).
        #expect(waves.map(\.count) == [10, 10, 10])
        #expect(waves[2][2].speciesID == "rat_king" && waves[2][2].level == level)
        #expect(waves[2].filter { $0.speciesID == "rat_king" }.count == 1)
        let monsters = waves.joined().filter { $0.speciesID != "rat_king" }
        #expect(monsters.allSatisfy { map.encounters?.monsters[$0.speciesID ?? ""] != nil })
        // The boss outranks them all, and each wave stands a little closer to its level.
        #expect(monsters.allSatisfy { $0.level < level })
        #expect(waves[0].allSatisfy { $0.level <= level - 13 } && waves[1].allSatisfy { $0.level <= level - 7 })
        for (index, wave) in waves.enumerated() { #expect(wave.allSatisfy { $0.wave == index + 1 }) }
        let ids = waves.joined().map(\.id)
        #expect(Set(ids).count == ids.count && ids.allSatisfy { $0 >= 10 })

        // The fight opens with the first wave and knows how many follow.
        let battle = try #require(BattleController.boss(npc, encounters: map.encounters, session: session))
        #expect(battle.enemies.count == 10 && battle.wave == 1 && battle.waveCount == 3)
        #expect(!battle.enemies.contains { $0.speciesID == "rat_king" })
        #if DEBUG
        // Debug wins (screenshots) take every wave down at once.
        battle.winForDebug()
        #expect(battle.result?.outcome == .victory)
        #endif
        // Without the map's monsters it fights alone, in one wave.
        let alone = try #require(BattleController.boss(npc, session: session))
        #expect(alone.enemies.count == 1 && alone.waveCount == 1)
    }

    @Test func theNextWaveStepsInWhenOneIsBeaten() {
        let content = Content.shared
        let jelly = content.monster("jelly")!
        // Far faster (turn order is a shuffle weighted by speed), so it as good as always moves first.
        let hero = Combatant(id: 0, side: .party, source: .hero, name: "Hero", art: "player_walk", level: 30, element: .neutral,
                             stats: Stats(hp: 500, mp: 20, attack: 60, defense: 50, magic: 10, speed: 10_000), hp: 500, mp: 20,
                             skills: [], captureRate: 0)
        let foeStats = jelly.stats(at: 1)
        let first = Combatant(id: 11, side: .enemies, source: .wild("jelly"), name: "Jelly", art: jelly.art, level: 1, element: jelly.element,
                              stats: foeStats, hp: 1, mp: 0, skills: [], captureRate: jelly.captureRate)
        var boss = Combatant(id: 20, side: .enemies, source: .wild("jelly"), name: "Boss", art: jelly.art, level: 5, element: jelly.element,
                             stats: foeStats, hp: foeStats.hp, mp: 0, skills: [], captureRate: 0)
        boss.wave = 2
        let engine = BattleEngine(party: [hero], enemies: [first], content: content, seed: 9, waves: [[boss]])
        #expect(engine.wave == 1 && engine.waveCount == 2)
        let events = engine.resolveRound(heroAction: .attack(target: 11))
        // Beating the first wave isn't a win yet: the boss steps in for the next round.
        #expect(engine.outcome == .ongoing)
        #expect(engine.wave == 2)
        #expect(engine.combatant(20)?.isAlive == true)
        let steppedIn = events.contains { event in
            if case .wave(let number, let total, let arrivals) = event { return number == 2 && total == 2 && arrivals.map(\.id) == [20] }
            return false
        }
        #expect(steppedIn)
    }

    #if DEBUG
    @Test func bossesTellTheirStoryTheFirstTimeOnly() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let npc = try #require(Content.shared.boss(fighting: "rat_king"))
        let victory = try #require(npc.victory)
        let first = try #require(BattleController.boss(npc, session: session))
        first.winForDebug()
        #expect(first.result?.outcome == .victory)
        #expect(first.result?.story?.title == victory.title)
        #expect(first.result?.story?.paragraphs == victory.story)
        // Beaten once, a rematch is just a fight (the story stays in the Monster Book).
        session.defeatBoss(npc)
        let rematch = try #require(BattleController.boss(npc, session: session))
        rematch.winForDebug()
        #expect(rematch.result?.outcome == .victory)
        #expect(rematch.result?.story == nil)
    }
    #endif

    @Test func everyTownSellsAHomewardFeather() throws {
        let content = Content.shared
        let feather = try #require(content.item("homeward_feather"))
        #expect(feather.type == .consumable)
        #expect(feather.travel == true)
        let shops = content.maps.flatMap { $0.npcs ?? [] }.filter { $0.role == .shop }
        #expect(!shops.isEmpty)
        for shop in shops {
            #expect(shop.stock?.contains(feather.id) == true, "\(shop.id) doesn't sell it")
        }
        // A way home from the bag, for any class; not something to use in a fight.
        let session = GameSession.newGame(name: "Test", raceID: "human")
        session.addItem(feather.id)
        #expect(session.consumables.contains { $0.id == feather.id })
        #expect(!session.battleItems.contains { $0.id == feather.id })
        #expect(session.use(feather.id) == nil)
        #expect(session.count(of: feather.id) == 1)
    }

    @Test func shopsBuyBackAndAdventurersTrade() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let potion = try #require(Content.shared.item("potion"))
        let gold = session.data.gold
        let potions = session.count(of: "potion")
        #expect(session.sell("potion") == GameSession.sellPrice(of: potion))
        #expect(session.data.gold == gold + GameSession.sellPrice(of: potion))
        #expect(session.count(of: "potion") == potions - 1)
        #expect(session.sell("not_an_item") == nil)

        let friend = Adventurer(name: "Mimi", raceID: "elf", classID: "mage", level: 10, look: .standard)
        let offers = session.tradeOffers(with: friend)
        // The same day gives the same offers.
        #expect(offers.map(\.id) == session.tradeOffers(with: friend).map(\.id))
        session.data.gold = 100_000
        let deal = try #require(offers.first { $0.kind == .theySell })
        #expect(session.trade(deal))
        #expect(session.count(of: deal.item.id) >= 1)
        // Each deal is made once.
        #expect(!session.trade(deal))
        #expect(!session.tradeOffers(with: friend).contains { $0.id == deal.id })
        if let buy = offers.first(where: { $0.kind == .theyBuy }) {
            // Adventurers pay more than the shop does.
            #expect(buy.price > GameSession.sellPrice(of: buy.item))
        }
    }

    @Test func battleButtonsKeepYourOrder() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        #expect(session.battleButtons == GameSession.defaultBattleButtons)
        // Your own order sticks.
        session.data.battleButtons = ["skills", "more", "attack", "items", "guard", "run", "capture"]
        #expect(session.battleButtons == ["skills", "more", "attack", "items", "guard", "run", "capture"])
        // Skills pinned beside Attack in older versions drop out; a missing command comes back at the end.
        session.data.battleButtons = ["skill:bash", "attack", "skills", "more", "items", "skill:first_aid", "guard"]
        #expect(session.battleButtons == ["attack", "skills", "more", "items", "guard", "capture", "run"])
    }

    @Test func questFlow() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        session.data.quests["hope_of_meadowbrook"] = QuestProgress(state: .completed, count: 3)
        let quest = Content.shared.quest("jelly_trouble")!
        #expect(session.status(of: quest) == .available)
        session.acceptQuest(quest.id)
        for _ in 0..<3 { session.record(.defeat, target: "jelly") }
        session.record(.defeat, target: "bunny")
        #expect(session.status(of: quest) == .ready)
        let gold = session.data.gold
        session.turnInQuest(quest.id)
        #expect(session.status(of: quest) == .completed)
        #expect(session.data.gold == gold + (quest.reward.gold ?? 0))
        // Completing it unlocks the follow-ups.
        #expect(session.status(of: Content.shared.quest("new_friend")!) == .available)
    }

    @Test func questRewardsGrowWithYourLevel() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        session.data.quests["hope_of_meadowbrook"] = QuestProgress(state: .completed, count: 3)
        let quest = Content.shared.quest("jelly_trouble")!
        // At the level it's meant for, a quest pays its own reward.
        #expect(session.questPay(quest).gold == quest.reward.gold)
        #expect(session.questPay(quest).exp == quest.reward.exp)
        // Outgrown, it pays for your level: a bit more than a bounty.
        session.data.hero.level = 44
        let rules = Content.shared.rewards
        let pay = session.questPay(quest)
        #expect(pay.gold == rules.quests.goldPerLevel * 44)
        #expect(pay.gold > rules.bounties.goldPerLevel * 44)
        #expect(Double(pay.exp) > Double(GameSession.expToNext(level: 44)) * rules.bounties.exp)
        // A quest that pays no EXP still pays none.
        #expect(session.questPay(Content.shared.quest("choose_path")!).exp == 0)
        session.acceptQuest(quest.id)
        for _ in 0..<3 { session.record(.defeat, target: "jelly") }
        let gold = session.data.gold
        session.turnInQuest(quest.id)
        #expect(session.data.gold == gold + pay.gold)
        // What it paid stays on record, however far you level on.
        session.data.hero.level = 60
        #expect(session.paid(for: quest).gold == pay.gold)
        #expect(session.paid(for: quest).exp == pay.exp)
    }

    @Test func battleRunsToAnEnd() {
        let content = Content.shared
        let jelly = content.monster("jelly")!
        let heroStats = Stats(hp: 200, mp: 20, attack: 30, defense: 10, magic: 10, speed: 20)
        let hero = Combatant(id: 0, side: .party, source: .hero, name: "Hero", art: "player_walk", level: 5, element: .neutral,
                             stats: heroStats, hp: 200, mp: 20, skills: [], captureRate: 0)
        let stats = jelly.stats(at: 1)
        let enemy = Combatant(id: 10, side: .enemies, source: .wild("jelly"), name: "Jelly", art: jelly.art, level: 1, element: jelly.element,
                              stats: stats, hp: stats.hp, mp: stats.mp, skills: jelly.skills, captureRate: jelly.captureRate)
        let engine = BattleEngine(party: [hero], enemies: [enemy], content: content, seed: 42)
        var rounds = 0
        while engine.outcome == .ongoing && rounds < 20 {
            _ = engine.resolveRound(heroAction: .attack(target: 10))
            rounds += 1
        }
        // A nearly beaten monster may run off instead of going down.
        #expect(engine.outcome == .victory || engine.outcome == .fled)
    }

    @Test func companionsFollowOrders() {
        let content = Content.shared
        let jelly = content.monster("jelly")!
        let stats = Stats(hp: 200, mp: 20, attack: 30, defense: 10, magic: 10, speed: 20)
        let hero = Combatant(id: 0, side: .party, source: .hero, name: "Hero", art: "player_walk", level: 5, element: .neutral,
                             stats: stats, hp: 200, mp: 20, skills: [], captureRate: 0)
        let pet = Combatant(id: 1, side: .party, source: .pet(UUID()), name: "Pet", art: jelly.art, level: 5, element: jelly.element,
                            stats: stats, hp: 200, mp: 20, skills: jelly.skills, captureRate: 0)
        let foeStats = jelly.stats(at: 30)
        let foe = Combatant(id: 10, side: .enemies, source: .wild("jelly"), name: "Jelly", art: jelly.art, level: 30, element: jelly.element,
                            stats: foeStats, hp: foeStats.hp, mp: foeStats.mp, skills: [], captureRate: 0)
        let engine = BattleEngine(party: [hero, pet], enemies: [foe], content: content, seed: 7)
        // Told to guard, it guards; left to itself, it would have gone for the monster.
        let events = engine.resolveRound(heroAction: .defend, orders: [1: .defend])
        let guards = events.filter { event in
            if case .defend(let actor) = event { return actor == 1 }
            return false
        }
        let attacks = events.filter { event in
            if case .attack(let actor, _) = event { return actor == 1 }
            return false
        }
        #expect(guards.count == 1)
        #expect(attacks.isEmpty)
    }

    @Test func friendsWithoutACompanionTryToSealOne() {
        let content = Content.shared
        let jelly = content.monster("jelly")!
        let stats = Stats(hp: 200, mp: 20, attack: 30, defense: 10, magic: 10, speed: 20)
        let hero = Combatant(id: 0, side: .party, source: .hero, name: "Hero", art: "player_walk", level: 5, element: .neutral,
                             stats: stats, hp: 200, mp: 20, skills: [], captureRate: 0)
        let foeStats = jelly.stats(at: 3)
        // Nearly beaten and on its own: weak enough for a fair throw.
        let foe = Combatant(id: 10, side: .enemies, source: .wild("jelly"), name: "Jelly", art: jelly.art, level: 3, element: jelly.element,
                            stats: foeStats, hp: 1, mp: 0, skills: [], captureRate: jelly.captureRate)
        func throwsAStone(stones: Int) -> (thrown: Bool, ally: Combatant?, foe: Combatant?) {
            var ally = Combatant(id: 2, side: .party, source: .ally(UUID()), name: "Momo", art: "player_walk", level: 5, element: .neutral,
                                 stats: stats, hp: 200, mp: 20, skills: [], captureRate: 0)
            ally.sealStones = stones
            let engine = BattleEngine(party: [hero, ally], enemies: [foe], content: content, seed: 3)
            // You stand guard, so it's the friend's move that counts.
            let events = engine.resolveRound(heroAction: .defend)
            let thrown = events.contains { event in
                if case .capture(let actor, let target, _, _, _) = event { return actor == 2 && target == 10 }
                return false
            }
            return (thrown, engine.combatant(2), engine.combatant(10))
        }
        let carrying = throwsAStone(stones: 2)
        #expect(carrying.thrown)
        // The stone is used up either way, and a catch is theirs.
        #expect(carrying.ally?.sealStones == 1)
        if carrying.foe?.isCaptured == true { #expect(carrying.foe?.capturedBy == 2) }
        // Out of stones, they fight on instead.
        #expect(!throwsAStone(stones: 0).thrown)
    }

    @Test func frostBreathFreezesForOneTurn() {
        let content = Content.shared
        let jelly = content.monster("jelly")!
        // Far faster than the monster (turn order is a shuffle weighted by speed), so the hero as good
        // as always moves first.
        let stats = Stats(hp: 500, mp: 200, attack: 30, defense: 10, magic: 40, speed: 10_000)
        var hero = Combatant(id: 0, side: .party, source: .hero, name: "Hero", art: "player_walk", level: 20, element: .neutral,
                             stats: stats, hp: 500, mp: 200, skills: ["frost_breath"], captureRate: 0)
        hero.skillLevels = ["frost_breath": 1]
        // Slow and tough, so it lasts the whole test.
        let foeStats = Stats(hp: 5000, mp: 0, attack: 20, defense: 10, magic: 10, speed: 1)
        let foe = Combatant(id: 10, side: .enemies, source: .wild("jelly"), name: "Jelly", art: jelly.art, level: 20, element: jelly.element,
                            stats: foeStats, hp: 5000, mp: 0, skills: [], captureRate: 0)
        let engine = BattleEngine(party: [hero], enemies: [foe], content: content, seed: 5)
        func foeActed(_ events: [BattleEvent]) -> Bool {
            events.contains { event in
                if case .attack(let actor, _) = event { return actor == 10 }
                return false
            }
        }
        func foeFrozen(_ events: [BattleEvent]) -> Bool {
            events.contains { event in
                if case .frozen(let target) = event { return target == 10 }
                return false
            }
        }
        // The ice takes hold only some of the time (a whole party frozen every round was a lock), so
        // breathe until it does: that round the monster's turn is lost.
        #expect((content.skill("frost_breath")?.inflicts?.chance ?? 1) < 1)
        func tookHold(_ events: [BattleEvent]) -> Bool {
            events.contains { event in
                if case .afflicted(10, .freeze, 1) = event { return true }
                return false
            }
        }
        var first = engine.resolveRound(heroAction: .skill("frost_breath", target: 10))
        for _ in 0..<20 where !tookHold(first) {
            first = engine.resolveRound(heroAction: .skill("frost_breath", target: 10))
        }
        #expect(tookHold(first))
        #expect(foeFrozen(first))
        #expect(!foeActed(first))
        // One turn only: next round it moves again.
        let second = engine.resolveRound(heroAction: .defend)
        #expect(!foeFrozen(second))
        #expect(foeActed(second))
    }

    @Test func frozenFightersSitOutTogetherAtTheRoundsStart() {
        let content = Content.shared
        let jelly = content.monster("jelly")!
        let stats = Stats(hp: 500, mp: 200, attack: 30, defense: 10, magic: 40, speed: 1)
        let hero = Combatant(id: 0, side: .party, source: .hero, name: "Hero", art: "player_walk", level: 20, element: .neutral,
                             stats: stats, hp: 500, mp: 200, skills: [], captureRate: 0)
        // Fast, so in the old order their frozen turns would have come between the others' moves.
        let foeStats = Stats(hp: 5000, mp: 0, attack: 20, defense: 10, magic: 10, speed: 80)
        let foes = (10...12).map { id in
            var foe = Combatant(id: id, side: .enemies, source: .wild("jelly"), name: "Jelly", art: jelly.art, level: 20, element: jelly.element,
                                stats: foeStats, hp: 5000, mp: 0, skills: [], captureRate: 0)
            if id != 11 { foe.frozenRounds = 1 }
            return foe
        }
        let engine = BattleEngine(party: [hero], enemies: foes, content: content, seed: 5)
        let events = engine.resolveRound(heroAction: .defend)
        let frozen = events.prefix { event in
            if case .frozen = event { return true }
            return false
        }
        #expect(frozen.count == 2)
        let acted = Set(events.compactMap { event -> Int? in
            if case .attack(let actor, _) = event { return actor }
            return nil
        })
        #expect(!acted.contains(10))
        #expect(!acted.contains(12))
    }

    @Test func poisonBitesEachRoundAndCursesWeaken() throws {
        let content = Content.shared
        let jelly = content.monster("jelly")!
        let stats = Stats(hp: 500, mp: 200, attack: 30, defense: 10, magic: 40, speed: 50)
        var hero = Combatant(id: 0, side: .party, source: .hero, name: "Hero", art: "player_walk", level: 20, element: .neutral,
                             stats: stats, hp: 500, mp: 200, skills: ["poison", "curse"], captureRate: 0)
        hero.skillLevels = ["poison": 1, "curse": 1]
        let foeStats = jelly.stats(at: 20)
        // Plenty of HP, so it lasts the whole test.
        let foe = Combatant(id: 10, side: .enemies, source: .wild("jelly"), name: "Jelly", art: jelly.art, level: 20, element: jelly.element,
                            stats: foeStats, hp: foeStats.hp * 20, mp: 0, skills: [], captureRate: 0)
        let engine = BattleEngine(party: [hero], enemies: [foe], content: content, seed: 3)
        func bites(_ events: [BattleEvent]) -> [Int] {
            events.compactMap { event in
                if case .ailmentDamage(let target, _, let amount) = event, target == 10 { return amount }
                return nil
            }
        }

        // Poison takes hold and bites at the end of the round it lands in, then once a round: 3 bites.
        let first = engine.resolveRound(heroAction: .skill("poison", target: 10))
        let tookHold = first.contains { event in
            if case .afflicted(let target, let effect, _) = event { return target == 10 && effect == .poison }
            return false
        }
        #expect(tookHold)
        let bite = try #require(bites(first).first)
        #expect(bite > 0)
        #expect(bites(engine.resolveRound(heroAction: .defend)) == [bite])
        #expect(bites(engine.resolveRound(heroAction: .defend)) == [bite])
        #expect(bites(engine.resolveRound(heroAction: .defend)).isEmpty)

        // A curse lowers the stats behind its hits (attack and magic) by a fifth for the rest of the
        // round and 3 more, and says by how much.
        let cursing = engine.resolveRound(heroAction: .skill("curse", target: 10))
        let shown = cursing.contains { event in
            if case .statsChanged(10, let changes, 3) = event {
                return changes.map(\.stat) == [.attack, .magic] && changes.allSatisfy { abs($0.amount + 0.2) < 0.001 }
            }
            return false
        }
        #expect(shown)
        let cursed = try #require(engine.combatant(10))
        #expect(abs(cursed.factor(.attack) - 0.8) < 0.001 && abs(cursed.factor(.magic) - 0.8) < 0.001)
        for _ in 0..<3 { _ = engine.resolveRound(heroAction: .defend) }
        #expect(abs((engine.combatant(10)?.factor(.attack) ?? 0) - 0.8) < 0.001)
        _ = engine.resolveRound(heroAction: .defend)
        #expect(engine.combatant(10)?.factor(.attack) == 1)
        #expect(engine.combatant(10)?.lowered.isEmpty == true)
    }

    @Test func aBossesMinionsStandTheirGround() {
        let content = Content.shared
        let jelly = content.monster("jelly")!
        let stats = Stats(hp: 500, mp: 20, attack: 1, defense: 50, magic: 1, speed: 1)
        let hero = Combatant(id: 0, side: .party, source: .hero, name: "Hero", art: "player_walk", level: 30, element: .neutral,
                             stats: stats, hp: 500, mp: 20, skills: [], captureRate: 0)
        // The boss is down and its last minion nearly beaten: it can't run off and turn the win into "It got away".
        let boss = Combatant(id: 10, side: .enemies, source: .wild("jelly"), name: "Boss", art: jelly.art, level: 30, element: jelly.element,
                             stats: stats, hp: 0, mp: 0, skills: [], captureRate: 0)
        let minionStats = jelly.stats(at: 5)
        let minion = Combatant(id: 11, side: .enemies, source: .wild("jelly"), name: "Jelly", art: jelly.art, level: 5, element: jelly.element,
                               stats: minionStats, hp: 1, mp: 0, skills: [], captureRate: jelly.captureRate)
        let engine = BattleEngine(party: [hero], enemies: [boss, minion], content: content, seed: 11)
        for _ in 0..<20 { _ = engine.resolveRound(heroAction: .defend) }
        #expect(engine.outcome == .ongoing)
        #expect(engine.combatant(11)?.hasFled == false)
    }

    @Test func companionsHoldBackOnlyWhileYouSeal() {
        let content = Content.shared
        let jelly = content.monster("jelly")!
        let foeStats = jelly.stats(at: 1)
        func play(_ heroAction: BattleAction) -> [BattleEvent] {
            let hero = Combatant(id: 0, side: .party, source: .hero, name: "Hero", art: "player_walk", level: 5, element: .neutral,
                                 stats: Stats(hp: 500, mp: 20, attack: 30, defense: 50, magic: 10, speed: 50), hp: 500, mp: 20,
                                 skills: [], captureRate: 0)
            let pet = Combatant(id: 1, side: .party, source: .pet(UUID()), name: "Pet", art: jelly.art, level: 5, element: jelly.element,
                                stats: Stats(hp: 500, mp: 0, attack: 30, defense: 50, magic: 10, speed: 10_000), hp: 500, mp: 0,
                                skills: [], captureRate: 0)
            let foe = Combatant(id: 10, side: .enemies, source: .wild("jelly"), name: "Jelly", art: jelly.art, level: 1, element: jelly.element,
                                stats: foeStats, hp: 1, mp: 0, skills: [], captureRate: jelly.captureRate)
            let engine = BattleEngine(party: [hero, pet], enemies: [foe], content: content, seed: 5)
            return engine.resolveRound(heroAction: heroAction)
        }
        // The monster could be sealed, but you're not throwing a stone: your companion goes for it.
        let attacked = play(.defend).contains { event in
            if case .attack(let actor, _) = event { return actor == 1 }
            return false
        }
        #expect(attacked)
        // You throw one: it holds back (if the stone didn't already seal it).
        let wentFor = play(.capture(target: 10)).contains { event in
            if case .attack(let actor, _) = event { return actor == 1 }
            return false
        }
        #expect(!wentFor)
    }

    @Test func yourSideGoesInTheOrderItChoseThenTheMonsters() {
        let content = Content.shared
        let jelly = content.monster("jelly")!
        let sturdy = Stats(hp: 9_999, mp: 0, attack: 1, defense: 999, magic: 1, speed: 1)
        let hero = Combatant(id: 0, side: .party, source: .hero, name: "Hero", art: "player_walk", level: 40, element: .neutral,
                             stats: sturdy, hp: 9_999, mp: 0, skills: [], captureRate: 0)
        var pet = Combatant(id: 1, side: .party, source: .pet(UUID()), name: "Pet", art: jelly.art, level: 40, element: .neutral,
                            stats: sturdy, hp: 9_999, mp: 0, skills: [], captureRate: 0)
        pet.ownerID = 0
        let friend = Combatant(id: 2, side: .party, source: .ally(UUID()), name: "Maple", art: "player_walk", level: 40, element: .neutral,
                               stats: sturdy, hp: 9_999, mp: 0, skills: [], captureRate: 0)
        // Far faster than everyone, and it still waits for your side.
        let foe = Combatant(id: 10, side: .enemies, source: .wild("jelly"), name: "Jelly", art: jelly.art, level: 40, element: jelly.element,
                            stats: Stats(hp: 9_999, mp: 0, attack: 1, defense: 999, magic: 1, speed: 10_000), hp: 9_999, mp: 0,
                            skills: [], captureRate: 0)
        func actors(_ events: [BattleEvent]) -> [Int] {
            events.compactMap { event in
                switch event {
                case .attack(let actor, _), .skill(let actor, _, _, _), .defend(let actor): actor
                default: nil
                }
            }
        }
        let engine = BattleEngine(party: [hero, pet, friend], enemies: [foe], content: content, seed: 3)
        // Chosen at once: you first, your companion right after you, the monster last.
        let quick = actors(engine.resolveRound(heroAction: .attack(target: 10), heroChoseAt: 0))
        #expect(Array(quick.prefix(2)) == [0, 1])
        #expect(quick.last == 10)
        // Chosen as the bell rings: your friend got in first.
        let slow = actors(engine.resolveRound(heroAction: .attack(target: 10), heroChoseAt: 1))
        #expect(slow.first == 2)
        #expect(Array(slow.suffix(3)) == [0, 1, 10])
    }

    @Test func reviveWakesAFaintedCompanionAndBlessHelps() {
        let content = Content.shared
        let jelly = content.monster("jelly")!
        let heroStats = Stats(hp: 200, mp: 100, attack: 30, defense: 10, magic: 20, speed: 99)
        var hero = Combatant(id: 0, side: .party, source: .hero, name: "Hero", art: "player_walk", level: 40, element: .neutral,
                             stats: heroStats, hp: 200, mp: 100, skills: ["revive", "bless"], captureRate: 0)
        hero.skillLevels = ["revive": 1, "bless": 1]
        let petStats = Stats(hp: 100, mp: 0, attack: 10, defense: 10, magic: 0, speed: 1)
        let pet = Combatant(id: 1, side: .party, source: .pet(UUID()), name: "Pet", art: jelly.art, level: 10, element: .neutral,
                            stats: petStats, hp: 0, mp: 0, skills: [], captureRate: 0)
        let stats = jelly.stats(at: 1)
        let enemy = Combatant(id: 10, side: .enemies, source: .wild("jelly"), name: "Jelly", art: jelly.art, level: 1, element: jelly.element,
                              stats: stats, hp: 9_999, mp: 0, skills: [], captureRate: 0)
        let engine = BattleEngine(party: [hero, pet], enemies: [enemy], content: content, seed: 7)
        _ = engine.resolveRound(heroAction: .skill("revive", target: 1))
        // Revive Lv1 brings them back with 30% of their HP; a level-1 jelly can't knock that out.
        #expect(engine.combatant(1)!.hp > 0)
        #expect(engine.combatant(0)!.mp < 100)
        _ = engine.resolveRound(heroAction: .skill("bless", target: 0))
        let blessed = engine.combatant(0)!
        #expect(blessed.raised[.attack]?.rounds == BattleEngine.buffLength + 1)
        #expect(blessed.raised[.defense]?.rounds == BattleEngine.buffLength + 1)
        #expect(blessed.attack > Double(heroStats.attack))
    }

    @Test func buffsRaiseStatsForAWhileAndSayByHowMuch() throws {
        let content = Content.shared
        let jelly = content.monster("jelly")!
        let stats = Stats(hp: 500, mp: 200, attack: 30, defense: 40, magic: 20, speed: 50)
        var hero = Combatant(id: 0, side: .party, source: .hero, name: "Hero", art: "player_walk", level: 40, element: .neutral,
                             stats: stats, hp: 500, mp: 200, skills: ["protection", "berserk", "guardianship"], captureRate: 0)
        hero.skillLevels = ["protection": 1, "berserk": 1, "guardianship": 1]
        let friend = Combatant(id: 2, side: .party, source: .ally(UUID()), name: "Momo", art: "player_walk", level: 40, element: .neutral,
                               stats: Stats(hp: 500, mp: 0, attack: 20, defense: 20, magic: 0, speed: 1), hp: 500, mp: 0,
                               skills: [], captureRate: 0)
        let foeStats = jelly.stats(at: 1)
        let foe = Combatant(id: 10, side: .enemies, source: .wild("jelly"), name: "Jelly", art: jelly.art, level: 1, element: jelly.element,
                            stats: foeStats, hp: 9_999, mp: 0, skills: [], captureRate: 0)
        let engine = BattleEngine(party: [hero, friend], enemies: [foe], content: content, seed: 9)

        // Protection: DEF +40%, said with the amount, for this round and 3 more.
        let shielding = engine.resolveRound(heroAction: .skill("protection", target: 0))
        #expect(shielding.contains { event in
            if case .statsChanged(0, let changes, 3) = event { return changes == [StatChange(stat: .defense, amount: 0.4)] }
            return false
        })
        let shielded = try #require(engine.combatant(0))
        #expect(abs(shielded.defense - 56) < 0.001)
        for _ in 0..<3 { _ = engine.resolveRound(heroAction: .defend) }
        #expect(engine.combatant(0)?.raised[.defense] != nil)
        _ = engine.resolveRound(heroAction: .defend)
        #expect(engine.combatant(0)?.raised[.defense] == nil)

        // Berserk trades defense for attack.
        _ = engine.resolveRound(heroAction: .skill("berserk", target: 0))
        let raging = try #require(engine.combatant(0))
        #expect(abs(raging.factor(.attack) - 1.3) < 0.001)
        #expect(abs(raging.factor(.defense) - 0.75) < 0.001)

        // Guardianship wards everyone on your side.
        let ward = engine.resolveRound(heroAction: .skill("guardianship", target: 0))
        let warded = Set(ward.compactMap { event -> Int? in
            if case .statsChanged(let target, _, _) = event { return target }
            return nil
        })
        #expect(warded == [0, 2])
        #expect(engine.combatant(2)?.raised[.defense] != nil)
    }

    @Test func monstersPowerThemselvesUp() throws {
        let content = Content.shared
        let wolf = try #require(content.monster("werewolf"))
        let hero = Combatant(id: 0, side: .party, source: .hero, name: "Hero", art: "player_walk", level: 60, element: .neutral,
                             stats: Stats(hp: 99_999, mp: 0, attack: 1, defense: 999, magic: 1, speed: 1), hp: 99_999, mp: 0,
                             skills: [], captureRate: 0)
        let stats = wolf.stats(at: 20)
        let foe = Combatant(id: 10, side: .enemies, source: .wild("werewolf"), name: "Werewolf", art: wolf.art, level: 20, element: wolf.element,
                            stats: stats, hp: stats.hp, mp: stats.mp, skills: wolf.skills, captureRate: wolf.captureRate)
        let engine = BattleEngine(party: [hero], enemies: [foe], content: content, seed: 21)
        var raged = false
        for _ in 0..<30 where !raged {
            raged = engine.resolveRound(heroAction: .defend).contains { event in
                if case .statsChanged(10, let changes, _) = event { return changes.contains { $0.stat == .attack && $0.amount > 0 } }
                return false
            }
        }
        #expect(raged)
    }

    @Test func troublemakersOnlyPickFightsTheyCanWin() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        session.data.hero.level = 50
        session.data.pets.removeAll()
        func rival(_ level: Int, pet: String? = nil) -> Adventurer {
            Adventurer(name: "Rook", raceID: "human", classID: "fighter", level: level, look: .standard, petSpecies: pet, hostile: true)
        }
        // About your level or stronger: they come for you.
        #expect(session.dares(rival(50)))
        #expect(session.dares(rival(45)))
        // Much weaker: they leave you be.
        #expect(!session.dares(rival(44)))
        // Their companion counts on their side.
        #expect(session.dares(rival(25, pet: "jelly")))
    }

    @Test func friendsFightOnAfterYouFallAndWakeYou() {
        let content = Content.shared
        let jelly = content.monster("jelly")!
        let stats = Stats(hp: 200, mp: 100, attack: 30, defense: 10, magic: 20, speed: 10)
        // You've fallen; a friend who knows Revive is still standing.
        let hero = Combatant(id: 0, side: .party, source: .hero, name: "Hero", art: "player_walk", level: 40, element: .neutral,
                             stats: stats, hp: 0, mp: 20, skills: [], captureRate: 0)
        var friend = Combatant(id: 2, side: .party, source: .ally(UUID()), name: "Maple", art: "player_walk", level: 40, element: .neutral,
                               stats: stats, hp: 200, mp: 100, skills: ["revive"], captureRate: 0)
        friend.skillLevels = ["revive": 1]
        let foe = Combatant(id: 10, side: .enemies, source: .wild("jelly"), name: "Jelly", art: jelly.art, level: 1, element: jelly.element,
                            stats: jelly.stats(at: 1), hp: 9_999, mp: 0, skills: [], captureRate: 0)
        let engine = BattleEngine(party: [hero, friend], enemies: [foe], content: content, seed: 4)
        _ = engine.resolveRound(heroAction: .defend)
        // The fight goes on without you, and your friend wakes you.
        #expect(engine.outcome == .ongoing)
        #expect(engine.combatant(0)!.hp > 0)

        // With only your companion standing, a fall loses the fight: companions don't fight on alone.
        let pet = Combatant(id: 1, side: .party, source: .pet(UUID()), name: "Pet", art: jelly.art, level: 40, element: .neutral,
                            stats: stats, hp: 200, mp: 0, skills: [], captureRate: 0)
        let alone = BattleEngine(party: [hero, pet], enemies: [foe], content: content, seed: 4)
        _ = alone.resolveRound(heroAction: .defend)
        #expect(alone.outcome == .defeat)
    }

    @Test func aSealStoneWorksOnAnyMonsterAtAnyHP() {
        let content = Content.shared
        let jelly = content.monster("jelly")!
        let stats = jelly.stats(at: 1)
        let hero = Combatant(id: 0, side: .party, source: .hero, name: "Hero", art: "player_walk", level: 1, element: .neutral,
                             stats: Stats(hp: 60, attack: 10, defense: 8, speed: 10), hp: 60, mp: 0, skills: [], captureRate: 0)
        var enemy = Combatant(id: 10, side: .enemies, source: .wild("jelly"), name: "Jelly", art: jelly.art, level: 1, element: jelly.element,
                              stats: stats, hp: stats.hp, mp: 0, skills: [], captureRate: jelly.captureRate)
        let other = Combatant(id: 11, side: .enemies, source: .wild("jelly"), name: "Jelly B", art: jelly.art, level: 1, element: jelly.element,
                              stats: stats, hp: stats.hp, mp: 0, skills: [], captureRate: jelly.captureRate)
        // Another monster still standing doesn't stop it.
        func chance(at hp: Int) -> Double? {
            enemy.hp = hp
            guard case .ready(let chance) = BattleEngine(party: [hero], enemies: [enemy, other], content: content).captureStatus(of: 10) else {
                return nil
            }
            return chance
        }
        let full = chance(at: stats.hp), half = chance(at: stats.hp / 2), weak = chance(at: 1)
        #expect(full != nil && half != nil && weak != nil)
        if let full, let half, let weak {
            // The weaker it is, the better the odds: a long shot at full HP, and not easy even at 1 HP.
            #expect(full < half && half < weak)
            #expect(full < 0.1)
            #expect(weak > 0.2 && weak < 0.6)
        }
        // Wounds count ×0.25 at full HP, ×1 at 20% and ×3 at the very end (below 20% as before).
        #expect(abs(BattleEngine.captureWeakness(atHP: 1) - 0.25) < 0.000_1)
        #expect(abs(BattleEngine.captureWeakness(atHP: 0.2) - 1) < 0.000_1)
        #expect(abs(BattleEngine.captureWeakness(atHP: 0) - 3) < 0.000_1)
        // No stone holds a boss.
        let boss = Combatant(id: 12, side: .enemies, source: .wild("jelly"), name: "Boss", art: jelly.art, level: 5, element: jelly.element,
                             stats: stats, hp: 1, mp: 0, skills: [], captureRate: 0)
        #expect(BattleEngine(party: [hero], enemies: [boss], content: content).captureStatus(of: 12) == .impossible)
    }

    /// Moon, Heart and Star Seals hold more often than a plain Seal Stone, and a Wishing Seal always
    /// does, except on a boss.
    @Test func strongerSealStonesHoldMoreOftenAndAWishingSealAlways() throws {
        let content = Content.shared
        let jelly = try #require(content.monster("jelly"))
        let stats = jelly.stats(at: 1)
        let hero = Combatant(id: 0, side: .party, source: .hero, name: "Hero", art: "player_walk", level: 1, element: .neutral,
                             stats: Stats(hp: 60, attack: 10, defense: 8, speed: 10), hp: 60, mp: 0, skills: [], captureRate: 0)
        let enemy = Combatant(id: 10, side: .enemies, source: .wild("jelly"), name: "Jelly", art: jelly.art, level: 1, element: jelly.element,
                              stats: stats, hp: stats.hp / 2, mp: 0, skills: [], captureRate: jelly.captureRate)
        let engine = BattleEngine(party: [hero], enemies: [enemy], content: content)
        func odds(_ stone: String?) -> Double? {
            guard case .ready(let chance) = engine.captureStatus(of: 10, with: stone.flatMap(content.item)) else { return nil }
            return chance
        }
        let plain = try #require(odds(nil))
        let moon = try #require(odds("moon_seal"))
        let heart = try #require(odds("heart_seal"))
        let star = try #require(odds("star_seal"))
        #expect(odds("seal_stone") == plain)
        #expect(plain < moon && moon < heart && heart < star)
        #expect(star <= BattleEngine.captureCeiling(power: 3))
        #expect(odds("wishing_seal") == 1)
        let boss = Combatant(id: 12, side: .enemies, source: .wild("jelly"), name: "Boss", art: jelly.art, level: 5, element: jelly.element,
                             stats: stats, hp: 1, mp: 0, skills: [], captureRate: 0)
        #expect(BattleEngine(party: [hero], enemies: [boss], content: content).captureStatus(of: 12, with: content.item("wishing_seal")) == .impossible)
    }

    /// A Seal Stone is used up whether it holds or not; Capture throws the plainest one you have and
    /// leaves a Wishing Seal for you to choose from Items.
    @Test func everyThrowUsesTheStoneAndCaptureKeepsTheWishingSeal() throws {
        let content = Content.shared
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let jelly = try #require(content.monster("jelly"))
        let stats = jelly.stats(at: 1)
        let hero = Combatant(id: 0, side: .party, source: .hero, name: "Hero", art: "player_walk", level: 1, element: .neutral,
                             stats: Stats(hp: 60, attack: 10, defense: 8, speed: 10), hp: 60, mp: 0, skills: [], captureRate: 0)
        let enemy = Combatant(id: 10, side: .enemies, source: .wild("jelly"), name: "Jelly", art: jelly.art, level: 1, element: jelly.element,
                              stats: stats, hp: 1, mp: 0, skills: [], captureRate: jelly.captureRate)
        let battle = BattleController(engine: BattleEngine(party: [hero], enemies: [enemy], content: content), session: session)
        session.addItem("wishing_seal")
        session.addItem("moon_seal", 2)
        #expect(battle.stones.map(\.id) == ["moon_seal", "wishing_seal"])
        battle.apply(.capture(actor: 0, target: 10, success: false, wobbles: 1, stone: "moon_seal"))
        #expect(session.count(of: "moon_seal") == 1)
        battle.apply(.capture(actor: 0, target: 10, success: true, wobbles: 3, stone: "moon_seal"))
        #expect(session.count(of: "moon_seal") == 0)
        // Only the Wishing Seal is left: Capture asks which stone instead of throwing it.
        battle.capture()
        #expect(battle.phase == .stones)
        #expect(session.count(of: "wishing_seal") == 1)
    }

    /// A friend's throw uses up one of their own Seal Stones, never one from your bag. Counting
    /// theirs used to trip Swift's exclusivity check and crash the fight.
    @Test func aFriendsThrowUsesTheirOwnStone() throws {
        let content = Content.shared
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let momo = Adventurer(name: "Momo", raceID: "elf", classID: "mage", level: 5, look: .standard)
        session.data.friends = [momo]
        session.addItem("seal_stone")
        let jelly = try #require(content.monster("jelly"))
        let stats = Stats(hp: 60, attack: 10, defense: 8, speed: 10)
        let hero = Combatant(id: 0, side: .party, source: .hero, name: "Hero", art: "player_walk", level: 5, element: .neutral,
                             stats: stats, hp: 60, mp: 0, skills: [], captureRate: 0)
        var ally = Combatant(id: 2, side: .party, source: .ally(momo.id), name: "Momo", art: "player_walk", level: 5, element: .neutral,
                             stats: stats, hp: 60, mp: 0, skills: [], captureRate: 0)
        ally.sealStones = momo.stonesLeft
        let enemy = Combatant(id: 10, side: .enemies, source: .wild("jelly"), name: "Jelly", art: jelly.art, level: 1, element: jelly.element,
                              stats: jelly.stats(at: 1), hp: 1, mp: 0, skills: [], captureRate: jelly.captureRate)
        let battle = BattleController(engine: BattleEngine(party: [hero, ally], enemies: [enemy], content: content), session: session)
        battle.apply(.capture(actor: 2, target: 10, success: false, wobbles: 1))
        #expect(session.friends.first?.sealStones == momo.stonesLeft - 1)
        #expect(session.count(of: "seal_stone") == 1)
    }

    /// With one monster there's no choosing which: Attack goes straight for it. With two, you pick.
    @Test func aLoneTargetNeedsNoPicking() throws {
        let content = Content.shared
        let jelly = try #require(content.monster("jelly"))
        let hero = Combatant(id: 0, side: .party, source: .hero, name: "Hero", art: "player_walk", level: 1, element: .neutral,
                             stats: Stats(hp: 60, attack: 10, defense: 8, speed: 10), hp: 60, mp: 0, skills: [], captureRate: 0)
        func monster(_ id: Int) -> Combatant {
            Combatant(id: id, side: .enemies, source: .wild("jelly"), name: "Jelly", art: jelly.art, level: 1, element: jelly.element,
                      stats: jelly.stats(at: 1), hp: 30, mp: 0, skills: [], captureRate: jelly.captureRate)
        }
        let alone = BattleController(engine: BattleEngine(party: [hero], enemies: [monster(10)], content: content),
                                     session: GameSession.newGame(name: "Test", raceID: "human"))
        alone.attack()
        #expect(alone.phase != .target)
        let pair = BattleController(engine: BattleEngine(party: [hero], enemies: [monster(10), monster(11)], content: content),
                                    session: GameSession.newGame(name: "Test", raceID: "human"))
        pair.attack()
        #expect(pair.phase == .target)
        #expect(pair.validTargets == [10, 11])
    }

    /// While you throw a Seal Stone, your companion and your friends leave that monster alone and
    /// fight on against the rest (they used to stand guard, which only made sense with one left).
    @Test func yourSideSparesTheMonsterYouSeal() {
        let content = Content.shared
        let jelly = content.monster("jelly")!
        let tough = Stats(hp: 500, mp: 0, attack: 40, defense: 30, magic: 10, speed: 5)
        let hero = Combatant(id: 0, side: .party, source: .hero, name: "Hero", art: "player_walk", level: 40, element: .neutral,
                             stats: tough, hp: 500, mp: 0, skills: [], captureRate: 0)
        let pet = Combatant(id: 1, side: .party, source: .pet(UUID()), name: "Pet", art: jelly.art, level: 40, element: .neutral,
                            stats: tough, hp: 500, mp: 0, skills: [], captureRate: 0)
        let friend = Combatant(id: 2, side: .party, source: .ally(UUID()), name: "Maple", art: "player_walk", level: 40, element: .neutral,
                               stats: tough, hp: 500, mp: 0, skills: [], captureRate: 0)
        // The one you seal is the weakest, the one they'd go for first.
        let stats = jelly.stats(at: 1)
        let sealed = Combatant(id: 10, side: .enemies, source: .wild("jelly"), name: "Jelly", art: jelly.art, level: 1, element: jelly.element,
                               stats: stats, hp: 1, mp: 0, skills: [], captureRate: jelly.captureRate)
        let other = Combatant(id: 11, side: .enemies, source: .wild("jelly"), name: "Jelly B", art: jelly.art, level: 1, element: jelly.element,
                              stats: stats, hp: 9_999, mp: 0, skills: [], captureRate: jelly.captureRate)
        for seed in UInt64(1)...6 {
            let engine = BattleEngine(party: [hero, pet, friend], enemies: [sealed, other], content: content, seed: seed)
            _ = engine.resolveRound(heroAction: .capture(target: 10))
            // Sealed or broken free, it's untouched; the other one took their blows.
            #expect(engine.combatant(10)!.hp == 1)
            #expect(engine.combatant(11)!.hp < 9_999)
            #expect(engine.outcome == .ongoing)
        }
    }

    /// A monster in a boss's wave can be sealed too: a sealed monster is yours however the fight
    /// ends, so a later wave can't take it from you.
    @Test func sealingWorksWhileABossWaveIsToCome() {
        let content = Content.shared
        let jelly = content.monster("jelly")!
        let stats = jelly.stats(at: 1)
        let hero = Combatant(id: 0, side: .party, source: .hero, name: "Hero", art: "player_walk", level: 1, element: .neutral,
                             stats: Stats(hp: 60, attack: 10, defense: 8, speed: 10), hp: 60, mp: 0, skills: [], captureRate: 0)
        let weak = Combatant(id: 10, side: .enemies, source: .wild("jelly"), name: "Jelly", art: jelly.art, level: 1, element: jelly.element,
                             stats: stats, hp: 1, mp: 0, skills: [], captureRate: jelly.captureRate)
        var boss = Combatant(id: 20, side: .enemies, source: .wild("jelly"), name: "Boss", art: jelly.art, level: 5, element: jelly.element,
                             stats: stats, hp: stats.hp, mp: 0, skills: [], captureRate: 0)
        boss.wave = 2
        guard case .ready = BattleEngine(party: [hero], enemies: [weak], content: content, waves: [[boss]]).captureStatus(of: 10) else {
            Issue.record("expected a monster in a boss's wave to be sealable")
            return
        }
    }

    #if DEBUG
    /// A beaten boss always drops a piece of gear, however much its two waves of followers dropped
    /// first (two pieces a fight at most, and the boss used to roll last).
    @Test func aBeatenBossAlwaysDropsGear() throws {
        let content = Content.shared
        let npc = try #require(content.boss(fighting: "rat_king"))
        let boss = try #require(content.monster("rat_king"))
        let encounters = try #require(content.home(ofNPC: npc.id)?.encounters)
        for _ in 0..<4 {
            let session = GameSession.newGame(name: "Test", raceID: "human")
            let fight = try #require(BattleController.boss(npc, encounters: encounters, session: session))
            fight.winForDebug()
            let result = try #require(fight.result)
            let bossDropped = result.loot.contains { found in
                guard let item = content.item(found.id) else { return false }
                return result.lines.contains(L("{name} dropped {item}!", ["name": boss.name, "item": item.name]))
            }
            #expect(bossDropped)
        }
    }
    #endif

    @Test func fullPartyLeavesSomeoneBehind() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        for _ in 0..<GameSession.maxPets {
            #expect(session.addPet(session.makePet(species: "jelly", level: 1)!, countsForQuests: false))
        }
        let newcomer = session.makePet(species: "bunny", level: 3)!
        #expect(!session.addPet(newcomer, countsForQuests: false))
        session.pendingPet = newcomer
        let parting = session.data.pets[2]
        session.leaveBehind(parting.id)
        #expect(session.data.pets.count == GameSession.maxPets)
        #expect(session.data.pets.contains { $0.id == newcomer.id })
        #expect(!session.data.pets.contains { $0.id == parting.id })
        #expect(session.pendingPet == nil)
    }

    @Test func eachGameHasItsOwnSave() {
        let first = GameSession.newGame(name: "One", raceID: "human")
        let second = GameSession.newGame(name: "Two", raceID: "elf")
        #expect(first.data.slot != nil && first.data.slot != second.data.slot)
        first.save()
        second.save()
        let names = Set(SaveStore.all().map(\.hero.name))
        #expect(names.isSuperset(of: ["One", "Two"]))
        if let slot = first.data.slot { SaveStore.delete(slot: slot) }
        #expect(!SaveStore.all().contains { $0.slot == first.data.slot })
        #expect(SaveStore.all().contains { $0.slot == second.data.slot })
        if let slot = second.data.slot { SaveStore.delete(slot: slot) }
    }

    @Test func oldSavesWithFriendsRescale() {
        // 0.1.0 saves: levels from before the stretch, and friends to scale up too. This used to
        // trip Swift's exclusivity check and crash on Continue.
        var data = GameSession.newGame(name: "Test", raceID: "human").data
        data.hero.level = 10
        data.levelsRescaled = nil
        data.friends = [Adventurer(name: "Momo", raceID: "elf", classID: "mage", level: 8, look: .standard)]
        let session = GameSession(data: data)
        session.rescaleLevelsIfNeeded()
        #expect(session.data.hero.level == GameSession.stretchedLevel(10))
        #expect(session.friends.first?.level == GameSession.stretchedLevel(8))
        #expect(session.data.levelsRescaled == true)
    }

    @Test func friendsJoinTheParty() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        session.data.hero.level = 6
        let momo = Adventurer(name: "Momo", raceID: "elf", classID: "mage", level: 4, look: .standard, petSpecies: "jelly")
        let grump = Adventurer(name: "Grump", raceID: "dwarf", classID: "fighter", level: 7, look: .standard, hostile: true)
        #expect(!session.befriend(grump))
        #expect(session.befriend(momo))
        // Only friends walking around nearby can join.
        session.invite(momo.id)
        #expect(session.partyMembers.isEmpty)
        session.adventurersAround = [momo.id]
        session.invite(momo.id)
        #expect(session.partyMembers.map(\.name) == ["Momo"])
        // Friends keep up with you.
        #expect(session.partyMembers[0].level == 5)
        let controller = BattleController.duel(with: grump, session: session)
        #expect(controller.party.contains { $0.name == "Momo" })
        // Momo's companion comes along, named for Momo, and stands behind Momo.
        #expect(controller.party.contains { $0.name == "Momo's Jelly Puff" && $0.petID != nil })
        let fighter = controller.party.first { $0.name == "Momo" }
        #expect(fighter != nil && controller.party.first { $0.name == "Momo's Jelly Puff" }?.ownerID == fighter?.id)
        #expect(controller.party.first { $0.name == "Momo" }?.classID == "mage")
        #expect(controller.enemies.map(\.name) == ["Grump"])
        session.leaveParty(momo.id)
        #expect(session.partyMembers.isEmpty)
        #expect(session.friends.count == 1)
    }

    @Test func friendsSayWhenTheyGoUpALevelWithYou() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        session.data.hero.level = 30
        let momo = Adventurer(name: "Momo", raceID: "elf", classID: "mage", level: 27, look: .standard)
        let pip = Adventurer(name: "Pip", raceID: "human", classID: "fighter", level: 40, look: .standard)
        #expect(session.befriend(momo))
        #expect(session.befriend(pip))
        session.adventurersAround = [momo.id, pip.id]
        session.invite(momo.id)
        session.invite(pip.id)
        // You go up a level: Momo keeps a level behind you and says so; Pip, already past you, doesn't.
        session.data.hero.level = 31
        let grown = session.growParty()
        #expect(grown.map { $0.name } == ["Momo"])
        #expect(grown.first?.level == 30)
        #expect(session.growParty().isEmpty)
    }

    @Test func theOldSaveMovesInOnceAndCopiesCollapse() throws {
        let manager = FileManager.default
        try? manager.removeItem(at: SaveStore.folder)
        defer {
            try? manager.removeItem(at: SaveStore.folder)
            try? manager.removeItem(at: SaveStore.legacyURL)
        }
        // A save from before the folder (no slot), in Application Support: a path with a space.
        var old = GameSession.newGame(name: "Old", raceID: "human").data
        old.slot = nil
        try manager.createDirectory(at: SaveStore.legacyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(old).write(to: SaveStore.legacyURL)
        // However often the title screen looks, it moves in once, and the old file goes.
        for _ in 0..<3 { _ = SaveStore.all() }
        #expect(SaveStore.all().filter { $0.hero.name == "Old" }.count == 1)
        #expect(!manager.fileExists(atPath: SaveStore.legacyURL.path(percentEncoded: false)))
        // Copies that differ only in their slot (what the old bug left behind) collapse to one.
        var copy = old
        for _ in 0..<2 {
            copy.slot = UUID().uuidString
            SaveStore.save(copy)
        }
        #expect(SaveStore.all().filter { $0.hero.name == "Old" }.count == 1)
        // A copy you played on is a game of its own, and stays.
        copy.slot = UUID().uuidString
        copy.gold += 100
        SaveStore.save(copy)
        #expect(SaveStore.all().filter { $0.hero.name == "Old" }.count == 2)
    }

    @Test func aFullPartyBringsItsCompanions() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let friends = (0..<5).map { index in
            Adventurer(name: "Friend \(index)", raceID: "elf", classID: "mage", level: 4, look: .standard, petSpecies: "jelly")
        }
        for friend in friends { #expect(session.befriend(friend)) }
        session.adventurersAround = Set(friends.map(\.id))
        for friend in friends { session.invite(friend.id) }
        // Four friends travel with you; the fifth waits for a place.
        #expect(GameSession.maxAllies == 4)
        #expect(session.partyMembers.count == 4)
        let rival = Adventurer(name: "Grump", raceID: "dwarf", classID: "fighter", level: 7, look: .standard, hostile: true)
        let controller = BattleController.duel(with: rival, session: session)
        // Each brings their companion, and nobody on your side shares an id with the other (10 and up).
        #expect(controller.party.filter { $0.petID != nil }.count == 4)
        let ids = controller.party.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.allSatisfy { $0 < 10 })
    }

    @Test func thePartySplitsWhenSomeoneFaints() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let maple = Adventurer(name: "Maple", raceID: "human", classID: "mage", level: 10, look: .standard)
        let kip = Adventurer(name: "Kip", raceID: "elf", classID: "fighter", level: 10, look: .standard)
        for friend in [maple, kip] { #expect(session.befriend(friend)) }
        session.adventurersAround = [maple.id, kip.id]
        session.invite(maple.id)
        session.invite(kip.id)
        // Out in Sunny Meadow, having come from Meadowbrook: everyone's checkpoint is the town.
        let town = try #require(Content.shared.map("meadowbrook"))
        session.reachCheckpoint(town)
        let meadow = try #require(Content.shared.map("sunny_meadow"))
        session.data.mapID = meadow.id
        session.reachCheckpoint(meadow)
        session.playerPosition = CGPoint(x: 100, y: 50)
        let square = Spot(mapID: town.id, entry: nil)

        // Kip faints, but the fight is won: Kip wakes up in town and waits there.
        _ = session.partWays(fainted: [kip.id], heroFainted: false)
        #expect(session.friendsAtYourSide.map(\.name) == ["Maple"])
        #expect(session.friends.first { $0.id == kip.id }?.waitingAt == square)

        // You fall with Maple still standing: you wake up in town, and Maple waits where you fell.
        let lines = session.partWays(fainted: [], heroFainted: true)
        #expect(lines == ["You wake up at \(town.name), a little bruised.", "Maple waits for you where you fell."])
        #expect(session.data.mapID == town.id)
        #expect(session.friends.first { $0.id == maple.id }?.waitingAt == Spot(mapID: meadow.id, position: [100, 50]))
        // Both are still in your party, but they don't fight until you come back for them.
        #expect(session.partyMembers.count == 2 && session.friendsAtYourSide.isEmpty)
        let encounters = try #require(meadow.encounters)
        #expect(!BattleController.encounter(encounters, session: session).party.contains { $0.isAlly })
        session.rejoin(maple.id)
        #expect(session.friendsAtYourSide.map(\.name) == ["Maple"])

        // Falling together, a friend who saved where you did wakes up beside you.
        let together = session.partWays(fainted: [maple.id], heroFainted: true)
        #expect(together.first == "You and Maple wake up at \(town.name), a little bruised.")
        #expect(session.friendsAtYourSide.map(\.name) == ["Maple"])
    }

    @Test func youWakeUpInTheLastTownYouVisited() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let content = Content.shared
        let towns = content.maps.filter { $0.fence == true }
        #expect(towns.count >= 4)
        // Walking into a wild map keeps the town you came from as your checkpoint.
        let town = try #require(towns.first { $0.id != content.startMap })
        session.reachCheckpoint(town)
        let wild = try #require(content.maps.first { $0.fence != true && $0.encounters != nil && $0.exits.contains { $0.to == town.id } })
        session.reachCheckpoint(wild)
        #expect(session.checkpoint == Checkpoint(mapID: town.id, entry: nil))
        // An older save that kept a wild map's entrance wakes up in the town nearest to it instead.
        for map in content.maps where map.fence != true {
            session.data.checkpoint = Checkpoint(mapID: map.id, entry: .west)
            let point = session.checkpoint
            #expect(point.entry == nil)
            #expect(content.map(point.mapID)?.fence == true, "\(map.id) → \(point.mapID)")
        }
        // Feathers for the way home: now and then after a fight, always after a boss.
        #expect(GameSession.featherDropChance(boss: true) == 1)
        #expect((0.03...0.2).contains(GameSession.featherDropChance(boss: false)))
        #expect(content.item(GameSession.featherID)?.travel == true)
    }

    @Test func botsAreTagged() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        session.postChat("hi!", from: "Momo", kind: .adventurer)
        #expect(session.chat.last?.badge == .bot)
        // You, and the people of the world, wear no tag.
        session.postChat("hello", from: "Test", kind: .you)
        #expect(session.chat.last?.badge == nil)
        session.postChat("Welcome!", from: "Elder Oak", kind: .npc)
        #expect(session.chat.last?.badge == nil)
    }

    @Test func theWeatherHoldsForASpellAndFitsTheMap() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let swamp = try #require(Content.shared.map("frog_swamp"))
        let desert = try #require(Content.shared.map("genie_desert"))
        let cave = try #require(Content.shared.map("rat_cavern"))
        // A cave has no sky; everywhere else always has some weather. (With the weather switched on,
        // whatever this simulator's Settings say.)
        #expect(Weather.on(cave, at: start, since: start, changing: true) == nil)
        var seen: Set<Weather> = []
        for hour in 0..<(24 * 30) {
            let date = start.addingTimeInterval(Double(hour) * 60)
            let weather = try #require(Weather.on(swamp, at: date, since: start, changing: true))
            seen.insert(weather)
            // The desert's sky never rains, fogs or snows.
            let dry = try #require(Weather.on(desert, at: date, since: start, changing: true))
            #expect(dry == .clear || dry == .cloudy)
            // The same moment gives the same weather, so walking off and back doesn't reroll it.
            #expect(Weather.on(swamp, at: date, since: start, changing: true) == weather)
        }
        // Over a month of in-game days the swamp sees more than one kind.
        #expect(seen.count > 1)
        #expect(seen.isSubset(of: [.clear, .cloudy, .rain, .storm, .fog]))
        // The light follows the clock: the fractional hours agree with the calendar's hour. Nine
        // daylight minutes bring 18hr; then the night's hours go by half again as fast.
        let evening = start.addingTimeInterval(9.5 * 60)
        #expect(GameClock.moment(at: evening, since: start).hour == 18)
        #expect(abs(GameClock.hours(at: evening, since: start) - 18.75) < 0.001)
    }

    @Test func nightsAreShortAndShowersBlowOver() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        // A day is twelve real minutes of daylight and an eight-minute night.
        var night = 0
        for second in 0..<Int(GameClock.dayMinutes * 60) {
            if !GameClock.moment(at: start.addingTimeInterval(Double(second)), since: start).isDaytime { night += 1 }
        }
        #expect(abs(Double(night) / 60 - 8) < 0.05)
        // Debug launches can open at any hour of the day.
        for hour in 0..<24 {
            let date = start.addingTimeInterval(GameClock.minutes(untilHour: hour) * 60 + 1)
            #expect(GameClock.moment(at: date, since: start).hour == hour)
        }
        // Rain and storms come and go within about a real minute.
        let swamp = try #require(Content.shared.map("frog_swamp"))
        var wet = 0
        var longest = 0
        for second in stride(from: 0, to: 60 * 60 * 24, by: 5) {
            let weather = Weather.on(swamp, at: start.addingTimeInterval(Double(second)), since: start, changing: true)
            wet = weather == .rain || weather == .storm ? wet + 5 : 0
            longest = max(longest, wet)
        }
        #expect(longest > 0)
        #expect(longest <= 65)
        // With the weather switched off in Settings, the sky stays clear all day.
        for second in stride(from: 0, to: 60 * 60 * 24, by: 60) {
            #expect(Weather.on(swamp, at: start.addingTimeInterval(Double(second)), since: start, changing: false) == .clear)
        }
    }

    @Test func announcementsFollowYouFromMapToMap() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        session.startChat(on: "Meadowbrook")
        session.announce("Dawn breaks over Storyleaf.")
        session.postChat("lol", from: "Momo", kind: .adventurer)
        session.startChat(on: "Ingothold")
        // The game's own notices stay; the map's own chatter starts over.
        #expect(session.chat.map(\.kind) == [.announcement, .system])
        #expect(session.log.contains { $0.kind == .announcement })
    }

    @Test func aRareSightingMakesItTurnUpMoreOften() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let meadow = try #require(Content.shared.map("sunny_meadow"))
        let encounters = try #require(meadow.encounters)
        let rare = try #require(encounters.monsters.keys.first { Content.shared.monster($0)?.rare == true })
        let base = try #require(encounters.monsters[rare])
        session.data.mapID = meadow.id
        #expect(BattleController.encounterWeights(encounters, session: session)[rare] == base)
        session.sighting = GameSession.Sighting(mapID: meadow.id, monsterID: rare, boost: 6, until: Date().addingTimeInterval(60))
        #expect(BattleController.encounterWeights(encounters, session: session)[rare] == base * 6)
        // Only on its own map, and only until it's over.
        session.data.mapID = "meadowbrook"
        #expect(BattleController.encounterWeights(encounters, session: session)[rare] == base)
        session.data.mapID = meadow.id
        session.sighting = GameSession.Sighting(mapID: meadow.id, monsterID: rare, boost: 6, until: Date().addingTimeInterval(-1))
        #expect(BattleController.encounterWeights(encounters, session: session)[rare] == base)
    }

    @Test func marketTradersCallOutTheirDeals() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let trader = Adventurer(name: "Momo", raceID: "dwarf", classID: "fighter", level: 30, look: .standard)
        let offers = session.tradeOffers(with: trader)
        // The sign shows something they really sell today, and what they call out is a real deal.
        let sign = try #require(session.marketSign(for: trader))
        #expect(offers.contains { $0.kind == .theySell && sign == "\($0.item.name) · \($0.price)g" })
        let shout = try #require(session.marketShout(for: trader))
        #expect(offers.contains { shout.contains($0.item.name) && shout.contains("\($0.price)") })
    }

    @Test func botsWearArmourForTheirClassAndLevel() {
        func bot(_ classID: String, _ level: Int) -> Adventurer {
            Adventurer(name: "Momo", raceID: "elf", classID: classID, level: level, look: .standard)
        }
        var worn: Set<String> = []
        for _ in 0..<60 {
            for (classID, level) in [("novice", 5), ("fighter", 45), ("mage", 45), ("tamer", 70), ("fighter", 90)] {
                let someone = bot(classID, level)
                let armor = GameSession.armor(for: someone)
                #expect(armor?.type == .armor)
                #expect((armor?.level ?? 1) <= level, "\(armor?.id ?? "-") is above level \(level)")
                #expect(armor?.classes?.contains(classID) ?? true, "a \(classID) can't wear \(armor?.id ?? "-")")
                // The same adventurer always wears the same.
                #expect(GameSession.armor(for: someone)?.id == armor?.id)
                if let armor { worn.insert(armor.id) }
            }
        }
        // ...but the crowd doesn't all wear the same, and past their first steps it isn't a tunic.
        #expect(worn.count >= 8)
        #expect((GameSession.armor(for: bot("fighter", 45))?.level ?? 1) >= 14)
        #expect(!GameSession.wearsBoots(bot("fighter", 30)))
    }

    @Test func botsFightWithAWeaponForTheirClassAndLevel() {
        var held: Set<String> = []
        for _ in 0..<60 {
            for (classID, level) in [("novice", 5), ("fighter", 45), ("mage", 45), ("tamer", 70), ("fighter", 90)] {
                let someone = Adventurer(name: "Momo", raceID: "elf", classID: classID, level: level, look: .standard)
                let weapon = GameSession.weapon(for: someone)
                #expect(weapon?.type == .weapon)
                #expect((weapon?.level ?? 1) <= level, "\(weapon?.id ?? "-") is above level \(level)")
                #expect(weapon?.classes?.contains(classID) ?? true, "a \(classID) can't hold \(weapon?.id ?? "-")")
                // The same adventurer always holds the same.
                #expect(GameSession.weapon(for: someone)?.id == weapon?.id)
                if let weapon { held.insert(weapon.id) }
            }
        }
        #expect(held.count >= 8)
    }

    @Test func aBackupComesBackAsAGameOfItsOwn() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        session.data.hero.level = 12
        let game = try SaveStore.imported(try JSONEncoder().encode(session.data))
        #expect(game.hero.name == "Test" && game.hero.level == 12)
        // A slot of its own, so it never overwrites the game it was made from.
        #expect(game.slot != nil && game.slot != session.data.slot)
        #expect(throws: (any Error).self) { try SaveStore.imported(Data("not a save".utf8)) }
    }

    @Test func autoFightsOnlyMonstersWellBelowYou() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let meadow = try #require(Content.shared.map("sunny_meadow")?.encounters)
        let lowest = meadow.levels.first ?? 1
        let highest = meadow.levels.last ?? lowest
        session.data.hero.level = highest + BattleController.autoLevelGap
        #expect(BattleController.encounter(meadow, session: session).canAuto)
        // Every monster here is within a few levels of you: you fight it yourself.
        session.data.hero.level = lowest + BattleController.autoLevelGap - 1
        #expect(!BattleController.encounter(meadow, session: session).canAuto)
        // Never in a duel.
        session.data.hero.level = 60
        let rival = Adventurer(name: "Grump", raceID: "dwarf", classID: "fighter", level: 1, look: .standard, hostile: true)
        #expect(!BattleController.duel(with: rival, session: session).canAuto)
    }

    @Test func theHeroOnAutoFightsLikeAFriend() {
        let content = Content.shared
        let jelly = content.monster("jelly")!
        let stats = Stats(hp: 200, mp: 100, attack: 30, defense: 10, magic: 20, speed: 10)
        var hero = Combatant(id: 0, side: .party, source: .hero, name: "Hero", art: "player_walk", level: 40, element: .neutral,
                             stats: stats, hp: 200, mp: 100, skills: ["first_aid"], captureRate: 0)
        hero.skillLevels = ["first_aid": 1]
        let friend = Combatant(id: 2, side: .party, source: .ally(UUID()), name: "Maple", art: "player_walk", level: 40, element: .neutral,
                               stats: stats, hp: 30, mp: 0, skills: [], captureRate: 0)
        let foe = Combatant(id: 10, side: .enemies, source: .wild("jelly"), name: "Jelly", art: jelly.art, level: 1, element: jelly.element,
                            stats: jelly.stats(at: 1), hp: 5, mp: 0, skills: [], captureRate: 0)
        let engine = BattleEngine(party: [hero, friend], enemies: [foe], content: content, seed: 2)
        // A friend in trouble is healed first, as a friend would; then it's the monster's turn to fall.
        guard case .skill(let skill, let target) = engine.autoAction(for: 0) else {
            Issue.record("expected First Aid on Maple")
            return
        }
        #expect(skill == "first_aid" && target == 2)
    }

    /// Friends (and you on Auto) weigh their moves: a plain blow for a monster it would finish off,
    /// a sweep for a crowd, a spell's element where it's a weak spot.
    @Test func adventurersMakeEducatedChoices() {
        let content = Content.shared
        let jelly = content.monster("jelly")!
        func hero(_ skills: [String], stats: Stats) -> Combatant {
            var hero = Combatant(id: 0, side: .party, source: .hero, name: "Hero", art: "player_walk", level: 30, element: .neutral,
                                 stats: stats, hp: stats.hp, mp: stats.mp, skills: skills, captureRate: 0)
            hero.skillLevels = Dictionary(uniqueKeysWithValues: skills.map { ($0, 1) })
            return hero
        }
        func foe(_ id: Int, hp: Int, element: Element = .water) -> Combatant {
            Combatant(id: id, side: .enemies, source: .wild("jelly"), name: "Jelly", art: jelly.art, level: 30, element: element,
                      stats: Stats(hp: 1_000, mp: 0, attack: 5, defense: 10, magic: 5, speed: 1), hp: hp, mp: 0, skills: [], captureRate: 0)
        }
        let fighter = Stats(hp: 500, mp: 100, attack: 30, defense: 10, magic: 5, speed: 10)

        // A monster one plain blow would beat isn't worth MP.
        let finishing = BattleEngine(party: [hero(["power_strike"], stats: fighter)], enemies: [foe(10, hp: 1)], content: content, seed: 1)
        guard case .attack(let target) = finishing.autoAction(for: 0) else {
            Issue.record("expected a plain blow on the nearly beaten monster")
            return
        }
        #expect(target == 10)

        // A crowd is swept.
        let crowd = (10..<14).map { foe($0, hp: 1_000) }
        let sweeping = BattleEngine(party: [hero(["whirlwind", "bash"], stats: fighter)], enemies: crowd, content: content, seed: 1)
        guard case .skill(let sweep, _) = sweeping.autoAction(for: 0) else {
            Issue.record("expected Whirlwind on the crowd")
            return
        }
        #expect(sweep == "whirlwind")

        // Fire goes where it's a weak spot (metal), not where it's resisted (water).
        let mage = Stats(hp: 500, mp: 100, attack: 10, defense: 10, magic: 60, speed: 10)
        let aiming = BattleEngine(party: [hero(["fire_bolt"], stats: mage)], enemies: [foe(10, hp: 1_000, element: .water), foe(11, hp: 1_000, element: .metal)],
                                  content: content, seed: 1)
        guard case .skill(let spell, let mark) = aiming.autoAction(for: 0) else {
            Issue.record("expected Fire Bolt")
            return
        }
        #expect(spell == "fire_bolt" && mark == 11)
    }

    @Test func monstersBeatenTogetherFallTogether() {
        let content = Content.shared
        let jelly = content.monster("jelly")!
        let stats = Stats(hp: 200, mp: 100, attack: 60, defense: 10, magic: 20, speed: 999)
        var hero = Combatant(id: 0, side: .party, source: .hero, name: "Hero", art: "player_walk", level: 40, element: .neutral,
                             stats: stats, hp: 200, mp: 100, skills: ["whirlwind"], captureRate: 0)
        hero.skillLevels = ["whirlwind": 1]
        let foes = (10..<13).map { id -> Combatant in
            Combatant(id: id, side: .enemies, source: .wild("jelly"), name: id == 11 ? "Fire Rat" : "Jelly", art: jelly.art, level: 1,
                      element: jelly.element, stats: jelly.stats(at: 1), hp: 1, mp: 0, skills: [], captureRate: 0)
        }
        let engine = BattleEngine(party: [hero], enemies: foes, content: content, seed: 5)
        let events = engine.resolveRound(heroAction: .skill("whirlwind", target: 10))
        let defeats = events.indices.filter { index in
            if case .defeated = events[index] { return true }
            return false
        }
        // The sweep's knock-outs come one after another, so the battle plays them as one.
        #expect(defeats.count == 3)
        #expect(defeats == Array((defeats.first ?? 0)..<((defeats.first ?? 0) + 3)))
        #expect(BattleController.tally(foes.map(\.name)) == "Jelly ×2 and Fire Rat")
        #expect(BattleController.tally(["Fire Rat"]) == "Fire Rat")
    }

    @Test func questsOpenRoads() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let road = Content.shared.map("sunny_meadow")!.exits.first { $0.to == "pineapple_shore" }!
        #expect(!session.canTravel(road))
        session.data.quests["jelly_trouble"] = QuestProgress(state: .completed, count: 3)
        #expect(session.canTravel(road))
    }

    @Test func bigSpellsSplash() {
        let fire = Content.shared.skill("fire_bolt")!
        #expect(BattleEngine.splashFraction(of: fire, level: 4) == 0)
        #expect(BattleEngine.splashFraction(of: fire, level: 5) > 0)
        #expect(BattleEngine.splashFraction(of: fire, level: 10) > BattleEngine.splashFraction(of: fire, level: 5))
        #expect(BattleEngine.splashFraction(of: Content.shared.skill("bash")!, level: 10) == 0)
    }
}

@MainActor
struct PerformanceTests {
    /// How long one map may take to build. An optimised build, like the App Store's, should do it in
    /// a few seconds. A debug build runs this code many times slower: in the CI tests job (a simulator
    /// on a shared runner) the biggest maps took up to 48 s, so there the bound only catches a map
    /// that's become pathologically slow, and the job's log lists every map's time (⏱) to watch.
    #if DEBUG
    static let mapBuildLimit: Duration = .seconds(90)
    #else
    static let mapBuildLimit: Duration = .seconds(3)
    #endif

    /// Every map must build, and quickly; this prints how long each one takes.
    @Test func mapsBuildQuickly() async {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        for def in Content.shared.maps {
            let clock = ContinuousClock()
            var grid: WorldMap?
            let gridTime = clock.measure { grid = WorldMap(def: def) }
            let start = clock.now
            let scene = WorldScene(map: def, session: session, input: InputState(), entry: nil)
            await scene.build { _ in }
            let sceneTime = clock.now - start
            #expect(scene.isBuilt)
            print("⏱ \(def.id): grid \(gridTime), scene \(sceneTime), cells \(grid!.columns * grid!.rows)")
            #expect(sceneTime < Self.mapBuildLimit, "\(def.id) took \(sceneTime) to build")
        }
    }
}

/// Reasons to come back (GameSession+Rewards.swift): titles, the daily gift, bounties, the Monster
/// Book's milestones and rebirth's quicker climb.
@MainActor
struct RewardTests {
    @Test func titlesAreEarnedOnceAndWorn() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let apprentice = try #require(Content.shared.title("apprentice"))
        #expect(!session.hasEarned(apprentice))
        let progress = session.titleProgress(apprentice)
        #expect(progress.have == 1 && progress.need == 10)
        session.data.hero.level = 10
        #expect(session.checkTitles().contains { $0.id == apprentice.id })
        // Earned once, and it stays earned (a rebirth takes the level back down).
        #expect(session.checkTitles().isEmpty)
        session.data.hero.level = 1
        #expect(session.hasEarned(apprentice))
        session.wear(apprentice)
        #expect(session.wornTitle?.id == apprentice.id)
        // Only an earned title can be worn.
        session.wear(try #require(Content.shared.title("legend")))
        #expect(session.wornTitle?.id == apprentice.id)
        session.wear(nil)
        #expect(session.wornTitle == nil)
        // A boss's title says which boss.
        let wolfbane = try #require(Content.shared.title("wolfbane"))
        #expect(session.titleRequirement(wolfbane).contains("Wolf"))
    }

    @Test func theDailyGiftComesOnceADayAndGoesRound() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        // A new game's first gift is the next day's: its first day has the story and the tour.
        session.data.giftDay = GameSession.dayKey(start)
        #expect(session.collectDailyGift(on: start) == nil)
        let gifts = Content.shared.rewards.dailyGifts
        for place in 1...(gifts.count + 1) {
            let day = start.addingTimeInterval(Double(place) * 24 * 3600)
            let gold = session.data.gold
            let gift = try #require(session.collectDailyGift(on: day))
            #expect(gift.day == (place - 1) % gifts.count + 1)
            #expect(session.data.gold == gold + gift.gold)
            #expect(session.collectDailyGift(on: day) == nil)
        }
        #expect(session.data.giftDays == gifts.count + 1)
    }

    @Test func bountiesStayAllDayCountAndPayOnce() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        session.data.hero.level = 12
        session.markVisited("sunny_meadow")
        session.markVisited("northern_grassland")
        let board = session.refreshBounties()
        #expect(board.bounties.count == Content.shared.rewards.bounties.perDay)
        // The same board all day.
        session.data.bounties = nil
        #expect(session.refreshBounties() == board)

        // Each win counts; a bounty pays once it's done, and only once; all claimed, the bonus.
        session.data.bounties = BountyBoard(day: GameSession.dayKey(), bounties: [Bounty(kind: .wins, count: 2, exp: 10, gold: 20)])
        session.noteBounties(beaten: [], sealed: 0, on: "sunny_meadow")
        #expect(session.data.bounties?.bounties.first?.progress == 1)
        #expect(session.claimBounty(0).isEmpty)
        session.noteBounties(beaten: [], sealed: 0, on: "sunny_meadow")
        let gold = session.data.gold
        #expect(!session.claimBounty(0).isEmpty)
        #expect(session.data.gold == gold + 20)
        #expect(session.claimBounty(0).isEmpty)
        #expect(session.data.bountiesDone == 1)
        #expect(session.canClaimBountyBonus)
        #expect(!session.claimBountyBonus().isEmpty)
        #expect(!session.canClaimBountyBonus)

        // Monsters count where they were beaten and by element; seals count as seals.
        let jelly = try #require(Content.shared.monster("jelly"))
        session.data.bounties = BountyBoard(day: GameSession.dayKey(), bounties: [
            Bounty(kind: .defeatOnMap, target: "sunny_meadow", count: 3, exp: 1, gold: 1),
            Bounty(kind: .defeatElement, target: jelly.element.rawValue, count: 3, exp: 1, gold: 1),
            Bounty(kind: .seal, count: 1, exp: 1, gold: 1),
        ])
        session.noteBounties(beaten: [jelly, jelly], sealed: 1, on: "frog_swamp")
        let bounties = try #require(session.data.bounties?.bounties)
        #expect(bounties[0].progress == 0)
        #expect(bounties[1].progress == 2)
        #expect(bounties[2].isDone)

        // A new day pays what was finished and left unclaimed, then brings a new board.
        session.data.bounties = BountyBoard(day: "2000-01-01", bounties: [Bounty(kind: .wins, count: 1, exp: 1, gold: 50)])
        session.data.bounties?.bounties[0].progress = 1
        let before = session.data.gold
        #expect(session.refreshBounties().day == GameSession.dayKey())
        #expect(session.data.gold >= before + 50)
    }

    @Test func aBountyOfAKindThatsGoneStillLoads() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        session.data.bounties = BountyBoard(day: "2026-10-06", bounties: [Bounty(kind: .wins, count: 3, exp: 1, gold: 1)])
        let json = try #require(String(data: JSONEncoder().encode(session.data), encoding: .utf8))
        let edited = json.replacingOccurrences(of: "\"kind\":\"wins\"", with: "\"kind\":\"gone\"")
        #expect(edited != json)
        let loaded = try JSONDecoder().decode(SaveData.self, from: Data(edited.utf8))
        let bounty = try #require(loaded.bounties?.bounties.first)
        #expect(bounty.type == nil)
        #expect(session.describe(bounty) == "An old bounty")
    }

    @Test func theMonsterBooksMilestonesPayOnce() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let first = try #require(session.nextBookMilestone)
        for monster in Content.shared.monsters.prefix(first.count) { session.sawMonster(monster.id, level: 1) }
        let gold = session.data.gold
        session.claimBookMilestones()
        #expect(session.data.gold == gold + first.reward.gold)
        #expect(session.data.bookRewards == [first.count])
        session.claimBookMilestones()
        #expect(session.data.gold == gold + first.reward.gold)
        #expect(session.nextBookMilestone?.count != first.count)
    }

    @Test func cardsGoInTheBookAndMakeYouStronger() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let monster = try #require(Content.shared.monsters.first { $0.rare != true && $0.boss != true })
        let before = session.heroStats
        let gain = session.cardGain(of: monster)
        #expect(gain != .zero)
        #expect(!session.hasCard(monster.id))
        session.findCard(of: monster)
        #expect(session.hasCard(monster.id))
        #expect(session.cardCount == 1)
        #expect(session.heroStats == before + gain)
        // A spare is sold on the spot: gold, and no more strength.
        let gold = session.data.gold
        session.findCard(of: monster)
        #expect(session.data.gold == gold + session.spareCardGold(monster))
        #expect(session.heroStats == before + gain)
        #expect(session.cards(of: monster.id) == 2)
        #expect(session.cardCount == 1)
    }

    @Test func everyCardIsWorthSomething() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        for monster in Content.shared.monsters {
            #expect(session.cardGain(of: monster) != .zero, "\(monster.id)'s card gives nothing")
            #expect(session.spareCardGold(monster) > 0)
        }
        // Rare monsters and bosses leave their cards more often.
        let common = try #require(Content.shared.monsters.first { $0.rare != true && $0.boss != true })
        let rare = try #require(Content.shared.monsters.first { $0.rare == true })
        let boss = try #require(Content.shared.monsters.first { $0.boss == true })
        #expect(session.cardChance(for: common) < session.cardChance(for: rare))
        #expect(session.cardChance(for: rare) < session.cardChance(for: boss))
    }

    @Test func cardQuestsAndTitlesCountKindsOfCard() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let quest = try #require(Content.shared.quest("models_wanted"))
        session.acceptQuest(quest.id)
        #expect(session.status(of: quest) == .active(progress: 0, goal: 5))
        for monster in Content.shared.monsters.prefix(5) { session.findCard(of: monster) }
        #expect(session.status(of: quest) == .ready)
        session.turnInQuest(quest.id)
        // The cards are only shown, never handed over; the toys are yours.
        #expect(session.cardCount == 5)
        #expect(session.count(of: "toy_bear") == 1)
        for monster in Content.shared.monsters.dropFirst(5).prefix(5) { session.findCard(of: monster) }
        let earned = session.checkTitles(quietly: true)
        #expect(earned.contains { $0.id == "card_collector" })
    }

    @Test func toysRaiseACompanionForGoodUpToTen() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let pet = try #require(session.makePet(species: "jelly", level: 5))
        session.addPet(pet, countsForQuests: false)
        let toy = try #require(Content.shared.item("toy_soldier"))
        let raise = try #require(toy.stats)
        let before = session.stats(of: pet)
        session.addItem(toy.id, 12)
        #expect(session.giveToy(toy.id, to: pet.id) != nil)
        let played = try #require(session.data.pets.first { $0.id == pet.id })
        #expect(session.stats(of: played) == before + raise)
        #expect(session.count(of: toy.id) == 11)
        for _ in 0..<12 { session.giveToy(toy.id, to: pet.id) }
        let full = try #require(session.data.pets.first { $0.id == pet.id })
        #expect(full.toys == GameSession.toysPerCompanion)
        #expect(session.stats(of: full) == before + raise * GameSession.toysPerCompanion)
        #expect(session.count(of: toy.id) == 12 - GameSession.toysPerCompanion)
        // A potion isn't a toy.
        session.addItem("potion")
        #expect(session.giveToy("potion", to: pet.id) == nil)
    }

    @Test func rebornHeroesClimbFaster() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        #expect(session.rebirthEXPBoost == 1)
        session.data.hero.rebirths = 1
        #expect(abs(session.rebirthEXPBoost - 1.2) < 0.0001)
        session.data.hero.rebirths = 9
        #expect(session.rebirthEXPBoost == 2)
    }

    @Test func botsWearTitlesThatFitTheirLevel() {
        let id = UUID()
        #expect(GameSession.botTitle(level: 5, id: id) == nil)
        #expect(GameSession.botTitle(level: 70, id: id)?.id == GameSession.botTitle(level: 70, id: id)?.id)
        let names = Set((0..<40).compactMap { _ in GameSession.botTitle(level: 70, id: UUID())?.name })
        #expect(names.isSubset(of: [Content.shared.title("veteran")?.name].compactMap { $0 }))
        #expect(!names.isEmpty)
    }
}
