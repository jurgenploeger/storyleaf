import SpriteKit

/// Which tile each of a land's cells shows (`WorldScene.makeGround`, and the continent's chunks):
/// its ground, with soft roads, accent patches, ponds and shorelines drawn over it from the cells
/// round it (`ArtLibrary.organicTile`), and across the band where it gives way to the land next
/// door (`Seam`), that land's ground in patches. Each cell's pick depends only on the cells within
/// two of it, so any piece of the land can be tiled on its own.
final class GroundTiles {
    private let map: WorldMap
    private let art: ArtLibrary
    private let theme: MapDef.Theme
    private let tileSize = CGSize(width: WorldMap.tileSize, height: WorldMap.tileSize)
    private let waterID: String
    /// The water's tile (animated, for placeholder water).
    let water: SKTileGroup
    /// Every tile picked so far, by what's drawn on it.
    private var groups: [String: SKTileGroup]
    /// Each tile's picture, for drawing hills (`HillArt`).
    private(set) var pictures: [ObjectIdentifier: SKTexture]
    /// Accent patches (flower meadows, moss) blend in as soft blobs. Not in towns, where the accent
    /// is terrace paving and stays square.
    private let patchAccent: Bool
    /// Plain tiles come in four versions that fit together in any order, so big areas don't repeat.
    /// Animated placeholder water keeps its single animated tile.
    private let waterVaries: Bool
    /// The sea (on the continent), round the land and in over its box past its coast (`Region`).
    /// It lies lower than the land (`WorldMap.seaDrop`; `WorldScene.placeSea` draws it), so its cells
    /// have no ground, and the land's edge along it is cut clear, curving as a lake's shore does.
    private var sea: Set<GridPoint> = []
    /// The lands next door whose ground comes over the line in patches, by seam (`WorldMap.seams`),
    /// graded as it is there.
    private let others: [(land: MapDef, from: ArtLibrary.Foreign)?]
    private var lookPast: [GridPoint: Int?] = [:]
    private static let full = 0b111_111_111, sides = 0b010_101_010

    /// The tiles picked so far, for a tile set.
    var allGroups: [SKTileGroup] { Array(groups.values) }

    init(map: WorldMap, art: ArtLibrary) {
        self.map = map
        self.art = art
        theme = map.def.theme
        waterID = theme.water ?? "tile_water"
        let frames = art.waterFrames(waterID)
        water = SKTileGroup(tileDefinition: SKTileDefinition(textures: frames, size: CGSize(width: WorldMap.tileSize, height: WorldMap.tileSize),
                                                             timePerFrame: 0.9))
        groups = ["water": water]
        pictures = [ObjectIdentifier(water): frames.first ?? SKTexture()]
        patchAccent = (theme.accentPatches ?? 0) > 0 && theme.accent != nil && theme.accent != theme.ground
        waterVaries = frames.count == 1
        others = map.seams.map { seam in
            Content.shared.map(seam.neighbour).map { (land: $0, from: ArtLibrary.Foreign(land: $0.id, palette: $0.theme.palette)) }
        }
        if map.region != nil {
            for row in -2..<(map.rows + 2) {
                for col in -2..<(map.columns + 2) {
                    let cell = GridPoint(col: col, row: row)
                    let open = map.contains(cell) ? map.ground[row][col] == .sea : map.isOpenSea(cell)
                    if open { sea.insert(cell) }
                }
            }
        }
    }

    private func group(_ key: String, _ texture: () -> SKTexture) -> SKTileGroup {
        if let known = groups[key] { return known }
        let picture = texture()
        let made = SKTileGroup(tileDefinition: SKTileDefinition(texture: picture, size: tileSize))
        groups[key] = made
        pictures[ObjectIdentifier(made)] = picture
        return made
    }

    private func plain(_ id: String, _ variant: Int) -> SKTileGroup {
        group("\(id)#\(variant)") { art.tileVariant(id, variant) }
    }

