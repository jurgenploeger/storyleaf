import SpriteKit

/// Draws the bridges where roads cross a map's river, and the footbridges and jetties out into its
/// lakes (`WorldMap.Bridge`): a deck of planks lying on the water in the ground's own layer
/// (`deck`), and posts and rails standing along its sides (`rails`), the near side sorted in front
/// of whoever walks the deck and the far side behind, so you walk between them. Wood, drawn in
/// code a pixel at a time like the tiles, in the map's palette.
enum BridgeArt {
    /// How far a deck reaches on over the land at an end that meets it, in cells: well onto the bank
    /// (`WorldMap.bank`), its end posts standing on land. A third of a cell only touched the shore.
    static let overlap: CGFloat = 0.6

    /// The wood, as 0...255 channels.
    private static let plank = (r: 164.0, g: 116.0, b: 70.0)
    private static let gap = (r: 78.0, g: 52.0, b: 34.0)
    private static let beam = (r: 112.0, g: 76.0, b: 46.0)
    private static let edge = (r: 84.0, g: 56.0, b: 34.0)
    private static let nail = (r: 60.0, g: 52.0, b: 48.0)

    /// A bridge's deck for the ground's own (unprojected) layer, where it lies over its cells:
    /// planks across it, a beam along each side and a strip of shadow on the water past them,
    /// `pixels` to a cell like the tiles. Nil if it can't be drawn.
    static func deck(for bridge: WorldMap.Bridge, pixels: Int, palette: MapPalette?) -> SKSpriteNode? {
        guard pixels > 0 else { return nil }
        let tile = WorldMap.tileSize
        let before = bridge.landsAtStart ? overlap : 0, after = bridge.landsAtEnd ? overlap : 0
        let cellsAlong = CGFloat(bridge.end - bridge.start + 1) + before + after
        let shadow = max(2, pixels / 8), beamWidth = max(2, pixels / 10)
        let deckWide = bridge.lanes * pixels
        let across = deckWide + 2 * shadow
        let along = Int((cellsAlong * CGFloat(pixels)).rounded())
        let plankDeep = max(3, pixels / 4)
        // Grid-space orientation: x east, y north (image rows top down).
        let width = bridge.northward ? across : along, height = bridge.northward ? along : across
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        func put(_ x: Int, _ y: Int, _ color: (r: Double, g: Double, b: Double), alpha: Double = 1) {
            let index = ((height - 1 - y) * width + x) * 4
            bytes[index] = UInt8(min(255, max(0, color.r * alpha)))
            bytes[index + 1] = UInt8(min(255, max(0, color.g * alpha)))
            bytes[index + 2] = UInt8(min(255, max(0, color.b * alpha)))
            bytes[index + 3] = UInt8(alpha * 255)
        }
        for v in 0..<along {
            let board = v / plankDeep, inBoard = v % plankDeep
            // Each plank a little lighter or darker than the next.
            let tone = 0.92 + 0.16 * noise(board, bridge.lane &* 31 &+ bridge.start)
            for u in 0..<across {
                let x = bridge.northward ? u : v, y = bridge.northward ? v : u
                let inside = u - shadow
                if inside < 0 || inside >= deckWide {
                    put(x, y, (0, 0, 0), alpha: 0.28)
                    continue
                }
                if inside == 0 || inside == deckWide - 1 {
                    put(x, y, edge)
                } else if inside < beamWidth || inside >= deckWide - beamWidth {
                    put(x, y, beam)
                } else if inBoard == plankDeep - 1 {
                    put(x, y, gap)
                } else if inBoard == plankDeep / 2, inside == beamWidth + 1 || inside == deckWide - beamWidth - 2 {
                    put(x, y, nail)
                } else {
                    var shade = tone * (inBoard == 0 ? 1.12 : 1)
                    // A darker fleck of grain here and there.
                    if noise(inside, v &* 7 &+ bridge.lane) < 0.06 { shade *= 0.85 }
                    put(x, y, (plank.r * shade, plank.g * shade, plank.b * shade))
                }
            }
        }
        guard var image = Self.image(bytes, width: width, height: height) else { return nil }
        if let palette, let graded = Recolor.grade(palette, image: image) { image = graded }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .nearest
        let scale = tile / CGFloat(pixels)
        let sprite = SKSpriteNode(texture: texture, size: CGSize(width: CGFloat(width) * scale, height: CGFloat(height) * scale))
        sprite.anchorPoint = .zero
        let low = CGFloat(bridge.start) - before, side = CGFloat(bridge.lane) - CGFloat(shadow) / CGFloat(pixels)
        sprite.position = bridge.northward ? CGPoint(x: side * tile, y: low * tile) : CGPoint(x: low * tile, y: side * tile)
        return sprite
    }

