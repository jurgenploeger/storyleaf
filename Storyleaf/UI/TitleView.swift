import SpriteKit
import SwiftUI
import UniformTypeIdentifiers

/// Title screen: continue a saved game, or create a hero (name + race, like Fairyland Online).
struct TitleView: View {
    let onStart: (GameSession) -> Void

    @State private var creating = DebugLaunch.titlePage == "create"
    @State private var name = L("Hero")
    @State private var look = DebugLaunch.createLook(Look(hair: Look.standard.hair, outfit: Look.standard.outfit, skin: Look.standard.skin, gender: "male"))
    @State private var raceID = DebugLaunch.createRace ?? "human"
    /// Your games, the last played first; the carousel shows one at a time.
    @State private var saves = SaveStore.all()
    @State private var selectedSlot: String?
    @State private var showingChangelog = DebugLaunch.titlePage == "news"
    /// What's new's page (0 is the newest): turning it scrolls back up to the panel's top.
    @State private var changelogPage = 0
    @State private var showingSettings = DebugLaunch.titlePage == "settings"
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
    /// The title's own menu, not hero creation, Settings, What's new or the languages.
    private var onMenu: Bool { !creating && !showingLanguages && !showingChangelog && !showingSettings }

    var body: some View {
        ZStack {
            if let intro {
                IntroView(finishTitle: intro.thenCreate ? L("Create your hero") : L("Done"), startPage: intro.startPage,
                          onClose: { withAnimation(.easeInOut(duration: 0.25)) { self.intro = nil } }) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        self.intro = nil
                        if intro.thenCreate { creating = true }
                    }
                }
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
                        ScrollViewReader { reader in
                            ScrollView {
                                page
                                    .frame(maxWidth: .infinity)
                                    .frame(minHeight: proxy.size.height)
                                    .id(Self.pageTop)
                            }
                            .scrollBounceBehavior(.basedOnSize)
                            .onChange(of: changelogPage) { scrollUp(reader) }
                        }
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
                    ScrollViewReader { reader in
                        ScrollView {
                            VStack(spacing: 18) {
                                logo.padding(.top, 12)
                                page.id(Self.pageTop)
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
                        .onChange(of: changelogPage) { scrollUp(reader) }
                    }
                }
                languageButton
            }
        }
        // The app icon's sky, its rays fanning out from behind the logo's leaf wherever the logo is
        // (the story pages have none: there, near the top).
        .storyleafSky(fallback: UnitPoint(x: 0.5, y: 0.18))
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

    /// The scroll anchor at the top of what shows with the logo.
    private static let pageTop = "page"

