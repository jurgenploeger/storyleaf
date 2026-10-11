import SwiftUI

/// On-map HUD in Fairyland Online's style: round faces with HP/MP for you, your companion and
/// your party, and the calendar plate top-left, a framed minimap top-right, the system log, joystick bottom-left and
/// a glossy toolbar bottom-right. While you're talking to someone (or any window is open over the map)
/// the controls step aside, so nothing peeks out from behind the conversation.
struct WorldHUD: View {
    let coordinator: GameCoordinator

    private var session: GameSession { coordinator.session }
    private var controlsHidden: Bool { coordinator.overlay != nil }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 6) {
                // The faces open their stats, and the party folds and unfolds; the rest lets taps
                // through to the map.
                StatusCluster(session: session, onInspect: { coordinator.open(.profile($0)) })
                    .coachTarget(.status)
                CalendarPlate(session: session)
                    .allowsHitTesting(false)
                SystemLog(lines: session.log)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            VStack(alignment: .trailing, spacing: 6) {
                MinimapWindow(
                    image: coordinator.world.minimapImage(explored: session.exploredVersion),
                    name: session.mapName,
                    cell: session.mapCell,
                    dots: session.minimapDots,
                    columns: coordinator.world.def.width,
                    rows: coordinator.world.def.height,
                    onOpen: { coordinator.open(.worldMap) }
                )
                .coachTarget(.minimap)
                HStack(spacing: 6) {
                    FLIconButton(icon: .settings, label: L("Settings"), size: 40) {
                        coordinator.open(.menu(.settings))
                    }
                    FLIconButton(icon: .talk, label: L("Chat"), size: 40, badge: session.unreadChat > 0) {
                        coordinator.open(.chat)
                    }
                    .coachTarget(.chat)
                }
                .stepsAside(controlsHidden)
                SavedBadge(lastSaved: session.lastSaved)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            JoystickView(input: coordinator.input)
                .coachTarget(.joystick)
                .stepsAside(controlsHidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 8)
                .padding(.bottom, 10)

            VStack(alignment: .trailing, spacing: 10) {
                if let id = session.nearbyNPC, let npc = Content.shared.npc(id) {
                    Button {
                        coordinator.talkToNearby()
                    } label: {
                        if npc.role == .chest {
                            Label(L("Open {name}", ["name": npc.name]), icon: .gift)
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
                HStack(spacing: 7) {
                    // Settings has its own button up top, next to Chat. Friends is a tab of the menu
                    // only: a fifth button here would run into the joystick on a phone held upright.
                    ForEach(MenuTab.allCases.filter { $0 != .settings && $0 != .friends }) { tab in
                        FLIconButton(icon: tab.icon, label: tab.title, badge: badge(for: tab)) {
                            coordinator.open(.menu(tab))
                        }
                    }
                }
                .coachTarget(.toolbar)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.bottom, 14)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: session.nearbyNPC)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: session.nearbyAdventurer?.id)
            .stepsAside(controlsHidden)
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
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

/// Fairyland's top-left faces: you in a big round frame with your level, HP and MP; your companion
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
                            PortraitRow(face: ArtLibrary.shared.face(session.artID(for: friend)), level: friend.level, name: friend.name,
                                        detail: away == nil ? session.content.classDef(friend.classID).name : L("Waiting"), size: 30) {
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
            HStack(spacing: 6) {
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
            .frame(width: size > 40 ? 132 : 112, alignment: .leading)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(HUDStyle.panel)
        }
    }
}

/// A round, bevelled portrait with Fairyland's little level chip at the bottom left. It glows when
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
            .background(Circle().fill(RadialGradient(colors: [Color(red: 0.98, green: 0.95, blue: 0.85), Color(red: 0.75, green: 0.88, blue: 0.98)],
                                                     center: UnitPoint(x: 0.4, y: 0.35), startRadius: 1, endRadius: size * 0.7)))
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(HUDStyle.bevel, lineWidth: size > 40 ? 3 : 2))
            .overlay(alignment: .bottomLeading) {
                Text("\(level)")
                    .font(HUDStyle.mono(size > 40 ? 10 : 8))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .frame(minWidth: size * 0.36, minHeight: size * 0.32)
                    .background(Circle().fill(HUDStyle.frameDark).overlay(Circle().strokeBorder(HUDStyle.bevel, lineWidth: 1.5)))
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

/// The tan calendar plate with a sun or moon, and the EXP bar underneath.
private struct CalendarPlate: View {
    let session: GameSession
    /// With night and day switched off in Settings, the sun shines on the plate around the clock.
    @AppStorage(GameSettings.dayAndNightKey) private var dayAndNight = true

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            let moment = GameClock.moment(at: context.date, since: session.data.startedAt)
            let daytime = moment.isDaytime || !dayAndNight
            let hero = session.data.hero
            VStack(spacing: 3) {
                HStack(spacing: 5) {
                    IconImage(daytime ? .sun : .moon, size: 14)
                        .foregroundStyle(daytime ? HUDStyle.orange : Color(red: 0.35, green: 0.35, blue: 0.75))
                    Text(moment.text)
                        .font(HUDStyle.mono(10))
                        .foregroundStyle(HUDStyle.plateDark)
                    Spacer(minLength: 0)
                    IconImage(.coins, size: 14)
                        .foregroundStyle(HUDStyle.coin)
                        .shadow(color: HUDStyle.plateDark, radius: 0, x: 1, y: 1)
                    Text("\(session.data.gold)")
                        .font(HUDStyle.mono(10))
                        .foregroundStyle(HUDStyle.plateDark)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(HUDStyle.plateBackground)
                HStack(spacing: 3) {
                    Text(L("EXP")).font(HUDStyle.mono(8)).foregroundStyle(.white)
                    StatBar(label: "", value: hero.exp, maximum: GameSession.expToNext(level: hero.level), color: HUDStyle.exp, height: 7, showsNumbers: false)
                }
                .padding(.horizontal, 4)
            }
            .frame(width: 214)
        }
    }
}

/// Fairyland's yellow system messages, fading after a few seconds. The game's announcements stand
/// out on banners of their own.
private struct SystemLog: View {
    let lines: [GameSession.LogLine]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 1) {
                ForEach(lines.filter { context.date.timeIntervalSince($0.time) < 12 }.suffix(4)) { line in
                    row(line)
                        .transition(.opacity)
                }
            }
            .frame(width: 240, alignment: .leading)
            .animation(.easeOut(duration: 0.3), value: lines.count)
        }
    }

    @ViewBuilder
    private func row(_ line: GameSession.LogLine) -> some View {
        switch line.kind {
        case .announcement:
            HStack(alignment: .top, spacing: 5) {
                IconImage(.sparkles, size: 12)
                Text(line.text)
                    .font(HUDStyle.mono(10))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(HUDStyle.gold)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(HUDStyle.ink.opacity(0.8))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(HUDStyle.gold.opacity(0.75), lineWidth: 1))
            )
            .padding(.vertical, 1)
        case .system, .quest, .battle, .reward:
            Text(line.text)
                .font(HUDStyle.mono(10))
                .foregroundStyle(color(for: line.kind))
                .shadow(color: .black, radius: 0, x: 1, y: 1)
        }
    }

    private func color(for kind: GameSession.LogLine.Kind) -> Color {
        switch kind {
        case .system: HUDStyle.nameYellow
        case .quest: Color(red: 0.55, green: 0.95, blue: 1)
        case .battle: .white
        case .reward: HUDStyle.green
        case .announcement: HUDStyle.gold
        }
    }
}

