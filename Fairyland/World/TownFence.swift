import SpriteKit

/// A town's fence as one continuous picket fence round its square: the picket art is slanted onto
/// each edge's diagonal so neighbouring pieces join up and turn at the corners, and a stone gate
/// arch stands over every road that runs through it. A city's is a wall of stone instead, round
/// towers at its corners, either side of each gate and along it between (`stone`).
enum TownFence {
    /// Pickets are drawn one picture per cell, this tall (points).
    private static let height: CGFloat = 21
    private static let gateHeight: CGFloat = 51
    /// A city wall's towers stand at most this many cells apart along a straight stretch.
    private static let towerEvery = 8

    /// `stone`: a city's wall (`BorderArt.wallPicture`) rather than a village's pickets.
    static func place(cells: [GridPoint], map: WorldMap, world: SKNode, art: ArtLibrary, stone: Bool = false) {
        let fence = Set(cells)
        let palette = map.def.theme.palette
        let source = stone ? BorderArt.wallPicture(palette: palette) : art.sprite("fence").texture.cgImage()
        let height = stone ? BorderArt.wallHeight : Self.height
        guard !fence.isEmpty, let source, let pickets = cropped(source) else { return }
        let tile = WorldMap.tileSize
        let c = CGFloat(0.5).squareRoot()
        // Half a cell along the grid's x axis on screen; along y it's (-dx, dy).
        let east = CGVector(dx: c * tile / 2, dy: c * tile / 4)
        let north = CGVector(dx: -east.dx, dy: east.dy)
        let pad: CGFloat = 2
        let size = CGSize(width: east.dx * 2 + pad * 2, height: east.dy * 2 + height + pad * 2)
        let middle = CGPoint(x: size.width / 2, y: east.dy + pad)

        func has(_ dc: Int, _ dr: Int, _ cell: GridPoint) -> Bool { fence.contains(GridPoint(col: cell.col + dc, row: cell.row + dr)) }
        var textures: [Int: SKTexture] = [:]
        for cell in cells {
            var mask = 0
            if has(1, 0, cell) { mask |= 1 }
            if has(0, 1, cell) { mask |= 2 }
            if has(-1, 0, cell) { mask |= 4 }
            if has(0, -1, cell) { mask |= 8 }
            if mask == 0 { mask = 5 }
            if textures[mask] == nil {
                textures[mask] = render(size: size) { context in
                    // Along x the picture runs from the west end to the east end; along y from the
                    // north end to the south end, so it reads left to right on screen. Each half of
                    // the cell shows its half of the picture, so straight runs repeat seamlessly.
                    // The far halves (north, east) first.
                    if mask & 2 != 0 { draw(pickets, in: context, from: middle + north, along: north * -2, part: 0, height: height) }
                    if mask & 1 != 0 { draw(pickets, in: context, from: middle + east * -1, along: east * 2, part: 1, height: height) }
                    if mask & 4 != 0 { draw(pickets, in: context, from: middle + east * -1, along: east * 2, part: 0, height: height) }
                    if mask & 8 != 0 { draw(pickets, in: context, from: middle + north, along: north * -2, part: 1, height: height) }
                }
            }
            guard let texture = textures[mask] else { continue }
            let node = SKSpriteNode(texture: texture, size: size)
            node.anchorPoint = CGPoint(x: 0.5, y: middle.y / size.height)
            node.position = map.center(of: cell)
            node.zPosition = -node.position.y
            world.addChild(node)
        }

        // A city wall's towers: at its corners and either side of each gate, and along each straight
        // stretch between, no two closer than half the stretch they're spread along.
        if stone, let tower = BorderArt.towerPicture(palette: palette) {
            let texture = SKTexture(cgImage: tower)
            texture.filteringMode = .nearest
            var spots: [GridPoint] = []
            for cell in cells.sorted(by: WorldMap.inOrder) {
                let east = has(1, 0, cell) || has(-1, 0, cell), north = has(0, 1, cell) || has(0, -1, cell)
                let ends = [(1, 0), (0, 1), (-1, 0), (0, -1)].filter { has($0.0, $0.1, cell) }.count < 2
                let along = east && !north ? cell.col : !east && north ? cell.row : 0
                guard (east && north) || ends || along % towerEvery == 0 else { continue }
                guard spots.allSatisfy({ max(abs($0.col - cell.col), abs($0.row - cell.row)) > 3 }) || east && north || ends else { continue }
                spots.append(cell)
            }
            for cell in spots {
                let node = SKSpriteNode(texture: texture, size: BorderArt.towerSize)
                node.anchorPoint = CGPoint(x: 0.5, y: 0.06)
                node.position = map.center(of: cell)
                node.zPosition = -node.position.y + 0.01
                world.addChild(node)
            }
        }

        // Gates: the two ends of each gap where a road runs through, joined by an arch.
        guard let arch = cropped(art.sprite("town_gate").texture.cgImage()) else { return }
        var done: Set<GridPoint> = []
        for cell in cells where !done.contains(cell) {
            let links = [(1, 0), (0, 1), (-1, 0), (0, -1)].filter { has($0.0, $0.1, cell) }
            guard links.count == 1 else { continue }
            // Look the other way along the fence for the end across the road.
            let step = (-links[0].0, -links[0].1)
            var other: GridPoint?
            for distance in 2...6 {
                let candidate = GridPoint(col: cell.col + step.0 * distance, row: cell.row + step.1 * distance)
                if fence.contains(candidate) { other = candidate; break }
            }
            guard let other else { continue }
            done.insert(cell)
            done.insert(other)
            // Draw from the west/north end to the east/south end.
            let (from, to) = step.0 + step.1 * -1 > 0 ? (cell, other) : (other, cell)
            world.addChild(gate(arch, from: map.center(of: from), to: map.center(of: to)))
        }
    }

