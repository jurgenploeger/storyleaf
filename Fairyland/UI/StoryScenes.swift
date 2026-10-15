import Observation
import SpriteKit
import SwiftUI

// MARK: - On screen

/// A little living picture for a page of the story (IntroView), made of the game itself rather than
/// drawn for it: a patch of a real map with its own ground, scenery and people (MapPatch), the
/// battle stage with the fighters, spells and Seal Stone of a real fight (BattleActor, SkillEffects),
/// and the HUD's own joystick and buttons over it. It loops; with Reduce Motion it holds still.
struct StoryVignette: View {
    @State private var scene: StoryScene

    init(_ kind: StoryScene.Kind) {
        _scene = State(initialValue: StoryScene(kind: kind))
    }

    var body: some View {
        VignetteView(scene: scene)
    }
}

/// A StoryScene on screen, with its HUD over it.
struct VignetteView: View {
    let scene: StoryScene
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SpriteView(scene: scene, isPaused: reduceMotion, options: [.allowsTransparency])
            .overlay { VignetteHUDView(hud: scene.hud) }
            .aspectRatio(StoryScene.stage.width / StoryScene.stage.height, contentMode: .fit)
            .frame(maxWidth: 560)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(HUDStyle.frameMid.opacity(0.8), lineWidth: 2))
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

/// What a vignette's HUD shows over the picture, set by its scene as it plays.
@Observable
final class VignetteHUD {
    /// What a won fight paid, for the victory card.
    struct Reward: Equatable {
        let exp: Int
        let gold: Int
    }

    /// The battle's log line along the top ("2 monsters appear!").
    var banner: String?
    /// The joystick while it's out, and where its cap is pushed (-1...1 each way, y up).
    var stick: CGVector?
    /// The battle's buttons while it's your turn; Capture glows in once a monster is weak enough.
    var commands = false
    var capture = false
    /// The button a finger is on ("attack", "skills", "capture").
    var pressed: String?
    /// A finger tapping the picture, in the scene's points (y up); `taps` counts them, so each shows.
    var tap: CGPoint?
    var taps = 0
    /// The victory card.
    var victory: Reward?
    /// Which part of How to play the reel is showing (`StoryScene.Clip`).
    var clip = 0
    /// The tip on the How to play page the picture is showing now: one at a time, so the town part
    /// lights Towns as you walk into the square and Quests once Elder Oak speaks.
    var tip = 0

    /// A clear screen for the next part.
    func clear() {
        banner = nil
        stick = nil
        commands = false
        capture = false
        pressed = nil
        tap = nil
        victory = nil
    }
}

/// The game's own HUD over a vignette, at the picture's scale: the battle's log line, the joystick,
/// the command buttons (Attack, Skills and More, and Capture once it glows in), a finger's taps and
/// the victory card.
private struct VignetteHUDView: View {
    let hud: VignetteHUD

    var body: some View {
        GeometryReader { proxy in
            // The picture is shaped like a phone held sideways; its HUD keeps to that, a little larger
            // so it reads.
            let scale = proxy.size.width / 700
            let points = proxy.size.width / StoryScene.stage.width
            ZStack {
                if let banner = hud.banner {
                    // The battle's message line (BattleView.logLine). A new line takes the old one's
                    // place at once, as in a fight; only its coming and going fades.
                    Text(banner)
                        .font(HUDStyle.font(max(9, 13 * scale)))
                        .foregroundStyle(HUDStyle.cream)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(HUDStyle.ink.opacity(0.78)))
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 5)
                        .transition(.opacity)
                }
                // The joystick and the commands are drawn at full size and scaled down, so they sit in
                // overlays: their full size would push the rest of the HUD (the message line) about.
                if let stick = hud.stick {
                    Color.clear
                        .overlay(alignment: .bottomLeading) {
                            JoystickPreview(push: stick)
                                .scaleEffect(scale, anchor: .bottomLeading)
                                .padding(.leading, 6)
                                .padding(.bottom, 6)
                        }
                        .transition(.opacity)
                }
                if hud.commands {
                    // On the arc round Attack, as in a fight (`ThumbArc`).
                    Color.clear
                        .overlay(alignment: .bottomTrailing) {
                            ThumbArc {
                                command("attack", title: L("Attack"), icon: .sword, size: 88, tint: .primary)
                                    .layoutValue(key: ArcSlot.self, value: 0)
                                command("skills", title: L("Skills"), icon: .sparkles, size: 56, tint: .normal)
                                    .layoutValue(key: ArcSlot.self, value: 1)
                                if hud.capture {
                                    command("capture", title: L("Capture"), icon: .sealStone, size: 56, tint: .special)
                                        .layoutValue(key: ArcSlot.self, value: 2)
                                        .transition(.scale(scale: 0.2).combined(with: .opacity))
                                }
                                command("more", title: L("More"), icon: .more, size: 56, tint: .quiet)
                                    .layoutValue(key: ArcSlot.self, value: 3)
                            }
                            .scaleEffect(scale, anchor: .bottomTrailing)
                            .padding(.trailing, 6)
                            .padding(.bottom, 6)
                        }
                        .transition(.opacity)
                }
                if let reward = hud.victory {
                    VStack(spacing: 4) {
                        Text(L("Victory!"))
                            .font(HUDStyle.font(15))
                            .foregroundStyle(HUDStyle.gold)
                        HStack(spacing: 10) {
                            Label { Text(L("+{exp} EXP", ["exp": reward.exp])) } icon: { IconImage(.star, size: 11).foregroundStyle(HUDStyle.exp) }
                            Label { Text(verbatim: "+\(reward.gold)") } icon: { IconImage(.coins, size: 11).foregroundStyle(HUDStyle.coin) }
                        }
                        .labelStyle(CompactLabelStyle())
                        .font(HUDStyle.font(11))
                        .foregroundStyle(HUDStyle.cream)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(HUDStyle.panel)
                    // Where the monsters stood, clear of you and your LEVEL UP!.
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.leading, 18)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
                if let tap = hud.tap {
                    TapMark()
                        .id(hud.taps)
                        .position(x: tap.x * points, y: (StoryScene.stage.height - tap.y) * points)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.2), value: hud.banner != nil)
        .animation(.easeOut(duration: 0.25), value: hud.commands)
        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: hud.capture)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: hud.pressed)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: hud.victory)
    }

    /// One of BattleView's round buttons, pressed down while a finger is on it.
    private func command(_ id: String, title: String, icon: GameIcon, size: CGFloat, tint: RoundCommandButton.Tint) -> some View {
        RoundCommandButton(title: title, icon: icon, size: size, tint: tint) {}
            .scaleEffect(hud.pressed == id ? 0.88 : 1)
            .brightness(hud.pressed == id ? 0.08 : 0)
    }
}

/// A finger tapping: a fingertip and a ring spreading from it, then gone.
private struct TapMark: View {
    @State private var spread = false
    @State private var gone = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(.white, lineWidth: 2)
                .frame(width: 26, height: 26)
                .scaleEffect(spread ? 1.6 : 0.4)
                .opacity(spread ? 0 : 0.95)
            IconImage(.tap, size: 20)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 1)
                .offset(x: 7, y: 12)
        }
        .opacity(gone ? 0 : 1)
        .onAppear {
            withAnimation(.easeOut(duration: 0.55)) { spread = true }
            withAnimation(.easeIn(duration: 0.3).delay(0.7)) { gone = true }
        }
    }
}

// MARK: - The scene

final class StoryScene: SKScene {
    enum Kind {
        /// Liora's light over a meadow where a bit of every tale has come to live.
        case gathering
        /// The Big Bad Wolf, the Rat King and the Drunk Dragon, each blocking the way in its own land.
        case shadows
        /// You walk into Meadowbrook's square with your companion, where Elder Oak is waiting.
        case arrival
        /// How to play, played: a walk with the joystick and a tap, a fight with a spell, a Seal
        /// Stone, the victory and a level up, and a quest giver in town (`Clip`).
        case reel
    }

    /// The parts of the How to play reel, in order; it loops.
    enum Clip: Int, CaseIterable {
        case walk, battle, seal, victory, town

        /// The tips on the How to play page it shows (IntroView), by their place there, in the
        /// order it shows them: the town is Towns first, then Quests when Elder Oak speaks.
        var tips: [Int] {
            switch self {
            case .walk: [0]
            case .battle: [1]
            case .seal: [2]
            case .victory: [3]
            case .town: [5, 4]
            }
        }

        /// The part that shows a tip.
        static func showing(tip: Int) -> Clip {
            allCases.first { $0.tips.contains(tip) } ?? .walk
        }
    }

