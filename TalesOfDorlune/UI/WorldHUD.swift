import SwiftUI

/// On-map HUD in Fairyland Online's style: your round face with HP, MP and XP, your companion's
/// small face on its corner, and your party top-left (the date is on the map, `MapOverlay`), a framed minimap top-right with what
/// just happened toasting under it, joystick bottom-left, and Chat and the menu bottom-right (one
/// button that opens into the menu's pages). While you're talking to someone (or any window is open
/// over the map) the controls step aside, so nothing peeks out from behind the conversation.
struct WorldHUD: View {
    let coordinator: GameCoordinator
    /// The menu button opened into its list of pages (`GameMenu`).
    @State private var menuOpen = DebugLaunch.opensHUDMenu
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var bottomGap: (joystick: CGFloat, buttons: CGFloat) { (joystick: onItsSide ? 8 : 10, buttons: HUDMargins.bottom(onItsSide: onItsSide)) }
    /// On a phone on its side the bottom controls sit down in the home indicator's strip, a few
    /// points off the screen's edge (playtesting 2026-10-16: "should sit lower"): the indicator hides
    /// itself and a swipe there moves the joystick first (`GameView`). Upright, they keep over it.
    private var onItsSide: Bool { verticalSizeClass == .compact }
    /// How tall the faces (and a joined party's plate) are, and the minimap, measured: upright, the
    /// toasts go below whichever reaches lower (playtesting 2026-10-26: a long toast ran under the
    /// minimap).
    @State private var facesHeight: CGFloat = 0
    @State private var minimapHeight: CGFloat = 0
    private var toastGap: CGFloat {
        onItsSide ? 10 : max(10, minimapHeight + 8 - facesHeight - 6)
    }
    private var bottomEdge: SwiftUI.Edge.Set { HUDMargins.bottomEdge(onItsSide: onItsSide) }

