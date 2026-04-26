//  ConfidenceAggregator.swift
//  BibleApp
//
//  Pure Signal 3 — time-window guard + composite confidence calculation.
//  No iOS/Apple imports except Foundation. KMP extraction target.
//
//  The time-window guard is the single most impactful false-positive eliminator:
//  it suppresses ALL signals when less than 60% of the expected verse duration
//  has elapsed, preventing mid-verse advances from short pauses early in a verse.

import Foundation

enum ConfidenceAggregator {

    // MARK: - Time-window score (Signal 3)

    /// Returns a 0.0–1.0 score based on how far into the expected verse duration we are.
    ///
    ///  ratio < 0.60 → 0.0   (hard suppress — too early to be at a boundary)
    ///  ratio 0.60–0.80 → ramps 0.0→0.5
    ///  ratio 0.80–1.20 → ramps 0.5→1.0 (peak confidence window)
    ///  ratio 1.20–1.50 → stays 1.0 (lector still within normal range)
    ///  ratio ≥ 1.50    → 0.7  (slow reader; stay alert, slight decay)
    static func timeWindowScore(elapsed: Double, estimated: Double) -> Double {
        guard estimated > 0 else { return 0 }
        let ratio = elapsed / estimated
        switch ratio {
        case ..<0.60:
            return 0.0
        case 0.60..<0.80:
            return lerp(from: 0.0, to: 0.5, t: (ratio - 0.60) / 0.20)
        case 0.80..<1.20:
            return lerp(from: 0.5, to: 1.0, t: (ratio - 0.80) / 0.40)
        case 1.20..<1.50:
            return 1.0
        default:
            return 0.7
        }
    }

    // MARK: - Composite score

    /// Combine all four signal scores into a single confidence value.
    static func composite(_ snapshot: ConfidenceSnapshot) -> Double {
        snapshot.composite
    }

    /// Convenience: build a snapshot and return composite in one call.
    static func evaluate(
        pauseScore: Double,
        prosodyScore: Double,
        elapsed: Double,
        estimated: Double,
        anchorMatchScore: Double = 0
    ) -> (snapshot: ConfidenceSnapshot, composite: Double) {
        var snapshot = ConfidenceSnapshot()
        snapshot.pauseScore       = pauseScore
        snapshot.prosodyScore     = prosodyScore
        snapshot.timeWindowScore  = timeWindowScore(elapsed: elapsed, estimated: estimated)
        snapshot.anchorMatchScore = anchorMatchScore
        return (snapshot, snapshot.composite)
    }

    // MARK: - Stall detection

    /// Returns true when the lector has spent more than `stallMultiplier` times
    /// the estimated duration without an advance — engine should enter .stalled.
    static func isStalled(elapsed: Double, estimated: Double, stallMultiplier: Double = 2.5) -> Bool {
        guard estimated > 0 else { return false }
        return elapsed > estimated * stallMultiplier
    }

    // MARK: - Private

    private static func lerp(from a: Double, to b: Double, t: Double) -> Double {
        a + (b - a) * min(max(t, 0), 1)
    }
}
