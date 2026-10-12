import SpriteKit

/// What your equipment looks like on the hero: the weapon in hand (the item's own pixel art, in
/// front of or behind the body depending on facing) and a sparkle in an accessory's colour.
/// Armour and boots change the sprite itself (`GameSession.rules(for:armor:)` and GearOverlay).
enum GearArt {
    // MARK: Weapon

    /// A weapon sprite for `item`, sized for a character `height` points tall.
    static func weapon(_ item: ItemDef, height: CGFloat) -> SKSpriteNode? {
        guard item.type == .weapon else { return nil }
        if let art = item.art, let held = held(art) {
            // The item's own art (drawn diagonally, grip bottom-left), so every weapon looks like itself.
            let size = CGSize(width: height * 0.48, height: height * 0.48)
            let node = SKSpriteNode(texture: held.texture, size: size)
            node.anchorPoint = held.grip
            node.name = "weapon"
            if let hex = item.glow, let color = UIColor(hex: hex), let at = item.glowAt, at.count == 2 {
                // glowAt is in the art's pixels, rows top-down; the node's origin is the grip.
                let spot = CGPoint(x: at[0] / held.pixels.width - held.grip.x, y: 1 - at[1] / held.pixels.height - held.grip.y)
                node.addChild(glow(color, at: CGPoint(x: spot.x * size.width, y: spot.y * size.height), height: height))
            }
            return node
        }
        let texture = texture(for: item.icon ?? "sword")
        let node = SKSpriteNode(texture: texture, size: CGSize(width: height * 0.42, height: height * 0.42))
        node.anchorPoint = CGPoint(x: 0.2, y: 0.2)   // the grip
        node.name = "weapon"
        return node
    }

    /// The same weapon as a picture for SwiftUI (the Character tab's hero): the image, its grip as a
    /// unit point (y up, like an anchor) and its size as a share of the character's height.
    static func heldImage(_ item: ItemDef) -> (image: UIImage, grip: CGPoint, scale: CGFloat)? {
        guard item.type == .weapon else { return nil }
        if let art = item.art, let held = held(art), let image = ArtLibrary.shared.artImage(art) {
            return (image, held.grip, 0.48)
        }
        return (UIImage(cgImage: texture(for: item.icon ?? "sword").cgImage()), CGPoint(x: 0.2, y: 0.2), 0.42)
    }

    /// A magic weapon's light: a small soft glow at the tip that slowly breathes, and now and then
    /// a tiny sparkle drifting up from it. Kept faint so it reads as magic, not a lamp.
    private static func glow(_ color: UIColor, at tip: CGPoint, height: CGFloat) -> SKNode {
        let group = SKNode()
        group.position = tip
        group.zPosition = 1
        let light = SKSpriteNode(texture: SoftTextures.glow, size: CGSize(width: height * 0.32, height: height * 0.32))
        light.color = color
        light.colorBlendFactor = 1
        light.blendMode = .add
        light.alpha = 0.3
        let breathe = SKAction.sequence([.fadeAlpha(to: 0.5, duration: 1.1), .fadeAlpha(to: 0.25, duration: 1.1)])
        breathe.timingMode = .easeInEaseOut
        light.run(.repeatForever(breathe))
        group.addChild(light)
        let spark = SKSpriteNode(texture: SoftTextures.star, size: CGSize(width: 5, height: 5))
        spark.color = color
        spark.colorBlendFactor = 1
        spark.blendMode = .add
        spark.alpha = 0
        group.addChild(spark)
        let drift = SKAction.sequence([
            // Weakly: the endless action would otherwise keep the spark (and its gear) alive forever.
            .run { [weak spark] in spark?.position = CGPoint(x: .random(in: -3...3), y: .random(in: -2...2)) },
            .group([.sequence([.fadeAlpha(to: 0.8, duration: 0.25), .fadeOut(withDuration: 0.6)]), .moveBy(x: 0, y: 7, duration: 0.85)]),
            .wait(forDuration: 1.4, withRange: 1.6),
        ])
        spark.run(.repeatForever(drift))
        return group
    }

    private static var heldCache: [String: (texture: SKTexture, grip: CGPoint, pixels: CGSize)] = [:]