    private var session: GameSession { coordinator.session }
    private var controlsHidden: Bool { coordinator.overlay != nil }
    /// In a party you've joined it leads you: the joystick and what you'd walk up to (someone to
    /// talk to, your things, an adventurer) step aside till you leave it.
    private var following: Bool { session.joinedParty != nil }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 6) {
                    // The faces open their stats, and the party folds and unfolds; the rest lets taps
                    // through to the map.
                    StatusCluster(session: session, onInspect: { coordinator.open(.profile($0)) })
                        .coachTarget(.status)
                    // The party you've joined: whose it is, and a way out of it.
                    if let joined = session.joinedParty, let leader = joined.leader {
                        JoinedPartyPlate(leader: leader, count: joined.members.count) { coordinator.leaveJoinedParty() }
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { facesHeight = $0 }
                // What just happened, top centre under the panels on both sides (walking into a land
                // too: its toast, no banner of its own; playtesting 2026-10-24).
                // The autosave's "Saved" under them, in the same style.
                VStack(spacing: 4) {
                    GameToasts(lines: session.log)
                    SavedBadge(lastSaved: session.lastSaved)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, toastGap)
                .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            VStack(alignment: .trailing, spacing: 6) {
                let minimap = coordinator.minimap(explored: session.exploredVersion, overviews: WorldOverview.shared.images.count)
                MinimapWindow(
                    picture: minimap.picture,
                    cell: session.mapCell,
                    dots: session.minimapDots,
                    marks: session.minimapMarks,
                    onOpen: { coordinator.open(.worldMap) }
                )
                .coachTarget(.minimap)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { minimapHeight = $0 }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            // While the menu's open, a tap anywhere else closes it.
            if menuOpen {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { menuOpen = false }
            }

            JoystickView(input: coordinator.input)
                .coachTarget(.joystick)
                .stepsAside(controlsHidden || following)
                // As far in from the edge as every other control (the HUD's own 8 points; playtesting
                // 2026-10-17: it sat twice as far in as the toolbar opposite).
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.bottom, bottomGap.joystick)
                .ignoresSafeArea(.container, edges: bottomEdge)

            VStack(alignment: .trailing, spacing: 10) {
                if let id = session.nearbyNPC, let npc = Content.shared.npc(id) {
                    Button {
                        coordinator.talkToNearby()
                    } label: {
                        if npc.role == .chest {
                            Label(L("Open {name}", ["name": npc.name]), icon: .gift)
                        } else if npc.role == .waystone {
                            Label(L("Touch the waystone"), icon: .sparkles)
                        } else if npc.role == .stairs {
                            if Content.shared.leadsDown(npc) {
                                Label(L("Go down"), icon: .arrowDown)
                            } else {
                                Label(L("Go up"), icon: .arrowUp)
                            }
                        } else {
                            Label(L("Talk to {name}", ["name": npc.name]), icon: .talk)
                        }
                    }
                    .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold))
                    .transition(.scale(scale: 0.7, anchor: .bottomTrailing).combined(with: .opacity))
                    .stepsAside(controlsHidden || following)
                } else if session.nearbyPile != nil {
                    // What you lost when you fell, lying here (`LostPile`).
                    Button {
                        coordinator.pickUpPile()
                    } label: {
                        Label(L("Pick up your things"), icon: .backpack)
                    }
                    .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold))
                    .transition(.scale(scale: 0.7, anchor: .bottomTrailing).combined(with: .opacity))
                    .stepsAside(controlsHidden || following)
                } else if let adventurer = session.nearbyAdventurer {
                    AdventurerCard(coordinator: coordinator, adventurer: adventurer)
                        .transition(.scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity))
                        .stepsAside(controlsHidden || following)
                }
                // Chat, then the menu: one button that opens into its pages (playtesting 2026-10-24:
                // a row of four buttons, Chat and Settings up by the minimap), each a window of its own
                // (2026-10-25), Friends too.
                HStack(alignment: .bottom, spacing: 7) {
                    // The Bag a tap away, left of Chat (playtesting 2026-10-26: "Put an inventory button
                    // on the left of chat, so it's easier accessable"): its window opens as from the menu.
                    FLIconButton(icon: MenuTab.bag.icon, label: MenuTab.bag.menuTitle, badge: badge(for: .bag)) {
                        menuOpen = false
                        coordinator.open(.menu(.bag))
                    }
                    .stepsAside(controlsHidden)
                    FLIconButton(icon: .talk, label: L("Chat"), badge: session.unreadChat > 0) {
                        menuOpen = false
                        coordinator.open(.chat)
                    }
                    .coachTarget(.chat)
                    .stepsAside(controlsHidden)
                    // A window chosen from it just opens, the menu closing behind it: closing the window
                    // closes everything (playtesting 2026-10-26). The Bag isn't in it: it has its own
                    // button, left of Chat (playtesting 2026-10-26).
                    GameMenu(items: [.character, .companions, .friends, .quests, .settings], open: $menuOpen,
                             badge: { badge(for: $0) }) { tab in
                        menuOpen = false
                        coordinator.open(.menu(tab))
                    }
                    .coachTarget(.toolbar)
                    .stepsAside(controlsHidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.bottom, bottomGap.buttons)
            .ignoresSafeArea(.container, edges: bottomEdge)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: session.nearbyNPC)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: session.nearbyAdventurer?.id)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: session.nearbyPile)
        }
        .padding(.horizontal, HUDMargins.side)
        .padding(.top, 4)
        .onChange(of: controlsHidden) { if controlsHidden { menuOpen = false } }
    }

    private func badge(for tab: MenuTab) -> Bool {
        switch tab {
        case .character: session.canChooseClass || session.canSpendSkillPoint || session.hasGearUpgrade
        case .quests: session.activeQuests.contains { session.status(of: $0) == .ready }
        case .bag: session.count(of: "pet_egg") > 0
        case .companions, .friends, .settings: false
        }
    }
}

/// The top-left column's width: every panel in it as wide as the next (playtesting 2026-10-18), and
/// clear of the minimap on the narrowest phones. A party folded into one row just fits.
private enum TopLeft {
    static let width: CGFloat = 214
}

/// Fairyland Online's top-left faces: you in a big round frame with your level, HP, MP and XP; your companion's
/// face small on its bottom-right corner, a button of its own (2026-10-26: one stats block, yours); and the friends in your party, smaller. Once two or more friends travel
/// with you, they fold into one row of small faces under yours so they don't cover the map: tap the row to see
/// everyone in full, and the arrow by the last friend to fold them again. Your face or your stats open the Hero
/// window, your companion's face the Companions window (`GameCoordinator.open`), a friend's face their card.
private struct StatusCluster: View {
    let session: GameSession
    let onInspect: (Profile) -> Void
    @AppStorage(GameSettings.partyFoldedKey) private var folded = true

