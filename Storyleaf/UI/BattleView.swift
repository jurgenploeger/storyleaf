import SwiftUI
import UIKit

/// Battle HUD: what just happened in a slim line top centre, the chat top right, and the commands
/// round the big button bottom right, with the time to choose as a ring about it. How fast the
/// fight plays and Auto wait behind More. Results at the end. Names, levels, HP and MP sit on the
/// fighters themselves.
struct BattleView: View {
    let controller: BattleController
    /// Unread chat: a gold dot on the chat button.
    var unreadChat = false
    /// Opens the chat over the fight (GameView holds it); nil while it's open, which hides the button.
    var onChat: (() -> Void)? = nil
    /// A phone on its side: the line of what just happened can run wider.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        ZStack {
            topBar
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 8)
                .padding(.top, 4)

            commandArea
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 14)
                .padding(.bottom, 14)
                // While a round plays nothing here takes a tap, but Auto's button, to take over.
                .allowsHitTesting(controller.phase != .animating || controller.isAuto)

            if controller.phase == .finished, let result = controller.result {
                ResultPanel(result: result, session: controller.session, onContinue: controller.leave)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: controller.phase)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: controller.choosingForCompanion)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: controller.isAuto)
    }

    /// Along the top: what just happened, centred, and the chat at the right end.
    private var topBar: some View {
        ZStack(alignment: .topTrailing) {
            news
                .frame(maxWidth: verticalSizeClass == .compact ? 520 : 360)
                // Clear of the chat button whichever side, so it stays centred.
                .padding(.horizontal, 48)
                .frame(maxWidth: .infinity)
            chatButton
        }
    }

    /// The chat, top right as on the map; hidden while it's open and once the fight is over.
    @ViewBuilder
    private var chatButton: some View {
        if controller.phase != .finished, let onChat {
            FLIconButton(icon: .talk, label: L("Chat"), size: Self.chatSize, badge: unreadChat, action: onChat)
        }
    }

    private static let chatSize: CGFloat = 40

    /// What just happened, and in a boss fight how far through its waves you are.
    private var news: some View {
        VStack(spacing: 6) {
            // As tall as the chat button at least, so a one-line message sits level with it.
            logLine
                .frame(minHeight: Self.chatSize)
            if controller.waveCount > 1 {
                WaveTracker(wave: controller.wave, total: controller.waveCount)
            }
        }
        .allowsHitTesting(false)
    }

    /// One slim line of what just happened, or two when it's long.
    private var logLine: some View {
        Text(controller.message)
            .font(HUDStyle.font(12))
            .foregroundStyle(HUDStyle.cream)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(HUDStyle.ink.opacity(0.78)))
    }

    /// The commands bottom right; over a list or while picking a target, the time left to choose
    /// sits on top of it (with the commands it's the ring round the big button).
    private var commandArea: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if [.skills, .items, .stones, .target].contains(controller.phase),
               let deadline = controller.turnDeadline, let total = BattleController.turnSeconds {
                TurnClockBar(deadline: deadline, total: total)
                    .transition(.opacity)
            }
            commands
        }
    }

    @ViewBuilder
    private var commands: some View {
        switch controller.phase {
        case .command:
            if controller.choosingForCompanion {
                CompanionPad(controller: controller)
                    .padding(.top, 64)
                    .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
            } else {
                CommandPad(controller: controller)
                    .padding(.top, 64)   // clear of the log line
                    .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
            }
        case .skills where controller.choosingForCompanion:
            ChoiceCard(title: L("{companion}'s skills", ["companion": controller.companion?.name ?? L("Companion")]), icon: .paw, onBack: controller.back) {
                if controller.companionSkills.isEmpty {
                    EmptyNote(L("No skills yet."))
                }
                ForEach(controller.companionSkills) { skill in
                    let price = controller.companionCost(of: skill)
                    ChoiceRow(action: { controller.useSkill(skill) }, enabled: (controller.companion?.mp ?? 0) >= price) {
                        SkillIcon(skill: skill, size: 26)
                        Text(skill.name).lineLimit(1).minimumScaleFactor(0.75)
                        Text(L("Lv{level}", ["level": controller.companionLevel(of: skill)])).font(HUDStyle.mono(10)).foregroundStyle(HUDStyle.frameDark).fixedSize()
                        if let element = skill.element { ElementBadge(element: element) }
                        Spacer()
                        Text(L("{cost} MP", ["cost": price])).foregroundStyle(HUDStyle.mp)
                    }
                }
            }
            .transition(.scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity))
        case .skills:
            ChoiceCard(title: L("Skills"), icon: .sparkles, onBack: controller.back) {
                if controller.skills.isEmpty {
                    EmptyNote(controller.skills.isEmpty && !controller.session.learnableSkills.isEmpty
                              ? L("No skills yet.\nLearn one in the Character menu.")
                              : controller.session.skillHint)
                }
                ForEach(controller.skills) { skill in
                    let affordable = (controller.hero?.mp ?? 0) >= controller.cost(of: skill)
                    ChoiceRow(action: { controller.useSkill(skill) }, enabled: affordable) {
                        SkillIcon(skill: skill, size: 26)
                        Text(skill.name).lineLimit(1).minimumScaleFactor(0.75)
                        Text(L("Lv{level}", ["level": controller.level(of: skill)])).font(HUDStyle.mono(10)).foregroundStyle(HUDStyle.frameDark).fixedSize()
                        if let element = skill.element { ElementBadge(element: element) }
                        Spacer()
                        Text(L("{cost} MP", ["cost": controller.cost(of: skill)])).foregroundStyle(HUDStyle.mp)
                    }
                }
            }
            .transition(.scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity))
        case .items:
            ChoiceCard(title: L("Items"), icon: .backpack, onBack: controller.back) {
                if controller.items.isEmpty {
                    EmptyNote(L("Your bag is empty.\nShops in town sell potions."))
                }
                ForEach(controller.items) { item in
                    // A Seal Stone is thrown like Capture, so it's dim when there's nothing to seal.
                    ChoiceRow(action: { controller.useItem(item) }, enabled: item.capture != true || controller.canCapture) {
                        ItemIcon(item: item, size: 26, count: controller.session.count(of: item.id))
                        Text(item.name)
                        Spacer()
                        // How much a stone helps: stronger ones are likelier to hold, a Wishing Seal always does.
                        if item.capture == true {
                            Text(item.sure == true ? L("Never fails") : L("Odds ×{power}", ["power": (item.sealPower ?? 1).formatted()]))
                                .font(HUDStyle.font(10))
                                .foregroundStyle(item.sure == true ? HUDStyle.gold : HUDStyle.frameDark)
                        }
                    }
                }
            }
            .transition(.scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity))
        case .stones:
            // Capture with more than one kind of Seal Stone: which to throw, with what each brings.
            ChoiceCard(title: L("Seal Stones"), icon: .sealStone, onBack: controller.back) {
                ForEach(controller.stones) { stone in
                    ChoiceRow(action: { controller.capture(with: stone) }, enabled: controller.canCapture) {
                        ItemIcon(item: stone, size: 26, count: controller.session.count(of: stone.id))
                        Text(stone.name)
                        Spacer()
                        Text(stone.sure == true ? L("Never fails") : L("Odds ×{power}", ["power": (stone.sealPower ?? 1).formatted()]))
                            .font(HUDStyle.font(10))
                            .foregroundStyle(stone.sure == true ? HUDStyle.gold : HUDStyle.frameDark)
                    }
                }
            }
            .transition(.scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity))
        case .target:
            HStack(spacing: 10) {
                IconImage(.tap, size: 18).foregroundStyle(HUDStyle.gold)
                Text(controller.prompt).font(HUDStyle.font(13))
                Button(L("Cancel"), action: controller.back)
                    .buttonStyle(PixelButtonStyle(compact: true))
            }
            .foregroundStyle(HUDStyle.cream)
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .background(Capsule().fill(HUDStyle.ink.opacity(0.9)).overlay(Capsule().strokeBorder(HUDStyle.gold.opacity(0.8), lineWidth: 2)))
            .transition(.move(edge: .trailing).combined(with: .opacity))
        case .animating where controller.isAuto:
            AutoPlaying { controller.toggleAuto() }
                .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
        case .animating, .finished:
            EmptyView()
        }
    }
}

