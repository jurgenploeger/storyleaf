import CoreGraphics
import Foundation
import Observation

/// The tag next to someone's name: BOT for the computer-run adventurers.
nonisolated enum PlayerBadge: String, Sendable {
    case bot = "BOT"

    /// The tag as shown over a name and in the chat.
    var title: String {
        switch self {
        case .bot: L("BOT")
        }
    }
}

/// The player's progress: hero, companions, bag, quests. All rules for levelling,
/// equipment, class choice and quests live here; the scenes and UI just call in.
@Observable
final class GameSession {
    /// Like Fairyland Online, a handful of companions; catch a sixth and one has to stay behind.
    static let maxPets = 5
    /// A newly caught companion waiting for room in a full party.
    var pendingPet: Pet?
    /// The adventurer you're standing next to (the HUD shows their card).
    var nearbyAdventurer: Adventurer?
    /// Everyone travelling together with them, whoever leads first (`Crowd.group`): just them on
    /// their own, no one with no one near.
    var nearbyGroup: [Adventurer] = []
    /// How many travel together with them, them among them: 1 on their own.
    var nearbyGroupSize: Int { max(1, nearbyGroup.count) }
    /// The adventurers' party you've joined (`askToJoin`), if any: you follow them about, and they
    /// fight beside you.
    var joinedParty: JoinedParty?
    /// Who said no to partying up lately, and till when they'd say no again (`askAlong`, `askToJoin`).
    @ObservationIgnored var declinedUntil: [UUID: Date] = [:]
    /// Guests who just left your party (`leaveParty`): gone from your list, but still about, so the
    /// map keeps them there for you to ask along again.
    @ObservationIgnored var partedGuests: [UUID: Adventurer] = [:]
    /// When the party you've joined heads off on its own (`passPartyTime`).
    @ObservationIgnored var joinedUntil: Date = .distantFuture
    /// Whether the weaver has a cape for you (`capesWaiting`), as of the last time a milestone could
    /// have been met (`checkTitles`) or a cape was woven: the "!" over her, without working out every
    /// cape's progress each frame.
    var capeReady = false
    /// Adventurers walking around near you on this map: only they can be invited along.
    var adventurersAround: Set<UUID> = []
    /// Up to four friends can travel with you, a party of five, each with their companion. (In a
    /// battle, friends take ids 2…5 and their companions 6…9, below the monsters' 10 and up.)
    static let maxAllies = 4

    var data: SaveData
    /// Name of the map the player is on, for the HUD.
    var mapName = ""
    /// NPC close enough to talk to, for the HUD's Talk button.
    var nearbyNPC: String?
    /// What you lost, lying near enough to pick up (`LostPile`), for the HUD's Pick up button.
    var nearbyPile: UUID?
    /// An adventurer's offer for something you've put up for trade, waiting for your answer
    /// (`GameSession+TradeList`).
    var pendingBid: Bid?
    /// The tile the hero stands on, for the minimap.
    var mapCell = GridPoint(col: 0, row: 0)
    /// Everyone else on this map, as dots on the minimap.
    var minimapDots: [MinimapDot] = []
    /// Who does what on this map, as icons on the minimap.
    var minimapMarks: [MinimapMark] = []

    /// Someone else on the minimap: an adventurer, a friend you've made, a red-named one looking for
    /// a fight, a friend in your party, or one of the folk who live there (villagers and locals).
    struct MinimapDot: Hashable {
        enum Kind { case adventurer, friend, hostile, party, folk }
        let cell: GridPoint
        let kind: Kind

        /// An adventurer's dot: red-named, in the party you've joined, a friend, or anyone.
        static func kind(of adventurer: Adventurer, friends: Set<UUID>, party: Set<UUID>) -> Kind {
            if adventurer.hostile { return .hostile }
            if party.contains(adventurer.id) { return .party }
            return friends.contains(adventurer.id) ? .friend : .adventurer
        }
    }

    /// Someone with a job, as an icon on the minimap (like RuneScape's): a quest giver (with a quest
    /// for you, or one to hand in), the healer, the shop, the smith, the weaver, a guild, a chest
    /// still to open, a boss still to beat, and a cave's stairs down or up.
    struct MinimapMark: Hashable {
        /// `lost`: what you lost when you fell, where it lies (`LostPile`).
        enum Kind { case quest, questNew, questReady, healer, shop, smith, weaver, barber, bank, guild, chest, boss, stairsDown, stairsUp, waystone, lost }
        let cell: GridPoint
        let kind: Kind
    }
    /// Recent system messages, shown Fairyland Online-style in the HUD.
    private(set) var log: [LogLine] = []
    /// When the game was last written to disk (the HUD flashes "Saved").
    private(set) var lastSaved: Date?

    struct LogLine: Identifiable {
        /// `announcement`: the game's own notices.
        enum Kind { case system, quest, battle, reward, announcement }
        let id = UUID()
        let text: String
        let kind: Kind
        let time = Date()
    }

    /// What people on this map have said: the Chat window. Starts over on each map, but for the
    /// game's announcements, which stay.
    struct ChatLine: Identifiable {
        /// `announcement`: the game's own notice of what's happening where and when
        /// (content/announcements.json). `notice`: what just happened to you (`post`: EXP won, an
        /// item found, a quest's step), shown a moment as a toast first, its `tone` its log line's.
        enum Kind { case you, adventurer, villager, npc, system, announcement, notice }
        let id = UUID()
        let speaker: String
        let text: String
        let kind: Kind
        /// BOT, next to the speaker's name.
        var badge: PlayerBadge? = nil
        /// A notice's kind of news (`LogLine.Kind`), for its colour.
        var tone: LogLine.Kind? = nil
        let time = Date()
    }

    private(set) var chat: [ChatLine] = []
    var unreadChat = 0

    func postChat(_ text: String, from speaker: String, kind: ChatLine.Kind) {
        // Adventurers are computer-run for now, and say so.
        let badge: PlayerBadge? = switch kind {
        case .adventurer: .bot
        case .you, .villager, .npc, .system, .announcement, .notice: nil
        }
        chat.append(ChatLine(speaker: speaker, text: text, kind: kind, badge: badge))
        if chat.count > 80 { chat.removeFirst(chat.count - 80) }
        if kind != .you { unreadChat += 1 }
    }

    func startChat(on mapName: String) {
        // The game's notices and what's happened to you lately stay; what people said starts over.
        let kept = chat.filter { $0.kind == .announcement || $0.kind == .notice }.suffix(20)
        chat = Array(kept) + [ChatLine(speaker: "", text: L("You entered {map}.", ["map": mapName]), kind: .system)]
        unreadChat = 0
    }

    /// One of the game's own notices: in the chat, set apart from what people say, and the message log.
    func announce(_ text: String) {
        postChat(text, from: "", kind: .announcement)
        post(text, .announcement)
    }

    /// A rare monster sighted somewhere (an announcement): it turns up `boost` times as often on that
    /// map until `until`.
    struct Sighting {
        let mapID: String
        let monsterID: String
        let boost: Int
        let until: Date
    }

    @ObservationIgnored var sighting: Sighting?

    /// Something that just happened (`LogLine`): a toast on the map for a few seconds (`WorldHUD`),
    /// then kept in the chat (playtesting 2026-10-24: it piled up in the top-left corner). Seen as it
    /// toasts, so it doesn't count as unread; an announcement is in the chat already (`announce`).
    /// `toast: false` for what a window has just shown (a battle's pay, on its result card): only
    /// the chat keeps it (playtesting 2026-10-24).
    func post(_ text: String, _ kind: LogLine.Kind = .system, toast: Bool = true) {
        if toast {
            log.append(LogLine(text: text, kind: kind))
            if log.count > 12 { log.removeFirst(log.count - 12) }
        }
        guard kind != .announcement else { return }
        chat.append(ChatLine(speaker: "", text: text, kind: .notice, tone: kind))
        if chat.count > 80 { chat.removeFirst(chat.count - 80) }
    }
    /// Last known position on the current map (saved with the game).
    @ObservationIgnored var playerPosition: CGPoint?
    /// Set by the game while you're on a map: casts a field spell like Bridge of Light. Nil on the
    /// title screen and in tests, where there's nowhere to go.
    @ObservationIgnored var onCastField: ((SkillDef) -> Void)?
    /// The same for a travel item from the bag (a Homeward Feather).
    @ObservationIgnored var onTravel: ((ItemDef) -> Void)?

    var content: Content { .shared }

    init(data: SaveData) {
        self.data = data
        if let position = data.position, position.count == 2 {
            playerPosition = CGPoint(x: position[0], y: position[1])
        }
        if self.data.hero.learnedSkills == nil {
            // Older saves learned skills automatically; keep them, and don't charge for them.
            let legacy = classSkills(upTo: data.hero.level).map(\.id)
            self.data.hero.learnedSkills = legacy
            self.data.hero.bonusSkillPoints = legacy.count
        }
        Self.moveGearToItsSlot(&self.data)
        stockBankOnce()
        returnBankedGold()
        fitBag()
        deliverQuestTreasures()
        applyLook()
    }

    /// Quest treasures you're owed: a quest finished before it gave its treasure (an older save)
    /// sends it now, once, with a note from whoever gave the quest. What came.
    @discardableResult
    func deliverQuestTreasures() -> [ItemDef] {
        var given = Set(data.questTreasuresGiven ?? [])
        var sent: [ItemDef] = []
        for quest in content.quests where data.quests[quest.id]?.state == .completed {
            for id in quest.reward.items ?? [] where content.isQuestTreasure(id) && !given.contains(id) {
                // Not while the bag is full: it waits, and comes once there's room.
                guard let item = content.item(id), hasRoom(for: [id]) else { continue }
                addItem(id)
                given.insert(id)
                sent.append(item)
                let giver = content.npc(quest.giver)?.name ?? quest.giver
                post(L("{giver} sends you {item}, for “{quest}”.", ["giver": giver, "item": item.name, "quest": quest.title]), .reward)
            }
        }
        data.questTreasuresGiven = given.sorted()
        return sent
    }

    /// Gear worn in a slot that isn't its own goes where it belongs: Speed Boots were an accessory
    /// before boots had a slot. If that slot is taken, it goes back in the bag.
    static func moveGearToItsSlot(_ data: inout SaveData) {
        for slot in ItemType.equipmentSlots {
            guard let id = data.hero.equipment[slot], let item = Content.shared.item(id), item.type != slot else { continue }
            data.hero.equipment[slot] = nil
            if ItemType.equipmentSlots.contains(item.type), data.hero.equipment[item.type] == nil {
                data.hero.equipment[item.type] = id
            } else {
                data.inventory[id, default: 0] += 1
            }
        }
    }

    static func newGame(name: String, raceID: String, look: Look = .standard) -> GameSession {
        let content = Content.shared
        let hero = Hero(
            name: name, raceID: raceID, classID: "novice", level: 1, exp: 0, hp: 1, mp: 0,
            equipment: Equipment(armor: "cloth_tunic"), look: look
        )
        let data = SaveData(
            hero: hero, pets: [], activePetID: nil, gold: 30, inventory: ["potion": 3],
            quests: [:], mapID: content.startMap, position: nil, startedAt: Date()
        )
        var slotted = data
        slotted.slot = UUID().uuidString   // every new game gets its own save
        slotted.skillLevelsDoubled = true  // already on the 10-step skill scale
        slotted.levelsRescaled = true      // and on the 200-level scale (a debug level isn't stretched)
        slotted.giftDay = GameSession.dayKey()  // the first daily gift is tomorrow's: today has the story and the tour
        slotted.bankStocked = true         // nothing to put in the bank: a new game starts with it
        let session = GameSession(data: slotted)
        session.restoreHero()
        // Like Fairyland Online, your first companion comes from an egg in the first quest.
        return session
    }

    func save() {
        guard !isDeleted else { return }
        data.position = playerPosition.map { [Double($0.x), Double($0.y)] }
        if !seen.isEmpty { data.explored = (data.explored ?? [:]).merging(seen) { $1 } }
        tidyItemOrders()
        data.savedAt = Date()
        SaveStore.save(data)
        lastSaved = Date()
    }

    /// Set once the game is deleted, so a late autosave can't bring it back.
    private(set) var isDeleted = false

    /// Deletes this game's save for good (Settings → Danger zone).
    func deleteGame() {
        isDeleted = true
        if let slot = data.slot { SaveStore.delete(slot: slot) }
    }

    // MARK: - Looks

    /// Art id of the hero as customised: a recoloured copy of player_walk.
    static let heroArt = "hero"

    /// A whole sheet's colours (other adventurers; the hero's hood or helmet). Worn armour takes
    /// over the outfit's colours (leather, steel, silk…).
    static func rules(for look: Look, armor: ItemDef? = nil) -> [RecolorRule] {
        let options = Content.shared.appearance
        let skin: [RecolorRule] = options.skin.first { $0.id == look.skin }?.recolor ?? []
        let hair: [RecolorRule] = options.hair.first { $0.id == look.hair }?.recolor ?? []
        // Skin first (pale), then hair (saturated), then outfit (green): they never overlap.
        return skin + hair + outfitRules(for: look, armor: armor)
    }

    private static func outfitRules(for look: Look, armor: ItemDef?) -> [RecolorRule] {
        if let worn = armor?.recolor, !worn.isEmpty { return worn }
        return Content.shared.appearance.outfits.first { $0.id == look.outfit }?.recolor ?? []
    }

