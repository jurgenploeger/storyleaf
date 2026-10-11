import SpriteKit

/// Draws a hill (`WorldMap.Hill`): the ground it rises over as one picture (the map's own tiles,
/// bare patches on its steepest slopes, its trail painted up it), lit from the upper left like the
/// trees' shadows say, then lifted off the map by its heights (`SKWarpGeometryGrid`).
enum HillArt {
    struct Look {
        /// The ground's tile pictures by cell, as the map has them.
        let ground: (GridPoint) -> CGImage?
        /// The trail's tile pictures by cell (the map's road).
        let trail: (GridPoint) -> CGImage?
        /// What shows through on its steepest slopes, by cell (none when the map doesn't say).
        let bank: ((GridPoint) -> CGImage?)?
        /// The soft colour patches over the map's whole ground: a pixel a cell, north at the top.
        let variation: CGImage?
        let mapSize: (columns: Int, rows: Int)
        /// Slopes in shade lean toward this colour, sunny ones toward the highlight.
        let shadow: (r: Double, g: Double, b: Double)
        let highlight: (r: Double, g: Double, b: Double)
    }

    /// The hill as a sprite in grid space (for the projected ground layer), or nil if it can't be drawn.
    static func sprite(for hill: WorldMap.Hill, look: Look) -> SKSpriteNode? {
        guard let first = hill.cells.first, let sample = look.ground(first) else { return nil }
        let tile = WorldMap.tileSize
        let px = sample.width
        let scale = CGFloat(px)
        let low = hill.origin
        // Its samples' area, and room above and to the right for it to rise into.
        let lift = Int((hill.peak * CGFloat(2).squareRoot() / tile).rounded(.up)) + 1
        let columns = hill.size.columns + lift, rows = hill.size.rows + lift
        let width = columns * px, height = rows * px
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        func rect(_ cell: GridPoint) -> CGRect {
            CGRect(x: CGFloat(cell.col - low.col) * scale, y: CGFloat(cell.row - low.row) * scale, width: scale, height: scale)
        }
        func spot(_ point: CGPoint) -> CGPoint {
            CGPoint(x: (point.x - CGFloat(low.col)) * scale, y: (point.y - CGFloat(low.row)) * scale)
        }
        let whole = CGRect(x: 0, y: 0, width: width, height: height)
        let area = (0..<hill.size.rows).flatMap { j in (0..<hill.size.columns).map { i in GridPoint(col: low.col + i, row: low.row + j) } }
            .filter { $0.col >= 0 && $0.row >= 0 && $0.col < look.mapSize.columns && $0.row < look.mapSize.rows }

        // The ground, tile by tile as the map has it.
        context.interpolationQuality = .none
        for cell in area {
            if let picture = look.ground(cell) { context.draw(picture, in: rect(cell)) }
        }

        // Per sample (`Hill.samples` a cell): how much bank shows, how it's lit, and where it ends.
        let samples = WorldMap.Hill.samples
        let sw = columns * samples, sh = rows * samples
        var bare = [UInt8](repeating: 0, count: sw * sh * 4)
        var multiply = [UInt8](repeating: 255, count: sw * sh * 4)
        var screen = [UInt8](repeating: 0, count: sw * sh * 4)
        var mask = [UInt8](repeating: 0, count: sw * sh * 4)
        for index in stride(from: 3, to: screen.count, by: 4) { screen[index] = 255 }
        // Sunlight from the upper left of the screen (up the map and to the left), 36° up.
        let up = 36 * Double.pi / 180
        let toward = (x: -0.6, y: 1.0), length = (0.36 + 1.0).squareRoot()
        let light = (x: toward.x / length * cos(up), y: toward.y / length * cos(up), z: sin(up))
        let ambient = 0.25
        let flat = ambient + (1 - ambient) * light.z
        let deepest = max(look.shadow.r, look.shadow.g, look.shadow.b, 0.01)
        let tint = (look.shadow.r / deepest, look.shadow.g / deepest, look.shadow.b / deepest)
        let steepest = 1.5 * Double(hill.peak) / hill.band
        for j in 0..<sh {
            for i in 0..<sw {
                let x = Double(low.col) + (Double(i) + 0.5) / Double(samples)
                let y = Double(low.row) + (Double(j) + 0.5) / Double(samples)
                // Image rows run top down.
                let index = ((sh - 1 - j) * sw + i) * 4
                let field = hill.field(x, y)
                // Its outline, softened, and the trail's start out on the ground in front.
                var edge = min(1, max(0, (field + 0.06) / 0.25))
                if field < 0.2 { edge = max(edge, min(1, max(0, (0.45 - hill.distanceToTrail(x, y)) / 0.1))) }
                for channel in 0..<4 { mask[index + channel] = UInt8(edge * 255) }
                guard field > 0 else { continue }
                // How the slope faces the sun. Heights stand 1/cos 30° taller than they're drawn.
                let e = 0.05
                let hx = Double(hill.shape(x + e, y) - hill.shape(x - e, y)) / (2 * e) / Double(tile) / 0.866
                let hy = Double(hill.shape(x, y + e) - hill.shape(x, y - e)) / (2 * e) / Double(tile) / 0.866
                let lambert = (-hx * light.x - hy * light.y + light.z) / (hx * hx + hy * hy + 1).squareRoot()
                var shade = (ambient + (1 - ambient) * max(0, lambert)) / flat
                let s = hill.rise(x, y)
                shade *= 1 + 0.07 * Double(hill.shape(x, y) / hill.peak)
                // The foot tucked in a little darker, the shoulder catching a little more light.
                if s < 0.3 { shade *= 1 - 0.1 * sin(Double.pi * s / 0.3) }
                if s > 0.7 { shade *= 1 + 0.06 * sin(Double.pi * (s - 0.7) / 0.3) }
                if shade < 1 {
                    let lean = (1 - shade) * 0.6
                    multiply[index] = UInt8(min(255, max(0, shade * (1 - lean * (1 - tint.0)) * 255)))
                    multiply[index + 1] = UInt8(min(255, max(0, shade * (1 - lean * (1 - tint.1)) * 255)))
                    multiply[index + 2] = UInt8(min(255, max(0, shade * (1 - lean * (1 - tint.2)) * 255)))
                } else {
                    let glow = min(1, shade - 1)
                    screen[index] = UInt8(min(255, look.highlight.r * glow * 255))
                    screen[index + 1] = UInt8(min(255, look.highlight.g * glow * 255))
                    screen[index + 2] = UInt8(min(255, look.highlight.b * glow * 255))
                }
                // The bank shows through in ragged patches where it's steepest, but not by the trail.
                guard look.bank != nil, s > 0, s < 1 else { continue }
                let slope = Double(hill.peak) * 6 * s * (1 - s) * hill.uphill(x, y).growth / hill.band
                let ragged = sin(x * 2.3 + 1.1) * sin(y * 1.9 + 0.3) * 0.5 + sin(x * 5.1) * sin(y * 4.7 + 2) * 0.3
                var amount = min(1, max(0, (slope / steepest - 0.72 + ragged * 0.15) / 0.12)) * 0.75
                if amount > 0 { amount *= min(1, max(0, (hill.distanceToTrail(x, y) - 0.55) / 0.3)) }
                for channel in 0..<4 { bare[index + channel] = UInt8(amount * 255) }
            }
        }
        context.interpolationQuality = .medium
        if let bank = look.bank, let patches = image(bare, width: sw, height: sh) {
            context.saveGState()
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            context.interpolationQuality = .none
            for cell in area where hill.cells.contains(cell) {
                if let picture = bank(cell) { context.draw(picture, in: rect(cell)) }
            }
            context.interpolationQuality = .medium
            context.setBlendMode(.destinationIn)
            context.draw(patches, in: whole)
            context.endTransparencyLayer()
            context.restoreGState()
        }

        // The trail, cut into the slope: a shadow along its uphill edge, a lighter lip along the
        // downhill one, and the trail itself in the map's road.
        func line(_ shift: Double) -> CGPath {
            let path = CGMutablePath()
            path.addLines(between: hill.trail.map { point in
                let up = hill.uphill(Double(point.x), Double(point.y))
                return spot(CGPoint(x: Double(point.x) + up.x * shift, y: Double(point.y) + up.y * shift))
            })
            return path
        }
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(0.6 * scale)
        context.setStrokeColor(UIColor(white: 0, alpha: 0.3).cgColor)
        context.addPath(line(0.12))
        context.strokePath()
        context.setStrokeColor(UIColor(white: 1, alpha: 0.16).cgColor)
        context.addPath(line(-0.12))
        context.strokePath()
        context.addPath(line(0))
        context.replacePathWithStrokedPath()
        context.clip()
        context.interpolationQuality = .none
        for cell in area {
            if let picture = look.trail(cell) { context.draw(picture, in: rect(cell)) }
        }
        context.restoreGState()

        // The colour patches the rest of the ground has, then the light, then its outline.
        context.interpolationQuality = .medium
        if let variation = look.variation {
            context.draw(variation, in: CGRect(x: -CGFloat(low.col) * scale, y: -CGFloat(low.row) * scale,
                                               width: CGFloat(look.mapSize.columns) * scale, height: CGFloat(look.mapSize.rows) * scale))
        }
        if let shading = image(multiply, width: sw, height: sh), let glow = image(screen, width: sw, height: sh),
           let outline = image(mask, width: sw, height: sh) {
            context.setBlendMode(.multiply)
            context.draw(shading, in: whole)
            context.setBlendMode(.screen)
            context.draw(glow, in: whole)
            context.setBlendMode(.destinationIn)
            context.draw(outline, in: whole)
            context.setBlendMode(.normal)
        }
        guard let picture = context.makeImage() else { return nil }

        let texture = SKTexture(cgImage: picture)
        texture.filteringMode = .nearest
        let sprite = SKSpriteNode(texture: texture, size: CGSize(width: CGFloat(columns) * tile, height: CGFloat(rows) * tile))
        sprite.anchorPoint = .zero
        sprite.position = CGPoint(x: CGFloat(low.col) * tile, y: CGFloat(low.row) * tile)
        // Lifted by its heights, two points a cell: up the screen is up the map and right at once in
        // the ground's grid, `height × √2` along each.
        let gridColumns = columns * 2, gridRows = rows * 2
        var source: [SIMD2<Float>] = [], destination: [SIMD2<Float>] = []
        for j in 0...gridRows {
            for i in 0...gridColumns {
                let u = Float(i) / Float(gridColumns), v = Float(j) / Float(gridRows)
                let rise = hill.height(atCells: Double(low.col) + Double(i) / 2, Double(low.row) + Double(j) / 2) * CGFloat(2).squareRoot()
                source.append(SIMD2(u, v))
                destination.append(SIMD2(u + Float(rise / sprite.size.width), v + Float(rise / sprite.size.height)))
            }
        }
        sprite.warpGeometry = SKWarpGeometryGrid(columns: gridColumns, rows: gridRows, sourcePositions: source, destinationPositions: destination)
        return sprite
    }

    /// Premultiplied RGBA bytes, top row first, as an image.
    private static func image(_ bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
