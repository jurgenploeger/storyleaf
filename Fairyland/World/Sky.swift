import SpriteKit
import UIKit

/// The time of day and the weather over a map. The light follows the game clock (`GameClock`): warm
/// at dawn and dusk, deep blue at night, and the clouds of the weather (`Weather`) dim it further.
/// Settings can switch either off: then it's always midday, or always clear.
/// Rain falls in slanting streaks and rings the ground, a storm adds lightning, fog drifts past in
/// banks, and snow flurries. When the weather turns, the old fades out as the new fades in. A dark
/// map (a cave) has no sky. It lives on the camera, so a battle's backdrop is the map without it.
final class Sky {
    private let shade = SKSpriteNode(color: .white, size: CGSize(width: 3000, height: 3000))
    private let camera: SKCameraNode
    /// The weather's rain, fog or snow, faded with the map's mood (`setMood`).
    private let weatherLayer = SKNode()
    private let map: MapDef
    private let start: Date?
    private(set) var weather: Weather?
    private var layer: SKNode?
    private var color: (r: Double, g: Double, b: Double) = (1, 1, 1)
    private var checkTimer: TimeInterval = 0
    /// Sunlight now, 0 at night to 1 by day, for the sun's flare and sunbeams (`Lighting.sunlight`).
    /// Clouds hide them.
    private(set) var sunlight: CGFloat = 1

    /// The colour the time of day multiplies the map by, at hours of the day, eased between.
    private static let light: [(hour: Double, r: Double, g: Double, b: Double)] = [
        (0, 0.42, 0.47, 0.78),
        (4.5, 0.42, 0.47, 0.78),
        (6, 1, 0.8, 0.76),
        (7.5, 1, 1, 1),
        (16.5, 1, 1, 1),
        (18, 1, 0.78, 0.6),
        (19.5, 0.42, 0.47, 0.78),
        (24, 0.42, 0.47, 0.78),
    ]

    init?(map: MapDef, camera: SKCameraNode, start: Date?) {
        guard map.ambience?.darkness == nil, map.ambience?.weather?.isEmpty != true else { return nil }
        self.map = map
        self.camera = camera
        self.start = start
        shade.blendMode = .multiply
        shade.zPosition = 43_000
        camera.addChild(shade)
        camera.addChild(weatherLayer)
        turn(to: Weather.on(map, since: start), fade: 0)
        color = target()
        apply()
        sunlight = sunGoal()
    }

    /// The hour the light follows: the clock's, or always midday with night and day switched off
    /// in Settings.
    private var hour: Double {
        GameSettings.dayAndNight ? GameClock.hours(since: start).truncatingRemainder(dividingBy: 24) : 12
    }

    /// Where the sun (or the moon) is at this hour: the hills' light and the shadows follow it.
    var sun: Sun { Sun(hour: hour) }

    private func sunGoal() -> CGFloat {
        guard weather?.sunny ?? true else { return 0 }
        let hour = self.hour
        return CGFloat(max(0, min(1, min(hour - 6, 18.5 - hour) / 1.5)))
    }

    func update(_ dt: TimeInterval) {
        checkTimer -= dt
        if checkTimer <= 0 {
            checkTimer = 1
            let now = Weather.on(map, since: start)
            if now != weather { turn(to: now, fade: 5) }
        }
        // Ease toward the light of the hour, so a change of weather dims the map gradually.
        let goal = target()
        let t = dt == 0 ? 1 : min(1, dt / 2.5)
        color = (color.r + (goal.r - color.r) * t, color.g + (goal.g - color.g) * t, color.b + (goal.b - color.b) * t)
        sunlight += (sunGoal() - sunlight) * CGFloat(t)
        apply()
    }

    private func apply() {
        shade.color = UIColor(red: color.r, green: color.g, blue: color.b, alpha: 1)
        // Plain daylight changes nothing; skip drawing it.
        shade.isHidden = color.r > 0.995 && color.g > 0.995 && color.b > 0.995
    }

    private func target() -> (r: Double, g: Double, b: Double) {
        let hour = self.hour
        var day = (r: 1.0, g: 1.0, b: 1.0)
        for (a, b) in zip(Self.light, Self.light.dropFirst()) where hour >= a.hour && hour <= b.hour {
            let t = b.hour > a.hour ? (hour - a.hour) / (b.hour - a.hour) : 0
            let eased = t * t * (3 - 2 * t)
            day = (a.r + (b.r - a.r) * eased, a.g + (b.g - a.g) * eased, a.b + (b.b - a.b) * eased)
            break
        }
        let cloud: (r: Double, g: Double, b: Double) = weather?.shade ?? (1, 1, 1)
        return (day.r * cloud.r, day.g * cloud.g, day.b * cloud.b)
    }

    private func turn(to next: Weather?, fade: TimeInterval) {
        weather = next
        if let old = layer {
            old.run(.sequence([.fadeOut(withDuration: fade), .removeFromParent()]))
        }
        layer = nil
        guard let next, next != .clear, next != .cloudy else { return }
        let node = SKNode()
        for child in Self.nodes(for: next) { node.addChild(child) }
        node.alpha = fade > 0 ? 0 : 1
        weatherLayer.addChild(node)
        if fade > 0 { node.run(.fadeIn(withDuration: fade)) }
        layer = node
    }

    /// How much of the map's weather shows, 0...1 (`WorldScene.mood`): it thins out toward a
    /// border you can walk across, and the next land's comes in beyond it.
    func setMood(_ strength: CGFloat) {
        weatherLayer.alpha = strength
        weatherLayer.isHidden = strength <= 0.01
    }

    /// Walked over a border from under `other`: the light and the clouds' shade go on from where
    /// they were, easing toward this map's own (`update`).
    func carryOn(from other: Sky) {
        color = other.color
        sunlight = other.sunlight
        apply()
    }

