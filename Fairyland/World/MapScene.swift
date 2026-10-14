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
}

extension WorldScene: MapScene {}
extension ContinentScene: MapScene {}
