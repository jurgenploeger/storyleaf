import SwiftUI

/// Your party is full and a new friend wants to join: pick who stays behind (it can be the
/// newcomer). Like Fairyland Online, you can't carry more than five companions.
struct LeaveBehindCard: View {
    let session: GameSession
    let onDone: () -> Void
    @State private var choice: UUID?

    var body: some View {
        let newcomer = session.pendingPet
        let everyone = session.data.pets + (newcomer.map { [$0] } ?? [])
        VStack(spacing: 12) {
            VStack(spacing: 3) {
                Text(L("Party full!"))
                    .font(HUDStyle.font(24))
                    .foregroundStyle(HUDStyle.gold)
                    // Clear of the close button, and still centred.
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 18)
                Text(L("You can travel with {count} companions. Who stays behind?", ["count": GameSession.maxPets]))
                    .font(HUDStyle.font(12))
                    .foregroundStyle(HUDStyle.cream)
                    .multilineTextAlignment(.center)
            }
            // Scrolls only when it can't all fit (a phone on its side).
            FitOrScroll {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                    ForEach(everyone) { pet in
                        let isNew = pet.id == newcomer?.id
                        Button {
                            choice = pet.id
                        } label: {
                            VStack(spacing: 3) {
                                SpriteImage(art: session.artID(for: pet), size: 56)
                                Text(pet.name).font(HUDStyle.font(12)).lineLimit(1)
                                Text(L("Lv {level} · {monster}", ["level": pet.level, "monster": session.species(of: pet)?.name ?? ""]))
                                    .font(HUDStyle.font(9))
                                    .foregroundStyle(HUDStyle.dim)
                                    .lineLimit(1)
                            }
                            .foregroundStyle(HUDStyle.cream)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(choice == pet.id ? HUDStyle.orange.opacity(0.35) : .white.opacity(0.07))
                                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(choice == pet.id ? HUDStyle.orange : .clear, lineWidth: 2))
                            )
                            .overlay(alignment: .topTrailing) {
                                if isNew {
                                    Text(L("NEW"))
                                        .font(HUDStyle.font(9))
                                        .foregroundStyle(HUDStyle.ink)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(HUDStyle.gold))
                                        .padding(5)
                                }
                            }
                        }
                        .buttonStyle(PressScaleStyle())
                    }
                }
            }
            if let choice, let pet = everyone.first(where: { $0.id == choice }) {
                Button(pet.id == newcomer?.id ? L("Let {name} go", ["name": pet.name]) : L("Leave {name} behind", ["name": pet.name])) {
                    session.leaveBehind(choice)
                    onDone()
                }
                .buttonStyle(PixelButtonStyle(tint: HUDStyle.orange))
            } else {
                Text(L("Tap a companion")).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
            }
        }
        .padding(20)
        .frame(maxWidth: 460)
        .gameWindow()
        // Closing it keeps your party as it is: the newcomer goes back to the wild.
        .windowCloseButton {
            if let newcomer { session.leaveBehind(newcomer.id) }
            onDone()
        }
        .padding(20)
    }
}