    /// Whether the ground past the land's edge at `cell` is water: where a river runs on into the
    /// land next door (`Region`).
    private func waterBeyond(_ cell: GridPoint) -> Bool {
        map.region?.isRiver(cell) ?? false
    }

    /// Which cells of the 3×3 around `cell` are `kind` (bit row * 3 + col, row 0 north).
    private func mask(_ cell: GridPoint, _ kind: Ground) -> Int {
        let own = map.ground[cell.row][cell.col] == kind
        var bits = 0
        for dy in -1...1 {
            for dx in -1...1 {
                let next = GridPoint(col: cell.col + dx, row: cell.row + dy)
                // Off the land (past its box, or a land next door's) a road or patch carries on;
                // water only where a river runs off it.
                let hit = map.contains(next) && map.ground[next.row][next.col] != .away ? map.ground[next.row][next.col] == kind
                    : kind == .water ? waterBeyond(next) : own
                if hit { bits |= 1 << ((1 - dy) * 3 + dx + 1) }
            }
        }
        return bits
    }

    /// The water cells of the 5×5 around `cell` (bit row * 5 + col, row 0 north), for shorelines.
    private func poolMask(_ cell: GridPoint) -> Int {
        var bits = 0
        for dy in -2...2 {
            for dx in -2...2 {
                let next = GridPoint(col: cell.col + dx, row: cell.row + dy)
                let water = map.contains(next) && map.ground[next.row][next.col] != .away ? map.ground[next.row][next.col] == .water : waterBeyond(next)
                if water { bits |= 1 << ((2 - dy) * 5 + dx + 2) }
            }
        }
        return bits
    }

    /// The sea's cells of the 3×3 around `cell` (as `mask`), and of the 5×5 (as `poolMask`).
    private func shore(_ cell: GridPoint) -> Int {
        var bits = 0
        for dy in -1...1 {
            for dx in -1...1 where sea.contains(GridPoint(col: cell.col + dx, row: cell.row + dy)) { bits |= 1 << ((1 - dy) * 3 + dx + 1) }
        }
        return bits
    }

    private func seaPool(_ cell: GridPoint) -> Int {
        var bits = 0
        for dy in -2...2 {
            for dx in -2...2 where sea.contains(GridPoint(col: cell.col + dx, row: cell.row + dy)) { bits |= 1 << ((2 - dy) * 5 + dx + 2) }
        }
        return bits
    }

    /// Which land's ground shows at a cell, as the index of its seam: on this land as laid out, just
    /// over the border as the band runs on into the land next door.
    private func otherLook(_ cell: GridPoint) -> Int? {
        if map.owns(cell) { return map.foreign[cell] }
        if let known = lookPast[cell] { return known }
        let found = map.seams.indices.first { map.seams[$0].covers(cell) && map.seams[$0].showsOther(cell) }
        lookPast[cell] = found
        return found
    }

    /// How a road cell takes on the road of the land next door across the band between them: its
    /// road tile, graded as it is there, mixed in by that land's share of the ground at the cell
    /// (`Seam.share`, half on the border), in eighths. The ground there comes in patches; a road
    /// changing in patches looked torn, and changing at the border it was cut straight across
    /// (playtesting 2026-10-15). Nil where no band reaches.
    private func roadFade(_ cell: GridPoint) -> ArtLibrary.Fade? {
        var best: (seam: Int, share: Double)?
        for index in map.seams.indices {
            guard let share = map.seams[index].share(cell), share > (best?.share ?? 0) else { continue }
            best = (index, share)
        }
        guard let best, let other = others[best.seam] else { return nil }
        let eighths = (best.share * 8).rounded()
        guard eighths > 0 else { return nil }
        return ArtLibrary.Fade(tile: other.land.theme.path, from: other.from, share: eighths / 8)
    }

