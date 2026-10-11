import SpriteKit

/// Draws a hill (`WorldMap.Hill`): the ground it rises over as one picture (the map's own tiles,
/// bare patches on its steepest slopes, its trail painted up it), lit from the upper left like the
/// trees' shadows say, then lifted off the map by its heights. The lifting is a small shader on a
/// flat sprite over where the hill shows on screen: each pixel finds the ground point that rises to
/// it (`WorldMap.groundPoint`'s halving, against the same heights walkers stand on) and shows the
/// picture there. A warped sprite (`SKWarpGeometryGrid`) did the same, but SpriteKit crashed
/// subdividing grids that size.
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

    /// The hill as a sprite in the map's own space (put it straight in the world), or nil if it
    /// can't be drawn.
    static func sprite(for hill: WorldMap.Hill, look: Look) -> SKSpriteNode? {
        guard let first = hill.cells.first, let sample = look.ground(first) else { return nil }
        let tile = WorldMap.tileSize
        let px = sample.width
        let scale = CGFloat(px)
        let low = hill.origin
        // Its samples' area.
        let columns = hill.size.columns, rows = hill.size.rows
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
        var mask = [UInt8](repeating: 0, count: sw * sh * 4)
        // How bright each sample is lit, 1 on the flat (bottom row first, like the heights).
        var light = [Float](repeating: 1, count: sw * sh)
        // Sunlight from the upper left of the screen (up the map and to the left), 36° up. Soft: the
        // sides away from it go a few shades darker, the sides facing it only a shade lighter, so
        // the hill reads as matte ground rather than something glossy.
        let up = 36 * Double.pi / 180
        let toward = (x: -0.6, y: 1.0), length = (0.36 + 1.0).squareRoot()
        let sun = (x: toward.x / length * cos(up), y: toward.y / length * cos(up), z: sin(up))
        let ambient = 0.45
        let flat = ambient + (1 - ambient) * sun.z
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
                let lambert = (-hx * sun.x - hy * sun.y + sun.z) / (hx * hx + hy * hy + 1).squareRoot()
                var shade = (ambient + (1 - ambient) * max(0, lambert)) / flat
                let s = hill.rise(x, y)
                // The foot tucked in a little darker.
                if s < 0.3 { shade *= 1 - 0.08 * sin(Double.pi * s / 0.3) }
                light[j * sw + i] = Float(shade)
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
        context.setStrokeColor(UIColor(white: 1, alpha: 0.1).cgColor)
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
        shade(context, light: light, samples: (sw, sh), perSample: Float(px) / Float(samples), tint: tint)
        if let outline = image(mask, width: sw, height: sh) {
            context.setBlendMode(.destinationIn)
            context.draw(outline, in: whole)
            context.setBlendMode(.normal)
        }
        guard let picture = context.makeImage() else { return nil }

        let texture = SKTexture(cgImage: picture)
        texture.filteringMode = .nearest
        // Its heights, as a picture the shader reads (smoothly between samples, like
        // `Hill.height(atCells:_:)`): 255ths of its peak in red, and what's left over in green.
        let width2 = hill.size.columns * samples + 1, depth2 = hill.size.rows * samples + 1
        var levels = [UInt8](repeating: 0, count: width2 * depth2 * 4)
        for j in 0..<depth2 {
            for i in 0..<width2 {
                let value = Double(hill.heights[j * width2 + i]) / Double(max(hill.peak, 1)) * 255
                let units = min(255, max(0, value.rounded(.down)))
                let index = ((depth2 - 1 - j) * width2 + i) * 4
                levels[index] = UInt8(units)
                levels[index + 1] = UInt8(min(255, max(0, ((value - units) * 255).rounded())))
                levels[index + 3] = 255
            }
        }
        guard let heightImage = image(levels, width: width2, height: depth2) else { return nil }
        let heights = SKTexture(cgImage: heightImage)
        heights.filteringMode = .linear
        // Where it shows on screen: its area's corners on the ground, and up to its peak above.
        let corners = [(0, 0), (columns, 0), (0, rows), (columns, rows)].map {
            WorldMap.project(CGPoint(x: CGFloat(low.col + $0.0) * tile, y: CGFloat(low.row + $0.1) * tile))
        }
        let left = corners.map(\.x).min()!, right = corners.map(\.x).max()!
        let bottom = corners.map(\.y).min()!, top = corners.map(\.y).max()! + hill.peak + 2
        let sprite = SKSpriteNode(texture: texture, size: CGSize(width: right - left, height: top - bottom))
        sprite.anchorPoint = .zero
        sprite.position = CGPoint(x: left, y: bottom)
        let shader = SKShader(source: Self.lifting)
        shader.uniforms = [
            SKUniform(name: "u_box", vectorFloat4: SIMD4(Float(left), Float(bottom), Float(right - left), Float(top - bottom))),
            SKUniform(name: "u_area", vectorFloat4: SIMD4(Float(low.col), Float(low.row), Float(columns), Float(rows))),
            SKUniform(name: "u_peak", float: Float(hill.peak)),
            SKUniform(name: "u_heights", texture: heights),
            SKUniform(name: "u_samples", vectorFloat4: SIMD4(Float(low.col), Float(low.row), Float(samples), 0)),
            SKUniform(name: "u_sampleSize", vectorFloat2: SIMD2(Float(width2), Float(depth2))),
        ]
        sprite.shader = shader
        return sprite
    }

    /// Each pixel of the sprite over the hill's place on screen: the ground point that rises to it,
    /// found by halving (the ground under a spot only ever rises going up the screen, as a hill is
    /// never steeper than the view), then the hill's picture there. `WorldMap.project` and
    /// `unproject` in reverse; `tileSize` is 44.
    private static let lifting = """
    void main() {
        vec2 spot = u_box.xy + v_tex_coord * u_box.zw;
        float low = spot.y - u_peak - 1.0;
        float high = spot.y;
        float across = spot.x / 0.70710678;
        for (int i = 0; i < 16; i++) {
            float middle = 0.5 * (low + high);
            float along = middle / 0.35355339;
            vec2 cell = vec2(along + across, along - across) * (0.5 / 44.0);
            vec2 at = ((cell - u_samples.xy) * u_samples.z + 0.5) / u_sampleSize;
            vec4 level = texture2D(u_heights, at);
            float lift = (level.r * 255.0 + level.g) / 255.0 * u_peak;
            if (middle + lift > spot.y) { high = middle; } else { low = middle; }
        }
        float along = 0.5 * (low + high) / 0.35355339;
        vec2 cell = vec2(along + across, along - across) * (0.5 / 44.0);
        vec2 uv = (cell - u_area.xy) / u_area.zw;
        if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
            gl_FragColor = vec4(0.0);
        } else {
            gl_FragColor = texture2D(u_texture, uv);
        }
    }
    """

    /// Lights the picture a pixel (a tile's pixel) at a time: how lit the slope is there, in steps
    /// of 6%, with a 4×4 ordered dither where one step gives way to the next, the way pixel art
    /// shades a hill in a few flat tones. A smooth gradient over pixel-art ground read as gloss.
    /// Shade leans toward the map's shadow colour (`tint`, its channels over its brightest).
    private static func shade(_ context: CGContext, light: [Float], samples: (columns: Int, rows: Int), perSample: Float,
                              tint: (Double, Double, Double)) {
        guard let data = context.data else { return }
        let width = context.width, height = context.height, rowBytes = context.bytesPerRow
        let bytes = data.bindMemory(to: UInt8.self, capacity: rowBytes * height)
        let dither: [Float] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map { ($0 + 0.5) / 16 - 0.5 }
        let step: Float = 0.06
        let lean = (Float(1 - tint.0), Float(1 - tint.1), Float(1 - tint.2))
        let sw = samples.columns, sh = samples.rows
        for y in 0..<height {
            // Memory rows run top down; samples bottom up.
            let fy = (Float(height - 1 - y) + 0.5) / perSample - 0.5
            let j = max(0, min(sh - 2, Int(fy.rounded(.down))))
            let ty = min(1, max(0, fy - Float(j)))
            for x in 0..<width {
                let fx = (Float(x) + 0.5) / perSample - 0.5
                let i = max(0, min(sw - 2, Int(fx.rounded(.down))))
                let tx = min(1, max(0, fx - Float(i)))
                let a = light[j * sw + i], b = light[j * sw + i + 1]
                let c = light[(j + 1) * sw + i], d = light[(j + 1) * sw + i + 1]
                let near = a + (b - a) * tx, far = c + (d - c) * tx
                let lit = near + (far - near) * ty
                let steps = ((lit - 1) / step + dither[(y % 4) * 4 + x % 4]).rounded()
                guard steps != 0 else { continue }
                let s = min(1 + step, 1 + steps * step)
                let index = y * rowBytes + x * 4
                if s < 1 {
                    let toward = (1 - s) * 0.4
                    bytes[index] = UInt8(min(255, Float(bytes[index]) * s * (1 - toward * lean.0)))
                    bytes[index + 1] = UInt8(min(255, Float(bytes[index + 1]) * s * (1 - toward * lean.1)))
                    bytes[index + 2] = UInt8(min(255, Float(bytes[index + 2]) * s * (1 - toward * lean.2)))
                } else {
                    // Premultiplied: no channel brighter than the pixel is opaque.
                    let alpha = Float(bytes[index + 3])
                    bytes[index] = UInt8(min(alpha, Float(bytes[index]) * s))
                    bytes[index + 1] = UInt8(min(alpha, Float(bytes[index + 1]) * s))
                    bytes[index + 2] = UInt8(min(alpha, Float(bytes[index + 2]) * s))
                }
            }
        }
    }

    /// Premultiplied RGBA bytes, top row first, as an image.
    private static func image(_ bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
