import SwiftUI
import UIKit

/// Battle HUD: what just happened in a slim line top centre, the time left to choose in a pill by
/// it, and the commands in a row along the bottom, all one size, your skills among them. How fast
/// the fight plays and Auto wait behind More. Results at the end. Names, levels, HP and MP sit on
/// the fighters themselves. No chat in a fight: it's back on the map once the fight is over.
struct BattleView: View {
    let controller: BattleController
    /// A phone on its side: the line of what just happened can run wider.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        ZStack {
            topBar
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 8)
                .padding(.top, 4)

            if controller.phase == .command {
                LockInStrip(controller: controller)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, 14)
                    // Upright, above the commands' row, which can reach across the bottom.
                    .padding(.bottom, verticalSizeClass == .compact ? 18 : 104)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            commands
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

    /// Along the top: what just happened, centred.
    private var topBar: some View {
        news
            .frame(maxWidth: verticalSizeClass == .compact ? 520 : 360)
            .frame(maxWidth: .infinity)
    }

    /// The top row's height: the field below is laid out clear of it (`BattleScene.portraitTopInset`).
    private static let topRowHeight: CGFloat = 40

    /// What just happened, and in a boss fight how far through its waves you are. With a turn
    /// clock, the time left to choose in a pill over the line; on its side beside it instead, as
    /// the fighters' heads come up close under the top row there (`BattleScene.layout`).
    private var news: some View {
        VStack(spacing: 6) {
            if verticalSizeClass == .compact {
                HStack(spacing: 8) {
                    clockPill
                    // As tall as the top row at least, so the field below doesn't shift with the message.
                    logLine
                        .frame(minHeight: Self.topRowHeight)
                }
            } else {
                clockPill
                logLine
                    .frame(minHeight: Self.topRowHeight)
            }
            if controller.waveCount > 1 {
                WaveTracker(wave: controller.wave, total: controller.waveCount)
            }
            if let boss = controller.boss {
                BossBar(boss: boss)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
    }

    /// One slim line of what just happened, or two when it's long: a toast, as on the map.
    private var logLine: some View {
        ToastLabel(text: controller.message)
    }

    /// The time left to choose, with a turn clock on (Settings' Time to choose). Its place is kept
    /// while a round plays, so the line beside it doesn't jump from turn to turn.
    @ViewBuilder
    private var clockPill: some View {
        if BattleController.turnSeconds != nil {
            TurnClockPill(deadline: controller.turnDeadline, window: BattleController.turnSeconds ?? 10)
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
        case .items:
            ChoiceCard(title: L("Items"), onBack: controller.back) {
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
            ChoiceCard(title: L("Seal Stones"), onBack: controller.back) {
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

/// The boss's HP along the top while it's on the field: its name in gold and its level over a long
/// red bar that drains with every blow (its own plate under its feet is as small as its wave's).
private struct BossBar: View {
    let boss: Combatant

    var body: some View {
        let level = L("Lv{level}", ["level": boss.level])
        VStack(spacing: 3) {
            HStack(spacing: 6) {
                Text(boss.name)
                    .font(HUDStyle.font(12))
                    .foregroundStyle(HUDStyle.gold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(level)
                    .font(HUDStyle.font(10).monospacedDigit())
                    .foregroundStyle(HUDStyle.cream)
                    .fixedSize()
            }
            GlossyBar(fraction: CGFloat(boss.hpFraction), color: HUDStyle.hp, height: 9)
                .animation(.easeOut(duration: 0.35), value: boss.hpFraction)
        }
        .frame(width: 240)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(HUDStyle.ink.opacity(0.85))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(HUDStyle.gold.opacity(0.7), lineWidth: 1.5))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(boss.name), \(level), \(L("HP")) \(Int((boss.hpFraction * 100).rounded()))%")
    }
}

/// While you choose, your party's faces bottom left, each ticked once that one has locked in their
/// move: your friends one by one as the time to choose runs (`BattleController.lockIns`), you when
/// you've chosen. Your side acts in the order it chose, as in Fairyland Online, so the ticks show who
/// you'd go before. Only with friends at your side.
private struct LockInStrip: View {
    let controller: BattleController

    var body: some View {
        if let lockIns = controller.lockIns {
            TimelineView(.periodic(from: lockIns.since, by: 0.25)) { context in
                HStack(spacing: 5) {
                    ForEach(controller.choosers) { fighter in
                        face(fighter, ready: fighter.isHero
                             ? controller.choosingForCompanion
                             : lockIns.friends[fighter.id].map { context.date >= lockIns.since.addingTimeInterval($0 * lockIns.window) } ?? false)
                    }
                }
            }
        }
    }

    private func face(_ fighter: Combatant, ready: Bool) -> some View {
        Image(uiImage: ArtLibrary.shared.face(fighter.art))
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .padding(3)
            .frame(width: 32, height: 32)
            .background(Circle().fill(RadialGradient(colors: [HUDStyle.portrait, HUDStyle.portraitRim],
                                                     center: UnitPoint(x: 0.4, y: 0.35), startRadius: 1, endRadius: 22)))
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(ready ? AnyShapeStyle(HUDStyle.gold) : AnyShapeStyle(HUDStyle.bevel), lineWidth: 2))
            .overlay(alignment: .bottomTrailing) {
                if ready {
                    IconImage(.check, size: 9)
                        .foregroundStyle(.white)
                        .frame(width: 15, height: 15)
                        .background(Circle().fill(Color(red: 0.25, green: 0.7, blue: 0.35)).overlay(Circle().strokeBorder(.white, lineWidth: 1.2)))
                        .offset(x: 3, y: 3)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .opacity(ready ? 1 : 0.75)
            .shadow(color: .black.opacity(0.35), radius: 2, y: 2)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: ready)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ready ? "\(fighter.name), \(L("Ready"))" : fighter.name)
    }
}

/// The time left to choose, top centre in a dark pill like the map's (`mapPill`): an hourglass and
/// the seconds over a yellow bar running down as the time does (playtesting 2026-10-26: "The timer
/// should show a yellow bar"), the same in every phase of a turn (the commands, a list, picking a
/// target). Red for the last three, with a beat as each goes. When it runs out the hero attacks. While no clock
/// ticks (a round playing, the buttons being rearranged) it keeps its place unseen.
private struct TurnClockPill: View {
    let deadline: Date?
    /// The whole time a turn gives, in seconds: the bar is full at it.
    let window: TimeInterval
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let urgentSeconds: TimeInterval = 3
    /// Red that reads on the navy (`HUDStyle.hp` is too deep there).
    private static let urgentRed = Color(red: 1, green: 0.45, blue: 0.4)

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: deadline == nil)) { context in
            let left = deadline.map { max(0, $0.timeIntervalSince(context.date)) } ?? 0
            let urgent = deadline != nil && left <= Self.urgentSeconds
            // How much of the second on show is left: 1 just as it shows, down to 0 as it goes.
            let into = CGFloat(left - left.rounded(.down))
            pill(seconds: Int(left.rounded(.up)), share: CGFloat(min(1, left / max(window, 1))), urgent: urgent)
                .scaleEffect(urgent && !reduceMotion ? 1 + 0.14 * into * into : 1)
        }
        .opacity(deadline == nil ? 0 : 1)
        .animation(.easeOut(duration: 0.2), value: deadline == nil)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Time left to choose before you attack"))
        .accessibilityHidden(deadline == nil)
    }

    private func pill(seconds: Int, share: CGFloat, urgent: Bool) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                IconImage(.hourglass, size: 13)
                    .foregroundStyle(urgent ? Self.urgentRed : HUDStyle.gold)
                Text(verbatim: String(seconds))
                    .font(HUDStyle.mono(13))
                    .foregroundStyle(urgent ? Self.urgentRed : HUDStyle.cream)
                    // Two digits' room, so the pill keeps its width as they count down.
                    .frame(minWidth: 16)
            }
            // The time left as a bar, emptying from the right; red with the numbers at the end.
            Capsule()
                .fill(HUDStyle.cream.opacity(0.18))
                .frame(width: 52, height: 4)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(urgent ? Self.urgentRed : HUDStyle.gold)
                        .frame(width: 52 * share, height: 4)
                }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 1)
        .mapPill()
        .overlay(Capsule().strokeBorder(Self.urgentRed, lineWidth: 1.5).opacity(urgent ? 1 : 0))
    }
}

