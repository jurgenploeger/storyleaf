import CoreGraphics

/// The lands as one continent (content/world.json, painted by tools/world_layout.py): each land a
/// shape of its own (`Region`), as RuneScape's regions are, the shapes fitting into each other where
/// their boxes overlap; where no land lies, the sea. You walk from one land into the next anywhere
/// along the border they share, once you can: where a quest opens the road between them, a fence
/// stands along it with a barred gate on the road until the quest is done; where no road crosses, a
/// fence stands until the roads you can take join the two lands some other way (`joined`), so no
/// border lets you round a quest. A town is a land like any other, its walled square in the middle
/// of its own countryside. Caves aren't on it: you go into them through their mouths, behind a
/// loading card, as ever.
enum Continent {
    /// A land beside another (`here`), as `here` sees it.
    struct Neighbour {
        let def: MapDef
        /// Its box's south-west cell, in `here`'s cells.
        let offset: GridPoint
        /// The road across this border, as `here` has it.
        let exit: MapDef.Exit?
        /// Where that road crosses: the last cell on `here`'s side (`Region.Road.at`); the next one
        /// over, the way the exit goes, is this land's.
        let road: GridPoint?
        /// The quest that opens the road, from either side (maps.json gives it on the side you
        /// come from first; the border's the same gate both ways).
        let quest: String?
        /// Where the two meet: each cell of `here` along the border, with the cell of this land beside
        /// it (east, west, north or south of it), in `here`'s cells.
        let border: [(inside: GridPoint, outside: GridPoint)]

        /// Whether you can step over onto `cell` (one of this land's, beside one of `here`'s, in
        /// `here`'s cells). `done`: whether you've done a quest; `joined`: whether the roads you can
        /// take join the two lands already (`Continent.joined`). Anywhere along the border once you can
        /// cross at all (`isCrossable`).
        func isOpen(over cell: GridPoint, done: (String) -> Bool, joined: Bool) -> Bool {
            isCrossable(done: done, joined: joined)
        }

        /// The cell the road crosses onto, this land's (in `here`'s cells).
        func gate(of exit: MapDef.Exit) -> GridPoint? {
            road.map { $0.stepped(exit.edge) }
        }

        /// Whether you can walk across it anywhere: a road crosses it with no quest, or its quest
        /// is done; where no road crosses, once the roads you can take join the two lands (`joined`),
        /// so it never takes you round a quest.
        func isCrossable(done: (String) -> Bool, joined: Bool) -> Bool {
            if let quest { return done(quest) }
            return exit != nil || joined
        }

        /// Whether a wall stands along it (`BorderArt`): until you can walk across.
        func isWalled(done: (String) -> Bool, joined: Bool) -> Bool {
            !isCrossable(done: done, joined: joined)
        }

        /// A cell of `here`, in this land's own cells.
        func local(_ cell: GridPoint) -> GridPoint {
            GridPoint(col: cell.col - offset.col, row: cell.row - offset.row)
        }

        /// How many cells `cell` (of `here`) is from this border, a step any way at a time.
        func distance(from cell: GridPoint) -> Int {
            border.reduce(Int.max) { nearest, pair in
                min(nearest, max(abs(pair.inside.col - cell.col), abs(pair.inside.row - cell.row)))
            }
        }
    }

    /// How many cells either side of a quest's road its gate is open, once the quest is done.
    static let gateReach = 2

    /// The lands on the continent and where each lies (its box's south-west cell), in world cells.
    private static var lands: [(def: MapDef, origin: GridPoint)] {
        let content = Content.shared
        return content.maps.compactMap { def in content.world[def.id].map { (def, $0) } }
    }

    /// Where `def`'s box's south-west cell lies on the continent, or nil off it (a cave).
    static func origin(of def: MapDef) -> GridPoint? { Content.shared.world[def.id] }

    /// `def`'s shape on the continent, or nil off it (a cave).
    static func region(of def: MapDef) -> Region? { Content.shared.regions[def.id] }

