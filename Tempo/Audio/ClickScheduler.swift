//
//  ClickScheduler.swift
//  Tempo
//
//  This is the heart of the metronome.
//
//  A small timer on a dedicated queue wakes up every few milliseconds and only
//  looks a short distance into the future. Click buffers are placed on the
//  AVAudioPlayerNode timeline with absolute sample times, so the audio hardware
//  clock — not the timer — is what actually keeps time. Timer jitter can only
//  affect *when a buffer is queued*, never the moment it sounds.
//

import AVFoundation

final class ClickScheduler {
    struct Configuration: Equatable {
        var bpm: Double = 120
        var beatsPerBar: Int = 4
        var subdivision: Int = 1
        var accentedBeats: Set<Int> = [0]
        var sound: ClickSound = .classic
        var countInBeats: Int = 0
    }

    struct Click {
        let sampleTime: AVAudioFramePosition
        let kind: ClickKind
        /// Beat index inside the bar (0 based).
        let beatIndex: Int
        let barIndex: Int
        let isCountIn: Bool
        /// Sample time of the beat this click belongs to (the parent beat for
        /// subdivision clicks), used by the UI to derive the beat phase.
        let beatStartSample: AVAudioFramePosition
        let beatDurationSamples: Double
    }

    private let player: AVAudioPlayerNode
    private let bank: ClickBank
    private let sampleRate: Double

    private let queue = DispatchQueue(label: "com.sunday.tempo.click-scheduler", qos: .userInteractive)
    private let lock = NSLock()

    // Shared with the UI thread.
    private var configuration = Configuration()
    private var log: [Click] = []
    private var lookaheadSeconds: TimeInterval = 0.20

    private var timer: DispatchSourceTimer?

    // Confined to `queue`.
    private var anchored = false
    private var currentBeatStart: Double = 0
    private var beatDurationSamples: Double = 0
    private var stepInBeat = 0
    private var beatInBar = 0
    private var barIndex = 0
    private var countInRemaining = 0
    private var activeSubdivision = 1
    private var activeBeatsPerBar = 4

    /// Delay between pressing start and the first click, so the UI has a
    /// moment to react and the first buffer is never scheduled in the past.
    private let startLeadSeconds: TimeInterval = 0.09
    private let tickInterval: TimeInterval = 0.008
    private let maxLoggedClicks = 48

    init(player: AVAudioPlayerNode, bank: ClickBank, sampleRate: Double) {
        self.player = player
        self.bank = bank
        self.sampleRate = sampleRate
    }

    // MARK: - Control

