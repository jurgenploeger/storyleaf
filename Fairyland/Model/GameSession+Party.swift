import CoreGraphics
import Foundation

/// Partying up with the computer-run adventurers as with Fairyland's other players (playtesting
/// 2026-10-16): they don't always say yes, you can join a party of theirs as they can join yours, and
/// after a while they head off on their own.
extension GameSession {
    /// A party of adventurers you've joined (`askToJoin`): everyone in it, whoever leads first. You
    /// walk behind them and they fight beside you, till they head off (`joinedStay`) or you walk off.
    struct JoinedParty: Equatable {
        var members: [Adventurer]
        var leader: Adventurer? { members.first }
    }

    /// What an adventurer says when you ask them to party up, and whether it's yes.
    struct PartyReply: Equatable {
        let accepted: Bool
        let line: String
    }

    /// Why you're no longer in the party you'd joined: you walked off or chose to leave, they headed
    /// off on their own, or they're nowhere about any more (you went somewhere else).
    enum PartyEnd { case wandered, headedOff, gone }

    /// How far apart in level you can be before an adventurer would mostly rather not party up.
    static let partyLevelGap = 20
    /// How long someone who said no keeps saying it, in seconds.
    static let declineFor: TimeInterval = 180
    /// How far from whoever leads the party you've joined you can walk before you've left it, in points.
    static let joinedReach: CGFloat = 420

    /// Debug launches (`stay=s`): how long anyone stays in a party, in seconds, in place of crowd.json's.
    static var stayOverride: TimeInterval?

    /// Everyone who fights beside you: the friends at your side, then the party you've joined.
    var fightersAtYourSide: [Adventurer] {
        Array((friendsAtYourSide + (joinedParty?.members ?? [])).prefix(Self.maxAllies))
    }

    /// Whether there's no room for anyone more: the friends in your party and the party you've joined
    /// fill it (`maxAllies`).
    var partyIsFull: Bool { partyMembers.count + (joinedParty?.members.count ?? 0) >= Self.maxAllies }

    /// Whether `adventurer` is in the party you've joined.
    func isInJoinedParty(_ adventurer: Adventurer) -> Bool {
        joinedParty?.members.contains { $0.id == adventurer.id } == true
    }

    /// How long someone stays in a party before heading off, in seconds of play (crowd.json
    /// `stayMinutes`).
    func stayLength() -> TimeInterval {
        if let override = Self.stayOverride { return override }
        let minutes = content.crowd.stayMinutes ?? [15, 40]
        let low = minutes.first ?? 15
        return Double.random(in: low...max(low, minutes.last ?? low)) * 60
    }

    /// Whether `adventurer` says yes to partying up, at `chance` (crowd.json `acceptChance`, less
    /// for some reason of theirs): never while they've just said no, and far less often with you far
    /// apart in level. After a no, they say no again for a while (`declineFor`). `roll`: the dice,
    /// 0 to 1.
    private func agrees(_ adventurer: Adventurer, chance: Double, roll: Double, now: Date) -> Bool {
        if let until = declinedUntil[adventurer.id], until > now { return false }
        if roll < chance * (isFarApart(adventurer) ? 0.25 : 1) { return true }
        declinedUntil[adventurer.id] = now.addingTimeInterval(Self.declineFor)
        return false
    }

    private func isFarApart(_ adventurer: Adventurer) -> Bool {
        abs(adventurer.level - data.hero.level) > Self.partyLevelGap
    }

    private var acceptChance: Double { content.crowd.acceptChance ?? 0.75 }

    /// Asks a friend to join your party (from their card, or the Friends list): they join
    /// (`invite`), or say no. Travelling with friends of their own (`busy`), they're half as keen.
    @discardableResult
    func askAlong(_ id: UUID, busy: Bool = false, roll: Double = .random(in: 0..<1), now: Date = Date()) -> PartyReply? {
        guard let friend = friends.first(where: { $0.id == id }), !isInParty(friend), !partyIsFull,
              adventurersAround.contains(id) else { return nil }
        let again = (declinedUntil[id] ?? .distantPast) > now
        guard agrees(friend, chance: acceptChance * (busy ? 0.5 : 1), roll: roll, now: now) else {
            post(L("{name} turned down your invite.", ["name": friend.name]))
            let line: String
            if again {
                line = L("Still no, sorry!")
            } else if isFarApart(friend) {
                line = L("We're too far apart in level, sorry!")
            } else if busy {
                line = L("I'm with my party right now. Another time!")
            } else {
                line = [L("Maybe another time!"), L("Not right now, thanks!"), L("Sorry, I'm about to head off!")].randomElement() ?? L("Maybe another time!")
            }
            return PartyReply(accepted: false, line: line)
        }
        invite(id)
        return PartyReply(accepted: true, line: [L("Sure, let's go!"), L("Count me in!"), L("Let's adventure together!")].randomElement() ?? L("Sure, let's go!"))
    }

