import SpriteKit
import UIKit

/// Light and depth on a map, from its `ambience` block in content/maps.json: pools of light on the
/// ground, slanting sunbeams, a sun flare at the edge of the screen and distance haze at the top.
/// The beams and the flare follow the sun through the day (`follow(_:)`). Glows around glowing
/// scenery, soft shadows under trees and the ground's colour patches are made per prop and per map
/// by the helpers below.
final class Lighting {
    private var flare: [(node: SKSpriteNode, size: CGFloat, along: CGFloat)] = []
    private var haze: SKSpriteNode?
    /// The sunbeams and the sun's flare, faded together at night and under cloud (`Sky.sunlight`).
    private let beamLayer = SKNode()
    private let sunGlow = SKNode()
    /// Each sunbeam, and how far it leans off the rest.
    private var sunbeams: [(node: SKSpriteNode, lean: CGFloat)] = []
    private var sun = Sun.noon
    private var screen = CGSize.zero

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
                let lean = CGFloat.random(in: -0.08...0.08, using: &rng)
                node.zRotation = Self.tilt(sun) + lean
                sunbeams.append((node, lean))
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
            // The sun's glow at the edge of the screen (`placeFlare`), then faint lens rings toward
            // the middle.
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
        screen = size
        haze?.size = CGSize(width: size.width * 1.2, height: size.height * 0.55)
        haze?.position = CGPoint(x: 0, y: size.height / 2)
        placeFlare()
    }

    /// Turns the sunbeams and moves the sun's flare to where `sun` is.
    func follow(_ sun: Sun) {
        self.sun = sun
        let tilt = Self.tilt(sun)
        for beam in sunbeams { beam.node.zRotation = tilt + beam.lean }
        placeFlare()
    }

    /// The sun's flare at the edge of the screen toward the sun (`Sun.angleOnScreen`): in the top-left
    /// corner at midday, the top in the morning, down the left side in the afternoon, never in
    /// the lower half, where it would wash out the controls.
    private func placeFlare() {
        guard !flare.isEmpty else { return }
        let turned = (sun.angleOnScreen - Sun.noon.angleOnScreen).remainder(dividingBy: 2 * Double.pi)
        let angle = min(Double.pi, max(Double.pi / 12, 0.75 * Double.pi + turned))
        let reach = max(abs(cos(angle)), abs(sin(angle)))
        let edge = CGPoint(x: screen.width * 0.42 * CGFloat(cos(angle) / reach), y: screen.height * 0.45 * CGFloat(sin(angle) / reach))
        for part in flare {
            let side = screen.height * part.size
            part.node.size = CGSize(width: side, height: side)
            part.node.position = CGPoint(x: edge.x * (1 - part.along), y: edge.y * (1 - part.along))
        }
    }

    /// How the sunbeams lean: their tops toward the sun on screen, by a little over half as much,
    /// and never more than about a tenth of a turn. Upright when the light is overhead.
    private static func tilt(_ sun: Sun) -> CGFloat {
        let fromUpright = (sun.angleOnScreen - Double.pi / 2).remainder(dividingBy: 2 * Double.pi)
        return CGFloat(min(0.6, max(-0.6, 0.6 * fromUpright)))
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

    /// A soft shadow on the ground under a tree or rock, cast away from the sun (`fall(from:)`): a
    /// round of shade under it stretched along the ground, short at midday (a little toward the
    /// lower right) and long when the sun is low, round in the soft light as it rises and sets,
    /// fainter by moonlight. Drawn under everything that stands, so it never covers a character.
    final class Shadow {
        /// Where it lies: on flat ground one part, under everything that stands; on a hill one for
        /// the strip it stands on and one for each of the two in front (`HillArt.strip(at:)`), each
        /// sorted with its strip and shown only from where that strip begins on screen up to where
        /// the one behind it does.
        private let parts: [(node: SKSpriteNode, from: CGFloat, to: CGFloat)]
        private let foot: CGPoint
        private let width: CGFloat

        /// `layers`: where each part begins on screen and how deep it's sorted, the strip it stands
        /// on first; none on flat ground.
        init(under node: SKSpriteNode, in world: SKNode, layers: [(from: CGFloat, z: CGFloat)] = []) {
            foot = node.position
            width = node.size.width
            let far: CGFloat = 1_000_000
            let spans = layers.isEmpty ? [(from: -far, z: CGFloat(-99_300.1))] : layers
            var parts: [(node: SKSpriteNode, from: CGFloat, to: CGFloat)] = []
            var to = far
            for (index, span) in spans.enumerated() {
                let from = index == spans.count - 1 ? -far : span.from
                let shadow = SKSpriteNode(texture: SoftTextures.glow)
                shadow.color = .black
                shadow.colorBlendFactor = 1
                shadow.zPosition = span.z + 0.1
                if spans.count > 1 { shadow.shader = Shadow.clip }
                world.addChild(shadow)
                parts.append((shadow, from, to))
                to = from
            }
            self.parts = parts
            fall(from: .noon)
        }

        /// Lays it on the ground away from `sun`: a round a little over half as wide as its scenery,
        /// stretched along the ground the lower the sun (by a quarter of the scenery's width at
        /// midday, at most 1.4 widths), drawn as `WorldMap.project` draws the ground.
        func fall(from sun: Sun) {
            let wide = Double(width)
            let level = (sun.x * sun.x + sun.y * sun.y).squareRoot()
            let length = level > 1e-6 ? min(1.4 * wide, 0.18 * wide * level / sun.z) : 0
            let away = level > 1e-6 ? (x: -sun.x / level, y: -sun.y / level) : (x: 1.0, y: 0.0)
            let along = 0.285 * wide + length / 2, side = 0.285 * wide
            func screen(_ x: Double, _ y: Double) -> (x: Double, y: Double) { (0.70710678 * (x - y), 0.35355339 * (x + y)) }
            let middle = screen(away.x * length / 2, away.y * length / 2)
            // The round's two axes on screen, then the ellipse they make: its axes and turn.
            let u = screen(away.x * along, away.y * along), v = screen(-away.y * side, away.x * side)
            let xx = u.x * u.x + v.x * v.x, yy = u.y * u.y + v.y * v.y, xy = u.x * u.y + v.x * v.y
            let mean = (xx + yy) / 2, spread = (((xx - yy) / 2) * ((xx - yy) / 2) + xy * xy).squareRoot()
            let long = (mean + spread).squareRoot(), short = max(0, mean - spread).squareRoot()
            let turn = 0.5 * atan2(2 * xy, xx - yy)
            let centre = CGPoint(x: foot.x + CGFloat(middle.x), y: foot.y + CGFloat(middle.y))
            let size = CGSize(width: 2 * long, height: 2 * short)
            // How far it reaches up and down the screen from its middle.
            let rising = long * sin(turn), standing = short * cos(turn)
            let reach = CGFloat((rising * rising + standing * standing).squareRoot())
            for part in parts {
                part.node.isHidden = centre.y + reach < part.from || centre.y - reach >= part.to
                guard !part.node.isHidden else { continue }
                part.node.position = centre
                part.node.size = size
                part.node.zRotation = CGFloat(turn)
                part.node.alpha = 0.3 * CGFloat(sun.strength)
                guard part.node.shader != nil else { continue }
                let clip = SIMD4(Float(size.width * CGFloat(sin(turn))), Float(size.height * CGFloat(cos(turn))),
                                 Float(part.from - centre.y), Float(part.to - centre.y))
                part.node.setValue(SKAttributeValue(vectorFloat4: clip), forAttribute: "a_clip")
            }
        }

        /// Shows only the part of a shadow from one height on screen to another (`a_clip`: its width
        /// times the sine of its turn, its height times the cosine, then the two heights, all from
        /// its middle).
        private static let clip: SKShader = {
            let shader = SKShader(source: """
            void main() {
                float up = (v_tex_coord.x - 0.5) * a_clip.x + (v_tex_coord.y - 0.5) * a_clip.y;
                if (up < a_clip.z || up >= a_clip.w) {
                    gl_FragColor = vec4(0.0);
                } else {
                    gl_FragColor = SKDefaultShading();
                }
            }
            """)
            shader.attributes = [SKAttribute(name: "a_clip", type: .vectorFloat4)]
            return shader
        }()
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