    var body: some View {
        let hero = session.data.hero
        let stats = session.heroStats
        // A companion that has fainted isn't shown on your face (playtesting 2026-10-26).
        let pet = session.activePet.flatMap { $0.hp > 0 ? $0 : nil }
        let friends = session.partyMembers
        let crowded = friends.count >= 2
        VStack(alignment: .leading, spacing: 4) {
            Button { onInspect(.hero) } label: {
                PortraitRow(face: ArtLibrary.shared.face(GameSession.heroArt), level: hero.level, name: hero.name,
                            detail: session.heroClass.name, size: HeroFace.size,
                            glowing: session.canChooseClass || session.canSpendSkillPoint) {
                    TaggedBar(tag: L("HP"), value: hero.hp, maximum: stats.hp, color: HUDStyle.hp)
                    TaggedBar(tag: L("MP"), value: hero.mp, maximum: stats.mp, color: HUDStyle.mp)
                    // XP to the next level under the bars, as tall as they are (playtesting 2026-10-24:
                    // it had a row of its own under the calendar; 2026-10-26: no thinner).
                    ExpBar(value: hero.exp, maximum: GameSession.expToNext(level: hero.level))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("{name}, level {level}: stats", ["name": hero.name, "level": hero.level]))
            // Your companion's face over the corner of yours, a button of its own laid over your row so
            // it takes its taps first. Your portrait is a square as tall as the row (`PortraitBeside`).
            .overlay(alignment: .topLeading) {
                if let pet {
                    GeometryReader { proxy in
                        let side = proxy.size.height
                        CompanionBadgeButton(session: session, pet: pet) { onInspect(.pet(pet.id)) }
                            .position(x: side - CompanionBadge.inset, y: side - CompanionBadge.inset)
                    }
                }
            }
            // Room under your row for the rest of the badge's tap area, clear of whatever comes next.
            .padding(.bottom, pet == nil ? 0 : CompanionBadge.overhang)
            if crowded && folded {
                FoldedParty(session: session, friends: friends) { setFolded(false) }
                    .transition(.opacity)
            } else {
                ForEach(friends) { friend in
                    // A friend waiting somewhere for you to come back for them is greyed out.
                    let away = session.whereabouts(of: friend)
                    let statsLabel = away.map { L("{name}, level {level}, waiting at {map}: stats", ["name": friend.name, "level": friend.level, "map": $0]) } ?? L("{name}, level {level}: stats", ["name": friend.name, "level": friend.level])
                    HStack(spacing: 4) {
                        Button { onInspect(.adventurer(friend)) } label: {
                            // With the fold arrow beside it (4 apart, 28 wide), together as wide as the rest.
                            PortraitRow(face: ArtLibrary.shared.face(session.artID(for: friend)), level: friend.level, name: friend.name,
                                        detail: away == nil ? session.content.classDef(friend.classID).name : L("Waiting"), size: 30,
                                        width: TopLeft.width - (crowded && friend.id == friends.last?.id ? 32 : 0)) {
                                EmptyView()
                            }
                            .saturation(away == nil ? 1 : 0)
                            .opacity(away == nil ? 1 : 0.75)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(statsLabel)
                        if crowded && friend.id == friends.last?.id {
                            Button { setFolded(true) } label: { FoldArrow(up: true) }
                                .buttonStyle(.plain)
                                .accessibilityLabel(L("Fold your party into one row"))
                        }
                    }
                }
            }
        }
    }

    private func setFolded(_ value: Bool) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { folded = value }
    }
}

/// Your face in the top-left: bigger than the rest (2026-10-26), at least this tall, taller if your
/// name and bars beside it need more.
private enum HeroFace {
    static let size: CGFloat = 72
}

/// Your companion's face as a button on the corner of yours: its name, level and HP read out, and a
/// tap opens the Companions window.
private struct CompanionBadgeButton: View {
    let session: GameSession
    let pet: Pet
    let open: () -> Void

    var body: some View {
        let stats = session.stats(of: pet)
        Button(action: open) {
            CompanionBadge(face: ArtLibrary.shared.face(session.artID(for: pet)), fainted: pet.hp <= 0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("{name}, level {level}: stats", ["name": pet.name, "level": pet.level]))
        .accessibilityValue(pet.hp > 0 ? L("HP") + " \(pet.hp) / \(stats.hp)" : L("Fainted"))
    }
}

/// Your companion's small round face: a bevelled ring round it and a dark rim outside that, so it
/// reads as a button apart from your face beneath (no HP arc on it: playtesting 2026-10-26; its HP
/// is read out, and in the Companions window). Grey once it has fainted. No level chip, as small as it is: its level is in the Companions window, and read out.
/// Drawn `size` across, tapped anywhere in a circle `target` across (44 points, Apple's least).
private struct CompanionBadge: View {
    let face: UIImage
    let fainted: Bool

