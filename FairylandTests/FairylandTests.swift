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
                // Every exit needs a way back, or you'd get stuck: by the other side, but a cave's
                // road back out of its mouth inland by the other side from the way you walk in
                // (`Region.Road.into`), and the land's by the side its mouth is toward.
                let into = content.regions[map.id]?.roads[exit.to]?.into
                let outOfCave = content.regions[exit.to]?.roads[map.id]?.into != nil
                let side: Edge? = into.map(\.opposite) ?? (outOfCave ? nil : exit.edge.opposite)
                #expect(destination?.exits.contains { $0.to == map.id && (side == nil || $0.edge == side) } == true,
                        "map \(exit.to) has no \(side.map { "\($0)" } ?? "") exit back to \(map.id)")
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

    @Test func roadsIntoCavesEndAtAHillInland() throws {
        // Where a road leads into a cave, it ends inland (playtesting 2026-10-16: not at the edge of
        // the map, where its mountains stood out in the sea) at a rocky hill, the road climbing a
        // little to the cave's mouth in a wall of rock turned toward you (`WorldMap.raiseGate`).
        let tile = WorldMap.tileSize
        for def in content.maps where def.theme.cave == nil && def.town == nil {
            let map = Layouts.of(def)
            for exit in def.exits where content.map(exit.to)?.theme.cave != nil {
                let crag = map.crags.first { $0.edge == exit.edge }
                #expect(crag?.inland == true, "map \(def.id): no hill inland where its road leads into \(exit.to)")
                guard let crag else { continue }
                let hill = map.hills[crag.hill]
                let mouth = try #require(hill.mouth)
                func height(out: Double) -> CGFloat {
                    hill.height(atCells: mouth.x + mouth.into.x * out, mouth.y + mouth.into.y * out)
                }
                print("⛰ \(def.id) cave hill: \(Int(hill.highest)) high, mouth at \(Int(height(out: 0))), a wall \(Int(height(out: 1) - height(out: 0))) over it")
                // Its face is turned toward you: you walk north or east into it.
                #expect(mouth.into.x >= 0 && mouth.into.y >= 0, "map \(def.id): the cave's mouth faces away")
                // In a wall of rock at least 40 points taller a cell in, the hill rising on behind it.
                #expect(height(out: 1) - height(out: 0) > 40, "map \(def.id): no wall of rock over the cave's mouth")
                #expect(height(out: 5) > 50, "map \(def.id): no hill behind the cave's mouth")
                // A mountain over it, tall enough to have its top (playtesting 2026-10-16: 0.7.8's,
                // about 75 points, was too small).
                #expect(hill.highest >= 100, "map \(def.id): its cave's hill is only \(Int(hill.highest)) high")
                // The road reaches the mouth, climbing only a little, and you can walk it from the hub.
                let last = GridPoint(col: Int((mouth.x - mouth.into.x * 0.5).rounded(.down)),
                                     row: Int((mouth.y - mouth.into.y * 0.5).rounded(.down)))
                #expect(map.ground[last.row][last.col] == .path && map.isWalkable(last), "map \(def.id): the road doesn't reach the cave's mouth")
                #expect(!map.path(from: map.center(of: map.center), to: map.center(of: map.entryCell(from: exit.edge))).isEmpty,
                        "map \(def.id): no way from its middle to the cave's mouth")
                // Only through the mouth, and you don't arrive in it.
                #expect(map.exit(at: last)?.to == exit.to, "map \(def.id): the cave's mouth doesn't lead into \(exit.to)")
                let ways = (0..<map.rows).flatMap { row in (0..<map.columns).map { GridPoint(col: $0, row: row) } }
                    .filter { map.exit(at: $0)?.to == exit.to }
                #expect(ways.count <= Int(2 * mouth.half) + 1, "map \(def.id): \(ways.count) cells lead into \(exit.to)")
                #expect(map.exit(at: map.entryCell(from: exit.edge)) == nil, "map \(def.id): you'd come out of \(exit.to) in its mouth")
                // Partway up a slope, so it shows: not up in the air, and the hill rising behind it.
                #expect(height(out: 0) < 70, "map \(def.id): the cave's mouth stands \(height(out: 0)) up")
                #expect(height(out: mouth.depth) - height(out: 0) > 10, "map \(def.id): the cave's mouth is on the flat")
                // On the land itself, clear of its coast: none of it over the sea or down the shore.
                for cell in hill.cells {
                    #expect(map.owns(cell) && !map.isSunken(cell), "map \(def.id): its cave's hill reaches off the land at \(cell)")
                }
                // Its rock is a wall: you can walk on its foot and up its road to the mouth, never up
                // onto it.
                for cell in hill.cells where map.ground[cell.row][cell.col] != .path {
                    if hill.height(atCells: Double(cell.col) + 0.5, Double(cell.row) + 0.5) > WorldMap.cragFoot {
                        #expect(!map.isWalkable(cell), "map \(def.id): you can climb its rock at \(cell)")
                    }
                }
                // No road climbs it but its own, up to the mouth (playtesting 2026-10-16: Lotus Land's
                // road to the Rat Cavern ran up over the mountain's flank on its way from the hub).
                var climbed: [GridPoint] = []
                for cell in hill.cells where map.ground[cell.row][cell.col] == .path {
                    let dx = Double(cell.col) + 0.5 - mouth.x, dy = Double(cell.row) + 0.5 - mouth.y
                    let across = dx * mouth.along.x + dy * mouth.along.y, inward = dx * mouth.into.x + dy * mouth.into.y
                    if abs(across) <= 2.5, inward >= -Double(WorldMap.gateApproach) - 2, inward <= 1.5 { continue }
                    if hill.height(atCells: Double(cell.col) + 0.5, Double(cell.row) + 0.5) > 6 { climbed.append(cell) }
                }
                print("⛰ \(def.id) cave hill: \(Int(hill.lobes[0].across)) across")
                #expect(climbed.isEmpty, "map \(def.id): a road climbs its cave's hill at \(Array(climbed.prefix(5)))")
                // And it never leans out of sight.
                for cell in hill.cells where (cell.col + cell.row) % 3 == 0 {
                    let x = Double(cell.col) + 0.5, y = Double(cell.row) + 0.5, e = 0.1
                    let drop = (hill.height(atCells: x + e, y + e) - hill.height(atCells: x - e, y - e)) / (2 * e * tile)
                    #expect(drop > -0.65, "map \(def.id): its hill folds over at \(cell)")
                }
            }
        }
        // Nowhere else: no road from the meadow leads into a cave.
        #expect(Layouts.of(try #require(content.map("sunny_meadow"))).crags.isEmpty)
    }

    /// A road to a land over the sea (`MapDef.Exit.ship`) ends at a harbor: on the coast its exit's
    /// side faces, its pier out over the open sea, walked out to its end, where you step aboard the
    /// ship to the land it sails to, which has one back; and you come ashore by its own pier, its
    /// captain standing there.
    @Test func harborsSailBetweenTheLands() throws {
        let world = World.continent()
        var ships = 0
        for def in content.maps where content.world[def.id] != nil {
            for exit in def.exits where exit.ship == true {
                ships += 1
                let map = Layouts.of(def)
                let land = try #require(world.land(def.id))
                let harbor = try #require(map.harbors.first { $0.exit.to == exit.to }, "map \(def.id): no harbor for its ship to \(exit.to)")
                let road = harbor.road
                #expect(road.pier == exit.edge, "map \(def.id): its pier to \(exit.to) doesn't run \(exit.edge)")
                // The road reaches the coast, and you can walk it from the hub.
                #expect(map.owns(road.at) && map.isWalkable(road.at), "map \(def.id): its harbor's road ends off the land")
                #expect(map.ground[road.at.row][road.at.col] == .path, "map \(def.id): its road doesn't reach the harbor")
                #expect(!map.path(from: map.center(of: map.center), to: map.center(of: road.at)).isEmpty,
                        "map \(def.id): no way from its middle to the harbor")
                // Its pier: out over the sea, no land's, walked on.
                for cell in road.pierCells {
                    let there = world.world(cell, of: land)
                    #expect(world.land(at: there) == nil && world.isWalkable(there) && world.pier(at: there)?.id == def.id,
                            "map \(def.id): its pier's cell \(cell) isn't the sea's, to walk on")
                }
                let end = try #require(road.pierCell(along: Region.Road.pierLength, across: 0))
                #expect(!world.path(from: world.world(road.at, of: land), to: world.world(end, of: land)).isEmpty,
                        "map \(def.id): you can't walk out to the end of its pier")
                // Aboard at its end, not on the way out; ashore by its foot, on the land.
                #expect(road.boarding.allSatisfy { map.boarding(at: $0)?.to == exit.to }, "map \(def.id): its pier's end doesn't take you aboard")
                let first = try #require(road.pierCell(along: 1, across: 0))
                #expect(map.boarding(at: road.at) == nil && map.boarding(at: first) == nil, "map \(def.id): you'd board on the way out")
                let ashore = map.entryCell(from: exit.edge)
                #expect(map.owns(ashore) && map.isWalkable(ashore) && map.boarding(at: ashore) == nil,
                        "map \(def.id): you'd come ashore off the land")
                #expect(max(abs(ashore.col - road.at.col), abs(ashore.row - road.at.row)) <= 4, "map \(def.id): you come ashore away from its harbor")
                // Its captain stands by the pier, on the land.
                for local in def.locals ?? [] where local.home.at == "harbor" {
                    let spot = try #require(map.spot(of: local.home))
                    #expect(map.owns(spot) && max(abs(spot.col - road.at.col), abs(spot.row - road.at.row)) <= 5,
                            "map \(def.id): \(local.name) stands away from the harbor, at \(spot)")
                }
                // A ship sails back.
                let other = try #require(content.map(exit.to))
                #expect(other.exits.contains { $0.to == def.id && $0.ship == true && $0.edge == exit.edge.opposite },
                        "\(exit.to) has no ship back to \(def.id)")
            }
        }
        #expect(ships >= 2, "no ship sails anywhere")
        // The island is out at sea, a land of its own: no land next door.
        let isle = try #require(content.map("starfall_isle"))
        #expect(Continent.neighbours(of: isle).isEmpty, "Starfall Isle touches another land")
    }

    /// Before a land's laid out, its plain ground shows its roads (`ContinentScene.placeholderRoads`),
    /// meeting the road that comes over the border from the land next door, so the road never stops
    /// at the line while it's still being laid out (playtesting 2026-10-16).
    @Test func roadsRunOnOverPlaceholderGround() throws {
        var crossings = 0
        for def in content.maps {
            guard let origin = content.world[def.id], let region = content.regions[def.id] else { continue }
            let ours = ContinentScene.placeholderRoads(of: def, origin: origin)
            for exit in def.exits where exit.ship != true {
                guard let next = content.map(exit.to), let there = content.world[next.id], let road = region.roads[exit.to] else { continue }
                crossings += 1
                let theirs = ContinentScene.placeholderRoads(of: next, origin: there)
                let here = GridPoint(col: road.at.col + origin.col, row: road.at.row + origin.row)
                #expect(ours.contains(here), "\(def.id): its placeholder road to \(next.id) stops short of the border")
                #expect(theirs.contains(here.stepped(exit.edge)), "\(def.id) → \(next.id): the placeholder road over the border doesn't start at it")
            }
        }
        #expect(crossings > 40, "only \(crossings) roads cross a border")
    }

    /// Lands a road joins touch on the continent (content/world.json), and the road runs on across
    /// the border: where it leaves one land it comes into the next, on the same world cells, as wide.
    @Test func roadsRunOnIntoTheNextLand() throws {
        var maps: [String: WorldMap] = [:]
        func grid(_ def: MapDef) -> WorldMap {
            if let known = maps[def.id] { return known }
            let made = Layouts.of(def)
            maps[def.id] = made
            return made
        }
        /// The road's cells on `map` along the line through `cell` across the way `edge` goes (within
        /// 5 of it), in world cells along the line.
        func road(on map: WorldMap, at cell: GridPoint, across edge: Edge, origin: GridPoint) -> Set<Int> {
            let alongColumns = edge == .north || edge == .south
            return Set((-5...5).compactMap { step -> Int? in
                let spot = alongColumns ? GridPoint(col: cell.col + step, row: cell.row) : GridPoint(col: cell.col, row: cell.row + step)
                guard map.owns(spot), map.ground[spot.row][spot.col] == .path else { return nil }
                return alongColumns ? spot.col + origin.col : spot.row + origin.row
            })
        }
        for def in content.maps {
            guard let origin = content.world[def.id], let region = content.regions[def.id] else { continue }
            // (Over the sea by ship, the road ends at a harbor: `harborsSailBetweenTheLands`.)
            for exit in def.exits where exit.ship != true {
                guard let next = content.map(exit.to), let there = content.world[next.id],
                      let crossing = region.roads[exit.to], let back = content.regions[next.id]?.roads[def.id] else { continue }
                // The two crossings are side by side, over the line the way the exit goes.
                let over = crossing.at.stepped(exit.edge)
                #expect(GridPoint(col: over.col + origin.col - there.col, row: over.row + origin.row - there.row) == back.at,
                        "\(def.id) → \(next.id): the roads cross the border in different places")
                let map = grid(def), other = grid(next)
                let ours = road(on: map, at: crossing.at, across: exit.edge, origin: origin)
                let across = road(on: other, at: back.at, across: exit.edge, origin: there)
                #expect(!ours.isEmpty && ours == across,
                        "\(def.id) → \(next.id): the road doesn't run on (\(ours.sorted()) meets \(across.sorted()))")
            }
        }
        // Every land outside the caves is on the continent, with its shape.
        for def in content.maps where def.theme.cave == nil {
            #expect(content.world[def.id] != nil && content.regions[def.id] != nil, "\(def.id) has no place on the continent")
        }
    }

    /// Two lands see the border they share the same from either side: the same cells along it, the
    /// same road and quest across it, open on the same cells, so you can walk back the way you came;
    /// and the band where one gives way to the other shows the same land's ground at every cell.
    @Test func bordersAreTheSameFromEitherSide() {
        var maps: [String: WorldMap] = [:]
        func grid(_ def: MapDef) -> WorldMap {
            if let known = maps[def.id] { return known }
            let made = Layouts.of(def)
            maps[def.id] = made
            return made
        }
        for def in content.maps where content.world[def.id] != nil {
            for here in Continent.neighbours(of: def) {
                guard let back = Continent.neighbours(of: here.def).first(where: { $0.def.id == def.id }) else {
                    Issue.record("\(here.def.id) doesn't see \(def.id) next door")
                    continue
                }
                // The same pieces of border, in this land's cells.
                func key(_ a: GridPoint, _ b: GridPoint) -> [Int] { [a.col, a.row, b.col, b.row] }
                let ours = Set(here.border.map { key($0.inside, $0.outside) })
                let theirs = Set(back.border.map { pair in
                    key(GridPoint(col: pair.outside.col + here.offset.col, row: pair.outside.row + here.offset.row),
                        GridPoint(col: pair.inside.col + here.offset.col, row: pair.inside.row + here.offset.row))
                })
                #expect(ours == theirs, "\(def.id) | \(here.def.id): not the same border from both sides")
                #expect(here.quest == back.quest, "\(def.id) | \(here.def.id): a different quest from each side")
                #expect((here.exit == nil) == (back.exit == nil), "\(def.id) | \(here.def.id): a road from one side only")
                for pair in here.border {
                    let mine = here.local(pair.inside)
                    for (done, joined) in [(true, true), (false, true), (true, false), (false, false)] {
                        #expect(here.isOpen(over: pair.outside, done: { _ in done }, joined: joined) == back.isOpen(over: mine, done: { _ in done }, joined: joined),
                                "\(def.id) | \(here.def.id): open on one side only at \(pair.inside)")
                    }
                }
                // The band: every cell either side shows the same land's ground whichever of the two
                // works it out, and there's one between every two lands (a town's countryside too).
                let seam = grid(def).seams.first { $0.neighbour == here.def.id }
                let other = grid(here.def).seams.first { $0.neighbour == def.id }
                #expect(seam != nil && other != nil, "\(def.id) | \(here.def.id): no band between them, or from one side only")
                guard let seam, let other else { continue }
                var differ = 0
                for pair in here.border where (pair.inside.col + pair.inside.row) % 2 == 0 {
                    for dr in stride(from: -Seam.depth, through: Seam.depth, by: 3) {
                        for dc in stride(from: -Seam.depth, through: Seam.depth, by: 3) {
                            let cell = GridPoint(col: pair.inside.col + dc, row: pair.inside.row + dr)
                            guard seam.side(cell) != nil, other.side(here.local(cell)) != nil else { continue }
                            if seam.showsOther(cell) == other.showsOther(here.local(cell)) { differ += 1 }
                        }
                    }
                }
                #expect(differ == 0, "\(def.id) | \(here.def.id): \(differ) cells of the band show a different land from each side")
                // Where a road crosses, the cells over the line its tiles take for road are the land next
                // door's road, cell for cell, so the two roads' edges meet (playtesting 2026-10-16:
                // Ingothold's road into the Genie Desert stepped at the line).
                if let road = grid(def).region?.roads[here.def.id], road.into == nil {
                    let mine = grid(def), theirs = grid(here.def)
                    var unmet: [GridPoint] = []
                    for dr in -4...4 {
                        for dc in -4...4 {
                            let cell = GridPoint(col: road.at.col + dc, row: road.at.row + dr)
                            let local = here.local(cell)
                            guard !mine.owns(cell), theirs.owns(local) else { continue }
                            let beside = (-1...1).contains { dy in (-1...1).contains { dx in mine.owns(GridPoint(col: cell.col + dx, row: cell.row + dy)) } }
                            guard beside else { continue }
                            if mine.roadsPast.contains(cell) != (theirs.ground[local.row][local.col] == .path) { unmet.append(cell) }
                        }
                    }
                    #expect(unmet.isEmpty, "\(def.id) | \(here.def.id): its road takes \(unmet.count) cells over the line otherwise than there, first \(Array(unmet.prefix(3)))")
                }
                // Past the border, the cells round this land's own show to its tiles (`Blend.shows`)
                // what the land holding them lays out there, a third land's patches too, so a tile
                // meets the one past the border as it would its own (playtesting 2026-10-16).
                guard let blend = grid(def).blend else { continue }
                let near = grid(here.def)
                var seenWrong: [GridPoint] = []
                for pair in here.border {
                    for dr in -1...1 {
                        for dc in -1...1 {
                            let cell = GridPoint(col: pair.outside.col + dc, row: pair.outside.row + dr)
                            guard blend.around.owner(cell).map({ blend.around.lands[$0] }) == here.def.id else { continue }
                            let local = here.local(cell)
                            let theirs = near.foreign[local].map { near.seams[$0].neighbour } ?? here.def.id
                            if blend.shows(cell).map({ blend.around.lands[$0] }) != theirs { seenWrong.append(cell) }
                        }
                    }
                }
                #expect(seenWrong.isEmpty, "\(def.id) | \(here.def.id): \(seenWrong.count) cells past the border show otherwise than there, first \(Array(seenWrong.prefix(3)))")
            }
        }
    }

    /// A border no road crosses opens only once the roads you can take join its two lands anyway
    /// (`Continent.joined`), so walking over it never takes you round a quest: whatever quests are
    /// done, where you can go with the borders open is where the roads alone would take you.
    @Test func openBordersNeverSkipAQuest() {
        let quests = Set(content.maps.flatMap { $0.exits.compactMap(\.requires) }).sorted()
        let start = content.startMap
        for mask in 0..<(1 << quests.count) {
            let done = Set(quests.indices.filter { mask & (1 << $0) != 0 }.map { quests[$0] })
            let isDone: (String) -> Bool = { done.contains($0) }
            // Where the roads alone lead: those of these lands are joined to each other, no others.
            let reached = Continent.reachable(from: start, done: isDone)
            for def in content.maps where content.world[def.id] != nil && reached.contains(def.id) {
                for neighbour in Continent.neighbours(of: def) where neighbour.isCrossable(done: isDone, joined: reached.contains(neighbour.def.id)) {
                    #expect(reached.contains(neighbour.def.id),
                            "\(def.id) | \(neighbour.def.id): open with only \(done.sorted()) done, but no road leads there yet")
                }
            }
        }
    }

    /// Where a road crosses a border with no quest on it, you can step over before the land past
    /// it is built (`ContinentScene.canCross`): it's open there, onto that land.
    @Test func roadsOverBordersCanBeWalkedBeforeTheLandIsBuilt() {
        for def in content.maps where content.world[def.id] != nil {
            for neighbour in Continent.neighbours(of: def) where neighbour.exit != nil && neighbour.quest == nil {
                guard let exit = neighbour.exit, let gate = neighbour.gate(of: exit) else {
                    Issue.record("\(def.id) | \(neighbour.def.id): no crossing for the road")
                    continue
                }
                #expect(neighbour.isOpen(over: gate, done: { _ in false }, joined: false), "\(def.id) | \(neighbour.def.id): shut where the road crosses")
                #expect(Continent.owner(of: gate, from: def)?.id == neighbour.def.id, "\(def.id) | \(neighbour.def.id): the road crosses onto another land")
            }
        }
    }

    /// Every land has a colour to lie past the border in till its picture's drawn
    /// (`WorldScene.groundColor`): its ground's, not black.
    @Test func everyLandHasAGroundColourToStandInForIt() {
        for def in content.maps where content.world[def.id] != nil {
            let (red, green, blue) = WorldScene.groundColor(of: def, art: ArtLibrary.shared)
            #expect(red + green + blue > 0.15, "\(def.id): its ground's colour came out black")
        }
    }

    @Test func everyMapHasRoomToWalk() {
        for def in content.maps {
            let map = Layouts.of(def)
            for exit in def.exits {
                #expect(map.isWalkable(map.entryCell(from: exit.edge)), "map \(def.id) entry from \(exit.edge) is blocked")
            }
            // Everyone stands on the land itself (`Region`), not in the sea or a land next door.
            for npc in def.npcs ?? [] {
                #expect(map.owns(map.spot(of: npc)), "map \(def.id): \(npc.id) stands off its land")
            }
        }
    }

    /// A tap out past the land's edge, on the sea, walks you to the dry land nearest it, not out onto
    /// the water (the tapped cell clamped to the edge used to count as the spot itself).
    @Test func tapsOnTheSeaStopAtTheShore() throws {
        let def = try #require(content.map("meadowbrook"))
        let map = Layouts.of(def)
        let start = map.center(of: map.entryCell(from: try #require(def.exits.first).edge))
        let sea = WorldMap.project(CGPoint(x: -3 * WorldMap.tileSize, y: CGFloat(map.rows / 2) * WorldMap.tileSize))
        let end = try #require(map.path(from: start, to: sea).last)
        #expect(map.isWalkable(map.rawCell(at: end)), "a tap on the sea walked you out to \(map.rawCell(at: end))")
    }

    @Test func lakesAndRiversLeaveEverywhereInReach() throws {
        for def in content.maps where def.theme.lakes != nil || Continent.region(of: def)?.hasRiver == true {
            let map = Layouts.of(def)
            // What each map got, for the log (the tests job lists these lines).
            let lakes = map.lakes.map { "lake \($0.water.count)" + ($0.island.isEmpty ? "" : " with an island of \($0.island.count)") }
            let bridges = map.bridges.map { "\($0.kind) \($0.end - $0.start + 1)" }
            print("🌊 \(def.id): " + (lakes + ["river \(map.river.count)", "bridges: " + bridges.joined(separator: ", ")]).joined(separator: "; "))
            if let asked = def.theme.lakes {
                #expect(map.lakes.count == asked.count, "map \(def.id) has \(map.lakes.count) lakes, not \(asked.count)")
                // Lakes, not ponds: however squashed and cut back, over a quarter of a round the size asked.
                let smallest = asked.size.first ?? 8
                #expect(map.lakes.allSatisfy { Double($0.water.count) > 0.25 * Double.pi * smallest * smallest }, "map \(def.id): a lake came out a pond")
                #expect(map.lakes.filter { !$0.island.isEmpty }.count == asked.islands ?? 0, "map \(def.id): an island is missing")
                // A jetty out into each, a footbridge out to each island.
                #expect(map.bridges.filter { $0.kind == .jetty }.count == map.lakes.count, "map \(def.id): a lake has no jetty")
                #expect(map.bridges.filter { $0.kind == .foot }.count == map.lakes.filter { !$0.island.isEmpty }.count, "map \(def.id): an island has no footbridge")
            }
            if map.region?.hasRiver == true {
                #expect(!map.river.isEmpty, "map \(def.id) has no river")
                // A bridge wherever a road crosses it (a local waits on the bridge on some), never a ford.
                #expect(map.fords == 0, "map \(def.id): a road fords its river \(map.fords) times, with no room for a bridge")
                let waits = (def.locals ?? []).contains { $0.home.at == "bridge" || $0.walk?.at == "bridge" }
                #expect(!waits || map.bridges.contains { $0.kind == .road }, "map \(def.id): no road crosses its river")
                // The water can't be walked on but over a bridge.
                #expect(map.river.allSatisfy { map.bridgeCells.contains($0) || !map.isWalkable($0) }, "map \(def.id): you can wade its river")
            }
            for bridge in map.bridges {
                for cell in bridge.cells where map.contains(cell) && map.ground[cell.row][cell.col] == .water {
                    #expect(map.isWalkable(cell), "map \(def.id): a bridge you can't walk over at \(cell)")
                }
            }
            // From the hub every bit of land can be walked to, over the bridges, the islands too.
            let hub = map.offset(def.hub?.first ?? 0, def.hub?.last ?? 0)
            var reached: Set<GridPoint> = [hub]
            var queue = [hub]
            while let cell = queue.popLast() {
                for dr in -1...1 {
                    for dc in -1...1 {
                        let next = GridPoint(col: cell.col + dc, row: cell.row + dr)
                        if map.isWalkable(next), reached.insert(next).inserted { queue.append(next) }
                    }
                }
            }
            var stranded = 0
            for row in 0..<map.rows {
                for col in 0..<map.columns where map.isWalkable(GridPoint(col: col, row: row)) && !reached.contains(GridPoint(col: col, row: row)) {
                    stranded += 1
                }
            }
            #expect(stranded == 0, "map \(def.id): \(stranded) cells cut off from the hub")
        }
    }

    @Test func shoresSlopeDownToTheWater() throws {
        // Out in the fields the land slopes down to the sea and into the lakes (`WorldMap.shore`):
        // at the water's level beside it, never folding out of view going up the screen.
        let tile = WorldMap.tileSize
        var sloping = 0
        for def in content.maps where Continent.region(of: def) != nil && def.theme.cave == nil {
            let map = Layouts.of(def)
            guard let shore = map.shore else { continue }
            sloping += 1
            func height(_ cell: GridPoint) -> CGFloat {
                map.height(atGrid: CGPoint(x: (CGFloat(cell.col) + 0.5) * tile, y: (CGFloat(cell.row) + 0.5) * tile))
            }
            for lake in map.lakes {
                #expect(lake.water.allSatisfy { abs(height($0) + WorldMap.lakeDrop) < 1 },
                        "map \(def.id): a lake isn't down at its water's level")
            }
            // The land along the coast, at the sea's level (but by a hill, which it rises to meet
            // over a couple of cells, `WorldMap.layShore`).
            var coast = 0, low = 0
            for row in 0..<map.rows {
                for col in 0..<map.columns {
                    let cell = GridPoint(col: col, row: row)
                    guard map.owns(cell),
                          [Edge.east, .west, .north, .south].contains(where: { map.isOpenSea(cell.stepped($0)) }) else { continue }
                    let byHill = (-2...2).contains { dr in
                        (-2...2).contains { dc in map.hillIndex(at: GridPoint(col: col + dc, row: row + dr)) != nil }
                    }
                    guard !byHill else { continue }
                    coast += 1
                    if height(cell) < -WorldMap.seaDrop + 1 { low += 1 }
                }
            }
            #expect(coast == 0 || Double(low) >= 0.75 * Double(coast), "map \(def.id): only \(low) of \(coast) cells on the coast down at the sea")
            // A cell east and a cell north at once (up the screen) it never drops faster than the view.
            let samples = WorldMap.Hill.samples, width = shore.size.columns * samples + 1, depth = shore.size.rows * samples + 1
            var steepest: Float = 0
            for j in 0..<(depth - samples) {
                for i in 0..<(width - samples) {
                    steepest = max(steepest, shore.heights[j * width + i] - shore.heights[(j + samples) * width + i + samples])
                }
            }
            #expect(Double(steepest) < WorldMap.Hill.foldLimit, "map \(def.id): its shore drops \(steepest) points a cell up the screen")
            // You walk down it as you would up a hill: a tap on it finds where you stand.
            if let cell = shore.cells.min(by: { height($0) < height($1) }) {
                let spot = map.center(of: cell)
                let shown = CGPoint(x: spot.x, y: spot.y + map.height(at: spot))
                #expect(map.groundPoint(under: shown).distance(to: spot) < 1, "map \(def.id): a tap on its shore misses where it was")
            }
        }
        #expect(sloping >= 10, "only \(sloping) lands slope down to the water")
    }

    @Test func hillsRiseWithATrailUp() throws {
        let tile = WorldMap.tileSize
        for def in content.maps where def.theme.hills != nil {
            let map = Layouts.of(def)
            // Its own hills, not a range where a road leads into a cave (`roadsIntoCavesRunIntoAMountain`).
            let fields = map.hills.filter { !$0.isCrag }
            #expect(!fields.isEmpty, "map \(def.id) has no hills")
            #expect(fields.contains { hill in hill.cells.contains { map.isFreeForScenery($0) } },
                    "map \(def.id): nothing can grow on its hills")
            // What each map raised, for the log (the tests job lists these lines).
            let ranges = fields.map { "\(Int($0.peak)) high \($0.size.columns)×\($0.size.rows) \($0.trails.count) trails" }
            print("⛰ \(def.id): rocky \(map.rockiness), " + ranges.joined(separator: "; "))
            // Ranges stretch across the land, not a hump each; and a map with mountains has one.
            #expect(fields.contains { $0.size.columns >= 24 || $0.size.rows >= 24 }, "map \(def.id): only small hills")
            if let asked = def.theme.hills?.mountains?.height {
                // As tall as asked, near enough: each map with mountains has room for them (they
                // face you, steeper toward you than away, so they need less).
                #expect(fields.contains { $0.hasMountain && Double($0.peak) >= asked * 0.85 },
                        "map \(def.id): no mountain near \(Int(asked)) high (needs more room)")
            }
            // Not every range has a trail up it, but every land has one, and every mountain.
            #expect(fields.contains { !$0.trails.isEmpty }, "map \(def.id): no trail up any of its hills")
            for hill in fields {
                func height(_ point: CGPoint) -> CGFloat { map.height(atGrid: CGPoint(x: point.x * tile, y: point.y * tile)) }
                func cell(_ point: CGPoint) -> GridPoint { GridPoint(col: Int(point.x.rounded(.down)), row: Int(point.y.rounded(.down))) }
                #expect(!hill.hasMountain || !hill.trails.isEmpty, "map \(def.id): a mountain with no trail")
                // Its first trail starts on the ground; every trail comes out on its summit's top, every
                // step of it walkable, and you can walk from the first trail's foot to the top of each.
                let start = hill.trails.first?.points.first
                if let start { #expect(height(start) < 1, "map \(def.id): the first trail starts up in the air") }
                for trail in hill.trails {
                    guard let start else { break }
                    guard let foot = trail.points.first, let top = trail.points.last else { continue }
                    #expect(height(top) >= CGFloat(hill.lobes[trail.lobe].peak) - 1, "map \(def.id): a trail stops short of the top")
                    #expect(trail.points.allSatisfy { map.isWalkable(cell($0)) }, "map \(def.id): a trail is blocked")
                    #expect(!map.path(from: map.center(of: cell(start)), to: map.center(of: cell(top))).isEmpty, "map \(def.id): no way up")
                    guard height(foot) < 1 else { continue }
                    // A footpath leads from a trail on the ground to the roads, and road goes on to
                    // the map's edge (on the continent, to where a road crosses its border).
                    // Step by step as walkers go, diagonals too: a footpath can join one of the
                    // narrower side trails, whose cells often only meet corner to corner.
                    let crossings = Set(map.region?.roads.values.map(\.at) ?? [])
                    var seen: Set<GridPoint> = [cell(foot)]
                    var queue = [cell(foot)]
                    var outside = false
                    while let at = queue.popLast(), !outside {
                        for (dc, dr) in [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)] {
                            let next = GridPoint(col: at.col + dc, row: at.row + dr)
                            // Over a bridge where the road crosses a river, too.
                            guard map.contains(next), map.ground[next.row][next.col] == .path || map.bridgeCells.contains(next),
                                  seen.insert(next).inserted else { continue }
                            if next.col == 0 || next.row == 0 || next.col == map.columns - 1 || next.row == map.rows - 1
                                || crossings.contains(next) { outside = true }
                            queue.append(next)
                        }
                    }
                    #expect(outside, "map \(def.id): no footpath from the trail at \(cell(foot)) to the roads")
                }
                // You can walk up it anywhere, its steepest sides too (nothing grows on it yet).
                #expect(hill.cells.allSatisfy { map.isWalkable($0) }, "map \(def.id): part of a hill you can't walk on")
                // Never so steep that ground facing away from you would lean out of sight: going up
                // the map and right at once (up the screen), it never drops faster than the view.
                for cell in hill.cells {
                    for (dx, dy) in [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)] {
                        let point = CGPoint(x: CGFloat(cell.col) + dx, y: CGFloat(cell.row) + dy)
                        let e: CGFloat = 0.1
                        let drop = (height(CGPoint(x: point.x + e, y: point.y + e)) - height(CGPoint(x: point.x - e, y: point.y - e))) / (2 * e * tile)
                        #expect(drop > -0.65, "map \(def.id): a hill folds over at \(point)")
                    }
                }
            }
        }
        // The more dangerous the map, the rockier and steeper its hills: grassy slopes in the meadow,
        // crags where the monsters are strongest.
        let meadow = Layouts.of(try #require(content.map("sunny_meadow")))
        let steppe = Layouts.of(try #require(content.map("secret_plain")))
        #expect(meadow.rockiness == 0 && steppe.rockiness == 1)
        #expect(meadow.hills.allSatisfy { $0.steepness < steppe.hills.first?.steepness ?? 0 })
        // A town's terraces stand up too, their stairs climbing to the top.
        for def in content.maps where def.town?.terraces?.isEmpty == false {
            let map = Layouts.of(def)
            #expect(map.plateaus.contains { $0.height == WorldMap.terraceHeight }, "map \(def.id): terraces lie flat")
        }
    }

    /// Glimmerbough, Starfall Isle's fairy village (playtesting 2026-10-16: "something worthy to do on
    /// Starfall Isle"): a healer, a shop and quest givers with five quests (and three more for the
    /// Glimmerdeep, the crystal cave under it), and a boss up on its mountain that drops a weapon for
    /// every class you can choose.
    @Test func glimmerboughHasSomethingForEveryone() throws {
        let isle = try #require(content.map("starfall_isle"))
        let npcs = isle.npcs ?? []
        for role in [NPCRole.healer, .shop, .quests, .boss] {
            #expect(npcs.contains { $0.role == role }, "Starfall Isle has no \(role)")
        }
        let givers = Set(npcs.filter { $0.role == .quests }.map(\.id))
        #expect(content.quests.filter { givers.contains($0.giver) }.count == 9)
        let boss = try #require(npcs.first { $0.role == .boss }?.monster.flatMap(content.monster))
        let weapons = (boss.drops ?? []).compactMap { content.item($0.item) }.filter { $0.type == .weapon }
        for cls in content.classes where cls.id != "novice" {
            #expect(weapons.contains { $0.classes?.contains(cls.id) == true }, "the Fallen Star drops no weapon for a \(cls.id)")
        }
    }

    /// Every land out in the fields has a village (playtesting 2026-10-17: "little villages or
    /// communities with characters and their own stories or quests, similar to RuneScape"): two
    /// quest givers or more, each at the door of a house of their own, folk living round them, and a
    /// story there that ends in a treasure.
    @Test func fieldsHaveVillages() throws {
        let lands = ["sunny_meadow", "northern_grassland", "pineapple_shore", "twilight_woods", "smiling_forest",
                     "candy_mountain", "frog_swamp", "wolf_lair", "swan_lake", "valley_of_fear", "lotus_land", "puppet_hill",
                     "genie_desert", "goldburg_lake", "crystal_mountain", "sleepy_town", "snow_white_forest",
                     "moonglow", "secret_plain", "hachoo_island", "rosen_lake", "water_temple", "emerald_road"]
        for id in lands {
            let def = try #require(content.map(id))
            let givers = (def.npcs ?? []).filter { $0.role == .quests }
            let houses = Set((def.buildings ?? []).map { [$0.x, $0.y] })
            #expect(givers.filter { houses.contains([$0.x + 1, $0.y + 2]) }.count >= 2, "\(id): no village of quest givers at their doors")
            #expect((def.locals ?? []).count >= 3, "\(id): hardly anyone lives there")
            let quests = content.quests.filter { quest in givers.contains { $0.id == quest.giver } }
            #expect(quests.contains { ($0.reward.items ?? []).contains { item in content.isQuestTreasure(item) } }, "\(id): no story there ends in a treasure")
        }
    }

    @Test func summitsHoldWhatsSetUpThere() throws {
        // A boss, a chest or a friend set up on a summit (`NPCDef.summit`) stands up on its top, on
        // ground you can walk on, and you can get there from the middle of the map.
        let tile = WorldMap.tileSize
        for def in content.maps {
            let up = (def.npcs ?? []).filter { $0.summit != nil }
            guard !up.isEmpty else { continue }
            let map = Layouts.of(def)
            let hub = map.offset(def.hub?.first ?? 0, def.hub?.last ?? 0)
            for npc in up {
                let summit = try #require(npc.summit)
                guard map.summits.indices.contains(summit) else {
                    Issue.record("map \(def.id): no summit \(summit) for \(npc.id)")
                    continue
                }
                let top = map.summits[summit]
                let spot = map.spot(of: npc)
                let peak = map.height(atGrid: CGPoint(x: top.x * tile, y: top.y * tile))
                let here = map.height(atGrid: CGPoint(x: (CGFloat(spot.col) + 0.5) * tile, y: (CGFloat(spot.row) + 0.5) * tile))
                #expect(peak > 60 && here > peak * 0.8, "map \(def.id): \(npc.id) isn't up on a summit (\(here) of \(peak) high)")
                #expect(map.isWalkable(spot), "map \(def.id): \(npc.id) stands where you can't walk")
                #expect(!map.path(from: map.center(of: hub), to: map.center(of: spot)).isEmpty, "map \(def.id): no way up to \(npc.id)")
            }
        }
    }

    @Test func localsLiveWhereYouCanFindThem() {
        // The people who live on each map (`MapDef.Local`): the landmark they live by is there, and
        // home and wherever they walk to are on ground you can walk on and get to from where the
        // roads meet.
        for def in content.maps {
            guard let locals = def.locals, !locals.isEmpty else { continue }
            let map = Layouts.of(def)
            let hub = map.center(of: map.offset(def.hub?.first ?? 0, def.hub?.last ?? 0))
            for local in locals {
                for place in [local.home] + (local.walk.map { [$0] } ?? []) {
                    if let at = place.at {
                        #expect(map.landmark(at, which: place.which ?? 0) != nil, "map \(def.id): no \(at) for \(local.name)")
                    }
                    guard let spot = map.spot(of: place) else {
                        Issue.record("map \(def.id): nowhere for \(local.name) to stand")
                        continue
                    }
                    #expect(map.isWalkable(spot), "map \(def.id): \(local.name) stands where you can't walk")
                    #expect(!map.path(from: hub, to: map.center(of: spot)).isEmpty, "map \(def.id): no way to \(local.name) at \(spot)")
                }
            }
        }
    }

    @Test func housesStandOffTheRoads() {
        for def in content.maps {
            let map = Layouts.of(def)
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
            let map = Layouts.of(def)
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

    @Test func singlePicturesTurnTheWayTheyWalk() {
        let art = ArtLibrary.shared
        // A monster is one picture, mirrored to walk the other way; a walk sheet has side views.
        #expect(art.walkCycle("monster_jelly").mirrors)
        #expect(!art.walkCycle("monster_jelly").facesRight)
        #expect(!art.walkCycle("player_walk").mirrors)
        #expect(!art.walkCycle("pet_walk").mirrors)
        // Most look left or at you; a few look right, and a copy looks the way its base does.
        #expect(art.walkCycle("npc_ugly_duckling").facesRight)
        #expect(art.walkCycle("monster_tree_snake_sunny").facesRight)
    }

    @Test func theSunCrossesTheSkyAndShadowsFollow() throws {
        // Midday's sun is where the hills' light always came from: up the map and to the left, 36° up.
        let noon = Sun.noon
        let length = (0.36 + 1.0).squareRoot(), up = 36 * Double.pi / 180
        #expect(abs(noon.x + 0.6 / length * cos(up)) < 1e-9)
        #expect(abs(noon.y - 1 / length * cos(up)) < 1e-9)
        #expect(abs(noon.z - sin(up)) < 1e-9)
        #expect(noon.strength == 1)
        for step in 0..<96 {
            let sun = Sun(hour: Double(step) / 4)
            #expect(abs(sun.x * sun.x + sun.y * sun.y + sun.z * sun.z - 1) < 1e-9)
            #expect(sun.z > 0.13, "the light never comes from below the horizon at \(Double(step) / 4)hr")
        }
        // East in the morning, west in the evening, low then and highest at midday; soft and from
        // overhead as it rises and sets, so the moon takes over without a jump; fainter at night.
        #expect(Sun(hour: 7.5).x > 0.3)
        #expect(Sun(hour: 16.5).x < -0.3)
        #expect(Sun(hour: 8).z < noon.z && Sun(hour: 16).z < noon.z)
        #expect(Sun(hour: 6).z > 0.99 && Sun(hour: 18).z > 0.99)
        #expect(abs(Sun(hour: 5.999).z - Sun(hour: 6).z) < 0.01)
        #expect(Sun(hour: 0).strength < 1)
        // The hills' light at midday is what it always was.
        let ambient = HillArt.ambient(rocky: 0.3)
        for (hx, hy) in [(0.0, 0.0), (0.4, -0.2), (-0.7, 0.5), (0.1, 0.9)] {
            let lambert = (-hx * noon.x - hy * noon.y + noon.z) / (hx * hx + hy * hy + 1).squareRoot()
            let flat = ambient + (1 - ambient) * noon.z
            let was = (ambient + (1 - ambient) * max(0, lambert)) / flat
            #expect(abs(HillArt.sunlight(hx: hx, hy: hy, ambient: ambient, sun: noon).shade - was) < 1e-9)
        }
        // A slope facing east is brighter in the morning than in the evening.
        let east = (hx: -0.5, hy: 0.0)
        #expect(HillArt.sunlight(hx: east.hx, hy: east.hy, ambient: ambient, sun: Sun(hour: 8)).shade
            > HillArt.sunlight(hx: east.hx, hy: east.hy, ambient: ambient, sun: Sun(hour: 16)).shade)

        // A tree's shadow: a little to the right at midday, toward you in the morning, away from
        // you in the evening, longer then; round when the light is overhead.
        let world = SKNode()
        let tree = SKSpriteNode(color: .green, size: CGSize(width: 60, height: 90))
        tree.position = CGPoint(x: 100, y: 200)
        let shadow = Lighting.Shadow(under: tree, in: world)
        #expect(world.children.count == 1)
        let cast = try #require(world.children.first as? SKSpriteNode)
        shadow.fall(from: noon)
        #expect(cast.position.x > tree.position.x + 5)
        #expect(abs(cast.size.width - 48) < 2 && abs(cast.size.height - 17.3) < 1.5, "midday's shadow is as it always was")
        let midday = cast.position.distance(to: tree.position)
        shadow.fall(from: Sun(hour: 7.5))
        #expect(cast.position.y < tree.position.y - 5)
        #expect(cast.position.distance(to: tree.position) > midday)
        shadow.fall(from: Sun(hour: 16.5))
        #expect(cast.position.y > tree.position.y + 5)
        shadow.fall(from: Sun(hour: 6))
        #expect(abs(cast.position.x - tree.position.x) < 0.5 && abs(cast.position.y - tree.position.y) < 0.5)
        #expect(abs(cast.size.width - 2 * cast.size.height) < 0.5)
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

    @Test func townsfolksHairIsOneColour() throws {
        // A whole-sheet palette swap can't reach every shade of hair (its deep reds and pale tips are
        // the skin's and the boots' colours too), so townsfolk drawn from a hero's sheet stack its
        // paper-doll layers, the hair on its own.
        let content = Content.shared
        let heroSheets = Set(content.races.flatMap { [$0.sheet] + ($0.sheets ?? [:]).values } + ["dwarf_npc_walk"])
        for npc in content.maps.flatMap({ $0.npcs ?? [] }) {
            guard let derive = ArtLibrary.shared.asset(npc.art)?.derive, heroSheets.contains(derive.from) else { continue }
            let layers = try #require(derive.layers, "\(npc.id): \(npc.art) recolours all of \(derive.from), half its hair")
            for layer in layers {
                #expect(ArtLibrary.shared.artImage(layer.id) != nil, "\(npc.art): no layer \(layer.id)")
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

    /// Adventurers walk companions at home in a land like the one they roam, where one fits
    /// (playtesting 2026-10-16: a frost-maned lion in the desert): never one that lives only in the
    /// cold out in the hot south-east, and no frost monster in the mild lands.
    @Test func companionsSuitTheLandTheyRoam() {
        let content = Content.shared
        func homes(_ id: String) -> Set<MapDef.Climate?> {
            Set(content.maps.filter { $0.encounters?.monsters[id] != nil }.map(\.climate))
        }
        let cases: [(level: Int, climate: MapDef.Climate)] = [(130, .hot), (60, .hot), (150, .cold), (80, .cold)]
        for (level, climate) in cases {
            for _ in 0..<20 {
                guard let id = Crowd.companion(forLevel: level, climate: climate) else {
                    Issue.record("no companion for level \(level)")
                    return
                }
                #expect(homes(id).contains(climate), "level \(level) in a \(climate) land → \(id)")
            }
        }
        for _ in 0..<20 {
            let id = Crowd.companion(forLevel: 40) ?? ""
            #expect(!id.contains("frost") && !id.contains("snow"), "a mild land → \(id)")
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

    @Test func chestsFillAgainAfterAWhile() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let chest = try #require(Content.shared.npc("crystal_summit_chest"))
        let rules = try #require(Content.shared.rewards.chests)
        // The first time, its own treasure.
        #expect(session.openChest(chest)?.id == "crystal_crown_pendant")
        #expect(session.isOpened(chest.id))
        #expect(session.openChest(chest) == nil)
        // A while later, something new, and gold for its level.
        let opened = try #require(session.data.chestsOpenedAt?[chest.id])
        session.data.chestsOpenedAt?[chest.id] = opened.addingTimeInterval(-rules.refillHours * 3600 - 1)
        #expect(!session.isOpened(chest.id))
        let gold = session.data.gold
        #expect(session.openChest(chest) != nil)
        #expect(session.data.gold > gold)
        #expect(session.isOpened(chest.id))
        // One opened before chests filled again is full already.
        session.data.openedChests = ["snow_summit_chest"]
        #expect(!session.isOpened("snow_summit_chest"))
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

    /// Rebirth was taken out (0.7.27): a hero reborn twice and at level 30 again goes back to the
    /// level their last rebirth began at, and the rebirth titles go. Once.
    @Test func aRebornHeroGetsTheirLevelBack() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        session.data.hero.rebirths = 2
        session.data.hero.level = 30
        session.data.titles = ["apprentice", "reborn", "twice_reborn"]
        session.data.title = "reborn"
        session.retireRebirthsIfNeeded()
        #expect(session.data.hero.level == 106)
        #expect(session.data.hero.rebirths == nil)
        #expect(session.data.titles?.contains("reborn") == false)
        #expect(session.data.titles?.contains("apprentice") == true)
        #expect(session.data.title == nil)
        session.data.hero.level = 120
        session.retireRebirthsIfNeeded()
        #expect(session.data.hero.level == 120)
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

    /// A quest that asks you to bring something (RuneScape's Sheep Shearer): its monsters drop it
    /// while you're on it, never more than it wants, and handing it in hands it over.
    @Test func bringQuestsHandOverWhatTheyAsk() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let quest = try #require(Content.shared.quest("wool_for_the_lambs"))
        #expect(session.questDrops(from: "golden_hamster").isEmpty)   // not before it's taken
        session.data.hero.level = quest.minLevel ?? 1
        for required in quest.requires ?? [] { session.data.quests[required] = QuestProgress(state: .completed, count: 1) }
        session.acceptQuest(quest.id)
        #expect(session.status(of: quest) == .active(progress: 0, goal: 5))
        for _ in 0..<400 { _ = session.questDrops(from: "golden_hamster") }
        #expect(session.count(of: "tuft_of_wool") == 5, "the hamsters dropped \(session.count(of: "tuft_of_wool")) tufts, not 5")
        #expect(session.questDrops(from: "jelly").isEmpty)
        #expect(session.status(of: quest) == .ready)
        session.turnInQuest(quest.id)
        #expect(session.count(of: "tuft_of_wool") == 0 && session.hasCompleted(quest.id))
        #expect(session.questDrops(from: "golden_hamster").isEmpty)   // not after it's done
    }

    /// A quest that asks you to carve something (RuneScape's Lost City): its monsters drop the piece
    /// you can't buy, you carve it from the bag with the rest, and they drop no more once it's carved.
    @Test func carvedQuestItemsAreMadeFromTheBag() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let quest = try #require(Content.shared.quest("a_flute_for_shelly"))
        let flute = try #require(Content.shared.item("driftwood_flute"))
        let piece = try #require(Content.shared.item("driftwood_piece"))
        session.data.hero.level = quest.minLevel ?? 1
        for required in quest.requires ?? [] { session.data.quests[required] = QuestProgress(state: .completed, count: 1) }
        session.acceptQuest(quest.id)
        #expect(session.handmade(using: piece)?.id == flute.id)
        #expect(!session.canCraft(flute) && !session.make(flute.id))
        for _ in 0..<200 { _ = session.questDrops(from: "wood_crab") }
        #expect(session.count(of: piece.id) == 1)
        session.addItem("poplar", 2)
        #expect(session.make(flute.id))
        #expect(session.count(of: flute.id) == 1 && session.count(of: piece.id) == 0 && session.count(of: "poplar") == 0)
        #expect(session.status(of: quest) == .ready && session.handmade(using: piece) == nil)
        for _ in 0..<200 { _ = session.questDrops(from: "wood_crab") }
        #expect(session.count(of: piece.id) == 0)
        // Made by hand, never at a smith's.
        #expect(!session.recipes.contains { $0.make != nil })
    }

    /// The ship to Starfall Isle sails once Captain Brine's last quest is done; the one back always
    /// does, so you're never stranded. Brine stands by the pier.
    @Test func theShipWaitsOnItsQuest() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let sneezle = try #require(Content.shared.map("hachoo_island")), isle = try #require(Content.shared.map("starfall_isle"))
        let out = try #require(sneezle.exits.first { $0.to == isle.id }), back = try #require(isle.exits.first { $0.to == sneezle.id })
        #expect(out.ship == true && out.requires == "the_star_chart")
        #expect(!session.canTravel(out) && session.canTravel(back))
        session.data.quests["the_star_chart"] = QuestProgress(state: .completed, count: 1)
        #expect(session.canTravel(out))
        let map = Layouts.of(sneezle)
        let brine = try #require(sneezle.npcs?.first { $0.id == "captain_brine" })
        let dock = try #require(map.harbors.first).road.at
        let spot = map.spot(of: brine)
        #expect(map.owns(spot) && max(abs(spot.col - dock.col), abs(spot.row - dock.row)) <= 6, "Captain Brine stands at \(spot), the pier leaves at \(dock)")
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
        // Past the best gear monsters drop, weapons and armour come from the top (trinkets from
        // anywhere). Quest and summit treasures go higher, but no monster drops them.
        // Gear only: a quest's pieces (materials) go past the top gear's level.
        let droppable = Content.shared.items.filter {
            ItemType.equipmentSlots.contains($0.type) && !bossDrops.contains($0.id) && !Content.shared.isTreasure($0.id)
        }
        let top = try #require(droppable.compactMap(\.level).max())
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

    @Test func goldShortensFromTenThousandUp() {
        let en = Locale(identifier: "en_US")
        #expect(HUDStyle.short(9_999, locale: en) == "9,999")
        #expect(HUDStyle.short(10_000, locale: en) == "10K")
        #expect(HUDStyle.short(12_345, locale: en) == "12.3K")
        #expect(HUDStyle.short(123_456, locale: en) == "123K")
        // Rounded down: never more than you have.
        #expect(HUDStyle.short(999_999, locale: en) == "999K")
        #expect(HUDStyle.short(1_000_000, locale: en) == "1M")
        #expect(HUDStyle.short(1_457_603, locale: en) == "1.45M")
        #expect(HUDStyle.short(1_450_000, locale: en) == "1.45M")
        #expect(HUDStyle.short(14_570_000, locale: en) == "14.5M")
        #expect(HUDStyle.short(2_000_000_000, locale: en) == "2B")
        // In the phone's own way with numbers, like the HP bars beside it.
        #expect(HUDStyle.short(1_457_603, locale: Locale(identifier: "nl_NL")) == "1,45M")
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

    /// The Quests list puts the quest you took last at the top, and the one you finished last first
    /// (playtesting 2026-10-16); quests from saves before they kept dates come after, in the game's order.
    @Test func newQuestsAreAtTheTop() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let quests = Content.shared.quests.map(\.id).filter { $0 != "hope_of_meadowbrook" && $0 != "jelly_trouble" }.prefix(4).map { $0 }
        // A day ago, so taking one now dates it later.
        let start = Date(timeIntervalSinceNow: -86_400)
        session.data.quests[quests[0]] = QuestProgress(state: .active, count: 0)
        session.data.quests[quests[1]] = QuestProgress(state: .active, count: 0, taken: start)
        session.data.quests[quests[2]] = QuestProgress(state: .active, count: 0, taken: start.addingTimeInterval(60))
        #expect(session.activeQuests.map(\.id) == [quests[2], quests[1], quests[0]])
        session.data.quests[quests[3]] = QuestProgress(state: .completed, count: 0, finished: start)
        session.data.quests[quests[1]] = QuestProgress(state: .completed, count: 0, taken: start, finished: start.addingTimeInterval(120))
        #expect(session.completedQuests.map(\.id) == [quests[1], quests[3]])
        // Taking one dates it: it goes to the top.
        session.data.quests["hope_of_meadowbrook"] = QuestProgress(state: .completed, count: 3)
        session.acceptQuest("jelly_trouble")
        #expect(session.activeQuests.first?.id == "jelly_trouble")
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

    /// A monster with a healing skill mends itself when badly hurt, but only once a fight and by no
    /// more than a fifth of its HP (playtesting 2026-10-19: some should heal, fights stay fair).
    @Test func monstersMendThemselvesOnceAndModestly() throws {
        let content = Content.shared
        let wisp = try #require(content.monster("wisp"))
        #expect(wisp.skills.contains("recovery"))
        let heroStats = Stats(hp: 5000, mp: 20, attack: 30, defense: 400, magic: 10, speed: 20)
        let hero = Combatant(id: 0, side: .party, source: .hero, name: "Hero", art: "player_walk", level: 40, element: .neutral,
                             stats: heroStats, hp: 5000, mp: 20, skills: [], captureRate: 0)
        let stats = wisp.stats(at: 40)
        let low = stats.hp / 10
        let foe = Combatant(id: 10, side: .enemies, source: .wild("wisp"), name: "Wisp", art: wisp.art, level: 40, element: wisp.element,
                            stats: stats, hp: low, mp: stats.mp, skills: wisp.skills, captureRate: 0)
        let engine = BattleEngine(party: [hero], enemies: [foe], content: content, seed: 11)
        var heals: [Int] = []
        for _ in 0..<16 where engine.outcome == .ongoing {
            for event in engine.resolveRound(heroAction: .defend) {
                if case .skill(let actor, let skill, _, let hits) = event, actor == 10, skill.kind == .heal {
                    heals += hits.map(\.amount)
                }
            }
        }
        #expect(heals.count == 1)
        #expect(heals.allSatisfy { $0 > 0 && $0 <= Int(Double(stats.hp) * BattleEngine.monsterHealCap) })
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

    /// The Character screen's upgrade arrow: gear the hero can wear that's worth more to their class
    /// than what's on. Not another class's, not one above their level, not a worse one. And the
    /// Bag's search and Best for you.
    @Test func betterGearIsMarkedAndFound() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        session.data.hero.classID = "fighter"
        session.data.hero.level = 40
        session.data.hero.equipment[.weapon] = "bronze_broadsword"
        session.data.inventory = [:]
        session.addItem("wooden_sword")
        session.addItem("luna_axe")
        session.addItem("luna_staff")
        #expect(session.upgrade(for: .weapon) == nil, "worse, too high a level, or a mage's")
        #expect(!session.hasGearUpgrade)
        session.addItem("silver_sword")
        #expect(session.upgrade(for: .weapon)?.id == "silver_sword")
        #expect(session.hasGearUpgrade)
        // An empty slot takes anything you can wear.
        session.data.hero.equipment[.armor] = nil
        session.addItem("cloth_tunic")
        #expect(session.upgrade(for: .armor)?.id == "cloth_tunic")
        // Best for you puts what the fighter can wear first, the strongest of it first; then the rest
        // (the Luna Axe is stronger still, but needs level 100).
        let weapons = session.bagEquipment.filter { $0.type == .weapon }
        let best = ItemFinder.arrange(weapons, search: "", sort: .best, session: session).map(\.id)
        #expect(best.first == "silver_sword")
        #expect(best.firstIndex(of: "luna_axe")! > best.firstIndex(of: "wooden_sword")!)
        // Search finds a name or a kind.
        #expect(ItemFinder.arrange(session.bagEquipment, search: "armor", sort: .standard, session: session).map(\.id) == ["cloth_tunic"])
        #expect(ItemFinder.arrange(weapons, search: "luna", sort: .name, session: session).map(\.id) == ["luna_axe", "luna_staff"])
    }

    /// Quest treasures (gear a quest gives that no shop sells) come only from their quest: no monster
    /// drops one, no trader carries one and no adventurer wears one. A save that finished the quest
    /// before it gave its treasure gets it once, by post.
    @Test func questTreasuresComeOnlyFromQuests() throws {
        let content = Content.shared
        #expect(content.items.filter { content.isQuestTreasure($0.id) }.count >= 20)
        #expect(content.questGiving("oxhide_mail")?.id == "four_oxen")
        // Shop gear a quest gives isn't one (the Leather Vest for choosing your path).
        #expect(!content.isQuestTreasure("leather_vest"))
        // A summit's treasure is as much yours alone (`chestHolding`).
        #expect(content.chestHolding("crystal_crown_pendant")?.id == "crystal_summit_chest")
        #expect(content.isTreasure("crystal_crown_pendant") && !content.isQuestTreasure("crystal_crown_pendant"))
        let session = GameSession.newGame(name: "Test", raceID: "human")
        session.data.hero.classID = "fighter"
        for level in stride(from: 10, through: 200, by: 10) {
            for draw in 0..<40 {
                if let drop = session.equipmentDrop(level: level, best: draw % 2 == 0) {
                    #expect(!content.isTreasure(drop.id), "a level-\(level) monster dropped \(drop.id)")
                }
            }
            for classID in ["fighter", "mage", "tamer"] {
                let adventurer = Adventurer(name: "Momo", raceID: "elf", classID: classID, level: level, look: .standard)
                if let armor = GameSession.armor(for: adventurer) {
                    #expect(!content.isTreasure(armor.id), "a level-\(level) \(classID) wears \(armor.id)")
                }
                for offer in session.tradeOffers(with: adventurer) {
                    #expect(!content.isTreasure(offer.item.id), "a level-\(level) trader sells \(offer.item.id)")
                }
            }
        }
        // Handing the quest in gives it.
        session.data.hero.level = 100
        session.data.quests["four_oxen"] = QuestProgress(state: .active, count: 8)
        session.turnInQuest("four_oxen")
        #expect(session.count(of: "oxhide_mail") == 1)
        #expect(session.deliverQuestTreasures().isEmpty)
        // A quest finished before it gave its treasure: it comes when the game loads, and only once.
        var older = session.data
        older.quests["wolf_hunt"] = QuestProgress(state: .completed, count: 0)
        older.questTreasuresGiven = ["oxhide_mail"]
        let loaded = GameSession(data: older)
        #expect(loaded.count(of: "woodcutters_coat") == 1)
        #expect(loaded.count(of: "oxhide_mail") == 1)
        #expect(GameSession(data: loaded.data).count(of: "woodcutters_coat") == 1)
    }

    /// A quest giver with nothing for you says why, and where there's work: a level to reach,
    /// someone else's quest to finish first, or all done, with who needs someone like you.
    @Test func questGiversSayWhyAndWhereNext() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        // Too low a level for the Old Ox's first quest.
        session.data.hero.level = 90
        #expect(session.quests(from: "old_ox").isEmpty)
        #expect(session.questGiverNote("old_ox") == "Come back at level 100, and I'll have something for you.")
        // Mayor Poppy's work waits on Elder Oak's Monkey Business.
        session.data.hero.level = 30
        #expect(session.questGiverNote("mayor") == "Finish “Monkey Business” for Elder Oak in Meadowbrook first, and come back to me.")
        // All the Swan Keeper had is done: the quest open to you that suits your level best is the
        // Old Ox's, from level 100.
        session.data.hero.level = 103
        session.data.quests["wishes_of_a_duckling"] = QuestProgress(state: .completed, count: 0)
        // (quests(from:) still lists what's handed in; the dialog leaves those out.)
        #expect(session.quests(from: "swan_keeper").allSatisfy { session.status(of: $0) == .completed })
        #expect(session.questGiverNote("swan_keeper") == "That's all I had for you. Thank you! Old Ox in Hidden Steppe has work for someone like you.")
        // Every quest at the hero's level everywhere is done: the next one to open.
        for quest in Content.shared.quests where (quest.minLevel ?? 1) <= 103 {
            session.data.quests[quest.id] = QuestProgress(state: .completed, count: 0)
        }
        #expect(session.questGiverNote("swan_keeper") == "That's all I had for you. Thank you! Old Ox in Hidden Steppe will have work for you at level 106.")
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

    /// Friends don't always come along (playtesting 2026-10-16): mostly yes, but no again for a while
    /// after a no, mostly no far apart in level, and less keen with friends of their own.
    @Test func friendsCanTurnDownAnInvite() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        session.data.hero.level = 30
        let chance = Content.shared.crowd.acceptChance ?? 0.75
        let momo = Adventurer(name: "Momo", raceID: "elf", classID: "mage", level: 28, look: .standard)
        let pip = Adventurer(name: "Pip", raceID: "human", classID: "fighter", level: 80, look: .standard)
        let kip = Adventurer(name: "Kip", raceID: "dwarf", classID: "fighter", level: 31, look: .standard)
        let lia = Adventurer(name: "Lia", raceID: "human", classID: "mage", level: 29, look: .standard)
        for friend in [momo, pip, kip, lia] { #expect(session.befriend(friend)) }
        session.adventurersAround = Set([momo, pip, kip, lia].map(\.id))
        let now = Date()
        // A no, and no again a moment later however the dice fall; asked again later, a yes.
        #expect(session.askAlong(momo.id, roll: 0.99, now: now)?.accepted == false)
        #expect(session.partyMembers.isEmpty)
        #expect(session.askAlong(momo.id, roll: 0, now: now.addingTimeInterval(60))?.line == "Still no, sorry!")
        #expect(session.askAlong(momo.id, roll: 0, now: now.addingTimeInterval(GameSession.declineFor + 1))?.accepted == true)
        #expect(session.partyMembers.map(\.name) == ["Momo"])
        // Fifty levels apart, dice that'd mean yes for anyone else mean no.
        #expect(session.askAlong(pip.id, roll: chance * 0.5, now: now)?.accepted == false)
        // With friends of their own they're half as keen.
        #expect(session.askAlong(kip.id, busy: true, roll: chance * 0.75, now: now)?.accepted == false)
        #expect(session.askAlong(lia.id, roll: chance * 0.75, now: now)?.accepted == true)
    }

    /// You can join a party of adventurers (playtesting 2026-10-16): whoever leads answers, they fight
    /// beside you, with room for you and your party's friends or not at all; and after a while they
    /// head off on their own, as a friend at your side does, who then won't come straight back.
    @Test func youCanJoinTheirPartyAndTheyHeadOffAfterAWhile() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        session.data.hero.level = 20
        let group = ["Ash", "Bree", "Cole"].map { Adventurer(name: $0, raceID: "human", classID: "fighter", level: 21, look: .standard) }
        let grump = Adventurer(name: "Grump", raceID: "dwarf", classID: "fighter", level: 20, look: .standard, hostile: true)
        // On their own, there's no party to join.
        #expect(session.askToJoin([group[0]], roll: 0) == nil)
        let now = Date()
        #expect(session.askToJoin(group, roll: 0.99, now: now)?.accepted == false)
        #expect(session.askToJoin(group, roll: 0, now: now.addingTimeInterval(60))?.accepted == false)
        #expect(session.joinedParty == nil)
        #expect(session.askToJoin(group, roll: 0, now: now.addingTimeInterval(GameSession.declineFor + 1))?.accepted == true)
        #expect(session.joinedParty?.leader?.name == "Ash")
        #expect(session.isInJoinedParty(group[2]))
        // They fight beside you, but they're not your friends: they throw no Seal Stones of yours.
        let controller = BattleController.duel(with: grump, session: session)
        for member in group {
            let fighter = controller.party.first { $0.name == member.name }
            #expect(fighter != nil, "\(member.name) isn't in the fight")
            #expect(fighter?.sealStones == 0)
        }
        // Room for one friend more, a party of five.
        let momo = Adventurer(name: "Momo", raceID: "elf", classID: "mage", level: 19, look: .standard)
        #expect(session.befriend(momo))
        session.adventurersAround = [momo.id]
        #expect(!session.partyIsFull)
        session.invite(momo.id)
        #expect(session.partyIsFull)
        #expect(session.fightersAtYourSide.map(\.name) == ["Momo", "Ash", "Bree", "Cole"])
        // Time passes: Momo heads off first, and won't come straight back; then their party does.
        session.partyStays[momo.id] = 100
        session.joinedStay = 200
        #expect(session.passPartyTime(99).left.isEmpty)
        let first = session.passPartyTime(2)
        #expect(first.left.map(\.name) == ["Momo"] && first.headedOff == nil)
        #expect(session.partyMembers.isEmpty && session.isFriend(momo))
        #expect(session.askAlong(momo.id, roll: 0)?.accepted == false)
        #expect(session.passPartyTime(100).headedOff?.name == "Ash")
        #expect(session.joinedParty == nil && session.fightersAtYourSide.isEmpty)
        // A party of four has no room for you and a friend of yours.
        let four = group + [Adventurer(name: "Dot", raceID: "elf", classID: "mage", level: 22, look: .standard)]
        let pip = Adventurer(name: "Pip", raceID: "human", classID: "fighter", level: 20, look: .standard)
        #expect(session.befriend(pip))
        session.adventurersAround = [pip.id]
        session.invite(pip.id)
        #expect(session.askToJoin(four, roll: 0)?.line == "Sorry, our party's full!")
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

    @Test func teleportsGoToAnyTownYouveBeenTo() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let content = Content.shared
        let towns = content.maps.filter { $0.fence == true }.map(\.id)
        // In the first town with nowhere else visited, there's nowhere to go.
        session.data.mapID = content.startMap
        #expect(session.travelDestinations.isEmpty)
        // Out in the wild having been to them all: every town, the checkpoint first.
        let wild = try #require(content.maps.first { $0.fence != true && $0.encounters != nil })
        session.data.mapID = wild.id
        for town in towns { session.markVisited(town) }
        let home = try #require(towns.last)
        session.reachCheckpoint(try #require(content.map(home)))
        #expect(session.travelDestinations.first == home)
        #expect(Set(session.travelDestinations) == Set(towns))
        // In one of them: every other one.
        session.data.mapID = towns[0]
        #expect(session.travelDestinations.count == towns.count - 1)
        #expect(!session.travelDestinations.contains(towns[0]))
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

    /// Some adventurers travel together, as you do with your party (crowd.json `groupChance`):
    /// never troublemakers, no more in a group than `groupSize` lets, about the same level, all
    /// counted among the map's adventurers; and when the one leading leaves (joining you, or after a
    /// duel), the rest go on together in the same order.
    @Test func adventurersTravelInGroups() throws {
        let def = try #require(Content.shared.map("meadowbrook"))
        let most = Content.shared.crowd.groupSize?.last ?? 1
        let map = Layouts.of(def)
        var seen = false
        for _ in 0..<8 {
            let crowd = Crowd(def: def, map: map, world: SKNode())
            let everyone = crowd.adventurerPositions.map(\.profile)
            #expect(everyone.count <= def.crowd?.adventurers ?? 0)
            for adventurer in everyone {
                let group = crowd.group(of: adventurer.id)
                #expect(group.count <= most, "a group of \(group.count)")
                #expect(group.contains { $0.id == adventurer.id })
                guard group.count > 1 else { continue }
                #expect(group.allSatisfy { !$0.hostile })
                let levels = group.map(\.level)
                #expect((levels.max() ?? 0) - (levels.min() ?? 0) <= 6, "levels \(levels) in one group")
            }
            let leaders = everyone.filter { crowd.groupSize(of: $0.id) > 1 && crowd.group(of: $0.id).first?.id == $0.id }
            guard let leader = leaders.first else { continue }
            seen = true
            let rest = crowd.group(of: leader.id).dropFirst().map(\.id)
            crowd.remove(leader.id, poof: false)
            #expect(crowd.group(of: rest[0]).map(\.id) == rest)
        }
        #expect(seen, "no adventurers travelled together in Meadowbrook in eight tries")
    }

    /// Adventurers don't keep together for ever (playtesting 2026-10-16): after a while whoever walks
    /// behind in a group heads off on their own (`Crowd.mingle`); the party you've joined keeps
    /// together, leading you about.
    @Test func adventurersComeAndGoFromGroups() throws {
        let def = try #require(Content.shared.map("meadowbrook"))
        let map = Layouts.of(def)
        var tried = 0
        for _ in 0..<16 where tried < 3 {
            let crowd = Crowd(def: def, map: map, world: SKNode(), mingle: 0.05...0.05)
            let everyone = crowd.adventurerPositions.map(\.profile)
            let leaders = everyone.filter { crowd.groupSize(of: $0.id) > 1 && crowd.group(of: $0.id).first?.id == $0.id }
            guard leaders.count >= 2 else { continue }
            tried += 1
            let yours = crowd.group(of: leaders[0].id).map(\.id)
            let theirs = crowd.group(of: leaders[1].id).map(\.id)
            #expect(crowd.lead(you: leaders[0].id))
            #expect(crowd.yourLeader == leaders[0].id && crowd.yourPlace != nil)
            crowd.update(dt: 0.1, player: CGPoint(x: -100_000, y: -100_000))
            #expect(crowd.group(of: leaders[0].id).map(\.id) == yours, "the party you joined split up")
            #expect(crowd.group(of: leaders[1].id).map(\.id) != theirs, "no one left their group")
            crowd.letYouGo()
            #expect(crowd.yourLeader == nil && crowd.yourPlace == nil)
        }
        #expect(tried > 0, "never two groups in Meadowbrook in sixteen tries")
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
    }

    /// A woman in armour with a walk sheet of its own still has her hair: the armour goes over her
    /// hairstyle from a fifth of the way down the head (`nape_*`), dyed her colour.
    @Test func armourSheetsKeepTheHerosHair() throws {
        let content = Content.shared
        let plate = try #require(content.item("iron_plate"))
        let race = content.race("human")
        let look = Look(hair: "blue", outfit: "green", skin: "fair", gender: "female")
        let layers = GameSession.layers(race: race, look: look, armor: plate)
        let sheet = try #require(plate.sheets?["human"])
        #expect(layers.map(\.id) == ["nape_\(GameSession.style(for: look, race: race))_human_female", sheet])
        #expect(layers.first?.recolor?.isEmpty == false)
        for layer in layers { #expect(ArtLibrary.shared.artImage(layer.id) != nil, "art/sprites/\(layer.id).png is missing") }
    }

    /// A festive hat sits on the hair, in place of a helmet or hood; and in a festive season, about
    /// half the crowd wears one of its hats, the same one all season.
    @Test func festiveHatsSitOnTheHair() throws {
        let content = Content.shared
        let hide = try #require(content.item("copper_hide"))
        let race = content.race("human")
        #expect(GameSession.layers(race: race, look: .standard, armor: hide).map(\.id).contains("hood_human"))
        let hatted = GameSession.layers(race: race, look: .standard, armor: hide, hatted: true).map(\.id)
        #expect(!hatted.contains("hood_human") && hatted.contains { $0.hasPrefix("hair_") })
        for hat in content.items where hat.type == .head {
            #expect(["crown", "santa", "ears", "mask"].contains(hat.hat ?? ""), "\(hat.id) has no way to be drawn")
            #expect(hat.color != nil && hat.price == 0)
        }

        let calendar = Calendar(identifier: .gregorian)
        let party = try #require(calendar.date(from: DateComponents(year: 2027, month: 1, day: 1, hour: 12)))
        let summer = try #require(calendar.date(from: DateComponents(year: 2027, month: 7, day: 1, hour: 12)))
        let hats = try #require(GameSession.season(on: party)?.season.hats)
        var wearing = 0
        for _ in 0..<60 {
            let someone = Adventurer(name: "Momo", raceID: "elf", classID: "mage", level: 40, look: .standard)
            let hat = GameSession.hat(for: someone, on: party)
            #expect(GameSession.hat(for: someone, on: party)?.id == hat?.id)
            #expect(GameSession.hat(for: someone, on: summer) == nil)
            if let hat {
                #expect(hats.contains(hat.id))
                wearing += 1
            }
        }
        #expect((15...45).contains(wearing), "\(wearing) of 60 wear a party hat")
    }

    /// Gloves, boots and a necklace on the crowd too, each for their level and class, the same every
    /// time, and not on everyone.
    @Test func botsWearGlovesBootsAndNecklaces() {
        var counts: [ItemType: Int] = [:]
        for _ in 0..<60 {
            let someone = Adventurer(name: "Momo", raceID: "dwarf", classID: "tamer", level: 70, look: .standard)
            let worn = GameSession.trinkets(for: someone)
            #expect(GameSession.trinkets(for: someone).map(\.id) == worn.map(\.id))
            #expect(Set(worn.map(\.type)).count == worn.count)
            for item in worn {
                #expect([ItemType.gloves, .boots, .necklace].contains(item.type))
                #expect((item.level ?? 1) <= 70, "\(item.id) is above level 70")
                #expect(item.color != nil, "\(item.id) has no colour to wear it in")
                counts[item.type, default: 0] += 1
            }
        }
        for slot in [ItemType.gloves, .boots, .necklace] {
            #expect((10...59).contains(counts[slot] ?? 0), "\(counts[slot] ?? 0) of 60 wear \(slot)")
        }
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
        // Since 0.6.0 the road to Pineapple Shore leaves from Meadowbrook (it was Sunny Meadow's).
        guard let road = Content.shared.map("meadowbrook")?.exits.first(where: { $0.to == "pineapple_shore" }) else {
            Issue.record("no road from Meadowbrook to Pineapple Shore")
            return
        }
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
    /// on a shared runner) the biggest maps took 50 to 91 s across runs of the same code (the runner's
    /// speed swings that much), and with the shores (0.6.0) Smiling Forest 145 to 152 s laid out and
    /// built, so there the bound only catches a map that's become pathologically slow, and the job's
    /// log lists every map's time (⏱) to watch.
    #if DEBUG
    static let mapBuildLimit: Duration = .seconds(200)
    #else
    static let mapBuildLimit: Duration = .seconds(3)
    #endif

    /// A land built in the background gives the frame back every few milliseconds; this prints the
    /// longest it kept the game waiting in one go and where (⏱), on a big wooded land and on the
    /// sand coast past the downs. In a debug build on a CI simulator it's many times what a phone
    /// takes.
    @Test func landsBuildAFewMillisecondsAtATime() async {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        for id in ["smiling_forest", "pineapple_shore"] {
            guard let def = Content.shared.map(id) else { continue }
            let clock = ContinuousClock()
            let start = clock.now
            let grid = WorldMap(def: def)
            let laidOut = clock.now - start
            let scene = WorldScene(map: def, session: session, input: InputState(), entry: nil, grid: grid)
            await scene.build(pace: .background) { _ in }
            #expect(scene.isBuilt)
            let slices = scene.longestSlices.map { "\($0.time) (lines \($0.from) to \($0.to))" }.joined(separator: ", ")
            print("⏱ \(id) in the background: laid out \(laidOut) (off the main thread), longest slice \(scene.longestSlice), in all \(clock.now - start); longest in WorldScene.swift: \(slices)")
        }
    }

    /// Every map must build, and quickly; this prints how long each one takes: laying it out (the
    /// grid, off the main thread in the game) and building its scene on that layout, as the game
    /// does (the scene isn't made to lay it out again).
    @Test func mapsBuildQuickly() async throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        for def in Content.shared.maps {
            let clock = ContinuousClock()
            var laidOut: WorldMap?
            let gridTime = clock.measure { laidOut = WorldMap(def: def) }
            let grid = try #require(laidOut)
            let start = clock.now
            let scene = WorldScene(map: def, session: session, input: InputState(), entry: nil, grid: grid)
            await scene.build { _ in }
            let sceneTime = clock.now - start
            #expect(scene.isBuilt)
            print("⏱ \(def.id): grid \(gridTime), scene \(sceneTime), cells \(grid.columns * grid.rows)")
            #expect(gridTime + sceneTime < Self.mapBuildLimit, "\(def.id) took \(gridTime + sceneTime) to build")
        }
    }
}

/// Reasons to come back (GameSession+Rewards.swift): titles, the daily gift, bounties and the
/// Monster Book's milestones.
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
        // Earned once, and it stays earned.
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

    /// A land's cape (rewards.json `prizes`): earned once every monster that lives there is beaten,
    /// told of once, woven by the weaver (whose "!" says so) and had once; worn in its own slot for
    /// its stats; and woven again if it's lost.
    @Test func capesAreEarnedWovenAndWorn() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let prize = try #require(session.prizes.first { $0.kind == .land && $0.land == "sunny_meadow" })
        let weaver = try #require(session.weaver)
        let monsters = session.monsters(of: "sunny_meadow")
        #expect(!monsters.isEmpty)
        let start = session.prizeProgress(prize)
        #expect(start.have == 0 && start.need == monsters.count)
        #expect(!session.hasEarned(prize) && session.notice(for: weaver.npc.id) == nil)
        #expect(!session.takeCape(prize))
        for monster in monsters.dropLast() { session.beatMonster(monster, level: 3) }
        #expect(!session.hasEarned(prize))
        session.beatMonster(try #require(monsters.last), level: 3)
        #expect(session.hasEarned(prize))
        #expect(session.capesWaiting.map(\.item) == [prize.item])
        // Told once (after a fight, as `checkTitles` runs), and the weaver's "!" says so.
        session.checkTitles()
        #expect(session.notice(for: weaver.npc.id) == .available)
        #expect(session.data.capesTold == [prize.item])
        session.checkTitles()
        #expect(session.data.capesTold == [prize.item])
        // Woven once.
        #expect(session.takeCape(prize))
        #expect(session.count(of: prize.item) == 1 && session.hasCape(prize))
        #expect(!session.takeCape(prize))
        #expect(session.capesWaiting.isEmpty && session.notice(for: weaver.npc.id) == nil)
        // Worn in its own slot, next to armour, for its stats.
        let before = session.heroStats
        session.equip(prize.item)
        #expect(session.data.hero.equipment.cape == prize.item && session.hasCape(prize))
        let cape = try #require(Content.shared.item(prize.item))
        #expect(session.heroStats.defense == before.defense + (cape.stats?.defense ?? 0))
        #expect(GameSession.lookKey(for: session.data.hero).contains(prize.item))
        // Lost (it can't be sold), it can be woven again.
        session.unequip(.cape)
        #expect(session.removeItem(prize.item))
        #expect(session.capesWaiting.map(\.item) == [prize.item])
        session.checkTitles()
        #expect(session.notice(for: weaver.npc.id) == .available)
    }

    /// The capes are the weaver's alone: none for sale, none dropped, no adventurer wears one; the
    /// Storyleaf Cape takes every other one; and a save from before capes loads with none on.
    @Test func capesAreOnlyTheWeavers() throws {
        let content = Content.shared
        let capes = content.items.filter { $0.type == .cape }
        #expect(capes.count == content.rewards.prizes?.count)
        let session = GameSession.newGame(name: "Test", raceID: "human")
        for cape in capes {
            #expect(content.isTreasure(cape.id) && cape.price == 0, "\(cape.id) could be sold or found elsewhere")
            session.addItem(cape.id)
            #expect(!session.sellableItems.contains { $0.id == cape.id }, "\(cape.id) can be sold")
        }
        session.data.hero.level = 200
        for _ in 0..<300 {
            if let drop = session.equipmentDrop(level: 190, best: true) { #expect(drop.type != .cape, "a monster dropped \(drop.id)") }
        }
        let crown = try #require(session.prizes.first { $0.kind == .capes })
        let others = session.prizes.filter { $0.kind != .capes }
        let crowning = session.prizeProgress(crown)
        #expect(crowning.have == 0 && crowning.need == others.count)
        let old = try JSONDecoder().decode(Equipment.self, from: Data(#"{"weapon":"wooden_sword","armor":"cloth_tunic"}"#.utf8))
        #expect(old.cape == nil)
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

    /// Festive seasons (playtesting 2026-10-17: "festive items like party, halloween, Christmas and
    /// Easter"): each on its own days, the New Year's party round the turn of the year, Easter with
    /// Easter Sunday. The first gift of one brings one of its hats you haven't got, once a season;
    /// won fights leave its treats now and then, and only in a season.
    @Test func festiveSeasonsComeOnTheirDays() throws {
        let calendar = Calendar(identifier: .gregorian)
        func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .distantPast
        }
        #expect(GameSession.season(on: day(2026, 10, 31))?.key == "halloween-2026")
        #expect(GameSession.season(on: day(2026, 12, 24))?.key == "christmas-2026")
        #expect(GameSession.season(on: day(2026, 12, 31))?.key == "party-2026")
        #expect(GameSession.season(on: day(2027, 1, 7))?.key == "party-2026")
        #expect(GameSession.season(on: day(2027, 3, 28))?.key == "easter-2027")
        #expect(GameSession.season(on: day(2026, 4, 12))?.key == "easter-2026")
        #expect(GameSession.season(on: day(2026, 7, 1)) == nil)
        #expect(GameSession.season(on: day(2027, 1, 8)) == nil)
        for (year, month, date) in [(2025, 4, 20), (2026, 4, 5), (2027, 3, 28), (2028, 4, 16)] {
            let sunday = GameSession.easter(year: year)
            #expect(sunday.month == month && sunday.day == date, "Easter \(year)")
        }

        let session = GameSession.newGame(name: "Test", raceID: "human")
        let halloween = try #require(GameSession.season(on: day(2026, 10, 20))?.season)
        let first = try #require(session.collectDailyGift(on: day(2026, 10, 20)))
        #expect(first.greeting == halloween.greeting)
        let mask = try #require(first.items.first { halloween.hats.contains($0) })
        #expect(session.count(of: mask) == 1)
        let next = try #require(session.collectDailyGift(on: day(2026, 10, 21)))
        #expect(next.greeting == nil && !next.items.contains { halloween.hats.contains($0) })
        // A year on, another of its hats: one you haven't got.
        let again = try #require(session.collectDailyGift(on: day(2027, 10, 20)))
        #expect(again.items.contains { halloween.hats.contains($0) && $0 != mask })
        #expect(!session.sellableItems.contains { $0.id == mask }, "\(mask) can be sold")

        var drops: [String: Int] = [:]
        for _ in 0..<2000 {
            if let found = session.seasonDrop(on: day(2026, 10, 20)) { drops[found.id, default: 0] += 1 }
            #expect(session.seasonDrop(on: day(2026, 7, 1)) == nil)
        }
        #expect(Set(drops.keys).isSubset(of: Set(halloween.treats + halloween.hats)))
        let treats = halloween.treats.reduce(0) { $0 + (drops[$1] ?? 0) }
        #expect((200...420).contains(treats), "\(treats) treats in 2000 fights")
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
        // No second of it: none to sell, no gold, no more strength (playtesting 2026-10-16).
        let gold = session.data.gold
        #expect(session.findCard(of: monster) == nil)
        #expect(session.data.gold == gold)
        #expect(session.heroStats == before + gain)
        #expect(session.cards(of: monster.id) == 1)
        #expect(session.cardCount == 1)
    }

    @Test func everyCardIsWorthSomething() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        for monster in Content.shared.monsters {
            #expect(session.cardGain(of: monster) != .zero, "\(monster.id)'s card gives nothing")
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

    @Test func botsWearTitlesThatFitTheirLevel() {
        let id = UUID()
        #expect(GameSession.botTitle(level: 5, id: id) == nil)
        #expect(GameSession.botTitle(level: 70, id: id)?.id == GameSession.botTitle(level: 70, id: id)?.id)
        let names = Set((0..<40).compactMap { _ in GameSession.botTitle(level: 70, id: UUID())?.name })
        #expect(names.isSubset(of: [Content.shared.title("veteran")?.name].compactMap { $0 }))
        #expect(!names.isEmpty)
    }
}

/// Each land laid out once for all the tests that only look at its layout (`ContentTests`): laying
/// one out takes seconds on CI, and those tests went through every land again and again, six of them
/// a quarter of an hour each, so the suite ran past its time. Don't change what they hand back: the
/// other tests see it too. (Tests that build scenes or plans on a land lay out their own.)
@MainActor
enum Layouts {
    private static var made: [String: WorldMap] = [:]

    static func of(_ def: MapDef) -> WorldMap {
        if let known = made[def.id] { return known }
        let map = WorldMap(def: def)
        made[def.id] = map
        return map
    }
}

/// The continent as one grid of world cells (`World`, docs/continuous-world.md).
@MainActor
struct WorldStoreTests {
    let content = Content.shared

    /// Every cell a land's shape owns is that land's on the continent's grid, and no cell is two
    /// lands'.
    @Test func everyLandCellHasOneOwner() {
        let world = World.continent()
        #expect(world.conflicts == 0, "\(world.conflicts) cells claimed by two lands")
        #expect(world.lands.count == content.maps.filter { content.world[$0.id] != nil }.count)
        for land in world.lands {
            guard let region = content.regions[land.id] else {
                Issue.record("\(land.id): no shape")
                continue
            }
            var owned = 0
            for row in 0..<land.rows {
                for col in 0..<land.columns where region.owns(GridPoint(col: col, row: row)) {
                    owned += 1
                    let cell = world.world(GridPoint(col: col, row: row), of: land)
                    if world.land(at: cell)?.id != land.id {
                        Issue.record("\(land.id): world cell \(cell) is \(world.land(at: cell)?.id ?? "nobody")'s")
                        return
                    }
                }
            }
            #expect(owned > 0, "\(land.id) owns no cells")
        }
    }

    /// A land's cells and world cells convert back and forth.
    @Test func worldAndLandCellsConvertBothWays() {
        let world = World.continent()
        for land in world.lands {
            for cell in [GridPoint(col: 0, row: 0), GridPoint(col: land.columns - 1, row: land.rows - 1), GridPoint(col: land.columns / 2, row: 3)] {
                #expect(world.local(world.world(cell, of: land), in: land) == cell, "\(land.id): \(cell)")
            }
        }
    }

    /// Chunks tile the grid: every cell is in the one chunk whose cells include it, west and south
    /// of the grid's origin too.
    @Test func chunksTileTheContinent() {
        let cells = [GridPoint(col: 0, row: 0), GridPoint(col: 31, row: 31), GridPoint(col: 32, row: 0), GridPoint(col: -1, row: -1),
                     GridPoint(col: -32, row: -33), GridPoint(col: 548, row: -467)]
        for cell in cells {
            let chunk = World.chunk(of: cell)
            let inside = World.cells(in: chunk)
            #expect(inside.count == World.chunkSize * World.chunkSize)
            #expect(inside.contains(cell), "\(cell) isn't in its chunk \(chunk)")
            #expect(inside.allSatisfy { World.chunk(of: $0) == chunk }, "chunk \(chunk) holds another's cells")
        }
        #expect(World.chunk(of: GridPoint(col: -1, row: 0)) == GridPoint(col: -1, row: 0))
    }

    /// A land laid out into the store gives each of its cells the ground and walking its own map
    /// has, and the lands not laid out yet stay empty.
    @Test func aLaidOutLandFillsItsOwnCells() throws {
        let world = World.continent()
        let def = try #require(content.map("sunny_meadow"))
        let land = try #require(world.land("sunny_meadow"))
        let map = WorldMap(def: def)
        world.add(map)
        #expect(world.isLaidOut("sunny_meadow"))
        #expect(!world.isLaidOut("frog_swamp"))
        var checked = 0, wrong = 0
        for row in 0..<map.rows {
            for col in 0..<map.columns {
                let cell = GridPoint(col: col, row: row)
                guard map.owns(cell) else { continue }
                let there = world.world(cell, of: land)
                if world.ground(at: there) != map.ground[row][col] || world.isWalkable(there) != map.isWalkable(cell) { wrong += 1 }
                checked += 1
            }
        }
        #expect(checked > 1000, "only \(checked) cells of Sunny Meadow")
        #expect(wrong == 0, "\(wrong) of Sunny Meadow's \(checked) cells differ in the store")
        let other = try #require(world.land("frog_swamp"))
        let region = try #require(content.regions["frog_swamp"])
        var empty: GridPoint?
        search: for row in 0..<other.rows {
            for col in 0..<other.columns where region.owns(GridPoint(col: col, row: row)) {
                empty = world.world(GridPoint(col: col, row: row), of: other)
                break search
            }
        }
        let cell = try #require(empty)
        #expect(world.ground(at: cell) == nil, "Frog Swamp has ground before it's laid out")
    }

    /// Before a land's laid out you can walk anywhere on it but its rivers and lakes, as its shape
    /// has them (`World.walkable`), so its layout never keeps you off it: over the border on each
    /// of its roads too. Never out at sea.
    @Test func aLandNotLaidOutIsWalkedButForItsRivers() throws {
        let world = World.continent()
        var owned = 0, rivers = 0, wrong: [String] = []
        for land in world.lands {
            let region = try #require(content.regions[land.id])
            for row in 0..<land.rows {
                for col in 0..<land.columns {
                    let cell = GridPoint(col: col, row: row)
                    let there = world.world(cell, of: land)
                    guard region.owns(cell), world.land(at: there)?.id == land.id else { continue }
                    owned += 1
                    if region.isRiver(cell) { rivers += 1 }
                    if world.isWalkable(there) == region.isRiver(cell), wrong.count < 5 { wrong.append("\(land.id) \(cell)") }
                }
            }
            for (to, road) in region.roads {
                #expect(world.isWalkable(world.world(road.at, of: land)), "\(land.id): its road to \(to) is shut at the border")
            }
        }
        #expect(rivers > 0 && rivers < owned, "\(rivers) of \(owned) cells under a river")
        #expect(wrong.isEmpty, "walked otherwise than the shape has it: \(wrong)")
        let sea = (0..<world.columns).lazy.map { GridPoint(col: world.low.col + $0, row: world.low.row) }.first { world.land(at: $0) == nil }
        #expect(sea.map { !world.isWalkable($0) } ?? false, "the sea's walkable, or there's none")
    }

    /// A way over the store (`World.path`) steps a cell at a time over ground you can walk on, never
    /// cutting a corner, and ends where it was asked to; one out of reach is none.
    @Test func pathsKeepToWalkableGround() throws {
        let world = World.continent()
        let def = try #require(content.map("sunny_meadow"))
        let land = try #require(world.land("sunny_meadow"))
        let map = WorldMap(def: def)
        world.add(map)
        let middle = try #require(world.nearestWalkable(to: world.world(map.center, of: land)))
        var found = 0
        for (dc, dr) in [(20, 0), (0, 20), (-25, 10), (15, -30), (30, 30)] {
            guard let goal = world.nearestWalkable(to: GridPoint(col: middle.col + dc, row: middle.row + dr)) else { continue }
            let cells = world.path(from: middle, to: goal)
            guard !cells.isEmpty else { continue }
            found += 1
            #expect(cells.last == goal)
            var at = middle
            for next in cells {
                let dx = next.col - at.col, dy = next.row - at.row
                #expect(max(abs(dx), abs(dy)) == 1 && world.isWalkable(next), "a step from \(at) to \(next)")
                if dx != 0, dy != 0 {
                    let open = world.isWalkable(GridPoint(col: at.col + dx, row: at.row)) && world.isWalkable(GridPoint(col: at.col, row: at.row + dy))
                    #expect(open, "cuts a corner at \(at)")
                }
                at = next
            }
        }
        #expect(found >= 2, "only \(found) of the ways across Sunny Meadow found")
        #expect(world.path(from: middle, to: GridPoint(col: middle.col + 100, row: middle.row), reach: 64).isEmpty)
    }
}

/// A land's scenery decided before it's drawn (`LandPlanner`, docs/continuous-world.md step 1b).
@MainActor
struct LandPlanTests {
    let content = Content.shared

    private func planned(_ def: MapDef) async -> (map: WorldMap, plan: LandPlan) {
        let map = WorldMap(def: def)
        let planner = LandPlanner(def: def, map: map, art: ArtLibrary.shared)
        await planner.planUpToLocals(pause: {})
        await planner.planTheRest(pause: {})
        return (map, planner.plan)
    }

    /// Every way into a cave still leads on once its scenery and signposts are set down
    /// (playtesting 2026-10-16: the Rat Cavern's signpost stood where you came in from Lotus Land, in
    /// a tunnel a cell wide, and shut you in).
    @Test func cavesStayOpenFromEveryWayIn() async {
        for def in content.maps where def.theme.cave != nil {
            let (map, plan) = await planned(def)
            let arrivals = def.exits.map { map.entryCell(from: $0.edge) }
            // Everywhere you can walk to from its hub, where its roads meet and it's dug out from
            // (`MapDef.hub`, else the middle), a side at a time as you walk. The middle itself can be
            // rock when the hub's elsewhere: the Rat Cavern's is in its south west.
            let hub = def.hub ?? [0, 0]
            let start = GridPoint(col: map.center.col + (hub.first ?? 0), row: map.center.row + (hub.count > 1 ? hub[1] : 0))
            var reached: Set<GridPoint> = [start]
            var queue = [start]
            while let cell = queue.popLast() {
                for step in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let next = GridPoint(col: cell.col + step.0, row: cell.row + step.1)
                    guard map.isWalkable(next), !reached.contains(next) else { continue }
                    reached.insert(next)
                    queue.append(next)
                }
            }
            print("🪧 \(def.id): signposts at \(plan.signposts.map { "\($0.cell) to \($0.exit.to)" }), arriving at \(arrivals)")
            for (exit, arrival) in zip(def.exits, arrivals) {
                #expect(map.isWalkable(arrival) && reached.contains(arrival),
                        "map \(def.id): where you come in from \(exit.to), \(arrival), doesn't lead to its hub")
            }
            for sign in plan.signposts {
                #expect(!arrivals.contains { max(abs($0.col - sign.cell.col), abs($0.row - sign.cell.row)) <= 1 },
                        "map \(def.id): the signpost to \(sign.exit.to) stands where you come in")
            }
            // Climbing in by its stairs from the level over or under it (`NPCRole.stairs`), you come
            // out in front of them, somewhere that leads on too.
            for stairs in def.npcs ?? [] where stairs.role == .stairs {
                let other = stairs.to ?? ""
                let landing = map.stairsArrival(from: other)
                #expect(landing.map { map.isWalkable($0) && reached.contains($0) } == true,
                        "map \(def.id): where you climb in from \(other), \(String(describing: landing)), doesn't lead to its hub")
                #expect(content.map(other)?.npcs?.contains { $0.role == .stairs && $0.to == def.id } == true,
                        "map \(other) has no stairs back to \(def.id)")
            }
        }
    }

    /// Building the scene takes no cell the plan didn't: where you can walk is settled once the plan's
    /// run, so the continent's store can have it without drawing the land.
    @Test func theSceneTakesNoCellItsPlanDidnt() async throws {
        let def = try #require(content.map("sunny_meadow"))
        let plan = await planned(def)
        let scene = WorldScene(map: def, session: GameSession.newGame(name: "Test", raceID: "human"), input: InputState(), entry: nil)
        await scene.build { _ in }
        var differ: [GridPoint] = []
        for row in 0..<plan.map.rows {
            for col in 0..<plan.map.columns {
                let cell = GridPoint(col: col, row: row)
                if plan.map.isWalkable(cell) != scene.layout.isWalkable(cell) { differ.append(cell) }
            }
        }
        #expect(differ.isEmpty, "\(differ.count) cells differ between the plan and the scene, first \(Array(differ.prefix(5)))")
        #expect(!plan.plan.props.isEmpty, "Sunny Meadow planned no props")
    }

    /// No prop stands on the coast's own cells, which the shoreline curves through: a palm on
    /// Ingothold Lake's beach stood in the sea (playtesting 2026-10-15).
    @Test func propsKeepOffTheCoast() async throws {
        let def = try #require(content.map("goldburg_lake"))
        let result = await planned(def)
        let map = result.map
        let cells = result.plan.props.map(\.cell) + result.plan.seamProps.map(\.cell)
        let wet = cells.filter { cell in
            (-1...1).contains { dr in
                (-1...1).contains { dc in
                    let next = GridPoint(col: cell.col + dc, row: cell.row + dr)
                    return map.contains(next) ? map.ground[next.row][next.col] == .sea : map.isOpenSea(next)
                }
            }
        }
        #expect(!cells.isEmpty, "Ingothold Lake planned no props")
        #expect(wet.isEmpty, "\(wet.count) props on Ingothold Lake's coast, first \(Array(wet.prefix(3)))")
    }

    /// A lake's island stays open to walk about on: nothing in the way inside it, a little round its
    /// shore, none beside its footbridge (Swan Lake's grew into a thicket, playtesting 2026-10-16).
    @Test func lakeIslandsStayOpen() async throws {
        let def = try #require(content.map("swan_lake"))
        let result = await planned(def)
        let map = result.map
        let island = Set(map.lakes.flatMap { $0.island })
        try #require(!island.isEmpty, "Swan Lake has no island")
        func around(_ cell: GridPoint) -> [GridPoint] {
            (-1...1).flatMap { dr in (-1...1).map { dc in GridPoint(col: cell.col + dc, row: cell.row + dr) } }
        }
        let shore = island.filter { around($0).contains { !island.contains($0) } }
        let inTheWay = (result.plan.props + result.plan.seamProps).filter { $0.prop?.blocking == true && island.contains($0.cell) }
        let inside = inTheWay.filter { !shore.contains($0.cell) }
        let byTheBridge = inTheWay.filter { around($0.cell).contains { map.bridgeCells.contains($0) } }
        #expect(inside.isEmpty, "\(inside.count) things in the way inside Swan Lake's island, first \(inside.first?.cell as Any)")
        #expect(byTheBridge.isEmpty, "\(byTheBridge.count) things in the way beside the island's footbridge")
        #expect(inTheWay.count * 4 <= shore.count, "\(inTheWay.count) things in the way round an island shore \(shore.count) cells long")
    }

    /// The same land plans the same every time: its props, its neighbours' over the line, its people
    /// and its signposts, on the same cells, nudged the same.
    @Test func aLandsPlanIsTheSameEveryTime() async throws {
        let def = try #require(content.map("frog_swamp"))
        let first = await planned(def).plan
        let second = await planned(def).plan
        #expect(first.props.map { $0.cell } == second.props.map { $0.cell })
        #expect(first.props.map { $0.nudge } == second.props.map { $0.nudge })
        #expect(first.seamProps.map { $0.cell } == second.seamProps.map { $0.cell })
        #expect(first.reeds.map { $0.cell } == second.reeds.map { $0.cell })
        #expect(first.npcs.map { $0.cell } == second.npcs.map { $0.cell })
        #expect(first.signposts.map { $0.cell } == second.signposts.map { $0.cell })
        #expect(!first.props.isEmpty, "Frog Swamp planned no props")
    }

    /// What lines the roads on every land that has any (🚧 in the tests job's log, to tune by): how
    /// many stretches of each kind and how many cells they take, against how much road it has.
    @Test func roadsidesOnEveryLand() async throws {
        for def in content.maps where def.theme.roadside != nil {
            let (map, plan) = await planned(def)
            var roads = 0
            for row in 0..<map.rows {
                for col in 0..<map.columns where map.ground[row][col] == .path && map.owns(GridPoint(col: col, row: row)) { roads += 1 }
            }
            let kinds = Dictionary(grouping: plan.roadsides, by: { $0.kind.rawValue }).map { "\($0.value.count) \($0.key)" }.sorted()
            let cells = plan.roadsides.reduce(0) { $0 + $1.cells.count }
            print("🚧 \(def.id): \(plan.roadsides.count) lined (\(kinds.joined(separator: ", "))), \(cells) cells; \(roads) road cells, \(map.fenceCells.count) wall")
        }
    }

    /// Stretches of the roads are lined (`LandPlanner.planRoadsides`): a fence, a low wall or a row of
    /// the land's props on the cells beside a road, one after another along it, and never in the
    /// way: a fence or a wall can't be walked through, and you can always get round it from the
    /// road to the ground behind.
    @Test func roadsidesLineTheRoads() async throws {
        var kinds: Set<String> = []
        for id in ["sunny_meadow", "valley_of_fear", "crystal_mountain", "twilight_woods", "goldburg", "frog_swamp"] {
            let def = try #require(content.map(id))
            let (map, plan) = await planned(def)
            print("🚧 \(id): " + plan.roadsides.map { "\($0.kind.rawValue) \($0.cells.count)" }.joined(separator: ", "))
            for line in plan.roadsides {
                kinds.insert(line.kind.rawValue)
                #expect(line.cells.count >= 4, "\(id): a lined stretch only \(line.cells.count) long")
                // One after another: a fence's or a wall's cells side by side, so its pieces join; a
                // row's corner to corner where it steps with the road's edge.
                for (a, b) in zip(line.cells, line.cells.dropFirst()) {
                    let apart = line.kind == .row ? max(abs(a.col - b.col), abs(a.row - b.row)) : abs(a.col - b.col) + abs(a.row - b.row)
                    #expect(apart == 1, "\(id): a lined stretch skips from \(a) to \(b)")
                }
                func isRoad(_ cell: GridPoint) -> Bool { map.contains(cell) && map.ground[cell.row][cell.col] == .path }
                // The road on one side of it, the same side all along: beside every cell, or a cell
                // further where a fence steps out with the road's edge.
                let side = [Edge.north, .east, .south, .west].first { side in
                    line.cells.allSatisfy { isRoad($0.stepped(side.opposite)) || isRoad($0.stepped(side.opposite, by: 2)) }
                }
                guard let side else {
                    Issue.record("\(id): a lined stretch at \(line.cells[0]) not along a road")
                    continue
                }
                if line.kind != .row {
                    #expect(line.cells.allSatisfy { !map.isWalkable($0) }, "\(id): a \(line.kind.rawValue) you can walk through")
                }
                // In a town, out in its countryside, clear of its wall and gates.
                #expect(line.cells.allSatisfy { cell in map.fenceCells.allSatisfy { max(abs($0.col - cell.col), abs($0.row - cell.row)) > 3 } },
                        "\(id): a \(line.kind.rawValue) up against the town's wall")
                // From the road in front of its middle round to the ground behind it.
                let besideRoad = line.cells.filter { isRoad($0.stepped(side.opposite)) }
                let middle = besideRoad.isEmpty ? line.cells[line.cells.count / 2] : besideRoad[besideRoad.count / 2]
                let way = map.path(from: map.center(of: middle.stepped(side.opposite)), to: map.center(of: middle.stepped(side)))
                #expect(!way.isEmpty, "\(id): no way round the \(line.kind.rawValue) at \(middle)")
            }
        }
        #expect(kinds.contains("fence") || kinds.contains("wall"), "no fence or wall along any road")
        #expect(kinds.contains("row"), "no row of props along any road")
    }
}

/// Where a land's layout spends its time, step by step (⏱ in the tests job's log). In a Release
/// build (the job's `configuration`) the layout took about as long as in a Debug one (Frog Swamp
/// 85 s on CI's simulator, 2026-10-15), so its time goes somewhere the optimiser can't reach.
@MainActor
struct LayoutStepTests {
    @Test func layoutSteps() throws {
        for id in ["frog_swamp", "goldburg_lake", "smiling_forest"] {
            let def = try #require(Content.shared.map(id))
            WorldMap.timings = []
            _ = WorldMap(def: def)
            let steps = WorldMap.timings ?? []
            WorldMap.timings = nil
            let total = steps.reduce(Duration.zero) { $0 + $1.time }
            let slowest = steps.sorted { $0.time > $1.time }.map { "\($0.step) \($0.time)" }.joined(separator: ", ")
            print("⏱ \(id) laid out in \(total): \(slowest)")
            #expect(!steps.isEmpty)
        }
    }
}
