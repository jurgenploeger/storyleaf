import CoreImage
import SpriteKit

/// A tilt-shift depth of field, as if the camera were focused on the hero: scenery toward the top
/// of the screen (farther away) goes softly out of focus, scenery toward the bottom (closer) a little
/// less, and the band around the hero stays sharp. Each sprite swaps between its sharp texture and a
/// few pre-blurred copies as the camera moves, so nothing is filtered per frame. Tuned per map by
/// `ambience.focus` in content/maps.json.
final class DepthOfField {
    /// Blurred steps between sharp and fully soft.
    static let levels = 3

    private struct Entry {
        let node: SKSpriteNode
        let sharp: SKTexture
        let size: CGSize
        let anchor: CGPoint
        var level = 0
    }

    private struct Look {
        let texture: SKTexture
        /// Blurred size over sharp size (the blur spills past the sprite's edges).
        let grow: CGSize
        /// The spill on each side, as a fraction of the sharp size.
        let pad: CGSize
    }

    /// The sprites, by what holds them: a map's scenery is in chunks (`WorldScene.chunk(at:)`), and
    /// only those in the scene are refocused.
    private struct Group {
        weak var holder: SKNode?
        var entries: [Entry] = []
    }
    private var groups: [ObjectIdentifier: Group] = [:]
    private var cache: [ObjectIdentifier: [Look]] = [:]
    /// Strongest blur, in points.
    private let blur: Double
    /// Half-height of the sharp band, as a fraction of half the screen.
    private let band: CGFloat
    /// How soft the bottom of the screen gets, relative to the top.
    private let near: CGFloat
    private var lastCamera = CGPoint(x: CGFloat.infinity, y: CGFloat.infinity)
    private var lastHalfHeight: CGFloat = 0
    private static let context = CIContext()

    init(_ def: MapDef.Ambience.Focus?) {
        blur = max(0, def?.blur ?? 1.5)
        band = CGFloat(min(0.9, max(0, def?.band ?? 0.4)))
        near = CGFloat(min(1, max(0, def?.near ?? 0.5)))
    }

    /// Lets a scenery sprite drift in and out of focus. Call once it has its texture, size and anchor.
    func add(_ node: SKSpriteNode) {
        guard blur > 0, let texture = node.texture else { return }
        let key = node.parent.map { ObjectIdentifier($0) } ?? ObjectIdentifier(DepthOfField.self)
        groups[key, default: Group(holder: node.parent)].entries.append(Entry(node: node, sharp: texture, size: node.size, anchor: node.anchorPoint))
    }

    /// Refocuses everything on the next `update`, moved or not: chunks have come into the scene.
    func refocus() {
        lastCamera = CGPoint(x: CGFloat.infinity, y: CGFloat.infinity)
    }

    /// Refocuses around the camera. `halfHeight` is half the visible height in world points.
    func update(camera: CGPoint, halfHeight: CGFloat) {
        guard blur > 0, halfHeight > 0 else { return }
        let moved = abs(camera.x - lastCamera.x) + abs(camera.y - lastCamera.y)
        guard moved >= 1 || abs(halfHeight - lastHalfHeight) > 0.5 else { return }
        lastCamera = camera
        lastHalfHeight = halfHeight
        for key in Array(groups.keys) {
            // A chunk out of the scene waits until it's back.
            if let holder = groups[key]?.holder, holder.parent == nil { continue }
            refocus(&groups[key]!.entries, camera: camera, halfHeight: halfHeight)
        }
    }

    private func refocus(_ entries: inout [Entry], camera: CGPoint, halfHeight: CGFloat) {
        for index in entries.indices {
            let entry = entries[index]
            // Where the sprite's middle sits on screen: 0 on the hero's line, ±1 at the screen's edges.
            let middle = entry.node.position.y + entry.size.height * (0.5 - entry.anchor.y)
            let offset = (middle - camera.y) / halfHeight
            var amount = min(1, max(0, (abs(offset) - band) / (1 - band)))
            amount = amount * amount * (3 - 2 * amount)
            if offset < 0 { amount *= near }
            let target = amount * CGFloat(Self.levels)
            // A little hysteresis, so a sprite sitting on a boundary doesn't flicker.
            guard abs(target - CGFloat(entry.level)) > 0.6 else { continue }
            let level = Int(target.rounded())
            guard level != entry.level else { continue }
            entries[index].level = level
            apply(level, to: entry)
        }
    }

    private func apply(_ level: Int, to entry: Entry) {
        guard level > 0, let look = looks(for: entry)?[level - 1] else {
            entry.node.texture = entry.sharp
            entry.node.size = entry.size
            entry.node.anchorPoint = entry.anchor
            return
        }
        entry.node.texture = look.texture
        entry.node.size = CGSize(width: entry.size.width * look.grow.width, height: entry.size.height * look.grow.height)
        // Keep the sprite's foot on the same spot of the bigger, padded texture.
        entry.node.anchorPoint = CGPoint(
            x: (look.pad.width + entry.anchor.x) / look.grow.width,
            y: (look.pad.height + entry.anchor.y) / look.grow.height
        )
    }

    /// The blurred copies of an entry's texture, made the first time they're needed and shared by
    /// every sprite using that texture.
    private func looks(for entry: Entry) -> [Look]? {
        let key = ObjectIdentifier(entry.sharp)
        if let cached = cache[key] { return cached.isEmpty ? nil : cached }
        let image = entry.sharp.cgImage()
        let width = CGFloat(image.width), height = CGFloat(image.height)
        guard width > 0, height > 0, entry.size.width > 0 else {
            cache[key] = []
            return nil
        }
        let input = CIImage(cgImage: image)
        let pixelsPerPoint = Double(width / entry.size.width)
        var made: [Look] = []
        for level in 1...Self.levels {
            let sigma = blur * Double(level) / Double(Self.levels) * pixelsPerPoint
            let pad = CGFloat(ceil(sigma * 2.5))
            let rect = input.extent.insetBy(dx: -pad, dy: -pad)
            guard let blurred = Self.context.createCGImage(input.applyingGaussianBlur(sigma: sigma), from: rect) else {
                cache[key] = []
                return nil
            }
            let texture = SKTexture(cgImage: blurred)
            texture.filteringMode = .linear
            made.append(Look(
                texture: texture,
                grow: CGSize(width: rect.width / width, height: rect.height / height),
                pad: CGSize(width: pad / width, height: pad / height)
            ))
        }
        cache[key] = made
        return made
    }
}