/// A boss fight's waves: a pip for each, the boss's a star, gold once you've reached it.
private struct WaveTracker: View {
    let wave: Int
    let total: Int

    var body: some View {
        HStack(spacing: 5) {
            Text(wave == total ? L("Boss wave") : L("Wave {wave} of {total}", ["wave": wave, "total": total]))
                .font(HUDStyle.font(11))
                .padding(.trailing, 2)
            ForEach(1...total, id: \.self) { index in
                Group {
                    if index == total {
                        IconImage(.star, size: 11)
                    } else {
                        Circle().frame(width: 7, height: 7)
                    }
                }
                .foregroundStyle(index <= wave ? HUDStyle.gold : HUDStyle.cream.opacity(0.3))
            }
        }
        .foregroundStyle(HUDStyle.cream)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(HUDStyle.ink.opacity(0.8)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(wave == total ? L("Boss wave, the last of {total}", ["total": total]) : L("Wave {wave} of {total}", ["wave": wave, "total": total]))
    }
}

/// The time left to choose, draining on top of a list (Skills, Items) or the target prompt, red
/// for the last two seconds. When it runs out the hero attacks. With the commands it's a ring
/// round the big button instead (`TurnClockRing`).
private struct TurnClockBar: View {
    let deadline: Date
    let total: TimeInterval

    var body: some View {
        TimelineView(.animation) { context in
            let left = max(0, deadline.timeIntervalSince(context.date))
            let urgent = left <= 2
            HStack(spacing: 6) {
                IconImage(.sword, size: 12)
                GlossyBar(fraction: CGFloat(min(1, left / total)), color: urgent ? HUDStyle.hp : HUDStyle.gold, height: 7)
                    .frame(width: 80)
                Text("\(Int(left.rounded(.up)))s")
                    .font(HUDStyle.mono(10))
                    .frame(width: 24, alignment: .leading)
            }
            .foregroundStyle(urgent ? HUDStyle.hp : HUDStyle.cream)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(HUDStyle.ink.opacity(0.8)))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Time left to choose before you attack"))
    }
}

// MARK: - Commands

/// A big button in the corner (Attack unless you change it), the time to choose as a ring round
/// it, and the other commands on an arc about it, where a thumb reaches them all alike: Skills,
/// then whatever else turns up (Capture when there's a monster to befriend, Items when someone is
/// low on HP), with More straight above the big button. Less-used commands hide behind More, and
/// with them Auto and the fight's pace. Holding any button makes them all wiggle, like the iPhone
/// home screen: drag them into any order (onto the big button, or into the "Behind More" tray),
/// then tap Done.
private struct CommandPad: View {
    let controller: BattleController
    /// Debug `more`: open from the start, for screenshots.
    @State private var showMore = DebugLaunch.opensMore
    /// While rearranging: the whole order, `moreDivider` included (nil otherwise).
    @State private var editing: [String]?
    /// Where each button sits, for working out what a dragged button is over.
    @State private var frames: [String: CGRect] = [:]
    @State private var trayFrame: CGRect = .zero
    @State private var dragging: String?
    @State private var dragPoint: CGPoint = .zero
    /// The button last swapped with, so hovering over it doesn't swap back and forth.
    @State private var lastTarget: String?

    private let mainSize: CGFloat = 88
    private let buttonSize: CGFloat = 56
    private static let space = "commandPad"

    var body: some View {
        Group {
            if let editing {
                editPad(editing)
            } else {
                pad
            }
        }
        .coordinateSpace(name: Self.space)
        .onAppear { if DebugLaunch.arrangesButtons, editing == nil { arrange() } }
        // Moving the buttons around isn't choosing: the turn clock waits.
        .onChange(of: editing == nil) { _, settled in controller.holdTurnClock(!settled, for: "arrange") }
        // The pad can go mid-move (AUTO tapped while the buttons wiggle plays the round): its hold
        // goes with it, or the clock and Auto would wait for it forever.
        .onDisappear { controller.holdTurnClock(false, for: "arrange") }
    }

    /// Your order (`GameSession.battleButtons`), split into the big button, the column beside it
    /// (bottom up, above More) and the More menu, leaving out what can't be used right now.
    private var sections: (main: String?, column: [String], more: [String]) {
        let order = controller.session.battleButtons.filter(isAvailable)
        let divider = order.firstIndex(of: GameSession.moreDivider) ?? order.endIndex
        var front = Array(order[..<divider])
        var more = Array(order[divider...].dropFirst())
        // Low on HP: Items comes out of More, glowing green.
        if controller.needsHealing, let index = more.firstIndex(of: "items") {
            more.remove(at: index)
            front.insert("items", at: min(1, front.count))
        }
        if front.isEmpty, !more.isEmpty { front.append(more.removeFirst()) }
        return (front.first, Array(front.dropFirst()), more)
    }

    private func isAvailable(_ id: String) -> Bool {
        id == "capture" ? controller.canCapture : true
    }

    /// Auto and the fight's pace: at the end of what More opens, after the commands behind it.
    private static let paceIDs = ["auto", "pace"]

