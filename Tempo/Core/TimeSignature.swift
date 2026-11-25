//
//  TimeSignature.swift
//  Tempo
//

import Foundation

/// A musical time signature such as 4/4 or 6/8.
///
/// Values are always valid: the initializer clamps unsupported input, which
/// keeps engine code free of defensive checks.
struct TimeSignature: Hashable, Identifiable, Sendable {
    static let allowedNoteValues = [2, 4, 8, 16]
    static let validBeats = 1...16

    let beats: Int
    let noteValue: Int

    init(beats: Int, noteValue: Int) {
        self.beats = min(max(beats, TimeSignature.validBeats.lowerBound), TimeSignature.validBeats.upperBound)
        self.noteValue = TimeSignature.allowedNoteValues.contains(noteValue) ? noteValue : 4
    }

    var id: String { displayName }

    var displayName: String { "\(beats)/\(noteValue)" }

    /// 6/8, 9/8 and 12/8 are compound meters: they group into dotted beats,
    /// so the first note of each group is accented instead of only the first
    /// note of the bar.
    var isCompound: Bool {
        noteValue == 8 && beats >= 6 && beats % 3 == 0
    }

    /// Beat indices that receive an accent when accents are enabled.
    var accentedBeats: Set<Int> {
        if isCompound {
            return Set(stride(from: 0, to: beats, by: 3))
        }
        return [0]
    }

    /// How the bar is grouped, used for the caption under the beat dots.
    var grouping: [Int] {
        if isCompound {
            return Array(repeating: 3, count: beats / 3)
        }
        return [beats]
    }

    static let presets: [TimeSignature] = [
        TimeSignature(beats: 2, noteValue: 4),
        TimeSignature(beats: 3, noteValue: 4),
        TimeSignature(beats: 4, noteValue: 4),
        TimeSignature(beats: 5, noteValue: 4),
        TimeSignature(beats: 6, noteValue: 8),
        TimeSignature(beats: 7, noteValue: 8),
        TimeSignature(beats: 9, noteValue: 8),
        TimeSignature(beats: 12, noteValue: 8),
    ]

    static let fourFour = TimeSignature(beats: 4, noteValue: 4)
}

extension TimeSignature: Codable {
    private enum CodingKeys: String, CodingKey {
        case beats
        case noteValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let beats = try container.decodeIfPresent(Int.self, forKey: .beats) ?? 4
        let noteValue = try container.decodeIfPresent(Int.self, forKey: .noteValue) ?? 4
        self.init(beats: beats, noteValue: noteValue)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(beats, forKey: .beats)
        try container.encode(noteValue, forKey: .noteValue)
    }
}
