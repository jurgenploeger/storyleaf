import SpriteKit

/// Nobody on screen is ever hidden behind the scenery (playtesting 2026-10-31): the scenery tall
/// enough to hide someone (houses, trees, big rocks, a city's walls), noted as it's set down, and
/// faded while anyone stands behind it; and a spot nothing hides for those who stand still
/// (`clearSpot`). Kept by each land on the continent (`LandStage`) and by a cave or a land's own
/// scene (`WorldScene`), in their own points. A cave's rock (`CaveWalls`) isn't noted: it stays solid.
final class SeeThrough {
    /// The tall scenery, in every piece of the screen its picture reaches into.
    private var talls: [GridPoint: [SKSpriteNode]] = [:]
    /// What's faded now (`fade`).
    private var faded: Set<SKSpriteNode> = []
    /// How big a piece of the screen `talls` is kept in.
    private static let piece: CGFloat = 400
    /// How tall a picture has to be to hide anyone: about a walker's height.
    private static let tallEnough: CGFloat = 40
    /// How faded scenery stands while someone's behind it.
    private static let fadedAlpha: CGFloat = 0.45

    /// Notes a piece of scenery (its frame in the same points as whoever walks by it), if it's tall
    /// enough to hide someone.
    func note(_ node: SKSpriteNode) {
        let frame = node.frame
        guard frame.height >= Self.tallEnough, Self.isSane(frame) else { return }
        let low = Self.key(frame.minX, frame.minY), high = Self.key(frame.maxX, frame.maxY)
        for col in low.col...high.col {
            for row in low.row...high.row { talls[GridPoint(col: col, row: row), default: []].append(node) }
        }
    }

    /// Where someone standing at `feet` shows: the middle of their frame, where the figure is,
    /// raised `lift` with the ground under them.
    static func body(at feet: CGPoint, size: CGSize, lift: CGFloat) -> CGRect {
        CGRect(x: feet.x - size.width * 0.22, y: feet.y + lift + size.height * 0.04,
               width: size.width * 0.44, height: size.height * 0.78)
    }

    /// The tall scenery in front of someone standing at `feet` (nearer the bottom of the screen,
    /// which sorts in front) and over a good part of them: a quarter of the figure, past its
    /// picture's empty sides.
    func covering(feet: CGPoint, size: CGSize, lift: CGFloat) -> Set<SKSpriteNode> {
        let body = Self.body(at: feet, size: size, lift: lift)
        var found = Set<SKSpriteNode>()
        guard Self.isSane(body) else { return found }
        let low = Self.key(body.minX, body.minY), high = Self.key(body.maxX, body.maxY)
        for col in low.col...high.col {
            for row in low.row...high.row {
                for node in talls[GridPoint(col: col, row: row)] ?? [] where node.zPosition > -feet.y && !node.isHidden {
                    let frame = node.frame.insetBy(dx: node.frame.width * 0.12, dy: 0)
                    let overlap = frame.intersection(body)
                    if !overlap.isNull, overlap.width * overlap.height > body.width * body.height * 0.25 { found.insert(node) }
                }
            }
        }
        return found
    }

    /// Fades what stands in front of each walker on screen (`visible`), and brings back what no
    /// one's behind any more. Each group's `offset` brings its walkers' positions into these points.
    func fade(over groups: [(walkers: [Walker], offset: CGVector)], visible: CGRect) {
        var now = Set<SKSpriteNode>()
        for group in groups {
            for walker in group.walkers where !walker.isHidden && walker.parent != nil {
                let feet = CGPoint(x: walker.position.x + group.offset.dx, y: walker.position.y + group.offset.dy)
                guard Self.body(at: feet, size: walker.sprite.size, lift: walker.lift).intersects(visible) else { continue }
                now.formUnion(covering(feet: feet, size: walker.sprite.size, lift: walker.lift))
            }
        }
        for node in now.subtracting(faded) {
            node.run(.fadeAlpha(to: Self.fadedAlpha, duration: 0.2), withKey: "seeThrough")
        }
        for node in faded.subtracting(now) {
            node.run(.fadeAlpha(to: 1, duration: 0.3), withKey: "seeThrough")
        }
        faded = now
    }

    /// The nearest cell to `home`, within four, where someone `size` big stands with nothing in
    /// front of them: on `map`'s own walkable ground and not `taken`. Nil if `home` is clear, or
    /// nothing near is.
    func clearSpot(near home: CGPoint, size: CGSize, map: WorldMap, taken: Set<GridPoint>) -> GridPoint? {
        func hidden(_ point: CGPoint) -> Bool {
            !covering(feet: point, size: size, lift: map.height(at: point)).isEmpty
        }
        guard hidden(home) else { return nil }
        let start = map.cell(at: home)
        for radius in 1...4 {
            var ring: [GridPoint] = []
            for dc in -radius...radius {
                for dr in -radius...radius where max(abs(dc), abs(dr)) == radius {
                    ring.append(GridPoint(col: start.col + dc, row: start.row + dr))
                }
            }
            // The nearest on the screen first.
            let middle = map.center(of: start)
            ring.sort { map.center(of: $0).distance(to: middle) < map.center(of: $1).distance(to: middle) }
            if let spot = ring.first(where: { map.owns($0) && map.isWalkable($0) && !taken.contains($0) && !hidden(map.center(of: $0)) }) {
                return spot
            }
        }
        return nil
    }

    /// The piece of the screen a point is in. A point that isn't a number (or is past any the world
    /// has) goes in a piece far off rather than stopping the game: `Int` traps on those.
    /// A rectangle with real numbers, a few screens across at most: anything else is a walker or a
    /// sprite somewhere it shouldn't be, and looking it up would walk a million pieces.
    private static func isSane(_ rect: CGRect) -> Bool {
        !rect.isNull && rect.minX.isFinite && rect.minY.isFinite && rect.width.isFinite && rect.height.isFinite
            && rect.width < piece * 8 && rect.height < piece * 8
    }

    private static func key(_ x: CGFloat, _ y: CGFloat) -> GridPoint {
        func index(_ value: CGFloat) -> Int {
            let piece = (value / Self.piece).rounded(.down)
            return piece.isFinite ? Int(max(-1_000_000, min(1_000_000, piece))) : 1_000_000
        }
        return GridPoint(col: index(x), row: index(y))
    }
}
