import SpriteKit

/// Little animals living on a map (`ambience.critters`): bunnies in the meadows, frogs by the
/// ponds, crabs on the beach, songbirds and chicks pecking about, squirrels in the woods, lizards in
/// the sand and mice in the caves; in the darker, harder places crows, spiders, red-eyed rats,
/// scorpions and will-o'-wisps. They sit about near home, hop now and then, and hop off when you
/// come close; a songbird or crow flies away instead, and lands back home once you've gone. Now and
/// then a flock (`ambience.birds`) crosses the sky, its shadows sweeping over the ground.
final class Critters {
    private final class Critter {
        let node = SKNode()
        let body: SKSpriteNode
        /// Sitting, then mid-hop (a crab's claws down, then up).
        let frames: [SKTexture]
        /// Head down to peck at the ground, now and then while it rests (songbirds, chicks).
        let peck: SKTexture?
        /// Wings spread: it flies off when you come close instead of hopping (songbirds).
        let flight: SKTexture?
        let shadow: SKSpriteNode
        let home: CGPoint
        /// How far it floats over its shadow (a wisp), bobbing.
        let hover: CGFloat
        /// How far one hop goes, how high it jumps (0 for a scuttle) and how long it takes.
        let reach: CGFloat
        let height: CGFloat
        let time: TimeInterval
        /// Seconds until it fancies another hop, and until the hop it's in lands.
        var rest: TimeInterval
        var busy: TimeInterval = 0
        /// Seconds until a bird that flew off comes back.
        var away: TimeInterval = 0

        /// `scale` sizes the whole critter (a crow is a big songbird); `hover` floats it above its
        /// shadow, bobbing, in a soft glow of `glow` (a wisp).
        init(frames: [SKTexture], peck: SKTexture? = nil, flight: SKTexture? = nil, at point: CGPoint,
             reach: CGFloat, height: CGFloat, time: TimeInterval, rest: TimeInterval,
             scale: CGFloat = 1, hover: CGFloat = 0, glow: UIColor? = nil) {
            self.frames = frames
            self.peck = peck
            self.flight = flight
            self.reach = reach
            self.height = height
            self.time = time
            self.rest = rest
            self.hover = hover
            home = point
            let body = SKSpriteNode(texture: frames[0])
            self.body = body
            shadow = SKSpriteNode(texture: SoftTextures.glow, size: CGSize(width: body.size.width * 0.9, height: 5))
            body.anchorPoint = CGPoint(x: 0.5, y: 0.1)
            body.zPosition = 0.5
            shadow.color = .black
            shadow.colorBlendFactor = 1
            shadow.alpha = 0.3
            shadow.zPosition = -0.5
            node.addChild(shadow)
            node.addChild(body)
            node.position = point
            node.setScale(scale)
            if hover > 0 {
                shadow.alpha = 0.15
                body.position.y = hover
                let bob = SKAction.moveBy(x: 0, y: 4, duration: 1.1)
                bob.timingMode = .easeInEaseOut
                body.run(.repeatForever(.sequence([bob, bob.reversed()])), withKey: "bob")
                if frames.count > 1 {
                    body.run(.repeatForever(.animate(with: frames, timePerFrame: 0.22)), withKey: "flicker")
                }
            }
            if let glow {
                let light = SKSpriteNode(texture: SoftTextures.glow, size: CGSize(width: 44, height: 44))
                light.color = glow
                light.colorBlendFactor = 1
                light.blendMode = .add
                light.alpha = 0.55
                light.zPosition = -0.1
                light.position = CGPoint(x: 0, y: body.size.height * 0.45)
                body.addChild(light)
            }
        }
    }

    private let world: SKNode
    private var critters: [Critter] = []
    /// How high the ground lies under a spot on screen (`WorldMap.height(at:)`): on a hill, or down
    /// the shore's slope (`WorldMap.shore`), they sit on it.
    private let ground: (CGPoint) -> CGFloat
    private let birds: String?
    private var untilFlock: TimeInterval

    init(_ def: MapDef.Ambience?, world: SKNode, map: WorldMap, seed: String) {
        self.world = world
        ground = { map.height(at: $0) }
        birds = def?.birds
        var rng = SeededRandom(text: seed + "/critters")
        untilFlock = .random(in: 4...10, using: &rng)
        let water = map.ponds.flatMap { $0 }
        for group in def?.critters ?? [] {
            for _ in 0..<max(0, group.count) {
                guard let cell = Self.home(for: group.kind, map: map, water: water, rng: &rng),
                      let critter = Self.make(group.kind, at: map.base(of: cell), rng: &rng) else { continue }
                critter.node.zPosition = -critter.node.position.y
                // Up (or down) on the ground there.
                let lift = height(of: critter, at: critter.node.position)
                critter.body.position.y += lift
                critter.shadow.position.y = lift
                world.addChild(critter.node)
                critters.append(critter)
            }
        }
    }