    /// The scene's size in points; the view scales it to fit.
    static let stage = CGSize(width: 360, height: 170)
    /// What the HUD over the picture shows (VignetteView draws it).
    let hud = VignetteHUD()
    private let kind: Kind
    private var built = false
    private var firstClip: Clip
    private let art = ArtLibrary.shared

    // The map: a patch of it seen through `world` at `zoom`, the camera gliding after `followed` to
    // keep them at `focus` on screen.
    private let mapRoot = SKNode()
    private let world = SKNode()
    private var patch: MapPatch?
    private var zoom: CGFloat = 0.8
    private var focus = CGPoint(x: 180, y: 85)
    private var followed: SKNode?
    /// A companion trailing whoever it walks with, as on the map (Walker.follow).
    private var trail: (leader: Walker, companion: Walker)?
    private var lastUpdate: TimeInterval = 0
    /// A tint over the land (night in the woods, the cave's dark), part of what a backdrop shows.
    private let tint = SKSpriteNode(color: .clear, size: StoryScene.stage)

    // A battle, laid out as BattleScene lays one out on a phone held sideways, shrunk to fit.
    private let battleRoot = SKNode()
    private let backdrop = SKSpriteNode(color: UIColor(red: 0.2, green: 0.35, blue: 0.3, alpha: 1), size: StoryScene.stage)
    private let shade = SKSpriteNode(color: UIColor(red: 0.05, green: 0.08, blue: 0.2, alpha: 0.38), size: StoryScene.stage)
    private let battleStage = SKNode()
    private static let battleZoom: CGFloat = 0.55
    private var actors: [Int: BattleActor] = [:]
    private var arrows: [SKNode] = []
    /// White over everything: an encounter's flash, and the fade into a fight.
    private let flash = SKSpriteNode(color: .white, size: StoryScene.stage)

    // How to play's pieces, made once and played again each time round.
    private var meadow: MapPatch?
    private var meadowHero: Walker?
    private var meadowPet: Walker?
    private var square: Square?
    /// Where the fight on the stage has got to, so a part can carry on from the one before.
    private var fight: Fight?

    /// Meadowbrook's square and who's in it.
    private struct Square {
        let patch: MapPatch
        let elder: Walker
        let marker: SKNode
        let hero: Walker
        let pet: Walker

        /// Where the camera looks: by the fountain, which puts Elder Oak low enough for his "!", and what
        /// he says (four lines in French), to fit in the picture above him, and Nurse Mira clear of
        /// the joystick.
        var view: CGPoint { patch.point(12.9, 13.5) }
    }

    /// The fight's moments the reel's parts start from.
    private enum Fight {
        case opening, sealing, won
    }

    init(kind: Kind, startClip: Int = 0) {
        self.kind = kind
        firstClip = Clip(rawValue: startClip) ?? .walk
        super.init(size: Self.stage)
        scaleMode = .aspectFill
        anchorPoint = .zero
        backgroundColor = .clear
        addChild(mapRoot)
        mapRoot.addChild(world)
        tint.anchorPoint = .zero
        tint.zPosition = 1_000
        tint.isHidden = true
        mapRoot.addChild(tint)
        addChild(battleRoot)
        battleRoot.isHidden = true
        for node in [backdrop, shade] {
            node.anchorPoint = .zero
            battleRoot.addChild(node)
        }
        backdrop.zPosition = -10_000
        shade.zPosition = -9_000
        battleStage.setScale(Self.battleZoom)
        battleRoot.addChild(battleStage)
        flash.anchorPoint = .zero
        flash.zPosition = 40_000
        flash.alpha = 0
        addChild(flash)
    }

    required init?(coder: NSCoder) {
        fatalError("StoryScene is made in code")
    }

    override func didMove(to view: SKView) {
        guard !built else { return }
        built = true
        switch kind {
        case .gathering: buildGathering()
        case .shadows: buildShadows()
        case .arrival: buildArrival()
        case .reel: buildReel()
        }
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate > 0 ? min(0.1, currentTime - lastUpdate) : 0
        lastUpdate = currentTime
        if let trail, trail.companion.parent != nil {
            trail.leader.markFootstep()
            trail.companion.follow(trail.leader, dt: dt, footstep: trail.leader.footstep(behind: 34), canStand: { _ in true })
        }
        guard let patch else { return }
        patch.sortByDepth()
        if let followed, followed.parent === patch.things {
            // Glide after them, like the map's camera.
            let goal = cameraSpot(looking: followed.position)
            let step = min(1, CGFloat(dt) * 3)
            patch.position = CGPoint(x: patch.position.x + (goal.x - patch.position.x) * step,
                                     y: patch.position.y + (goal.y - patch.position.y) * step)
        }
    }

    // MARK: - The map

    /// Puts `patch` on screen at `zoom`, looking at `point` on it (at `focus` on screen).
    private func show(_ patch: MapPatch, zoom: CGFloat, looking point: CGPoint, focus: CGPoint = CGPoint(x: 180, y: 85)) {
        if self.patch !== patch {
            self.patch?.removeFromParent()
            world.addChild(patch)
            self.patch = patch
        }
        self.zoom = zoom
        self.focus = focus
        world.setScale(zoom)
        patch.position = cameraSpot(looking: point)
        patch.sortByDepth()
        mapRoot.isHidden = false
    }

    /// Where the patch goes for `point` on it to be at `focus` on screen.
    private func cameraSpot(looking point: CGPoint) -> CGPoint {
        CGPoint(x: focus.x / zoom - point.x, y: focus.y / zoom - point.y)
    }

    /// Walks `walker` from where it'll be (`points[0]`) through the rest at the map's walking pace,
    /// turning to each new way; with `steer`, the joystick pushes the way it goes. Returns the walk
    /// (run it on the walker) and how long it takes.
    private func walking(_ walker: Walker, through points: [CGPoint], steer: Bool) -> (action: SKAction, time: TimeInterval) {
        var steps: [SKAction] = []
        var time: TimeInterval = 0
        for (from, to) in zip(points, points.dropFirst()) {
            let way = to - from
            guard way.length > 0.5 else { continue }
            let facing = Direction(way)
            let push = way.normalized
            steps.append(.run { [weak self, weak walker] in
                walker?.face(facing)
                walker?.setWalking(true)
                if steer { self?.hud.stick = push }
            })
            let leg = TimeInterval(way.length / walker.walkSpeed)
            steps.append(.move(to: to, duration: leg))
            time += leg
        }
        steps.append(.run { [weak self, weak walker] in
            walker?.setWalking(false)
            if steer { self?.hud.stick = .zero }
        })
        return (.sequence(steps), time)
    }

    /// Back and forth between where it stands and `point`, resting at each end.
    private func pace(_ walker: Walker, to point: CGPoint, pause: TimeInterval) {
        let home = walker.position
        let there = walking(walker, through: [home, point], steer: false)
        let back = walking(walker, through: [point, home], steer: false)
        walker.run(.repeatForever(.sequence([.wait(forDuration: pause), there.action, .wait(forDuration: pause), back.action])), withKey: "move")
    }

    /// A finger taps the ground: the swirl where it touched, and the fingertip over it.
    private func tapGround(at point: CGPoint) {
        guard let patch else { return }
        Effects.tapMarker(at: point, in: patch)
        hud.tap = patch.convert(point, to: self)
        hud.taps += 1
    }

    // MARK: - The story

