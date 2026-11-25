//
//  MetronomeEngine.swift
//  Tempo
//
//  Observable facade over the audio graph and the scheduler.
//
//  The engine never uses a timer to make sound. It queues click buffers on the
//  audio timeline (ClickScheduler) and then reads the *render position* of the
//  player on every display refresh to drive the UI — so what you see is derived
//  from the same clock as what you hear.
//

import AVFoundation
import Observation
import QuartzCore
import SwiftUI
import UIKit

@MainActor
@Observable
final class MetronomeEngine {

    // MARK: - State for the UI (updated from the audio clock)

    private(set) var isRunning = false
    private(set) var isCountingIn = false
    private(set) var displayedBeat = -1
    private(set) var displayedBar = 0
    /// 0...1 progress through the current beat.
    private(set) var beatPhase: Double = 0
    /// Incremented once per audible beat so views can trigger one-shot effects.
    private(set) var pulseToken = 0
    private(set) var pulseKind: ClickKind = .beat
    private(set) var tapCount = 0
    var errorMessage: String?

    // MARK: - Persisted settings

    private let store: SettingsStore
    private var settings: MetronomeSettings

    // MARK: - Audio graph

    private let audioEngine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let previewPlayer = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private let bank: ClickBank
    private let scheduler: ClickScheduler
    private let session = AudioSessionController()
    private let nowPlaying = NowPlayingController()

    private let hapticAccent = UIImpactFeedbackGenerator(style: .medium)
    private let hapticBeat = UIImpactFeedbackGenerator(style: .light)

    // MARK: - Bookkeeping

    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private var displayProxy: DisplayLinkProxy?
    @ObservationIgnored private var lastBeatStartSample: AVAudioFramePosition?
    @ObservationIgnored private var resumeAfterInterruption = false
    @ObservationIgnored private var tapTempo = TapTempo()
    @ObservationIgnored private var tapResetTask: Task<Void, Never>?
    @ObservationIgnored private var previewTeardownTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var nowPlayingToken = ""

    // MARK: - Init

    init(store: SettingsStore = SettingsStore()) {
        let audioFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)
            ?? AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let clickBank = ClickBank(format: audioFormat)

        self.store = store
        self.settings = store.load()
        self.format = audioFormat
        self.bank = clickBank
        self.scheduler = ClickScheduler(player: player, bank: clickBank, sampleRate: audioFormat.sampleRate)

