import SpriteKit
import SwiftUI

/// Hosts an SKView and cross-fades whenever the scene changes (map to map, into and out of battle),
/// except walking over a border into the land next door, which was on screen already.
struct SpriteKitView: UIViewRepresentable {
    let scene: SKScene

    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = 60
        #if DEBUG
        // Not while filming the App Store preview (debug `demo`) or shooting its screenshots (`clean`).
        if !DebugLaunch.hidesFrameCounter {
            view.showsFPS = true
            view.showsNodeCount = true
        }
        #endif
        view.presentScene(scene)
        return view
    }

    func updateUIView(_ view: SKView, context: Context) {
        guard view.scene !== scene else { return }
        // Walked over a border into the land next door: it was on screen already, so no fade.
        if let land = scene as? WorldScene, land.arrivesOnFoot {
            land.arrivesOnFoot = false
            view.presentScene(scene)
            return
        }
        let transition: SKTransition = scene is BattleScene
            ? .fade(with: .white, duration: 0.45)
            : .fade(withDuration: 0.5)
        view.presentScene(scene, transition: transition)
    }
}
