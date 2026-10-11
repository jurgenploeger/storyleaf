import SpriteKit
import UIKit

/// Light and depth on a map, from its `ambience` block in content/maps.json: pools of light on the
/// ground, slanting sunbeams, a sun flare in the corner of the screen and distance haze at the top.
/// Glows around glowing scenery, soft shadows under trees and the ground's colour patches are made
/// per prop and per map by the helpers below.
final class Lighting {
    private var flare: [(node: SKSpriteNode, size: CGFloat, along: CGFloat)] = []
    private var haze: SKSpriteNode?
    /// The sunbeams and the sun's flare, faded together at night and under cloud (`Sky.sunlight`).
    private let beamLayer = SKNode()
    private let sunGlow = SKNode()

    init(_ def: MapDef.Ambience?, world: SKNode, camera: SKCameraNode, bounds: CGRect, seed: String) {
        var rng = SeededRandom(text: seed + "/light")
        world.addChild(beamLayer)
        camera.addChild(sunGlow)

        if let patches = def?.lightPatches, let color = UIColor(hex: patches.color) {
            let alpha = CGFloat(patches.alpha ?? 0.2)
            for _ in 0..<patches.count {
                let width = Self.pick(patches.size, fallback: 60...140, &rng)
                let node = Self.soft(color, size: CGSize(width: width, height: width * 0.5))
                node.position = Self.point(in: bounds, &rng)
                node.zPosition = -99_400
                node.alpha = alpha
                let duration = Double.random(in: 2.5...5, using: &rng)
                node.run(.repeatForever(.sequence([.fadeAlpha(to: alpha * 0.55, duration: duration), .fadeAlpha(to: alpha, duration: duration)])))
                world.addChild(node)
            }
        }

        if let beams = def?.sunbeams, let color = UIColor(hex: beams.color) {
            let alpha = CGFloat(beams.alpha ?? 0.12)
            for _ in 0..<beams.count {
                let width = Self.pick(beams.size, fallback: 30...70, &rng)
                let node = Self.soft(color, size: CGSize(width: width, height: width * 7))
                node.anchorPoint = CGPoint(x: 0.5, y: 0.05)
                node.zRotation = -0.45 + CGFloat.random(in: -0.08...0.08, using: &rng)
                node.position = Self.point(in: bounds, &rng)
                node.zPosition = 22_000
                node.alpha = 0
                let wait = Double.random(in: 0...6, using: &rng), duration = Double.random(in: 3...6, using: &rng)
                let shimmer = SKAction.sequence([
                    .fadeAlpha(to: alpha, duration: duration), .wait(forDuration: duration), .fadeAlpha(to: alpha * 0.2, duration: duration),
                ])
                node.run(.sequence([.wait(forDuration: wait), .repeatForever(shimmer)]))
                beamLayer.addChild(node)
            }
        }

        if let hex = def?.sun, let color = UIColor(hex: hex) {
            // The sun's glow in the top-left corner, then faint lens rings toward the middle.
            let parts: [(size: CGFloat, alpha: CGFloat, along: CGFloat)] = [(1.1, 0.4, 0), (0.2, 0.1, 0.45), (0.12, 0.08, 0.7), (0.3, 0.05, 1.3)]
            for part in parts {
                let node = Self.soft(color, size: .zero)
                node.alpha = part.alpha
                node.zPosition = 44_500
                sunGlow.addChild(node)
                flare.append((node, part.size, part.along))
            }
        }

        if let hex = def?.haze, let color = UIColor(hex: hex) {
            let node = SKSpriteNode(texture: SoftTextures.fade)
            node.color = color
            node.colorBlendFactor = 1
            node.alpha = CGFloat(def?.hazeAlpha ?? 0.2)
            node.anchorPoint = CGPoint(x: 0.5, y: 1)
            node.zPosition = 44_000
            camera.addChild(node)
            haze = node
        }
    }

