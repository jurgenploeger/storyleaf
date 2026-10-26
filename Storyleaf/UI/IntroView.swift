import SwiftUI

/// The onboarding before a new hero is made, a slide at a time like a carousel: the story in three
/// chapters, each with a little animated scene made of the game itself (StoryVignette), then how to
/// play, a slide for each step with its part of the game played (a walk, a fight, a Seal Stone, a
/// level up, the town and a quest), and the whole world map. Each slide's picture fills the top of
/// the window (its left side, on a phone held sideways) and melts into it (`progressiveFade`), its
/// title and words below; Back, Next and a dot for each slide along the foot, and a swipe turns too.
/// Also opens from the title screen, at How to play.
struct IntroView: View {
    /// What the last slide's button says ("Create your hero", or "Done" when just reading).
    let finishTitle: String
    /// Skip, over the picture: when finishing makes a hero. When just reading, the close button does it.
    let skips: Bool
    /// The close button: back to the title screen, without making a hero.
    let onClose: () -> Void
    let onFinish: () -> Void
    @State private var page: Int
    /// Which way the last turn went, for the words to slide in from that side.
    @State private var forward = true
    /// How to play's picture, the same scene on all its slides, each playing its own part of it.
    @State private var reel: StoryScene
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// How to play's first slide, after the story's three.
    static let howToPlayPage = 3

    private enum Slide: Equatable {
        case chapter(StoryScene.Kind)
        /// A step of How to play, by its place among them (`HowToPlayStep.all`).
        case step(Int)
        case world
    }

    private static let slides: [Slide] = [.chapter(.gathering), .chapter(.shadows), .chapter(.arrival)]
        + (0..<HowToPlayStep.count).map(Slide.step) + [.world]

    init(finishTitle: String, skips: Bool = true, startPage: Int = 0, onClose: @escaping () -> Void, onFinish: @escaping () -> Void) {
        self.finishTitle = finishTitle
        self.skips = skips
        self.onClose = onClose
        self.onFinish = onFinish
        let page = min(max(0, startPage), Self.slides.count - 1)
        _page = State(initialValue: page)
        var clip = StoryScene.Clip.walk
        if case .step(let step) = Self.slides[page] { clip = StoryScene.Clip.showing(step: step) }
        _reel = State(initialValue: StoryScene(kind: .reel, startClip: DebugLaunch.introClip ?? clip.rawValue))
    }

    private var slide: Slide { Self.slides[page] }
    private var isLastPage: Bool { page == Self.slides.count - 1 }
    /// A phone on its side: the picture on the left, the words on the right.
    private var wide: Bool { verticalSizeClass == .compact }