    private var pad: some View {
        let (main, column, more) = sections
        let shown = showMore ? more + Self.paceIDs : column
        return ThumbArc {
            if let main {
                button(main, size: mainSize)
                    .overlay { TurnClockRing(controller: controller, diameter: mainSize + 16) }
                    .layoutValue(key: ArcSlot.self, value: 0)
            }
            // Left of the big button first, then up and to the left, then on round a wider arc
            // (slot 3, straight up, is More's).
            ForEach(Array(shown.enumerated()), id: \.element) { index, id in
                Group {
                    if Self.paceIDs.contains(id) {
                        paceButton(id)
                    } else {
                        button(id, size: buttonSize)
                    }
                }
                .layoutValue(key: ArcSlot.self, value: index < 2 ? index + 1 : index + 2)
                .transition(.scale(scale: 0.2).combined(with: .opacity))
            }
            // More sits straight above the big button, always in the same spot.
            RoundCommandButton(title: showMore ? L("Close") : L("More"), icon: showMore ? .close : .more, size: buttonSize,
                               tint: .quiet, onHold: arrange) {
                showMore.toggle()
            }
            .layoutValue(key: ArcSlot.self, value: 3)
        }
        .padding(.leading, 14)
        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: showMore)
        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: controller.canCapture)
        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: controller.needsHealing)
    }

    private func arrange() {
        showMore = false
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { editing = controller.session.battleButtons }
    }

    /// Auto and the fight's pace (1× or 2×), lit while on and kept for the next fights (Settings
    /// has them too). Auto is faded where it can't play (a boss, a duel, monsters too strong for
    /// it) and says why when tapped.
    private func paceButton(_ id: String) -> some View {
        let isAuto = id == "auto"
        let fast = controller.speed > 1
        let on = isAuto ? controller.isAuto : fast
        return RoundCommandButton(title: isAuto ? L("Auto") : L("Pace"), icon: isAuto ? .paw : .wind, size: buttonSize,
                                  tint: on ? .lit : .normal, text: isAuto ? L("AUTO") : (fast ? "2×" : "1×")) {
            SoundEffects.shared.play(.tap, volume: 0.7)
            if isAuto { controller.toggleAuto() } else { controller.toggleSpeed() }
        }
        .opacity(isAuto && !controller.isAuto && !controller.canAuto ? 0.5 : 1)
        .accessibilityLabel(isAuto
                            ? (controller.isAuto ? L("Auto is on. Tap to choose yourself.") : L("Auto: fight on your own."))
                            : (fast ? L("Battle speed: double. Tap for normal.") : L("Battle speed: normal. Tap for double.")))
    }

    // MARK: Rearranging

    private func editPad(_ order: [String]) -> some View {
        let divider = order.firstIndex(of: GameSession.moreDivider) ?? order.endIndex
        let main = order.first
        let row = Array(order[..<divider].dropFirst())
        let tray = Array(order[divider...].dropFirst())
        return VStack(alignment: .trailing, spacing: 22) {
            HStack(spacing: 8) {
                Text(L("Drag to rearrange"))
                    .font(HUDStyle.font(11))
                    .foregroundStyle(HUDStyle.cream)
                Button(L("Reset")) { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { editing = GameSession.defaultBattleButtons } }
                    .font(HUDStyle.font(12))
                    .foregroundStyle(HUDStyle.cream)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.white.opacity(0.15)))
                Button {
                    controller.arrangeButtons(order)
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { editing = nil }
                } label: {
                    Text(L("Done"))
                        .font(HUDStyle.font(13))
                        .foregroundStyle(HUDStyle.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(HUDStyle.gold))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(HUDStyle.ink.opacity(0.85)))

            // What waits behind More.
            VStack(alignment: .trailing, spacing: 8) {
                Text(L("Behind More"))
                    .font(HUDStyle.font(11))
                    .foregroundStyle(HUDStyle.cream.opacity(0.8))
                RightToLeftRows {
                    ForEach(tray, id: \.self) { id in editTile(id, size: buttonSize) }
                }
                .frame(minWidth: buttonSize * 2, minHeight: buttonSize, alignment: .bottomTrailing)
                .padding(.bottom, 16)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(HUDStyle.ink.opacity(0.55))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(HUDStyle.cream.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            )
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { trayFrame = $0 }
            .zIndex(tray.contains { $0 == dragging } ? 1 : 0)

            HStack(alignment: .bottom, spacing: 14) {
                RightToLeftRows {
                    ForEach(row, id: \.self) { id in editTile(id, size: buttonSize) }
                }
                .zIndex(row.contains { $0 == dragging } ? 1 : 0)
                VStack(spacing: 26) {
                    RoundCommandButton(title: L("More"), icon: .more, size: buttonSize, tint: .quiet) {}
                        .allowsHitTesting(false)
                        .opacity(0.5)
                    if let main { editTile(main, size: mainSize) }
                }
                .zIndex(main == dragging ? 1 : 0)
            }
            .padding(.leading, 14)
        }
    }

    /// A wiggling button that can be dragged; taps do nothing while rearranging.
    private func editTile(_ id: String, size: CGFloat) -> some View {
        let isDragged = dragging == id
        let center = frames[id].map { CGPoint(x: $0.midX, y: $0.midY) } ?? dragPoint
        return button(id, size: size)
            .allowsHitTesting(false)
            .modifier(Wiggle(active: !isDragged))
            .opacity(id == "capture" && !controller.canCapture ? 0.7 : 1)
            .contentShape(Rectangle())
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frames[id] = $0 }
            .scaleEffect(isDragged ? 1.15 : 1)
            .offset(isDragged ? CGSize(width: dragPoint.x - center.x, height: dragPoint.y - center.y) : .zero)
            .zIndex(isDragged ? 1 : 0)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                    .onChanged { value in
                        if dragging != id {
                            dragging = id
                            lastTarget = nil
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        dragPoint = value.location
                        drag(id, over: value.location)
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            dragging = nil
                            lastTarget = nil
                        }
                    }
            )
    }

    /// Moves the dragged button into the place of whatever it's over (iPhone home screen style), or to
    /// the end of the tray when it's dropped into the tray's empty space.
    private func drag(_ id: String, over point: CGPoint) {
        guard var order = editing, let from = order.firstIndex(of: id) else { return }
        if let target = frames.first(where: { $0.key != id && order.contains($0.key) && $0.value.contains(point) })?.key {
            guard target != lastTarget, let to = order.firstIndex(of: target) else { return }
            lastTarget = target
            order.move(fromOffsets: [from], toOffset: to > from ? to + 1 : to)
        } else if trayFrame.contains(point), let divider = order.firstIndex(of: GameSession.moreDivider), from < divider {
            lastTarget = nil
            order.remove(at: from)
            order.append(id)
        } else {
            lastTarget = nil
            return
        }
        // Something always has to be the big button.
        if order.first == GameSession.moreDivider, order.count > 1 { order.swapAt(0, 1) }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { editing = order }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func button(_ id: String, size: CGFloat) -> some View {
        let info = BattleCommand(id)
        return RoundCommandButton(title: info.title, icon: id == "items" && controller.needsHealing ? .heartPlus : info.icon,
                                  size: size, tint: tint(for: id, big: size == mainSize), onHold: arrange) {
            perform(id)
        }
    }

    private func tint(for id: String, big: Bool) -> RoundCommandButton.Tint {
        if id == "capture" { return .special }
        if id == "items", controller.needsHealing { return .heal }
        return big ? .primary : .normal
    }

    private func perform(_ id: String) {
        switch id {
        case "attack": controller.attack()
        case "skills": controller.openSkills()
        case "items": controller.openItems()
        case "guard": controller.defend()
        case "run": controller.escape()
        case "capture": controller.capture()
        default: break
        }
    }
}

