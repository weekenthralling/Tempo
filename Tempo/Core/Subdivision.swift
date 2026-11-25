//
//  Subdivision.swift
//  Tempo
//

import Foundation

/// How many clicks are played per beat.
enum Subdivision: Int, CaseIterable, Identifiable, Sendable, Codable {
    case none = 1
    case eighth = 2
    case triplet = 3
    case sixteenth = 4

    var id: Int { rawValue }

    var stepsPerBeat: Int { rawValue }

    var titleKey: String {
        switch self {
        case .none: return "subdivision.none"
        case .eighth: return "subdivision.eighth"
        case .triplet: return "subdivision.triplet"
        case .sixteenth: return "subdivision.sixteenth"
        }
    }

    /// A compact label for the control button.
    var badge: String {
        switch self {
        case .none: return "1"
        case .eighth: return "2"
        case .triplet: return "3"
        case .sixteenth: return "4"
        }
    }

    var symbolName: String {
        switch self {
        case .none: return "1.circle.fill"
        case .eighth: return "2.circle.fill"
        case .triplet: return "3.circle.fill"
        case .sixteenth: return "4.circle.fill"
        }
    }
}
