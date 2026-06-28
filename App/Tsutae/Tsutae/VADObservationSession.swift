import Foundation
import OSLog
import TsutaeCore

struct VADObservationSegmentSummary: Sendable, Equatable {
    let index: Int
    let startMs: Double
    let endMs: Double
    let byteStart: Int
    let byteEnd: Int
    let reason: String

    var byteRange: Range<Int> {
        byteStart..<byteEnd
    }

    var durationMs: Double {
        max(0, endMs - startMs)
    }
}

struct VADObservationSummary: Sendable, Equatable {
    let sessionID: UUID
    let reason: String
    let engine: String
    let audioMs: Double
    let processedMs: Double
    let completedMs: Double
    let speechWindows: Int
    let silenceWindows: Int
    let maxProbability: Double
    let firstSpeechMs: Double?
    let lastSpeechMs: Double?
    let longestSilenceMs: Double
    let detectAverageMs: Double
    let detectMaxMs: Double
    let errors: Int
    let audioBytes: Int
    let pendingBytes: Int
    let segments: [VADObservationSegmentSummary]

    var segmentBytes: Int {
        segments.reduce(0) { $0 + max(0, $1.byteEnd - $1.byteStart) }
    }

    var segmentSavedPercent: Double {
        guard audioBytes > 0 else { return 0 }
        return max(0, (1.0 - Double(segmentBytes) / Double(audioBytes)) * 100.0)
    }

    var segmentByteRanges: [Range<Int>] {
        segments.map(\.byteRange)
    }

    var asASRSampleLogSnapshot: ASRSampleLog.VADSnapshot {
        ASRSampleLog.VADSnapshot(
            engine: engine,
            reason: reason,
            audioMs: audioMs,
            processedMs: processedMs,
            speechWindows: speechWindows,
            silenceWindows: silenceWindows,
            maxProbability: maxProbability,
            firstSpeechMs: firstSpeechMs,
            lastSpeechMs: lastSpeechMs,
            longestSilenceMs: longestSilenceMs,
            segmentBytes: segmentBytes,
            segmentSavedPercent: segmentSavedPercent,
            segments: segments.map {
                ASRSampleLog.VADSegmentSnapshot(
                    index: $0.index,
                    startMs: $0.startMs,
                    endMs: $0.endMs,
                    byteStart: $0.byteStart,
                    byteEnd: $0.byteEnd,
                    reason: $0.reason
                )
            }
        )
    }
}

