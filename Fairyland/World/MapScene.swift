import SpriteKit

/// The scene you walk about in, as the game drives it from its menus and battles
/// (`GameCoordinator`): a land of its own (`WorldScene`), or the continent as one place
/// (`ContinentScene`, docs/continuous-world.md) while it's shown.
protocol MapScene: SKScene {
    /// Set while a window or a battle is up: you don't walk, tap or meet monsters meanwhile.
    var isInputLocked: Bool { get set }
    /// Back from a battle or a window: you can walk again.
    func resume()
    /// What's on screen for behind a battle, the party (and a boss, `npcID`) left out.
    func battleBackdrop(hiding npcID: String?) -> SKTexture?
    /// The HUD's Talk button: whoever's near enough.
    func talkToNearby()
    /// You said something in the Chat window.
    func heroSay(_ text: String)
    /// An adventurer's answer, in a bubble over them.
    func adventurerSays(_ line: String, _ id: UUID)
    /// After a duel you won, the rival skulks off.
    func dismissAdventurer(_ id: UUID)
    /// A duel with an adventurer, from their card.
    func startDuel(with rival: Adventurer)
    /// A Homeward Feather taking you away, then `done`; and bringing you down where you arrive.
    func featherAway(then done: @escaping () -> Void)
    func awaitFeatherArrival()
    func featherArrive()
    /// Debug launches walking you about: no battles on the way.
    var holdsEncounters: Bool { get set }

    #if DEBUG
    func encounterForDebug()
    /// The `count` nearest friendly adventurers brought over (`invite=n`, `meet=n`); 0, the nearest
    /// group travelling together, in line (`group`).
    func summonAdventurersForDebug(_ count: Int) -> [Adventurer]
    func featherAwayForDebug()
    func sayForDebug(_ text: String)
    func localTellsForDebug()
    #endif
}

extension WorldScene: MapScene {}
extension ContinentScene: MapScene {}