    /// The stone arch over a road through a fence, from `a` to `b` on screen (the west or north
    /// end first), standing on the line between them. `picture`: the arch, cropped (`cropped`).
    static func gate(_ picture: CGImage, from a: CGPoint, to b: CGPoint) -> SKSpriteNode {
        let pad: CGFloat = 2
        let span = CGVector(dx: b.x - a.x, dy: b.y - a.y)
        let gateSize = CGSize(width: abs(span.dx) + pad * 2, height: abs(span.dy) + gateHeight + pad * 2)
        let start = CGPoint(x: span.dx >= 0 ? pad : gateSize.width - pad, y: span.dy >= 0 ? pad : gateSize.height - gateHeight - pad)
        let texture = render(size: gateSize) { context in
            draw(picture, in: context, from: start, along: span, part: nil, height: gateHeight)
        }
        let node = SKSpriteNode(texture: texture, size: gateSize)
        node.anchorPoint = CGPoint(x: start.x / gateSize.width, y: start.y / gateSize.height)
        node.position = a
        node.zPosition = -(a.y + b.y) / 2
        return node
    }

    /// One cell's stretch of a railing picture that has a post at each end (`posts`: how far across
    /// the cropped picture their centres sit, 0...1), slanted along the edge it stands on: west to
    /// east (`alongColumns`) or north to south, left to right on screen either way. Its posts land
    /// on the cell's edges, where the next cell's posts land too, so a run reads as one railing.
    /// The anchor is the middle of its foot, to go on the cell's centre.
    static func railing(_ image: CGImage, posts: (CGFloat, CGFloat), height: CGFloat,
                        alongColumns: Bool) -> (texture: SKTexture, size: CGSize, anchor: CGPoint)? {
        guard let picture = cropped(image), posts.1 > posts.0 else { return nil }
        let c = CGFloat(0.5).squareRoot(), tile = WorldMap.tileSize
        // One cell along the edge: east climbs to the right, south drops to the right.
        let cell = CGVector(dx: c * tile, dy: alongColumns ? c * tile / 2 : -c * tile / 2)
        let full = cell * (1 / (posts.1 - posts.0))
        let pad: CGFloat = 2
        let size = CGSize(width: full.dx + pad * 2, height: abs(full.dy) + height + pad * 2)
        let origin = CGPoint(x: pad, y: pad + max(0, -full.dy))
        let texture = render(size: size) { context in
            draw(picture, in: context, from: origin, along: full, part: nil, height: height)
        }
        let middle = origin + full * ((posts.0 + posts.1) / 2)
        return (texture, size, CGPoint(x: middle.x / size.width, y: middle.y / size.height))
    }

    /// `image` slanted along `along` from `origin` (its bottom edge follows the line, its sides
    /// stay upright). `part` 0 or 1 draws only the first or second half of it.
    private static func draw(_ image: CGImage, in context: CGContext, from origin: CGPoint, along: CGVector, part: Int?, height: CGFloat) {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        context.saveGState()
        context.concatenate(CGAffineTransform(a: along.dx / w, b: along.dy / w, c: 0, d: height / h, tx: origin.x, ty: origin.y))
        if let part { context.clip(to: CGRect(x: CGFloat(part) * w / 2, y: 0, width: w / 2, height: h)) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        context.restoreGState()
    }

    /// A texture `size` points big, drawn at two pixels per point.
    private static func render(size: CGSize, _ body: (CGContext) -> Void) -> SKTexture {
        let scale: CGFloat = 2
        guard let context = CGContext(data: nil, width: Int((size.width * scale).rounded(.up)), height: Int((size.height * scale).rounded(.up)),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return SKTexture() }
        context.interpolationQuality = .none
        context.scaleBy(x: scale, y: scale)
        body(context)
        guard let image = context.makeImage() else { return SKTexture() }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .nearest
        return texture
    }

    /// The image without its transparent margins.
    static func cropped(_ image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data
        else { return image }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 8 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return image }
        // The bitmap's rows run top to bottom, like the image's.
        return image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
    }
}
