# Tales of Dorlune

A cozy 2.5D pixel-art RPG for iPhone (portrait and landscape), inspired by Fairyland Online (2007).
The bundle ID (`com.jurgenploeger.fairyland`) and the save files keep the game's first name, Fairyland; players know the game as Tales of Dorlune (since 0.8.11; Talewild from 0.8.1), set in the land of Dorlune, and the code and project are still called Storyleaf.
Built with SwiftUI + SpriteKit. Art is generated with [Retro Diffusion](https://www.retrodiffusion.ai).

## What's in the game

- **30 isometric maps** you walk between along winding roads, each with its own storybook name: towns
  (Meadowbrook, Prismhaven, Larkspur, dwarven Ingothold) with streets, shops, fairytale buildings and raised
  stone terraces, and wild zones from Sunny Meadow, the Windswept Downs and Gumdrop Peaks to Swan Lake,
  Lotus Land, Marionette Rise, Shiverdell, Genie Desert, Dozywick and Moonwhisper, then the level
  105–200 lands beyond: the Hidden Steppe, Sneezle Sands, Briarmere, the Tidewater Shrine, the Whispering Hollow and
  the Emerald Road. Quests open the roads onward.
- **Random encounters** in the wild (no monsters on the map), with **turn-based battles** fought where you
  stand. Big spells splash onto nearby monsters. Fourteen bosses wait on their maps behind two waves of ten of their followers, up to the Emerald Dragon at level 200.
- **Eleven languages:** English, Spanish, Portuguese (Brazil), French, German, Italian, Russian, Japanese,
  Korean, and Chinese (Simplified and Traditional), switched from the title screen or Settings.
- **105 monsters** across seven elements, including rare, tougher colour variants.
- **Capture like Fairyland Online:** throw a Seal Stone at the last monster standing once it's below 20% HP.
  It may break free or run away. Keep up to 5 companions; your first hatches from the starter quest's egg.
- **Classes and skills:** start as a Novice, join a guild at level 10. Each level gives a skill point to learn
  a new skill or power one up (levels 1–10), each with its own animation.
- **The long climb, like Fairyland Online:** zones run from level 1 to 200. Past level 100 each level takes
  more EXP (twice as much by 140), like the original's slow late game. Level 200 is the top, and there Elder
  Oak gives the Goldleaf gear, ivory and gold, to show for it. Roughly 145 hours of battling to level 200.
- **A living world:** villagers and other adventurers (computer-run for now, tagged BOT) wander and chat (see
  the chat window), you can befriend adventurers and bring up to four along in your party, with their
  companions (they fight on if you faint, and wait for you where you fell), and danger zones allow duels.
  Ingothold's square is a market of traders under signs, and announcements in the chat tell of dawn and dusk,
  arrivals, other adventurers' news and rare monster sightings. Moderators get a MOD tag and a World channel.
- **Customisation:** name, gender, hairstyle, hair, outfit and skin, all chosen when you make a hero; armour
  recolours your outfit and your weapon shows in hand.
- **Onboarding:** a new game opens with the story, how to play and a map of the whole world, and the first
  time you play a spotlight tour walks through the HUD (Previous, Next, Skip).
- Quests, shops, healers, checkpoints, an in-game calendar and an original storybook soundtrack (flutes, harp, music box, strings and more, synthesized on the device).

## Run it

Needs Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
make open        # generates Storyleaf.xcodeproj and opens it in Xcode
```

Pick a simulator or your iPhone in the Xcode toolbar and press ⌘R (or run `make sim`).

### On your iPhone

1. Connect the iPhone with a cable (the first time; after that Wi-Fi works), unlock it, and tap **Trust**.
2. On the iPhone: **Settings → Privacy & Security → Developer Mode → On** (it restarts).
3. In Xcode, pick your iPhone in the device menu and press ⌘R.
4. First launch only: **Settings → General → VPN & Device Management** → trust your Apple ID.

With a free Apple ID the app expires after 7 days. Press ⌘R again to reinstall.

## Editing the game (no code needed)

| File | What's in it |
|---|---|
| `content/maps.json` | maps, exits, themes, scenery, ambience, NPCs, encounter tables |
| `content/monsters.json` | species stats, elements, capture rates |
| `content/classes.json` | races, classes, stat growth, skill unlocks, class-choice level |
| `content/skills.json` | skills and spells, power, MP, element, battle animation |
| `content/items.json` | potions, eggs, equipment |
| `content/quests.json` | quests, objectives, rewards, the elder's question |
| `content/changelog.json` | release notes shown under "What's new" on the title screen (newest first) |
| `content/music.json` | the songs and their instruments, in a tracker-style note format (`tools/music_preview.py` renders them to WAV) |
| `art/assets.json` | every sprite and its Retro Diffusion prompt |

Rebuild after editing. The unit tests (⌘U) check that every reference between these files resolves.

## Art pipeline (Retro Diffusion)

```bash
cp .env.example .env         # paste your API key (retrodiffusion.ai → Dev Tools)
make art-list                # what's defined, what's generated
make art-cost                # free: what generating the missing sprites would cost
make art                     # generate missing sprites → art/sprites/<id>.png
```

Anything not generated yet shows as built-in placeholder pixel art.
`python3 tools/rd.py generate <id> --force --variants 4` gives you options, and `python3 tools/rd.py use <id> <file>` picks one.
Every generation is kept in `art-variants/<id>/`.

The app icon and title logo come from the Figma file and live in `Storyleaf/Resources/Assets.xcassets`.

## Screenshots without a Mac

Every push to a `claude/**` branch runs the **Screenshots** GitHub Action on a macOS runner. It builds the app
for the iOS Simulator, opens each scene in `tools/screenshots.txt` with the debug shortcuts below, and saves
the images to the `screenshots` branch in a folder named after the branch (also attached to the run as an
artifact). On a private repo, macOS runner minutes count 10× against the Actions allowance.

## Debug shortcuts

Set `STORYLEAF_DEBUG` in the scheme's environment variables (comma-separated):
`newgame`, `level=5`, `map=sunny_meadow`, `battle`, `menu=companions`, `npc=elder`, `landscape`.

## Project layout

```
project.yml            XcodeGen spec (source of truth for the Xcode project)
content/               game data (JSON)
art/                   sprite manifest + generated PNGs
tools/rd.py            Retro Diffusion client (Python standard library only)
Storyleaf/App/         app, coordinator, SpriteKit host, debug launch
Storyleaf/Model/       save data, session rules (levels, quests, items), calendar
Storyleaf/World/       isometric maps, walking, NPCs, ambience
Storyleaf/Battle/      battle engine, controller, scene, skill effects
Storyleaf/Audio/       storybook synth (additive instruments, drums, reverb) + music player
Storyleaf/Art/         sprite loading and placeholder art
Storyleaf/UI/          SwiftUI HUD, menus, dialogs, battle UI
StoryleafTests/        rules and content tests
```

## Working from your phone (no Mac needed)

Pushes to `main` are built by GitHub Actions (`.github/workflows/testflight.yml`): it archives the app, signs
it with Apple's cloud signing and uploads it to TestFlight, so every build lands on your iPhone through the
TestFlight app:

1. In App Store Connect, create the app (bundle id `com.jurgenploeger.fairyland`) and an internal TestFlight
   group with yourself in it; install **TestFlight** on the iPhone.
2. Add the repository secrets the workflow's header lists (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`,
   `APPLE_TEAM_ID`): an App Store Connect API key with the Admin role, and your team ID. Optionally
   `DEV_CERT_P12` and `DEV_CERT_PASSWORD`, one Apple Development certificate exported from Keychain Access
   (base64 of the .p12): without it, every build makes a new one and revokes the last, and Apple emails
   "Your Certificate Has Been Revoked" each time. Renew it when it expires, after a year.
3. From the Claude app on your phone, open a **Claude Code** cloud session on this repo. It can edit and push
   but can't run Xcode, so check game-data edits with `python3 tools/check_content.py` before pushing.
   To generate art there, add `RETRO_DIFFUSION_API_KEY` to the cloud environment's variables.
