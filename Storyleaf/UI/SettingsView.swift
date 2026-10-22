import SwiftUI
import UniformTypeIdentifiers

/// Sound, feel and game options. A tab in the menu, and a panel on the title screen (where
/// there's no game to save or leave, so `session` is nil).
struct SettingsView: View {
    var session: GameSession?
    var onQuitToTitle: (() -> Void)?
    /// The title screen's Import a backup (its file picker lives there).
    var onImportBackup: (() -> Void)?

    @AppStorage(GameSettings.musicVolumeKey) private var musicVolume = 1.0
    @AppStorage(GameSettings.soundVolumeKey) private var soundVolume = 1.0
    @AppStorage(GameSettings.soundEffectsKey) private var soundEffects = true
    @AppStorage(GameSettings.footstepsKey) private var footsteps = true
    @AppStorage(GameSettings.hapticsKey) private var haptics = true
    @AppStorage(GameSettings.dayAndNightKey) private var dayAndNight = true
    @AppStorage(GameSettings.weatherKey) private var weather = true
    @AppStorage(GameSettings.commandCompanionKey) private var commandCompanion = true
    @AppStorage(GameSettings.turnTimerKey) private var turnTimer = 10.0
    @AppStorage(GameSettings.battleSpeedKey) private var battleSpeed = 1.0
    @AppStorage(GameSettings.autoBattleKey) private var autoBattle = false
    @State private var music = MusicPlayer.shared
    @State private var justSaved = false
    @State private var confirmQuit = false
    @State private var confirmDelete = false
    @State private var backup: SaveBackup?
    @State private var exporting = false
    @State private var backedUp = false
    /// The language you play in shows as one line; Change opens the whole list.
    @State private var choosingLanguage = false
    @State private var localizer = Localizer.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section(L("Language"), icon: .globe) {
                Button {
                    withAnimation(Reveal.animation) { choosingLanguage.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text(localizer.current.name)
                        Spacer(minLength: 6)
                        Text(choosingLanguage ? L("Done") : L("Change"))
                            .foregroundStyle(HUDStyle.gold)
                        IconImage(.chevronDown, size: 11)
                            .foregroundStyle(HUDStyle.gold)
                            .rotationEffect(.degrees(choosingLanguage ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Language: {language}", ["language": localizer.current.name]))
                // Picking one rebuilds the menu in it, which folds the list away again.
                if choosingLanguage {
                    LanguageList()
                        .transition(.reveal)
                }
            }

            // Every kind of sound has its own switch, and its volume under it.
            section(L("Sound"), icon: .volume) {
                SoundRow(title: L("Music"), icon: music.isMuted ? .musicOff : .music,
                         isOn: Binding(get: { !music.isMuted }, set: { on in if on == music.isMuted { music.toggleMute() } }),
                         volume: $musicVolume)
                    .onChange(of: musicVolume) { _, volume in MusicPlayer.shared.setVolume(volume) }
                SoundRow(title: L("Sound effects"), icon: .volume, isOn: $soundEffects, volume: $soundVolume) {
                    SoundEffects.shared.play(.coins)
                }
                .onChange(of: soundEffects) { _, on in if on { SoundEffects.shared.play(.coins) } }
                SoundRow(title: L("Footsteps"), icon: nil, isOn: $footsteps)
            }

            section(L("Feel"), icon: .tap) {
                Toggle(L("Vibration on hits and rewards"), isOn: $haptics)
                    .onChange(of: haptics) { _, on in if on { Haptics.impact(.medium) } }
            }

            // The sky over the maps: the light follows the clock, and the weather comes and goes.
            section(L("World"), icon: .sun) {
                Toggle(L("Day and night"), isOn: $dayAndNight)
                Text(L("Off, it's always daytime."))
                    .font(HUDStyle.font(10))
                    .foregroundStyle(HUDStyle.dim)
                Toggle(L("Weather"), isOn: $weather)
                Text(L("Off, the sky stays clear: no rain, storms, fog or snow."))
                    .font(HUDStyle.font(10))
                    .foregroundStyle(HUDStyle.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            section(L("Battle"), icon: .paw) {
                Toggle(L("Choose your companion's moves"), isOn: $commandCompanion)
                Text(L("After your own choice, tell your companion what to do. Off, it fights on its own."))
                    .font(HUDStyle.font(10))
                    .foregroundStyle(HUDStyle.dim)
                TurnTimerRow(seconds: $turnTimer)
                Text(L("How long you have to pick each move before your hero attacks on their own. With VoiceOver or Switch Control on, there's no clock."))
                    .font(HUDStyle.font(10))
                    .foregroundStyle(HUDStyle.dim)
                    .fixedSize(horizontal: false, vertical: true)
                // The same switches as Pace and Auto behind More in a fight, kept from fight to fight.
                Toggle(L("Double-speed fights"), isOn: Binding(get: { battleSpeed > 1 }, set: { battleSpeed = $0 ? 2 : 1 }))
                Toggle(L("Auto in easy fights"), isOn: $autoBattle)
                Text(L("Easy fights are against wild monsters at least {count} levels below you. Both switches are also behind More in a fight.", ["count": BattleController.autoLevelGap]))
                    .font(HUDStyle.font(10))
                    .foregroundStyle(HUDStyle.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let session {
                section(L("Game"), icon: .book) {
                    HStack(spacing: 10) {
                        Button {
                            session.save()
                            SoundEffects.shared.play(.questAccept, volume: 0.6)
                            justSaved = true
                        } label: {
                            Label(justSaved ? L("Saved") : L("Save now"), icon: justSaved ? .check : .checkCircle)
                        }
                        .buttonStyle(PixelButtonStyle(compact: true))
                        if let onQuitToTitle {
                            Button {
                                confirmQuit = true
                            } label: {
                                Label(L("Back to title"), icon: .arrowLeft)
                            }
                            .buttonStyle(PixelButtonStyle(compact: true))
                            .alert(L("Back to the title screen?"), isPresented: $confirmQuit) {
                                Button(L("Save and leave")) {
                                    session.save()
                                    onQuitToTitle()
                                }
                                Button(L("Cancel"), role: .cancel) {}
                            } message: {
                                Text(L("Your game is saved first, so you can continue where you left off."))
                            }
                        }
                    }
                    Text(L("Your progress also saves by itself every few seconds."))
                        .font(HUDStyle.font(10))
                        .foregroundStyle(HUDStyle.dim)
                    Button {
                        session.save()
                        if let contents = try? JSONEncoder().encode(session.data) {
                            backup = SaveBackup(contents: contents)
                            exporting = true
                        }
                    } label: {
                        Label(backedUp ? L("Backed up") : L("Back up to Files"), icon: backedUp ? .check : .arrowUp)
                    }
                    .buttonStyle(PixelButtonStyle(compact: true))
                    .fileExporter(isPresented: $exporting, document: backup, contentType: .json,
                                  defaultFilename: SaveBackup.fileName(for: session.data)) { result in
                        if case .success = result { backedUp = true }
                    }
                    Text(L("Keep a copy in Files or iCloud Drive, for a new phone or in case the app is deleted. Bring it back with Import a backup on the title screen."))
                        .font(HUDStyle.font(10))
                        .foregroundStyle(HUDStyle.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let session, let onQuitToTitle {
                section(L("Danger zone"), icon: .close) {
                    Text(L("Deleting a game can't be undone."))
                        .font(HUDStyle.font(10))
                        .foregroundStyle(HUDStyle.dim)
                    Button {
                        confirmDelete = true
                    } label: {
                        Label(L("Delete this game"), icon: .close)
                    }
                    .buttonStyle(PixelButtonStyle(tint: Color(red: 0.9, green: 0.35, blue: 0.35), compact: true))
                    .alert(L("Delete {hero}'s game?", ["hero": session.data.hero.name]), isPresented: $confirmDelete) {
                        Button(L("Delete for good"), role: .destructive) {
                            session.deleteGame()
                            onQuitToTitle()
                        }
                        Button(L("Cancel"), role: .cancel) {}
                    } message: {
                        Text(L("{hero}, level {level}, and everything they carry will be gone for good.", ["hero": session.data.hero.name, "level": session.data.hero.level]))
                    }
                }
            }

            if let onImportBackup {
                section(L("Backups"), icon: .arrowDown) {
                    Button(action: onImportBackup) {
                        Label(L("Import a backup"), icon: .arrowDown)
                    }
                    .buttonStyle(PixelButtonStyle(compact: true))
                    Text(L("A backup from Files or iCloud Drive comes back as a game of its own, next to your others."))
                        .font(HUDStyle.font(10))
                        .foregroundStyle(HUDStyle.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            section(L("About"), icon: .star) {
                Text(L("Storyleaf {version}", ["version": Self.version]))
                Text(L("Art made with Retro Diffusion, icons by Iconaut (MIT). Music and sound effects are synthesized in the game."))
                    .font(HUDStyle.font(10))
                    .foregroundStyle(HUDStyle.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(HUDStyle.font(12))
        .foregroundStyle(HUDStyle.cream)
        .tint(HUDStyle.gold)
        .toggleStyle(PixelSwitchStyle())
    }

    private func section<Content: View>(_ title: String, icon: GameIcon, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, icon: icon)
                .font(HUDStyle.font(14))
                .foregroundStyle(HUDStyle.gold)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06)))
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}

/// Time to choose in a fight: Off, 10, 20 or 30 seconds, as a row of pills.
private struct TurnTimerRow: View {
    @Binding var seconds: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                IconImage(.sword, size: 14)
                    .frame(width: 18)
                Text(L("Time to choose"))
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 6) {
                ForEach(GameSettings.turnTimerChoices, id: \.self) { choice in
                    let chosen = seconds == choice
                    Button {
                        seconds = choice
                    } label: {
                        Text(choice == 0 ? L("Off") : L("{seconds} s", ["seconds": Int(choice)]))
                            .font(HUDStyle.font(11))
                            .foregroundStyle(chosen ? HUDStyle.ink : HUDStyle.cream)
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .background(Capsule().fill(chosen ? HUDStyle.gold : HUDStyle.ink.opacity(0.5)))
                            .overlay(Capsule().strokeBorder(HUDStyle.cream.opacity(chosen ? 0 : 0.4), lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }
        }
    }
}

/// One kind of sound: its switch, and under it (when it has one) a volume slider that plays a
/// preview when you let go. The slider dims while the sound is switched off.
private struct SoundRow: View {
    let title: String
    let icon: GameIcon?
    @Binding var isOn: Bool
    var volume: Binding<Double>?
    var onRelease: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $isOn) {
                HStack(spacing: 10) {
                    Group {
                        if let icon { IconImage(icon, size: 14) } else { Color.clear }
                    }
                    .frame(width: 18, height: 14)
                    Text(title)
                }
            }
            if let volume {
                HStack(spacing: 10) {
                    Slider(value: volume, in: 0...1, onEditingChanged: { editing in
                        if !editing { onRelease() }
                    })
                    Text("\(Int((volume.wrappedValue * 100).rounded()))%")
                        .font(HUDStyle.font(10))
                        .monospacedDigit()
                        .frame(width: 38, alignment: .trailing)
                }
                .padding(.leading, 28)
                .disabled(!isOn)
                .opacity(isOn ? 1 : 0.4)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(L("{title} volume", ["title": title]))
                .accessibilityValue(L("{percent} percent", ["percent": Int((volume.wrappedValue * 100).rounded())]))
            }
        }
    }
}