    static let size: CGFloat = 30
    static let target: CGFloat = 44
    /// Its middle this far in from your portrait's bottom-right corner (the square's, not the
    /// circle's): it covers the corner of your face and hangs a little past it.
    static let inset: CGFloat = 12
    /// How far its tap area reaches below your row.
    static var overhang: CGFloat { target / 2 - inset }

    var body: some View {
        Image(uiImage: face)
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .padding(Self.size * 0.1)
            .frame(width: Self.size, height: Self.size)
            .background(Circle().fill(RadialGradient(colors: [HUDStyle.portrait, HUDStyle.portraitRim],
                                                     center: UnitPoint(x: 0.4, y: 0.35), startRadius: 1, endRadius: Self.size * 0.7)))
            .clipShape(Circle())
            .saturation(fainted ? 0 : 1)
            .overlay(Circle().strokeBorder(HUDStyle.bevel, lineWidth: 2))
            .background(Circle().fill(HUDStyle.frameDark).padding(-1.5))
            .shadow(color: .black.opacity(0.45), radius: 1.5, y: 1)
            .frame(width: Self.target, height: Self.target)
            .contentShape(Circle())
    }
}

/// A big party folded into one row of small faces under yours: your friends' (grey while they wait
/// somewhere for you). Tap it to see everyone in full.
private struct FoldedParty: View {
    let session: GameSession
    let friends: [Adventurer]
    let unfold: () -> Void

    var body: some View {
        Button(action: unfold) {
            HStack(spacing: 4) {
                ForEach(friends) { friend in
                    Portrait(face: ArtLibrary.shared.face(session.artID(for: friend)), level: friend.level, size: 30)
                        .saturation(friend.waitingAt == nil ? 1 : 0)
                }
                FoldArrow(up: false)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .frame(width: TopLeft.width, alignment: .leading)
            .background(HUDStyle.panel)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("Show your whole party"))
    }
}

/// The little orange arrow on the party's fold: down to unfold it, up to fold it again.
private struct FoldArrow: View {
    let up: Bool

    var body: some View {
        IconImage(up ? .chevronUp : .chevronDown, size: 12)
            .font(.system(size: 9, weight: .black))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(Circle().fill(HUDStyle.orange).overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1)))
            .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
    }
}

/// One face in the top-left: a round portrait with a level chip, then a name and bars on a panel,
/// the portrait as tall as the panel (2026-10-26: "the same height as the block on the right").
private struct PortraitRow<Bars: View>: View {
    let face: UIImage
    let level: Int
    let name: String
    var detail: String? = nil
    /// The portrait's least size: it grows to the panel's height (`PortraitBeside`).
    let size: CGFloat
    var glowing = false
    /// The whole row's width, portrait and panel.
    var width: CGFloat = TopLeft.width
    @ViewBuilder let bars: () -> Bars

    /// A row with no bars, only a name (a friend's).
    private static var nameOnly: Bool { Bars.self == EmptyView.self }

    var body: some View {
        // Top-aligned: the panel's top edge lines up with the portrait's, and so with the
        // minimap's across the screen.
        // A little air between the face and the panel (playtesting 2026-10-26).
        PortraitBeside(width: width, least: size, spacing: 9) {
            GeometryReader { proxy in
                Portrait(face: face, level: level, size: min(proxy.size.width, proxy.size.height), glowing: glowing)
            }
            VStack(alignment: .leading, spacing: 2) {
                // Names and words in the game's rounded letters; only numbers are monospaced
                // (2026-10-26).
                HStack(spacing: 4) {
                    Text(name).font(HUDStyle.font(size > 40 ? 11 : 10)).foregroundStyle(HUDStyle.nameYellow).lineLimit(1)
                    if let detail {
                        Text(detail).font(HUDStyle.font(9)).foregroundStyle(HUDStyle.dim).lineLimit(1)
                    }
                }
                .shadow(color: .black, radius: 0, x: 1, y: 1)
                // The name up at the top, the bars down at the bottom, sharing out any room the
                // portrait leaves (playtesting 2026-10-26: the name sat low, room above it). A friend's
                // row, a name alone, keeps it in the middle.
                if !Self.nameOnly { Spacer(minLength: 0) }
                bars()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Self.nameOnly ? .leading : .topLeading)
            .padding(.horizontal, 7)
            .padding(.top, 2)
            .padding(.bottom, 5)
            .background(HUDStyle.panel)
        }
    }
}

/// A portrait beside its panel: the panel as tall as its name and bars, the portrait a square as
/// tall as that (at least `least`), the panel taking the rest of `width`. The panel's height doesn't
/// hang on its width (one line of name, bars of fixed height), so it's measured first.
private struct PortraitBeside: Layout {
    let width: CGFloat
    let least: CGFloat
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: width, height: side(subviews))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let length = side(subviews)
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: length, height: length))
        subviews[1].place(at: CGPoint(x: bounds.minX + length + spacing, y: bounds.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: max(0, width - length - spacing), height: length))
    }

    private func side(_ subviews: Subviews) -> CGFloat {
        guard subviews.count == 2 else { return least }
        let panel = subviews[1].sizeThatFits(ProposedViewSize(width: max(0, width - least - spacing), height: nil)).height
        return max(least, panel.rounded(.up))
    }
}

