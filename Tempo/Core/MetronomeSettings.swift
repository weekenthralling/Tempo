//
//  MetronomeSettings.swift
//  Tempo
//

import Foundation

/// Everything the app remembers between launches.
struct MetronomeSettings: Equatable, Sendable {
    var bpm: Double = 120
    var timeSignature: TimeSignature = .fourFour
    var subdivision: Subdivision = .none
    var displayMode: DisplayMode = .pendulum
    var accentFirstBeat: Bool = true
    var clickSound: ClickSound = .classic
    var volume: Double = 0.8
    var hapticsEnabled: Bool = false
    var flashEnabled: Bool = true
    var keepScreenAwake: Bool = true
    var mixWithOtherAudio: Bool = true
    /// Number of bars counted in before the first real bar (0 = off).
    var countInBars: Int = 0

    static let `default` = MetronomeSettings()

    /// Repairs anything that could have been stored by an older version or
    /// by a corrupted defaults file.
    func validated() -> MetronomeSettings {
        var copy = self
        copy.bpm = TempoMath.clampBPM(bpm)
        copy.volume = TempoMath.clampVolume(volume)
        copy.countInBars = min(max(countInBars, 0), 4)
        copy.timeSignature = TimeSignature(beats: timeSignature.beats, noteValue: timeSignature.noteValue)
        return copy
    }
}

extension MetronomeSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case bpm
        case timeSignature
        case subdivision
        case displayMode
        case accentFirstBeat
        case clickSound
        case volume
        case hapticsEnabled
        case flashEnabled
        case keepScreenAwake
        case mixWithOtherAudio
        case countInBars
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = MetronomeSettings.default
        bpm = try container.decodeIfPresent(Double.self, forKey: .bpm) ?? fallback.bpm
        timeSignature = try container.decodeIfPresent(TimeSignature.self, forKey: .timeSignature) ?? fallback.timeSignature
        subdivision = try container.decodeIfPresent(Subdivision.self, forKey: .subdivision) ?? fallback.subdivision
        displayMode = try container.decodeIfPresent(DisplayMode.self, forKey: .displayMode) ?? fallback.displayMode
        accentFirstBeat = try container.decodeIfPresent(Bool.self, forKey: .accentFirstBeat) ?? fallback.accentFirstBeat
        clickSound = try container.decodeIfPresent(ClickSound.self, forKey: .clickSound) ?? fallback.clickSound
        volume = try container.decodeIfPresent(Double.self, forKey: .volume) ?? fallback.volume
        hapticsEnabled = try container.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? fallback.hapticsEnabled
        flashEnabled = try container.decodeIfPresent(Bool.self, forKey: .flashEnabled) ?? fallback.flashEnabled
        keepScreenAwake = try container.decodeIfPresent(Bool.self, forKey: .keepScreenAwake) ?? fallback.keepScreenAwake
        mixWithOtherAudio = try container.decodeIfPresent(Bool.self, forKey: .mixWithOtherAudio) ?? fallback.mixWithOtherAudio
        countInBars = try container.decodeIfPresent(Int.self, forKey: .countInBars) ?? fallback.countInBars
    }
}

/// Small wrapper around `UserDefaults` so the engine never touches JSON directly.
struct SettingsStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "tempo.settings.v1") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> MetronomeSettings {
        guard
            let data = defaults.data(forKey: key),
            let settings = try? JSONDecoder().decode(MetronomeSettings.self, from: data)
        else {
            return .default
        }
        return settings.validated()
    }

    func save(_ settings: MetronomeSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
