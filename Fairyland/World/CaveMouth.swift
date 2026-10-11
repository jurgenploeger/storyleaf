import SpriteKit

/// The way into a cave from outside (`WorldMap.Crag`), where the road meets the cave's rock at the
/// map's edge. On the sides of the map away from you (north and east) the rock's face there looks
/// your way, and the mouth is a dark arch in it at the end of the road. On the sides toward you
/// (south and west) that face would look away, out of sight, so the road runs on out past the edge
/// under an arch of rock into a dark cleft instead. Either way the cave's darkness spills a little
/// way out over the road.
enum CaveMouth {
    /// How tall each tier of the rock stands where a road leads into a cave (`WorldMap.cragTiers`):
    /// the first well over a cave's own walls, the mountain or ridge beyond in two more steps.
    static let heights: [CGFloat] = [56, 44, 44]
    /// Their tops a little darker than their rock, like a cave's, but out in the daylight; the
    /// higher, the lighter, so each step stands apart from the one below.
    static let topShades: [CGFloat] = [0.32, 0.25, 0.18]
    /// The mouth is in the first tier.
    static var height: CGFloat { heights[0] }
    static var topShade: CGFloat { topShades[0] }
    /// Pixels per point in its pictures, like the walls' blocks.
    private static let scale: CGFloat = 2