    // MARK: Weather

    private static func nodes(for weather: Weather) -> [SKNode] {
        switch weather {
        case .clear, .cloudy: []
        case .rain: [rain(heavy: false), splashes(heavy: false)]
        case .storm: [rain(heavy: true), splashes(heavy: true), lightning()]
        case .fog: fog()
        case .snow: snow()
        }
    }

    /// A flurry: the snow of a snowy map's ambience, far flakes and near ones.
    private static func snow() -> [SKNode] {
        let far = Ambience.emitters("snow")
        far.forEach { $0.zPosition = 30_000 }
        let near = Ambience.nearSnow()
        near.zPosition = 30_500
        for emitter in far + [near] { emitter.advanceSimulationTime(TimeInterval(emitter.particleLifetime)) }
        return far + [near]
    }

    /// Long thin drops slanting down a little to the left, falling fast across the whole screen.
    private static func rain(heavy: Bool) -> SKEmitterNode {
        let emitter = SKEmitterNode()
        emitter.particleTexture = streak
        emitter.particleColor = UIColor(red: 0.78, green: 0.86, blue: 1, alpha: 1)
        emitter.particleColorBlendFactor = 1
        emitter.particlePositionRange = CGVector(dx: 1500, dy: 0)
        emitter.position = CGPoint(x: 80, y: 520)
        emitter.particleBirthRate = heavy ? 260 : 130
        emitter.particleLifetime = 2
        emitter.particleSpeed = heavy ? 640 : 540
        emitter.particleSpeedRange = 80
        emitter.emissionAngle = -.pi / 2 - 0.22
        emitter.particleRotation = -0.22
        emitter.particleScale = 1
        emitter.particleScaleRange = 0.4
        emitter.particleAlpha = heavy ? 0.6 : 0.5
        emitter.particleAlphaRange = 0.2
        emitter.zPosition = 30_000
        emitter.advanceSimulationTime(2)
        return emitter
    }

    /// Little rings opening on the ground where drops land.
    private static func splashes(heavy: Bool) -> SKEmitterNode {
        let emitter = SKEmitterNode()
        emitter.particleTexture = ring
        emitter.particleColor = UIColor(red: 0.85, green: 0.92, blue: 1, alpha: 1)
        emitter.particleColorBlendFactor = 1
        emitter.particlePositionRange = CGVector(dx: 1200, dy: 1800)
        emitter.particleBirthRate = heavy ? 70 : 35
        emitter.particleLifetime = 0.45
        emitter.particleSpeed = 0
        emitter.particleScale = 0.4
        emitter.particleScaleSpeed = 2.2
        emitter.yScale = 0.5
        emitter.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0.55, 0], times: [0, 1])
        emitter.zPosition = 29_000
        emitter.advanceSimulationTime(1)
        return emitter
    }

    /// Now and then the whole sky flashes white, twice in quick succession.
    private static func lightning() -> SKNode {
        let flash = SKSpriteNode(color: UIColor(red: 0.92, green: 0.95, blue: 1, alpha: 1), size: CGSize(width: 3000, height: 3000))
        flash.blendMode = .add
        flash.alpha = 0
        flash.zPosition = 43_500
        let strike = SKAction.sequence([
            .wait(forDuration: 11, withRange: 14),
            .fadeAlpha(to: 0.5, duration: 0.05), .fadeAlpha(to: 0.05, duration: 0.12),
            .fadeAlpha(to: 0.35, duration: 0.05), .fadeAlpha(to: 0, duration: 0.6),
        ])
        flash.run(.repeatForever(strike))
        return flash
    }

    /// Big soft banks of mist drifting slowly across, plus a pale veil over everything.
    private static func fog() -> [SKNode] {
        let veil = SKSpriteNode(color: UIColor(red: 0.86, green: 0.89, blue: 0.93, alpha: 1), size: CGSize(width: 3000, height: 3000))
        veil.alpha = 0.18
        veil.zPosition = 31_000
        var nodes: [SKNode] = [veil]
        for index in 0..<7 {
            let bank = SKSpriteNode(texture: SoftTextures.cloud, size: CGSize(width: .random(in: 420...700), height: .random(in: 160...260)))
            bank.color = UIColor(red: 0.92, green: 0.94, blue: 0.97, alpha: 1)
            bank.colorBlendFactor = 1
            bank.alpha = .random(in: 0.25...0.4)
            bank.zPosition = 31_100
            let y = CGFloat(index) / 6 * 700 - 350 + .random(in: -40...40)
            let x = CGFloat.random(in: -700...700)
            bank.position = CGPoint(x: x, y: y)
            let speed = CGFloat.random(in: 6...14)
            let first = SKAction.moveTo(x: 900, duration: TimeInterval((900 - x) / speed))
            let loop = SKAction.repeatForever(.sequence([.moveTo(x: -900, duration: 0), .moveTo(x: 900, duration: TimeInterval(1800 / speed))]))
            bank.run(.sequence([first, loop]))
            nodes.append(bank)
        }
        return nodes
    }

    /// A raindrop: a thin line, clear at the top and brightest at the bottom.
    private static let streak: SKTexture = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: 2, height: 22)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let colors = [UIColor(white: 1, alpha: 0).cgColor, UIColor.white.cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
        return SKTexture(image: image)
    }()

    /// A splash: a thin white ring.
    private static let ring: SKTexture = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let side: CGFloat = 16
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            context.cgContext.setStrokeColor(UIColor.white.cgColor)
            context.cgContext.setLineWidth(1.5)
            context.cgContext.strokeEllipse(in: CGRect(x: 1, y: 1, width: side - 2, height: side - 2))
        }
        return SKTexture(image: image)
    }()
}