// MARK: - Commands

/// The commands in one row along the bottom, all the same size (the user, 2026-10-26: "the buttons
/// to show as the same size at the bottom ... 'More' is all the way on the left"): More at the left
/// end, then a button for each of your skills (`SkillRow`), your first command (Attack unless you
/// change it) at the right end where the thumb rests, and before it, right to left, whatever else
/// turns up (Capture when there's a monster to befriend, Items when someone is low on HP).
/// Less-used commands hide behind More, and with them Auto and the fight's pace. Holding a command
/// makes them all wiggle, like the iPhone home screen: drag them into any order (onto the first, or
/// into the "Behind More" tray), then tap Done. The skills keep their place by More.
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

    private let buttonSize = CommandRow.size
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

    /// Your order (`GameSession.battleButtons`), split into the first button (the row's right end),
    /// the rest of the row (right to left, before More) and the More menu, leaving out what can't be
    /// used right now.
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

    /// More at the left end, opening up and to the right; then the skills; the first button at the
    /// right end. More's panel reaches as far right as a row of three: a shorter one makes room for it.
    private var pad: some View {
        let (main, column, more) = sections
        return SkillRow(controller: controller, skills: controller.skills, others: column.count + (main == nil ? 0 : 1),
                        least: MoreMenu.width) { size in
            MoreMenu(controller: controller, commands: more + Self.paceIDs, open: $showMore, size: size,
                     onPick: perform, onHold: arrange)
        } tail: { size in
            ForEach(Array(column.reversed()), id: \.self) { id in
                button(id, size: size)
                    .transition(.scale(scale: 0.2).combined(with: .opacity))
            }
            if let main {
                button(main, size: size, isMain: true)
            }
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

            // The row as it plays: More at the left end, the first button at the right, the rest
            // right to left between them (on up into a second row when they don't fit).
            HStack(alignment: .bottom, spacing: CommandRow.spacing) {
                RoundCommandButton(title: L("More"), icon: .more, size: buttonSize, tint: .quiet) {}
                    .allowsHitTesting(false)
                    .opacity(0.5)
                RightToLeftRows(spacing: CommandRow.spacing) {
                    ForEach(main.map { [$0] + row } ?? row, id: \.self) { id in editTile(id, size: buttonSize, isMain: id == main) }
                }
                .zIndex(order[..<divider].contains { $0 == dragging } ? 1 : 0)
            }
            .padding(.leading, 14)
        }
    }

    /// A wiggling button that can be dragged; taps do nothing while rearranging.
    private func editTile(_ id: String, size: CGFloat, isMain: Bool = false) -> some View {
        let isDragged = dragging == id
        let center = frames[id].map { CGPoint(x: $0.midX, y: $0.midY) } ?? dragPoint
        return button(id, size: size, isMain: isMain)
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
        // Something always has to be the first button.
        if order.first == GameSession.moreDivider, order.count > 1 { order.swapAt(0, 1) }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { editing = order }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func button(_ id: String, size: CGFloat, isMain: Bool = false) -> some View {
        let info = BattleCommand(id)
        return RoundCommandButton(title: info.title, icon: id == "items" && controller.needsHealing ? .heartPlus : info.icon,
                                  size: size, tint: tint(for: id, main: isMain), onHold: arrange) {
            perform(id)
        }
    }

    private func tint(for id: String, main: Bool) -> RoundCommandButton.Tint {
        if id == "capture" { return .special }
        if id == "items", controller.needsHealing { return .heal }
        return main ? .primary : .normal
    }

    private func perform(_ id: String) {
        switch id {
        case "attack": controller.attack()
        case "items": controller.openItems()
        case "guard": controller.defend()
        case "run": controller.escape()
        case "capture": controller.capture()
        default: break
        }
    }
}

