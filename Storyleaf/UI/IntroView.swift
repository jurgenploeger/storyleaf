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
            L("Long ago, the goddess Liora gathered the world's fairy tales into one land: Avalune. Villages grew up between the stories, and adventurers came from far and wide to explore them."),
            L("Every tale found a home: Thumbelina's lotus pond, Snow White's forest, the Emerald Road to Oz and the golden sands of the Thousand and One Nights. For a long time, they all lived happily ever after."),
        ]
        case .shadows: [
            L("Lately the tales have been going wrong. A Big Bad Wolf prowls the Snow White Forest. A Rat King has cut off the dwarves of Ingothold. A dragon drinks at the oasis in Genie Desert and scares away the caravans."),
            L("Nobody knows why. Some say pages are being torn from Liora's great storybook, and every lost page lets a little more darkness in."),
        ]
        case .arrival, .reel: [
            L("You arrive in Meadowbrook as a new adventurer, with the whole of Avalune ahead of you."),
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
        // Towns before Quests, as the reel shows them: the square as you walk in, then Elder Oak's
        // quest (playtesting 2026-10-24: the other way round, they lit in the wrong order).
        Tip(icon: .heart, title: L("Towns"), text: L("Shops, healers and checkpoints wait in town. Your progress saves by itself.")),
        Tip(icon: .star, title: L("Quests"), text: L("Villagers with a gold ! have work for you. Quests reward you and open the roads to new places.")),
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
                        reel.play(clip: StoryScene.Clip.showing(tip: index).rawValue, lighting: index)
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
            PageTitle(text: L("The world of Avalune"), icon: .map)
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

/// The continent as it really lies (playtesting 2026-10-24: the page showed a made-up grid of the
/// roads, not the world): each land's own map where it is (`WorldOverview`, as the world map in the
/// game draws it), its shape in a colour from its ground until that's drawn, the sea all round, turned
/// like the game's view so north points up-left. The towns are named, the bosses' lands carry a
/// sword, and where you start a gold dot. Pinch (or the buttons) to zoom and drag to look round, as
/// on the world map in the game (playtesting 2026-10-24); it opens on the whole continent.
struct IntroAtlas: View {
    /// The place to mark with a gold dot.
    let highlight: String?
    @State private var picture: CGImage?
    /// Points a cell (0 until the view's size is known), and where the turned map sits in the view.
    @State private var scale: CGFloat = 0
    @State private var pan: CGSize = .zero
    @State private var dragStart: CGSize?
    @State private var pinchStart: (scale: CGFloat, pan: CGSize)?
    private static let maxScale: CGFloat = 8
    private static let height: CGFloat = 440
    private let overview = WorldOverview.shared

    /// A land on the continent, its box's south-west cell there and its middle.
    private struct Land: Identifiable {
        let def: MapDef
        let origin: GridPoint
        let middle: GridPoint
        var id: String { def.id }
    }

    private let lands: [Land]
    /// The continent's cells, with a little sea round it: its south-west cell and how many it spans.
    private let low: GridPoint
    private let columns: Int
    private let rows: Int

    init(highlight: String?, content: Content = .shared) {
        self.highlight = highlight
        let lands = content.maps.compactMap { def -> Land? in
            guard let origin = content.world[def.id] else { return nil }
            let middle = content.regions[def.id]?.middle ?? GridPoint(col: def.width / 2, row: def.height / 2)
            return Land(def: def, origin: origin, middle: GridPoint(col: origin.col + middle.col, row: origin.row + middle.row))
        }
        self.lands = lands
        let sea = 10
        low = GridPoint(col: (lands.map(\.origin.col).min() ?? 0) - sea, row: (lands.map(\.origin.row).min() ?? 0) - sea)
        columns = (lands.map { $0.origin.col + $0.def.width }.max() ?? 0) + sea - low.col
        rows = (lands.map { $0.origin.row + $0.def.height }.max() ?? 0) + sea - low.row
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                // The picture rides in an overlay, so its size never moves the view's.
                Color.clear
                    .frame(width: size.width, height: size.height)
                    .overlay(alignment: .topLeading) {
                        if let picture, scale > 0 {
                            Image(decorative: picture, scale: 1)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: CGFloat(columns), height: CGFloat(rows))
                                .transformEffect(CGAffineTransform(a: scale, b: -scale / 2, c: scale, d: scale / 2,
                                                                   tx: pan.width, ty: scale * CGFloat(columns) / 2 + pan.height))
                        }
                    }
                if scale > 0 {
                    ForEach(lands) { land in
                        mark(for: land)
                            .position(point(of: land.middle))
                    }
                }
                controls(in: size)
                    .frame(width: size.width, height: size.height, alignment: .bottomTrailing)
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .contentShape(Rectangle())
            // Ahead of the page's own scrolling while a finger's on the map.
            .highPriorityGesture(dragging(in: size).simultaneously(with: pinching(in: size)))
            .onAppear { if scale == 0 { fit(in: size) } }
            .onChange(of: size) { fit(in: size) }
        }
        .frame(height: Self.height)
        .background(Color(red: Double(WorldMap.seaColor.r) / 255, green: Double(WorldMap.seaColor.g) / 255, blue: Double(WorldMap.seaColor.b) / 255))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(HUDStyle.bevel.opacity(0.6), lineWidth: 1.5))
        .onAppear { overview.prepare() }
        // Drawn again as each land's own map comes in.
        .task(id: overview.images.count) { picture = compose() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("World map of {count} places, starting in {map}", ["count": lands.count, "map": lands.first { $0.id == highlight }?.def.name ?? "Meadowbrook"]))
    }

    // MARK: Looking round (as `WorldAtlas`)

    /// The whole continent in view, in the middle.
    private func fit(in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        scale = smallestScale(in: size)
        let wide = scale * CGFloat(columns + rows), tall = wide / 2
        pan = CGSize(width: (size.width - wide) / 2, height: (size.height - tall) / 2)
    }

    /// As far out as it zooms: the whole continent in view.
    private func smallestScale(in size: CGSize) -> CGFloat {
        min(size.width / CGFloat(max(1, columns + rows)), size.height * 2 / CGFloat(max(1, columns + rows)))
    }

    private func clamped(_ value: CGFloat, in size: CGSize) -> CGFloat {
        min(Self.maxScale, max(smallestScale(in: size), value))
    }

    /// Keeps the continent in view: zoomed out, in the middle; zoomed in, the middle of the view
    /// over it.
    private func clampedPan(_ value: CGSize, in size: CGSize) -> CGSize {
        let wide = scale * CGFloat(columns + rows), tall = wide / 2
        func axis(_ value: CGFloat, view: CGFloat, map: CGFloat) -> CGFloat {
            map <= view ? (view - map) / 2 : min(0, max(view - map, value))
        }
        return CGSize(width: axis(value.width, view: size.width, map: wide), height: axis(value.height, view: size.height, map: tall))
    }

    private func dragging(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let start = dragStart ?? pan
                dragStart = start
                pan = clampedPan(CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height), in: size)
            }
            .onEnded { _ in dragStart = nil }
    }

    private func pinching(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStart ?? (scale: scale, pan: pan)
                pinchStart = start
                zoom(to: start.scale * value.magnification, around: value.startLocation, from: start, in: size)
            }
            .onEnded { _ in pinchStart = nil }
    }

    /// Zooms to `target`, keeping the spot at `anchor` where it is.
    private func zoom(to target: CGFloat, around anchor: CGPoint, from start: (scale: CGFloat, pan: CGSize), in size: CGSize) {
        let next = clamped(target, in: size)
        let ratio = next / start.scale
        scale = next
        pan = clampedPan(CGSize(width: anchor.x - (anchor.x - start.pan.width) * ratio,
                                height: anchor.y - (anchor.y - start.pan.height) * ratio), in: size)
    }

    private func controls(in size: CGSize) -> some View {
        VStack(spacing: 6) {
            mapButton(Text("+").font(HUDStyle.font(16)), label: L("Zoom in")) {
                zoom(to: scale * 1.6, around: CGPoint(x: size.width / 2, y: size.height / 2), from: (scale: scale, pan: pan), in: size)
            }
            mapButton(Text("−").font(HUDStyle.font(16)), label: L("Zoom out")) {
                zoom(to: scale / 1.6, around: CGPoint(x: size.width / 2, y: size.height / 2), from: (scale: scale, pan: pan), in: size)
            }
        }
        .padding(6)
    }

    private func mapButton(_ face: some View, label: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.25)) { action() }
        } label: {
            face
                .foregroundStyle(HUDStyle.ink)
                .frame(width: 30, height: 30)
                .background(Circle().fill(HUDStyle.plate))
                .overlay(Circle().strokeBorder(HUDStyle.ink.opacity(0.6), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Where a cell of the continent shows in the view: its place in the picture (columns east,
    /// rows north to south), turned and squashed like the world (`WorldAtlas`).
    private func point(of cell: GridPoint) -> CGPoint {
        let u = CGFloat(cell.col - low.col) + 0.5, v = CGFloat(rows - (cell.row - low.row)) - 0.5
        return CGPoint(x: scale * (u + v) + pan.width, y: scale * (v - u) / 2 + scale * CGFloat(columns) / 2 + pan.height)
    }

    /// A town's name under a gold square, a boss's sword, where you start a gold dot and its name.
    @ViewBuilder
    private func mark(for land: Land) -> some View {
        let start = land.id == highlight
        let boss = land.def.npcs?.contains { $0.role == .boss } ?? false
        if start || land.def.town != nil {
            VStack(spacing: 1) {
                if start {
                    Circle().fill(HUDStyle.gold).frame(width: 9, height: 9)
                        .overlay(Circle().stroke(HUDStyle.ink, lineWidth: 1.5))
                } else {
                    RoundedRectangle(cornerRadius: 2).fill(HUDStyle.ink.opacity(0.5)).frame(width: 8, height: 8)
                        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(HUDStyle.gold, lineWidth: 1.5))
                }
                Text(land.def.name)
                    .font(HUDStyle.font(8))
                    .foregroundStyle(start ? HUDStyle.gold : HUDStyle.cream)
                    .lineLimit(1)
                    .fixedSize()
                    .shadow(color: HUDStyle.ink, radius: 0, x: 1, y: 1)
            }
        } else if boss {
            IconImage(.sword, size: 9)
                .foregroundStyle(HUDStyle.hp)
                .padding(2)
                .background(Circle().fill(HUDStyle.ink.opacity(0.85)))
        }
    }

    /// The continent in one picture, a pixel a cell, north up: the sea, and each land's own map (its
    /// shape in a colour from its ground, until that's drawn), as `WorldAtlas` draws it.
    private func compose() -> CGImage? {
        guard columns > 0, rows > 0,
              let context = CGContext(data: nil, width: columns, height: rows, bitsPerComponent: 8, bytesPerRow: columns * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .none
        let sea = WorldMap.seaColor
        context.setFillColor(red: CGFloat(sea.r) / 255, green: CGFloat(sea.g) / 255, blue: CGFloat(sea.b) / 255, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: columns, height: rows))
        for land in lands {
            let def = land.def
            let rect = CGRect(x: land.origin.col - low.col, y: land.origin.row - low.row, width: def.width, height: def.height)
            if let image = overview.images[def.id] {
                context.draw(image, in: rect)
            } else {
                let tint = WorldAtlas.tint(of: def)
                if let shape = WorldScene.silhouette(of: def, color: PixelColor(r: UInt8(tint.r * 255), g: UInt8(tint.g * 255), b: UInt8(tint.b * 255))) {
                    context.draw(shape, in: rect)
                }
            }
        }
        return context.makeImage()
    }
}
