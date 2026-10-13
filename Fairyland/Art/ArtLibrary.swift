import SpriteKit
import UIKit

nonisolated struct ArtManifest: Decodable {
    let assets: [ArtAsset]
}

/// One entry of art/assets.json. The `request` block is only used by tools/rd.py.
nonisolated struct ArtAsset: Decodable {
    let id: String
    /// walk_sheet | npc | monster | tile | prop | building
    let kind: String
    /// Frame size in pixels for walk sheets.
    let frame: Int?
    /// Which direction each sheet row faces, top to bottom.
    let directions: [String]?
    /// Optional draw-size multiplier. Stick to whole numbers to keep pixels square.
    let scale: Double?
    /// A free palette-swapped copy of another sprite (used until this one gets its own PNG).
    let derive: Derivation?
    /// Which way a single picture looks, "left" (when not given) or "right": it has no side views,
    /// so walking the other way it's mirrored (`WalkCycle.mirrors`). A copy looks the way its base does.
    let faces: String?
}

/// One paper-doll layer (an art/sprites PNG) and how it's recoloured before stacking: by its own
/// rules, or with nil by the sprite's (`ArtLibrary.register`'s `recolor`).
nonisolated struct ArtLayer: Sendable {
    let id: String
    var recolor: [RecolorRule]? = nil
}

/// A texture plus the size it should be drawn at.
struct SpriteArt {
    let texture: SKTexture
    let size: CGSize
}

/// A directional walk cycle. The first frame of each direction doubles as the idle pose.
struct WalkCycle {
    let frames: [Direction: [SKTexture]]
    let size: CGSize
    /// A single picture that looks right (`ArtAsset.faces`); most look left or straight at you.
    var facesRight = false

    func frames(_ direction: Direction) -> [SKTexture] {
        frames[direction] ?? frames[.down] ?? []
    }

    /// The same picture whichever way it goes (a single image, or a sheet with no side views): it's
    /// mirrored to walk the other way.
    var mirrors: Bool {
        frames(.left).first === frames(.right).first
    }
}

/// Loads Retro Diffusion sprites from the bundled `art/` folder, falling back to
/// placeholder pixel art for anything that hasn't been generated yet.
final class ArtLibrary {
    static let shared = ArtLibrary()

    private let manifest: ArtManifest
    private var textures: [String: SKTexture] = [:]
    private var cycles: [String: WalkCycle] = [:]
    private var images: [String: UIImage] = [:]
    /// Sprites made at runtime (the customised hero, recoloured companions), keyed by id.
    private var runtime: [String: (asset: ArtAsset, key: String)] = [:]
    /// Gear drawn onto runtime sprites after their recolour (the hero's armour and boots).
    private var gearLooks: [String: GearLook] = [:]
    /// Paper-doll layers stacked in place of a runtime sprite's base (body, locks, then hair or headgear).
    private var layerSets: [String: [ArtLayer]] = [:]

    init() {
        do {
            guard let url = Bundle.main.url(forResource: "assets", withExtension: "json", subdirectory: "art") else {
                throw CocoaError(.fileNoSuchFile)
            }
            manifest = try JSONDecoder().decode(ArtManifest.self, from: Data(contentsOf: url))
        } catch {
            print("⚠️ Couldn't read art/assets.json: \(error)")
            manifest = ArtManifest(assets: [])
        }
    }

    /// The current map's colour grade, and which map it belongs to.
    private var palette: MapPalette?
    private var paletteMap: String?
    /// Sprite kinds that take on a map's palette.
    private static let gradedKinds: Set<String> = ["tile", "prop", "building"]

    /// Ground, scenery and buildings graded for the map the library grades for now (`use`).
    private var gradedTextures: [String: SKTexture] = [:]
    /// Another map's graded art, kept while it may be wanted again: a land next door, on screen
    /// past the border or being built while you walk toward it, takes turns with the one you're in.
    private struct Graded {
        let palette: MapPalette?
        let textures: [String: SKTexture]
        let blended: [String: SKTexture]
        let tileImages: [String: CGImage]
        let variants: [String: [UInt8]]
    }
    private var stashed: [String: Graded] = [:]
    /// The stashed maps, the longest unused first. A few at most: the land you're in, those beside
    /// it and the one you came from.
    private var stashOrder: [String] = []
    private static let stashLimit = 4

