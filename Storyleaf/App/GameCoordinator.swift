import Observation
import SpriteKit
import UIKit

enum MenuTab: String, CaseIterable, Identifiable {
    case character = "Character"
    case companions = "Companions"
    case friends = "Friends"
    case bag = "Bag"
    case quests = "Quests"
    case settings = "Settings"

    var id: String { rawValue }

    /// The tab's name as shown (the raw value stays English: it's the id).
    var title: String {
        switch self {
        case .character: L("Character")
        case .companions: L("Companions")
        case .friends: L("Friends")
        case .bag: L("Bag")
        case .quests: L("Quests")
        case .settings: L("Settings")
        }
    }

    /// Its name in the menu and on its window when it has no pages of its own.
    var menuTitle: String {
        switch self {
        case .character: L("Hero")
        case .companions: L("Companion")
        case .bag: L("Inventory")
        case .quests, .settings, .friends: title
        }
    }

    var icon: GameIcon {
        switch self {
        case .character: .user
        case .companions: .paw
        case .friends: .users
        case .settings: .settings
        case .bag: .backpack
        case .quests: .star
        }
    }
}

/// Owns what's on screen: the current map, a battle, or a menu/dialog on top.
@Observable
final class GameCoordinator {
    enum Overlay: Equatable {
        case menu(MenuTab)
        case npc(String)
        case worldMap
        case chat
        /// Swapping goods with an adventurer you're standing next to.
        case trade(Adventurer)
        /// Someone's stats: tapped on the map, or their face in the top-left corner.
        case profile(Profile)
        /// Which town or waystone to travel to (`TravelPicker`), when there's more than one.
        case destinations(Travel)
    }

    /// A way to a town you've been to or a waystone you've woken (`GameSession.travelDestinations`):
    /// Bridge of Light (the skill's id) or a Homeward Feather (the item's id), its MP or its feather
    /// spent once you pick where; or touching a waystone you've woken, free.
    enum Travel: Equatable {
        case bridge(String)
        case feather(String)
        case waystone
    }

    let session: GameSession
    let input: InputState
    /// The game's own notices in the chat (content/announcements.json).
    let announcer: Announcer
    private(set) var world: WorldScene
    private(set) var battle: BattleController?
    private(set) var overlay: Overlay?
    /// False until the first map frame has rendered (the loading curtain stays up until then).
    private(set) var isReady = false
    /// The map being travelled to, while its loading card is showing.
    private(set) var loadingMapName: String?
    /// How far the map build has got, 0...1, for the loading bar.
    private(set) var loadProgress: Double = 0
    @ObservationIgnored private var loadingStarted = Date()
    @ObservationIgnored private(set) var battleScene: BattleScene?
    /// Set by the app: saves are done, go back to the title screen.
    @ObservationIgnored var onQuitToTitle: (() -> Void)?
    /// The day's gift, given and waiting to be shown (GameView's DailyGiftCard).
    var dailyGift: GameSession.DailyGift?

    /// `grid`: the land the save starts in, laid out already off the main thread (`layOut`), which
    /// began at `began`.
    init(session: GameSession, grid: WorldMap? = nil, began: Date? = nil) {
        let input = InputState()
        let map = Self.startingMap(of: session)
        self.session = session
        self.input = input
        announcer = Announcer(session: session)
        // Titles an older save already deserves, in one line (before this map's visit counts).
        session.checkTitles(quietly: true)
        session.markVisited(map.id)
        session.rescaleLevelsIfNeeded()
        session.rescaleSkillLevelsIfNeeded()
        session.retireRebirthsIfNeeded()
        session.handOutArmourHatsIfNeeded()
        session.handOutMissingStarterGifts()
        session.claimBookMilestones()
        session.refreshBounties()
        dailyGift = session.collectDailyGift()
        let began = began ?? Date()
        world = WorldScene(map: map, session: session, input: input, entry: nil, grid: grid?.def.id == map.id ? grid : nil)
        if Continent.origin(of: map) != nil {
            // A land on the continent: the continent, with you where the save left you there (the
            // land's scene above only says where that is).
            startOnContinent(map, grid: grid?.def.id == map.id ? grid : nil, began: began)
        } else {
            wire(world)
            build(world, mapID: map.id, began: began)
        }
        startAutosave()
        announcer.start()
        session.onCastField = { [weak self] skill in self?.castField(skill) }
        session.onTravel = { [weak self] item in self?.travel(with: item) }
        SoundEffects.shared.preload()
    }