    /// Liora's light over a meadow where a bit of every tale has come to live: Thumbelina's lotus
    /// pond, Snow White's apple tree, poppies from the Emerald Road, a lamp and a flying carpet from
    /// the Thousand and One Nights, candy canes from Gumdrop Peaks. Its creatures play below while
    /// sparks of the tales drift up into her light.
    private func buildGathering() {
        guard let meadow = MapPatch(map: "sunny_meadow", columns: 22, rows: 22) else { return }
        meadow.road([(0, 8), (7, 10), (12, 10), (21, 12)])
        meadow.blob(8, 14, radius: 2.5, .water)
        meadow.blob(14, 6, radius: 2.6, .accent)
        meadow.layGround()
        let scenery: [(String, CGFloat, CGFloat)] = [
            ("lotus", 8, 14), ("lily_pad", 7, 13), ("lily_pad", 9, 15), ("apple_tree", 12, 14),
            ("poppy_patch", 14, 6), ("poppy_patch", 15, 8), ("poppy_patch", 13, 7), ("magic_lamp", 8, 7),
            ("flying_carpet", 7, 8), ("candy_cane", 14, 13), ("candy_cane", 15, 12.4), ("blossom_tree", 5, 12),
            ("tree", 4, 9), ("big_tree", 11, 17), ("golden_tree", 17, 9), ("mushroom", 10, 12),
            ("daisy", 11, 8), ("daisy_yellow", 13, 12), ("sunflower", 15, 11), ("bush", 6, 6),
        ]
        for (id, col, row) in scenery { meadow.prop(id, col, row) }
        meadow.walker("monster_jelly", 10, 10)
        meadow.walker("monster_pineapple", 13, 11, facing: .left)
        meadow.walker("monster_yellow_butterfly", 9, 11)
        let bunny = meadow.walker("pet_walk", 12, 8, facing: .right)
        show(meadow, zoom: 0.8, looking: meadow.middle)
        pace(bunny, to: meadow.point(13.5, 8.6), pause: 1.2)

        // Liora's light, high over the land, drawing every tale toward it.
        let light = glow(Nodes.gold, size: 120, at: CGPoint(x: 180, y: 150))
        light.run(.repeatForever(.sequence([.scale(to: 1.15, duration: 1.4), .scale(to: 0.92, duration: 1.4)])))
        Ambience.twinkle(around: CGPoint(x: 180, y: 136), radius: 34, count: 6, in: self)
        run(.repeatForever(.sequence([.run { [weak self] in self?.riseToTheLight() }, .wait(forDuration: 0.28)])))
        particles("petals")
    }

    /// The tales gone wrong, each in its own land and as you'll meet it: the Big Bad Wolf in the
    /// snowy wood at night, the Rat King in his cavern, the Drunk Dragon at the oasis. One after
    /// another they step out on the battle stage, roaring, under a red glow.
    private func buildShadows() {
        let lands = [makeForest(), makeCavern(), makeOasis()]
        let bosses = ["big_bad_wolf", "rat_king", "drunk_dragon"]
        // Each land's own weather drifting over it: snow in the wood, motes in the cave, dust in the desert.
        let weather = ["snow", "motes", "dust"].map { particleLayer($0) }
        weather.dropFirst().forEach { $0.isHidden = true }
        // As BattleScene would show them, on a blurred snapshot of the land; if the snapshot can't
        // be taken, the land itself stays behind them.
        var backdrops: [SKTexture?] = []
        for land in lands {
            guard let land else {
                backdrops.append(nil)
                continue
            }
            show(land.patch, zoom: 0.8, looking: land.patch.middle)
            setTint(land.tint)
            backdrops.append(snapshot())
        }
        let turn: TimeInterval = 4
        var steps: [SKAction] = []
        for (index, id) in bosses.enumerated() {
            guard let boss = Self.boss(id) else { continue }
            let actor = BattleActor(fighter: boss, art: art)
            actor.place(at: CGPoint(x: Self.field.width * 0.5, y: Self.field.height * 0.22), facing: .down)
            actor.alpha = 0
            battleStage.addChild(actor)
            let red = glow(UIColor(red: 1, green: 0.2, blue: 0.25, alpha: 1), size: 150, at: actor.center, in: battleStage)
            red.zPosition = actor.zPosition - 1
            red.alpha = 0
            let land = index < lands.count ? lands[index] : nil
            let shot = index < backdrops.count ? backdrops[index] : nil
            steps.append(.run { [weak self] in
                guard let self else { return }
                for (place, layer) in weather.enumerated() { layer.isHidden = place != index }
                if let shot {
                    self.backdrop.texture = shot
                    self.mapRoot.isHidden = true
                } else if let land {
                    self.show(land.patch, zoom: 0.8, looking: land.patch.middle)
                    self.setTint(land.tint)
                }
                self.hud.banner = L("{monster} blocks your way!", ["monster": boss.name])
                actor.run(.fadeIn(withDuration: 0.6))
                red.run(.sequence([.fadeAlpha(to: 0.55, duration: 0.6),
                                   .repeat(.sequence([.fadeAlpha(to: 0.3, duration: 0.9), .fadeAlpha(to: 0.6, duration: 0.9)]), count: 2)]))
                actor.run(.sequence([.wait(forDuration: 0.7), .run { [weak self, weak actor] in
                    guard let self, let actor else { return }
                    _ = SkillEffects.roar(from: actor, on: [], level: 3, in: self.battleStage)
                    self.shake()
                }]))
            })
            steps.append(.wait(forDuration: turn - 0.6))
            steps.append(.run {
                actor.run(.fadeOut(withDuration: 0.6))
                red.run(.fadeOut(withDuration: 0.6))
            })
            steps.append(.wait(forDuration: 0.6))
        }
        battleRoot.isHidden = false
        if let first = backdrops.first ?? nil {
            backdrop.texture = first
            mapRoot.isHidden = true
        } else if let forest = lands.first ?? nil {
            show(forest.patch, zoom: 0.8, looking: forest.patch.middle)
            setTint(forest.tint)
        }
        guard !steps.isEmpty else { return }
        run(.repeatForever(.sequence(steps)))
    }

    /// The Snow White Forest at night.
    private func makeForest() -> (patch: MapPatch, tint: UIColor)? {
        guard let forest = MapPatch(map: "snow_white_forest", columns: 22, rows: 22) else { return nil }
        forest.road([(0, 9), (10, 10), (21, 12)])
        forest.blob(6, 15, radius: 2.2, .water)
        forest.layGround()
        let scenery: [(String, CGFloat, CGFloat)] = [
            ("big_snow_pine", 6, 12), ("snow_pine", 4, 9), ("snow_tree", 9, 14), ("frost_pine", 14, 15),
            ("big_snow_tree", 16, 13), ("snow_bush", 12, 13), ("snow_pine", 17, 8), ("snow_bush", 8, 7),
            ("frost_pine", 13, 6), ("big_snow_pine", 18, 11), ("dead_tree", 7, 10), ("boulder", 15, 9), ("snow_pine", 11, 5),
        ]
        for (id, col, row) in scenery { forest.prop(id, col, row) }
        return (forest, UIColor(red: 0.05, green: 0.04, blue: 0.2, alpha: 0.5))
    }

    /// The Rat King's cavern: rock floor, stalagmites, crystals and an old mine cart in the dark.
    private func makeCavern() -> (patch: MapPatch, tint: UIColor)? {
        guard let cavern = MapPatch(map: "rat_cavern", columns: 22, rows: 22) else { return nil }
        cavern.road([(0, 10), (21, 11)])
        cavern.blob(7, 14, radius: 2.4, .accent)
        cavern.blob(15, 6, radius: 2.2, .accent)
        cavern.layGround()
        let scenery: [(String, CGFloat, CGFloat)] = [
            ("stalagmite", 7, 13), ("stalagmite", 14, 14), ("small_stalagmite", 9, 12), ("crystal", 12, 13),
            ("amber_crystal", 16, 12), ("mine_cart", 8, 8), ("skull_bones", 13, 8), ("boulder", 5, 10),
            ("crystal_shard", 15, 9), ("stalagmite", 17, 7), ("small_stalagmite", 11, 6), ("ore_vein", 6, 6),
        ]
        for (id, col, row) in scenery { cavern.prop(id, col, row) }
        return (cavern, UIColor(red: 0.03, green: 0.04, blue: 0.12, alpha: 0.55))
    }

    /// The oasis in Genie Desert where the dragon drinks: sand, palms round the water, cactus.
    private func makeOasis() -> (patch: MapPatch, tint: UIColor)? {
        guard let oasis = MapPatch(map: "genie_desert", columns: 22, rows: 22) else { return nil }
        oasis.road([(0, 8), (21, 9)])
        oasis.blob(10, 14, radius: 2.6, .water)
        oasis.blob(15, 6, radius: 2.4, .accent)
        oasis.layGround()
        let scenery: [(String, CGFloat, CGFloat)] = [
            ("oasis_palm", 8, 12), ("oasis_palm", 13, 15), ("palm_tree", 12, 12), ("palm_sapling", 7, 15),
            ("cactus", 15, 11), ("small_cactus", 6, 9), ("yellow_cactus", 16, 7), ("sandstone_boulder", 13, 6),
            ("desert_pot", 9, 10), ("dry_bush", 11, 7), ("flying_carpet", 17, 10), ("red_rock", 5, 6),
        ]
        for (id, col, row) in scenery { oasis.prop(id, col, row) }
        return (oasis, UIColor(red: 0.35, green: 0.1, blue: 0.2, alpha: 0.3))
    }

    private func setTint(_ color: UIColor) {
        tint.color = color
        tint.isHidden = false
    }