    /// The palette and map the library grades for now, to go back to (`use`).
    var grading: (palette: MapPalette?, map: String?) { (palette, paletteMap) }

    /// Grades ground, scenery and buildings with `map`'s palette from now on. Sprites already
    /// on screen keep their textures. The art graded for the map before is put aside, and taken
    /// up again if it comes back soon, so lands can take turns cheaply.
    func use(palette: MapPalette?, for map: String) {
        guard map != paletteMap else { return }
        if let current = paletteMap {
            stashed[current] = Graded(palette: self.palette, textures: gradedTextures, blended: blended, tileImages: tileImages, variants: variantCache)
            stashOrder.removeAll { $0 == current }
            stashOrder.append(current)
        }
        let kept = stashed.removeValue(forKey: map)
        stashOrder.removeAll { $0 == map }
        while stashOrder.count > Self.stashLimit { stashed[stashOrder.removeFirst()] = nil }
        paletteMap = map
        self.palette = palette
        gradedTextures = kept?.textures ?? [:]
        blended = kept?.blended ?? [:]
        tileImages = kept?.tileImages ?? [:]
        variantCache = kept?.variants ?? [:]
    }

    /// Lets go of a map's graded art: nothing of it is on screen any more.
    func release(map: String) {
        guard map != paletteMap else { return }
        stashed[map] = nil
        stashOrder.removeAll { $0 == map }
    }

    /// A tile's image graded with `palette`, whatever map the library is grading for right now: the
    /// HUD draws a new map's minimap as soon as the scene exists, before its `build` takes the
    /// library over from the map you came from.
    func gradedTile(_ id: String, palette: MapPalette?) -> CGImage? {
        guard let image = sourceImage(id) else { return nil }
        guard let palette else { return image }
        return Recolor.grade(palette, image: image) ?? image
    }

    /// The sprite's image with the current map's palette, for ground, scenery and buildings.
    private func gradedImage(_ id: String) -> CGImage? {
        guard let image = sourceImage(id) else { return nil }
        guard let palette, Self.gradedKinds.contains(kind(of: id)) else { return image }
        return Recolor.grade(palette, image: image) ?? image
    }

    /// Registers (or updates) a recoloured copy of `base` under `id`, e.g. the customised hero.
    /// `key` identifies the look, so re-registering the same look is free.
    /// `layers` (art/sprites PNGs, bottom first) replace the base's own picture when they all exist;
    /// the base still supplies the frame size and directions.
    func register(_ id: String, from base: String, recolor rules: [RecolorRule], key: String, gear: GearLook? = nil,
                  layers: [ArtLayer]? = nil) {
        guard runtime[id]?.key != key else { return }
        let kind = asset(base)?.kind ?? "monster"
        runtime[id] = (ArtAsset(id: id, kind: kind, frame: nil, directions: nil, scale: nil, derive: Derivation(from: base, recolor: rules), faces: nil), key)
        gearLooks[id] = gear
        layerSets[id] = layers
        textures[id] = nil
        gradedTextures[id] = nil
        cycles[id] = nil
        images = images.filter { $0.key != id && !$0.key.hasPrefix(id + "#") }
    }

    /// The sprite's own art as an image, or nil when it has none yet (no placeholder).
    func artImage(_ id: String) -> UIImage? {
        let cacheKey = "art:" + id
        if let cached = images[cacheKey] { return cached }
        guard let cgImage = sourceImage(id) else { return nil }
        let image = UIImage(cgImage: cgImage)
        images[cacheKey] = image
        return image
    }

