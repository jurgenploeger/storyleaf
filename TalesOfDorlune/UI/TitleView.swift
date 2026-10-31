import SpriteKit
import SwiftUI
import UniformTypeIdentifiers

/// Title screen: continue a saved game, or create a hero (name + race, like Fairyland Online).
struct TitleView: View {
    /// Where its logo stands, published for RootView's logo to move from when a game starts.
    var logoSpot: LogoSpot? = nil
    /// Its own logo hidden while RootView's is on its way to the loading screen.
    var logoHidden = false
    let onStart: (GameSession) -> Void

    @State private var creating = DebugLaunch.titlePage == "create"
    @State private var name = L("Hero")
    @State private var look = DebugLaunch.createLook(Look(hair: Look.standard.hair, outfit: Look.standard.outfit, skin: Look.standard.skin, gender: "male"))
    @State private var raceID = DebugLaunch.createRace ?? "human"
    /// Your games, the last played first; the carousel shows one at a time.
    @State private var saves = SaveStore.all()
    @State private var selectedSlot: String?
    @State private var showingChangelog = DebugLaunch.titlePage == "news"
    /// What's new's page (0 is the newest): turning it scrolls back up to the window's top.
    @State private var changelogPage = 0
    @State private var showingSettings = DebugLaunch.titlePage == "settings"
    /// The Settings window's tab (`SettingsPage`).
    @State private var settingsPage: SettingsPage = DebugLaunch.subTab.flatMap(SettingsPage.init(rawValue:)) ?? .general
    @State private var showingLanguages = DebugLaunch.titlePage == "languages"
    /// Its language: switching rebuilds the screen's text in place.
    @State private var localizer = Localizer.shared
    /// Import a backup: the file picker, and what came of it.
    @State private var importing = false
    @State private var importNote: String?
    /// The story pages: before a new hero is made, or read from the title menu.
    @State private var intro: IntroRequest? = DebugLaunch.introPage.map { IntroRequest(startPage: $0, thenCreate: false) }
    /// The newest release notes you've opened (What's new).
    @AppStorage(GameSettings.seenReleaseKey) private var seenRelease = ""
    /// The game the carousel is showing.
    private var selectedSave: SaveData? {
        saves.first { $0.slot == selectedSlot } ?? saves.first
    }

    private var newestRelease: String { Content.shared.releases.first?.version ?? Self.appVersion }

    /// What's new wears a gold dot until you've read the newest notes. A first game starts out
    /// with them read: there's nothing older to compare them with.
    private var hasUnreadNotes: Bool { !saves.isEmpty && seenRelease != newestRelease }

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    /// A phone on its side, too short for the logo above everything: the logo on the left, the
    /// rest on the right.
    private var wide: Bool { verticalSizeClass == .compact }
    /// The title's own menu, not hero creation or the languages (What's new and Settings cover the
    /// whole screen).
    private var onMenu: Bool { !creating && !showingLanguages }

    /// How What's new and Settings open and close: fading in over the sky as the story pages do.
    private static let windowFade = Animation.easeInOut(duration: 0.25)