    var body: some View {
        GeometryReader { proxy in
            let size = CGSize(width: min(proxy.size.width, 720), height: min(proxy.size.height, wide ? proxy.size.height : 680))
            Group {
                if wide {
                    HStack(spacing: 0) {
                        visual(fade: .trailing)
                            .frame(width: min(size.width * 0.6, size.height * 1.7))
                        words
                    }
                } else {
                    // Wider than tall, so little of the picture's sides is cropped (VignetteView).
                    VStack(spacing: 0) {
                        visual(fade: .bottom)
                            .frame(height: min((size.width - 6) / 1.6, size.height * 0.5))
                        words
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .background(HUDStyle.panel)
            .windowCloseButton(onClose)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
        .onChange(of: page) { old, new in
            // How to play's picture plays the part for the step you turned to; from Towns to Quests,
            // both the town, it carries on.
            guard case .step(let step) = Self.slides[new] else { return }
            let clip = StoryScene.Clip.showing(step: step).rawValue
            if case .step = Self.slides[old], reel.hud.clip == clip { return }
            reel.play(clip: clip)
        }
    }

    // MARK: The picture

    /// The slide's picture inside the window's frame, its outer corners rounded as the window's, with
    /// Skip over its corner.
    private func visual(fade: SwiftUI.Edge) -> some View {
        let corner = HUDStyle.windowRadius - 3
        return ZStack {
            picture(fade: fade)
                // How to play's slides share one picture, so turning between them doesn't fade it.
                .id(pictureID)
                .transition(.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: corner, bottomLeadingRadius: wide ? corner : 0,
                                          bottomTrailingRadius: 0, topTrailingRadius: wide ? 0 : corner))
        .overlay(alignment: .topLeading) {
            if skips && !isLastPage {
                Button(L("Skip"), action: onFinish)
                    .buttonStyle(PixelButtonStyle(compact: true))
                    .padding(10)
            }
        }
        .contentShape(Rectangle())
        // The world map drags round itself instead.
        .gesture(swipe, including: slide == .world ? .subviews : .all)
        // Inside the window's bevel.
        .padding(EdgeInsets(top: 3, leading: 3, bottom: wide ? 3 : 0, trailing: wide ? 0 : 3))
    }

    @ViewBuilder
    private func picture(fade: SwiftUI.Edge) -> some View {
        switch slide {
        case .chapter(let kind): StoryVignette(kind, fade: fade)
        case .step: VignetteView(scene: reel, fade: fade)
        case .world: IntroAtlas(highlight: Content.shared.startMap, fade: fade)
        }
    }

    private var pictureID: String {
        switch slide {
        case .chapter(let kind): "\(kind)"
        case .step: "reel"
        case .world: "world"
        }
    }

    // MARK: The words

    /// The slide's title and words, then the way on.
    private var words: some View {
        VStack(spacing: 0) {
            ScrollView {
                // Stacked, so the old slide's words and the new one's cross over each other.
                ZStack(alignment: .topLeading) {
                    text
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(page)
                        .transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                                removal: .opacity))
                }
                .padding(.horizontal, 18)
                .padding(.top, wide ? 18 : 2)
                .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            .clipped()
            .simultaneousGesture(swipe)
            controls
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 14)
        }
    }

    @ViewBuilder
    private var text: some View {
        switch slide {
        case .chapter(let kind): ChapterText(chapter: kind)
        case .step(let index): StepText(step: HowToPlayStep.all[index])
        case .world: WorldText()
        }
    }

    // MARK: Turning

    /// The dots, which slide you're on, over Back and Next (Next makes way for the last slide's
    /// button, which can be long: "Create your hero").
    private var controls: some View {
        VStack(spacing: 12) {
            PageDots(count: Self.slides.count, current: page)
            HStack(spacing: 10) {
                Button {
                    turn(by: -1)
                } label: {
                    Label(L("Back"), icon: .arrowLeft)
                }
                .buttonStyle(PixelButtonStyle(compact: true))
                .opacity(page == 0 ? 0.4 : 1)
                .disabled(page == 0)
                Spacer(minLength: 0)
                Button {
                    if isLastPage {
                        onFinish()
                    } else {
                        turn(by: 1)
                    }
                } label: {
                    Label(isLastPage ? finishTitle : L("Next"), icon: .arrowRight)
                }
                .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
            }
            .lineLimit(1)
        }
    }

    /// A swipe across, like a carousel: to the left for the next slide, to the right for the one before.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                let across = value.translation.width
                guard abs(across) > 50, abs(across) > abs(value.translation.height) * 1.5 else { return }
                turn(by: across < 0 ? 1 : -1)
            }
    }

    private func turn(by step: Int) {
        let next = page + step
        guard Self.slides.indices.contains(next) else { return }
        forward = step > 0
        withAnimation(.easeInOut(duration: 0.25)) { page = next }
    }
}

/// A dot for each slide, the one you're on drawn long and gold.
private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? HUDStyle.gold : HUDStyle.cream.opacity(0.35))
                    .frame(width: index == current ? 18 : 7, height: 7)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: current)
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
            // Clear of the close button in the corner, on a phone held sideways.
            .padding(.trailing, 24)
    }
}

/// A picture melting into the window along one edge (the onboarding's slides): blurred more and
/// more toward it, as through frosted glass, then fading out so the window's glass shows through.
struct ProgressiveFade: ViewModifier {
    let edge: SwiftUI.Edge
    /// How far in from the edge the blur reaches, and the fade, as fractions of the picture across it.
    static let blurReach: CGFloat = 0.42
    static let fadeReach: CGFloat = 0.24
    /// Frosted layers, each starting a little nearer the edge, so the blur deepens toward it.
    private static let layers = 4

    func body(content: Content) -> some View {
        content
            .overlay {
                ZStack {
                    ForEach(0..<Self.layers, id: \.self) { layer in
                        let step = Self.blurReach / CGFloat(Self.layers)
                        let start = 1 - Self.blurReach + CGFloat(layer) * step
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .mask(ramp(from: .clear, at: start, to: .black, at: min(1, start + step)))
                    }
                }
                // Frosted toward the glass's own deep blue, not a milky white.
                .environment(\.colorScheme, .dark)
                .allowsHitTesting(false)
            }
            .mask(ramp(from: .black, at: 1 - Self.fadeReach, to: .clear, at: 1))
    }

