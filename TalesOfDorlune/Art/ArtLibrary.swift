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
/// rules, or with nil by the sprite's (`ArtLibrary.register`'s `recolor`, or its `derive`'s).
nonisolated struct ArtLayer: Decodable, Sendable {
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
    /// Each direction's standing pose breathing out, and with its eyes shut for a blink: none for a
    /// sprite with no eyes (art/eyes.json) and no walk sheet.
    var poses: [Direction: IdlePose] = [:]

    func frames(_ direction: Direction) -> [SKTexture] {
        frames[direction] ?? frames[.down] ?? []
    }

    /// The same picture whichever way it goes (a single image, or a sheet with no side views): it's
    /// mirrored to walk the other way.
    var mirrors: Bool {
        frames(.left).first === frames(.right).first
    }
}

/// A standing pose (a walk cycle's first frame) as it breathes and blinks: a pixel lower breathing
/// out (`out`), its eyes shut (`shut`), or both.
struct IdlePose {
    var shut: SKTexture?
    var out: SKTexture?
    var outShut: SKTexture?
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
        remember(image, for: texture)
        if Self.gradedKinds.contains(kind(of: id)) {
            gradedTextures[id] = texture
        } else {
            textures[id] = texture
        }
        return texture
    }

    /// The sprite's own PNG, or — for derived sprites — its base's PNG with the palette swap applied.
    /// `shut`: its eyes shut for a blink (art/eyes.json), on its own PNG or on its paper-doll layers
    /// before they're recoloured and dressed, so whatever is drawn over the face still is.
    private func sourceImage(_ id: String, depth: Int = 0, shut: Bool = false) -> CGImage? {
        // "raw:<id>": the art as it's drawn, graded for no map (the sea, the same blue round every land).
        if id.hasPrefix("raw:") { return sourceImage(String(id.dropFirst(4)), depth: depth, shut: shut) }
        if let url = pngURL(id), let image = UIImage(contentsOfFile: url.path)?.cgImage {
            return shut ? eyesShut(in: image, as: id, frames: sheetFrames(id, width: image.width, height: image.height)) : image
        }
        guard depth < 3, let derive = asset(id)?.derive else { return nil }
        let base: CGImage
        let recolored: CGImage?
        // Paper-doll layers are recoloured one by one (a layer's own rules, like the hair's, touch
        // only that layer), then stacked.
        let layers = layerSets[id] ?? derive.layers
        // The layers' frames lie as the sprite's do.
        let frames = shut ? layers?.first.flatMap { pngSize($0.id) }.flatMap { sheetFrames(id, width: $0.width, height: $0.height) } : nil
        if let layers, let original = stacked(layers, shut: frames),
           let dressed = stacked(layers, recolor: derive.recolor, shut: frames) {
            base = original
            recolored = dressed
        } else if let sheet = sourceImage(derive.from, depth: depth + 1, shut: shut) {
            base = sheet
            recolored = Recolor.apply(derive.recolor, to: sheet)
        } else {
            return nil
        }
        if let gear = gearLooks[id], let recolored, let from = asset(derive.from) {
            let directions = from.directions ?? ["up", "right", "down", "left"]
            // The plain body the hands, chin and boots are found on (GearLook.body).
            let skeleton = gear.body.flatMap { pngURL($0) }.flatMap { UIImage(contentsOfFile: $0.path)?.cgImage }
            // A festive hat's piece, cut out by tools/wear_art.py (art/sprites/wear_<hat>.png).
            let piece = gear.hat.flatMap { pngURL("wear_\($0)") }.flatMap { UIImage(contentsOfFile: $0.path)?.cgImage }
            let cape = gear.cape == nil && gear.cloak == nil ? nil : pngURL("wear_cape").flatMap { UIImage(contentsOfFile: $0.path)?.cgImage }
            let scarf = gear.scarf == nil ? nil : pngURL("wear_scarf").flatMap { UIImage(contentsOfFile: $0.path)?.cgImage }
            return GearOverlay.apply(gear, original: base, dressed: recolored, skeleton: skeleton, piece: piece,
                                     capePiece: cape, scarfPiece: scarf, frame: from.frame ?? 48, directions: directions)
        }
        return recolored
    }

    /// art/sprites PNGs drawn on top of each other, bottom first; nil unless every one exists.
    /// With `rules`, each layer is recoloured first: by its own rules if it has them, else by these.
    /// With `shut` (where the frames lie), the eyes of the body or head layers are shut first
    /// (`EyeBlink.key(forLayer:)`); an armour sheet's or a helmet's face is left as it is
    /// (`cleanFaces` says where that shows).
    private func stacked(_ layers: [ArtLayer], recolor rules: [RecolorRule]? = nil, shut frames: SheetFrames? = nil) -> CGImage? {
        let images = layers.compactMap { layer -> CGImage? in
            guard var image = pngImage(layer.id) else { return nil }
            if frames != nil, let eyes = EyeBlink.key(forLayer: layer.id) {
                image = eyesShut(in: image, as: eyes, frames: frames)
            }
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
        /// `ground`: a land's ground across a band, this one's or (`from`) a land next door's, under
        /// the rest (see `organicTile`).
        nonisolated enum Style: Sendable { case road, patch, water, cut, ground }
        let tile: String
        /// Roads and patches: bit `row * 3 + col` is set where that cell of the 3×3 around this one
        /// holds the layer (row 0 north, col 0 west; bit 4 is the cell itself). Water: the same for
        /// the 5×5 around it (bit `row * 5 + col`, bit 12 is the cell itself).
        let mask: Int
        let style: Style
        /// A land next door's tile, graded with its palette as it is there, not this land's: its
        /// ground in patches across the band between the two (`Seam`).
        var from: Foreign? = nil
        /// A road taking on the land next door's road across the band (`Fade`).
        var fade: Fade? = nil
    }

    /// A land next door, for its tiles (`GroundLayer.from`).
    nonisolated struct Foreign: Sendable {
        let land: String
        let palette: MapPalette?
    }

    /// A road across the band between two lands (`Seam`): the land next door's road tile, graded as
    /// it is there, mixed into this land's by `share` (0...1), so the road changes look a little at
    /// a time instead of all at once at the border.
    nonisolated struct Fade: Sendable {
        let tile: String
        let from: Foreign
        let share: Double

        /// What tells one fade from another in a texture's key.
        var key: String { "\(from.land)~\(tile)~\(share)" }
    }

    /// One of four versions of a tile (0 is the tile itself). The others show the texture shifted
    /// and mirrored inside a soft frame of the original, so they share its edges: any mix of them
    /// tiles seamlessly, and big areas stop repeating the same square.
    func tileVariant(_ id: String, _ index: Int) -> SKTexture {
        let key = "variant|\(id)|\(index % 4)"
        if let cached = blended[key] { return cached }
        let image = tileImage(id)
        let size = max(image.width, 16)
        let texture = makeTexture(variantPixels(id, index, size: size), size: size)
        blended[key] = texture
        return texture
    }

    /// A land's water two cells or more from any shore, out in a lake or a wide river: version `index`
    /// of its tile a shade deeper (`deepShade`), as `organicTile` darkens the water toward it from
    /// the shallows, so a lake has a middle instead of one flat blue.
    func deepWaterTile(_ id: String, _ index: Int) -> SKTexture {
        let key = "deep|\(id)|\(index % 4)"
        if let cached = blended[key] { return cached }
        let size = max(tileImage(id).width, 16)
        var out = variantPixels(id, index, size: size)
        let deep = Self.deepShade(1)
        for i in stride(from: 0, to: out.count, by: 4) {
            for c in 0..<3 { out[i + c] = UInt8(Double(out[i + c]) * (1 - deep)) }
        }
        let texture = makeTexture(out, size: size)
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

    /// Version `variant` of a land next door's tile, graded as it is there (`Foreign`), for a cell
    /// all its ground, the size of this land's `base` tile.
    func foreignTile(_ id: String, palette: MapPalette?, from land: String, variant: Int, base: String) -> SKTexture {
        let key = "foreign|\(land)|\(id)|\(variant % 4)"
        if let cached = blended[key] { return cached }
        let size = max(tileImage(base).width, 16)
        let texture = makeTexture(foreignPixels(id, palette: palette, from: land, variant: variant, size: size), size: size)
        blended[key] = texture
        return texture
    }

    /// Version `variant` of this land's tile `id` with a land next door's mixed in (`Fade`), for a
    /// road cell all road across the band between them.
    func fadedTile(_ id: String, fade: Fade, variant: Int) -> SKTexture {
        let key = "faded|\(id)|\(fade.key)|\(variant % 4)"
        if let cached = blended[key] { return cached }
        let size = max(tileImage(id).width, 16)
        let texture = makeTexture(fadedPixels(id, fade: fade, variant: variant, size: size), size: size)
        blended[key] = texture
        return texture
    }

    /// This land's tile `id` and the land next door's (`fade`) mixed, pixel by pixel.
    private func fadedPixels(_ id: String, fade: Fade, variant: Int, size: Int) -> [UInt8] {
        let own = variantPixels(id, variant, size: size)
        let theirs = foreignPixels(fade.tile, palette: fade.from.palette, from: fade.from.land, variant: variant, size: size)
        guard own.count == theirs.count else { return own }
        let share = min(1, max(0, fade.share))
        var out = own
        for index in out.indices {
            let mixed: Double = Double(own[index]) * (1 - share) + Double(theirs[index]) * share
            out[index] = UInt8(min(255, mixed.rounded()))
        }
        return out
    }

    /// A ground tile with soft, rounded roads, patches and water drawn over `base`. Roads and
    /// patches are rounded strokes joining the cells around this one that hold them, so corners
    /// curve and diagonal steps become smooth bends; their edges wobble in a pattern that repeats
    /// every tile. Water is a smooth field over the 5×5 cells around, so shores curve freely instead
    /// of following cell edges, and wobbles with its place on the map (`cell`). Either way
    /// neighbouring tiles meet seamlessly. Roads get a darker rim, water a foamy edge and a damp bank.
    /// Shoreline tiles are unique anyway, so they also use tile variant `variant`. A patch layer
    /// `from` a land next door is its ground, graded as it is there.
    ///
    /// Across the band between two lands (`Seam`), the grounds each cell round shows (`ground`
    /// layers, in the same order whichever land draws the tile) go down first, over `base`: at each
    /// pixel the last of them whose soft shape reaches it, else the first with a cell within `verge`
    /// of it. So what shows between the shapes, along an edge, is the same from both tiles either
    /// side of it, though a land next door draws the one past its border: with the land's own
    /// ground there, its patches stopped dead along the border (playtesting 2026-10-16).
    func organicTile(base: String, layers: [GroundLayer], cell: GridPoint, variant: Int) -> SKTexture {
        let hasWater = layers.contains { $0.style == .water || $0.style == .cut }
        let place = hasWater ? "@\(cell.col),\(cell.row)#\(variant)" : ""
        let key = "organic|\(base)|" + layers.map { "\($0.tile):\($0.mask):\($0.style):\($0.from?.land ?? ""):\($0.fade?.key ?? "")" }.joined(separator: "|") + place
        if let cached = blended[key] { return cached }
        let size = max(tileImage(base).width, 16)
        let pick = hasWater ? variant : 0
        var out = variantPixels(base, pick, size: size)
        let rim = 1.2 / Double(size)
        let grounds = layers.filter { $0.style == .ground }
        if !grounds.isEmpty {
            var texels: [[UInt8]] = []
            var segments: [[(x0: Double, y0: Double, x1: Double, y1: Double)]] = []
            // Each ground's cells of the 3×3, in this cell's coordinates.
            var cells: [[(x: Double, y: Double)]] = []
            for layer in grounds {
                if let from = layer.from {
                    texels.append(foreignPixels(layer.tile, palette: from.palette, from: from.land, variant: pick, size: size))
                } else {
                    texels.append(variantPixels(layer.tile, pick, size: size))
                }
                segments.append(Self.strokes(mask: layer.mask))
                var near: [(x: Double, y: Double)] = []
                for bit in 0..<9 where layer.mask & (1 << bit) != 0 {
                    let x: Double = Double(bit % 3 - 1)
                    let y: Double = Double(1 - bit / 3)
                    near.append((x: x, y: y))
                }
                cells.append(near)
            }
            for py in 0..<size {
                for px in 0..<size {
                    let x: Double = (Double(px) + 0.5) / Double(size) - 0.5
                    let y: Double = 0.5 - (Double(py) + 0.5) / Double(size)
                    let reach: Double = 0.42 + Self.wobble(x, y, style: .patch, cell: cell)
                    var shown: Int? = nil
                    // The last whose shape reaches here.
                    for index in grounds.indices.reversed() where shown == nil {
                        for segment in segments[index] where Self.distance(x, y, to: segment) < reach {
                            shown = index
                            break
                        }
                    }
                    // Else the first with a cell within `verge`.
                    for index in grounds.indices where shown == nil {
                        for spot in cells[index] where Self.gap(x, y, to: spot) < Self.verge {
                            shown = index
                            break
                        }
                    }
                    let index = (py * size + px) * 4
                    guard let ground = shown, texels[ground].count == out.count else { continue }
                    for c in 0..<3 { out[index + c] = texels[ground][index + c] }
                    out[index + 3] = 255
                }
            }
        }
        for layer in layers where layer.style != .ground {
            let shore = layer.style == .water || layer.style == .cut
            let texels: [UInt8]
            if layer.style == .cut {
                texels = []
            } else if let fade = layer.fade {
                texels = fadedPixels(layer.tile, fade: fade, variant: pick, size: size)
            } else if let from = layer.from {
                texels = foreignPixels(layer.tile, palette: from.palette, from: from.land, variant: pick, size: size)
            } else {
                texels = variantPixels(layer.tile, pick, size: size)
            }
            let segments: [(x0: Double, y0: Double, x1: Double, y1: Double)] = shore ? [] : Self.strokes(mask: layer.mask)
            let pools: [(x: Double, y: Double)] = shore ? Self.pools(mask: layer.mask) : []
            let radius: Double = switch layer.style {
            case .road: 0.36
            case .patch, .ground: 0.42
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
                    case .road, .patch, .ground:
                        guard depth > 0 else { continue }
                        let shade = layer.style == .road && depth < rim ? 0.72 : 1
                        for c in 0..<3 { out[index + c] = UInt8(Double(texels[index + c]) * shade) }
                        out[index + 3] = 255
                    case .water:
                        // A land's own water (not ice or chocolate) gets depth and a bank: paler in the
                        // shallows, deeper out from the shore, and a strip of damp earth and pebbles
                        // along it, where the land had stopped dead at a flat blue (playtesting 2026-10-23).
                        let natural = layer.tile == "tile_water"
                        let speck = Self.speck(px, py, cell)
                        if depth > 0 {
                            // Foam along the edge, broken here and there, with a few flecks out past it.
                            let foam = depth < 0.05 ? (speck < 0.75 ? 0.35 : 0.12) : (depth < 0.1 && speck < 0.12 ? 0.22 : 0)
                            let shallow = natural ? 0.3 * pow(max(0, 1 - depth / 0.4), 1.5) : 0
                            let deep = natural ? Self.deepShade(depth) : 0
                            for c in 0..<3 {
                                var value: Double = Double(texels[index + c]) * (1 - deep)
                                value += (Self.shallows[c] - value) * shallow
                                value = value * (1 - foam) + 255 * foam
                                out[index + c] = UInt8(max(0, min(255, value)))
                            }
                            out[index + 3] = 255
                        } else if depth > -0.06 {
                            // The lip of the bank, in the shadow it throws on the water's edge.
                            for c in 0..<3 {
                                let value: Double = natural ? Double(out[index + c]) * 0.55 + Self.bank[c] * 0.2 : Double(out[index + c]) * 0.8
                                out[index + c] = UInt8(max(0, min(255, value)))
                            }
                        } else if natural, depth > -0.3 {
                            // The bank: damp earth, more of it toward the water, and pebbles in it.
                            let near: Double = pow((depth + 0.3) / 0.24, 1.2)
                            for c in 0..<3 {
                                let ground: Double = Double(out[index + c])
                                let earth: Double = speck < 0.035 && near > 0.2 ? Self.pebble[c] : Self.bank[c]
                                let mix: Double = speck < 0.035 && near > 0.2 ? 0.85 : 0.72 * near
                                out[index + c] = UInt8(max(0, min(255, ground + (earth - ground) * mix)))
                            }
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
        let texture = makeTexture(out, size: size)
        blended[key] = texture
        return texture
    }

    private func makeTexture(_ bytes: [UInt8], size: Int) -> SKTexture {
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .nearest
        remember(image, for: texture)
        return texture
    }

    /// The image each texture the library made was drawn from (`picture(of:)`), while the texture
    /// lives.
    private struct Source {
        weak var texture: SKTexture?
        let image: CGImage
    }
    private var sources: [ObjectIdentifier: Source] = [:]
    /// How many `sources` there may be before those of textures gone are let go.
    private var sourcesPrunedAt = 4096

    /// The image `texture` shows: for a texture the library made, the image it was made from.
    /// `SKTexture.cgImage()` sets up a Core Image context every time it's called, and once for
    /// each tile along a coast that slopes to the sea (each its own, `organicTile`) that held a
    /// land's build up for many seconds on a phone, long enough for the watchdog to kill the game
    /// when the phone turned meanwhile.
    func picture(of texture: SKTexture) -> CGImage {
        if let known = sources[ObjectIdentifier(texture)], known.texture === texture { return known.image }
        return texture.cgImage()
    }

    private func remember(_ image: CGImage, for texture: SKTexture) {
        sources[ObjectIdentifier(texture)] = Source(texture: texture, image: image)
        if sources.count > sourcesPrunedAt {
            sources = sources.filter { $0.value.texture != nil }
            sourcesPrunedAt = max(4096, sources.count * 2)
        }
    }

    /// How much darker a land's water is `depth` cells in from its shore: none in the shallows, the
    /// most two cells out (`deepWaterTile`).
    nonisolated static func deepShade(_ depth: Double) -> Double {
        let t = max(0, min(1, (depth - 0.25) / 0.55))
        return 0.2 * t * t * (3 - 2 * t)
    }

    /// The shallows' pale turquoise, a bank's damp earth and its pebbles (premultiplied, opaque).
    nonisolated private static let shallows: [Double] = [128, 214, 222]
    nonisolated private static let bank: [Double] = [104, 86, 60]
    nonisolated private static let pebble: [Double] = [186, 180, 168]

    /// A pixel's own fixed chance, 0 to 1, for the foam's breaks and the bank's pebbles.
    nonisolated private static func speck(_ px: Int, _ py: Int, _ cell: GridPoint) -> Double {
        var h = UInt32(truncatingIfNeeded: px &* 73_856_093) ^ UInt32(truncatingIfNeeded: py &* 19_349_663)
        h ^= UInt32(truncatingIfNeeded: cell.col &* 83_492_791) ^ UInt32(truncatingIfNeeded: cell.row &* 2_654_435_761)
        h = (h ^ (h >> 13)) &* 1_274_126_177
        return Double((h ^ (h >> 16)) & 0xFFFF) / 65_535
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

    /// How far round a cell of the 3×3 a ground across a band shows where no shape reaches
    /// (`organicTile`): far enough that it fills the gap between this cell's own shape and that
    /// cell's side of it all along.
    nonisolated private static let verge = 0.27

    /// How far a point (in this cell's coordinates) is from the cell `offset` of the 3×3 round it.
    nonisolated private static func gap(_ x: Double, _ y: Double, to offset: (x: Double, y: Double)) -> Double {
        let dx: Double = max(0, abs(x - offset.x) - 0.5)
        let dy: Double = max(0, abs(y - offset.y) - 0.5)
        return (dx * dx + dy * dy).squareRoot()
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
            var cycle = WalkCycle(frames: Dictionary(uniqueKeysWithValues: Direction.allCases.map { ($0, [art.texture]) }), size: art.size,
                                  facesRight: asset?.faces == "right")
            // A single picture blinks, both eyes or none; it breathes by its `motion` (IdleMotion).
            if let eyes = eyeKey(id).flatMap({ EyeBlink.shared.pictures[$0] }), let shut = sourceImage(id, shut: true),
               EyeBlink.shutsEvenly(open: picture(of: art.texture), shut: shut, eyes: eyes) {
                let pose = IdlePose(shut: poseTexture(shut))
                cycle.poses = Dictionary(uniqueKeysWithValues: Direction.allCases.map { ($0, pose) })
            }
            return cycle
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
        var cycle = WalkCycle(frames: frames, size: CGSize(width: frameSize, height: frameSize) * scale)
        cycle.poses = idlePoses(id, sheet: picture(of: sheet), layout: layout, frame: Int(frameSize))
        return cycle
    }

    /// Where a sheet's frames lie, to find each direction's first.
    private struct SheetFrames {
        let layout: SheetLayout
        let frame: Int
    }

    private func sheetFrames(_ id: String, width: Int, height: Int) -> SheetFrames? {
        let asset = asset(id)
        guard asset?.kind == "walk_sheet" else { return nil }
        return SheetFrames(layout: SheetLayout(asset: asset, width: CGFloat(width), height: CGFloat(height)), frame: asset?.frame ?? 48)
    }

    private func pngImage(_ id: String) -> CGImage? {
        pngURL(id).flatMap { UIImage(contentsOfFile: $0.path)?.cgImage }
    }

    private func pngSize(_ id: String) -> (width: Int, height: Int)? {
        pngImage(id).map { ($0.width, $0.height) }
    }

    /// Whose eyes `id` has in art/eyes.json: its own, its base's, or its layers' (the face on top's);
    /// nil when it has none.
    private func eyeKey(_ id: String, depth: Int = 0) -> String? {
        let blink = EyeBlink.shared
        if blink.pictures[id] != nil || blink.sheets[id] != nil { return id }
        guard pngURL(id) == nil, depth < 3, let derive = asset(id)?.derive else { return nil }
        if let layers = layerSets[id] ?? derive.layers,
           let key = layers.reversed().lazy.compactMap({ EyeBlink.key(forLayer: $0.id) }).first(where: { blink.sheets[$0] != nil }) {
            return key
        }
        return eyeKey(derive.from, depth: depth + 1)
    }

    /// `image`, a sprite's own PNG or one of its paper-doll layers, with the eyes `key` has in
    /// art/eyes.json shut: a single picture's on it, a walk sheet's in each direction's first frame.
    private func eyesShut(in image: CGImage, as key: String, frames: SheetFrames?) -> CGImage {
        let blink = EyeBlink.shared
        if let eyes = blink.pictures[key] { return EyeBlink.shut(image, eyes: eyes, lash: true) ?? image }
        guard let frames, let directions = blink.sheets[key] else { return image }
        let eyes = directions.flatMap { direction, eyes -> [Eye] in
            guard let cell = frames.layout.cells(for: direction).first else { return [] }
            return eyes.map { $0.moved(to: (cell.column * frames.frame, cell.row * frames.frame)) }
        }
        return EyeBlink.shut(image, eyes: eyes, lash: false) ?? image
    }

    /// Each direction's standing pose (its first frame) breathing out, and with its eyes shut where
    /// every eye it has that way shut (`EyeBlink.shutsEvenly`) and no other face shows an open one
    /// (`cleanFaces`): drawn from the sprite again with them shut, as it's dressed and recoloured.
    /// Never one eye: a wink.
    private func idlePoses(_ id: String, sheet: CGImage, layout: SheetLayout, frame: Int) -> [Direction: IdlePose] {
        let key = eyeKey(id)
        let eyes = key.flatMap { EyeBlink.shared.sheets[$0] }
        let layers = layerSets[id] ?? asset(id)?.derive?.layers
        let clean = key.flatMap { key in layers.map { cleanFaces($0, key: key, frames: SheetFrames(layout: layout, frame: frame)) } }
        let shutSheet = eyes == nil ? nil : sourceImage(id, shut: true)
        var poses: [Direction: IdlePose] = [:]
        for direction in layout.directions {
            guard let cell = layout.cells(for: direction).first else { continue }
            let rect = CGRect(x: cell.column * frame, y: cell.row * frame, width: frame, height: frame)
            guard let open = sheet.cropping(to: rect) else { continue }
            let shut = shutSheet?.cropping(to: rect).flatMap { closed in
                let even = EyeBlink.shutsEvenly(open: open, shut: closed, eyes: eyes?[direction] ?? [])
                return (clean?.contains(direction) ?? true) && even ? closed : nil
            }
            poses[direction] = IdlePose(shut: shut.map(poseTexture), out: EyeBlink.exhaled(open).map(poseTexture),
                                        outShut: shut.flatMap(EyeBlink.exhaled).map(poseTexture))
        }
        return poses
    }

    /// The ways a sprite stacked from `layers` can blink without an open eye left beside the shut
    /// ones: none with a helmet's or an armour sheet's own face over its head (`hat_`, `armor_`:
    /// their eyes lie elsewhere), and only where its head hides an armour sheet's face under it
    /// round its eyes, two pixels out.
    private func cleanFaces(_ layers: [ArtLayer], key: String, frames: SheetFrames) -> Set<Direction> {
        let isFace = { (id: String) in id.hasPrefix("hat_") || id.hasPrefix("armor_") }
        guard let top = layers.lastIndex(where: { EyeBlink.key(forLayer: $0.id) != nil }),
              !layers[(top + 1)...].contains(where: { isFace($0.id) }),
              let head = pngImage(layers[top].id) else { return [] }
        let under = layers[..<top].filter { isFace($0.id) }.compactMap { pngImage($0.id) }
        var clean = Set<Direction>()
        for (direction, eyes) in EyeBlink.shared.sheets[key] ?? [:] {
            guard let cell = frames.layout.cells(for: direction).first else { continue }
            let placed = eyes.map { $0.moved(to: (cell.column * frames.frame, cell.row * frames.frame)) }
            if under.allSatisfy({ EyeBlink.hides(head, over: $0, round: placed, margin: 2) }) {
                clean.insert(direction)
            }
        }
        return clean
    }

    private func poseTexture(_ image: CGImage) -> SKTexture {
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .nearest
        remember(image, for: texture)
        return texture
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

    /// A round-portrait crop, like Fairyland Online's HUD faces: a square about one head high from the top
    /// of the sprite's visible pixels, centred on it. A hero's (or another adventurer's) is centred on
    /// their head as their plain body has it (`GearLook.body`, same poses, no hat), sized by that body:
    /// a tall hat or a hood measured from the top pushed the face to the bottom of the circle.
    /// Cleared with the sprite when it's re-registered.
    func face(_ id: String) -> UIImage {
        let cacheKey = id + "#face"
        if let cached = images[cacheKey] { return cached }
        let whole = image(id)
        guard let cgImage = whole.cgImage, let box = Self.visibleBounds(of: cgImage) else { return whole }
        var side = max(8, min(box.width, box.height * 0.62).rounded())
        var rect = CGRect(x: (box.midX - side / 2).rounded(), y: max(0, box.minY - 1), width: side, height: side)
        if let plain = plainFrame(id), let body = Self.visibleBounds(of: plain), let head = Self.skinBounds(of: plain) {
            side = max(8, min(body.width, body.height * 0.62).rounded())
            let x = min(max(0, (head.midX - side / 2).rounded()), CGFloat(cgImage.width) - side)
            let y = min(max(0, (head.midY - side / 2).rounded()), CGFloat(cgImage.height) - side)
            rect = CGRect(x: x, y: y, width: side, height: side)
        }
        let face = cgImage.cropping(to: rect).map { UIImage(cgImage: $0) } ?? whole
        images[cacheKey] = face
        return face
    }

    /// The plain body (`GearLook.body`) a hero's sprite `id` is drawn on, facing you, cut from its
    /// sheet as `image(id)` cuts the sprite's frame; nil for anyone else.
    private func plainFrame(_ id: String) -> CGImage? {
        guard let body = gearLooks[id]?.body, let sheet = pngURL(body).flatMap({ UIImage(contentsOfFile: $0.path)?.cgImage }) else { return nil }
        let asset = asset(id)
        let frame = CGFloat(asset?.frame ?? 48)
        let layout = SheetLayout(asset: asset, width: CGFloat(sheet.width), height: CGFloat(sheet.height))
        guard let cell = layout.cells(for: .down).first else { return nil }
        return sheet.cropping(to: CGRect(x: CGFloat(cell.column) * frame, y: CGFloat(cell.row) * frame, width: frame, height: frame))
    }

    /// The box around a plain body's head: its skin's biggest patch (the bald scalp is skin too), as
    /// GearOverlay finds it, in pixels from the top left.
    private static func skinBounds(of image: CGImage) -> CGRect? {
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
        var skin = [Bool](repeating: false, count: width * height)
        for i in 0..<(width * height) where pixels[i * 4 + 3] > 128 {
            let a = Double(pixels[i * 4 + 3])
            let r = Double(pixels[i * 4]) / a, g = Double(pixels[i * 4 + 1]) / a, b = Double(pixels[i * 4 + 2]) / a
            let high = max(r, g, b), low = min(r, g, b), delta = high - low
            var hue = 0.0
            if delta > 0 {
                if high == r { hue = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
                else if high == g { hue = 60 * ((b - r) / delta + 2) }
                else { hue = 60 * ((r - g) / delta + 4) }
            }
            if hue < 0 { hue += 360 }
            let saturation = high == 0 ? 0 : delta / high
            skin[i] = (hue <= 40 || hue >= 342) && saturation > 0.12 && saturation < 0.65 && high > 0.55
        }
        var seen = [Bool](repeating: false, count: width * height)
        var best: [Int] = []
        for start in 0..<(width * height) where skin[start] && !seen[start] {
            var stack = [start], patch: [Int] = []
            seen[start] = true
            while let i = stack.popLast() {
                patch.append(i)
                let x = i % width, y = i / width
                for (nx, ny) in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
                where nx >= 0 && ny >= 0 && nx < width && ny < height && skin[ny * width + nx] && !seen[ny * width + nx] {
                    seen[ny * width + nx] = true
                    stack.append(ny * width + nx)
                }
            }
            if patch.count > best.count { best = patch }
        }
        guard let left = best.map({ $0 % width }).min(), let right = best.map({ $0 % width }).max(),
              let top = best.map({ $0 / width }).min(), let bottom = best.map({ $0 / width }).max() else { return nil }
        return CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
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
