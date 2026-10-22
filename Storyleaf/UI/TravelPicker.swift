import SwiftUI

/// Where to, by Bridge of Light or a Homeward Feather (`GameCoordinator.Travel`): every town you've
/// been to but the one you're in (`GameSession.travelDestinations`), your checkpoint first. A tap
/// goes there. Nothing's spent until then: closing the window keeps your MP or your feather.
struct TravelPicker: View {
    let session: GameSession
    let travel: GameCoordinator.Travel
    let onGo: (String) -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
            VStack(spacing: 0) {
                FLTitleBar(title: L("Where to?"), icon: .map, onClose: onClose)
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        header
                        ForEach(session.travelDestinations, id: \.self) { town in row(town) }
                    }
                    .padding(14)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .frame(maxWidth: 420)
            .fitHeight()
            .gameWindow()
            .padding(20)
            .popIn()
        }
        .foregroundStyle(HUDStyle.cream)
    }

    /// What's taking you, and what it costs.
    @ViewBuilder private var header: some View {
        switch travel {
        case .bridge(let id):
            if let skill = Content.shared.skill(id) {
                let cost = GameSession.mpCost(of: skill, level: session.skillLevel(id))
                means(icon: SkillIcon(skill: skill, size: 36), name: skill.name, cost: L("{cost} MP", ["cost": cost]))
            }
        case .feather(let id):
            if let item = Content.shared.item(id) {
                means(icon: ItemIcon(item: item, size: 36, count: session.count(of: id)), name: item.name, cost: L("One is used up."))
            }
        }
    }

    private func means(icon: some View, name: String, cost: String) -> some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(HUDStyle.font(13))
                Text(cost).font(HUDStyle.font(10)).foregroundStyle(HUDStyle.dim)
            }
            Spacer(minLength: 0)
        }
    }

    private func row(_ town: String) -> some View {
        Button { onGo(town) } label: {
            HStack(spacing: 10) {
                IconImage(.map, size: 18)
                    .foregroundStyle(HUDStyle.gold)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.white.opacity(0.06)))
                Text(Content.shared.map(town)?.name ?? town).font(HUDStyle.font(13))
                Spacer(minLength: 4)
                if town == session.checkpoint.mapID {
                    Text(L("Checkpoint")).font(HUDStyle.font(10)).foregroundStyle(HUDStyle.gold)
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
    }
}