    /// Meadowbrook's square as it looks when you arrive: you and your companion walk up the street
    /// to Elder Oak, waiting by the fountain with a quest (the gold "!"), and he greets you.
    private func buildArrival() {
        guard let square = makeSquare(companion: "bunny", staff: false) else { return }
        self.square = square
        show(square.patch, zoom: 0.8, looking: square.view)
        run(.repeatForever(.sequence([greeting(steer: false), .wait(forDuration: 0.4)])))
    }

    /// Meadowbrook's square: Elder Oak by the fountain with a quest for you, Nurse Mira and Trader Bo
    /// at their places, cottages round the crossroads, and you with your companion coming up the
    /// street.
    private func makeSquare(companion species: String, staff: Bool) -> Square? {
        guard let patch = MapPatch(map: "meadowbrook", columns: 22, rows: 22) else { return nil }
        patch.road([(0, 10), (21, 10)])
        patch.road([(11, 0), (11, 21)])
        patch.blob(11, 10, radius: 1.6, .path)
        patch.layGround()
        let scenery: [(String, CGFloat, CGFloat)] = [
            ("fountain", 13, 13), ("house", 8, 15), ("inn", 16, 14), ("house_purple", 7, 7), ("item_shop", 15, 5),
            ("blossom_tree", 10, 15), ("blossom_tree", 17, 11), ("giant_flower", 9, 8.5), ("giant_flower", 14, 11.6),
            ("street_lamp", 10, 6.5), ("street_lamp", 12.6, 8.4), ("flowering_bush", 8.5, 10.6), ("daisy", 13, 6),
            ("tulip_patch", 9.4, 5.4), ("bench", 9.6, 12), ("daisy_blue", 13.5, 15.5), ("flowering_bush", 17.5, 9),
        ]
        for (id, col, row) in scenery { patch.prop(id, col, row) }
        let content = Content.shared
        let elder = patch.walker("npc_elder", 12.4, 11.2, label: content.npc("elder")?.name)
        // The quest "!" as the map shows it (WorldScene.placeNPCs).
        let marker = NameTag("!", size: 28)
        marker.position = CGPoint(x: 0, y: elder.sprite.size.height + 18)
        marker.zPosition = 6_000
        let bob = SKAction.sequence([.moveBy(x: 0, y: 5, duration: 0.4), .moveBy(x: 0, y: -5, duration: 0.4)])
        let pulse = SKAction.sequence([.scale(to: 1.15, duration: 0.4), .scale(to: 1, duration: 0.4)])
        marker.run(.repeatForever(.group([bob, pulse])))
        elder.addChild(marker)
        patch.walker("npc_healer", 8.6, 12.6, facing: .right, label: content.npc("healer")?.name)
        patch.walker("npc_trader", 14.2, 8.6, facing: .left, label: content.npc("shop")?.name)
        let hero = patch.walker("player_walk", 11, 4.5, facing: .left, label: L("Hero"))
        hero.tagMode = .whenStill
        hero.fidgets = true
        if staff { hero.setWeapon(content.item("oak_staff")) }
        let pet = patch.walker(content.monster(species)?.art ?? "pet_walk", 10.4, 3.9, facing: .left, label: content.monster(species)?.name)
        pet.tagMode = .whenClear
        pet.walkSpeed = 110
        return Square(patch: patch, elder: elder, marker: marker, hero: hero, pet: pet)
    }

    /// You and your companion come up the street to Elder Oak, and he greets you. Starts over each
    /// time it plays; with `steer` the joystick shows the way.
    private func greeting(steer: Bool) -> SKAction {
        guard let square else { return .wait(forDuration: 1) }
        let start = square.patch.point(11, 4.5), stop = square.patch.point(11.9, 9.9)
        let walk = walking(square.hero, through: [start, stop], steer: steer)
        let words = Content.shared.npc("elder")?.greeting ?? ""
        return .sequence([
            .run { [weak self] in
                guard let self, let square = self.square else { return }
                square.hero.removeAction(forKey: "move")
                square.hero.setWalking(false)
                square.hero.position = start
                square.hero.face(.left)
                square.pet.position = square.patch.point(10.4, 3.9)
                square.pet.face(.left)
                for walker in [square.hero, square.pet] {
                    walker.alpha = 0
                    walker.run(.fadeIn(withDuration: 0.4))
                }
                square.marker.alpha = 1
                self.trail = (square.hero, square.pet)
                self.followed = nil
                if steer { self.hud.stick = .zero }
            },
            .wait(forDuration: 0.6),
            .run { [weak hero = square.hero] in hero?.run(walk.action, withKey: "move") },
            .wait(forDuration: walk.time + 0.4),
            .run { [weak self] in
                guard let square = self?.square else { return }
                // He has something to say: his words in a bubble, where his "!" was.
                square.marker.run(.fadeOut(withDuration: 0.2))
                square.elder.say(words, for: 3.4)
                // He has a quest for you: How to play (the part with the joystick) lights Quests.
                if steer { self?.hud.tip = Clip.town.tips[1] }
            },
            .wait(forDuration: 4.2),
            .run { [weak self] in
                guard let square = self?.square else { return }
                for walker in [square.hero, square.pet] { walker.run(.fadeOut(withDuration: 0.4)) }
                square.marker.run(.fadeIn(withDuration: 0.4))
            },
            .wait(forDuration: 0.5),
        ])
    }

    // MARK: - How to play

    /// Plays the reel from `clip` on (0 walk, 1 battle, 2 seal, 3 victory, 4 town), round and round.
    /// The How to play page calls it when a tip is tapped.
    func play(clip index: Int) {
        let count = Clip.allCases.count
        let clip = Clip(rawValue: ((index % count) + count) % count) ?? .walk
        guard kind == .reel, built else {
            firstClip = clip
            return
        }
        removeAction(forKey: "reel")
        battleStage.removeAllActions()
        hud.clear()
        hud.clip = clip.rawValue
        hud.tip = clip.tips[0]
        let part: SKAction = switch clip {
        case .walk: walkClip()
        case .battle: battleClip()
        case .seal: sealClip()
        case .victory: victoryClip()
        case .town: townClip()
        }
        // The next part starts outside SpriteKit's frame, as a map's fights do (WorldScene.startEncounter):
        // a fight snapshots the map for its backdrop.
        run(.sequence([part, .run { [weak self] in
            Task { @MainActor [weak self] in self?.play(clip: clip.rawValue + 1) }
        }]), withKey: "reel")
    }

    private func buildReel() {
        meadow = makeMeadow()
        square = makeSquare(companion: "pineapple", staff: true)
        play(clip: firstClip.rawValue)
        // Debug `clip`: screenshots count their seconds from here.
        DebugLaunch.markReady()
    }

    /// Sunny Meadow, where How to play walks and fights: a road past a pond and a flower meadow,
    /// and you, a young mage, with your companion.
    private func makeMeadow() -> MapPatch? {
        guard let meadow = MapPatch(map: "sunny_meadow", columns: 22, rows: 22) else { return nil }
        meadow.road([(0, 9), (6, 10), (11, 11), (16, 11), (21, 13)])
        meadow.blob(7, 15, radius: 2.6, .water)
        meadow.blob(12, 6, radius: 2.8, .accent)
        meadow.layGround()
        let scenery: [(String, CGFloat, CGFloat)] = [
            ("tree", 4, 13), ("big_tree", 9, 16), ("blossom_tree", 13, 14), ("tree", 15, 16), ("bush", 10, 13),
            ("flowering_bush", 14, 13), ("daisy", 8, 12), ("daisy_yellow", 12, 13), ("mushroom", 5, 12), ("sunflower", 16, 14),
            ("lily_pad", 7, 15), ("lotus", 8, 14), ("tree", 5, 6), ("autumn_tree", 8, 5), ("bush", 9, 8),
            ("daisy", 11, 9), ("daisy_blue", 13, 8), ("giant_flower", 17, 8), ("rock", 18, 10), ("pumpkin_patch", 16, 7),
            ("tree", 19, 6), ("golden_tree", 19, 11), ("tulip_patch", 6, 8), ("clover_patch", 14, 10), ("big_blossom_tree", 18, 15),
            ("tree_stump", 3, 9),
        ]
        for (id, col, row) in scenery { meadow.prop(id, col, row) }
        let content = Content.shared
        let hero = meadow.walker("player_walk", 6, 10, facing: .right, label: L("Hero"))
        hero.tagMode = .whenStill
        hero.fidgets = true
        hero.setWeapon(content.item("oak_staff"))
        let pet = meadow.walker(content.monster("pineapple")?.art ?? "monster_pineapple", 5.2, 9.6, facing: .right,
                                label: content.monster("pineapple")?.name)
        pet.tagMode = .whenClear
        pet.walkSpeed = 110
        meadowHero = hero
        meadowPet = pet
        return meadow
    }

