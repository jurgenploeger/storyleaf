import SwiftUI

/// The HUD pieces the first-play tour points at. Mark one with `.coachTarget(_:)`.
nonisolated enum CoachTarget: Hashable, Sendable {
    case status, joystick, minimap, toolbar, chat
}

nonisolated struct CoachAnchors: PreferenceKey {
    static var defaultValue: [CoachTarget: Anchor<CGRect>] { [:] }

    static func reduce(value: inout [CoachTarget: Anchor<CGRect>], nextValue: () -> [CoachTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Lets the first-play tour put a spotlight on this view.
    func coachTarget(_ target: CoachTarget) -> some View {
        anchorPreference(key: CoachAnchors.self, value: .bounds) { [target: $0] }
    }
}

/// Whether the tour still needs showing. It shows once per device, the first time you play.
/// Debug launches (tests, screenshots) skip it unless they pass the `coach` flag.
enum CoachMarks {
    private static let key = "coachMarksDone"

    static var shouldShow: Bool {
        DebugLaunch.showsCoachMarks || (!DebugLaunch.isActive && !UserDefaults.standard.bool(forKey: key))
    }

    static func markDone() {
        guard !DebugLaunch.isActive else { return }
        UserDefaults.standard.set(true, forKey: key)
    }
}

private struct CoachStep {
    let target: CoachTarget?
    let icon: GameIcon
    let title: String
    let text: String

    static var all: [CoachStep] { [
        CoachStep(target: .status, icon: .heart, title: L("Health and magic"),
                  text: L("H is your health and M your magic; the thin bar under them is your EXP. The round badge shows your level. Once you have a companion, its face and bars show under yours.")),
        CoachStep(target: .joystick, icon: .tap, title: L("Walking"),
                  text: L("Drag the stick to walk, or tap the ground and your hero walks there.")),
        CoachStep(target: .minimap, icon: .map, title: L("Where you are"),
                  text: L("The minimap shows what's around you. Tap it for the world map.")),
        CoachStep(target: .toolbar, icon: .backpack, title: L("Your adventure"),
                  text: L("Tap the menu for your hero, companion, friends, inventory, quests and settings. A gold dot means there's something new.")),
        CoachStep(target: .chat, icon: .talk, title: L("Other adventurers"),
                  text: L("Adventurers wander Storyleaf too. Read what they say and chat back here. What you win and find shows for a moment, then waits here too.")),
        CoachStep(target: nil, icon: .star, title: L("Your first quest"),
                  text: L("Walk up to someone with a gold ! and tap Talk. New adventurers start with Elder Oak in Meadowbrook.")),
    ] }
}

/// The first-play tour: dims the screen except for one control at a time, with a note beside it:
/// Previous, Next and Skip, and the close button in its corner.
struct CoachMarksView: View {
    let anchors: [CoachTarget: Anchor<CGRect>]
    let onDone: () -> Void
    @State private var index = 0
    @State private var pulse = false

    private var steps: [CoachStep] { CoachStep.all }

    var body: some View {
        // This reader keeps to the safe area, so it knows where the Dynamic Island is on a phone
        // lying down (one that ignores the safe area reads its insets as zero); the spotlight
        // inside covers the whole screen.
        GeometryReader { safe in
            GeometryReader { proxy in
                let step = steps[index]
                let hole = step.target.flatMap { anchors[$0] }.map { proxy[$0].insetBy(dx: -8, dy: -8) }
                ZStack {
                    SpotlightShape(hole: hole ?? CGRect(x: proxy.size.width / 2, y: proxy.size.height / 2, width: 0, height: 0))
                        .fill(Color.black.opacity(0.62), style: FillStyle(eoFill: true))
                        // Swallow taps, so the hero doesn't walk off during the tour.
                        .contentShape(Rectangle())
                        .onTapGesture {}

                    if let hole {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(HUDStyle.gold, lineWidth: 3)
                            .frame(width: hole.width, height: hole.height)
                            .scaleEffect(pulse ? 1.05 : 1)
                            .position(x: hole.midX, y: hole.midY)
                            .allowsHitTesting(false)
                    }

                    note(step, hole: hole, in: proxy.size, insets: safe.safeAreaInsets)
                }
            }
            .ignoresSafeArea()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    /// The note sits below a control in the top half of the screen and above one in the bottom half,
    /// clear of the Dynamic Island and the rounded corners when the phone lies on its side.
    private func note(_ step: CoachStep, hole: CGRect?, in size: CGSize, insets: EdgeInsets) -> some View {
        let leading = max(12, insets.leading + 8), trailing = max(12, insets.trailing + 8)
        let width = min(330, size.width - leading - trailing)
        var alignment = Alignment.center
        var edges = EdgeInsets()
        if let hole {
            let left = min(max(leading, hole.midX - width / 2), size.width - width - trailing)
            edges.leading = left
            if hole.midY < size.height / 2 {
                alignment = .topLeading
                edges.top = hole.maxY + 14
            } else {
                alignment = .bottomLeading
                edges.bottom = size.height - hole.minY + 14
            }
        }
        return bubble(step)
            .frame(width: width)
            .padding(edges)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .animation(.easeInOut(duration: 0.3), value: index)
    }

    private func bubble(_ step: CoachStep) -> some View {
        let isLast = index == steps.count - 1
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                IconImage(step.icon, size: 16).foregroundStyle(HUDStyle.gold)
                Text(step.title).font(HUDStyle.font(14)).foregroundStyle(HUDStyle.gold)
                Spacer(minLength: 4)
                Text("\(index + 1) / \(steps.count)").font(HUDStyle.font(10)).foregroundStyle(HUDStyle.dim)
            }
            // Clear of the close button in the corner.
            .padding(.trailing, 26)
            Text(step.text)
                .font(HUDStyle.font(11))
                .foregroundStyle(HUDStyle.cream)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(L("Skip"), action: onDone)
                    .buttonStyle(PixelButtonStyle(compact: true))
                    .opacity(isLast ? 0 : 1)
                    .disabled(isLast)
                Spacer(minLength: 0)
                Button {
                    withAnimation(.easeInOut(duration: 0.35)) { index -= 1 }
                } label: {
                    Label(L("Previous"), icon: .arrowLeft, size: 12)
                }
                .buttonStyle(PixelButtonStyle(compact: true))
                .opacity(index == 0 ? 0.4 : 1)
                .disabled(index == 0)
                Button {
                    if isLast {
                        onDone()
                    } else {
                        withAnimation(.easeInOut(duration: 0.35)) { index += 1 }
                    }
                } label: {
                    Label(isLast ? L("Let's go") : L("Next"), icon: isLast ? .check : .arrowRight, size: 12)
                }
                .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
            }
        }
        .padding(14)
        .background(HUDStyle.panel)
        // Closing it ends the tour, like Skip.
        .windowCloseButton(onDone)
    }
}

/// The whole screen with a rounded hole cut out, which glides from one control to the next.
nonisolated struct SpotlightShape: Shape {
    var hole: CGRect

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(hole.origin.x, hole.origin.y), AnimatablePair(hole.width, hole.height)) }
        set { hole = CGRect(x: newValue.first.first, y: newValue.first.second, width: newValue.second.first, height: newValue.second.second) }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if hole.width > 0, hole.height > 0 {
            path.addRoundedRect(in: hole, cornerSize: CGSize(width: 14, height: 14))
        }
        return path
    }
}
