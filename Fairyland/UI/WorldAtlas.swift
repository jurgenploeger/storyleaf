import SwiftUI

/// The whole world at a glance, like Fairyland's world map: every place on the roads between
/// them, turned like the game's isometric view so north points up-left and east up-right, the way
/// you walk out of a map on screen. A compass in the corner says so. Places you haven't been to show as "???". A quest
/// closes a road one way only (the way back is always open, so you can't get stuck), so a closed road is dashed from the
/// end it's closed at, where the fence stands in the game, with a lock in its middle. Tap a place to read about it.
struct WorldAtlas: View {
    let session: GameSession
    @State private var selected: String?
    @State private var pulse = false

    enum Status: Equatable {
        case here, visited, undiscovered
        case locked(quest: String?)
    }

    private struct Road: Identifiable {
        let a: MapDef
        let b: MapDef
        /// The ends it's closed from (a quest barricades the exit there); it's open the other way.
        let closedFrom: [String]
        let known: Bool
        var id: String { a.id + "|" + b.id }
    }

    /// One step east moves a place a cell right and a cell up; one step north, a cell left and a cell up.
    private let cell = CGSize(width: 64, height: 46)
    private var maps: [MapDef] { Content.shared.maps.filter { $0.world?.count == 2 } }
    /// Screen column (east minus north) and row from the bottom (east plus north) of a place.
    private func spot(_ map: MapDef) -> (across: Int, up: Int) {
        let world = map.world ?? [0, 0]
        return (world[0] - world[1], world[0] + world[1])
    }
    private var minAcross: Int { maps.map { spot($0).across }.min() ?? 0 }
    private var maxAcross: Int { maps.map { spot($0).across }.max() ?? 0 }
    private var minUp: Int { maps.map { spot($0).up }.min() ?? 0 }
    private var maxUp: Int { maps.map { spot($0).up }.max() ?? 0 }

    /// Room round the atlas: a badge reaches past its spot and its name hangs below it, so the
    /// places along the edges need it to show whole.
    private let margin = EdgeInsets(top: 10, leading: 10, bottom: 34, trailing: 10)

    var body: some View {
        VStack(spacing: 8) {
            ScrollView([.vertical, .horizontal], showsIndicators: false) {
                atlas
                    .padding(margin)
            }
            // Opens on where you are: the scroll view lines up the same share of the atlas and of
            // itself, so your place shows in the middle when it's in the middle of the world, and
            // whole, nearer the edge, when it's near one.
            .defaultScrollAnchor(here)
            .frame(maxHeight: 400)
            .background(Color(red: 0.16, green: 0.42, blue: 0.62))
            .overlay(alignment: .topTrailing) { AtlasCompass().padding(6).allowsHitTesting(false) }

            if let selected, let map = Content.shared.map(selected) {
                caption(for: map)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    private var atlasSize: CGSize {
        CGSize(width: CGFloat(maxAcross - minAcross + 1) * cell.width, height: CGFloat(maxUp - minUp + 1) * cell.height)
    }

    /// Where you are in the scrolling atlas, margins and all, as shares of its size.
    private var here: UnitPoint {
        guard let map = maps.first(where: { $0.id == session.data.mapID }) else { return .center }
        let middle = center(of: map)
        return UnitPoint(x: (middle.x + margin.leading) / (atlasSize.width + margin.leading + margin.trailing),
                         y: (middle.y + margin.top) / (atlasSize.height + margin.top + margin.bottom))
    }

    private var atlas: some View {
        ZStack(alignment: .topLeading) {
            ForEach(roads) { road in
                let paint = road.known ? HUDStyle.plate : HUDStyle.plate.opacity(0.35)
                if road.closedFrom.isEmpty {
                    // In one stroke: two halves would overlap in the middle and show a brighter dot there.
                    Path { path in
                        path.move(to: center(of: road.a))
                        path.addLine(to: center(of: road.b))
                    }
                    .stroke(paint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                } else {
                    // In halves, dashed from an end it's closed at, with the lock in the middle.
                    ForEach([road.a, road.b]) { end in
                        Path { path in
                            path.move(to: center(of: end))
                            path.addLine(to: midpoint(road))
                        }
                        .stroke(paint, style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: road.closedFrom.contains(end.id) ? [5, 7] : []))
                    }
                    IconImage(.lock, size: 12)
                        .foregroundStyle(HUDStyle.ink)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(HUDStyle.gold))
                        .position(midpoint(road))
                }
            }
            ForEach(maps) { map in
                PlaceBadge(map: map, status: status(of: map), selected: selected == map.id, pulse: pulse, labelWidth: cell.width + 12)
                    // The tap goes on the badge itself: after .position it'd cover the whole atlas.
                    .onTapGesture { selected = map.id }
                    .position(center(of: map))
            }
        }
        .frame(width: atlasSize.width, height: atlasSize.height)
    }

    // MARK: Caption

    /// About the place you tapped. Nothing until you do: the gold badge already says where you are.
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
            guard !session.canTravel(exit), let other = Content.shared.map(exit.to), other.world?.count == 2 else { return nil }
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
        let roads = maps.filter { session.hasVisited($0.id) }.flatMap { from in from.exits.filter { $0.to == map.id } }
        if roads.isEmpty || roads.contains(where: { session.canTravel($0) }) { return .undiscovered }
        return .locked(quest: roads.lazy.compactMap(\.requires).first.flatMap { session.content.quest($0)?.title })
    }

    private var roads: [Road] {
        var seen = Set<String>()
        var result: [Road] = []
        for map in maps {
            for exit in map.exits {
                guard let other = Content.shared.map(exit.to), other.world?.count == 2 else { continue }
                let key = [map.id, other.id].sorted().joined(separator: "|")
                guard seen.insert(key).inserted else { continue }
                let back = other.exits.filter { $0.to == map.id }
                var closedFrom: [String] = []
                if !session.canTravel(exit) { closedFrom.append(map.id) }
                if back.contains(where: { !session.canTravel($0) }) { closedFrom.append(other.id) }
                let known = session.hasVisited(map.id) || session.hasVisited(other.id)
                result.append(Road(a: map, b: other, closedFrom: closedFrom, known: known))
            }
        }
        return result
    }

    // MARK: Layout

    private func center(of map: MapDef) -> CGPoint {
        let at = spot(map)
        return CGPoint(x: (CGFloat(at.across - minAcross) + 0.5) * cell.width,
                       y: (CGFloat(maxUp - at.up) + 0.5) * cell.height)
    }

    private func midpoint(_ road: Road) -> CGPoint {
        let a = center(of: road.a), b = center(of: road.b)
        return CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }
}

/// A little compass rose, turned like the atlas: N up-left, E up-right.
private struct AtlasCompass: View {
    var body: some View {
        let reach: CGFloat = 17
        // The same slant as a step between places on the atlas.
        let slope: CGFloat = 46.0 / 64.0
        let dy = reach * slope / (1 + slope * slope).squareRoot()
        let dx = reach / (1 + slope * slope).squareRoot()
        ZStack {
            Circle().fill(HUDStyle.ink.opacity(0.55)).frame(width: 54, height: 54)
            Path { path in
                path.move(to: CGPoint(x: 27 - dx, y: 27 - dy)); path.addLine(to: CGPoint(x: 27 + dx, y: 27 + dy))
                path.move(to: CGPoint(x: 27 + dx, y: 27 - dy)); path.addLine(to: CGPoint(x: 27 - dx, y: 27 + dy))
            }
            .stroke(HUDStyle.cream.opacity(0.7), lineWidth: 1.5)
            ForEach(["N", "E", "S", "W"], id: \.self) { label in
                let sx: CGFloat = label == "E" || label == "S" ? 1 : -1
                let sy: CGFloat = label == "S" || label == "W" ? 1 : -1
                Text(label == "N" ? L("N") : label == "E" ? L("E") : label == "S" ? L("S") : L("W"))
                    .font(HUDStyle.font(label == "N" ? 11 : 9))
                    .foregroundStyle(label == "N" ? HUDStyle.gold : HUDStyle.cream)
                    .position(x: 27 + sx * (dx + 5), y: 27 + sy * (dy + 5))
            }
        }
        .frame(width: 54, height: 54)
        .accessibilityHidden(true)
    }
}

/// One place on the world map: a coloured badge (themed by its ground) with its name, or a
/// mystery badge until you've been there.
private struct PlaceBadge: View {
    let map: MapDef
    let status: WorldAtlas.Status
    let selected: Bool
    let pulse: Bool
    /// How wide the name under the badge may run.
    let labelWidth: CGFloat

