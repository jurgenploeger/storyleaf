import CoreImage
import SpriteKit

/// The battle stage, Fairyland-style: the fight happens right where you were walking (a
/// snapshot of the map), fighters stand on ground circles in two diagonal lines, and every
/// skill has its own effect that grows with the skill's level.
final class BattleScene: SKScene {
    private let controller: BattleController
    private let art = ArtLibrary.shared
    /// Everything that shakes on big hits.
    private let stage = SKNode()
    private let backdrop: SKTexture?
    private lazy var blurredBackdrop: SKTexture? = backdrop.flatMap { Self.blur($0, radius: 5) }
    private var ground: SKNode?
    private var actors: [Int: BattleActor] = [:]
    private var markers: [SKNode] = []
    /// Fainted friends shown faintly while you choose who to revive.
    private var ghosts: Set<Int> = []
    /// While a special attack plays: its colour and tier, so every blow it lands flares in its light
    /// (SkillFlares.swift).
    private var flareLight: (color: UIColor, level: Int)?

    init(controller: BattleController, size: CGSize, backdrop: SKTexture?) {
        self.controller = controller
        self.backdrop = backdrop
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = UIColor(red: 0.2, green: 0.35, blue: 0.3, alpha: 1)
        addChild(stage)
        for fighter in controller.combatants {
            let actor = BattleActor(fighter: fighter, art: art)
            if fighter.isHero {
                actor.setGear(weapon: controller.session.equipped(.weapon), accessory: controller.session.equipped(.accessory))
            } else if let person = controller.person(behind: fighter) {
                // Friends and rivals fight with a weapon of their own, as you do.
                actor.setGear(weapon: GameSession.weapon(for: person), accessory: nil)
            }
            actors[fighter.id] = actor
            stage.addChild(actor)
        }
        controller.scene = self
        layout()
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didMove(to view: SKView) {
        MusicPlayer.shared.play(controller.music)
        setPace(controller.speed)
        layout()
        enter()
    }

    /// Whose move you're choosing, its ring lit: your hero, then your companion.
    private var chooserID: Int?

    override func update(_ currentTime: TimeInterval) {
        // Checked each frame: the controller decides whose choice it is, and when.
        let deciding: [BattleController.Phase] = [.command, .skills, .items, .stones, .target]
        let chooser = controller.choosingForCompanion ? controller.companion : controller.hero
        let choosing = controller.hasBegun && deciding.contains(controller.phase) && chooser?.isAlive == true ? chooser?.id : nil
        guard choosing != chooserID else { return }
        if let old = chooserID { actors[old]?.setChoosing(false) }
        chooserID = choosing
        if let choosing { actors[choosing]?.setChoosing(true) }
    }

    /// How fast everything on the field plays (BattleController.speed: 1, or 2 with the 2× button).
    func setPace(_ value: Double) {
        speed = CGFloat(value)
    }

    /// Both sides march in from off-stage at the start, monsters hopping into place; your first
    /// turn (and its clock) starts once they're all in. The scene sits still through the fade in,
    /// so the wait starts after it.
    private func enter() {
        let duration = march(actors.values.sorted(by: { $0.fighterID < $1.fighterID }))
        run(.sequence([.wait(forDuration: duration), .run { [weak self] in self?.controller.begin() }]), withKey: "enter")
    }

    /// Fighters walk in from off-stage to their places, one after another (a boss fight's next
    /// wave comes in the same way). Returns how long until the last one is in place.
    @discardableResult
    private func march(_ group: [BattleActor]) -> TimeInterval {
        for (index, actor) in group.enumerated() {
            let isEnemy = controller.enemies.contains { $0.id == actor.fighterID }
            let offset = isPortrait
                ? CGVector(dx: isEnemy ? -60 : 60, dy: isEnemy ? 160 : -160)
                : CGVector(dx: isEnemy ? -220 : 220, dy: 0)
            actor.position = actor.home + offset
            actor.alpha = 0
            // Track `home` every frame: the layout can still change while they walk in.
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
        return 0.08 * Double(max(0, group.count - 1)) + 0.5
    }

    override func didChangeSize(_ oldSize: CGSize) {
        layout()
    }

    // MARK: - Layout

    private var isPortrait: Bool { size.height > size.width }
    /// How far a portrait line climbs for each point it runs right (26 up for 108 across).
    private static let portraitSlope: CGFloat = 26.0 / 108.0
    /// How far apart neighbours stand in a portrait line: the same in every line on both sides, so
    /// five of yours stand as far apart as five monsters (`layout` works it out).
    private var lineSpacing: CGFloat = 108
    /// On its side, how far down each fighter in a line stands from the one before: 76, closer in a
    /// long line so all of it fits under the HUD's top row (`layout` works it out).
    private var landscapeStep: CGFloat = 76
    /// On its side, the lowest and highest a fighter's spot may be: its nameplate clear of the
    /// bottom, its head clear of the HUD's top row.
    private var landscapeFloor: CGFloat = 0
    private var landscapeCeiling: CGFloat = 0
    /// A fighter's height above its spot, and its nameplate's depth below it.
    private static let headroom: CGFloat = 56
    private static let plateDepth: CGFloat = 30
    /// Upright, how big everyone stands: a crowded field (both sides with friends and companions)
    /// shrinks everybody a little, and its rows close up to match, so the two sides keep a gap
    /// between them (`layout` works it out).
    private var fieldScale: CGFloat = 1

    /// Upright, room at the top for the HUD: below the Dynamic Island (or the clock), the message
    /// line and the chat, and in a boss fight its waves under that, with the field kept well clear
    /// of them.
    private var portraitTopInset: CGFloat {
        (view?.safeAreaInsets.top ?? 0) + (controller.waveCount > 1 ? 176 : 150)
    }

    private func layout() {
        guard size.width > 1, size.height > 1 else { return }
        buildGround()
        // Leave room for the HUD: your faces and the message line along the top, the command wheel
        // bottom-right.
        let insets: (top: CGFloat, bottom: CGFloat) = isPortrait ? (portraitTopInset, 240) : (70, 40)
        let area = CGRect(x: 0, y: insets.bottom, width: size.width, height: max(120, size.height - insets.top - insets.bottom))
        lineSpacing = sharedSpacing()
        // Up to eight on the field at full size; past that everyone shrinks a little more with
        // each, down to 78% for a full field of fifteen or more.
        let crowd = controller.enemiesOnField.count + controller.party.count
        fieldScale = isPortrait ? min(1, max(0.78, 1 - CGFloat(crowd - 8) * 0.03)) : 1
        if isPortrait {
            // Monsters up on the left looking down-right at your party, which stands lower on the
            // right looking back up-left; both lines sit around the middle of the screen.
            // A wide gap between the sides, so it reads as two lines facing off. The monsters' line
            // is centred across the screen however many there are, not bunched up on the left.
            // Shrunk, the monsters also stand a little higher (there's room under the HUD once they're
            // smaller), opening up the gap between the sides.
            let lift = (1 - fieldScale) * 0.3
            arrange(controller.enemiesOnField, around: CGPoint(x: area.midX, y: area.minY + area.height * (0.64 + lift)), facing: .down)
            arrange(controller.party, around: CGPoint(x: area.midX + 50, y: area.minY + area.height * 0.06), facing: .up)
        } else {
            landscapeFloor = area.minY + Self.plateDepth
            landscapeCeiling = area.maxY - Self.headroom
            // Companions stand a little above whoever they came with.
            let climb = max(0, companionOffset(facing: .left).dy)
            let longest = (lines(of: controller.enemiesOnField, facing: .right) + lines(of: controller.party, facing: .left)).map(\.count).max() ?? 1
            landscapeStep = longest > 1 ? min(76, max(36, (landscapeCeiling - landscapeFloor - climb) / CGFloat(longest - 1))) : 76
            arrange(controller.enemiesOnField, around: CGPoint(x: area.minX + area.width * 0.28, y: area.midY + 4), facing: .right)
            arrange(controller.party, around: CGPoint(x: area.minX + area.width * 0.6, y: area.midY - 24), facing: .left)
        }
        showTargets(controller.validTargets)
    }

    /// Fighters stand in diagonal lines of up to five, like Fairyland's battle formation; a bigger
    /// group forms a second row behind the first. Someone alone with their companion (you without a
    /// friend, or a lone rival) stands side by side with it in one line. With friends, companions
    /// stand right behind whoever they came with: the people make the line, and their companions a
    /// row back.
    private func arrange(_ group: [Combatant], around center: CGPoint, facing: Direction) {
        let ids = Set(group.map(\.id))
        let followers = group.filter { fighter in fighter.ownerID.map { ids.contains($0) } == true }
        guard !followers.isEmpty else {
            let rows = stride(from: 0, to: group.count, by: 5).map { Array(group[$0..<min($0 + 5, group.count)]) }
            arrange(rows: rows, around: center, facing: facing)
            return
        }
        let leaders = group.filter { fighter in !followers.contains { $0.id == fighter.id } }
        if leaders.count == 1 {
            // Side by side: the person first, then their companion.
            arrange(rows: [leaders + followers], around: center, facing: facing)
            return
        }
        let front = rowShift(depth: 0.5, facing: facing)
        let behind = companionOffset(facing: facing)
        let escorted = Set(leaders.indices.filter { index in followers.contains { $0.ownerID == leaders[index].id } })
        let points = linePoints(count: leaders.count, around: center + front, facing: facing, trailing: behind, escorted: escorted)
        for (fighter, point) in zip(leaders, points) {
            actors[fighter.id]?.place(at: point, facing: Self.profile(facing), scale: fieldScale)
        }
        for follower in followers {
            guard let index = leaders.firstIndex(where: { $0.id == follower.ownerID }) else { continue }
            actors[follower.id]?.place(at: points[index] + behind, facing: Self.profile(facing), scale: fieldScale)
        }
    }

    private func arrange(rows: [[Combatant]], around center: CGPoint, facing: Direction) {
        // The first row stands at the back, away from the other side.
        var centers = rows.indices.map { index in
            center + rowShift(depth: CGFloat(index) - CGFloat(rows.count - 1) / 2, facing: facing)
        }
        // On its side, the rows move over together where one would reach under the Dynamic Island
        // (linePoints would move just that one, onto the row in front).
        if !isPortrait, let sides = landscapeSides {
            let ends = zip(rows, centers).map { row, point in
                (left: point.x - landscapeSpacing * CGFloat(row.count - 1) / 2, right: point.x + landscapeSpacing * CGFloat(row.count - 1) / 2)
            }
            let left = ends.map { $0.left }.min() ?? sides.lowerBound
            let right = ends.map { $0.right }.max() ?? sides.upperBound
            let shift = left < sides.lowerBound ? sides.lowerBound - left : right > sides.upperBound ? sides.upperBound - right : 0
            centers = centers.map { CGPoint(x: $0.x + shift, y: $0.y) }
        }
        for (row, point) in zip(rows, centers) {
            arrangeLine(row, around: point, facing: facing)
        }
    }

    /// On its side, how far apart neighbours in a line stand: 56, a little more in a long line
    /// closed up to fit (`landscapeStep`).
    private var landscapeSpacing: CGFloat { 56 + (76 - landscapeStep) / 2 }

    /// On its side, how far left and right a fighter may stand: its nameplate clear of the Dynamic
    /// Island and the rounded corners, whichever side they're on.
    private var landscapeSides: ClosedRange<CGFloat>? {
        let left = (view?.safeAreaInsets.left ?? 0) + 44
        let right = size.width - (view?.safeAreaInsets.right ?? 0) - 44
        return left < right ? left...right : nil
    }

    /// From a fighter to the companion standing behind them, one row back.
    private func companionOffset(facing: Direction) -> CGVector {
        let front = rowShift(depth: 0.5, facing: facing)
        let back = rowShift(depth: -0.5, facing: facing)
        return CGVector(dx: back.dx - front.dx, dy: back.dy - front.dy)
    }

    /// The lines a side stands in, as `arrange` lays them out: its people in one (their companions
    /// a row back), someone alone side by side with their companion, or, with no companions, rows of
    /// up to five; and how far a companion behind the first or last one sticks out past the end.
    private func lines(of group: [Combatant], facing: Direction) -> [(count: Int, overhang: CGFloat)] {
        let ids = Set(group.map(\.id))
        let followers = group.filter { fighter in fighter.ownerID.map { ids.contains($0) } == true }
        guard !followers.isEmpty else {
            return stride(from: 0, to: group.count, by: 5).map { (count: min(5, group.count - $0), overhang: 0) }
        }
        let leaders = group.filter { fighter in !followers.contains { $0.id == fighter.id } }
        if leaders.count == 1 { return [(count: group.count, overhang: 0)] }
        let behind = companionOffset(facing: facing)
        let end = behind.dx < 0 ? leaders.first : leaders.last
        let escorted = end.map { leader in followers.contains { $0.ownerID == leader.id } } ?? false
        return [(count: leaders.count, overhang: escorted ? abs(behind.dx) : 0)]
    }

    /// One spacing for every portrait line in the fight, both sides: the widest (up to 108) that
    /// still fits the most crowded line on screen, with any companion at its end.
    private func sharedSpacing() -> CGFloat {
        let all = lines(of: controller.enemiesOnField, facing: .down) + lines(of: controller.party, facing: .up)
        return all.filter { $0.count > 1 }
            .map { (size.width - 100 - $0.overhang) / CGFloat($0.count - 1) }
            .reduce(108, min)
    }

    /// Where a row stands from the middle of the formation, `depth` rows toward the other side
    /// (negative: back, away from it): up-left for monsters, down-right for you.
    private func rowShift(depth: CGFloat, facing: Direction) -> CGVector {
        let toward: CGFloat = facing == .right || facing == .down ? 1 : -1
        return isPortrait
            ? CGVector(dx: depth * 36 * fieldScale * (facing == .down ? 1 : -1), dy: depth * 74 * fieldScale * (facing == .down ? -1 : 1))
            : CGVector(dx: depth * 70 * toward, dy: -depth * 20)
    }

    /// Which way fighters look: across at the other side in profile, as in Fairyland's battles. In
    /// portrait the two lines face off up and down the screen, but people still turn sideways, your
    /// party to the left toward the monsters up on the left and those to the right, instead of
    /// showing their backs. (Monsters have only a front view, so they look the same either way.)
    private static func profile(_ facing: Direction) -> Direction {
        switch facing {
        case .up: .left
        case .down: .right
        default: facing
        }
    }

    private func arrangeLine(_ group: [Combatant], around center: CGPoint, facing: Direction) {
        for (fighter, point) in zip(group, linePoints(count: group.count, around: center, facing: facing)) {
            actors[fighter.id]?.place(at: point, facing: Self.profile(facing), scale: fieldScale)
        }
    }

    /// Spots for a line of `count` fighters around `center`, evenly spaced. `trailing`: from each one
    /// to the companion standing behind them; `escorted`: which of them have one, kept on screen too.
    private func linePoints(count: Int, around center: CGPoint, facing: Direction, trailing: CGVector = .zero,
                            escorted: Set<Int> = []) -> [CGPoint] {
        // Only a companion behind the first or last one sticks out past the end of the line, so
        // room is kept for it only then: a line without spreads across the screen, centred.
        let extraLeft = trailing.dx < 0 && escorted.contains(0) ? -trailing.dx : 0
        let extraRight = trailing.dx > 0 && escorted.contains(count - 1) ? trailing.dx : 0
        // Every line in the fight is spaced alike, closed up enough for the longest to fit; in
        // portrait a line then slides over so everyone stays on screen.
        // On its side, a line closed up to fit spreads out a little sideways instead.
        let spacing = isPortrait ? lineSpacing : landscapeSpacing
        var center = center
        if isPortrait, count > 1 {
            let half = spacing * CGFloat(count - 1) / 2
            center.x = min(max(center.x, 50 + half + extraLeft), size.width - 50 - half - extraRight)
        }
        if !isPortrait, count > 1 {
            // The whole line, companions behind included, between the bottom and the HUD's top row,
            // and its ends clear of the Dynamic Island's side (spread out, a long line reached under it).
            let half = landscapeStep * CGFloat(count - 1) / 2
            let climb = escorted.isEmpty ? 0 : max(0, trailing.dy)
            center.y = min(max(center.y, landscapeFloor + half), landscapeCeiling - climb - half)
            if let sides = landscapeSides {
                let across = spacing * CGFloat(count - 1) / 2
                let left = sides.lowerBound + across + extraLeft, right = sides.upperBound - across - extraRight
                if left <= right { center.x = min(max(center.x, left), right) }
            }
        }
        // Each fighter stands a step up from the last, at the same angle on both sides however
        // many stand in a line (a fixed step tilted a packed line of five more than a line of two).
        let rise = isPortrait ? spacing * Self.portraitSlope : -landscapeStep
        // Only your party needs lifting clear of the command wheel; monsters stay where they are
        // so a long line (and a second row behind it) doesn't climb off the top.
        if isPortrait, count > 1, facing == .up {
            // Its lowest fighter stands where one alone would.
            center.y += rise * CGFloat(count - 1) / 2
        }
        return (0..<count).map { index in
            let offset = CGFloat(index) - CGFloat(count - 1) / 2
            return CGPoint(x: center.x + offset * spacing, y: center.y + offset * rise)
        }
    }

    private func buildGround() {
        ground?.removeFromParent()
        let node = SKNode()
        node.zPosition = -10_000
        if let backdrop {
            // The map you were standing on, softly blurred so the fighters stand out.
            let sprite = SKSpriteNode(texture: blurredBackdrop ?? backdrop)
            let scale = max(size.width / backdrop.size().width, size.height / backdrop.size().height)
            sprite.size = backdrop.size() * scale
            sprite.position = CGPoint(x: size.width / 2, y: size.height / 2)
            node.addChild(sprite)
        } else {
            let texture = art.tileTexture("tile_grass")
            let tile: CGFloat = 32
            for col in 0...Int(size.width / tile) {
                for row in 0...Int(size.height / tile) {
                    let sprite = SKSpriteNode(texture: texture, size: CGSize(width: tile, height: tile))
                    sprite.anchorPoint = .zero
                    sprite.position = CGPoint(x: CGFloat(col) * tile, y: CGFloat(row) * tile)
                    node.addChild(sprite)
                }
            }
        }
        let shade = SKSpriteNode(color: UIColor(red: 0.05, green: 0.08, blue: 0.2, alpha: backdrop == nil ? 0.3 : 0.38), size: size)
        shade.anchorPoint = .zero
        shade.zPosition = 2
        node.addChild(shade)
        stage.addChild(node)
        ground = node
    }

    /// Gaussian-blurs a texture once, clamping the edges so the borders don't fade out. (The story's
    /// pictures blur their fights' backdrops with it too, StoryScene.)
    static func blur(_ texture: SKTexture, radius: Double) -> SKTexture? {
        let source = CIImage(cgImage: texture.cgImage())
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(source.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage?.cropped(to: source.extent),
              let image = CIContext(options: nil).createCGImage(output, from: source.extent)
        else { return nil }
        let blurred = SKTexture(cgImage: image)
        blurred.filteringMode = .linear
        return blurred
    }

    // MARK: - Targeting

    /// `labels`: a word over some of them, above the arrow (a Seal Stone's odds on each monster).
    func showTargets(_ ids: [Int], labels: [Int: String] = [:]) {
        markers.forEach { $0.removeFromParent() }
        markers = []
        for id in ghosts where !ids.contains(id) { actors[id]?.alpha = 0 }
        ghosts = ghosts.filter { ids.contains($0) }
        for id in ids {
            guard let actor = actors[id] else { continue }
            // A fainted friend (for Revive) has faded away: show it as a ghost to tap.
            if controller.combatants.first(where: { $0.id == id })?.isFallen == true {
                actor.alpha = 0.45
                ghosts.insert(id)
            }
            let arrow = SKLabelNode()
            arrow.attributedText = Nodes.outlined("▼", size: 20, color: UIColor(red: 1, green: 0.55, blue: 0.15, alpha: 1))
            // Above the name over the fighter's head, where they stand: a wave still marching in
            // (or a fighter stepping back from a blow) would leave it hanging where they were.
            arrow.position = CGPoint(x: actor.home.x, y: actor.home.y + actor.nameHeight * actor.fieldScale + 8)
            arrow.zPosition = 20_000
            arrow.run(.repeatForever(.sequence([.moveBy(x: 0, y: 5, duration: 0.3), .moveBy(x: 0, y: -5, duration: 0.3)])))
            stage.addChild(arrow)
            markers.append(arrow)
            if let text = labels[id] {
                let label = SKLabelNode()
                label.attributedText = Nodes.outlined(text, size: 14, color: UIColor(red: 0.62, green: 1, blue: 0.9, alpha: 1))
                label.position = CGPoint(x: actor.home.x, y: arrow.position.y + 22)
                label.zPosition = 20_000
                stage.addChild(label)
                markers.append(label)
            }
            actor.setHighlighted(true)
        }
        for (id, actor) in actors where !ids.contains(id) {
            actor.setHighlighted(false)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        // Fainted friends count too: they're who Revive is for.
        let candidates = actors.values.filter { controller.validTargets.contains($0.fighterID) }
        guard let tapped = candidates.min(by: { $0.center.distance(to: point) < $1.center.distance(to: point) }),
              tapped.center.distance(to: point) < 80
        else { return }
        controller.select(tapped.fighterID)
    }

    // MARK: - Playback

    func play(_ events: [BattleEvent]) async {
        var index = 0
        while index < events.count {
            // Everyone one blow knocks out (a sweep, a spell and its splash) falls at once.
            var fallen: [Int] = []
            while index < events.count, case .defeated(let id) = events[index] {
                fallen.append(id)
                index += 1
            }
            if !fallen.isEmpty {
                await defeat(fallen)
                refreshBars()
                continue
            }
            // Likewise everyone one spell raises or lowers shows it at once (a ward over the party).
            var changed = 0
            while index < events.count, case .statsChanged(let id, let changes, _) = events[index] {
                controller.apply(events[index])
                if let actor = actors[id] { SkillEffects.statChanges(changes, on: actor, in: stage) }
                changed += 1
                index += 1
            }
            if changed > 0 {
                await pause(0.75)
                refreshBars()
                continue
            }
            // Everyone the ice holds shivers at once, and poison bites the whole field at once, with
            // whoever it finishes off falling together after.
            var frozen: [Int] = []
            while index < events.count, case .frozen(let id) = events[index] {
                controller.apply(events[index])
                if let actor = actors[id] { SkillEffects.frozenShiver(on: actor, in: stage) }
                frozen.append(id)
                index += 1
            }
            if !frozen.isEmpty {
                await pause(0.6)
                refreshBars()
                continue
            }
            var bitten = 0
            var poisoned: [Int] = []
            while index < events.count {
                if case .ailmentDamage(let id, _, let amount) = events[index] {
                    controller.apply(events[index])
                    if let actor = actors[id] { poisonBite(on: actor, amount: amount) }
                    bitten += 1
                } else if bitten > 0, case .defeated(let id) = events[index] {
                    poisoned.append(id)
                } else {
                    break
                }
                index += 1
            }
            if bitten > 0 {
                await pause(0.55)
                refreshBars()
                if !poisoned.isEmpty {
                    await defeat(poisoned)
                    refreshBars()
                }
                continue
            } else {
                await animate(events[index])
                index += 1
            }
            refreshBars()
        }
    }

    /// Poison's bite on one fighter: it shudders, and the HP it loses floats up.
    private func poisonBite(on actor: BattleActor, amount: Int) {
        SkillEffects.poisonBite(on: actor, in: stage)
        Effects.damageBurst("-\(amount)", style: .poison, at: actor.top, in: stage)
        // Named, so it's clear the HP went to the poison and not to a blow.
        Effects.floatingText(L("Poison"), color: SkillEffects.color(of: .poison), at: actor.top + CGVector(dx: 0, dy: 24), in: stage, size: 12)
    }

    /// Fighters knocked out together fall together: a puff of black smoke each and one fade, so a
    /// sweep that wins the fight doesn't wait on every monster in turn.
    private func defeat(_ ids: [Int]) async {
        controller.applyDefeats(ids)
        let fallen = ids.compactMap { actors[$0] }
        for actor in fallen {
            SkillEffects.smoke(at: actor.center, in: stage)
            actor.run(.group([.fadeOut(withDuration: 0.4), .moveBy(x: 0, y: 14, duration: 0.4)]), withKey: "defeat")
        }
        await pause(fallen.isEmpty ? 0.2 : 0.6)
    }

    private func animate(_ event: BattleEvent) async {
        switch event {
        case .attack(let actorID, let hit):
            await attack(by: actorID, hit: hit) { self.controller.apply(event) }
            await pause(0.3)

        case .skill(let actorID, let skill, let level, let hits):
            controller.apply(event)
            shout(skill.name + "!", over: actorID, color: skill.element?.color, skill: skill)
            await castSkill(skill, level: level, from: actorID, hits: hits)
            await pause(0.35)

        case .item(_, _, let target, let hp, let mp):
            controller.apply(event)
            if let actor = actors[target] {
                SkillEffects.sparkles(on: actor, color: SkillEffects.healGreen, level: 1, in: stage)
                Effects.damageBurst(hp > 0 ? "+\(hp)" : L("+{amount} MP", ["amount": mp]), style: .heal, at: actor.top, in: stage)
            }
            await pause(0.5)

        case .defend(let actorID):
            controller.apply(event)
            if let actor = actors[actorID] {
                SkillEffects.shield(on: actor, in: stage)
                Effects.floatingText(L("Guard!"), color: UIColor(red: 0.6, green: 0.85, blue: 1, alpha: 1), at: actor.top, in: stage, size: 14)
            }
            await pause(0.45)

        case .capture(let actorID, let targetID, let success, let wobbles, let stoneID):
            let stone = stoneID.flatMap(controller.session.content.item)
            controller.announce(L("{name} throws a {stone}!", ["name": controller.name(actorID), "stone": stone?.name ?? L("Seal Stone")]))
            await captureAnimation(from: actorID, to: targetID, success: success, wobbles: wobbles, art: stone?.art)
            controller.apply(event)
            await pause(0.6)

        case .fled(let id):
            controller.apply(event)
            if let actor = actors[id] {
                // A panicked hop or two, then off it goes in a puff of dust.
                let away: CGFloat = actor.position.x > size.width / 2 ? 1 : -1
                let hop = SKAction.sequence([.moveBy(x: away * 14, y: 16, duration: 0.12), .moveBy(x: away * 14, y: -16, duration: 0.12)])
                await actor.run(.repeat(hop, count: 2))
                SkillEffects.smoke(at: actor.center, in: stage)
                await actor.run(.group([.moveBy(x: away * size.width * 0.6, y: 0, duration: 0.35), .fadeOut(withDuration: 0.35)]))
            }
            await pause(0.3)

        case .escape(_, let success):
            controller.apply(event)
            if success {
                let dx: CGFloat = isPortrait ? 0 : size.width
                let dy: CGFloat = isPortrait ? -size.height : 0
                for actor in actors.values where controller.party.contains(where: { $0.id == actor.fighterID }) {
                    actor.run(.moveBy(x: dx, y: dy, duration: 0.5), withKey: "escape")
                }
            }
            await pause(0.6)

        case .defeated(let id):
            await defeat([id])

        case .message:
            controller.apply(event)
            await pause(0.8)

        case .afflicted(let targetID, let effect, _):
            controller.apply(event)
            if let actor = actors[targetID] { SkillEffects.afflicted(actor, effect: effect, in: stage) }
            await pause(0.55)

        case .frozen(let targetID):
            controller.apply(event)
            if let actor = actors[targetID] { SkillEffects.frozenShiver(on: actor, in: stage) }
            await pause(0.6)
            refreshBars()

        case .ailmentDamage(let targetID, _, let amount):
            controller.apply(event)
            if let actor = actors[targetID] { poisonBite(on: actor, amount: amount) }
            await pause(0.55)

        case .statsChanged(let targetID, let changes, _):
            controller.apply(event)
            if let actor = actors[targetID] { SkillEffects.statChanges(changes, on: actor, in: stage) }
            await pause(0.75)

        case .wave(_, _, let arrivals):
            controller.apply(event)
            // The beaten wave has left the field; the next marches in to take its place.
            for foe in controller.enemies where foe.wave < controller.wave {
                actors.removeValue(forKey: foe.id)?.removeFromParent()
            }
            var arriving: [BattleActor] = []
            for fighter in arrivals {
                let actor = BattleActor(fighter: fighter, art: art)
                actors[fighter.id] = actor
                stage.addChild(actor)
                arriving.append(actor)
            }
            layout()
            march(arriving)
            await pause(0.9 + 0.08 * Double(arriving.count))
        }
    }

    /// A plain attack in the fighter's own style. Fighters close in with a double slash; mages stay
    /// back and loose a bolt of magic from their staff; beast tamers pounce with claw marks; novices
    /// and monsters dash in with a single slash. Elves dart in quicker and leave a green shimmer,
    /// dwarves hit hard enough to shake the ground.
    private func attack(by actorID: Int, hit: Hit, apply: @escaping () -> Void) async {
        let fighter = controller.combatants.first { $0.id == actorID }
        let target = actors[hit.target]
        let landed: () -> Void = {
            apply()
            if fighter?.raceID == "dwarf" {
                self.shake(strength: 4)
                SkillEffects.burst(at: target?.position ?? .zero, color: UIColor(red: 0.8, green: 0.6, blue: 0.35, alpha: 1), count: 8, speed: 45, in: self.stage)
            }
            if fighter?.raceID == "elf", let target {
                SkillEffects.burst(at: target.center, color: UIColor(red: 0.55, green: 0.95, blue: 0.45, alpha: 1), count: 8, speed: 55, in: self.stage)
            }
            self.impact(hit, heal: false)
        }
        switch fighter?.classID ?? "" {
        case "mage":
            let violet = UIColor(red: 0.75, green: 0.5, blue: 1, alpha: 1)
            if let caster = actors[actorID] {
                caster.sprite.flash(violet)
                SkillEffects.magicCircle(at: caster.position, color: violet, radius: 30, duration: 0.25, in: stage)
            }
            await pause(0.15)
            await SkillEffects.projectile(from: actors[actorID]?.center, to: target?.center, color: violet, level: 1, trail: true, in: stage)
            if let target { SkillEffects.explosion(on: target, color: violet, level: 1, in: stage) }
            landed()
        case "tamer":
            await lunge(actorID, toward: hit.target, speed: fighter?.raceID == "elf" ? 0.7 : 1) {
                if let target { SkillEffects.claws(on: target, level: 2, in: self.stage) }
                landed()
            }
        case "fighter":
            await lunge(actorID, toward: hit.target, speed: fighter?.raceID == "elf" ? 0.7 : 1) {
                SkillEffects.slash(on: target, level: 3, in: self.stage)
                landed()
            }
        default:
            await lunge(actorID, toward: hit.target, speed: fighter?.raceID == "elf" ? 0.7 : 1) {
                SkillEffects.slash(on: target, level: 1, in: self.stage)
                landed()
            }
        }
    }

    /// Picks the effect for a skill; bigger and flashier at higher skill levels, and a full show
    /// (dimmed field, magic circles, an elemental finale) once the skill is mastered.
    private func castSkill(_ skill: SkillDef, level: Int, from actorID: Int, hits: [Hit]) async {
        let targets = hits.compactMap { actors[$0.target] }
        let heal = skill.kind == .heal || skill.kind == .revive
        let blessBlue = UIColor(red: 0.6, green: 0.85, blue: 1, alpha: 1)
        // Every skill has a look of its own (`animation` in content/skills.json; the checker keeps
        // them apart), and its colour where it has one (frost's ice, a rage's red), else its element's.
        let style = skill.animation ?? (heal ? "heal" : skill.kind == .magic ? "fire" : "slash")
        let color = SkillEffects.styleColor(style) ?? skill.element?.color
            ?? (heal ? SkillEffects.healGreen : skill.kind == .buff ? blessBlue : .white)
        actors[actorID]?.sprite.flash(color)
        // People gather themselves in their own way (class and race).
        let fighter = controller.combatants.first { $0.id == actorID }
        if let caster = actors[actorID], fighter?.classID != nil || fighter?.raceID != nil {
            SkillEffects.flourish(on: caster, classID: fighter?.classID, raceID: fighter?.raceID, color: color, in: stage)
        }
        // A mastered skill gets the whole stage: its name in gold, the field dims, a magic circle
        // and a pillar of light at the caster; the finale plays after the skill lands.
        // Your hero's and bosses' only: monsters, companions and friends master their skills by
        // level 18, and a show on every one of their turns would drag every battle out.
        let isBoss = fighter?.speciesID.flatMap { Content.shared.monster($0)?.boss } == true
        let mastered = level >= GameSession.maxSkillLevel && (fighter?.isHero == true || isBoss)
        var dimmer: SKNode?
        if mastered {
            // A grand chord as its name goes up in gold.
            SoundEffects.shared.play(.ultimate)
            SkillEffects.masterBanner(skill.name, level: level, size: size, in: self)
            dimmer = SkillEffects.ultimateStart(caster: actors[actorID], color: color, size: size, in: stage)
            await pause(0.75)
        }
        defer {
            if let dimmer { SkillEffects.ultimateEnd(dimmer, color: color, size: size, in: stage) }
        }
        // The effects grow in five tiers: every two skill levels look a step grander.
        let level = (level + 1) / 2
        // From the third tier, your hero's and bosses' skills gather themselves with a swell of sound,
        // louder each tier (everyone else's would swell on every turn).
        if level >= 3, fighter?.isHero == true || isBoss {
            SoundEffects.shared.play(.surge, volume: 0.4 + 0.2 * Float(level - 2))
        }
        if let caster = actors[actorID] {
            let hold = SkillEffects.charge(on: caster, color: color, level: level, in: stage)
            if hold > 0 { await pause(hold) }
        }
        // Special attacks leave the caster's hands in a flare, and every blow they land flares too.
        if skill.kind.isAttack {
            if let caster = actors[actorID] { SkillEffects.castFlare(on: caster, color: color, level: level, in: stage) }
            flareLight = (color, level)
        }
        defer { flareLight = nil }
        if level >= 3 { SkillEffects.screenFlash(color: color, strength: 0.18 + 0.08 * CGFloat(level - 3), size: size, in: self) }
        // Revive: a pillar of light on the fallen ally, who rises back into view.
        if skill.kind == .revive {
            for target in targets {
                target.run(.group([.fadeIn(withDuration: 0.5), .move(to: target.home, duration: 0.5)]), withKey: "revive")
                SkillEffects.lightPillar(on: target, level: level, in: stage)
            }
            await pause(0.4)
            for hit in hits {
                guard let target = actors[hit.target] else { continue }
                SkillEffects.sparkles(on: target, color: SkillEffects.healGreen, level: 2, in: stage)
                Effects.damageBurst("+\(hit.amount)", style: .heal, at: target.top, in: stage)
            }
            for target in targets { SkillEffects.glory(on: target, color: color, level: level, in: stage) }
            if mastered {
                SkillEffects.ultimateFinale(on: targets, style: "holy", color: color, size: size, in: stage)
                await pause(0.7)
            }
            return
        }
        // Buffs, each in its own way (Bless's pillar, Protection's shield, Berserk's flames...);
        // what it raised, and by how much, shows in the events after this one.
        if skill.kind == .buff {
            await pause(SkillEffects.buff(style, on: targets, level: level, in: stage))
            for target in targets { SkillEffects.glory(on: target, color: color, level: level, in: stage) }
            if mastered {
                SkillEffects.ultimateFinale(on: targets, style: "holy", color: color, size: size, in: stage)
                await pause(0.7)
            }
            return
        }

        // Curses and poisons: a dark mote flies to the foe and sinks in (a mist spreads over all of
        // them at once). Each mark shows as it takes hold, in the events after this one.
        // Evil Eye glares from a great eye instead, and Poison Mist rolls in as a fog.
        if skill.kind == .curse {
            switch style {
            case "glare":
                for target in targets { SkillEffects.evilEye(on: target, in: stage) }
                await pause(0.55)
            case "mist":
                SkillEffects.poisonMist(on: targets, in: stage)
                await pause(0.6)
            default:
                let poison = skill.inflicts?.effect == .poison
                if skill.target != .allEnemies, let first = targets.first {
                    await SkillEffects.projectile(from: actors[actorID]?.center, to: first.center, color: color, level: level, trail: true, in: stage)
                }
                for target in targets {
                    if poison {
                        SkillEffects.poisonCloud(on: target, level: level, in: stage)
                    } else {
                        SkillEffects.curseSpell(on: target, level: level, in: stage)
                    }
                }
                await pause(0.35)
            }
            return
        }

        switch style {
        case "slash":
            await lunge(actorID, toward: hits.first?.target ?? actorID) {
                for target in targets { SkillEffects.slash(on: target, level: level, in: self.stage) }
                self.impactAll(hits, heal: false)
            }
        case "whirlwind":
            if let actor = actors[actorID] {
                // A pirouette: twice round on the spot, swelling a little as it spins.
                await actor.run(.group([actor.pirouette(turns: 2, duration: 0.5),
                                        .sequence([.scale(by: 1.15, duration: 0.2), .scale(by: 1 / 1.15, duration: 0.3)])]))
            }
            for target in targets { SkillEffects.whirl(on: target, level: level, in: stage) }
            impactAll(hits, heal: false)
        case "fire" where skill.element == .fire:
            await SkillEffects.fireball(from: actors[actorID]?.center, to: targets.first?.center, level: level, in: stage)
            for target in targets { SkillEffects.fireBlast(on: target, level: level, in: stage) }
            impactAll(hits, heal: false)
        case "fire":
            // Magic of another element in the fire style: a glowing bolt in its own colour.
            await SkillEffects.projectile(from: actors[actorID]?.center, to: targets.first?.center, color: color, level: level, trail: true, in: stage)
            for target in targets { SkillEffects.explosion(on: target, color: color, level: level, in: stage) }
            impactAll(hits, heal: false)
        case "stone":
            var erupts: TimeInterval = 0.25
            for target in targets { erupts = SkillEffects.stoneSpikes(under: target, level: level, in: stage) }
            await pause(erupts)
            shake(strength: 2 + CGFloat(level))
            impactAll(hits, heal: false)
        case "leaves":
            for target in targets { SkillEffects.leafCyclone(around: target, level: level, in: stage) }
            await pause(0.45)
            impactAll(hits, heal: false)
        case "water":
            await SkillEffects.waterOrb(from: actors[actorID]?.center, to: targets.first?.center, level: level, in: stage)
            for target in targets { SkillEffects.waterSplash(on: target, level: level, in: stage) }
            impactAll(hits, heal: false)
        case "holy":
            for target in targets { SkillEffects.lightPillar(on: target, level: level, in: stage) }
            await pause(0.35)
            impactAll(hits, heal: heal)
        case "wild":
            for target in targets { SkillEffects.claws(on: target, level: level, in: stage) }
            await pause(0.2)
            impactAll(hits, heal: false)
        case "needles":
            for target in targets { SkillEffects.needles(on: target, level: level, in: stage) }
            await pause(0.35)
            impactAll(hits, heal: false)
        case "bounce":
            await leap(actorID, onto: hits.first?.target ?? actorID) {
                for target in targets { SkillEffects.shockwave(under: target, level: level, in: self.stage) }
                self.impactAll(hits, heal: false)
            }
        case "bite":
            await lunge(actorID, toward: hits.first?.target ?? actorID) {
                for target in targets { SkillEffects.bite(on: target, in: self.stage) }
                self.impactAll(hits, heal: false)
            }
        case "shadow_bite":
            await lunge(actorID, toward: hits.first?.target ?? actorID) {
                for target in targets { SkillEffects.shadowBite(on: target, in: self.stage) }
                self.impactAll(hits, heal: false)
            }
        case "venom_bite":
            await lunge(actorID, toward: hits.first?.target ?? actorID) {
                for target in targets { SkillEffects.venomBite(on: target, in: self.stage) }
                self.impactAll(hits, heal: false)
            }
        case "smash":
            await lunge(actorID, toward: hits.first?.target ?? actorID) {
                for target in targets { SkillEffects.smash(on: target, level: level, in: self.stage) }
                self.shake(strength: 3 + CGFloat(level))
                self.impactAll(hits, heal: false)
            }
        case "frost":
            await pause(SkillEffects.frostBreath(from: actors[actorID]?.center, on: targets, level: level, in: stage))
            impactAll(hits, heal: false)
        case "bubbles":
            await pause(SkillEffects.bubbleStream(from: actors[actorID]?.center, to: targets, level: level, in: stage))
            impactAll(hits, heal: false)
        case "embers":
            await pause(SkillEffects.emberSpray(from: actors[actorID]?.center, to: targets, level: level, in: stage))
            impactAll(hits, heal: false)
        case "mud":
            await pause(SkillEffects.mudShot(from: actors[actorID]?.center, to: targets, level: level, in: stage))
            impactAll(hits, heal: false)
        case "boulder":
            await pause(SkillEffects.rockThrow(from: actors[actorID]?.center, to: targets, level: level, in: stage))
            shake(strength: 3 + CGFloat(level))
            impactAll(hits, heal: false)
        case "vine":
            await pause(SkillEffects.vineWhip(from: actors[actorID]?.center, to: targets, level: level, in: stage))
            impactAll(hits, heal: false)
        case "gold_spin":
            if let actor = actors[actorID] {
                await actor.run(.rotate(byAngle: .pi * 2, duration: 0.25))
                actor.zRotation = 0
            }
            await pause(SkillEffects.goldenSpin(from: actors[actorID]?.center, to: targets, level: level, in: stage))
            impactAll(hits, heal: false)
        case "gust":
            await pause(SkillEffects.gust(from: actors[actorID]?.center, on: targets, level: level, in: stage))
            impactAll(hits, heal: false)
        case "roar":
            await pause(SkillEffects.roar(from: actors[actorID], on: targets, level: level, in: stage))
            shake(strength: 3 + CGFloat(level))
            impactAll(hits, heal: false)
        case "web":
            await pause(SkillEffects.webShot(from: actors[actorID]?.center, on: targets, level: level, in: stage))
            impactAll(hits, heal: false)
        case "flash":
            for target in targets { SkillEffects.flashBurst(on: target, level: level, in: stage) }
            SkillEffects.screenFlash(color: .white, strength: 0.3, size: size, in: self)
            await pause(0.2)
            impactAll(hits, heal: false)
        case "first_aid":
            for target in targets { SkillEffects.firstAid(on: target, in: stage) }
            await pause(0.3)
            impactAll(hits, heal: true)
        case "heart":
            for target in targets { SkillEffects.healingHeart(on: target, in: stage) }
            await pause(0.4)
            impactAll(hits, heal: true)
        case "paw":
            for target in targets { SkillEffects.pawPrints(on: target, in: stage) }
            await pause(0.55)
            impactAll(hits, heal: true)
        case "rain":
            SkillEffects.lightRain(on: targets, level: level, in: stage)
            await pause(0.4)
            impactAll(hits, heal: true)
        default:
            for target in targets { SkillEffects.sparkles(on: target, color: color, level: level, in: stage) }
            await pause(0.3)
            impactAll(hits, heal: heal)
        }
        for target in targets { SkillEffects.glory(on: target, color: color, level: level, in: stage) }
        if level >= 4, !heal { shake(strength: CGFloat(level - 2) * 3) }
        if mastered {
            await pause(0.2)
            SkillEffects.ultimateFinale(on: targets, style: SkillEffects.finale(for: style), color: color, size: size, in: stage)
            await pause(0.35)
            SkillEffects.screenFlash(color: .white, strength: 0.55, size: size, in: self)
            if !heal { shake(strength: 14) }
            await pause(0.6)
        }
    }

    // MARK: - Moves

    /// Dash toward the target, run `atContact`, dash back.
    private func lunge(_ actorID: Int, toward targetID: Int, speed: Double = 1, atContact: () -> Void) async {
        guard let actor = actors[actorID], let target = actors[targetID], actorID != targetID else {
            atContact()
            return
        }
        let offset = target.home - actor.home
        let step = offset.normalized * min(offset.length * 0.6, 150)
        let out = SKAction.move(to: actor.home + step, duration: 0.16 * speed)
        out.timingMode = .easeIn
        await actor.run(out)
        atContact()
        let back = SKAction.move(to: actor.home, duration: 0.22 * speed)
        back.timingMode = .easeOut
        await actor.run(back)
    }

    /// Jump in an arc onto the target and slam down.
    private func leap(_ actorID: Int, onto targetID: Int, atContact: () -> Void) async {
        guard let actor = actors[actorID], let target = actors[targetID] else {
            atContact()
            return
        }
        let landing = target.home + (actor.home - target.home).normalized * 40
        let rise = SKAction.group([.move(to: CGPoint(x: (actor.home.x + landing.x) / 2, y: max(actor.home.y, landing.y) + 90), duration: 0.22)])
        rise.timingMode = .easeOut
        let fall = SKAction.move(to: landing, duration: 0.16)
        fall.timingMode = .easeIn
        await actor.run(.sequence([rise, fall]))
        atContact()
        shake(strength: 4)
        await actor.run(.move(to: actor.home, duration: 0.25))
    }

    /// The move's name over whoever made it, with the skill's icon tile in front when there is one,
    /// so every cast (yours, a companion's, a monster's) shows what it was.
    private func shout(_ text: String, over actorID: Int, color: UIColor?, skill: SkillDef? = nil) {
        guard let actor = actors[actorID] else { return }
        let label = SKLabelNode()
        label.attributedText = Nodes.outlined(text, size: 15, color: Nodes.gold)
        label.verticalAlignmentMode = .center
        let group = SKNode()
        group.position = actor.top + CGVector(dx: 0, dy: 36)
        group.zPosition = 22_000
        group.addChild(label)
        if let skill, let tile = Self.skillTile(skill, size: 24) {
            let gap: CGFloat = 4
            let total = tile.frame.width + gap + label.frame.width
            tile.position = CGPoint(x: -total / 2 + tile.frame.width / 2, y: 0)
            label.position.x = tile.position.x + tile.frame.width / 2 + gap + label.frame.width / 2
            group.addChild(tile)
        }
        group.setScale(0.4)
        stage.addChild(group)
        group.run(.sequence([
            .scale(to: 1.1, duration: 0.12), .scale(to: 1, duration: 0.08),
            .wait(forDuration: 0.7), .group([.fadeOut(withDuration: 0.3), .moveBy(x: 0, y: 12, duration: 0.3)]),
            .removeFromParent(),
        ]))
    }

    /// A skill's icon on its coloured tile, like `SkillIcon` in the menus.
    private static func skillTile(_ skill: SkillDef, size: CGFloat) -> SKNode? {
        guard let id = skill.art, let image = ArtLibrary.shared.artImage(id) else { return nil }
        let tile = SKShapeNode(rectOf: CGSize(width: size, height: size), cornerRadius: size * 0.26)
        tile.fillColor = skill.tileColor
        tile.strokeColor = UIColor(white: 1, alpha: 0.75)
        tile.lineWidth = 1.5
        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest
        let picture = SKSpriteNode(texture: texture, size: CGSize(width: size * 0.84, height: size * 0.84))
        tile.addChild(picture)
        return tile
    }

    private func impactAll(_ hits: [Hit], heal: Bool) {
        for hit in hits { impact(hit, heal: heal) }
    }

    private func impact(_ hit: Hit, heal: Bool) {
        guard let target = actors[hit.target] else { return }
        if heal {
            SkillEffects.sparkles(on: target, color: SkillEffects.healGreen, level: 2, in: stage)
            Effects.damageBurst("+\(hit.amount)", style: .heal, at: target.top, in: stage)
            return
        }
        if let flare = flareLight {
            SkillEffects.impactFlare(on: target, color: flare.color, level: flare.level, in: stage)
        }
        Effects.damageBurst("-\(hit.amount)", style: hit.critical ? .critical : hit.splash ? .splash : .normal, at: target.top, in: stage)
        if hit.effectiveness > 1 {
            Effects.floatingText(L("Weak spot!"), color: Nodes.gold, at: target.top + CGVector(dx: 0, dy: 22), in: stage, size: 12)
        } else if hit.effectiveness < 1 {
            Effects.floatingText(L("Resisted"), color: UIColor(white: 0.85, alpha: 1), at: target.top + CGVector(dx: 0, dy: 22), in: stage, size: 11)
        }
        target.sprite.flash(.red)
        target.run(.sequence([.moveBy(x: 6, y: 0, duration: 0.04), .moveBy(x: -12, y: 0, duration: 0.06), .moveBy(x: 6, y: 0, duration: 0.04)]))
    }

    private func shake(strength: CGFloat) {
        stage.removeAction(forKey: "shake")
        stage.position = .zero
        var moves: [SKAction] = []
        for index in 0..<6 {
            let amount = strength * CGFloat(6 - index) / 6
            moves.append(.moveTo(x: index % 2 == 0 ? amount : -amount, duration: 0.035))
        }
        moves.append(.moveTo(x: 0, duration: 0.03))
        stage.run(.sequence(moves), withKey: "shake")
    }

    /// Fairyland-style sealing, a charm rather than a thrown ball: the Seal Stone (the teal crystal
    /// from your bag) rises from the thrower's hand and glides over the monster, a seal of teal light
    /// opens on the ground under it, and the monster turns to light and spirals up into the crystal.
    /// The crystal then pulses `wobbles` times, each pulse lighting one mark round the seal, until
    /// it sets in gold, or the crystal cracks apart and the monster pours back out.
    /// `art`: the thrown stone's sprite (a plain Seal Stone's if nil).
    private func captureAnimation(from actorID: Int, to targetID: Int, success: Bool, wobbles: Int, art: String? = nil) async {
        guard let actor = actors[actorID], let target = actors[targetID] else { return }
        let light = SkillEffects.ElementLight.seal

        // Everything else dims so the moment is about the stone.
        let dim = SKSpriteNode(color: .black, size: CGSize(width: size.width * 3, height: size.height * 3))
        dim.position = CGPoint(x: size.width / 2, y: size.height / 2)
        dim.zPosition = 14_000
        dim.alpha = 0
        stage.addChild(dim)
        dim.run(.fadeAlpha(to: 0.35, duration: 0.4), withKey: "fade")

        // The crystal, in a soft halo of its own light.
        let stone = SKNode()
        stone.position = actor.center
        stone.zPosition = 15_000
        let halo = SkillEffects.lightBall(light, size: 70, tint: 0.35, core: false)
        halo.zPosition = -0.5
        halo.alpha = 0.7
        stone.addChild(halo)
        let crystal = SKSpriteNode(texture: art.map { ArtLibrary.shared.sprite($0).texture } ?? SkillEffects.sealStoneTexture,
                                   size: CGSize(width: 34, height: 34))
        stone.addChild(crystal)
        stage.addChild(stone)
        halo.run(.repeatForever(.sequence([.scale(to: 1.15, duration: 0.45), .scale(to: 0.9, duration: 0.45)])), withKey: "pulse")

        // It lifts off the thrower's hand and glides over, trailing motes (no spin: it floats).
        stone.alpha = 0
        stone.setScale(0.4)
        await stone.run(.group([.fadeIn(withDuration: 0.18), .scale(to: 1, duration: 0.25), .moveBy(x: 0, y: 22, duration: 0.25)]))
        let hover = target.center + CGVector(dx: 0, dy: target.height * 0.5 + 30)
        let path = CGMutablePath()
        path.move(to: stone.position)
        path.addQuadCurve(to: hover, control: CGPoint(x: (stone.position.x + hover.x) / 2, y: max(stone.position.y, hover.y) + 50))
        let glide = SKAction.follow(path, asOffset: false, orientToPath: false, duration: 0.6)
        glide.timingMode = .easeInEaseOut
        let trail = SKAction.repeat(.sequence([.run { [weak self, weak stone] in
            guard let self, let stone else { return }
            let mote = SkillEffects.glowSprite(light.bright, size: CGSize(width: 7, height: 7))
            mote.position = stone.position + CGVector(dx: .random(in: -6...6), dy: .random(in: -6...6))
            mote.zPosition = 14_900
            self.stage.addChild(mote)
            mote.run(.sequence([.group([.fadeOut(withDuration: 0.35), .moveBy(x: 0, y: -10, duration: 0.35), .scale(to: 0.3, duration: 0.35)]),
                                .removeFromParent()]))
        }, .wait(forDuration: 0.035)]), count: 17)
        await stone.run(.group([glide, trail]))
        crystal.run(.repeatForever(.sequence([.moveBy(x: 0, y: 3, duration: 0.4), .moveBy(x: 0, y: -3, duration: 0.4)])), withKey: "bob")

        // The seal opens under the monster and the crystal's light falls on it.
        let radius = max(40, target.height * 0.55)
        let seal = SkillEffects.SealCircle(radius: radius, marks: max(1, wobbles))
        seal.position = target.position
        stage.addChild(seal)
        seal.open()
        let beam = SkillEffects.streak(light, size: CGSize(width: 22, height: hover.y - target.position.y), tint: 0.25)
        beam.position = CGPoint(x: target.position.x, y: (hover.y + target.position.y) / 2)
        beam.zPosition = 14_500
        beam.alpha = 0
        stage.addChild(beam)
        beam.run(.fadeAlpha(to: 0.75, duration: 0.2), withKey: "fade")
        await pause(0.3)

        // The monster turns to light and spirals up into the crystal.
        SkillEffects.sealSpiral(from: target.position, to: hover, radius: radius, count: 30, in: stage)
        target.sprite.color = light.bright
        await target.run(.group([
            .customAction(withDuration: 0.2) { _, t in target.sprite.colorBlendFactor = t / 0.2 },
            .sequence([.wait(forDuration: 0.15), .group([
                .scaleX(to: 0.4 * target.fieldScale, duration: 0.45), .scaleY(to: 1.4 * target.fieldScale, duration: 0.45),
                .moveBy(x: 0, y: 24, duration: 0.45), .fadeOut(withDuration: 0.45),
            ])]),
        ]))
        await pause(0.3)
        beam.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]), withKey: "fade")
        SkillEffects.screenFlash(color: light.core, strength: 0.35, size: size, in: self)
        halo.run(.sequence([.scale(to: 1.8, duration: 0.1), .scale(to: 1, duration: 0.2)]), withKey: "flare")

        // The crystal pulses, a ring of light each time, and each pulse lights one of the seal's marks.
        for index in 0..<wobbles {
            await pause(0.32)
            SkillEffects.ring(at: stone.position, color: light.main, size: CGSize(width: 34, height: 34), grow: 2.6, in: stage)
            seal.light(mark: index)
            crystal.run(.sequence([
                .group([.scale(to: 1.18, duration: 0.08), .rotate(toAngle: 0.14, duration: 0.08)]),
                .rotate(toAngle: -0.14, duration: 0.12),
                .group([.scale(to: 1, duration: 0.1), .rotate(toAngle: 0, duration: 0.1)]),
            ]), withKey: "pulse")
            await pause(0.3)
        }
        await pause(0.35)

        if success {
            // Sealed: the seal closes in gold into the crystal, which shines and floats home.
            seal.close()
            SkillEffects.rays(at: stone.position, color: Nodes.gold, count: 10, length: 70, width: 6, z: 14_800, in: stage)
            SkillEffects.burst(at: stone.position, color: Nodes.gold, count: 24, speed: 100, in: stage)
            crystal.removeAction(forKey: "bob")
            crystal.color = Nodes.gold
            crystal.run(.sequence([.colorize(withColorBlendFactor: 0.6, duration: 0.1), .colorize(withColorBlendFactor: 0, duration: 0.4)]), withKey: "shine")
            Effects.floatingText(L("Sealed!"), color: Nodes.gold, at: stone.position + CGVector(dx: 0, dy: 36), in: stage, size: 24)
            await stone.run(.sequence([.scale(to: 1.45, duration: 0.12), .scale(to: 1.1, duration: 0.12)]))
            await pause(0.5)
            let home = SKAction.move(to: actor.center, duration: 0.45)
            home.timingMode = .easeInEaseOut
            await stone.run(.group([home, .scale(to: 0.4, duration: 0.45), .sequence([.wait(forDuration: 0.3), .fadeOut(withDuration: 0.15)])]))
        } else {
            // The crystal cracks apart, the seal flickers out and the monster pours back down.
            SkillEffects.screenFlash(color: .white, strength: 0.3, size: size, in: self)
            SkillEffects.crystalShards(at: stone.position, in: stage)
            seal.shatter()
            stone.run(.group([.scale(to: 1.4, duration: 0.12), .fadeOut(withDuration: 0.12)]), withKey: "burst")
            SkillEffects.sealSpiral(from: target.home, to: stone.position, radius: radius, count: 20, reverse: true, in: stage)
            await pause(0.45)
            target.position = target.home
            target.xScale = target.fieldScale
            target.yScale = 0.2 * target.fieldScale
            target.sprite.colorBlendFactor = 1
            await target.run(.group([.fadeIn(withDuration: 0.15), .scaleY(to: target.fieldScale, duration: 0.22)]))
            target.run(.customAction(withDuration: 0.3) { _, t in target.sprite.colorBlendFactor = 1 - t / 0.3 }, withKey: "unflash")
            Effects.floatingText(L("Broke free!"), color: .white, at: target.top, in: stage, size: 18)
        }
        stone.removeFromParent()
        await dim.run(.fadeOut(withDuration: 0.3))
        dim.removeFromParent()
    }

    /// The hero levelled up with the win: light pours down on them in a burst of gold, "LEVEL UP!"
    /// fills the field, and their bars fill up (a new level restores HP and MP, so a hero who
    /// fell gets back up for it).
    func celebrateLevelUp(to level: Int) {
        guard let id = controller.hero?.id, let hero = actors[id] else { return }
        let gold = Nodes.gold
        hero.run(.group([.fadeIn(withDuration: 0.4), .move(to: hero.home, duration: 0.4)]), withKey: "revive")
        hero.setHealth(1, mana: 1)
        SkillEffects.screenFlash(color: gold, strength: 0.3, size: size, in: self)
        SkillEffects.lightPillar(on: hero, level: 5, in: stage)
        SkillEffects.glory(on: hero, color: gold, level: 5, in: stage)
        SkillEffects.burst(at: hero.center, color: gold, count: 24, speed: 130, in: stage)
        hero.sprite.run(.sequence([.moveBy(x: 0, y: 18, duration: 0.16), .moveBy(x: 0, y: -18, duration: 0.2)]), withKey: "cheer")

        let banner = SKNode()
        banner.position = CGPoint(x: size.width / 2, y: size.height * 0.58)
        banner.zPosition = 31_000
        let title = NameTag(L("LEVEL UP!"), color: gold, size: 36, alignment: .center)
        let subtitle = NameTag(L("Level {level}", ["level": level]), color: .white, size: 18, alignment: .center)
        subtitle.position.y = -36
        banner.addChild(title)
        banner.addChild(subtitle)
        banner.setScale(0.3)
        banner.alpha = 0
        addChild(banner)
        SkillEffects.rays(at: banner.position, color: gold, count: 14, length: 150, width: 10, z: 30_900, in: self)
        banner.run(.sequence([
            .group([.fadeIn(withDuration: 0.12), .scale(to: 1.2, duration: 0.2)]),
            .scale(to: 1, duration: 0.12),
            .wait(forDuration: 1),
            .group([.fadeOut(withDuration: 0.3), .moveBy(x: 0, y: 24, duration: 0.3)]),
            .removeFromParent(),
        ]))
    }

    /// A friend or your companion went up a level with the win: light pours down on them in gold,
    /// they hop, and "LEVEL UP!" stands over their head with the new level (the hero's fills the
    /// field). A new level restores them, so their bars fill up.
    func celebrateLevelUp(of id: Int, to level: Int) {
        guard let actor = actors[id] else { return }
        let gold = Nodes.gold
        actor.setHealth(1, mana: 1)
        SkillEffects.lightPillar(on: actor, level: 3, in: stage)
        SkillEffects.glory(on: actor, color: gold, level: 4, in: stage)
        SkillEffects.burst(at: actor.center, color: gold, count: 14, speed: 90, in: stage)
        actor.sprite.run(.sequence([.moveBy(x: 0, y: 14, duration: 0.15), .moveBy(x: 0, y: -14, duration: 0.18)]), withKey: "cheer")

        let tag = SKNode()
        tag.position = actor.top + CGVector(dx: 0, dy: 16)
        tag.zPosition = 30_500
        let title = NameTag(L("LEVEL UP!"), color: gold, size: 15, alignment: .center)
        let subtitle = NameTag(L("Lv {level}", ["level": level]), color: .white, size: 12, alignment: .center)
        subtitle.position.y = -16
        tag.addChild(title)
        tag.addChild(subtitle)
        tag.setScale(0.4)
        tag.alpha = 0
        stage.addChild(tag)
        tag.run(.sequence([
            .group([.fadeIn(withDuration: 0.12), .scale(to: 1.15, duration: 0.18)]),
            .scale(to: 1, duration: 0.1),
            .wait(forDuration: 1.1),
            .group([.fadeOut(withDuration: 0.3), .moveBy(x: 0, y: 16, duration: 0.3)]),
            .removeFromParent(),
        ]))
    }

    /// Bars, and the marks of any poison, curse or blessing while it lasts.
    func refreshBars() {
        for fighter in controller.combatants {
            actors[fighter.id]?.setHealth(fighter.hpFraction, mana: fighter.mpFraction)
            // Raises and drops count the round they're in too; show the rounds still to come.
            actors[fighter.id]?.setMarks(poison: fighter.poisonRounds, lowered: max(0, fighter.loweredRounds - 1),
                                         raised: max(0, fighter.raisedRounds - 1))
            actors[fighter.id]?.setFrozen(fighter.frozenRounds > 0 && fighter.isAlive)
        }
    }

    private func pause(_ seconds: TimeInterval) async {
        await run(.wait(forDuration: seconds))
    }

    #if DEBUG
    /// Debug launches (`cast=`): the hero casts a skill at the monsters (all of them, or one: the
    /// `target`th on the field counting from 0, else the first) without playing a round. With
    /// `stopAt` the battle slows right down and freezes that many seconds into the cast, so a
    /// screenshot catches the effect mid-flight.
    func castForDebug(_ skillID: String, level: Int, target: Int? = nil, stopAt: TimeInterval?) {
        guard let skill = Content.shared.skill(skillID), let hero = controller.combatants.first(where: { $0.isHero }) else { return }
        for actor in actors.values {
            actor.removeAction(forKey: "enter")
            actor.position = actor.home
            actor.alpha = 1
        }
        let foes = controller.enemiesOnField.map(\.id)
        let one = foes.isEmpty ? [] : [foes[min(max(target ?? 0, 0), foes.count - 1)]]
        let targets = skill.target == .allEnemies ? foes : one
        let hits = controller.expectedHitsForDebug(skill, level: level, on: targets)
        if let stopAt {
            speed = 0.03
            run(.sequence([.wait(forDuration: stopAt), .run { [weak self] in self?.isPaused = true }]))
        }
        shout(skill.name + "!", over: hero.id, color: skill.element?.color, skill: skill)
        Task { await castSkill(skill, level: level, from: hero.id, hits: hits) }
    }

    /// Debug launches (`seal=ok|fail`): the hero seals the first monster, the animation only,
    /// frozen `stopAt` seconds into it (the battle runs at 20% speed till then; the whole seal
    /// takes about 5.5 s).
    /// `stone`: the kind thrown (an item id; a plain Seal Stone if nil).
    func sealForDebug(success: Bool, stopAt: TimeInterval?, stone: String? = nil) {
        guard let hero = controller.combatants.first(where: { $0.isHero }),
              let foe = controller.enemiesOnField.first else { return }
        // A real throw takes the target arrows away first (BattleController), so this one does too.
        showTargets([])
        for actor in actors.values {
            actor.removeAction(forKey: "enter")
            actor.position = actor.home
            actor.alpha = 1
        }
        if let stopAt {
            speed = 0.2
            run(.sequence([.wait(forDuration: stopAt), .run { [weak self] in self?.isPaused = true }]))
        }
        let art = stone.flatMap { controller.session.content.item($0)?.art }
        Task { await captureAnimation(from: hero.id, to: foe.id, success: success, wobbles: 3, art: art) }
    }
    #endif
}

/// One fighter on the battle stage, drawn at 2× on a Fairyland-style ground circle.
final class BattleActor: SKNode {
    let fighterID: Int
    let sprite: SKSpriteNode
    private(set) var home: CGPoint = .zero
    private let cycle: WalkCycle
    private let bar: HealthBar
    private let ring: SKShapeNode