/// The time left to choose, draining round the big button: gold, red for the last two seconds,
/// with the seconds on it. When it runs out the hero attacks. Nothing while no clock is ticking.
private struct TurnClockRing: View {
    let controller: BattleController
    let diameter: CGFloat

    var body: some View {
        if let deadline = controller.turnDeadline, let total = BattleController.turnSeconds {
            TimelineView(.animation) { context in
                let left = max(0, deadline.timeIntervalSince(context.date))
                let urgent = left <= 2
                ZStack(alignment: .topTrailing) {
                    Circle()
                        .stroke(HUDStyle.ink.opacity(0.75), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: CGFloat(min(1, left / total)))
                        .stroke(urgent ? HUDStyle.hp : HUDStyle.gold, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(left.rounded(.up)))")
                        .font(HUDStyle.mono(11))
                        .foregroundStyle(urgent ? HUDStyle.hp : HUDStyle.cream)
                        .frame(minWidth: 22, minHeight: 20)
                        .background(Capsule().fill(HUDStyle.ink.opacity(0.92)))
                        .offset(x: 6, y: -4)
                }
                .frame(width: diameter, height: diameter)
            }
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("Time left to choose before you attack"))
        }
    }
}

/// Auto at work: the big button's corner turns gold and says so, its ring turning, and a tap takes
/// the fight back from the next round. (The switch that starts it is behind More.)
private struct AutoPlaying: View {
    let onTakeOver: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turning = false

    var body: some View {
        Button {
            SoundEffects.shared.play(.tap, volume: 0.7)
            onTakeOver()
        } label: {
            Text(L("AUTO"))
                .font(HUDStyle.font(16))
                .foregroundStyle(HUDStyle.ink)
                .frame(width: 88, height: 88)
                .background(
                    Circle()
                        .fill(RadialGradient(colors: [Color(red: 1, green: 0.92, blue: 0.55), Color(red: 0.98, green: 0.68, blue: 0.2)],
                                             center: UnitPoint(x: 0.35, y: 0.3), startRadius: 1, endRadius: 66))
                        .overlay(Circle().strokeBorder(.white.opacity(0.75), lineWidth: 2))
                )
                .overlay {
                    Circle()
                        .stroke(HUDStyle.gold, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [9, 7]))
                        .frame(width: 104, height: 104)
                        .rotationEffect(.degrees(turning ? 360 : 0))
                }
                .overlay(alignment: .top) {
                    Text(L("Tap to take over"))
                        .font(HUDStyle.font(10))
                        .foregroundStyle(HUDStyle.cream)
                        .shadow(color: .black, radius: 0, x: 1, y: 1)
                        .fixedSize()
                        .offset(y: -30)
                }
        }
        .buttonStyle(RoundPressStyle())
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) { turning = true }
        }
        .accessibilityLabel(L("Auto is on. Tap to choose yourself."))
    }
}

/// Which place round the big button a command takes (`ThumbArc`): 0 is the big button.
nonisolated struct ArcSlot: LayoutValueKey {
    static let defaultValue = 0
}

/// The commands round the big button in the corner, so a thumb reaches them all alike: the big
/// button bottom right (slot 0), then an arc about it (1 to its left, 2 up and to the left, 3
/// straight up), a wider arc of four beyond that (4 to 7), and so on. Labels hang below the
/// buttons, outside the layout, so the arcs leave room for them.
struct ThumbArc: Layout {
    /// From the big button's middle to the first arc, and from each arc to the next.
    var firstRadius: CGFloat = 104
    var ringGap: CGFloat = 80

    /// Where a slot sits from the big button's middle (up is negative).
    private func offset(of slot: Int) -> CGPoint {
        guard slot > 0 else { return .zero }
        var ring = 0, first = 1, count = 3
        while slot >= first + count {
            first += count
            count += 1
            ring += 1
        }
        // From straight left (180°) round to straight up (90°).
        let angle = Double.pi * (1 - 0.5 * Double(slot - first) / Double(count - 1))
        let radius = firstRadius + ringGap * CGFloat(ring)
        return CGPoint(x: radius * CGFloat(cos(angle)), y: -radius * CGFloat(sin(angle)))
    }

    /// Each button's frame about the big button's middle.
    private func frames(_ subviews: Subviews) -> [CGRect] {
        subviews.map { subview in
            let size = subview.sizeThatFits(.unspecified)
            let center = offset(of: subview[ArcSlot.self])
            return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let union = frames(subviews).reduce(CGRect.null) { $0.union($1) }
        return union.isNull ? .zero : union.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placed = frames(subviews)
        let union = placed.reduce(CGRect.null) { $0.union($1) }
        guard !union.isNull else { return }
        for (subview, frame) in zip(subviews, placed) {
            subview.place(at: CGPoint(x: bounds.maxX - union.maxX + frame.midX, y: bounds.maxY - union.maxY + frame.midY),
                          anchor: .center, proposal: ProposedViewSize(frame.size))
        }
    }
}

/// Your companion's turn, after the hero's choice: Attack in the big button's spot, and round it
/// on the same arc its Skills, Guard, and Auto to let it decide for itself. The chip on top shows
/// whose turn it is. The hero's choice is made by then, so there's no going back to it (that would
/// start their clock over).
private struct CompanionPad: View {
    let controller: BattleController

    var body: some View {
        VStack(alignment: .trailing, spacing: 16) {
            if let companion = controller.companion {
                HStack(spacing: 8) {
                    SpriteImage(art: companion.art, size: 30)
                    Text(L("{companion}'s turn", ["companion": companion.name]))
                        .font(HUDStyle.font(13))
                        .foregroundStyle(HUDStyle.cream)
                }
                .padding(.leading, 8)
                .padding(.trailing, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(HUDStyle.ink.opacity(0.88)).overlay(Capsule().strokeBorder(HUDStyle.gold.opacity(0.7), lineWidth: 1.5)))
            }

            ThumbArc {
                RoundCommandButton(title: L("Attack"), icon: .tooth, size: 88, tint: .primary) { controller.attack() }
                    .overlay { TurnClockRing(controller: controller, diameter: 104) }
                    .layoutValue(key: ArcSlot.self, value: 0)
                if !controller.companionSkills.isEmpty {
                    RoundCommandButton(title: L("Skills"), icon: .sparkles, size: 56, tint: .normal) { controller.openSkills() }
                        .layoutValue(key: ArcSlot.self, value: 1)
                }
                RoundCommandButton(title: L("Guard"), icon: .shield, size: 56, tint: .normal) { controller.defend() }
                    .layoutValue(key: ArcSlot.self, value: controller.companionSkills.isEmpty ? 1 : 2)
                RoundCommandButton(title: L("Auto"), icon: .paw, size: 56, tint: .quiet) { controller.letCompanionDecide() }
                    .layoutValue(key: ArcSlot.self, value: 3)
            }
        }
        .padding(.leading, 14)
    }
}

/// The name and icon of a battle button id (see `GameSession.battleButtons`).
private struct BattleCommand {
    let title: String
    let icon: GameIcon

