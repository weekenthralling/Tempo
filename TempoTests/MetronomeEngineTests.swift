//
//  MetronomeEngineTests.swift
//  TempoTests
//
//  These run inside the app host on the simulator, so they exercise the real
//  audio graph and the audio-clock -> UI pipeline, not just the pure math.
//

import XCTest
@testable import Tempo

@MainActor
final class MetronomeEngineTests: XCTestCase {
    private func makeEngine() -> (engine: MetronomeEngine, defaults: UserDefaults, suiteName: String) {
        let suiteName = "tempo.engine.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (MetronomeEngine(store: SettingsStore(defaults: defaults)), defaults, suiteName)
    }

    func testStartReachesTheFirstBeatOnTheAudioClock() async throws {
        let context = makeEngine()
        defer {
            context.engine.stop()
            context.defaults.removePersistentDomain(forName: context.suiteName)
        }

        context.engine.bpm = 120
        context.engine.start()

        XCTAssertTrue(context.engine.isRunning)
        XCTAssertNil(context.engine.errorMessage)

        // The scheduler starts 90 ms after the press and the display link needs
        // a few frames, so give the simulator some slack.
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, context.engine.displayedBeat < 0 {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertEqual(context.engine.displayedBeat, 0, "First beat should become visible")
        XCTAssertGreaterThan(context.engine.beatPhase, 0, "Beat phase should advance with the audio clock")
        XCTAssertEqual(context.engine.displayedBar, 0)

        context.engine.stop()
        XCTAssertFalse(context.engine.isRunning)
        XCTAssertEqual(context.engine.displayedBeat, -1)
        XCTAssertEqual(context.engine.beatPhase, 0)
    }

    func testCountInDoesNotStartAtBarOne() async throws {
        let context = makeEngine()
        defer {
            context.engine.stop()
            context.defaults.removePersistentDomain(forName: context.suiteName)
        }

        context.engine.bpm = 180
        context.engine.countInBars = 1
        context.engine.timeSignature = TimeSignature(beats: 2, noteValue: 4)
        context.engine.start()

        XCTAssertTrue(context.engine.isRunning)
        XCTAssertNil(context.engine.errorMessage)

        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, !context.engine.isCountingIn {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(context.engine.isCountingIn, "Count-in should be reported")
    }

    func testStoppingWhileIdleIsSafe() {
        let context = makeEngine()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }

        context.engine.stop()
        XCTAssertFalse(context.engine.isRunning)
        XCTAssertEqual(context.engine.displayedBeat, -1)
    }

    func testSoundPreviewDoesNotStartTheMetronome() async throws {
        let context = makeEngine()
        defer {
            context.engine.stop()
            context.defaults.removePersistentDomain(forName: context.suiteName)
        }

        context.engine.previewClickSound()
        XCTAssertFalse(context.engine.isRunning)
        XCTAssertNil(context.engine.errorMessage)
        // Let the preview teardown task run so it cannot leak into other tests.
        try await Task.sleep(nanoseconds: 500_000_000)
    }

    func testChangingTempoAndSignatureWhileRunningKeepsTicking() async throws {
        let context = makeEngine()
        defer {
            context.engine.stop()
            context.defaults.removePersistentDomain(forName: context.suiteName)
        }

        context.engine.start()
        XCTAssertTrue(context.engine.isRunning)

        context.engine.bpm = 240
        context.engine.subdivision = .triplet
        context.engine.timeSignature = TimeSignature(beats: 3, noteValue: 4)

        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertTrue(context.engine.isRunning)
        XCTAssertNil(context.engine.errorMessage)
        XCTAssertGreaterThanOrEqual(context.engine.displayedBeat, 0)
    }
}
