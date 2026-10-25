# Launch audit (2026-10-06, at 0.3.60)

What stands between Tales of Dorlune and the App Store, what's broken or off-balance, and what would bring players
back. Six read-throughs of the code and content (battle, saves and app lifecycle, world and performance, UI with
accessibility and translation, content and balance, App Store readiness), Python battle simulations that copy the
engine's formulas, and the CI screenshots. Every finding here was checked against the code; numbers marked
*est.* come from simulations or models, not from a phone. Tick items off or delete them as they're done.

## Fixed in 0.3.60

- A fight froze for good when AUTO was tapped while the battle buttons wiggled to be rearranged.
- A beaten boss could miss its promised gear drop when two followers dropped gear first; the boss now rolls first.
- Capture waits for a boss's last wave: a monster sealed in an earlier wave was lost, Seal Stone and all, if the
  player then lost or ran.
- Music comes back after a call, Siri, an alarm or a change of headphones or speaker.
- The first title screen speaks the chosen language (the default hero name); save cards' dates follow it, and
  "Played {time}" no longer reads as play time in seven languages.
- `CFBundleLocalizations` lists the 11 languages, so the App Store page and system screens (the Files pickers)
  aren't English-only.
- `PrivacyInfo.xcprivacy` (UserDefaults CA92.1, file timestamps C617.1 and DDA9.1), and CI fails without it.
- The intro's last page buttons no longer overflow; two node retain cycles in `GearArt`; the Silverfang Warden's
  victory text no longer says "Lieutenant".
- Villagers' names are translated (`villagerNames` was missing from `content/i18n/fields.json`, so they were the
  only names left in English).
- Landscape App Store slides: `store_land_*` scenes (debug `clean`: no frame counter, no Dynamic Island mask;
  `nohud` for the map) and `tools/store_slides.py`, which captions them and exports both sizes without alpha.

## Done in 0.3.61

- Moderator mode is gone: no `/mod` code, MOD tag or World channel left for App Review to find (2.3.1).
- The Red Bull is the Blaze Bull in every language (the Chinese 红牛/紅牛 and Italian "Toro Rosso" were Red Bull
  brands too), and the changelog no longer promises online play.
- Frost Breath freezes 30% of the time instead of always.
- Gentler first fights: Sunny Meadow 1-4 in ones and twos, Windswept Downs 3-10, Pineapple Harvest from level 8.
- Settings → Battle → Time to choose: Off, 10, 20 or 30 seconds; no clock with VoiceOver or Switch Control on.
- Reasons to come back: 32 titles worn over your name (bots wear theirs), daily bounties with a bonus, a daily
  gift in a round of seven, Monster Book milestones, and rebirth worth more (EXP boost, titles, name colour).
  Rebirth itself went in 0.7.27: level 200 is the top, with Elder Oak's Goldleaf gear to earn there.

## Before you submit

### Blockers

1. **Privacy policy.** App Store Connect requires a Privacy Policy URL for iOS apps, and guideline 5.1.1(i) also
   wants a link inside the app. Host a short page (nothing is collected; saves stay on the device; no ads,
   analytics, accounts or network) somewhere neutral, then add a "Privacy policy" link to Settings → About,
   translated. App Privacy can honestly say "Data Not Collected".
2. **Support URL, copyright and App Review contact.** All required. The Support URL "must lead to actual contact
   information".
3. **Screenshots.** At least one for "iPhone with Dynamic Island (medium display)" is required, and 1206×2622 (the
   CI size) is accepted. But "Images can't include alpha channels or transparencies", and CI's PNGs are RGBA;
   Debug builds also show SpriteKit's FPS and node counter in map and battle shots (only `demo` hides it). The
   6.5" set is required unless the large Dynamic Island set (1320×2868) is provided, so shoot the store scenes
   once on an iPhone 17 Pro Max simulator too. Flatten to JPEG (`sips -s format jpeg`) and add a `clean` debug
   flag for the counter. Lead with gameplay, not the title screen (2.3.3).
