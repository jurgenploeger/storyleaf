import SwiftUI

/// The whole world at a glance, RuneScape-style: the continent's lands as they really lie and look
/// (each land's minimap, `WorldOverview`), the sea all round, north up like a paper map (playtesting
/// 2026-10-26: turned like the game's isometric view, north up-left, its compass's points weren't a
/// quarter turn apart). Drag to look round, pinch (or the buttons) to zoom, twist with two fingers to
/// turn it: the compass turns with it, and a tap on the compass turns north back up. The names and
/// marks stay upright however it's turned. It opens on where you are. Places you haven't been to
/// are faded and named "???"; a quest's shut gate shows its lock; caves show where they open. A
/// dark land shows only where you've been, as its minimap does. Zoomed in, a land you've been to
/// shows who's where with the minimap's badges (the healer, the shop, a quest's "!" and so on). Tap
/// a place to pick out its name. A quest closes a road one way only (the way back is always open,
/// so you can't get stuck).
struct WorldAtlas: View {
    let session: GameSession
    /// Over the map's top left and bottom left corners, on the window's own blue melting into the
    /// map over a blur that deepens toward the edge (`edgeBand`): the window's title, the time and
    /// where you are (`MapOverlay`).
    private let topLeading: AnyView
    private let bottomLeading: AnyView
    @State private var selected: String?
    @State private var pulse = false
    /// Which badges show (playtesting 2026-10-30: "Add filters to the map so you can quickly see
    /// stuff"), kept for the next time the map opens.
    @AppStorage("mapFilter") private var filter: MapFilter = .all
    /// How the map lies in the view: its zoom, its turn and the spot in the middle.
    @State private var framing = Framing()
    /// The view's size, for the buttons over it.
    @State private var viewSize: CGSize = .zero
    /// A finger dragging the map: how it lay when the drag began, and the drag's translation then.
    @State private var drag: (framing: Framing, translation: CGSize)?
    /// Two fingers pinching and twisting it; `twoFingersDown` while they're on it, back to false
    /// however their touch ends.
    @State private var fingers: TwoFingers?
    @GestureState private var twoFingersDown = false
    /// The map gliding to where a button or the compass sends it.
    @State private var gliding: Task<Void, Never>?
    @State private var picture: CGImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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

    /// How the map lies in the view. The picture is a pixel a cell, north up (`compose`); a spot on
    /// it is counted in cells, east from its west edge and south from its north edge. Turned, it
    /// turns about the middle of the view, so a spot's place on screen is the middle, plus its way
    /// from `focus`, zoomed and turned.
    private nonisolated struct Framing: Equatable {
        /// Points a cell (0 until the map's first laid out).
        var scale: CGFloat = 0
        /// How far it's turned clockwise, in radians: on screen, north points that way from straight up.
        var rotation: CGFloat = 0
        /// The spot of the picture in the middle of the view.
        var focus: CGPoint = .zero

        /// Where a spot of the picture shows, from the middle of the view.
        func offset(of spot: CGPoint) -> CGPoint {
            let x = (spot.x - focus.x) * scale, y = (spot.y - focus.y) * scale
            let cosine = cos(rotation), sine = sin(rotation)
            return CGPoint(x: x * cosine - y * sine, y: x * sine + y * cosine)
        }

        /// The spot of the picture that shows `offset` from the middle of the view.
        func spot(at offset: CGPoint) -> CGPoint {
            guard scale > 0 else { return focus }
            let cosine = cos(rotation), sine = sin(rotation)
            return CGPoint(x: focus.x + (offset.x * cosine + offset.y * sine) / scale,
                           y: focus.y + (offset.y * cosine - offset.x * sine) / scale)
        }

        /// `fraction` of the way from `start` to `end`: the zoom by even ratios, the turn and the
        /// middle along a line.
        static func between(_ start: Framing, _ end: Framing, _ fraction: CGFloat) -> Framing {
            func mix(_ from: CGFloat, _ to: CGFloat) -> CGFloat { from + (to - from) * fraction }
            let scale = start.scale > 0 && end.scale > 0 ? start.scale * pow(end.scale / start.scale, fraction) : mix(start.scale, end.scale)
            return Framing(scale: scale, rotation: mix(start.rotation, end.rotation),
                           focus: CGPoint(x: mix(start.focus.x, end.focus.x), y: mix(start.focus.y, end.focus.y)))
        }
    }