    /// An item sprite as a held weapon: its texture, the grip (the lowest, leftmost bit of art) as a
    /// unit point like an anchor, and the art's size in pixels.
    private static func held(_ art: String) -> (texture: SKTexture, grip: CGPoint, pixels: CGSize)? {
        if let cached = heldCache[art] { return cached }
        guard let image = ArtLibrary.shared.artImage(art)?.cgImage else { return nil }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        // Rows run top to bottom. The grip is the solid pixel nearest the bottom-left corner (soft
        // glow pixels and lone sparkles don't count).
        var best: (x: Int, y: Int)?
        func solid(_ x: Int, _ y: Int) -> Bool {
            x >= 0 && y >= 0 && x < width && y < height && pixels[(y * width + x) * 4 + 3] > 200
        }
        for y in 0..<height {
            // Skip lone sparkle pixels: a part of the weapon has solid neighbours.
            for x in 0..<width where solid(x, y) && [(1, 0), (-1, 0), (0, 1), (0, -1)].filter({ solid(x + $0.0, y + $0.1) }).count >= 2 {
                // Distance from each corner, along both edges.
                if best == nil || x + (height - y) < best!.x + (height - best!.y) { best = (x, y) }
            }
        }
        guard let grip = best else { return nil }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .nearest
        // Hold it a little up the handle, not by the very tip.
        let anchor = CGPoint(x: (Double(grip.x) + 3) / Double(width), y: (Double(height - grip.y) + 2) / Double(height))
        let artSize = CGSize(width: width, height: height)
        heldCache[art] = (texture, anchor, artSize)
        return (texture, anchor, artSize)
    }

    /// Holds the weapon in the hand for the way the character faces (`hand(in:facing:)`), in the
    /// frame the sprite shows: just behind the body, so the hand closes over the grip and the rest
    /// of the weapon shows past it, rather than hanging beside it. Pointing up and away from the
    /// body, mirrored facing away or left. `frame`: a frame other than the one showing (the walk's
    /// next, `Walker`).
    static func pose(_ weapon: SKSpriteNode, facing: Direction, height: CGFloat, frame: SKTexture? = nil) {
        weapon.position = grip(on: weapon.parent as? SKSpriteNode, frame: frame, facing: facing, height: height)
        weapon.xScale = facing == .up || facing == .left ? -1 : 1
        weapon.zPosition = -1
    }

    /// Where a weapon's grip goes on `body` (a walking sprite) showing `frame` (else its own): its
    /// hand there, from the sprite's anchor.
    static func grip(on body: SKSpriteNode?, frame: SKTexture? = nil, facing: Direction, height: CGFloat) -> CGPoint {
        let size = body?.size ?? CGSize(width: height, height: height)
        let anchor = body?.anchorPoint ?? CGPoint(x: 0.5, y: 0.08)
        let spot = (frame ?? body?.texture).map { hand(in: $0, facing: facing) } ?? hand(top: 0.27, bottom: 0.94, facing: facing)
        return CGPoint(x: (spot.x - anchor.x) * size.width, y: (spot.y - anchor.y) * size.height)
    }

    /// Where the hand that holds a weapon is in a walking sprite's frame facing `facing`, as a unit
    /// point (x from the left, y up from the bottom, like an anchor): beside the body (at the side
    /// facing you, the side facing away, or the near hand walking sideways, measured on the walk
    /// sheets' 48-pixel frames) and part way down the figure in that very frame, from the top of its
    /// head to its feet, so it sits lower on a dwarf and bobs a pixel as the walk does.
    static func hand(in frame: SKTexture, facing: Direction) -> CGPoint {
        let bounds = Self.figure(of: frame)
        return hand(top: bounds.top, bottom: bounds.bottom, facing: facing)
    }

    /// The hand for a figure reaching from `top` to `bottom` of its frame (shares of its height,
    /// from the top).
    private static func hand(top: CGFloat, bottom: CGFloat, facing: Direction) -> CGPoint {
        let (across, down): (CGFloat, CGFloat) = switch facing {
        case .down: (3, 0.58)
        case .up: (-9, 0.55)
        case .right: (3, 0.56)
        case .left: (-4, 0.56)
        }
        return CGPoint(x: 0.5 + across / 48, y: 1 - (top + down * (bottom - top)))
    }

    /// How far down its frame a figure's top and bottom are (shares of the frame's height, from
    /// the top), by its solid pixels; kept per frame while the frame lasts.
    private static func figure(of frame: SKTexture) -> (top: CGFloat, bottom: CGFloat) {
        if let known = figures.object(forKey: frame) { return (CGFloat(known.cgPointValue.x), CGFloat(known.cgPointValue.y)) }
        var found = (top: CGFloat(0.27), bottom: CGFloat(0.94))
        let image = frame.cgImage()
        let width = image.width, height = image.height
        if width > 0, height > 0 {
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
                guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            // Rows run top to bottom.
            var top = height, bottom = -1
            if drawn {
                for row in 0..<height {
                    for col in 0..<width where pixels[(row * width + col) * 4 + 3] > 127 {
                        top = min(top, row)
                        bottom = max(bottom, row)
                    }
                }
            }
            if bottom >= top { found = (CGFloat(top) / CGFloat(height), CGFloat(bottom + 1) / CGFloat(height)) }
        }
        figures.setObject(NSValue(cgPoint: CGPoint(x: found.top, y: found.bottom)), forKey: frame)
        return found
    }

    /// Each frame's figure (`figure(of:)`), forgotten with the frame.
    private static let figures = NSMapTable<SKTexture, NSValue>.weakToStrongObjects()

    private static var cache: [String: SKTexture] = [:]