    init(fighter: Combatant, art: ArtLibrary) {
        fighterID = fighter.id
        cycle = art.walkCycle(fighter.art)
        let size = cycle.size * 2
        sprite = SKSpriteNode(texture: cycle.frames(.down).first, size: size)
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.05)
        // Everyone with MP shows it in a blue bar under their HP.
        bar = HealthBar(width: 44, level: fighter.level, mana: fighter.stats.mp > 0)
        // Every ground circle is seen from the same angle: its height keeps to its width, so a
        // wide hero's circle isn't flatter than a monster's.
        let ringWidth = max(64, size.width * 0.85)
        ring = SKShapeNode(ellipseOf: CGSize(width: ringWidth, height: ringWidth * Self.ringAspect))
        super.init()
        ring.strokeColor = UIColor(white: 1, alpha: 0.55)
        ring.lineWidth = 2
        ring.fillColor = UIColor(white: 0, alpha: 0.18)
        ring.zPosition = -2
        addChild(ring)
        addChild(sprite)
        // Name, level and HP on one compact plate under the feet: the name in small letters
        // right on top of the bar, so nothing floats over the fighters' heads.
        bar.position = CGPoint(x: 0, y: -25)
        bar.fraction = CGFloat(fighter.hpFraction)
        bar.manaFraction = CGFloat(fighter.mpFraction)
        addChild(bar)
        // The same small gap over every head, wherever the art's top edge sits in its frame.
        nameHeight = size.height * (1 - sprite.anchorPoint.y - Self.emptyTop(of: sprite.texture)) + Self.nameGap
        let label = NameTag(fighter.name, size: 9)
        label.position = CGPoint(x: 0, y: bar.position.y + 2)
        addChild(label)
        sprite.run(IdleMotion.of(art: fighter.art).action(height: size.height, delay: .random(in: 0..<0.8)), withKey: "idle")
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// How big it stands on a crowded field (BattleScene's `fieldScale`), name plate and all.
    private(set) var fieldScale: CGFloat = 1
    /// How tall it stands on the field, shrunk with it.
    var height: CGFloat { sprite.size.height * fieldScale }
    var center: CGPoint { position + CGVector(dx: 0, dy: height * 0.45) }
    var top: CGPoint { position + CGVector(dx: 0, dy: height * 0.85) }
    /// Just over the head (the turn arrow points down at it).
    private(set) var nameHeight: CGFloat = 0
    private static let nameGap: CGFloat = 4
    /// A ground circle's height for its width (a monster's 68-wide circle stays 26 tall).
    private static let ringAspect: CGFloat = 26.0 / 68.0

