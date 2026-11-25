//
//  ClickBank.swift
//  Tempo
//
//  Every click is synthesized at launch instead of shipping sample files.
//  That keeps the app bundle tiny, avoids licensing questions, and lets the
//  accent / beat / subdivision variants share one timbre.
//

import AVFoundation

final class ClickBank {
    private let format: AVAudioFormat
    private var storage: [ClickSound: [ClickKind: AVAudioPCMBuffer]] = [:]

    init(format: AVAudioFormat) {
        self.format = format
        for sound in ClickSound.allCases {
            var variants: [ClickKind: AVAudioPCMBuffer] = [:]
            for kind in ClickKind.allCases {
                variants[kind] = ClickSynth.makeBuffer(format: format, sound: sound, kind: kind)
            }
            storage[sound] = variants
        }
    }

    func buffer(sound: ClickSound, kind: ClickKind) -> AVAudioPCMBuffer {
        if let buffer = storage[sound]?[kind] {
            return buffer
        }
        // Should never happen: every combination is generated in init.
        return ClickSynth.makeBuffer(format: format, sound: .classic, kind: kind)
    }
}

private enum ClickSynth {
    private enum Waveform {
        case sine
        case triangle
        case square
    }

    private struct Recipe {
        var frequency: Double
        var waveform: Waveform
        /// Exponential decay time constant, in seconds.
        var decay: Double
        /// Amount of a slightly detuned second partial.
        var harmonic: Double
        /// Amount of filtered noise in the attack transient.
        var noise: Double
        /// Downward pitch bend at the attack; makes clicks feel "physical".
        var pitchDrop: Double
    }

    private static func recipe(for sound: ClickSound) -> Recipe {
        switch sound {
        case .classic:
            return Recipe(frequency: 1500, waveform: .sine, decay: 0.014, harmonic: 0.35, noise: 0.18, pitchDrop: 0.35)
        case .woodblock:
            return Recipe(frequency: 1050, waveform: .triangle, decay: 0.020, harmonic: 0.55, noise: 0.30, pitchDrop: 0.50)
        case .beep:
            return Recipe(frequency: 880, waveform: .sine, decay: 0.030, harmonic: 0.05, noise: 0.00, pitchDrop: 0.00)
        case .digital:
            return Recipe(frequency: 2000, waveform: .square, decay: 0.008, harmonic: 0.00, noise: 0.05, pitchDrop: 0.15)
        }
    }

    static func makeBuffer(format: AVAudioFormat, sound: ClickSound, kind: ClickKind) -> AVAudioPCMBuffer {
        let sampleRate = format.sampleRate
        let recipe = recipe(for: sound)

        let pitchScale: Double
        let gain: Float
        let duration: Double

        switch kind {
        case .accent:
            pitchScale = 1.22
            gain = 0.95
            duration = 0.075
        case .beat:
            pitchScale = 1.0
            gain = 0.62
            duration = 0.060
        case .subdivision:
            pitchScale = 1.9
            gain = 0.34
            duration = 0.040
        }

        let frameCount = AVAudioFrameCount((duration * sampleRate).rounded())
        guard
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
            let channel = buffer.floatChannelData?[0]
        else {
            // The format comes from AVAudioFormat(standardFormatWithSampleRate:),
            // so this is unreachable in practice.
            preconditionFailure("Unable to allocate click buffer")
        }
        buffer.frameLength = frameCount

        let frequency = recipe.frequency * pitchScale
        var seed: UInt32 = 0x9E37_79B9

        // Deterministic noise so previews sound identical every launch.
        func nextNoise() -> Double {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Double(seed) / Double(UInt32.max) * 2 - 1
        }

        var phase = 0.0
        var peak: Float = 0

        for index in 0..<Int(frameCount) {
            let t = Double(index) / sampleRate
            let attack = min(1.0, t / 0.0012)
            let body = exp(-t / recipe.decay)
            let envelope = attack * body

            // Integrate instantaneous frequency for the pitch bend.
            let instantaneous = frequency * (1 + recipe.pitchDrop * exp(-t / 0.012))
            phase += 2 * Double.pi * instantaneous / sampleRate

            var wave: Double
            switch recipe.waveform {
            case .sine:
                wave = sin(phase)
            case .triangle:
                wave = 2 / Double.pi * asin(sin(phase))
            case .square:
                wave = tanh(2.5 * sin(phase))
            }

            if recipe.harmonic != 0 {
                wave += recipe.harmonic * sin(phase * 2.02)
            }
            if recipe.noise > 0 {
                let burst = exp(-t / 0.004)
                wave += recipe.noise * nextNoise() * burst
            }

            let value = Float(wave * envelope)
            channel[index] = value
            peak = max(peak, abs(value))
        }

        // Normalize to a common peak, apply the relative gain, then fade the
        // tail so the buffer never ends on a discontinuity (which would click).
        let scale = peak > 0 ? gain / peak : 0
        let fadeFrames = max(1, Int(0.004 * sampleRate))
        for index in 0..<Int(frameCount) {
            var value = channel[index] * scale
            let remaining = Int(frameCount) - index
            if remaining < fadeFrames {
                value *= Float(remaining) / Float(fadeFrames)
            }
            channel[index] = value
        }

        return buffer
    }
}