    init(_ id: String) {
        switch id {
        case "attack": title = L("Attack"); icon = .sword
        case "skills": title = L("Skills"); icon = .sparkles
        case "items": title = L("Items"); icon = .backpack
        case "guard": title = L("Guard"); icon = .shield
        case "run": title = L("Run"); icon = .wind
        case "capture": title = L("Capture"); icon = .sealStone
        default: title = L("More"); icon = .more
        }
    }
}

/// The home-screen wiggle for buttons being rearranged, each a little out of step with the others.
private struct Wiggle: ViewModifier {
    let active: Bool
    @State private var speed = Double.random(in: 0.11...0.15)

    // `Self.Content`: plain `Content` is the game's data store.
    func body(content: Self.Content) -> some View {
        content.phaseAnimator([false, true]) { view, tilted in
            view.rotationEffect(.degrees(active ? (tilted ? 2.5 : -2.5) : 0))
        } animation: { _ in
            .easeInOut(duration: speed)
        }
    }
}

/// Lays its views out in rows from the bottom-right corner: right to left, and when a row is full,
/// on up into the next one. Labels hang below the buttons, so rows leave room for them.
private struct RightToLeftRows: Layout {
    var spacing: CGFloat = 12
    var rowSpacing: CGFloat = 26

    private func rows(_ sizes: [CGSize], maxWidth: CGFloat) -> [[Int]] {
        var rows: [[Int]] = [[]]
        var width: CGFloat = 0
        for (index, size) in sizes.enumerated() {
            let row = rows[rows.count - 1]
            let needed = row.isEmpty ? size.width : width + spacing + size.width
            if !row.isEmpty, needed > maxWidth {
                rows.append([index])
                width = size.width
            } else {
                rows[rows.count - 1].append(index)
                width = needed
            }
        }
        return rows
    }

    private func measure(_ subviews: Subviews) -> [CGSize] {
        subviews.map { $0.sizeThatFits(.unspecified) }
    }

    /// Without a width on offer, four buttons to a row.
    private func maxWidth(_ proposal: ProposedViewSize, _ sizes: [CGSize]) -> CGFloat {
        if let width = proposal.width, width.isFinite { return width }
        return 4 * (sizes.first?.width ?? 56) + 3 * spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = measure(subviews)
        guard !sizes.isEmpty else { return .zero }
        let rows = rows(sizes, maxWidth: maxWidth(proposal, sizes))
        let widths = rows.map { row in row.map { sizes[$0].width }.reduce(0, +) + spacing * CGFloat(max(0, row.count - 1)) }
        let heights = rows.map { row in row.map { sizes[$0].height }.max() ?? 0 }
        return CGSize(width: widths.max() ?? 0, height: heights.reduce(0, +) + rowSpacing * CGFloat(max(0, rows.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = measure(subviews)
        var y = bounds.maxY
        for row in rows(sizes, maxWidth: bounds.width) {
            var x = bounds.maxX
            for index in row {
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .bottomTrailing, proposal: ProposedViewSize(sizes[index]))
                x -= sizes[index].width + spacing
            }
            y -= (row.map { sizes[$0].height }.max() ?? 0) + rowSpacing
        }
    }
}

struct RoundCommandButton: View {
    enum Tint {
        /// special glows gold (Capture); heal glows green (Items when HP is low); lit is a switch
        /// that's on (Auto, double pace), gold without the glow.
        case primary, normal, special, heal, quiet, lit
    }

    let title: String
    let icon: GameIcon
    let size: CGFloat
    let tint: Tint
    var onHold: (() -> Void)? = nil
    /// A word in the middle instead of the icon ("AUTO", "2×").
    var text: String? = nil
    let action: () -> Void

    @State private var pulse = false

    private var colors: [Color] {
        switch tint {
        case .primary: [Color(red: 1, green: 0.62, blue: 0.45), Color(red: 0.9, green: 0.3, blue: 0.3)]
        case .special, .lit: [Color(red: 1, green: 0.92, blue: 0.55), Color(red: 0.98, green: 0.68, blue: 0.2)]
        case .heal: [Color(red: 0.8, green: 1, blue: 0.75), Color(red: 0.3, green: 0.78, blue: 0.4)]
        case .normal: [.white, HUDStyle.cream, Color(red: 0.86, green: 0.78, blue: 0.64)]
        case .quiet: [Color(red: 0.42, green: 0.36, blue: 0.56), HUDStyle.ink]
        }
    }

    /// Buttons that want attention pulse with a coloured glow.
    private var glow: Color? {
        switch tint {
        case .special: HUDStyle.gold
        case .heal: HUDStyle.green
        default: nil
        }
    }

    private var foreground: Color {
        switch tint {
        case .primary, .quiet: .white
        case .normal, .special, .heal, .lit: HUDStyle.ink
        }
    }

    var body: some View {
        PressButton(action: action, onHold: onHold) {
            VStack(spacing: 1) {
                if let text {
                    Text(text)
                        .font(HUDStyle.font(size * 0.27))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 4)
                } else {
                    IconImage(icon, size: size * 0.4)
                }
                if size >= 80 {
                    Text(title).font(HUDStyle.font(12))
                }
            }
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(RadialGradient(colors: colors, center: UnitPoint(x: 0.35, y: 0.3), startRadius: 1, endRadius: size * 0.75))
                    .overlay(Circle().strokeBorder(.white.opacity(tint == .quiet ? 0.35 : 0.75), lineWidth: 2))
                    .overlay(
                        Ellipse().fill(.white.opacity(0.35))
                            .frame(width: size * 0.5, height: size * 0.2)
                            .offset(y: -size * 0.3)
                    )
            )
            .shadow(color: glow?.opacity(pulse ? 0.9 : 0.3) ?? .black.opacity(0.4),
                    radius: glow == nil ? 4 : (pulse ? 12 : 5), x: 0, y: glow == nil ? 4 : 0)
        }
        .overlay(alignment: .bottom) {
            if size < 80 {
                Text(title)
                    .font(HUDStyle.font(10))
                    .foregroundStyle(HUDStyle.cream)
                    .shadow(color: .black, radius: 0, x: 1, y: 1)
                    .fixedSize()
                    .offset(y: 15)
            }
        }
        .onAppear {
            guard glow != nil else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityLabel(title)
    }
}

/// A button that shrinks while pressed; holding it calls `onHold` instead of `action`.
private struct PressButton<Label: View>: View {
    let action: () -> Void
    let onHold: (() -> Void)?
    @ViewBuilder let label: () -> Label
    @State private var pressed = false
    /// Set by a hold, so letting go afterwards doesn't also count as a tap.
    @State private var held = false