    /// Critters hop about, and away from `player`; now and then a flock sets off across `visible`.
    /// `flocks`: whether its birds cross the sky: only the land you're in sends them over, or a
    /// cave's bats flew over the desert next to it (playtesting 2026-10-21: "There are bats flying in
    /// genie desert and other maps, which is weird").
    func update(dt: TimeInterval, player: CGPoint, visible: CGRect, flocks: Bool = true, canStand: (CGPoint) -> Bool) {
        for critter in critters {
            if critter.away > 0 {
                critter.away -= dt
                // It comes back once you've moved on from its spot.
                if critter.away <= 0 {
                    if critter.home.distance(to: player) > 140 { land(critter) } else { critter.away = 3 }
                }
                continue
            }
            critter.busy -= dt
            critter.rest -= dt
            critter.node.zPosition = -critter.node.position.y
            guard critter.busy <= 0 else { continue }
            let away = critter.node.position - player
            if away.length < 64 {
                // Too close: off it goes, away from you.
                let direction = away.length > 0 ? away.normalized : CGVector(dx: 1, dy: 0)
                if critter.flight != nil {
                    flyOff(critter, along: direction)
                } else {
                    hop(critter, along: direction, running: true, canStand: canStand)
                }
            } else if critter.rest <= 0 {
                critter.rest = .random(in: 1.2...5)
                if let peck = critter.peck, Bool.random() {
                    // A peck or two at the ground instead of a hop.
                    let still = critter.frames[0]
                    let once = SKAction.sequence([.setTexture(peck), .wait(forDuration: 0.16), .setTexture(still), .wait(forDuration: 0.12)])
                    critter.body.run(.repeat(once, count: Int.random(in: 1...3)), withKey: "hop")
                    critter.busy = 0.9
                    continue
                }
                // A wander, drifting back home once it has strayed.
                let homeward = critter.home - critter.node.position
                let angle = CGFloat.random(in: 0..<(2 * CGFloat.pi))
                let direction = homeward.length > 90 ? homeward.normalized : CGVector(dx: cos(angle), dy: sin(angle) * 0.6)
                hop(critter, along: direction, running: false, canStand: canStand)
            }
        }
        guard birds != nil, flocks else { return }
        untilFlock -= dt
        if untilFlock <= 0 {
            untilFlock = .random(in: 16...34)
            launchFlock(across: visible)
        }
    }

    // MARK: Critters

    /// How high the ground lies under `point`, in `critter`'s own units (it's scaled).
    private func height(of critter: Critter, at point: CGPoint) -> CGFloat {
        ground(point) / max(critter.node.yScale, 0.01)
    }

    /// Where one lives: frogs and crabs by the water, the rest anywhere in the open.
    private static func home(for kind: String, map: WorldMap, water: [GridPoint], rng: inout SeededRandom) -> GridPoint? {
        if kind == "frog" || kind == "crab", !water.isEmpty {
            for _ in 0..<30 {
                let pond = water[Int.random(in: 0..<water.count, using: &rng)]
                let cell = GridPoint(col: pond.col + Int.random(in: -2...2, using: &rng), row: pond.row + Int.random(in: -2...2, using: &rng))
                if map.isFreeForScenery(cell, blocking: false) { return cell }
            }
        }
        return map.randomFreeCell(blocking: false, using: &rng)
    }

