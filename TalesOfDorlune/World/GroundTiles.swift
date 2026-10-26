import SpriteKit

/// Which tile each of a land's cells shows (`WorldScene.makeGround`, and the continent's chunks):
/// its ground, with soft roads, accent patches, ponds and shorelines drawn over it from the cells
/// round it (`ArtLibrary.organicTile`), and across the band where it gives way to the land next
/// door (`Seam`), that land's ground in patches. Each cell's pick depends only on the cells within
/// two of it, so any piece of the land can be tiled on its own; and across the band, only on what
/// they show, whichever land holds them (`Blend`), so a tile meets the one past the border as it
/// would one of its own.
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
    /// The lands next door whose ground comes over the line in patches, by id, graded as it is there.
    private var others: [String: (land: MapDef, from: ArtLibrary.Foreign)?] = [:]
    private var lookPast: [GridPoint: String?] = [:]
    private static let full = 0b111_111_111, sides = 0b010_101_010
    /// Every cell of `poolMask`'s 5×5.
    private static let wholePool = (1 << 25) - 1

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
                // Off the land (past its box, or a land next door's) a patch carries on; water only
                // where a river runs off it; a road on a land next door only where its own runs on
                // from this one's (`WorldMap.roadsPast`), as that land lays it out, so the two meet.
                let hit: Bool
                if map.contains(next), map.ground[next.row][next.col] != .away {
                    hit = map.ground[next.row][next.col] == kind
                } else if kind == .water {
                    hit = waterBeyond(next)
                } else if kind == .path, map.region != nil, !map.isOpenSea(next) {
                    hit = map.roadsPast.contains(next)
                } else {
                    hit = own
                }
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

    /// A land next door, for its ground graded as it is there.
    private func foreignLand(_ id: String) -> (land: MapDef, from: ArtLibrary.Foreign)? {
        if let known = others[id] { return known }
        let found = Content.shared.map(id).map { (land: $0, from: ArtLibrary.Foreign(land: $0.id, palette: $0.theme.palette)) }
        others[id] = found
        return found
    }

    /// Which land's ground shows at a cell, by id: on this land as laid out (`WorldMap.foreign`),
    /// past its border as the land there lays it out (`Blend.shows`), a land next door's own or a
    /// third land's come over onto it. Nil on the sea, or past where the band could reach.
    private func look(_ cell: GridPoint) -> String? {
        if map.owns(cell) { return map.foreign[cell].map { map.seams[$0].neighbour } ?? map.def.id }
        if let known = lookPast[cell] { return known }
        let found = map.blend.flatMap { blend in blend.shows(cell).map { blend.around.lands[$0] } }
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
        guard let best, let other = foreignLand(map.seams[best.seam].neighbour) else { return nil }
        let eighths = (best.share * 8).rounded()
        guard eighths > 0 else { return nil }
        return ArtLibrary.Fade(tile: other.land.theme.path, from: other.from, share: eighths / 8)
    }

    /// The grounds the 3×3 round `cell` shows across the band (`look`), this land's and the lands
    /// next door's, a layer each (`base` this land's) with the cells showing it (bit row * 3 + col,
    /// row 0 north), by land id: `ArtLibrary.organicTile` lays them in that order, the same whichever
    /// land draws the tile. Nil where they're all this land's. One land's alone left out the others'
    /// where three met, and patches stopped dead there (playtesting 2026-10-16).
    private func grounds(_ cell: GridPoint, base: String) -> [ArtLibrary.GroundLayer]? {
        var masks: [String: Int] = [:]
        var bit = 0
        for dy in -1...1 {
            for dx in -1...1 {
                if let land = look(GridPoint(col: cell.col + dx, row: cell.row - dy)) { masks[land, default: 0] |= 1 << bit }
                bit += 1
            }
        }
        guard masks.keys.contains(where: { $0 != map.def.id }) else { return nil }
        return masks.keys.sorted().compactMap { land -> ArtLibrary.GroundLayer? in
            let mask = masks[land] ?? 0
            if land == map.def.id { return ArtLibrary.GroundLayer(tile: base, mask: mask, style: .ground) }
            guard let other = foreignLand(land) else { return nil }
            return ArtLibrary.GroundLayer(tile: other.land.theme.ground, mask: mask, style: .ground, from: other.from)
        }
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
        // The grounds across the band first, under everything of this land's.
        let band = map.seams.isEmpty ? nil : grounds(cell, base: base)
        if let band { layers += band }
        if patch != 0, let accent = theme.accent { layers.append(.init(tile: accent, mask: patch, style: .patch)) }
        let fade = road == 0 || map.seams.isEmpty ? nil : roadFade(cell)
        if road != 0 { layers.append(.init(tile: theme.path, mask: road, style: .road, fade: fade)) }
        if pond != 0 { layers.append(.init(tile: waterID, mask: poolMask(cell), style: .water)) }
        let near = sea.isEmpty ? 0 : seaPool(cell)
        let coast = near == 0 ? 0 : shore(cell)
        if coast != 0 { layers.append(.init(tile: base, mask: near, style: .cut)) }
        let chosen: SKTileGroup
        // A land's own water deepens out from its shores (`ArtLibrary.organicTile`): two cells out it's
        // the deep tile, nearer it's drawn as a shore is, shaded by how far in it lies.
        let natural = waterID == "tile_water" && waterVaries
        if pond == full, coast == 0, natural, poolMask(cell) == Self.wholePool {
            chosen = group("deep|\(waterID)#\(variant)") { art.deepWaterTile(waterID, variant) }
        } else if pond == full, coast == 0, !natural {
            chosen = waterVaries ? plain(waterID, variant) : water
        } else if road == full, pond == 0, coast == 0 {
            if let fade {
                chosen = group("faded|\(theme.path)|\(fade.key)#\(variant)") { art.fadedTile(theme.path, fade: fade, variant: variant) }
            } else {
                chosen = plain(theme.path, variant)
            }
        } else if let band, band.count == 1, let only = band.first, only.mask == full, layers.count == 1, let from = only.from {
            // All the land next door's ground.
            chosen = group("foreign|\(from.land)#\(variant)") {
                art.foreignTile(only.tile, palette: from.palette, from: from.land, variant: variant, base: base)
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
