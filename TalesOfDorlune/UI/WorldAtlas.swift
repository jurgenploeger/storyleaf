import SwiftUI

/// The whole world at a glance, RuneScape-style: the continent's lands as they really lie and look
/// (each land's minimap, `WorldOverview`), the sea all round, turned like the game's isometric view
/// so north points up-left and east up-right, the way you walk on screen. A compass in the corner
/// says so. Drag to look round, pinch (or the buttons) to zoom; it opens on where you are. Places you
/// haven't been to are faded and named "???"; a quest's shut gate shows its lock; caves show where
/// they open. A dark land shows only where you've been, as its minimap does. Zoomed in, a land you've
/// been to shows who's where with the minimap's badges (the healer, the shop, a quest's "!" and so
/// on). Tap a place to read about it. A quest closes a road one way only (the way back is always open, so you can't get stuck).
struct WorldAtlas: View {
    let session: GameSession
    @State private var selected: String?
    @State private var pulse = false
    /// Points a cell (0 until the map's first laid out), and where the turned map sits in the view.
    @State private var scale: CGFloat = 0
    @State private var pan: CGSize = .zero
    @State private var dragStart: CGSize?
    @State private var pinchStart: (scale: CGFloat, pan: CGSize)?
    @State private var picture: CGImage?
    private let overview = WorldOverview.shared

    enum Status: Equatable {
        case here, visited, undiscovered
        case locked(quest: String?)
    }

    /// A land on the continent and its box's south-west cell there.
    private struct Land {
        let def: MapDef
        let origin: GridPoint
    }

    private var lands: [Land] {
        let content = Content.shared
        return content.maps.compactMap { def in content.world[def.id].map { Land(def: def, origin: $0) } }
    }

    /// The continent's cells, with a border of sea: its south-west cell and how many it spans.
    private var bounds: (low: GridPoint, columns: Int, rows: Int) {
        let all = lands
        let sea = 24
        let low = GridPoint(col: (all.map(\.origin.col).min() ?? 0) - sea, row: (all.map(\.origin.row).min() ?? 0) - sea)
        let high = GridPoint(col: (all.map { $0.origin.col + $0.def.width }.max() ?? 0) + sea,
                             row: (all.map { $0.origin.row + $0.def.height }.max() ?? 0) + sea)
        return (low, high.col - low.col, high.row - low.row)
    }

    private static let seaColor = WorldMap.seaColor
    private static let minScale: CGFloat = 0.15
    private static let maxScale: CGFloat = 8