    /// Walk: the joystick pushes you along the road, then a tap on the meadow walks you there, until
    /// a monster jumps out (the encounter's white flash).
    private func walkClip() -> SKAction {
        guard let meadow, let hero = meadowHero, let pet = meadowPet else { return .wait(forDuration: 1) }
        battleRoot.isHidden = true
        let road = [meadow.point(6, 10), meadow.point(11, 11), meadow.point(13.5, 11)]
        let tapped = meadow.point(15, 9.2)
        hero.removeAction(forKey: "move")
        hero.setWalking(false)
        hero.position = road[0]
        hero.face(.right)
        pet.position = meadow.point(5.2, 9.6)
        pet.face(.right)
        followed = hero
        trail = (hero, pet)
        show(meadow, zoom: 0.85, looking: hero.position, focus: CGPoint(x: 160, y: 72))
        hud.stick = .zero
        let stroll = walking(hero, through: road, steer: true)
        let detour = walking(hero, through: [road[2], tapped], steer: false)
        return .sequence([
            .wait(forDuration: 0.7),
            .run { [weak hero] in hero?.run(stroll.action, withKey: "move") },
            .wait(forDuration: stroll.time + 0.6),
            .run { [weak self] in self?.tapGround(at: tapped) },
            .wait(forDuration: 0.3),
            .run { [weak hero] in hero?.run(detour.action, withKey: "move") },
            .wait(forDuration: detour.time + 0.5),
            // A monster jumps out: the screen flashes white twice, as on the map.
            .run { [weak self] in
                self?.flash.run(.sequence([
                    .fadeAlpha(to: 0.85, duration: 0.08), .fadeAlpha(to: 0, duration: 0.08),
                    .fadeAlpha(to: 0.85, duration: 0.08), .fadeAlpha(to: 0, duration: 0.08),
                ]))
            },
            .wait(forDuration: 0.34),
        ])
    }

    /// Battle: two monsters appear; Attack, a tap on a monster, your bolt of magic; your companion's
    /// Pine Needles; the Golden Hamster's Golden Spin; then Skills and a Fire Bolt on its weak spot.
    private func battleClip() -> SKAction {
        setUpFight(.opening)
        hud.banner = L("{count} monsters appear!", ["count": 2])
        flash.alpha = 1
        flash.run(.fadeOut(withDuration: 0.45))
        return .sequence([
            .wait(forDuration: 1.1),
            .run { [weak self] in self?.hud.commands = true },
            .wait(forDuration: 0.7),
            .run { [weak self] in self?.press("attack") },
            .wait(forDuration: 0.35),
            .run { [weak self] in self?.showTargets([10, 11]) },
            .wait(forDuration: 0.7),
            .run { [weak self] in self?.tap(fighter: 11) },
            .wait(forDuration: 0.2),
            .run { [weak self] in
                self?.showTargets([])
                self?.magicBolt(at: 11, damage: 14, leaving: 0.45)
            },
            .wait(forDuration: 1.1),
            .run { [weak self] in self?.pineNeedles() },
            .wait(forDuration: 1.2),
            .run { [weak self] in self?.goldenSpin() },
            .wait(forDuration: 1.2),
            .run { [weak self] in self?.press("skills") },
            .wait(forDuration: 0.45),
            .run { [weak self] in self?.fireBolt(at: 10) },
            .wait(forDuration: 1.9),
            // The seal carries on from here.
            .run { [weak self] in self?.fight = .sealing },
        ])
    }

    /// Companions: the last monster is down below 20% of its HP, Capture glows in, and the Seal
    /// Stone seals it.
    private func sealClip() -> SKAction {
        if fight != .sealing { setUpFight(.sealing) }
        hud.commands = true
        return .sequence([
            .wait(forDuration: 0.5),
            .run { [weak self] in self?.hud.capture = true },
            .wait(forDuration: 1.1),
            .run { [weak self] in self?.press("capture") },
            .wait(forDuration: 0.35),
            .run { [weak self] in
                guard let self else { return }
                self.hud.commands = false
                self.hud.capture = false
                self.hud.banner = L("{name} throws a Seal Stone!", ["name": L("Hero")])
                self.seal(11)
            },
            // As the seal sets in gold, the line BattleController shows.
            .wait(forDuration: Self.sealedAt),
            .run { [weak self] in
                self?.hud.banner = L("Sealed! {name} was captured!", ["name": Self.fighter(11)?.name ?? ""])
            },
            .wait(forDuration: Self.sealTime - Self.sealedAt + 0.5),
            .run { [weak self] in self?.fight = .won },
        ])
    }

    /// Grow: the fight is won, light pours down on you with LEVEL UP!, and the victory card shows
    /// what it paid.
    private func victoryClip() -> SKAction {
        if fight != .won { setUpFight(.won) }
        hud.banner = L("{name} reached level {level}!", ["name": L("Hero"), "level": 13])
        return .sequence([
            .wait(forDuration: 0.3),
            .run { [weak self] in self?.levelUp(to: 13) },
            .wait(forDuration: 1.7),
            .run { [weak self] in self?.hud.victory = VignetteHUD.Reward(exp: 46, gold: 18) },
            .wait(forDuration: 2.6),
        ])
    }

    /// Quests and towns: back in Meadowbrook, the joystick takes you up the street to Elder Oak and
    /// his gold "!", and he has something to ask.
    private func townClip() -> SKAction {
        guard let square else { return .wait(forDuration: 1) }
        battleRoot.isHidden = true
        fight = nil
        show(square.patch, zoom: 0.8, looking: square.view)
        return greeting(steer: true)
    }

    // MARK: - The fight

    /// The field BattleScene would lay this fight out on: the picture's size before it's shrunk.
    private static var field: CGSize {
        CGSize(width: stage.width / battleZoom, height: stage.height / battleZoom)
    }

    /// Where everyone stands, as BattleScene arranges a phone held sideways: the monsters in a line on
    /// the left, you on the right side by side with your companion, in a line of your own.
    private static let places: [Int: CGPoint] = [
        10: CGPoint(x: 172, y: 150), 11: CGPoint(x: 238, y: 82),
        0: CGPoint(x: 352, y: 128), 1: CGPoint(x: 416, y: 60),
    ]

    /// The fighters: you (0), a young mage; your companion (1), a Pineapple Sprout; and the wild
    /// Golden Hamster (10) and Fluffy Bunny (11) from Sunny Meadow.
    private static func fighter(_ id: Int) -> Combatant? {
        let content = Content.shared
        switch id {
        case 0:
            let stats = Stats(hp: 132, mp: 64, attack: 18, defense: 15, magic: 36, speed: 14)
            var hero = Combatant(id: 0, side: .party, source: .hero, name: L("Hero"), art: "player_walk", level: 12,
                                 element: .neutral, stats: stats, hp: stats.hp, mp: stats.mp, skills: ["fire_bolt"], captureRate: 0)
            hero.classID = "mage"
            hero.raceID = "human"
            return hero
        case 1:
            guard let species = content.monster("pineapple") else { return nil }
            let stats = species.stats(at: 10)
            var companion = Combatant(id: 1, side: .party, source: .pet(UUID()), name: species.name, art: species.art, level: 10,
                                      element: species.element, stats: stats, hp: stats.hp, mp: stats.mp, skills: species.skills, captureRate: 0)
            companion.ownerID = 0
            return companion
        case 10, 11:
            let (speciesID, level) = id == 10 ? ("golden_hamster", 7) : ("bunny", 6)
            guard let species = content.monster(speciesID) else { return nil }
            let stats = species.stats(at: level)
            return Combatant(id: id, side: .enemies, source: .wild(speciesID), name: species.name, art: species.art, level: level,
                             element: species.element, stats: stats, hp: stats.hp, mp: stats.mp, skills: species.skills,
                             captureRate: species.captureRate)
        default:
            return nil
        }
    }

    /// A boss as it stands in its fight, at its level on the map.
    private static func boss(_ id: String) -> Combatant? {
        let content = Content.shared
        guard let species = content.monster(id) else { return nil }
        let level = content.boss(fighting: id)?.level ?? 50
        let stats = species.stats(at: level)
        return Combatant(id: 100, side: .enemies, source: .wild(id), name: species.name, art: species.art, level: level,
                         element: species.element, stats: stats, hp: stats.hp, mp: stats.mp, skills: species.skills, captureRate: 0)
    }