    /// A one-off recoloured portrait for pickers and previews (cached by `key`).
    func preview(from base: String, recolor rules: [RecolorRule], key: String, facing direction: Direction = .down,
                 layers: [ArtLayer]? = nil) -> UIImage {
        let id = "preview:" + base + ":" + key + ":" + (layers ?? []).map(\.id).joined(separator: "+")
        register(id, from: base, recolor: rules, key: key, layers: layers)
        return image(id, facing: direction)
    }

    func asset(_ id: String) -> ArtAsset? {
        guard let own = manifest.assets.first(where: { $0.id == id }) ?? runtime[id]?.asset else { return nil }
        // The base can itself be derived (hero → human_female_walk → player_walk): resolve it fully, or
        // the frame size and direction order are lost and the wrong row shows (her back for "down").
        guard let derive = own.derive, derive.from != id, let base = asset(derive.from) else { return own }
        return ArtAsset(id: own.id, kind: own.kind, frame: own.frame ?? base.frame, directions: own.directions ?? base.directions,
                        scale: own.scale ?? base.scale, derive: derive, faces: own.faces ?? base.faces)
    }

    private func kind(of id: String) -> String {
        asset(id)?.kind ?? "monster"
    }

    private func pngURL(_ id: String) -> URL? {
        Bundle.main.url(forResource: id, withExtension: "png", subdirectory: "art/sprites")
    }

    /// The generated PNG for `id` (art/sprites/<id>.png), or nil if it doesn't exist yet.
    func generatedTexture(_ id: String) -> SKTexture? {
        if let cached = gradedTextures[id] ?? textures[id] { return cached }
        guard let image = gradedImage(id) else { return nil }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .nearest
        if Self.gradedKinds.contains(kind(of: id)) {
            gradedTextures[id] = texture
        } else {
            textures[id] = texture
        }
        return texture
    }

    /// The sprite's own PNG, or — for derived sprites — its base's PNG with the palette swap applied.
    private func sourceImage(_ id: String, depth: Int = 0) -> CGImage? {
        // "raw:<id>": the art as it's drawn, graded for no map (the sea, the same blue round every land).
        if id.hasPrefix("raw:") { return sourceImage(String(id.dropFirst(4)), depth: depth) }
        if let url = pngURL(id), let image = UIImage(contentsOfFile: url.path)?.cgImage { return image }
        guard depth < 3, let derive = asset(id)?.derive else { return nil }
        let base: CGImage
        let recolored: CGImage?
        // Paper-doll layers are recoloured one by one (a layer's own rules, like the hair's, touch
        // only that layer), then stacked.
        if let layers = layerSets[id], let original = stacked(layers), let dressed = stacked(layers, recolor: derive.recolor) {
            base = original
            recolored = dressed
        } else if let sheet = sourceImage(derive.from, depth: depth + 1) {
            base = sheet
            recolored = Recolor.apply(derive.recolor, to: sheet)
        } else {
            return nil
        }
        if let gear = gearLooks[id], let recolored, let from = asset(derive.from) {
            let directions = from.directions ?? ["up", "right", "down", "left"]
            return GearOverlay.apply(gear, original: base, dressed: recolored, frame: from.frame ?? 48, directions: directions)
        }
        return recolored
    }

