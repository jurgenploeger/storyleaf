import CoreGraphics
import Foundation

/// A free "derived" sprite: an existing sprite with a palette swap, like classic games made
/// villagers and monster variants. Declared in art/assets.json as
/// `"derive": { "from": "player_walk", "recolor": [ … ] }`. With `layers` it's stacked from
/// paper-doll layers instead, like a hero (`ArtLibrary.register`): a quest giver's hair, on a layer
/// of its own, takes its colour on every shade.
nonisolated struct Derivation: Decodable, Sendable {
    let from: String
    let recolor: [RecolorRule]
    var layers: [ArtLayer]? = nil
}

/// Changes pixels whose colour falls in a hue range (optionally only saturated or bright ones).
/// Hues are in degrees; a range like [330, 20] wraps around red.
nonisolated struct RecolorRule: Decodable, Sendable {
    let hue: [Double]?
    let minSaturation: Double?
    let maxSaturation: Double?
    let minValue: Double?
    let maxValue: Double?
    /// Set the hue to this…
    let to: Double?
    /// …or rotate it by this many degrees.
    let shift: Double?
    /// With `to` and a `hue` window, keeps the shading's hue shift: each hue lands its distance
    /// from the window's middle times this away from `to`. 0 (the default) paints one flat hue;
    /// a negative spread flips the ramp, so shadows that leaned blue in a green lean red in a brown.
    let spread: Double?
    /// Multipliers for saturation and brightness.
    let saturation: Double?
    let value: Double?
    /// Added to the saturation and brightness after the multipliers: with them a dye lays a material's
    /// ramp round its own colour (`DyeDef.rule(onto:)`), however pale or dark the material was.
    var saturationOffset: Double? = nil
    var valueOffset: Double? = nil

    func matches(hue h: Double, saturation s: Double, value v: Double) -> Bool {
        guard s >= (minSaturation ?? 0.15), s <= (maxSaturation ?? 1), v >= (minValue ?? 0), v <= (maxValue ?? 1) else { return false }
        guard let range = hue, range.count == 2 else { return true }
        return range[0] <= range[1] ? (h >= range[0] && h <= range[1]) : (h >= range[0] || h <= range[1])
    }

    /// How far hue `h` lies from the middle of the `hue` window, in degrees (negative below it).
    func distanceFromMiddle(of h: Double) -> Double {
        guard let range = hue, range.count == 2 else { return 0 }
        let width = range[0] <= range[1] ? range[1] - range[0] : range[1] + 360 - range[0]
        var distance = (h - range[0] - width / 2).truncatingRemainder(dividingBy: 360)
        if distance > 180 { distance -= 360 } else if distance < -180 { distance += 360 }
        return distance
    }

    /// The same change, made wherever `window` matches (its hue, saturations and values) instead.
    func within(_ window: RecolorRule) -> RecolorRule {
        RecolorRule(hue: window.hue, minSaturation: window.minSaturation, maxSaturation: window.maxSaturation,
                    minValue: window.minValue, maxValue: window.maxValue,
                    to: to, shift: shift, spread: spread, saturation: saturation, value: value,
                    saturationOffset: saturationOffset, valueOffset: valueOffset)
    }
}

/// A map's colour mood (`theme.palette` in content/maps.json), applied to its ground, scenery and
/// buildings as they load. Heroes, monsters and items keep their own colours so they stand out.
nonisolated struct MapPalette: Decodable, Sendable {
    /// Hue swaps applied first, like a derive (greens to teal, sand to lilac).
    let recolor: [RecolorRule]?
    /// Saturation multiplier for coloured pixels (greys and outlines stay grey).
    let saturation: Double?
    /// Dark pixels lean toward `shadow` and bright ones toward `highlight`. Only the colour's
    /// difference from grey is added, so brightness stays put.
    let shadow: String?
    let highlight: String?
    /// How strongly shadows lean (default 0.35) and highlights lean (defaults to `tone`).
    let tone: Double?
    let glow: Double?
    /// The light characters stand in: their sprites are tinted toward it by `lightStrength`
    /// (0...1, default 0.4), so they blend with the map instead of looking pasted on.
    let light: String?
    let lightStrength: Double?
    /// How strongly the ground varies in colour across the map, in big soft patches leaning
    /// toward `shadow` and `highlight` (0...1, default 0.12).
    let variation: Double?
}

