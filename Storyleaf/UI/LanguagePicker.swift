import SwiftUI

/// Every language the game speaks, each in its own name; tapping one switches the game to it at
/// once (`Localizer.choose`). In Settings, and behind the globe button on the title screen.
struct LanguageList: View {
    @State private var localizer = Localizer.shared

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(localizer.languages) { language in
                let selected = language.code == localizer.language
                Button {
                    localizer.choose(language.code)
                } label: {
                    HStack(spacing: 6) {
                        Text(language.name).lineLimit(1).minimumScaleFactor(0.7)
                        Spacer(minLength: 0)
                        if selected { IconImage(.check, size: 12) }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PixelButtonStyle(tint: selected ? HUDStyle.gold : HUDStyle.cream, compact: true))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// The title screen's language panel: the list under a title bar.
struct LanguagePanel: View {
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FLTitleBar(title: L("Language"), icon: .globe, onClose: onClose)
            LanguageList()
                .padding(14)
        }
        .frame(maxWidth: 640)
        .gameWindow()
    }
}
