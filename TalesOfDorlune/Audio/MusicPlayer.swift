import AVFoundation
import Observation

/// Plays the songs from content/music.json in stereo: one per map, plus battle and victory.
/// Uses the "ambient" audio session, so the phone's silent switch mutes it.
@Observable
final class MusicPlayer {
    static let shared = MusicPlayer()

    private(set) var isMuted: Bool

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var synth: SongSynth?
    @ObservationIgnored private var tunes: [String: Tune] = [:]
    @ObservationIgnored private var current: String?
    /// Unit tests run inside the app: no music then (like SoundEffects), so the synth leaves them the CPU.
    @ObservationIgnored private let isEnabled = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil

    init() {
        isMuted = UserDefaults.standard.bool(forKey: "musicMuted")
        // A call, Siri or an alarm stops the engine, and so does a new output (Bluetooth, AirPlay)
        // changing the sample rate. Start it again once they're done: the app may never leave the
        // foreground in between, and the music stayed silent until it did.
        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            Task { @MainActor [weak self] in self?.resume() }
        }
        center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.resume() }
        }
    }

    func toggleMute() {
        isMuted.toggle()
        UserDefaults.standard.set(isMuted, forKey: "musicMuted")
        synth?.setMuted(isMuted)
    }

    /// Music volume from Settings (0...1).
    func setVolume(_ volume: Double) {
        engine.mainMixerNode.outputVolume = Self.mixerVolume(volume)
    }

    private static func mixerVolume(_ volume: Double) -> Float {
        Float(0.7 * min(1, max(0, volume)))
    }

    /// Switches to a song (nil = silence). Playing the current song again does nothing. `fade`: over
    /// how many seconds the song playing fades out first, and the new one fades in (walking from
    /// one land into the next, `ContinentScene.arrive`); none cuts over at once, the new one fading
    /// in quickly.
    func play(_ id: String?, fade: Double = 0) {
        guard id != current else { return }
        current = id
        startIfNeeded()
        synth?.play(id.flatMap { tunes[$0] }, id: id, fadeOut: fade, fadeIn: fade > 0 ? fade : 0.4)
    }

    /// Restarts audio after the app returns to the foreground or the output changes.
    func resume() {
        guard synth != nil, !engine.isRunning else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        try? engine.start()
    }

    private func startIfNeeded() {
        guard synth == nil, isEnabled else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient)
            try session.setActive(true)

            let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
            let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate > 0 ? sampleRate : 44_100, channels: 2)!
            // Instruments are baked for the output's sample rate.
            let content = Content.shared
            for song in content.songs {
                tunes[song.id] = Tune(song, instruments: content.instruments, sampleRate: format.sampleRate)
            }
            let synth = SongSynth(sampleRate: format.sampleRate)
            synth.setMuted(isMuted)
            let source = Self.makeSourceNode(synth: synth, format: format)
            engine.attach(source)
            engine.connect(source, to: engine.mainMixerNode, format: format)
            engine.mainMixerNode.outputVolume = Self.mixerVolume(GameSettings.musicVolume)
            engine.prepare()
            try engine.start()
            self.synth = synth
        } catch {
            print("⚠️ Music unavailable: \(error)")
        }
    }

    /// Built outside the main actor so the render block can run on the audio thread.
    private nonisolated static func makeSourceNode(synth: SongSynth, format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            synth.render(frameCount: Int(frameCount), into: UnsafeMutableAudioBufferListPointer(audioBufferList))
            return noErr
        }
    }
}
