import SpriteKit
import UIKit

/// The whimsy layer of a map: drifting petals, fireflies, bubbles or lanterns, butterflies, cloud
/// shadows, a colour mood and a soft vignette. Driven by the `ambience` block in content/maps.json;
/// the animals that live on a map are `Critters`.
final class Ambience {
    private let tint: SKSpriteNode?
    private let vignette: SKSpriteNode?
    /// The drifting particles, and how many each lets go a second at full strength (`setMood`).
    private var emitters: [(node: SKEmitterNode, rate: CGFloat)] = []
    private var tintAlpha: CGFloat = 0
    private var vignetteAlpha: CGFloat = 0

    /// `inside`: brings a point of `bounds` onto the land itself, so its butterflies start there.
    init(_ def: MapDef.Ambience?, world: SKNode, camera: SKCameraNode, bounds: CGRect, seed: String,
         inside: (CGPoint) -> CGPoint = { $0 }) {
        var rng = SeededRandom(text: seed + "/ambience")
        var drifting: [(node: SKEmitterNode, rate: CGFloat)] = []

        // One kind, or several joined with "+" (e.g. "snow+sparkles").
        for kind in (def?.particles ?? "").split(separator: "+").map(String.init) {
            for emitter in Self.emitters(kind) {
                emitter.targetNode = world
                emitter.zPosition = 30_000
                camera.addChild(emitter)
                // Already drifting when you arrive, instead of starting from an empty sky.
                emitter.advanceSimulationTime(TimeInterval(emitter.particleLifetime))
                drifting.append((emitter, emitter.particleBirthRate))
            }
            if kind == "snow" {
                // Big close flakes that move with the camera, rushing past in front of the world.
                let near = Self.nearSnow()
                near.zPosition = 30_500
                camera.addChild(near)
                near.advanceSimulationTime(TimeInterval(near.particleLifetime))
                drifting.append((near, near.particleBirthRate))
            }
        }

        for _ in 0..<(def?.butterflies ?? 0) {
            let point = inside(CGPoint(x: .random(in: bounds.minX...bounds.maxX, using: &rng), y: .random(in: bounds.minY...bounds.maxY, using: &rng)))
            world.addChild(Self.butterfly(at: point, rng: &rng))
        }

        if def?.clouds == true {
            let count = max(3, Int(bounds.width * bounds.height / 1_400_000))
            for _ in 0..<count {
                world.addChild(Self.cloudShadow(bounds: bounds, rng: &rng))
            }
        }

        if let hex = def?.tint, let color = UIColor(hex: hex) {
            let node = SKSpriteNode(color: color, size: CGSize(width: 3000, height: 3000))
            node.alpha = CGFloat(def?.tintAlpha ?? 0.15)
            // Under the time of day's light, as the haze is (`Lighting`): a pale tint over the night
            // washed it out.
            node.zPosition = 42_900
            camera.addChild(node)
            tint = node
        } else {
            tint = nil
        }

        if let strength = def?.vignette, strength > 0 {
            let node = SKSpriteNode(texture: SoftTextures.vignette)
            node.alpha = CGFloat(strength)
            node.zPosition = 46_000
            camera.addChild(node)
            vignette = node
        } else {
            vignette = nil
        }
        emitters = drifting
        tintAlpha = tint?.alpha ?? 0
        vignetteAlpha = vignette?.alpha ?? 0
    }

    func resize(to size: CGSize) {
        vignette?.size = CGSize(width: size.width * 1.15, height: size.height * 1.15)
    }

    /// How much of the map's mood shows, 0...1 (`WorldScene.mood`): its colour and its drifting
    /// particles fade toward a border you can walk across, as the next land's come in beyond it.
    func setMood(_ strength: CGFloat) {
        tint?.alpha = tintAlpha * strength
        vignette?.alpha = vignetteAlpha * strength
        for emitter in emitters { emitter.node.particleBirthRate = emitter.rate * strength }
    }