    /// The bald body's colours: skin and outfit. Its hair is on the hair and locks layers, so a dye
    /// leaves the rest alone (ginger boots and belts keep their colour).
    static func bodyRules(for look: Look, armor: ItemDef? = nil) -> [RecolorRule] {
        let skin: [RecolorRule] = Content.shared.appearance.skin.first { $0.id == look.skin }?.recolor ?? []
        return skin + outfitRules(for: look, armor: armor)
    }

    /// The hair and locks layers hold nothing but hair, so the hair colour's rules widen to the
    /// `hairLayer` window there: every shade of the ginger takes the colour, down to the deep red
    /// shadows and the pale tips. The outfit's rules follow for a collar showing through.
    static func hairLayerRules(for look: Look, armor: ItemDef? = nil) -> [RecolorRule] {
        let options = Content.shared.appearance
        var hair: [RecolorRule] = options.hair.first { $0.id == look.hair }?.recolor ?? []
        if let window = options.hairLayer {
            hair = hair.map { $0.within(window) }
        }
        return hair + outfitRules(for: look, armor: armor)
    }

    /// The hairstyle a hero wears: their pick, else their walk sheet's own hair (a gender's: a
    /// ponytail, braids), else their race's.
    static func style(for look: Look, race: RaceDef) -> String {
        let styles = Content.shared.appearance.styles(for: race.sheet(for: look.gender))
        if let picked = look.style, styles.contains(where: { $0.id == picked }) { return picked }
        if let own = styles.first(where: { $0.sheet == race.sheet(for: look.gender) }) { return own.id }
        return race.hair ?? styles.first?.id ?? "spiky"
    }

    /// The hero as paper-doll layers (art/sprites, made by tools/hero_layers.py): the bald body, the
    /// locks it keeps (a beard), then the hairstyle. Locks and hair take the hair colour on every
    /// shade; the body only skin and outfit. Armour with its own walk sheet for the race (items.json
    /// `sheets`) takes the body's place, its head cut off (`bareHead`) and the hero's own over it.
    /// On the head, `hat`: a festive one sits on the hair (GearOverlay.hat). One that goes with an
    /// armour (`headgear`) takes the hair's place: an armour sheet's helmet, hood or coif
    /// (`hat_<kind>_<race>`, in the skin tone and its tint) over the hair from a fifth of the way down
    /// the head (`nape_*`), so long hair, a ponytail or braids show below it, the beard on top; or a
    /// hide cloak's hood (`hood_*`, painted in its colour by GearOverlay.hood). Under the helmet the
    /// head lies over the nape, as it should facing you or side on; from behind its back view
    /// (`napeback_*`) goes over the head, or a band of scalp showed below the helmet (playtesting
    /// 2026-10-24).
    static func layers(race: RaceDef, look: Look, armor: ItemDef? = nil, hat: ItemDef? = nil) -> [ArtLayer] {
        let style = Self.style(for: look, race: race)
        let body = Self.body(race: race, look: look)
        let hair = hairLayerRules(for: look, armor: armor)
        let skin = Content.shared.appearance.skin.first { $0.id == look.skin }?.recolor ?? []
        let locks = ArtLayer(id: "locks_\(body)", recolor: hair)
        // What's on the head, and the hair still showing below it.
        var under: [ArtLayer] = []
        var back: [ArtLayer] = []
        var top = [locks, ArtLayer(id: "hair_\(style)_\(body)", recolor: hair)]
        if let kind = hat?.headgear {
            if kind == "hood" {
                top = [locks, ArtLayer(id: "hood_\(body)", recolor: [])]
            } else {
                under = [ArtLayer(id: "nape_\(style)_\(body)", recolor: hair)]
                back = [ArtLayer(id: "napeback_\(style)_\(body)", recolor: hair)]
                top = [ArtLayer(id: "hat_\(kind)_\(race.id)", recolor: skin + (hat?.tint ?? [])), locks]
            }
        }
        if let sheet = armor?.sheets?[race.id] {
            // Its head is cut off: the hero's own over it, in their skin tone.
            if armor?.bareHead == true {
                return under + [ArtLayer(id: sheet), ArtLayer(id: "head_\(body)", recolor: skin)] + back + top
            }
            return [ArtLayer(id: "nape_\(style)_\(body)", recolor: hair), ArtLayer(id: sheet)]
        }
        return under + [ArtLayer(id: "body_\(body)", recolor: bodyRules(for: look, armor: armor))] + back + top
    }

    /// Which of the paper-doll bodies a hero wears: each gender's walk sheet has its own set, and the
    /// race's default sheet keeps the plain names (body_elf, body_elf_male).
    static func body(race: RaceDef, look: Look) -> String {
        look.gender.flatMap { race.sheets?[$0] != nil ? "\(race.id)_\($0)" : nil } ?? race.id
    }

    func equipped(_ slot: ItemType) -> ItemDef? {
        data.hero.equipment[slot].flatMap(content.item)
    }

    /// Changes whenever the hero's sprite should be redrawn (look, race or gear).
    var heroLookKey: String { Self.lookKey(for: data.hero) }

    static func lookKey(for hero: Hero) -> String {
        let gear = ItemType.equipmentSlots.map { hero.equipment[$0] ?? "-" }.joined(separator: ",")
        let look = hero.look ?? .standard
        return "\(Content.shared.race(hero.raceID).sheet(for: look.gender))/\(look.key)/\(gear)"
    }

    func applyLook() {
        Self.registerHero(data.hero, as: Self.heroArt)
    }

    /// Draws a hero exactly as the game shows them (race, gender, hairstyle, colours, worn gear)
    /// under the art id `id`: the hero in play, or a saved hero on the title screen.
    static func registerHero(_ hero: Hero, as id: String) {
        let content = Content.shared
        registerArt(id, race: content.race(hero.raceID), look: hero.look ?? .standard,
                    armor: hero.equipment[.armor].flatMap(content.item),
                    worn: [ItemType.gloves, .boots, .necklace, .head].compactMap { hero.equipment[$0].flatMap(content.item) },
                    cape: hero.equipment[.cape].flatMap(content.item), key: Self.lookKey(for: hero))
    }

    /// Draws someone of `race` in `look` under the art id `id`: the hero, or another adventurer. Worn
    /// armour takes over the outfit's colours and adds its cut (or brings its own walk sheet); gloves,
    /// boots and a necklace (`worn`) show in their colours. A status cape hangs on their back, and a
    /// festive hat (`worn` too) sits on their head, over everything.
    private static func registerArt(_ id: String, race: RaceDef, look: Look, armor: ItemDef?, worn: [ItemDef] = [],
                                    cape: ItemDef? = nil, key: String) {
        let necklace = worn.first { $0.type == .necklace }
        // A festive scarf is worn as a necklace, drawn round the neck instead of a pendant.
        let scarf = necklace?.wear == "scarf" ? necklace : nil
        let pendant = scarf == nil ? necklace : nil
        let hat = worn.first { $0.type == .head }
        // A festive hat is fitted to the head; a hood that goes with a hide cloak is painted in its colour.
        let festive = hat?.headgear == nil ? hat : nil
        let hood = hat?.headgear == "hood" ? hat : nil
        var gear = GearLook(wear: armor?.wear, accent: armor?.accent, pattern: armor?.pattern,
                            cape: cape?.color, capeTrim: cape?.accent, cloak: armor?.wear == "cloak" ? armor?.color : nil,
                            gloves: worn.first { $0.type == .gloves }?.color, boots: worn.first { $0.type == .boots }?.color,
                            necklace: pendant?.color, chain: pendant?.accent,
                            hat: festive?.hat, hatColor: festive?.color, hatTrim: festive?.accent,
                            scarf: scarf?.color, hood: hood?.color, hoodTrim: hood?.accent, hoodFur: hood?.pattern == "fur",
                            body: "body_\(Self.body(race: race, look: look))")
        var rules = Self.rules(for: look, armor: armor)
        if let armor, armor.sheets?[race.id] != nil {
            // The armour's own sheet is already drawn and coloured: only the skin tone applies, plus a
            // rare colour variant's tint. It's drawn on the race's own body, poses and all.
            gear.wear = nil
            gear.accent = nil
            gear.pattern = nil
            gear.cloak = nil
            gear.body = "body_\(race.id)"
            rules = (Content.shared.appearance.skin.first { $0.id == look.skin }?.recolor ?? []) + (armor.tint ?? [])
        }
        ArtLibrary.shared.register(id, from: race.sheet(for: look.gender), recolor: rules, key: key,
                                   gear: gear, layers: Self.layers(race: race, look: look, armor: armor, hat: hat))
    }

    /// A companion looks like its species; colourful ones are rarer variants you catch.
    func artID(for pet: Pet) -> String {
        species(of: pet)?.art ?? ""
    }

    func renamePet(_ id: UUID, to name: String) {
        guard let index = data.pets.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        data.pets[index].name = String(trimmed.prefix(12))
        post(L("{pet} loves the new name!", ["pet": data.pets[index].name]), .reward)
        save()
    }

    // MARK: - Hero

    var heroRace: RaceDef { content.race(data.hero.raceID) }
    var heroClass: ClassDef { content.classDef(data.hero.classID) }

    var heroStats: Stats {
        heroRace.base + heroClass.growth * (data.hero.level - 1) + equipmentBonus + cardBonus
    }

    // MARK: - Levels
    //
    // Like Fairyland Online, levels go to 200. There's no rebirth (playtesting 2026-10-17: "The
    // limit is just level 200"): the Goldleaf gear Elder Oak gives at 200 is the prize at the top.

    static let levelCap = 200

    /// Rebirth was taken out in 0.7.27. A hero reborn before then is put back at the level their
    /// last rebirth started from (101, and 5 more for each earlier one), with the skills they'd
    /// learned, and the rebirth titles go.
    func retireRebirthsIfNeeded() {
        guard let rebirths = data.hero.rebirths else { return }
        data.hero.rebirths = nil
        let retired: Set<String> = ["reborn", "twice_reborn", "phoenix"]
        data.titles = data.titles?.filter { !retired.contains($0) }
        if let title = data.title, retired.contains(title) { data.title = nil }
        guard rebirths > 0 else { save(); return }
        let level = min(Self.levelCap, 101 + 5 * (rebirths - 1))
        if data.hero.level < level {
            data.hero.level = level
            data.hero.exp = 0
        }
        restoreHero()
        post(L("Rebirth is gone from Dorlune: you're back at level {level}, where your rebirth began.", ["level": data.hero.level]), .reward)
        checkTitles(quietly: true)
        save()
    }

    /// A new hairstyle and hair colour at a barber (`NPCRole.barber`), for `price` gold: only the
    /// hair changes, the rest of the look stays as the hero was made. False if the gold isn't there.
    func restyle(_ look: Look, price: Int) -> Bool {
        guard data.gold >= price else { return false }
        var restyled = data.hero.look ?? .standard
        restyled.hair = look.hair
        restyled.style = look.style
        data.gold -= price
        data.hero.look = restyled
        applyLook()
        save()
        return true
    }

    /// Since 0.7.59 an armour's helmet, hood or coif is a hat of its own (items.json `headpiece`),
    /// worth a quarter of what the armour was (playtesting 2026-10-21: "any armor that shows a hat
    /// should have that as a hat item"). A save from before gets the hat of every such armour it has,
    /// and the one it wears goes on its head if nothing's there, so no one loses a thing.
    func handOutArmourHatsIfNeeded() {
        guard data.armourHatsGiven != true else { return }
        data.armourHatsGiven = true
        var given = 0
        for (id, count) in data.inventory where count > 0 {
            guard let hat = content.item(id)?.headpiece else { continue }
            addItem(hat, count, force: true)
            given += count
        }
        if let hat = data.hero.equipment[.armor].flatMap(content.item)?.headpiece {
            if data.hero.equipment[.head] == nil { data.hero.equipment[.head] = hat } else { addItem(hat, force: true) }
            given += 1
            applyLook()
        }
        if given > 0 { post(L("Helmets and hoods are hats of their own now: yours are in your bag, or on your head."), .reward) }
        save()
    }

    /// Maps a level from before the stretch (monsters topped out at 32) onto today's 1–105.
    static func stretchedLevel(_ old: Int) -> Int {
        max(1, Int((1 + Double(old - 1) * 104 / 31).rounded()))
    }

    /// Skills used to master at level 5; now it takes 10. Older saves keep their progress: a skill
    /// at level L becomes 2L (level 1 stays 1), so a mastered skill is still mastered.
    func rescaleSkillLevelsIfNeeded() {
        guard data.skillLevelsDoubled != true else { return }
        data.skillLevelsDoubled = true
        guard var levels = data.hero.skillLevels else { return }
        for (id, level) in levels where level > 1 {
            levels[id] = min(Self.maxSkillLevel, level * 2)
        }
        data.hero.skillLevels = levels
    }

    func rescaleLevelsIfNeeded() {
        guard data.levelsRescaled != true else { return }
        data.levelsRescaled = true
        guard data.hero.level > 1 || data.pets.contains(where: { $0.level > 1 }) else { return }
        data.hero.level = Self.stretchedLevel(data.hero.level)
        data.hero.exp = 0
        for index in data.pets.indices {
            data.pets[index].level = Self.stretchedLevel(data.pets[index].level)
            data.pets[index].exp = 0
            let stats = stats(of: data.pets[index])
            data.pets[index].hp = stats.hp
            data.pets[index].mp = stats.mp
        }
        // Read first, then write: `data.friends?[i].level = f(data…)` reads `data` while the
        // optional-chained write already holds it, which Swift's exclusivity check aborts on.
        if var friends = data.friends {
            for index in friends.indices {
                friends[index].level = Self.stretchedLevel(friends[index].level)
            }
            data.friends = friends
        }
        restoreHero()
        post(L("The world grew bigger! You're now level {level}.", ["level": data.hero.level]), .reward)
    }

