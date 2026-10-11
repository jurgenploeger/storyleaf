import SpriteKit

/// Anything that walks around a map: the hero, a companion, an NPC or a passer-by.
/// Walk sheets animate per direction; single-image sprites hop instead. Standing still,
/// everyone breathes gently so the world never looks frozen.
final class Walker: SKNode {
    let sprite: SKSpriteNode
    var walkSpeed: CGFloat = 88
    /// Waypoints still to walk, in world coordinates (tap-to-move).
    var path: [CGPoint] = []

    private(set) var facing: Direction = .down
    private(set) var isWalking = false
    private var cycle: WalkCycle
    private var tag: NameTag?
    private var titleTag: NameTag?
    private var shownTitle: String?
    /// When the name tag shows: the party's while standing still, everyone else's up close or when tapped.
    /// `whenClear`, your companion's: while still, unless it would print over the name of whoever it
    /// follows (`follow`), as it does right behind you when the two names are long.
    enum TagMode { case always, whenStill, whenClear, onDemand }
    var tagMode: TagMode = .always {
        didSet { refreshTag() }
    }
    /// The hero is close by; `.onDemand` tags show then.
    var isNear = false {
        didSet { if isNear != oldValue { refreshTag() } }
    }
    /// Its name would sit on its leader's where it stands; a `.whenClear` tag hides then.
    private var crowded = false {
        didSet { if crowded != oldValue { refreshTag() } }
    }
    /// How close the hero gets before someone's name shows.
    static let nameRange: CGFloat = 120
    private var revealed = false
    private var tagShown: Bool?
    private var bubble: SKNode?
    /// Breathing while standing still; off for things that shouldn't, like gift boxes.
    var idles = true {
        didSet { if idles != oldValue { animate() } }
    }
    /// Monsters squish, hop or sway instead of breathing.
    var motion: IdleMotion = .breathe {
        didSet { if motion != oldValue { animate() } }
    }
    /// The hero fidgets when left standing: glances around, stretches.
    var fidgets = false {
        didSet { if fidgets, !isWalking { startFidgeting() } }
    }
    /// So a crowd doesn't breathe in unison.
    private let breathOffset = TimeInterval.random(in: 0..<1.6)
    /// The current map's light, cast softly on everyone standing in it (`theme.palette.light`).
    static var light: (color: UIColor, strength: CGFloat)?

    /// Everything you see of it, raised with the ground it stands on (a hilltop, a terrace).
    /// Children added to the walker go in here.
    private let body = SKNode()
    /// How high the ground under it stands (`WorldScene.groundHeight(at:)`).
    private(set) var lift: CGFloat = 0

    override var position: CGPoint {
        didSet { settle() }
    }

    /// Up onto the ground under its spot: as it walks, and once it's on the map.
    func settle() {
        let height = (scene as? WorldScene)?.groundHeight(at: position) ?? 0
        guard height != lift else { return }
        lift = height
        body.position.y = height
    }

    override func addChild(_ node: SKNode) {
        if node === body { super.addChild(node) } else { body.addChild(node) }
    }