    /// A few stars twinkling around a point (fairy rings, fountains).
    static func twinkle(around point: CGPoint, radius: CGFloat, count: Int, in parent: SKNode) {
        for index in 0..<count {
            let star = SKSpriteNode(texture: SoftTextures.star, size: CGSize(width: 7, height: 7))
            star.blendMode = .add
            star.position = point + CGVector(dx: .random(in: -radius...radius), dy: .random(in: -radius * 0.6...radius * 0.6) + 10)
            star.zPosition = 24_000
            star.alpha = 0
            let blink = SKAction.sequence([
                .fadeIn(withDuration: 0.5), .wait(forDuration: 0.3), .fadeOut(withDuration: 0.6), .wait(forDuration: .random(in: 0.4...1.4)),
            ])
            star.run(.sequence([.wait(forDuration: Double(index) * 0.35), .repeatForever(blink)]))
            parent.addChild(star)
        }
    }

    // MARK: Particles

    /// The near layer of a snowfall: fewer, bigger, faster flakes in screen space, a little soft.
    static func nearSnow() -> SKEmitterNode {
        let emitter = SKEmitterNode()
        // Out of focus: a plain soft blur, faintly blue so it shows over snow.
        emitter.particleTexture = SoftTextures.glow
        emitter.particleColor = UIColor(red: 0.9, green: 0.94, blue: 1, alpha: 1)
        emitter.particleColorBlendFactor = 1
        emitter.particlePositionRange = CGVector(dx: 1100, dy: 700)
        emitter.position = CGPoint(x: 0, y: 120)
        emitter.particleBirthRate = 5
        emitter.particleLifetime = 8
        emitter.particleLifetimeRange = 2
        emitter.particleSpeed = 55
        emitter.particleSpeedRange = 20
        emitter.emissionAngle = -.pi / 2 - 0.15
        emitter.emissionAngleRange = 0.35
        emitter.xAcceleration = 6
        emitter.particleScale = 0.35
        emitter.particleScaleRange = 0.12
        emitter.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0, 0.8, 0.8, 0], times: [0, 0.1, 0.85, 1])
        return emitter
    }

    /// The emitters for one kind of particle: candy sprinkles come in four colours, the rest in one.
    static func emitters(_ kind: String) -> [SKEmitterNode] {
        guard kind == "sprinkles" else { return particles(kind).map { [$0] } ?? [] }
        let colors = [
            UIColor(red: 1, green: 0.56, blue: 0.78, alpha: 1), UIColor(red: 1, green: 0.89, blue: 0.48, alpha: 1),
            UIColor(red: 0.56, green: 0.89, blue: 0.82, alpha: 1), UIColor(red: 0.66, green: 0.72, blue: 1, alpha: 1),
        ]
        return colors.map { color in
            let emitter = SKEmitterNode()
            emitter.particlePositionRange = CGVector(dx: 1200, dy: 1200)
            emitter.particleTexture = SoftTextures.sprinkle
            emitter.particleColor = color
            emitter.particleColorBlendFactor = 1
            emitter.particleBirthRate = 1.2
            emitter.particleLifetime = 11
            emitter.particleSpeed = 24
            emitter.particleSpeedRange = 10
            emitter.emissionAngle = -.pi * 0.62
            emitter.emissionAngleRange = 0.5
            emitter.yAcceleration = -4
            emitter.particleRotationRange = .pi * 2
            emitter.particleRotationSpeed = 2.2
            emitter.particleScale = 1.6
            emitter.particleScaleRange = 0.4
            emitter.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0, 1, 1, 0], times: [0, 0.1, 0.85, 1])
            emitter.advanceSimulationTime(12)
            return emitter
        }
    }

    private static func particles(_ kind: String) -> SKEmitterNode? {
        let emitter = SKEmitterNode()
        emitter.particlePositionRange = CGVector(dx: 1200, dy: 1200)
        switch kind {
        case "petals", "leaves":
            emitter.particleTexture = kind == "petals" ? SoftTextures.petal : SoftTextures.leaf
            emitter.particleBirthRate = 2.2
            emitter.particleLifetime = 12
            emitter.particleSpeed = 20
            emitter.particleSpeedRange = 10
            emitter.emissionAngle = -.pi * 0.7
            emitter.emissionAngleRange = 0.6
            emitter.xAcceleration = -2
            emitter.yAcceleration = -3
            emitter.particleRotationRange = .pi * 2
            emitter.particleRotationSpeed = 1.4
            emitter.particleScale = 2
            emitter.particleScaleRange = 0.8
            emitter.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0, 0.95, 0.95, 0], times: [0, 0.1, 0.8, 1])
        case "fireflies":
            emitter.particleTexture = SoftTextures.glow
            emitter.particleColor = UIColor(red: 0.8, green: 1, blue: 0.45, alpha: 1)
            emitter.particleColorBlendFactor = 1
            emitter.particleBlendMode = .add
            emitter.particleBirthRate = 4
            emitter.particleLifetime = 7
            emitter.particleLifetimeRange = 3
            emitter.particleSpeed = 9
            emitter.particleSpeedRange = 6
            emitter.emissionAngleRange = .pi * 2
            emitter.particleScale = 0.35
            emitter.particleScaleRange = 0.2
            emitter.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0, 1, 0.2, 1, 0], times: [0, 0.2, 0.5, 0.75, 1])
        case "sparkles":
            emitter.particleTexture = SoftTextures.star
            emitter.particleBlendMode = .add
            emitter.particleBirthRate = 7
            emitter.particleLifetime = 1.6
            emitter.particleLifetimeRange = 0.8
            emitter.particleSpeed = 3
            emitter.emissionAngleRange = .pi * 2
            emitter.particleScale = 1.5
            emitter.particleScaleRange = 1
            emitter.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0, 1, 0], times: [0, 0.4, 1])
        case "snow":
            // Far flakes: small, slow and many, settling with the ground as you walk.
            emitter.particleTexture = SoftTextures.flake
            emitter.particleBirthRate = 40
            emitter.particleLifetime = 12
            emitter.particleLifetimeRange = 4
            emitter.particleSpeed = 24
            emitter.particleSpeedRange = 10
            emitter.emissionAngle = -.pi / 2
            emitter.emissionAngleRange = 0.5
            emitter.xAcceleration = 3
            emitter.particleScale = 0.16
            emitter.particleScaleRange = 0.07
            emitter.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0, 0.95, 0.95, 0], times: [0, 0.1, 0.85, 1])
        case "dust":
            emitter.particleTexture = SoftTextures.glow
            emitter.particleColor = UIColor(red: 1, green: 0.88, blue: 0.62, alpha: 1)
            emitter.particleColorBlendFactor = 1
            emitter.particleBirthRate = 6
            emitter.particleLifetime = 10
            emitter.particleSpeed = 34
            emitter.particleSpeedRange = 14
            emitter.emissionAngle = 0.15
            emitter.emissionAngleRange = 0.3
            emitter.particleScale = 0.16
            emitter.particleScaleRange = 0.1
            emitter.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0, 0.6, 0.6, 0], times: [0, 0.2, 0.8, 1])
        case "motes":
            emitter.particleTexture = SoftTextures.glow
            emitter.particleColor = UIColor(red: 0.55, green: 0.85, blue: 1, alpha: 1)
            emitter.particleColorBlendFactor = 1
            emitter.particleBlendMode = .add
            emitter.particleBirthRate = 3
            emitter.particleLifetime = 9
            emitter.particleLifetimeRange = 3
            emitter.particleSpeed = 6
            emitter.emissionAngle = .pi / 2
            emitter.emissionAngleRange = 1
            emitter.particleScale = 0.3
            emitter.particleScaleRange = 0.15
            emitter.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0, 0.8, 0.3, 0.8, 0], times: [0, 0.25, 0.5, 0.75, 1])
        case "bubbles":
            // Rising from the water, wobbling a little, gone at the top.
            emitter.particleTexture = SoftTextures.bubble
            emitter.particleBirthRate = 2.5
            emitter.particleLifetime = 7
            emitter.particleLifetimeRange = 2
            emitter.particleSpeed = 16
            emitter.particleSpeedRange = 8
            emitter.emissionAngle = .pi / 2
            emitter.emissionAngleRange = 0.5
            emitter.xAcceleration = 1.5
            emitter.particleScale = 1.6
            emitter.particleScaleRange = 0.7
            emitter.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0, 0.8, 0.8, 0], times: [0, 0.15, 0.9, 1])
        case "dandelions":
            // Fluffy seeds riding the breeze.
            emitter.particleTexture = SoftTextures.fluff
            emitter.particleBirthRate = 1.4
            emitter.particleLifetime = 15
            emitter.particleSpeed = 18
            emitter.particleSpeedRange = 8
            emitter.emissionAngle = 0.25
            emitter.emissionAngleRange = 0.5
            emitter.yAcceleration = -0.6
            emitter.particleRotationRange = 0.8
            emitter.particleRotationSpeed = 0.3
            emitter.particleScale = 1.5
            emitter.particleScaleRange = 0.5
            emitter.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0, 0.95, 0.95, 0], times: [0, 0.1, 0.85, 1])
        case "lanterns":
            // Paper lanterns floating up into the night.
            emitter.particleTexture = SoftTextures.lantern
            emitter.particleBirthRate = 0.45
            emitter.particleLifetime = 24
            emitter.particleLifetimeRange = 4
            emitter.particleSpeed = 11
            emitter.particleSpeedRange = 4
            emitter.emissionAngle = .pi / 2
            emitter.emissionAngleRange = 0.35
            emitter.particleScale = 1.8
            emitter.particleScaleRange = 0.6
            emitter.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0, 1, 1, 0], times: [0, 0.1, 0.8, 1])
        case "zzz":
            // Sleepy Z's drifting up and fading.
            emitter.particleTexture = SoftTextures.zee
            emitter.particleColor = UIColor(red: 0.85, green: 0.82, blue: 1, alpha: 1)
            emitter.particleColorBlendFactor = 1
            emitter.particleBirthRate = 0.8
            emitter.particleLifetime = 6
            emitter.particleLifetimeRange = 2
            emitter.particleSpeed = 10
            emitter.particleSpeedRange = 4
            emitter.emissionAngle = .pi / 2 + 0.2
            emitter.emissionAngleRange = 0.4
            emitter.particleRotationRange = 0.4
            emitter.particleScale = 1.4
            emitter.particleScaleRange = 0.4
            emitter.particleScaleSpeed = 0.15
            emitter.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0, 0.9, 0.6, 0], times: [0, 0.2, 0.7, 1])
        case "notes":
            // A music-box tune drifting over the hill.
            emitter.particleTexture = SoftTextures.note
            emitter.particleColor = UIColor(red: 1, green: 0.82, blue: 0.95, alpha: 1)
            emitter.particleColorBlendFactor = 1
            emitter.particleColorGreenRange = 0.3
            emitter.particleColorBlueRange = 0.3
            emitter.particleBirthRate = 1
            emitter.particleLifetime = 7
            emitter.particleLifetimeRange = 2
            emitter.particleSpeed = 12
            emitter.particleSpeedRange = 5
            emitter.emissionAngle = .pi / 2
            emitter.emissionAngleRange = 0.8
            emitter.particleRotationRange = 0.6
            emitter.particleRotationSpeed = 0.4
            emitter.particleScale = 1.5
            emitter.particleScaleRange = 0.4
            emitter.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0, 0.9, 0.9, 0], times: [0, 0.15, 0.75, 1])
        default:
            return nil
        }
        emitter.advanceSimulationTime(12)
        return emitter
    }

    // MARK: Butterflies

    private static func butterfly(at point: CGPoint, rng: inout SeededRandom) -> SKNode {
        let colors: [(name: String, hex: UInt32)] = [("pink", 0xF8BBD0), ("yellow", 0xFFF59D), ("blue", 0xB3E5FC),
                                                     ("lilac", 0xE1BEE7), ("orange", 0xFFCC80)]
        let pick = colors[Int.random(in: 0..<colors.count, using: &rng)]
        let color = PixelColor(pick.hex)
        // As tools/critter_art.py draws it (lit, outlined, a pixel to a pixel like the critters), flapping
        // open, half, closed and back; else as drawn here, 7 × 5, shown three times as big.
        let frames = ["open", "half", "closed", "half"].map { pose in
            CritterArt.drawn("butterfly_\(pick.name)_\(pose)", SoftTextures.butterfly(color: color, open: pose == "open"))
        }
        let drawn = frames[0].size().width > 7
        let sprite = SKSpriteNode(texture: frames[0], size: drawn ? frames[0].size() : CGSize(width: 21, height: 15))
        sprite.position = point
        sprite.zPosition = 25_000
        sprite.run(.repeatForever(.animate(with: frames, timePerFrame: drawn ? 0.06 : 0.11)))

        // A lazy loop that always returns home, so butterflies never drift off the map.
        var moves: [SKAction] = []
        var total = CGVector.zero
        for _ in 0..<5 {
            let step = CGVector(dx: .random(in: -70...70, using: &rng), dy: .random(in: -50...50, using: &rng))
            total = CGVector(dx: total.dx + step.dx, dy: total.dy + step.dy)
            let move = SKAction.moveBy(x: step.dx, y: step.dy, duration: .random(in: 2...4, using: &rng))
            move.timingMode = .easeInEaseOut
            moves.append(move)
        }
        let home = SKAction.moveBy(x: -total.dx, y: -total.dy, duration: 3)
        home.timingMode = .easeInEaseOut
        moves.append(home)
        sprite.run(.repeatForever(.sequence(moves)))
        let bob = SKAction.sequence([.moveBy(x: 0, y: 4, duration: 0.5), .moveBy(x: 0, y: -4, duration: 0.5)])
        sprite.run(.repeatForever(bob))
        return sprite
    }

    // MARK: Clouds

    private static func cloudShadow(bounds: CGRect, rng: inout SeededRandom) -> SKNode {
        let width = CGFloat.random(in: 380...620, using: &rng)
        let cloud = SKSpriteNode(texture: SoftTextures.cloud, size: CGSize(width: width, height: width * 0.45))
        cloud.color = .black
        cloud.colorBlendFactor = 1
        cloud.alpha = 0.1
        cloud.zPosition = 20_000
        let left = bounds.minX - width
        let right = bounds.maxX + width
        let startX = CGFloat.random(in: left...right, using: &rng)
        cloud.position = CGPoint(x: startX, y: .random(in: bounds.minY...bounds.maxY, using: &rng))
        let speed = CGFloat.random(in: 9...16, using: &rng)
        // Drift east, wrap around, repeat.
        let first = SKAction.moveTo(x: right, duration: TimeInterval((right - startX) / speed))
        let loop = SKAction.repeatForever(.sequence([.moveTo(x: left, duration: 0), .moveTo(x: right, duration: TimeInterval((right - left) / speed))]))
        cloud.run(.sequence([first, loop]))
        return cloud
    }
}