    /// A new page of What's new starts at its top, not where the last one was read to.
    private func scrollUp(_ reader: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.25)) { reader.scrollTo(Self.pageTop, anchor: .top) }
    }

    /// A backup from Files becomes a game of its own on the carousel (never over another one).
    private func importBackup(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let raw = try? Data(contentsOf: url), let game = try? SaveStore.imported(raw) else {
            importNote = L("That file isn't a Storyleaf backup.")
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
        } else if showingChangelog {
            ChangelogPanel(page: $changelogPage) { showingChangelog = false }
        } else if showingSettings {
            VStack(alignment: .leading, spacing: 0) {
                FLTitleBar(title: L("Settings"), icon: .settings, onClose: { showingSettings = false })
                VStack(alignment: .leading, spacing: 12) {
                    SettingsView(onImportBackup: {
                        showingSettings = false
                        importing = true
                    })
                    Button {
                        showingSettings = false
                    } label: {
                        Label(L("Back"), icon: .arrowLeft)
                    }
                    .buttonStyle(PixelButtonStyle(compact: true))
                }
                .padding(16)
            }
            .frame(maxWidth: 640)
            .gameWindow()
        } else {
            // Your game, and how to start. The round buttons wait at the bottom of the screen
            // (on a phone on its side, under the logo).
            VStack(spacing: 12) {
                games
                startButtons
            }
        }
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

    private var logo: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .raysAnchor(Brand.leafInLogo)
            .frame(maxWidth: 440)
            .accessibilityLabel(L("Storyleaf, a cozy pixel adventure"))
    }

    /// Your games, one at a time, or before the first one, a hero waiting to be made.
    @ViewBuilder
    private var games: some View {
        if saves.isEmpty {
            SpriteImage(art: "player_walk", size: 96)
        } else {
            SaveCarousel(saves: saves, selection: $selectedSlot)
        }
    }

    /// Continue the game on show, or start another.
    private var startButtons: some View {
        VStack(spacing: 12) {
            if let save = selectedSave {
                Button {
                    onStart(GameSession(data: save))
                } label: {
                    Label(L("Continue: {hero}, Lv {level}", ["hero": save.hero.name, "level": save.hero.level]), icon: .play)
                }
                .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold))
            }
            Button {
                // A new game gets its own save, next to the others.
                startNewGame()
            } label: {
                Label(L("New game"), icon: .sparkles)
            }
            // Before your first game, it's the one thing to do.
            .buttonStyle(PixelButtonStyle(tint: saves.isEmpty ? HUDStyle.gold : HUDStyle.cream))
        }
    }

    /// The rest waits in small round buttons, only what fits the moment. A backup is for bringing
    /// a game over before you have one (later it's in Settings); How to play and What's new are
    /// for a player who already has a game.
    private var roundButtons: some View {
        HStack(alignment: .top, spacing: 4) {
            Button(L("Settings")) { showingSettings = true }
                .buttonStyle(TitleRoundButtonStyle(icon: .settings))
            if saves.isEmpty {
                Button(L("Import a backup")) { importing = true }
                    .buttonStyle(TitleRoundButtonStyle(icon: .arrowDown))
            } else {
                Button(L("How to play")) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        intro = IntroRequest(startPage: IntroView.howToPlayPage, thenCreate: false)
                    }
                }
                .buttonStyle(TitleRoundButtonStyle(icon: .book))
                Button(L("What's new")) {
                    seenRelease = newestRelease
                    changelogPage = 0
                    showingChangelog = true
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
            FLTitleBar(title: L("Create your hero"), icon: .user, onClose: { creating = false })
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

/// Release notes from content/changelog.json, newest first, five releases a page. Only the
/// newest is open; tap any other to read it.
private struct ChangelogPanel: View {
    /// The page showing, 0 being the newest (TitleView scrolls up to the panel when it turns).
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FLTitleBar(title: L("What's new"), icon: .book, onClose: onClose)
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
                if pageCount > 1 {
                    pager.padding(.top, 4)
                }
            }
            .padding(16)
        }
        .foregroundStyle(HUDStyle.cream)
        .frame(maxWidth: 640)
        .gameWindow()
    }

    /// Newer and Older under the notes, and which page this is.
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
                Label(L("Older"), icon: .arrowRight)
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
            .frame(height: 190)
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
        VStack(spacing: 4) {
            IdlePair(hero: art, pet: petArt)
            Text(L("Lv {level} {class} · {map}", ["level": save.hero.level, "class": content.classDef(save.hero.classID).name, "map": content.map(save.mapID)?.name ?? ""]))
                .font(HUDStyle.font(10))
                .foregroundStyle(HUDStyle.ink.opacity(0.65))
            // When you last played it, so you can tell your games apart.
            if let savedAt = save.savedAt {
                Text(L("Played {time}", ["time": savedAt.formatted(.relative(presentation: .named).locale(Localizer.shared.locale))]))
                    .font(HUDStyle.font(9))
                    .foregroundStyle(HUDStyle.ink.opacity(0.5))
            }
        }
        .padding(.bottom, 28)   // room for the page dots
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
    private static let size = CGSize(width: 150, height: 112)
    private static let floor: CGFloat = 6

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
            add(hero, height: 100, x: size.width / 2 - 18, motion: .breathe)
            add(pet, height: 58, x: size.width / 2 + 36, motion: IdleMotion.of(art: pet))
        } else {
            add(hero, height: 100, x: size.width / 2, motion: .breathe)
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
                        .fill(LinearGradient(colors: [.white, HUDStyle.cream, HUDStyle.cream.opacity(0.85)], startPoint: .top, endPoint: .bottom))
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
                .foregroundStyle(HUDStyle.ink.opacity(0.75))
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