actor VADObservationSession {
    private let logger = Logger(subsystem: "dev.yanfch.Tsutae", category: "VADObserve")
    private let sessionID: UUID
    private let config: Config
    private let windowBytes: Int
    private let windowMs: Double
    private let pauseDurationMs: Double
    private let segmentPrerollMs: Double = 200
    private let segmentTrailingSilenceMs: Double = 200
    private let segmentMinDurationMs: Double = 600
    private let segmentMaxDurationMs: Double = 25_000
    private let sampleRate: Double = 16_000
    private let bytesPerSample = MemoryLayout<Int16>.size
    private let startedAt = CFAbsoluteTimeGetCurrent()

    private var pendingSamples = Data()
    private var observedBytes = 0
    private var observedAudioMs: Double = 0
    private var processedAudioMs: Double = 0
    private var completedAudioMs: Double = 0
    private var startedWindowCount = 0
    private var completedWindowCount = 0
    private var inFlightWindowCount = 0
    private var ignoredAfterFinishWindows = 0
    private var ignoredAfterFinishFrames = 0
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
    private var pendingFinishReason: String?
    private var summaryLogged = false
    private var cachedSummary: VADObservationSummary?
    private var finishWaiters: [CheckedContinuation<VADObservationSummary?, Never>] = []
    private var segmentCandidates: [SegmentCandidate] = []
    private var segmentStartMs: Double?
    private var segmentHasSpeech = false

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
        guard isFinished == false else {
            ignoredAfterFinishFrames += 1
            return
        }
        observedAudioMs += frameDurationMs(frame)
        observedBytes += frame.samples.count
        pendingSamples.append(frame.samples)

        while pendingSamples.count >= windowBytes {
            let window = pendingSamples.prefix(windowBytes)
            pendingSamples.removeFirst(windowBytes)
            await processWindow(Data(window), frameIndex: frame.frameIndex)
            guard isFinished == false else { return }
        }
    }

    func finish(reason: String) async -> VADObservationSummary? {
        if let cachedSummary {
            return cachedSummary
        }

        guard isFinished == false else {
            return await withCheckedContinuation { continuation in
                finishWaiters.append(continuation)
            }
        }

        isFinished = true
        pendingFinishReason = reason

        guard inFlightWindowCount == 0 else {
            return await withCheckedContinuation { continuation in
                finishWaiters.append(continuation)
            }
        }
        return logSummary(reason: reason)
    }

    private func processWindow(_ samples: Data, frameIndex: Int) async {
        let windowStartMs = processedAudioMs
        let windowEndMs = processedAudioMs + windowMs
        processedAudioMs = windowEndMs
        startedWindowCount += 1
        inFlightWindowCount += 1
        let windowNumber = startedWindowCount

        do {
            let startedAt = CFAbsoluteTimeGetCurrent()
            let result = try await ConfiguredVADDetector.detect(
                AudioFrame(samples: samples, frameIndex: windowNumber),
                config: config
            )
            let detectElapsedMs = elapsedMs(since: startedAt)

            guard acceptCompletedWindow(windowEndMs: windowEndMs) else { return }
            detectTotalMs += detectElapsedMs
            detectMaxMs = max(detectMaxMs, detectElapsedMs)
            maxProbability = max(maxProbability, result.probability)

            if result.isSpeech {
                recordSpeechWindow(
                    windowStartMs: windowStartMs,
                    windowEndMs: windowEndMs,
                    frameIndex: frameIndex,
                    windowNumber: windowNumber,
                    probability: result.probability
                )
            } else {
                recordSilenceWindow(
                    windowStartMs: windowStartMs,
                    windowEndMs: windowEndMs,
                    frameIndex: frameIndex,
                    windowNumber: windowNumber,
                    probability: result.probability
                )
            }
        } catch {
            guard acceptCompletedWindow(windowEndMs: windowEndMs) else { return }
            errors += 1
            lastError = error.localizedDescription
            if errors <= 3 {
                let message = "VAD observe failed. session=\(sessionID.uuidString) frame=\(frameIndex) window=\(windowNumber) error=\(error.localizedDescription)"
                logger.error("\(message, privacy: .public)")
                PerformanceLog.record(category: "VADObserve", message: message)
            }
        }
    }

    private func acceptCompletedWindow(windowEndMs: Double) -> Bool {
        inFlightWindowCount = max(0, inFlightWindowCount - 1)

        guard isFinished == false else {
            ignoredAfterFinishWindows += 1
            logPendingSummaryIfReady()
            return false
        }

        completedWindowCount += 1
        completedAudioMs = windowEndMs
        return true
    }

    private func logPendingSummaryIfReady() {
        guard isFinished, inFlightWindowCount == 0, let reason = pendingFinishReason else { return }
        _ = logSummary(reason: reason)
    }

    private func logSummary(reason: String) -> VADObservationSummary? {
        guard summaryLogged == false else { return cachedSummary }
        summaryLogged = true
        pendingFinishReason = nil
        finalizeSegment(endMs: completedAudioMs, reason: reason)

        let totalObservedBytes = observedBytes
        let segmentSummaries = segmentCandidates.map { candidate in
            let range = candidate.byteRange(totalBytes: totalObservedBytes, sampleRate: sampleRate, bytesPerSample: bytesPerSample)
            return VADObservationSegmentSummary(
                index: candidate.index,
                startMs: candidate.startMs,
                endMs: candidate.endMs,
                byteStart: range.lowerBound,
                byteEnd: range.upperBound,
                reason: candidate.reason
            )
        }
        let detectAverageMs = completedWindowCount > 0 ? detectTotalMs / Double(completedWindowCount) : 0
        let segmentTotalMs = segmentCandidates.reduce(0) { $0 + $1.durationMs }
        let summary = VADObservationSummary(
            sessionID: sessionID,
            reason: reason,
            engine: config.vad.engine,
            audioMs: observedAudioMs,
            processedMs: processedAudioMs,
            completedMs: completedAudioMs,
            speechWindows: speechWindows,
            silenceWindows: silenceWindows,
            maxProbability: maxProbability,
            firstSpeechMs: firstSpeechMs,
            lastSpeechMs: lastSpeechMs,
            longestSilenceMs: longestSilenceMs,
            detectAverageMs: detectAverageMs,
            detectMaxMs: detectMaxMs,
            errors: errors,
            audioBytes: totalObservedBytes,
            pendingBytes: pendingSamples.count,
            segments: segmentSummaries
        )
        let message = [
            "VAD observe summary.",
            "session=\(sessionID.uuidString)",
            "reason=\(reason)",
            "engine=\(config.vad.engine)",
            "windows=\(completedWindowCount)",
            "started_windows=\(startedWindowCount)",
            "in_flight_windows=\(inFlightWindowCount)",
            "ignored_after_finish_windows=\(ignoredAfterFinishWindows)",
            "ignored_after_finish_frames=\(ignoredAfterFinishFrames)",
            "audio_ms=\(formatMs(observedAudioMs))",
            "processed_ms=\(formatMs(processedAudioMs))",
            "completed_ms=\(formatMs(completedAudioMs))",
            "pending_bytes=\(pendingSamples.count)",
            "speech_windows=\(speechWindows)",
            "silence_windows=\(silenceWindows)",
            "max_probability=\(formatProbability(maxProbability))",
            "first_speech_ms=\(formatOptionalMs(firstSpeechMs))",
            "last_speech_ms=\(formatOptionalMs(lastSpeechMs))",
            "longest_silence_ms=\(formatMs(longestSilenceMs))",
            "segments=\(segmentCandidates.count)",
            "segment_total_ms=\(formatMs(segmentTotalMs))",
            "segment_max_ms=\(formatMs(segmentCandidates.map { $0.durationMs }.max() ?? 0))",
            "detect_avg_ms=\(formatMs(detectAverageMs))",
            "detect_max_ms=\(formatMs(detectMaxMs))",
            "errors=\(errors)",
            "last_error=\(lastError ?? "")",
            "elapsed_ms=\(formatMs(elapsedMs(since: startedAt)))"
        ].joined(separator: " ")
        logger.info("\(message, privacy: .public)")
        PerformanceLog.record(category: "VADObserve", message: message)
        logSegmentSummary()
        cachedSummary = summary
        let waiters = finishWaiters
        finishWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: summary)
        }
        return summary
    }

    private func recordSpeechWindow(
        windowStartMs: Double,
        windowEndMs: Double,
        frameIndex: Int,
        windowNumber: Int,
        probability: Double
    ) {
        speechWindows += 1
        firstSpeechMs = firstSpeechMs ?? windowStartMs
        lastSpeechMs = windowEndMs
        pauseLoggedForCurrentSilence = false
        observeSegmentSpeech(windowStartMs: windowStartMs, windowEndMs: windowEndMs)

        guard isInSpeech == false else { return }
        isInSpeech = true
        let message = "VAD observe speech started. session=\(sessionID.uuidString) frame=\(frameIndex) window=\(windowNumber) audio_ms=\(formatMs(windowStartMs)) probability=\(formatProbability(probability))"
        logger.info("\(message, privacy: .public)")
        PerformanceLog.record(category: "VADObserve", message: message)
    }

    private func recordSilenceWindow(
        windowStartMs: Double,
        windowEndMs: Double,
        frameIndex: Int,
        windowNumber: Int,
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

        let message = "VAD observe pause reached. session=\(sessionID.uuidString) frame=\(frameIndex) window=\(windowNumber) audio_ms=\(formatMs(windowEndMs)) silence_ms=\(formatMs(silenceMs)) probability=\(formatProbability(probability))"
        logger.info("\(message, privacy: .public)")
        PerformanceLog.record(category: "VADObserve", message: message)
        finalizeSegment(endMs: min(windowEndMs, lastSpeechMs + segmentTrailingSilenceMs), reason: "pause")
    }

    private func observeSegmentSpeech(windowStartMs: Double, windowEndMs: Double) {
        if segmentStartMs == nil {
            segmentStartMs = max(0, windowStartMs - segmentPrerollMs)
        }
        segmentHasSpeech = true

        guard let startMs = segmentStartMs, windowEndMs - startMs >= segmentMaxDurationMs else { return }
        finalizeSegment(endMs: windowEndMs, reason: "max_duration")
        segmentStartMs = max(0, windowEndMs - segmentPrerollMs)
        segmentHasSpeech = true
    }

    private func finalizeSegment(endMs: Double, reason: String) {
        guard segmentHasSpeech, let startMs = segmentStartMs else { return }
        let normalizedEndMs = max(startMs, endMs)
        guard normalizedEndMs - startMs >= segmentMinDurationMs else {
            segmentStartMs = nil
            segmentHasSpeech = false
            return
        }
        segmentCandidates.append(
            SegmentCandidate(
                index: segmentCandidates.count + 1,
                startMs: startMs,
                endMs: normalizedEndMs,
                reason: reason
            )
        )
        segmentStartMs = nil
        segmentHasSpeech = false
    }

    private func logSegmentSummary() {
        let totalObservedBytes = observedBytes
        let totalSegmentBytes = segmentCandidates.reduce(0) {
            $0 + $1.byteRange(totalBytes: totalObservedBytes, sampleRate: sampleRate, bytesPerSample: bytesPerSample).count
        }
        let segmentList = segmentCandidates
            .map { "\($0.index):\(formatMs($0.startMs))-\(formatMs($0.endMs)):\($0.reason)" }
            .joined(separator: ",")
        let byteList = segmentCandidates
            .map {
                let range = $0.byteRange(totalBytes: totalObservedBytes, sampleRate: sampleRate, bytesPerSample: bytesPerSample)
                return "\($0.index):\(range.lowerBound)-\(range.upperBound):\(range.count)"
            }
            .joined(separator: ",")
        let message = [
            "VAD observe segments.",
            "session=\(sessionID.uuidString)",
            "count=\(segmentCandidates.count)",
            "min_ms=\(formatMs(segmentMinDurationMs))",
            "max_ms=\(formatMs(segmentMaxDurationMs))",
            "preroll_ms=\(formatMs(segmentPrerollMs))",
            "trailing_ms=\(formatMs(segmentTrailingSilenceMs))",
            "audio_bytes=\(totalObservedBytes)",
            "segment_bytes=\(totalSegmentBytes)",
            "segments=\(segmentList.isEmpty ? "none" : segmentList)"
        ].joined(separator: " ")
        logger.info("\(message, privacy: .public)")
        PerformanceLog.record(category: "VADObserve", message: message)

        let bytesMessage = [
            "VAD observe segment bytes.",
            "session=\(sessionID.uuidString)",
            "sample_rate=\(Int(sampleRate))",
            "bytes_per_sample=\(bytesPerSample)",
            "audio_bytes=\(totalObservedBytes)",
            "ranges=\(byteList.isEmpty ? "none" : byteList)"
        ].joined(separator: " ")
        logger.info("\(bytesMessage, privacy: .public)")
        PerformanceLog.record(category: "VADObserve", message: bytesMessage)
    }

    private func frameDurationMs(_ frame: AudioFrame) -> Double {
        Double(frame.samples.count) / Double(bytesPerSample) / sampleRate * 1_000.0
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

private struct SegmentCandidate {
    let index: Int
    let startMs: Double
    let endMs: Double
    let reason: String

    var durationMs: Double {
        max(0, endMs - startMs)
    }

    func byteRange(totalBytes: Int, sampleRate: Double, bytesPerSample: Int) -> Range<Int> {
        let start = Self.byteOffset(forAudioMs: startMs, sampleRate: sampleRate, bytesPerSample: bytesPerSample)
        let end = Self.byteOffset(forAudioMs: endMs, sampleRate: sampleRate, bytesPerSample: bytesPerSample)
        let clampedStart = min(max(0, start), totalBytes)
        let clampedEnd = min(max(clampedStart, end), totalBytes)
        return clampedStart..<clampedEnd
    }

    private static func byteOffset(forAudioMs audioMs: Double, sampleRate: Double, bytesPerSample: Int) -> Int {
        let rawOffset = audioMs / 1_000.0 * sampleRate * Double(bytesPerSample)
        let roundedOffset = Int(rawOffset.rounded())
        return roundedOffset - roundedOffset % bytesPerSample
    }
}
