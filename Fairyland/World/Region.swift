import CoreGraphics

/// A land's shape on the continent (content/world.json, painted by tools/world_layout.py): which
/// cells of its box are its own land, which round it are the sea it draws, which run under the
/// rivers, where its middle is, and where each of its roads crosses its border. Its box is its map (`MapDef.width` × `height`): the
/// lands' boxes overlap where their shapes fit into each other, as RuneScape's regions do, and each
/// lays out and draws only its own cells. The shape reaches `margin` cells round the box, for the sea.
nonisolated struct Region: Sendable {
    /// How far round the land's box its shape is given.
    let margin: Int
    let columns: Int
    let rows: Int
    /// For each cell of the box and the margin round it, row by row from the south: 0 neither, 1 the
    /// land's own, 2 the sea it draws (the sea nearest it), 3 the land's own under a river, 4 a land
    /// next door's under a river.
    private let codes: [UInt8]
    /// The land's middle, in its cells: what everything set down by hand is placed out from.
    let middle: GridPoint
    /// Where each road crosses the land's border, by the map it leads to.
    let roads: [String: Road]
    /// The middles of the rivers that run through it or past it, from their springs to the sea, in
    /// its cells: which way each runs where a road crosses it (`WorldMap.layRivers`).
    let rivers: [[CGPoint]]

    /// Where a road crosses the land's border: the last cell on this side (the next one over, the
    /// way its exit goes, is the other land's), and the turns it takes on its way there from the
    /// hub, as [x, y] out from the middle, through the middle of the land. A road into a cave ends
    /// inland instead (tools/world_layout.py `cave_gates`): `at` is the cell in front of the cave's
    /// mouth, in a rocky hill (`WorldMap.raiseGate`), and `into` the way you walk into it, north or
    /// east so its face is turned toward you.
    nonisolated struct Road: Sendable {
        let at: GridPoint
        let via: [[Int]]
        var into: Edge? = nil
    }

    /// `runs`: world.json's rows of [code, length, code, length, ...], from the south.
    init(margin: Int, columns: Int, rows: Int, runs: [[Int]], middle: GridPoint, roads: [String: Road], rivers: [[CGPoint]] = []) {
        self.margin = margin
        self.columns = columns
        self.rows = rows
        self.middle = middle
        self.roads = roads
        self.rivers = rivers
        let width = columns + 2 * margin, height = rows + 2 * margin
        var codes = [UInt8](repeating: 0, count: width * height)
        for (row, line) in runs.prefix(height).enumerated() {
            var col = 0
            for pair in stride(from: 0, to: line.count - 1, by: 2) {
                let code = UInt8(clamping: line[pair]), length = max(0, line[pair + 1])
                if code != 0 {
                    for x in col..<min(width, col + length) { codes[row * width + x] = code }
                }
                col += length
            }
        }
        self.codes = codes
    }

    private func code(_ cell: GridPoint) -> UInt8 {
        let x = cell.col + margin, y = cell.row + margin, width = columns + 2 * margin
        guard x >= 0, y >= 0, x < width, y < rows + 2 * margin else { return 0 }
        return codes[y * width + x]
    }

    /// Whether a cell (in the land's cells) is its own land (a river's too).
    func owns(_ cell: GridPoint) -> Bool {
        let code = code(cell)
        return code == 1 || code == 3
    }

    /// Whether a cell (in the land's cells, in its box or round it) runs under a river, its own or a
    /// land's next door.
    func isRiver(_ cell: GridPoint) -> Bool {
        let code = code(cell)
        return code == 3 || code == 4
    }

    /// Whether a river runs through the land.
    var hasRiver: Bool { codes.contains(3) }

    /// Whether a cell (in the land's cells, in its box or round it) is the sea it draws.
    func drawsSea(at cell: GridPoint) -> Bool { code(cell) == 2 }

    /// Every cell of the sea it draws, in its cells, row by row from the south.
    var sea: [GridPoint] {
        let width = columns + 2 * margin
        return codes.indices.filter { codes[$0] == 2 }.map { GridPoint(col: $0 % width - margin, row: $0 / width - margin) }
    }
}