    var body: some View {
        ZStack {
            if let intro {
                IntroView(finishTitle: intro.thenCreate ? L("Create your hero") : L("Done"), skips: intro.thenCreate,
                          howToPlayOnly: intro.howToPlayOnly, startPage: intro.startPage,
                          onClose: { withAnimation(.easeInOut(duration: 0.25)) { self.intro = nil } }) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        self.intro = nil
                        if intro.thenCreate { creating = true }
                    }
                }
                .transition(.opacity)
            } else if showingChangelog {
                // What's new and Settings open as the story pages do (playtesting 2026-10-26: "almost
                // full screen and no logo on the top"): one window over the sky, the logo and the
                // round buttons out of the way.
                ChangelogPanel(page: $changelogPage) {
                    withAnimation(Self.windowFade) { showingChangelog = false }
                }
                .padding(16)
                .transition(.opacity)
            } else if showingSettings {
                settingsWindow
                    .padding(16)
                    .transition(.opacity)
            } else if wide {
                // The logo on the left, with the round buttons under it on the menu (half the width
                // there, a narrower strip beside anything else), and the rest on the right: in the
                // middle of the screen when it fits, scrolling on its own when it doesn't.
                HStack(spacing: 28) {
                    VStack(spacing: 14) {
                        logo
                        if onMenu { roundButtons }
                    }
                    .frame(maxWidth: onMenu ? .infinity : 220)
                    GeometryReader { proxy in
                        ScrollView {
                            page
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: proxy.size.height)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .id(localizer.language)
                languageButton
            } else {
                // Upright, the round buttons sit at the bottom of the screen, under everything
                // else (scrolling with it when the screen is too short for all of it).
                GeometryReader { proxy in
                    ScrollView {
                        VStack(spacing: 18) {
                            logo.padding(.top, 12)
                            page
                            if onMenu {
                                Spacer(minLength: 10)
                                roundButtons
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: proxy.size.height)
                        .id(localizer.language)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                languageButton
            }
        }
        // The sky, its soft light behind the logo wherever the logo is (the story pages have
        // none: there, near the top).
        .talesOfDorluneSky(fallback: UnitPoint(x: 0.5, y: 0.18))
        .onAppear {
            MusicPlayer.shared.play("title")
            if saves.isEmpty { seenRelease = newestRelease }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            importBackup(result)
        }
        .alert(importNote ?? "", isPresented: Binding(get: { importNote != nil }, set: { if !$0 { importNote = nil } })) {
            Button(L("OK"), role: .cancel) {}
        }
    }

    /// A backup from Files becomes a game of its own on the carousel (never over another one).
    private func importBackup(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let raw = try? Data(contentsOf: url), let game = try? SaveStore.imported(raw) else {
            importNote = L("That file isn't a Tales of Dorlune backup.")
            return
        }
        SaveStore.save(game)
        saves = SaveStore.all()
        // A copy of a game you still have doesn't show up twice (SaveStore.all keeps the first).
        if saves.contains(where: { $0.slot == game.slot }) {
            selectedSlot = game.slot
            importNote = L("{hero}, level {level}, is back!", ["hero": game.hero.name, "level": game.hero.level])
        } else {
            importNote = L("You already have this game.")
        }
    }

    /// What shows with the logo: the menu, or what one of its buttons opened.
    @ViewBuilder
    private var page: some View {
        if creating {
            creation
        } else if showingLanguages {
            LanguagePanel { showingLanguages = false }
        } else {
            // Your game, and how to start. The round buttons wait at the bottom of the screen
            // (on a phone on its side, under the logo).
            VStack(spacing: 12) {
                games
                startButtons
            }
        }
    }

    /// Settings, its pages as tabs along the top as in the game's Settings window, the close button
    /// over the corner; as big as What's new.
    private var settingsWindow: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageTabs(page: $settingsPage, title: { $0.title })
            // Closed by its close button alone, as the story pages and What's new are.
            ScrollView {
                SettingsView(onImportBackup: {
                    showingSettings = false
                    importing = true
                }, page: settingsPage)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: 720, maxHeight: .infinity)
        .gameWindow()
        .windowCloseButton(closeSettings)
        // A language switch (General) rebuilds its text in place.
        .id(localizer.language)
    }

    private func closeSettings() {
        withAnimation(Self.windowFade) { showingSettings = false }
    }

    /// The language button, top right of the menu: the first thing a player who can't read English
    /// needs. Once there's a game, the language is chosen (and still in Settings).
    @ViewBuilder
    private var languageButton: some View {
        if onMenu, saves.isEmpty {
            Button {
                showingLanguages = true
            } label: {
                Label(localizer.current.name, icon: .globe)
            }
            .buttonStyle(PixelButtonStyle(compact: true))
            .accessibilityLabel(L("Language: {language}", ["language": localizer.current.name]))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.top, 8)
            .padding(.trailing, 12)
        }
    }

    /// As big as on the loading screen, so starting a game only moves it there.
    private var logo: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .logoSpot(logoSpot)
            .opacity(logoHidden ? 0 : 1)
            .raysAnchor(Brand.raysInLogo)
            .frame(maxWidth: LoadingCurtain.logoWidth, maxHeight: wide ? 190 : 260)
            .accessibilityLabel(L("Tales of Dorlune"))
    }

