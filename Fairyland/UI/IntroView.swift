import SwiftUI

/// The onboarding before a new hero is made: the story in three chapters, each with a little
/// animated scene made of the game itself (StoryVignette), then how to play (the game played: a
/// walk, a fight, a Seal Stone, a level up and a quest, each tip lighting up as it plays) and the
/// whole world map. Also opens from the title screen, at How to play.
struct IntroView: View {
    /// What the last page's button says ("Create your hero", or "Done" when just reading).
    let finishTitle: String
    /// The close button: back to the title screen, without making a hero.
    let onClose: () -> Void
    let onFinish: () -> Void
    @State private var page: Int

    private static let pageCount = 5
    /// How to play's page, after the story's three.
    static let howToPlayPage = 3

    init(finishTitle: String, startPage: Int = 0, onClose: @escaping () -> Void, onFinish: @escaping () -> Void) {
        self.finishTitle = finishTitle
        self.onClose = onClose
        self.onFinish = onFinish
        _page = State(initialValue: min(max(0, startPage), Self.pageCount - 1))
    }

    var body: some View {
        VStack(spacing: 10) {
            ScrollView {
                Group {
                    switch page {
                    case 0: ChapterPage(chapter: .gathering)
                    case 1: ChapterPage(chapter: .shadows)
                    case 2: ChapterPage(chapter: .arrival)
                    case Self.howToPlayPage: HowToPlayPage()
                    default: WorldPage()
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: 720)
            .background(HUDStyle.panel)
            .windowCloseButton(onClose)
            .id(page)
            .transition(.opacity)

            // The last page's button is the longest ("Create your hero"): there's no Skip to make room
            // for, and on a narrow phone the page dots step aside too.
            ViewThatFits(in: .horizontal) {
                controls(dots: true)
                controls(dots: false)
            }
            .frame(maxWidth: 720)
        }
        .padding(16)
    }

    private var isLastPage: Bool { page == Self.pageCount - 1 }

    private func controls(dots: Bool) -> some View {
        HStack(spacing: 10) {
            if !isLastPage {
                Button(L("Skip"), action: onFinish)
                    .buttonStyle(PixelButtonStyle(compact: true))
            }
            Spacer(minLength: 0)
            if dots {
                PageDots(count: Self.pageCount, current: page)
                Spacer(minLength: 0)
            }
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { page -= 1 }
            } label: {
                Label(L("Back"), icon: .arrowLeft)
            }
            .buttonStyle(PixelButtonStyle(compact: true))
            .opacity(page == 0 ? 0.4 : 1)
            .disabled(page == 0)
            Button {
                if isLastPage {
                    onFinish()
                } else {
                    withAnimation(.easeInOut(duration: 0.25)) { page += 1 }
                }
            } label: {
                Label(isLastPage ? finishTitle : L("Next"), icon: .arrowRight)
            }
            .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
        }
        .lineLimit(1)
    }
}

private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? HUDStyle.gold : HUDStyle.cream.opacity(0.45))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(L("Page {page} of {count}", ["page": current + 1, "count": count]))
    }
}

private struct PageTitle: View {
    let text: String
    let icon: GameIcon

    var body: some View {
        Label(text, icon: icon, size: 18)
            .font(HUDStyle.font(18))
            .foregroundStyle(HUDStyle.gold)
            .shadow(color: HUDStyle.frameDark, radius: 0, x: 1, y: 1)
            // Clear of the close button in the corner.
            .padding(.trailing, 24)
    }
}

// MARK: - Story

/// A chapter of the story: its title, its living picture, and its lines told one after another.
private struct ChapterPage: View {
    let chapter: StoryScene.Kind

    private var title: (text: String, icon: GameIcon) {
        switch chapter {
        case .gathering: (text: L("Once upon a time"), icon: GameIcon.book)
        case .shadows: (text: L("The tales go wrong"), icon: GameIcon.moon)
        case .arrival, .reel: (text: L("A new adventurer"), icon: GameIcon.sparkles)
        }
    }

    private var lines: [String] {
        switch chapter {
        case .gathering: [
            L("Long ago, the goddess Liora gathered the world's fairy tales into one land: Storyleaf. Villages grew up between the stories, and adventurers came from far and wide to explore them."),
            L("Every tale found a home: Thumbelina's lotus pond, Snow White's forest, the Emerald Road to Oz and the golden sands of the Thousand and One Nights. For a long time, they all lived happily ever after."),
        ]
        case .shadows: [
            L("Lately the tales have been going wrong. A Big Bad Wolf prowls the Snow White Forest. A Rat King has cut off the dwarves of Ingothold. A dragon drinks at the oasis in Genie Desert and scares away the caravans."),
            L("Nobody knows why. Some say pages are being torn from Liora's great storybook, and every lost page lets a little more darkness in."),
        ]
        case .arrival, .reel: [
            L("You arrive in Meadowbrook as a new adventurer, with the whole of Storyleaf ahead of you."),
            L("Elder Oak is waiting in the village square with three gifts. Find a companion, learn from the guild masters, and set the stories right, one tale at a time."),
        ]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageTitle(text: title.text, icon: title.icon)
            StoryVignette(chapter)
            StoryLines(lines: lines)
        }
        .font(HUDStyle.font(12))
        .foregroundStyle(HUDStyle.cream)
    }
}

