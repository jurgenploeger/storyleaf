import CoreGraphics
import Foundation
import SpriteKit

/// One eye that shuts for a blink (art/eyes.json): its box in pixels from the top left, painted over
/// with the colour at `fill` in the open picture, so a recoloured copy shuts in its own colours.
nonisolated struct Eye: Sendable {
    let x, y, width, height: Int
    let fill: (x: Int, y: Int)

    init?(_ numbers: [Int]) {
        guard numbers.count == 6 else { return nil }
        x = numbers[0]
        y = numbers[1]
        width = numbers[2]
        height = numbers[3]
        fill = (numbers[4], numbers[5])
    }

    /// The same eye in a frame whose top left is at `origin` on its sheet.
    func moved(to origin: (x: Int, y: Int)) -> Eye {
        Eye([x + origin.x, y + origin.y, width, height, fill.x + origin.x, fill.y + origin.y])!
    }
}

/// Where every sprite's eyes are (art/eyes.json), so it can blink: a walk sheet's in each
/// direction's standing pose, a single picture's on it. A hero's or a quest giver's come from their
/// body layer, which stands for its head too (`key(forLayer:)`). Both eyes shut or neither: never a
/// wink (`shut`, `shutsEvenly`, `ArtLibrary.cleanFaces`).
nonisolated struct EyeBlink: Sendable {
    let sheets: [String: [Direction: [Eye]]]
    let pictures: [String: [Eye]]

    static let shared = EyeBlink()

    private init() {
        struct File: Decodable {
            let sheets: [String: [String: [[Int]]]]
            let pictures: [String: [[Int]]]
        }
        guard let url = Bundle.main.url(forResource: "eyes", withExtension: "json", subdirectory: "art"),
              let file = try? JSONDecoder().decode(File.self, from: Data(contentsOf: url)) else {
            print("⚠️ Couldn't read art/eyes.json")
            sheets = [:]
            pictures = [:]
            return
        }
        sheets = file.sheets.mapValues { directions in
            Dictionary(uniqueKeysWithValues: directions.compactMap { name, eyes in
                Direction(rawValue: name).map { ($0, eyes.compactMap(Eye.init)) }
            })
        }
        pictures = file.pictures.mapValues { $0.compactMap(Eye.init) }
    }

    /// Whose eyes a paper-doll layer has: a body's own, its head's (cut from the body) its body's.
    static func key(forLayer id: String) -> String? {
        if id.hasPrefix("body_") { return id }
        if id.hasPrefix("head_") { return "body_" + id.dropFirst(5) }
        return nil
    }

    /// `image` with `eyes` shut. A single picture's get a lash (`lash`); a walk sheet's shut under
    /// the lid already drawn over them. All of them or none: where one's fill colour is clear (a
    /// layer that doesn't reach there, like a head cut off above it), none shut, or one would wink.
    static func shut(_ image: CGImage, eyes: [Eye], lash: Bool) -> CGImage? {
        guard !eyes.isEmpty, var pixels = Pixels(image) else { return nil }
        let open = pixels
        guard eyes.allSatisfy({ (open.at($0.fill.x, $0.fill.y)?.3 ?? 0) >= 128 }) else { return nil }
        for eye in eyes {
            guard let fill = open.at(eye.fill.x, eye.fill.y) else { continue }
            // The lash in the eye's own darkest colour, so a pair's match; round it where the eye has
            // nothing darker than its lid (a white glint in a dark face).
            func darkest(margin: Int) -> (UInt8, UInt8, UInt8, UInt8)? {
                var found: (UInt8, UInt8, UInt8, UInt8)?
                for y in (eye.y - margin)..<(eye.y + eye.height + margin) {
                    for x in (eye.x - margin)..<(eye.x + eye.width + margin) {
                        guard let pixel = open.at(x, y), pixel.3 >= 128 else { continue }
                        if found.map({ Pixels.luma(pixel) < Pixels.luma($0) }) ?? true { found = pixel }
                    }
                }
                return found
            }
            let lashColor: (UInt8, UInt8, UInt8, UInt8)?
            if let inside = darkest(margin: 0), Pixels.luma(inside) < Pixels.luma(fill) - 30 {
                lashColor = inside
            } else {
                lashColor = darkest(margin: 1)
            }
            for y in eye.y..<(eye.y + eye.height) {
                for x in eye.x..<(eye.x + eye.width) where (open.at(x, y)?.3 ?? 0) >= 128 {
                    pixels.set(x, y, fill)
                }
            }
            guard lash, let lashColor else { continue }
            // Two-thirds of the way down, as eyelids meet; one pixel wide, it reads as a dash.
            let row = eye.y + min(eye.height - 1, eye.height * 2 / 3)
            let span = eye.width == 1 ? (eye.x - 1)...(eye.x + 1) : eye.x...(eye.x + eye.width - 1)
            for x in span where (open.at(x, row)?.3 ?? 0) >= 128 {
                pixels.set(x, row, lashColor)
            }
        }
        return pixels.image()
    }

    /// Whether every one of `eyes` shut as the sprite is finally drawn: some of each changed from
    /// `open` to `shut`. Where one didn't (it lies under a hat or hair drawn over the face, or its
    /// layer couldn't shut it), the sprite doesn't blink facing that way at all, or it would wink.
    static func shutsEvenly(open: CGImage, shut: CGImage, eyes: [Eye]) -> Bool {
        guard !eyes.isEmpty, let before = Pixels(open), let after = Pixels(shut) else { return false }
        return eyes.allSatisfy { eye in
            (eye.y..<(eye.y + eye.height)).contains { y in
                (eye.x..<(eye.x + eye.width)).contains { x in
                    guard let a = before.at(x, y), let b = after.at(x, y) else { return false }
                    return a != b
                }
            }
        }
    }

    /// Whether `top` covers every pixel `lower` draws round `eyes` (their boxes, `margin` out).
    static func hides(_ top: CGImage, over lower: CGImage, round eyes: [Eye], margin: Int) -> Bool {
        guard let above = Pixels(top), let below = Pixels(lower) else { return false }
        return eyes.allSatisfy { eye in
            ((eye.y - margin)..<(eye.y + eye.height + margin)).allSatisfy { y in
                ((eye.x - margin)..<(eye.x + eye.width + margin)).allSatisfy { x in
                    (below.at(x, y)?.3 ?? 0) < 128 || (above.at(x, y)?.3 ?? 0) >= 128
                }
            }
        }
    }

    /// A standing frame breathing out: everything above the waist (a little past halfway down what's
    /// drawn) a pixel lower, so a breath moves whole pixels instead of stretching them.
    static func exhaled(_ frame: CGImage) -> CGImage? {
        guard var pixels = Pixels(frame) else { return nil }
        let rows = (0..<pixels.height).filter { y in (0..<pixels.width).contains { (pixels.at($0, y)?.3 ?? 0) >= 128 } }
        guard let top = rows.first, let bottom = rows.last, bottom - top > 4 else { return nil }
        let waist = top + (bottom - top) * 55 / 100
        let open = pixels
        for y in stride(from: waist, to: top, by: -1) {
            for x in 0..<pixels.width {
                pixels.set(x, y, open.at(x, y - 1) ?? (0, 0, 0, 0))
            }
        }
        for x in 0..<pixels.width {
            pixels.set(x, top, (0, 0, 0, 0))
        }
        return pixels.image()
    }

    /// The blink, over and over: `shut` the eyes a moment every few seconds, then `open` them.
    @MainActor static func blinking(shut: SKAction, open: SKAction) -> SKAction {
        .repeatForever(.sequence([.wait(forDuration: 4.2, withRange: 4), shut, .wait(forDuration: 0.12), open]))
    }
}

/// A picture's pixels, RGBA premultiplied, the top row first.
private nonisolated struct Pixels {
    let width: Int
    let height: Int
    private var bytes: [UInt8]

    init?(_ image: CGImage) {
        width = image.width
        height = image.height
        guard let drawn = PixelImage.pixels(of: image, width: width, height: height) else { return nil }
        bytes = drawn
    }

    func at(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8, UInt8)? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let i = (y * width + x) * 4
        return (bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3])
    }

    mutating func set(_ x: Int, _ y: Int, _ pixel: (UInt8, UInt8, UInt8, UInt8)) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        let i = (y * width + x) * 4
        bytes[i] = pixel.0
        bytes[i + 1] = pixel.1
        bytes[i + 2] = pixel.2
        bytes[i + 3] = pixel.3
    }

    static func luma(_ pixel: (UInt8, UInt8, UInt8, UInt8)) -> Double {
        0.299 * Double(pixel.0) + 0.587 * Double(pixel.1) + 0.114 * Double(pixel.2)
    }

    func image() -> CGImage? {
        PixelImage.make(bytes, width: width, height: height)
    }
}
