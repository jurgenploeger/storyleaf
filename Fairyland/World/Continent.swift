import CoreGraphics

/// The lands as one continent (content/world.json, laid out by tools/world_layout.py): where each
/// lies, which touch, and where you can walk across. Lands a road joins are open along the border
/// they share; a road a quest opens crosses a fence through a gate, shut until the quest is done;
/// every other border is walled off. All round the lands, where no land lies, is the sea, fading into
/// haze further out. Caves aren't on it: you go into them through their mouths, behind a loading
/// card, as ever.
enum Continent {
    /// A land beside another (`here`), as `here` sees it.
    struct Neighbour {
        let def: MapDef
        /// Its south-west cell, in `here`'s cells.
        let offset: GridPoint
        /// The edge of `here` it lies along.
        let edge: Edge
        /// The cells along that edge the two share: columns on the north and south, rows on the
        /// east and west, in `here`'s cells.
        let span: ClosedRange<Int>
        /// The road across this border, as `here` has it.
        let exit: MapDef.Exit?
        /// Where that road crosses, along the edge (in `here`'s cells): `meets`, else `at`, from
        /// the edge's middle.
        let road: Int?
        /// The quest that opens the road, from either side (maps.json gives it on the side you
        /// come from first; the border's the same gate both ways).
        let quest: String?

        /// Whether you can walk across where the border is `along` (a cell along it, as `span`
        /// counts): anywhere along a road's border; through its gate, only once its quest is done,
        /// where a quest opens the road; nowhere where no road crosses.
        func isOpen(at along: Int, done: (String) -> Bool) -> Bool {
            guard exit != nil, span.contains(along) else { return false }
            guard let quest else { return true }
            guard let road else { return false }
            return abs(along - road) <= Continent.gateReach && done(quest)
        }

        /// Whether the whole border is walled off (only a gate, if that, in it): no road, or a quest's.
        var isWalled: Bool { exit == nil || quest != nil }

        /// A cell of `here`, in this land's own cells.
        func local(_ cell: GridPoint) -> GridPoint {
            GridPoint(col: cell.col - offset.col, row: cell.row - offset.row)
        }

        /// How many cells `cell` (of `here`) is from this border: from the edge, and from the end
        /// of the stretch they share where it's past it.
        func distance(from cell: GridPoint, columns: Int, rows: Int) -> Int {
            let (inward, along) = Continent.place(of: cell, from: edge, columns: columns, rows: rows)
            let outside = along < span.lowerBound ? span.lowerBound - along : along > span.upperBound ? along - span.upperBound : 0
            return max(0, inward) + outside
        }
    }

    /// How many cells either side of a quest's road its gate is open, once the quest is done.
    static let gateReach = 2

    /// A cell's place from one of a land's edges: how far in from it (0 on its outer row, negative
    /// past it) and where along it (columns on the north and south, rows on the east and west).
    static func place(of cell: GridPoint, from edge: Edge, columns: Int, rows: Int) -> (inward: Int, along: Int) {
        switch edge {
        case .north: (rows - 1 - cell.row, cell.col)
        case .south: (cell.row, cell.col)
        case .east: (columns - 1 - cell.col, cell.row)
        case .west: (cell.col, cell.row)
        }
    }

    /// The lands on the continent and where each lies, in world cells.
    private static var lands: [(def: MapDef, origin: GridPoint)] {
        let content = Content.shared
        return content.maps.compactMap { def in content.world[def.id].map { (def, $0) } }
    }

    /// Where `def`'s south-west cell lies on the continent, or nil off it (a cave).
    static func origin(of def: MapDef) -> GridPoint? { Content.shared.world[def.id] }

    /// The lands sharing a stretch of border with `here` (none for a cave), each with the road
    /// across, if one crosses.
    static func neighbours(of here: MapDef) -> [Neighbour] {
        guard let origin = origin(of: here) else { return [] }
        var found: [Neighbour] = []
        for (def, there) in lands where def.id != here.id {
            let dx = there.col - origin.col, dy = there.row - origin.row
            // The columns and rows of `here` the other land spans (empty where it's beside it).
            let columns = (low: max(0, dx), high: min(here.width, dx + def.width) - 1)
            let rows = (low: max(0, dy), high: min(here.height, dy + def.height) - 1)
            let edge: Edge
            if dx == here.width, rows.low <= rows.high {
                edge = .east
            } else if dx + def.width == 0, rows.low <= rows.high {
                edge = .west
            } else if dy == here.height, columns.low <= columns.high {
                edge = .north
            } else if dy + def.height == 0, columns.low <= columns.high {
                edge = .south
            } else {
                continue
            }
            let span = edge == .east || edge == .west ? rows.low...rows.high : columns.low...columns.high
            let exit = here.exits.first { $0.to == def.id && $0.edge == edge }
            let back = def.exits.first { $0.to == here.id }
            let length = edge == .east || edge == .west ? here.height : here.width
            let road = exit.map { length / 2 + ($0.meets ?? $0.at ?? 0) }
            found.append(Neighbour(def: def, offset: GridPoint(col: dx, row: dy), edge: edge, span: span, exit: exit, road: road,
                                   quest: exit == nil ? nil : exit?.requires ?? back?.requires))
        }
        return found
    }