    func resize(to size: CGSize) {
        haze?.size = CGSize(width: size.width * 1.2, height: size.height * 0.55)
        haze?.position = CGPoint(x: 0, y: size.height / 2)
        let sun = CGPoint(x: -size.width * 0.42, y: size.height * 0.45)
        for part in flare {
            let side = size.height * part.size
            part.node.size = CGSize(width: side, height: side)
            part.node.position = CGPoint(x: sun.x * (1 - part.along), y: sun.y * (1 - part.along))
        }
    }

    /// How much the sun shines, 0...1: its flare and the sunbeams fade with it.
    func sunlight(_ amount: CGFloat) {
        beamLayer.alpha = amount
        sunGlow.alpha = amount
        beamLayer.isHidden = amount <= 0.01
        sunGlow.isHidden = amount <= 0.01
    }

    // MARK: Per prop

    /// A soft glow behind a glowing prop (crystals, glowing mushrooms, lanterns), gently pulsing.
    /// It sits just behind the prop, so whatever stands in front hides it and whatever stands
    /// behind is lit by it.
    static func glow(behind node: SKSpriteNode, color: UIColor, in world: SKNode, rng: inout SeededRandom) {
        let glow = soft(color, size: CGSize(width: node.size.width * 1.9, height: node.size.width * 1.5))
        glow.position = node.position + CGVector(dx: 0, dy: node.size.height * 0.4)
        glow.zPosition = node.zPosition - 0.5
        let alpha = CGFloat.random(in: 0.3...0.45, using: &rng)
        glow.alpha = alpha
        let duration = Double.random(in: 1.4...2.6, using: &rng)
        glow.run(.repeatForever(.sequence([.fadeAlpha(to: alpha * 0.55, duration: duration), .fadeAlpha(to: alpha, duration: duration)])))
        world.addChild(glow)
    }

    /// A soft shadow on the ground under a tree or rock, a little toward the lower right as if lit
    /// from the upper left. Drawn under everything that stands, so it never covers a character; on
    /// a hill, `above` is the depth of the strip it stands on (`HillArt.strip(at:)`), so it lies on
    /// the hill instead of under it, and `front` where the strip in front begins on screen and its
    /// depth.
    static func shadow(under node: SKSpriteNode, in world: SKNode, above ground: CGFloat? = nil,
                       front: (line: CGFloat, z: CGFloat)? = nil) {
        let width = node.size.width * 0.8
        let size = CGSize(width: width, height: width * 0.36)
        let middle = node.position + CGVector(dx: width * 0.12, dy: -1)
        // Raised ground in front may start under it (`front`, from its line on screen down): the part
        // below that lies on it, so it's sorted with it.
        let bottom = middle.y - size.height / 2
        let cut = front.map { min(1, max(0, ($0.line - bottom) / size.height)) } ?? 0
        let parts: [(from: CGFloat, to: CGFloat, z: CGFloat)] = [(0, cut, front?.z ?? 0), (cut, 1, ground ?? -99_300.1)]
        for part in parts where part.to > part.from {
            let texture = part.from == 0 && part.to == 1
                ? SoftTextures.glow : SKTexture(rect: CGRect(x: 0, y: part.from, width: 1, height: part.to - part.from), in: SoftTextures.glow)
            let shadow = SKSpriteNode(texture: texture, size: CGSize(width: width, height: size.height * (part.to - part.from)))
            shadow.anchorPoint = CGPoint(x: 0.5, y: 0)
            shadow.color = .black
            shadow.colorBlendFactor = 1
            shadow.alpha = 0.3
            shadow.position = CGPoint(x: middle.x, y: bottom + size.height * part.from)
            shadow.zPosition = part.z + 0.1
            world.addChild(shadow)
        }
    }

    // MARK: Ground colour

