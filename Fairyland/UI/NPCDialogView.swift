import SwiftUI

/// Talking to someone: the healer, the shop, the quest giver, a guild master or a boss.
struct NPCDialogView: View {
    let npc: NPCDef
    let session: GameSession
    let onClose: () -> Void
    /// Bosses: start the fight.
    var onFight: (NPCDef) -> Void = { _ in }
    @State private var reply: String?
    /// A quest just handed in: its reward card covers the dialog until you continue.
    @State private var finished: FinishedQuest?
    /// An item tapped in the shop or at the smith, for a closer look.
    @State private var info: ItemDef? = DebugLaunch.itemInfo

    var body: some View {
        GeometryReader { proxy in
            // Fairyland-style: the character stands big in the bottom-right corner, cut off by the
            // edge of the screen, and talks from a speech bubble on their left.
            let portrait = min(proxy.size.width * 0.5, proxy.size.height * 0.6, 300)
            let bottom = max(16, proxy.safeAreaInsets.bottom)
            ZStack(alignment: .bottomTrailing) {
                Color.black.opacity(0.35)
                    .onTapGesture(perform: onClose)

                SpriteImage(art: npc.art, size: portrait)
                    .offset(x: portrait * 0.22, y: portrait * 0.16)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                // The tail points at the speaker's mouth, about a third of the picture's height up
                // from the bottom of the screen.
                bubble(maxHeight: proxy.size.height * 0.5, tailY: portrait * 0.34 - bottom)
                    .frame(maxWidth: 520)
                    .padding(.leading, 12)
                    .padding(.trailing, portrait * 0.62)
                    .padding(.bottom, bottom)

                if let finished {
                    QuestCompleteCard(session: session, finished: finished) { self.finished = nil }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .transition(.opacity)
                }

                if let info {
                    ItemInfoCard(session: session, item: info) { self.info = nil }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .transition(.opacity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .animation(.easeOut(duration: 0.2), value: finished?.quest.id)
            .animation(.easeOut(duration: 0.15), value: info?.id)
        }
        .ignoresSafeArea()
    }

    private func bubble(maxHeight: CGFloat, tailY: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            FLTitleBar(title: npc.name, onClose: onClose)
            VStack(alignment: .leading, spacing: 10) {
                Text(reply ?? npc.greeting)
                    .font(HUDStyle.font(13))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ScrollView {
                    Group {
                        switch npc.role {
                        case .healer: HealerPanel(session: session, reply: $reply)
                        case .shop: ShopPanel(session: session, stock: npc.stock ?? [], reply: $reply, info: $info)
                        case .quests: QuestGiverPanel(session: session, giver: npc.id, reply: $reply, finished: $finished)
                        case .guild: GuildPanel(session: session, classID: npc.classId ?? "", reply: $reply)
                        case .chest: EmptyView()   // opened straight from the map (GameCoordinator.open)
                        case .boss: BossPanel(session: session, boss: npc, onFight: onFight)
                        case .smith: SmithPanel(session: session, reply: $reply, info: $info)
                        }
                        if npc.rebirth == true {
                            RebirthPanel(session: session, reply: $reply)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: min(260, max(120, maxHeight - 110)))
            }
            .padding(12)
        }
        .foregroundStyle(HUDStyle.cream)
        // The title bar's corners round with the window's.
        .clipShape(RoundedRectangle(cornerRadius: HUDStyle.windowRadius))
        // The window is a speech bubble: its glass runs out round the tail, and its frame goes all
        // the way round over the title bar, like every window's (`gameWindow`).
        .background(SpeechBubble(tailY: tailY).fill(HUDStyle.glass).shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 2))
        .overlay(HUDStyle.frame(SpeechBubble(tailY: tailY)))
    }
}

/// A rounded window with a tail on its right edge pointing at the speaker: its middle `tailY`
/// points up from the bottom edge, the tip a little higher. The tail stands out past the frame.
/// Insetting moves its sides in too, so a bevel drawn with `strokeBorder` follows it.
private nonisolated struct SpeechBubble: InsettableShape {
    var cornerRadius: CGFloat = 10
    var tailY: CGFloat
    var tailBase: CGFloat = 24
    var tailLength: CGFloat = 16
    var tailRise: CGFloat = 5
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let box = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = max(0, cornerRadius - insetAmount)
        // The tail at no inset, its base clear of the corners...
        let half = tailBase / 2
        let middle = min(max(rect.maxY - tailY, rect.minY + cornerRadius + half), rect.maxY - cornerRadius - half)
        let upper = CGPoint(x: rect.maxX, y: middle - half)
        let lower = CGPoint(x: rect.maxX, y: middle + half)
        let tip = CGPoint(x: rect.maxX + tailLength, y: middle - tailRise)
        // ...then each side moved in by the inset, meeting the other and the inset edge.
        let top = Self.side(from: upper, to: tip, moved: insetAmount, toward: lower)
        let bottom = Self.side(from: lower, to: tip, moved: insetAmount, toward: upper)
        let edge: Line = (CGPoint(x: box.maxX, y: box.minY), CGVector(dx: 0, dy: 1))

        var path = Path()
        path.move(to: CGPoint(x: box.midX, y: box.minY))
        path.addArc(tangent1End: CGPoint(x: box.maxX, y: box.minY), tangent2End: CGPoint(x: box.maxX, y: box.maxY), radius: radius)
        path.addLine(to: Self.crossing(top, edge) ?? upper)
        path.addLine(to: Self.crossing(top, bottom) ?? tip)
        path.addLine(to: Self.crossing(bottom, edge) ?? lower)
        path.addArc(tangent1End: CGPoint(x: box.maxX, y: box.maxY), tangent2End: CGPoint(x: box.minX, y: box.maxY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: box.minX, y: box.maxY), tangent2End: CGPoint(x: box.minX, y: box.minY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: box.minX, y: box.minY), tangent2End: CGPoint(x: box.maxX, y: box.minY), radius: radius)
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> SpeechBubble {
        var shape = self
        shape.insetAmount += amount
        return shape
    }

    private typealias Line = (point: CGPoint, direction: CGVector)

    /// The line from `start` to `end`, moved `distance` towards `inside`.
    private static func side(from start: CGPoint, to end: CGPoint, moved distance: CGFloat, toward inside: CGPoint) -> Line {
        let direction = CGVector(dx: end.x - start.x, dy: end.y - start.y)
        let length = max((direction.dx * direction.dx + direction.dy * direction.dy).squareRoot(), 0.001)
        var normal = CGVector(dx: -direction.dy / length, dy: direction.dx / length)
        if normal.dx * (inside.x - start.x) + normal.dy * (inside.y - start.y) < 0 {
            normal = CGVector(dx: -normal.dx, dy: -normal.dy)
        }
        return (CGPoint(x: start.x + normal.dx * distance, y: start.y + normal.dy * distance), direction)
    }

    /// Where two lines cross, or nil when they run side by side.
    private static func crossing(_ a: Line, _ b: Line) -> CGPoint? {
        let cross = a.direction.dx * b.direction.dy - a.direction.dy * b.direction.dx
        guard abs(cross) > 0.000_001 else { return nil }
        let along = ((b.point.x - a.point.x) * b.direction.dy - (b.point.y - a.point.y) * b.direction.dx) / cross
        return CGPoint(x: a.point.x + a.direction.dx * along, y: a.point.y + a.direction.dy * along)
    }
}

/// Fairyland Online's rebirth: from level 101 (5 more each time), for gold.
private struct RebirthPanel: View {
    let session: GameSession
    @Binding var reply: String?
    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().overlay(HUDStyle.cream.opacity(0.3))
            Text(L("Rebirth")).font(HUDStyle.font(13)).foregroundStyle(HUDStyle.gold)
            Text(L("Each rebirth earns a fifth more EXP in battle (up to double), a title, and a new colour for your name."))
                .font(HUDStyle.font(11)).foregroundStyle(HUDStyle.cream)
                .fixedSize(horizontal: false, vertical: true)
            if session.data.hero.level < session.rebirthLevel {
                Text(L("Reach level {level} and I can help you be reborn: back to level 1, keeping your skills and some of your strength.", ["level": session.rebirthLevel]))
                    .font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
                    .fixedSize(horizontal: false, vertical: true)
            } else if confirming {
                Text(L("Start again at level 1? You keep your skills, pets and items."))
                    .font(HUDStyle.font(11))
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(L("Be reborn ({gold}g)", ["gold": session.rebirthCost])) {
                        session.rebirth()
                        confirming = false
                        reply = L("Welcome back, little one. You'll grow even stronger this time.")
                    }
                    .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
                    Button(L("Not yet")) { confirming = false }
                        .buttonStyle(PixelButtonStyle(compact: true))
                }
            } else {
                Button {
                    if session.canRebirth {
                        confirming = true
                    } else {
                        reply = L("Rebirth costs {gold} gold. Come back when you have it.", ["gold": session.rebirthCost])
                    }
                } label: {
                    Label(L("Be reborn ({gold}g)", ["gold": session.rebirthCost]), icon: .sparkles)
                }
                .buttonStyle(PixelButtonStyle(tint: session.canRebirth ? HUDStyle.gold : HUDStyle.dim, compact: true))
            }
        }
    }
}