    var body: some View {
        ZStack {
            if status == .here {
                Circle().fill(HUDStyle.gold.opacity(0.35)).frame(width: pulse ? 50 : 38, height: pulse ? 50 : 38)
            }
            Circle()
                .fill(known ? tint : HUDStyle.ink.opacity(0.85))
                .frame(width: 34, height: 34)
                .overlay(Circle().strokeBorder(ring, lineWidth: status == .here || selected ? 3 : 2))
            switch status {
            case .locked:
                IconImage(.lock, size: 15).foregroundStyle(HUDStyle.cream.opacity(0.8))
            case .undiscovered:
                Text("?").font(HUDStyle.font(16)).foregroundStyle(HUDStyle.cream.opacity(0.8))
            case .here, .visited:
                if map.fence == true { IconImage(.star, size: 15).foregroundStyle(HUDStyle.ink) }
            }
        }
        .frame(width: 50, height: 50)
        // The name hangs below, outside the badge's frame, so the badge's middle is the circle's
        // and .position puts the circle right on the crossroads.
        .overlay(alignment: .top) {
            Text(known ? map.name : "???")
                .font(HUDStyle.font(9))
                .foregroundStyle(status == .here ? HUDStyle.gold : known ? HUDStyle.cream : HUDStyle.cream.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .shadow(color: HUDStyle.ink, radius: 0, x: 1, y: 1)
                .frame(width: labelWidth)
                .fixedSize(horizontal: false, vertical: true)
                .offset(y: 53)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(known ? map.name : L("Undiscovered place"))
        .accessibilityAddTraits(.isButton)
    }

    private var known: Bool { status == .here || status == .visited }

    private var ring: Color {
        if status == .here { return HUDStyle.gold }
        return selected ? HUDStyle.cream : HUDStyle.cream.opacity(known ? 0.8 : 0.4)
    }

    /// A colour for the kind of place, from its ground tile.
    private var tint: Color {
        let ground = map.theme.ground
        if map.fence == true { return Color(red: 0.98, green: 0.78, blue: 0.45) }
        if ground.contains("snow") { return Color(red: 0.9, green: 0.95, blue: 1) }
        if ground.contains("desert") || ground.contains("sand") { return Color(red: 0.95, green: 0.83, blue: 0.5) }
        if ground.contains("cave") || ground.contains("scree") { return Color(red: 0.62, green: 0.64, blue: 0.72) }
        if ground.contains("dark") { return Color(red: 0.55, green: 0.45, blue: 0.75) }
        if ground.contains("swamp") { return Color(red: 0.55, green: 0.62, blue: 0.35) }
        if ground.contains("forest") { return Color(red: 0.36, green: 0.68, blue: 0.36) }
        return Color(red: 0.52, green: 0.82, blue: 0.42)
    }
}