    /// The land a save starts in.
    static func startingMap(of session: GameSession) -> MapDef {
        Content.shared.map(session.data.mapID) ?? Content.shared.maps[0]
    }

    /// Lays a land out off the main thread: the one piece of a load that can't be cut finer, so the
    /// screen still turns with the phone (and the loading card with it) meanwhile.
    static func layOut(_ def: MapDef) async -> WorldMap {
        let caves = WorldMap.caves
        let around = Continent.neighbourhood(of: def)
        return await Task.detached(priority: .userInitiated) { await MapLayouts.shared.lay(def, caves: caves, around: around) }.value
    }

    /// Saves quietly every 20 seconds while exploring (and after every important moment elsewhere).
    private func startAutosave() {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard let self else { return }
                if self.battle == nil { self.session.save() }
            }
        }
    }

    /// Back in front after a while: a new day brings new bounties and its gift.
    func welcomeBack() {
        session.refreshBounties()
        if dailyGift == nil, let gift = session.collectDailyGift() { dailyGift = gift }
    }

    /// The scene SpriteKit should show right now.
    var scene: SKScene { battle != nil ? (battleScene ?? mapScene) : mapScene }
    /// The scene you walk about in: the continent, unless you're in a cave (its own scene, `world`).
    var mapScene: any MapScene {
        if showsContinent, let continent { return continent }
        return world
    }

    /// The land you're in: on the continent the one your feet are in, in a cave the cave.
    var currentLand: MapDef {
        showsContinent ? continent?.here ?? world.def : world.def
    }

    /// The HUD's minimap of the land you're in, with what's round it, and that land's size in cells.
    func minimap(explored version: Int, overviews: Int) -> (picture: WorldScene.MinimapPicture, columns: Int, rows: Int) {
        if showsContinent, let continent, let here = continent.here, let picture = continent.minimapPicture(overviews: overviews) {
            return (picture, here.width, here.height)
        }
        return (world.minimapPicture(explored: version, overviews: overviews), world.def.width, world.def.height)
    }

    /// In a cave, its own map for the map window (playtesting 2026-10-17: the world map showed the
    /// sea round the island instead): the minimap's picture of it, only as far as you've explored on
    /// a dark one. Nil out on the continent, where the window shows the world.
    var caveMap: CaveMap.Picture? {
        guard !showsContinent, world.def.theme.cave != nil else { return nil }
        return CaveMap.Picture(image: world.minimapImage(explored: session.exploredVersion),
                               columns: world.def.width, rows: world.def.height)
    }

    /// The levels of the cave you're in that its map window can show, the top first (playtesting
    /// 2026-10-20: "there should be navigation to see all three levels"): every one once you have
    /// its map, else those you've been down to. Empty out on the continent.
    var caveLevels: [MapDef] {
        guard caveMap != nil else { return [] }
        return Content.shared.caveLevels(of: world.def).filter { $0.id == world.def.id || session.isCharted($0) || session.hasVisited($0.id) }
    }

    /// Another level of the cave's map, for the map window: laid out the first time it's asked for,
    /// dark where you haven't been unless you have its map.
    func caveMap(of level: MapDef) async -> CaveMap.Picture? {
        if level.id == world.def.id { return caveMap }
        let whole: UIImage
        if let drawn = levelPictures[level.id] {
            whole = drawn
        } else {
            let grid = await Self.layOut(level)
            whole = UIImage(cgImage: WorldScene.overview(of: grid, art: ArtLibrary.shared))
            levelPictures[level.id] = whole
        }
        let image = session.isFogged(level)
            ? WorldScene.fog(whole, seen: session.explored(level.id), columns: level.width, rows: level.height) : whole
        return CaveMap.Picture(image: image, columns: level.width, rows: level.height)
    }

    /// The other cave levels' minimaps, whole, once laid out (`caveMap(of:)`).
    @ObservationIgnored private var levelPictures: [String: UIImage] = [:]

    /// The continent as one place (`ContinentScene`, docs/continuous-world.md): every land on it, with
    /// no border between them. Made once, the first time you're on it, and kept while you're in a
    /// cave.
    private(set) var continent: ContinentScene?
    /// Whether you're on the continent (not in a cave): what's shown and what the HUD asks.
    private var showsContinent = false

    /// The continent, made and wired the first time it's wanted.
    private func makeContinent() -> ContinentScene {
        if let continent { return continent }
        let scene = ContinentScene(session: session, input: input)
        scene.onTalk = { [weak self] npc in self?.open(.npc(npc.id)) }
        scene.onInspect = { [weak self] profile in self?.open(.profile(profile)) }
        scene.onEncounter = { [weak self] encounters, backdrop in self?.startBattle(encounters, backdrop: backdrop) }
        scene.onDuel = { [weak self] rival, backdrop in self?.startDuel(with: rival, backdrop: backdrop) }
        scene.onTravel = { [weak self] exit in self?.travel(through: exit) }
        continent = scene
        return scene
    }

    /// The game starts on the continent: behind the loading card till the chunks round you are drawn.
    private func startOnContinent(_ map: MapDef, grid: WorldMap?, began: Date) {
        loadingStarted = began
        loadProgress = 0.15
        let scene = makeContinent()
        // Laid out already, as the game opened.
        if let grid { scene.adopt(grid) }
        showsContinent = true
        let saved = session.playerPosition
        Task { [weak self] in
            await scene.place(on: map, entry: nil, arrival: saved)
            await self?.waitForContinent()
            self?.finishLoading()
        }
    }

    /// Till the land you're in is drawn round you on the continent (or a couple of minutes, should
    /// it never be), the loading bar creeping on meanwhile.
    private func waitForContinent() async {
        guard let continent else { return }
        for _ in 0..<480 where !continent.isReady {
            try? await Task.sleep(for: .milliseconds(250))
            loadProgress = min(0.95, loadProgress + 0.01)
        }
    }

    /// Builds the scenery a piece at a time. The bar follows how long each piece took the last time
    /// this map loaded (on this phone); the first time, the scene's own rough guesses.
    private func build(_ scene: WorldScene, mapID: String, began: Date) {
        let learned = Self.learnedSteps(mapID)
        let gridDone = Date()
        loadProgress = learned?.first ?? 0.15
        Task { [weak self] in
            var marks = [gridDone]
            await scene.build { guess in
                marks.append(Date())
                let step = marks.count - 1
                if let learned, step < learned.count {
                    self?.loadProgress = learned[step]
                } else {
                    self?.loadProgress = 0.15 + guess * 0.8
                }
            }
            self?.loadTiming = (mapID, began, marks)
        }
    }

    /// When the current load began and when each of its steps finished, until the first frame.
    @ObservationIgnored private var loadTiming: (mapID: String, began: Date, marks: [Date])?

    private static func learnedSteps(_ mapID: String) -> [Double]? {
        UserDefaults.standard.array(forKey: "loadSteps." + mapID) as? [Double]
    }

    /// Remembers what share of the whole load each step took, for the next time.
    private func rememberLoadTiming() {
        guard let timing = loadTiming else { return }
        loadTiming = nil
        let total = Date().timeIntervalSince(timing.began)
        guard total > 0 else { return }
        let steps = timing.marks.map { min(0.99, $0.timeIntervalSince(timing.began) / total) }
        UserDefaults.standard.set(steps, forKey: "loadSteps." + timing.mapID)
    }

    private func wire(_ scene: WorldScene) {
        scene.onFirstFrame = { [weak self] in self?.finishLoading() }
        scene.onEncounter = { [weak self] encounters, backdrop in self?.startBattle(encounters, backdrop: backdrop) }
        scene.onTalk = { [weak self] npc in self?.open(.npc(npc.id)) }
        scene.onTravel = { [weak self] exit in self?.travel(through: exit) }
        scene.onDuel = { [weak self] rival, backdrop in self?.startDuel(with: rival, backdrop: backdrop) }
        scene.onInspect = { [weak self] profile in self?.open(.profile(profile)) }
    }

    // MARK: Maps

    private func travel(through exit: MapDef.Exit) {
        guard let destination = Content.shared.map(exit.to) else {
            mapScene.resume()
            return
        }
        SoundEffects.shared.play(.whoosh)
        // In by its own road back to where you were: a cave's comes in on the side you walked into
        // its mouth from, not across from the side the land's road names (playtesting 2026-10-16).
        let back = destination.exits.first { $0.to == session.data.mapID }?.edge
        go(to: destination, entry: back ?? exit.edge.opposite)
    }

    /// Stairs in a cave (`NPCRole.stairs`): down to the level under it, or back up, coming out in
    /// front of the stairs there that lead back (RuneScape's ladders; playtesting 2026-10-18).
    private func climb(_ stairs: NPCDef) {
        guard let to = stairs.to, let destination = Content.shared.map(to) else { return }
        SoundEffects.shared.play(.whoosh)
        go(to: destination, entry: nil, byStairsFrom: session.data.mapID)
    }

    /// Shows the loading card first, then builds the (big) map behind it. `arrival`: where to stand
    /// there instead of where its road from `entry` comes in. `byStairsFrom`: climbing from that
    /// cave level, in front of the stairs leading back to it (`WorldMap.stairsArrival`). `waystone`:
    /// in front of that waystone there (`WorldMap.waystoneArrival`).
    private func go(to map: MapDef, entry: Edge?, arrival: CGPoint? = nil, byStairsFrom stairs: String? = nil,
                    waystone: String? = nil) {
        // The map you're leaving stays on screen under the card for a moment: nothing more happens on it.
        mapScene.isInputLocked = true
        loadingMapName = map.name
        loadingStarted = Date()
        loadProgress = 0
        isReady = false
        if Continent.origin(of: map) != nil {
            // A land on the continent (out of a cave, carried to a town, waking at your checkpoint):
            // you're put there on it, its chunks drawn behind the card.
            Task {
                try? await Task.sleep(for: .milliseconds(280))
                session.markVisited(map.id)
                session.bossesBeatenHere = []
                session.reachCheckpoint(map)
                let scene = makeContinent()
                showsContinent = true
                input.move = .zero
                await scene.place(on: map, entry: entry, arrival: arrival, waystone: waystone)
                await waitForContinent()
                scene.resume()
                finishLoading()
                session.save()
            }
            return
        }
        Task {
            try? await Task.sleep(for: .milliseconds(280))
            let began = Date()
            let grid = await GameCoordinator.layOut(map)
            let landing = arrival ?? (stairs.flatMap { grid.stairsArrival(from: $0) } ?? waystone.flatMap { grid.waystoneArrival($0) })
                .map { grid.center(of: $0) }
            loadMap(map, grid: grid, began: began, entry: entry, arrival: landing)
        }
    }

    /// Keeps the loading card up long enough to read, then fades it out.
    private func finishLoading() {
        rememberLoadTiming()
        // The map's chat has started over by now (WorldScene.didMove), so the notice stays in it.
        announcer.arrived(at: currentLand)
        let remaining = 0.8 - Date().timeIntervalSince(loadingStarted)
        Task {
            loadProgress = 1
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
            // Carried by a Homeward Feather: you're not standing there yet when the card lifts.
            let byFeather = arrivesByFeather
            arrivesByFeather = false
            if byFeather { mapScene.awaitFeatherArrival() }
            isReady = true
            // A debug launch's screenshot of the continent waits, the card gone as a player's would
            // be, for the lands round you to come in too (`isSettled`), a few minutes at most.
            if DebugLaunch.isActive, showsContinent, !byFeather, let continent {
                loadingMapName = nil
                continent.hurries = true
                for _ in 0..<960 where !continent.isSettled {
                    try? await Task.sleep(for: .milliseconds(250))
                }
                continent.hurries = false
            }
            DebugLaunch.markReady()
            loadingMapName = nil
            if byFeather {
                try? await Task.sleep(for: .milliseconds(250))
                mapScene.featherArrive()
            }
        }
    }

    private func loadMap(_ map: MapDef, grid: WorldMap, began: Date, entry: Edge?, arrival: CGPoint? = nil) {
        session.data.mapID = map.id
        session.markVisited(map.id)
        session.bossesBeatenHere = []
        if entry == nil { session.playerPosition = nil }
        session.reachCheckpoint(map)
        let scene = WorldScene(map: map, session: session, input: input, entry: entry, arrival: arrival, grid: grid)
        wire(scene)
        build(scene, mapID: map.id, began: began)
        input.move = .zero
        world = scene
        showsContinent = false
        session.save()
    }

    // MARK: Battles

    func startBattle(_ encounters: MapDef.Encounters, backdrop: SKTexture? = nil) {
        // One battle at a time: a second starting on top of the first would take its place mid-fade.
        guard battle == nil else { return }
        let controller = BattleController.encounter(encounters, session: session)
        SoundEffects.shared.play(.encounter)
        controller.onFinish = { [weak self] outcome in self?.endBattle(outcome) }
        battleScene = BattleScene(controller: controller, size: mapScene.size, backdrop: backdrop)
        input.move = .zero
        battle = controller
        isReady = true
        DebugLaunch.markReady()
    }

    /// The adventurer you're duelling, so they can leave the map if you win.
    private var rival: Adventurer?

    private func startDuel(with rival: Adventurer, backdrop: SKTexture?) {
        guard battle == nil else { return }
        let controller = BattleController.duel(with: rival, session: session)
        controller.onFinish = { [weak self] outcome in self?.endBattle(outcome) }
        battleScene = BattleScene(controller: controller, size: mapScene.size, backdrop: backdrop)
        input.move = .zero
        self.rival = rival
        battle = controller
        isReady = true
        DebugLaunch.markReady()
    }

    /// The boss you're fighting, so it disappears from the map once beaten.
    private var boss: NPCDef?

    func fightBoss(_ npc: NPCDef) {
        guard battle == nil, let controller = BattleController.boss(npc, encounters: currentLand.encounters, session: session) else { return }
        overlay = nil
        controller.onFinish = { [weak self] outcome in self?.endBattle(outcome) }
        // The map you're standing on, like any fight (without the boss: it's in the battle now).
        battleScene = BattleScene(controller: controller, size: mapScene.size, backdrop: mapScene.battleBackdrop(hiding: npc.id))
        input.move = .zero
        boss = npc
        battle = controller
        isReady = true
        DebugLaunch.markReady()
    }

    /// From the adventurer card: befriend, invite along, or challenge.
    func befriend(_ adventurer: Adventurer) {
        if session.befriend(adventurer) {
            mapScene.adventurerSays([L("Yay, friends! ^_^"), L("Sure! Let's adventure sometime!"), L("Friends! :D")].randomElement()!, adventurer.id)
        }
    }

    func trade(with adventurer: Adventurer) {
        open(.trade(adventurer))
    }

    /// Asks a friend along: they join you, or say why not (`GameSession.askAlong`). One travelling
    /// with others is less keen.
    func invite(_ adventurer: Adventurer) {
        let busy = session.nearbyGroup.count > 1 && session.nearbyGroup.contains { $0.id == adventurer.id }
        if let reply = session.askAlong(adventurer.id, busy: busy) { mapScene.adventurerSays(reply.line, adventurer.id) }
        session.nearbyAdventurer = nil
    }

    /// Asks the group the adventurer travels with to let you join them: whoever leads answers
    /// (`GameSession.askToJoin`), and with a yes you follow them about.
    func askToJoin(_ adventurer: Adventurer) {
        let group = session.nearbyGroup
        guard group.contains(where: { $0.id == adventurer.id }), let reply = session.askToJoin(group) else { return }
        mapScene.adventurerSays(reply.line, group.first?.id ?? adventurer.id)
        session.nearbyAdventurer = nil
    }

    /// Leaves the party you've joined, of your own accord.
    func leaveJoinedParty() {
        guard let leader = session.leaveJoinedParty(.wandered) else { return }
        mapScene.adventurerSays([L("See you around!"), L("Take care out there!"), L("Bye for now!")].randomElement() ?? L("See you around!"), leader.id)
    }

    func challenge(_ adventurer: Adventurer) {
        mapScene.startDuel(with: adventurer)
    }

    #if DEBUG
    /// Debug launches (`duel`): a duel starts at once, without walking up to anyone.
    func duelForDebug(_ rival: Adventurer) {
        startDuel(with: rival, backdrop: nil)
    }
    #endif

    private func endBattle(_ outcome: BattleOutcome) {
        let fainted = battle?.heroIsDown == true
        battle = nil
        battleScene = nil
        if let rival, outcome == .victory { mapScene.dismissAdventurer(rival.id) }
        rival = nil
        if let boss, outcome == .victory { session.defeatBoss(boss) }
        boss = nil
        if fainted, let map = Content.shared.map(session.checkpoint.mapID) {
            // Fainted (even if your friends won): wake up at the checkpoint.
            go(to: map, entry: session.checkpoint.entry)
        } else {
            mapScene.resume()
        }
        session.save()
    }

    // MARK: Menus & dialogs

    func open(_ overlay: Overlay) {
        // Gift boxes, stairs and waystones aren't people: walking up and tapping opens them, takes
        // you down (or up), or away, no conversation.
        if case .npc(let id) = overlay, let npc = Content.shared.npc(id), npc.role.isObject {
            switch npc.role {
            case .stairs: climb(npc)
            case .waystone: touch(npc)
            default: openChest(npc)
            }
            return
        }
        self.overlay = overlay
        if case .npc = overlay { SoundEffects.shared.play(.talk) }
        if case .npc(let id) = overlay, let npc = Content.shared.npc(id), !npc.role.isObject {
            session.postChat(npc.greeting, from: npc.name, kind: .npc)
            session.unreadChat = max(0, session.unreadChat - 1)
        }
        mapScene.isInputLocked = true
        input.move = .zero
    }

    private func openChest(_ chest: NPCDef) {
        if session.isOpened(chest.id) {
            // Something new turns up in it after a while (`GameSession.refillsAt`); just when isn't
            // said (playtesting 2026-10-16: "come back later" instead of the exact hours).
            session.post(L("The {chest} is empty. Come back later.", ["chest": chest.name.midSentence]))
        } else if session.openChest(chest) != nil {
            session.save()
        } else {
            session.post(L("The ribbon is tied tight. Maybe someone in town knows who it's for."))
        }
    }

    /// A waystone (`NPCRole.waystone`): once its quest has woken it, anywhere you can travel to,
    /// free; till then, cold.
    private func touch(_ waystone: NPCDef) {
        guard session.isAwake(waystone) else {
            session.post(L("The waystone is cold and still. Someone nearby might know how to wake it."))
            return
        }
        choose(.waystone)
    }

    /// A field spell cast from the Character screen. Bridge of Light carries you to a town you've
    /// been to.
    private func castField(_ skill: SkillDef) {
        guard battle == nil, skill.id == "bridge_of_light" else { return }
        guard session.data.hero.mp >= cost(of: skill) else {
            session.post(L("Not enough MP for {skill}.", ["skill": skill.name]))
            return
        }
        choose(.bridge(skill.id))
    }

    private func cost(of skill: SkillDef) -> Int {
        GameSession.mpCost(of: skill, level: session.skillLevel(skill.id))
    }

    /// A travel item used from the bag (the Homeward Feather): to a town you've been to, like
    /// Bridge of Light, for any class. One is used up.
    private func travel(with item: ItemDef) {
        guard battle == nil, item.travel == true, session.count(of: item.id) > 0 else { return }
        choose(.feather(item.id))
    }

    /// Where to: with one town or waystone to go to, straight there; with more, the choice
    /// (`TravelPicker`), nothing spent until you pick one.
    private func choose(_ travel: Travel) {
        let places = session.travelDestinations
        guard let only = places.first else {
            session.post(L("There's no other town you've been to yet."))
            return
        }
        if places.count == 1 {
            depart(travel, to: only)
            return
        }
        overlay = .destinations(travel)
        mapScene.isInputLocked = true
        input.move = .zero
    }

    /// Off to a town or a waystone (`travelDestinations`: a town's map id or a waystone's id):
    /// Bridge of Light spends its MP; a Homeward Feather is used up and whisks you away first, the
    /// window and the bag closed so you see it; a waystone you're touching takes you free.
    func depart(_ travel: Travel, to destination: String) {
        let waystone = Content.shared.npc(destination).flatMap { $0.role == .waystone ? $0.id : nil }
        guard battle == nil, session.travelDestinations.contains(destination),
              let map = waystone.flatMap({ Content.shared.home(ofNPC: $0) }) ?? Content.shared.map(destination) else { return }
        switch travel {
        case .bridge(let id):
            guard let skill = Content.shared.skill(id), session.data.hero.mp >= cost(of: skill) else { return }
            session.data.hero.mp -= cost(of: skill)
            carry(to: map, waystone: waystone, saying: L("A bridge of light carries you to {place}.", ["place": map.name]))
        case .waystone:
            carry(to: map, waystone: waystone, saying: L("The waystone hums, and the world folds round you. You step out in {place}.", ["place": map.name]))
        case .feather(let id):
            guard session.removeItem(id) else { return }
            let line = L("The wind carries you to {place}.", ["place": map.name])
            // The feathers whisk you up before the map changes; you come down in the same light at
            // the other end (finishLoading).
            overlay = nil
            SoundEffects.shared.play(.whoosh)
            mapScene.featherAway { [weak self] in
                guard let self else { return }
                arrivesByFeather = true
                carry(to: map, waystone: waystone, saying: line, sound: false)
            }
        }
    }

    /// Set while a Homeward Feather is carrying you: the next map brings you down in its light.
    @ObservationIgnored private var arrivesByFeather = false

    /// Off to a town's square, or to the `waystone` on `map`, wherever you are: the window closes
    /// and the map changes.
    private func carry(to map: MapDef, waystone: String? = nil, saying line: String, sound: Bool = true) {
        overlay = nil
        session.post(line, .quest)
        if sound { SoundEffects.shared.play(.whoosh) }
        go(to: map, entry: nil, waystone: waystone)
    }

    func closeOverlay() {
        SoundEffects.shared.play(.close, volume: 0.8)
        overlay = nil
        mapScene.resume()
        session.save()
    }

    func talkToNearby() {
        mapScene.talkToNearby()
    }

    func say(_ text: String) {
        mapScene.heroSay(text)
    }
}