    /// Everything the mouth needs, already sorted, to put straight in the world.
    static func sprites(for crag: WorldMap.Crag, map: WorldMap, art: ArtLibrary) -> [SKNode] {
        let tile = WorldMap.tileSize
        let side = art.tileVariant(crag.cave.rock, 1).cgImage()
        let top = art.tileVariant(crag.cave.rock, 0).cgImage()
        let across = crag.edge == .north || crag.edge == .south
        // Along the edge, and in toward the map, in grid points.
        let along = across ? CGVector(dx: 1, dy: 0) : CGVector(dx: 0, dy: 1)
        let inward: CGVector = switch crag.edge {
        case .north: CGVector(dx: 0, dy: -1)
        case .south: CGVector(dx: 0, dy: 1)
        case .east: CGVector(dx: -1, dy: 0)
        case .west: CGVector(dx: 1, dy: 0)
        }
        /// The point on the map's edge `at` cells along it and `inward` cells in (below 0 out past
        /// it), in grid points.
        func ground(_ at: CGFloat, _ inside: CGFloat) -> CGPoint {
            let start: CGPoint = switch crag.edge {
            case .north: CGPoint(x: 0, y: CGFloat(map.rows) * tile)
            case .south: .zero
            case .east: CGPoint(x: CGFloat(map.columns) * tile, y: 0)
            case .west: .zero
            }
            return CGPoint(x: start.x + (along.dx * at + inward.dx * inside) * tile,
                           y: start.y + (along.dy * at + inward.dy * inside) * tile)
        }
        let from = CGFloat(crag.mouth.lowerBound), to = CGFloat(crag.mouth.upperBound + 1)
        let length = (to - from) * tile
        let toward = crag.opensTowardYou
        // The face the mouth is in: on the edge, looking in; or the arch's, a cell out, looking out.
        let base = WorldMap.project(ground(from, toward ? -1 : 0))
        let unit = WorldMap.project(CGPoint(x: along.dx, y: along.dy))
        let step = CGVector(dx: unit.x, dy: unit.y)
        let mouth = opening(length: length, height: height)
        var sprites: [SKNode] = []
        if let floor = darkness(from: from, to: to, toward: toward, ground: ground) { sprites.append(floor) }

        // A cell of it at a time, each sorted just in front of the rock it's on (or, for an arch, just
        // in front of whoever stands under it): one picture would be in front of some and behind others.
        for cell in crag.mouth {
            let u0 = (CGFloat(cell) - from) * tile, u1 = u0 + tile
            let corners = [base + step * u0, base + step * u1]
            var points = corners + corners.map { $0 + CGVector(dx: 0, dy: height) }
            if toward {
                points += [WorldMap.project(ground(CGFloat(cell), 0)), WorldMap.project(ground(CGFloat(cell) + 1, 0))]
                    .map { $0 + CGVector(dx: 0, dy: height) }
            }
            let xs = points.map(\.x), ys = points.map(\.y)
            let box = CGRect(x: xs.min()! - 4, y: ys.min()! - 4, width: xs.max()! - xs.min()! + 8, height: ys.max()! - ys.min()! + 8)
            guard let context = CGContext(data: nil, width: Int((box.width * scale).rounded(.up)), height: Int((box.height * scale).rounded(.up)),
                                          bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { continue }
            context.interpolationQuality = .none
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -box.minX, y: -box.minY)
            if toward {
                // The arch's top, the rock's top tile, lit like the tops either side.
                let topCorners = [corners[0], corners[1], WorldMap.project(ground(CGFloat(cell) + 1, 0)), WorldMap.project(ground(CGFloat(cell), 0))]
                    .map { $0 + CGVector(dx: 0, dy: height) }
                let outline = CGMutablePath()
                outline.addLines(between: topCorners)
                outline.closeSubpath()
                context.saveGState()
                context.addPath(outline)
                context.clip()
                let origin = WorldMap.project(.zero) + CGVector(dx: 0, dy: height)
                let c = CGFloat(0.5).squareRoot()
                context.concatenate(CGAffineTransform(a: c, b: c / 2, c: -c, d: c / 2, tx: origin.x, ty: origin.y))
                let corner = ground(CGFloat(cell), -1)
                let lowest = CGPoint(x: min(corner.x, corner.x + along.dx * tile), y: min(corner.y, corner.y + along.dy * tile))
                context.draw(top, in: CGRect(x: lowest.x - 2, y: lowest.y - 2, width: tile + 4, height: tile + 4))
                context.restoreGState()
                context.saveGState()
                context.addPath(outline)
                context.clip()
                context.setFillColor(UIColor(white: 0, alpha: topShade).cgColor)
                context.fill(box)
                context.restoreGState()
                // Light along the lip over its face; a dark rim where it drops away behind.
                line(context, topCorners[0], topCorners[1], UIColor(white: 1, alpha: 0.4))
                line(context, topCorners[2], topCorners[3], UIColor(white: 0, alpha: 0.5))
            }
            // On the face, in its own terms: across it from `base`, and up.
            context.saveGState()
            context.concatenate(CGAffineTransform(a: step.dx, b: step.dy, c: 0, d: 1, tx: base.x, ty: base.y))
            context.clip(to: CGRect(x: u0, y: -8, width: tile, height: height + 16))
            if toward {
                face(context, length: length, side: side, mouth: mouth, shade: crag.edge == .south ? 0.32 : 0.12)
            } else {
                dark(context, mouth: mouth)
            }
            context.restoreGState()
            guard let image = context.makeImage() else { continue }
            let texture = SKTexture(cgImage: image)
            texture.filteringMode = .nearest
            let sprite = SKSpriteNode(texture: texture, size: box.size)
            sprite.anchorPoint = .zero
            sprite.position = box.origin
            // A mouth: between the rock it's on (sorted by its middle, half a cell out past the edge)
            // and whoever stands in the road's last cell (half a cell in). An arch: in front of the
            // rock beside it and of whoever walks under it from the map.
            let middle = WorldMap.project(ground(CGFloat(cell) + 0.5, toward ? -0.5 : 0))
            sprite.zPosition = -middle.y + (toward ? 2 : 0)
            sprites.append(sprite)
        }
        return sprites
    }

    /// The mouth in a face `length` points across and `height` up (x across it, y up): straight sides
    /// a little in from each end up to about half its height, then a rough round top.
    private static func opening(length: CGFloat, height: CGFloat) -> CGPath {
        let side = max(6, length * 0.14)
        let spring = height * 0.45, crown = height * 0.82
        let path = CGMutablePath()
        path.move(to: CGPoint(x: side, y: -1))
        let steps = 16
        for k in 0...steps {
            let t = CGFloat(k) / CGFloat(steps)
            let middle = 2 * t - 1
            let round = max(0, 1 - middle * middle).squareRoot()
            // A little rough, but not at its feet.
            let rough: CGFloat = k == 0 || k == steps ? 0 : 1.5 * CGFloat(sin(Double(k) * 2.3 + 0.7))
            path.addLine(to: CGPoint(x: side + (length - 2 * side) * t, y: spring + (crown - spring) * round + rough))
        }
        path.addLine(to: CGPoint(x: length - side, y: -1))
        path.closeSubpath()
        return path
    }

