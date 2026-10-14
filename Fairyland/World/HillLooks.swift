import SpriteKit

/// How a land's hills and its shore look (`HillArt.Look`): drawn the same in the land's own scene
/// (`WorldScene`) and on the continent (`ContinentScene`).
struct HillLooks {
    /// How lit a cave's range is turned from the sun (`HillArt.Look.ambient`): deeper shade than
    /// other hills, so a mountain's shape shows.
    static let cragShade = 0.25

    /// Plain hills.
    let plain: HillArt.Look
    /// A range where a road leads into a cave: a mountain of layered rock, its foot grassy, in deeper
    /// shade and brighter sun; out past the map's edge the ground is rock too.
    let crag: HillArt.Look
    /// A range with a mountain in it: bare layered rock from partway up (`look(for:)` sets how far),
    /// its foothills' tops below that, in deeper shade and brighter sun, so its height shows.
    let mountain: HillArt.Look

    /// `ground`: each cell's own tile picture, as the land's ground shows it; nil where it has none
    /// (past the map's edge, or the sea), where the land out there is drawn instead. `variation`: the
    /// soft colour patches over the land's whole ground (`Lighting.groundVariation`). Tiles are graded
    /// with whichever palette `art` is using, so the land's own.
    init(map: WorldMap, art: ArtLibrary, ground: @escaping (GridPoint) -> CGImage?, variation: CGImage?) {
        let theme = map.def.theme
        var images: [String: CGImage] = [:]
        func picture(_ key: String, _ texture: () -> SKTexture?) -> CGImage? {
            if let known = images[key] { return known }
            let made = texture().map { art.picture(of: $0) }
            images[key] = made
            return made
        }
        func tiles(_ id: String) -> (GridPoint) -> CGImage? {
            { cell in picture("\(id)#\(WorldScene.variant(of: cell))") { art.tileVariant(id, WorldScene.variant(of: cell)) } }
        }
        let palette = theme.palette
        // Rock shows on the slopes of all but the gentlest hills: the map's own bank, or scree.
        let rock: String? = theme.hills?.bank ?? (map.rockiness >= 0.2 ? "tile_scree" : nil)
        // Past the map's edge (a range where a road leads into a cave), the land out there.
        let beyond = tiles(theme.border ?? theme.ground)
        let look = HillArt.Look(
            ground: { cell in
                guard map.contains(cell), let own = ground(cell) else { return beyond(cell) }
                return own
            },
            trail: tiles(theme.path),
            bank: rock.map(tiles),
            rocky: map.rockiness,
            variation: variation,
            mapSize: (map.columns, map.rows),
            shadow: Lighting.rgb(palette?.shadow) ?? (r: 0.2, g: 0.22, b: 0.3),
            highlight: Lighting.rgb(palette?.highlight) ?? (r: 1, g: 0.95, b: 0.8))
        plain = look
        let scree = tiles(theme.hills?.bank ?? "tile_scree")
        var crag = look
        crag.ground = { cell in map.contains(cell) ? look.ground(cell) : scree(cell) }
        crag.bank = scree
        crag.rocky = 1
        crag.rockAbove = 0.2
        crag.ambient = HillLooks.cragShade
        crag.brightest = 1.3
        crag.strata = 14
        // Its road stays a road all the way up to the cave's mouth.
        crag.road = { cell in map.contains(cell) && map.ground[cell.row][cell.col] == .path }
        // Out past the ends of its edge, it stops where a land next door lies.
        var elsewhere: [GridPoint: Bool] = [:]
        crag.hidden = { cell in
            guard !map.owns(cell) else { return false }
            if let known = elsewhere[cell] { return known }
            let land = Continent.isLand(cell, from: map.def)
            elsewhere[cell] = land
            return land
        }
        self.crag = crag
        var mountain = look
        mountain.bank = look.bank ?? scree
        mountain.ambient = HillLooks.cragShade
        mountain.brightest = 1.2
        mountain.strata = 14
        self.mountain = mountain
    }

    /// How a range of the land's looks.
    func look(for hill: WorldMap.Hill) -> HillArt.Look {
        if hill.isCrag { return crag }
        guard hill.hasMountain else { return plain }
        var style = mountain
        style.rockFrom = Double(hill.peak) * 0.4
        return style
    }

    /// How the land's shore looks (`WorldMap.shore`): the same ground again, sunk and lit by how it
    /// slopes, and nothing past the land's own cells. `overlays`: the decks of the bridges out over
    /// a sunk lake (`BridgeArt.deckPicture`).
    static func shore(of map: WorldMap, ground: @escaping (GridPoint) -> CGImage?, variation: CGImage?,
                      overlays: [(image: CGImage, frame: CGRect)]) -> HillArt.Look {
        let palette = map.def.theme.palette
        return HillArt.Look(
            ground: { cell in map.owns(cell) ? ground(cell) : nil },
            trail: { _ in nil },
            bank: nil,
            rocky: 0,
            variation: variation,
            mapSize: (map.columns, map.rows),
            shadow: Lighting.rgb(palette?.shadow) ?? (r: 0.2, g: 0.22, b: 0.3),
            highlight: Lighting.rgb(palette?.highlight) ?? (r: 1, g: 0.95, b: 0.8),
            overlays: overlays)
    }
}
