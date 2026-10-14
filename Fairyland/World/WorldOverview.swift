import Observation
import UIKit

/// Every land's map for the world map (`WorldAtlas`): the same picture as its minimap, one pixel a
/// cell (`WorldScene.overview(of:art:)`). A land you're in hands its minimap over, and one next door
/// its own as soon as it's laid out (`GameCoordinator.buildNextDoor`); the rest are laid out one at
/// a time in the background, those round you first, and kept on disk after (for this build of the
/// game and its maps), so the world map opens on the whole continent.
@MainActor @Observable
final class WorldOverview {
    static let shared = WorldOverview()

    /// Each land's picture, by id.
    private(set) var images: [String: CGImage] = [:]
    @ObservationIgnored private var making = false
    /// Pictures handed in while the HUD's being drawn (a minimap made for it), shown a moment later.
    @ObservationIgnored private var pending: [String: CGImage] = [:]

    /// A land's picture, drawn already (its minimap). It may come in while SwiftUI's drawing the
    /// HUD, so it's added once that's done.
    func remember(_ id: String, _ image: CGImage) {
        guard images[id] == nil, pending[id] == nil else { return }
        save(id, image)
        pending[id] = image
        guard pending.count == 1 else { return }
        Task { self.flush() }
    }

    private func flush() {
        images.merge(pending) { kept, _ in kept }
        pending = [:]
    }

    /// The lands round where you are, nearest first: drawn before the rest (`prepare(first:)`).
    @ObservationIgnored private var wanted: [String] = []
    /// While the continent lays out the lands round you (`ContinentScene.buildWanted`), which come
    /// first: lands are laid out one at a time (`MapLayouts`), so these wait. Those it lays out, it
    /// hands in (`remember`), and they aren't laid out again.
    @ObservationIgnored var isHeld = false

    /// Fills in every land on the continent that isn't drawn yet: from disk, else laid out in the
    /// background, one at a time, each showing as it's done. `first`: the lands round where you
    /// are, nearest first, drawn before the rest even once it's under way, as the ground past
    /// your borders waits on them (`WorldScene.placeFarLands`).
    func prepare(first: [String] = []) {
        if !first.isEmpty { wanted = first }
        let content = Content.shared
        let missing = content.maps.filter { content.world[$0.id] != nil && images[$0.id] == nil && pending[$0.id] == nil }
        for def in missing {
            if let image = load(def.id) { images[def.id] = image }
        }
        guard !making else { return }
        let jobs = missing.filter { images[$0.id] == nil }
        guard !jobs.isEmpty else { return }
        making = true
        let caves = WorldMap.caves
        Task {
            var left = jobs
            while !left.isEmpty {
                while isHeld { try? await Task.sleep(for: .milliseconds(500)) }
                let next = wanted.compactMap { id in left.firstIndex { $0.id == id } }.first ?? 0
                let def = left.remove(at: next)
                guard images[def.id] == nil, pending[def.id] == nil else { continue }
                let around = Continent.neighbourhood(of: def)
                let map = await Task.detached(priority: .utility) { await MapLayouts.shared.lay(def, caves: caves, around: around) }.value
                remember(def.id, WorldScene.overview(of: map, art: ArtLibrary.shared))
            }
            making = false
        }
    }

    // MARK: On disk

    /// Where the pictures are kept: a folder for this build of the game and its maps, so a new
    /// version draws them afresh (and the old folders go).
    @ObservationIgnored private lazy var folder: URL? = {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let root = caches.appendingPathComponent("world-map", isDirectory: true)
        let here = root.appendingPathComponent(Self.stamp, isDirectory: true)
        let manager = FileManager.default
        for old in (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] where old.lastPathComponent != Self.stamp {
            try? manager.removeItem(at: old)
        }
        try? manager.createDirectory(at: here, withIntermediateDirectories: true)
        return here
    }()

    private func load(_ id: String) -> CGImage? {
        guard let url = folder?.appendingPathComponent(id + ".png") else { return nil }
        return UIImage(contentsOfFile: url.path)?.cgImage
    }

    private func save(_ id: String, _ image: CGImage) {
        guard let url = folder?.appendingPathComponent(id + ".png"), let data = UIImage(cgImage: image).pngData() else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// How the lands are drawn on it: one more each time that changes (each land its own shape now,
    /// clear where a land next door's is, `Region`), so the pictures kept are drawn afresh even in
    /// the same build.
    private static let look = 4

    /// This build of the game and its maps: the version, the build, how they're drawn (`look`) and
    /// a hash of the maps and the continent (FNV-1a).
    private static let stamp: String = {
        let info = Bundle.main.infoDictionary
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        func mix(_ data: Data) {
            for byte in data {
                hash ^= UInt64(byte)
                hash = hash &* 0x100_0000_01B3
            }
        }
        for name in ["maps", "world"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "content"),
               let data = try? Data(contentsOf: url) {
                mix(data)
            }
        }
        let version = (info?["CFBundleShortVersionString"] as? String ?? "") + "-" + (info?["CFBundleVersion"] as? String ?? "")
        mix(Data((version + "-\(WorldOverview.look)").utf8))
        return String(hash, radix: 16)
    }()
}