    /// Two fingers on the map: how it lay when they came down, the spot between them then (from the
    /// middle of the view), and how far they've pinched and twisted since.
    private struct TwoFingers {
        let start: Framing
        let anchor: CGPoint
        var magnification: CGFloat = 1
        var turn: CGFloat = 0
        /// The twist they'd made when the map began turning with them (`turnThreshold`), taken off
        /// so it doesn't jump: nil till then.
        var held: CGFloat?
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

    init(session: GameSession, @ViewBuilder topLeading: () -> some View, @ViewBuilder bottomLeading: () -> some View) {
        self.session = session
        self.topLeading = AnyView(topLeading())
        self.bottomLeading = AnyView(bottomLeading())
    }

    private static let seaColor = WorldMap.seaColor
    private static var sea: Color {
        Color(red: Double(seaColor.r) / 255, green: Double(seaColor.g) / 255, blue: Double(seaColor.b) / 255)
    }
    private static let minScale: CGFloat = 0.15
    private static let maxScale: CGFloat = 8
    /// How far two fingers must twist before the map turns with them, so a pinch doesn't turn it
    /// (radians: about 7 degrees).
    private static let turnThreshold: CGFloat = 0.12
    /// A turn left this near north settles on it (radians: about 6 degrees).
    private static let northSnap: CGFloat = 0.1
    /// The blur under the map's top and bottom edges (`edgeBand`): copies of the map, each blurred
    /// more and reaching less far in from the edge (a fraction of the band), so it's blurred most
    /// at the edge and not at all where the band ends.
    private static let edgeBlurs: [(radius: CGFloat, reach: CGFloat)] = [(2.5, 1), (6, 0.6), (12, 0.3)]

