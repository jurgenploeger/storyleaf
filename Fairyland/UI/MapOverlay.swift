import SwiftUI

/// Tapping the minimap: the world map, with where you are. In a cave, the cave's own map instead,
/// as far as you've explored it, with a way to the world map.
struct MapOverlay: View {
    let session: GameSession
    /// The cave you're in, if you're in one (`GameCoordinator.caveMap`).
    var cave: CaveMap.Picture? = nil
    let onClose: () -> Void
    @State private var showsWorld = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            // The game's window, like every other: the title bar along its top edge, the atlas below
            // out to its frame (no frame of its own inside it).
            VStack(spacing: 0) {
                if let cave, !showsWorld {
                    FLTitleBar(title: session.mapName, icon: .map, onClose: onClose)
                    CaveMap(picture: cave, cell: session.mapCell, marks: session.minimapMarks) {
                        showsWorld = true
                    }
                } else {
                    FLTitleBar(title: L("World map"), icon: .map, onClose: onClose)
                    WorldAtlas(session: session)
                }
            }
            // As tall as the map wants, or what the screen has room for (a phone on its side):
            // the atlas scrolls in whatever height is left under the title.
            .frame(maxWidth: 720)
            .gameWindow()
            .padding(14)
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

    let picture: Picture
    let cell: GridPoint
    let marks: [GameSession.MinimapMark]
    let showWorld: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { space in
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
                            .offset(offset(of: mark.cell, zoom: zoom))
                    }
                    Circle()
                        .fill(HUDStyle.gold)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(HUDStyle.ink, lineWidth: 1.5))
                        .offset(offset(of: cell, zoom: zoom))
                }
                .frame(width: space.size.width, height: space.size.height)
            }
            .frame(minHeight: 260)
            .background(Color(red: 0.03, green: 0.05, blue: 0.1))
            .clipped()
            Button(L("World map"), action: showWorld)
                .buttonStyle(PixelButtonStyle(compact: true))
                .padding(.bottom, 10)
        }
    }

    /// Where a cell lies from the middle of the turned map, as the minimap places its dots.
    private func offset(of other: GridPoint, zoom: CGFloat) -> CGSize {
        let x = (CGFloat(other.col) + 0.5 - CGFloat(picture.columns) / 2) * zoom
        let y = (CGFloat(picture.rows) / 2 - CGFloat(other.row) - 0.5) * zoom
        let half = CGFloat(0.5).squareRoot()
        return CGSize(width: (x + y) * half, height: (y - x) * half * 0.5)
    }
}
