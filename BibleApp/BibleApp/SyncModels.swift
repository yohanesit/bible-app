//  SyncModels.swift
//  BibleApp
//
//  Pure value types for the verse-sync engine.
//  No iOS/Apple imports — KMP extraction target.
//
//  KMP note:
//    AnchorSet   → data class AnchorSet(val phrases: Map<String, List<String>>, val durations: Map<String, Double>)
//    MassSession → data class MassSession(val id: String, val startTime: Long, ...)
//    SyncEvent   → data class SyncEvent(val timestamp: Long, val eventType: String, ...)

import Foundation

// MARK: - AnchorSet

/// Built once at load time from a day's readings. Maps verse IDs to their
/// anchor phrase tokens and estimated reading durations.
struct AnchorSet {
    let phrases: [String: [String]]     // verse id → 3–5 content word tokens
    let durations: [String: Double]     // verse id → estimated seconds to read

    static let empty = AnchorSet(phrases: [:], durations: [:])
}

// MARK: - MassSession

/// Runtime state for an active Mass. Not persisted between launches.
struct MassSession {
    let id: UUID
    let startTime: Date
    var currentReadingIndex: Int
    var currentVerseIndex: Int
    var syncMode: SyncMode
    var events: [SyncEvent]

    enum SyncMode { case auto, manual }

    init(readingIndex: Int = 0, verseIndex: Int = 0) {
        id = UUID()
        startTime = Date()
        currentReadingIndex = readingIndex
        currentVerseIndex = verseIndex
        syncMode = .auto
        events = []
    }
}

// MARK: - SyncEvent

/// Logged on every state transition. Accumulated locally for calibration.
///
/// KMP note: replace `Date` with `Long` (epoch ms) in Kotlin.
struct SyncEvent: Codable {
    let timestamp: Date
    let eventType: EventType
    let verseId: String
    let confidenceAtDecision: Double
    let wasUserCorrected: Bool

    enum EventType: String, Codable {
        case advanced
        case held
        case correctedByUser
        case driftDetected
        case driftCorrected
    }
}

// MARK: - ConfidenceSnapshot

/// Internal to the engine per evaluation cycle. Not persisted.
struct ConfidenceSnapshot {
    var pauseScore: Double       = 0
    var prosodyScore: Double     = 0
    var timeWindowScore: Double  = 0
    var anchorMatchScore: Double = 0

    // Tunable weights — Phase 1: anchor weight neutral (0.0) until AnchorMatcher exists
    static let pauseWeight:  Double = 0.25
    static let prosodyWeight: Double = 0.15
    static let timeWeight:   Double = 0.60
    static let anchorWeight: Double = 0.00   // raised to 0.25 in Phase 2

    var composite: Double {
        pauseScore      * Self.pauseWeight  +
        prosodyScore    * Self.prosodyWeight +
        timeWindowScore * Self.timeWeight   +
        anchorMatchScore * Self.anchorWeight
    }
}

// MARK: - PauseEvent

struct PauseEvent {
    let duration: TimeInterval
    let classification: PauseClass

    enum PauseClass {
        case short    // < 0.5s  — likely breath, low signal weight
        case medium   // 0.5–1.0s — possible verse end
        case long     // > 1.0s  — strong boundary candidate

        var score: Double {
            switch self {
            case .short:  return 0.1
            case .medium: return 0.4
            case .long:   return 0.8
            }
        }
    }

    init(duration: TimeInterval) {
        self.duration = duration
        switch duration {
        case ..<0.5:  classification = .short
        case 0.5..<1.0: classification = .medium
        default:      classification = .long
        }
    }
}
