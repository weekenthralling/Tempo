//
//  TempoMath.swift
//  Tempo
//
//  The arithmetic behind the metronome. Kept free of any audio or UI types so
//  it can be unit tested (and even compiled on macOS for a quick check).
//

import Foundation

enum TempoMath {
    /// The metronome's supported range. 30 BPM is a useful slow practice tempo,
    /// 300 BPM covers most subdivisions people actually need.
    static let minBPM: Double = 30
    static let maxBPM: Double = 300

    /// The interval between two beats, in seconds.
    static func beatInterval(bpm: Double) -> TimeInterval {
        60.0 / clampBPM(bpm)
    }

    /// Number of samples in one beat at a given sample rate.
    ///
    /// Schedule times are computed from this value and then rounded to whole
    /// frames, so rounding error never accumulates across beats.
    static func samplesPerBeat(bpm: Double, sampleRate: Double) -> Double {
        beatInterval(bpm: bpm) * sampleRate
    }

    /// Interval between two subdivision clicks, in seconds.
    static func stepInterval(bpm: Double, stepsPerBeat: Int) -> TimeInterval {
        beatInterval(bpm: bpm) / Double(max(1, stepsPerBeat))
    }

    static func clampBPM(_ bpm: Double) -> Double {
        // NaN has no sensible clamp; ±infinity should still land on the
        // nearest supported tempo instead of jumping to the default.
        guard !bpm.isNaN else { return 120 }
        return min(max(bpm, minBPM), maxBPM)
    }

    static func clampVolume(_ volume: Double) -> Double {
        guard !volume.isNaN else { return 0.8 }
        return min(max(volume, 0), 1)
    }

    /// Human friendly tempo name for the current BPM.
    static func marking(forBPM bpm: Double) -> TempoMarking {
        TempoMarking.marking(for: clampBPM(bpm))
    }
}