/// More, at the left end of the row: a round button that, tapped, opens a panel up and to the
/// right of it, over the field, listing what waits behind it (the commands put there, then Auto and
/// the fight's pace), its dots turning into a cross that closes it, as the map's menu does
/// (playtesting 2026-10-24: it scattered more round buttons over the arc). It takes only the
/// button's room, and the row stays as it is under the panel. Holding it rearranges the buttons.
private struct MoreMenu: View {
    let controller: BattleController
    let commands: [String]
    @Binding var open: Bool
    let size: CGFloat
    let onPick: (String) -> Void
    let onHold: () -> Void

    /// The panel's width (the row makes room for it to the right of More: `CommandPad.row`).
    static let width: CGFloat = 176
    private static let spring = Animation.spring(response: 0.34, dampingFraction: 0.78)

    var body: some View {
        PressButton(action: {
            SoundEffects.shared.play(.tap, volume: 0.7)
            open.toggle()
        }, onHold: onHold) {
            Group {
                if open {
                    IconImage(.close, size: size * 0.4)
                } else {
                    IconImage(.more, size: size * 0.56)
                        .shadow(color: HUDStyle.frameDark, radius: 0, x: 1, y: 1)
                }
            }
            .foregroundStyle(.white)
            .frame(width: size, height: size)
        }
        .accessibilityLabel(open ? L("Close") : L("More"))
        .background(
            Circle()
                .fill(LinearGradient(colors: HUDStyle.tile, startPoint: .top, endPoint: .bottom))
                .overlay(Circle().strokeBorder(HUDStyle.bevel, lineWidth: 2.5))
                .overlay(
                    // The button's gloss; none on the cross.
                    Ellipse().fill(.white.opacity(open ? 0 : 0.35))
                        .frame(width: size * 0.5, height: size * 0.2)
                        .offset(y: -size * 0.3)
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 4)
        .overlay(alignment: .bottom) {
            if !open {
                Text(L("More"))
                    .font(HUDStyle.font(10))
                    .foregroundStyle(HUDStyle.cream)
                    .shadow(color: .black, radius: 0, x: 1, y: 1)
                    .fixedSize()
                    .offset(y: 15)
            }
        }
        .overlay(alignment: .topLeading) {
            if open {
                panel
                    // Its bottom a little above the button, its left edge level with the button's.
                    .alignmentGuide(.top) { $0[.bottom] + 10 }
                    .transition(.scale(scale: 0.4, anchor: .bottomLeading).combined(with: .opacity))
            }
        }
        .animation(Self.spring, value: open)
    }

    /// What waits behind More, in a window of the button's blue.
    private var panel: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(commands.enumerated()), id: \.element) { index, id in
                row(id)
                    // One after another up from the button as it opens.
                    .transition(.asymmetric(
                        insertion: .offset(y: 14).combined(with: .opacity)
                            .animation(Self.spring.delay(Double(commands.count - 1 - index) * 0.035)),
                        removal: .opacity.animation(.easeOut(duration: 0.12))))
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: HUDStyle.tile, startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(HUDStyle.bevel, lineWidth: 2.5))
        )
        .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 4)
    }

    private func row(_ id: String) -> some View {
        let isAuto = id == "auto", isPace = id == "pace"
        let fast = controller.speed > 1
        let info = BattleCommand(id)
        let healing = id == "items" && controller.needsHealing
        return Button {
            SoundEffects.shared.play(.tap, volume: 0.7)
            if isPace {
                // The pace stays open to see it change.
                controller.toggleSpeed()
            } else {
                open = false
                if isAuto { controller.toggleAuto() } else { onPick(id) }
            }
        } label: {
            HStack(spacing: 9) {
                IconImage(isAuto ? .paw : isPace ? .wind : healing ? .heartPlus : info.icon, size: 24)
                Text(isAuto ? L("Auto") : isPace ? L("Pace") : info.title)
                    .font(HUDStyle.font(13))
                    .foregroundStyle(healing ? HUDStyle.green : id == "capture" ? HUDStyle.gold : .white)
                    .shadow(color: HUDStyle.frameDark, radius: 0, x: 1, y: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                if isPace {
                    Text(fast ? "2×" : "1×")
                        .font(HUDStyle.font(13))
                        .foregroundStyle(fast ? HUDStyle.gold : HUDStyle.cream)
                } else if isAuto, controller.isAuto {
                    IconImage(.check, size: 14).foregroundStyle(HUDStyle.gold)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        // Auto is faded where it can't play (a boss, a duel, monsters too strong for it) and says why
        // when tapped.
        .opacity(isAuto && !controller.isAuto && !controller.canAuto ? 0.5 : 1)
        .accessibilityLabel(isAuto
                            ? (controller.isAuto ? L("Auto is on. Tap to choose yourself.") : L("Auto: fight on your own."))
                            : isPace ? (fast ? L("Battle speed: double. Tap for normal.") : L("Battle speed: normal. Tap for double."))
                            : info.title)
    }
}

/// Auto at work: the commands' corner turns gold and says so, its ring turning, and a tap takes
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

/// Your companion's turn, after the hero's choice: the same row as the hero's, Auto to let it
/// decide for itself where More is, then its skills, Guard, and Attack at the right end. The chip
/// on top shows whose turn it is. The hero's choice is made by then, so there's no going back to
/// it (that would start their clock over).
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

            SkillRow(controller: controller, skills: controller.companionSkills, others: 2) { size in
                RoundCommandButton(title: L("Auto"), icon: .paw, size: size, tint: .quiet) { controller.letCompanionDecide() }
            } tail: { size in
                RoundCommandButton(title: L("Guard"), icon: .shield, size: size, tint: .normal) { controller.defend() }
                RoundCommandButton(title: L("Attack"), icon: .tooth, size: size, tint: .primary) { controller.attack() }
            }
        }
        .padding(.leading, 14)
    }
}