    private static func make(_ kind: String, at point: CGPoint, rng: inout SeededRandom) -> Critter? {
        switch kind {
        case "bunny":
            let furs: [(name: String, fur: UInt32, light: UInt32, dark: UInt32)] = [
                ("brown", 0xB98A62, 0xE2C29F, 0x7D5A3F), ("cream", 0xEDDCC2, 0xFFF6E8, 0xB8A386),
                ("grey", 0xA9A9B0, 0xD8D8DE, 0x707078), ("white", 0xF4F4F4, 0xFFFFFF, 0xC0C0C8),
            ]
            let coat = furs[Int.random(in: 0..<furs.count, using: &rng)]
            let frames = [false, true].map { hop in
                CritterArt.drawn("bunny_\(coat.name)_\(hop ? "hop" : "sit")",
                                 CritterArt.bunny(fur: PixelColor(coat.fur), light: PixelColor(coat.light), dark: PixelColor(coat.dark), hop: hop))
            }
            return Critter(frames: frames, at: point, reach: 26, height: 7, time: 0.3, rest: .random(in: 0.5...4, using: &rng))
        case "frog":
            return Critter(frames: [CritterArt.drawn("frog_sit", CritterArt.frog(hop: false)),
                                    CritterArt.drawn("frog_hop", CritterArt.frog(hop: true))], at: point,
                           reach: 34, height: 9, time: 0.34, rest: .random(in: 1...6, using: &rng))
        case "crab":
            return Critter(frames: [CritterArt.drawn("crab_down", CritterArt.crab(up: false)),
                                    CritterArt.drawn("crab_up", CritterArt.crab(up: true))], at: point,
                           reach: 22, height: 0, time: 0.5, rest: .random(in: 0.5...4, using: &rng))
        case "songbird":
            // A robin, a bluebird or a finch.
            let plumes: [(name: String, back: UInt32, breast: UInt32, wing: UInt32)] = [
                ("robin", 0x8A6248, 0xE8834A, 0x6B4A36), ("bluebird", 0x4F7FC8, 0xE8A06A, 0x3A5E9A), ("finch", 0xD9B23A, 0xF4DA74, 0x7A6028),
            ]
            let plume = plumes[Int.random(in: 0..<plumes.count, using: &rng)]
            func draw(_ pose: CritterArt.BirdPose) -> SKTexture {
                CritterArt.drawn("songbird_\(plume.name)_\(pose)",
                                 CritterArt.songbird(pose, back: PixelColor(plume.back), breast: PixelColor(plume.breast), wing: PixelColor(plume.wing)))
            }
            return Critter(frames: [draw(.sit), draw(.hop)], peck: draw(.peck), flight: draw(.fly), at: point,
                           reach: 14, height: 4, time: 0.18, rest: .random(in: 0.5...3, using: &rng))
        case "crow":
            // A songbird's shape, bigger, in black with a red eye.
            func draw(_ pose: CritterArt.BirdPose) -> SKTexture {
                CritterArt.drawn("crow_\(pose)",
                                 CritterArt.songbird(pose, back: PixelColor(0x2E2C3A), breast: PixelColor(0x3C3A4C), wing: PixelColor(0x211F2C),
                                                     beak: PixelColor(0x6E6A78), eye: PixelColor(0xFF4A4A), outline: PixelColor(0x15121C), longBeak: true))
            }
            return Critter(frames: [draw(.sit), draw(.hop)], peck: draw(.peck), flight: draw(.fly), at: point,
                           reach: 16, height: 5, time: 0.22, rest: .random(in: 0.5...3, using: &rng), scale: 1.25)
        case "spider":
            return Critter(frames: [CritterArt.drawn("spider_a", CritterArt.spider(step: false)),
                                    CritterArt.drawn("spider_b", CritterArt.spider(step: true))], at: point,
                           reach: 22, height: 0, time: 0.3, rest: .random(in: 0.5...4, using: &rng))
        case "rat":
            return Critter(frames: [CritterArt.drawn("rat_a", CritterArt.rat(step: false)),
                                    CritterArt.drawn("rat_b", CritterArt.rat(step: true))], at: point,
                           reach: 26, height: 0, time: 0.3, rest: .random(in: 0.5...3, using: &rng))
        case "scorpion":
            return Critter(frames: [CritterArt.drawn("scorpion_a", CritterArt.scorpion(step: false)),
                                    CritterArt.drawn("scorpion_b", CritterArt.scorpion(step: true))], at: point,
                           reach: 18, height: 0, time: 0.45, rest: .random(in: 1...5, using: &rng))
        case "wisp":
            // Drifts slowly instead of hopping, floating and flickering.
            return Critter(frames: [CritterArt.drawn("wisp_a", CritterArt.wisp(flicker: false)),
                                    CritterArt.drawn("wisp_b", CritterArt.wisp(flicker: true))], at: point,
                           reach: 20, height: 0, time: 1.1, rest: .random(in: 1...4, using: &rng),
                           hover: 14, glow: UIColor(red: 0.45, green: 0.85, blue: 1, alpha: 1))
        case "chick":
            return Critter(frames: [CritterArt.drawn("chick_sit", CritterArt.chick(.sit)), CritterArt.drawn("chick_hop", CritterArt.chick(.hop))],
                           peck: CritterArt.drawn("chick_peck", CritterArt.chick(.peck)), at: point,
                           reach: 10, height: 3, time: 0.2, rest: .random(in: 0.5...3, using: &rng))
        case "squirrel":
            return Critter(frames: [CritterArt.drawn("squirrel_sit", CritterArt.squirrel(hop: false)),
                                    CritterArt.drawn("squirrel_hop", CritterArt.squirrel(hop: true))], at: point,
                           reach: 30, height: 8, time: 0.28, rest: .random(in: 0.5...4, using: &rng))
        case "lizard":
            return Critter(frames: [CritterArt.drawn("lizard_a", CritterArt.lizard(step: false)),
                                    CritterArt.drawn("lizard_b", CritterArt.lizard(step: true))], at: point,
                           reach: 26, height: 0, time: 0.35, rest: .random(in: 1...5, using: &rng))
        case "mouse":
            return Critter(frames: [CritterArt.drawn("mouse_a", CritterArt.mouse(step: false)),
                                    CritterArt.drawn("mouse_b", CritterArt.mouse(step: true))], at: point,
                           reach: 20, height: 0, time: 0.3, rest: .random(in: 0.5...4, using: &rng))
        default:
            return nil
        }
    }

