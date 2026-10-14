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

    init(session: GameSession) {
        let input = InputState()
        let map = Content.shared.map(session.data.mapID) ?? Content.shared.maps[0]
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
        let began = Date()
        world = WorldScene(map: map, session: session, input: input, entry: nil)
        wire(world)
        build(world, mapID: map.id, began: began)
        startAutosave()
        announcer.start()
        session.onCastField = { [weak self] skill in self?.castField(skill) }
        session.onTravel = { [weak self] item in self?.travel(with: item) }
        SoundEffects.shared.preload()
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
    var scene: SKScene { battle != nil ? (battleScene ?? world) : world }

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
        scene.onLandsNear = { [weak self] near in self?.landsNear(near) }
        scene.onCross = { [weak self] neighbour, land, point in self?.cross(neighbour, into: land, at: point) }
    }

    // MARK: Next door

    /// Lands next door, built (or being built) in the background to show past the borders of the
    /// land you're in, by id.
    @ObservationIgnored private var nextDoor: [String: WorldScene] = [:]
    /// The one being built now: one at a time, the nearest first.
    @ObservationIgnored private var buildingNextDoor: String?
    /// How near a land's border you come before it's built and shown (in cells: a little more than
    /// you can see past it, with time to build it at a walk), and how far you go before it's let go.
    private static let buildWithin = 48
    private static let keepWithin = 64
    /// Debug launches (`border`): the land next door is built at once for the screenshot
    /// (`showNextDoorForDebug`), not in the background as you near it.
    @ObservationIgnored var holdsNextDoor = false

    /// Every half second, the land you're in says how far each land next door is: the nearest not
    /// built yet starts building, the built ones near enough show past their borders, and those
    /// left far behind are let go.
    private func landsNear(_ near: [(neighbour: Continent.Neighbour, distance: Int)]) {
        guard !holdsNextDoor else { return }
        let here = world
        let shown = here.shownNextDoor
        for (neighbour, distance) in near {
            let id = neighbour.def.id
            if let land = nextDoor[id] ?? shown[id] {
                if land.isBuilt, distance <= Self.keepWithin, shown[id] == nil { here.show(land, as: neighbour) }
            } else if buildingNextDoor == nil, distance <= Self.buildWithin {
                buildNextDoor(neighbour.def)
            }
        }
        let wanted = Set(near.filter { $0.distance <= Self.keepWithin }.map(\.neighbour.def.id))
        for id in Set(nextDoor.keys).union(shown.keys) where !wanted.contains(id) && id != buildingNextDoor {
            here.hide(id)
            nextDoor[id] = nil
            ArtLibrary.shared.release(map: id)
        }
    }

    #if DEBUG
    /// Debug launches (`border=<land>`): that land next door built at once (in long slices) and
    /// shown, for a screenshot of the border.
    func showNextDoorForDebug(_ id: String) async {
        guard let neighbour = world.neighbours.first(where: { $0.def.id == id }) else { return }
        buildingNextDoor = id
        let land = WorldScene(map: neighbour.def, session: session, input: input, entry: nil, nextDoor: true)
        land.friendsElsewhere = world.visitingFriends
        nextDoor[id] = land
        await land.build(pace: .hurried) { _ in }
        _ = land.minimap
        buildingNextDoor = nil
        world.show(land, as: neighbour)
    }
    #endif

    /// Lays a land next door out off the main thread, then builds it a few milliseconds a frame.
    private func buildNextDoor(_ def: MapDef) {
        buildingNextDoor = def.id
        let caves = WorldMap.caves
        let coast = Continent.coast(of: def)
        let away = world.visitingFriends
        Task { [weak self] in
            let grid = await Task.detached(priority: .userInitiated) { await MapLayouts.shared.lay(def, caves: caves, coast: coast) }.value
            guard let self else { return }
            // Its picture at once, from the layout, to lie past the border (`WorldScene.placeFarLands`)
            // and on the minimap while the land itself is built.
            WorldOverview.shared.remember(def.id, WorldScene.overview(of: grid, art: ArtLibrary.shared))
            let land = WorldScene(map: def, session: session, input: input, entry: nil, grid: grid, nextDoor: true)
            land.friendsElsewhere = away
            nextDoor[def.id] = land
            await land.build(pace: .background) { _ in }
            // Its picture for the minimap and the world map (`WorldOverview`).
            _ = land.minimap
            if buildingNextDoor == def.id { buildingNextDoor = nil }
        }
    }

    /// You've walked over a border. Into a land shown next door: it simply carries on there, no
    /// loading card (`WorldScene.takeOver`), and the land you left shows next door in its turn.
    /// Into one not built yet: there behind the card, where you stepped across.
    private func cross(_ neighbour: Continent.Neighbour, into land: WorldScene?, at point: CGPoint) {
        guard let land else {
            SoundEffects.shared.play(.whoosh)
            go(to: neighbour.def, entry: nil, arrival: point)
            return
        }
        let previous = world
        previous.isInputLocked = true
        land.walkedInFrom = previous
        land.arrivesOnFoot = true
        nextDoor[land.def.id] = nil
        nextDoor[previous.def.id] = previous
        session.data.mapID = land.def.id
        session.markVisited(land.def.id)
        session.bossesBeatenHere = []
        session.reachCheckpoint(land.def)
        // Its first frame tells the announcer you've arrived (`finishLoading`), as after a card.
        wire(land)
        world = land
        Task { [weak self] in
            // Once it's taken over (as it shows), with where you stand there.
            try? await Task.sleep(for: .milliseconds(300))
            self?.session.save()
        }
    }

    // MARK: Maps

    private func travel(through exit: MapDef.Exit) {
        guard let destination = Content.shared.map(exit.to) else {
            world.resume()
            return
        }
        SoundEffects.shared.play(.whoosh)
        go(to: destination, entry: exit.edge.opposite)
    }

    /// Shows the loading card first, then builds the (big) map behind it. `arrival`: where to stand
    /// there instead of where its road from `entry` comes in.
    private func go(to map: MapDef, entry: Edge?, arrival: CGPoint? = nil) {
        // The map you're leaving stays on screen under the card for a moment: nothing more happens on it.
        world.isInputLocked = true
        loadingMapName = map.name
        loadingStarted = Date()
        loadProgress = 0
        isReady = false
        Task {
            try? await Task.sleep(for: .milliseconds(280))
            loadMap(map, entry: entry, arrival: arrival)
        }
    }

    /// Keeps the loading card up long enough to read, then fades it out.
    private func finishLoading() {
        rememberLoadTiming()
        // The map's chat has started over by now (WorldScene.didMove), so the notice stays in it.
        announcer.arrived(at: world.def)
        let remaining = 0.8 - Date().timeIntervalSince(loadingStarted)
        Task {
            loadProgress = 1
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
            // Carried by a Homeward Feather: you're not standing there yet when the card lifts.
            let byFeather = arrivesByFeather
            arrivesByFeather = false
            if byFeather { world.awaitFeatherArrival() }
            isReady = true
            DebugLaunch.markReady()
            loadingMapName = nil
            if byFeather {
                try? await Task.sleep(for: .milliseconds(250))
                world.featherArrive()
            }
        }
    }

    private func loadMap(_ map: MapDef, entry: Edge?, arrival: CGPoint? = nil) {
        session.data.mapID = map.id
        session.markVisited(map.id)
        session.bossesBeatenHere = []
        if entry == nil { session.playerPosition = nil }
        session.reachCheckpoint(map)
        // A new start: the lands next door to wherever you were are let go (the new one's are built
        // as you walk toward them).
        for id in nextDoor.keys { ArtLibrary.shared.release(map: id) }
        nextDoor = [:]
        buildingNextDoor = nil
        let began = Date()
        let scene = WorldScene(map: map, session: session, input: input, entry: entry, arrival: arrival)
        wire(scene)
        build(scene, mapID: map.id, began: began)
        input.move = .zero
        world = scene
        session.save()
    }

    // MARK: Battles

    func startBattle(_ encounters: MapDef.Encounters, backdrop: SKTexture? = nil) {
        // One battle at a time: a second starting on top of the first would take its place mid-fade.
        guard battle == nil else { return }
        let controller = BattleController.encounter(encounters, session: session)
        SoundEffects.shared.play(.encounter)
        controller.onFinish = { [weak self] outcome in self?.endBattle(outcome) }
        battleScene = BattleScene(controller: controller, size: world.size, backdrop: backdrop)
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
        battleScene = BattleScene(controller: controller, size: world.size, backdrop: backdrop)
        input.move = .zero
        self.rival = rival
        battle = controller
        isReady = true
        DebugLaunch.markReady()
    }

    /// The boss you're fighting, so it disappears from the map once beaten.
    private var boss: NPCDef?

    func fightBoss(_ npc: NPCDef) {
        guard battle == nil, let controller = BattleController.boss(npc, encounters: world.def.encounters, session: session) else { return }
        overlay = nil
        controller.onFinish = { [weak self] outcome in self?.endBattle(outcome) }
        // The map you're standing on, like any fight (without the boss: it's in the battle now).
        battleScene = BattleScene(controller: controller, size: world.size, backdrop: world.battleBackdrop(hiding: npc.id))
        input.move = .zero
        boss = npc
        battle = controller
        isReady = true
        DebugLaunch.markReady()
    }

    /// From the adventurer card: befriend, invite along, or challenge.
    func befriend(_ adventurer: Adventurer) {
        if session.befriend(adventurer) {
            world.adventurerSays([L("Yay, friends! ^_^"), L("Sure! Let's adventure sometime!"), L("Friends! :D")].randomElement()!, adventurer.id)
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
        world.startDuel(with: adventurer)
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
        if let rival, outcome == .victory { world.dismissAdventurer(rival.id) }
        rival = nil
        if let boss, outcome == .victory { session.defeatBoss(boss) }
        boss = nil
        if fainted, let map = Content.shared.map(session.checkpoint.mapID) {
            // Fainted (even if your friends won): wake up at the checkpoint.
            go(to: map, entry: session.checkpoint.entry)
        } else {
            world.resume()
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
        world.isInputLocked = true
        input.move = .zero
    }

    private func openChest(_ chest: NPCDef) {
        if session.isOpened(chest.id) {
            session.post(L("The {chest} is empty.", ["chest": chest.name.midSentence]))
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
        world.isInputLocked = true
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
            world.featherAway { [weak self] in
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
        world.resume()
        session.save()
    }

    func talkToNearby() {
        world.talkToNearby()
    }

    func say(_ text: String) {
        world.heroSay(text)
    }
}
