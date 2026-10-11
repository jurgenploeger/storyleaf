import CoreGraphics
import Foundation

extension WorldMap {
    /// Raised ground out in the fields (`theme.hills`): a range of summits melted into one another,
    /// each rising smoothly from its foot to a rounded top of its own height, so a long ridge of hills
    /// or a mountain among its foothills. You can walk up it anywhere; its trails, the easy way up,
    /// wind up round its sides from the side that faces you and onto the tops.
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
            /// Which way a steeper side faces, if it has one (unit, in the grid), and how much faster
            /// it climbs there at its foot (`depth`). Only ever toward you: ground facing you can be as
            /// steep as you like, ground facing away no steeper than the view.
            var steepSide: (x: Double, y: Double)?
            var steepening = 0.0

            /// `steepness`: its range's (`Hill.steepness`).
            init(x: Double, y: Double, along: Double, across: Double, angle: Double, peak: Double, steepness: Double) {
                self.x = x
                self.y = y
                self.along = along
                self.across = across
                self.angle = angle
                self.peak = peak
                band = max(3, 1.5 * peak / steepness)
                cosine = cos(angle)
                sine = sin(angle)
            }

            /// How far inside its ellipse a point is: about the cells in from its edge, below 0 outside.
            /// On a steeper side it grows faster from the edge, up to `1 + steepening` times as fast at
            /// the edge itself and its usual pace by the middle, so the outline stays where it was.
            func depth(_ x: Double, _ y: Double) -> Double {
                let dx = x - self.x, dy = y - self.y
                let u = (dx * cosine + dy * sine) / along
                let v = (dy * cosine - dx * sine) / across
                let inside = (1 - (u * u + v * v).squareRoot()) * min(along, across)
                guard let side = steepSide, inside > 0 else { return inside }
                let toward = min(1, max(0, (dx * side.x + dy * side.y) / across))
                return inside * (1 + steepening * toward * toward)
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
        /// How high the ground really stands at its highest, from its samples: where two summits'
        /// tops meet it can stand up to a fifth over `peak`.
        var highest: CGFloat = 0
        /// How steep its summits' sides get halfway up, at most, in points a cell
        /// (`steepness(rockiness:)`).
        let steepness: Double
        /// Its trails: the first from the ground in front, then one up its mountain.
        var trails: [Trail] = []
        /// A cave's mouth in its side, where a road leads into a cave (`WorldMap.raiseCrags`): its
        /// middle at the foot (in cells), which way is along the edge it's on and which way into
        /// the hill (unit), how far across either side it opens (cells; the way out of the map is
        /// only there, `WorldMap.exit(at:)`), and how far in the mountain over it stands (cells).
        nonisolated struct Mouth {
            let x, y: Double
            let along: (x: Double, y: Double)
            let into: (x: Double, y: Double)
            let half, depth: Double
        }
        var mouth: Mouth?
        /// A range along a map's edge with a cave's mouth in it, rising on past the edge, rather than
        /// hills out in the fields.
        var isCrag: Bool { mouth != nil }
        /// The cells it rises over.
        var cells: Set<GridPoint> = []
        /// Its height sampled `samples` times a cell from `origin` over `size` cells, for walkers
        /// (`height(atCells:_:)`) and for drawing it.
        var origin = GridPoint(col: 0, row: 0)
        var size = (columns: 0, rows: 0)
        var heights: [Float] = []
        static let samples = 4

        /// How steep a range's sides get halfway up, at most, in points a cell: gentle slopes on the
        /// easiest maps (10), steep and rocky on the most dangerous (14). The view looks down at 30°,
        /// so ground facing away from you would drop out of sight past about 22 points a cell (going
        /// diagonally); this leaves room for the ripples and where summits meet.
        static func steepness(rockiness: Double) -> Double {
            10 + 4 * min(1, max(0, rockiness))
        }

        init(lobes: [Lobe], ripples: [(fx: Double, px: Double, fy: Double, py: Double)], steepness: Double) {
            self.lobes = lobes
            self.ripples = ripples
            self.steepness = steepness
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

        /// A trail up summit `index` as a path would wind up it, not zig-zagging: from its foot at
        /// angle `start` (grid space; toward the bottom of the screen is 225°), round its side one way
        /// (`way`, 1 or -1), climbing evenly as it goes and far enough round that halfway up it's no
        /// steeper than an easy walk (`stretch`, 1 or more, takes it further), bending gently in and
        /// out (`bends` times, from `phase`), then onto the top. Low hills get a curve; a mountain it
        /// sweeps round, and one it would take most of the way round turns back once (a hairpin).
        /// Nil if it doesn't get there.
        func traceTrail(on index: Int, from start: Double, way: Double, stretch: Double, phase: Double, bends: Int) -> [CGPoint]? {
            let lobe = lobes[index]
            let cx = lobe.x, cy = lobe.y
            func risen(_ x: Double, _ y: Double) -> Double { rise(of: index, x, y) }
            // The foot, where it starts.
            let out = (x: cos(start), y: sin(start))
            var reach = 0.0
            while reach < 80 {
                let px = cx + reach * out.x, py = cy + reach * out.y
                guard lobe.depth(px, py) + ripple(px, py) > 0.02 else { break }
                reach += 0.05
            }
            var x = cx + reach * out.x, y = cy + reach * out.y
            // A short way in from the ground, straight up the slope.
            let up = uphill(of: index, x, y)
            var points = stride(from: 5, through: 1, by: -1).map { CGPoint(x: x - up.x * 0.12 * Double($0), y: y - up.y * 0.12 * Double($0)) }
            points.append(CGPoint(x: x, y: y))
            // How far round: halfway up, about 5 points a cell.
            let middle = max(2, reach - lobe.band / 2)
            let sweep = min(max(1.5 * lobe.peak / (5 * middle) * stretch, 1.2), 3.2 * Double.pi)
            let legs = sweep <= 1.6 * Double.pi ? 1 : 2
            let each = sweep / Double(legs)
            // Bends of up to about a cell either way.
            let bend = min(0.12, 0.8 / lobe.band)
            let step = 0.15
            var turn = way
            for leg in 0..<legs {
                let from = risen(x, y), to = Double(leg + 1) / Double(legs)
                var gone = 0.0, last = atan2(y - cy, x - cx)
                for _ in 0..<4000 {
                    let n = uphill(of: index, x, y)
                    // Across the slope, the way it goes round.
                    var tx = n.y, ty = -n.x
                    if ((x - cx) * ty - (y - cy) * tx) * turn < 0 { tx = -tx; ty = -ty }
                    let progress = min(1, gone / each)
                    let swing: Double = sin(progress * Double.pi * Double(bends) + phase)
                    let wave: Double = bend * swing * sin(progress * Double.pi)
                    let want = from + (to - from) * progress + wave
                    let gain = n.growth / lobe.band * step
                    let climb = min(1, max(-0.5, (want - risen(x, y)) / max(gain, 1e-9)))
                    let across = max(0, 1 - climb * climb).squareRoot()
                    x += step * (across * tx + climb * n.x)
                    y += step * (across * ty + climb * n.y)
                    points.append(CGPoint(x: x, y: y))
                    let now = atan2(y - cy, x - cx)
                    var turned = now - last
                    while turned > .pi { turned -= 2 * .pi }
                    while turned < -.pi { turned += 2 * .pi }
                    gone += turned * turn
                    last = now
                    if leg == legs - 1, risen(x, y) >= 0.999 { break }
                    if gone >= each { break }
                }
                turn = -turn
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
