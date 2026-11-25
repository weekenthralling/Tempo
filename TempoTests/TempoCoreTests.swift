//
//  TempoCoreTests.swift
//  TempoTests
//
//  Unit tests for the pure (non-audio) logic. Everything that decides timing,
//  accents or persisted state is covered here so a change in the math shows up
//  long before anyone listens to the clicks.
//

import XCTest
@testable import Tempo

final class TempoCoreTests: XCTestCase {

    // MARK: - BPM math

    func testClampBPM() {
        XCTAssertEqual(TempoMath.clampBPM(10), TempoMath.minBPM)
        XCTAssertEqual(TempoMath.clampBPM(1_000), TempoMath.maxBPM)
        XCTAssertEqual(TempoMath.clampBPM(120), 120)
        XCTAssertEqual(TempoMath.clampBPM(.nan), 120)
        XCTAssertEqual(TempoMath.clampBPM(.infinity), TempoMath.maxBPM)
        XCTAssertEqual(TempoMath.clampBPM(-.infinity), TempoMath.minBPM)
    }

    func testBeatInterval() {
        XCTAssertEqual(TempoMath.beatInterval(bpm: 60), 1, accuracy: 1e-12)
        XCTAssertEqual(TempoMath.beatInterval(bpm: 120), 0.5, accuracy: 1e-12)
        XCTAssertEqual(TempoMath.beatInterval(bpm: 240), 0.25, accuracy: 1e-12)
    }

    func testSamplesPerBeat() {
        XCTAssertEqual(TempoMath.samplesPerBeat(bpm: 120, sampleRate: 48_000), 24_000, accuracy: 1e-9)
        XCTAssertEqual(TempoMath.samplesPerBeat(bpm: 90, sampleRate: 44_100), 44_100 * 2.0 / 3.0, accuracy: 1e-6)
    }

    func testStepIntervalDividesBeatEvenly() {
        XCTAssertEqual(TempoMath.stepInterval(bpm: 120, stepsPerBeat: 3), 0.5 / 3, accuracy: 1e-12)
        XCTAssertEqual(TempoMath.stepInterval(bpm: 120, stepsPerBeat: 1), 0.5, accuracy: 1e-12)
    }

    // MARK: - Time signatures

    func testTimeSignatureClampsUnsupportedInput() {
        XCTAssertEqual(TimeSignature(beats: 0, noteValue: 7), TimeSignature(beats: 1, noteValue: 4))
        XCTAssertEqual(TimeSignature(beats: 99, noteValue: 4), TimeSignature(beats: 16, noteValue: 4))
        XCTAssertEqual(TimeSignature(beats: 4, noteValue: 32), TimeSignature(beats: 4, noteValue: 4))
    }

    func testSimpleMetersAccentOnlyTheDownbeat() {
        XCTAssertEqual(TimeSignature(beats: 4, noteValue: 4).accentedBeats, [0])
        XCTAssertEqual(TimeSignature(beats: 3, noteValue: 4).accentedBeats, [0])
        XCTAssertEqual(TimeSignature(beats: 2, noteValue: 4).accentedBeats, [0])
        XCTAssertEqual(TimeSignature(beats: 5, noteValue: 4).accentedBeats, [0])
    }

    func testCompoundMetersAccentEachGroup() {
        XCTAssertTrue(TimeSignature(beats: 6, noteValue: 8).isCompound)
        XCTAssertEqual(TimeSignature(beats: 6, noteValue: 8).accentedBeats, [0, 3])
        XCTAssertEqual(TimeSignature(beats: 9, noteValue: 8).accentedBeats, [0, 3, 6])
        XCTAssertEqual(TimeSignature(beats: 12, noteValue: 8).accentedBeats, [0, 3, 6, 9])

        // 3/8 is simple triple, 7/8 is irregular: both accent only beat 1.
        XCTAssertFalse(TimeSignature(beats: 3, noteValue: 8).isCompound)
        XCTAssertEqual(TimeSignature(beats: 3, noteValue: 8).accentedBeats, [0])
        XCTAssertFalse(TimeSignature(beats: 7, noteValue: 8).isCompound)
        XCTAssertEqual(TimeSignature(beats: 7, noteValue: 8).accentedBeats, [0])
    }

    func testGrouping() {
        XCTAssertEqual(TimeSignature(beats: 6, noteValue: 8).grouping, [3, 3])
        XCTAssertEqual(TimeSignature(beats: 9, noteValue: 8).grouping, [3, 3, 3])
        XCTAssertEqual(TimeSignature(beats: 4, noteValue: 4).grouping, [4])
    }

