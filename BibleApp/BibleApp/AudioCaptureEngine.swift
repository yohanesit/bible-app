//  AudioCaptureEngine.swift
//  BibleApp
//
//  iOS-only. Wraps AVAudioEngine to deliver two concurrent streams:
//    • rmsStream  — (timestamp, rms) pairs at ~32ms intervals
//    • pcmStream  — raw AVAudioPCMBuffer frames for prosody and anchor matching
//
//  The engine runs at 16 kHz mono Float32 — the standard for speech processing.
//  Callers (SyncEngineCoordinator) consume the AsyncStreams and may drop frames
//  under load; the engine never blocks on consumer back-pressure.

import AVFoundation

@MainActor
final class AudioCaptureEngine {

    // MARK: - Streams

    private(set) var rmsStream: AsyncStream<(timestamp: Double, rms: Float)>!
    private(set) var pcmStream: AsyncStream<AVAudioPCMBuffer>!

    private var rmsContinuation: AsyncStream<(timestamp: Double, rms: Float)>.Continuation?
    private var pcmContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?

    // MARK: - AVFoundation objects

    private let engine = AVAudioEngine()
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    // MARK: - State

    private(set) var isRunning = false

    // MARK: - Lifecycle

    init() {
        rmsStream = AsyncStream { [weak self] continuation in
            self?.rmsContinuation = continuation
        }
        pcmStream = AsyncStream { [weak self] continuation in
            self?.pcmContinuation = continuation
        }
    }

    /// Request microphone permission then start the engine.
    /// Throws if permission is denied or the engine fails to start.
    func start() async throws {
        guard !isRunning else { return }

        // Permission check
        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard granted else { throw CaptureError.microphonePermissionDenied }

        try configureSession()
        try installTap()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }

    // MARK: - Private setup

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .record,
            mode: .measurement,             // disables AGC for consistent RMS readings
            options: [.mixWithOthers]       // allows background audio to continue
        )
        try session.setActive(true)
    }

    private func installTap() throws {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Converter from device's native format → 16 kHz mono Float32
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw CaptureError.formatConversionUnsupported
        }

        // 512 samples at 16 kHz ≈ 32 ms per callback — balances latency vs CPU
        let bufferSize: AVAudioFrameCount = 512

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) {
            [weak self] inputBuffer, time in
            guard let self else { return }

            // Convert to target format
            let frameCapacity = AVAudioFrameCount(
                Double(inputBuffer.frameLength) * self.targetFormat.sampleRate / inputFormat.sampleRate
            ) + 1

            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: self.targetFormat,
                frameCapacity: frameCapacity
            ) else { return }

            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return inputBuffer
            }
            guard status != .error, error == nil else { return }

            // Compute RMS energy
            let rms = self.computeRMS(buffer: convertedBuffer)
            let timestamp = time.hostTime.asSeconds

            // Yield to both streams — non-blocking (drop if consumer is slow)
            self.rmsContinuation?.yield((timestamp: timestamp, rms: rms))
            self.pcmContinuation?.yield(convertedBuffer)
        }
    }

    private func computeRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }

        var sumOfSquares: Float = 0
        for i in 0..<frameCount {
            let sample = channelData[i]
            sumOfSquares += sample * sample
        }
        return sqrt(sumOfSquares / Float(frameCount))
    }

    // MARK: - Errors

    enum CaptureError: Error, LocalizedError {
        case microphonePermissionDenied
        case formatConversionUnsupported

        var errorDescription: String? {
            switch self {
            case .microphonePermissionDenied:   return "Microphone permission denied."
            case .formatConversionUnsupported:  return "Audio format conversion unsupported on this device."
            }
        }
    }
}

// MARK: - Time helpers

private extension UInt64 {
    var asSeconds: Double {
        var info = mach_timebase_info()
        mach_timebase_info(&info)
        let nanos = self * UInt64(info.numer) / UInt64(info.denom)
        return Double(nanos) / 1_000_000_000
    }
}