    /// Your games, one at a time, or before the first one, a hero waiting to be made.
    @ViewBuilder
    private var games: some View {
        if saves.isEmpty {
            SpriteImage(art: "player_walk", size: 134)
        } else {
            SaveCarousel(saves: saves, selection: $selectedSlot)
        }
    }

    /// Continue the game on show, or start another: the screen's main choices, so big, and as wide
    /// as each other (playtesting 2026-10-26: "they are primary").
    private var startButtons: some View {
        VStack(spacing: 14) {
            if let save = selectedSave {
                Button {
                    onStart(GameSession(data: save))
                } label: {
                    // No icon: the words alone, centred (playtesting 2026-10-30).
                    Text(L("Continue: {hero}, Lv {level}", ["hero": save.hero.name, "level": save.hero.level]))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, primary: true))
            }
            Button {
                // A new game gets its own save, next to the others.
                startNewGame()
            } label: {
                Text(L("New game"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
            }
            // Before your first game, it's the one thing to do.
            .buttonStyle(PixelButtonStyle(tint: saves.isEmpty ? HUDStyle.gold : HUDStyle.cream, primary: true))
        }
        .frame(maxWidth: 320)
    }

    /// The rest waits in small round buttons, only what fits the moment. A backup is for bringing
    /// a game over before you have one (later it's in Settings); How to play and What's new are
    /// for a player who already has a game.
    private var roundButtons: some View {
        HStack(alignment: .top, spacing: 4) {
            Button(L("Settings")) {
                withAnimation(Self.windowFade) { showingSettings = true }
            }
                .buttonStyle(TitleRoundButtonStyle(icon: .settings))
            if saves.isEmpty {
                Button(L("Import a backup")) { importing = true }
                    .buttonStyle(TitleRoundButtonStyle(icon: .arrowDown))
            } else {
                Button(L("How to play")) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        intro = IntroRequest(startPage: 0, thenCreate: false, howToPlayOnly: true)
                    }
                }
                .buttonStyle(TitleRoundButtonStyle(icon: .book))
                Button(L("What's new")) {
                    seenRelease = newestRelease
                    changelogPage = 0
                    withAnimation(Self.windowFade) { showingChangelog = true }
                }
                .buttonStyle(TitleRoundButtonStyle(icon: .star, marked: hasUnreadNotes))
                .accessibilityValue(hasUnreadNotes ? L("Unread") : "")
            }
        }
    }

    /// A new game opens with the story pages, then hero creation.
    private func startNewGame() {
        withAnimation(.easeInOut(duration: 0.25)) { intro = IntroRequest(startPage: 0, thenCreate: true) }
    }

    private var creation: some View {
        VStack(alignment: .leading, spacing: 0) {
            WindowTitle(L("Create your hero"), onClose: { creating = false })
            VStack(alignment: .leading, spacing: 12) {
                LookEditor(name: $name, look: $look, raceID: raceID)

                Text(L("Race")).font(HUDStyle.font(12)).foregroundStyle(HUDStyle.dim)
                AdaptiveStack(spacing: 10) {
                    ForEach(Content.shared.races) { race in
                        RaceCard(race: race, selected: race.id == raceID)
                            .onTapGesture { raceID = race.id }
                    }
                }

                HStack {
                    Button(L("Back")) { creating = false }
                        .buttonStyle(PixelButtonStyle(compact: true))
                    Spacer()
                    Button {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        let session = GameSession.newGame(name: trimmed.isEmpty ? L("Hero") : String(trimmed.prefix(12)), raceID: raceID, look: look)
                        session.save()
                        onStart(session)
                    } label: {
                        Label(L("Begin adventure"), icon: .arrowRight)
                    }
                    .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold))
                }
            }
            .padding(16)
        }
        .foregroundStyle(HUDStyle.cream)
        .frame(maxWidth: 640)
        .gameWindow()
    }
}