    var equipmentBonus: Stats {
        ItemType.equipmentSlots
            .compactMap { data.hero.equipment[$0] }
            .compactMap { content.item($0)?.stats }
            .reduce(Stats.zero, +)
    }

    // MARK: - Skills
    //
    // Every level gives a skill point. Your class unlocks new skills at milestone levels;
    // a point either learns one of those or raises a skill you know (up to level 10).

    /// Skills you've learned that your current class uses.
    /// The skills you've learned, in your order (`skillOrder`, set on the Skills page: playtesting
    /// 2026-10-30, "so you can decide which ones are one tap"), the battle row's from More rightward
    /// (what it has no room for waits behind More); ones you haven't placed after, in your class's order.
    var heroSkills: [SkillDef] {
        let learned = Set(data.hero.learnedSkills ?? [])
        return Self.ordered(classSkills(upTo: data.hero.level).filter { learned.contains($0.id) }, by: data.skillOrder)
    }

    /// `skills` in `order`, those it doesn't have after, as they came.
    static func ordered(_ skills: [SkillDef], by order: [String]?) -> [SkillDef] {
        guard let order else { return skills }
        let place = Dictionary(order.enumerated().map { ($0.element, $0.offset) }) { first, _ in first }
        return skills.enumerated()
            .sorted { (place[$0.element.id] ?? order.count + $0.offset, $0.offset) < (place[$1.element.id] ?? order.count + $1.offset, $1.offset) }
            .map(\.element)
    }

    /// `order` with `id` put where `target` is, the rest shifting along; nil when either isn't in
    /// it, or they're the same.
    private static func moved(_ id: String, onto target: String, in order: [String]) -> [String]? {
        var order = order
        guard id != target, let from = order.firstIndex(of: id), let to = order.firstIndex(of: target) else { return nil }
        order.remove(at: from)
        order.insert(id, at: to)
        return order
    }

    /// A companion's skills, its species', in your order of them (the Companions page: playtesting
    /// 2026-10-30, "Same for the companion"), as its battle row shows them.
    func skills(of pet: Pet) -> [SkillDef] {
        Self.ordered(species(of: pet)?.skills.compactMap { content.skill($0) } ?? [], by: pet.skillOrder)
    }

    /// Puts a companion's skill `id` where `target` is in its order. False when either isn't one it
    /// has, or they're the same.
    @discardableResult
    func moveSkill(_ id: String, onto target: String, of petID: UUID) -> Bool {
        guard let index = data.pets.firstIndex(where: { $0.id == petID }),
              let order = Self.moved(id, onto: target, in: skills(of: data.pets[index]).map(\.id)) else { return false }
        data.pets[index].skillOrder = order
        SoundEffects.shared.play(.tap, volume: 0.7)
        return true
    }

    /// Puts skill `id` where `target` is in your order, the rest shifting along. False when either
    /// isn't one you know, or they're the same.
    @discardableResult
    func moveSkill(_ id: String, onto target: String) -> Bool {
        guard let order = Self.moved(id, onto: target, in: heroSkills.map(\.id)) else { return false }
        data.skillOrder = order
        SoundEffects.shared.play(.tap, volume: 0.7)
        return true
    }

    // MARK: - Battle buttons

    /// In `battleButtons`, everything after this sits in the More menu.
    static let moreDivider = "more"
    /// No Skills: each skill is a button of its own in the row, between More and the rest
    /// (BattleView's `SkillRow`), so they aren't moved about with these.
    static let defaultBattleButtons = ["attack", "capture", moreDivider, "items", "guard", "run"]

    /// The battle buttons in your order: the first is the big one, those after `moreDivider` wait
    /// in the More menu. Only real commands: older saves can hold skills once pinned there
    /// ("skill:<id>"), and the Skills button that opened a list of them ("skills").
    var battleButtons: [String] {
        var order = (data.battleButtons ?? Self.defaultBattleButtons).filter { Self.defaultBattleButtons.contains($0) }
        for command in Self.defaultBattleButtons where !order.contains(command) { order.append(command) }
        return order
    }

    /// Skills your class offers at your level that you haven't learned yet.
    var learnableSkills: [SkillDef] {
        let learned = Set(data.hero.learnedSkills ?? [])
        return classSkills(upTo: data.hero.level).filter { !learned.contains($0.id) }
    }

    /// The next skill your class unlocks at a higher level.
    var nextSkillUnlock: (skill: SkillDef, level: Int)? {
        heroClass.skills.filter { $0.level > data.hero.level }.min { $0.level < $1.level }
            .flatMap { unlock in content.skill(unlock.skill).map { ($0, unlock.level) } }
    }

    private func classSkills(upTo level: Int) -> [SkillDef] {
        heroClass.skills.filter { $0.level <= level }.compactMap { content.skill($0.skill) }
    }

    /// "No skills yet" plus what to do about it.
    var skillHint: String {
        if let skill = learnableSkills.first { return L("No skills yet.\nSpend your skill point to learn {skill}.", ["skill": skill.name]) }
        if let next = nextSkillUnlock { return L("No skills yet.\nYou can learn {skill} at level {level}.", ["skill": next.skill.name, "level": next.level]) }
        return L("No skills yet.")
    }

    /// Ten steps from learning a skill to mastering it.
    static let maxSkillLevel = 10
    /// Past mastery your hero's skills keep growing, a little stronger every level and grander in
    /// battle at every ten (`skillRank`), up to 50 (playtesting 2026-10-23: "you should be able to
    /// continuously improve these skills"). Monsters', companions' and friends' stop at mastery.
    static let skillLevelCap = 50

    /// The milestone a skill has reached: 0 before mastery, then one for every ten levels, from
    /// 1 (Mastered, 10) to 5 (Legendary, 50).
    static func skillRank(_ level: Int) -> Int { min(5, max(0, level / 10)) }

    static func skillRankName(_ rank: Int) -> String? {
        switch rank {
        case 1: L("Mastered")
        case 2: L("Heroic")
        case 3: L("Epic")
        case 4: L("Mythic")
        case 5: L("Legendary")
        default: nil
        }
    }

    func skillLevel(_ id: String) -> Int {
        max(1, data.hero.skillLevels?[id] ?? 1)
    }

    /// A point to spend and something to spend it on: a skill to learn, or one not yet at its cap.
    var canSpendSkillPoint: Bool {
        unspentSkillPoints > 0
            && (!learnableSkills.isEmpty || heroSkills.contains { skillLevel($0.id) < Self.skillLevelCap })
    }

    /// One point per level gained. Learning costs one and each upgrade one; points in skills
    /// your class no longer has come back.
    var unspentSkillPoints: Int {
        let spent = heroSkills.reduce(0) { $0 + skillLevel($1.id) }
        return max(0, data.hero.level - 1 + (data.hero.bonusSkillPoints ?? 0) - spent)
    }

    func learnSkill(_ id: String) {
        guard unspentSkillPoints > 0, let skill = learnableSkills.first(where: { $0.id == id }) else { return }
        SoundEffects.shared.play(.learn)
        data.hero.learnedSkills = (data.hero.learnedSkills ?? []) + [id]
        var levels = data.hero.skillLevels ?? [:]
        levels[id] = 1
        data.hero.skillLevels = levels
        post(L("You learned {skill}!", ["skill": skill.name]), .reward)
    }

    func upgradeSkill(_ id: String) {
        guard unspentSkillPoints > 0, heroSkills.contains(where: { $0.id == id }), skillLevel(id) < Self.skillLevelCap else { return }
        var levels = data.hero.skillLevels ?? [:]
        levels[id] = skillLevel(id) + 1
        data.hero.skillLevels = levels
    }

    /// Higher skill levels hit harder and cost a little more: a point a level to mastery, then a
    /// point every five.
    static func mpCost(of skill: SkillDef, level: Int) -> Int {
        skill.mp + min(level, maxSkillLevel) - 1 + max(0, level - maxSkillLevel) / 5
    }

    var canChooseClass: Bool {
        data.hero.classID == "novice" && data.hero.level >= content.classChoiceLevel
    }

    /// EXP for the next level. Past 100 it climbs faster, like Fairyland Online's slow late game:
    /// twice the old amount by level 140 and 3.5 times by 200.
    static func expToNext(level: Int) -> Int {
        let base = 10 + level * level * 5
        guard level > 100 else { return base }
        return Int((Double(base) * (1 + Double(level - 100) / 40)).rounded())
    }

    func restoreHero() {
        let stats = heroStats
        data.hero.hp = stats.hp
        data.hero.mp = stats.mp
    }

    /// Adds EXP and returns how many levels the hero gained.
    @discardableResult
    func gainHeroEXP(_ amount: Int) -> Int {
        guard amount > 0 else { return 0 }
        guard data.hero.level < Self.levelCap else { return 0 }
        data.hero.exp += amount
        var levels = 0
        while data.hero.level < Self.levelCap, data.hero.exp >= Self.expToNext(level: data.hero.level) {
            data.hero.exp -= Self.expToNext(level: data.hero.level)
            data.hero.level += 1
            levels += 1
        }
        if levels > 0 { restoreHero() }
        return levels
    }

    func chooseClass(_ id: String) {
        guard canChooseClass, content.classes.contains(where: { $0.id == id }) else { return }
        data.hero.classID = id
        SoundEffects.shared.play(.levelUp)
        Haptics.success()
        post(L("You joined the {guild} as a {className}!", ["guild": content.classDef(id).guild ?? L("guild"), "className": content.classDef(id).name]), .reward)
        // Gear the new class can't use goes back into the bag.
        for slot in ItemType.equipmentSlots {
            if let itemID = data.hero.equipment[slot], let item = content.item(itemID), equipIssue(item) != nil {
                unequip(slot)
            }
        }
        restoreHero()
    }

    func clampHero() {
        let stats = heroStats
        data.hero.hp = min(data.hero.hp, stats.hp)
        data.hero.mp = min(data.hero.mp, stats.mp)
    }

    // MARK: - Companions

    var activePet: Pet? { data.pets.first { $0.id == data.activePetID } }

    func species(of pet: Pet) -> MonsterDef? { content.monster(pet.speciesID) }

    /// Its species at its level, and what its toys have added.
    func stats(of pet: Pet) -> Stats {
        guard let species = species(of: pet) else { return .zero }
        return species.stats(at: pet.level) + (pet.toyStats ?? .zero)
    }

    func makePet(species id: String, level: Int, name: String? = nil) -> Pet? {
        guard let species = content.monster(id) else { return nil }
        let stats = species.stats(at: level)
        return Pet(id: UUID(), speciesID: id, name: name ?? species.name, level: level, exp: 0, hp: stats.hp, mp: stats.mp)
    }

    @discardableResult
    func addPet(_ pet: Pet, countsForQuests: Bool = true) -> Bool {
        guard data.pets.count < Self.maxPets else { return false }
        data.pets.append(pet)
        if data.activePetID == nil { data.activePetID = pet.id }
        if countsForQuests { record(.capture, target: pet.speciesID) }
        checkTitles()
        return true
    }

    // MARK: - Exploring dark maps

    /// Cells seen on dark maps since the last save, kept out of `data` so exploring doesn't redraw
    /// everything that shows the save; `save()` writes them in.
    @ObservationIgnored private var seen: [String: Data] = [:]
    /// Goes up whenever you see somewhere new on a dark map, so the minimap redraws.
    private(set) var exploredVersion = 0

    /// The cells you've seen on a dark map, one bit each (`SaveData.explored`).
    func explored(_ mapID: String) -> Data? { seen[mapID] ?? data.explored?[mapID] }

    /// Marks cells of a dark map as seen. Returns true if any of them is new.
    @discardableResult
    func explore(_ cells: [GridPoint], on mapID: String, columns: Int, rows: Int) -> Bool {
        let size = (columns * rows + 7) / 8
        var bits = explored(mapID) ?? Data()
        // A map that changed size since: start afresh.
        if bits.count != size { bits = Data(count: size) }
        var fresh = false
        for cell in cells where cell.col >= 0 && cell.row >= 0 && cell.col < columns && cell.row < rows {
            let index = cell.row * columns + cell.col
            let mask = UInt8(1 << (index % 8))
            if bits[index / 8] & mask == 0 {
                bits[index / 8] |= mask
                fresh = true
            }
        }
        guard fresh else { return false }
        seen[mapID] = bits
        exploredVersion += 1
        return true
    }

    // MARK: - Friends & party

    /// The adventurers you've befriended (not the guests in your party).
    var friends: [Adventurer] { (data.friends ?? []).filter { $0.guest != true } }

    /// Everyone in your party, friends and guests (`Adventurer.guest`).
    var partyMembers: [Adventurer] {
        (data.partyIDs ?? []).compactMap { id in data.friends?.first { $0.id == id } }
    }

    /// Who's in your party without being your friend.
    var partyGuests: [Adventurer] { partyMembers.filter { $0.guest == true } }

    /// The friends in your party who are with you, not waiting somewhere for you to come back for
    /// them: they walk and fight beside you.
    var friendsAtYourSide: [Adventurer] { partyMembers.filter { $0.waitingAt == nil } }