4. **Age rating.** Expect 13+: frequent cartoon or fantasy violence is 13+ on its own, and infrequent alcohol
   references (the Drunk Dragon and its hangover quest) are 13+ too. Don't choose Made for Kids.
5. **Where it's sold.** Untick China mainland (games need an NPPA approval number) and Vietnam (games must be
   licensed there). Declare your EU trader status (DSA) in App Store Connect.
6. **The name: Tales of Dorlune** (since 0.8.10; Talewild before). Set it as the app's name (and a subtitle) in
   App Store Connect, the wordmark in `Logo.png` (the store slides draw it too), and search TALES OF DORLUNE and
   DORLUNE on the USPTO, EUIPO and J-PlatPat registers (docs/fairyland-online.md → Names: Bandai Namco's Tales
   marks). A domain and social handles for the new name are still to find: talewild.app and its handles were
   bought for the old one. The privacy policy and support pages above can live on the domain.

### Strongly recommended

- **Ship as 1.0.0 with a launch changelog.** The title screen's "What's new" lists 60+ pre-release entries (crash
  fixes, playtests), which reads like a beta (2.2).
- **Say the adventurers are computer-run.** The first-play tour says "Adventurers wander Dorlune too. Read what
  they say and chat back here." (`CoachMarks.swift`) without saying they're bots. Mention it there and in the
  review notes, and keep chat shots out of the listing, so nothing reads as real players' content (1.2).
- **Iconaut's MIT notice.** MIT asks for its copyright and permission notice in copies; Settings only says
  "icons by Iconaut (MIT)" and `third_party/iconaut/LICENSE` isn't in the bundle. Add an Acknowledgements screen.
- **Test where reviewers look.** iPhone-only apps run on iPads in compatibility mode, and reviewers often use
  iPads; also try a 375-pt iPhone (SE). iPhone apps are offered on Apple silicon Macs and Vision Pro by default:
  opt out unless you've tried them there.
- **Profile on an older iPhone (A12/A13)** with Instruments before launch (see Performance below).
- **Keep the listing clean of the original**: no Fairyland Online, LagerNet, Tales of Mysteria, "tribute",
  "remake", "inspired by", "MMO", "online" or "multiplayer" in the name, subtitle, keywords, description,
  screenshots or review notes.
- **App preview (optional).** 15-30 s, 886×1920 portrait, at most 30 fps, H.264 with stereo AAC audio. The CI
  `gameplay` recording is 58 s at 1206×2622 with no sound, so cut and convert it (ffmpeg) before uploading.
- `art/spend-log.jsonl` (Retro Diffusion prompts and spend) ships inside the app, because `art/` is a folder
  reference. Nothing secret, but move it out of `art/`.

### Review notes (ready to paste)

> Tales of Dorlune is a single-player RPG that runs entirely offline: no accounts, no network connections, no ads, no
> in-app purchases, no tracking and no data collection. Everyone else in the world is computer-controlled:
> villagers, traders and the adventurers marked BOT, who wander, post pre-written chat lines, can be befriended
> to join your party, and may challenge you to duels in danger zones. There are no other human players. The chat
> window is part of this simulation: what you type stays on your device, and bots may answer with canned lines.
> Saves stay on the device; Settings > Back up to Files exports a save, and Import a backup on the title screen
> (in its Settings once a game exists) restores it. Quick tour: New game, then the story and a short tour; walk into Sunny Meadow for battles; weaken
> the last monster below 20% HP and use Capture with a Seal Stone; tap a BOT adventurer, then Befriend.

## Bugs and balance, most important first

### High

1. **Performance on the wooded maps** (*est.*, needs a phone). Since 0.5.0 scenery is parented to 400-point
   chunks and only those near the camera are in the scene (`WorldScene.showChunks`), so Twilight Woods, Snow
   White Forest, Smiling Forest and Frog Swamp no longer keep their 10-12k nodes and 3.5-4.7k actions live.
   Still to do on an iPhone XS or 11: profile walking toward a border, where the land next door builds a few
   milliseconds a frame (the tests print the longest slice, ⏱), and memory with two or three lands loaded.
