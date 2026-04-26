//  SyncStateMachine.swift
//  BibleApp
//
//  Pure reducer — no iOS/Apple imports. KMP extraction target.
//  All state transitions, guards, and timeout thresholds live here.
//
//  KMP note: Replace enum with sealed class; switch with when.

import Foundation

// MARK: - States

enum SyncState: Equatable {
    case idle
    case preMass
    case listening
    case candidateBoundary    // confidence crossed threshold; anchor window open
    case advancing            // animating to next verse; returns to listening immediately
    case stalled              // reading longer than 2.5× expected; no forced advance
    case desynced             // background check found drift; may auto-correct
    case ended                // last verse done; mic released
    case manualOverride       // user long-pressed; engine resumes from chosen verse
}

// MARK: - Input events

enum SyncInput {
    case massStarted
    case massStopped
    case preMassEntered
    case confidenceCrossedThreshold(Double)
    case anchorMatchConfirmed(Double)      // score from AnchorMatcher
    case anchorWindowTimedOut
    case advanceAnimationCompleted
    case stallTimerFired
    case newPauseDetected                  // resets stall timer in .stalled
    case driftDetected(correctionConfidence: Double)
    case driftCorrectionApplied
    case manualVerseTap                    // user long-pressed a verse
    case lastVerseAdvanced
    case appBackgrounded
    case appForegrounded
}

// MARK: - Output effects

enum SyncEffect {
    case startMicrophone
    case stopMicrophone
    case openAnchorWindow               // tell AnchorMatcher to start listening
    case closeAnchorWindow
    case advanceToNextVerse
    case startStallTimer
    case cancelStallTimer
    case applyDriftCorrection
    case fireHaptic(HapticKind)
    case showStalledIndicator
    case hideStalledIndicator
    case showDesyncIndicator
    case hideDesyncIndicator
    case offerResyncAfterBackground

    enum HapticKind {
        case verseAdvance
        case readingChange
        case majorTransition
        case driftCorrection
        case manualOverride
    }
}

// MARK: - Machine

/// Pure reducer. Given current state + input → (next state, [effects]).
/// The coordinator owns the state and executes effects.
enum SyncStateMachine {

    // Confidence threshold to enter candidateBoundary.
    static let advanceThreshold: Double = 0.65

    // Anchor match score required to confirm advance.
    static let anchorConfirmThreshold: Double = 0.75

    // Drift correction auto-applies when background confidence exceeds this.
    static let driftAutoCorrectThreshold: Double = 0.85

    static func reduce(
        state: SyncState,
        input: SyncInput
    ) -> (next: SyncState, effects: [SyncEffect]) {

        switch (state, input) {

        // ── Startup ─────────────────────────────────────────────────────────

        case (_, .preMassEntered):
            return (.preMass, [])

        case (.idle, .massStarted), (.preMass, .massStarted):
            return (.listening, [.startMicrophone])

        case (_, .massStopped):
            return (.idle, [.stopMicrophone, .cancelStallTimer,
                            .closeAnchorWindow, .hideStalledIndicator, .hideDesyncIndicator])

        // ── Listening → CandidateBoundary ───────────────────────────────────

        case (.listening, .confidenceCrossedThreshold(let score)) where score >= advanceThreshold:
            return (.candidateBoundary, [.openAnchorWindow])

        case (.stalled, .confidenceCrossedThreshold(let score)) where score >= advanceThreshold:
            return (.candidateBoundary, [.cancelStallTimer, .hideStalledIndicator, .openAnchorWindow])

        // ── CandidateBoundary resolution ─────────────────────────────────────

        case (.candidateBoundary, .anchorMatchConfirmed(let score)) where score >= anchorConfirmThreshold:
            return (.advancing, [.closeAnchorWindow, .advanceToNextVerse,
                                 .fireHaptic(.verseAdvance), .cancelStallTimer])

        case (.candidateBoundary, .anchorWindowTimedOut):
            // Anchor not found in time — decay and return to listening
            return (.listening, [.closeAnchorWindow])

        // ── Advancing → Listening ────────────────────────────────────────────

        case (.advancing, .advanceAnimationCompleted):
            return (.listening, [.startStallTimer])

        case (.advancing, .lastVerseAdvanced):
            return (.ended, [.stopMicrophone, .cancelStallTimer])

        // ── Stall detection ──────────────────────────────────────────────────

        case (.listening, .stallTimerFired):
            return (.stalled, [.showStalledIndicator])

        case (.stalled, .newPauseDetected):
            // A new pause resets the stall window — maybe reading resumed
            return (.stalled, [.startStallTimer])

        // ── Desync ──────────────────────────────────────────────────────────

        case (.listening, .driftDetected(let confidence)) where confidence >= driftAutoCorrectThreshold:
            return (.listening, [.applyDriftCorrection, .fireHaptic(.driftCorrection)])

        case (.listening, .driftDetected):
            return (.desynced, [.showDesyncIndicator])

        case (.desynced, .driftCorrectionApplied):
            return (.listening, [.hideDesyncIndicator, .fireHaptic(.driftCorrection)])

        // ── Manual override ──────────────────────────────────────────────────

        case (_, .manualVerseTap):
            return (.manualOverride, [.closeAnchorWindow, .cancelStallTimer,
                                      .hideStalledIndicator, .hideDesyncIndicator,
                                      .fireHaptic(.manualOverride)])

        case (.manualOverride, .massStarted):
            // Tapping "resume" after manual override
            return (.listening, [.startStallTimer])

        // ── Background / foreground ──────────────────────────────────────────

        case (_, .appBackgrounded):
            // Mic stays on (background audio entitlement). No state change needed.
            return (state, [])

        case (_, .appForegrounded):
            if state == .listening || state == .stalled || state == .candidateBoundary {
                return (state, [.offerResyncAfterBackground])
            }
            return (state, [])

        // ── Last verse ───────────────────────────────────────────────────────

        case (.listening, .lastVerseAdvanced):
            return (.ended, [.stopMicrophone, .cancelStallTimer, .fireHaptic(.verseAdvance)])

        // ── Fallthrough: no-op for unhandled combinations ────────────────────

        default:
            return (state, [])
        }
    }
}