/// A round, bevelled portrait with Fairyland Online's little level chip at the bottom left: a circle for one
/// digit, a pill as wide as the number for more (playtesting 2026-10-17). It glows when
/// there's something to spend (a class to choose, skill points).
private struct Portrait: View {
    let face: UIImage
    let level: Int
    let size: CGFloat
    var glowing = false
    @State private var pulse = false

    var body: some View {
        Image(uiImage: face)
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .padding(size * 0.08)
            .frame(width: size, height: size)
            .background(Circle().fill(RadialGradient(colors: [HUDStyle.portrait, HUDStyle.portraitRim],
                                                     center: UnitPoint(x: 0.4, y: 0.35), startRadius: 1, endRadius: size * 0.7)))
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(HUDStyle.bevel, lineWidth: size > 40 ? 3 : 2))
            .overlay(alignment: .bottomLeading) {
                Text("\(level)")
                    .font(HUDStyle.mono(size > 40 ? 10 : 8))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, size > 40 ? 4 : 3)
                    .frame(minWidth: size * 0.34, minHeight: size * 0.34)
                    .background(Capsule().fill(HUDStyle.frameDark).overlay(Capsule().strokeBorder(HUDStyle.bevel, lineWidth: 1.5)))
                    .offset(x: -2, y: 2)
            }
            .shadow(color: glowing ? HUDStyle.gold.opacity(pulse ? 1 : 0.3) : .black.opacity(0.35), radius: glowing ? 8 : 2, y: glowing ? 0 : 2)
            .onAppear {
                guard glowing else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
            }
    }
}

/// A bar in the top-left with its tag (HP, MP, XP) on a dark chip after it, the chips one width so
/// the bars line up. XP's bar is thinner and has no numbers.
private struct TaggedBar: View {
    let tag: String
    let value: Int
    let maximum: Int
    let color: Color
    var height: CGFloat = 9
    var showsNumbers = true

    var body: some View {
        HStack(spacing: 3) {
            StatBar(label: "", value: value, maximum: maximum, color: color, height: height, showsNumbers: showsNumbers)
            Text(tag)
                .font(HUDStyle.font(9))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 1)
                .frame(width: 20, height: 11)
                .background(RoundedRectangle(cornerRadius: 3).fill(HUDStyle.frameDark))
        }
    }
}

/// Under your party, while you travel in someone else's (`GameSession.joinedParty`): whose it is and
/// how many of them, and Leave party.
private struct JoinedPartyPlate: View {
    let leader: Adventurer
    let count: Int
    let leave: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            IconImage(.users, size: 13)
                .foregroundStyle(HUDStyle.green)
            VStack(alignment: .leading, spacing: 0) {
                Text(L("In {name}'s party", ["name": leader.name]))
                    .font(HUDStyle.font(11))
                    .foregroundStyle(HUDStyle.cream)
                Text(L("{count} of them, and you", ["count": count]))
                    .font(HUDStyle.font(9))
                    .foregroundStyle(HUDStyle.dim)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            // On one line: the words beside it give way instead.
            Button(action: leave) {
                Text(L("Leave party"))
                    .lineLimit(1)
                    .fixedSize()
            }
            .buttonStyle(PixelButtonStyle(compact: true))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(width: TopLeft.width)
        .background(HUDStyle.panel)
    }
}