    /// One hop (or scuttle) along `direction`, turning aside if that way is blocked; it stays put
    /// if every way is.
    private func hop(_ critter: Critter, along direction: CGVector, running: Bool, canStand: (CGPoint) -> Bool) {
        let start = critter.node.position
        let length = critter.reach * (running ? 1.4 : CGFloat.random(in: 0.6...1))
        let time = critter.time * (running ? 0.8 : 1)
        for turn in [0, 0.6, -0.6, 1.2, -1.2] as [CGFloat] {
            let way = CGVector(dx: direction.dx * cos(turn) - direction.dy * sin(turn),
                               dy: direction.dx * sin(turn) + direction.dy * cos(turn))
            let target = start + way * length
            guard canStand(target), canStand(start + way * (length / 2)) else { continue }
            let move = SKAction.move(to: target, duration: time)
            move.timingMode = .easeInEaseOut
            critter.node.run(move, withKey: "hop")
            if way.dx != 0 { critter.body.xScale = way.dx < 0 ? -1 : 1 }
            // Onto the ground where it lands, up a hill or down the shore.
            let from = height(of: critter, at: start), lands = height(of: critter, at: target)
            critter.shadow.run(.moveTo(y: lands, duration: time), withKey: "hop")
            if critter.height > 0 {
                let up = SKAction.moveTo(y: max(from, lands) + critter.height, duration: time / 2)
                up.timingMode = .easeOut
                let down = SKAction.moveTo(y: lands, duration: time / 2)
                down.timingMode = .easeIn
                critter.body.run(.group([
                    .sequence([up, down]),
                    .sequence([.setTexture(critter.frames[1]), .wait(forDuration: time), .setTexture(critter.frames[0])]),
                ]), withKey: "hop")
            } else {
                // A crab scuttles, claws clacking as it goes; a lizard or mouse patters along.
                let clack = SKAction.animate(with: critter.frames, timePerFrame: 0.08)
                critter.body.run(.group([
                    .sequence([.repeat(clack, count: max(1, Int(time / 0.16))), .setTexture(critter.frames[0])]),
                    .moveBy(x: 0, y: lands - from, duration: time),
                ]), withKey: "hop")
            }
            critter.busy = time + (running ? 0.05 : 0.25)
            return
        }
    }

    /// A songbird takes off: up and away over the trees, fading out of sight.
    private func flyOff(_ critter: Critter, along direction: CGVector) {
        guard let flight = critter.flight else { return }
        critter.node.removeAction(forKey: "hop")
        critter.body.removeAction(forKey: "hop")
        let side: CGFloat = direction.dx < 0 ? -1 : 1
        critter.body.xScale = side
        critter.body.zPosition = 30_000
        let flap = SKAction.animate(with: [flight, critter.frames[1]], timePerFrame: 0.08)
        let rise = SKAction.moveBy(x: side * 140, y: 170, duration: 1.1)
        rise.timingMode = .easeIn
        critter.body.run(.group([
            .repeat(flap, count: 7), rise, .sequence([.wait(forDuration: 0.6), .fadeOut(withDuration: 0.5)]),
        ]), withKey: "hop")
        critter.shadow.run(.fadeOut(withDuration: 0.4))
        critter.away = .random(in: 8...16)
    }

    /// Back home, gliding down from the sky.
    private func land(_ critter: Critter) {
        guard let flight = critter.flight else { return }
        critter.body.removeAllActions()
        critter.node.position = critter.home
        critter.node.zPosition = -critter.home.y
        let side: CGFloat = Bool.random() ? 1 : -1
        critter.body.xScale = side
        let lift = height(of: critter, at: critter.home)
        critter.body.position = CGPoint(x: -side * 70, y: 110 + lift)
        critter.body.texture = flight
        critter.shadow.position.y = lift
        let glide = SKAction.move(to: CGPoint(x: 0, y: lift + critter.hover), duration: 0.9)
        glide.timingMode = .easeOut
        let flap = SKAction.animate(with: [flight, critter.frames[1]], timePerFrame: 0.1)
        critter.body.run(.sequence([
            .group([.fadeIn(withDuration: 0.3), glide, .repeat(flap, count: 4)]),
            .setTexture(critter.frames[0]),
            .run { critter.body.zPosition = 0.5 },
        ]), withKey: "hop")
        critter.shadow.run(.fadeAlpha(to: 0.3, duration: 0.9))
        critter.busy = 1.2
        critter.rest = .random(in: 1...3)
    }

    // MARK: Birds

    /// A few birds (gulls, bats) crossing the screen, with their shadows far below on the ground.
    private func launchFlock(across visible: CGRect) {
        guard let kind = birds else { return }
        let fromLeft = Bool.random()
        let count = kind == "gulls" ? Int.random(in: 1...3) : Int.random(in: 3...6)
        let speed: CGFloat = kind == "gulls" ? 55 : (kind == "bats" ? 85 : 95)
        let y = visible.minY + visible.height * CGFloat.random(in: 0.5...0.9)
        let startX = fromLeft ? visible.minX - 60 : visible.maxX + 60
        let endX = fromLeft ? visible.maxX + 160 : visible.minX - 160
        let path = SKAction.moveBy(x: endX - startX, y: CGFloat.random(in: -60...60), duration: TimeInterval(abs(endX - startX) / speed))
        let frames = [CritterArt.drawn("flock_\(kind)_up", CritterArt.bird(kind, up: true)),
                      CritterArt.drawn("flock_\(kind)_down", CritterArt.bird(kind, up: false))]
        for index in 0..<count {
            // A loose V behind the leader.
            let back = CGFloat(index) * 16 * (fromLeft ? -1 : 1)
            let side = CGFloat(index % 2 == 0 ? 1 : -1) * CGFloat((index + 1) / 2) * 9
            let start = CGPoint(x: startX + back, y: y + side)
            let bird = SKSpriteNode(texture: frames[0])
            bird.xScale = fromLeft ? 2 : -2
            bird.yScale = 2
            bird.position = start
            bird.zPosition = 33_000
            bird.run(.repeatForever(.animate(with: frames, timePerFrame: kind == "gulls" ? 0.24 : 0.1)), withKey: "flap")
            if kind == "bats" {
                let flutter = SKAction.moveBy(x: 0, y: 6, duration: 0.25)
                bird.run(.repeatForever(.sequence([flutter, flutter.reversed()])), withKey: "flutter")
            }
            bird.run(.sequence([path, .removeFromParent()]), withKey: "fly")
            world.addChild(bird)
            let shadow = SKSpriteNode(texture: SoftTextures.glow, size: CGSize(width: bird.size.width * 1.2, height: 6))
            shadow.color = .black
            shadow.colorBlendFactor = 1
            shadow.alpha = 0.12
            shadow.zPosition = 20_000
            shadow.position = start + CGVector(dx: 0, dy: -150)
            shadow.run(.sequence([path, .removeFromParent()]), withKey: "fly")
            world.addChild(shadow)
        }
    }
}