    var body: some View {
        label()
            .contentShape(Rectangle())
            .scaleEffect(pressed ? 0.9 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: pressed)
            .onTapGesture {
                if held { held = false } else { action() }
            }
            .onLongPressGesture(minimumDuration: 0.45) {
                guard let onHold else { return }
                held = true
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onHold()
            } onPressingChanged: { pressing in
                pressed = pressing
                if pressing { held = false }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
            .accessibilityAction(named: L("Arrange buttons")) { onHold?() }
    }
}

private struct RoundPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Lists

private struct ChoiceCard<Content: View>: View {
    let title: String
    let icon: GameIcon
    let onBack: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FLTitleBar(title: title, icon: icon, onClose: onBack)
            // Hug the rows; long lists scroll instead of growing past the scene.
            ScrollView {
                VStack(spacing: 6, content: content)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(max(contentHeight, 1), 220))
            .padding(12)
        }
        .frame(width: 300)
        .gameWindow()
    }
}

private struct ChoiceRow<Label: View>: View {
    let action: () -> Void
    let enabled: Bool
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6, content: label)
                .font(HUDStyle.font(13))
                .foregroundStyle(HUDStyle.ink)
                .padding(.leading, 6)
                .padding(.trailing, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(enabled ? HUDStyle.cream : HUDStyle.dim))
        }
        .buttonStyle(RoundPressStyle())
    }
}

// MARK: - Status & results

/// A scrolling column as tall as its content, up to the room there is: when it all fits it's just
/// the content, no fade and nothing to scroll. When it doesn't, its bottom fades out while there's
/// more below (the end scrolls up clear of the fade), and its scroll bar runs down the window's
/// edge: it reaches `edge` out past the content on each side, the window's padding.
private struct FittedScroll<Content: View>: View {
    var edge: CGFloat = 0
    @ViewBuilder let content: () -> Content
    /// How tall the fade at the bottom is.
    private static var fade: CGFloat { 36 }
    @State private var contentHeight: CGFloat = 0
    @State private var viewHeight: CGFloat = 0
    /// How far it's scrolled down.
    @State private var scrolled: CGFloat = 0

    private var overflows: Bool { contentHeight > viewHeight + 1 }
    private var moreBelow: Bool { overflows && scrolled < contentHeight + Self.fade - viewHeight - 2 }

    var body: some View {
        ScrollView {
            content()
                .background(GeometryReader { proxy in
                    let frame = proxy.frame(in: .named("fittedScroll"))
                    Color.clear
                        .onAppear { contentHeight = frame.height; scrolled = -frame.minY }
                        .onChange(of: frame) { _, frame in
                            contentHeight = frame.height
                            scrolled = -frame.minY
                        }
                })
                .padding(.bottom, overflows ? Self.fade : 0)
                .padding(.horizontal, edge)
        }
        .coordinateSpace(name: "fittedScroll")
        .scrollBounceBehavior(.basedOnSize)
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { viewHeight = proxy.size.height }
                .onChange(of: proxy.size.height) { _, height in viewHeight = height }
        })
        .mask(
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, moreBelow ? .clear : .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: Self.fade)
            }
        )
        // No taller than the content: a short list leaves the window short.
        .frame(maxHeight: contentHeight > 0 ? contentHeight : nil)
        .padding(.horizontal, -edge)
    }
}

private struct ResultPanel: View {
    /// The window's padding, which the rewards' scroll bar reaches out across to the edge.
    private static let inset: CGFloat = 22
    let result: BattleResult
    let session: GameSession
    let onContinue: () -> Void

    /// A boss's story first (the first time you beat it), then the summary; then, if needed, who
    /// stays behind (full party) and skill choices.
    private enum Stage { case story, summary, release, levelUp }
    @State private var stage: Stage

    init(result: BattleResult, session: GameSession, onContinue: @escaping () -> Void) {
        self.result = result
        self.session = session
        self.onContinue = onContinue
        _stage = State(initialValue: result.story == nil ? .summary : .story)
    }