extension TitleView {
    /// The version from project.yml (MARKETING_VERSION), falling back to the newest changelog entry.
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? Content.shared.releases.first?.version ?? "?"
    }
}

/// Release notes from content/changelog.json, newest first, five releases a page, in a window
/// nearly as big as the screen. Only the newest is open; tap any other to read it.
private struct ChangelogPanel: View {
    /// The page showing, 0 being the newest (turning it scrolls back up to the top).
    @Binding var page: Int
    let onClose: () -> Void
    @State private var open: Set<String> = Set(Content.shared.releases.prefix(1).map(\.id))

    private static let perPage = 5
    private var releases: [ReleaseNote] { Content.shared.releases }
    private var pageCount: Int { max(1, (releases.count + Self.perPage - 1) / Self.perPage) }

    /// This page's releases.
    private var shown: [ReleaseNote] {
        let start = min(max(0, page), pageCount - 1) * Self.perPage
        return Array(releases.dropFirst(start).prefix(Self.perPage))
    }

    /// The scroll anchor at the notes' top.
    private static let top = "top"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WindowTitle(L("What's new"), onClose: onClose)
            ScrollViewReader { reader in
                ScrollView {
                    notes
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(Self.top)
                }
                .scrollBounceBehavior(.basedOnSize)
                // A new page starts at its top, not where the last one was read to.
                .onChange(of: page) {
                    withAnimation(.easeInOut(duration: 0.25)) { reader.scrollTo(Self.top, anchor: .top) }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            // The pager stays at the window's foot, however short or long the page's notes.
            if pageCount > 1 {
                pager
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
        .foregroundStyle(HUDStyle.cream)
        .frame(maxWidth: 720, maxHeight: .infinity)
        .gameWindow()
    }

    /// This page's releases.
    private var notes: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(shown) { release in
                let isOpen = open.contains(release.id)
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            if isOpen { open.remove(release.id) } else { open.insert(release.id) }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("v\(release.version)").font(HUDStyle.font(16)).foregroundStyle(HUDStyle.gold)
                                Spacer()
                                Text(release.date).font(HUDStyle.font(10)).foregroundStyle(HUDStyle.dim)
                                IconImage(isOpen ? .chevronUp : .chevronDown, size: 12)
                                    .foregroundStyle(HUDStyle.dim)
                            }
                            Text(release.title).font(HUDStyle.font(13))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(isOpen ? L("Hides the notes") : L("Shows the notes"))
                    if isOpen {
                        ForEach(release.notes, id: \.self) { note in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("•").foregroundStyle(HUDStyle.gold)
                                Text(note).fixedSize(horizontal: false, vertical: true)
                            }
                            .font(HUDStyle.font(11))
                        }
                    }
                }
            }
        }
    }

    /// Newer and Older at the window's foot, and which page this is.
    private var pager: some View {
        HStack(spacing: 10) {
            Button {
                turn(to: page - 1)
            } label: {
                Label(L("Newer"), icon: .arrowLeft)
            }
            .buttonStyle(PixelButtonStyle(compact: true))
            .opacity(page <= 0 ? 0.4 : 1)
            .disabled(page <= 0)
            Spacer(minLength: 0)
            // "2 / 17", like the tour's steps: short enough beside the buttons in every language.
            Text(verbatim: "\(page + 1) / \(pageCount)")
                .font(HUDStyle.font(11))
                .foregroundStyle(HUDStyle.dim)
                .accessibilityLabel(L("Page {page} of {count}", ["page": page + 1, "count": pageCount]))
            Spacer(minLength: 0)
            Button {
                turn(to: page + 1)
            } label: {
                // The arrow after the word, pointing the way it goes.
                HStack(spacing: 6) {
                    Text(L("Older"))
                    IconImage(.arrowRight, size: 15)
                }
            }
            .buttonStyle(PixelButtonStyle(compact: true))
            .opacity(page >= pageCount - 1 ? 0.4 : 1)
            .disabled(page >= pageCount - 1)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func turn(to newPage: Int) {
        withAnimation(.easeInOut(duration: 0.2)) { page = min(max(0, newPage), pageCount - 1) }
    }
}

/// Your saved heroes, each as they look in the game; swipe between them when there's more than one.
private struct SaveCarousel: View {
    let saves: [SaveData]
    @Binding var selection: String?

    var body: some View {
        if saves.count == 1, let save = saves.first {
            SavedHeroCard(save: save)
        } else {
            TabView(selection: Binding(get: { selection ?? saves.first?.slot }, set: { selection = $0 })) {
                ForEach(saves, id: \.slot) { save in
                    SavedHeroCard(save: save)
                        .tag(save.slot)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(height: 262)
            // The games either side fade out toward the edges as they slide by, instead of
            // being cut off sharp.
            .mask(
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.18),
                    .init(color: .black, location: 0.82),
                    .init(color: .clear, location: 1),
                ], startPoint: .leading, endPoint: .trailing)
            )
        }
    }
}