/// A framed minimap window around the hero, with Fairyland's coordinates on a plate in its corner.
/// Tap for the full map.
private struct MinimapWindow: View {
    let image: UIImage
    let name: String
    let cell: GridPoint
    let dots: [GameSession.MinimapDot]
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
                            Image(uiImage: image)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: CGFloat(columns) * zoom, height: CGFloat(rows) * zoom)
                                .offset(
                                    x: layer / 2 - (CGFloat(cell.col) + 0.5) * zoom,
                                    y: layer / 2 - (CGFloat(rows - 1 - cell.row) + 0.5) * zoom
                                )
                        }
                        .rotationEffect(.degrees(-45))
                        .scaleEffect(x: 1, y: 0.5)
                    // The other players, round dots on top of the turned map (drawn in it, they'd
                    // be squashed flat).
                    ForEach(Array(dots.enumerated()), id: \.offset) { _, dot in
                        Circle()
                            .fill(color(of: dot.kind))
                            .frame(width: 5, height: 5)
                            .overlay(Circle().stroke(HUDStyle.ink, lineWidth: 1))
                            .offset(offset(of: dot.cell))
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

    /// Party friends green, other friends white, red-named adventurers red, everyone else the blue
    /// of their names.
    private func color(of kind: GameSession.MinimapDot.Kind) -> Color {
        switch kind {
        case .party: HUDStyle.green
        case .friend: .white
        case .hostile: Color(uiColor: Crowd.hostileColor)
        case .adventurer: Color(uiColor: Crowd.adventurerColor)
        }
    }
}

/// Flashes briefly whenever the game autosaves.
private struct SavedBadge: View {
    let lastSaved: Date?
    @State private var visible = false

    var body: some View {
        Label(L("Saved"), icon: .checkCircle, size: 13)
            .font(HUDStyle.font(10))
            .foregroundStyle(HUDStyle.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(HUDStyle.ink.opacity(0.8)))
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