enum Recolor {
    /// Applies the first matching rule to every opaque pixel. Outlines and greys stay put
    /// unless a rule explicitly asks for low saturation.
    nonisolated static func apply(_ rules: [RecolorRule], to image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        guard var pixels = PixelImage.pixels(of: image, width: width, height: height) else { return nil }

        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[index + 3])
            guard alpha > 0 else { continue }
            // Un-premultiply, recolour in HSV, premultiply again.
            let r = Double(pixels[index]) / alpha, g = Double(pixels[index + 1]) / alpha, b = Double(pixels[index + 2]) / alpha
            var (h, s, v) = hsv(r, g, b)
            guard let rule = rules.first(where: { $0.matches(hue: h, saturation: s, value: v) }) else { continue }
            if let to = rule.to { h = to + (rule.spread ?? 0) * rule.distanceFromMiddle(of: h) } else if let shift = rule.shift { h += shift }
            h = h.truncatingRemainder(dividingBy: 360)
            if h < 0 { h += 360 }
            s = min(1, max(0, s * (rule.saturation ?? 1) + (rule.saturationOffset ?? 0)))
            v = min(1, max(0, v * (rule.value ?? 1) + (rule.valueOffset ?? 0)))
            let (nr, ng, nb) = rgb(h, s, v)
            pixels[index] = UInt8(max(0, min(255, (nr * alpha).rounded())))
            pixels[index + 1] = UInt8(max(0, min(255, (ng * alpha).rounded())))
            pixels[index + 2] = UInt8(max(0, min(255, (nb * alpha).rounded())))
        }
        return PixelImage.make(pixels, width: width, height: height)
    }

    /// Grades a sprite with a map's palette: hue swaps, saturation, then coloured shadows and highlights.
    nonisolated static func grade(_ palette: MapPalette, image: CGImage) -> CGImage? {
        var source = image
        if let rules = palette.recolor, !rules.isEmpty, let swapped = apply(rules, to: image) { source = swapped }
        let width = source.width, height = source.height
        guard var pixels = PixelImage.pixels(of: source, width: width, height: height) else { return nil }

        let saturation = palette.saturation ?? 1
        let tone = palette.tone ?? 0.35, glow = palette.glow ?? tone
        let shadow = offset(palette.shadow), highlight = offset(palette.highlight)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[index + 3])
            guard alpha > 0 else { continue }
            var r = Double(pixels[index]) / alpha, g = Double(pixels[index + 1]) / alpha, b = Double(pixels[index + 2]) / alpha
            if saturation != 1 {
                let (h, s, v) = hsv(r, g, b)
                if s > 0.08 { (r, g, b) = rgb(h, min(1, s * saturation), v) }
            }
            let luminance = 0.299 * r + 0.587 * g + 0.114 * b
            let dark = tone * pow(max(0, 1 - luminance), 1.5), light = glow * pow(max(0, luminance), 1.5)
            r += dark * shadow.r + light * highlight.r
            g += dark * shadow.g + light * highlight.g
            b += dark * shadow.b + light * highlight.b
            pixels[index] = UInt8(max(0, min(1, r)) * alpha)
            pixels[index + 1] = UInt8(max(0, min(1, g)) * alpha)
            pixels[index + 2] = UInt8(max(0, min(1, b)) * alpha)
        }
        return PixelImage.make(pixels, width: width, height: height)
    }

    /// How a dyed piece's icon, and a weapon's held sprites, are recoloured (`ArtLibrary`, a dyed item's
    /// art): the picture's main colour and its trim, found on it, taken to the two dyes
    /// (`DyeDef.rule(onto:)`, as a sheet's are). Its colours (but its outlines) fall in families: its
    /// commonest hue (the hues within 40° of it), the next commonest, and its greys (with a barely
    /// coloured family of their hue: a steel's blue shading). The biggest is its main colour and the next
    /// its trim (each at least a twenty-fifth of it). A weapon, drawn with its grip
    /// bottom left, has its main colour on whichever of the two lies nearer its tip, top right: the
    /// blade or the staff's head, the trim on the hilt or the haft. Every family gets a rule, those not
    /// dyed one that changes nothing, so a dye takes only its own family's colours. The families are
    /// found on `image` (an icon) and measured on `target` (a held sprite shrunk from it), so a weapon's
    /// blade is its blade in the hand too. tools/dye_art.py `icon_rules` is the same.
    nonisolated static func dyeRules(for image: CGImage, main: DyeDef?, trim: DyeDef?, weapon: Bool, on target: CGImage? = nil) -> [RecolorRule] {
        struct Seen { let h: Double, s: Double, v: Double, x: Double, y: Double }
        func colours(_ picture: CGImage) -> [Seen] {
            let width = picture.width
            guard let pixels = PixelImage.pixels(of: picture, width: width, height: picture.height) else { return [] }
            var seen: [Seen] = []
            for index in stride(from: 0, to: pixels.count, by: 4) {
                let alpha = Double(pixels[index + 3])
                guard alpha >= 128 else { continue }
                let (h, s, v) = hsv(Double(pixels[index]) / alpha, Double(pixels[index + 1]) / alpha, Double(pixels[index + 2]) / alpha)
                guard v >= 0.2 else { continue }
                seen.append(Seen(h: h, s: s, v: v, x: Double((index / 4) % width), y: Double((index / 4) / width)))
            }
            return seen
        }
        let seen = colours(image)
        var windows: [RecolorRule] = []
        var left = seen.filter { $0.s >= 0.25 }
        for _ in 0..<2 where !left.isEmpty {
            var hues = [Double](repeating: 0, count: 36)
            for each in left { hues[min(35, Int(each.h / 10))] += 1 }
            let smoothed = (0..<36).map { bin in (-2...2).reduce(0.0) { $0 + hues[(bin + $1 + 36) % 36] } }
            let peak = smoothed.indices.max { smoothed[$0] < smoothed[$1] } ?? 0
            let middle = Double(peak) * 10 + 5
            windows.append(RecolorRule(hue: [(middle - 40 + 360).truncatingRemainder(dividingBy: 360), (middle + 40).truncatingRemainder(dividingBy: 360)],
                                       minSaturation: 0.25, maxSaturation: nil, minValue: 0.2, maxValue: nil,
                                       to: nil, shift: nil, spread: nil, saturation: nil, value: nil))
            left = left.filter { abs(($0.h - middle + 540).truncatingRemainder(dividingBy: 360) - 180) > 40 }
        }
        windows.append(RecolorRule(hue: nil, minSaturation: 0.02, maxSaturation: 0.25, minValue: 0.2, maxValue: nil,
                                   to: nil, shift: nil, spread: nil, saturation: nil, value: nil))
        // Each colour in the first family whose window it falls in, as `apply` will take it.
        func families(_ seen: [Seen]) -> [[Seen]] {
            var found = [[Seen]](repeating: [], count: windows.count)
            for each in seen {
                if let at = windows.firstIndex(where: { $0.matches(hue: each.h, saturation: each.s, value: each.v) }) { found[at].append(each) }
            }
            return found
        }
        let own = families(seen)
        // A metal's tinted greys and its faintly blue shading are one material: a coloured family that's
        // barely coloured (its middle saturation under 0.45) and of the greys' own hue goes with them.
        let grey = windows.count - 1
        var group = Array(windows.indices)
        let tinted = own[grey].filter { $0.s >= 0.05 }
        if !tinted.isEmpty {
            let y = tinted.reduce(0.0) { $0 + sin($1.h * .pi / 180) }, x = tinted.reduce(0.0) { $0 + cos($1.h * .pi / 180) }
            let greyHue = (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
            for at in 0..<grey where !own[at].isEmpty {
                let middle = own[at].map(\.s).sorted()[own[at].count / 2]
                if middle < 0.45, windows[at].matches(hue: greyHue, saturation: 0.5, value: 0.5) { group[at] = grey }
            }
        }
        func members(_ found: [[Seen]], _ of: Int) -> [Seen] {
            windows.indices.filter { group[$0] == of }.flatMap { found[$0] }
        }
        let least = max(12, 0.04 * Double(seen.count))
        // The biggest first (the first found of two the same size).
        let ranked = windows.indices.filter { group[$0] == $0 && Double(members(own, $0).count) >= least }
            .sorted { (members(own, $0).count, -$0) > (members(own, $1).count, -$1) }
        guard var mainAt = ranked.first else { return [] }
        var trimAt = ranked.count > 1 ? ranked[1] : nil
        func tip(_ of: Int) -> Double {
            let all = members(own, of)
            return all.reduce(0) { $0 + $1.x - $1.y } / Double(all.count)
        }
        if weapon, let other = trimAt, tip(other) > tip(mainAt) {
            trimAt = mainAt
            mainAt = other
        }
        let measured = target.map { families(colours($0)) } ?? own
        return windows.indices.map { at -> RecolorRule in
            let of = group[at]
            guard let dye = of == mainAt ? main : of == trimAt ? trim : nil else { return windows[at] }
            let found = members(measured, of)
            let all = found.isEmpty ? members(own, of) : found
            let s = all.map(\.s).sorted(), v = all.map(\.v).sorted()
            let window = windows[at]
            // Its lightest is its very lightest: a picture's few highlights would clip to white.
            return dye.rule(onto: DyeMaterial(hue: window.hue, minSaturation: window.minSaturation ?? 0, maxSaturation: window.maxSaturation,
                                              minValue: window.minValue, saturation: max(0.02, s[s.count / 2]), value: v[v.count / 2],
                                              light: v[v.count - 1]))
        }
    }

    nonisolated private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.sorted()[values.count / 2]
    }

    /// A hex colour's difference from the grey of the same brightness.
    nonisolated private static func offset(_ hex: String?) -> (r: Double, g: Double, b: Double) {
        guard let hex, let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) else { return (0, 0, 0) }
        let r = Double((value >> 16) & 255) / 255, g = Double((value >> 8) & 255) / 255, b = Double(value & 255) / 255
        let grey = 0.299 * r + 0.587 * g + 0.114 * b
        return (r - grey, g - grey, b - grey)
    }

    nonisolated private static func hsv(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let maximum = max(r, g, b), minimum = min(r, g, b), delta = maximum - minimum
        var hue = 0.0
        if delta > 0 {
            if maximum == r { hue = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
            else if maximum == g { hue = 60 * ((b - r) / delta + 2) }
            else { hue = 60 * ((r - g) / delta + 4) }
        }
        if hue < 0 { hue += 360 }
        return (hue, maximum == 0 ? 0 : delta / maximum, maximum)
    }

    nonisolated private static func rgb(_ h: Double, _ s: Double, _ v: Double) -> (Double, Double, Double) {
        let c = v * s, x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1)), m = v - c
        let (r, g, b): (Double, Double, Double) = switch h {
        case ..<60: (c, x, 0)
        case ..<120: (x, c, 0)
        case ..<180: (0, c, x)
        case ..<240: (0, x, c)
        case ..<300: (x, 0, c)
        default: (c, 0, x)
        }
        return (r + m, g + m, b + m)
    }
}