2. **Memory grows with every map visit** (*est.* rate). Each new villager or adventurer look caches a recoloured
   sheet in `ArtLibrary` for good; nothing evicts them and nothing handles memory warnings. Fix: an LRU cap on
   runtime looks, and a purge on memory warnings.
   - Playtesting 2026-10-12: the app sometimes crashes as a battle starts. A code audit found no Swift trap on
     that path; likeliest is memory at its peak (the map still loaded, a full-resolution snapshot of it read back
     and blurred on the CPU with a new Core Image context every battle). Since 0.4.12 it's blurred at half size
     with one shared context and only the blurred copy is kept, and a battle can no longer start on top of a
     conversation or another battle (`GameCoordinator`'s battle guards, `WorldScene.checkCell`). Still open: the
     purge on memory warnings above, and the phone's crash log (Settings › Privacy & Security › Analytics &
     Improvements › Analytics Data: a `JetsamEvent` means memory) to confirm.
3. **Nothing teaches befriending, the biggest difficulty lever** (*est.* hero and companion alone win 9-83% of
   fights on mid-level maps, 54-100% with two friends): neither How to play nor the first-play tour mentions it.
   Add a tip or a coach mark. The Wisdom answer also hatches a Jelly Puff, clearly weaker than the other two eggs.

### Medium

4. **Save failures are silent.** `SaveStore.save` only prints the error, and `GameSession.save()` sets `lastSaved`
   anyway, so with full storage the HUD keeps saying "Saved" and "Save and leave" quits. Return success, warn the
   player, and only show "Saved" when it worked.
5. **Some battle results are only saved after Continue.** A captured monster waiting for a party slot
   (`pendingPet`) lives only in memory, and the boss's rare drop and "defeated" flag run when the result card
   closes. A call or a crash on the result card loses them. Roll them before the victory's save; persist the
   waiting companion.
6. **The save format is fragile for updates.** Synthesized `Codable` makes every non-optional field required
   (`SaveData.version`, `MonsterSighting.defeated`, `Adventurer.id`/`hostile` despite their defaults), and
   `SaveStore.all()` drops a save it can't decode with `try?`. One new non-optional field in an update would hide
   every player's game from the title screen. Write `init(from:)` with `decodeIfPresent`, and add a test that
   decodes a saved 0.3.x file.
7. **Quest gates can be walked round, and some roads are level cliffs.** Windswept Downs → Pineapple Shore and Swan
   Lake → Snow White Forest have no gate while other roads into the same maps do. Ungated roads jump from Frog
   Swamp (21-35) to Ingothold Lake (58-72), from Ingothold Lake to Briarmere (135-155) and from Moonwhisper
   (85-105) to Whispering Hollow (165-185). Either gate every road in (and have `check_content.py` check it) or
   drop the barricades and show recommended levels.
8. ~~Quest rewards are out of scale.~~ Done in 0.3.63: a quest pays at least 0.3× the EXP your level needs and 12
    gold a level when you hand it in (`quests` in content/rewards.json, a bit more than a bounty), or its own reward
    when that's more, and every quest row shows what it pays. The Elder, Chief and Mayor chain used to pay 6-15% of
    a level (The Rat King: 900 EXP at level 45).
9. **The late game thins out.** Gear stops at level 105 for weapons, 78 for armour and 58 for accessories while
    levels run to 200 (Snow Cloak ends up on every late hero and bot), and late maps reuse low-EXP species, so
    *est.* 25-30 fights per level at 160-180 against 4-6 before 100. Extend the gear lines (free `derive`
    recolours) and add a per-map EXP multiplier.
10. **Classes run out of things to learn.** Mage attack spells cover fire, earth and wood only, so there's no
    weak-spot spell for 72 of 105 species or the final Emerald Dragon (wood). Fighters have 5 skills (last at 40)
    and Tamers 6, so their points pile up after about level 50-60. Advanced classes (below) fix this properly.
11. **Selling takes one tap, with no confirmation**, and when a stack runs out the next row slides under your
    finger, so the next tap sells something else. Keep sold-out rows in place until the panel reopens; confirm
    for gear and gems.