    /// The share of `texture`'s height that's empty above the art.
    private static func emptyTop(of texture: SKTexture?) -> CGFloat {
        guard let image = texture?.cgImage(), image.width > 0, image.height > 0 else { return 0 }
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data
        else { return 0 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        // The bitmap's rows run top to bottom, like the image's.
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 8 {
                return CGFloat(y) / CGFloat(height)
            }
        }
        return 0
    }

    func place(at point: CGPoint, facing direction: Direction, scale: CGFloat = 1) {
        home = point
        fieldScale = scale
        setScale(scale)
        if !hasActions() { position = point }
        zPosition = -point.y
        sprite.texture = cycle.frames(direction).first
        facing = direction
        if let weapon = sprite.childNode(withName: "weapon") as? SKSpriteNode {
            GearArt.pose(weapon, facing: direction, height: sprite.size.height)
        }
    }

    private var facing: Direction = .down

    /// Whirlwind's pirouette: the fighter turns on the spot through each way its sheet faces (front,
    /// side, back, other side), `turns` times round, quickest halfway, and ends facing as it started.
    func pirouette(turns: Int, duration: TimeInterval) -> SKAction {
        let order: [Direction] = [.down, .left, .up, .right]
        let start = order.firstIndex(of: facing) ?? 0
        let quarters = CGFloat(turns * order.count)
        return .sequence([
            .customAction(withDuration: duration) { [weak self] _, elapsed in
                let t = min(1, elapsed / CGFloat(duration))
                let quarter = Int((t * t * (3 - 2 * t) * quarters).rounded())
                self?.show(facing: order[(start + quarter) % order.count])
            },
            .run { [weak self] in
                guard let self else { return }
                self.show(facing: self.facing)
            },
        ])
    }

