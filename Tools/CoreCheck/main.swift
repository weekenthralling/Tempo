//
//  main.swift
//  TempoCoreCheck
//
//  A tiny command line harness that compiles the Foundation-only core of the
//  app on macOS and checks the timing math. The XCTest target covers the same
//  ground, but this runs without an iOS simulator runtime:
//
//      ./Scripts/verify-core.sh
//

import Foundation

private var failures = 0
private var checks = 0

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() {
        failures += 1
        print("  ✗ \(message)")
    }
}

private func checkEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) {
    check(lhs == rhs, "\(message) — got \(lhs), expected \(rhs)")
}

private func checkClose(_ lhs: Double, _ rhs: Double, tolerance: Double = 1e-9, _ message: String) {
    check(abs(lhs - rhs) <= tolerance, "\(message) — got \(lhs), expected \(rhs)")
}

// MARK: - BPM math

print("BPM math")
checkEqual(TempoMath.clampBPM(10), TempoMath.minBPM, "clamps low BPM")
checkEqual(TempoMath.clampBPM(1_000), TempoMath.maxBPM, "clamps high BPM")
checkEqual(TempoMath.clampBPM(.nan), 120, "NaN falls back to 120")
checkEqual(TempoMath.clampBPM(.infinity), TempoMath.maxBPM, "positive infinity clamps to 300")
checkEqual(TempoMath.clampBPM(-.infinity), TempoMath.minBPM, "negative infinity clamps to 30")
checkClose(TempoMath.beatInterval(bpm: 120), 0.5, "120 BPM = 0.5 s per beat")
checkClose(TempoMath.beatInterval(bpm: 60), 1.0, "60 BPM = 1 s per beat")
checkClose(TempoMath.samplesPerBeat(bpm: 120, sampleRate: 48_000), 24_000, "samples per beat @ 48 kHz")
checkClose(TempoMath.stepInterval(bpm: 120, stepsPerBeat: 3), 0.5 / 3, "triplet step interval")
checkClose(TempoMath.stepInterval(bpm: 120, stepsPerBeat: 1), 0.5, "no-subdivision step interval")

// MARK: - Time signatures

print("Time signatures")
checkEqual(TimeSignature(beats: 0, noteValue: 7), TimeSignature(beats: 1, noteValue: 4), "clamps invalid signature")
checkEqual(TimeSignature(beats: 99, noteValue: 4), TimeSignature(beats: 16, noteValue: 4), "clamps beats to 16")
checkEqual(TimeSignature(beats: 4, noteValue: 32), TimeSignature(beats: 4, noteValue: 4), "clamps note value")
checkEqual(TimeSignature(beats: 4, noteValue: 4).accentedBeats, [0], "4/4 accents beat 1")
checkEqual(TimeSignature(beats: 6, noteValue: 8).accentedBeats, [0, 3], "6/8 accents both groups")
checkEqual(TimeSignature(beats: 9, noteValue: 8).accentedBeats, [0, 3, 6], "9/8 accents three groups")
checkEqual(TimeSignature(beats: 12, noteValue: 8).accentedBeats, [0, 3, 6, 9], "12/8 accents four groups")
check(!TimeSignature(beats: 3, noteValue: 8).isCompound, "3/8 is a simple meter")
check(!TimeSignature(beats: 7, noteValue: 8).isCompound, "7/8 is an irregular meter")
checkEqual(TimeSignature(beats: 6, noteValue: 8).grouping, [3, 3], "6/8 groups as 3+3")
checkEqual(TimeSignature(beats: 4, noteValue: 4).grouping, [4], "4/4 groups as 4")

// MARK: - Tap tempo

print("Tap tempo")
do {
    var tap = TapTempo()
    check(tap.register(at: 0) == nil, "first tap does not produce a BPM")
    checkClose(tap.register(at: 0.5) ?? 0, 120, tolerance: 0.001, "two taps at 0.5 s = 120 BPM")
    checkClose(tap.register(at: 1.0) ?? 0, 120, tolerance: 0.001, "third tap keeps 120 BPM")
    checkEqual(tap.tapCount, 3, "tap count")
}
do {
    var tap = TapTempo()
    _ = tap.register(at: 0)
    _ = tap.register(at: 0.02)
    checkEqual(tap.tapCount, 1, "impossible double tap is ignored")
}
do {
    var tap = TapTempo()
    _ = tap.register(at: 0)
    _ = tap.register(at: 0.5)
    check(tap.register(at: 3.0) == nil, "tap after a long pause starts over")
    checkEqual(tap.tapCount, 1, "tap count resets after pause")
}
do {
    var tap = TapTempo()
    var bpm: Double?
    for timestamp in [0, 0.5, 1.0, 1.1, 1.6, 2.1] {
        bpm = tap.register(at: timestamp)
    }
    checkClose(bpm ?? 0, 120, tolerance: 0.5, "trimmed mean shrugs off one sloppy tap")
}
do {
    var tap = TapTempo()
    _ = tap.register(at: 0)
    checkEqual(tap.register(at: 0.19) ?? 0, TempoMath.maxBPM, "tap tempo clamps at 300 BPM")
}

// MARK: - Tempo markings