    private var title: String {
        switch result.outcome {
        case .victory: L("Victory!")
        case .fled: L("It got away…")
        case .defeat: L("Defeated…")
        case .escaped: L("Escaped")
        case .ongoing: ""
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            switch stage {
            case .story:
                if let story = result.story {
                    BossStoryCard(story: story, onDone: advance)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            case .summary:
                summary
            case .release:
                LeaveBehindCard(session: session, onDone: advance)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            case .levelUp:
                if let level = result.newLevel {
                    LevelUpCard(session: session, level: level, onDone: onContinue)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: stage)
    }

    private func advance() {
        if stage == .story {
            stage = .summary
        } else if stage == .summary, session.pendingPet != nil {
            stage = .release
        } else if stage != .levelUp, result.newLevel != nil, session.canSpendSkillPoint {
            stage = .levelUp
        } else {
            onContinue()
        }
    }

    private var summary: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(HUDStyle.font(26))
                .foregroundStyle(result.outcome == .victory ? HUDStyle.gold : HUDStyle.cream)
                // Clear of the close button, and still centred.
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 18)
            // As tall as the rewards, scrolling only when they can't all fit (a big win, or a
            // phone on its side), with its scroll bar along the window's right edge.
            FittedScroll(edge: Self.inset) { details }
            Button(L("Continue"), action: advance)
                .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold))
                .padding(.top, 6)
        }
        .padding(Self.inset)
        .frame(maxWidth: 420)
        .gameWindow()
        // Closing it is Continue: the pay is already in your bag.
        .windowCloseButton(advance)
        .padding(20)
    }

    /// The pay, the level-up, what was found, and what else happened.
    private var details: some View {
        VStack(spacing: 10) {
            if result.exp > 0 || result.gold > 0 {
                HStack(spacing: 18) {
                    // None when you were out cold at the end (your friends won it).
                    if result.exp > 0 {
                        Label { Text(L("+{exp} EXP", ["exp": result.exp])) } icon: {
                            IconImage(.star, size: 18).foregroundStyle(HUDStyle.exp)
                        }
                    }
                    Label { Text("+\(result.gold)") } icon: {
                        IconImage(.coins, size: 18).foregroundStyle(HUDStyle.gold)
                    }
                }
                .font(HUDStyle.font(16))
                .foregroundStyle(HUDStyle.cream)
            }
            if let level = result.newLevel {
                LevelUpBanner(level: level, gains: session.heroClass.growth * result.levelsGained)
            }
            if !result.others.isEmpty {
                PartyLevelUps(others: result.others)
            }
            if !result.loot.isEmpty {
                LootGrid(loot: result.loot)
            }
            if !result.newCards.isEmpty {
                NewCards(session: session, ids: result.newCards)
            }
            ForEach(Array(result.lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(HUDStyle.font(13))
                    .foregroundStyle(HUDStyle.cream)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

/// A boss beaten for the first time: what the win means, told as a short story before the pay.
/// The boss in a ring of light over the title; the paragraphs come in one after another, at about
/// reading pace. A tap shows the rest at once; Continue goes on to the rewards.
private struct BossStoryCard: View {
    let story: BossStory
    let onDone: () -> Void
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How many paragraphs are showing.
    @State private var shown = 0

    private var told: Bool { shown >= story.paragraphs.count }

    var body: some View {
        Group {
            if verticalSizeClass == .compact {
                // Landscape: the boss beside the story, so it all fits.
                HStack(spacing: 18) {
                    portrait(size: 80)
                    VStack(spacing: 10) {
                        heading
                        ViewThatFits(in: .vertical) {
                            paragraphs
                            ScrollView { paragraphs }
                                .scrollBounceBehavior(.basedOnSize)
                        }
                        continueButton
                    }
                }
            } else {
                VStack(spacing: 12) {
                    portrait(size: 96)
                    heading
                    paragraphs
                    continueButton
                }
            }
        }
        .padding(22)
        .frame(maxWidth: verticalSizeClass == .compact ? 620 : 420)
        .gameWindow()
        .contentShape(RoundedRectangle(cornerRadius: HUDStyle.windowRadius))
        .onTapGesture { revealAll() }
        // Closing it skips the rest of the story, on to the rewards.
        .windowCloseButton(onDone)
        .padding(20)
        .task { await tell() }
    }

    private func portrait(size: CGFloat) -> some View {
        SpriteImage(art: story.art, size: size)
            .frame(width: size + 16, height: size + 16)
            .background(
                Circle()
                    .fill(RadialGradient(colors: [HUDStyle.gold.opacity(0.3), HUDStyle.gold.opacity(0.04)],
                                         center: .center, startRadius: 0, endRadius: size * 0.6))
                    .overlay(Circle().strokeBorder(HUDStyle.gold.opacity(0.5), lineWidth: 1.5))
            )
            .accessibilityHidden(true)
    }

    /// The title, with a little star rule under it like a storybook chapter.
    private var heading: some View {
        VStack(spacing: 6) {
            Text(story.title)
                .font(HUDStyle.font(22))
                .foregroundStyle(HUDStyle.gold)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                Capsule().fill(HUDStyle.gold.opacity(0.45)).frame(width: 44, height: 1.5)
                Text("✦").font(HUDStyle.font(11)).foregroundStyle(HUDStyle.gold.opacity(0.8))
                Capsule().fill(HUDStyle.gold.opacity(0.45)).frame(width: 44, height: 1.5)
            }
            .accessibilityHidden(true)
        }
    }

    /// Every paragraph takes its place from the start (unshown ones invisible), so nothing jumps.
    private var paragraphs: some View {
        VStack(spacing: 10) {
            ForEach(Array(story.paragraphs.enumerated()), id: \.offset) { index, paragraph in
                Text(paragraph)
                    .font(HUDStyle.font(14))
                    .foregroundStyle(HUDStyle.cream)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(index < shown ? 1 : 0)
                    .offset(y: index < shown ? 0 : 8)
            }
        }
    }

    private var continueButton: some View {
        Button(L("Continue")) {
            if told { onDone() } else { revealAll() }
        }
        .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold))
        .opacity(told ? 1 : 0.5)
        .padding(.top, 4)
    }

    /// One paragraph after another, each given time to be read (all at once with Reduce Motion).
    private func tell() async {
        if reduceMotion {
            shown = story.paragraphs.count
            return
        }
        var pause = 0.5
        for (index, paragraph) in story.paragraphs.enumerated() {
            try? await Task.sleep(for: .seconds(pause))
            guard !Task.isCancelled else { return }
            if shown <= index {
                withAnimation(.easeOut(duration: 0.8)) { shown = index + 1 }
            }
            pause = min(3.5, max(1.5, Double(paragraph.count) * 0.022))
        }
    }

    private func revealAll() {
        guard !told else { return }
        withAnimation(.easeOut(duration: 0.3)) { shown = story.paragraphs.count }
    }
}

/// What a win (or a quest) turned up, as little item tiles with how many and the name underneath.
struct LootGrid: View {
    let loot: [(id: String, count: Int)]
    var title = L("Found")

    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.gold)
            CenteredRows(spacing: 8, rowSpacing: 8) {
                ForEach(Array(loot.enumerated()), id: \.offset) { _, entry in
                    if let item = Content.shared.item(entry.id) {
                        VStack(spacing: 3) {
                            ItemIcon(item: item, size: 40, count: entry.count)
                            Text(item.name)
                                .font(HUDStyle.font(10))
                                .foregroundStyle(HUDStyle.cream)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .frame(width: 78)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.06)))
    }
}

/// Monster cards new to the Book after a win, face up, each with what it gives for good.
private struct NewCards: View {
    let session: GameSession
    let ids: [String]