    /// How strong your side is in a fight, as the levels of everyone who'd stand with you added up:
    /// you, your companion while it's up, and everyone fighting beside you with theirs (a step below
    /// their own level, as they fight).
    var partyStrength: Int {
        let companion = activePet.map { $0.hp > 0 ? $0.level : 0 } ?? 0
        return data.hero.level + companion + fightersAtYourSide.map(Self.strength).reduce(0, +)
    }

    /// An adventurer's strength with their companion, the same way.
    static func strength(of adventurer: Adventurer) -> Int {
        adventurer.level + (adventurer.petSpecies == nil ? 0 : max(1, adventurer.level - 1))
    }

    /// Whether a red-named troublemaker dares pick a fight with you: only one about as strong as
    /// your side or stronger (nine tenths of it, with their companion). Much stronger, or with a
    /// party that's more than a match together, and they leave you be.
    func dares(_ rival: Adventurer) -> Bool {
        Self.strength(of: rival) * 10 >= partyStrength * 9
    }

    func isFriend(_ adventurer: Adventurer) -> Bool { friends.contains { $0.id == adventurer.id } }
    func isInParty(_ adventurer: Adventurer) -> Bool { data.partyIDs?.contains(adventurer.id) == true }

    /// Most adventurers are happy to be friends; the grumpy red-named ones aren't. A guest in your
    /// party becomes a friend, and stays one after they leave it.
    @discardableResult
    func befriend(_ adventurer: Adventurer) -> Bool {
        guard !isFriend(adventurer), !adventurer.hostile else { return false }
        if let index = data.friends?.firstIndex(where: { $0.id == adventurer.id }) {
            data.friends?[index].guest = nil
        } else {
            var friend = adventurer
            friend.hostile = false
            data.friends = (data.friends ?? []) + [friend]
        }
        post(L("{name} is now your friend!", ["name": adventurer.name]), .reward)
        checkTitles()
        save()
        return true
    }

    /// Brings `id` into your party: a friend, or anyone else about (`met`, as you met them), who comes
    /// along as a guest (`Adventurer.guest`): you don't have to be friends to party up (playtesting
    /// 2026-10-26: "I shouldn't need to befriend someone to invite them to my party").
    func invite(_ id: UUID, met: Adventurer? = nil) {
        guard data.partyIDs?.contains(id) != true, !partyIsFull, adventurersAround.contains(id) else { return }
        if data.friends?.contains(where: { $0.id == id }) != true {
            guard var guest = met, guest.id == id, !guest.hostile else { return }
            guest.guest = true
            guest.waitingAt = nil
            data.friends = (data.friends ?? []) + [guest]
        }
        guard let friend = data.friends?.first(where: { $0.id == id }) else { return }
        // Friends keep up with you, and save where you last did. Read first, then write: the right
        // side of an optional-chained write runs while the write holds `data`, so reading `data`
        // there (`checkpoint` does) trips Swift's exclusivity check and the game aborts.
        let level = max(friend.level, data.hero.level - 1)
        let saved = checkpoint
        if let index = data.friends?.firstIndex(where: { $0.id == id }) {
            data.friends?[index].level = level
            data.friends?[index].waitingAt = nil
            data.friends?[index].checkpoint = saved
        }
        data.partyIDs = (data.partyIDs ?? []) + [id]
        var leaves = data.partyLeaves ?? [:]
        leaves[id.uuidString] = Date().addingTimeInterval(stayLength())
        data.partyLeaves = leaves
        post(L("{name} joined your party!", ["name": friend.name]), .reward)
        save()
    }

    func leaveParty(_ id: UUID) {
        guard let friend = data.friends?.first(where: { $0.id == id }) else { return }
        data.partyIDs?.removeAll { $0 == id }
        data.partyLeaves?[id.uuidString] = nil
        if let index = data.friends?.firstIndex(where: { $0.id == id }) {
            data.friends?[index].waitingAt = nil
        }
        if friend.guest == true {
            // Not a friend: gone from your list, still about to ask along again.
            data.friends?.removeAll { $0.id == id }
            var parted = friend
            parted.guest = nil
            parted.waitingAt = nil
            partedGuests[id] = parted
        }
        post(L("{name} left the party. See you around!", ["name": friend.name]))
        save()
    }

    /// A friend who was waiting for you: you've found them, and off you go together again.
    func rejoin(_ id: UUID) {
        guard let index = data.friends?.firstIndex(where: { $0.id == id }), let friend = data.friends?[index],
              friend.waitingAt != nil else { return }
        data.friends?[index].waitingAt = nil
        post(L("{name} is back with you!", ["name": friend.name]), .reward)
        save()
    }

    /// Where a friend in your party is waiting for you ("the Sunny Meadow entrance", "Meadowbrook"),
    /// or nil while they're at your side.
    func whereabouts(of friend: Adventurer) -> String? {
        guard let spot = data.friends?.first(where: { $0.id == friend.id })?.waitingAt else { return nil }
        if spot.position == nil { return checkpointName(Checkpoint(mapID: spot.mapID, entry: spot.entry)) }
        return content.map(spot.mapID)?.name ?? L("somewhere")
    }

    func unfriend(_ id: UUID) {
        leaveParty(id)
        data.friends?.removeAll { $0.id == id }
        save()
    }

    func stats(of adventurer: Adventurer) -> Stats {
        content.race(adventurer.raceID).base + content.classDef(adventurer.classID).growth * (adventurer.level - 1)
    }

    func skills(of adventurer: Adventurer) -> [SkillDef] {
        content.classDef(adventurer.classID).skills.filter { $0.level <= adventurer.level }.compactMap { content.skill($0.skill) }
    }

    /// Their walk sheet in their colours, in the armour they wear.
    func artID(for adventurer: Adventurer) -> String {
        Self.registerAdventurer(adventurer)
    }

    /// Draws another adventurer like a hero, in the armour that suits them (`armor(for:)`), the
    /// gloves, boots and necklace they have on (`trinkets(for:)`) and in a festive season, the hat
    /// they wear for it (`hat(for:)`).
    static func registerAdventurer(_ adventurer: Adventurer) -> String {
        // A festive scarf is a necklace: worn in place of theirs.
        let festive = Self.hat(for: adventurer)
        let armor = Self.armor(for: adventurer)
        // The hat that goes with their armour, unless a festive one is on their head.
        let headpiece = festive?.type == .head ? nil : armor?.headpiece.flatMap(Content.shared.item)
        return registerPerson(race: adventurer.raceID, look: adventurer.look, armor: armor,
                              worn: Self.trinkets(for: adventurer).filter { $0.type != festive?.type } + [festive, headpiece].compactMap { $0 })
    }

    /// Someone of a race and look (a villager in plain clothes without `armor`), drawn from the same
    /// paper-doll layers as a hero, so their hair takes its colour on every shade too (a whole-sheet
    /// recolour leaves the ginger's deep reds and pale tips).
    static func registerPerson(race raceID: String, look: Look, armor: ItemDef? = nil, worn: [ItemDef] = []) -> String {
        let id = "adv:\(raceID):\(look.key):\(armor?.id ?? "-")" + worn.map { ":" + $0.id }.joined()
        registerArt(id, race: Content.shared.race(raceID), look: look, armor: armor, worn: worn, key: id)
        return id
    }

    /// The armour another adventurer wears, like a player would: one their class can wear at their
    /// level, mostly of the best kind (a third of the time the kind before it). Novices wear tunics
    /// and leather vests. The same adventurer always picks the same, until they outgrow it.
    static func armor(for adventurer: Adventurer) -> ItemDef? {
        // Never a quest treasure: those are yours alone.
        let wearable = Content.shared.items.filter {
            $0.type == .armor && ($0.level ?? 1) <= adventurer.level && ($0.classes?.contains(adventurer.classID) ?? true)
                && !Content.shared.isTreasure($0.id)
        }
        let tiers = Set(wearable.map { $0.level ?? 1 }).sorted(by: >)
        guard let best = tiers.first else { return nil }
        let seed = Self.seed(adventurer.id)
        let tier = tiers.count > 1 && seed % 3 == 0 ? tiers[1] : best
        let choices = wearable.filter { ($0.level ?? 1) == tier }
        return choices[Int((seed / 3) % UInt64(choices.count))]
    }

    /// The weapon an adventurer fights with, in their hand on the map and in battle: one for their
    /// class, of the best kind they're old enough for (a kind lower for a third of them), the same
    /// one every time, like their armour.
    static func weapon(for adventurer: Adventurer) -> ItemDef? {
        let usable = Content.shared.items.filter {
            $0.type == .weapon && ($0.level ?? 1) <= adventurer.level && ($0.classes?.contains(adventurer.classID) ?? true)
                && !Content.shared.isTreasure($0.id)
        }
        let tiers = Set(usable.map { $0.level ?? 1 }).sorted(by: >)
        guard let best = tiers.first else { return nil }
        // A different draw from their armour's, so the two don't always step down together.
        let seed = Self.seed(adventurer.id) / 11
        let tier = tiers.count > 1 && seed % 3 == 0 ? tiers[1] : best
        let choices = usable.filter { ($0.level ?? 1) == tier }
        return choices[Int((seed / 3) % UInt64(choices.count))]
    }

    /// The gloves, boots and necklace an adventurer has on, each like their armour: of the best kind
    /// for their level and class, never a quest treasure. A third go without each, the same ones
    /// every time.
    static func trinkets(for adventurer: Adventurer) -> [ItemDef] {
        let seed = Self.seed(adventurer.id) / 7
        let slots: [ItemType] = [.gloves, .boots, .necklace]
        return slots.indices.compactMap { index -> ItemDef? in
            let slot = slots[index]
            let draw = seed >> UInt64(index * 6)
            guard draw % 3 != 0 else { return nil }
            let wearable = Content.shared.items.filter {
                $0.type == slot && ($0.level ?? 1) <= adventurer.level && ($0.classes?.contains(adventurer.classID) ?? true)
                    && !Content.shared.isTreasure($0.id) && !Content.shared.isFestive($0.id)
            }
            guard let best = wearable.map({ $0.level ?? 1 }).max() else { return nil }
            let choices = wearable.filter { ($0.level ?? 1) == best }
            return choices[Int((draw / 3) % UInt64(choices.count))]
        }
    }

    /// The hat an adventurer wears in a festive season (rewards.json `seasons`): one of its hats (or
    /// scarves) for half of them, the same one all season.
    static func hat(for adventurer: Adventurer, on date: Date = GameSession.today) -> ItemDef? {
        guard let festive = season(on: date)?.season, !festive.hats.isEmpty else { return nil }
        let seed = Self.seed(adventurer.id) / 13
        guard seed % 2 == 0 else { return nil }
        return Content.shared.item(festive.hats[Int((seed / 2) % UInt64(festive.hats.count))])
    }