/// The critters' and birds' pixel art, drawn facing right.
enum CritterArt {
    private static let ink = PixelColor(0x3B2A22)

    enum BirdPose { case sit, hop, peck, fly }

    /// A critter as tools/critter_art.py draws it (art/sprites/critter_<name>.png: lit from the top
    /// left, outlined in a deep shade of each part), else as it's drawn here.
    static func drawn(_ name: String, _ fallback: @autoclosure () -> SKTexture) -> SKTexture {
        guard let image = ArtLibrary.shared.artImage("critter_" + name)?.cgImage else { return fallback() }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .nearest
        return texture
    }

    /// A little songbird on the ground: sitting, mid-hop (legs tucked), pecking, or taking off.
    /// A crow is drawn the same way, black, with a red `eye` and a longer grey beak.
    static func songbird(_ pose: BirdPose, back: PixelColor, breast: PixelColor, wing: PixelColor,
                         beak: PixelColor = PixelColor(0xF2B33D), eye: PixelColor? = nil, outline: PixelColor? = nil,
                         longBeak: Bool = false) -> SKTexture {
        let leg = longBeak ? beak : PixelColor(0xC08A50)
        let eye = eye ?? ink, outline = outline ?? ink
        var c = PixelCanvas(width: 11, height: 10)
        switch pose {
        case .fly:
            c.ellipse(5.5, 6.2, 3.0, 1.6, back)
            c.ellipse(6.8, 6.8, 1.6, 1.0, breast)
            c.ellipse(8.4, 5.0, 1.8, 1.7, back)
            c[9, 4] = eye
            c[10, 5] = beak
            for (y, from, to) in [(1, 4, 5), (2, 3, 6), (3, 3, 6), (4, 4, 6)] { c.fill(from, y, to - from + 1, 1, wing) }
            c.fill(0, 6, 3, 1, wing)
        case .peck:
            c.ellipse(4.6, 5.6, 3.4, 2.5, back)
            c.ellipse(6.4, 6.4, 1.8, 1.7, breast)
            c.ellipse(3.8, 5.2, 2.2, 1.3, wing)
            c.ellipse(8.2, 6.8, 2.1, 2.0, back)
            c[8, 6] = eye
            c[10, 8] = beak
            c[0, 3] = wing
            c[1, 4] = wing
            c[0, 4] = wing
            c[5, 9] = leg
            c[7, 9] = leg
        case .sit, .hop:
            c.ellipse(4.8, 6.2, 3.4, 2.6, back)
            c.ellipse(6.6, 6.4, 1.8, 1.9, breast)
            c.ellipse(8.2, 5.0, 1.2, 1.0, breast)
            c.ellipse(7.6, 3.6, 2.3, 2.2, back)
            c.ellipse(4.0, 5.8, 2.2, 1.3, wing)
            c[8, 3] = eye
            c[10, 4] = beak
            if longBeak { c[9, 4] = beak }
            c[0, 4] = wing
            c[0, 5] = wing
            c[1, 5] = wing
            if pose == .sit {
                c[5, 9] = leg
                c[7, 9] = leg
            }
        }
        c.outline(outline)
        return c.texture()
    }

    /// A fluffy yellow chick: sitting, mid-hop, or pecking.
    static func chick(_ pose: BirdPose) -> SKTexture {
        let body = PixelColor(0xFFD84A), wing = PixelColor(0xF0B830), beak = PixelColor(0xF08A30)
        var c = PixelCanvas(width: 9, height: 9)
        if pose == .peck {
            c.ellipse(3.6, 4.6, 3.2, 2.6, body)
            c.ellipse(6.0, 5.6, 1.8, 1.6, body)
            c.ellipse(2.8, 4.6, 1.6, 1.0, wing)
            c[6, 5] = ink
            c[8, 6] = beak
            c[3, 8] = beak
            c[5, 8] = beak
        } else {
            c.ellipse(3.8, 5.0, 3.2, 2.8, body)
            c.ellipse(5.4, 3.0, 1.9, 1.8, body)
            c.ellipse(3.0, 5.2, 1.6, 1.0, wing)
            c[5, 2] = ink
            c[7, 3] = beak
            if pose == .sit {
                c[3, 8] = beak
                c[5, 8] = beak
            }
        }
        c.outline(PixelColor(0x8A5A1A))
        return c.texture()
    }