        configureGraph()
        configureCallbacks()
        updateNowPlaying()
    }

    deinit {
        displayLink?.invalidate()
    }

    // MARK: - Settings surface

    var bpm: Double {
        get { settings.bpm }
        set {
            let value = TempoMath.clampBPM(newValue)
            guard value != settings.bpm else { return }
            settings.bpm = value
            settingsDidChange()
        }
    }

    var timeSignature: TimeSignature {
        get { settings.timeSignature }
        set {
            let value = TimeSignature(beats: newValue.beats, noteValue: newValue.noteValue)
            guard value != settings.timeSignature else { return }
            settings.timeSignature = value
            settingsDidChange()
        }
    }

    var subdivision: Subdivision {
        get { settings.subdivision }
        set {
            guard newValue != settings.subdivision else { return }
            settings.subdivision = newValue
            settingsDidChange()
        }
    }

    var displayMode: DisplayMode {
        get { settings.displayMode }
        set {
            guard newValue != settings.displayMode else { return }
            settings.displayMode = newValue
            settingsDidChange()
        }
    }

    var accentFirstBeat: Bool {
        get { settings.accentFirstBeat }
        set {
            guard newValue != settings.accentFirstBeat else { return }
            settings.accentFirstBeat = newValue
            settingsDidChange()
        }
    }

    var clickSound: ClickSound {
        get { settings.clickSound }
        set {
            guard newValue != settings.clickSound else { return }
            settings.clickSound = newValue
            settingsDidChange()
        }
    }

    var volume: Double {
        get { settings.volume }
        set {
            let value = TempoMath.clampVolume(newValue)
            guard value != settings.volume else { return }
            settings.volume = value
            settingsDidChange()
        }
    }

    var hapticsEnabled: Bool {
        get { settings.hapticsEnabled }
        set {
            guard newValue != settings.hapticsEnabled else { return }
            settings.hapticsEnabled = newValue
            settingsDidChange()
        }
    }

    var flashEnabled: Bool {
        get { settings.flashEnabled }
        set {
            guard newValue != settings.flashEnabled else { return }
            settings.flashEnabled = newValue
            settingsDidChange()
        }
    }

    var keepScreenAwake: Bool {
        get { settings.keepScreenAwake }
        set {
            guard newValue != settings.keepScreenAwake else { return }
            settings.keepScreenAwake = newValue
            settingsDidChange()
        }
    }

    var mixWithOtherAudio: Bool {
        get { settings.mixWithOtherAudio }
        set {
            guard newValue != settings.mixWithOtherAudio else { return }
            settings.mixWithOtherAudio = newValue
            if isRunning {
                try? session.activate(mixWithOthers: newValue)
            }
            settingsDidChange()
        }
    }

    var countInBars: Int {
        get { settings.countInBars }
        set {
            let value = min(max(newValue, 0), 4)
            guard value != settings.countInBars else { return }
            settings.countInBars = value
            settingsDidChange()
        }
    }

    var tempoMarking: TempoMarking {
        TempoMarking.marking(for: settings.bpm)
    }

    /// Seconds per beat, used by views for animation durations.
    var beatDuration: TimeInterval {
        TempoMath.beatInterval(bpm: settings.bpm)
    }

    // MARK: - Transport

    func toggle() {
        if isRunning {
            stop()
        } else {
            start()
        }
    }

    func start() {
        guard !isRunning else { return }
        errorMessage = nil

        do {
            try session.activate(mixWithOthers: settings.mixWithOtherAudio)
            if !audioEngine.isRunning {
                audioEngine.prepare()
                try audioEngine.start()
            }
            player.play()
        } catch {
            session.deactivate()
            errorMessage = (error as NSError).localizedDescription
            return
        }

        resetVisualState()
        scheduler.update(makeConfiguration())
        scheduler.start()

        isRunning = true
        resumeAfterInterruption = false
        hapticAccent.prepare()
        hapticBeat.prepare()
        startDisplayLink()
        updateIdleTimer()
        updateNowPlaying()
    }

    func stop() {
        guard isRunning else { return }
        flushSettings()
        scheduler.stop()
        player.stop()
        previewPlayer.stop()
        audioEngine.pause()
        session.deactivate()

        isRunning = false
        stopDisplayLink()
        resetVisualState()
        updateIdleTimer()
        updateNowPlaying()
    }

    func tapTempoBPM() {
        tapResetTask?.cancel()
        if let value = tapTempo.register(at: CACurrentMediaTime()) {
            bpm = value.rounded()
        }
        tapCount = tapTempo.tapCount

        tapResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_100_000_000)
            guard !Task.isCancelled, let self else { return }
            self.tapTempo.reset()
            self.tapCount = 0
        }
    }

    /// Plays the currently selected sound without starting the metronome.
    func previewClickSound() {
        guard !isRunning else { return }
        do {
            try session.activate(mixWithOthers: settings.mixWithOtherAudio)
            if !audioEngine.isRunning {
                audioEngine.prepare()
                try audioEngine.start()
            }
            if !previewPlayer.isPlaying {
                previewPlayer.play()
            }
            previewPlayer.scheduleBuffer(
                bank.buffer(sound: settings.clickSound, kind: .accent),
                at: nil,
                options: [],
                completionHandler: nil
            )
            schedulePreviewTeardown()
        } catch {
            session.deactivate()
            errorMessage = (error as NSError).localizedDescription
        }
    }

    // MARK: - Lifecycle

    func scenePhaseDidChange(_ phase: ScenePhase) {
        switch phase {
        case .background:
            flushSettings()
            // Timer wake-ups may be coalesced in the background, so queue more
            // audio ahead. The click itself still lands on the audio clock.
            scheduler.setLookahead(0.9)
        case .active:
            scheduler.setLookahead(0.2)
            recoverAudioIfNeeded()
        default:
            scheduler.setLookahead(0.4)
        }
    }

    // MARK: - Audio clock -> UI

    func updateFromAudioClock() {
        guard isRunning else { return }
        guard let now = scheduler.currentSampleTime() else { return }

        let clicks = scheduler.recentClicks()
        var activeBeat: ClickScheduler.Click?
        for click in clicks where click.sampleTime <= now {
            if click.kind != .subdivision {
                activeBeat = click
            }
        }
        guard let beat = activeBeat else { return }

        let elapsed = Double(now - beat.beatStartSample)
        let duration = max(beat.beatDurationSamples, 1)
        beatPhase = min(max(elapsed / duration, 0), 1)

        if displayedBeat != beat.beatIndex { displayedBeat = beat.beatIndex }
        if displayedBar != beat.barIndex { displayedBar = beat.barIndex }
        if isCountingIn != beat.isCountIn { isCountingIn = beat.isCountIn }

        guard lastBeatStartSample != beat.beatStartSample else { return }
        lastBeatStartSample = beat.beatStartSample
        pulseToken &+= 1
        pulseKind = beat.kind
        emitHaptic(for: beat)
    }

    // MARK: - Graph

    private func configureGraph() {
        audioEngine.attach(player)
        audioEngine.attach(previewPlayer)
        audioEngine.connect(player, to: audioEngine.mainMixerNode, format: format)
        audioEngine.connect(previewPlayer, to: audioEngine.mainMixerNode, format: format)
        applyVolume()
        audioEngine.prepare()
    }

    private func rebuildGraph() {
        audioEngine.stop()
        audioEngine.detach(player)
        audioEngine.detach(previewPlayer)
        audioEngine.reset()
        configureGraph()
    }

    private func applyVolume() {
        let value = Self.outputVolume(for: settings.volume)
        player.volume = value
        previewPlayer.volume = value
    }

    private static func outputVolume(for volume: Double) -> Float {
        let clamped = TempoMath.clampVolume(volume)
        return Float(pow(clamped, 1.6))
    }

    private func makeConfiguration() -> ClickScheduler.Configuration {
        ClickScheduler.Configuration(
            bpm: settings.bpm,
            beatsPerBar: settings.timeSignature.beats,
            subdivision: settings.subdivision.stepsPerBeat,
            accentedBeats: settings.accentFirstBeat ? settings.timeSignature.accentedBeats : [],
            sound: settings.clickSound,
            countInBeats: settings.countInBars * settings.timeSignature.beats
        )
    }

    private func settingsDidChange() {
        scheduler.update(makeConfiguration())
        applyVolume()
        if isRunning {
            updateIdleTimer()
        }
        updateNowPlaying()
        scheduleSettingsSave()
    }

    /// Dragging the tempo slider fires this many times per second. Writing
    /// defaults and the Now Playing card on every tick is wasted work, so both
    /// are coalesced.
    private func scheduleSettingsSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, let self else { return }
            self.store.save(self.settings)
        }
    }

    private func flushSettings() {
        saveTask?.cancel()
        saveTask = nil
        store.save(settings)
    }

    // MARK: - Display link

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let proxy = DisplayLinkProxy(engine: self)
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayProxy = proxy
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        displayProxy = nil
    }

    private func resetVisualState() {
        displayedBeat = -1
        displayedBar = 0
        isCountingIn = false
        beatPhase = 0
        lastBeatStartSample = nil
    }

    private func emitHaptic(for click: ClickScheduler.Click) {
        guard settings.hapticsEnabled else { return }
        switch click.kind {
        case .accent:
            hapticAccent.impactOccurred(intensity: 1.0)
            hapticAccent.prepare()
        case .beat:
            hapticBeat.impactOccurred(intensity: 0.65)
            hapticBeat.prepare()
        case .subdivision:
            break
        }
    }

    // MARK: - Interruptions & recovery

    private func configureCallbacks() {
        session.onInterruptionBegan = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleInterruptionBegan()
            }
        }
        session.onInterruptionEnded = { [weak self] shouldResume in
            Task { @MainActor [weak self] in
                self?.handleInterruptionEnded(shouldResume: shouldResume)
            }
        }
        session.onOutputRouteLost = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleOutputRouteLost()
            }
        }
        session.onMediaServicesReset = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleMediaServicesReset()
            }
        }

        nowPlaying.onPlay = { [weak self] in
            Task { @MainActor [weak self] in
                self?.start()
            }
        }
        nowPlaying.onPause = { [weak self] in
            Task { @MainActor [weak self] in
                self?.stop()
            }
        }
        nowPlaying.onToggle = { [weak self] in
            Task { @MainActor [weak self] in
                self?.toggle()
            }
        }
    }

    private func handleInterruptionBegan() {
        guard isRunning else { return }
        flushSettings()
        resumeAfterInterruption = true
        scheduler.stop()
        player.stop()
        audioEngine.pause()
        isRunning = false
        stopDisplayLink()
        resetVisualState()
        updateIdleTimer()
        updateNowPlaying()
    }

    private func handleInterruptionEnded(shouldResume: Bool) {
        let resume = resumeAfterInterruption
        resumeAfterInterruption = false
        if resume, shouldResume {
            start()
        }
    }

    private func handleOutputRouteLost() {
        guard isRunning else { return }
        stop()
    }

    private func handleMediaServicesReset() {
        let wasRunning = isRunning
        scheduler.stop()
        player.stop()
        previewPlayer.stop()
        isRunning = false
        stopDisplayLink()
        resetVisualState()
        nowPlayingToken = ""
        rebuildGraph()
        if wasRunning {
            start()
        } else {
            updateNowPlaying()
        }
    }

    /// The audio engine can be stopped by the system without an interruption
    /// notification. When the app becomes active again, rebuild the timeline.
    private func recoverAudioIfNeeded() {
        guard isRunning, !audioEngine.isRunning else { return }
        do {
            try session.activate(mixWithOthers: settings.mixWithOtherAudio)
            audioEngine.prepare()
            try audioEngine.start()
            player.stop()
            player.play()
            scheduler.stop()
            scheduler.start()
            lastBeatStartSample = nil
        } catch {
            errorMessage = (error as NSError).localizedDescription
            stop()
        }
    }

    // MARK: - Screen / lock screen

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = settings.keepScreenAwake && isRunning
    }

    private func updateNowPlaying() {
        let signature = "\(Int(settings.bpm.rounded()))|\(settings.timeSignature.displayName)|\(isRunning)"
        guard signature != nowPlayingToken else { return }
        nowPlayingToken = signature
        nowPlaying.update(
            isPlaying: isRunning,
            bpm: settings.bpm,
            timeSignature: settings.timeSignature.displayName,
            title: Self.appDisplayName
        )
    }

    private static var appDisplayName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? "Tempo"
    }

    private func schedulePreviewTeardown() {
        previewTeardownTask?.cancel()
        previewTeardownTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_100_000_000)
            guard !Task.isCancelled, let self, !self.isRunning else { return }
            self.previewPlayer.stop()
            self.audioEngine.pause()
            self.session.deactivate()
        }
    }
}

// MARK: - Display link proxy

/// A tiny target for `CADisplayLink` that keeps a weak reference to the engine,
/// so the run loop never retains the engine (or its audio graph) forever.
@MainActor
private final class DisplayLinkProxy: NSObject {
    weak var engine: MetronomeEngine?

    init(engine: MetronomeEngine) {
        self.engine = engine
    }

    @objc func tick() {
        engine?.updateFromAudioClock()
    }
}
