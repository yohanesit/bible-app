//  PauseDetector.swift
//  BibleApp
//
//  Pure Signal 1 — classifies silence gaps from the RMS stream.
//  No iOS/Apple imports except Foundation (for TimeInterval). KMP extraction target.
//
//  KMP note: Replace TimeInterval with Double; keep all logic identical.

import Foundation

/// Stateful detector that consumes RMS energy values and emits PauseEvents.
///
/// Call `process(rms:at:)` on every RMS sample from AudioCaptureEngine.
/// When a silence window ends, the detector calls `onPause` with the classified event.
final class PauseDetector {

    // MARK: - Configuration

    /// Linear RMS below this threshold is considered silence.
    /// -40 dBFS ≈ 0.01 linear for a 0–1 float signal.
    var silenceThreshold: Float = 0.01

    /// Minimum sustained silence before a pause is registered (debounces breath pops).
    var minimumPauseDuration: TimeInterval = 0.15

    // MARK: - State

    private var silenceStartTime: Double? = nil
    private var inSilence = false

    // MARK: - Output

    var onPause: ((PauseEvent) -> Void)?

    // MARK: - Processing

    /// Feed one RMS sample. `timestamp` is seconds since audio session start.
    func process(rms: Float, at timestamp: Double) {
        if rms < silenceThreshold {
            if !inSilence {
                inSilence = true
                silenceStartTime = timestamp
            }
        } else {
            if inSilence, let start = silenceStartTime {
                let duration = timestamp - start
                if duration >= minimumPauseDuration {
                    onPause?(PauseEvent(duration: duration))
                }
            }
            inSilence = false
            silenceStartTime = nil
        }
    }

    /// Returns the current pause duration if currently in silence, else nil.
    func currentSilenceDuration(at timestamp: Double) -> TimeInterval? {
        guard inSilence, let start = silenceStartTime else { return nil }
        return timestamp - start
    }

    func reset() {
        silenceStartTime = nil
        inSilence = false
    }
}