/// The commands' row along the bottom (`CommandPad`, `CompanionPad`): every button the same size,
/// evenly spaced; the labels hang below the buttons, outside the layout.
nonisolated enum CommandRow {
    static let size: CGFloat = 56
    static let spacing: CGFloat = 14
    /// Closed up, for a row too long for a narrow phone upright.
    static let narrowSize: CGFloat = 42
    static let narrowSpacing: CGFloat = 8
}

/// A row of commands with your skills in it (the user, 2026-10-26: skills as buttons in the row,
/// not behind a menu): `lead` at the left end (More, or Auto on your companion's turn), then a
/// round button for each skill (`SkillCommandButton`), then `tail`, the other commands, Attack at
/// the right end. Too long for the phone, the row closes up and its buttons shrink a little, as
/// it always did; longer still, the skills slide sideways between the two ends, which stay put.
/// Holding a skill shows its card over the row (`SkillCard`): its level, element, MP and what it
/// does, as the list of skills once did.
private struct SkillRow<Lead: View, Tail: View>: View {
    let controller: BattleController
    let skills: [SkillDef]
    /// How many buttons `tail` holds.
    let others: Int
    /// The least the row may measure across (More's panel reaches that far right of it).
    var least: CGFloat = 0
    @ViewBuilder let lead: (CGFloat) -> Lead
    @ViewBuilder let tail: (CGFloat) -> Tail
    /// The skill whose card shows.
    @State private var card: String?
    @State private var hideCard: Task<Void, Never>?

