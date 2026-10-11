import CoreGraphics
import Foundation

extension WorldMap {
    /// A hill out in the fields (`theme.hills`): smooth ground rising from its foot to a rounded top
    /// `peak` points up, a few ellipses melted together. Its sides are too steep to walk but for its
    /// trail, which zig-zags up the side that faces you (switchbacks) and onto the top.
    /// Points here are in cells (grid space divided by `WorldMap.tileSize`).
    nonisolated struct Hill {
        /// One of the ellipses it's made of: its middle, and its reach along and across (turned by
        /// `angle`), in cells.
        nonisolated struct Lobe {
            var x, y, along, across, angle: Double
        }
        let lobes: [Lobe]
        /// Gentle waves along its outline (frequency and phase across and up), so no two are alike.
        let ripples: [(fx: Double, px: Double, fy: Double, py: Double)]
        /// How high its top stands, in points.
        let peak: CGFloat
        /// How far in from its foot its top begins, in cells: never so close that its far side would
        /// lean back out of sight, which keeps the ground under every spot on screen one place.
        let band: Double
        /// Its trail's middle, from the ground at its foot to its top.
        var trail: [CGPoint] = []
        /// The cells it rises over.
        var cells: Set<GridPoint> = []
        /// Its height sampled `samples` times a cell from `origin` over `size` cells, for walkers
        /// (`height(atCells:_:)`) and for drawing it.
        var origin = GridPoint(col: 0, row: 0)
        var size = (columns: 0, rows: 0)
        var heights: [Float] = []
        static let samples = 4
        /// How steep a hill's sides get halfway up, at most, in points a cell. The view looks down at
        /// 30°, so ground facing away from you would drop out of sight past about 22 points a cell
        /// (going diagonally); this leaves room for the ripples and where its ellipses meet.
        static let steepest: Double = 15

        /// How far inside it a point is: about the cells in from its foot, below 0 outside it.
        func field(_ x: Double, _ y: Double) -> Double {
            var value = -Double.infinity
            for lobe in lobes {
                let dx = x - lobe.x, dy = y - lobe.y
                let u = dx * cos(lobe.angle) + dy * sin(lobe.angle)
                let v = -dx * sin(lobe.angle) + dy * cos(lobe.angle)
                let reach = ((u / lobe.along) * (u / lobe.along) + (v / lobe.across) * (v / lobe.across)).squareRoot()
                let inside = (1 - reach) * min(lobe.along, lobe.across)
                value = value == -.infinity ? inside : Self.smoothMax(value, inside, 1.2)
            }
            var ripple = 0.0
            for wave in ripples { ripple += sin(x * wave.fx + wave.px) * sin(y * wave.fy + wave.py) }
            return value + ripple * 0.12
        }

        /// How far up it a point is: 0 at its foot (and outside it), 1 where its top begins.
        func rise(_ x: Double, _ y: Double) -> Double {
            min(1, max(0, field(x, y) / band))
        }

        /// Its height at a point, worked out exactly: gentle at the foot, steepest halfway up and
        /// rounding off onto the top (smoothstep).
        func shape(_ x: Double, _ y: Double) -> CGFloat {
            let s = rise(x, y)
            return peak * CGFloat(s * s * (3 - 2 * s))
        }

        /// Straight up its slope from a point (unit length), and how fast `field` grows that way.
        func uphill(_ x: Double, _ y: Double) -> (x: Double, y: Double, growth: Double) {
            let e = 1e-3
            let gx = (field(x + e, y) - field(x - e, y)) / (2 * e)
            let gy = (field(x, y + e) - field(x, y - e)) / (2 * e)
            let length = max(1e-9, (gx * gx + gy * gy).squareRoot())
            return (gx / length, gy / length, length)
        }

        /// Its height at a point, from the samples (what walkers stand on and what's drawn).
        func height(atCells x: Double, _ y: Double) -> CGFloat {
            let width = size.columns * Self.samples + 1, depth = size.rows * Self.samples + 1
            let fx = (x - Double(origin.col)) * Double(Self.samples), fy = (y - Double(origin.row)) * Double(Self.samples)
            guard fx >= 0, fy >= 0, fx < Double(width - 1), fy < Double(depth - 1) else { return 0 }
            let i = Int(fx), j = Int(fy)
            let tx = Float(fx - Double(i)), ty = Float(fy - Double(j))
            let a = heights[j * width + i], b = heights[j * width + i + 1]
            let c = heights[(j + 1) * width + i], d = heights[(j + 1) * width + i + 1]
            let bottom = a + (b - a) * tx, top = c + (d - c) * tx
            return CGFloat(bottom + (top - bottom) * ty)
        }

        /// A smooth maximum: like `max`, but rounding off where `a` and `b` are within `k`.
        static func smoothMax(_ a: Double, _ b: Double, _ k: Double) -> Double {
            let h = max(k - abs(a - b), 0) / k
            return max(a, b) + h * h * k / 4
        }

        /// A trail up the side facing you: from the ground at the foot, `legs` legs back and forth
        /// across it, each a little further up (an even share of the way to the top) and turning about
        /// 45° either side of straight in front of the top, then up onto the top. Nil if it doesn't
        /// get there.
        func traceTrail(startingLeft: Bool) -> [CGPoint]? {
            let cx = lobes[0].x, cy = lobes[0].y
            // Straight in front: toward the bottom of the screen (225° in grid space).
            let front = 1.25 * Double.pi, spread = Double.pi / 4
            func turned(_ x: Double, _ y: Double) -> Double {
                var angle = atan2(y - cy, x - cx) - front
                while angle > .pi { angle -= 2 * .pi }
                while angle < -.pi { angle += 2 * .pi }
                return angle
            }
            var way: Double = startingLeft ? 1 : -1
            // The foot, where the first leg starts.
            let start = front - spread * way
            var reach = 0.0
            while field(cx + reach * cos(start), cy + reach * sin(start)) > 0.02, reach < 40 { reach += 0.05 }
            var x = cx + reach * cos(start), y = cy + reach * sin(start)
            // A short way in from the ground, straight up the slope.
            let up = uphill(x, y)
            var points = stride(from: 5, through: 1, by: -1).map { CGPoint(x: x - up.x * 0.12 * Double($0), y: y - up.y * 0.12 * Double($0)) }
            points.append(CGPoint(x: x, y: y))
            let step = 0.15
            let legs = band >= 5.1 ? 3 : 2
            for leg in 0..<legs {
                let from = rise(x, y), to = Double(leg + 1) / Double(legs)
                let first = turned(x, y), last = spread * way
                let span = max(abs(last - first), 0.01)
                for _ in 0..<400 {
                    let n = uphill(x, y)
                    // Across the slope, the way this leg goes round.
                    var tx = n.y, ty = -n.x
                    if ((x - cx) * ty - (y - cy) * tx) * way < 0 { tx = -tx; ty = -ty }
                    let progress = min(1, abs(turned(x + step * tx, y + step * ty) - first) / span)
                    let want = from + (to - from) * progress
                    let gain = n.growth / band * step
                    let climb = min(1, max(0, (want - rise(x, y)) / max(gain, 1e-9)))
                    let across = (1 - climb * climb).squareRoot()
                    x += step * (across * tx + climb * n.x)
                    y += step * (across * ty + climb * n.y)
                    points.append(CGPoint(x: x, y: y))
                    if leg == legs - 1, rise(x, y) >= 0.999 { break }
                    if (turned(x, y) - last) * way >= 0 { break }
                }
                way = -way
            }
            // On up onto the top, and a little way across it.
            var onTop = 0
            for _ in 0..<200 where onTop < 4 {
                if rise(x, y) >= 0.999 { onTop += 1 }
                let n = uphill(x, y)
                x += step * n.x
                y += step * n.y
                points.append(CGPoint(x: x, y: y))
            }
            guard rise(x, y) >= 0.999 else { return nil }
            // Every other point is plenty for a smooth line.
            return stride(from: 0, to: points.count - 1, by: 2).map { points[$0] } + [points[points.count - 1]]
        }

        /// How far a point is from the trail's middle, in cells.
        func distanceToTrail(_ x: Double, _ y: Double) -> Double {
            var best = Double.infinity
            for (a, b) in zip(trail, trail.dropFirst()) {
                let ax = Double(a.x), ay = Double(a.y)
                let vx = Double(b.x) - ax, vy = Double(b.y) - ay
                let length = vx * vx + vy * vy
                let t: Double = length > 0 ? min(1, max(0, ((x - ax) * vx + (y - ay) * vy) / length)) : 0
                let dx = x - (ax + t * vx), dy = y - (ay + t * vy)
                best = min(best, (dx * dx + dy * dy).squareRoot())
            }
            return best
        }
    }
}