    /// A red squirrel, its bushy tail curled up behind it (stretched out mid-hop).
    static func squirrel(hop: Bool) -> SKTexture {
        let fur = PixelColor(0xB5652F), tail = PixelColor(0xC0703A), tip = PixelColor(0xE39C5E)
        let belly = PixelColor(0xF0D2A8), dark = PixelColor(0x7A3F1C)
        var c = PixelCanvas(width: 15, height: 13)
        if hop {
            c.ellipse(3.0, 7.0, 3.2, 2.6, tail)
            c.ellipse(1.8, 6.0, 1.6, 1.4, tip)
            c.ellipse(8.0, 8.4, 3.8, 2.4, fur)
            c.ellipse(9.0, 9.4, 2.0, 1.2, belly)
            c.ellipse(11.8, 6.0, 2.4, 2.1, fur)
            c.fill(11, 2, 2, 2, fur)
            c[12, 5] = ink
            c[14, 6] = dark
            c.fill(4, 11, 2, 1, dark)
            c.fill(12, 10, 2, 1, dark)
        } else {
            c.ellipse(3.2, 5.0, 3.0, 4.2, tail)
            c.ellipse(2.4, 3.2, 1.8, 2.0, tip)
            c.ellipse(8.2, 9.0, 3.4, 3.0, fur)
            c.ellipse(9.4, 9.8, 1.6, 1.8, belly)
            c.ellipse(10.8, 5.6, 2.4, 2.2, fur)
            c.fill(10, 2, 2, 2, fur)
            c[11, 5] = ink
            c[13, 6] = dark
            c.fill(7, 12, 2, 1, dark)
            c.fill(10, 12, 2, 1, dark)
        }
        c.outline(ink)
        return c.texture()
    }

    /// A sandy desert lizard seen from above, legs splayed, mid-stride one way or the other.
    static func lizard(step: Bool) -> SKTexture {
        let body = PixelColor(0xD2A85A), spot = PixelColor(0x9A6A30)
        var c = PixelCanvas(width: 17, height: 9)
        c.ellipse(8.5, 4.5, 4.0, 1.8, body)
        c.ellipse(13.6, 4.2, 2.4, 1.6, body)
        c.fill(3, 4, 2, 2, body)
        c.fill(1, 5, 2, 1, body)
        c[0, 6] = body
        c[7, 4] = spot
        c[9, 3] = spot
        c[10, 5] = spot
        c[14, 3] = ink
        let legs = step ? [(11, 2), (12, 1), (6, 6), (5, 7), (11, 6), (12, 7), (6, 2), (5, 1)]
            : [(11, 2), (10, 1), (6, 6), (7, 7), (11, 6), (10, 7), (6, 2), (7, 1)]
        for (x, y) in legs { c[x, y] = spot }
        c.outline(PixelColor(0x5A3A18))
        return c.texture()
    }

    /// A black spider with a purple sheen and red eyes, its legs bent above and below it; the
    /// pairs lift in turn as it runs.
    static func spider(step: Bool) -> SKTexture {
        let body = PixelColor(0x2A2233), sheen = PixelColor(0x5A3F78), leg = PixelColor(0x1C1724), eye = PixelColor(0xFF4040)
        var c = PixelCanvas(width: 16, height: 12)
        c.ellipse(6.2, 5.6, 3.4, 2.6, body)
        c.ellipse(5.4, 4.6, 1.6, 0.9, sheen)
        c.ellipse(10.6, 5.8, 2.0, 1.8, body)
        c[11, 5] = eye
        c[12, 5] = eye
        c[12, 6] = eye
        c.outline(PixelColor(0x0E0B12))
        // Legs go on after the outline, so they stay thin: hip, a step out, knee, foot.
        for (index, (x, dx)) in [(5, -2), (7, -1), (9, 1), (11, 2)].enumerated() {
            let lift = (index % 2 == 0) == step ? 1 : 0
            for (sign, hip) in [(-1, 4), (1, 7)] {
                let points = [(x, hip), (x + dx.signum(), hip + sign), (x + dx, hip + sign * (3 - lift)),
                              (x + 2 * dx, hip + sign * (2 - lift) + sign * 2)]
                for (px, py) in points { c[px, py] = leg }
            }
        }
        return c.texture()
    }

    /// A grey-brown rat with red eyes and a long pink tail, feet pattering.
    static func rat(step: Bool) -> SKTexture {
        let fur = PixelColor(0x6E5E54), belly = PixelColor(0x9A8A7C), pink = PixelColor(0xD99AA4), eye = PixelColor(0xFF3A3A)
        var c = PixelCanvas(width: 17, height: 8)
        c.ellipse(7.0, 4.6, 4.4, 2.6, fur)
        c.ellipse(11.4, 4.4, 2.6, 2.0, fur)
        c.ellipse(7.6, 5.6, 2.6, 1.2, belly)
        c.ellipse(10.0, 2.0, 1.5, 1.4, fur)
        c[10, 1] = pink
        c[12, 3] = eye
        c[14, 4] = fur
        c[15, 5] = pink
        for (x, y) in [(0, 2), (1, 3), (1, 4), (2, 5), (3, 5)] { c[x, y] = pink }
        for (x, y) in step ? [(5, 7), (9, 7)] : [(4, 7), (8, 7)] { c[x, y] = PixelColor(0x4A3E36) }
        c.outline(PixelColor(0x2A201C))
        return c.texture()
    }

