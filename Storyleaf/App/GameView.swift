import SwiftUI

/// The game screen: SpriteKit underneath, SwiftUI HUD and menus on top.
struct GameView: View {
    let coordinator: GameCoordinator
    /// The first-play tour of the HUD (see CoachMarks).
    @State private var touring = CoachMarks.shouldShow
    /// The chat window over a battle (the fight waits while you type).
    @State private var battleChat = false
    @Environment(\.scenePhase) private var scenePhase
    /// Switching language (Settings) redraws the HUD in it; the menu redraws itself.
    @State private var localizer = Localizer.shared

    var body: some View {
        ZStack {
            SpriteKitView(scene: coordinator.scene)
                .ignoresSafeArea()

            if let battle = coordinator.battle {
                // Chat stays one tap away mid-fight, at the right end of the battle's top row.
                BattleView(controller: battle, unreadChat: coordinator.session.unreadChat > 0,
                           onChat: battleChat ? nil : { openBattleChat() })
                    .id(localizer.language)
                if battleChat {
                    ChatView(session: coordinator.session, onSay: coordinator.say) { battleChat = false }
                }
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
                               loadLevel: coordinator.caveMap(of:), onClose: coordinator.closeOverlay)
                case .trade(let adventurer):
                    TradeView(session: coordinator.session, adventurer: adventurer, onClose: coordinator.closeOverlay)
                case .chat:
                    ChatView(session: coordinator.session, onSay: coordinator.say, onClose: coordinator.closeOverlay)
                case .profile(let profile):
                    ProfileCard(session: coordinator.session, profile: profile, onClose: coordinator.closeOverlay)
                case .destinations(let travel):
                    TravelPicker(session: coordinator.session, travel: travel, onGo: { coordinator.depart(travel, to: $0) },
                                 onClose: coordinator.closeOverlay)
                case .npc(let id):
                    if let npc = Content.shared.npc(id) {
                        NPCDialogView(npc: npc, session: coordinator.session, onClose: coordinator.closeOverlay, onFight: coordinator.fightBoss)
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
            if !coordinator.isReady {
                if let name = coordinator.loadingMapName {
                    MapLoadingCard(mapName: name, progress: coordinator.loadProgress).transition(.opacity)
                } else {
                    LoadingCurtain(progress: coordinator.loadProgress).transition(.opacity)
                }
            }
        }
        .animation(.easeOut(duration: 0.4), value: coordinator.isReady)
        .onChange(of: coordinator.battle == nil) { battleChat = false }
        // The fight waits while you type, turn clock and all.
        .onChange(of: battleChat) { coordinator.battle?.holdTurnClock(battleChat, for: "chat") }
        // And while the app isn't in front (another app, the lock screen, a call, Control Centre).
        .onChange(of: scenePhase == .active) { _, active in
            coordinator.battle?.holdTurnClock(!active, for: "away")
            if active { coordinator.welcomeBack() }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        // A swipe up from the bottom edge (the joystick and the buttons sit close to it on a phone on
        // its side) moves the joystick first; a second one goes home.
        .defersSystemGestures(on: .bottom)
    }

    /// The chat over a fight: read, so the dot goes.
    private func openBattleChat() {
        coordinator.session.unreadChat = 0
        battleChat = true
    }
}
