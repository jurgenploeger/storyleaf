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

/// Title screen until a game is started or continued. Starting one carries the logo down to the
/// loading screen; once the game is ready, the clouds come up over it and clear off the game.
struct RootView: View {
    @State private var coordinator: GameCoordinator?
    @State private var pending: GameSession?
    /// How far the opening of a game started on the title has got.
    @State private var opening = Opening.loading
    /// The logo's place on the title and on the loading screen, so it moves from one to the other.
    @Namespace private var logoSpace
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(GameSettings.appearanceKey) private var appearance = "system"

    enum Opening {
        /// The loading screen, the game being built under it.
        case loading
        /// The game's ready: the clouds rise over the screen.
        case landing
        /// The clouds fade, the game showing through them.
        case clearing
    }

    /// How long the clouds take to fade off the game.
    private static let clearingTime = 0.8

    var body: some View {
        Group {
            if DebugLaunch.holdsLoadingCurtain {
                // Debug `curtain`: the loading screen, held part-way (screenshots of it).
                if DebugLaunch.holdsTravelCard {
                    MapLoadingCard(mapName: Content.shared.map("genie_desert")?.name ?? "", progress: 0.41)
                } else {
                    LoadingCurtain(progress: 0.41)
                }
            } else {
                ZStack {
                    // The game, once made: under the loading screen till the clouds clear off it.
                    if let coordinator {
                        GameView(coordinator: coordinator)
                    }
                    if let pending {
                        LoadingCurtain(progress: coordinator?.loadProgress ?? 0, logoSpace: logoSpace, landing: opening != .loading)
                            .opacity(opening == .clearing ? 0 : 1)
                            .zIndex(1)
                            // There at once, under the title fading off it: only its bar fades in.
                            .transition(.identity)
                            .task {
                                // Let the curtain draw before the (heavier) map build starts. The land is laid
                                // out off the main thread, so the screen still turns with the phone meanwhile.
                                let start = Date()
                                try? await Task.sleep(for: .milliseconds(60))
                                let began = Date()
                                let grid = await GameCoordinator.layOut(GameCoordinator.startingMap(of: pending))
                                // Making the game holds the screen a moment: not while the logo is on its way.
                                let wait = LoadingCurtain.handOff - Date().timeIntervalSince(start)
                                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                                let game = GameCoordinator(session: pending, grid: grid, began: began)
                                game.onQuitToTitle = { quitToTitle() }
                                coordinator = game
                            }
                    } else if coordinator == nil {
                        // Fading away over the loading screen as the logo moves down onto it.
                        TitleView(logoSpace: logoSpace) { session in
                            // Once: the title can still be tapped as it fades.
                            guard pending == nil else { return }
                            withAnimation(.easeInOut(duration: LoadingCurtain.handOff)) { pending = session }
                        }
                        .zIndex(2)
                        .transition(.opacity)
                    }
                }
                .onChange(of: coordinator?.isReady == true) { _, ready in
                    if ready, pending != nil, opening == .loading { land() }
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

    /// The game is ready under the loading screen: the clouds rush up over it, as if the logo fell
    /// through them to the ground, then fade off the game.
    private func land() {
        opening = .landing
        SoundEffects.shared.play(.whoosh, volume: 0.6)
        Task {
            try? await Task.sleep(for: .seconds(LoadingCurtain.landingTime))
            withAnimation(.easeInOut(duration: Self.clearingTime)) { opening = .clearing }
            try? await Task.sleep(for: .seconds(Self.clearingTime))
            pending = nil
            opening = .loading
        }
    }

    /// Leaves the game for the title screen (Settings → Back to title; the game is already saved).
    private func quitToTitle() {
        coordinator = nil
        pending = nil
        opening = .loading
    }
}