    /// `inner` up to `start` and `outer` from `end` on, counted from the far side of the picture
    /// (0) to `edge` (1).
    private func ramp(from inner: Color, at start: CGFloat, to outer: Color, at end: CGFloat) -> LinearGradient {
        LinearGradient(stops: [.init(color: inner, location: start), .init(color: outer, location: end)],
                       startPoint: point(on: edge.opposite), endPoint: point(on: edge))
    }

    private func point(on edge: SwiftUI.Edge) -> UnitPoint {
        switch edge {
        case .top: .top
        case .bottom: .bottom
        case .leading: .leading
        case .trailing: .trailing
        }
    }
}

private extension SwiftUI.Edge {
    var opposite: SwiftUI.Edge {
        switch self {
        case .top: .bottom
        case .bottom: .top
        case .leading: .trailing
        case .trailing: .leading
        }
    }
}

extension View {
    /// Melts into the window along `edge` (`ProgressiveFade`).
    func progressiveFade(_ edge: SwiftUI.Edge) -> some View {
        modifier(ProgressiveFade(edge: edge))
    }
}

// MARK: - Story

/// A chapter of the story: its title and its lines told one after another.
private struct ChapterText: View {
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
            L("Long ago, the goddess Liora gathered the world's fairy tales into one land: Dorlune. Villages grew up between the stories, and adventurers came from far and wide to explore them."),
            L("Every tale found a home: Thumbelina's lotus pond, Snow White's forest, the Emerald Road to Oz and the golden sands of the Thousand and One Nights. For a long time, they all lived happily ever after."),
        ]
        case .shadows: [
            L("Lately the tales have been going wrong. A Big Bad Wolf prowls the Snow White Forest. A Rat King has cut off the dwarves of Ingothold. A dragon drinks at the oasis in Genie Desert and scares away the caravans."),
            L("Nobody knows why. Some say pages are being torn from Liora's great storybook, and every lost page lets a little more darkness in."),
        ]
        case .arrival, .reel: [
            L("You arrive in Meadowbrook as a new adventurer, with the whole of Dorlune ahead of you."),
            L("Elder Oak is waiting in the village square with three gifts. Find a companion, learn from the guild masters, and set the stories right, one tale at a time."),
        ]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PageTitle(text: title.text, icon: title.icon)
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

/// A step of How to play, a slide of its own; the reel plays its part (`StoryScene.Clip.steps`).
private struct HowToPlayStep {
    let icon: GameIcon
    let title: String
    let text: String

    /// As many as `all` holds, without making their words.
    static let count = 6

    static var all: [HowToPlayStep] {
        [
            HowToPlayStep(icon: .tap, title: L("Walk"), text: L("Drag the stick in the corner, or tap the ground and your hero walks there.")),
            HowToPlayStep(icon: .sword, title: L("Battle"), text: L("Monsters jump out as you explore the wild. Battles take turns: attack, cast a skill or use an item.")),
            HowToPlayStep(icon: .paw, title: L("Companions"), text: L("Throw a Seal Stone at a monster to befriend it: the weaker it is, the likelier it works. Keep up to five.")),
            HowToPlayStep(icon: .star, title: L("Grow"), text: L("Every level gives a skill point. At level {level}, visit a guild master in town to become a Fighter, Mage or Beast Tamer.", ["level": Content.shared.classChoiceLevel])),
            // Towns before Quests, as the town part shows them: the square as you walk in, then Elder
            // Oak's quest.
            HowToPlayStep(icon: .heart, title: L("Towns"), text: L("Shops, healers and checkpoints wait in town. Your progress saves by itself.")),
            HowToPlayStep(icon: .star, title: L("Quests"), text: L("Villagers with a gold ! have work for you. Quests reward you and open the roads to new places.")),
        ]
    }
}

private struct StepText: View {
    let step: HowToPlayStep

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("How to play"))
                .font(HUDStyle.font(11))
                .foregroundStyle(HUDStyle.dim)
            PageTitle(text: step.title, icon: step.icon)
            Text(step.text)
                .font(HUDStyle.font(12))
                .foregroundStyle(HUDStyle.cream)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - World map