private struct SavedHeroCard: View {
    let save: SaveData
    private let art: String

    init(save: SaveData) {
        self.save = save
        art = "title-hero-\(save.slot ?? "game")"
        GameSession.registerHero(save.hero, as: art)
    }

    var body: some View {
        let content = Content.shared
        // The companion walking with them, if one is out.
        let pet = save.pets.first { $0.id == save.activePetID }
        let petArt = pet.flatMap { content.monster($0.speciesID)?.art }
        // Big enough to read at a glance which game it is (playtesting 2026-10-26: the lines were small).
        VStack(spacing: 6) {
            IdlePair(hero: art, pet: petArt)
            Text(L("Lv {level} {class} · {map}", ["level": save.hero.level, "class": content.classDef(save.hero.classID).name, "map": content.map(save.mapID)?.name ?? ""]))
                .font(HUDStyle.font(17))
                .foregroundStyle(Brand.skyText.opacity(0.9))
            // When you last played it, so you can tell your games apart.
            if let savedAt = save.savedAt {
                Text(L("Played {time}", ["time": savedAt.formatted(.relative(presentation: .named).locale(Localizer.shared.locale))]))
                    .font(HUDStyle.font(14))
                    .foregroundStyle(Brand.skyText.opacity(0.7))
            }
        }
        .multilineTextAlignment(.center)
        // Room for the page dots, apart from the lines over them (playtesting 2026-10-30: they sat
        // right under "Played yesterday"; 2026-10-31: "Add some space between the carousel dots and
        // the heroes"). The carousel is as much taller (`SaveCarousel`).
        .padding(.bottom, 56)
    }
}

/// The hero facing you, breathing like they do while standing in the game, and their companion
/// close beside them with its own idle motion (squish, hop, sway…). A tiny SpriteKit scene, so
/// both move exactly as they do on the map.
private struct IdlePair: View {
    @State private var scene: SKScene

    init(hero: String, pet: String?) {
        _scene = State(initialValue: Self.makeScene(hero: hero, pet: pet))
    }

    var body: some View {
        SpriteView(scene: scene, options: [.allowsTransparency])
            .frame(width: Self.size.width, height: Self.size.height)
            .accessibilityHidden(true)
    }

    /// Room under their feet for a squish or a sway to dip into (a swaying companion's corners
    /// drop a couple of points), and over the hero's head for a breath.
    /// Larger than at first (playtesting 2026-10-26: "The hero and companion can be shown a bit
    /// larger here"), about 1.4 times.
    private static let size = CGSize(width: 210, height: 156)
    private static let floor: CGFloat = 8

