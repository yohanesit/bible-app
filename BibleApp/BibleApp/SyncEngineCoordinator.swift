//  SyncEngineCoordinator.swift
//  BibleApp
//
//  iOS-only @Observable that owns all sync modules and exposes state to SwiftUI.
//  Drives the full Phase 1 engine: signals 1 (pause) + 3 (time window).
//  Anchor matching (signal 4) is wired in Phase 2; prosody (signal 2) in Phase 2.

import AVFoundation
import Observation
import SwiftUI

@Observable
@MainActor
final class SyncEngineCoordinator {

    // MARK: - Public state (observed by SwiftUI)

    var syncState: SyncState = .idle
    var currentReadingIndex: Int = 0
    var currentVerseIndex: Int = 0
    var currentLineIndex: Int = 0
    var showStalledIndicator: Bool = false
    var showDesyncIndicator: Bool = false
    var micPermissionDenied: Bool = false

    // MARK: - Active readings

    private(set) var readings: [MassReading] = []

    var currentVerse: VerseSegment? {
        readings[safe: currentReadingIndex]?.verses[safe: currentVerseIndex]
    }

    var currentLine: LineSegment? {
        currentVerse?.lines[safe: currentLineIndex]
    }

    var totalVerses: Int {
        readings[safe: currentReadingIndex]?.verses.count ?? 0
    }

    // MARK: - Private modules

    private let audioEngine = AudioCaptureEngine()
    private let pauseDetector = PauseDetector()

    // MARK: - Timing state

    private var verseStartTime: Date = .now
    private var latestPauseScore: Double = 0
    private var stallTask: Task<Void, Never>?
    private var anchorWindowTask: Task<Void, Never>?
    private var rmsTask: Task<Void, Never>?

    // MARK: - Configurable

    var wordsPerMinute: Double = AnchorExtractor.defaultWPM

    // MARK: - Mass lifecycle

    func beginMass(readings: [MassReading]) async {
        guard syncState == .idle || syncState == .preMass else { return }
        self.readings = readings
        currentReadingIndex = 0
        currentVerseIndex = 0

        do {
            try await audioEngine.start()
            micPermissionDenied = false
        } catch AudioCaptureEngine.CaptureError.microphonePermissionDenied {
            micPermissionDenied = true
            // Graceful degradation: manual mode only, no auto-sync
            return
        } catch {
            micPermissionDenied = true
            return
        }

        currentLineIndex = 0
        apply(.massStarted)
        verseStartTime = .now
        startRMSConsumer()
        startStallTimer()
    }

    func enterPreMass(readings: [MassReading]) {
        self.readings = readings
        currentReadingIndex = 0
        currentVerseIndex = 0
        apply(.preMassEntered)
    }

    func endMass() {
        stallTask?.cancel()
        anchorWindowTask?.cancel()
        rmsTask?.cancel()
        audioEngine.stop()
        apply(.massStopped)
        readings = []
    }

    // MARK: - Manual override

    func manualOverride(readingIndex: Int, verseIndex: Int, lineIndex: Int = 0) {
        apply(.manualVerseTap)
        currentReadingIndex = readingIndex
        currentVerseIndex = verseIndex
        currentLineIndex = lineIndex
        verseStartTime = .now
        latestPauseScore = 0
        stallTask?.cancel()
        startStallTimer()
        apply(.massStarted)
    }

    // MARK: - RMS consumer

    private func startRMSConsumer() {
        rmsTask = Task { [weak self] in
            guard let self else { return }
            for await (timestamp, rms) in self.audioEngine.rmsStream {
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    self.pauseDetector.process(rms: rms, at: timestamp)
                }
            }
        }