    /// Sets the stage for a moment of the fight, over the map where you stand.
    private func setUpFight(_ moment: Fight) {
        takeBackdrop()
        mapRoot.isHidden = true
        battleRoot.isHidden = false
        followed = nil
        trail = nil
        battleStage.removeAllActions()
        battleStage.removeAllChildren()
        actors = [:]
        arrows = []
        let ids: [Int] = switch moment {
        case .opening: [10, 11, 0, 1]
        case .sealing: [11, 0, 1]
        case .won: [0, 1]
        }
        for id in ids {
            guard let fighter = Self.fighter(id), let place = Self.places[id] else { continue }
            let actor = BattleActor(fighter: fighter, art: art)
            if id == 0 { actor.setWeapon(Content.shared.item("oak_staff")) }
            actor.place(at: place, facing: id >= 10 ? .right : .left)
            battleStage.addChild(actor)
            actors[id] = actor
        }
        switch moment {
        case .opening:
            march(ids)
        case .sealing:
            actors[11]?.setHealth(0.15, mana: 1)
            actors[0]?.setHealth(0.92, mana: 0.92)
            actors[1]?.setHealth(1, mana: 1)
        case .won:
            actors[0]?.setHealth(0.92, mana: 0.92)
        }
        fight = moment
    }

    /// The fight happens where you stand: the map as it is now, without you and your companion,
    /// blurred behind the battle like BattleScene's (WorldScene.battleBackdrop). Keeps the last one
    /// when the map on screen is elsewhere.
    private func takeBackdrop() {
        guard let meadow else { return }
        if patch !== meadow || mapRoot.isHidden {
            guard backdrop.texture == nil else { return }
            // Straight to a fight: the meadow where the walk ends.
            show(meadow, zoom: 0.85, looking: meadow.point(15, 9.2), focus: CGPoint(x: 160, y: 72))
        }
        let party: [SKNode] = [meadowHero, meadowPet].compactMap { $0 }
        party.forEach { $0.isHidden = true }
        let shot = snapshot()
        party.forEach { $0.isHidden = false }
        if let shot { backdrop.texture = shot }
    }

    /// What the map shows now, blurred.
    private func snapshot() -> SKTexture? {
        guard let view, let shot = view.texture(from: mapRoot, crop: CGRect(origin: .zero, size: size)) else { return nil }
        return BattleScene.blur(shot, radius: 5) ?? shot
    }

    /// Everyone walks in from off-stage to their places, one after another (BattleScene.march).
    private func march(_ ids: [Int]) {
        for (index, id) in ids.enumerated() {
            guard let actor = actors[id] else { continue }
            let offset = CGVector(dx: id >= 10 ? -220 : 220, dy: 0)
            actor.position = actor.home + offset
            actor.alpha = 0
            let duration = 0.5
            let walkIn = SKAction.customAction(withDuration: duration) { node, elapsed in
                guard let actor = node as? BattleActor else { return }
                let t = min(1, elapsed / duration)
                let eased = 1 - (1 - t) * (1 - t)
                actor.position = actor.home + offset * (1 - eased)
                actor.alpha = min(1, t * 2)
            }
            actor.run(.sequence([.wait(forDuration: 0.08 * Double(index)), walkIn]), withKey: "enter")
        }
    }

    /// The orange arrows over whoever you can pick (BattleScene.showTargets).
    private func showTargets(_ ids: [Int]) {
        arrows.forEach { $0.removeFromParent() }
        arrows = []
        for (id, actor) in actors { actor.setHighlighted(ids.contains(id)) }
        for id in ids {
            guard let actor = actors[id] else { continue }
            let arrow = SKLabelNode()
            arrow.attributedText = Nodes.outlined("▼", size: 20, color: UIColor(red: 1, green: 0.55, blue: 0.15, alpha: 1))
            arrow.position = CGPoint(x: actor.home.x, y: actor.home.y + actor.nameHeight + 8)
            arrow.zPosition = 20_000
            arrow.run(.repeatForever(.sequence([.moveBy(x: 0, y: 5, duration: 0.3), .moveBy(x: 0, y: -5, duration: 0.3)])))
            battleStage.addChild(arrow)
            arrows.append(arrow)
        }
    }

    /// A finger on one of the buttons for a moment.
    private func press(_ id: String) {
        hud.pressed = id
        run(.sequence([.wait(forDuration: 0.25), .run { [weak self] in
            if self?.hud.pressed == id { self?.hud.pressed = nil }
        }]))
    }

    /// A finger tapping a fighter to pick them.
    private func tap(fighter id: Int) {
        guard let actor = actors[id] else { return }
        hud.tap = battleStage.convert(actor.center, to: self)
        hud.taps += 1
    }

    /// A blow lands: its number, "Weak spot!" when it hit one, a flash and a shudder, and the HP bar
    /// drops to `hp` (BattleScene.impact).
    private func impact(on id: Int, _ amount: Int, hp: Double, mana: Double = 1, weakSpot: Bool = false) {
        guard let target = actors[id] else { return }
        Effects.damageBurst("-\(amount)", style: .normal, at: target.top, in: battleStage)
        if weakSpot {
            Effects.floatingText(L("Weak spot!"), color: Nodes.gold, at: target.top + CGVector(dx: 0, dy: 22), in: battleStage, size: 12)
        }
        target.sprite.flash(.red)
        target.run(.sequence([.moveBy(x: 6, y: 0, duration: 0.04), .moveBy(x: -12, y: 0, duration: 0.06), .moveBy(x: 6, y: 0, duration: 0.04)]))
        target.setHealth(hp, mana: mana)
    }

    /// Knocked out: a puff of black smoke and they're gone (BattleScene.defeat).
    private func defeat(_ id: Int) {
        guard let actor = actors[id] else { return }
        SkillEffects.smoke(at: actor.center, in: battleStage)
        actor.run(.group([.fadeOut(withDuration: 0.4), .moveBy(x: 0, y: 14, duration: 0.4)]))
    }

    /// A mage's plain attack: a violet circle at their feet and a bolt of magic from the staff
    /// (BattleScene.attack).
    private func magicBolt(at targetID: Int, damage: Int, leaving hp: Double) {
        guard let caster = actors[0], let target = actors[targetID] else { return }
        let violet = UIColor(red: 0.75, green: 0.5, blue: 1, alpha: 1)
        caster.sprite.flash(violet)
        SkillEffects.magicCircle(at: caster.position, color: violet, radius: 30, duration: 0.25, in: battleStage)
        let orb = SkillEffects.glowSprite(violet, size: CGSize(width: 26, height: 26))
        orb.addChild(SkillEffects.glowSprite(.white, size: CGSize(width: 12, height: 12)))
        orb.position = caster.center
        orb.alpha = 0
        battleStage.addChild(orb)
        let travel = SKAction.move(to: target.center, duration: 0.3)
        travel.timingMode = .easeIn
        orb.run(.sequence([
            .wait(forDuration: 0.15), .fadeIn(withDuration: 0.02), travel,
            .run { [weak self] in
                guard let self, let target = self.actors[targetID] else { return }
                SkillEffects.explosion(on: target, color: violet, level: 1, in: self.battleStage)
                self.impact(on: targetID, damage, hp: hp)
            },
            .removeFromParent(),
        ]))
    }

    /// Your companion's Pine Needles rain on both monsters.
    private func pineNeedles() {
        guard let companion = actors[1], let skill = Content.shared.skill("pine_needles") else { return }
        shout(skill.name + "!", over: 1, skill: skill)
        companion.sprite.flash(skill.tileColor)
        for id in [10, 11] {
            if let target = actors[id] { SkillEffects.needles(on: target, level: 2, in: battleStage) }
        }
        battleStage.run(.sequence([.wait(forDuration: 0.4), .run { [weak self] in
            self?.impact(on: 10, 9, hp: 0.72)
            self?.impact(on: 11, 7, hp: 0.15)
        }]))
    }

    /// The Golden Hamster spins and flings a disc of gold at you.
    private func goldenSpin() {
        guard let hamster = actors[10], let skill = Content.shared.skill("golden_spin") else { return }
        shout(skill.name + "!", over: 10, skill: skill)
        hamster.run(.sequence([.rotate(byAngle: .pi * 2, duration: 0.25), .rotate(toAngle: 0, duration: 0)]))
        battleStage.run(.sequence([
            .wait(forDuration: 0.25),
            .run { [weak self] in
                guard let self, let hamster = self.actors[10], let hero = self.actors[0] else { return }
                SkillEffects.goldenSpin(from: hamster.center, to: [hero], level: 2, in: self.battleStage)
            },
            .wait(forDuration: 0.3),
            .run { [weak self] in self?.impact(on: 0, 11, hp: 0.92) },
        ]))
    }