/// What just happened (EXP and gold won, an item found, a quest's step, the land you walk into, the
/// game's announcements): toasts in the battle's style (`ToastLabel`), top centre, each for a few
/// seconds, three at most, newest last; then they live in the chat (`GameSession.post`; playtesting
/// 2026-10-24: Fairyland Online's yellow lines piled up in the top-left corner, then black pills with
/// icons down the right, unlike the battle's).
private struct GameToasts: View {
    let lines: [GameSession.LogLine]
    /// How long each shows.
    private static let shown: TimeInterval = 3.5

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let showing = Array(lines.filter { context.date.timeIntervalSince($0.time) < Self.shown }.suffix(3))
            VStack(spacing: 4) {
                ForEach(showing) { line in
                    ToastLabel(text: line.text)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showing.map(\.id))
        }
        // As wide as the battle's line runs at most: a long one wraps to two.
        .frame(maxWidth: 300)
    }
}

/// XP toward the next level: a thin bar under HP and MP, tagged as they are and as long as theirs.
private struct ExpBar: View {
    let value: Int
    let maximum: Int

    var body: some View {
        TaggedBar(tag: L("XP"), value: value, maximum: maximum, color: HUDStyle.exp, showsNumbers: false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("XP"))
            .accessibilityValue("\(value) / \(maximum)")
    }
}

/// The menu: one round button with three lines that, tapped, grows into a panel listing the menu's
/// windows (Hero, Companion, Friends, Quests, Settings), the round close button in its top
/// right corner (playtesting 2026-10-25). A gold dot on the button while any window has something new,
/// and on that window's row. It takes the button's room only: open, the panel spreads up and to the
/// left over Chat, which stays put (playtesting 2026-10-24: it pushed Chat aside). Tapping a row opens
/// that window and closes the panel (playtesting 2026-10-26).
private struct GameMenu: View {
    let items: [MenuTab]
    @Binding var open: Bool
    let badge: (MenuTab) -> Bool
    let onPick: (MenuTab) -> Void