private struct HealerPanel: View {
    let session: GameSession
    @Binding var reply: String?

    var body: some View {
        Button {
            session.restParty()
            session.post(L("Your party is fully rested."), .reward)
            session.save()
            reply = L("There you go! Everyone is fully rested.")
        } label: {
            Label(L("Rest and recover (free)"), icon: .heartPlus)
        }
        .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold))
    }
}

private struct ShopPanel: View {
    let session: GameSession
    let stock: [String]
    @Binding var reply: String?
    /// Tap an item for everything about it (who can use it, from what level).
    @Binding var info: ItemDef?
    @State private var selling = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(L("{gold} gold", ["gold": session.data.gold]), icon: .coins)
                    .font(HUDStyle.font(12))
                    .foregroundStyle(HUDStyle.gold)
                Spacer()
                Button(L("Buy")) { selling = false }
                    .buttonStyle(PixelButtonStyle(tint: selling ? HUDStyle.cream : HUDStyle.gold, compact: true))
                Button(L("Sell")) { selling = true }
                    .buttonStyle(PixelButtonStyle(tint: selling ? HUDStyle.gold : HUDStyle.cream, compact: true))
            }
            if selling {
                sellList
            } else {
                buyList
            }
        }
    }

    private var buyList: some View {
        ForEach(stock.compactMap { session.content.item($0) }) { item in
            HStack(spacing: 10) {
                Button { info = item } label: {
                    HStack(spacing: 10) {
                        ItemIcon(item: item, size: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name)
                            let detail = item.type == .consumable ? (item.description ?? "") : "\(item.type.displayName) · \(item.stats?.bonusSummary ?? "")"
                            // Two lines at most: a tap opens the card with all of it.
                            Text(detail).font(HUDStyle.font(10)).foregroundStyle(HUDStyle.green).lineLimit(2)
                            if item.type != .consumable, let issue = session.equipIssue(item) {
                                Text(issue).font(HUDStyle.font(10)).foregroundStyle(HUDStyle.orange)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(L("Shows what it does and who can use it"))
                if session.count(of: item.id) > 0 {
                    Text(L("own {count}", ["count": session.count(of: item.id)])).font(HUDStyle.font(10)).foregroundStyle(HUDStyle.dim)
                }
                Button(L("{gold}g", ["gold": item.price])) {
                    if session.buy(item.id) {
                        session.post(L("Bought {item}.", ["item": item.name]), .reward)
                        reply = L("Thanks! Enjoy your {item}.", ["item": item.name])
                    } else {
                        reply = L("Hmm, you're a bit short on gold.")
                    }
                }
                .buttonStyle(PixelButtonStyle(tint: session.data.gold >= item.price ? HUDStyle.gold : HUDStyle.dim, compact: true))
            }
            .font(HUDStyle.font(12))
        }
    }

    /// Everything in your bag the shop will take, at half price. What you're wearing stays on.
    @ViewBuilder
    private var sellList: some View {
        let items = session.sellableItems
        if items.isEmpty {
            Text(L("Nothing to sell. Monsters drop materials, and gear you've outgrown can come here."))
                .font(HUDStyle.font(11))
                .foregroundStyle(HUDStyle.dim)
        }
        ForEach(items) { item in
            HStack(spacing: 10) {
                Button { info = item } label: {
                    HStack(spacing: 10) {
                        ItemIcon(item: item, size: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name)
                            Text(L("{type} · you have {count}", ["type": item.type.displayName, "count": session.count(of: item.id)]))
                                .font(HUDStyle.font(10))
                                .foregroundStyle(HUDStyle.dim)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(L("Shows what it does and who can use it"))
                Button(L("Sell {gold}g", ["gold": GameSession.sellPrice(of: item)])) {
                    if let paid = session.sell(item.id) {
                        session.post(L("Sold {item} for {gold} gold.", ["item": item.name, "gold": paid]), .reward)
                        reply = L("A fine {item}! Here's {gold} gold.", ["item": item.name, "gold": paid])
                    }
                }
                .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
            }
            .font(HUDStyle.font(12))
        }
    }
}

private struct QuestGiverPanel: View {
    let session: GameSession
    let giver: String
    @Binding var reply: String?
    @Binding var finished: FinishedQuest?
    @State private var asking: String?

    var body: some View {
        let quests = session.quests(from: giver).filter { session.status(of: $0) != .completed }
        VStack(alignment: .leading, spacing: 8) {
            if quests.isEmpty {
                // Why there's nothing, and where there's work instead.
                Text(session.questGiverNote(giver)).font(HUDStyle.font(12)).foregroundStyle(HUDStyle.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(quests) { quest in
                VStack(alignment: .leading, spacing: 6) {
                    QuestRow(session: session, quest: quest)
                    switch session.status(of: quest) {
                    case .available:
                        if asking == quest.id, let question = quest.question {
                            Text(question.text).font(HUDStyle.font(12)).foregroundStyle(HUDStyle.gold)
                            HStack {
                                ForEach(question.answers, id: \.text) { answer in
                                    Button(answer.text) {
                                        session.acceptQuest(quest.id, answer: answer)
                                        asking = nil
                                        reply = L("{answer}… a fine answer. Here are your gifts. Hatch that egg and come show me!", ["answer": answer.text])
                                    }
                                    .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
                                }
                            }
                        } else {
                            Button(L("Accept")) {
                                if quest.question != nil {
                                    asking = quest.id
                                    reply = quest.question?.text
                                } else {
                                    session.acceptQuest(quest.id)
                                    reply = L("Wonderful! I knew I could count on you.")
                                }
                            }
                            .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
                        }
                    case .ready:
                        Button(L("Complete quest")) {
                            let level = session.data.hero.level
                            session.turnInQuest(quest.id)
                            session.save()
                            reply = L("Thank you! You've been a great help.")
                            let reached = session.data.hero.level
                            finished = FinishedQuest(quest: quest, newLevel: reached > level ? reached : nil, levelsGained: reached - level)
                            if reached > level {
                                // The level-up jingle after the quest's own little fanfare.
                                Task {
                                    try? await Task.sleep(for: .milliseconds(600))
                                    SoundEffects.shared.play(.levelUp)
                                }
                            }
                        }
                        .buttonStyle(PixelButtonStyle(tint: HUDStyle.green, compact: true))
                    default:
                        EmptyView()
                    }
                }
            }
        }
    }
}

private struct GuildPanel: View {
    let session: GameSession
    let classID: String
    @Binding var reply: String?
    @State private var confirming = false

    var body: some View {
        let path = session.content.classDef(classID)
        let hero = session.data.hero
        let skillList = path.skills.compactMap { unlock in session.content.skill(unlock.skill).map { L("{skill} (Lv {level})", ["skill": $0.name, "level": unlock.level]) } }.joined(separator: ", ")
        VStack(alignment: .leading, spacing: 8) {
            Text(L("{guild}: {className}", ["guild": path.guild ?? L("Guild"), "className": path.name])).font(HUDStyle.font(13)).foregroundStyle(HUDStyle.gold)
            Text(path.description).font(HUDStyle.font(11))
            Text(L("Skills: {skills}", ["skills": skillList]))
                .font(HUDStyle.font(10))
                .foregroundStyle(HUDStyle.dim)

            if hero.classID == path.id {
                Text(L("Welcome back, {className}!", ["className": path.name])).font(HUDStyle.font(12)).foregroundStyle(HUDStyle.green)
            } else if hero.classID != "novice" {
                Text(L("You've already chosen the path of the {className}.", ["className": session.heroClass.name])).font(HUDStyle.font(12)).foregroundStyle(HUDStyle.dim)
            } else if !session.canChooseClass {
                Text(L("Come back when you reach level {level}.", ["level": session.content.classChoiceLevel])).font(HUDStyle.font(12)).foregroundStyle(HUDStyle.dim)
            } else if confirming {
                HStack {
                    Text(L("This choice is permanent. Sure?")).font(HUDStyle.font(12))
                    Button(L("Yes, become a {className}", ["className": path.name])) {
                        session.chooseClass(path.id)
                        session.save()
                        reply = L("Welcome to the {guild}, {className}! Your new skills await.", ["guild": path.guild ?? L("guild"), "className": path.name])
                    }
                    .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
                    Button(L("Not yet")) { confirming = false }
                        .buttonStyle(PixelButtonStyle(compact: true))
                }
            } else {
                Button(L("Join and become a {className}", ["className": path.name])) { confirming = true }
                    .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold))
            }
        }
    }
}

/// A boss: how strong it is, and a button to take it on.
private struct BossPanel: View {
    let session: GameSession
    let boss: NPCDef
    let onFight: (NPCDef) -> Void

    var body: some View {
        let species = boss.monster.flatMap(session.content.monster)
        let level = boss.level ?? 10
        VStack(alignment: .leading, spacing: 8) {
            if let species {
                HStack(spacing: 8) {
                    Text(L("Lv {level} {monster}", ["level": level, "monster": species.name])).foregroundStyle(HUDStyle.gold)
                    ElementBadge(element: species.element)
                }
                .font(HUDStyle.font(13))
                if level > session.data.hero.level + 2 {
                    Text(L("This looks really dangerous at your level…")).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.orange)
                }
            }
            if let drops = species?.drops, !drops.isEmpty {
                let names = drops.compactMap { session.content.item($0.item)?.name }
                Text(L("Rare drops: {items}", ["items": names.joined(separator: ", ")])).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
            }
            if session.isBeatenHere(boss) {
                EmptyNote(L("Beaten! It'll be back next time you come by."))
            } else {
                Button { onFight(boss) } label: { Label(session.isDefeated(boss) ? L("Rematch!") : L("Fight!"), icon: .sword) }
                    .buttonStyle(PixelButtonStyle(tint: Color(red: 1, green: 0.55, blue: 0.5)))
            }
        }
    }
}

/// A quest you just handed in, and the level it took you to (if any).
struct FinishedQuest {
    let quest: QuestDef
    let newLevel: Int?
    var levelsGained = 0
}

/// "Quest complete!": what the quest paid, laid out like the victory card after a battle (EXP with
/// a star, gold with coins, the level-up banner, items as tiles), then roads. A
/// level-up follows with the skill card, as after a battle.
private struct QuestCompleteCard: View {
    let session: GameSession
    let finished: FinishedQuest
    let onDone: () -> Void
    @State private var levelUp = false

    private var quest: QuestDef { finished.quest }

    /// Items in reward order, repeats counted.
    private var loot: [(id: String, count: Int)] {
        var result: [(id: String, count: Int)] = []
        for id in quest.reward.items ?? [] {
            if let index = result.firstIndex(where: { $0.id == id }) {
                result[index].count += 1
            } else {
                result.append((id: id, count: 1))
            }
        }
        return result
    }

    private var roads: [String] {
        let content = session.content
        return content.maps.flatMap { map in
            map.exits.filter { $0.requires == quest.id }.map { "\(map.name) → \(content.map($0.to)?.name ?? $0.to)" }
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
                .onTapGesture {}
            if levelUp, let level = finished.newLevel {
                LevelUpCard(session: session, level: level, onDone: onDone)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else {
                card
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: levelUp)
    }

    private func advance() {
        if !levelUp, finished.newLevel != nil, session.canSpendSkillPoint {
            levelUp = true
        } else {
            onDone()
        }
    }

    private var card: some View {
        VStack(spacing: 10) {
            VStack(spacing: 2) {
                Text(L("Quest complete!"))
                    .font(HUDStyle.font(24))
                    .foregroundStyle(HUDStyle.gold)
                    // Clear of the close button, and still centred.
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 18)
                Text(quest.title)
                    .font(HUDStyle.font(14))
                    .foregroundStyle(HUDStyle.cream)
                    .multilineTextAlignment(.center)
            }
            // Scrolls only when it can't all fit (a phone on its side after a big quest).
            ViewThatFits(in: .vertical) {
                rewards
                ScrollView { rewards }
                    .scrollBounceBehavior(.basedOnSize)
            }
            Button(L("Continue"), action: advance)
                .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold))
                .padding(.top, 6)
        }
        .padding(22)
        .frame(maxWidth: 420)
        .gameWindow()
        // Closing it is Continue: the rewards are already yours.
        .windowCloseButton(advance)
        .padding(20)
    }

    /// EXP and gold, the level-up, items, then roads.
    private var rewards: some View {
        VStack(spacing: 10) {
            let paid = session.paid(for: quest)
            let gold = paid.gold
            let exp = paid.exp
            if gold > 0 || exp > 0 {
                HStack(spacing: 18) {
                    if exp > 0 {
                        Label { Text(L("+{exp} EXP", ["exp": exp])) } icon: {
                            IconImage(.star, size: 18).foregroundStyle(HUDStyle.exp)
                        }
                    }
                    if gold > 0 {
                        Label { Text("+\(gold)") } icon: {
                            IconImage(.coins, size: 18).foregroundStyle(HUDStyle.gold)
                        }
                    }
                }
                .font(HUDStyle.font(16))
                .foregroundStyle(HUDStyle.cream)
            }
            if let level = finished.newLevel {
                LevelUpBanner(level: level, gains: session.heroClass.growth * finished.levelsGained)
            }
            if !loot.isEmpty {
                LootGrid(loot: loot, title: L("Got"))
            }
            if !roads.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(roads, id: \.self) { road in
                        Label(L("Road open: {road}", ["road": road]), icon: .map, size: 14)
                    }
                }
                .font(HUDStyle.font(12))
                .foregroundStyle(HUDStyle.cream)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.06)))
            }
        }
    }
}