/// Lines that appear one after another, as if read aloud (all at once with Reduce Motion, or
/// when tapped).
private struct StoryLines: View {
    let lines: [String]
    @State private var shown = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                Text(line)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(index < shown ? 1 : 0)
                    .offset(y: index < shown ? 0 : 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeOut(duration: 0.3)) { shown = lines.count } }
        .task {
            guard !reduceMotion else {
                shown = lines.count
                return
            }
            for index in lines.indices where index >= shown {
                do {
                    try await Task.sleep(for: .milliseconds(index == 0 ? 400 : 1_400))
                } catch {
                    return
                }
                withAnimation(.easeOut(duration: 0.6)) { shown = max(shown, index + 1) }
            }
        }
    }
}

// MARK: - How to play

private struct Tip {
    let icon: GameIcon
    let title: String
    let text: String
}

private struct HowToPlayPage: View {
    /// The game played, a part for each tip; tapping a tip shows its part.
    @State private var reel = StoryScene(kind: .reel, startClip: DebugLaunch.introClip ?? 0)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let tips: [Tip] = [
        Tip(icon: .tap, title: L("Walk"), text: L("Drag the stick in the corner, or tap the ground and your hero walks there.")),
        Tip(icon: .sword, title: L("Battle"), text: L("Monsters jump out as you explore the wild. Battles take turns: attack, cast a skill or use an item.")),
        Tip(icon: .paw, title: L("Companions"), text: L("Throw a Seal Stone at a monster to befriend it: the weaker it is, the likelier it works. Keep up to five.")),
        Tip(icon: .star, title: L("Grow"), text: L("Every level gives a skill point. At level {level}, visit a guild master in town to become a Fighter, Mage or Beast Tamer.", ["level": Content.shared.classChoiceLevel])),
        Tip(icon: .star, title: L("Quests"), text: L("Villagers with a gold ! have work for you. Quests reward you and open the roads to new places.")),
        Tip(icon: .heart, title: L("Towns"), text: L("Shops, healers and checkpoints wait in town. Your progress saves by itself.")),
    ]

    var body: some View {
        // The tip the picture is showing now (none while it holds still).
        let showing = reduceMotion ? nil : reel.hud.tip
        VStack(alignment: .leading, spacing: 12) {
            PageTitle(text: L("How to play"), icon: .sparkles)
            VignetteView(scene: reel)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
                ForEach(Array(tips.enumerated()), id: \.offset) { index, tip in
                    let lit = showing == index
                    HStack(alignment: .top, spacing: 10) {
                        IconImage(tip.icon, size: 20)
                            .foregroundStyle(HUDStyle.gold)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tip.title).font(HUDStyle.font(13)).foregroundStyle(HUDStyle.gold)
                            Text(tip.text).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.cream)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    // The whole cell, so every highlight is the same width and the text lines up.
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(lit ? 0.12 : 0))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(HUDStyle.gold.opacity(lit ? 0.8 : 0), lineWidth: 1.5))
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        reel.play(clip: StoryScene.Clip.showing(tip: index).rawValue)
                    }
                }
            }
            .animation(.easeOut(duration: 0.3), value: reel.hud.tip)
        }
    }
}

// MARK: - World map

private struct WorldPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PageTitle(text: L("The world of Storyleaf"), icon: .map)
            Text(L("Roads join every place to its neighbours. Your journey starts in Meadowbrook. Quests open the roads further out, where stronger monsters live."))
                .font(HUDStyle.font(11))
                .foregroundStyle(HUDStyle.cream)
                .fixedSize(horizontal: false, vertical: true)
            IntroAtlas(highlight: Content.shared.startMap)
            HStack(spacing: 14) {
                Label { Text(L("Start")) } icon: { Circle().fill(HUDStyle.gold).frame(width: 9, height: 9) }
                Label { Text(L("Town")) } icon: { RoundedRectangle(cornerRadius: 2).strokeBorder(HUDStyle.gold, lineWidth: 2).frame(width: 10, height: 10) }
                Label { Text(L("Boss")) } icon: { IconImage(.sword, size: 10).foregroundStyle(HUDStyle.hp) }
            }
            .font(HUDStyle.font(10))
            .foregroundStyle(HUDStyle.dim)
            .labelStyle(CompactLabelStyle())
        }
    }
}

/// Every map laid out by its roads: each exit puts the next map one step north, south, east or
/// west of the one it leaves, starting from the first map.
struct IntroAtlas: View {
    struct Place: Identifiable {
        let id: String
        let name: String
        let col: Int
        let row: Int
        let isTown: Bool
        let hasBoss: Bool
        let ground: UIImage
    }