    /// The land a world cell lies in, if any (none: the sea).
    static func owner(atWorld cell: GridPoint) -> MapDef? {
        let regions = Content.shared.regions
        for (def, origin) in lands {
            let local = GridPoint(col: cell.col - origin.col, row: cell.row - origin.row)
            guard local.col >= 0, local.row >= 0, local.col < def.width, local.row < def.height,
                  regions[def.id]?.owns(local) == true else { continue }
            return def
        }
        return nil
    }

    /// The land a cell of `here` lies in (in `here`'s cells, anywhere), if any: none off the continent.
    static func owner(of cell: GridPoint, from here: MapDef) -> MapDef? {
        guard let origin = origin(of: here) else { return nil }
        return owner(atWorld: GridPoint(col: cell.col + origin.col, row: cell.row + origin.row))
    }

    /// Whether a cell of `here` (in its cells, anywhere) lies in any land.
    static func isLand(_ cell: GridPoint, from here: MapDef) -> Bool {
        owner(of: cell, from: here) != nil
    }

    /// The lands sharing a stretch of border with `here` (none for a cave), each with the road
    /// across, if one crosses.
    static func neighbours(of here: MapDef) -> [Neighbour] {
        guard let origin = origin(of: here), let region = region(of: here) else { return [] }
        let regions = Content.shared.regions
        // The lands whose boxes come within a cell of here's, with their shapes and offsets.
        let near: [(def: MapDef, region: Region, offset: GridPoint)] = lands.compactMap { land in
            guard land.def.id != here.id, let shape = regions[land.def.id] else { return nil }
            let offset = GridPoint(col: land.origin.col - origin.col, row: land.origin.row - origin.row)
            guard offset.col <= here.width, offset.row <= here.height,
                  offset.col + land.def.width >= 0, offset.row + land.def.height >= 0 else { return nil }
            return (land.def, shape, offset)
        }
        var borders: [String: [(inside: GridPoint, outside: GridPoint)]] = [:]
        for row in 0..<here.height {
            for col in 0..<here.width {
                let cell = GridPoint(col: col, row: row)
                guard region.owns(cell) else { continue }
                for edge in [Edge.east, .west, .north, .south] {
                    let next = cell.stepped(edge)
                    guard !region.owns(next) else { continue }
                    for land in near {
                        let local = GridPoint(col: next.col - land.offset.col, row: next.row - land.offset.row)
                        guard land.region.owns(local) else { continue }
                        borders[land.def.id, default: []].append((cell, next))
                        break
                    }
                }
            }
        }
        return near.compactMap { land in
            guard let border = borders[land.def.id] else { return nil }
            let exit = here.exits.first { $0.to == land.def.id }
            let back = land.def.exits.first { $0.to == here.id }
            return Neighbour(def: land.def, offset: land.offset, exit: exit, road: exit.flatMap { region.roads[$0.to]?.at },
                             quest: exit == nil ? nil : exit?.requires ?? back?.requires, border: border)
        }
    }

    /// Whether the roads you can take now join two maps (`done`: whether you've done a quest): roads
    /// between lands and into caves and out, each both ways, a road a quest opens once it's done.
    static func joined(_ first: String, _ second: String, done: (String) -> Bool) -> Bool {
        reachable(from: first, done: done).contains(second)
    }

    /// The maps the roads you can take now lead to from `start` (`joined`), it among them.
    static func reachable(from start: String, done: (String) -> Bool) -> Set<String> {
        let content = Content.shared
        var roads: [String: Set<String>] = [:]
        for def in content.maps {
            for exit in def.exits {
                let back = content.map(exit.to)?.exits.first { $0.to == def.id }
                guard (exit.requires ?? back?.requires).map(done) ?? true else { continue }
                roads[def.id, default: []].insert(exit.to)
                roads[exit.to, default: []].insert(def.id)
            }
        }
        var seen: Set<String> = [start]
        var queue = [start]
        while let id = queue.popLast() {
            for next in roads[id] ?? [] where !seen.contains(next) {
                seen.insert(next)
                queue.append(next)
            }
        }
        return seen
    }

