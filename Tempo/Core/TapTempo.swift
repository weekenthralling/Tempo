//
//  TapTempo.swift
//  Tempo
//

import Foundation

/// Turns a series of user taps into a BPM value.
///
/// Taps are averaged with a trimmed mean so a single sloppy tap does not throw
/// the tempo off, and the whole history is discarded after a pause so the next
/// tap starts a new measurement.
struct TapTempo {
    private(set) var timestamps: [TimeInterval] = []

    let resetInterval: TimeInterval
    let maxIntervals: Int

    init(resetInterval: TimeInterval = 2.0, maxIntervals: Int = 6) {
        self.resetInterval = resetInterval
        self.maxIntervals = maxIntervals
    }

    var tapCount: Int { timestamps.count }

    /// Registers a tap and returns an updated BPM once two or more taps exist.
    @discardableResult
    mutating func register(at timestamp: TimeInterval) -> Double? {
        if let last = timestamps.last, timestamp - last > resetInterval {
            timestamps.removeAll()
        }
        // Ignore impossible double taps (debounce) so a sticky button cannot
        // push the tempo to 300 BPM.
        if let last = timestamps.last, timestamp - last < 0.08 {
            return nil
        }

        timestamps.append(timestamp)
        if timestamps.count > maxIntervals + 1 {
            timestamps.removeFirst(timestamps.count - (maxIntervals + 1))
        }

        guard timestamps.count >= 2 else { return nil }
        let intervals = zip(timestamps.dropFirst(), timestamps).map { $0 - $1 }
        let sorted = intervals.sorted()
        let usable = sorted.count >= 4 ? Array(sorted.dropFirst().dropLast()) : sorted
        let average = usable.reduce(0, +) / Double(usable.count)
        guard average > 0 else { return nil }
        return TempoMath.clampBPM(60.0 / average)
    }

    mutating func reset() {
        timestamps.removeAll()
    }
}