    /// A rust-red scorpion, its tail curled up over its back and its claws held out in front.
    static func scorpion(step: Bool) -> SKTexture {
        let body = PixelColor(0x8A3A2A), light = PixelColor(0xB85A3E), dark = PixelColor(0x5A2218)
        var c = PixelCanvas(width: 16, height: 11)
        c.ellipse(7.5, 7.0, 4.0, 2.0, body)
        c.ellipse(7.0, 6.4, 2.2, 0.8, light)
        for (x, y) in [(3, 6), (2, 5), (2, 4), (2, 3), (3, 2), (4, 1), (5, 1), (6, 2)] { c[x, y] = body }
        c[7, 3] = dark
        c[6, 3] = dark
        c.ellipse(13.4, 5.8, 1.8, 1.5, body)
        c[15, 6] = .clear
        c[14, 6] = .clear
        c[12, 7] = body
        c[11, 6] = body
        for (x, y) in step ? [(5, 9), (7, 9), (9, 9), (10, 9)] : [(4, 9), (6, 9), (8, 9), (10, 9)] { c[x, y] = dark }
        c[10, 6] = PixelColor(0x1A0A08)
        c.outline(PixelColor(0x3A140C))
        return c.texture()
    }

    /// A will-o'-wisp: a pale blue flame with two dark eyes, its tip flickering one way, then the other.
    static func wisp(flicker: Bool) -> SKTexture {
        let core = PixelColor(0xF2FFFF), mid = PixelColor(0xA8ECFF), edge = PixelColor(0x5EC4F0), eye = PixelColor(0x1E3A5A)
        var c = PixelCanvas(width: 11, height: 13)
        c.ellipse(5.5, 8.0, 4.2, 4.2, edge)
        let tip = flicker ? [(5, 0), (4, 1), (5, 1), (6, 2), (3, 2), (4, 2), (5, 2), (3, 3)]
            : [(5, 0), (6, 1), (5, 1), (4, 2), (5, 2), (6, 2), (7, 3)]
        for (x, y) in tip { c[x, y] = edge }
        c.fill(3, 3, 5, 2, edge)
        c.ellipse(5.5, 8.4, 3.0, 3.0, mid)
        c.ellipse(5.5, 9.0, 1.8, 1.8, core)
        for (x, y) in [(4, 8), (7, 8), (4, 7), (7, 7)] { c[x, y] = eye }
        return c.texture()
    }

    /// A little grey mouse, feet pattering.
    static func mouse(step: Bool) -> SKTexture {
        let fur = PixelColor(0x9A9AA6), ear = PixelColor(0xB8B8C4), pink = PixelColor(0xE7A6B0), feet = PixelColor(0x6A6A76)
        var c = PixelCanvas(width: 12, height: 7)
        c.ellipse(5.4, 4.4, 3.6, 2.3, fur)
        c.ellipse(8.6, 4.0, 2.0, 1.7, fur)
        c.ellipse(7.4, 1.8, 1.6, 1.5, ear)
        c[7, 1] = pink
        c[9, 3] = ink
        c[11, 4] = pink
        for (x, y) in [(0, 3), (0, 4), (1, 5), (2, 5)] { c[x, y] = pink }
        for (x, y) in step ? [(4, 6), (7, 6)] : [(3, 6), (6, 6)] { c[x, y] = feet }
        c.outline(PixelColor(0x3A3A44))
        return c.texture()
    }

    static func bunny(fur: PixelColor, light: PixelColor, dark: PixelColor, hop: Bool) -> SKTexture {
        var c = PixelCanvas(width: 15, height: 13)
        let pink = PixelColor(0xF2A7B5)
        let nose = PixelColor(0xE58A9A)
        if hop {
            c.ellipse(6.5, 7.4, 5.4, 3.0, fur)
            c.ellipse(7.5, 8.4, 2.8, 1.5, light)
            c.ellipse(11.2, 4.9, 2.7, 2.4, fur)
            c.fill(8, 0, 2, 3, fur)
            c.fill(10, 0, 2, 3, fur)
            c[8, 1] = pink
            c.ellipse(1.6, 6.6, 1.5, 1.5, .white)
            c.fill(0, 9, 4, 1, dark)
            c.fill(11, 9, 3, 1, dark)
            c[12, 4] = ink
            c[14, 5] = nose
        } else {
            c.ellipse(6.2, 8.6, 4.8, 3.6, fur)
            c.ellipse(7.2, 9.6, 2.6, 1.9, light)
            c.ellipse(10.6, 5.6, 2.8, 2.5, fur)
            c.fill(9, 0, 2, 4, fur)
            c.fill(12, 1, 2, 3, fur)
            c[9, 1] = pink
            c[9, 2] = pink
            c.ellipse(1.8, 7.8, 1.5, 1.5, .white)
            c.fill(3, 12, 3, 1, dark)
            c.fill(8, 12, 2, 1, dark)
            c[11, 5] = ink
            c[13, 6] = nose
        }
        c.outline(ink)
        return c.texture()
    }

