import AVFoundation
import Foundation

/// The old chiptune voices, still used by any track that names a `wave` instead of an `instrument`.
nonisolated enum Wave: Sendable {
    case square, triangle, noise
}

/// The drum sounds a `drums` track can hit: K kick, S brush snare, H hi-hat (also N), T tambourine,
/// C cymbal, R rim or shaker.
nonisolated enum Drum: Sendable {
    case kick, snare, hat, tambourine, cymbal, rim

    init?(_ letter: Character) {
        switch letter {
        case "K": self = .kick
        case "S": self = .snare
        case "H", "N": self = .hat
        case "T": self = .tambourine
        case "C": self = .cymbal
        case "R": self = .rim
        default: return nil
        }
    }
}

/// An instrument from music.json, turned into per-sample numbers.
nonisolated struct Instrument: Sendable {
    let ratios: [Double]
    let amplitudes: [Float]
    /// Each partial's level is multiplied by this every sample (its decay).
    let decayFactors: [Float]
    let attackSamples: Double
    /// Multiplied into the level every sample once the note is let go.
    let releaseFactor: Float
    let vibratoDepth: Double
    let vibratoRate: Double
    let vibratoDelay: Double
    /// Frequency multipliers for the detuned copies (chorus).
    let detunes: [Double]
    let breath: Float
    let click: Float
    let gain: Float

    init(_ def: InstrumentDef, sampleRate: Double) {
        let partials = (def.partials ?? [[1, 1, 0]]).filter { $0.count == 3 }.prefix(SongSynth.maxPartials)
        ratios = partials.map { $0[0] }
        amplitudes = partials.map { Float($0[1]) }
        decayFactors = partials.map { Float(exp(-$0[2] / sampleRate)) }
        attackSamples = max(1, (def.attack ?? 0.005) * sampleRate)
        releaseFactor = Float(exp(-4.6 / max(1, (def.release ?? 0.2) * sampleRate)))
        let vibrato = def.vibrato ?? []
        vibratoDepth = vibrato.count == 3 ? vibrato[0] : 0
        vibratoRate = vibrato.count == 3 ? vibrato[1] : 0
        vibratoDelay = vibrato.count == 3 ? vibrato[2] : 0
        let cents = def.detune ?? 0
        let offsets: [Double] = switch min(SongSynth.maxDetunes, max(1, def.voices ?? 1)) {
        case 1: [0]
        case 2: [-cents, cents]
        default: [-cents, 0, cents]
        }
        detunes = offsets.map { pow(2, $0 / 1200) }
        breath = Float(def.breath ?? 0)
        click = Float(def.click ?? 0)
        gain = Float(def.gain ?? 0.5)
    }
}