    /// `badge`: BOT after the name.
    init(cycle: WalkCycle, label: String?, labelColor: UIColor = .white, badge: PlayerBadge? = nil) {
        self.cycle = cycle
        sprite = SKSpriteNode(texture: cycle.frames(.down).first, size: cycle.size)
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.08)
        super.init()
        super.addChild(body)
        addChild(Nodes.shadow(width: cycle.size.width * 0.5))
        addChild(sprite)
        Self.lit(sprite)
        if let label {
            let tag = NameTag(label, color: labelColor, size: 11, badge: badge)
            tag.position = CGPoint(x: 0, y: cycle.size.height * 0.95)
            addChild(tag)
            self.tag = tag
        }
        animate()
    }

    /// Swaps the look (after customising the hero or recolouring a companion).
    func setCycle(_ cycle: WalkCycle) {
        self.cycle = cycle
        sprite.size = cycle.size
        animate()
    }

    /// Shows the weapon in hand and an accessory's sparkle.
    func setGear(weapon: ItemDef?, accessory: ItemDef?) {
        sprite.childNode(withName: "weapon")?.removeFromParent()
        body.childNode(withName: "aura")?.removeFromParent()
        if let weapon, let node = GearArt.weapon(weapon, height: cycle.size.height) {
            Self.lit(node)
            sprite.addChild(node)
        }
        if let accessory, let aura = GearArt.aura(accessory, height: cycle.size.height) {
            addChild(aura)
        }
        poseGear()
    }

    /// Tints a sprite with the map's light, so characters take on the colours around them.
    private static func lit(_ node: SKSpriteNode) {
        guard let light else { return }
        node.color = light.color
        node.colorBlendFactor = light.strength
    }

    private func poseGear() {
        if let weapon = sprite.childNode(withName: "weapon") as? SKSpriteNode {
            GearArt.pose(weapon, facing: facing, height: cycle.size.height)
        }
    }

    func setLabel(_ text: String) {
        tag?.setText(text)
    }

    func setBadge(_ badge: PlayerBadge?) {
        tag?.setBadge(badge)
    }

    func setLabelColor(_ color: UIColor) {
        tag?.setColor(color)
    }

    /// A title worn over the name (Character → Titles), in small gold letters; it shows and hides
    /// with the name.
    /// The title worn over the name, in its rank's colour (TitleBadge's, on the map).
    func setTitle(_ title: TitleDef?) {
        guard title?.name != shownTitle else { return }
        shownTitle = title?.name
        titleTag?.removeFromParent()
        titleTag = nil
        guard let title, let tag else { return }
        let node = NameTag(title.name, color: TitleBadge.mapColor(rank: title.tier), size: 9)
        node.position = CGPoint(x: 0, y: 15)
        tag.addChild(node)
        titleTag = node
    }

    /// Shows the name tag for a few seconds, whatever its mode (someone tapped them).
    func revealTag(for duration: TimeInterval = 4) {
        revealed = true
        refreshTag()
        run(.sequence([.wait(forDuration: duration), .run { [weak self] in
            self?.revealed = false
            self?.refreshTag()
        }]), withKey: "reveal")
    }

    private func refreshTag() {
        guard let tag else { return }
        let show = switch tagMode {
        case .always: true
        case .whenStill: !isWalking || revealed
        case .whenClear: (!isWalking && !crowded) || revealed
        case .onDemand: isNear || revealed
        }
        guard show != tagShown else { return }
        let first = tagShown == nil
        tagShown = show
        tag.removeAction(forKey: "fade")
        if first {
            tag.alpha = show ? 1 : 0
        } else if show {
            // A short pause first, so the party's names don't blink on every brief stop.
            let delay = (tagMode == .whenStill || tagMode == .whenClear) && !revealed ? 0.6 : 0
            tag.run(.sequence([.wait(forDuration: delay), .fadeIn(withDuration: 0.2)]), withKey: "fade")
        } else {
            tag.run(.fadeOut(withDuration: 0.2), withKey: "fade")
        }
    }

    /// A speech bubble above the name tag for a few seconds.
    func say(_ text: String, for duration: TimeInterval = 3.5) {
        bubble?.removeFromParent()
        let node = Nodes.speechBubble(text)
        node.position = CGPoint(x: 0, y: (tag?.position.y ?? sprite.size.height) + 20)
        node.zPosition = 6_000
        node.alpha = 0
        node.setScale(0.6)
        addChild(node)
        bubble = node
        let pop = SKAction.group([.fadeIn(withDuration: 0.15), .scale(to: 1, duration: 0.15)])
        node.run(.sequence([pop, .wait(forDuration: duration), .fadeOut(withDuration: 0.3), .removeFromParent()]))
    }

    /// Where this walker has just been, newest first, a step apart: ground it stood on, so a
    /// follower can always walk there.
    private var footsteps: [CGPoint] = []
    /// How much longer a follower keeps to its leader's footsteps after its usual place was blocked.
    private var trailing: TimeInterval = 0

    /// Notes where it stands now. Call it every frame on anyone who's followed (the hero, an
    /// adventurer with a pet).
    func markFootstep() {
        if let last = footsteps.first {
            let gap = last.distance(to: position)
            if gap < 6 { return }
            // A jump (a new map, a road bounced back from): the old trail leads nowhere now.
            if gap > 200 { footsteps = [] }
        }
        footsteps.insert(position, at: 0)
        // Enough for a full party in single file (about 400 px).
        if footsteps.count > 64 { footsteps.removeLast() }
    }

    /// The point `distance` back along its footsteps. Where they don't go back that far (it's only
    /// just arrived), the rest is straight back from the way it faces.
    func footstep(behind distance: CGFloat) -> CGPoint {
        var previous = position
        var left = distance
        for point in footsteps {
            let gap = previous.distance(to: point)
            if gap > 0, gap >= left { return previous + (point - previous) * (left / gap) }
            left -= gap
            previous = point
        }
        return previous + facing.vector * -left
    }

    /// Trails behind `leader` like a companion: close enough to feel together, never on top. It keeps
    /// to ground it can stand on: when its place beside the leader is in water or a wall, or one is in
    /// the way, it walks to `footstep` instead (its place in single file on the trail of whoever leads
    /// the line), and it slides along whatever's in its way like the hero does. `beside`: at the
    /// leader's side instead (a friend's companion, with the next friend walking behind them).
    func follow(_ leader: Walker, dt: TimeInterval, footstep: CGPoint, canStand: (CGPoint) -> Bool, beside: Bool = false) {
        let behind = leader.facing.vector * -1
        var goal: CGPoint
        if beside {
            let side = CGVector(dx: -behind.dy, dy: behind.dx)
            goal = leader.position + side * 26 + behind * 8
        } else if leader.facing.isHorizontal {
            goal = leader.position + behind * 34 + CGVector(dx: 0, dy: 6)
        } else {
            goal = leader.position + behind * 14 + CGVector(dx: -30, dy: 0)
        }
        // Once blocked, it keeps to the footsteps a moment, so it doesn't dither along a ragged shore.
        if !Self.isClear(from: position, to: goal, canStand) { trailing = 0.6 }
        if trailing > 0 {
            trailing -= dt
            goal = footstep
        }
        let offset = goal - position
        let distance = offset.length
        // While the leader walks it walks too, right up to its place. Followers are quicker than
        // you, so they caught up, stopped within a few points of their place and stepped on again:
        // every stop and start began the walk from its first frame, so they seemed to slide.
        if distance > 300 {
            position = goal
        } else if distance > 6 || (leader.isWalking && distance > 0.5) {
            let step = min(distance, max(walkSpeed, distance * 2) * CGFloat(dt))
            let move = offset * (step / distance)
            var next = position + move
            // Stuck in a wall already (just arrived)? Then walk straight out; otherwise don't walk in.
            if canStand(position), !canStand(next) {
                let alongX = CGPoint(x: position.x + move.dx, y: position.y)
                let alongY = CGPoint(x: position.x, y: position.y + move.dy)
                next = canStand(alongX) ? alongX : canStand(alongY) ? alongY : position
            }
            position = next
            face(Direction(offset, current: facing))
            setWalking(true)
        } else {
            setWalking(false)
            face(leader.facing)
        }
        if tagMode == .whenClear { crowded = tagCrowds(leader) }
    }

    /// Whether its name tag, where it stands now, would print over `other`'s.
    func tagCrowds(_ other: Walker) -> Bool {
        guard let tag, let theirs = other.tag else { return false }
        let mine = tag.calculateAccumulatedFrame().offsetBy(dx: position.x, dy: position.y)
        let them = theirs.calculateAccumulatedFrame().offsetBy(dx: other.position.x, dy: other.position.y)
        return mine.insetBy(dx: -4, dy: -2).intersects(them)
    }

    /// Whether the way from `start` to `end`, and `end` itself, is all ground to stand on.
    private static func isClear(from start: CGPoint, to end: CGPoint, _ canStand: (CGPoint) -> Bool) -> Bool {
        let offset = end - start
        let steps = max(1, Int(offset.length / 8))
        for index in 1...steps where !canStand(start + offset * (CGFloat(index) / CGFloat(steps))) {
            return false
        }
        return true
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    var headTop: CGPoint { CGPoint(x: position.x, y: position.y + sprite.size.height + 14) }

    /// Walks along `path`; returns true while there's still somewhere to go.
    @discardableResult
    func followPath(dt: TimeInterval) -> Bool {
        guard let next = path.first else { return false }
        let offset = next - position
        let distance = offset.length
        let step = walkSpeed * CGFloat(dt)
        if distance <= step {
            position = next
            path.removeFirst()
        } else {
            position = position + offset * (step / distance)
            face(Direction(offset, current: facing))
        }
        return !path.isEmpty
    }

    func face(_ direction: Direction) {
        guard direction != facing else { return }
        facing = direction
        animate()
    }

    func setWalking(_ walking: Bool) {
        guard walking != isWalking else { return }
        isWalking = walking
        animate()
        refreshTag()
        if walking {
            removeAction(forKey: "fidget")
            removeAction(forKey: "glance")
        } else if fidgets {
            startFidgeting()
        }
    }

    private func startFidgeting() {
        let fidget = SKAction.sequence([.wait(forDuration: 5, withRange: 4), .run { [weak self] in self?.fidget() }])
        run(.repeatForever(fidget), withKey: "fidget")
    }

    /// Look left and right, or have a little stretch.
    private func fidget() {
        guard !isWalking else { return }
        if Bool.random() {
            let original = facing
            let sides: [Direction] = original.isHorizontal ? [.down, original == .left ? .right : .left] : [.left, .right].shuffled()
            run(.sequence([
                .run { [weak self] in self?.face(sides[0]) }, .wait(forDuration: 0.7),
                .run { [weak self] in self?.face(sides[1]) }, .wait(forDuration: 0.7),
                .run { [weak self] in self?.face(original) },
            ]), withKey: "glance")
        } else {
            let stretch = SKAction.sequence([.scaleY(to: 1.12, duration: 0.18), .scaleY(to: 0.94, duration: 0.12), .scaleY(to: 1, duration: 0.14)])
            stretch.timingMode = .easeInEaseOut
            sprite.run(stretch, withKey: "stretch")
        }
    }

    private func animate() {
        sprite.removeAction(forKey: "walk")
        sprite.removeAction(forKey: "idle")
        sprite.position = .zero
        sprite.xScale = 1
        sprite.yScale = 1
        sprite.zRotation = 0
        let frames = cycle.frames(facing)
        sprite.texture = frames.first
        poseGear()
        guard isWalking else {
            breathe()
            return
        }
        if frames.count > 1 {
            sprite.run(.repeatForever(.animate(with: frames, timePerFrame: 0.16)), withKey: "walk")
        } else {
            let up = SKAction.moveBy(x: 0, y: 5, duration: 0.13)
            up.timingMode = .easeOut
            let down = SKAction.moveBy(x: 0, y: -5, duration: 0.13)
            down.timingMode = .easeIn
            sprite.run(.repeatForever(.sequence([up, down])), withKey: "walk")
        }
    }

    /// Standing still: breathing for people, a squish, hop or sway for monsters.
    private func breathe() {
        guard idles else { return }
        sprite.run(motion.action(height: sprite.size.height, delay: breathOffset), withKey: "idle")
    }
}
