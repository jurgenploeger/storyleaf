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

            // The game's window, like every other. A cave's: its title along the top, the time and
            // where you are under it, its map below. The world's: the atlas out to the frame, its
            // title and where you are over it (playtesting 2026-10-26).
            VStack(spacing: 0) {
                if let cave, !showsWorld {
                    WindowTitle(level?.name ?? session.mapName, onClose: onClose)
                        .padding(.bottom, 8)
                    if level == nil {
                        pills
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }
                    if levels.count > 1 { levelChips }
                    if level != nil {
                        CaveMap(picture: levelPicture, cell: nil, marks: []) { showsWorld = true }
                    } else {
                        CaveMap(picture: cave, cell: session.mapCell, marks: session.minimapMarks) {
                            showsWorld = true
                        }
                    }
                } else {
                    WorldAtlas(session: session) {
                        VStack(alignment: .leading, spacing: 6) {
                            WindowTitle(L("World map"), onClose: onClose)
                            pills.padding(.horizontal, 16)
                        }
                    } bottomLeading: {
                        // The land you're in.
                        Text(session.mapName)
                            .font(HUDStyle.font(15))
                            .foregroundStyle(HUDStyle.cream)
                            .shadow(color: .black.opacity(0.8), radius: 0, x: 1, y: 1)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel(L("You are in {place}", ["place": session.mapName]))
                    }
                }
            }
            // As big as a menu window, the map filling what's left under the title.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .gameWindow()
            .menuWindowMargins()
        }
    }

    /// The time of day and your coordinates, each on a dark pill (playtesting 2026-10-26: "The
    /// year/date/time bar should only become a in-game time with sun/moon icon, just showing in a
    /// dark blue pill. The coordinates should also show in a dark blue pill").
    private var pills: some View {
        let x = session.mapCell.col, y = rows - 1 - session.mapCell.row
        return HStack(spacing: 6) {
            GameTimePill(session: session)
            // Close together: a thin space either side of the colon.
            Text(verbatim: "\(x)\u{2009}:\u{2009}\(y)")
                .font(HUDStyle.font(11).monospacedDigit())
                .foregroundStyle(HUDStyle.cream)
                .mapPill()
                .accessibilityLabel(L("Coordinates {x}, {y}", ["x": x, "y": y]))
        }
    }

    /// One chip a level, gold for the one shown.
    private var levelChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(levels) { option in
                    FilterChip(title: option.name, on: option.id == (level?.id ?? session.data.mapID)) { show(option) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
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
            // Its compass as the cave lies, turned like the game's view (`MapCompass.isometric`).
            .overlay(alignment: .topTrailing) {
                MapCompass(size: 60, isometric: true).padding(10).allowsHitTesting(false).accessibilityHidden(true)
            }
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

/// The time of day on the game's clock (`GameClock`) with a sun by day and a moon by night, on a
/// dark pill: on the map, where the HUD's calendar plate went. Only the hour, in the player's own
/// way of writing it ("8 PM", "20 Uhr"; playtesting 2026-10-26: "Don't show the minutes").
private struct GameTimePill: View {
    let session: GameSession
    /// With night and day switched off in Settings, the sun shines on the pill around the clock.
    @AppStorage(GameSettings.dayAndNightKey) private var dayAndNight = true

    var body: some View {
        // An in-game minute passes every real second by day.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let hours = GameClock.hours(at: context.date, since: session.data.startedAt)
            let hour = Int(hours) % 24
            let daytime = (6..<18).contains(hour) || !dayAndNight
            HStack(spacing: 4) {
                IconImage(daytime ? .sun : .moon, size: 12)
                    .foregroundStyle(daytime ? HUDStyle.gold : HUDStyle.cream)
                Text(Self.text(hour: hour))
                    .font(HUDStyle.font(11).monospacedDigit())
                    .foregroundStyle(HUDStyle.cream)
                    .lineLimit(1)
                    .fixedSize()
            }
            .mapPill()
        }
    }

    private static func text(hour: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        let utc = TimeZone(identifier: "UTC") ?? .current
        calendar.timeZone = utc
        guard let date = calendar.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: hour)) else {
            return String(format: "%02d", hour)
        }
        return date.formatted(Date.FormatStyle(locale: Localizer.shared.locale, calendar: calendar, timeZone: utc)
            .hour(.defaultDigits(amPM: .abbreviated)))
    }
}

extension View {
    /// A dark navy pill, for what the map says over itself (the time, your coordinates).
    func mapPill() -> some View {
        padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(HUDStyle.ink.opacity(0.88)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
    }
}
