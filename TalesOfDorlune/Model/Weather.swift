import Foundation

/// The weather on a map: picked from the map's `ambience.weather` weights in content/maps.json,
/// and changing every `spell` in-game hours (six real minutes by day, four at night). Rain and
/// storms blow over in about a real minute and leave the rest of their spell grey. The same save on
/// the same map at the same hour always gets the same weather, so walking off and back doesn't
/// reroll it. `Sky` draws it, with the light of the time of day.
enum Weather: String, CaseIterable {
    case clear, cloudy, rain, storm, fog, snow

    /// In-game hours each spell of weather lasts.
    static let spell = 6
    /// Where a map doesn't say: mostly clear, sometimes cloudy, rainy or foggy.
    static let usual: [String: Double] = ["clear": 6, "cloudy": 2, "rain": 2, "fog": 1]

    /// Debug launches (`weather=rain`) set this to have it everywhere there's a sky.
    static var forced: Weather?

    /// The weather on `map` at `date`, or nil on a map with no sky (a cave, or `weather: {}`).
    /// With the weather switched off in Settings (`changing` false), it's always clear.
    static func on(_ map: MapDef, at date: Date = Date(), since start: Date?, changing: Bool = GameSettings.weather) -> Weather? {
        guard map.ambience?.darkness == nil, map.ambience?.weather?.isEmpty != true else { return nil }
        if let forced { return forced }
        guard changing else { return .clear }
        let weights = (map.ambience?.weather ?? usual)
            .compactMap { entry in Weather(rawValue: entry.key).map { ($0, entry.value) } }
            .filter { $0.1 > 0 }
            .sorted { $0.0.rawValue < $1.0.rawValue }
        let total = weights.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return nil }
        let hours = GameClock.hours(at: date, since: start)
        let slot = Int(hours) / spell
        var rng = SeededRandom(text: "\(map.id)/weather/\(slot)")
        var roll = Double.random(in: 0..<total, using: &rng)
        var weather = weights.last?.0
        for (kind, weight) in weights {
            roll -= weight
            if roll < 0 {
                weather = kind
                break
            }
        }
        // A shower passes in a real minute: an in-game hour by day, `nightPace` hours at night (a
        // spell starts at 0, 6, 12 or 18hr, so it's all day or all night). Then it stays grey.
        if weather == .rain || weather == .storm {
            let begun = Double(slot * spell)
            let shower = (6..<18).contains(Int(begun) % 24) ? 1 : GameClock.nightPace
            if hours - begun >= shower { return .cloudy }
        }
        return weather
    }

    /// How much the clouds dim the light (multiplied into the time of day's colour).
    var shade: (r: Double, g: Double, b: Double) {
        switch self {
        case .clear: (1, 1, 1)
        case .cloudy: (0.88, 0.89, 0.92)
        case .rain: (0.76, 0.79, 0.86)
        case .storm: (0.6, 0.63, 0.72)
        case .fog: (0.93, 0.94, 0.96)
        case .snow: (0.9, 0.92, 0.97)
        }
    }

    /// Whether the sun's flare and sunbeams still shine through.
    var sunny: Bool { self == .clear }
}