    /// Fire Bolt on the Golden Hamster: metal melts in fire, so it's a weak spot, and it falls.
    private func fireBolt(at targetID: Int) {
        guard let caster = actors[0], let target = actors[targetID], let skill = Content.shared.skill("fire_bolt") else { return }
        let color = skill.element?.color ?? Nodes.gold
        shout(skill.name + "!", over: 0, skill: skill)
        caster.sprite.flash(color)
        SkillEffects.flourish(on: caster, classID: "mage", raceID: "human", color: color, in: battleStage)
        // The fireball (SkillEffects.fireball, without waiting on it).
        let ball = SkillEffects.lightBall(.fire, size: 42)
        ball.position = caster.center
        ball.zPosition = 18_200
        ball.alpha = 0
        battleStage.addChild(ball)
        let travel = SKAction.move(to: target.center, duration: 0.3)
        travel.timingMode = .easeIn
        ball.run(.sequence([
            .wait(forDuration: 0.45),
            .run { [weak self, weak ball] in
                guard let self, let ball else { return }
                ball.alpha = 1
                ball.run(.repeatForever(.sequence([.scale(to: 1.12, duration: 0.05), .scale(to: 0.92, duration: 0.05)])), withKey: "flicker")
                ball.addChild(SkillEffects.trail(.fire, level: 1, parent: self.battleStage))
            },
            travel,
            .run { [weak self, weak ball] in
                guard let self else { return }
                for child in ball?.children ?? [] where child.children.contains(where: { $0 is SKEmitterNode }) {
                    SkillEffects.settle(child, in: self.battleStage)
                }
                ball?.removeAllActions()
                ball?.removeFromParent()
                guard let target = self.actors[targetID] else { return }
                SkillEffects.fireBlast(on: target, level: 1, in: self.battleStage)
                self.impact(on: targetID, 31, hp: 0, weakSpot: true)
                self.actors[0]?.setHealth(0.92, mana: 0.92)
            },
        ]))
        battleStage.run(.sequence([.wait(forDuration: 1.3), .run { [weak self] in self?.defeat(targetID) }]))
    }

    /// The move's name over whoever made it, with the skill's icon on its coloured tile in front
    /// (BattleScene.shout).
    private func shout(_ text: String, over id: Int, skill: SkillDef?) {
        guard let actor = actors[id] else { return }
        let label = SKLabelNode()
        label.attributedText = Nodes.outlined(text, size: 15, color: Nodes.gold)
        label.verticalAlignmentMode = .center
        let group = SKNode()
        group.position = actor.top + CGVector(dx: 0, dy: 36)
        group.zPosition = 22_000
        group.addChild(label)
        if let skill, let art = skill.art, let image = ArtLibrary.shared.artImage(art) {
            let side: CGFloat = 24
            let tile = SKShapeNode(rectOf: CGSize(width: side, height: side), cornerRadius: side * 0.26)
            tile.fillColor = skill.tileColor
            tile.strokeColor = UIColor(white: 1, alpha: 0.75)
            tile.lineWidth = 1.5
            let texture = SKTexture(image: image)
            texture.filteringMode = .nearest
            tile.addChild(SKSpriteNode(texture: texture, size: CGSize(width: side * 0.84, height: side * 0.84)))
            let gap: CGFloat = 4
            let total = side + gap + label.frame.width
            tile.position = CGPoint(x: -total / 2 + side / 2, y: 0)
            label.position.x = tile.position.x + side / 2 + gap + label.frame.width / 2
            group.addChild(tile)
        }
        group.setScale(0.4)
        battleStage.addChild(group)
        group.run(.sequence([
            .scale(to: 1.1, duration: 0.12), .scale(to: 1, duration: 0.08),
            .wait(forDuration: 0.7), .group([.fadeOut(withDuration: 0.3), .moveBy(x: 0, y: 12, duration: 0.3)]),
            .removeFromParent(),
        ]))
    }

    /// The field shakes on a big moment.
    private func shake() {
        battleStage.removeAction(forKey: "shake")
        let home = battleStage.position
        var moves: [SKAction] = []
        for index in 0..<6 {
            let amount = 5 * CGFloat(6 - index) / 6
            moves.append(.move(to: CGPoint(x: home.x + (index % 2 == 0 ? amount : -amount), y: home.y), duration: 0.035))
        }
        moves.append(.move(to: home, duration: 0.03))
        battleStage.run(.sequence(moves), withKey: "shake")
    }

    /// How long `seal` takes, from the stone leaving your hand to it floating home.
    private static let sealTime: TimeInterval = 5.8
    /// When the seal sets in gold and "Sealed!" rises (`seal`).
    private static let sealedAt: TimeInterval = 4.3

