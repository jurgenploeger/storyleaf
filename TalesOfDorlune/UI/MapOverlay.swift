import SwiftUI

/// Tapping the minimap: the world map, with where you are. In a cave, the cave's own map instead,
/// as far as you've explored it, with a way to the world map, and its other levels a tap away.
struct MapOverlay: View {
    let session: GameSession
    /// The cave you're in, if you're in one (`GameCoordinator.caveMap`).
    var cave: CaveMap.Picture? = nil
    /// The cave's levels it can show, the top first (`GameCoordinator.caveLevels`): with more than
    /// one, a chip for each over the map.
    var levels: [MapDef] = []
    /// Another level's map (`GameCoordinator.caveMap(of:)`).
    var loadLevel: @MainActor (MapDef) async -> CaveMap.Picture? = { _ in nil }
    /// How many rows the land you're in has, to number your cell from its north edge
    /// (`GameCoordinator.mapRows`).
    var rows = 0
    let onClose: () -> Void
    @State private var showsWorld = false
    /// The level shown when it isn't the one you're on, and its map once it's drawn.
    @State private var level: MapDef?
    @State private var levelPicture: CaveMap.Picture?

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            // The game's window, like every other: the title bar along its top edge, the atlas below
            // out to its frame (no frame of its own inside it).
            VStack(spacing: 0) {
                if let cave, !showsWorld {
                    FLTitleBar(title: level?.name ?? session.mapName, icon: .map, onClose: onClose)
                    if level == nil { here }
                    if levels.count > 1 { levelChips }
                    if level != nil {
                        CaveMap(picture: levelPicture, cell: nil, marks: []) { showsWorld = true }
                    } else {
                        CaveMap(picture: cave, cell: session.mapCell, marks: session.minimapMarks) {
                            showsWorld = true
                        }
                    }
                } else {
                    FLTitleBar(title: L("World map"), icon: .map, onClose: onClose)
                    here
                    WorldAtlas(session: session)
                }
            }
            // As big as a menu window, the map filling what's left under the title.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .gameWindow()
            .menuWindowMargins()
        }
    }

    /// Where you are: the land's name, and on their plates the date and time and your coordinates, as
    /// the minimap's title bar and the HUD's calendar plate showed them before (playtesting 2026-10-25:
    /// "Only when you tap on the mini map you see the coordinates"; "Remove the day/time bar in the top
    /// left and incorporate that in the map modal").
    private var here: some View {
        HStack(spacing: 8) {
            IconImage(.map, size: 14).foregroundStyle(HUDStyle.gold)
            Text(session.mapName)
                .font(HUDStyle.font(12))
                .foregroundStyle(HUDStyle.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            GameDatePlate(session: session)
            Text(verbatim: "\(session.mapCell.col) : \(rows - 1 - session.mapCell.row)")
                .font(HUDStyle.mono(11))
                .foregroundStyle(HUDStyle.plateDark)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(HUDStyle.plateBackground)
                .accessibilityLabel(L("Coordinates {x}, {y}", ["x": session.mapCell.col, "y": rows - 1 - session.mapCell.row]))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color(red: 0.03, green: 0.05, blue: 0.1))
    }

    /// One chip a level, gold for the one shown.
    private var levelChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(levels) { option in
                    FilterChip(title: option.name, on: option.id == (level?.id ?? session.data.mapID)) { show(option) }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(red: 0.03, green: 0.05, blue: 0.1))
    }

    private func show(_ option: MapDef) {
        guard option.id != (level?.id ?? session.data.mapID) else { return }
        levelPicture = nil
        guard option.id != session.data.mapID else {
            level = nil
            return
        }
        level = option
        Task {
            let picture = await loadLevel(option)
            if level?.id == option.id { levelPicture = picture }
        }
    }
}

