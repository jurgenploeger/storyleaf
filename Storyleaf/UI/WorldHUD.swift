import SwiftUI

/// On-map HUD in Fairyland Online's style: round faces with HP/MP for you (and your EXP), your
/// companion and your party, and the calendar plate top-left, a framed minimap top-right with what
/// just happened toasting under it, joystick bottom-left, and Chat and the menu bottom-right (one
/// button that opens into the menu's pages). While you're talking to someone (or any window is open
/// over the map) the controls step aside, so nothing peeks out from behind the conversation.
struct WorldHUD: View {
    let coordinator: GameCoordinator
    /// The menu button opened into its list of pages (`GameMenu`).
    @State private var menuOpen = DebugLaunch.opensHUDMenu
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var bottomGap: (joystick: CGFloat, buttons: CGFloat) { onItsSide ? (8, 8) : (10, 14) }
    /// On a phone on its side the bottom controls sit down in the home indicator's strip, a few
    /// points off the screen's edge (playtesting 2026-10-16: "should sit lower"): the indicator hides
    /// itself and a swipe there moves the joystick first (`GameView`). Upright, they keep over it.
    private var onItsSide: Bool { verticalSizeClass == .compact }
    private var bottomEdge: SwiftUI.Edge.Set { onItsSide ? .bottom : [] }

    private var session: GameSession { coordinator.session }
    private var controlsHidden: Bool { coordinator.overlay != nil }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 6) {
                // The faces open their stats, and the party folds and unfolds; the rest lets taps
                // through to the map.
                StatusCluster(session: session, onInspect: { coordinator.open(.profile($0)) })
                    .coachTarget(.status)
                // The party you've joined: whose it is, and a way out of it.
                if let joined = session.joinedParty, let leader = joined.leader {
                    JoinedPartyPlate(leader: leader, count: joined.members.count) { coordinator.leaveJoinedParty() }
                }
                CalendarPlate(session: session)
                    .allowsHitTesting(false)
                // What just happened, top centre under the panels on both sides (walking into a land
                // too: its toast, no banner of its own; playtesting 2026-10-24).
                // The autosave's "Saved" under them, in the same style.
                VStack(spacing: 4) {
                    GameToasts(lines: session.log)
                    SavedBadge(lastSaved: session.lastSaved)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            VStack(alignment: .trailing, spacing: 6) {
                let minimap = coordinator.minimap(explored: session.exploredVersion, overviews: WorldOverview.shared.images.count)
                MinimapWindow(
                    picture: minimap.picture,
                    name: session.mapName,
                    cell: session.mapCell,
                    dots: session.minimapDots,
                    marks: session.minimapMarks,
                    columns: minimap.columns,
                    rows: minimap.rows,
                    onOpen: { coordinator.open(.worldMap) }
                )
                .coachTarget(.minimap)
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
                .stepsAside(controlsHidden)
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
                } else if let adventurer = session.nearbyAdventurer {
                    AdventurerCard(coordinator: coordinator, adventurer: adventurer)
                        .transition(.scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity))
                }
                // Chat, then the menu: one button that opens into its pages (playtesting 2026-10-24:
                // a row of four buttons, Chat and Settings up by the minimap). Friends stays a tab of
                // the menu window.
                HStack(alignment: .bottom, spacing: 7) {
                    FLIconButton(icon: .talk, label: L("Chat"), badge: session.unreadChat > 0) {
                        menuOpen = false
                        coordinator.open(.chat)
                    }
                    .coachTarget(.chat)
                    GameMenu(items: [.character, .companions, .bag, .quests, .settings], open: $menuOpen,
                             badge: { badge(for: $0) }) { tab in
                        coordinator.open(.menu(tab))
                    }
                    .coachTarget(.toolbar)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.bottom, bottomGap.buttons)
            .ignoresSafeArea(.container, edges: bottomEdge)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: session.nearbyNPC)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: session.nearbyAdventurer?.id)
            .stepsAside(controlsHidden)
        }
        .padding(.horizontal, 8)
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

/// Fairyland Online's top-left faces: you in a big round frame with your level, HP and MP; your companion
/// underneath with its own; and the friends in your party, smaller. Once three or more of you travel
/// together, the others fold into one row of small faces under yours so they don't cover the map:
/// tap the row to see everyone in full, and the arrow by the last friend to fold them again. Tap a
/// face to see their stats.
private struct StatusCluster: View {
    let session: GameSession
    let onInspect: (Profile) -> Void
    @AppStorage(GameSettings.partyFoldedKey) private var folded = true