    /// Room under the sliding skills for their names, which hang below the buttons and would be cut
    /// off there, and above them for their MP badges. Computed: a generic type can't store a static.
    private static var nameRoom: CGFloat { 18 }
    private static var badgeRoom: CGFloat { 6 }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(size: CommandRow.size, spacing: CommandRow.spacing, slides: false)
            row(size: CommandRow.narrowSize, spacing: CommandRow.narrowSpacing, slides: false)
            row(size: CommandRow.narrowSize, spacing: CommandRow.narrowSpacing, slides: true)
        }
        .overlay(alignment: .top) {
            if let id = card, let skill = skills.first(where: { $0.id == id }) {
                SkillCard(skill: skill, level: level(of: skill), cost: cost(of: skill), enoughMP: mp >= cost(of: skill))
                    // Its foot a little above the buttons, over the middle of the row.
                    .alignmentGuide(.top) { $0[.bottom] + 16 }
                    .allowsHitTesting(false)
                    .transition(.scale(scale: 0.85, anchor: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: card)
        // Debug `skills`: the first skill's card, for screenshots.
        .onAppear { if DebugLaunch.showsSkillCard, card == nil { card = skills.first?.id } }
        .onDisappear { hideCard?.cancel() }
    }

    @ViewBuilder
    private func row(size: CGFloat, spacing: CGFloat, slides: Bool) -> some View {
        let count = 1 + skills.count + others
        let short = least - (CGFloat(count) * size + CGFloat(count - 1) * spacing)
        HStack(alignment: .bottom, spacing: spacing) {
            lead(size)
            if slides {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: spacing) {
                        buttons(size: size)
                    }
                    .padding(.top, Self.badgeRoom)
                    .padding(.bottom, Self.nameRoom)
                    .padding(.horizontal, 4)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                // In the row only as tall as its buttons, level with the rest.
                .padding(.top, -Self.badgeRoom)
                .padding(.bottom, -Self.nameRoom)
            } else {
                if short > spacing { Color.clear.frame(width: short - spacing, height: size) }
                buttons(size: size)
            }
            tail(size)
        }
    }

    private func buttons(size: CGFloat) -> some View {
        ForEach(skills) { skill in
            SkillCommandButton(skill: skill, cost: cost(of: skill), usable: controller.canUse(skill), size: size,
                               picked: card == skill.id) {
                use(skill)
            } onHold: {
                show(skill)
            }
            .transition(.scale(scale: 0.2).combined(with: .opacity))
        }
    }

    /// Whoever is choosing: your companion on its turn, else your hero.
    private var mp: Int { (controller.choosingForCompanion ? controller.companion?.mp : controller.hero?.mp) ?? 0 }

    private func level(of skill: SkillDef) -> Int {
        controller.choosingForCompanion ? controller.companionLevel(of: skill) : controller.level(of: skill)
    }

    private func cost(of skill: SkillDef) -> Int {
        controller.choosingForCompanion ? controller.companionCost(of: skill) : controller.cost(of: skill)
    }

    /// A greyed skill does nothing but say why (`BattleController.useSkill`: not the MP for it,
    /// nobody fainted to revive).
    private func use(_ skill: SkillDef) {
        hideCard?.cancel()
        card = nil
        if !controller.canUse(skill) { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
        controller.useSkill(skill)
    }

    /// Its card, for a few seconds or until a skill is tapped.
    private func show(_ skill: SkillDef) {
        card = skill.id
        hideCard?.cancel()
        hideCard = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            card = nil
        }
    }
}