/// A cave's map (playtesting 2026-10-17: "When I'm in a cave, it should show the map of that"): its
/// minimap's picture, dark where you haven't been, turned and squashed as the minimap is, so it
/// lies the way the cave does on screen, fitted to the window. Where you are and who does what (the
/// minimap's icons); a button to the world map under it.
struct CaveMap: View {
    /// The cave's minimap, one pixel a cell (`WorldScene.minimapImage`), rows north at the top.
    struct Picture {
        let image: UIImage
        let columns: Int
        let rows: Int
    }

    /// Nil while it's drawn (another level's, laid out the first time it's shown).
    let picture: Picture?
    /// Where you are: nil on another level.
    let cell: GridPoint?
    let marks: [GameSession.MinimapMark]
    let showWorld: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { space in
                if let picture {
                    // Turned 45 degrees and squashed by half, the cave spans (columns + rows) / sqrt(2)
                    // cells across and half that down: as big as fits.
                    let half = CGFloat(0.5).squareRoot()
                    let span = CGFloat(picture.columns + picture.rows) * half
                    let zoom = max(1, min(space.size.width / span, space.size.height / (span * 0.5)))
                    ZStack {
                        Image(uiImage: picture.image)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: CGFloat(picture.columns) * zoom, height: CGFloat(picture.rows) * zoom)
                            .rotationEffect(.degrees(-45))
                            .scaleEffect(x: 1, y: 0.5)
                        ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in
                            MinimapIcon(kind: mark.kind)
                                .offset(offset(of: mark.cell, in: picture, zoom: zoom))
                        }
                        if let cell {
                            Circle()
                                .fill(HUDStyle.gold)
                                .frame(width: 10, height: 10)
                                .overlay(Circle().stroke(HUDStyle.ink, lineWidth: 1.5))
                                .offset(offset(of: cell, in: picture, zoom: zoom))
                        }
                    }
                    .frame(width: space.size.width, height: space.size.height)
                } else {
                    ProgressView()
                        .tint(HUDStyle.cream)
                        .frame(width: space.size.width, height: space.size.height)
                }
            }
            .frame(minHeight: 260)
            .background(Color(red: 0.03, green: 0.05, blue: 0.1))
            .clipped()
            .overlay(alignment: .topTrailing) { MapCompass(size: 60).padding(10).allowsHitTesting(false) }
            Button(L("World map"), action: showWorld)
                .buttonStyle(PixelButtonStyle(compact: true))
                .padding(.bottom, 10)
        }
    }

    /// Where a cell lies from the middle of the turned map, as the minimap places its dots.
    private func offset(of other: GridPoint, in picture: Picture, zoom: CGFloat) -> CGSize {
        let x = (CGFloat(other.col) + 0.5 - CGFloat(picture.columns) / 2) * zoom
        let y = (CGFloat(picture.rows) / 2 - CGFloat(other.row) - 0.5) * zoom
        let half = CGFloat(0.5).squareRoot()
        return CGSize(width: (x + y) * half, height: (y - x) * half * 0.5)
    }
}

/// The date and time on the game's calendar on a tan plate, with a sun by day and a moon by night
/// (`GameClock`): on the map's "you are here" row, where the HUD's calendar plate went.
private struct GameDatePlate: View {
    let session: GameSession
    /// With night and day switched off in Settings, the sun shines on the plate around the clock.
    @AppStorage(GameSettings.dayAndNightKey) private var dayAndNight = true

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            let moment = GameClock.moment(at: context.date, since: session.data.startedAt)
            let daytime = moment.isDaytime || !dayAndNight
            HStack(spacing: 4) {
                IconImage(daytime ? .sun : .moon, size: 12)
                    .foregroundStyle(daytime ? HUDStyle.orange : Color(red: 0.35, green: 0.35, blue: 0.75))
                Text(moment.text)
                    .font(HUDStyle.font(11).monospacedDigit())
                    .foregroundStyle(HUDStyle.plateDark)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(HUDStyle.plateBackground)
        }
    }
}