    /// The land next door whose patches reach `cell` (its own, or one round it), and which cells of
    /// the 3×3 round it show that land (bit row * 3 + col, row 0 north).
    private func patches(_ cell: GridPoint) -> (seam: Int, mask: Int)? {
        var looks: [Int?] = []
        for dy in -1...1 {
            for dx in -1...1 { looks.append(otherLook(GridPoint(col: cell.col + dx, row: cell.row - dy))) }
        }
        guard let seam = looks[4] ?? looks.compactMap({ $0 }).first else { return nil }
        var bits = 0
        for (bit, look) in looks.enumerated() where look == seam { bits |= 1 << bit }
        return (seam, bits)
    }

    /// The tile a cell of the land's box shows (none on the sea, or on a land next door's cell), and
    /// whether it's within two of the sea (its bank, `WorldScene.bank`).
    func pick(_ cell: GridPoint) -> (group: SKTileGroup?, nearSea: Bool) {
        let (col, row) = (cell.col, cell.row)
        let kind = map.ground[row][col]
        guard kind != .sea, kind != .away else { return (nil, false) }
        let full = Self.full
        let road = mask(cell, .path), pond = mask(cell, .water)
        let variant = WorldScene.variant(of: cell)
        let patch = patchAccent ? mask(cell, .accent) : 0
        // What shows between the soft shapes: the cell's own ground, or for a road, pond or patch
        // cell the ground around it.
        let base: String = switch kind {
        case .ground: theme.ground
        case .border: theme.border ?? theme.ground
        case .accent where !patchAccent: theme.accent ?? theme.ground
        default: mask(cell, .border) & Self.sides != 0 ? (theme.border ?? theme.ground) : theme.ground
        }
        var layers: [ArtLibrary.GroundLayer] = []
        // The land next door's patches first, under everything of this land's.
        let other = map.seams.isEmpty ? nil : patches(cell)
        let otherLand = other.flatMap { others[$0.seam] }
        if let other, let otherLand {
            layers.append(.init(tile: otherLand.land.theme.ground, mask: other.mask, style: .patch, from: otherLand.from))
        }
        if patch != 0, let accent = theme.accent { layers.append(.init(tile: accent, mask: patch, style: .patch)) }
        let fade = road == 0 || map.seams.isEmpty ? nil : roadFade(cell)
        if road != 0 { layers.append(.init(tile: theme.path, mask: road, style: .road, fade: fade)) }
        if pond != 0 { layers.append(.init(tile: waterID, mask: poolMask(cell), style: .water)) }
        let near = sea.isEmpty ? 0 : seaPool(cell)
        let coast = near == 0 ? 0 : shore(cell)
        if coast != 0 { layers.append(.init(tile: base, mask: near, style: .cut)) }
        let chosen: SKTileGroup
        if pond == full, coast == 0 {
            chosen = waterVaries ? plain(waterID, variant) : water
        } else if road == full, pond == 0, coast == 0 {
            if let fade {
                chosen = group("faded|\(theme.path)|\(fade.key)#\(variant)") { art.fadedTile(theme.path, fade: fade, variant: variant) }
            } else {
                chosen = plain(theme.path, variant)
            }
        } else if let other, let otherLand, other.mask == full, layers.count == 1 {
            // All the land next door's ground.
            let land = otherLand.land
            chosen = group("foreign|\(land.id)#\(variant)") {
                art.foreignTile(land.theme.ground, palette: land.theme.palette, from: land.id, variant: variant, base: base)
            }
        } else if layers.isEmpty {
            chosen = plain(base, variant)
        } else if let accent = theme.accent, patch == full, road == 0, pond == 0, coast == 0 {
            chosen = plain(accent, variant)
        } else {
            // Shorelines depend on where they are (see organicTile), so each gets its own tile.
            let place = pond != 0 || coast != 0 ? "@\(col),\(row)" : ""
            let key = base + "|" + layers.map { "\($0.style)\($0.mask)\($0.from?.land ?? "")\($0.fade?.key ?? "")" }.joined(separator: "|") + place
            chosen = group(key) { art.organicTile(base: base, layers: layers, cell: cell, variant: variant) }
        }
        return (chosen, near != 0)
    }
}