    /// Where `here` lies among the lands, for laying it out off the main actor (`WorldMap`): its shape,
    /// and which land holds each cell of its box and the margin round it. Nil for a cave.
    static func neighbourhood(of here: MapDef) -> Neighbourhood? {
        guard let origin = origin(of: here), let region = region(of: here) else { return nil }
        let regions = Content.shared.regions
        let margin = region.margin
        let width = here.width + 2 * margin, height = here.height + 2 * margin
        var owners = [Int16](repeating: -1, count: width * height)
        var ids: [String] = []
        for land in lands {
            guard let shape = regions[land.def.id] else { continue }
            // Its box in this window's cells.
            let left = land.origin.col - origin.col + margin, bottom = land.origin.row - origin.row + margin
            let from = (col: max(0, left), row: max(0, bottom))
            let to = (col: min(width, left + land.def.width), row: min(height, bottom + land.def.height))
            guard from.col < to.col, from.row < to.row else { continue }
            let index = Int16(ids.count)
            var any = false
            for y in from.row..<to.row {
                for x in from.col..<to.col where shape.owns(GridPoint(col: x - left, row: y - bottom)) {
                    owners[y * width + x] = index
                    any = true
                }
            }
            guard any else { continue }
            ids.append(land.def.id)
        }
        return Neighbourhood(region: region, origin: origin, lands: ids, owners: owners)
    }

    /// The other lands within `reach` cells of `here`'s box, each with its box's south-west cell in
    /// `here`'s cells (none for a cave): what shows round it on the minimap and past its borders.
    static func lands(near here: MapDef, within reach: Int) -> [(def: MapDef, offset: GridPoint)] {
        guard let origin = origin(of: here) else { return [] }
        return lands.compactMap { land in
            guard land.def.id != here.id else { return nil }
            let low = GridPoint(col: land.origin.col - origin.col, row: land.origin.row - origin.row)
            guard low.col + land.def.width > -reach, low.row + land.def.height > -reach,
                  low.col < here.width + reach, low.row < here.height + reach else { return nil }
            return (land.def, low)
        }
    }
}

/// Where a land lies among the others (`Continent.neighbourhood(of:)`), for laying it out off the
/// main actor: its shape, and which land holds each cell of its box and the margin round it.
nonisolated struct Neighbourhood: Sendable {
    let region: Region
    /// The land's box's south-west cell on the continent.
    let origin: GridPoint
    /// The lands holding any cell of the window, this one among them, by id.
    let lands: [String]
    /// Which of `lands` holds each cell of the window (the box and `region.margin` round it, row by
    /// row from the south), -1 none: the sea.
    private let owners: [Int16]

    init(region: Region, origin: GridPoint, lands: [String], owners: [Int16]) {
        self.region = region
        self.origin = origin
        self.lands = lands
        self.owners = owners
    }

    var margin: Int { region.margin }
    /// The window's size.
    var width: Int { region.columns + 2 * region.margin }
    var height: Int { region.rows + 2 * region.margin }

    /// Which of `lands` holds a cell (in the land's cells), nil for the sea; out past the window, the sea.
    func owner(_ cell: GridPoint) -> Int? {
        let x = cell.col + margin, y = cell.row + margin
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let index = owners[y * width + x]
        return index < 0 ? nil : Int(index)
    }

    /// Whether a cell (in the land's cells) lies in any land.
    func isLand(_ cell: GridPoint) -> Bool { owner(cell) != nil }
}

nonisolated extension GridPoint {
    /// The cell `count` steps over `edge`'s way.
    func stepped(_ edge: Edge, by count: Int = 1) -> GridPoint {
        switch edge {
        case .east: GridPoint(col: col + count, row: row)
        case .west: GridPoint(col: col - count, row: row)
        case .north: GridPoint(col: col, row: row + count)
        case .south: GridPoint(col: col, row: row - count)
        }
    }
}
