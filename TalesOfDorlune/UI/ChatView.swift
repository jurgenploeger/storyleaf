import SwiftUI

/// The map's chat window: everything adventurers, villagers and NPCs have said here, the game's
/// announcements, and a box to say something yourself (someone might answer).
struct ChatView: View {
    let session: GameSession
    let onSay: (String) -> Void
    let onClose: () -> Void
    @State private var draft = ""
    @FocusState private var typing: Bool
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                FLTitleBar(title: L("Chat · {map}", ["map": session.mapName]), icon: .talk, onClose: onClose)
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(session.chat) { line in
                                ChatLineView(line: line)
                                    .id(line.id)
                            }
                        }
                        .padding(12)
                    }
                    .defaultScrollAnchor(.bottom)
                    .onChange(of: session.chat.last?.id) {
                        guard let last = session.chat.last?.id else { return }
                        withAnimation(.easeOut(duration: 0.2)) { reader.scrollTo(last, anchor: .bottom) }
                        session.unreadChat = 0
                    }
                }
                .frame(maxHeight: .infinity)

                HStack(spacing: 8) {
                    TextField(L("Say something…"), text: $draft)
                        .font(HUDStyle.font(13))
                        .foregroundStyle(HUDStyle.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(HUDStyle.cream))
                        .focused($typing)
                        .submitLabel(.send)
                        .onSubmit(send)
                    Button(action: send) {
                        IconImage(.arrowRight, size: 18)
                            .foregroundStyle(HUDStyle.ink)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(HUDStyle.gold).overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1.5)))
                    }
                    .buttonStyle(PressScaleStyle())
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel(L("Send"))
                }
                .padding(10)
                .background(HUDStyle.ink.opacity(0.6))
            }
            // As big as the menu's windows (playtesting 2026-10-25: "Make the chat modal the same size as
            // the other modals"): out to the HUD's own margins (`MenuMorph`).
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .gameWindow()
            .padding(.horizontal, MenuMorph.side)
            .padding(.top, MenuMorph.side)
            .padding(.bottom, MenuMorph.bottom(onItsSide: verticalSizeClass == .compact))
            .ignoresSafeArea(.container, edges: MenuMorph.bottomEdge(onItsSide: verticalSizeClass == .compact))
        }
        .onAppear { session.unreadChat = 0 }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        onSay(String(text.prefix(80)))
        draft = ""
    }
}

struct ChatLineView: View {
    let line: GameSession.ChatLine

    private var color: Color {
        switch line.kind {
        case .you: HUDStyle.gold
        case .adventurer: Color(uiColor: Crowd.adventurerColor)
        case .villager: HUDStyle.cream
        case .npc: HUDStyle.green
        case .system: HUDStyle.dim
        case .announcement: HUDStyle.gold
        case .notice: ChatLineView.color(of: line.tone ?? .system)
        }
    }

    /// A notice's colour, by its kind of news: as the HUD's toasts mark it (`WorldHUD`).
    static func color(of tone: GameSession.LogLine.Kind) -> Color {
        switch tone {
        case .system: HUDStyle.nameYellow
        case .quest: Color(red: 0.55, green: 0.95, blue: 1)
        case .battle: .white
        case .reward: HUDStyle.green
        case .announcement: HUDStyle.gold
        }
    }

    /// A notice's mark, by its kind of news.
    static func icon(of tone: GameSession.LogLine.Kind) -> GameIcon {
        switch tone {
        case .system: .sparkles
        case .quest: .star
        case .battle: .sword
        case .reward: .gift
        case .announcement: .sparkles
        }
    }

    var body: some View {
        switch line.kind {
        case .system:
            Text(line.text)
                .font(HUDStyle.font(11))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
        case .announcement:
            // The game's own notices: a gold banner, apart from what people say.
            HStack(alignment: .top, spacing: 7) {
                IconImage(.sparkles, size: 14)
                    .foregroundStyle(HUDStyle.gold)
                Text(line.text)
                    .font(HUDStyle.font(12))
                    .foregroundStyle(HUDStyle.gold)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(HUDStyle.gold.opacity(0.13))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(HUDStyle.gold.opacity(0.75), lineWidth: 1))
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L("Announcement: {text}", ["text": line.text]))
        case .notice:
            // What happened to you lately, toasted on the map first.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                IconImage(ChatLineView.icon(of: line.tone ?? .system), size: 11)
                    .foregroundStyle(color)
                Text(line.text)
                    .font(HUDStyle.font(11))
                    .foregroundStyle(color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .you, .adventurer, .villager, .npc:
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let badge = line.badge {
                    NameBadge(badge: badge)
                }
                (Text("[\(line.speaker)] ").foregroundStyle(color) + Text(line.text).foregroundStyle(HUDStyle.cream))
                    .font(HUDStyle.font(12))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