    var body: some View {
        VStack(spacing: 8) {
            // As much of the window as there is under the title.
            GeometryReader { proxy in
                map(in: proxy.size)
            }
            .frame(minHeight: 260, maxHeight: .infinity)
            .background(Color(red: Double(Self.seaColor.r) / 255, green: Double(Self.seaColor.g) / 255, blue: Double(Self.seaColor.b) / 255))
            .overlay(alignment: .topTrailing) { MapCompass().padding(10).allowsHitTesting(false) }

            if let selected, let map = Content.shared.map(selected) {
                caption(for: map)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
        }
        .onAppear {
            overview.prepare()
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
        }
        // Drawn again as each land's picture comes in.
        .task(id: overview.images.count) { picture = compose() }
    }

    // MARK: The map

    private func map(in size: CGSize) -> some View {
        let (_, columns, rows) = bounds
        return ZStack(alignment: .topLeading) {
            // The picture rides in an overlay, so its size never moves the view's.
            Color.clear
                .frame(width: size.width, height: size.height)
                .overlay(alignment: .topLeading) {
                    if let picture, scale > 0 {
                        Image(decorative: picture, scale: 1)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: CGFloat(columns), height: CGFloat(rows))
                            .transformEffect(CGAffineTransform(a: scale, b: -scale / 2, c: scale, d: scale / 2,
                                                               tx: pan.width, ty: scale * CGFloat(columns) / 2 + pan.height))
                    }
                }
            if scale > 0 {
                ForEach(marks) { mark in
                    view(of: mark)
                        .position(point(of: mark.cell))
                }
            }
            controls(in: size)
                .frame(width: size.width, height: size.height, alignment: .bottomTrailing)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .contentShape(Rectangle())
        .gesture(dragging(in: size).simultaneously(with: pinching(in: size)))
        .onTapGesture(coordinateSpace: .local) { location in tap(at: location) }
        .onAppear { if scale == 0 { open(in: size) } }
    }

    /// Opens on where you are, your land filling most of the view.
    private func open(in size: CGSize) {
        let here = lands.first { $0.def.id == session.data.mapID }
        let span = CGFloat((here?.def.width ?? 150) + (here?.def.height ?? 120))
        scale = clamped(size.width * 0.8 / span, in: size)
        centre(on: hereCell ?? lands.first.map { GridPoint(col: $0.origin.col + $0.def.width / 2, row: $0.origin.row + $0.def.height / 2) },
               in: size)
    }

    private func centre(on cell: GridPoint?, in size: CGSize) {
        guard let cell else { return }
        let at = point(of: cell, pan: .zero)
        pan = clampedPan(CGSize(width: size.width / 2 - at.x, height: size.height / 2 - at.y), in: size)
    }

    /// Where a cell of the continent shows in the view: its place in the picture (columns east, rows
    /// north to south), turned and squashed like the world.
    private func point(of cell: GridPoint, pan: CGSize? = nil) -> CGPoint {
        let (low, columns, rows) = bounds
        let u = CGFloat(cell.col - low.col) + 0.5, v = CGFloat(rows - (cell.row - low.row)) - 0.5
        let shift = pan ?? self.pan
        return CGPoint(x: scale * (u + v) + shift.width, y: scale * (v - u) / 2 + scale * CGFloat(columns) / 2 + shift.height)
    }

    /// The continent's cell under a point in the view.
    private func cell(at location: CGPoint) -> GridPoint {
        let (low, columns, rows) = bounds
        let x = (location.x - pan.width) / scale
        let y = 2 * (location.y - pan.height - scale * CGFloat(columns) / 2) / scale
        let v = (x + y) / 2, u = (x - y) / 2
        return GridPoint(col: low.col + Int(u.rounded(.down)), row: low.row + Int((CGFloat(rows) - v).rounded(.down)))
    }

    private func clamped(_ value: CGFloat, in size: CGSize) -> CGFloat {
        let (_, columns, rows) = bounds
        // At the least, the whole continent in view.
        let whole = min(size.width / CGFloat(columns + rows), size.height * 2 / CGFloat(columns + rows))
        return min(Self.maxScale, max(min(whole, Self.minScale), value))
    }

    /// Keeps the middle of the view over the continent.
    private func clampedPan(_ value: CGSize, in size: CGSize) -> CGSize {
        let (_, columns, rows) = bounds
        let wide = scale * CGFloat(columns + rows), tall = wide / 2
        return CGSize(width: min(size.width / 2, max(size.width / 2 - wide, value.width)),
                      height: min(size.height / 2, max(size.height / 2 - tall, value.height)))
    }

    private func dragging(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let start = dragStart ?? pan
                dragStart = start
                pan = clampedPan(CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height), in: size)
            }
            .onEnded { _ in dragStart = nil }
    }

    private func pinching(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStart ?? (scale: scale, pan: pan)
                pinchStart = start
                zoom(to: start.scale * value.magnification, around: value.startLocation, from: start, in: size)
            }
            .onEnded { _ in pinchStart = nil }
    }

    /// Zooms to `target`, keeping the spot at `anchor` where it is.
    private func zoom(to target: CGFloat, around anchor: CGPoint, from start: (scale: CGFloat, pan: CGSize), in size: CGSize) {
        let next = clamped(target, in: size)
        let ratio = next / start.scale
        scale = next
        pan = clampedPan(CGSize(width: anchor.x - (anchor.x - start.pan.width) * ratio,
                                height: anchor.y - (anchor.y - start.pan.height) * ratio), in: size)
    }

    private func controls(in size: CGSize) -> some View {
        VStack(spacing: 6) {
            mapButton(Text("+").font(HUDStyle.font(16)), label: L("Zoom in")) {
                zoom(to: scale * 1.6, around: CGPoint(x: size.width / 2, y: size.height / 2), from: (scale: scale, pan: pan), in: size)
            }
            mapButton(Text("−").font(HUDStyle.font(16)), label: L("Zoom out")) {
                zoom(to: scale / 1.6, around: CGPoint(x: size.width / 2, y: size.height / 2), from: (scale: scale, pan: pan), in: size)
            }
            mapButton(IconImage(.user, size: 14), label: L("Where you are")) { centre(on: hereCell, in: size) }
        }
        .padding(6)
    }

    private func mapButton(_ face: some View, label: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.25)) { action() }
        } label: {
            face
                .foregroundStyle(HUDStyle.ink)
                .frame(width: 30, height: 30)
                .background(Circle().fill(HUDStyle.plate))
                .overlay(Circle().strokeBorder(HUDStyle.ink.opacity(0.6), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func tap(at location: CGPoint) {
        guard scale > 0 else { return }
        // A cave's mark first, small as it is; else the land under the tap.
        if let cave = marks.first(where: { $0.kind == .cave && point(of: $0.cell).distance(to: location) < 18 }) {
            selected = cave.place
            return
        }
        selected = Continent.owner(atWorld: cell(at: location))?.id
    }

    // MARK: Marks

    /// What's marked over the map: each land's name, the caves where they open, a quest's shut
    /// gate, who's where in the lands you've been to (`badge`), and you.
    private struct Mark: Identifiable {
        enum Kind { case land, cave, lock, here, badge }
        let id: String
        let kind: Kind
        /// The place it's about (a land or a cave).
        let place: String
        let cell: GridPoint
        /// A badge's icon, as on the minimap.
        var badge: GameSession.MinimapMark.Kind? = nil
    }

    /// How far in the map must be zoomed (points a cell) for the badges to show: out where whole
    /// lands fit, they'd pile up on each other.
    private static let badgeScale: CGFloat = 0.6

    /// The badges of the lands you've been to (playtesting 2026-10-21: "On the world map, there
    /// should be the badges of what is where"), at their people's spots (`WorldOverview.spots`).
    /// Where two would overlap at this zoom, the one that matters more stays: a quest to hand in or
    /// news first, a boss, then the town's services.
    private var badges: [Mark] {
        guard scale >= Self.badgeScale else { return [] }
        let order: [GameSession.MinimapMark.Kind] = [.lost, .questReady, .questNew, .boss, .healer, .bank, .shop, .smith, .weaver,
                                                     .barber, .guild, .waystone, .quest, .chest]
        var found: [Mark] = []
        for land in lands where session.hasVisited(land.def.id) {
            guard let spots = overview.spots[land.def.id] else { continue }
            for npc in land.def.npcs ?? [] {
                guard let kind = session.minimapKind(for: npc), order.contains(kind), let spot = spots[npc.id] else { continue }
                found.append(Mark(id: "badge \(land.def.id) \(npc.id)", kind: .badge, place: land.def.id,
                                  cell: GridPoint(col: land.origin.col + spot.col, row: land.origin.row + spot.row), badge: kind))
            }
        }
        // What you lost when you fell, where it lies (`LostPile`), in whichever land.
        for pile in session.lostPiles {
            guard let land = lands.first(where: { $0.def.id == pile.mapID }), let position = pile.position, position.count == 2 else { continue }
            let grid = WorldMap.unproject(CGPoint(x: position[0], y: position[1]))
            found.append(Mark(id: "lost \(pile.id)", kind: .badge, place: pile.mapID,
                              cell: GridPoint(col: land.origin.col + Int((grid.x / WorldMap.tileSize).rounded(.down)),
                                              row: land.origin.row + Int((grid.y / WorldMap.tileSize).rounded(.down))),
                              badge: .lost))
        }
        found.sort { (order.firstIndex(of: $0.badge ?? .chest) ?? 0) < (order.firstIndex(of: $1.badge ?? .chest) ?? 0) }
        var kept: [(mark: Mark, at: CGPoint)] = []
        for mark in found {
            let at = point(of: mark.cell, pan: .zero)
            if kept.allSatisfy({ $0.at.distance(to: at) >= 12 }) { kept.append((mark, at)) }
        }
        return kept.map(\.mark)
    }

    private var marks: [Mark] {
        // The badges first, under the names, caves and you.
        var marks: [Mark] = badges
        let content = Content.shared
        for land in lands {
            let def = land.def
            let middle = content.regions[def.id]?.middle ?? GridPoint(col: def.width / 2, row: def.height / 2)
            marks.append(Mark(id: "land " + def.id, kind: .land, place: def.id,
                              cell: GridPoint(col: land.origin.col + middle.col, row: land.origin.row + middle.row)))
            for exit in def.exits {
                let crossing = Self.crossing(of: exit, in: land)
                if content.world[exit.to] == nil, content.map(exit.to) != nil {
                    marks.append(Mark(id: "cave \(def.id) \(exit.to)", kind: .cave, place: exit.to, cell: crossing))
                } else if !session.canTravel(exit), session.hasVisited(def.id) || session.hasVisited(exit.to) {
                    marks.append(Mark(id: "lock \(def.id) \(exit.to)", kind: .lock, place: exit.to, cell: crossing))
                }
            }
        }
        if let here = hereCell { marks.append(Mark(id: "here", kind: .here, place: session.data.mapID, cell: here)) }
        return marks
    }

    /// Where a road leaves a land through `exit`, on the continent: where it crosses the land's border
    /// (`Region.Road`), else (a land with no shape) where it leaves its edge.
    private static func crossing(of exit: MapDef.Exit, in land: Land) -> GridPoint {
        let def = land.def
        if let road = Content.shared.regions[def.id]?.roads[exit.to] {
            return GridPoint(col: land.origin.col + road.at.col, row: land.origin.row + road.at.row)
        }
        let length = exit.edge == .east || exit.edge == .west ? def.height : def.width
        let along = length / 2 + (exit.at ?? 0)
        let local: GridPoint = switch exit.edge {
        case .east: GridPoint(col: def.width - 1, row: along)
        case .west: GridPoint(col: 0, row: along)
        case .north: GridPoint(col: along, row: def.height - 1)
        case .south: GridPoint(col: along, row: 0)
        }
        return GridPoint(col: land.origin.col + local.col, row: land.origin.row + local.row)
    }

    /// Where you are on the continent: in a land, where you stand; in a cave, where it opens.
    private var hereCell: GridPoint? {
        let id = session.data.mapID
        if let origin = Content.shared.world[id] {
            guard let position = session.playerPosition else { return nil }
            let grid = WorldMap.unproject(position)
            return GridPoint(col: origin.col + Int((grid.x / WorldMap.tileSize).rounded(.down)),
                             row: origin.row + Int((grid.y / WorldMap.tileSize).rounded(.down)))
        }
        // On a cave's deeper level, where the cave over it opens: up its stairs (`NPCRole.stairs`).
        var cave = id
        for _ in 0..<8 {
            guard let up = Content.shared.map(cave)?.npcs?.first(where: { $0.role == .stairs && !Content.shared.leadsDown($0) })?.to
            else { break }
            cave = up
        }
        for land in lands {
            if let exit = land.def.exits.first(where: { $0.to == cave }) { return Self.crossing(of: exit, in: land) }
        }
        return nil
    }

    @ViewBuilder
    private func view(of mark: Mark) -> some View {
        switch mark.kind {
        case .here:
            ZStack {
                Circle().fill(HUDStyle.gold.opacity(0.35)).frame(width: pulse ? 26 : 16, height: pulse ? 26 : 16)
                Circle().fill(HUDStyle.gold).frame(width: 10, height: 10).overlay(Circle().stroke(HUDStyle.ink, lineWidth: 1.5))
            }
            .allowsHitTesting(false)
            .accessibilityLabel(L("Where you are"))
        case .badge:
            if let kind = mark.badge {
                MinimapIcon(kind: kind)
                    .allowsHitTesting(false)
            }
        case .lock:
            IconImage(.lock, size: 10)
                .foregroundStyle(HUDStyle.ink)
                .frame(width: 18, height: 18)
                .background(Circle().fill(HUDStyle.gold))
                .allowsHitTesting(false)
        case .cave:
            let known = session.hasVisited(mark.place)
            VStack(spacing: 1) {
                Circle()
                    .fill(HUDStyle.ink)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(selected == mark.place ? HUDStyle.gold : HUDStyle.cream.opacity(0.8), lineWidth: 1.5))
                if scale >= 1.2 || selected == mark.place {
                    label(known ? Content.shared.map(mark.place)?.name ?? "" : "???", size: 8, color: HUDStyle.cream.opacity(known ? 1 : 0.6))
                }
            }
            .allowsHitTesting(false)
        case .land:
            if let def = Content.shared.map(mark.place) {
                let state = status(of: def)
                let known = state == .here || state == .visited
                // Out where the whole continent shows, only where you are and what you tapped.
                if scale >= 0.45 || state == .here || selected == def.id {
                    HStack(spacing: 3) {
                        if known, def.fence == true { IconImage(.star, size: 9).foregroundStyle(HUDStyle.gold) }
                        label(known ? def.name : "???", size: 10,
                              color: selected == def.id || state == .here ? HUDStyle.gold : HUDStyle.cream.opacity(known ? 1 : 0.7))
                    }
                    .allowsHitTesting(false)
                    .accessibilityLabel(known ? def.name : L("Undiscovered place"))
                }
            }
        }
    }

    private func label(_ text: String, size: CGFloat, color: Color) -> some View {
        Text(text)
            .font(HUDStyle.font(size))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .shadow(color: HUDStyle.ink, radius: 0, x: 1, y: 1)
            .shadow(color: HUDStyle.ink.opacity(0.6), radius: 1.5)
    }

    // MARK: The picture

    /// The continent in one picture, a pixel a cell, north up: the sea, and each land's own map (a
    /// rough patch of its ground's colour until that's drawn), faded where you haven't been, fogged
    /// where a dark land's still unseen.
    private func compose() -> CGImage? {
        let (low, columns, rows) = bounds
        guard columns > 0, rows > 0,
              let context = CGContext(data: nil, width: columns, height: rows, bitsPerComponent: 8, bytesPerRow: columns * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .none
        let sea = Self.seaColor
        context.setFillColor(red: CGFloat(sea.r) / 255, green: CGFloat(sea.g) / 255, blue: CGFloat(sea.b) / 255, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: columns, height: rows))
        for land in lands {
            let def = land.def
            let rect = CGRect(x: land.origin.col - low.col, y: land.origin.row - low.row, width: def.width, height: def.height)
            guard var image = overview.images[def.id] else {
                // Its shape in a colour from its ground, till it's drawn.
                let tint = Self.tint(of: def)
                if let shape = WorldScene.silhouette(of: def, color: PixelColor(r: UInt8(tint.r * 255), g: UInt8(tint.g * 255), b: UInt8(tint.b * 255))) {
                    context.setAlpha(0.55)
                    context.draw(shape, in: rect)
                    context.setAlpha(1)
                }
                continue
            }
            if def.ambience?.darkness != nil,
               let fogged = WorldScene.fog(UIImage(cgImage: image), seen: session.explored(def.id), columns: def.width, rows: def.height).cgImage {
                image = fogged
            }
            if !session.hasVisited(def.id), def.id != session.data.mapID, let faded = Self.faded(image) { image = faded }
            context.draw(image, in: rect)
        }
        return context.makeImage()
    }

    /// A land's picture faded toward grey, its sea left as it is: a place you haven't been to yet.
    private static func faded(_ image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let sea = seaColor
        for index in stride(from: 0, to: width * height * 4, by: 4) {
            // Not the sea, nor where it's clear (a land next door's, in this one's box).
            if pixels[index + 3] == 0 || (pixels[index] == sea.r && pixels[index + 1] == sea.g && pixels[index + 2] == sea.b) { continue }
            for channel in 0..<3 {
                pixels[index + channel] = UInt8((Double(pixels[index + channel]) * 0.45 + 150 * 0.55).rounded())
            }
        }
        return context.makeImage()
    }

    /// A colour for a land not drawn yet, from its ground.
    static func tint(of map: MapDef) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let ground = map.theme.ground
        if map.fence == true { return (0.98, 0.78, 0.45) }
        if ground.contains("snow") { return (0.9, 0.95, 1) }
        if ground.contains("desert") || ground.contains("sand") { return (0.95, 0.83, 0.5) }
        if ground.contains("cave") || ground.contains("scree") { return (0.62, 0.64, 0.72) }
        if ground.contains("dark") { return (0.55, 0.45, 0.75) }
        if ground.contains("swamp") { return (0.55, 0.62, 0.35) }
        if ground.contains("forest") { return (0.36, 0.68, 0.36) }
        return (0.52, 0.82, 0.42)
    }

    // MARK: Caption

    /// About the place you tapped. Nothing until you do: the gold mark already says where you are.
    private func caption(for map: MapDef) -> some View {
        Text(captionText(for: map))
            .font(HUDStyle.font(11))
            .foregroundStyle(HUDStyle.cream)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private func captionText(for map: MapDef) -> String {
        switch status(of: map) {
        case .here, .visited:
            return "\(map.name)\(levels(map))" + closedRoads(from: map)
        case .undiscovered:
            return L("Not discovered yet. Follow the roads to find it.")
        case .locked(let quest):
            return L("Locked. Finish “{quest}” to open the road.", ["quest": quest ?? L("a quest")])
        }
    }

    /// The roads out of `map` a quest still closes, a line each (the way back in is open).
    private func closedRoads(from map: MapDef) -> String {
        map.exits.compactMap { exit -> String? in
            guard !session.canTravel(exit), let other = Content.shared.map(exit.to) else { return nil }
            let place = session.hasVisited(other.id) ? other.name : L("an undiscovered place")
            let quest = exit.requires.flatMap { session.content.quest($0)?.title } ?? L("a quest")
            return "\n" + L("The road to {place} opens after “{quest}”; it's open coming the other way.", ["place": place, "quest": quest])
        }
        .joined()
    }

    private func levels(_ map: MapDef) -> String {
        if map.fence == true { return " · " + L("town") }
        guard let range = map.encounters?.levels, range.count == 2 else { return "" }
        return " · " + L("monsters Lv {min}–{max}", ["min": range[0], "max": range[1]])
    }

    // MARK: State

    func status(of map: MapDef) -> Status {
        if map.id == session.data.mapID { return .here }
        if session.hasVisited(map.id) { return .visited }
        // Roads into it from places you've been.
        let roads = Content.shared.maps.filter { session.hasVisited($0.id) }.flatMap { from in from.exits.filter { $0.to == map.id } }
        if roads.isEmpty || roads.contains(where: { session.canTravel($0) }) { return .undiscovered }
        return .locked(quest: roads.lazy.compactMap(\.requires).first.flatMap { session.content.quest($0)?.title })
    }
}

/// The map's compass (playtesting 2026-10-25: the minimap's little orange one, gone from there, bigger
/// in the map's window): a round pin in the close buttons' orange (`OrangeCloseButton`), a needle
/// through it, white to the north and deep orange to the south, and the four points round its rim,
/// all turned as the game's view is: north up and to the left, east up and to the right. The world
/// doesn't turn (its art is drawn from one side only), so neither does the compass.
struct MapCompass: View {
    var size: CGFloat = 72

    /// Where a step north, east, south and west lands on the turned, squashed map, as degrees
    /// clockwise from straight up (a row north is half as far up as it's across to the left).
    private static func angle(col: CGFloat, row: CGFloat) -> Double {
        let across = col - row, up = (col + row) / 2
        return atan2(Double(across), Double(up)) * 180 / Double.pi
    }
    static let north = angle(col: 0, row: 1)

    var body: some View {
        let points: [(label: String, angle: Double, main: Bool)] = [
            (L("N"), Self.north, true), (L("E"), Self.angle(col: 1, row: 0), false),
            (L("S"), Self.angle(col: 0, row: -1), false), (L("W"), Self.angle(col: -1, row: 0), false),
        ]
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [HUDStyle.closeLight, HUDStyle.orange, HUDStyle.closeDeep], center: UnitPoint(x: 0.35, y: 0.3),
                                     startRadius: 1, endRadius: size / 2))
                .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: max(1.5, size / 28)))
            // The needle: white to the north, the pin's deep orange to the south.
            VStack(spacing: 0) {
                CompassTriangle().fill(.white).frame(width: size * 0.16, height: size * 0.24)
                CompassTriangle().fill(HUDStyle.closeDeep).frame(width: size * 0.16, height: size * 0.24).rotationEffect(.degrees(180))
            }
            .shadow(color: HUDStyle.closeDeep.opacity(0.6), radius: 0, x: 1, y: 1)
            .rotationEffect(.degrees(Self.north))
            Circle().fill(.white).frame(width: size * 0.07, height: size * 0.07)
            ForEach(points, id: \.label) { point in
                let radians = point.angle * Double.pi / 180
                Text(point.label)
                    .font(HUDStyle.font(size * (point.main ? 0.2 : 0.15)))
                    .foregroundStyle(point.main ? .white : HUDStyle.cream)
                    .shadow(color: HUDStyle.closeDeep, radius: 0, x: 1, y: 1)
                    .offset(x: CGFloat(sin(radians)) * size * 0.36, y: -CGFloat(cos(radians)) * size * 0.36)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
        .accessibilityHidden(true)
    }
}

/// A triangle pointing up, its base along the bottom.
private struct CompassTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
