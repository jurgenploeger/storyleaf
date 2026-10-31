import SpriteKit

/// Nobody is set down behind the scenery (playtesting 2026-10-31): the scenery tall enough to hide
/// someone (houses, trees, big rocks, a city's walls), noted as it's set down, so the people who stand
/// about get a spot nothing hides (`clearSpot`) and passers-by stroll to such spots (`hides`, `Crowd`).
/// Nothing fades: the user, after it did, "The buildings/scenery shouldn't fade out when something is
/// behind it, I just meant that any characters in the game shouldn't be hidden by it, so their
/// placement should be different". You can still walk behind a house yourself. Kept by each land on the
/// continent (`LandStage`) and by a cave or a land's own scene (`WorldScene`), in their own points. A
/// cave's rock (`CaveWalls`) isn't noted.
final class SeeThrough {
    /// The tall scenery, in every piece of the screen its picture reaches into.
    private var talls: [GridPoint: [SKSpriteNode]] = [:]
    /// How big a piece of the screen `talls` is kept in.
    private static let piece: CGFloat = 400
    /// How tall a picture has to be to hide anyone: about a walker's height.
    private static let tallEnough: CGFloat = 40
    /// A walker's frame (48 points a side), for a spot someone will stand on.
    private static let walker = CGSize(width: 48, height: 48)

    /// Notes a piece of scenery (its frame in the same points as whoever walks by it), if it's tall
    /// enough to hide someone.
    func note(_ node: SKSpriteNode) {
        let frame = node.frame
        guard frame.height >= Self.tallEnough else { return }
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

    /// Whether someone standing on `cell` of `map` would be hidden by something in front of them.
    func hides(_ cell: GridPoint, on map: WorldMap) -> Bool {
        let feet = map.center(of: cell)
        return !covering(feet: feet, size: Self.walker, lift: map.height(at: feet)).isEmpty
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

    private static func key(_ x: CGFloat, _ y: CGFloat) -> GridPoint {
        GridPoint(col: Int((x / piece).rounded(.down)), row: Int((y / piece).rounded(.down)))
    }
}