    /// A bridge's posts and rails, standing in `world`: a post at each corner and about every cell
    /// and a quarter along both sides, two rails between each pair, and across a jetty's far end.
    /// `pixels`: the tiles' pixels to a cell, so the wood's pixels are the same size as theirs.
    static func rails(for bridge: WorldMap.Bridge, pixels: Int, palette: MapPalette?, in world: SKNode) {
        let tile = WorldMap.tileSize
        let scale = tile / CGFloat(max(1, pixels))
        guard let post = texture(post: true, palette: palette), let rail = texture(post: false, palette: palette) else { return }
        let before = bridge.landsAtStart ? overlap : 0, after = bridge.landsAtEnd ? overlap : 0
        let first = CGFloat(bridge.start) - before + 0.1, last = CGFloat(bridge.end + 1) + after - 0.1
        let count = max(2, Int(((last - first) / 1.25).rounded()) + 1)
        /// Where a spot on the deck (lanes across, cells along) stands on screen.
        func spot(_ across: CGFloat, _ along: CGFloat) -> CGPoint {
            WorldMap.project(bridge.northward ? CGPoint(x: across * tile, y: along * tile) : CGPoint(x: along * tile, y: across * tile))
        }
        let near = CGFloat(bridge.lane) + 0.12, far = CGFloat(bridge.lane + bridge.lanes) - 0.12
        let middle = spot((near + far) / 2, (first + last) / 2)
        /// A post at each spot, and two rails from each to the next, sorted in front of the deck
        /// if the line runs along its near side, behind if along its far side.
        func line(_ spots: [CGPoint], inFront: Bool) {
            for base in spots {
                let node = SKSpriteNode(texture: post, size: CGSize(width: 3 * scale, height: 10 * scale))
                node.anchorPoint = CGPoint(x: 0.5, y: 0.05)
                node.position = base
                node.zPosition = -base.y
                world.addChild(node)
            }
            for (a, b) in zip(spots, spots.dropFirst()) {
                let z = inFront ? -min(a.y, b.y) + 0.01 : -max(a.y, b.y) - 0.01
                for (lift, thick) in [(8.5 * scale, 2 * scale), (4.5 * scale, scale)] {
                    let length = a.distance(to: b)
                    let node = SKSpriteNode(texture: rail, size: CGSize(width: length + scale, height: thick))
                    node.anchorPoint = CGPoint(x: 0, y: 0.5)
                    node.position = CGPoint(x: a.x, y: a.y + lift)
                    node.zRotation = atan2(b.y - a.y, b.x - a.x)
                    node.zPosition = z
                    world.addChild(node)
                }
            }
        }
        let steps = (0..<count).map { first + (last - first) * CGFloat($0) / CGFloat(count - 1) }
        // The lane nearer you is the one lower on the screen, across (west or south) of the deck.
        line(steps.map { spot(near, $0) }, inFront: true)
        line(steps.map { spot(far, $0) }, inFront: false)
        // A jetty's far end, out in the water.
        if !bridge.landsAtStart || !bridge.landsAtEnd {
            let end = bridge.landsAtStart ? last : first
            let across = [spot(near, end), spot(far, end)]
            line(across, inFront: (across[0].y + across[1].y) / 2 < middle.y)
        }
    }

    /// A post (a few pixels wide, lit down one side, a lighter cap) or a rail's colour (light over
    /// dark, stretched), as a texture in the map's palette.
    private static func texture(post: Bool, palette: MapPalette?) -> SKTexture? {
        let width = post ? 3 : 1, height = post ? 10 : 2
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                // Lit from the upper left, as the art is: the cap and left side light, the right dark.
                var color = beam
                if y == 0 || (post && x == 0) {
                    color = plank
                } else if post, x == width - 1 {
                    color = edge
                } else if post {
                    color = (r: plank.r * 0.9, g: plank.g * 0.9, b: plank.b * 0.9)
                }
                let index = (y * width + x) * 4
                bytes[index] = UInt8(color.r)
                bytes[index + 1] = UInt8(color.g)
                bytes[index + 2] = UInt8(color.b)
                bytes[index + 3] = 255
            }
        }
        guard var image = Self.image(bytes, width: width, height: height) else { return nil }
        if let palette, let graded = Recolor.grade(palette, image: image) { image = graded }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .nearest
        return texture
    }

    /// A steady scatter from 0 to 1 for a pair of numbers.
    private static func noise(_ a: Int, _ b: Int) -> Double {
        var value = UInt32(truncatingIfNeeded: (a &* 73_856_093) ^ (b &* 19_349_663))
        value = (value ^ (value >> 13)) &* 0x5bd1_e995
        value ^= value >> 15
        return Double(value & 0xffff) / 65535
    }

    /// Premultiplied RGBA bytes, top row first, as an image.
    private static func image(_ bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0, let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