/// Small generated textures for effects: soft glows, petals, butterflies, the vignette.
enum SoftTextures {
    static let glow: SKTexture = radial(size: 32, colors: [.white, UIColor(white: 1, alpha: 0)])
    /// A snowflake: white with a pale blue rim, so it still shows against snowy ground.
    static let flake: SKTexture = radial(size: 32, colors: [
        .white, .white, UIColor(red: 0.93, green: 0.96, blue: 1, alpha: 1),
        UIColor(red: 0.62, green: 0.72, blue: 0.88, alpha: 0.6), UIColor(red: 0.62, green: 0.72, blue: 0.88, alpha: 0),
    ])
    static let cloud: SKTexture = radial(size: 128, colors: [.white, UIColor(white: 1, alpha: 0.6), UIColor(white: 1, alpha: 0)])
    static let vignette: SKTexture = radial(size: 256, colors: [UIColor(white: 0, alpha: 0), UIColor(white: 0, alpha: 0), UIColor(white: 0, alpha: 0.9)])
    /// White at the top fading to clear at the bottom (distance haze).
    static let fade: SKTexture = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: 4, height: 128)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let colors = [UIColor.white.cgColor, UIColor(white: 1, alpha: 0.35).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
            let locations: [CGFloat] = [0, 0.45, 1]
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) else { return }
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
        return SKTexture(image: image)
    }()

    static let petal: SKTexture = pixel(width: 3, height: 3) { c in
        c.fill(0, 0, 3, 3, PixelColor(0xF8BBD0))
        c[1, 1] = PixelColor(0xFFE4EE)
        c[0, 0] = .clear
    }

    static let leaf: SKTexture = pixel(width: 4, height: 3) { c in
        c.fill(0, 0, 4, 3, PixelColor(0xFFB74D))
        c[0, 0] = .clear
        c[3, 2] = .clear
        c.fill(0, 1, 4, 1, PixelColor(0xF57C00))
    }

    static let star: SKTexture = pixel(width: 5, height: 5) { c in
        c.fill(2, 0, 1, 5, .white)
        c.fill(0, 2, 5, 1, .white)
    }

    /// A soap bubble: a pale rim and a glint.
    static let bubble: SKTexture = pixel(width: 7, height: 7) { c in
        let rim = PixelColor(0xC9F1FF)
        c.fill(2, 0, 3, 1, rim)
        c.fill(2, 6, 3, 1, rim)
        c.fill(0, 2, 1, 3, rim)
        c.fill(6, 2, 1, 3, rim)
        c[1, 1] = rim
        c[5, 1] = rim
        c[1, 5] = rim
        c[5, 5] = rim
        c[2, 2] = .white
    }

    /// A dandelion seed: a white puff on a little stem.
    static let fluff: SKTexture = pixel(width: 7, height: 7) { c in
        for (x, y) in [(1, 0), (3, 0), (5, 0), (0, 1), (2, 1), (3, 1), (4, 1), (6, 1), (1, 2), (2, 2), (3, 2), (4, 2), (5, 2)] {
            c[x, y] = .white
        }
        c.fill(3, 3, 1, 3, PixelColor(0xD9D2C3))
        c[3, 6] = PixelColor(0x8D6E52)
    }

    /// A candy sprinkle, tinted by its emitter.
    static let sprinkle: SKTexture = pixel(width: 2, height: 4) { c in
        c.fill(0, 0, 2, 4, .white)
    }

    /// A paper lantern glowing warm.
    static let lantern: SKTexture = pixel(width: 5, height: 7) { c in
        c.fill(0, 1, 5, 5, PixelColor(0xFF9E3D))
        c.fill(1, 2, 3, 3, PixelColor(0xFFD27A))
        c[2, 3] = PixelColor(0xFFF4CF)
        c.fill(1, 0, 3, 1, PixelColor(0x7A2E1F))
        c.fill(1, 6, 3, 1, PixelColor(0x7A2E1F))
    }

    /// A "Z" for sleepy places, tinted by its emitter.
    static let zee: SKTexture = pixel(width: 5, height: 5) { c in
        c.fill(0, 0, 5, 1, .white)
        c[3, 1] = .white
        c[2, 2] = .white
        c[1, 3] = .white
        c.fill(0, 4, 5, 1, .white)
    }

    /// A music note, tinted by its emitter.
    static let note: SKTexture = pixel(width: 5, height: 7) { c in
        c.fill(3, 0, 1, 6, .white)
        c[4, 1] = .white
        c[4, 2] = .white
        c.fill(0, 5, 3, 2, .white)
        c[0, 5] = .clear
    }

    static func butterfly(color: PixelColor, open: Bool) -> SKTexture {
        pixel(width: 7, height: 5) { c in
            if open {
                c.fill(0, 0, 3, 3, color)
                c.fill(4, 0, 3, 3, color)
                c.fill(1, 3, 2, 2, color.shaded(0.85))
                c.fill(4, 3, 2, 2, color.shaded(0.85))
            } else {
                c.fill(2, 0, 1, 4, color)
                c.fill(4, 0, 1, 4, color)
            }
            c.fill(3, 0, 1, 5, PixelColor(0x3E2723))
        }
    }

    private static func pixel(width: Int, height: Int, draw: (inout PixelCanvas) -> Void) -> SKTexture {
        var canvas = PixelCanvas(width: width, height: height)
        draw(&canvas)
        return canvas.texture()
    }

    static func radial(size: CGFloat, colors: [UIColor]) -> SKTexture {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { context in
            let cgColors = colors.map(\.cgColor) as CFArray
            let locations: [CGFloat] = colors.indices.map { CGFloat($0) / CGFloat(max(1, colors.count - 1)) }
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: locations) else { return }
            let center = CGPoint(x: size / 2, y: size / 2)
            // Keep the last colour past the edge: otherwise the square's corners stay clear, and the
            // vignette shows as a dark oval with light corners. (Glows end clear, so they don't change.)
            context.cgContext.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: size / 2,
                                                 options: [.drawsAfterEndLocation])
        }
        return SKTexture(image: image)
    }
}

extension UIColor {
    /// "#RRGGBB"
    convenience init?(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