    func testTimeSignatureCodableRoundTrip() throws {
        let original = TimeSignature(beats: 7, noteValue: 8)
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(TimeSignature.self, from: data), original)
    }

    // MARK: - Tap tempo

    func testTapTempoNeedsTwoTaps() {
        var tap = TapTempo()
        XCTAssertNil(tap.register(at: 0))
        XCTAssertEqual(tap.register(at: 0.5) ?? 0, 120, accuracy: 0.001)
        XCTAssertEqual(tap.tapCount, 2)
    }

    func testTapTempoAveragesIntervals() {
        var tap = TapTempo()
        XCTAssertNil(tap.register(at: 0))
        // The second tap already yields a tempo.
        XCTAssertEqual(tap.register(at: 0.6) ?? 0, 100, accuracy: 0.001)
        XCTAssertEqual(tap.register(at: 1.2) ?? 0, 100, accuracy: 0.001)
    }

    func testTapTempoIgnoresImpossibleDoubleTaps() {
        var tap = TapTempo()
        XCTAssertNil(tap.register(at: 0))
        XCTAssertNil(tap.register(at: 0.02))
        XCTAssertEqual(tap.tapCount, 1)
    }

    func testTapTempoStartsOverAfterPause() {
        var tap = TapTempo()
        XCTAssertNil(tap.register(at: 0))
        XCTAssertEqual(tap.register(at: 0.5) ?? 0, 120, accuracy: 0.001)
        // Pause longer than the reset interval: the next tap starts a new run.
        XCTAssertNil(tap.register(at: 3.0))
        XCTAssertEqual(tap.tapCount, 1)
    }

    func testTapTempoTrimsOutliers() {
        var tap = TapTempo()
        let timestamps: [TimeInterval] = [0, 0.5, 1.0, 1.1, 1.6, 2.1]
        var lastBPM: Double?
        for timestamp in timestamps {
            lastBPM = tap.register(at: timestamp)
        }
        XCTAssertEqual(lastBPM ?? 0, 120, accuracy: 0.5)
    }

    func testTapTempoClampsToSupportedRange() {
        var tap = TapTempo()
        XCTAssertNil(tap.register(at: 0))
        XCTAssertEqual(tap.register(at: 0.19) ?? 0, TempoMath.maxBPM)
    }

    // MARK: - Tempo markings

    func testTempoMarkingsAreContiguous() {
        let markings = TempoMarking.all
        XCTAssertEqual(markings.first?.lowerBound, TempoMath.minBPM)
        for pair in zip(markings, markings.dropFirst()) {
            XCTAssertEqual(pair.0.upperBound, pair.1.lowerBound)
        }
        XCTAssertEqual(markings.last?.upperBound, .infinity)
    }

    func testTempoMarkingLookup() {
        XCTAssertEqual(TempoMarking.marking(for: 30).italian, "Grave")
        XCTAssertEqual(TempoMarking.marking(for: 119.9).italian, "Allegretto")
        XCTAssertEqual(TempoMarking.marking(for: 120).italian, "Allegro")
        XCTAssertEqual(TempoMarking.marking(for: 200).italian, "Prestissimo")
        XCTAssertEqual(TempoMarking.marking(for: 300).italian, "Prestissimo")
    }

    // MARK: - Subdivisions

    func testSubdivisionSteps() {
        XCTAssertEqual(Subdivision.none.stepsPerBeat, 1)
        XCTAssertEqual(Subdivision.eighth.stepsPerBeat, 2)
        XCTAssertEqual(Subdivision.triplet.stepsPerBeat, 3)
        XCTAssertEqual(Subdivision.sixteenth.stepsPerBeat, 4)
    }

    // MARK: - Settings

    func testSettingsValidationRepairsOutOfRangeValues() {
        var settings = MetronomeSettings.default
        settings.bpm = 9_999
        settings.volume = 3
        settings.countInBars = 99
        settings.timeSignature = TimeSignature(beats: 200, noteValue: 4)

        let repaired = settings.validated()
        XCTAssertEqual(repaired.bpm, TempoMath.maxBPM)
        XCTAssertEqual(repaired.volume, 1)
        XCTAssertEqual(TempoMath.clampVolume(.infinity), 1)
        XCTAssertEqual(TempoMath.clampVolume(.nan), 0.8)
        XCTAssertEqual(repaired.countInBars, 4)
        XCTAssertEqual(repaired.timeSignature.beats, 16)
    }

    func testSettingsCodableRoundTrip() throws {
        var original = MetronomeSettings.default
        original.bpm = 88
        original.timeSignature = TimeSignature(beats: 6, noteValue: 8)
        original.subdivision = .triplet
        original.displayMode = .digits
        original.clickSound = .woodblock
        original.hapticsEnabled = true
        original.countInBars = 1

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MetronomeSettings.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testDefaultDisplayModeIsPendulum() {
        XCTAssertEqual(MetronomeSettings.default.displayMode, .pendulum)
        XCTAssertEqual(DisplayMode.allCases, [.digits, .pendulum])
    }

    func testSettingsDecodingUsesDefaultsForMissingKeys() throws {
        let data = Data("{}".utf8)
        let decoded = try JSONDecoder().decode(MetronomeSettings.self, from: data)
        XCTAssertEqual(decoded, MetronomeSettings.default)
    }

    func testSettingsStorePersists() {
        let suiteName = "tempo.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var settings = MetronomeSettings.default
        settings.bpm = 144
        settings.clickSound = .digital

        let store = SettingsStore(defaults: defaults)
        store.save(settings)
        XCTAssertEqual(store.load(), settings)
    }

    func testSettingsStoreFallsBackToDefaultsWhenEmpty() {
        let suiteName = "tempo.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.load(), .default)
    }
}