    static func frog(hop: Bool) -> SKTexture {
        let green = PixelColor(0x6DBE45), light = PixelColor(0x9BD86A), dark = PixelColor(0x3F8A2A), belly = PixelColor(0xD8EE9A)
        var c = PixelCanvas(width: 13, height: 10)
        if hop {
            c.ellipse(6.2, 5.2, 5.2, 2.6, green)
            c.ellipse(7.2, 6.2, 2.8, 1.3, belly)
            c.ellipse(8.2, 2.4, 1.6, 1.6, green)
            c.ellipse(10.8, 2.8, 1.6, 1.6, green)
            c[8, 1] = .white
            c[9, 1] = ink
            c[11, 2] = .white
            c[12, 2] = ink
            c.fill(0, 6, 3, 1, dark)
            c.fill(0, 7, 2, 1, dark)
            c.fill(10, 7, 3, 1, dark)
        } else {
            c.ellipse(5.6, 6.6, 4.8, 3.0, green)
            c.ellipse(6.8, 7.6, 2.8, 1.6, belly)
            c.ellipse(3.2, 3.9, 1.8, 0.9, light)
            c.ellipse(2.4, 8.2, 2.2, 1.4, dark)
            c.ellipse(7.5, 3.2, 1.7, 1.7, green)
            c.ellipse(10.4, 3.5, 1.7, 1.7, green)
            c[7, 2] = .white
            c[8, 2] = ink
            c[10, 3] = .white
            c[11, 3] = ink
            c.fill(9, 6, 3, 1, dark)
            c.fill(1, 9, 3, 1, dark)
            c.fill(8, 9, 2, 1, dark)
        }
        c.outline(PixelColor(0x1F3A12))
        return c.texture()
    }

    static func crab(up: Bool) -> SKTexture {
        let red = PixelColor(0xE8603C), light = PixelColor(0xF89A6E), dark = PixelColor(0xA73A24)
        var c = PixelCanvas(width: 15, height: 10)
        let lift = up ? 1 : 0
        let legs = up ? [(3, 8), (2, 9), (4, 9), (11, 8), (12, 9), (10, 9)] : [(3, 8), (3, 9), (5, 9), (11, 8), (11, 9), (9, 9)]
        for (x, y) in legs { c[x, y] = dark }
        c.ellipse(7.5, 6.6, 4.1, 2.5, red)
        c.ellipse(7.5, 5.8, 2.4, 0.9, light)
        // Arms and pincers, raised a little while it scuttles.
        c[3, 6 - lift] = dark
        c[11, 6 - lift] = dark
        c.ellipse(1.9, 5.0 - Double(lift), 1.7, 1.6, red)
        c.ellipse(13.1, 5.0 - Double(lift), 1.7, 1.6, red)
        c[1, 4 - lift] = .clear
        c[13, 4 - lift] = .clear
        // Eyes on stalks.
        c[6, 3] = dark
        c[9, 3] = dark
        c[6, 2] = ink
        c[9, 2] = ink
        c.outline(PixelColor(0x5A1E12))
        return c.texture()
    }

    /// songbirds | gulls | bats, wings up or down.
    static func bird(_ kind: String, up: Bool) -> SKTexture {
        switch kind {
        case "gulls":
            let grey = PixelColor(0xC9D2DA), tip = PixelColor(0x4A4F57)
            var c = PixelCanvas(width: 15, height: 6)
            let wing = up ? [(0, 0), (1, 1), (2, 1), (3, 2), (4, 3), (10, 3), (11, 2), (12, 1), (13, 1), (14, 0)]
                : [(0, 3), (1, 3), (2, 3), (3, 3), (4, 3), (10, 3), (11, 3), (12, 3), (13, 3), (14, 3)]
            for (x, y) in wing { c[x, y] = grey }
            c[wing[0].0, wing[0].1] = tip
            c[wing[9].0, wing[9].1] = tip
            c.fill(5, 3, 5, 2, .white)
            c[10, 4] = PixelColor(0xF2B33D)
            return c.texture()
        case "bats":
            let wing = PixelColor(0x3A2A4A), body = PixelColor(0x261A30)
            var c = PixelCanvas(width: 13, height: 6)
            let spans: [(y: Int, from: Int, to: Int)] = up
                ? [(0, 0, 1), (0, 11, 12), (1, 1, 4), (1, 8, 11), (2, 2, 5), (2, 7, 10), (3, 4, 5), (3, 7, 8)]
                : [(2, 0, 4), (2, 8, 12), (3, 1, 4), (3, 8, 11), (4, 1, 1), (4, 3, 3), (4, 9, 9), (4, 11, 11)]
            for span in spans { c.fill(span.from, span.y, span.to - span.from + 1, 1, wing) }
            c.fill(5, 2, 3, 3, body)
            c[5, 1] = body
            c[7, 1] = body
            return c.texture()
        default:
            let body = PixelColor(0x6B4E3A), wing = PixelColor(0x8C6A50)
            var c = PixelCanvas(width: 9, height: 5)
            let feathers = up ? [(0, 0), (1, 1), (2, 2), (6, 2), (7, 1), (8, 0)] : [(0, 3), (1, 2), (2, 2), (6, 2), (7, 2), (8, 3)]
            for (x, y) in feathers { c[x, y] = wing }
            c.fill(3, 2, 3, 1, body)
            c[5, 1] = body
            c[4, 3] = body
            return c.texture()
        }
    }
}
