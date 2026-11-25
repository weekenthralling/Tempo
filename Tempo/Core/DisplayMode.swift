//
//  DisplayMode.swift
//  Tempo
//

import Foundation

/// How the tempo area presents the beat.
enum DisplayMode: String, CaseIterable, Identifiable, Codable, Sendable {
    /// A large BPM number — the quickest read on a music stand.
    case digits
    /// A mechanical metronome whose rod swings once per beat.
    case pendulum

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .digits: return "Digit display"
        case .pendulum: return "Pendulum display"
        }
    }

    var symbolName: String {
        switch self {
        case .digits: return "number"
        case .pendulum: return "metronome.fill"
        }
    }
}