print("Tempo markings")
let markings = TempoMarking.all
checkEqual(markings.first?.lowerBound, TempoMath.minBPM, "markings start at 30 BPM")
checkEqual(markings.last?.upperBound, .infinity, "last marking is open ended")
for pair in zip(markings, markings.dropFirst()) {
    checkEqual(pair.0.upperBound, pair.1.lowerBound, "markings are contiguous")
}
checkEqual(TempoMarking.marking(for: 30).italian, "Grave", "30 BPM is Grave")
checkEqual(TempoMarking.marking(for: 119.9).italian, "Allegretto", "119.9 BPM is Allegretto")
checkEqual(TempoMarking.marking(for: 120).italian, "Allegro", "120 BPM is Allegro")
checkEqual(TempoMarking.marking(for: 300).italian, "Prestissimo", "300 BPM is Prestissimo")

// MARK: - Subdivisions

print("Subdivisions")
checkEqual(Subdivision.none.stepsPerBeat, 1, "none = 1 step")
checkEqual(Subdivision.eighth.stepsPerBeat, 2, "eighth = 2 steps")
checkEqual(Subdivision.triplet.stepsPerBeat, 3, "triplet = 3 steps")
checkEqual(Subdivision.sixteenth.stepsPerBeat, 4, "sixteenth = 4 steps")

// MARK: - Scheduler drift (the same accumulating math the engine uses)

print("Scheduler drift")
/// Mirrors ClickScheduler: keep the beat position in Double, round to whole
/// samples when scheduling.  Runs for 10 minutes of audio.
func simulateBeatDrift(bpm: Double, sampleRate: Double, beats: Int) -> Double {
    var currentBeatStart = 0.0
    let beatDuration = TempoMath.samplesPerBeat(bpm: bpm, sampleRate: sampleRate)
    var worstError = 0.0

    for index in 0..<beats {
        let scheduled = currentBeatStart.rounded()
        let ideal = Double(index) * TempoMath.samplesPerBeat(bpm: bpm, sampleRate: sampleRate)
        worstError = max(worstError, abs(scheduled - ideal))
        currentBeatStart += beatDuration
    }
    return worstError
}

// 120 BPM for 10 minutes = 1200 beats; 137 BPM is a deliberately awkward tempo.
for bpm in [60.0, 120.0, 137.0, 208.0] {
    let beats = Int(TempoMath.beatInterval(bpm: bpm) * 600.0)
    let error = simulateBeatDrift(bpm: bpm, sampleRate: 48_000, beats: beats)
    check(error <= 1.0, "beat \(bpm) BPM drifts by at most one sample over 10 minutes (error \(error))")
}

/// Subdivision offsets inside a beat should be evenly spaced.
func simulateStepOffsets(bpm: Double, steps: Int, sampleRate: Double) -> [Double] {
    let beatDuration = TempoMath.samplesPerBeat(bpm: bpm, sampleRate: sampleRate)
    return (0..<steps).map { step in
        (Double(step) / Double(steps) * beatDuration).rounded()
    }
}

for steps in [1, 2, 3, 4] {
    let offsets = simulateStepOffsets(bpm: 120, steps: steps, sampleRate: 48_000)
    let expected = (0..<steps).map { Double($0) * 24_000 / Double(steps) }
    for (actual, ideal) in zip(offsets, expected) {
        checkClose(actual, ideal, tolerance: 1.0, "\(steps) subdivision steps are evenly spaced")
    }
}

// MARK: - Settings

print("Settings")
var repaired = MetronomeSettings.default
repaired.bpm = 9_999
repaired.volume = 3
repaired.countInBars = 99
repaired.timeSignature = TimeSignature(beats: 200, noteValue: 4)
let validated = repaired.validated()
checkEqual(validated.bpm, TempoMath.maxBPM, "validated BPM")
checkEqual(validated.volume, 1, "validated volume")
checkEqual(validated.countInBars, 4, "validated count-in bars")
checkEqual(validated.timeSignature.beats, 16, "validated signature")
checkEqual(MetronomeSettings.default.displayMode, .pendulum, "default display mode")

var roundTrip = MetronomeSettings.default
roundTrip.bpm = 88
roundTrip.timeSignature = TimeSignature(beats: 6, noteValue: 8)
roundTrip.subdivision = .triplet
roundTrip.displayMode = .digits
roundTrip.clickSound = .woodblock
roundTrip.hapticsEnabled = true
roundTrip.countInBars = 1
do {
    let data = try JSONEncoder().encode(roundTrip)
    let decoded = try JSONDecoder().decode(MetronomeSettings.self, from: data)
    checkEqual(decoded, roundTrip, "settings survive a JSON round trip")
checkEqual(decoded.displayMode, .digits, "display mode survives a JSON round trip")
}
do {
    let decoded = try JSONDecoder().decode(MetronomeSettings.self, from: Data("{}".utf8))
    checkEqual(decoded, MetronomeSettings.default, "missing JSON keys fall back to defaults")
}

// MARK: - Localized formatting

print("Localized formatting")
checkEqual(localizedInteger("Bar %lld", 7), "Bar 7", "integer placeholder is substituted")

// MARK: - Summary

print("")
if failures == 0 {
    print("✓ \(checks) checks passed")
    exit(0)
} else {
    print("✗ \(failures) of \(checks) checks failed")
    exit(1)
}
