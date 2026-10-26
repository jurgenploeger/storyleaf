import SwiftUI

/// Where to, by Bridge of Light, a Homeward Feather or a waystone (`GameCoordinator.Travel`): every
/// town you've been to but the one you're in, your checkpoint first, then the waystones you've woken
/// (`GameSession.travelDestinations`). A tap goes there. Nothing's spent until then: closing the
/// window keeps your MP or your feather.
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
                WindowTitle(L("Where to?"), onClose: onClose)
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        header
                        ForEach(session.travelDestinations, id: \.self) { place in row(place) }
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
        case .waystone:
            means(icon: IconImage(.sparkles, size: 22).foregroundStyle(HUDStyle.gold).frame(width: 36, height: 36),
                  name: L("Waystone"), cost: L("Free"))
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

    /// A town (its map's id) or a waystone (its own id), by name.
    private func row(_ place: String) -> some View {
        let waystone = Content.shared.npc(place)?.role == .waystone
        let land = waystone ? Content.shared.home(ofNPC: place) : Content.shared.map(place)
        return Button { onGo(place) } label: {
            HStack(spacing: 10) {
                IconImage(waystone ? .sparkles : .map, size: 18)
                    .foregroundStyle(HUDStyle.gold)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.white.opacity(0.06)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(land?.name ?? place).font(HUDStyle.font(13))
                    if waystone {
                        Text(L("Waystone")).font(HUDStyle.font(10)).foregroundStyle(HUDStyle.dim)
                    }
                }
                Spacer(minLength: 4)
                if place == session.checkpoint.mapID {
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