/// A skill as a round button in the battle's row (`SkillRow`), as big as the commands beside it:
/// its icon (art/sprites/skill_<id>.png, drawn as light on its tile's colour) cut round in a rim
/// of that colour, its MP in a badge on the rim and its name under it. Faded and grey when it
/// can't be used now. Holding it calls `onHold` (its card) instead of `action`.
struct SkillCommandButton: View {
    let skill: SkillDef
    let cost: Int
    let usable: Bool
    let size: CGFloat
    /// Its card is showing: a gold rim.
    var picked = false
    let action: () -> Void
    var onHold: (() -> Void)? = nil

    @State private var pressed = false
    /// Set by a hold, so letting go afterwards doesn't also count as a tap.
    @State private var held = false

    var body: some View {
        face
            .saturation(usable ? 1 : 0)
            .opacity(usable ? 1 : 0.45)
            .contentShape(Circle())
            .scaleEffect(pressed ? 0.9 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: pressed)
            .onTapGesture {
                if held { held = false } else { action() }
            }
            .onLongPressGesture(minimumDuration: 0.4) {
                guard let onHold else { return }
                held = true
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onHold()
            } onPressingChanged: { pressing in
                pressed = pressing
                if pressing { held = false }
            }
            .overlay(alignment: .bottom) {
                // Its name, as the commands have theirs; a long one cut short (the card has it whole).
                Text(skill.name)
                    .font(HUDStyle.font(10))
                    .foregroundStyle(HUDStyle.cream.opacity(usable ? 1 : 0.6))
                    .shadow(color: .black, radius: 0, x: 1, y: 1)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.8)
                    .frame(width: size * 1.15)
                    .offset(y: 15)
                    .allowsHitTesting(false)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(skill.name)
            .accessibilityValue(L("{cost} MP", ["cost": cost]))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
            .accessibilityAction(named: L("Skill details")) { onHold?() }
    }

    private var face: some View {
        ZStack {
            Circle().fill(Color(uiColor: skill.tileColor))
            if let picture = skill.art.flatMap(ArtLibrary.shared.artImage) {
                Image(uiImage: picture)
                    .interpolation(picture.size.width > 64 ? .high : .none)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size - 6, height: size - 6)
                    .clipShape(Circle())
            } else {
                IconImage(skill.icon.flatMap(GameIcon.init) ?? .sparkles, size: size * 0.56)
                    .foregroundStyle(.white)
                    .shadow(color: HUDStyle.ink.opacity(0.7), radius: 0, x: 0, y: 1)
            }
            // The commands' gloss.
            Ellipse().fill(.white.opacity(0.28))
                .frame(width: size * 0.5, height: size * 0.18)
                .offset(y: -size * 0.3)
            Circle().strokeBorder(picked ? AnyShapeStyle(HUDStyle.gold) : AnyShapeStyle(Color.white.opacity(0.75)),
                                  lineWidth: picked ? 3 : 2)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 4)
        .overlay(alignment: .topTrailing) {
            if cost > 0 {
                Text(verbatim: String(cost))
                    .font(HUDStyle.mono(max(8, size * 0.17)))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .frame(minWidth: size * 0.32, minHeight: size * 0.28)
                    .background(Capsule().fill(HUDStyle.mp).overlay(Capsule().strokeBorder(.white.opacity(0.85), lineWidth: 1)))
                    .offset(x: 3, y: -3)
            }
        }
    }
}