    var body: some View {
        let hero = session.data.hero
        let stats = session.heroStats
        let pet = session.activePet
        let friends = session.partyMembers
        let crowded = (pet == nil ? 0 : 1) + friends.count >= 2
        VStack(alignment: .leading, spacing: 4) {
            Button { onInspect(.hero) } label: {
                PortraitRow(face: ArtLibrary.shared.face(GameSession.heroArt), level: hero.level, name: hero.name,
                            detail: session.heroClass.name, size: 52,
                            glowing: session.canChooseClass || session.canSpendSkillPoint) {
                    TaggedBar(tag: L("H"), value: hero.hp, maximum: stats.hp, color: HUDStyle.hp)
                    TaggedBar(tag: L("M"), value: hero.mp, maximum: stats.mp, color: HUDStyle.mp)
                    // EXP to the next level, thin under the bars (playtesting 2026-10-24: it had a
                    // row of its own under the calendar).
                    ExpBar(value: hero.exp, maximum: GameSession.expToNext(level: hero.level))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("{name}, level {level}: stats", ["name": hero.name, "level": hero.level]))
            if crowded && folded {
                FoldedParty(session: session, pet: pet, friends: friends) { setFolded(false) }
                    .transition(.opacity)
            } else {
                if let pet {
                    let petStats = session.stats(of: pet)
                    Button { onInspect(.pet(pet.id)) } label: {
                        PortraitRow(face: ArtLibrary.shared.face(session.artID(for: pet)), level: pet.level, name: pet.name,
                                    detail: pet.hp > 0 ? nil : L("Fainted"), size: 38) {
                            TaggedBar(tag: L("H"), value: pet.hp, maximum: petStats.hp, color: HUDStyle.hp)
                            TaggedBar(tag: L("M"), value: pet.mp, maximum: petStats.mp, color: HUDStyle.mp)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("{name}, level {level}: stats", ["name": pet.name, "level": pet.level]))
                }
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

/// A big party folded into one row of small faces under yours: your companion's with a thin HP bar
/// (grey once it has fainted), then your friends' (grey while they wait somewhere for you). Tap it to
/// see everyone in full.
private struct FoldedParty: View {
    let session: GameSession
    let pet: Pet?
    let friends: [Adventurer]
    let unfold: () -> Void

    var body: some View {
        Button(action: unfold) {
            HStack(spacing: 4) {
                if let pet {
                    let stats = session.stats(of: pet)
                    let health: CGFloat = stats.hp > 0 ? min(1, CGFloat(pet.hp) / CGFloat(stats.hp)) : 0
                    VStack(spacing: 2) {
                        Portrait(face: ArtLibrary.shared.face(session.artID(for: pet)), level: pet.level, size: 32)
                            .saturation(pet.hp > 0 ? 1 : 0)
                        GlossyBar(fraction: health, color: HUDStyle.hp, height: 5)
                            .frame(width: 30)
                    }
                }
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

/// One face in the top-left: a round portrait with a level chip, then a name and bars on a panel.
private struct PortraitRow<Bars: View>: View {
    let face: UIImage
    let level: Int
    let name: String
    var detail: String? = nil
    let size: CGFloat
    var glowing = false
    /// The whole row's width, portrait and panel.
    var width: CGFloat = TopLeft.width
    @ViewBuilder let bars: () -> Bars

    var body: some View {
        // Top-aligned: the panel's top edge lines up with the portrait's, and so with the
        // minimap's across the screen.
        HStack(alignment: .top, spacing: 5) {
            Portrait(face: face, level: level, size: size, glowing: glowing)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(name).font(HUDStyle.mono(size > 40 ? 11 : 10)).foregroundStyle(HUDStyle.nameYellow).lineLimit(1)
                    if let detail {
                        Text(detail).font(HUDStyle.mono(9)).foregroundStyle(HUDStyle.dim).lineLimit(1)
                    }
                }
                .shadow(color: .black, radius: 0, x: 1, y: 1)
                bars()
            }
            // The panel takes what the portrait (and the 5 between) leaves, less its own padding.
            .frame(width: width - size - 5 - 14, alignment: .leading)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            // As tall as the portrait beside it (playtesting 2026-10-17), its name and bars in the middle.
            .frame(minHeight: size)
            .background(HUDStyle.panel)
        }
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

private struct TaggedBar: View {
    let tag: String
    let value: Int
    let maximum: Int
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            StatBar(label: "", value: value, maximum: maximum, color: color, height: 9)
            Text(tag)
                .font(HUDStyle.mono(9))
                .foregroundStyle(.white)
                .frame(width: 14, height: 11)
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
            Button(L("Leave party"), action: leave)
                .buttonStyle(PixelButtonStyle(compact: true))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(width: TopLeft.width)
        .background(HUDStyle.panel)
    }
}

/// The tan calendar plate with a sun or moon and the date.
private struct CalendarPlate: View {
    let session: GameSession
    /// With night and day switched off in Settings, the sun shines on the plate around the clock.
    @AppStorage(GameSettings.dayAndNightKey) private var dayAndNight = true

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            let moment = GameClock.moment(at: context.date, since: session.data.startedAt)
            let daytime = moment.isDaytime || !dayAndNight
            VStack(spacing: 3) {
                HStack(spacing: 5) {
                    IconImage(daytime ? .sun : .moon, size: 14)
                        .foregroundStyle(daytime ? HUDStyle.orange : Color(red: 0.35, green: 0.35, blue: 0.75))
                    Text(moment.text)
                        .font(HUDStyle.mono(10))
                        .foregroundStyle(HUDStyle.plateDark)
                    Spacer(minLength: 0)
                    // No gold here any more (2026-10-25): the coins you carry are in the bag, in a
                    // slot of their own, and the rest in the bank.
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(HUDStyle.plateBackground)
            }
            .frame(width: TopLeft.width)
        }
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

/// EXP toward the next level: a thin bar under the hero's HP and MP, as long as theirs.
private struct ExpBar: View {
    let value: Int
    let maximum: Int

    var body: some View {
        HStack(spacing: 3) {
            StatBar(label: "", value: value, maximum: maximum, color: HUDStyle.exp, height: 5, showsNumbers: false)
            // Where the H and M tags stand beside their bars.
            Color.clear.frame(width: 14, height: 5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("EXP"))
        .accessibilityValue("\(value) / \(maximum)")
    }
}

/// The menu: one button with three lines that, tapped, grows into a panel listing the menu's pages
/// (Hero, Companion, Inventory, Quests, Settings), its lines turning into a cross that closes it.
/// A gold dot on the button while any page has something new, and on that page's row. It takes the
/// button's room only: open, the panel spreads up and to the left over Chat, which stays put
/// (playtesting 2026-10-24: it pushed Chat aside).
private struct GameMenu: View {
    let items: [MenuTab]
    @Binding var open: Bool
    let badge: (MenuTab) -> Bool
    let onPick: (MenuTab) -> Void

    private static let button: CGFloat = 46
    private static let width: CGFloat = 178
    private static let spring = Animation.spring(response: 0.34, dampingFraction: 0.78)

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if open {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.element) { index, tab in
                        row(tab)
                            // One after another up from the button as it opens.
                            .transition(.asymmetric(
                                insertion: .offset(y: 14).combined(with: .opacity)
                                    .animation(Self.spring.delay(Double(items.count - 1 - index) * 0.035)),
                                removal: .opacity.animation(.easeOut(duration: 0.12))))
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, 4)
            }
            Button {
                SoundEffects.shared.play(.tap, volume: 0.7)
                open.toggle()
            } label: {
                MenuGlyph(open: open)
                    .frame(width: Self.button, height: Self.button)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel(open ? L("Close menu") : L("Open menu"))
        }
        .frame(width: open ? Self.width : Self.button, alignment: .trailing)
        .background(
            RoundedRectangle(cornerRadius: open ? 14 : 9)
                .fill(LinearGradient(colors: HUDStyle.tile, startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: open ? 14 : 9).strokeBorder(HUDStyle.bevel, lineWidth: 2.5))
                .overlay(alignment: .bottom) {
                    // The button's gloss, on its own square at the bottom; none on the cross that
                    // closes the open menu.
                    RoundedRectangle(cornerRadius: 6).fill(.white.opacity(open ? 0 : 0.35))
                        .frame(width: Self.button - 8, height: Self.button * 0.3)
                        .padding(.bottom, Self.button * 0.62)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 4)
                }
        )
        .overlay(alignment: .topTrailing) {
            if !open && items.contains(where: badge) {
                Circle().fill(HUDStyle.gold).frame(width: 12, height: 12)
                    .overlay(Circle().stroke(HUDStyle.ink, lineWidth: 1.5))
                    .offset(x: 3, y: -3)
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 2)
        .animation(Self.spring, value: open)
        .frame(width: Self.button, height: Self.button, alignment: .bottomTrailing)
    }

    private func row(_ tab: MenuTab) -> some View {
        Button {
            SoundEffects.shared.play(.tap, volume: 0.7)
            open = false
            onPick(tab)
        } label: {
            HStack(spacing: 9) {
                IconImage(tab.icon, size: 24)
                Text(title(tab))
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

    /// The menu's names for its pages.
    private func title(_ tab: MenuTab) -> String {
        switch tab {
        case .character: L("Hero")
        case .companions: L("Companion")
        case .bag: L("Inventory")
        case .quests, .settings, .friends: tab.title
        }
    }
}

/// Three white lines, turning into a cross when the menu's open: the top and bottom lines meet in the
/// middle and turn, the middle one shrinks away.
private struct MenuGlyph: View {
    let open: Bool

    var body: some View {
        ZStack {
            line.offset(y: open ? 0 : -7).rotationEffect(.degrees(open ? 45 : 0))
            line.scaleEffect(x: open ? 0.1 : 1).opacity(open ? 0 : 1)
            line.offset(y: open ? 0 : 7).rotationEffect(.degrees(open ? -45 : 0))
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

/// A framed minimap window around the hero, with Fairyland Online's coordinates on a plate in its corner.
/// Tap for the full map.
private struct MinimapWindow: View {
    /// The land's map and what's round it (`WorldScene.minimapPicture`).
    let picture: WorldScene.MinimapPicture
    let name: String
    let cell: GridPoint
    let dots: [GameSession.MinimapDot]
    let marks: [GameSession.MinimapMark]
    let columns: Int
    let rows: Int
    let onOpen: () -> Void
    @AppStorage("minimapCollapsed") private var collapsed = false

    private let width: CGFloat = 150
    private let height: CGFloat = 100
    private let zoom: CGFloat = 5
    /// The rotated map layer must be big enough to cover the window's corners.
    private let layer: CGFloat = 420

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(name).font(HUDStyle.mono(10)).lineLimit(1)
                Spacer(minLength: 2)
                Button {
                    MusicPlayer.shared.toggleMute()
                } label: {
                    IconImage(MusicPlayer.shared.isMuted ? .musicOff : .music, size: 16)
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 20)
                }
                .accessibilityLabel(MusicPlayer.shared.isMuted ? L("Turn music on") : L("Turn music off"))
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { collapsed.toggle() }
                } label: {
                    IconImage(collapsed ? .chevronDown : .close, size: 14)
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(HUDStyle.orange).overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1)))
                }
                .accessibilityLabel(collapsed ? L("Show minimap") : L("Hide minimap"))
            }
            .foregroundStyle(.white)
            .shadow(color: HUDStyle.frameDark, radius: 0, x: 1, y: 1)
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .padding(.vertical, 3)
            .background(LinearGradient(colors: [HUDStyle.frameLight, HUDStyle.frameMid, HUDStyle.frameDark], startPoint: .top, endPoint: .bottom))

            if !collapsed {
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
                .frame(width: width, height: height)
                .clipped()
                // Where you stand, on a small plate tucked into the corner over the map.
                .overlay(alignment: .bottomTrailing) {
                    Text("\(cell.col) : \(rows - 1 - cell.row)")
                        .font(HUDStyle.mono(9))
                        .foregroundStyle(HUDStyle.plateDark)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(HUDStyle.plateBackground)
                        .padding(4)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpen)
                .accessibilityLabel(L("Open map"))
                .accessibilityAddTraits(.isButton)
            }
        }
        .frame(width: width)
        .background(Color(red: 0.08, green: 0.2, blue: 0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(HUDStyle.bevel, lineWidth: 2.5))
        .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 2)
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

    var body: some View {
        ZStack {
            Circle().fill(fill)
            sign
        }
        .frame(width: 13, height: 13)
        .overlay(Circle().stroke(HUDStyle.ink, lineWidth: 1))
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
        }
    }

    private func mark(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 10, weight: .black, design: .rounded))
            .foregroundStyle(HUDStyle.ink)
    }

    private func glyph(_ icon: GameIcon) -> some View {
        IconImage(icon, size: 8).foregroundStyle(.white)
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