    /// Asks the adventurers travelling together as `group` (whoever leads first) to let you join
    /// them. Whoever leads answers: no without room for you and your party's friends as well
    /// (`maxAllies` in all), else as a friend you invite would (`agrees`). Yes, and you're in their
    /// party: you follow them about and they fight beside you, till they head off on their own
    /// (`stayLength`) or you walk off (`leaveJoinedParty`).
    @discardableResult
    func askToJoin(_ group: [Adventurer], roll: Double = .random(in: 0..<1), now: Date = Date()) -> PartyReply? {
        guard joinedParty == nil, group.count > 1, let leader = group.first, !group.contains(where: \.hostile) else { return nil }
        if partyMembers.count + group.count > Self.maxAllies {
            post(L("{name} turned down your request.", ["name": leader.name]))
            return PartyReply(accepted: false, line: L("Sorry, our party's full!"))
        }
        let again = (declinedUntil[leader.id] ?? .distantPast) > now
        guard agrees(leader, chance: acceptChance, roll: roll, now: now) else {
            post(L("{name} turned down your request.", ["name": leader.name]))
            let line: String
            if again {
                line = L("Still no, sorry!")
            } else if isFarApart(leader) {
                line = L("We're too far apart in level, sorry!")
            } else {
                line = [L("We're fine on our own for now, thanks!"), L("Maybe another time!")].randomElement() ?? L("Maybe another time!")
            }
            return PartyReply(accepted: false, line: line)
        }
        joinedParty = JoinedParty(members: group)
        joinedStay = stayLength()
        post(L("You joined {name}'s party!", ["name": leader.name]), .reward)
        return PartyReply(accepted: true, line: [L("Sure, come along!"), L("Welcome aboard!"), L("The more the merrier!")].randomElement() ?? L("Sure, come along!"))
    }

    /// Leaves the party you'd joined (`PartyEnd` says why), and says so. Returns who led it.
    @discardableResult
    func leaveJoinedParty(_ why: PartyEnd) -> Adventurer? {
        let leader = joinedParty?.leader
        joinedParty = nil
        guard let leader else { return nil }
        switch why {
        case .headedOff:
            post(L("{name}'s party heads off on its own. You're on your own again.", ["name": leader.name]))
            declinedUntil[leader.id] = Date().addingTimeInterval(Self.declineFor)
        case .wandered, .gone:
            post(L("You left {name}'s party.", ["name": leader.name]))
        }
        return leader
    }

    /// Time played together: each friend at your side, and the party you've joined, stays a while
    /// (`stayLength`), then heads off on their own. A friend who leaves stays a friend, and won't
    /// come along again straight away. Returns who just left your party, and who led the party you'd
    /// joined if it just headed off, for the scene to have them say goodbye.
    func passPartyTime(_ seconds: TimeInterval) -> (left: [Adventurer], headedOff: Adventurer?) {
        var left: [Adventurer] = []
        for friend in friendsAtYourSide {
            let stay = (partyStays[friend.id] ?? stayLength()) - seconds
            partyStays[friend.id] = stay
            if stay <= 0 { left.append(friend) }
        }
        for friend in left {
            leaveParty(friend.id)
            declinedUntil[friend.id] = Date().addingTimeInterval(Self.declineFor)
        }
        var headedOff: Adventurer?
        if joinedParty != nil {
            joinedStay -= seconds
            if joinedStay <= 0 { headedOff = leaveJoinedParty(.headedOff) }
        }
        return (left, headedOff)
    }

    /// What someone says as they head off on their own after a while together.
    static var goodbyes: [String] {
        [L("I have to head off now. Thanks for the adventure!"), L("That's me for today. See you around!"),
         L("Time for me to go my own way. Take care!")]
    }
}
