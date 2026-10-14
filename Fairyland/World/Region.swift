import Foundation

/// A land's shape on the continent (content/world.json, painted by tools/world_layout.py): which
/// cells of its box are its own land, which round it are the sea it draws, where its middle is, and
/// where each of its roads crosses its border. Its box is its map (`MapDef.width` × `height`): the
/// lands' boxes overlap where their shapes fit into each other, as RuneScape's regions do, and each
/// lays out and draws only its own cells. The shape reaches `margin` cells round the box, for the sea.
nonisolated struct Region: Sendable {
    /// How far round the land's box its shape is given.
    let margin: Int
    let columns: Int
    let rows: Int
    /// For each cell of the box and the margin round it, row by row from the south: 0 neither, 1 the
    /// land's own, 2 the sea it draws (the sea nearest it).
    private let codes: [UInt8]
    /// The land's middle, in its cells: what everything set down by hand is placed out from.
    let middle: GridPoint
    /// Where each road crosses the land's border, by the map it leads to.
    let roads: [String: Road]

    /// Where a road crosses the land's border: the last cell on this side (the next one over, the
    /// way its exit goes, is the other land's, or a cave's mountain), and the turns it takes on its
    /// way there from the hub, as [x, y] out from the middle, through the middle of the land.
    nonisolated struct Road: Sendable {
        let at: GridPoint
        let via: [[Int]]
    }

    /// `runs`: world.json's rows of [code, length, code, length, ...], from the south.
    init(margin: Int, columns: Int, rows: Int, runs: [[Int]], middle: GridPoint, roads: [String: Road]) {
        self.margin = margin
        self.columns = columns
        self.rows = rows
        self.middle = middle
        self.roads = roads
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

    /// Whether a cell (in the land's cells) is its own land.
    func owns(_ cell: GridPoint) -> Bool { code(cell) == 1 }

    /// Whether a cell (in the land's cells, in its box or round it) is the sea it draws.
    func drawsSea(at cell: GridPoint) -> Bool { code(cell) == 2 }

    /// Every cell of the sea it draws, in its cells, row by row from the south.
    var sea: [GridPoint] {
        let width = columns + 2 * margin
        return codes.indices.filter { codes[$0] == 2 }.map { GridPoint(col: $0 % width - margin, row: $0 / width - margin) }
    }
}