    private static let button: CGFloat = 46
    private static let spring = Animation.spring(response: 0.34, dampingFraction: 0.78)

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if open {
                panel
                    .transition(.scale(scale: 0.4, anchor: .bottomTrailing).combined(with: .opacity))
            } else {
                Button {
                    SoundEffects.shared.play(.tap, volume: 0.7)
                    open = true
                } label: {
                    MenuGlyph()
                        .frame(width: Self.button, height: Self.button)
                        .background(Self.surface(Circle()))
                        .overlay(alignment: .top) {
                            // The button's gloss, an oval across its top.
                            Ellipse().fill(.white.opacity(0.35))
                                .frame(width: Self.button * 0.62, height: Self.button * 0.28)
                                .padding(.top, 3)
                                .allowsHitTesting(false)
                        }
                        .overlay(alignment: .topTrailing) {
                            if items.contains(where: badge) {
                                Circle().fill(HUDStyle.gold).frame(width: 12, height: 12)
                                    .overlay(Circle().stroke(HUDStyle.ink, lineWidth: 1.5))
                            }
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel(L("Open menu"))
                .transition(.opacity)
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 2)
        .animation(Self.spring, value: open)
        .frame(width: Self.button, height: Self.button, alignment: .bottomTrailing)
    }

    /// The open menu: its windows, one after another, and the close button over its top right
    /// corner, as on every window (playtesting 2026-10-25).
    private var panel: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(items) { row($0) }
        }
        // As much room above the first row as below the last (playtesting 2026-10-26): the close
        // button hangs off the corner, clear of the rows' names on the left.
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .frame(width: HUDMargins.width)
        .background(Self.surface(RoundedRectangle(cornerRadius: HUDMargins.radius)))
        .overlay(alignment: .topTrailing) {
            OrangeCloseButton {
                SoundEffects.shared.play(.tap, volume: 0.7)
                open = false
            }
            .accessibilityLabel(L("Close menu"))
            .offset(x: OrangeCloseButton.overhang, y: -OrangeCloseButton.overhang)
        }
    }

    /// The button's and the panel's face: the HUD's blue tile with its bevel.
    private static func surface(_ shape: some InsettableShape) -> some View {
        HUDStyle.panelSurface(shape)
    }

    private func row(_ tab: MenuTab) -> some View {
        Button {
            SoundEffects.shared.play(.tap, volume: 0.7)
            onPick(tab)
        } label: {
            HStack(spacing: 9) {
                IconImage(tab.icon, size: 24)
                Text(tab.menuTitle)
                    .font(HUDStyle.font(13))
                    .foregroundStyle(.white)
                    .shadow(color: HUDStyle.frameDark, radius: 0, x: 1, y: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                if badge(tab) {
                    Circle().fill(HUDStyle.gold).frame(width: 10, height: 10)
                        .overlay(Circle().stroke(HUDStyle.ink, lineWidth: 1.5))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
    }
}

/// The HUD's room from the screen's edges, which the big windows keep too (the menu's, the map, Chat:
/// playtesting 2026-10-25, "the same margin spaces on each side as the original menu button and
/// menu"), and the menu panel's size.
@MainActor
enum HUDMargins {
    static let width: CGFloat = 178
    static let radius: CGFloat = 18
    /// From the sides (inside the safe area) and the top: the HUD's own 8 points.
    static let side: CGFloat = 8

    /// From the bottom: the menu button's gap (a phone on its side keeps it in the home indicator's
    /// strip, the safe area ignored there; upright, over it).
    static func bottom(onItsSide: Bool) -> CGFloat { onItsSide ? 8 : 14 }
    static func bottomEdge(onItsSide: Bool) -> SwiftUI.Edge.Set { onItsSide ? .bottom : [] }
}

/// Three white lines.
private struct MenuGlyph: View {
    var body: some View {
        VStack(spacing: 3.5) {
            line
            line
            line
        }
        .frame(width: 24, height: 24)
    }

    private var line: some View {
        Capsule()
            .fill(.white)
            .frame(width: 22, height: 3.5)
            .shadow(color: HUDStyle.frameDark, radius: 0, x: 1, y: 1)
    }
}

/// A round minimap around the hero, framed like the HUD's buttons (playtesting 2026-10-25: round, no
/// title bar, its music and hide buttons gone; the music is in Settings; its compass moved, bigger, to
/// the map's window, `MapCompass`). Tap for the full map, where the land's name and your coordinates are.
private struct MinimapWindow: View {
    /// The land's map and what's round it (`WorldScene.minimapPicture`).
    let picture: WorldScene.MinimapPicture
    let cell: GridPoint
    let dots: [GameSession.MinimapDot]
    let marks: [GameSession.MinimapMark]
    let onOpen: () -> Void

    private let size: CGFloat = 128
    private let zoom: CGFloat = 5
    /// The rotated map layer must be big enough to cover the window's corners.
    private let layer: CGFloat = 420

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.12, blue: 0.22)
            // Turned and squashed like the world, so "up" on the minimap is "up" on screen.
            // The map rides in an overlay: an image bigger than the layer (maps over 84 tiles
            // wide) must not resize or re-centre it, or the hero's cell drifts off the marker.
            Color.clear
                .frame(width: layer, height: layer)
                .overlay(alignment: .topLeading) {
                    Image(uiImage: picture.image)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: CGFloat(picture.columns) * zoom, height: CGFloat(picture.rows) * zoom)
                        .offset(
                            x: layer / 2 - (CGFloat(cell.col - picture.origin.col) + 0.5) * zoom,
                            y: layer / 2 - (CGFloat(picture.rows - 1 - (cell.row - picture.origin.row)) + 0.5) * zoom
                        )
                }
                .rotationEffect(.degrees(-45))
                .scaleEffect(x: 1, y: 0.5)
            // Everyone else, round dots on top of the turned map (drawn in it, they'd be
            // squashed flat): the folk who live here smaller.
            ForEach(Array(dots.enumerated()), id: \.offset) { _, dot in
                let size: CGFloat = dot.kind == .folk ? 4 : 5
                Circle()
                    .fill(color(of: dot.kind))
                    .frame(width: size, height: size)
                    .overlay(Circle().stroke(HUDStyle.ink, lineWidth: 1))
                    .offset(offset(of: dot.cell))
            }
            // Who does what, as icons over them.
            ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in
                MinimapIcon(kind: mark.kind)
                    .offset(offset(of: mark.cell))
            }
            Circle()
                .fill(HUDStyle.gold)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(HUDStyle.ink, lineWidth: 1.5))
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(HUDStyle.bevel, lineWidth: 3))
        .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 2)
        .contentShape(Circle())
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Open map"))
        .accessibilityAddTraits(.isButton)
    }

    /// Where a cell lands in the window, from its centre (the hero): its distance on the map layer,
    /// turned 45° and squashed in half like the layer itself.
    private func offset(of other: GridPoint) -> CGSize {
        let x = CGFloat(other.col - cell.col) * zoom
        let y = CGFloat(cell.row - other.row) * zoom
        let half = CGFloat(0.5).squareRoot()
        return CGSize(width: (x + y) * half, height: (y - x) * half * 0.5)
    }

    /// Party friends green, other friends white, red-named adventurers red, the folk who live here
    /// yellow (as RuneScape's people are), everyone else the blue of their names.
    private func color(of kind: GameSession.MinimapDot.Kind) -> Color {
        switch kind {
        case .party: HUDStyle.green
        case .friend: .white
        case .hostile: Color(uiColor: Crowd.hostileColor)
        case .adventurer: Color(uiColor: Crowd.adventurerColor)
        case .folk: Color(red: 1, green: 0.88, blue: 0.3)
        }
    }
}