    /// Where `here` lies among the lands, for the sea to come in over its coast (`Coast`): the lands
    /// near it and where roads cross between them, in its cells. Nil for a cave.
    static func coast(of here: MapDef) -> Coast? {
        guard let origin = origin(of: here) else { return nil }
        let reach = Coast.margin
        var near: [Coast.Land] = []
        var crossings: [GridPoint] = []
        for (def, there) in lands {
            let low = GridPoint(col: there.col - origin.col, row: there.row - origin.row)
            let high = GridPoint(col: low.col + def.width - 1, row: low.row + def.height - 1)
            guard high.col >= -reach, high.row >= -reach, low.col < here.width + reach, low.row < here.height + reach else { continue }
            near.append(Coast.Land(low: low, high: high, town: def.fence == true))
            for exit in def.exits where Content.shared.world[exit.to] != nil {
                let length = exit.edge == .east || exit.edge == .west ? def.height : def.width
                let along = length / 2 + (exit.meets ?? exit.at ?? 0)
                let cell: GridPoint = switch exit.edge {
                case .east: GridPoint(col: high.col, row: low.row + along)
                case .west: GridPoint(col: low.col, row: low.row + along)
                case .north: GridPoint(col: low.col + along, row: high.row)
                case .south: GridPoint(col: low.col + along, row: low.row)
                }
                crossings.append(cell)
            }
        }
        return Coast(origin: origin, lands: near, crossings: crossings)
    }

    /// Whether a cell of `here` (in its cells, past its edges) lies in any land.
    static func isLand(_ cell: GridPoint, from here: MapDef) -> Bool {
        guard let origin = origin(of: here) else { return false }
        let world = GridPoint(col: cell.col + origin.col, row: cell.row + origin.row)
        return lands.contains { contains(world, $0.def, at: $0.origin) }
    }

    private static func contains(_ world: GridPoint, _ def: MapDef, at origin: GridPoint) -> Bool {
        world.col >= origin.col && world.row >= origin.row && world.col < origin.col + def.width && world.row < origin.row + def.height
    }

    /// The sea round `here`: which cells within `margin` of its edges lie in no land and are
    /// `here`'s to draw (it's the nearest land to them, so two lands never draw the same water
    /// twice), and for each how many cells it is from the nearest land of all, for the haze.
    /// Off the continent (a cave), everything round it is its own: the cave's rock.
    static func sea(round here: MapDef, margin: Int) -> [GridPoint: Double] {
        var sea: [GridPoint: Double] = [:]
        let rows = -margin..<(here.height + margin), columns = -margin..<(here.width + margin)
        guard let origin = origin(of: here) else {
            for row in rows {
                for col in columns where row < 0 || col < 0 || row >= here.height || col >= here.width {
                    let outside = max(0, -row, -col, row - here.height + 1, col - here.width + 1)
                    sea[GridPoint(col: col, row: row)] = Double(outside)
                }
            }
            return sea
        }
        // The lands near enough to matter, in `here`'s cells.
        let near = lands.compactMap { land -> (id: String, low: GridPoint, high: GridPoint)? in
            let low = GridPoint(col: land.origin.col - origin.col, row: land.origin.row - origin.row)
            let high = GridPoint(col: low.col + land.def.width - 1, row: low.row + land.def.height - 1)
            let reach = margin * 3
            guard high.col >= -reach, high.row >= -reach, low.col < here.width + reach, low.row < here.height + reach else { return nil }
            return (land.def.id, low, high)
        }
        func gap(_ cell: GridPoint, _ low: GridPoint, _ high: GridPoint) -> Double {
            let dx = Double(max(0, low.col - cell.col, cell.col - high.col))
            let dy = Double(max(0, low.row - cell.row, cell.row - high.row))
            return (dx * dx + dy * dy).squareRoot()
        }
        for row in rows {
            for col in columns where row < 0 || col < 0 || row >= here.height || col >= here.width {
                let cell = GridPoint(col: col, row: row)
                var nearest = (id: "", distance: Double.infinity)
                var inLand = false
                for land in near {
                    let distance = gap(cell, land.low, land.high)
                    if distance == 0 { inLand = true; break }
                    // Ties go to the first in id order, the same for both lands.
                    if distance < nearest.distance || (distance == nearest.distance && land.id < nearest.id) {
                        nearest = (land.id, distance)
                    }
                }
                guard !inLand, nearest.id == here.id else { continue }
                // How far from any land: the mist thickens out there.
                sea[cell] = near.reduce(Double.infinity) { min($0, gap(cell, $1.low, $1.high)) }
            }
        }
        return sea
    }
}
