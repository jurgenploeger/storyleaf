import CoreGraphics
import Foundation

nonisolated extension WorldMap {
    /// Raised ground out in the fields (`theme.hills`): a range of summits melted into one another,
    /// each rising smoothly from its foot to a rounded top of its own height, so a long ridge of hills
    /// or a mountain among its foothills. You can walk up a hill anywhere, a mountain only by its trail
    /// (`WorldMap.shapeHill`); its trails, the easy way up, wind up round its sides from the side that
    /// faces you and onto the tops.
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
            /// A mountain's reach toward you (along `-angle`), in cells, shorter than `along`: turned
            /// to face you (`angle` 45°), it climbs gently from behind (`along`, as steep as ground
            /// facing away can be), steeper from the sides (`across`) and steepest up its face
            /// toward you, so it stands tall without a base that fills the map.
            var front: Double?
            /// Ridges down a mountain's face toward you, if it has any.
            var spurs: Spurs?

            /// Ridges fanning down a mountain's face from its summit (`front`): sharp crests with
            /// gullies between, unevenly spaced and sized, the most straight down the face toward
            /// you and fading away toward its sides, its summit and its foot, so its face reads as
            /// rock rather than a smooth mound. Only where it faces you: across a spur's far side,
            /// ground going up the screen drops, which the steep climb of the face makes up for there.
            nonisolated struct Spurs {
                /// How many ridges they'd be all the way round, how deep they cut (a share of the
                /// mountain's reach back), and three phases (where they fall, how unevenly spaced,
                /// how unevenly sized).
                let count, depth: Double
                let phases: (Double, Double, Double)
                /// Where they begin on the way round from the side (0) to straight toward you (1).
                static let from = 0.5

                /// How much deeper in the face stands at a point than its smooth shape, in shares of
                /// the reach back: `u` and `v` its place along (toward you below 0) and across, in
                /// shares of the reaches that way, and `reach` how far out it is (1 at the foot).
                func lift(u: Double, v: Double, reach: Double) -> Double {
                    let facing = min(1, -u / max(reach, 1e-9))
                    let k = min(1, max(0, (facing - Self.from) / (1 - Self.from)))
                    guard k > 0 else { return 0 }
                    let weight = k * k * (3 - 2 * k)
                    let angle = atan2(v, -u)
                    let warped = angle + 0.25 * sin(3 * angle + phases.1)
                    let ridge = 1 - abs(sin(count * warped / 2 + phases.0))
                    let size = 0.75 + 0.25 * sin(5 * angle + phases.2)
                    // Gone at the summit, where they'd all meet as steep as they are lower down
                    // while the face itself rounds off; deepest three quarters of the way down.
                    let out = min(reach, 1)
                    let fade = out * out * (1 - out * out * out) * 2.2
                    return depth * fade * size * (ridge - 0.5) * weight
                }
            }

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

            /// The round it stands in, for finding room for it: its middle and radius, in cells.
            var footprint: (x: Double, y: Double, radius: Double) {
                guard let front else { return (x, y, max(along, across)) }
                let shift = (along - front) / 2
                return (x + shift * cosine, y + shift * sine, max((along + front) / 2, across))
            }

            /// How far inside its ellipse a point is: about the cells in from its edge, below 0 outside.
            /// On a steeper side it grows faster from the edge, up to `1 + steepening` times as fast at
            /// the edge itself and its usual pace by the middle, so the outline stays where it was.
            /// A mountain (`front`) grows from its foot as fast as its gentle back does, steeper toward
            /// you and across, plus its spurs.
            func depth(_ x: Double, _ y: Double) -> Double {
                let dx = x - self.x, dy = y - self.y
                let lean = dx * cosine + dy * sine
                let u = lean / (lean < 0 ? front ?? along : along)
                let v = (dy * cosine - dx * sine) / across
                let reach = (u * u + v * v).squareRoot()
                var inside = (1 - reach) * (front == nil ? min(along, across) : along)
                if lean < 0, let spurs { inside += spurs.lift(u: u, v: v, reach: reach) * along }
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
        /// How low it lies at its lowest, below 0 where it's sunk (`sunken`).
        var lowest: CGFloat = 0
        /// Ground sunk below the land round it rather than raised: the shore sloping down to the sea
        /// and into the lakes (`WorldMap.shore`). Drawn as a hill is (`HillArt`), over its `cells`
        /// and a cell round them, with no outline, trails or bare rock of its own.
        var sunken = false
        /// How steep its summits' sides get halfway up, at most, in points a cell
        /// (`steepness(rockiness:)`).
        let steepness: Double
        /// Its trails: the first from the ground in front, then one up its mountain.
        var trails: [Trail] = []
        /// A cave's mouth in its side, where a road leads into a cave (`WorldMap.raiseCrags`): its
        /// middle at the foot (in cells), which way is along the rock face it's in and which way
        /// into the rock (unit), how far across either side it opens (cells; the way out of the map
        /// is only there, `WorldMap.exit(at:)`), and how far in the rock over it stands (cells).
        /// `beside`: in a crag beside the road's end, its face turned back along the map's edge,
        /// rather than where the road meets the edge.
        nonisolated struct Mouth {
            let x, y: Double
            let along: (x: Double, y: Double)
            let into: (x: Double, y: Double)
            let half, depth: Double
            let beside: Bool
        }
        var mouth: Mouth?
        /// The rock wall a cave's mouth is in, facing you (`WorldMap.raiseCrags`): from its foot, a
        /// line through the mouth's, it climbs `rise` points in `run` cells, near enough sheer, then
        /// falls back `fall` points a cell into the slopes behind; full height `reach` cells either
        /// side of the mouth, then tapering away, quickly at the end toward you (-`along`) and
        /// slowly at the end away (+`along`, up the map whichever edge it's on). Its face can be as
        /// steep as you like, facing you; its back and far end, facing away, fall no faster than
        /// ground can and still show. Its foot stands at `base` all along, or if nil on the ground.
        nonisolated struct Wall {
            let x, y: Double
            let along: (x: Double, y: Double)
            let into: (x: Double, y: Double)
            let base: Double?
            let reach: Double
            let taper: (toward: Double, away: Double)
            let run, rise, fall: Double

            /// A point's place from the middle of its foot: cells along it and cells in.
            func spot(_ x: Double, _ y: Double) -> (along: Double, into: Double) {
                let dx = x - self.x, dy = y - self.y
                return (dx * along.x + dy * along.y, dx * into.x + dy * into.y)
            }

            /// Its foot straight out from a point.
            func foot(_ x: Double, _ y: Double) -> (x: Double, y: Double) {
                let inward = spot(x, y).into
                return (x - into.x * inward, y - into.y * inward)
            }

            /// At a point in it: how much of its height stands there (1 in its full width, falling to
            /// 0 at its ends), how high it stands over its foot before that, and how far up its face
            /// the point is (0 at the foot, 1 at the top of the face). Nil outside it.
            func lift(_ x: Double, _ y: Double) -> (width: Double, height: Double, up: Double)? {
                let place = spot(x, y)
                guard place.into > 0 else { return nil }
                let end = place.along > 0 ? taper.away : taper.toward
                let width = Self.smooth((reach + end - abs(place.along)) / end)
                guard width > 0 else { return nil }
                let height = rise * Self.smooth(place.into / run) - fall * max(0, place.into - run)
                return (width, height, Self.smooth(place.into / (run * 0.4)) * width)
            }

            /// How far inside it a point is, about the cells in from its edge, below 0 outside it.
            func depth(_ x: Double, _ y: Double) -> Double {
                let place = spot(x, y)
                let back = run + ((base ?? 0) + rise) / fall
                let end = place.along > 0 ? taper.away : taper.toward
                return min(place.into + 0.5, back - place.into, reach + end - abs(place.along))
            }

            static func smooth(_ value: Double) -> Double {
                let t = min(1, max(0, value))
                return t * t * (3 - 2 * t)
            }
        }
        var wall: Wall?
        /// A range along a map's edge with a cave's mouth in it, rising on past the edge, rather than
        /// hills out in the fields.
        var isCrag: Bool { mouth != nil }
        /// A range with a mountain among its summits (`Lobe.front`).
        var hasMountain: Bool { lobes.contains { $0.front != nil } }
        /// The cells it rises over.
        var cells: Set<GridPoint> = []
        /// Its height sampled `samples` times a cell from `origin` over `size` cells, for walkers
        /// (`height(atCells:_:)`) and for drawing it.
        var origin = GridPoint(col: 0, row: 0)
        var size = (columns: 0, rows: 0)
        var heights: [Float] = []
        static let samples = 4

        /// The most the ground may drop going up the screen, in points over a cell across and a
        /// cell up the map at once: a little short of the view's 31, past which it would fold over
        /// and hide itself (and a tap would find two spots).
        static let foldLimit = 28.0

        /// Raises its samples wherever the ground, going up the screen, would drop faster than
        /// `foldLimit` (across a mountain's spurs it can), so every spot on screen still shows one
        /// place. As walkers stand on them, each square of four samples slopes evenly between its
        /// corners, so it drops fastest at its near corner or its far one: a diagonal of samples
        /// at a time, front to back (up the screen), each is raised as far as the squares in front
        /// of it need, the two beyond a square's near corner sharing what they're short of it, so
        /// a fold is filled in a few points, never piled up. Ground that already stays in sight is
        /// left as it is.
        mutating func unfold() {
            let width = size.columns * Self.samples + 1, depth = size.rows * Self.samples + 1
            guard width > 1, depth > 1 else { return }
            let most = Float(Self.foldLimit / Double(Self.samples))
            func at(_ i: Int, _ j: Int) -> Float { heights[j * width + i] }
            var raised: [(index: Int, height: Float)] = []
            for level in 1..<(width + depth - 1) {
                raised.removeAll(keepingCapacity: true)
                for i in max(0, level - depth + 1)...min(level, width - 1) {
                    let j = level - i
                    let here = at(i, j)
                    var need = here
                    // The square it's the far corner of: from its near corner, and from the two
                    // beside it.
                    if i > 0, j > 0 {
                        need = max(need, at(i - 1, j - 1) - most, (at(i - 1, j) + at(i, j - 1) - most) / 2)
                    }
                    // The squares it's beyond the near corner of, with the sample beside it.
                    if i > 0, j + 1 < depth {
                        let short = 2 * at(i - 1, j) - most - here - at(i - 1, j + 1)
                        need = max(need, here + short / 2)
                    }
                    if j > 0, i + 1 < width {
                        let short = 2 * at(i, j - 1) - most - at(i + 1, j - 1) - here
                        need = max(need, here + short / 2)
                    }
                    if need > here { raised.append((j * width + i, need)) }
                }
                for (index, height) in raised { heights[index] = height }
            }
        }

        /// How steep a range's sides get halfway up, at most, in points a cell: gentler slopes on the
        /// easiest maps (13), steep and rocky on the most dangerous (18). The view looks down at 30°,
        /// so ground facing away from you would drop out of sight past about 22 points a cell (going
        /// diagonally); this leaves room for the ripples and where summits meet, and `unfold()` keeps
        /// what's left in view. Up from 10 to 14 before 0.4.14, where hills hardly showed.
        static func steepness(rockiness: Double) -> Double {
            13 + 5 * min(1, max(0, rockiness))
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
            if let wall { deepest = max(deepest, wall.depth(x, y)) }
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
            if let wall, let lift = wall.lift(x, y) { highest = max(highest, lift.up) }
            return highest
        }

        /// Its height at a point, worked out exactly: each summit gentle at its foot, steepest halfway
        /// up and rounding off onto its top (smoothstep), and the summits blended (the fourth root of
        /// their heights' fourth powers): as high as the highest, a little fuller where two meet, and
        /// flat ground where none rise. A cave's wall (`wall`) stands over the ground at its foot.
        func shape(_ x: Double, _ y: Double) -> CGFloat {
            let ground = summits(x, y)
            guard let wall, let lift = wall.lift(x, y) else { return CGFloat(ground) }
            if let base = wall.base {
                return CGFloat(max(ground, max(0, base + lift.height) * lift.width))
            }
            // On the ground at its foot, falling back into the slopes behind, and on down to them
            // where they're lower than its foot; nothing stands level behind it to end in a cliff
            // where it does.
            let foot = wall.foot(x, y)
            let over = summits(foot.x, foot.y) + lift.height - ground
            return CGFloat(ground + max(0, over) * lift.width)
        }

        /// The summits' blended height at a point (`shape`).
        private func summits(_ x: Double, _ y: Double) -> Double {
            let wave = ripple(x, y)
            var total = 0.0
            for lobe in lobes {
                let s = min(1, max(0, (lobe.depth(x, y) + wave) / lobe.band))
                let height = lobe.peak * s * s * (3 - 2 * s)
                total += height * height * height * height
            }
            return total.squareRoot().squareRoot()
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
