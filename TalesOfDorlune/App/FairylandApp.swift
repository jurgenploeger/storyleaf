import SwiftUI
import UIKit

@main
struct FairylandApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Load the player's language before any text is made: the title screen's default hero name
        // (`L("Hero")`) is set before anything else would have woken the Localizer, so it stayed English.
        _ = Localizer.shared
        DebugLaunch.applyLanguage()
        DebugLaunch.seedTitleGames()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        DebugLaunch.forcesLandscape ? .landscape : .allButUpsideDown
    }
}

/// Title screen until a game is started or continued.
struct RootView: View {
    @State private var coordinator: GameCoordinator?
    @State private var pending: GameSession?
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(GameSettings.appearanceKey) private var appearance = "system"

    var body: some View {
        Group {
            if DebugLaunch.holdsLoadingCurtain {
                // Debug `curtain`: the loading screen, held part-way (screenshots of it).
                if DebugLaunch.holdsTravelCard {
                    MapLoadingCard(mapName: Content.shared.map("genie_desert")?.name ?? "", progress: 0.41)
                } else {
                    LoadingCurtain(progress: 0.41)
                }
            } else if let coordinator {
                GameView(coordinator: coordinator)
            } else if let pending {
                LoadingCurtain()
                    .task {
                        // Let the curtain draw before the (heavier) map build starts. The land is laid
                        // out off the main thread, so the screen still turns with the phone meanwhile.
                        try? await Task.sleep(for: .milliseconds(60))
                        let began = Date()
                        let grid = await GameCoordinator.layOut(GameCoordinator.startingMap(of: pending))
                        let game = GameCoordinator(session: pending, grid: grid, began: began)
                        game.onQuitToTitle = { quitToTitle() }
                        coordinator = game
                    }
            } else {
                TitleView { session in
                    pending = session
                }
            }
        }
        .onAppear {
            Self.applyAppearance(appearance)
            if coordinator == nil, let session = DebugLaunch.session() {
                let coordinator = GameCoordinator(session: session)
                self.coordinator = coordinator
                DebugLaunch.apply(to: coordinator)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: coordinator?.session.save()
            case .active:
                MusicPlayer.shared.resume()
                Self.applyAppearance(appearance)
                SeasonalIcon.update()
            default: break
            }
        }
        .onChange(of: appearance) { _, choice in Self.applyAppearance(choice) }
    }

    /// Settings → Appearance on every window: Light, Dark, or the phone's own look ("system").
    /// On the window rather than SwiftUI's `preferredColorScheme`, so alerts and file pickers follow
    /// too and going back to the phone's look takes at once. A debug launch's `dark` or `light` wins.
    static func applyAppearance(_ choice: String) {
        let style: UIUserInterfaceStyle = switch DebugLaunch.appearance ?? choice {
        case "light": .light
        case "dark": .dark
        default: .unspecified
        }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows { window.overrideUserInterfaceStyle = style }
        }
    }

    /// Leaves the game for the title screen (Settings → Back to title; the game is already saved).
    private func quitToTitle() {
        coordinator = nil
        pending = nil
    }
}
