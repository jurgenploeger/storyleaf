import UIKit

/// The app icon for the festive season that's on (rewards.json `seasons`, `GameSession.season`):
/// Halloween's, Christmas's or Easter's while it runs, the usual one the rest of the year. Each is an
/// alternate icon in the asset catalog (AppIcon-<Season>, drawn by tools/season_icon_art.py; listed in
/// project.yml's ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES). iOS tells the player whenever the icon
/// changes, so it's only asked when the icon is wrong, and never in tests or debug launches, where that
/// notice would sit over the screenshots.
enum SeasonalIcon {
    /// The alternate icon of each season that has one; the others (the New Year's party) keep the usual.
    private static let icons = ["halloween": "AppIcon-Halloween", "christmas": "AppIcon-Christmas", "easter": "AppIcon-Easter"]

    static func update(on date: Date = GameSession.today) {
        let environment = ProcessInfo.processInfo.environment
        guard environment["XCTestConfigurationFilePath"] == nil, (environment["STORYLEAF_DEBUG"] ?? "").isEmpty else { return }
        let app = UIApplication.shared
        guard app.supportsAlternateIcons, app.applicationState == .active else { return }
        let wanted = GameSession.season(on: date).flatMap { icons[$0.season.id] }
        guard app.alternateIconName != wanted else { return }
        app.setAlternateIconName(wanted) { _ in }
    }
}
