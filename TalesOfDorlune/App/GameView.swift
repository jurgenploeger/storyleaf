import SwiftUI

/// The game screen: SpriteKit underneath, SwiftUI HUD and menus on top.
struct GameView: View {
    let coordinator: GameCoordinator
    /// The first-play tour of the HUD (see CoachMarks).
    @State private var touring = CoachMarks.shouldShow
    @Environment(\.scenePhase) private var scenePhase
    /// Switching language (Settings) redraws the HUD in it; the menu redraws itself.
    @State private var localizer = Localizer.shared
    /// A loading screen is up: while a land loads, then while the clouds rise over it and part onto
    /// the game (`curtain`), as they do when the game opens (`land`).
    @State private var curtainUp = true
    @State private var curtain = Curtain.waiting
    /// The land being travelled to, kept for the card while the clouds clear (the coordinator lets
    /// go of it once the land's ready).
    @State private var curtainName: String?
    /// The first load is the opening's: RootView's clouds come down onto the game then.
    @State private var loadedOnce = false
    /// Which clouds are on their way, so one cut short by another load lets that one be.
    @State private var landingID = 0

    private enum Curtain { case waiting, landing, clearing }

    var body: some View {
        ZStack {
            SpriteKitView(scene: coordinator.scene)
                .ignoresSafeArea()

            if let battle = coordinator.battle {
                // No chat in a fight: the map's chat button brings it back once the fight is over.
                BattleView(controller: battle)
                    .id(localizer.language)
            } else {
                if !DebugLaunch.hidesHUD {
                    WorldHUD(coordinator: coordinator)
                        .id(localizer.language)
                }
                switch coordinator.overlay {
                case .menu(let tab):
                    MenuView(session: coordinator.session, window: tab, onClose: coordinator.closeOverlay, onQuitToTitle: coordinator.onQuitToTitle)
                case .worldMap:
                    MapOverlay(session: coordinator.session, cave: coordinator.caveMap, levels: coordinator.caveLevels,
                               loadLevel: coordinator.caveMap(of:), rows: coordinator.mapRows, onClose: coordinator.closeOverlay)
                case .trade(let adventurer):
                    TradeView(session: coordinator.session, adventurer: adventurer, onClose: coordinator.closeOverlay)
                case .chat:
                    ChatView(session: coordinator.session, onSay: coordinator.say, onClose: coordinator.closeOverlay)
                case .profile(.adventurer(let person)):
                    ProfileWindow(coordinator: coordinator, person: person, onClose: coordinator.closeOverlay)
                case .profile(.hero):
                    // `GameCoordinator.open` shows yours as the menu's Hero window, your companion's as
                    // its Companions window; these never stay open as profiles.
                    MenuView(session: coordinator.session, window: .character, onClose: coordinator.closeOverlay, onQuitToTitle: coordinator.onQuitToTitle)
                case .profile(.pet(_)):
                    MenuView(session: coordinator.session, window: .companions, onClose: coordinator.closeOverlay, onQuitToTitle: coordinator.onQuitToTitle)
                case .destinations(let travel):
                    TravelPicker(session: coordinator.session, travel: travel, onGo: { coordinator.depart(travel, to: $0) },
                                 onClose: coordinator.closeOverlay)
                case .npc(let id):
                    if let npc = Content.shared.npc(id) {
                        NPCDialogView(npc: npc, session: coordinator.session, onClose: coordinator.closeOverlay, onFight: coordinator.fightBoss,
                                      onBank: coordinator.openBank)
                    }
                case .bank(let id):
                    if let npc = Content.shared.npc(id) {
                        BankView(npc: npc, session: coordinator.session, onClose: coordinator.closeOverlay)
                    }
                case nil:
                    EmptyView()
                }
            }
        }
        .overlayPreferenceValue(CoachAnchors.self) { anchors in
            if touring, coordinator.isReady, coordinator.battle == nil, coordinator.overlay == nil {
                CoachMarksView(anchors: anchors) {
                    CoachMarks.markDone()
                    withAnimation(.easeOut(duration: 0.3)) { touring = false }
                }
                .transition(.opacity)
            }
        }
        .overlay {
            // The day's gift, once the map is up and nothing else is on screen.
            if let gift = coordinator.dailyGift, coordinator.isReady, coordinator.battle == nil, coordinator.overlay == nil, !touring {
                DailyGiftCard(session: coordinator.session, gift: gift) {
                    withAnimation(.easeOut(duration: 0.25)) { coordinator.dailyGift = nil }
                }
                .transition(.opacity)
            }
        }
        .overlay {
            // An adventurer's offer for what you've put up for trade, once nothing else is up.
            if let bid = coordinator.session.pendingBid, coordinator.isReady, coordinator.battle == nil,
               coordinator.overlay == nil, coordinator.dailyGift == nil, !touring {
                TradeBidCard(session: coordinator.session, bid: bid) { accept in
                    withAnimation(.easeOut(duration: 0.2)) { coordinator.answerBid(accept) }
                }
                .transition(.opacity)
            }
        }
        .overlay {
            if curtainUp {
                Group {
                    if let name = coordinator.loadingMapName ?? curtainName {
                        MapLoadingCard(mapName: name, progress: coordinator.loadProgress,
                                       landing: curtain != .waiting, clearing: curtain == .clearing)
                    } else {
                        LoadingCurtain(progress: coordinator.loadProgress, landing: curtain != .waiting, clearing: curtain == .clearing)
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.4), value: curtainUp)
        .onAppear {
            if coordinator.isReady {
                curtainUp = false
                loadedOnce = true
            }
        }
        .onChange(of: coordinator.loadingMapName) { _, name in
            if let name { curtainName = name }
        }
        .onChange(of: coordinator.isReady) { _, ready in
            guard ready else {
                // Another load: its card, and any clouds still on their way let be.
                landingID += 1
                curtain = .waiting
                curtainUp = true
                return
            }
            if loadedOnce {
                land()
            } else {
                loadedOnce = true
                curtainUp = false
            }
        }
        // The fight waits while the app isn't in front (another app, the lock screen, a call, Control Centre).
        .onChange(of: scenePhase == .active) { _, active in
            coordinator.battle?.holdTurnClock(!active, for: "away")
            // No push left on the stick while away: a thumb on it as the app went was never let go.
            coordinator.input.move = .zero
            if active { coordinator.welcomeBack() }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        // A swipe up from the bottom edge (the joystick and the buttons sit close to it on a phone on
        // its side) moves the joystick first; a second one goes home.
        .defersSystemGestures(on: .bottom)
    }

    /// The land's ready under the loading card: the clouds rush up over it, then rise on past and
    /// thin out, the game coming through (`RootView.land`, as the game opens).
    private func land() {
        landingID += 1
        let id = landingID
        curtain = .landing
        SoundEffects.shared.play(.whoosh, volume: 0.6)
        Task {
            try? await Task.sleep(for: .seconds(LoadingCurtain.landingTime))
            guard id == landingID else { return }
            curtain = .clearing
            try? await Task.sleep(for: .seconds(LoadingCurtain.clearingTime))
            guard id == landingID else { return }
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) {
                curtainUp = false
                curtain = .waiting
            }
            curtainName = nil
        }
    }
}