    /// The fighter, and the weapon in hand, turned to `direction` for a moment (`facing` stays).
    private func show(facing direction: Direction) {
        let texture = cycle.frames(direction).first
        guard sprite.texture !== texture else { return }
        sprite.texture = texture
        if let weapon = sprite.childNode(withName: "weapon") as? SKSpriteNode {
            GearArt.pose(weapon, facing: direction, height: sprite.size.height)
        }
    }

    /// The hero's weapon in hand and accessory sparkle (drawn at the sprite's own scale).
    func setGear(weapon: ItemDef?, accessory: ItemDef?) {
        if let weapon, let node = GearArt.weapon(weapon, height: sprite.size.height) {
            sprite.addChild(node)
            GearArt.pose(node, facing: facing, height: sprite.size.height)
        }
        if let accessory, let aura = GearArt.aura(accessory, height: sprite.size.height) {
            addChild(aura)
        }
    }

    func setHealth(_ fraction: Double, mana: Double) {
        bar.fraction = CGFloat(fraction)
        bar.manaFraction = CGFloat(mana)
    }

    /// Beside the HP bar while they last: poison's purple drop, a crimson arrow down for lowered
    /// stats (a curse) and a blue arrow up for raised ones (Bless, Protection...).
    private let marks = SKNode()
    private var shownMarks = [0, 0, 0]