    var body: some View {
        // Placed once, for the map and the blurred copies of it along its edges.
        let shown = framing.scale > 0 ? marks : []
        GeometryReader { proxy in
            map(in: proxy.size, marks: shown)
        }
        .frame(minHeight: 260, maxHeight: .infinity)
        .background(Self.sea)
        // Touches go through to the map under them.
        .overlay(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                topLeading
                    .allowsHitTesting(false)
                // The filters under the title, the one thing up here that takes a touch.
                filterChips
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 30)
            .background { edgeBand(.top, marks: shown).allowsHitTesting(false) }
        }
        .overlay(alignment: .bottom) {
            bottomLeading
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 18)
                // Clear of the zoom buttons on the right.
                .padding(.trailing, 62)
                .padding(.top, 30)
                // Level with the Where you are button beside it, as far in from the corner.
                .padding(.bottom, 22)
                .background { edgeBand(.bottom, marks: shown) }
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) { compass.padding(10) }
        // Over everything else: the edges, their blur and the land's name.
        .overlay(alignment: .bottomTrailing) { controls }
        .onAppear {
            overview.prepare()
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
        }
        .onDisappear { gliding?.cancel() }
        // Drawn again as each land's picture comes in.
        .task(id: overview.images.count) { picture = compose() }
    }

    // MARK: The map

    private func map(in size: CGSize, marks: [Mark]) -> some View {
        drawing(in: size, marks: marks)
            .clipped()
            .contentShape(Rectangle())
            .gesture(dragging(in: size).simultaneously(with: pinchingAndTwisting(in: size)))
            .onTapGesture(coordinateSpace: .local) { location in tap(at: location, in: size) }
            .onAppear {
                viewSize = size
                if framing.scale == 0 { open(in: size) }
            }
            .onChange(of: size) {
                viewSize = size
                if framing.scale == 0 { open(in: size) }
            }
            // Two fingers lifted, or their touch cancelled (by a call coming in, say).
            .onChange(of: twoFingersDown) {
                if !twoFingersDown, fingers != nil { lifted() }
            }
    }

    /// The map as drawn, without its touches: the picture, zoomed and turned, and the marks over
    /// it, each upright at its place however the map's turned.
    private func drawing(in size: CGSize, marks: [Mark]) -> some View {
        let (_, columns, rows) = bounds
        let origin = framing.offset(of: .zero)
        let cosine = cos(framing.rotation) * framing.scale, sine = sin(framing.rotation) * framing.scale
        let turned = CGAffineTransform(a: cosine, b: sine, c: -sine, d: cosine,
                                       tx: size.width / 2 + origin.x, ty: size.height / 2 + origin.y)
        return ZStack(alignment: .topLeading) {
            // The picture rides in an overlay, so its size never moves the view's.
            Color.clear
                .frame(width: size.width, height: size.height)
                .overlay(alignment: .topLeading) {
                    if let picture, framing.scale > 0 {
                        Image(decorative: picture, scale: 1)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: CGFloat(columns), height: CGFloat(rows))
                            .transformEffect(turned)
                    }
                }
            ForEach(marks) { mark in
                view(of: mark)
                    .position(point(of: mark.spot, in: size))
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// Along the map's top or bottom edge, under what's written there: the map blurred more the
    /// nearer the edge (`edgeBlurs`, as the story's pictures blur toward where they melt into the
    /// window, `EdgeBlur`), and over it the window's own glass melting to clear: the very gradient the
    /// window is filled with (`HUDStyle.glass`), as it lies behind that edge, so the band is the
    /// window's blue wherever it is (playtesting 2026-10-30: one blue at both edges, a top's
    /// `glassTop`, wasn't the window's at its foot), with no dark tint to muddy the map's colours.
    private func edgeBand(_ edge: SwiftUI.Edge, marks: [Mark]) -> some View {
        let top = edge == .top
        let size = viewSize
        return GeometryReader { band in
            ZStack {
                if framing.scale > 0, size.width > 0, size.height > 0 {
                    // Only the marks under the band.
                    let near = marks.filter { mark in
                        let y = point(of: mark.spot, in: size).y
                        return top ? y < band.size.height + 30 : y > size.height - band.size.height - 30
                    }
                    ForEach(Self.edgeBlurs.indices, id: \.self) { index in
                        drawing(in: size, marks: near)
                            .background(Self.sea)
                            .frame(width: band.size.width, height: band.size.height, alignment: top ? .top : .bottom)
                            .clipped()
                            .blur(radius: Self.edgeBlurs[index].radius, opaque: true)
                            .mask {
                                Self.ramp(edge, [.init(color: .black, location: 0),
                                                 .init(color: .black.opacity(0), location: Self.edgeBlurs[index].reach)])
                            }
                            // VoiceOver reads the map's marks once, from the map itself.
                            .accessibilityHidden(true)
                    }
                }
                // The window's glass as tall as the map, its own end of it showing in the band.
                Rectangle()
                    .fill(HUDStyle.glass)
                    .frame(width: band.size.width, height: max(band.size.height, size.height))
                    .frame(width: band.size.width, height: band.size.height, alignment: top ? .top : .bottom)
                    .clipped()
                    .mask {
                        Self.ramp(edge, [.init(color: .black, location: 0), .init(color: .black.opacity(0.75), location: 0.3),
                                         .init(color: .black.opacity(0.35), location: 0.65), .init(color: .black.opacity(0), location: 1)])
                    }
            }
        }
    }

    /// A gradient running in from `edge` (`stops` counted from there).
    private static func ramp(_ edge: SwiftUI.Edge, _ stops: [Gradient.Stop]) -> LinearGradient {
        LinearGradient(stops: stops, startPoint: edge == .top ? .top : .bottom, endPoint: edge == .top ? .bottom : .top)
    }

    /// Opens on where you are, north up, your land filling most of the view.
    private func open(in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let (_, columns, rows) = bounds
        let here = lands.first { $0.def.id == session.data.mapID }
        var opening = Framing()
        opening.scale = clamped(min(size.width * 0.8 / CGFloat(here?.def.width ?? 150), size.height * 0.7 / CGFloat(here?.def.height ?? 120)),
                                in: size)
        opening.rotation = CGFloat((DebugLaunch.mapTurn ?? 0) * Double.pi / 180)
        if let cell = hereCell ?? lands.first.map({ GridPoint(col: $0.origin.col + $0.def.width / 2, row: $0.origin.row + $0.def.height / 2) }) {
            opening.focus = spot(of: cell)
        } else {
            opening.focus = CGPoint(x: CGFloat(columns) / 2, y: CGFloat(rows) / 2)
        }
        framing = clampedFocus(opening)
    }

    /// A cell's middle on the picture: cells east from its west edge, south from its north edge.
    private func spot(of cell: GridPoint) -> CGPoint {
        let (low, _, rows) = bounds
        return Self.spot(of: cell, low: low, rows: rows)
    }

    private static func spot(of cell: GridPoint, low: GridPoint, rows: Int) -> CGPoint {
        CGPoint(x: CGFloat(cell.col - low.col) + 0.5, y: CGFloat(rows - (cell.row - low.row)) - 0.5)
    }

    /// Where a spot of the picture shows in a view of `size`.
    private func point(of spot: CGPoint, in size: CGSize) -> CGPoint {
        let at = framing.offset(of: spot)
        return CGPoint(x: size.width / 2 + at.x, y: size.height / 2 + at.y)
    }

    /// The continent's cell under a point in a view of `size`, however the map's turned.
    private func cell(at location: CGPoint, in size: CGSize) -> GridPoint {
        let (low, _, rows) = bounds
        let spot = framing.spot(at: CGPoint(x: location.x - size.width / 2, y: location.y - size.height / 2))
        return GridPoint(col: low.col + Int(spot.x.rounded(.down)), row: low.row + Int((CGFloat(rows) - spot.y).rounded(.down)))
    }

    private func clamped(_ value: CGFloat, in size: CGSize) -> CGFloat {
        let (_, columns, rows) = bounds
        // At the least, the whole continent in view.
        let whole = min(size.width / CGFloat(max(1, columns)), size.height / CGFloat(max(1, rows)))
        return min(Self.maxScale, max(min(whole, Self.minScale), value))
    }

    /// Keeps the middle of the view over the continent.
    private func clampedFocus(_ value: Framing) -> Framing {
        let (_, columns, rows) = bounds
        var kept = value
        kept.focus = CGPoint(x: min(CGFloat(columns), max(0, value.focus.x)), y: min(CGFloat(rows), max(0, value.focus.y)))
        return kept
    }

    /// The same turn, between half a turn back and half a turn on.
    private static func normalized(_ angle: CGFloat) -> CGFloat {
        let whole = 2 * CGFloat.pi
        var turn = angle.truncatingRemainder(dividingBy: whole)
        if turn > .pi {
            turn -= whole
        } else if turn <= -.pi {
            turn += whole
        }
        return turn
    }

    private func dragging(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                // While two fingers are down they move it; one left on carries on from there.
                guard fingers == nil else {
                    drag = nil
                    return
                }
                gliding?.cancel()
                let start = drag ?? (framing: framing, translation: value.translation)
                drag = start
                // The spot under the finger stays under it.
                var next = start.framing
                next.focus = start.framing.spot(at: CGPoint(x: start.translation.width - value.translation.width,
                                                            y: start.translation.height - value.translation.height))
                framing = clampedFocus(next)
            }
            .onEnded { _ in drag = nil }
    }

    /// Two fingers zoom it and, once they've twisted past `turnThreshold`, turn it, about the spot
    /// between them.
    private func pinchingAndTwisting(in size: CGSize) -> some Gesture {
        MagnifyGesture().simultaneously(with: RotateGesture())
            .updating($twoFingersDown) { _, down, _ in down = true }
            .onChanged { value in
                gliding?.cancel()
                let anchor = value.first.map { CGPoint(x: $0.startLocation.x - size.width / 2, y: $0.startLocation.y - size.height / 2) }
                var touch = fingers ?? TwoFingers(start: framing, anchor: anchor ?? .zero)
                if let pinch = value.first { touch.magnification = pinch.magnification }
                if let twist = value.second {
                    let turned = CGFloat(twist.rotation.radians)
                    if touch.held == nil, abs(turned) > Self.turnThreshold {
                        touch.held = turned > 0 ? Self.turnThreshold : -Self.turnThreshold
                    }
                    if let held = touch.held { touch.turn = turned - held }
                }
                fingers = touch
                framing = framed(by: touch, in: size)
            }
            .onEnded { _ in lifted() }
    }

    /// The two fingers off the map: one finger can drag it again, and its turn settles.
    private func lifted() {
        fingers = nil
        settleTurn()
    }

    /// How the map lies under two fingers: zoomed and turned about the spot that was between them,
    /// which stays there.
    private func framed(by touch: TwoFingers, in size: CGSize) -> Framing {
        let start = touch.start
        var next = start
        next.scale = clamped(start.scale * touch.magnification, in: size)
        next.rotation = start.rotation + touch.turn
        next.focus = start.spot(at: touch.anchor)
        next.focus = next.spot(at: CGPoint(x: -touch.anchor.x, y: -touch.anchor.y))
        return clampedFocus(next)
    }

    /// Once the fingers lift: the turn kept within half a turn either way, and settled on north
    /// when it's left near it.
    private func settleTurn() {
        var settled = framing
        settled.rotation = Self.normalized(framing.rotation)
        framing = settled
        guard settled.rotation != 0, abs(settled.rotation) < Self.northSnap else { return }
        var north = settled
        north.rotation = 0
        glide(to: north, from: settled)
    }

    /// The compass's tap: north back up, turning the short way round about the middle of the view.
    private func northUp() {
        var turned = framing
        turned.rotation = Self.normalized(framing.rotation)
        var north = turned
        north.rotation = 0
        glide(to: north, from: turned, duration: 0.4)
    }

    /// Glides the map from `origin` (where it is) to `target`, easing in and out; straight there
    /// with Reduce Motion. Stepped a frame at a time, so the picture and the marks over it move
    /// together, the marks round the middle as the map turns.
    private func glide(to target: Framing, from origin: Framing? = nil, duration: Double = 0.3) {
        gliding?.cancel()
        let start = origin ?? framing
        guard !reduceMotion, start != target else {
            framing = target
            return
        }
        gliding = Task {
            let began = Date()
            while !Task.isCancelled {
                let time = min(1, Date().timeIntervalSince(began) / duration)
                let eased = time < 0.5 ? 2 * time * time : 1 - pow(2 - 2 * time, 2) / 2
                framing = Framing.between(start, target, CGFloat(eased))
                if time >= 1 { break }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    /// The compass, turned with the map; a tap turns north back up.
    private var compass: some View {
        Button {
            northUp()
        } label: {
            MapCompass(heading: .radians(Double(framing.rotation)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("Turn the map north up"))
    }

    private var controls: some View {
        VStack(spacing: 6) {
            mapButton(Text("+").font(HUDStyle.font(16)), label: L("Zoom in")) { zoom(by: 1.6) }
            mapButton(Text("−").font(HUDStyle.font(16)), label: L("Zoom out")) { zoom(by: 1 / 1.6) }
            mapButton(IconImage(.user, size: 14), label: L("Where you are")) { centreOnHere() }
        }
        // Well in from the window's rounded corner (playtesting 2026-10-30: 6 points left them
        // squeezed into it).
        .padding(16)
    }

    /// Zooms about the middle of the view.
    private func zoom(by factor: CGFloat) {
        guard framing.scale > 0 else { return }
        var next = framing
        next.scale = clamped(framing.scale * factor, in: viewSize)
        glide(to: next)
    }

    /// Where you are in the middle of the view, the map turned as it is.
    private func centreOnHere() {
        guard framing.scale > 0, let here = hereCell else { return }
        var next = framing
        next.focus = spot(of: here)
        glide(to: clampedFocus(next))
    }

    private func mapButton(_ face: some View, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            face
                .foregroundStyle(HUDStyle.ink)
                .frame(width: 30, height: 30)
                .background(Circle().fill(HUDStyle.plate))
                .overlay(Circle().strokeBorder(HUDStyle.ink.opacity(0.6), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func tap(at location: CGPoint, in size: CGSize) {
        guard framing.scale > 0 else { return }
        // A group of badges zooms in on it, its badges parting as they come apart.
        if let group = marks.first(where: { $0.count > 1 && point(of: $0.spot, in: size).distance(to: location) < Self.badgeSize }) {
            var next = framing
            next.scale = clamped(framing.scale * 2.5, in: viewSize)
            next.focus = group.spot
            glide(to: clampedFocus(next))
            return
        }
        // A cave's mark first, small as it is; else the land under the tap.
        if let cave = marks.first(where: { $0.kind == .cave && point(of: $0.spot, in: size).distance(to: location) < 18 }) {
            selected = cave.place
            return
        }
        selected = Continent.owner(atWorld: cell(at: location, in: size))?.id
    }

    // MARK: Marks

    /// What's marked over the map: each land's name, the caves where they open, a quest's shut
    /// gate, who's where in the lands you've been to (`badge`), and you.
    private struct Mark: Identifiable {
        enum Kind { case land, cave, lock, here, badge }
        var id: String
        let kind: Kind
        /// The place it's about (a land or a cave).
        let place: String
        let cell: GridPoint
        /// A badge's icon, as on the minimap.
        var badge: GameSession.MinimapMark.Kind? = nil
        /// How many badges it stands for: more than one is a group, shown as its number.
        var count = 1
        /// Its cell's middle on the picture (`spot(of:)`), filled in by `spotted`.
        var spot: CGPoint = .zero
    }

    /// The marks with their spots on the picture, the continent's bounds worked out once for them all.
    private func spotted(_ marks: [Mark]) -> [Mark] {
        let (low, _, rows) = bounds
        return marks.map { mark in
            var placed = mark
            placed.spot = Self.spot(of: mark.cell, low: low, rows: rows)
            return placed
        }
    }

    /// A badge across, in points, and how near (on screen) two must be to group: bigger than the
    /// minimap's (playtesting 2026-10-26: "The badges on the map should be bigger").
    private static let badgeSize: CGFloat = 22
    private static let groupReach: CGFloat = 26

    /// The badges of the lands you've been to (playtesting 2026-10-21: "On the world map, there
    /// should be the badges of what is where"), at their people's spots (`WorldOverview.spots`).
    /// Badges that would overlap at this zoom group into one showing how many (playtesting
    /// 2026-10-26: "If you're zoomed out, they should group together in a badge that shows a
    /// number"); a group of one shows its badge, the one that matters most leading the group (a
    /// quest to hand in or news first, then the town's services). Tapping a group zooms in.
    private var badges: [Mark] {
        guard framing.scale > 0 else { return [] }
        let filter = self.filter
        let order: [GameSession.MinimapMark.Kind] = [.lost, .questReady, .questNew, .healer, .bank, .shop, .smith, .weaver,
                                                     .barber, .guild, .waystone, .quest, .chest]
        var found: [Mark] = []
        for land in lands where session.hasVisited(land.def.id) {
            guard let spots = overview.spots[land.def.id] else { continue }
            for npc in land.def.npcs ?? [] {
                guard let kind = session.minimapKind(for: npc), order.contains(kind), filter.shows(kind),
                      let spot = spots[npc.id] else { continue }
                found.append(Mark(id: "badge \(land.def.id) \(npc.id)", kind: .badge, place: land.def.id,
                                  cell: GridPoint(col: land.origin.col + spot.col, row: land.origin.row + spot.row), badge: kind))
            }
        }
        // What you lost when you fell, where it lies (`LostPile`), in whichever land.
        for pile in session.lostPiles where filter.shows(.lost) {
            guard let land = lands.first(where: { $0.def.id == pile.mapID }), let position = pile.position, position.count == 2 else { continue }
            let grid = WorldMap.unproject(CGPoint(x: position[0], y: position[1]))
            found.append(Mark(id: "lost \(pile.id)", kind: .badge, place: pile.mapID,
                              cell: GridPoint(col: land.origin.col + Int((grid.x / WorldMap.tileSize).rounded(.down)),
                                              row: land.origin.row + Int((grid.y / WorldMap.tileSize).rounded(.down))),
                              badge: .lost))
        }
        found.sort { (order.firstIndex(of: $0.badge ?? .chest) ?? 0) < (order.firstIndex(of: $1.badge ?? .chest) ?? 0) }
        // Grouped by how far apart they are on screen (as on the picture, however the map's turned):
        // each joins the first group whose leader is within reach, else leads a group of its own.
        var groups: [[Mark]] = []
        for mark in spotted(found) {
            if let index = groups.firstIndex(where: { $0[0].spot.distance(to: mark.spot) * framing.scale < Self.groupReach }) {
                groups[index].append(mark)
            } else {
                groups.append([mark])
            }
        }
        return groups.map { group -> Mark in
            guard group.count > 1 else { return group[0] }
            var leader = group[0]
            leader.id = "group " + leader.id
            leader.count = group.count
            // Where its badges are, on average.
            let sum = group.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.spot.x, y: $0.y + $1.spot.y) }
            leader.spot = CGPoint(x: sum.x / CGFloat(group.count), y: sum.y / CGFloat(group.count))
            return leader
        }
    }

    /// The filters, a chip each, one on at a time: as the Bag's kinds are.
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(MapFilter.allCases, id: \.self) { kind in
                    FilterChip(title: kind.title, on: filter == kind) {
                        withAnimation(.easeOut(duration: 0.2)) { filter = kind }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
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
        return spotted(marks)
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
            if mark.count > 1 {
                // A group: how many, in the brand's midnight ringed in gold.
                Text(verbatim: "\(mark.count)")
                    .font(HUDStyle.font(12))
                    .monospacedDigit()
                    .foregroundStyle(HUDStyle.cream)
                    .frame(width: Self.badgeSize + 4, height: Self.badgeSize + 4)
                    .background(Circle().fill(Brand.midnight))
                    .overlay(Circle().strokeBorder(HUDStyle.gold, lineWidth: 2))
                    .allowsHitTesting(false)
                    .accessibilityLabel(L("{count} places", ["count": mark.count]))
            } else if let kind = mark.badge {
                MinimapIcon(kind: kind, size: Self.badgeSize)
                    .allowsHitTesting(false)
            }
        case .lock:
            IconImage(.lock, size: 12)
                .foregroundStyle(HUDStyle.ink)
                .frame(width: Self.badgeSize, height: Self.badgeSize)
                .background(Circle().fill(HUDStyle.gold))
                .allowsHitTesting(false)
        case .cave:
            let known = session.hasVisited(mark.place)
            VStack(spacing: 1) {
                Circle()
                    .fill(HUDStyle.ink)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(selected == mark.place ? HUDStyle.gold : HUDStyle.cream.opacity(0.8), lineWidth: 1.5))
                if framing.scale >= 1.2 || selected == mark.place {
                    label(known ? Content.shared.map(mark.place)?.name ?? "" : "???", size: 11, color: .white.opacity(known ? 1 : 0.6))
                }
            }
            .allowsHitTesting(false)
        case .land:
            if let def = Content.shared.map(mark.place) {
                let state = status(of: def)
                let known = state == .here || state == .visited
                // Out where the whole continent shows, only where you are and what you tapped.
                if framing.scale >= 0.45 || state == .here || selected == def.id {
                    HStack(spacing: 3) {
                        if known, def.fence == true { IconImage(.star, size: 12).foregroundStyle(HUDStyle.gold) }
                        // White and bigger, so they read over any land (playtesting 2026-10-26: gold
                        // names over the meadows couldn't be read, and they were too small).
                        label(known ? def.name : "???", size: 14, color: .white.opacity(known ? 1 : 0.7))
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
/// in the map's window): a pale round face (playtesting 2026-10-26: on the orange one the needle's
/// red half didn't show), a needle through it, red to the north and slate to the south, and the four
/// points round its rim in dark ink, a quarter turn apart (playtesting 2026-10-26: drawn as the
/// game's turned view lies, north up-left and south down-right, they looked skewed). On the world
/// map north is up till you turn the map (`heading`): the needle and the points go round with it,
/// the letters staying upright. A cave's map lies as the game's view does (`isometric`): north up
/// and to the left, east up and to the right, as the cave does on screen.
struct MapCompass: View {
    var size: CGFloat = 72
    /// How far the map under it is turned clockwise: its north points that way from straight up.
    var heading: Angle = .zero
    /// The map under it lies turned and squashed as the game's view is (a cave's, `CaveMap`).
    var isometric = false
    /// The needle's north half, and the N.
    private static let needleRed = Color(red: 0.85, green: 0.16, blue: 0.14)

    /// Where a step `col` east and `row` north points on the map under it, as degrees clockwise
    /// from straight up.
    private func angle(col: CGFloat, row: CGFloat) -> Double {
        // On the turned, squashed view a row north is half as far up as it's across to the left.
        let (across, up) = isometric ? (col - row, (col + row) / 2) : (col, row)
        return atan2(Double(across), Double(up)) * 180 / Double.pi + heading.degrees
    }

    var body: some View {
        let north = angle(col: 0, row: 1)
        let points: [(label: String, angle: Double, main: Bool)] = [
            (L("N"), north, true), (L("E"), angle(col: 1, row: 0), false),
            (L("S"), angle(col: 0, row: -1), false), (L("W"), angle(col: -1, row: 0), false),
        ]
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [.white, Color(white: 0.9), Color(white: 0.74)], center: UnitPoint(x: 0.35, y: 0.3),
                                     startRadius: 1, endRadius: size / 2))
                .overlay(Circle().strokeBorder(HUDStyle.ink.opacity(0.55), lineWidth: max(1.5, size / 28)))
            // The needle: red to the north, slate to the south.
            VStack(spacing: 0) {
                CompassTriangle().fill(Self.needleRed).frame(width: size * 0.16, height: size * 0.24)
                CompassTriangle().fill(Color(white: 0.42)).frame(width: size * 0.16, height: size * 0.24).rotationEffect(.degrees(180))
            }
            .shadow(color: .black.opacity(0.25), radius: 0, x: 1, y: 1)
            .rotationEffect(.degrees(north))
            Circle().fill(HUDStyle.ink).frame(width: size * 0.07, height: size * 0.07)
            ForEach(points, id: \.label) { point in
                let radians = point.angle * Double.pi / 180
                Text(point.label)
                    .font(HUDStyle.font(size * (point.main ? 0.2 : 0.15)))
                    .foregroundStyle(point.main ? Self.needleRed : HUDStyle.ink)
                    .offset(x: CGFloat(sin(radians)) * size * 0.36, y: -CGFloat(cos(radians)) * size * 0.36)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
    }
}

/// A triangle pointing up, its base along the bottom.
private nonisolated struct CompassTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Which of the world map's badges show (`WorldAtlas.filter`): all of them, or one kind, so what
/// you're looking for stands out and doesn't hide in a group's number. Names, caves, locked roads
/// and where you are always show.
nonisolated enum MapFilter: String, CaseIterable {
    case all, quests, town, waystones, treasure

    var title: String {
        switch self {
        case .all: L("All")
        case .quests: L("Quests")
        case .town: L("Town")
        case .waystones: L("Waystones")
        case .treasure: L("Treasure")
        }
    }

    @MainActor func shows(_ kind: GameSession.MinimapMark.Kind) -> Bool {
        switch self {
        case .all: true
        case .quests: [.quest, .questNew, .questReady].contains(kind)
        case .town: [.healer, .bank, .shop, .smith, .weaver, .barber, .guild].contains(kind)
        case .waystones: kind == .waystone
        case .treasure: kind == .chest || kind == .lost
        }
    }
}