    /// The place to mark with a gold dot.
    let highlight: String?
    private let places: [Place]
    private let roads: [(from: String, to: String)]
    private let cols: ClosedRange<Int>
    private let rows: ClosedRange<Int>
    private static let rowHeight: CGFloat = 46

    init(highlight: String?, content: Content = .shared) {
        self.highlight = highlight
        var spots: [String: (col: Int, row: Int)] = [content.startMap: (0, 0)]
        var taken: Set<[Int]> = [[0, 0]]
        var queue = [content.startMap]
        var roads: [(from: String, to: String)] = []
        var seen: Set<String> = []
        while !queue.isEmpty {
            let id = queue.removeFirst()
            guard let map = content.map(id), let here = spots[id] else { continue }
            for exit in map.exits where content.map(exit.to) != nil {
                if seen.insert([id, exit.to].sorted().joined(separator: "|")).inserted {
                    roads.append((from: id, to: exit.to))
                }
                guard spots[exit.to] == nil else { continue }
                let step: (col: Int, row: Int) = switch exit.edge {
                case .north: (0, -1)
                case .south: (0, 1)
                case .east: (1, 0)
                case .west: (-1, 0)
                }
                var spot = (col: here.col + step.col, row: here.row + step.row)
                // Two roads can point at the same square: carry on in the same direction until one is free.
                while taken.contains([spot.col, spot.row]) {
                    spot = (spot.col + step.col, spot.row + step.row)
                }
                spots[exit.to] = spot
                taken.insert([spot.col, spot.row])
                queue.append(exit.to)
            }
        }
        places = content.maps.compactMap { map in
            guard let spot = spots[map.id] else { return nil }
            let ground = UIImage(cgImage: ArtLibrary.shared.tileTexture(map.theme.ground).cgImage())
            return Place(
                id: map.id, name: map.name, col: spot.col, row: spot.row,
                isTown: map.town != nil, hasBoss: map.npcs?.contains { $0.role == .boss } ?? false, ground: ground
            )
        }
        self.roads = roads
        let columns = places.map(\.col), lines = places.map(\.row)
        cols = (columns.min() ?? 0)...(columns.max() ?? 0)
        rows = (lines.min() ?? 0)...(lines.max() ?? 0)
    }

    var body: some View {
        GeometryReader { proxy in
            let byID = Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })
            let cell = CGSize(width: proxy.size.width / CGFloat(cols.count), height: proxy.size.height / CGFloat(rows.count))
            ZStack {
                Path { path in
                    for road in roads {
                        guard let a = byID[road.from], let b = byID[road.to] else { continue }
                        path.move(to: center(of: a, cell: cell))
                        path.addLine(to: center(of: b, cell: cell))
                    }
                }
                .stroke(HUDStyle.plate.opacity(0.75), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 5]))

                ForEach(places) { place in
                    PlaceBadge(place: place, isStart: place.id == highlight, width: cell.width)
                        .position(center(of: place, cell: cell))
                }
            }
        }
        .frame(height: CGFloat(rows.count) * Self.rowHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("World map of {count} places, starting in {map}", ["count": places.count, "map": places.first { $0.id == highlight }?.name ?? "Meadowbrook"]))
    }

    private func center(of place: Place, cell: CGSize) -> CGPoint {
        CGPoint(
            x: (CGFloat(place.col - cols.lowerBound) + 0.5) * cell.width,
            y: (CGFloat(place.row - rows.lowerBound) + 0.5) * cell.height
        )
    }
}

private struct PlaceBadge: View {
    let place: IntroAtlas.Place
    let isStart: Bool
    let width: CGFloat

    var body: some View {
        VStack(spacing: 2) {
            Image(uiImage: place.ground)
                .interpolation(.none)
                .resizable()
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: place.isTown ? 4 : 11))
                .overlay(
                    RoundedRectangle(cornerRadius: place.isTown ? 4 : 11)
                        .strokeBorder(place.isTown ? HUDStyle.gold : HUDStyle.cream.opacity(0.8), lineWidth: 2)
                )
                .overlay(alignment: .topTrailing) {
                    if place.hasBoss {
                        IconImage(.sword, size: 10)
                            .foregroundStyle(HUDStyle.hp)
                            .padding(2)
                            .background(Circle().fill(HUDStyle.ink))
                            .offset(x: 6, y: -6)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if isStart {
                        Circle().fill(HUDStyle.gold).frame(width: 10, height: 10)
                            .overlay(Circle().stroke(HUDStyle.ink, lineWidth: 1.5))
                            .offset(x: -5, y: -5)
                    }
                }
            Text(place.name)
                .font(HUDStyle.font(9))
                .foregroundStyle(isStart ? HUDStyle.gold : HUDStyle.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: max(40, width - 4))
        }
    }
}