/// A song turned into playable note events.
nonisolated struct Tune: Sendable {
    nonisolated struct Note: Sendable {
        /// Hz of each note sounding together (a chord); empty is a rest.
        let frequencies: [Double]
        /// Drum hits, on drum tracks.
        let drums: [Drum]
        let steps: Int
        /// Legacy chiptune tracks: -1 is a noise hit.
        var legacyFrequency: Double { drums.isEmpty ? (frequencies.first ?? 0) : -1 }
    }

    nonisolated struct Voice: Sendable {
        let wave: Wave?
        let duty: Double
        let instrument: Instrument?
        let isDrums: Bool
        let volume: Float
        let left: Float
        let right: Float
        let send: Float
        let notes: [Note]
    }

    let secondsPerStep: Double
    let loops: Bool
    let voices: [Voice]
    /// Chiptune songs keep their old dry sound; instrument songs go through the reverb.
    let isLegacy: Bool
    let reverb: Float

    /// Parses music.json notation: `C5:2 F#5:1 Bb4:4 -:2`, chords `C4+E4+G4:4`, drums `K+H:1 S:1`,
    /// with `|` bar lines ignored.
    init(_ song: SongDef, instruments: [InstrumentDef], sampleRate: Double = 44_100) {
        secondsPerStep = 30 / song.tempo   // a step is an eighth note
        loops = song.loops ?? true
        reverb = Float(song.reverb ?? 0.25)
        let byID = Dictionary(instruments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var legacy = true
        voices = song.tracks.map { track in
            let def = track.instrument.flatMap { byID[$0] }
            if def != nil { legacy = false }
            let isDrums = track.instrument == "drums" || track.wave == "noise"
            var wave: Wave?
            if def == nil {
                switch track.wave {
                case "triangle": wave = .triangle
                case "noise": wave = .noise
                default: wave = .square
                }
            }
            let notes = track.notes.split(separator: " ").compactMap { token -> Note? in
                guard token != "|" else { return nil }
                let parts = token.split(separator: ":")
                guard parts.count == 2, let steps = Int(parts[1]) else { return nil }
                let names = parts[0].split(separator: "+").map(String.init)
                if names == ["-"] { return Note(frequencies: [], drums: [], steps: steps) }
                if isDrums {
                    return Note(frequencies: [], drums: names.compactMap { $0.first.flatMap(Drum.init) }, steps: steps)
                }
                return Note(frequencies: names.compactMap(Self.frequency(of:)), drums: [], steps: steps)
            }
            let pan = max(-1, min(1, track.pan ?? 0))
            let angle = (pan + 1) * .pi / 4
            return Voice(
                wave: wave,
                duty: track.duty ?? 0.5,
                instrument: def.map { Instrument($0, sampleRate: sampleRate) },
                isDrums: isDrums,
                volume: Float(track.volume),
                left: Float(cos(angle)),
                right: Float(sin(angle)),
                send: Float(track.reverb ?? 1),
                notes: notes
            )
        }
        isLegacy = legacy
    }

    static func frequency(of name: String) -> Double? {
        let semitones: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
        guard let letter = name.first, var semitone = semitones[letter] else { return nil }
        var rest = name.dropFirst()
        if rest.first == "#" { semitone += 1; rest = rest.dropFirst() }
        else if rest.first == "b" { semitone -= 1; rest = rest.dropFirst() }
        guard let octave = Int(rest) else { return nil }
        let midi = 12 * (octave + 1) + semitone
        return 440 * pow(2, Double(midi - 69) / 12)
    }
}

/// Fairyland's music synth. Instrument tracks are additive voices (a few partials each, with their
/// own decay, attack, release, vibrato, chorus and a touch of breath or pluck noise) and a small drum
/// kit, mixed in stereo through a hall reverb. Notes ring on under the next one, so plucked strings and
/// bells overlap like real ones. Old chiptune tracks still play as before. Everything here runs off
/// the main actor, and nothing allocates on the audio thread except when a new song starts.
nonisolated final class SongSynth: @unchecked Sendable {
    static let maxStrikes = 6
    static let maxPartials = 8
    static let maxDetunes = 3

    private struct Strike {
        var active = false
        var frequency = 0.0
        var age = 0
        var gate = 0
        var release: Float = 1
        var drum: Drum?
        var filter: Float = 0
        var drumPhase = 0.0
    }

    private struct VoiceState {
        var noteIndex = -1
        var samplesLeft = 0
        var samplesPlayed = 0
        var phase = 0.0
        var noise: UInt32 = 0xACE1
        var noiseLevel: Float = 0
        var noiseCountdown = 0
        var finished = false
        var strikes = [Strike](repeating: Strike(), count: SongSynth.maxStrikes)
        var phases = [Double](repeating: 0, count: SongSynth.maxStrikes * SongSynth.maxPartials * SongSynth.maxDetunes)
        var levels = [Float](repeating: 0, count: SongSynth.maxStrikes * SongSynth.maxPartials)
        var nextStrike = 0
    }

    /// One Freeverb comb or allpass line.
    private struct Line {
        var buffer: [Float]
        var index = 0
        var filter: Float = 0
        init(_ length: Int) { buffer = [Float](repeating: 0, count: max(1, length)) }
    }

    private let lock = NSLock()
    private var queuedTune: Tune?
    private var queuedID: String?
    private var queuedFade: (out: Double, in: Double) = (0, 0.4)
    private var hasQueuedTune = false
    private var queuedMuted = false

    // Audio-thread state.
    private var tune: Tune?
    /// The playing song's id (`play`), to know it again.
    private var tuneID: String?
    /// The song waiting for the one playing to fade out first (`play`'s `fadeOut`).
    private var incoming: (tune: Tune?, id: String?)?
    private var voices: [VoiceState] = []
    private var muted = false
    private var fade: Float = 0
    /// How much the level rises each sample as a song fades in, and falls as one fades out.
    private var fadeInStep: Float
    private var fadeOutStep: Float = 0
    private var random: UInt32 = 0x9E37_79B9
    private var combs: [[Line]] = []
    private var allpasses: [[Line]] = []
    private let sine: [Float]
    let sampleRate: Double

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        fadeInStep = Float(1 / (sampleRate * 0.4))
        sine = (0...4096).map { Float(sin(Double($0) / 4096 * 2 * .pi)) }
        let scale = sampleRate / 44_100
        for side in 0..<2 {
            let spread = side == 0 ? 0 : 23
            combs.append([1116, 1188, 1277, 1356].map { Line(Int(Double($0 + spread) * scale)) })
            allpasses.append([556, 441].map { Line(Int(Double($0 + spread) * scale)) })
        }
    }

    /// Switches to `tune` (nil: silence), known as `id`: at once, or once the song playing has
    /// faded out over `fadeOut` seconds (walking from one land into the next, playtesting
    /// 2026-10-16: the music cut over at the border); either way fading in over `fadeIn`. Asked
    /// back for the song still fading out, it fades in again from where it is.
    func play(_ tune: Tune?, id: String? = nil, fadeOut: Double = 0, fadeIn: Double = 0.4) {
        lock.lock()
        queuedTune = tune
        queuedID = id
        queuedFade = (fadeOut, fadeIn)
        hasQueuedTune = true
        lock.unlock()
    }

    /// Starts a song from its beginning, silent at first (it fades in).
    private func start(_ next: Tune?, id: String?) {
        tune = next
        tuneID = id
        voices = Array(repeating: VoiceState(), count: next?.voices.count ?? 0)
        incoming = nil
        fade = 0
    }

    func setMuted(_ muted: Bool) {
        lock.lock()
        queuedMuted = muted
        lock.unlock()
    }

    // MARK: - Rendering

    func render(frameCount: Int, into buffers: UnsafeMutableAudioBufferListPointer) {
        // Pick up changes from the main thread without ever blocking the audio thread.
        if lock.try() {
            if hasQueuedTune {
                hasQueuedTune = false
                fadeInStep = Float(1 / (sampleRate * max(0.01, queuedFade.in)))
                if let id = queuedID, id == tuneID, tune != nil {
                    // Back to the song fading out: it fades in again where it is.
                    incoming = nil
                } else if queuedFade.out > 0, tune != nil, fade > 0, !muted, voices.contains(where: { !$0.finished }) {
                    // Still playing (a victory tune that's over goes at once): it fades out first.
                    incoming = (queuedTune, queuedID)
                    fadeOutStep = Float(1 / (sampleRate * queuedFade.out))
                } else {
                    start(queuedTune, id: queuedID)
                }
            }
            muted = queuedMuted
            lock.unlock()
        }
        // Faded out, or muted meanwhile: the next song.
        if let next = incoming, fade <= 0 || muted {
            start(next.tune, id: next.id)
        }

        guard let tune, !muted else {
            for buffer in buffers {
                if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
            }
            return
        }

        let stepSamples = max(1, Int(tune.secondsPerStep * sampleRate))
        let fadingOut = incoming != nil
        let wet = tune.reverb * 0.7
        let left = buffers.count > 0 ? buffers[0].mData?.assumingMemoryBound(to: Float.self) : nil
        let right = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil

        for frame in 0..<frameCount {
            var mixLeft: Float = 0
            var mixRight: Float = 0
            var send: Float = 0
            for index in voices.indices {
                let voice = tune.voices[index]
                guard !voice.notes.isEmpty else { continue }
                if voices[index].finished && !hasActiveStrikes(index) { continue }

                if !voices[index].finished, voices[index].samplesLeft <= 0 {
                    advance(index, voice: voice, tune: tune, stepSamples: stepSamples)
                }
                var sample: Float = 0
                if voice.wave != nil {
                    sample = legacySample(index, voice: voice)
                } else if let instrument = voice.instrument {
                    sample = voice.isDrums ? drumSample(index) : pitchedSample(index, instrument: instrument)
                }
                if !voices[index].finished {
                    voices[index].samplesLeft -= 1
                    voices[index].samplesPlayed += 1
                }
                sample *= voice.volume
                if tune.isLegacy {
                    mixLeft += sample
                } else {
                    mixLeft += sample * voice.left
                    mixRight += sample * voice.right
                    send += sample * voice.send
                }
            }

            fade = fadingOut ? max(0, fade - fadeOutStep) : min(1, fade + fadeInStep)
            let outLeft: Float
            let outRight: Float
            if tune.isLegacy {
                outLeft = max(-1, min(1, mixLeft * fade * 0.8))
                outRight = outLeft
            } else {
                let (reverbLeft, reverbRight) = reverbSample(send)
                outLeft = tanh((mixLeft + reverbLeft * wet) * 1.1) / 1.1 * fade
                outRight = tanh((mixRight + reverbRight * wet) * 1.1) / 1.1 * fade
            }
            if let right {
                left?[frame] = outLeft
                right[frame] = outRight
            } else {
                left?[frame] = (outLeft + outRight) / 2
            }
        }
    }

    /// Moves a voice on to its next note, starting a strike for each pitch (or drum) in it.
    private func advance(_ index: Int, voice: Tune.Voice, tune: Tune, stepSamples: Int) {
        voices[index].noteIndex += 1
        if voices[index].noteIndex >= voice.notes.count {
            if tune.loops {
                voices[index].noteIndex = 0
            } else {
                voices[index].finished = true
                return
            }
        }
        let note = voice.notes[voices[index].noteIndex]
        let gate = note.steps * stepSamples
        voices[index].samplesLeft = gate
        voices[index].samplesPlayed = 0
        guard voice.wave == nil, let instrument = voice.instrument else { return }
        if voice.isDrums {
            for drum in note.drums { startStrike(index, frequency: 0, gate: gate, drum: drum, instrument: instrument) }
        } else {
            for frequency in note.frequencies { startStrike(index, frequency: frequency, gate: gate, drum: nil, instrument: instrument) }
        }
    }

    private func startStrike(_ index: Int, frequency: Double, gate: Int, drum: Drum?, instrument: Instrument) {
        // A free slot, or the next one round the pool (the oldest).
        var slot = voices[index].strikes.firstIndex(where: { !$0.active }) ?? voices[index].nextStrike
        if slot >= Self.maxStrikes { slot = 0 }
        voices[index].nextStrike = (slot + 1) % Self.maxStrikes
        voices[index].strikes[slot] = Strike(active: true, frequency: frequency, age: 0, gate: gate, release: 1, drum: drum)
        for partial in 0..<Self.maxPartials {
            let level = partial < instrument.amplitudes.count ? instrument.amplitudes[partial] : 0
            voices[index].levels[slot * Self.maxPartials + partial] = level
            for copy in 0..<Self.maxDetunes {
                voices[index].phases[(slot * Self.maxPartials + partial) * Self.maxDetunes + copy] = 0
            }
        }
    }

    private func hasActiveStrikes(_ index: Int) -> Bool {
        voices[index].strikes.contains { $0.active }
    }

    private func pitchedSample(_ index: Int, instrument: Instrument) -> Float {
        var total: Float = 0
        let partialCount = instrument.ratios.count
        let copies = instrument.detunes.count
        for slot in 0..<Self.maxStrikes where voices[index].strikes[slot].active {
            var strike = voices[index].strikes[slot]
            let seconds = Double(strike.age) / sampleRate
            var vibrato = 1.0
            if instrument.vibratoDepth > 0 {
                let ramp = min(1, max(0, (seconds - instrument.vibratoDelay) / 0.3))
                let swing: Double = sin(2 * .pi * instrument.vibratoRate * seconds) * ramp
                vibrato = pow(2, instrument.vibratoDepth / 12 * swing)
            }
            var value: Float = 0
            for partial in 0..<partialCount {
                let levelIndex = slot * Self.maxPartials + partial
                let level = voices[index].levels[levelIndex] * instrument.decayFactors[partial]
                voices[index].levels[levelIndex] = level
                let step = strike.frequency * instrument.ratios[partial] * vibrato / sampleRate
                var sum: Float = 0
                for copy in 0..<copies {
                    let phaseIndex = (slot * Self.maxPartials + partial) * Self.maxDetunes + copy
                    var phase = voices[index].phases[phaseIndex] + step * instrument.detunes[copy]
                    if phase >= 1 { phase -= floor(phase) }
                    voices[index].phases[phaseIndex] = phase
                    sum += sineAt(phase)
                }
                value += level * sum
            }
            value /= Float(copies)
            if instrument.breath > 0 {
                strike.filter += 0.08 * (nextNoise() - strike.filter)
                value += strike.filter * instrument.breath * 3
            }
            if instrument.click > 0, seconds < 0.05 {
                value += nextNoise() * instrument.click * Float(exp(-seconds / 0.008))
            }
            let attack = Float(min(1, Double(strike.age) / instrument.attackSamples))
            if strike.age >= strike.gate {
                strike.release *= instrument.releaseFactor
                if strike.release < 0.0005 { strike.active = false }
            }
            total += value * attack * strike.release * instrument.gain
            strike.age += 1
            voices[index].strikes[slot] = strike
        }
        return total
    }

    private func drumSample(_ index: Int) -> Float {
        var total: Float = 0
        for slot in 0..<Self.maxStrikes where voices[index].strikes[slot].active {
            var strike = voices[index].strikes[slot]
            let t = Double(strike.age) / sampleRate
            let noise = nextNoise()
            var value: Float = 0
            switch strike.drum {
            case .kick:
                strike.drumPhase += (48 + 110 * exp(-t / 0.035)) / sampleRate
                if strike.drumPhase >= 1 { strike.drumPhase -= floor(strike.drumPhase) }
                value = sineAt(strike.drumPhase) * Float(exp(-t / 0.28)) + noise * 0.2 * Float(exp(-t / 0.003))
            case .snare:
                strike.filter += 0.35 * (noise - strike.filter)
                value = strike.filter * 0.8 * Float(exp(-t / 0.11)) + Float(sin(2 * .pi * 190 * t) * 0.25 * exp(-t / 0.04))
            case .hat:
                strike.filter += 0.3 * (noise - strike.filter)
                value = (noise - strike.filter) * Float(exp(-t / 0.035)) * 0.8
            case .tambourine:
                strike.filter += 0.3 * (noise - strike.filter)
                let jingle: Float = sin(2 * .pi * 23 * t) > 0 ? 1 : 0
                value = (noise - strike.filter) * Float(exp(-t / 0.12)) * (0.6 + 0.4 * jingle)
            case .cymbal:
                strike.filter += 0.2 * (noise - strike.filter)
                value = (noise - strike.filter) * Float(exp(-t / 0.9)) * 0.5
            case .rim:
                strike.filter += 0.3 * (noise - strike.filter)
                value = (noise - strike.filter) * Float(exp(-t / 0.018)) * 0.7
            case nil:
                value = 0
            }
            strike.age += 1
            if t > 1.2 { strike.active = false }
            total += value
            voices[index].strikes[slot] = strike
        }
        return total
    }

    /// The original chiptune voices: pulse, triangle and NES-style noise, one note at a time.
    private func legacySample(_ index: Int, voice: Tune.Voice) -> Float {
        guard !voices[index].finished, voices[index].noteIndex >= 0 else { return 0 }
        let note = voice.notes[voices[index].noteIndex]
        let played = Double(voices[index].samplesPlayed)
        let attack = sampleRate * 0.004
        let decay = sampleRate * 0.18
        let release = sampleRate * 0.02
        let frequency = note.legacyFrequency
        if frequency > 0 {
            voices[index].phase += frequency / sampleRate
            if voices[index].phase >= 1 { voices[index].phase -= 1 }
            let phase = voices[index].phase
            let raw: Float = switch voice.wave {
            case .square: phase < voice.duty ? 1 : -1
            case .triangle: Float(4 * abs(phase - 0.5) - 1)
            default: 0
            }
            let sustain = voice.wave == .triangle ? 0.9 : 0.55
            var envelope = min(1, played / attack) * (sustain + (1 - sustain) * exp(-played / decay))
            envelope *= min(1, Double(voices[index].samplesLeft) / release)
            return raw * Float(envelope)
        } else if frequency < 0 {
            if voices[index].noiseCountdown <= 0 {
                // 15-bit LFSR, like the NES noise channel.
                let noise = voices[index].noise
                let bit = (noise ^ (noise >> 1)) & 1
                voices[index].noise = (noise >> 1) | (bit << 14)
                voices[index].noiseLevel = (voices[index].noise & 1) == 0 ? 1 : -1
                voices[index].noiseCountdown = 3
            }
            voices[index].noiseCountdown -= 1
            return voices[index].noiseLevel * Float(exp(-played / (sampleRate * 0.035)))
        }
        return 0
    }

    /// Freeverb-style hall: four damped combs in parallel, then two allpasses, per side.
    private func reverbSample(_ input: Float) -> (Float, Float) {
        var out: (Float, Float) = (0, 0)
        for side in 0..<2 {
            var sum: Float = 0
            for line in 0..<combs[side].count {
                let i = combs[side][line].index
                let delayed = combs[side][line].buffer[i]
                combs[side][line].filter = delayed * 0.75 + combs[side][line].filter * 0.25
                combs[side][line].buffer[i] = input + combs[side][line].filter * 0.84
                combs[side][line].index = (i + 1) % combs[side][line].buffer.count
                sum += delayed
            }
            var value = sum * 0.25
            for line in 0..<allpasses[side].count {
                let i = allpasses[side][line].index
                let delayed = allpasses[side][line].buffer[i]
                allpasses[side][line].buffer[i] = value + delayed * 0.5
                allpasses[side][line].index = (i + 1) % allpasses[side][line].buffer.count
                value = delayed - value
            }
            if side == 0 { out.0 = value } else { out.1 = value }
        }
        return out
    }

    private func sineAt(_ phase: Double) -> Float {
        let position = phase * 4096
        let i = Int(position)
        let fraction = Float(position - Double(i))
        return sine[i] + (sine[min(4096, i + 1)] - sine[i]) * fraction
    }

    /// White noise in -1...1 (xorshift).
    private func nextNoise() -> Float {
        random ^= random << 13
        random ^= random >> 17
        random ^= random << 5
        return Float(random) / Float(UInt32.max) * 2 - 1
    }
}