    var body: some View {
        VStack(spacing: 6) {
            Text(ids.count == 1 ? L("New card!") : L("New cards!"))
                .font(HUDStyle.font(14))
                .foregroundStyle(HUDStyle.gold)
            CenteredRows(spacing: 10, rowSpacing: 8) {
                ForEach(ids, id: \.self) { id in
                    if let monster = session.content.monster(id) {
                        VStack(spacing: 4) {
                            MonsterCardFace(monster: monster, width: 56)
                            Text(session.cardGain(of: monster).bonusSummary)
                                .font(HUDStyle.font(10))
                                .foregroundStyle(HUDStyle.green)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            Text(L("Kept in your Monster Book, for good."))
                .font(HUDStyle.font(10))
                .foregroundStyle(HUDStyle.dim)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(HUDStyle.gold.opacity(0.1)))
    }
}

/// Friends and your companion who went up a level with the win, each with their new level, in a
/// gold box like the hero's banner.
private struct PartyLevelUps: View {
    let others: [LevelUp]

    var body: some View {
        VStack(spacing: 6) {
            Text(others.count == 1 ? L("Level up!") : L("Level ups!"))
                .font(HUDStyle.font(14))
                .foregroundStyle(HUDStyle.gold)
            CenteredRows(spacing: 6, rowSpacing: 6) {
                ForEach(Array(others.enumerated()), id: \.offset) { _, other in
                    HStack(spacing: 4) {
                        IconImage(.arrowUp, size: 11)
                            .foregroundStyle(HUDStyle.gold)
                        Text(other.name)
                            .foregroundStyle(HUDStyle.cream)
                        Text(L("Lv {level}", ["level": other.level]))
                            .foregroundStyle(HUDStyle.gold)
                    }
                    .font(HUDStyle.font(12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(HUDStyle.gold.opacity(0.14)))
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(HUDStyle.gold.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(HUDStyle.gold.opacity(0.4), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(others.map { L("{name} reached level {level}", ["name": $0.name, "level": $0.level]) }.joined(separator: ". "))
    }
}

/// A level-up, made a fuss of on the victory and quest cards: the new level on a gold medal in a
/// slowly turning sunburst, stars flying off it, "LEVEL UP!", and what the new levels raised.
struct LevelUpBanner: View {
    let level: Int
    /// What the levels raised: the class's growth for each level gained.
    let gains: Stats
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var burst = false

    /// The stats that went up, in the Character tab's order.
    private var raised: [(label: String, value: Int)] {
        let all: [(label: String, value: Int)] = [
            (L("HP"), gains.hp), (L("MP"), gains.mp), (L("ATK"), gains.attack),
            (L("DEF"), gains.defense), (L("MAG"), gains.magic), (L("SPD"), gains.speed),
        ]
        return all.filter { $0.value > 0 }
    }

    var body: some View {
        Group {
            if verticalSizeClass == .compact {
                // Landscape: the medal beside the words, so the card still fits the screen.
                HStack(spacing: 16) {
                    medal(size: 50)
                    VStack(alignment: .leading, spacing: 4) {
                        title(size: 22)
                        Text(gains.bonusSummary)
                            .font(HUDStyle.font(11))
                            .foregroundStyle(HUDStyle.green)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    medal(size: 66)
                    title(size: 28)
                    CenteredRows(spacing: 5, rowSpacing: 5) {
                        ForEach(Array(raised.enumerated()), id: \.offset) { _, stat in
                            chip(stat.label, stat.value)
                        }
                    }
                    Text(L("HP and MP fully restored"))
                        .font(HUDStyle.font(10))
                        .foregroundStyle(HUDStyle.dim)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(HUDStyle.gold.opacity(0.12)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(HUDStyle.gold.opacity(0.55), lineWidth: 1.5))
        .scaleEffect(shown ? 1 : 0.6)
        .opacity(shown ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55).delay(0.15)) { shown = true }
            withAnimation(.easeOut(duration: 0.9).delay(0.3)) { burst = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Level up! You're now level {level}. {bonuses}", ["level": level, "bonuses": gains.bonusSummary]))
    }

    private func medal(size: CGFloat) -> some View {
        ZStack {
            TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { context in
                let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 20) / 20
                // A soft glow, not a stark one: faint where it leaves the medal, mostly gone halfway
                // out, its wedges' edges blurred into the window's blue.
                Sunburst(rays: 14)
                    .fill(RadialGradient(stops: [
                        .init(color: HUDStyle.gold.opacity(0.38), location: 0.4),
                        .init(color: HUDStyle.gold.opacity(0.14), location: 0.65),
                        .init(color: HUDStyle.gold.opacity(0.04), location: 0.85),
                        .init(color: HUDStyle.gold.opacity(0), location: 1),
                    ], center: .center, startRadius: 0, endRadius: size * 1.2))
                    .frame(width: size * 2.4, height: size * 2.4)
                    .blur(radius: size * 0.04)
                    .rotationEffect(.degrees(turn * 360))
            }
            // Stars fly off from behind the medal as it lands.
            ForEach(0..<8, id: \.self) { index in
                IconImage(.star, size: size * 0.18)
                    .foregroundStyle(index % 2 == 0 ? HUDStyle.cream : HUDStyle.gold)
                    .offset(burst ? Self.flight(of: index, radius: size) : .zero)
                    .opacity(burst ? 0 : 1)
            }
            Circle()
                .fill(RadialGradient(colors: [Color(red: 1, green: 0.97, blue: 0.75), HUDStyle.gold, HUDStyle.orange],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 1, endRadius: size * 0.75))
                .overlay(Circle().strokeBorder(HUDStyle.cream, lineWidth: 2.5))
                .shadow(color: HUDStyle.gold.opacity(0.9), radius: 10)
                .frame(width: size, height: size)
            VStack(spacing: -4) {
                Text(L("LV")).font(HUDStyle.font(size * 0.19))
                Text("\(level)")
                    .font(HUDStyle.font(size * 0.42))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
            .foregroundStyle(HUDStyle.ink)
            .padding(.horizontal, size * 0.1)
        }
        .frame(width: size, height: size)
    }

    /// Where star `index` of eight ends up, all the way round the medal.
    private static func flight(of index: Int, radius: CGFloat) -> CGSize {
        let angle = CGFloat(index) / 8 * 2 * .pi
        return CGSize(width: cos(angle) * radius, height: sin(angle) * radius * 0.8)
    }

    private func title(size: CGFloat) -> some View {
        Text(L("LEVEL UP!"))
            .font(HUDStyle.font(size))
            .foregroundStyle(HUDStyle.gold)
            .shadow(color: HUDStyle.orange.opacity(0.9), radius: 0, x: 2, y: 2)
    }

    /// "HP +12": one raised stat, in a little dark pill.
    private func chip(_ label: String, _ value: Int) -> some View {
        let text: Text = Text(label + " ").foregroundStyle(HUDStyle.cream) + Text("+\(value)").foregroundStyle(HUDStyle.green)
        return text
            .font(HUDStyle.font(11))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(HUDStyle.ink.opacity(0.7)))
    }
}

/// Wedges of light round the middle, like a sunburst.
private nonisolated struct Sunburst: Shape {
    var rays = 12

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = max(rect.width, rect.height) / 2
        let step = 2 * CGFloat.pi / CGFloat(rays)
        for index in 0..<rays {
            let angle = step * CGFloat(index)
            path.move(to: center)
            path.addArc(center: center, radius: radius, startAngle: Angle(radians: Double(angle - step / 4)),
                        endAngle: Angle(radians: Double(angle + step / 4)), clockwise: false)
            path.closeSubpath()
        }
        return path
    }
}

/// Wraps its views into rows like text, each row centred.
private struct CenteredRows: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    private func rows(_ sizes: [CGSize], maxWidth: CGFloat) -> [[Int]] {
        var rows: [[Int]] = [[]]
        var width: CGFloat = 0
        for (index, size) in sizes.enumerated() {
            let row = rows[rows.count - 1]
            let needed = row.isEmpty ? size.width : width + spacing + size.width
            if !row.isEmpty, needed > maxWidth {
                rows.append([index])
                width = size.width
            } else {
                rows[rows.count - 1].append(index)
                width = needed
            }
        }
        return rows
    }

    private func rowWidth(_ row: [Int], _ sizes: [CGSize]) -> CGFloat {
        row.map { sizes[$0].width }.reduce(0, +) + spacing * CGFloat(max(0, row.count - 1))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        guard !sizes.isEmpty else { return .zero }
        let maxWidth = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? .infinity
        let rows = rows(sizes, maxWidth: maxWidth)
        let heights = rows.map { row in row.map { sizes[$0].height }.max() ?? 0 }
        let widest = rows.map { rowWidth($0, sizes) }.max() ?? 0
        return CGSize(width: maxWidth.isFinite ? maxWidth : widest,
                      height: heights.reduce(0, +) + rowSpacing * CGFloat(max(0, rows.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var y = bounds.minY
        for row in rows(sizes, maxWidth: bounds.width) {
            let height = row.map { sizes[$0].height }.max() ?? 0
            var x = bounds.midX - rowWidth(row, sizes) / 2
            for index in row {
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(sizes[index]))
                x += sizes[index].width + spacing
            }
            y += height + rowSpacing
        }
    }
}
