//
//  ClickSound.swift
//  Tempo
//

import Foundation

/// Which synthesized click timbre the metronome uses.
enum ClickSound: String, CaseIterable, Identifiable, Sendable, Codable {
    case classic
    case woodblock
    case beep
    case digital

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .classic: return "sound.classic"
        case .woodblock: return "sound.woodblock"
        case .beep: return "sound.beep"
        case .digital: return "sound.digital"
        }
    }

    var symbolName: String {
        switch self {
        case .classic: return "metronome.fill"
        case .woodblock: return "tuningfork"
        case .beep: return "waveform"
        case .digital: return "clock.badge.checkmark"
        }
    }
}

/// The role a click plays inside a beat.
enum ClickKind: String, CaseIterable, Hashable, Sendable {
    /// First beat of the bar (or of each compound group).
    case accent
    /// A regular beat.
    case beat
    /// A subdivision click, quieter and shorter than a beat.
    case subdivision
}
