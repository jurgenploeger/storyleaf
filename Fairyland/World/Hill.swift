import CoreGraphics
import Foundation

extension WorldMap {
    /// Raised ground out in the fields (`theme.hills`): a range of summits melted into one another,
    /// each rising smoothly from its foot to a rounded top of its own height, so a long ridge of hills
    /// or a mountain among its foothills. Its sides are too steep to walk but for its trails, which
    /// zig-zag up the sides that face you (switchbacks) and onto the tops.
    /// Points here are in cells (grid space divided by `WorldMap.tileSize`).
    nonisolated struct Hill {
        /// One of its summits: an ellipse (its middle, and its reach along and across, turned by
        /// `angle`, in cells) rising to a top `peak` points up.
        nonisolated struct Lobe {
            var x, y: Double
            let along, across, angle, peak: Double
            /// How far in from its foot its top begins, in cells: never so close that its far side
            /// would lean back out of sight, which keeps the ground under every spot on screen one place.
            let band: Double
            private let cosine, sine: Double

            init(x: Double, y: Double, along: Double, across: Double, angle: Double, peak: Double) {
                self.x = x
                self.y = y
                self.along = along
                self.across = across
                self.angle = angle
                self.peak = peak
                band = max(3, 1.5 * peak / Hill.steepest)
                cosine = cos(angle)
                sine = sin(angle)
            }

            /// How far inside its ellipse a point is: about the cells in from its edge, below 0 outside.
            func depth(_ x: Double, _ y: Double) -> Double {
                let dx = x - self.x, dy = y - self.y
                let u = (dx * cosine + dy * sine) / along
                let v = (dy * cosine - dx * sine) / across
                return (1 - (u * u + v * v).squareRoot()) * min(along, across)
            }
        }
        /// A trail up one of its summits (`lobe`): its middle, from its foot to the top.
        nonisolated struct Trail {
            let lobe: Int
            let points: [CGPoint]
        }
        let lobes: [Lobe]
        /// Gentle waves along its outline (frequency and phase across and up), so no two are alike.
        let ripples: [(fx: Double, px: Double, fy: Double, py: Double)]
        /// How high its highest top stands, in points.
        let peak: CGFloat
        /// Its trails: the first from the ground in front, the others to tops it doesn't reach.
        var trails: [Trail] = []
        /// The cells it rises over.
        var cells: Set<GridPoint> = []
        /// Its height sampled `samples` times a cell from `origin` over `size` cells, for walkers
        /// (`height(atCells:_:)`) and for drawing it.
        var origin = GridPoint(col: 0, row: 0)
        var size = (columns: 0, rows: 0)
        var heights: [Float] = []
        static let samples = 4
        /// How steep a summit's sides get halfway up, at most, in points a cell. The view looks down
        /// at 30°, so ground facing away from you would drop out of sight past about 22 points a cell
        /// (going diagonally); this leaves room for the ripples and where summits meet.
        static let steepest: Double = 13

        init(lobes: [Lobe], ripples: [(fx: Double, px: Double, fy: Double, py: Double)]) {
            self.lobes = lobes
            self.ripples = ripples
            peak = CGFloat(lobes.map(\.peak).max() ?? 0)
        }

        func ripple(_ x: Double, _ y: Double) -> Double {
            var ripple = 0.0
            for wave in ripples { ripple += sin(x * wave.fx + wave.px) * sin(y * wave.fy + wave.py) }
            return ripple * 0.12
        }

        /// How far inside it a point is: about the cells in from its foot, below 0 outside it.
        func field(_ x: Double, _ y: Double) -> Double {
            var deepest = -Double.infinity
            for lobe in lobes { deepest = max(deepest, lobe.depth(x, y)) }
            return deepest + ripple(x, y)
        }

        /// How far up summit `index` a point is: 0 at its foot (and outside it), 1 where its top begins.
        func rise(of index: Int, _ x: Double, _ y: Double) -> Double {
            min(1, max(0, (lobes[index].depth(x, y) + ripple(x, y)) / lobes[index].band))
        }

        /// How far up it a point is, on whichever summit it's highest up.
        func rise(_ x: Double, _ y: Double) -> Double {
            let wave = ripple(x, y)
            var highest = 0.0
            for lobe in lobes { highest = max(highest, min(1, (lobe.depth(x, y) + wave) / lobe.band)) }
            return highest
        }

        /// Its height at a point, worked out exactly: each summit gentle at its foot, steepest halfway
        /// up and rounding off onto its top (smoothstep), and the summits blended (the fourth root of
        /// their heights' fourth powers): as high as the highest, a little fuller where two meet, and
        /// flat ground where none rise.
        func shape(_ x: Double, _ y: Double) -> CGFloat {
            let wave = ripple(x, y)
            var total = 0.0
            for lobe in lobes {
                let s = min(1, max(0, (lobe.depth(x, y) + wave) / lobe.band))
                let height = lobe.peak * s * s * (3 - 2 * s)
                total += height * height * height * height
            }
            return CGFloat(total.squareRoot().squareRoot())
        }

        /// Straight up summit `index`'s slope from a point (unit length), and how fast its depth
        /// grows that way.
        func uphill(of index: Int, _ x: Double, _ y: Double) -> (x: Double, y: Double, growth: Double) {
            let e = 1e-3
            func depth(_ x: Double, _ y: Double) -> Double { lobes[index].depth(x, y) + ripple(x, y) }
            let gx = (depth(x + e, y) - depth(x - e, y)) / (2 * e)
            let gy = (depth(x, y + e) - depth(x, y - e)) / (2 * e)
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

        /// A trail up summit `index` on the side facing `front` (an angle in grid space; toward the
        /// bottom of the screen is 225°): from its foot, legs back and forth across that side, each a
        /// little further up (an even share of the way to the top) and turning about 45° either side of
        /// `front`, then up onto the top. Nil if it doesn't get there.
        func traceTrail(on index: Int, front: Double, startingLeft: Bool) -> [CGPoint]? {
            let lobe = lobes[index]
            let cx = lobe.x, cy = lobe.y
            let spread = Double.pi / 4
            func turned(_ x: Double, _ y: Double) -> Double {
                var angle = atan2(y - cy, x - cx) - front
                while angle > .pi { angle -= 2 * .pi }
                while angle < -.pi { angle += 2 * .pi }
                return angle
            }
            func risen(_ x: Double, _ y: Double) -> Double { rise(of: index, x, y) }
            var way: Double = startingLeft ? 1 : -1
            // The foot, where the first leg starts.
            let start = front - spread * way
            var reach = 0.0
            while lobe.depth(cx + reach * cos(start), cy + reach * sin(start)) + ripple(cx + reach * cos(start), cy + reach * sin(start)) > 0.02,
                  reach < 80 { reach += 0.05 }
            var x = cx + reach * cos(start), y = cy + reach * sin(start)
            // A short way in from the ground, straight up the slope.
            let up = uphill(of: index, x, y)
            var points = stride(from: 5, through: 1, by: -1).map { CGPoint(x: x - up.x * 0.12 * Double($0), y: y - up.y * 0.12 * Double($0)) }
            points.append(CGPoint(x: x, y: y))
            let step = 0.15
            // A leg for every couple of cells up: a mountain winds up and up.
            let legs = max(2, Int((lobe.band / 2.2).rounded()))
            for leg in 0..<legs {
                let from = risen(x, y), to = Double(leg + 1) / Double(legs)
                let first = turned(x, y), last = spread * way
                let span = max(abs(last - first), 0.01)
                for _ in 0..<1000 {
                    let n = uphill(of: index, x, y)
                    // Across the slope, the way this leg goes round.
                    var tx = n.y, ty = -n.x
                    if ((x - cx) * ty - (y - cy) * tx) * way < 0 { tx = -tx; ty = -ty }
                    let progress = min(1, abs(turned(x + step * tx, y + step * ty) - first) / span)
                    let want = from + (to - from) * progress
                    let gain = n.growth / lobe.band * step
                    let climb = min(1, max(0, (want - risen(x, y)) / max(gain, 1e-9)))
                    let across = (1 - climb * climb).squareRoot()
                    x += step * (across * tx + climb * n.x)
                    y += step * (across * ty + climb * n.y)
                    points.append(CGPoint(x: x, y: y))
                    if leg == legs - 1, risen(x, y) >= 0.999 { break }
                    if (turned(x, y) - last) * way >= 0 { break }
                }
                way = -way
            }
            // On up onto the top, and a little way across it.
            var onTop = 0
            for _ in 0..<200 where onTop < 4 {
                if risen(x, y) >= 0.999 { onTop += 1 }
                let n = uphill(of: index, x, y)
                x += step * n.x
                y += step * n.y
                points.append(CGPoint(x: x, y: y))
            }
            guard risen(x, y) >= 0.999 else { return nil }
            // Every other point is plenty for a smooth line.
            return stride(from: 0, to: points.count - 1, by: 2).map { points[$0] } + [points[points.count - 1]]
        }

        /// The steepest a trail climbs or drops over any cell of its length, in points a cell (where
        /// it doubles back on itself counts as the turn it is, not a cliff).
        func steepestClimb(along trail: [CGPoint]) -> Double {
            let heights = trail.map { Double(shape(Double($0.x), Double($0.y))) }
            var walked = [0.0]
            for (a, b) in zip(trail, trail.dropFirst()) { walked.append(walked[walked.count - 1] + Double(hypot(b.x - a.x, b.y - a.y))) }
            var worst = 0.0, j = 0
            for i in trail.indices {
                while j < trail.count - 1, walked[j] - walked[i] < 1 { j += 1 }
                guard walked[j] - walked[i] >= 1 else { break }
                worst = max(worst, abs(heights[j] - heights[i]) / (walked[j] - walked[i]))
            }
            return worst
        }

        /// How far a point is from the nearest trail's middle, in cells.
        func distanceToTrails(_ x: Double, _ y: Double) -> Double {
            trails.map { Self.distance(x, y, to: $0.points) }.min() ?? .infinity
        }

        /// How far a point is from a line's middle, in cells.
        static func distance(_ x: Double, _ y: Double, to line: [CGPoint]) -> Double {
            var best = Double.infinity
            for (a, b) in zip(line, line.dropFirst()) {
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