    private static func texture(for shape: String) -> SKTexture {
        if let cached = cache[shape] { return cached }
        var c = PixelCanvas(width: 16, height: 16)
        let outline = PixelColor(0x2A1E2E)
        let wood = PixelColor(0x8A5A32)
        switch shape {
        case "wand":   // Oak staff: a knotted stick with a leafy top.
            line(&c, from: (1, 15), to: (11, 5), color: outline, width: 3)
            line(&c, from: (1, 15), to: (11, 5), color: wood, width: 1)
            c.ellipse(12.5, 3.5, 3.2, 3.2, outline)
            c.ellipse(12.5, 3.5, 2.3, 2.3, PixelColor(0x5CCB5F))
            c[12, 2] = PixelColor(0xB8F5A0)
        case "diamond":   // Crystal wand: slim silver rod, glowing crystal.
            line(&c, from: (2, 14), to: (10, 6), color: outline, width: 3)
            line(&c, from: (2, 14), to: (10, 6), color: PixelColor(0xD8DCE8), width: 1)
            c.fill(10, 1, 5, 5, outline)
            c.fill(11, 2, 3, 3, PixelColor(0x6FE6F2))
            c[11, 2] = .white
        case "axe":
            line(&c, from: (2, 15), to: (11, 6), color: outline, width: 3)
            line(&c, from: (2, 15), to: (11, 6), color: wood, width: 1)
            c.ellipse(11.5, 4.5, 4.2, 3.4, outline)
            c.ellipse(11.5, 4.5, 3.2, 2.4, PixelColor(0xB9C2CF))
            c[10, 3] = .white
        case "paw":   // Tamer whip: a handle and a curling lash.
            line(&c, from: (1, 15), to: (5, 11), color: outline, width: 3)
            line(&c, from: (1, 15), to: (5, 11), color: wood, width: 1)
            for (x, y) in [(6, 10), (7, 8), (8, 6), (10, 5), (12, 5), (13, 7), (12, 9), (10, 9)] {
                c[x, y] = PixelColor(0xC98A4B)
                c[x + 1, y] = outline
            }
        default:   // Sword: silver blade, gold guard, brown grip.
            line(&c, from: (5, 10), to: (14, 1), color: outline, width: 3)
            line(&c, from: (5, 10), to: (14, 1), color: PixelColor(0xE4E8F0), width: 1)
            line(&c, from: (3, 8), to: (7, 12), color: outline, width: 3)
            line(&c, from: (3, 8), to: (7, 12), color: PixelColor(0xF2C230), width: 1)
            line(&c, from: (1, 14), to: (4, 11), color: outline, width: 3)
            line(&c, from: (1, 14), to: (4, 11), color: wood, width: 1)
        }
        let texture = c.texture()
        cache[shape] = texture
        return texture
    }

    private static func line(_ c: inout PixelCanvas, from a: (Int, Int), to b: (Int, Int), color: PixelColor, width: Int) {
        let steps = max(abs(b.0 - a.0), abs(b.1 - a.1))
        for step in 0...steps {
            let t = Double(step) / Double(max(1, steps))
            let x = Int((Double(a.0) + Double(b.0 - a.0) * t).rounded())
            let y = Int((Double(a.1) + Double(b.1 - a.1) * t).rounded())
            let half = width / 2
            c.fill(x - half, y - half, width, width, color)
        }
    }

    // MARK: Accessory

    /// A few twinkles around the wearer, in the accessory's colour.
    static func aura(_ item: ItemDef, height: CGFloat) -> SKNode? {
        guard item.type == .accessory else { return nil }
        let fallback: UIColor = switch item.icon {
        case "clover": UIColor(red: 0.55, green: 1, blue: 0.5, alpha: 1)
        case "gem": UIColor(red: 1, green: 0.45, blue: 0.5, alpha: 1)
        default: UIColor(red: 1, green: 0.88, blue: 0.45, alpha: 1)
        }
        let color = item.accent.flatMap { UIColor(hex: $0) } ?? fallback
        let aura = SKNode()
        aura.name = "aura"
        aura.zPosition = 2
        for index in 0..<3 {
            let star = SKSpriteNode(texture: SoftTextures.star, size: CGSize(width: 7, height: 7))
            star.color = color
            star.colorBlendFactor = 1
            star.blendMode = .add
            star.alpha = 0
            aura.addChild(star)
            let hop = SKAction.run { [weak star] in
                star?.position = CGPoint(x: .random(in: -height * 0.35...height * 0.35), y: .random(in: height * 0.2...height * 0.9))
            }
            let twinkle = SKAction.sequence([hop, .fadeIn(withDuration: 0.3), .wait(forDuration: 0.2), .fadeOut(withDuration: 0.5),
                                             .wait(forDuration: 0.6, withRange: 0.8)])
            star.run(.sequence([.wait(forDuration: 0.5 * Double(index)), .repeatForever(twinkle)]))
        }
        return aura
    }
}