    /// The Seal Stone at work, as BattleScene.captureAnimation plays it: the crystal rises from your
    /// hand and glides over the monster, a seal of teal light opens under it, the monster turns to
    /// light and spirals up into the crystal, which pulses three times, lighting a mark round the
    /// seal each time, and sets in gold.
    private func seal(_ targetID: Int) {
        guard let thrower = actors[0], let target = actors[targetID] else { return }
        let stage = battleStage
        let light = SkillEffects.ElementLight.seal
        let field = Self.field

        // Everything else dims so the moment is about the stone.
        let dim = SKSpriteNode(color: .black, size: CGSize(width: field.width * 3, height: field.height * 3))
        dim.position = CGPoint(x: field.width / 2, y: field.height / 2)
        dim.zPosition = 14_000
        dim.alpha = 0
        stage.addChild(dim)
        dim.run(.fadeAlpha(to: 0.35, duration: 0.4))

        // The crystal, in a soft halo of its own light.
        let stone = SKNode()
        stone.position = thrower.center
        stone.zPosition = 15_000
        let halo = SkillEffects.lightBall(light, size: 70, tint: 0.35, core: false)
        halo.zPosition = -0.5
        halo.alpha = 0.7
        stone.addChild(halo)
        let crystal = SKSpriteNode(texture: SkillEffects.sealStoneTexture, size: CGSize(width: 34, height: 34))
        stone.addChild(crystal)
        stone.alpha = 0
        stone.setScale(0.4)
        stage.addChild(stone)
        halo.run(.repeatForever(.sequence([.scale(to: 1.15, duration: 0.45), .scale(to: 0.9, duration: 0.45)])))

        // It lifts off your hand and glides over, trailing motes.
        let lifted = thrower.center + CGVector(dx: 0, dy: 22)
        let hover = target.center + CGVector(dx: 0, dy: target.height * 0.5 + 30)
        let path = CGMutablePath()
        path.move(to: lifted)
        path.addQuadCurve(to: hover, control: CGPoint(x: (lifted.x + hover.x) / 2, y: max(lifted.y, hover.y) + 50))
        let glide = SKAction.follow(path, asOffset: false, orientToPath: false, duration: 0.6)
        glide.timingMode = .easeInEaseOut
        let motes = SKAction.repeat(.sequence([.run { [weak stone, weak stage] in
            guard let stone, let stage else { return }
            let mote = SkillEffects.glowSprite(light.bright, size: CGSize(width: 7, height: 7))
            mote.position = stone.position + CGVector(dx: .random(in: -6...6), dy: .random(in: -6...6))
            mote.zPosition = 14_900
            stage.addChild(mote)
            mote.run(.sequence([.group([.fadeOut(withDuration: 0.35), .moveBy(x: 0, y: -10, duration: 0.35), .scale(to: 0.3, duration: 0.35)]),
                                .removeFromParent()]))
        }, .wait(forDuration: 0.035)]), count: 17)
        stone.run(.sequence([
            .group([.fadeIn(withDuration: 0.18), .scale(to: 1, duration: 0.25), .moveBy(x: 0, y: 22, duration: 0.25)]),
            .group([glide, motes]),
        ]))
        crystal.run(.sequence([.wait(forDuration: 0.85),
                               .repeatForever(.sequence([.moveBy(x: 0, y: 3, duration: 0.4), .moveBy(x: 0, y: -3, duration: 0.4)]))]),
                    withKey: "bob")

        // The seal opens under the monster and the crystal's light falls on it; the monster turns to
        // light and pours up into the crystal; the crystal pulses, a mark lighting each time; sealed.
        let radius = max(40, target.height * 0.55)
        let circle = SkillEffects.SealCircle(radius: radius, marks: 3)
        circle.position = target.position
        let beam = SkillEffects.streak(light, size: CGSize(width: 22, height: hover.y - target.position.y), tint: 0.25)
        beam.position = CGPoint(x: target.position.x, y: (hover.y + target.position.y) / 2)
        beam.zPosition = 14_500
        beam.alpha = 0
        var steps: [SKAction] = [
            .wait(forDuration: 0.85),
            .run { [weak stage] in
                stage?.addChild(circle)
                circle.open()
                stage?.addChild(beam)
                beam.run(.fadeAlpha(to: 0.75, duration: 0.2))
            },
            .wait(forDuration: 0.3),
            .run { [weak stage, weak target] in
                guard let stage, let target else { return }
                SkillEffects.sealSpiral(from: target.position, to: hover, radius: radius, count: 30, in: stage)
                target.sprite.color = light.bright
                target.run(.group([
                    .customAction(withDuration: 0.2) { node, elapsed in
                        (node as? BattleActor)?.sprite.colorBlendFactor = min(1, elapsed / 0.2)
                    },
                    .sequence([.wait(forDuration: 0.15), .group([
                        .scaleX(to: 0.4, duration: 0.45), .scaleY(to: 1.4, duration: 0.45),
                        .moveBy(x: 0, y: 24, duration: 0.45), .fadeOut(withDuration: 0.45),
                    ])]),
                ]))
            },
            .wait(forDuration: 0.9),
            .run { [weak self] in
                guard let self else { return }
                beam.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
                SkillEffects.screenFlash(color: light.core, strength: 0.35, size: self.size, in: self)
                halo.run(.sequence([.scale(to: 1.8, duration: 0.1), .scale(to: 1, duration: 0.2)]))
            },
        ]
        for index in 0..<3 {
            steps.append(.wait(forDuration: 0.32))
            steps.append(.run { [weak stage, weak stone] in
                guard let stage, let stone else { return }
                SkillEffects.ring(at: stone.position, color: light.main, size: CGSize(width: 34, height: 34), grow: 2.6, in: stage)
                circle.light(mark: index)
                crystal.run(.sequence([
                    .group([.scale(to: 1.18, duration: 0.08), .rotate(toAngle: 0.14, duration: 0.08)]),
                    .rotate(toAngle: -0.14, duration: 0.12),
                    .group([.scale(to: 1, duration: 0.1), .rotate(toAngle: 0, duration: 0.1)]),
                ]))
            })
            steps.append(.wait(forDuration: 0.3))
        }
        steps += [
            .wait(forDuration: 0.35),
            .run { [weak stage, weak stone] in
                guard let stage, let stone else { return }
                // Sealed: the seal closes in gold into the crystal, which shines.
                circle.close()
                SkillEffects.rays(at: stone.position, color: Nodes.gold, count: 10, length: 70, width: 6, z: 14_800, in: stage)
                SkillEffects.burst(at: stone.position, color: Nodes.gold, count: 24, speed: 100, in: stage)
                crystal.removeAction(forKey: "bob")
                crystal.color = Nodes.gold
                crystal.run(.sequence([.colorize(withColorBlendFactor: 0.6, duration: 0.1), .colorize(withColorBlendFactor: 0, duration: 0.4)]))
                Effects.floatingText(L("Sealed!"), color: Nodes.gold, at: stone.position + CGVector(dx: 0, dy: 36), in: stage, size: 24)
                stone.run(.sequence([.scale(to: 1.45, duration: 0.12), .scale(to: 1.1, duration: 0.12)]))
            },
            .wait(forDuration: 0.74),
            .run { [weak stone, weak thrower] in
                guard let stone, let thrower else { return }
                // It floats home to your hand.
                let home = SKAction.move(to: thrower.center, duration: 0.45)
                home.timingMode = .easeInEaseOut
                stone.run(.sequence([.group([home, .scale(to: 0.4, duration: 0.45), .sequence([.wait(forDuration: 0.3), .fadeOut(withDuration: 0.15)])]),
                                     .removeFromParent()]))
                dim.run(.sequence([.wait(forDuration: 0.45), .fadeOut(withDuration: 0.3), .removeFromParent()]))
            },
        ]
        stage.run(.sequence(steps))
    }

    /// A level up with the win: light pours down on you in a burst of gold and "LEVEL UP!" fills the
    /// field, and your bars fill up (BattleScene.celebrateLevelUp).
    private func levelUp(to level: Int) {
        guard let hero = actors[0] else { return }
        let gold = Nodes.gold
        hero.setHealth(1, mana: 1)
        SkillEffects.screenFlash(color: gold, strength: 0.3, size: size, in: self)
        SkillEffects.lightPillar(on: hero, level: 5, in: battleStage)
        SkillEffects.glory(on: hero, color: gold, level: 5, in: battleStage)
        SkillEffects.burst(at: hero.center, color: gold, count: 24, speed: 130, in: battleStage)
        hero.sprite.run(.sequence([.moveBy(x: 0, y: 18, duration: 0.16), .moveBy(x: 0, y: -18, duration: 0.2)]), withKey: "cheer")
        let banner = SKNode()
        banner.position = CGPoint(x: size.width / 2, y: size.height * 0.58)
        banner.zPosition = 31_000
        let title = NameTag(L("LEVEL UP!"), color: gold, size: 26, alignment: .center)
        let subtitle = NameTag(L("Level {level}", ["level": level]), color: .white, size: 13, alignment: .center)
        subtitle.position.y = -24
        banner.addChild(title)
        banner.addChild(subtitle)
        banner.setScale(0.3)
        banner.alpha = 0
        addChild(banner)
        SkillEffects.rays(at: banner.position, color: gold, count: 14, length: 100, width: 8, z: 30_900, in: self)
        banner.run(.sequence([
            .group([.fadeIn(withDuration: 0.12), .scale(to: 1.2, duration: 0.2)]),
            .scale(to: 1, duration: 0.12),
            .wait(forDuration: 1.1),
            .group([.fadeOut(withDuration: 0.3), .moveBy(x: 0, y: 16, duration: 0.3)]),
            .removeFromParent(),
        ]))
    }

    // MARK: - Pieces

    /// A soft, glowing light.
    @discardableResult
    private func glow(_ color: UIColor, size side: CGFloat, at point: CGPoint, in parent: SKNode? = nil) -> SKSpriteNode {
        let node = SKSpriteNode(texture: SoftTextures.glow, size: CGSize(width: side, height: side))
        node.color = color
        node.colorBlendFactor = 1
        node.blendMode = .add
        node.position = point
        node.zPosition = parent == nil ? 2_000 : -1
        (parent ?? self).addChild(node)
        return node
    }

    /// One of the map ambiences' particles (petals, snow…), drifting over the whole picture.
    private func particles(_ kind: String) {
        particleLayer(kind)
    }

    /// The particles in a layer of their own, to show and hide.
    @discardableResult
    private func particleLayer(_ kind: String) -> SKNode {
        let layer = SKNode()
        layer.zPosition = 2_500
        for emitter in Ambience.emitters(kind) {
            emitter.position = CGPoint(x: size.width / 2, y: size.height / 2 + 30)
            emitter.particlePositionRange = CGVector(dx: size.width + 60, dy: size.height + 60)
            layer.addChild(emitter)
            emitter.advanceSimulationTime(TimeInterval(emitter.particleLifetime))
        }
        addChild(layer)
        return layer
    }

    /// A spark lifting off the land and drifting up into Liora's light.
    private func riseToTheLight() {
        let star = SKSpriteNode(texture: SoftTextures.star, size: CGSize(width: 7, height: 7))
        star.color = Nodes.gold
        star.colorBlendFactor = 0.5
        star.blendMode = .add
        star.position = CGPoint(x: CGFloat.random(in: 10...350), y: CGFloat.random(in: 8...100))
        star.zPosition = 2_100
        star.alpha = 0
        addChild(star)
        let target = CGPoint(x: 180 + CGFloat.random(in: -14...14), y: 150 + CGFloat.random(in: -8...8))
        let fly = SKAction.move(to: target, duration: TimeInterval.random(in: 1.6...2.4))
        fly.timingMode = .easeIn
        star.run(.sequence([
            .fadeIn(withDuration: 0.3),
            .group([fly, .sequence([.wait(forDuration: 1.2), .fadeOut(withDuration: 0.5)])]),
            .removeFromParent(),
        ]))
    }
}
