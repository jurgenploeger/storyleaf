import Foundation

/// Fairyland Online's calendar ("1001/Fire/12/13hr"): by day an in-game hour passes every real minute,
/// and each 60-day month belongs to one of the five elements. Night (18hr to 6hr) runs at
/// `nightPace`, so it's over in eight real minutes rather than twelve.
enum GameClock {
    static let months: [Element] = [.metal, .wood, .water, .fire, .earth]
    /// In-game hours that pass in a real minute at night.
    static let nightPace = 1.5
    /// Real minutes in an in-game day: twelve of daylight, then the night at its pace.
    static let dayMinutes = 12 + 12 / nightPace

    struct Moment {
        let year: Int
        let month: Element
        let day: Int
        let hour: Int

        var isDaytime: Bool { (6..<18).contains(hour) }
        var text: String { L("{year}/{month}/{day}/{hour}hr", ["year": year, "month": month.displayName, "day": day, "hour": hour]) }
    }

    static func moment(at date: Date = Date(), since start: Date?) -> Moment {
        let hours = Int(self.hours(at: date, since: start))
        let days = hours / 24
        return Moment(year: 1001 + days / 300, month: months[(days / 60) % months.count], day: days % 60 + 1, hour: hours % 24)
    }

    /// In-game hours since the calendar began, with the minutes as a fraction (for light that
    /// changes smoothly through the day). The hour of the day is this modulo 24.
    static func hours(at date: Date = Date(), since start: Date?) -> Double {
        let origin = start ?? Date(timeIntervalSince1970: 1_790_000_000)
        // A new game opens mid-morning on day one, 9hr: three daylight minutes after dawn.
        let sinceDawn = max(0, date.timeIntervalSince(origin) / 60) + 3
        let days = (sinceDawn / dayMinutes).rounded(.down)
        let into = sinceDawn - days * dayMinutes
        return days * 24 + (into < 12 ? 6 + into : 18 + (into - 12) * nightPace)
    }

    /// Real minutes from a new game's 9hr until the clock first reads `hour` (0-23), for debug
    /// launches that start at a given time of day.
    static func minutes(untilHour hour: Int) -> Double {
        let sinceDawn = Double((hour - 6 + 24) % 24)
        let real = sinceDawn <= 12 ? sinceDawn : 12 + (sinceDawn - 12) / nightPace
        return (real - 3 + dayMinutes).truncatingRemainder(dividingBy: dayMinutes)
    }
}