    /// The same number for the same adventurer on every launch (Swift's own hashes change each run).
    private static func seed(_ id: UUID) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in id.uuidString.utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return hash
    }

    /// Party friends grow with you: after every win, the ones at your side keep up to a level behind
    /// you (with `standing`, only those still on their feet at the end; out cold, they learn nothing
    /// from it, like you). Returns who went up, with their new level.
    @discardableResult
    func growParty(standing: Set<UUID>? = nil) -> [(id: UUID, name: String, level: Int)] {
        let level = data.hero.level - 1
        let party = Set(data.partyIDs ?? [])
        guard var friends = data.friends else { return [] }
        var grown: [(id: UUID, name: String, level: Int)] = []
        for index in friends.indices where party.contains(friends[index].id) && friends[index].waitingAt == nil
            && standing?.contains(friends[index].id) != false && friends[index].level < level {
            friends[index].level = level
            grown.append((id: friends[index].id, name: friends[index].name, level: level))
        }
        data.friends = friends
        return grown
    }

    /// Full party: `id` stays behind (it may be the newcomer), and the newcomer takes its place.
    func leaveBehind(_ id: UUID) {
        guard let newcomer = pendingPet else { return }
        pendingPet = nil
        if id == newcomer.id {
            post(L("{pet} waves goodbye and hops back to the wild.", ["pet": newcomer.name]))
            return
        }
        guard let index = data.pets.firstIndex(where: { $0.id == id }) else { return }
        let parting = data.pets.remove(at: index)
        data.pets.append(newcomer)
        if data.activePetID == parting.id { data.activePetID = newcomer.id }
        post(L("{parting} stays behind. {pet} joined your party!", ["parting": parting.name, "pet": newcomer.name]), .reward)
        save()
    }

    func setActivePet(_ id: UUID) {
        guard data.pets.contains(where: { $0.id == id }) else { return }
        data.activePetID = id
    }

    /// Adds EXP to a companion and returns how many levels it gained.
    @discardableResult
    func gainPetEXP(_ id: UUID, _ amount: Int) -> Int {
        guard amount > 0, let index = data.pets.firstIndex(where: { $0.id == id }) else { return 0 }
        guard data.pets[index].level < Self.levelCap else { return 0 }
        data.pets[index].exp += amount
        var levels = 0
        while data.pets[index].level < Self.levelCap, data.pets[index].exp >= Self.expToNext(level: data.pets[index].level) {
            data.pets[index].exp -= Self.expToNext(level: data.pets[index].level)
            data.pets[index].level += 1
            levels += 1
        }
        if levels > 0 {
            let stats = stats(of: data.pets[index])
            data.pets[index].hp = stats.hp
            data.pets[index].mp = stats.mp
        }
        return levels
    }

    /// The healer: everyone back to full.
    func restParty() {
        SoundEffects.shared.play(.heal)
        restoreHero()
        for index in data.pets.indices {
            let stats = stats(of: data.pets[index])
            data.pets[index].hp = stats.hp
            data.pets[index].mp = stats.mp
        }
        // Friends in your party rest up too.
        if var friends = data.friends {
            for index in friends.indices {
                friends[index].hp = nil
                friends[index].mp = nil
            }
            data.friends = friends
        }
    }

    /// Where you wake up after fainting, and the first town Bridge of Light and Homeward Feathers
    /// offer to take you to (`travelDestinations`): the square of the last town you walked into.
    /// (An older save could hold a wild map's entrance; that becomes the town nearest to it.)
    var checkpoint: Checkpoint {
        inTown(data.checkpoint) ?? Checkpoint(mapID: content.startMap, entry: nil)
    }

    /// A saved checkpoint as a town's square: itself if it's in a town, else the town fewest roads
    /// away from it.
    func inTown(_ point: Checkpoint?) -> Checkpoint? {
        guard let point else { return nil }
        if content.map(point.mapID)?.fence == true { return Checkpoint(mapID: point.mapID, entry: nil) }
        return nearestTown(to: point.mapID).map { Checkpoint(mapID: $0, entry: nil) }
    }

    /// The town fewest roads away from `mapID` (searching outward along the maps' exits, both ways).
    func nearestTown(to mapID: String) -> String? {
        var seen: Set<String> = [mapID]
        var frontier = [mapID]
        while !frontier.isEmpty {
            var next: [String] = []
            for id in frontier {
                guard let map = content.map(id) else { continue }
                if map.fence == true { return id }
                // A cave's levels count as roads too, by their stairs (`NPCRole.stairs`).
                let stairs = (map.npcs ?? []).compactMap { $0.role == .stairs ? $0.to : nil }
                let roads = map.exits.map(\.to) + content.maps.filter { $0.exits.contains { $0.to == id } }.map(\.id) + stairs
                for other in roads where seen.insert(other).inserted { next.append(other) }
            }
            frontier = next
        }
        return nil
    }

    /// Walking into a town makes its square your checkpoint, and the friends at your side save there
    /// with you. Wild maps don't: waking up at the edge of a zone too hard for you could leave you
    /// fainting there over and over.
    func reachCheckpoint(_ map: MapDef) {
        guard map.fence == true else { return }
        let point = Checkpoint(mapID: map.id, entry: nil)
        let beside = Set(friendsAtYourSide.map(\.id))
        if var friends = data.friends, friends.contains(where: { beside.contains($0.id) && $0.checkpoint != point }) {
            for index in friends.indices where beside.contains(friends[index].id) {
                friends[index].checkpoint = point
            }
            data.friends = friends
        }
        guard point != data.checkpoint else { return }
        data.checkpoint = point
        post(L("Checkpoint saved at {place}.", ["place": checkpointName(point)]), .quest)
    }

    /// Where Bridge of Light, Homeward Feathers and waystones can take you: every town you've been
    /// to but the one you're in (by its map's id), your checkpoint first, then the rest in the order
    /// the world lists them; then every waystone you've woken but one in the land you're in (by
    /// its own id).
    var travelDestinations: [String] {
        let towns = content.maps.filter { $0.fence == true && $0.id != data.mapID && hasVisited($0.id) }.map(\.id)
        let home = checkpoint.mapID
        let waystones = content.maps.filter { $0.id != data.mapID }
            .flatMap { $0.npcs ?? [] }
            .filter { $0.role == .waystone && isAwake($0) }
            .map(\.id)
        return towns.filter { $0 == home } + towns.filter { $0 != home } + waystones
    }

    /// A waystone (`NPCRole.waystone`) is awake once the quest that wakes it (`NPCDef.quest`) is
    /// done.
    func isAwake(_ waystone: NPCDef) -> Bool {
        guard let quest = waystone.quest else { return true }
        return data.quests[quest]?.state == .completed
    }

    func checkpointName(_ point: Checkpoint) -> String {
        let name = content.map(point.mapID)?.name ?? L("town")
        return point.entry == nil ? name : L("the {map} entrance", ["map": name])
    }

    /// After a fight, the party may split up. Whoever fainted wakes up at their own checkpoint: you at
    /// yours (`faint()`), each friend at theirs. Friends still standing when you fell stay where the
    /// fight was. Either way they wait there until you come back for them (`rejoin`); a friend who
    /// wakes up where you do is right beside you again. Returns what happened, for the battle log.
    func partWays(fainted: Set<UUID>, heroFainted: Bool) -> [String] {
        let here = Spot(mapID: data.mapID, position: playerPosition.map { [Double($0.x), Double($0.y)] })
        var lines: [String] = []
        var wokeWithYou: [String] = []
        var stayed: [String] = []
        for friend in friendsAtYourSide {
            guard let index = data.friends?.firstIndex(where: { $0.id == friend.id }) else { continue }
            if fainted.contains(friend.id) {
                // Bruised when they wake, as you are: half their HP and MP.
                let stats = stats(of: friend)
                data.friends?[index].hp = max(1, stats.hp / 2)
                data.friends?[index].mp = stats.mp / 2
                let home = inTown(friend.checkpoint) ?? checkpoint
                if heroFainted && home == checkpoint {
                    wokeWithYou.append(friend.name)
                } else {
                    data.friends?[index].waitingAt = Spot(mapID: home.mapID, entry: home.entry)
                    lines.append(L("{name} fainted and wakes up at {place}.", ["name": friend.name, "place": checkpointName(home)]))
                }
            } else if heroFainted {
                data.friends?[index].waitingAt = here
                stayed.append(friend.name)
            }
        }
        if heroFainted {
            faint()
            let place = checkpointName(checkpoint)
            lines.insert(L("{names} wake up at {place}, a little bruised.", ["names": Self.listed([L("You")] + wokeWithYou), "place": place]), at: 0)
        }
        if !stayed.isEmpty {
            lines.append(stayed.count == 1
                ? L("{names} waits for you where you fell.", ["names": Self.listed(stayed)])
                : L("{names} wait for you where you fell.", ["names": Self.listed(stayed)]))
        }
        return lines
    }

    /// "Maple", "Maple and Kip", "Maple, Kip and Sprout".
    static func listed(_ names: [String]) -> String {
        guard let last = names.last else { return "" }
        return names.count > 1 ? L("{names} and {last}", ["names": names.dropLast().joined(separator: ", "), "last": last]) : last
    }

    /// Lost a battle: wake up at the last checkpoint, bruised.
    func faint() {
        let stats = heroStats
        data.hero.hp = max(1, stats.hp / 2)
        data.hero.mp = stats.mp / 2
        for index in data.pets.indices where data.pets[index].hp <= 0 {
            data.pets[index].hp = 1
        }
        data.mapID = checkpoint.mapID
        playerPosition = nil
    }

    // MARK: - Eggs & chests

    /// Whether a chest stands open and empty: opened, and not filled again yet (`refillsAt`).
    func isOpened(_ chestID: String) -> Bool {
        guard data.openedChests?.contains(chestID) == true else { return false }
        return refillsAt(chestID).map { $0 > Date() } ?? false
    }

    /// When a chest you've opened has something new in it: `rewards.chests.refillHours` after you
    /// last opened it. None for one opened before chests filled again (it's full already).
    func refillsAt(_ chestID: String) -> Date? {
        guard let opened = data.chestsOpenedAt?[chestID], let rules = content.rewards.chests else { return nil }
        return opened.addingTimeInterval(rules.refillHours * 3600)
    }

    /// Whether a chest can be opened yet (its quest, if it has one, has to be accepted first).
    func canOpen(_ chest: NPCDef) -> Bool {
        guard !isOpened(chest.id) else { return false }
        guard let questID = chest.quest else { return true }
        return data.quests[questID] != nil
    }

    /// Opens a chest and returns the item inside: the first time its own treasure (`gives`), and
    /// each time it's filled again after that, gold and something new for its level (`refill`).
    @discardableResult
    func openChest(_ chest: NPCDef) -> ItemDef? {
        guard canOpen(chest), let id = chest.gives, let treasure = content.item(id) else { return nil }
        var found = treasure, gold = 0
        if data.openedChests?.contains(chest.id) == true {
            let filled = refill(level: treasure.level ?? data.hero.level)
            guard let item = filled.item else { return nil }
            found = item
            gold = filled.gold
        } else {
            data.openedChests = (data.openedChests ?? []) + [chest.id]
        }
        guard hasRoom(for: [found.id]) else {
            post(L("Your bag is full. Make room, then open the chest."), .system)
            return nil
        }
        addItem(found.id)
        gainGold(gold)
        data.chestsOpenedAt = (data.chestsOpenedAt ?? [:]).merging([chest.id: Date()]) { $1 }
        SoundEffects.shared.play(.chest)
        record(.collect, target: "gift_box")
        post(L("Found {item} in the treasure chest!", ["item": found.name]), .reward)
        if gold > 0 { post(L("+{gold} gold", ["gold": gold]), .reward) }
        return found
    }

    /// What a chest holds when it's filled again, for its `level` (its own treasure's): gold, and a
    /// piece of gear around that level (`equipmentDrop`) `gearChance` of the time, else one of its
    /// `items` (rewards.json `chests`).
    private func refill(level: Int) -> (gold: Int, item: ItemDef?) {
        guard let rules = content.rewards.chests else { return (0, nil) }
        let gear = Double.random(in: 0..<1) < rules.gearChance ? equipmentDrop(level: level) : nil
        return (rules.goldPerLevel * level, gear ?? rules.items.randomElement().flatMap(content.item))
    }

    /// Hatches an egg from the bag into a new companion.
    func hatch(_ eggID: String) -> Pet? {
        guard let egg = content.item(eggID), let pool = egg.hatches, !pool.isEmpty, count(of: eggID) > 0 else { return nil }
        let species = data.eggSpecies.flatMap { pool.contains($0) ? $0 : nil } ?? pool.randomElement()!
        guard let pet = makePet(species: species, level: 1), data.pets.count < Self.maxPets else { return nil }
        SoundEffects.shared.play(.hatch)
        Haptics.success()
        removeItem(eggID)
        addPet(pet, countsForQuests: false)
        data.activePetID = pet.id
        post(L("{pet} hatched and joined you!", ["pet": pet.name]), .reward)
        record(.hatch, target: nil)
        return pet
    }

    // MARK: - Items

    func count(of id: String) -> Int { data.inventory[id] ?? 0 }

    /// Into the bag, if they fit: each one takes one of its 50 slots (`GameSession+Bank`). False, and a
    /// note, when the bag hasn't room for them all: they're left behind. `force`: put in whatever the
    /// bag holds (what an older save is owed, a quest's own things).
    @discardableResult
    func addItem(_ id: String, _ amount: Int = 1, force: Bool = false) -> Bool {
        guard amount > 0 else { return true }
        guard force || amount <= bagSlotsFree else {
            post(L("Your bag is full: {item} left behind.", ["item": content.item(id)?.name ?? id]), .reward)
            return false
        }
        data.inventory[id, default: 0] += amount
        return true
    }

    @discardableResult
    func removeItem(_ id: String) -> Bool {
        guard count(of: id) > 0 else { return false }
        data.inventory[id]! -= 1
        if data.inventory[id] == 0 { data.inventory[id] = nil }
        return true
    }

    /// What you carry to use, in your order of the bag (`GameSession+ItemOrder`), as the gear and
    /// materials are.
    var consumables: [ItemDef] {
        bagItems.filter { $0.type == .consumable }
    }

    /// What you can drink or feed in battle (not eggs or Seal Stones).
    var battleItems: [ItemDef] {
        consumables.filter { ($0.heal ?? 0) > 0 || ($0.mp ?? 0) > 0 }
    }

    var sealStones: Int {
        content.items.filter { $0.capture == true }.reduce(0) { $0 + count(of: $1.id) }
    }

    /// The kinds of Seal Stone in the bag, plainest first and a sure one (the Wishing Seal) last.
    var sealStoneKinds: [ItemDef] {
        content.items
            .filter { $0.capture == true && count(of: $0.id) > 0 }
            .sorted { ($0.sure == true ? 1 : 0, $0.sealPower ?? 1) < ($1.sure == true ? 1 : 0, $1.sealPower ?? 1) }
    }

    var bagEquipment: [ItemDef] {
        bagItems.filter { ItemType.equipmentSlots.contains($0.type) }
    }

    var bagMaterials: [ItemDef] {
        bagItems.filter { $0.type == .material }
    }

    /// Why the hero can't equip `item`, or nil if they can.
    func equipIssue(_ item: ItemDef) -> String? {
        if let classes = item.classes, !classes.contains(data.hero.classID) {
            let names = classes.map { content.classDef($0).name }.joined(separator: ", ")
            return L("Only for {classes}", ["classes": names])
        }
        if let level = item.level, data.hero.level < level {
            return L("Needs level {level}", ["level": level])
        }
        return nil
    }

    /// What a piece of gear is worth to the hero, to tell a better one from a worse: each bonus
    /// weighted by how much their class leans on that stat (its growth next to a novice's: a
    /// fighter's Attack, a mage's Magic), and by how big that stat's numbers run (a point of HP is
    /// worth less than a point of Attack, as a novice gains 9 HP a level and 2 Attack).
    func gearValue(_ item: ItemDef) -> Double {
        guard let bonus = item.stats else { return 0 }
        let lean = heroClass.growth, plain = content.classDef("novice").growth
        let stats: [KeyPath<Stats, Int>] = [\.hp, \.mp, \.attack, \.defense, \.magic, \.speed]
        return stats.reduce(0) { total, stat in
            let scale = Double(max(1, plain[keyPath: stat]))
            return total + Double(bonus[keyPath: stat]) * Double(lean[keyPath: stat]) / (scale * scale)
        }
    }

    /// Whether `item` (in the bag) would be an upgrade: the hero can wear it now, and it's worth
    /// more to them than what they have on in its slot, or the slot is empty.
    func isUpgrade(_ item: ItemDef) -> Bool {
        guard ItemType.equipmentSlots.contains(item.type), equipIssue(item) == nil else { return false }
        guard let worn = equipped(item.type) else { return true }
        return gearValue(item) > gearValue(worn) + 0.001
    }

    /// The best upgrade in the bag for `slot`, if there is one: the Character screen marks the slot.
    func upgrade(for slot: ItemType) -> ItemDef? {
        bagEquipment.filter { $0.type == slot && isUpgrade($0) }.max { gearValue($0) < gearValue($1) }
    }

    /// Something in the bag would be better than what the hero wears somewhere.
    var hasGearUpgrade: Bool { bagEquipment.contains { isUpgrade($0) } }

    func equip(_ id: String) {
        guard let item = content.item(id), ItemType.equipmentSlots.contains(item.type), equipIssue(item) == nil else { return }
        // What it replaces goes in the bag, in the slot this one leaves.
        guard removeItem(id) else { return }
        SoundEffects.shared.play(.equip)
        if let old = data.hero.equipment[item.type] { addItem(old, force: true) }
        data.hero.equipment[item.type] = id
        clampHero()
        applyLook()
    }

    func unequip(_ slot: ItemType) {
        guard let id = data.hero.equipment[slot], addItem(id) else { return }
        data.hero.equipment[slot] = nil
        clampHero()
        applyLook()
    }

    /// Buys `amount` of a thing from a shop, if the coins pay for them all and the bag has room.
    @discardableResult
    func buy(_ id: String, _ amount: Int = 1) -> Bool {
        guard amount > 0, let item = content.item(id) else { return false }
        let cost = item.price * amount
        guard data.gold >= cost else { return false }
        // Spending the last coins frees their slot.
        guard amount <= bagSlotsFree + (data.gold == cost ? 1 : 0) else {
            post(L("Your bag is full. Put something in the bank first."), .system)
            return false
        }
        data.gold -= cost
        SoundEffects.shared.play(.coins)
        addItem(id, amount)
        return true
    }

    /// How many you could buy at `price` each: as many as your coins pay for and your bag has room
    /// for (spending the very last coins frees their slot for one more).
    func affordable(at price: Int) -> Int {
        let free = bagSlotsFree
        guard price > 0 else { return free }
        let paid = data.gold / price
        if paid <= free { return paid }
        return paid == free + 1 && paid * price == data.gold ? paid : free
    }

    /// Whether a thing is bought and sold several at once (potions, materials, eggs...): anything
    /// but gear, which goes one piece at a time.
    static func sellsInBulk(_ item: ItemDef) -> Bool {
        !ItemType.equipmentSlots.contains(item.type)
    }

    // MARK: - Selling and trading

    /// Shops buy things back for half their price, like Fairyland Online's NPC shops.
    static func sellPrice(of item: ItemDef) -> Int { max(1, item.price / 2) }

    /// What a shop will take: anything in the bag with a price (eggs have none).
    var sellableItems: [ItemDef] {
        content.items.filter { $0.price > 0 && count(of: $0.id) > 0 }
    }

    /// Sells `amount` to a shop. Returns the gold paid, or nil if there weren't that many to sell.
    @discardableResult
    func sell(_ id: String, _ amount: Int = 1) -> Int? {
        guard amount > 0, let item = content.item(id), item.price > 0 else { return nil }
        let held = count(of: id)
        guard held >= amount else { return nil }
        // The coins go in the slot it leaves, if they need one.
        data.inventory[id] = held > amount ? held - amount : nil
        let paid = Self.sellPrice(of: item) * amount
        gainGold(paid)
        SoundEffects.shared.play(.coins)
        return paid
    }

    /// One deal an adventurer offers: they buy something of yours (for more than a shop pays), or
    /// sell you something they carry (for a little over the shop price, but shops may not stock it).
    struct TradeOffer: Identifiable {
        enum Kind { case theyBuy, theySell }
        let kind: Kind
        let item: ItemDef
        /// For one.
        let price: Int
        /// Who offered it, on which in-game day, for what: a deal is made once.
        let id: String
        /// The most the deal is for: a few of a potion or a material (they'd buy that many, or
        /// carry that many), one piece of gear.
        var stock = 1
    }

    /// Today's offers from `adventurer`. They change with the in-game day, and stay put while
    /// you think it over.
    func tradeOffers(with adventurer: Adventurer, at date: Date = Date()) -> [TradeOffer] {
        let moment = GameClock.moment(at: date, since: data.startedAt)
        // The English month name, as before translations: the same deals in every language.
        let day = "\(moment.year)/\(moment.month.rawValue.capitalized)/\(moment.day)"
        var rng = SeededRandom(text: "\(adventurer.id)|\(day)")
        let done = Set(data.tradesDone ?? [])
        func offer(_ kind: TradeOffer.Kind, _ item: ItemDef, _ price: Int) -> TradeOffer? {
            let id = "\(adventurer.id)|\(day)|\(kind == .theyBuy ? "buy" : "sell")|\(item.id)"
            guard !done.contains(id) else { return nil }
            // A few of a potion or a material, from the deal's own seed, so the day's offers stay
            // the ones they were.
            var roll = SeededRandom(text: id)
            let stock = GameSession.sellsInBulk(item) ? Int.random(in: 2...5, using: &roll) : 1
            return TradeOffer(kind: kind, item: item, price: price, id: id, stock: stock)
        }
        // They want a few of your things, each of a different kind (gear, potions, materials...; playtesting
        // 2026-10-25: "they should buy a lot of different items, currently they only buy materials"), and
        // pay half again what a shop would.
        let byKind = Dictionary(grouping: sellableItems, by: \.type)
        let kinds = byKind.keys.sorted { $0.rawValue < $1.rawValue }.shuffled(using: &rng)
        let wanted = kinds.prefix(3).compactMap { byKind[$0]?.randomElement(using: &rng) }
        // And they carry a few things around their level.
        let level = adventurer.level
        let goods = content.items.filter { item in
            item.price > 0 && item.capture != true && item.hatches == nil && !content.isTreasure(item.id)
                && (item.type == .consumable || item.type == .material || abs((item.level ?? 1) - level) <= 12)
        }
        let carried = Array(goods.shuffled(using: &rng).prefix(3))
        return wanted.compactMap { offer(.theyBuy, $0, max(Self.sellPrice(of: $0) + 1, Self.sellPrice(of: $0) * 3 / 2)) }
            + carried.compactMap { offer(.theySell, $0, max(1, $0.price * 11 / 10)) }
    }

    /// A market trader's sign: the first thing they're selling today, and its price.
    func marketSign(for trader: Adventurer) -> String? {
        guard let offer = tradeOffers(with: trader).first(where: { $0.kind == .theySell }) else { return nil }
        return L("{item} · {price}g", ["item": offer.item.name, "price": offer.price])
    }

    /// What a market trader calls out on the map's chat: one of today's real deals, from
    /// content/crowd.json `traderLines` ({item} and {price} for what they sell, {buy} and {price}
    /// for what they'd buy from you).
    func marketShout(for trader: Adventurer) -> String? {
        guard let offer = tradeOffers(with: trader).randomElement() else { return nil }
        let placeholder = offer.kind == .theyBuy ? "{buy}" : "{item}"
        guard let line = (content.crowd.traderLines ?? []).filter({ $0.contains(placeholder) }).randomElement() else { return nil }
        return line
            .replacingOccurrences(of: placeholder, with: offer.item.name)
            .replacingOccurrences(of: "{price}", with: "\(offer.price)")
    }

    /// Beat an adventurer and they drop everything they carry: today's goods (what they'd have sold
    /// you) go into your bag, and those deals are gone. Returns what you got.
    func takeSpoils(from adventurer: Adventurer) -> [ItemDef] {
        let goods = tradeOffers(with: adventurer).filter { $0.kind == .theySell }
        // What doesn't fit in the bag is left behind.
        let taken = goods.filter { addItem($0.item.id) }
        data.tradesDone = Array((data.tradesDone ?? []).suffix(200)) + goods.map(\.id)
        return taken.map(\.item)
    }

    /// Makes a deal, for `amount` (up to its `stock`). Returns false if you can't (not enough gold
    /// or room, or not that many of the item). A deal is made once, however many it was for.
    @discardableResult
    func trade(_ offer: TradeOffer, _ amount: Int = 1) -> Bool {
        guard amount > 0, amount <= offer.stock, !(data.tradesDone ?? []).contains(offer.id) else { return false }
        let total = offer.price * amount
        switch offer.kind {
        case .theyBuy:
            let held = count(of: offer.item.id)
            guard held >= amount else { return false }
            data.inventory[offer.item.id] = held > amount ? held - amount : nil
            gainGold(total)
        case .theySell:
            guard data.gold >= total,
                  amount <= bagSlotsFree + (data.gold == total ? 1 : 0) else { return false }
            data.gold -= total
            addItem(offer.item.id, amount)
        }
        data.tradesDone = Array((data.tradesDone ?? []).suffix(200)) + [offer.id]
        SoundEffects.shared.play(.coins)
        return true
    }

    // MARK: - Crafting
    // Fairyland Online's blacksmiths forged weapons from gathered wood, metal and gems. Here
    // monsters drop the materials, and a smith in each town turns a recipe into the weapon.

    /// Everything a smith can forge, lowest level first (not what's made by hand, `make`).
    var recipes: [ItemDef] {
        content.items.filter { $0.recipe != nil && $0.make == nil }.sorted { ($0.level ?? 1) < ($1.level ?? 1) }
    }

    struct Ingredient: Identifiable {
        let material: ItemDef
        let needed: Int
        let owned: Int
        var id: String { material.id }
    }

    /// The ingredients of `item`, in a stable order, with how many you have.
    func ingredients(of item: ItemDef) -> [Ingredient] {
        var parts: [Ingredient] = []
        for (id, needed) in (item.recipe ?? [:]).sorted(by: { $0.key < $1.key }) {
            guard let material = content.item(id) else { continue }
            parts.append(Ingredient(material: material, needed: needed, owned: count(of: id)))
        }
        return parts
    }

    func canCraft(_ item: ItemDef) -> Bool {
        guard let recipe = item.recipe, !recipe.isEmpty else { return false }
        return recipe.allSatisfy { count(of: $0.key) >= $0.value }
    }

    @discardableResult
    func craft(_ id: String) -> Bool {
        guard let item = content.item(id), canCraft(item), let recipe = item.recipe else { return false }
        // What's made goes in a slot its materials leave.
        for (material, needed) in recipe {
            data.inventory[material, default: 0] -= needed
            if data.inventory[material] == 0 { data.inventory[material] = nil }
        }
        addItem(id)
        return true
    }

    /// A material a monster of `level` might drop: mostly the newest kind it can carry, now and
    /// then the one before. Gems are the rarest.
    func materialDrop(level: Int) -> ItemDef? {
        let kinds = ["wood", "wood", "wood", "metal", "metal", "metal", "hide", "hide", "gem"]
        guard let kind = kinds.randomElement() else { return nil }
        let options = content.items
            .filter { $0.type == .material && $0.material == kind && ($0.level ?? 1) <= level }
            .sorted { ($0.level ?? 1) > ($1.level ?? 1) }
        guard !options.isEmpty else { return nil }
        return Double.random(in: 0..<1) < 0.3 && options.count > 1 ? options[1] : options[0]
    }

    /// The Homeward Feather: sold in every town shop, and now and then dropped after a won fight.
    static let featherID = "homeward_feather"

    /// What a beaten monster counts for in what a fight drops, by its level next to yours
    /// (playtesting 2026-10-30: a level 2 monster beaten at level 179 left five things and gold): in
    /// full from five levels under you up, a twentieth more for each level over (half again at most),
    /// a twentieth less for each level further under, down to a tenth. A fight is worth what its
    /// monsters are together, so more of them, and stronger ones, drop more.
    static func dropWorth(level: Int, heroLevel: Int) -> Double {
        let gap = level - heroLevel
        if gap >= 0 { return min(1.5, 1 + 0.05 * Double(gap)) }
        return max(0.1, min(1, 1 - 0.05 * Double(-gap - 5)))
    }

    /// How likely a won fight is to leave a Homeward Feather: about one in twelve for three monsters
    /// at your level (`worth`, `dropWorth`), more for more and stronger ones, and always after a boss,
    /// so a hard zone always gives you a way home.
    static func featherDropChance(boss: Bool, worth: Double) -> Double { boss ? 1 : min(0.2, 0.027 * worth) }

    /// How likely a beaten wild monster is to drop a piece of equipment: 6%, a point more for each
    /// level it has over you (up to 16%) and a point less for each below, down to 2% of what it's
    /// worth (`dropWorth`: 2% to a few levels under, a fifth of a point far under), so stronger fights
    /// pay better; a rare monster 35%, and a boss always.
    static func equipmentDropChance(level: Int, heroLevel: Int, rare: Bool, boss: Bool) -> Double {
        if boss { return 1 }
        if rare { return 0.35 }
        let floor = 0.02 * dropWorth(level: level, heroLevel: heroLevel)
        return min(0.16, max(floor, 0.06 + 0.01 * Double(level - heroLevel)))
    }

    /// How many equipment drops are trinkets (gloves, necklaces, boots, rings and charms). There
    /// are only a handful of each next to dozens of weapons and armours, so by level alone they'd
    /// hardly ever turn up.
    static let accessoryShare = 1.0 / 3

    /// The piece of equipment a beaten monster of `level` drops. One time in three
    /// (`accessoryShare`) a trinket: any up to its level, the stronger ones more often.
    /// Otherwise a weapon, an armour or the hat that goes with one, from the twelve levels up to its own (the top six from a rare
    /// monster or a boss), the higher ones more often, and three times in four something your
    /// class can use. Bosses' own rare drops aren't in it, nor are quest treasures; those stay theirs.
    func equipmentDrop(level: Int, best: Bool = false) -> ItemDef? {
        let span = best ? 6 : 12
        let kept = Set(content.monsters.flatMap { $0.drops ?? [] }.map(\.item)).union(content.items.map(\.id).filter(content.isTreasure))
        // Past the best gear a monster can drop, it drops from the top (quest treasures go higher).
        // Gear only: a quest's pieces have levels too, past any gear's.
        let gear = content.items.filter { ItemType.equipmentSlots.contains($0.type) && !kept.contains($0.id) }
        let top = min(level, gear.compactMap(\.level).max() ?? level)
        let accessories = content.items.filter {
            $0.type.isTrinket && !kept.contains($0.id) && ($0.level ?? 1) <= top && !content.isFestive($0.id)
        }
        if !accessories.isEmpty, Double.random(in: 0..<1) < Self.accessoryShare {
            let weights = accessories.map { Double($0.level ?? 1) + 10 }
            var roll = Double.random(in: 0..<weights.reduce(0, +))
            for (item, weight) in zip(accessories, weights) {
                if roll < weight { return item }
                roll -= weight
            }
            return accessories.last
        }
        let pool = content.items.filter {
            ($0.type == .weapon || $0.type == .armor || ($0.type == .head && $0.headgear != nil)) && !kept.contains($0.id)
                && ($0.level ?? 1) <= top && ($0.level ?? 1) > top - span
        }
        let yours = pool.filter { $0.classes?.contains(data.hero.classID) ?? true }
        let choices = !yours.isEmpty && Double.random(in: 0..<1) < 0.75 ? yours : pool
        // An item at the top of the range is `span` times as likely as one at the bottom.
        let weights = choices.map { Double(($0.level ?? 1) - (top - span)) }
        var roll = Double.random(in: 0..<max(1, weights.reduce(0, +)))
        for (item, weight) in zip(choices, weights) {
            if roll < weight { return item }
            roll -= weight
        }
        return choices.last
    }

    /// Uses a potion or ether outside battle, on the hero or a companion. Returns a message.
    /// Nothing is used up when it wouldn't help (Seal Stones and eggs aren't drunk at all).
    @discardableResult
    func use(_ id: String, onPet petID: UUID? = nil) -> String? {
        guard let item = content.item(id), item.type == .consumable, count(of: id) > 0 else { return nil }
        let heal = item.heal ?? 0, mp = item.mp ?? 0
        guard heal > 0 || mp > 0 else { return nil }
        if let petID, let index = data.pets.firstIndex(where: { $0.id == petID }) {
            let stats = stats(of: data.pets[index])
            let pet = data.pets[index]
            guard (heal > 0 && pet.hp < stats.hp) || (mp > 0 && pet.mp < stats.mp) else { return L("{name} doesn't need it.", ["name": pet.name]) }
            data.pets[index].hp = min(stats.hp, pet.hp + heal)
            data.pets[index].mp = min(stats.mp, pet.mp + mp)
            removeItem(id)
            return L("{name} feels better.", ["name": pet.name])
        }
        let stats = heroStats
        guard (heal > 0 && data.hero.hp < stats.hp) || (mp > 0 && data.hero.mp < stats.mp) else { return L("{name} doesn't need it.", ["name": data.hero.name]) }
        data.hero.hp = min(stats.hp, data.hero.hp + heal)
        data.hero.mp = min(stats.mp, data.hero.mp + mp)
        removeItem(id)
        return L("{name} feels better.", ["name": data.hero.name])
    }

    /// How many of a potion or ether it takes to fill the hero (no `petID`) or a companion up, as far
    /// as it can: none when it wouldn't help.
    func usesToFill(_ id: String, onPet petID: UUID? = nil) -> Int {
        guard let item = content.item(id), item.type == .consumable else { return 0 }
        let heal = item.heal ?? 0, mp = item.mp ?? 0
        let missing: (hp: Int, mp: Int)
        if let petID {
            guard let pet = data.pets.first(where: { $0.id == petID }) else { return 0 }
            let stats = stats(of: pet)
            missing = (max(0, stats.hp - pet.hp), max(0, stats.mp - pet.mp))
        } else {
            let stats = heroStats
            missing = (max(0, stats.hp - data.hero.hp), max(0, stats.mp - data.hero.mp))
        }
        let forHP = heal > 0 ? (missing.hp + heal - 1) / heal : 0
        let forMP = mp > 0 ? (missing.mp + mp - 1) / mp : 0
        return max(forHP, forMP)
    }

    /// Uses a potion or ether up to `times` times on the same one (playtesting 2026-10-26: "select
    /// the amount"), stopping once it wouldn't help any more or there's none left. How many were
    /// used, and a message.
    @discardableResult
    func use(_ id: String, times: Int, onPet petID: UUID? = nil) -> (used: Int, note: String?) {
        var used = 0
        var note: String?
        while used < times, count(of: id) > 0 {
            let before = count(of: id)
            let result = use(id, onPet: petID)
            guard count(of: id) < before else {
                if used == 0 { note = result }
                break
            }
            used += 1
            note = result
        }
        if used > 1, let note, let name = content.item(id)?.name {
            return (used, L("{item} ×{count}: {result}", ["item": name, "count": used, "result": note]))
        }
        return (used, note)
    }

    // MARK: - Quests

    enum QuestStatus: Equatable {
        case locked
        case available
        case active(progress: Int, goal: Int)
        case ready
        case completed
    }

    enum QuestNotice {
        case available, ready
    }

    func goal(of quest: QuestDef) -> Int {
        quest.objective.type == .chooseClass || quest.objective.type == .deliver ? 1 : (quest.objective.count ?? 1)
    }

    /// How hard a quest is for the hero now: how hard it is in itself (`baseDifficulty(of:)`),
    /// eased or toughened by how the level of what it has you fight compares with the hero's
    /// (playtesting 2026-10-23: "if I need to beat enemies that are way lower level than me, the
    /// quest difficulty is easy"). Twenty levels under the hero is easy whatever the quest.
    func difficulty(of quest: QuestDef) -> QuestDifficulty {
        let base = baseDifficulty(of: quest)
        guard let level = level(of: quest) else { return base }
        let gap = level - data.hero.level
        if gap <= -20 { return .easy }
        let step = gap <= -8 ? -1 : gap >= 20 ? 2 : gap >= 8 ? 1 : 0
        return QuestDifficulty(rawValue: min(max(base.rawValue + step, 1), QuestDifficulty.elite.rawValue)) ?? base
    }

    /// The level of what a quest has you fight (`Content.habitatLevel`): its target's, or for one
    /// that asks for drops, the gentlest of the monsters that drop them. Nil for one with no fight.
    func level(of quest: QuestDef) -> Int? {
        switch quest.objective.type {
        case .defeat, .capture:
            return quest.objective.target.flatMap(content.habitatLevel)
        case .bring:
            return (quest.drops ?? []).flatMap(\.from).compactMap(content.habitatLevel).min()
        case .cards, .collect, .hatch, .reachLevel, .chooseClass, .deliver:
            return nil
        }
    }

    /// How hard a quest is in itself: as it says (`QuestDef.difficulty`), else by what it asks. Fights
    /// with a boss and long hunts are hard; a handful of monsters, an errand or a level to reach is easy.
    func baseDifficulty(of quest: QuestDef) -> QuestDifficulty {
        if let set = quest.difficulty.flatMap(QuestDifficulty.init(rawValue:)) { return set }
        let count = quest.objective.count ?? 1
        switch quest.objective.type {
        case .defeat, .capture:
            if quest.objective.target.flatMap(content.monster)?.boss == true { return .hard }
            return count >= 12 ? .hard : count >= 8 ? .normal : .easy
        case .bring:
            let made = quest.objective.target.flatMap(content.item)?.make != nil
            let scarce = (quest.drops ?? []).contains { $0.chance < 0.35 }
            return made || scarce || count >= 5 ? .normal : .easy
        case .cards:
            return count >= 50 ? .hard : count >= 20 ? .normal : .easy
        case .collect, .hatch, .reachLevel, .chooseClass, .deliver:
            return .easy
        }
    }

    func status(of quest: QuestDef) -> QuestStatus {
        if let progress = data.quests[quest.id] {
            if progress.state == .completed { return .completed }
            let goal = goal(of: quest)
            let current: Int = switch quest.objective.type {
            case .defeat, .capture, .collect, .hatch: progress.count
            case .reachLevel: data.hero.level
            case .chooseClass: data.hero.classID == "novice" ? 0 : 1
            case .cards: cardCount
            case .bring: min(goal, quest.objective.target.map { count(of: $0) } ?? 0)
            case .deliver: min(goal, progress.count)
            }
            return current >= goal ? .ready : .active(progress: current, goal: goal)
        }
        let prerequisitesDone = (quest.requires ?? []).allSatisfy { data.quests[$0]?.state == .completed }
        let levelOK = data.hero.level >= (quest.minLevel ?? 1)
        return prerequisitesDone && levelOK ? .available : .locked
    }

    func quests(from giver: String) -> [QuestDef] {
        content.quests.filter { $0.giver == giver && status(of: $0) != .locked }
    }

    /// The one quest a giver talks to you about (playtesting 2026-10-25: "One should be completed
    /// first with storytelling"): one you've done to hand in, else the one you're on for them, else
    /// the next they have for you, in the game's order. Nil when they have nothing (`questGiverNote`).
    func currentQuest(from giver: String) -> QuestDef? {
        let theirs = quests(from: giver)
        return theirs.first { status(of: $0) == .ready }
            ?? theirs.first { data.quests[$0.id]?.state == .active }
            ?? theirs.first { status(of: $0) == .available }
    }

    /// Whether you're on a quest for `giver`: they give you no other till it's handed in.
    func isOnQuest(for giver: String) -> Bool {
        content.quests.contains { $0.giver == giver && data.quests[$0.id]?.state == .active }
    }

    /// What a quest giver with nothing for the hero says: why (a level to reach, someone else's
    /// quest to finish first, or nothing left at all), and once they're all done, who has work
    /// instead: the quest open to you now that suits your level best, or else the next to open.
    func questGiverNote(_ giver: String) -> String {
        let locked = content.quests.filter { $0.giver == giver && status(of: $0) == .locked }
        let done = { (id: String) in self.data.quests[id]?.state == .completed }
        if let level = locked.filter({ ($0.requires ?? []).allSatisfy(done) }).map({ $0.minLevel ?? 1 }).min() {
            return L("Come back at level {level}, and I'll have something for you.", ["level": level])
        }
        if let first = locked.flatMap({ $0.requires ?? [] }).compactMap(content.quest).first(where: { !done($0.id) }),
           let who = content.npc(first.giver), let place = content.home(ofNPC: first.giver) {
            return L("Finish “{quest}” for {giver} in {place} first, and come back to me.",
                     ["quest": first.title, "giver": who.name, "place": place.name])
        }
        var note = L("That's all I had for you. Thank you!")
        let elsewhere = content.quests.filter { $0.giver != giver }
        let opensAt = { (quest: QuestDef) in quest.minLevel ?? 1 }
        if let now = elsewhere.filter({ status(of: $0) == .available }).max(by: { opensAt($0) < opensAt($1) }),
           let who = content.npc(now.giver), let place = content.home(ofNPC: now.giver) {
            note += " " + L("{giver} in {place} has work for someone like you.", ["giver": who.name, "place": place.name])
        } else if let later = elsewhere.filter({ status(of: $0) == .locked && opensAt($0) > data.hero.level }).min(by: { opensAt($0) < opensAt($1) }),
                  let who = content.npc(later.giver), let place = content.home(ofNPC: later.giver) {
            note += " " + L("{giver} in {place} will have work for you at level {level}.",
                            ["giver": who.name, "place": place.name, "level": opensAt(later)])
        }
        return note
    }

    /// The quests you're on, the one you took last first (playtesting 2026-10-16: new quests at the
    /// top), then any taken before 0.7.19 kept no date, in the order the game lists them.
    var activeQuests: [QuestDef] {
        Self.latestFirst(content.quests.filter { data.quests[$0.id]?.state == .active }) { data.quests[$0.id]?.taken }
    }

    /// Whether a map's minimap shows only what you've seen: a dark map you don't have the whole map of.
    func isFogged(_ map: MapDef) -> Bool {
        map.ambience?.darkness != nil && !isCharted(map)
    }

    /// Whether you have a dark map's whole map (`MapDef.chart`): its quest is done.
    func isCharted(_ map: MapDef) -> Bool {
        map.chart.map { data.quests[$0]?.state == .completed } ?? false
    }

    /// A quest's number in the Quests list: where it comes in content/quests.json, from 1.
    func questNumber(_ quest: QuestDef) -> Int {
        (content.quests.firstIndex { $0.id == quest.id } ?? 0) + 1
    }

    /// The quests you've handed in, the one you finished last first, as `activeQuests`.
    var completedQuests: [QuestDef] {
        Self.latestFirst(content.quests.filter { data.quests[$0.id]?.state == .completed }) { data.quests[$0.id]?.finished }
    }

    /// `quests` with a date the latest first, then those without one in their order.
    private static func latestFirst(_ quests: [QuestDef], by date: (QuestDef) -> Date?) -> [QuestDef] {
        let dated = quests.compactMap { quest in date(quest).map { (quest: quest, date: $0) } }
        return dated.sorted { $0.date > $1.date }.map(\.quest) + quests.filter { date($0) == nil }
    }

    /// The favours you're doing that end with `npcID` (`deliver` quests you're on): something to
    /// hand them, not handed over yet.
    func errands(for npcID: String) -> [QuestDef] {
        content.quests.filter { quest in
            quest.objective.type == .deliver && quest.objective.target == npcID
                && data.quests[quest.id]?.state == .active && data.quests[quest.id]?.count == 0
        }
    }

    /// Hands over what a `deliver` quest takes to its `target` (if it's still in the bag), takes
    /// what they give back for the one who asked, and returns what they say. Nil if it isn't
    /// waiting on them.
    @discardableResult
    func deliver(_ id: String) -> String? {
        guard let quest = content.quest(id), let target = quest.objective.target, errands(for: target).contains(where: { $0.id == id })
        else { return nil }
        if let item = quest.objective.item { removeItem(item) }
        data.quests[id]?.count = 1
        SoundEffects.shared.play(.questAccept)
        let who = content.npc(target)?.name ?? target
        let giver = content.npc(quest.giver)?.name ?? quest.giver
        if let back = quest.objective.returns, let item = content.item(back) {
            addItem(back, force: true)
            post(L("{name} gave you {item}. Take it back to {giver}.", ["name": who, "item": item.name, "giver": giver]), .quest)
        } else {
            post(L("Delivered to {name}. Go back to {giver}.", ["name": who, "giver": giver]), .quest)
        }
        return quest.objective.text ?? L("For me? How kind! Tell {giver} thank you.", ["giver": giver])
    }

    func notice(for giver: String) -> QuestNotice? {
        // Someone waiting on a favour you're carrying to them.
        if !errands(for: giver).isEmpty { return .ready }
        if let npc = content.npc(giver), npc.role == .chest {
            return canOpen(npc) ? .available : nil
        }
        // The weaver, with a cape you've earned to weave.
        if content.npc(giver)?.role == .weaver {
            return capeReady ? .available : nil
        }
        let statuses = content.quests.filter { $0.giver == giver }.map { status(of: $0) }
        if statuses.contains(.ready) { return .ready }
        // One quest at a time: nothing new from them while you're on one of theirs.
        if statuses.contains(.available) && !isOnQuest(for: giver) { return .available }
        return nil
    }

    /// The elder's three gifts used to be gift boxes hidden around Meadowbrook. A save from then
    /// that took his quest without finding every box gets the missing gifts now, once.
    func handOutMissingStarterGifts() {
        guard data.version < 2 else { return }
        data.version = 2
        guard data.quests["hope_of_meadowbrook"]?.state == .active else { return }
        let boxes = [("gift_box_1", "wooden_sword"), ("gift_box_2", "novice_ring"), ("gift_box_3", "pet_egg")]
        for (box, item) in boxes where data.openedChests?.contains(box) != true {
            addItem(item, force: true)
            data.openedChests = (data.openedChests ?? []) + [box]
            if let name = content.item(item)?.name { post(L("Elder Oak left you a {item}.", ["item": name]), .reward) }
        }
    }

    func acceptQuest(_ id: String, answer: QuestDef.Question.Answer? = nil) {
        guard let quest = content.quest(id), status(of: quest) == .available, !isOnQuest(for: quest.giver) else { return }
        data.quests[id] = QuestProgress(state: .active, count: 0, taken: Date())
        SoundEffects.shared.play(.questAccept)
        if let answer { data.eggSpecies = answer.egg }
        post(L("Quest accepted: {quest}", ["quest": quest.title]), .quest)
        let starters = quest.starterItems ?? []
        // A quest's own things: they go in whatever the bag holds.
        for item in starters { addItem(item, force: true) }
        // "Received 3 Seal Stones." / "Received Wooden Sword, Novice Ring and Pet Egg."
        if let list = itemList(starters) {
            post(L("Received {items}.", ["items": list]), .reward)
        }
    }

    /// What the quests you're on have a beaten wild monster of `species` drop (`QuestDef.drops`):
    /// each item one wants that it drops, as often as its chance has it, till you have enough.
    func questDrops(from species: String) -> [ItemDef] {
        var found: [ItemDef] = []
        // Not once you've what it asks for (a carved flute: no more driftwood for it).
        for quest in activeQuests where status(of: quest) != .ready {
            for drop in quest.drops ?? [] where drop.from.contains(species) {
                let enough = drop.upTo ?? goal(of: quest)
                guard count(of: drop.item) < enough, let item = content.item(drop.item),
                      Double.random(in: 0..<1) < drop.chance, addItem(item.id) else { continue }
                found.append(item)
            }
        }
        return found
    }

    /// What you could make by hand from the bag with `item` for a quest you're on (`ItemDef.make`):
    /// the thing a quest asks you to bring, carved or joined from it, if you haven't got it yet.
    func handmade(using item: ItemDef) -> ItemDef? {
        for quest in activeQuests where quest.objective.type == .bring {
            guard let id = quest.objective.target, let made = content.item(id), made.make != nil,
                  made.recipe?[item.id] != nil, count(of: id) < goal(of: quest) else { continue }
            return made
        }
        return nil
    }

    /// Makes an item by hand from the bag (`ItemDef.make`): carves it, or pieces it together, from
    /// its `recipe`.
    @discardableResult
    func make(_ id: String) -> Bool {
        guard let item = content.item(id), let how = item.make, craft(id) else { return false }
        SoundEffects.shared.play(.equip)
        Haptics.success()
        switch how {
        case .carve: post(L("You carved {item}.", ["item": item.name]), .reward)
        case .join: post(L("You pieced together {item}.", ["item": item.name]), .reward)
        }
        return true
    }

    /// Counts a defeat or capture toward matching active quests.
    func record(_ type: QuestDef.ObjectiveType, target: String?) {
        for quest in activeQuests where quest.objective.type == type {
            if let wanted = quest.objective.target, wanted != target { continue }
            data.quests[quest.id]?.count += 1
        }
    }

    /// What someone shows as on the minimap and the world map (`MinimapIcon`): a quest giver as their
    /// mark says ("!" news, "?" done), the healer, the shop, the smith, the weaver (or her news), the
    /// barber, a guild, a boss, stairs, a waystone, and a chest still to open; nil for an opened chest.
    func minimapKind(for npc: NPCDef) -> MinimapMark.Kind? {
        if !errands(for: npc.id).isEmpty { return .questReady }
        switch npc.role {
        case .healer: return .healer
        case .shop: return .shop
        case .smith: return .smith
        case .weaver: return notice(for: npc.id) == nil ? .weaver : .questNew
        case .barber: return .barber
        case .bank: return .bank
        case .guild: return .guild
        case .boss: return .boss
        case .stairs: return Content.shared.leadsDown(npc) ? .stairsDown : .stairsUp
        case .chest: return isOpened(npc.id) ? nil : .chest
        case .waystone: return .waystone
        case .quests:
            switch notice(for: npc.id) {
            case .ready?: return .questReady
            case nil: return .quest
            default: return .questNew
            }
        }
    }

    func isDefeated(_ boss: NPCDef) -> Bool {
        data.defeatedBosses?.contains(boss.id) == true
    }

    /// Bosses beaten since arriving on this map. They're back for a rematch next visit.
    var bossesBeatenHere: Set<String> = []

    func isBeatenHere(_ boss: NPCDef) -> Bool {
        bossesBeatenHere.contains(boss.id)
    }

    /// Every win rolls the boss's rare drops (the colour variants of top armour).
    func defeatBoss(_ boss: NPCDef) {
        bossesBeatenHere.insert(boss.id)
        if !isDefeated(boss) {
            data.defeatedBosses = (data.defeatedBosses ?? []) + [boss.id]
        }
        let species = boss.monster.flatMap(content.monster)
        for drop in species?.drops ?? [] where Double.random(in: 0..<1) < drop.chance {
            guard let item = content.item(drop.item), addItem(item.id) else { continue }
            post(L("{monster} dropped {item}!", ["monster": species?.name ?? boss.name, "item": item.name]), .reward)
        }
        checkTitles()
        save()
    }

    func hasCompleted(_ questID: String) -> Bool {
        data.quests[questID]?.state == .completed
    }

    /// Quests open new roads.
    func canTravel(_ exit: MapDef.Exit) -> Bool {
        exit.requires.map(hasCompleted) ?? true
    }

    /// Whether you've been to a map (saves from before this was tracked know the start town,
    /// the current map and the last checkpoint).
    func hasVisited(_ mapID: String) -> Bool {
        data.visitedMaps?.contains(mapID) == true || mapID == data.mapID
            || mapID == content.startMap || mapID == data.checkpoint?.mapID
    }

    /// A species met in battle goes into the Monster Book (or widens the levels it was met at).
    func sawMonster(_ id: String, level: Int) {
        var book = data.monsterBook ?? [:]
        if var entry = book[id] {
            entry.lowestLevel = min(entry.lowestLevel, level)
            entry.highestLevel = max(entry.highestLevel, level)
            book[id] = entry
        } else {
            book[id] = MonsterSighting(lowestLevel: level, highestLevel: level)
        }
        data.monsterBook = book
    }

    func beatMonster(_ id: String, level: Int) {
        sawMonster(id, level: level)
        data.monsterBook?[id]?.defeated += 1
    }

    func sighting(of id: String) -> MonsterSighting? { data.monsterBook?[id] }

    func markVisited(_ mapID: String) {
        guard data.visitedMaps?.contains(mapID) != true else { return }
        data.visitedMaps = (data.visitedMaps ?? []) + [mapID]
        checkTitles()
    }

    /// What handing in `quest` pays: its own gold and EXP, whatever your level (playtesting
    /// 2026-10-20: "the xp you can win from a quest should be fixed [...] not based on my current
    /// level"; from 0.3.63 an outgrown quest paid for your level instead).
    func questPay(_ quest: QuestDef) -> (gold: Int, exp: Int) {
        (quest.reward.gold ?? 0, quest.reward.exp ?? 0)
    }

    /// What a finished quest paid: as noted when it was handed in, else (before 0.3.63) its own reward.
    func paid(for quest: QuestDef) -> (gold: Int, exp: Int) {
        let record = data.quests[quest.id]
        return (record?.paidGold ?? quest.reward.gold ?? 0, record?.paidEXP ?? quest.reward.exp ?? 0)
    }

    /// Hands in a finished quest and pays out. Returns what was earned.
    @discardableResult
    func turnInQuest(_ id: String) -> [String] {
        guard let quest = content.quest(id), status(of: quest) == .ready else { return [] }
        let pay = questPay(quest)
        // What it asked you to bring is handed over.
        if quest.objective.type == .bring, let item = quest.objective.target {
            for _ in 0..<goal(of: quest) { removeItem(item) }
        }
        // What the one you did the favour for sent back.
        if quest.objective.type == .deliver, let item = quest.objective.returns { removeItem(item) }
        data.quests[id]?.state = .completed
        data.quests[id]?.finished = Date()
        data.quests[id]?.paidGold = pay.gold
        data.quests[id]?.paidEXP = pay.exp
        SoundEffects.shared.play(.questDone)
        Haptics.success()
        post(L("Quest complete: {quest}", ["quest": quest.title]), .quest)
        var lines: [String] = []
        if pay.gold > 0 {
            gainGold(pay.gold)
            lines.append(L("+{gold} gold", ["gold": pay.gold]))
        }
        if pay.exp > 0 {
            lines.append(L("+{exp} EXP", ["exp": pay.exp]))
            if gainHeroEXP(pay.exp) > 0 { lines.append(L("Level up! You're now level {level}.", ["level": data.hero.level])) }
        }
        // What doesn't fit is left behind; a quest's treasure waits instead, and comes once there's
        // room (`deliverQuestTreasures`).
        for itemID in quest.reward.items ?? [] where addItem(itemID) {
            lines.append(L("Got {item}", ["item": content.item(itemID)?.name ?? itemID]))
            if content.isQuestTreasure(itemID) { data.questTreasuresGiven = (data.questTreasuresGiven ?? []) + [itemID] }
        }
        for map in content.maps {
            for exit in map.exits where exit.requires == id {
                let place = content.map(exit.to)?.name ?? exit.to
                lines.append(exit.ship == true ? L("The ship from {from} to {map} is ready to sail!", ["from": map.name, "map": place])
                             : L("The road from {from} to {map} is open!", ["from": map.name, "map": place]))
            }
            for stone in map.npcs ?? [] where stone.role == .waystone && stone.quest == id {
                lines.append(L("The waystone in {map} is awake! Touch it to travel.", ["map": map.name]))
            }
        }
        checkTitles()
        return lines
    }
}