        pauseDetector.onPause = { [weak self] event in
            guard let self else { return }
            Task { @MainActor in
                self.handlePause(event)
            }
        }
    }

    // MARK: - Pause handling (Signal 1 + Signal 3 combined)

    private func handlePause(_ event: PauseEvent) {
        guard syncState == .listening || syncState == .stalled else { return }

        let elapsed = Date.now.timeIntervalSince(verseStartTime)
        let estimated = currentLine?.estimatedDurationSecs ?? currentVerse?.estimatedDurationSecs ?? 0

        let (snapshot, composite) = ConfidenceAggregator.evaluate(
            pauseScore: event.classification.score,
            prosodyScore: 0,          // Phase 2: ProsodyAnalyzer
            elapsed: elapsed,
            estimated: estimated,
            anchorMatchScore: 0       // Phase 2: AnchorMatcher
        )

        latestPauseScore = snapshot.pauseScore

        if composite >= SyncStateMachine.advanceThreshold {
            apply(.confidenceCrossedThreshold(composite))
            // Phase 1: no anchor matching — simulate instant confirm at neutral confidence
            // so the engine advances on strong pause + time signal alone.
            // This is removed in Phase 2 when AnchorMatcher takes over.
            openAnchorWindowPhase1(composite: composite)
        }
    }

    // Phase 1 stub: advances without waiting for anchor match confirmation.
    // Replace with real AnchorMatcher in Phase 2.
    private func openAnchorWindowPhase1(composite: Double) {
        anchorWindowTask?.cancel()
        anchorWindowTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // 3-second anchor window — in Phase 1 we auto-confirm after a short delay
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            // Auto-confirm with the composite score as the anchor score
            self.apply(.anchorMatchConfirmed(composite))
            self.performAdvance()
        }
    }

    // MARK: - Advance

    private func performAdvance() {
        let reading = readings[safe: currentReadingIndex]
        let verse = reading?.verses[safe: currentVerseIndex]
        let lineCount = verse?.lines.count ?? 1
        let verseCount = reading?.verses.count ?? 0
        let isLastLineInVerse = currentLineIndex >= lineCount - 1
        let isLastVerseInReading = currentVerseIndex >= verseCount - 1
        let isLastReading = currentReadingIndex >= readings.count - 1

        if isLastLineInVerse && isLastVerseInReading && isLastReading {
            apply(.lastVerseAdvanced)
            return
        }

        if isLastLineInVerse {
            if isLastVerseInReading {
                currentReadingIndex += 1
                currentVerseIndex = 0
            } else {
                currentVerseIndex += 1
            }
            currentLineIndex = 0
        } else {
            currentLineIndex += 1
        }

        verseStartTime = .now
        latestPauseScore = 0
        apply(.advanceAnimationCompleted)
        startStallTimer()
    }

    // MARK: - Stall timer

    private func startStallTimer() {
        stallTask?.cancel()
        let estimated = currentLine?.estimatedDurationSecs ?? currentVerse?.estimatedDurationSecs ?? 15
        let stallDelay = estimated * 2.5

        stallTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(stallDelay))
            guard !Task.isCancelled else { return }
            self.apply(.stallTimerFired)
        }
    }

    // MARK: - State machine dispatch

    private func apply(_ input: SyncInput) {
        let (next, effects) = SyncStateMachine.reduce(state: syncState, input: input)
        syncState = next
        execute(effects)
    }

    private func execute(_ effects: [SyncEffect]) {
        for effect in effects {
            switch effect {
            case .startStallTimer:       startStallTimer()
            case .cancelStallTimer:      stallTask?.cancel()
            case .closeAnchorWindow:     anchorWindowTask?.cancel()
            case .showStalledIndicator:  showStalledIndicator = true
            case .hideStalledIndicator:  showStalledIndicator = false
            case .showDesyncIndicator:   showDesyncIndicator = true
            case .hideDesyncIndicator:   showDesyncIndicator = false
            case .stopMicrophone:
                rmsTask?.cancel()
                audioEngine.stop()
            case .fireHaptic:
                break   // Phase 2: HapticController
            case .advanceToNextVerse, .openAnchorWindow,
                 .applyDriftCorrection, .offerResyncAfterBackground,
                 .startMicrophone:
                break   // handled inline above or in Phase 2
            }
        }
    }
}

// MARK: - Safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
