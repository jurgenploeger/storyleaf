import Foundation

/// Where your friends are while they're not with you (playtesting 2026-10-31: "You should be able to
/// see if your friends are online and where they are"). Each is online for spells of `friendSpell`,
/// about one in two, and away for the rest; online, they're in a land that suits their level, among
/// those you've been to, as a crowd takes them in. Worked out from the clock, the same each time it's
/// asked, so a land's crowd brings in the friends who are there (`friendsIn`) and the Friends list
/// says where to find them.
extension GameSession {
    enum FriendStatus: Equatable {
        case offline
        case online(mapID: String)
    }

    /// How long a friend stays online, or away, at a time.
    static let friendSpell: TimeInterval = 50 * 60
    /// How likely a friend is to be online in any spell.
    static let friendOnlineChance = 0.5

    /// Whether a friend is online and in which land: with you if they're in your party (or where
    /// they wait for you), else as their spell has it.
    func status(of friend: Adventurer, at date: Date = Date()) -> FriendStatus {
        if isInParty(friend) { return .online(mapID: friend.waitingAt?.mapID ?? data.mapID) }
        let spell = Int((date.timeIntervalSince1970 / Self.friendSpell).rounded(.down))
        var rng = SeededRandom(text: "friend/" + friend.id.uuidString + "/" + String(spell))
        guard Double.random(in: 0..<1, using: &rng) < Self.friendOnlineChance,
              let land = friendLands(for: friend.level).randomElement(using: &rng) else { return .offline }
        return .online(mapID: land)
    }

    /// Your friends in a land now, not in your party: its crowd brings them in.
    func friendsIn(_ mapID: String) -> [Adventurer] {
        friends.filter { !isInParty($0) && status(of: $0) == .online(mapID: mapID) }
    }

    /// The lands a friend of `level` roams, as a crowd takes them in (`Crowd`): any town, or out in
    /// the wild where the monsters suit them; only those you've been to with adventurers about.
    private func friendLands(for level: Int) -> [String] {
        content.maps.filter { def in
            guard (def.crowd?.adventurers ?? 0) > 0, hasVisited(def.id) else { return false }
            if def.fence == true { return true }
            guard let levels = def.encounters?.levels, let low = levels.first, let high = levels.last else { return false }
            return ((low - 10)...(high + 13)).contains(level)
        }.map { $0.id }
    }
}
