import Observation
import SpriteKit

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

    var icon: GameIcon {
        switch self {
        case .character: .user
        case .companions: .paw
        case .friends: .users
        case .settings: .settings
        case .bag: .backpack
        case .quests: .book
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
        /// Which town to travel to (`TravelPicker`), when you've been to more than one.
        case destinations(Travel)
    }

    /// A way to a town you've been to: Bridge of Light (the skill's id) or a Homeward Feather (the
    /// item's id). Its MP or its feather is spent once you pick where.
    enum Travel: Equatable {
        case bridge(String)
        case feather(String)
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
        go(to: destination, entry: exit.edge.opposite)
    }

    /// Shows the loading card first, then builds the (big) map behind it. `arrival`: where to stand
    /// there instead of where its road from `entry` comes in.
    private func go(to map: MapDef, entry: Edge?, arrival: CGPoint? = nil) {
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
                await scene.place(on: map, entry: entry, arrival: arrival)
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
            loadMap(map, grid: grid, began: began, entry: entry, arrival: arrival)
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

    func invite(_ adventurer: Adventurer) {
        session.invite(adventurer.id)
        session.nearbyAdventurer = nil
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
        // Gift boxes aren't people: walking up and tapping opens them, no conversation.
        if case .npc(let id) = overlay, let npc = Content.shared.npc(id), npc.role == .chest {
            openChest(npc)
            return
        }
        self.overlay = overlay
        if case .npc = overlay { SoundEffects.shared.play(.talk) }
        if case .npc(let id) = overlay, let npc = Content.shared.npc(id), npc.role != .chest {
            session.postChat(npc.greeting, from: npc.name, kind: .npc)
            session.unreadChat = max(0, session.unreadChat - 1)
        }
        mapScene.isInputLocked = true
        input.move = .zero
    }

    private func openChest(_ chest: NPCDef) {
        if session.isOpened(chest.id) {
            // Something new turns up in it after a while (`GameSession.refillsAt`).
            let hours = session.refillsAt(chest.id).map { Int(($0.timeIntervalSinceNow / 3600).rounded(.up)) } ?? 0
            let name = chest.name.midSentence
            session.post(hours > 1 ? L("The {chest} is empty. Come back in about {hours} hours.", ["chest": name, "hours": hours])
                                   : L("The {chest} is empty. Come back in a little while.", ["chest": name]))
        } else if session.openChest(chest) != nil {
            session.save()
        } else {
            session.post(L("The ribbon is tied tight. Maybe someone in town knows who it's for."))
        }
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

    /// Where to: with one town to go to, straight there; with more, the choice (`TravelPicker`),
    /// nothing spent until you pick one.
    private func choose(_ travel: Travel) {
        let towns = session.travelDestinations
        guard let only = towns.first else {
            session.post(L("There's no other town you've been to yet."))
            return
        }
        if towns.count == 1 {
            depart(travel, to: only)
            return
        }
        overlay = .destinations(travel)
        mapScene.isInputLocked = true
        input.move = .zero
    }

    /// Off to town `mapID` (`travelDestinations`): Bridge of Light spends its MP; a Homeward
    /// Feather is used up and whisks you away first, the window and the bag closed so you see it.
    func depart(_ travel: Travel, to mapID: String) {
        guard battle == nil, session.travelDestinations.contains(mapID), let map = Content.shared.map(mapID) else { return }
        switch travel {
        case .bridge(let id):
            guard let skill = Content.shared.skill(id), session.data.hero.mp >= cost(of: skill) else { return }
            session.data.hero.mp -= cost(of: skill)
            carry(to: map, saying: L("A bridge of light carries you to {place}.", ["place": map.name]))
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
                carry(to: map, saying: line, sound: false)
            }
        }
    }

    /// Set while a Homeward Feather is carrying you: the next map brings you down in its light.
    @ObservationIgnored private var arrivesByFeather = false

    /// Off to a town's square, wherever you are: the window closes and the map changes.
    private func carry(to map: MapDef, saying line: String, sound: Bool = true) {
        overlay = nil
        session.post(line, .quest)
        if sound { SoundEffects.shared.play(.whoosh) }
        go(to: map, entry: nil)
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