    /// Frozen solid: a pale ice-blue glow over the fighter until their lost turn has passed.
    func setFrozen(_ frozen: Bool) {
        let existing = childNode(withName: "ice")
        if frozen, existing == nil {
            let ice = SkillEffects.glowSprite(SkillEffects.iceBlue, size: CGSize(width: sprite.size.width * 1.1, height: sprite.size.height * 1.05))
            ice.name = "ice"
            ice.position = CGPoint(x: 0, y: sprite.size.height * 0.45)
            ice.zPosition = 5
            ice.alpha = 0
            addChild(ice)
            ice.run(.fadeAlpha(to: 0.55, duration: 0.2))
        } else if !frozen, let existing {
            existing.name = nil
            existing.run(.sequence([.fadeOut(withDuration: 0.25), .removeFromParent()]))
        }
    }

    func setMarks(poison: Int, lowered: Int, raised: Int) {
        guard [poison, lowered, raised] != shownMarks else { return }
        shownMarks = [poison, lowered, raised]
        if marks.parent == nil {
            // Just past the bar plate's right end (its real drawn edge, not its nominal width), and
            // drawn over the bar and name plates (zPosition 5 000).
            marks.position = CGPoint(x: bar.calculateAccumulatedFrame().maxX + 9, y: bar.position.y)
            marks.zPosition = 5_100
            addChild(marks)
        }
        marks.removeAllChildren()
        var x: CGFloat = 0
        let kinds: [(rounds: Int, art: String, tint: UIColor)] = [
            (poison, "status_poison", SkillEffects.color(of: .poison)),
            (lowered, "status_curse", SkillEffects.color(of: .curse)),
            (raised, "status_raise", SkillEffects.raiseBlue),
        ]
        for (rounds, art, tint) in kinds where rounds > 0 {
            let icon: SKNode
            if let texture = SkillEffects.fxTexture(art) {
                // Glossy marks drawn at 3x (tools/fx_art.py), shown 13 pt tall and smoothly scaled.
                texture.filteringMode = .linear
                icon = SKSpriteNode(texture: texture, size: texture.size() * (13 / max(1, texture.size().height)))
            } else {
                let dot = SKShapeNode(circleOfRadius: 5)
                dot.fillColor = tint
                dot.strokeColor = UIColor(white: 0, alpha: 0.7)
                icon = dot
            }
            icon.position = CGPoint(x: x, y: 0)
            marks.addChild(icon)
            // The marks speak for themselves: no count of rounds left beside them.
            x += 15
        }
    }