    /// Big soft patches of colour over the ground, leaning toward the palette's shadow and
    /// highlight colours, so it isn't one flat colour: one pixel per cell, stretched over the map
    /// with smooth filtering. Lives in grid space, next to the ground tile map.
    static func groundVariation(columns: Int, rows: Int, tile: CGFloat, palette: MapPalette?, seed: String) -> SKSpriteNode? {
        let strength = palette?.variation ?? 0.12
        guard strength > 0, columns > 0, rows > 0 else { return nil }
        let dark: (r: Double, g: Double, b: Double) = rgb(palette?.shadow) ?? (r: 0.2, g: 0.22, b: 0.3)
        let light: (r: Double, g: Double, b: Double) = rgb(palette?.highlight) ?? (r: 1, g: 0.95, b: 0.8)
        var rng = SeededRandom(text: seed + "/ground")
        let coarse = Noise(columns: columns, rows: rows, step: 7, rng: &rng)
        let fine = Noise(columns: columns, rows: rows, step: 3, rng: &rng)
        var bytes = [UInt8](repeating: 0, count: columns * rows * 4)
        for row in 0..<rows {
            for col in 0..<columns {
                let n: Double = coarse.value(col, row) * 0.7 + fine.value(col, row) * 0.3
                let lean: Double = (n - 0.5) * 2
                let color = lean < 0 ? dark : light
                let alpha: Double = strength * min(1, abs(lean) * 1.6)
                // Image rows run north to south; grid rows count up from the south.
                let index = ((rows - 1 - row) * columns + col) * 4
                bytes[index] = UInt8(color.r * alpha * 255)
                bytes[index + 1] = UInt8(color.g * alpha * 255)
                bytes[index + 2] = UInt8(color.b * alpha * 255)
                bytes[index + 3] = UInt8(alpha * 255)
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: columns, height: rows, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: columns * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .linear
        let node = SKSpriteNode(texture: texture, size: CGSize(width: CGFloat(columns) * tile, height: CGFloat(rows) * tile))
        node.anchorPoint = .zero
        return node
    }

    /// Smooth random values over the map: a coarse random grid, eased between its points.
    private struct Noise {
        let values: [Double]
        let width: Int
        let step: Int

        init(columns: Int, rows: Int, step: Int, rng: inout SeededRandom) {
            self.step = step
            width = columns / step + 2
            let height = rows / step + 2
            var values: [Double] = []
            for _ in 0..<(width * height) { values.append(Double.random(in: 0...1, using: &rng)) }
            self.values = values
        }

        func value(_ col: Int, _ row: Int) -> Double {
            let gx = col / step, gy = row / step
            let tx = ease(Double(col % step) / Double(step)), ty = ease(Double(row % step) / Double(step))
            let a = values[gy * width + gx], b = values[gy * width + gx + 1]
            let c = values[(gy + 1) * width + gx], d = values[(gy + 1) * width + gx + 1]
            let top: Double = a + (b - a) * tx
            let bottom: Double = c + (d - c) * tx
            return top + (bottom - top) * ty
        }

        private func ease(_ t: Double) -> Double { t * t * (3 - 2 * t) }
    }

    // MARK: Helpers

    private static func soft(_ color: UIColor, size: CGSize) -> SKSpriteNode {
        let node = SKSpriteNode(texture: SoftTextures.glow, size: size)
        node.color = color
        node.colorBlendFactor = 1
        node.blendMode = .add
        return node
    }

    private static func point(in bounds: CGRect, _ rng: inout SeededRandom) -> CGPoint {
        CGPoint(x: CGFloat.random(in: bounds.minX...bounds.maxX, using: &rng), y: CGFloat.random(in: bounds.minY...bounds.maxY, using: &rng))
    }

    private static func pick(_ range: [Double]?, fallback: ClosedRange<CGFloat>, _ rng: inout SeededRandom) -> CGFloat {
        guard let range, range.count == 2, range[0] <= range[1] else { return CGFloat.random(in: fallback, using: &rng) }
        return CGFloat(Double.random(in: range[0]...range[1], using: &rng))
    }

    /// A hex colour ("#RRGGBB") as 0...1 channels.
    static func rgb(_ hex: String?) -> (r: Double, g: Double, b: Double)? {
        guard let hex, let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) else { return nil }
        return (Double((value >> 16) & 255) / 255, Double((value >> 8) & 255) / 255, Double(value & 255) / 255)
    }
}