    /// The cave's darkness in its mouth, deepest at the top, and its rim: a shadow just inside it.
    private static func dark(_ context: CGContext, mouth: CGPath) {
        let space = CGColorSpaceCreateDeviceRGB()
        let colors = [UIColor(red: 0.05, green: 0.045, blue: 0.06, alpha: 0.9).cgColor,
                      UIColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 0.97).cgColor] as CFArray
        context.saveGState()
        context.addPath(mouth)
        context.clip()
        if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height * 0.8),
                                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        context.restoreGState()
        context.addPath(mouth)
        context.setStrokeColor(UIColor(white: 0, alpha: 0.5).cgColor)
        context.setLineWidth(3)
        context.strokePath()
    }

    /// An arch's face: the rock's side tile across it but for the mouth, shaded like the walls'
    /// faces (`shade` by which way it looks), darker toward the ground and catching the light at
    /// its lip.
    private static func face(_ context: CGContext, length: CGFloat, side: CGImage, mouth: CGPath, shade: CGFloat) {
        let tile = WorldMap.tileSize
        let rect = CGRect(x: 0, y: 0, width: length, height: height)
        let frame = CGMutablePath()
        frame.addRect(rect)
        frame.addPath(mouth)
        context.addPath(frame)
        context.clip(using: .evenOdd)
        var y: CGFloat = 0
        while y < height {
            var x: CGFloat = 0
            while x < length {
                context.draw(side, in: CGRect(x: x, y: y, width: tile, height: tile))
                x += tile
            }
            y += tile
        }
        context.setFillColor(UIColor(white: 0, alpha: shade).cgColor)
        context.fill(rect)
        let space = CGColorSpaceCreateDeviceRGB()
        let toFloor = [UIColor(white: 0, alpha: 0.45).cgColor, UIColor(white: 0, alpha: 0).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: toFloor, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height * 0.7), options: [])
        }
        let lip = [UIColor(white: 1, alpha: 0).cgColor, UIColor(white: 1, alpha: 0.22).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: lip, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height - 7), end: CGPoint(x: 0, y: height), options: [])
        }
        // A shadow round the inside of the arch.
        context.addPath(mouth)
        context.setStrokeColor(UIColor(white: 0, alpha: 0.5).cgColor)
        context.setLineWidth(2.5)
        context.strokePath()
    }

    private static func line(_ context: CGContext, _ a: CGPoint, _ b: CGPoint, _ color: UIColor) {
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1.5)
        context.setLineCap(.round)
        context.move(to: a)
        context.addLine(to: b)
        context.strokePath()
    }

    /// The cave's darkness spilling out over the ground: a little over the road's last cell, and on
    /// the sides that face you deep in the cleft past the arch. On the ground, under everything.
    private static func darkness(from: CGFloat, to: CGFloat, toward: Bool, ground: (CGFloat, CGFloat) -> CGPoint) -> SKNode? {
        // From well in (clear) to out past the edge (dark).
        let inner: CGFloat = 1.2, outer: CGFloat = toward ? -3 : 0
        let corners = [ground(from, inner), ground(to, inner), ground(to, outer), ground(from, outer)].map(WorldMap.project)
        let xs = corners.map(\.x), ys = corners.map(\.y)
        let box = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        guard box.width > 0, box.height > 0,
              let context = CGContext(data: nil, width: Int(box.width.rounded(.up)), height: Int(box.height.rounded(.up)),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.translateBy(x: -box.minX, y: -box.minY)
        let outline = CGMutablePath()
        outline.addLines(between: corners)
        outline.closeSubpath()
        context.addPath(outline)
        context.clip()
        let middle = (from + to) / 2
        let start = WorldMap.project(ground(middle, inner)), end = WorldMap.project(ground(middle, toward ? -2 : 0))
        let colors: [CGColor] = toward
            ? [UIColor(white: 0, alpha: 0).cgColor, UIColor(white: 0, alpha: 0.6).cgColor, UIColor(white: 0, alpha: 0.95).cgColor]
            : [UIColor(white: 0, alpha: 0).cgColor, UIColor(white: 0, alpha: 0.15).cgColor, UIColor(white: 0, alpha: 0.35).cgColor]
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 0.45, 1])
        else { return nil }
        context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsAfterEndLocation])
        guard let image = context.makeImage() else { return nil }
        let sprite = SKSpriteNode(texture: SKTexture(cgImage: image), size: box.size)
        sprite.anchorPoint = .zero
        sprite.position = box.origin
        // Over the ground and the land past the map's edge, under the rock and whoever walks by.
        sprite.zPosition = -99_500
        return sprite
    }
}
