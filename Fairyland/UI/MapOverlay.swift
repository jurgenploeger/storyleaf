import SwiftUI

/// Tapping the minimap: the world map, with where you are. The whole map of the area you're in
/// stays hidden, so caves and forests are still yours to explore; the minimap shows what's near.
struct MapOverlay: View {
    let session: GameSession
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            // The game's window, like every other: the title bar along its top edge, the atlas below
            // out to its frame (no frame of its own inside it).
            VStack(spacing: 0) {
                FLTitleBar(title: L("World map"), icon: .map, onClose: onClose)
                WorldAtlas(session: session)
            }
            // As tall as the map wants, or what the screen has room for (a phone on its side):
            // the atlas scrolls in whatever height is left under the title.
            .frame(maxWidth: 720)
            .gameWindow()
            .padding(14)
        }
    }
}