    /// A target you can pick: an orange ring.
    private var targeted = false
    /// Whose move you're choosing (your hero, then your companion): the white ring lit up, glowing
    /// and breathing gently.
    private var choosing = false

    func setHighlighted(_ highlighted: Bool) {
        guard highlighted != targeted else { return }
        targeted = highlighted
        styleRing()
    }

    func setChoosing(_ choosing: Bool) {
        guard choosing != self.choosing else { return }
        self.choosing = choosing
        styleRing()
    }

    private func styleRing() {
        ring.removeAction(forKey: "choosing")
        ring.alpha = 1
        if targeted {
            ring.strokeColor = UIColor(red: 1, green: 0.6, blue: 0.2, alpha: 0.95)
            ring.lineWidth = 3
            ring.glowWidth = 0
        } else if choosing {
            ring.strokeColor = .white
            ring.lineWidth = 3
            ring.glowWidth = 3
            ring.run(.repeatForever(.sequence([.fadeAlpha(to: 0.6, duration: 0.6), .fadeAlpha(to: 1, duration: 0.6)])),
                     withKey: "choosing")
        } else {
            ring.strokeColor = UIColor(white: 1, alpha: 0.55)
            ring.lineWidth = 2
            ring.glowWidth = 0
        }
    }
}

extension Element {
    var color: UIColor {
        switch self {
        case .fire: UIColor(red: 1, green: 0.5, blue: 0.2, alpha: 1)
        case .water: UIColor(red: 0.35, green: 0.65, blue: 1, alpha: 1)
        case .wood: UIColor(red: 0.45, green: 0.85, blue: 0.35, alpha: 1)
        case .earth: UIColor(red: 0.75, green: 0.55, blue: 0.3, alpha: 1)
        case .metal: UIColor(red: 0.85, green: 0.85, blue: 0.9, alpha: 1)
        case .light: UIColor(red: 1, green: 0.95, blue: 0.55, alpha: 1)
        case .dark: UIColor(red: 0.6, green: 0.4, blue: 0.85, alpha: 1)
        case .neutral: .white
        }
    }
}
