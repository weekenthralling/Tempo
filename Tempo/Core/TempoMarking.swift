//
//  TempoMarking.swift
//  Tempo
//

import Foundation

/// The traditional Italian tempo names shown above the BPM number.
struct TempoMarking: Equatable, Sendable {
    let italian: String
    /// Localization key for the one-line description ("快板", "Walking pace"…).
    let descriptorKey: String
    let lowerBound: Double
    /// Exclusive upper bound; the last marking uses `.infinity`.
    let upperBound: Double

    var range: Range<Double> { lowerBound..<upperBound }

    static let all: [TempoMarking] = [
        TempoMarking(italian: "Grave", descriptorKey: "tempo.grave", lowerBound: 30, upperBound: 40),
        TempoMarking(italian: "Largo", descriptorKey: "tempo.largo", lowerBound: 40, upperBound: 50),
        TempoMarking(italian: "Larghetto", descriptorKey: "tempo.larghetto", lowerBound: 50, upperBound: 60),
        TempoMarking(italian: "Adagio", descriptorKey: "tempo.adagio", lowerBound: 60, upperBound: 66),
        TempoMarking(italian: "Andante", descriptorKey: "tempo.andante", lowerBound: 66, upperBound: 76),
        TempoMarking(italian: "Moderato", descriptorKey: "tempo.moderato", lowerBound: 76, upperBound: 108),
        TempoMarking(italian: "Allegretto", descriptorKey: "tempo.allegretto", lowerBound: 108, upperBound: 120),
        TempoMarking(italian: "Allegro", descriptorKey: "tempo.allegro", lowerBound: 120, upperBound: 156),
        TempoMarking(italian: "Vivace", descriptorKey: "tempo.vivace", lowerBound: 156, upperBound: 176),
        TempoMarking(italian: "Presto", descriptorKey: "tempo.presto", lowerBound: 176, upperBound: 200),
        TempoMarking(italian: "Prestissimo", descriptorKey: "tempo.prestissimo", lowerBound: 200, upperBound: .infinity),
    ]

    static func marking(for bpm: Double) -> TempoMarking {
        all.first { bpm < $0.upperBound } ?? all[all.count - 1]
    }
}