/// A held skill's card, over the row: its name, element and level, its MP (red when there isn't
/// enough) and what it does.
private struct SkillCard: View {
    let skill: SkillDef
    let level: Int
    let cost: Int
    let enoughMP: Bool

    /// The MP's blue, lighter to read on the navy.
    private static let mpLight = Color(red: 0.55, green: 0.78, blue: 1)
    private static let shortRed = Color(red: 1, green: 0.45, blue: 0.4)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let element = skill.element {
                    ElementIcon(element: element, size: 16)
                }
                Text(skill.name)
                    .font(HUDStyle.font(13))
                    .foregroundStyle(HUDStyle.gold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(L("Lv{level}", ["level": level]))
                    .font(HUDStyle.font(10).monospacedDigit())
                    .foregroundStyle(HUDStyle.cream)
                    .fixedSize()
                Spacer(minLength: 6)
                Text(L("{cost} MP", ["cost": cost]))
                    .font(HUDStyle.font(11).monospacedDigit())
                    .foregroundStyle(enoughMP ? Self.mpLight : Self.shortRed)
                    .fixedSize()
            }
            if let description = skill.description, !description.isEmpty {
                Text(description)
                    .font(HUDStyle.font(11))
                    .foregroundStyle(HUDStyle.cream.opacity(0.85))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 220, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(HUDStyle.ink.opacity(0.92))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(HUDStyle.gold.opacity(0.6), lineWidth: 1.5))
        )
        .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 2)
        .accessibilityElement(children: .combine)
    }
}

/// The name and icon of a battle button id (see `GameSession.battleButtons`).
private struct BattleCommand {
    let title: String
    let icon: GameIcon

    init(_ id: String) {
        switch id {
        case "attack": title = L("Attack"); icon = .sword
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
        case .normal, .quiet: HUDStyle.tile
        }
    }

    /// The HUD's own glossy blue, top to bottom, in its bevel (`FLIconButton`): the everyday
    /// commands and More, not cream (playtesting 2026-10-24: "the light yellow doesn't work").
    private var isBlue: Bool { tint == .normal || tint == .quiet }

    /// Buttons that want attention pulse with a coloured glow.
    private var glow: Color? {
        switch tint {
        case .special: HUDStyle.gold
        case .heal: HUDStyle.green
        default: nil
        }
    }

    /// A light button (gold, green), its icon on a pale ground.
    private var isLight: Bool {
        switch tint {
        case .special, .heal, .lit: true
        case .primary, .normal, .quiet: false
        }
    }

    private var foreground: Color {
        switch tint {
        case .primary, .normal, .quiet: .white
        case .special, .heal, .lit: HUDStyle.ink
        }
    }

    /// Under an icon: on the blue, the HUD buttons' hard dark blue edge; on a light button a crisp
    /// warm shadow (a soft dark rim round it looked muddy there).
    private var iconShadow: (color: Color, radius: CGFloat) {
        if isBlue { return (HUDStyle.frameDark, 0) }
        if isLight { return (Color(red: 0.43, green: 0.28, blue: 0.16).opacity(0.4), 0.4) }
        return (.clear, 0)
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
                    // Big: drawn as light, the icons washed out on the cream buttons at two fifths
                    // of them (playtesting 2026-10-24).
                    IconImage(icon, size: size * 0.56)
                        .shadow(color: iconShadow.color, radius: iconShadow.radius, x: isBlue ? 1 : 0, y: 1)
                }
                if size >= 80 {
                    Text(title).font(HUDStyle.font(12))
                }
            }
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(isBlue ? AnyShapeStyle(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                                 : AnyShapeStyle(RadialGradient(colors: colors, center: UnitPoint(x: 0.35, y: 0.3), startRadius: 1, endRadius: size * 0.75)))
                    .overlay(Circle().strokeBorder(isBlue ? AnyShapeStyle(HUDStyle.bevel) : AnyShapeStyle(Color.white.opacity(0.75)),
                                                   lineWidth: isBlue ? 2.5 : 2))
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
    let onBack: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WindowTitle(title, onClose: onBack)
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
                    GoldPill(amount: result.gold, size: 15, sign: "+")
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
        .contentShape(HUDStyle.windowShape)
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
