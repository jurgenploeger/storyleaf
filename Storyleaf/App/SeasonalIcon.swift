import UIKit

/// The app icon for the festive time of year: Halloween's all October and Christmas's all December (the
/// user's call, 2026-10-25: whole months, whatever the in-game seasons' own dates), Easter's while its
/// season runs (rewards.json `seasons`, `GameSession.season`), the usual one the rest of the year. Each is an
/// alternate icon in the asset catalog (AppIcon-<Season>, drawn by tools/season_icon_art.py; listed in
/// project.yml's ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES). iOS tells the player whenever the icon
/// changes, so it's only asked when the icon is wrong, and never in tests or debug launches, where that
/// notice would sit over the screenshots.
enum SeasonalIcon {
    /// The icon for `date`: October's and December's by the month, Easter's by its season (it moves
    /// every year); nil for the usual one (the New Year's party has none of its own).
    static func icon(on date: Date) -> String? {
        switch Calendar(identifier: .gregorian).component(.month, from: date) {
        case 10: return "AppIcon-Halloween"
        case 12: return "AppIcon-Christmas"
        default: return GameSession.season(on: date)?.season.id == "easter" ? "AppIcon-Easter" : nil
        }
    }

    static func update(on date: Date = GameSession.today) {
        let environment = ProcessInfo.processInfo.environment
        guard environment["XCTestConfigurationFilePath"] == nil, (environment["STORYLEAF_DEBUG"] ?? "").isEmpty else { return }
        let app = UIApplication.shared
        guard app.supportsAlternateIcons, app.applicationState == .active else { return }
        let wanted = icon(on: date)
        guard app.alternateIconName != wanted else { return }
        app.setAlternateIconName(wanted) { _ in }
    }
}