private struct WorldText: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PageTitle(text: L("The world of Dorlune"), icon: .map)
            Text(L("Roads join every place to its neighbours. Your journey starts in Meadowbrook. Quests open the roads further out, where stronger monsters live."))
                .font(HUDStyle.font(12))
                .foregroundStyle(HUDStyle.cream)
                .fixedSize(horizontal: false, vertical: true)
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
/// on the world map in the game (playtesting 2026-10-24); it opens on the whole continent, clear of
/// where it melts into the window (`fade`).
struct IntroAtlas: View {
    /// The place to mark with a gold dot.
    let highlight: String?
    /// The edge it melts into the window along (`progressiveFade`).
    let fade: SwiftUI.Edge
    @State private var picture: CGImage?
    /// Points a cell (0 until the view's size is known), and where the turned map sits in the view.
    @State private var scale: CGFloat = 0
    @State private var pan: CGSize = .zero
    @State private var dragStart: CGSize?
    @State private var pinchStart: (scale: CGFloat, pan: CGSize)?
    private static let maxScale: CGFloat = 8
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

    init(highlight: String?, fade: SwiftUI.Edge, content: Content = .shared) {
        self.highlight = highlight
        self.fade = fade
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
                // In the corner the window's close button and the fade leave free.
                controls(in: size)
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .contentShape(Rectangle())
            // Ahead of the page's own scrolling while a finger's on the map.
            .highPriorityGesture(dragging(in: size).simultaneously(with: pinching(in: size)))
            .onAppear { if scale == 0 { fit(in: size) } }
            .onChange(of: size) { fit(in: size) }
        }
        .background(Color(red: Double(WorldMap.seaColor.r) / 255, green: Double(WorldMap.seaColor.g) / 255, blue: Double(WorldMap.seaColor.b) / 255))
        .progressiveFade(fade)
        .onAppear { overview.prepare() }
        // Drawn again as each land's own map comes in.
        .task(id: overview.images.count) { picture = compose() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("World map of {count} places, starting in {map}", ["count": lands.count, "map": lands.first { $0.id == highlight }?.def.name ?? "Meadowbrook"]))
    }

    // MARK: Looking round (as `WorldAtlas`)

    /// The view but for where it fades into the window: where the continent is kept.
    private func clearArea(in size: CGSize) -> CGRect {
        let faded = EdgeInsets(fade, ProgressiveFade.fadeReach * (fade == .top || fade == .bottom ? size.height : size.width))
        return CGRect(x: faded.leading, y: faded.top, width: size.width - faded.leading - faded.trailing,
                      height: size.height - faded.top - faded.bottom)
    }

    /// The whole continent in view, in the middle.
    private func fit(in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        scale = smallestScale(in: size)
        let area = clearArea(in: size)
        let wide = scale * CGFloat(columns + rows), tall = wide / 2
        pan = CGSize(width: area.minX + (area.width - wide) / 2, height: area.minY + (area.height - tall) / 2)
    }

    /// As far out as it zooms: the whole continent in view.
    private func smallestScale(in size: CGSize) -> CGFloat {
        let area = clearArea(in: size)
        return min(area.width / CGFloat(max(1, columns + rows)), area.height * 2 / CGFloat(max(1, columns + rows)))
    }

    private func clamped(_ value: CGFloat, in size: CGSize) -> CGFloat {
        min(Self.maxScale, max(smallestScale(in: size), value))
    }

    /// Keeps the continent in view: zoomed out, in the middle; zoomed in, the middle of the view
    /// over it.
    private func clampedPan(_ value: CGSize, in size: CGSize) -> CGSize {
        let area = clearArea(in: size)
        let wide = scale * CGFloat(columns + rows), tall = wide / 2
        func axis(_ value: CGFloat, from start: CGFloat, view: CGFloat, map: CGFloat) -> CGFloat {
            map <= view ? start + (view - map) / 2 : min(start, max(start + view - map, value))
        }
        return CGSize(width: axis(value.width, from: area.minX, view: area.width, map: wide),
                      height: axis(value.height, from: area.minY, view: area.height, map: tall))
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
                zoom(to: scale * 1.6, around: CGPoint(x: clearArea(in: size).midX, y: clearArea(in: size).midY), from: (scale: scale, pan: pan), in: size)
            }
            mapButton(Text("−").font(HUDStyle.font(16)), label: L("Zoom out")) {
                zoom(to: scale / 1.6, around: CGPoint(x: clearArea(in: size).midX, y: clearArea(in: size).midY), from: (scale: scale, pan: pan), in: size)
            }
        }
        .padding(10)
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