    /// art/sprites PNGs drawn on top of each other, bottom first; nil unless every one exists.
    /// With `rules`, each layer is recoloured first: by its own rules if it has them, else by these.
    private func stacked(_ layers: [ArtLayer], recolor rules: [RecolorRule]? = nil) -> CGImage? {
        let images = layers.compactMap { layer -> CGImage? in
            guard let image = pngURL(layer.id).flatMap({ UIImage(contentsOfFile: $0.path)?.cgImage }) else { return nil }
            guard let rules else { return image }
            return Recolor.apply(layer.recolor ?? rules, to: image)
        }
        guard let first = images.first, images.count == layers.count else { return nil }
        let width = first.width, height = first.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .none
        for image in images {
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return context.makeImage()
    }

    func tileTexture(_ id: String) -> SKTexture {
        generatedTexture(id) ?? Placeholder.canvas(for: id, kind: "tile").texture()
    }

    /// Graded tile images and their variants' pixels for the current map (cleared by `use(palette:for:)`).
    private var tileImages: [String: CGImage] = [:]
    private var variantCache: [String: [UInt8]] = [:]

    private func tileImage(_ id: String) -> CGImage {
        if let cached = tileImages[id] { return cached }
        let image = gradedImage(id) ?? Placeholder.canvas(for: id, kind: "tile").cgImage()
        tileImages[id] = image
        return image
    }

    private var blended: [String: SKTexture] = [:]

    /// One layer of an organic ground tile (see `organicTile`).
    nonisolated struct GroundLayer: Sendable {
        /// `cut`: the land's edge over the sea, which lies lower: the pixels past the shore left clear.
        nonisolated enum Style: Sendable { case road, patch, water, cut }
        let tile: String
        /// Roads and patches: bit `row * 3 + col` is set where that cell of the 3×3 around this one
        /// holds the layer (row 0 north, col 0 west; bit 4 is the cell itself). Water: the same for
        /// the 5×5 around it (bit `row * 5 + col`, bit 12 is the cell itself).
        let mask: Int
        let style: Style
    }

    /// One of four versions of a tile (0 is the tile itself). The others show the texture shifted
    /// and mirrored inside a soft frame of the original, so they share its edges: any mix of them
    /// tiles seamlessly, and big areas stop repeating the same square.
    func tileVariant(_ id: String, _ index: Int) -> SKTexture {
        let key = "variant|\(id)|\(index % 4)"
        if let cached = blended[key] { return cached }
        let image = tileImage(id)
        let size = max(image.width, 16)
        let texture = Self.makeTexture(variantPixels(id, index, size: size), size: size)
        blended[key] = texture
        return texture
    }

    private func variantPixels(_ id: String, _ index: Int, size: Int) -> [UInt8] {
        let key = "\(id)|\(index % 4)|\(size)"
        if let cached = variantCache[key] { return cached }
        let made = makeVariantPixels(id, index, size: size)
        variantCache[key] = made
        return made
    }

    private func makeVariantPixels(_ id: String, _ index: Int, size: Int) -> [UInt8] {
        Self.variantPixels(of: Self.pixels(tileImage(id), size: size), index, size: size)
    }

    /// Version `index` of a tile from its pixels (`tileVariant`).
    nonisolated private static func variantPixels(of source: [UInt8], _ index: Int, size: Int) -> [UInt8] {
        let shifts: [(dx: Int, dy: Int, mirrorX: Bool, mirrorY: Bool)] = [
            (0, 0, false, false), (size / 2, size / 2, false, false), (size / 4, size * 5 / 8, true, false), (size * 5 / 8, size / 4, false, true),
        ]
        let shift = shifts[index % 4]
        guard index % 4 != 0 else { return source }
        var out = source
        let band = Double(size) / 5
        for y in 0..<size {
            for x in 0..<size {
                var sx = (x + shift.dx) % size, sy = (y + shift.dy) % size
                if shift.mirrorX { sx = size - 1 - sx }
                if shift.mirrorY { sy = size - 1 - sy }
                let edge = Double(min(min(x, y), min(size - 1 - x, size - 1 - y)))
                let t = max(0, min(1, (edge - 1) / band))
                let inside: Double = t * t * (3 - 2 * t)
                let i = (y * size + x) * 4, j = (sy * size + sx) * 4
                for c in 0..<4 {
                    let mixed: Double = Double(source[i + c]) * (1 - inside) + Double(source[j + c]) * inside
                    out[i + c] = UInt8(min(255, mixed))
                }
            }
        }
        return out
    }

    /// The ground of a land next door where it comes over the line onto the land being drawn
    /// (`Seam`): its tile, graded with its palette as it is there, and which side of the line each
    /// point of the cell lies (`Seam.side(across:)`: below 0 past it, in the cell's own coordinates
    /// as `organicTile` has them, -0.5...0.5, x east and y north).
    struct Over {
        let land: String
        let tile: String
        let palette: MapPalette?
        let side: (Double, Double) -> Double
    }

    /// Another land's tiles, graded with its palette, by land, tile, version and size: kept whatever
    /// map the library grades for, a few lands' ground at most.
    private var foreignVariants: [String: [UInt8]] = [:]

    private func foreignPixels(_ id: String, palette: MapPalette?, from land: String, variant: Int, size: Int) -> [UInt8] {
        let key = "\(land)|\(id)|\(variant % 4)|\(size)"
        if let cached = foreignVariants[key] { return cached }
        let image = gradedTile(id, palette: palette) ?? Placeholder.canvas(for: id, kind: "tile").cgImage()
        let made = Self.variantPixels(of: Self.pixels(image, size: size), variant, size: size)
        foreignVariants[key] = made
        return made
    }

    /// Version `variant` of a land next door's tile, graded as it is there (`Over`), for a cell all
    /// past the line, the size of this land's `base` tile.
    func foreignTile(_ id: String, palette: MapPalette?, from land: String, variant: Int, base: String) -> SKTexture {
        let key = "foreign|\(land)|\(id)|\(variant % 4)"
        if let cached = blended[key] { return cached }
        let size = max(tileImage(base).width, 16)
        let texture = Self.makeTexture(foreignPixels(id, palette: palette, from: land, variant: variant, size: size), size: size)
        blended[key] = texture
        return texture
    }

    /// A ground tile with soft, rounded roads, patches and water drawn over `base`. Roads and
    /// patches are rounded strokes joining the cells around this one that hold them, so corners
    /// curve and diagonal steps become smooth bends; their edges wobble in a pattern that repeats
    /// every tile. Water is a smooth field over the 5×5 cells around, so shores curve freely instead
    /// of following cell edges, and wobbles with its place on the map (`cell`). Either way
    /// neighbouring tiles meet seamlessly. Roads get a darker rim, water a foamy edge and a damp bank.
    /// Shoreline tiles are unique anyway, so they also use tile variant `variant`. `over`: a land
    /// next door's ground past the line it meets this one along, under the layers (`Over`; unique too).
    func organicTile(base: String, layers: [GroundLayer], cell: GridPoint, variant: Int, over: Over? = nil) -> SKTexture {
        let hasWater = layers.contains { $0.style == .water || $0.style == .cut }
        let unique = hasWater || over != nil
        let place = unique ? "@\(cell.col),\(cell.row)#\(variant)" + (over.map { "|over:" + $0.land } ?? "") : ""
        let key = "organic|\(base)|" + layers.map { "\($0.tile):\($0.mask):\($0.style)" }.joined(separator: "|") + place
        if let cached = blended[key] { return cached }
        let size = max(tileImage(base).width, 16)
        let pick = unique ? variant : 0
        var out = variantPixels(base, pick, size: size)
        if let over {
            // Past the line the land next door's ground, the pixels either side of it chequered, as
            // pixel art blends two grounds.
            let other = foreignPixels(over.tile, palette: over.palette, from: over.land, variant: pick, size: size)
            let blend = 1.4 / Double(size)
            for py in 0..<size {
                for px in 0..<size {
                    let x = (Double(px) + 0.5) / Double(size) - 0.5, y = 0.5 - (Double(py) + 0.5) / Double(size)
                    let side = over.side(x, y)
                    let past = abs(side) < blend ? (px + py) % 2 == 0 : side < 0
                    guard past else { continue }
                    let index = (py * size + px) * 4
                    for c in 0..<4 { out[index + c] = other[index + c] }
                }
            }
        }
        let rim = 1.2 / Double(size)
        for layer in layers {
            let shore = layer.style == .water || layer.style == .cut
            let texels = layer.style == .cut ? [] : variantPixels(layer.tile, pick, size: size)
            let segments: [(x0: Double, y0: Double, x1: Double, y1: Double)] = shore ? [] : Self.strokes(mask: layer.mask)
            let pools: [(x: Double, y: Double)] = shore ? Self.pools(mask: layer.mask) : []
            let radius: Double = switch layer.style {
            case .road: 0.36
            case .patch: 0.42
            case .water, .cut: 0
            }
            for py in 0..<size {
                for px in 0..<size {
                    // Cell coordinates: this cell spans -0.5...0.5, x east, y north.
                    let x = (Double(px) + 0.5) / Double(size) - 0.5, y = 0.5 - (Double(py) + 0.5) / Double(size)
                    let wobble = Self.wobble(x, y, style: layer.style, cell: cell)
                    let depth: Double
                    if shore {
                        depth = Self.waterDepth(x, y, pools: pools, wobble: wobble)
                    } else {
                        var distance = Double.infinity
                        for segment in segments { distance = min(distance, Self.distance(x, y, to: segment)) }
                        depth = radius + wobble - distance
                    }
                    let index = (py * size + px) * 4
                    switch layer.style {
                    case .road, .patch:
                        guard depth > 0 else { continue }
                        let shade = layer.style == .road && depth < rim ? 0.72 : 1
                        for c in 0..<3 { out[index + c] = UInt8(Double(texels[index + c]) * shade) }
                        out[index + 3] = 255
                    case .water:
                        if depth > 0 {
                            let foam = depth < 0.05 ? 0.35 : 0
                            for c in 0..<3 {
                                let mixed: Double = Double(texels[index + c]) * (1 - foam) + 255 * foam
                                out[index + c] = UInt8(min(255, mixed))
                            }
                            out[index + 3] = 255
                        } else if depth > -0.06 {
                            for c in 0..<3 { out[index + c] = UInt8(Double(out[index + c]) * 0.8) }
                        }
                    case .cut:
                        // Clear past the shore; the lip of the land along it a shade darker.
                        if depth > 0 {
                            for c in 0..<4 { out[index + c] = 0 }
                        } else if depth > -0.05 {
                            for c in 0..<3 { out[index + c] = UInt8(Double(out[index + c]) * 0.82) }
                        }
                    }
                }
            }
        }
        let texture = Self.makeTexture(out, size: size)
        blended[key] = texture
        return texture
    }

    private static func makeTexture(_ bytes: [UInt8], size: Int) -> SKTexture {
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .nearest
        return texture
    }

    /// Centres of the water cells in a 5×5 mask, relative to the middle cell (x east, y north).
    nonisolated private static func pools(mask: Int) -> [(x: Double, y: Double)] {
        var points: [(x: Double, y: Double)] = []
        for bit in 0..<25 where mask & (1 << bit) != 0 {
            points.append((Double(bit % 5 - 2), Double(2 - bit / 5)))
        }
        return points
    }

    /// How far inside the water a point is (in cells, negative on land): each water cell adds a
    /// soft round blob, and the shore is where they add up to a threshold.
    nonisolated private static func waterDepth(_ x: Double, _ y: Double, pools: [(x: Double, y: Double)], wobble: Double) -> Double {
        var field = 0.0
        for pool in pools {
            let dx = x - pool.x, dy = y - pool.y
            field += exp(-(dx * dx + dy * dy) / 0.49)
        }
        return (field + wobble * 1.8 - 0.55) / 1.2
    }

    /// An image's pixels (premultiplied RGBA), scaled to `size` × `size`.
    nonisolated private static func pixels(_ image: CGImage, size: Int) -> [UInt8] {
        PixelImage.pixels(of: image, width: size, height: size) ?? [UInt8](repeating: 0, count: size * size * 4)
    }

    /// The strokes a layer is drawn with: a dot on every cell that holds it, and a line to each
    /// neighbouring cell (diagonals too) that also holds it.
    nonisolated private static func strokes(mask: Int) -> [(x0: Double, y0: Double, x1: Double, y1: Double)] {
        var points: [(x: Double, y: Double)] = []
        for bit in 0..<9 where mask & (1 << bit) != 0 {
            points.append((Double(bit % 3 - 1), Double(1 - bit / 3)))
        }
        var segments: [(x0: Double, y0: Double, x1: Double, y1: Double)] = []
        for i in points.indices {
            segments.append((points[i].x, points[i].y, points[i].x, points[i].y))
            for j in points.indices where j > i && abs(points[i].x - points[j].x) <= 1 && abs(points[i].y - points[j].y) <= 1 {
                segments.append((points[i].x, points[i].y, points[j].x, points[j].y))
            }
        }
        return segments
    }

    /// How far an edge bulges out (+) or in (-) at a point. Roads and patches repeat every tile;
    /// shorelines follow the point's place on the map, so lakes meander.
    nonisolated private static func wobble(_ x: Double, _ y: Double, style: GroundLayer.Style, cell: GridPoint) -> Double {
        let turn: Double = 2 * Double.pi
        if style == .water || style == .cut {
            let gx: Double = Double(cell.col) + x
            let gy: Double = Double(cell.row) + y
            let a: Double = sin(1.7 * gx + 0.9 * gy)
            let b: Double = sin(2.3 * gy - 1.1 * gx + 1.7)
            let c: Double = sin(3.1 * gx + 2.9 * gy + 0.4)
            return 0.08 * a + 0.05 * b + 0.03 * c
        }
        let a: Double = sin(turn * (2 * x + y))
        let b: Double = sin(turn * (3 * y - x) + 1.3)
        return 0.045 * a + 0.03 * b
    }

    nonisolated private static func distance(_ x: Double, _ y: Double, to s: (x0: Double, y0: Double, x1: Double, y1: Double)) -> Double {
        let dx = s.x1 - s.x0, dy = s.y1 - s.y0
        let length = dx * dx + dy * dy
        let t = length == 0 ? 0 : max(0, min(1, ((x - s.x0) * dx + (y - s.y0) * dy) / length))
        let ex = s.x0 + t * dx - x, ey = s.y0 + t * dy - y
        return (ex * ex + ey * ey).squareRoot()
    }

    /// Animation frames for a water tile (a generated tile is a single frame).
    func waterFrames(_ id: String) -> [SKTexture] {
        if let texture = generatedTexture(id) { return [texture] }
        return [Placeholder.water(frame: 0).texture(), Placeholder.water(frame: 1).texture()]
    }

    /// A single image: the whole PNG, or the front-facing frame of a walk sheet.
    func sprite(_ id: String) -> SpriteArt {
        let kind = kind(of: id)
        if kind == "walk_sheet" {
            let cycle = walkCycle(id)
            return SpriteArt(texture: cycle.frames(.down).first ?? SKTexture(), size: cycle.size)
        }
        let scale = CGFloat(asset(id)?.scale ?? 1)
        if let texture = generatedTexture(id) {
            return SpriteArt(texture: texture, size: texture.size() * scale)
        }
        let texture = Placeholder.canvas(for: id, kind: kind).texture()
        return SpriteArt(texture: texture, size: texture.size() * (Placeholder.scale(for: kind) * scale))
    }

    /// Frames per direction. Single images become a one-frame cycle (they hop instead of walking).
    func walkCycle(_ id: String) -> WalkCycle {
        if let cached = cycles[id] { return cached }
        let cycle = makeWalkCycle(id)
        cycles[id] = cycle
        return cycle
    }

    private func makeWalkCycle(_ id: String) -> WalkCycle {
        let asset = asset(id)
        let kind = kind(of: id)
        let scale = CGFloat(asset?.scale ?? 1)

        guard kind == "walk_sheet" else {
            let art = sprite(id)
            return WalkCycle(frames: Dictionary(uniqueKeysWithValues: Direction.allCases.map { ($0, [art.texture]) }), size: art.size,
                             facesRight: asset?.faces == "right")
        }

        guard let sheet = generatedTexture(id) else {
            var frames: [Direction: [SKTexture]] = [:]
            for direction in Direction.allCases {
                frames[direction] = (0..<4).map { Placeholder.canvas(for: id, kind: kind, direction: direction, frame: $0).texture() }
            }
            return WalkCycle(frames: frames, size: CGSize(width: 48, height: 48) * scale)
        }

        let frameSize = CGFloat(asset?.frame ?? 48)
        let pixels = sheet.size()
        let layout = SheetLayout(asset: asset, width: pixels.width, height: pixels.height)
        var frames: [Direction: [SKTexture]] = [:]
        for direction in layout.directions {
            frames[direction] = layout.cells(for: direction).map { cell in
                // SpriteKit texture rects are normalised with the origin at the bottom-left.
                let rect = CGRect(
                    x: CGFloat(cell.column) * frameSize / pixels.width,
                    y: 1 - CGFloat(cell.row + 1) * frameSize / pixels.height,
                    width: frameSize / pixels.width,
                    height: frameSize / pixels.height
                )
                let texture = SKTexture(rect: rect, in: sheet)
                texture.filteringMode = .nearest
                return texture
            }
        }
        return WalkCycle(frames: frames, size: CGSize(width: frameSize, height: frameSize) * scale)
    }

    /// A portrait for SwiftUI screens (unscaled pixels — draw with `.interpolation(.none)`).
    /// Walk sheets can be shown facing any direction.
    func image(_ id: String, facing direction: Direction = .down) -> UIImage {
        let cacheKey = direction == .down ? id : id + "#" + direction.rawValue
        if let cached = images[cacheKey] { return cached }
        let asset = asset(id)
        let kind = kind(of: id)
        var cgImage: CGImage?
        if let full = sourceImage(id) {
            if kind == "walk_sheet" {
                let frame = CGFloat(asset?.frame ?? 48)
                let layout = SheetLayout(asset: asset, width: CGFloat(full.width), height: CGFloat(full.height))
                if let cell = layout.cells(for: direction).first {
                    cgImage = full.cropping(to: CGRect(x: CGFloat(cell.column) * frame, y: CGFloat(cell.row) * frame, width: frame, height: frame))
                }
            } else {
                cgImage = full
            }
        }
        let image = UIImage(cgImage: cgImage ?? Placeholder.canvas(for: id, kind: kind, direction: direction).cgImage())
        images[cacheKey] = image
        return image
    }

    /// A round-portrait crop, like Fairyland's HUD faces: a square about one head high from the top
    /// of the sprite's visible pixels, centred on it. Cleared with the sprite when it's re-registered.
    func face(_ id: String) -> UIImage {
        let cacheKey = id + "#face"
        if let cached = images[cacheKey] { return cached }
        let whole = image(id)
        guard let cgImage = whole.cgImage, let box = Self.visibleBounds(of: cgImage) else { return whole }
        let side = max(8, min(box.width, box.height * 0.62).rounded())
        let rect = CGRect(x: (box.midX - side / 2).rounded(), y: max(0, box.minY - 1), width: side, height: side)
        let face = cgImage.cropping(to: rect).map { UIImage(cgImage: $0) } ?? whole
        images[cacheKey] = face
        return face
    }

    /// The box around a picture's opaque pixels, in pixels from its top left.
    private static func visibleBounds(of image: CGImage) -> CGRect? {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 128 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}

/// Where each direction's frames sit in a walk sheet: one row per direction (the usual
/// layout), or all frames on one row split evenly. Row order comes from `directions`.
private struct SheetLayout {
    let directions: [Direction]
    let columns: Int
    let rows: Int

    init(asset: ArtAsset?, width: CGFloat, height: CGFloat) {
        let frame = CGFloat(asset?.frame ?? 48)
        directions = (asset?.directions ?? Direction.allCases.map(\.rawValue)).compactMap(Direction.init(rawValue:))
        columns = max(1, Int(width / frame))
        rows = max(1, Int(height / frame))
    }

    func cells(for direction: Direction) -> [(column: Int, row: Int)] {
        guard let index = directions.firstIndex(of: direction) else { return [] }
        if rows >= directions.count {
            return (0..<columns).map { ($0, index) }
        }
        let perDirection = max(1, columns / max(1, directions.count))
        return (0..<perDirection).map { (index * perDirection + $0, 0) }
    }
}
