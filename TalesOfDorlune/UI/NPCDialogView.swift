import SwiftUI

/// Talking to someone: the healer, the shop, the quest giver, a guild master or a boss.
struct NPCDialogView: View {
    let npc: NPCDef
    let session: GameSession
    let onClose: () -> Void
    /// Bosses: start the fight.
    var onFight: (NPCDef) -> Void = { _ in }
    /// Bankers: open the bank's window.
    var onBank: (NPCDef) -> Void = { _ in }
    @State private var reply: String?
    /// A quest just handed in: its reward card covers the dialog until you continue.
    @State private var finished: FinishedQuest?
    /// An item tapped in the shop or at the smith, for a closer look.
    @State private var info: ItemDef? = DebugLaunch.itemInfo
    /// How many of a potion or material to buy or sell, in a window over the shop. Debug
    /// `deal=<item>` (or `sell=<item>`) opens one.
    @State private var deal: ShopDeal? = DebugLaunch.shopDeal.flatMap { wanted in
        Content.shared.item(wanted.item).map { ShopDeal(item: $0, selling: wanted.selling) }
    }

    var body: some View {
        GeometryReader { proxy in
            // Fairyland Online-style: the character stands big in the bottom-right corner, cut off by the
            // edge of the screen, over the window they talk from, which runs the width of the screen
            // (playtesting 2026-10-26: a speech bubble beside them, its tail pointing at them, was
            // narrow). What's in the window keeps clear of them (`speakerRoom`).
            let portrait = min(proxy.size.width * 0.42, proxy.size.height * 0.55, 280)
            let bottom = max(16, proxy.safeAreaInsets.bottom)
            ZStack(alignment: .bottomTrailing) {
                Color.black.opacity(0.35)
                    .onTapGesture(perform: onClose)

                bubble(maxHeight: proxy.size.height * 0.5, speakerRoom: portrait * 0.5)
                    .padding(.horizontal, 12)
                    .padding(.bottom, bottom)

                SpriteImage(art: npc.art, size: portrait)
                    .offset(x: portrait * 0.22, y: portrait * 0.16)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

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

                if let deal {
                    ItemDealWindow(session: session, item: deal.item, selling: deal.selling,
                                   price: deal.selling ? GameSession.sellPrice(of: deal.item) : deal.item.price,
                                   onDeal: { count in
                                       let said: String? = deal.selling ? ShopPanel.sell(deal.item, count, session: session)
                                                               : ShopPanel.buy(deal.item, count, session: session)
                                       if let said { reply = said }
                                       self.deal = nil
                                   },
                                   onClose: { self.deal = nil })
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .transition(.opacity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .animation(.easeOut(duration: 0.2), value: finished?.quest.id)
            .animation(.easeOut(duration: 0.15), value: info?.id)
            .animation(.easeOut(duration: 0.15), value: deal?.id)
        }
        .ignoresSafeArea()
    }

    /// The window they talk from: what they say and its buttons lined up under their name, all
    /// clear of the `speakerRoom` the character stands in at the right.
    private func bubble(maxHeight: CGFloat, speakerRoom: CGFloat) -> some View {
        let window = RoundedRectangle(cornerRadius: HUDStyle.windowRadius)
        return VStack(alignment: .leading, spacing: 0) {
            WindowTitle(npc.name)
                .padding(.trailing, speakerRoom)
            VStack(alignment: .leading, spacing: 10) {
                if npc.role == .quests {
                    QuestConversation(session: session, giver: npc, reply: $reply, finished: $finished,
                                      room: min(260, max(120, maxHeight - 110)))
                } else {
                    talk(maxHeight: maxHeight)
                }
            }
            // In line with the name (`WindowTitle`'s 16 points in).
            .padding(.leading, 16)
            .padding(.trailing, 12 + speakerRoom)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(HUDStyle.cream)
        .clipShape(window)
        // The frame all the way round, like every window's (`gameWindow`), the close button over its corner.
        .background(window.fill(HUDStyle.glass).shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 2))
        .overlay(HUDStyle.frame(window))
        .windowCloseButton(onClose)
    }

    /// What everyone but a quest giver says, and what they do for you under it.
    @ViewBuilder
    private func talk(maxHeight: CGFloat) -> some View {
        Text(reply ?? npc.greeting)
            .font(HUDStyle.font(13))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // A favour you're carrying to them, whoever they are.
                ErrandPanel(session: session, npcID: npc.id, reply: $reply)
                Group {
                    switch npc.role {
                    case .healer: HealerPanel(session: session, reply: $reply)
                    case .shop: ShopPanel(session: session, stock: npc.stock ?? [], reply: $reply, info: $info, deal: $deal)
                    case .quests: EmptyView()   // QuestConversation
                    case .guild: GuildPanel(session: session, classID: npc.classId ?? "", reply: $reply)
                    case .chest, .stairs, .waystone: EmptyView()   // straight from the map (GameCoordinator.open)
                    case .boss: BossPanel(session: session, boss: npc, onFight: onFight)
                    case .smith: SmithPanel(session: session, reply: $reply, info: $info)
                    case .weaver: CapePanel(session: session, reply: $reply, info: $info)
                    case .barber: BarberPanel(session: session, price: npc.price ?? 1000, reply: $reply)
                    case .bank:
                        // The bank itself opens in a window of its own (`BankView`), with room to see it all.
                        Button {
                            onBank(npc)
                        } label: {
                            Label(L("Open the bank"), icon: .coins)
                        }
                        .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxHeight: min(260, max(120, maxHeight - 110)))
    }
}

/// The weaver's capes (rewards.json `prizes`), like RuneScape's capes for a skill at 99: each with
/// what it takes and how far along you are, those she can weave you now first. Tap one to see it.
private struct CapePanel: View {
    let session: GameSession
    @Binding var reply: String?
    @Binding var info: ItemDef?

    var body: some View {
        let waiting = session.capesWaiting
        let rest = session.prizes.filter { prize in !waiting.contains { $0.item == prize.item } }
        VStack(alignment: .leading, spacing: 8) {
            ForEach(waiting + rest) { prize in
                if let item = session.content.item(prize.item) { row(prize, item) }
            }
        }
    }

    private func row(_ prize: RewardsDef.Prize, _ item: ItemDef) -> some View {
        let progress = session.prizeProgress(prize)
        let earned = session.hasEarned(prize)
        return HStack(spacing: 8) {
            Button { info = item } label: {
                ItemIcon(item: item, size: 32).opacity(earned ? 1 : 0.55)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(HUDStyle.font(12)).foregroundStyle(earned ? HUDStyle.gold : HUDStyle.cream)
                Text(session.prizeRequirement(prize)).font(HUDStyle.font(10)).foregroundStyle(HUDStyle.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if session.hasCape(prize) {
                IconImage(.checkCircle, size: 16).foregroundStyle(HUDStyle.gold)
            } else if earned {
                Button(L("Weave it")) {
                    if session.takeCape(prize) {
                        reply = L("There: the {cape}. Wear it with pride.", ["cape": item.name])
                    }
                }
                .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
            } else {
                Text(verbatim: "\(progress.have)/\(progress.need)").font(HUDStyle.mono(10)).foregroundStyle(HUDStyle.dim)
            }
        }
    }
}

/// A barber (playtesting 2026-10-21: "You should be able to change your hair style and color
/// somewhere in the game, at a barber in a town"): the hairstyles and hair colours you made your hero
/// with, tried on the turning preview first (bare-headed, so a helmet doesn't hide the cut), and the
/// fee (`NPCDef.price`) once you like it. Only the hair changes; the rest of the look stays.
private struct BarberPanel: View {
    let session: GameSession
    let price: Int
    @Binding var reply: String?
    @State private var look: Look

    init(session: GameSession, price: Int, reply: Binding<String?>) {
        self.session = session
        self.price = price
        _reply = reply
        _look = State(initialValue: session.data.hero.look ?? .standard)
    }

    var body: some View {
        let race = session.heroRace
        let current = session.data.hero.look ?? .standard
        let changed = look.hair != current.hair || GameSession.style(for: look, race: race) != GameSession.style(for: current, race: race)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                TurntablePreview(look: look, race: race, size: 92)
                VStack(alignment: .leading, spacing: 8) {
                    StylePicker(look: $look, race: race)
                    SwatchPicker(title: L("Hair"), presets: session.content.appearance.hair, selection: $look.hair)
                }
            }
            HStack {
                GoldPill(amount: session.data.gold, size: 12)
                Spacer()
                Button {
                    reply = session.restyle(look, price: price)
                        ? L("There! It suits you.")
                        : L("That'll be {gold} gold, when you have it.", ["gold": price])
                } label: {
                    Label(L("New look for {gold} gold", ["gold": price]), icon: .palette)
                }
                .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold))
                .disabled(!changed)
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

/// How many of a thing to buy or sell at a shop, in a window over the dialog (`ItemDealWindow`).
private struct ShopDeal {
    let item: ItemDef
    let selling: Bool
    var id: String { "\(selling ? "sell" : "buy").\(item.id)" }
}

private struct ShopPanel: View {
    let session: GameSession
    let stock: [String]
    @Binding var reply: String?
    /// Tap an item for everything about it (who can use it, from what level).
    @Binding var info: ItemDef?
    /// A potion or material with more than one to buy or sell: how many, in a window of its own.
    @Binding var deal: ShopDeal?
    @State private var selling = DebugLaunch.shopDeal?.selling ?? false

    /// Buys `count` and says so; what the shopkeeper says back.
    static func buy(_ item: ItemDef, _ count: Int, session: GameSession) -> String {
        guard session.buy(item.id, count) else { return L("Hmm, you're a bit short on gold.") }
        let name = count > 1 ? "\(item.name) ×\(count)" : item.name
        session.post(L("Bought {item}.", ["item": name]), .reward)
        return L("Thanks! Enjoy your {item}.", ["item": name])
    }

    /// Sells `count` and says so; what the shopkeeper says back, if they were sold.
    static func sell(_ item: ItemDef, _ count: Int, session: GameSession) -> String? {
        guard let paid = session.sell(item.id, count) else { return nil }
        let name = count > 1 ? "\(item.name) ×\(count)" : item.name
        session.post(L("Sold {item} for {gold} gold.", ["item": name, "gold": paid]), .reward)
        return L("A fine {item}! Here's {gold} gold.", ["item": name, "gold": paid])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                GoldPill(amount: session.data.gold, size: 12)
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
                    // A potion or material, with coins and room for more than one: how many first.
                    if GameSession.sellsInBulk(item) && session.affordable(at: item.price) > 1 {
                        deal = ShopDeal(item: item, selling: false)
                    } else {
                        reply = Self.buy(item, 1, session: session)
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
                    // A potion or material you have more than one of: how many first.
                    if GameSession.sellsInBulk(item) && session.count(of: item.id) > 1 {
                        deal = ShopDeal(item: item, selling: true)
                    } else if let said = Self.sell(item, 1, session: session) {
                        reply = said
                    }
                }
                .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
            }
            .font(HUDStyle.font(12))
        }
    }
}

/// What you've brought someone for a `deliver` quest: a button to hand each one over. Nothing when
/// you've nothing for them.
private struct ErrandPanel: View {
    let session: GameSession
    let npcID: String
    @Binding var reply: String?

    var body: some View {
        let errands = session.errands(for: npcID)
        if !errands.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(errands) { quest in
                    let item = quest.objective.item.flatMap(session.content.item)
                    HStack(spacing: 8) {
                        if let item { ItemIcon(item: item, size: 28) }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(quest.title).font(HUDStyle.font(12))
                            if let giver = session.content.npc(quest.giver) {
                                Text(L("A favour for {name}", ["name": giver.name])).font(HUDStyle.font(10)).foregroundStyle(HUDStyle.dim)
                            }
                        }
                        Spacer(minLength: 4)
                        Button(item.map { L("Give {item}", ["item": $0.name]) } ?? L("Pass it on")) {
                            if let said = session.deliver(quest.id) {
                                session.save()
                                reply = said
                            }
                        }
                        .buttonStyle(PixelButtonStyle(tint: HUDStyle.green, compact: true))
                    }
                }
            }
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A quest giver, talked to a page at a time (playtesting 2026-10-25: "it needs to be conversational,
/// with next and back buttons [...] One should be completed first with storytelling"). They talk about
/// one quest at a time (`GameSession.currentQuest`): its story told in the sentences of its description,
/// Back and Next between them, and on the last page the quest itself and what you can do: take it on,
/// hear it again, or hand it in. Handing one in leads into the next one's story.
private struct QuestConversation: View {
    let session: GameSession
    let giver: NPCDef
    @Binding var reply: String?
    @Binding var finished: FinishedQuest?
    /// How tall the quest and its buttons may grow before they scroll.
    let room: CGFloat
    @State private var page = DebugLaunch.talkPage ?? 0
    /// What they said to what you just did (took the quest on, handed one in): it opens what follows.
    @State private var said: String?
    /// The quest you're on, told again from the start.
    @State private var retelling = false
    /// The answer picked to a quest's question, not yet confirmed.
    @State private var picked: String?

    var body: some View {
        let quest = session.currentQuest(from: giver.id)
        let told = (reply.map { [$0] } ?? []) + script(quest)
        let lines = told.isEmpty ? [giver.greeting] : told
        let index = min(page, lines.count - 1)
        let last = index == lines.count - 1
        VStack(alignment: .leading, spacing: 10) {
            // A favour you're carrying to them: what they say to it comes first.
            ErrandPanel(session: session, npcID: giver.id, reply: $reply)
            Text(lines[index])
                .font(HUDStyle.font(13))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 50, alignment: .topLeading)
                .contentShape(Rectangle())
                // A tap on what they're saying reads on, as Next does.
                .onTapGesture { if !last { turn(from: index, by: 1, of: lines.count) } }
                .accessibilityAddTraits(last ? [] : .isButton)
                .accessibilityHint(last ? "" : L("Next"))
                .id(index)
                .transition(.opacity)
            if last, let quest {
                ScrollView { offer(quest) }
                    .frame(maxHeight: room)
            }
            if lines.count > 1 {
                navigation(index: index, count: lines.count)
            }
        }
        .onChange(of: reply) { _, _ in page = 0 }
    }

    /// What they say, page by page, about where you are with them.
    private func script(_ quest: QuestDef?) -> [String] {
        let opening = said ?? giver.greeting
        guard let quest else { return [opening, session.questGiverNote(giver.id)] }
        switch session.status(of: quest) {
        case .available:
            // The question (which egg hatches) is asked on the last page, its answers taking it on.
            return [opening] + Conversation.pages(quest.description) + (quest.question.map { [$0.text] } ?? [])
        case .ready:
            return [said ?? L("You're back! Did you manage it?")]
        default:
            return retelling ? Conversation.pages(quest.description) : [said ?? L("How are you getting on?")]
        }
    }

    /// The quest on the last page, and what you can do about it.
    @ViewBuilder
    private func offer(_ quest: QuestDef) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            QuestRow(session: session, quest: quest, showsDescription: false)
            switch session.status(of: quest) {
            case .available:
                if let question = quest.question {
                    // Cards to pick from, one a row so a long answer reads whole; Confirm, bottom
                    // right where Next was, takes the one picked (playtesting 2026-10-26: buttons
                    // that answered at a tap, three a row, broke their words).
                    VStack(spacing: 6) {
                        ForEach(question.answers, id: \.text) { answer in
                            AnswerCard(text: answer.text, picked: picked == answer.text) {
                                withAnimation(.easeOut(duration: 0.15)) { picked = answer.text }
                            }
                        }
                    }
                } else {
                    Button(L("Accept")) {
                        session.acceptQuest(quest.id)
                        begin(L("Wonderful! I knew I could count on you."))
                    }
                    .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
                }
            case .ready:
                Button(L("Complete quest")) { handIn(quest) }
                    .buttonStyle(PixelButtonStyle(tint: HUDStyle.green, compact: true))
            case .active:
                Button(L("Tell me again")) {
                    retelling = true
                    withAnimation(.easeOut(duration: 0.15)) { page = 0 }
                }
                .buttonStyle(PixelButtonStyle(compact: true))
            default:
                EmptyView()
            }
        }
    }

    private func navigation(index: Int, count: Int) -> some View {
        HStack(spacing: 8) {
            // Back from the second page on (the onboarding's carousel does the same).
            Button { turn(from: index, by: -1, of: count) } label: { Label(L("Back"), icon: .arrowLeft, size: 12) }
                .buttonStyle(PixelButtonStyle(compact: true))
                .opacity(index == 0 ? 0 : 1)
                .disabled(index == 0)
                .accessibilityHidden(index == 0)
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                ForEach(0..<count, id: \.self) { dot in
                    Circle()
                        .fill(dot == index ? HUDStyle.gold : HUDStyle.cream.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityHidden(true)
            Spacer(minLength: 0)
            if index == count - 1, let quest = session.currentQuest(from: giver.id),
               session.status(of: quest) == .available, let question = quest.question {
                // On the question's page: Confirm, once an answer's picked.
                let answer = question.answers.first { $0.text == picked }
                Button {
                    guard let answer else { return }
                    session.acceptQuest(quest.id, answer: answer)
                    begin(L("{answer}… a fine answer. Here are your gifts. Hatch that egg and come show me!", ["answer": answer.text]))
                } label: {
                    HStack(spacing: 5) {
                        Text(L("Confirm"))
                        IconImage(.check, size: 12)
                    }
                }
                .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
                .opacity(answer == nil ? 0 : 1)
                .disabled(answer == nil)
                .accessibilityHidden(answer == nil)
            } else {
                // The arrow after the word, pointing the way it goes.
                Button { turn(from: index, by: 1, of: count) } label: {
                    HStack(spacing: 5) {
                        Text(L("Next"))
                        IconImage(.arrowRight, size: 12)
                    }
                }
                .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
                .opacity(index == count - 1 ? 0.4 : 1)
                .disabled(index == count - 1)
            }
        }
    }

    private func turn(from index: Int, by step: Int, of count: Int) {
        withAnimation(.easeOut(duration: 0.15)) { page = max(0, min(index + step, count - 1)) }
    }

    /// The conversation starts over from what they just said.
    private func begin(_ line: String) {
        reply = nil
        said = line
        retelling = false
        picked = nil
        page = 0
    }

    private func handIn(_ quest: QuestDef) {
        let level = session.data.hero.level
        session.turnInQuest(quest.id)
        session.save()
        let reached = session.data.hero.level
        finished = FinishedQuest(quest: quest, newLevel: reached > level ? reached : nil, levelsGained: reached - level)
        if reached > level {
            // The level-up jingle after the quest's own little fanfare.
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                SoundEffects.shared.play(.levelUp)
            }
        }
        // Thanks, and into the next one's story if they have one for you.
        let thanks = L("Thank you! You've been a great help.")
        begin(session.currentQuest(from: giver.id) == nil ? thanks : thanks + " " + L("There's more, if you'll hear me out."))
    }
}

/// One answer to a quest giver's question, as a card: tap to pick it (gold-edged, ticked), then
/// Confirm takes it.
private struct AnswerCard: View {
    let text: String
    let picked: Bool
    let pick: () -> Void

    var body: some View {
        let card = RoundedRectangle(cornerRadius: 10)
        Button(action: pick) {
            HStack(spacing: 8) {
                Text(text)
                    .font(HUDStyle.font(13))
                    .foregroundStyle(picked ? HUDStyle.gold : HUDStyle.cream)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // A ring, filled and ticked once picked.
                ZStack {
                    Circle().strokeBorder(picked ? HUDStyle.gold : HUDStyle.cream.opacity(0.45), lineWidth: 1.5)
                    if picked {
                        Circle().fill(HUDStyle.gold).padding(1)
                        IconImage(.check, size: 10).foregroundStyle(HUDStyle.ink)
                    }
                }
                .frame(width: 20, height: 20)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(card.fill(picked ? HUDStyle.gold.opacity(0.18) : HUDStyle.cream.opacity(0.07)))
            .overlay(card.strokeBorder(picked ? HUDStyle.gold : HUDStyle.cream.opacity(0.2), lineWidth: picked ? 2 : 1))
            .contentShape(card)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(picked ? .isSelected : [])
        .onChange(of: picked) { _, now in
            if now { SoundEffects.shared.play(.tap, volume: 0.7) }
        }
    }
}

/// What someone says, a page at a time.
nonisolated enum Conversation {
    /// `text` in pages to read one at a time: whole sentences, as many as fit in about three lines of
    /// the bubble (a character of Chinese, Japanese or Korean counts as two and a half of Latin).
    static func pages(_ text: String) -> [String] {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .bySentences) { sentence, _, _, _ in
            if let sentence = sentence?.trimmingCharacters(in: .whitespacesAndNewlines), !sentence.isEmpty {
                sentences.append(sentence)
            }
        }
        guard !sentences.isEmpty else { return text.isEmpty ? [] : [text] }
        let weight = { (line: String) in line.unicodeScalars.reduce(0.0) { $0 + ($1.value >= 0x2E80 ? 2.5 : 1) } }
        var pages: [String] = []
        for sentence in sentences {
            if let last = pages.last, weight(last) + weight(sentence) <= 150 {
                let wide = sentence.unicodeScalars.first.map { $0.value >= 0x2E80 } ?? false
                pages[pages.count - 1] = last + (wide ? "" : " ") + sentence
            } else {
                pages.append(sentence)
            }
        }
        return pages
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
