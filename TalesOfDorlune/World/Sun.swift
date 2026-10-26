import Foundation

/// Where the light over a map comes from at an hour of the day (`Sky.sun`): the sun by day, rising in
/// the east (up the screen), over the upper left at midday (where the art's own light comes from)
/// and setting in the west (behind you, to the left); the moon by night along the same path,
/// fainter. Low in the morning and evening, so shadows stretch long, highest at midday. As it
/// rises and sets, the light turns soft and comes from overhead, so nothing jumps when the sun
/// gives way to the moon. Hills are shaded by it (`HillArt`), and scenery casts its shadows away
/// from it (`Lighting.Shadow`).
struct Sun: Equatable {
    /// Toward the light, unit length: `x` east (across the map), `y` north (up it), `z` up.
    let x, y, z: Double
    /// How strongly it shades and casts shadows: 1 by sunlight, less by moonlight.
    let strength: Double

    /// Midday: from the upper left of the screen (up the map and to the left), 36° up.
    static let noon = Sun(hour: 12)

    /// The hour of the day, 0 to 24.
    init(hour: Double) {
        let hour = (hour.truncatingRemainder(dividingBy: 24) + 24).truncatingRemainder(dividingBy: 24)
        let day = hour >= 6 && hour < 18
        // How far across the sky: 0 rising, 0.5 at the top, 1 setting.
        let across = (day ? hour - 6 : (hour - 18 + 24).truncatingRemainder(dividingBy: 24)) / 12
        let arc = sin(Double.pi * across)
        // A half turn from east-north-east to west-south-west, through where the art's light is at midday.
        let turn = atan2(1.0, -0.6) + (across - 0.5) * Double.pi
        let up = max(8, 36 * arc) * Double.pi / 180
        // Soft light from overhead as it rises and sets, all its own an hour on.
        let own = min(1, arc / sin(Double.pi / 12))
        let toward = (x: cos(turn) * cos(up) * own, y: sin(turn) * cos(up) * own, z: sin(up) * own + 1 - own)
        let length = (toward.x * toward.x + toward.y * toward.y + toward.z * toward.z).squareRoot()
        x = toward.x / length
        y = toward.y / length
        z = toward.z / length
        strength = day ? 1 : 0.6
    }

    /// Which way it is on screen, as an angle (0 to the right, π/2 straight up): its direction on the
    /// map as `WorldMap.project` draws it, and up the screen as high as it is.
    var angleOnScreen: Double {
        atan2(0.35355339 * (x + y) + 0.8660254 * z, 0.70710678 * (x - y))
    }

    /// How dark a slope facing away from the sun is next to the flat, `ambient` how lit it still is
    /// then at midday (`HillArt.Look.ambient`). The same at every hour: the sky's light fades with
    /// the sun's.
    static func shaded(ambient: Double) -> Double {
        ambient / (ambient + (1 - ambient) * noon.z)
    }
}