    private static func makeScene(hero: String, pet: String?) -> SKScene {
        let scene = SKScene(size: size)
        scene.backgroundColor = .clear
        scene.scaleMode = .aspectFit
        func add(_ art: String, height: CGFloat, x: CGFloat, motion: IdleMotion) {
            let cycle = ArtLibrary.shared.walkCycle(art)
            guard let texture = cycle.frames(.down).first, cycle.size.height > 0 else { return }
            texture.filteringMode = .nearest
            let node = SKSpriteNode(texture: texture, size: cycle.size * (height / cycle.size.height))
            node.anchorPoint = CGPoint(x: 0.5, y: 0.04)
            node.position = CGPoint(x: x, y: floor)
            scene.addChild(node)
            node.run(motion.action(height: node.size.height, delay: .random(in: 0..<0.6)))
        }
        if let pet {
            add(hero, height: 140, x: size.width / 2 - 25, motion: .breathe)
            add(pet, height: 81, x: size.width / 2 + 50, motion: IdleMotion.of(art: pet))
        } else {
            add(hero, height: 140, x: size.width / 2, motion: .breathe)
        }
        return scene
    }
}

/// The title's small round buttons, for what you need now and then: the cream face of the other
/// buttons in a circle, the icon on it and the name underneath. `marked` puts the HUD's gold dot
/// on its corner (something new behind it).
private struct TitleRoundButtonStyle: ButtonStyle {
    let icon: GameIcon
    var marked = false

    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 6) {
            IconImage(icon, size: 24)
                .foregroundStyle(HUDStyle.ink)
                .frame(width: 50, height: 50)
                .background(
                    Circle()
                        .fill(LinearGradient(colors: [HUDStyle.buttonShine, HUDStyle.buttonFace, HUDStyle.buttonFace.opacity(0.85)], startPoint: .top, endPoint: .bottom))
                        .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: configuration.isPressed ? 0 : 3)
                        .overlay(Circle().strokeBorder(HUDStyle.frameDark.opacity(0.7), lineWidth: 1.5))
                )
                .overlay(alignment: .topTrailing) {
                    if marked {
                        // Centred on the rim at the top right (its middle 24 pt out at 45°),
                        // half over the button and half off it.
                        Circle().fill(HUDStyle.gold).frame(width: 13, height: 13)
                            .overlay(Circle().stroke(HUDStyle.ink, lineWidth: 1.5))
                            .offset(x: -1.5, y: 1.5)
                    }
                }
                .offset(y: configuration.isPressed ? 2 : 0)
            configuration.label
                .font(HUDStyle.font(11))
                .foregroundStyle(Brand.skyText.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 92)
        .contentShape(Rectangle())
        .onChange(of: configuration.isPressed) { _, pressed in
            if pressed { SoundEffects.shared.play(.tap, volume: 0.7) }
        }
    }
}

private struct IntroRequest {
    let startPage: Int
    /// Go on to hero creation afterwards (a new game), rather than back to the menu.
    let thenCreate: Bool
    /// How to play's slides alone (the title screen's How to play), not the story before them.
    var howToPlayOnly = false
}

private struct RaceCard: View {
    let race: RaceDef
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(race.name).font(HUDStyle.font(14)).foregroundStyle(selected ? HUDStyle.gold : HUDStyle.cream)
            Text(race.description).font(HUDStyle.font(10)).foregroundStyle(HUDStyle.dim)
                .fixedSize(horizontal: false, vertical: true)
            Text(L("HP {hp} · MP {mp} · ATK {attack} · DEF {defense} · MAG {magic} · SPD {speed}", ["hp": race.base.hp, "mp": race.base.mp, "attack": race.base.attack, "defense": race.base.defense, "magic": race.base.magic, "speed": race.base.speed]))
                .font(HUDStyle.font(9))
                .foregroundStyle(HUDStyle.cream)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(selected ? 0.14 : 0.05))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? HUDStyle.gold : .clear, lineWidth: 2))
        )
        .contentShape(Rectangle())
    }
}