12. **Layout.** The guild's "This choice is permanent" row, the smith's weapon tabs, the adventurer card in danger
    zones and the first quest's three answers don't fit in some languages; in landscape the world map's close
    button is cut off and the NPC bubble sits under the Dynamic Island.
13. **"Leave {name} behind" deletes the companion for good**, with no confirmation (`GameSession.leaveBehind`).
    Say "Release" and confirm.
14. **Rare soft-lock.** With five companions the starter egg can't hatch and there's no release button, which
    blocks Hope of Meadowbrook (a hatch quest) and the Elder's quests after it.
15. ~~**The English tagline is part of the logo**~~ Done in 0.8.1: the logo has no tagline, just the
    wordmark (TALES OF DORLUNE in gold since 0.8.10, `tools/logo_art.py`), the same in every language.
16. **The music synth runs all the time**, muted or not (*est.* a few % of a core for the whole session). Stop the
    engine while muted or at volume 0.

### Low

- Losing a fight doesn't write the companion's damage back (`syncParty()` isn't called on defeat).
- Revive spends its MP when its target was already revived; potions can be used on full-HP targets and show
  "+0 MP".
- No Dynamic Type, several tap targets under 44 pt (the minimap's music toggle sits next to its ✕), and looping
  pulses that ignore Reduce Motion.
- `L()` replaces placeholders one at a time, so a hero named "{level}" gets substituted.
- Backgrounding mid-battle saves the potions and Seal Stones already used without the fight's progress.
- A battle or map change can start while a dialog is open; a pinch starts a walk; tap-walking cuts tree corners.
- Walking up or down covers twice the ground per second as walking sideways (the joystick moves in screen points),
  so encounters come twice as often.
- `UIRequiresFullScreen` is deprecated and does nothing for an iPhone-only app.

## Gamification and new mechanics

The first fights are gentler now (0.3.61); teaching befriending (High 3) is the next most useful thing. The rest
is ranked by value for effort, built on Fairyland Online's own systems where it had them
(`docs/fairyland-online.md`), and all of it works offline. Keep it cozy: gifts rather than punishing streaks, and
no loot boxes, energy timers or paid currency.

**Done in 0.3.61:** titles worn over your name (bots wear theirs), Monster Book milestones, daily bounties with
a bonus and a daily gift in a round of seven, and rebirth worth doing (a battle EXP boost, titles and a name
colour; bonus skill points were dropped, since a reborn hero keeps their spent points and couldn't use them until
past their old level). Next: show the gift's round and the bounties on the HUD so they're found without opening
Quests, and ask for a rating after the first boss win (`requestReview`, three prompts a year at most).

**Soon after launch:**

1. **Seasonal events.** Halloween falls in the launch window: a dated `content/events.json`, a sighting boost, a
   recoloured outfit via `derive` and an event title.
2. **Opt-in local notifications** for the daily board and rare sightings. No server needed.
3. **Cards and dolls** (FO): monster drops collected in the Book. Cards done in 0.3.69, each with its own
   bonus for good rather than set bonuses, plus companion toys and the toymaker's card quests. Dolls still to do.

**Bigger (1.1 and on), already on the roadmap in `docs/fairyland-online.md`:**

4. **Companion intimacy and fusions** (FO's Arms, Armor, Magic and Soul at 30, 50, 60 and 80): a reason to raise a
   favourite, and a way to grow strong without leaning on bot friends.
5. **Advanced classes at level 60** (FO), each new skill with its own animation: fills the empty skill points and
   the late game.
6. **Work skills feeding the smith** (FO's woodcutting, mining and others), and a forging fee as a gold sink.
7. **Hall of Fame and leaderboards**, ranked against the bots, who keep growing; later a weekly guild contest
   modelled on FO's Kingdom Wars.

## Sources

- App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- Screenshot specifications: https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications
- App preview specifications: https://developer.apple.com/help/app-store-connect/reference/app-preview-specifications
- App information (Privacy Policy URL, China mainland, Vietnam):
  https://developer.apple.com/help/app-store-connect/reference/app-information/app-information
- Platform version information (Support URL, copyright, review contact):
  https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information
- Age ratings: https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions
- Required-reason APIs: https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