    func start() {
        queue.sync {
            stopTimerLocked()
            let config = configurationSnapshot()
            anchored = false
            stepInBeat = 0
            beatInBar = 0
            barIndex = 0
            activeSubdivision = max(1, config.subdivision)
            activeBeatsPerBar = max(1, config.beatsPerBar)
            countInRemaining = max(0, config.countInBeats)
            beatDurationSamples = TempoMath.samplesPerBeat(bpm: config.bpm, sampleRate: sampleRate)
            clearLog()

            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(
                deadline: .now(),
                repeating: tickInterval,
                leeway: .milliseconds(2)
            )
            timer.setEventHandler { [weak self] in
                self?.tick()
            }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        queue.sync {
            stopTimerLocked()
            anchored = false
            clearLog()
        }
    }

    func update(_ configuration: Configuration) {
        lock.lock()
        self.configuration = configuration
        lock.unlock()
    }

    /// A longer lookahead is used while the app is in the background, where the
    /// system may coalesce timer wake-ups. The audio clock is unaffected.
    func setLookahead(_ seconds: TimeInterval) {
        lock.lock()
        lookaheadSeconds = min(max(seconds, 0.05), 2.0)
        lock.unlock()
    }

    // MARK: - Read side (called from the UI thread)

    func recentClicks(limit: Int = 24) -> [Click] {
        lock.lock()
        defer { lock.unlock() }
        return Array(log.suffix(limit))
    }

    /// The player's current position on the audio timeline.
    func currentSampleTime() -> AVAudioFramePosition? {
        guard
            let renderTime = player.lastRenderTime,
            renderTime.isSampleTimeValid,
            let playerTime = player.playerTime(forNodeTime: renderTime),
            playerTime.isSampleTimeValid
        else {
            return nil
        }
        return playerTime.sampleTime
    }

    // MARK: - Scheduling

    private func tick() {
        guard let now = currentSampleTime() else { return }
        let config = configurationSnapshot()

        if !anchored {
            let lead = AVAudioFramePosition((startLeadSeconds * sampleRate).rounded())
            currentBeatStart = Double(now + lead)
            beatDurationSamples = TempoMath.samplesPerBeat(bpm: config.bpm, sampleRate: sampleRate)
            anchored = true
        }

        let horizon = now + AVAudioFramePosition((lookaheadSeconds * sampleRate).rounded())
        let tooOld = now - AVAudioFramePosition((0.05 * sampleRate).rounded())

        // If the main thread was blocked (or we just came back from the
        // background) advance the musical position instead of firing a burst of
        // late clicks.
        var skipped = 0
        while nextClickSampleTime < tooOld, skipped < 4096 {
            advanceStep()
            skipped += 1
        }

        // Still behind after the safety limit (device slept for a long time):
        // re-anchor the grid just ahead of now instead of firing a burst of
        // clicks that are already in the past.
        if nextClickSampleTime < tooOld {
            let stepFraction = Double(stepInBeat) / Double(max(1, activeSubdivision))
            let lead = AVAudioFramePosition((startLeadSeconds * sampleRate).rounded())
            currentBeatStart = Double(now + lead) - beatDurationSamples * stepFraction
        }

        while nextClickSampleTime <= horizon {
            scheduleClick(at: nextClickSampleTime)
            advanceStep()
        }

        pruneLog(before: now - AVAudioFramePosition((4 * sampleRate).rounded()))
    }

    private var nextClickSampleTime: AVAudioFramePosition {
        let stepFraction = Double(stepInBeat) / Double(max(1, activeSubdivision))
        return AVAudioFramePosition((currentBeatStart + beatDurationSamples * stepFraction).rounded())
    }

    private func scheduleClick(at sampleTime: AVAudioFramePosition) {
        let config = configurationSnapshot()
        let isCountIn = countInRemaining > 0

        let kind: ClickKind
        if stepInBeat > 0 {
            kind = .subdivision
        } else if isCountIn {
            kind = beatInBar == 0 ? .accent : .beat
        } else if config.accentedBeats.contains(beatInBar) {
            kind = .accent
        } else {
            kind = .beat
        }

        let buffer = bank.buffer(sound: config.sound, kind: kind)
        let time = AVAudioTime(sampleTime: sampleTime, atRate: sampleRate)
        player.scheduleBuffer(buffer, at: time, options: [], completionHandler: nil)

        appendLog(
            Click(
                sampleTime: sampleTime,
                kind: kind,
                beatIndex: beatInBar,
                barIndex: barIndex,
                isCountIn: isCountIn,
                beatStartSample: AVAudioFramePosition(currentBeatStart.rounded()),
                beatDurationSamples: beatDurationSamples
            )
        )
    }

    private func advanceStep() {
        stepInBeat += 1
        guard stepInBeat >= activeSubdivision else { return }

        stepInBeat = 0
        currentBeatStart += beatDurationSamples

        let config = configurationSnapshot()
        beatDurationSamples = TempoMath.samplesPerBeat(bpm: config.bpm, sampleRate: sampleRate)
        // Tempo changes take effect on the next beat. Subdivision changes are
        // also applied on beat boundaries so a half-played beat stays coherent.
        activeSubdivision = max(1, config.subdivision)
        advanceBeat()
    }

    private func advanceBeat() {
        let config = configurationSnapshot()

        if countInRemaining > 0 {
            countInRemaining -= 1
            if countInRemaining == 0 {
                // Count-in finished: the first real beat starts now.
                beatInBar = 0
                barIndex = 0
                activeBeatsPerBar = max(1, config.beatsPerBar)
            } else {
                beatInBar = (beatInBar + 1) % max(1, activeBeatsPerBar)
            }
            return
        }

        beatInBar += 1
        if beatInBar >= activeBeatsPerBar {
            beatInBar = 0
            barIndex += 1
            // Signature changes are picked up at the next bar line.
            activeBeatsPerBar = max(1, config.beatsPerBar)
        }
    }

    private func stopTimerLocked() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
    }

    // MARK: - Shared state

    private func configurationSnapshot() -> Configuration {
        lock.lock()
        defer { lock.unlock() }
        return configuration
    }

    private func appendLog(_ click: Click) {
        lock.lock()
        log.append(click)
        if log.count > maxLoggedClicks {
            log.removeFirst(log.count - maxLoggedClicks)
        }
        lock.unlock()
    }

    private func pruneLog(before threshold: AVAudioFramePosition) {
        lock.lock()
        log.removeAll { $0.beatStartSample < threshold }
        lock.unlock()
    }

    private func clearLog() {
        lock.lock()
        log.removeAll()
        lock.unlock()
    }
}