/// One of the minimap's icons for who does what (`GameSession.MinimapMark`), RuneScape-style: a
/// small round in its own colour with a white sign, outlined like the dots. A quest giver shows the
/// "!" or "?" floating over their head in gold, else a book.
struct MinimapIcon: View {
    let kind: GameSession.MinimapMark.Kind
    /// Across, in points: 13 on the minimap, bigger on the world map.
    var size: CGFloat = 13

    var body: some View {
        ZStack {
            Circle().fill(fill)
            sign
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(HUDStyle.ink, lineWidth: size > 16 ? 1.5 : 1))
    }

    @ViewBuilder private var sign: some View {
        switch kind {
        case .questNew: mark("!")
        case .questReady: mark("?")
        case .quest: glyph(.star)
        case .healer: glyph(.heart)
        case .shop: glyph(.coins)
        case .smith: glyph(.hammer)
        case .weaver: glyph(.shieldStar)
        case .barber: glyph(.palette)
        // RuneScape's bank: coins on gold.
        case .bank: glyph(.coins)
        case .guild: glyph(.shield)
        case .chest: glyph(.gift)
        case .boss: glyph(.sword)
        case .stairsDown: glyph(.arrowDown)
        case .stairsUp: glyph(.arrowUp)
        case .waystone: glyph(.sparkles)
        // What you lost when you fell: a bag, on red.
        case .lost: glyph(.backpack)
        }
    }

    private func mark(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 10 * size / 13, weight: .black, design: .rounded))
            .foregroundStyle(HUDStyle.ink)
    }

    private func glyph(_ icon: GameIcon) -> some View {
        IconImage(icon, size: 8 * size / 13).foregroundStyle(.white)
    }

    private var fill: Color {
        switch kind {
        case .questNew, .questReady: HUDStyle.gold
        case .quest: Color(red: 0.3, green: 0.55, blue: 0.95)
        case .healer: Color(red: 0.92, green: 0.32, blue: 0.42)
        case .shop: Color(red: 0.25, green: 0.68, blue: 0.36)
        case .smith: Color(red: 0.5, green: 0.52, blue: 0.6)
        case .weaver: Color(red: 0.78, green: 0.36, blue: 0.62)
        case .barber: Color(red: 0.2, green: 0.62, blue: 0.66)
        case .bank: Color(red: 0.86, green: 0.62, blue: 0.1)
        case .guild: Color(red: 0.58, green: 0.4, blue: 0.86)
        case .chest: Color(red: 0.74, green: 0.47, blue: 0.2)
        case .boss: Color(red: 0.62, green: 0.1, blue: 0.16)
        case .stairsDown, .stairsUp: Color(red: 0.42, green: 0.42, blue: 0.5)
        // A portal's own bright cyan: in the quest givers' blue it read as one of them (playtesting
        // 2026-10-23).
        case .waystone: Color(red: 0.05, green: 0.8, blue: 0.95)
        case .lost: Color(red: 0.9, green: 0.3, blue: 0.14)
        }
    }
}

/// Flashes briefly whenever the game autosaves: a toast like the rest (`ToastLabel`), top centre
/// (playtesting 2026-10-24: a green pill under the minimap).
private struct SavedBadge: View {
    let lastSaved: Date?
    @State private var visible = false

    var body: some View {
        ToastLabel(text: L("Saved"))
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(false)
            .onChange(of: lastSaved) {
                withAnimation(.easeOut(duration: 0.2)) { visible = true }
                Task {
                    try? await Task.sleep(for: .seconds(1.6))
                    withAnimation(.easeIn(duration: 0.4)) { visible = false }
                }
            }
            .accessibilityHidden(true)
    }
}

private extension View {
    /// Fades a control out, and stops it taking taps, while a conversation or window covers the map.
    func stepsAside(_ hidden: Bool) -> some View {
        opacity(hidden ? 0 : 1)
            .allowsHitTesting(!hidden)
            .animation(.easeOut(duration: 0.2), value: hidden)
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.system(size: 8))
            configuration.title
        }
    }
}
