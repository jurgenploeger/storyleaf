import CoreGraphics

nonisolated enum Direction: String, CaseIterable {
    case down, left, right, up

    var isHorizontal: Bool { self == .left || self == .right }

    /// Unit vector pointing the way this direction faces.
    var vector: CGVector {
        switch self {
        case .down: CGVector(dx: 0, dy: -1)
        case .up: CGVector(dx: 0, dy: 1)
        case .left: CGVector(dx: -1, dy: 0)
        case .right: CGVector(dx: 1, dy: 0)
        }
    }

    /// The facing that best matches `vector`. Near 45° it sticks with `current`
    /// so sprites don't flicker between two directions.
    init(_ vector: CGVector, current: Direction? = nil) {
        let bias: CGFloat = current.map { $0.isHorizontal ? 0.8 : 1.25 } ?? 1
        if abs(vector.dx) > abs(vector.dy) * bias {
            self = vector.dx < 0 ? .left : .right
        } else {
            self = vector.dy < 0 ? .down : .up
        }
    }
}

nonisolated extension CGPoint {
    static func + (point: CGPoint, vector: CGVector) -> CGPoint {
        CGPoint(x: point.x + vector.dx, y: point.y + vector.dy)
    }

    static func - (lhs: CGPoint, rhs: CGPoint) -> CGVector {
        CGVector(dx: lhs.x - rhs.x, dy: lhs.y - rhs.y)
    }

    func distance(to other: CGPoint) -> CGFloat {
        (other - self).length
    }
}

nonisolated extension CGVector {
    var length: CGFloat { hypot(dx, dy) }

    var normalized: CGVector {
        let length = length
        return length > 0 ? CGVector(dx: dx / length, dy: dy / length) : .zero
    }

    static func * (vector: CGVector, scale: CGFloat) -> CGVector {
        CGVector(dx: vector.dx * scale, dy: vector.dy * scale)
    }
}

nonisolated extension CGSize {
    static func * (size: CGSize, scale: CGFloat) -> CGSize {
        CGSize(width: size.width * scale, height: size.height * scale)
    }
}

/// Deterministic RNG (SplitMix64) so the world and placeholder art are the same every launch.
nonisolated struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    /// Stable across launches (unlike `hashValue`), so maps look the same every visit.
    init(text: String) {
        state = text.unicodeScalars.reduce(UInt64(5381)) { $0 &* 33 &+ UInt64($1.value) }
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
