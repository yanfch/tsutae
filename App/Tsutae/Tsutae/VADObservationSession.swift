import Foundation
import OSLog
import TsutaeCore

actor VADObservationSession {
    private let logger = Logger(subsystem: "dev.yanfch.Tsutae", category: "VADObserve")
    private let sessionID: UUID
    private let config: Config
    private let windowBytes: Int
    private let windowMs: Double
    private let pauseDurationMs: Double
    private let startedAt = CFAbsoluteTimeGetCurrent()

    private var pendingSamples = Data()
    private var observedAudioMs: Double = 0
    private var processedAudioMs: Double = 0
    private var windowCount = 0
    private var speechWindows = 0
    private var silenceWindows = 0
    private var maxProbability: Double = 0
    private var firstSpeechMs: Double?
    private var lastSpeechMs: Double?
    private var longestSilenceMs: Double = 0
    private var isInSpeech = false
    private var pauseLoggedForCurrentSilence = false
    private var detectTotalMs: Double = 0
    private var detectMaxMs: Double = 0
    private var errors = 0
    private var lastError: String?
    private var isFinished = false

    init(sessionID: UUID = UUID(), config: Config) {
        self.sessionID = sessionID
        self.config = config
        self.windowBytes = 4_096 * MemoryLayout<Int16>.size
        self.windowMs = 4_096.0 / 16_000.0 * 1_000.0
        self.pauseDurationMs = Double(config.vad.pauseDurationMs)
        EngineManager.shared.vad(id: config.vad.engine)?.reset()

        let message = "VAD observe started. session=\(sessionID.uuidString) engine=\(config.vad.engine) sensitivity=\(String(format: "%.2f", config.vad.sensitivity)) pause_ms=\(config.vad.pauseDurationMs)"
        logger.info("\(message, privacy: .public)")
        PerformanceLog.record(category: "VADObserve", message: message)
    }

    func observe(_ frame: AudioFrame) async {
        guard isFinished == false else { return }
        observedAudioMs += frameDurationMs(frame)
        pendingSamples.append(frame.samples)

        while pendingSamples.count >= windowBytes {
            let window = pendingSamples.prefix(windowBytes)
            pendingSamples.removeFirst(windowBytes)
            await processWindow(Data(window), frameIndex: frame.frameIndex)
        }
    }

    func finish(reason: String) {
        guard isFinished == false else { return }
        isFinished = true

        let detectAverageMs = windowCount > 0 ? detectTotalMs / Double(windowCount) : 0
        let message = [
            "VAD observe summary.",
            "session=\(sessionID.uuidString)",
            "reason=\(reason)",
            "engine=\(config.vad.engine)",
            "windows=\(windowCount)",
            "audio_ms=\(formatMs(observedAudioMs))",
            "processed_ms=\(formatMs(processedAudioMs))",
            "speech_windows=\(speechWindows)",
            "silence_windows=\(silenceWindows)",
            "max_probability=\(formatProbability(maxProbability))",
            "first_speech_ms=\(formatOptionalMs(firstSpeechMs))",
            "last_speech_ms=\(formatOptionalMs(lastSpeechMs))",
            "longest_silence_ms=\(formatMs(longestSilenceMs))",
            "detect_avg_ms=\(formatMs(detectAverageMs))",
            "detect_max_ms=\(formatMs(detectMaxMs))",
            "errors=\(errors)",
            "last_error=\(lastError ?? "")",
            "elapsed_ms=\(formatMs(elapsedMs(since: startedAt)))"
        ].joined(separator: " ")
        logger.info("\(message, privacy: .public)")
        PerformanceLog.record(category: "VADObserve", message: message)
    }

    private func processWindow(_ samples: Data, frameIndex: Int) async {
        let windowStartMs = processedAudioMs
        let windowEndMs = processedAudioMs + windowMs
        processedAudioMs = windowEndMs
        windowCount += 1

        do {
            let startedAt = CFAbsoluteTimeGetCurrent()
            let result = try await ConfiguredVADDetector.detect(
                AudioFrame(samples: samples, frameIndex: windowCount),
                config: config
            )
            let detectElapsedMs = elapsedMs(since: startedAt)
            detectTotalMs += detectElapsedMs
            detectMaxMs = max(detectMaxMs, detectElapsedMs)
            maxProbability = max(maxProbability, result.probability)

            if result.isSpeech {
                recordSpeechWindow(
                    windowStartMs: windowStartMs,
                    windowEndMs: windowEndMs,
                    frameIndex: frameIndex,
                    probability: result.probability
                )
            } else {
                recordSilenceWindow(
                    windowStartMs: windowStartMs,
                    windowEndMs: windowEndMs,
                    frameIndex: frameIndex,
                    probability: result.probability
                )
            }
        } catch {
            errors += 1
            lastError = error.localizedDescription
            if errors <= 3 {
                let message = "VAD observe failed. session=\(sessionID.uuidString) frame=\(frameIndex) window=\(windowCount) error=\(error.localizedDescription)"
                logger.error("\(message, privacy: .public)")
                PerformanceLog.record(category: "VADObserve", message: message)
            }
        }
    }

    private func recordSpeechWindow(
        windowStartMs: Double,
        windowEndMs: Double,
        frameIndex: Int,
        probability: Double
    ) {
        speechWindows += 1
        firstSpeechMs = firstSpeechMs ?? windowStartMs
        lastSpeechMs = windowEndMs
        pauseLoggedForCurrentSilence = false

        guard isInSpeech == false else { return }
        isInSpeech = true
        let message = "VAD observe speech started. session=\(sessionID.uuidString) frame=\(frameIndex) window=\(windowCount) audio_ms=\(formatMs(windowStartMs)) probability=\(formatProbability(probability))"
        logger.info("\(message, privacy: .public)")
        PerformanceLog.record(category: "VADObserve", message: message)
    }

    private func recordSilenceWindow(
        windowStartMs: Double,
        windowEndMs: Double,
        frameIndex: Int,
        probability: Double
    ) {
        silenceWindows += 1
        if isInSpeech {
            isInSpeech = false
        }

        guard let lastSpeechMs else { return }
        let silenceMs = max(0, windowEndMs - lastSpeechMs)
        longestSilenceMs = max(longestSilenceMs, silenceMs)
        guard silenceMs >= pauseDurationMs, pauseLoggedForCurrentSilence == false else { return }
        pauseLoggedForCurrentSilence = true

        let message = "VAD observe pause reached. session=\(sessionID.uuidString) frame=\(frameIndex) window=\(windowCount) audio_ms=\(formatMs(windowEndMs)) silence_ms=\(formatMs(silenceMs)) probability=\(formatProbability(probability))"
        logger.info("\(message, privacy: .public)")
        PerformanceLog.record(category: "VADObserve", message: message)
    }

    private func frameDurationMs(_ frame: AudioFrame) -> Double {
        Double(frame.samples.count) / Double(MemoryLayout<Int16>.size) / 16_000.0 * 1_000.0
    }

    private func elapsedMs(since startedAt: CFAbsoluteTime) -> Double {
        (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000.0
    }

    private func formatMs(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func formatOptionalMs(_ value: Double?) -> String {
        guard let value else { return "none" }
        return formatMs(value)
    }

    private func formatProbability(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}
