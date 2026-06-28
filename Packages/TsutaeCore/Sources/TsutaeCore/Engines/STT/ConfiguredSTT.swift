import Foundation
import OSLog
@preconcurrency import Speech

public final class AppleSpeechSTT: STTEngine, @unchecked Sendable {
    public let id = "apple_speech"
    public let displayName = "Apple Speech"
    public let isLocal = true
    public let supportedLanguages = ["auto", "zh", "en"]
    public var status: EngineStatus { .ready }
    
    public init() {}
    
    public func transcribe(_ audio: AudioData, language: String?) async throws -> Transcript {
        try await Self.requestAuthorizationIfNeeded()
        let locale = Self.locale(for: language)
        guard let recognizer = locale.map(SFSpeechRecognizer.init(locale:)) ?? SFSpeechRecognizer() else {
            throw AppleSpeechSTTError.recognizerUnavailable
        }
        
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tsutae-\(UUID().uuidString).wav")
        try WAVEncoder.encode(audio).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let request = SFSpeechURLRecognitionRequest(url: tempURL)
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.shouldReportPartialResults = false
        
        return try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var didFinish = false
            var task: SFSpeechRecognitionTask?
            
            let finish: (Result<Transcript, Error>) -> Void = { result in
                lock.lock()
                guard didFinish == false else {
                    lock.unlock()
                    return
                }
                didFinish = true
                let activeTask = task
                lock.unlock()
                activeTask?.cancel()
                continuation.resume(with: result)
            }
            
            task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    finish(.failure(error))
                    return
                }
                
                guard let result, result.isFinal else { return }
                finish(
                    .success(
                        Transcript(
                            text: result.bestTranscription.formattedString,
                            language: language,
                            durationMs: nil,
                            confidence: nil,
                            isFinal: true
                        )
                    )
                )
            }
            
            Task {
                try? await Task.sleep(for: .seconds(12))
                finish(.failure(AppleSpeechSTTError.recognitionTimedOut))
            }
        }
    }
    
    public func stream(_ audio: AsyncStream<AudioChunk>, language: String?) -> AsyncThrowingStream<TranscriptUpdate, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var data = Data()
                for await chunk in audio {
                    data.append(chunk.samples)
                }
                do {
                    let transcript = try await transcribe(AudioData(samples: data), language: language)
                    continuation.yield(.final(transcript))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    private static func requestAuthorizationIfNeeded() async throws {
        guard Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") != nil else {
            throw AppleSpeechSTTError.missingUsageDescription
        }
        
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized:
            return
        case .notDetermined:
            let resolved: SFSpeechRecognizerAuthorizationStatus
            do {
                resolved = try await withTimeout(seconds: 8) {
                    await withCheckedContinuation { continuation in
                        SFSpeechRecognizer.requestAuthorization { authorization in
                            continuation.resume(returning: authorization)
                        }
                    }
                }
            } catch is TimeoutError {
                throw AppleSpeechSTTError.authorizationPending
            }
            guard resolved == .authorized else {
                throw AppleSpeechSTTError.authorizationDenied
            }
        default:
            throw AppleSpeechSTTError.authorizationDenied
        }
    }
    
    private static func locale(for language: String?) -> Locale? {
        switch language?.lowercased() {
        case "zh", "zh-hans", "zh-cn":
            return Locale(identifier: "zh-CN")
        case "en", "en-us", "en-gb":
            return Locale(identifier: "en-US")
        default:
            return nil
        }
    }
    private static func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw TimeoutError()
            }
            let value = try await group.next()!
            group.cancelAll()
            return value
        }
    }
}

private struct TimeoutError: Error {}

public enum AppleSpeechSTTError: LocalizedError {
    case authorizationDenied
    case authorizationPending
    case recognizerUnavailable
    case recognitionTimedOut
    case missingUsageDescription
    
    public var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "Speech recognition permission was denied."
        case .authorizationPending:
            return "Speech recognition permission is still waiting for your response. Please approve or dismiss the system prompt."
        case .recognizerUnavailable:
            return "Apple Speech recognizer is unavailable for the selected language."
        case .recognitionTimedOut:
            return "Apple Speech fallback timed out while waiting for a recognition result."
        case .missingUsageDescription:
            return "Apple Speech fallback is unavailable because NSSpeechRecognitionUsageDescription is missing from the app bundle."
        }
    }
}

public enum STTTranscriptionError: LocalizedError, Sendable {
    case emptyTranscript(engine: String)
    case allRoutesFailed(primaryEngine: String, primaryError: String, fallbackEngine: String?, fallbackError: String?)

    public var errorDescription: String? {
        switch self {
        case .emptyTranscript(let engine):
            return "STT engine returned an empty transcript. engine=\(engine)"
        case .allRoutesFailed(let primaryEngine, let primaryError, let fallbackEngine, let fallbackError):
            var message = "STT failed. primary=\(primaryEngine): \(primaryError)"
            if let fallbackEngine, let fallbackError {
                message += "; fallback=\(fallbackEngine): \(fallbackError)"
            }
            return message
        }
    }

    public var isLikelyLongAudioLimit: Bool {
        switch self {
        case .emptyTranscript:
            return false
        case .allRoutesFailed(_, let primaryError, _, let fallbackError):
            return Self.isLikelyLongAudioLimit(primaryError)
                || fallbackError.map(Self.isLikelyLongAudioLimit) == true
        }
    }

    private static func isLikelyLongAudioLimit(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("cache capacity")
            || normalized.contains("prompt length")
            || normalized.contains("allowed range")
            || normalized.contains("too long")
    }
}

public enum STTEngineFactory {
    public static func makePrimaryEngine(config: Config.STTConfig) throws -> STTEngine {
        switch config.mode {
        case .localFirst:
            return makeLocalEngine(config: config)
        case .remoteFirst:
            if let remote = try makeRemoteEngine(config: config) {
                return remote
            }
            return makeLocalEngine(config: config)
        }
    }
    
    public static func makeFallbackEngine(config: Config.STTConfig) throws -> STTEngine? {
        switch config.fallbackEngine {
        case "apple_speech":
            return AppleSpeechSTT()
        case "openai_compatible":
            return try makeRemoteEngine(config: config)
        default:
            return nil
        }
    }
    
    public static func makeLocalEngine(config: Config.STTConfig) -> STTEngine {
        let modelID = config.local.preferredModel ?? config.model ?? "parakeet-tdt-v3"
        return FluidAudioSTT(modelID: modelID, languageHint: config.language)
    }
    
    public static func makeRemoteEngine(config: Config.STTConfig) throws -> STTEngine? {
        guard config.remote.enabled || config.mode == .remoteFirst else {
            return nil
        }
        
        guard let baseURLString = config.remote.baseURL ?? config.fallbackBaseURL,
              let baseURL = URL(string: baseURLString),
              let model = config.remote.model,
              model.isEmpty == false else {
            return nil
        }
        let apiKeyRef = config.remote.apiKeyRef ?? config.fallbackAPIKeyRef
        let apiKey = try apiKeyRef.flatMap { try SecretsManager.get($0) }
        
        return OpenAICompatibleSTT(
            id: "openai_compatible",
            displayName: "OpenAI Compatible STT",
            baseURL: baseURL,
            model: model,
            apiKey: apiKey,
            isLocal: false,
            supportedLanguages: ["auto", "zh", "en"],
            requestStyle: remoteRequestStyle(config.remote.requestStyle)
        )
    }
    
    private static func remoteRequestStyle(_ style: Config.STTRemoteRequestStyle) -> OpenAICompatibleRequestStyle {
        switch style {
        case .audioTranscriptions:
            return .audioTranscriptions
        case .chatCompletionsAudio:
            return .chatCompletionsAudio
        }
    }
}

public enum ConfiguredSTTRouter {
    private static let logger = Logger(subsystem: "dev.yanfch.Tsutae", category: "STTRouter")
    private static let localChunkTargetSeconds: Double = 25.0
    private static let localChunkHardSeconds: Double = 29.0
    private static let localChunkOverlapSeconds: Double = 0.2
    private static let chunkTextOverlapMaxCharacters = 12

    private struct TranscriptionChunk {
        let audio: AudioData
        let sourceRange: Range<Int>
    }
    
    public static func shouldKeepLocalModelWarmed(config: Config? = nil) throws -> Bool {
        let resolvedConfig = try config ?? ConfigLoader.load()
        return resolvedConfig.stt.mode == .localFirst || resolvedConfig.stt.local.keepModelWarmedInRemoteFirst
    }
    
    public static func applyLocalModelResidencyPolicy(config: Config? = nil) async throws {
        let resolvedConfig = try config ?? ConfigLoader.load()
        let localEngine = STTEngineFactory.makeLocalEngine(config: resolvedConfig.stt)
        let modelID = resolvedConfig.stt.local.preferredModel ?? resolvedConfig.stt.model ?? ""
        
        if try shouldKeepLocalModelWarmed(config: resolvedConfig), modelID.isEmpty == false {
            await FluidAudioSTT.unloadAllModels(except: modelID)
            let startedAt = CFAbsoluteTimeGetCurrent()
            try await localEngine.load()
            let message = "STT prewarm finished. engine=\(localEngine.id) model=\(modelID) elapsed_ms=\(formatElapsedMs(since: startedAt))"
            logger.info("\(message, privacy: .public)")
            PerformanceLog.record(category: "STTRouter", message: message)
        } else {
            await FluidAudioSTT.unloadAllModels()
            let message = "STT local models unloaded by residency policy. engine=\(localEngine.id) model=\(modelID) mode=\(resolvedConfig.stt.mode.rawValue)"
            logger.info("\(message, privacy: .public)")
            PerformanceLog.record(category: "STTRouter", message: message)
        }
    }
    
    public static func prewarmLocalModel(config: Config? = nil) async throws {
        try await applyLocalModelResidencyPolicy(config: config)
    }
    
    public static func unloadLocalModel(config: Config? = nil) async throws {
        let resolvedConfig = try config ?? ConfigLoader.load()
        let localEngine = STTEngineFactory.makeLocalEngine(config: resolvedConfig.stt)
        let modelID = resolvedConfig.stt.local.preferredModel ?? resolvedConfig.stt.model ?? ""
        await FluidAudioSTT.unloadAllModels()
        let message = "STT local model force-unloaded. engine=\(localEngine.id) model=\(modelID)"
        logger.info("\(message, privacy: .public)")
        PerformanceLog.record(category: "STTRouter", message: message)
    }
    
    public static func transcribe(_ audio: AudioData, config: Config? = nil) async throws -> Transcript {
        let overallStartedAt = CFAbsoluteTimeGetCurrent()
        let resolvedConfig = try config ?? ConfigLoader.load()
        let primary = try STTEngineFactory.makePrimaryEngine(config: resolvedConfig.stt)
        let fallback = try STTEngineFactory.makeFallbackEngine(config: resolvedConfig.stt)
        let language = normalizedLanguage(resolvedConfig.stt.language)
        let localModelID = resolvedConfig.stt.local.preferredModel ?? resolvedConfig.stt.model ?? "unknown"
        let guidance = LocalSTTModelCatalog.recordingGuidance(for: localModelID)
        let routeContext = "mode=\(resolvedConfig.stt.mode.rawValue) primary=\(primary.id) fallback=\(fallback?.id ?? "none") language=\(language ?? "auto") local_model=\(localModelID) remote_model=\(resolvedConfig.stt.remote.model ?? "none") audio_bytes=\(audio.samples.count) audio_seconds=\(audioDurationSeconds(audio)) local_warning_seconds=\(guidance.warningSeconds) local_recommended_max_seconds=\(guidance.recommendedMaximumSeconds) local_guidance_estimated=\(guidance.isEstimated)"
        let startMessage = "STT transcription started. \(routeContext)"
        logger.info("\(startMessage, privacy: .public)")
        PerformanceLog.record(category: "STTRouter", message: startMessage)
        
        do {
            let primaryLoadStartedAt = CFAbsoluteTimeGetCurrent()
            try await primary.load()
            let primaryLoadMessage = "STT primary load finished. engine=\(primary.id) elapsed_ms=\(formatElapsedMs(since: primaryLoadStartedAt))"
            logger.info("\(primaryLoadMessage, privacy: .public)")
            PerformanceLog.record(category: "STTRouter", message: primaryLoadMessage)

            if shouldChunkLocalPrimary(audio: audio, engine: primary, config: resolvedConfig) {
                let primaryTranscribeStartedAt = CFAbsoluteTimeGetCurrent()
                let transcript = try await transcribeLocalChunks(
                    audio,
                    engine: primary,
                    language: language,
                    config: resolvedConfig,
                    overallStartedAt: overallStartedAt
                )
                let primaryDoneMessage = "STT primary chunked transcription finished. engine=\(primary.id) model=\(modelID(for: primary.id, config: resolvedConfig.stt)) text_chars=\(transcript.text.count) audio_seconds=\(audioDurationSeconds(audio)) elapsed_ms=\(formatElapsedMs(since: primaryTranscribeStartedAt)) total_elapsed_ms=\(formatElapsedMs(since: overallStartedAt))"
                logger.info("\(primaryDoneMessage, privacy: .public)")
                PerformanceLog.record(category: "STTRouter", message: primaryDoneMessage)
                return transcript
            }

            let primaryTranscribeStartedAt = CFAbsoluteTimeGetCurrent()
            let transcript = try validateTranscript(
                try await primary.transcribe(audio, language: language),
                engineID: primary.id
            )
            let primaryDoneMessage = "STT primary transcription finished. engine=\(primary.id) model=\(modelID(for: primary.id, config: resolvedConfig.stt)) text_chars=\(transcript.text.count) audio_seconds=\(audioDurationSeconds(audio)) elapsed_ms=\(formatElapsedMs(since: primaryTranscribeStartedAt)) total_elapsed_ms=\(formatElapsedMs(since: overallStartedAt))"
            logger.info("\(primaryDoneMessage, privacy: .public)")
            PerformanceLog.record(category: "STTRouter", message: primaryDoneMessage)
            return transcript
        } catch {
            let primaryError = error
            let primaryFailedMessage = "STT primary failed. engine=\(primary.id) model=\(modelID(for: primary.id, config: resolvedConfig.stt)) audio_seconds=\(audioDurationSeconds(audio)) error=\(error.localizedDescription) elapsed_ms=\(formatElapsedMs(since: overallStartedAt))"
            logger.error("\(primaryFailedMessage, privacy: .public)")
            PerformanceLog.record(category: "STTRouter", message: primaryFailedMessage)
            guard let fallback, fallback.id != primary.id else {
                throw error
            }

            do {
                let fallbackLoadStartedAt = CFAbsoluteTimeGetCurrent()
                try await fallback.load()
                let fallbackLoadMessage = "STT fallback load finished. engine=\(fallback.id) elapsed_ms=\(formatElapsedMs(since: fallbackLoadStartedAt))"
                logger.info("\(fallbackLoadMessage, privacy: .public)")
                PerformanceLog.record(category: "STTRouter", message: fallbackLoadMessage)

                let fallbackTranscribeStartedAt = CFAbsoluteTimeGetCurrent()
                let transcript = try validateTranscript(
                    try await fallback.transcribe(audio, language: language),
                    engineID: fallback.id
                )
                let fallbackDoneMessage = "STT fallback transcription finished. engine=\(fallback.id) model=\(modelID(for: fallback.id, config: resolvedConfig.stt)) text_chars=\(transcript.text.count) audio_seconds=\(audioDurationSeconds(audio)) elapsed_ms=\(formatElapsedMs(since: fallbackTranscribeStartedAt)) total_elapsed_ms=\(formatElapsedMs(since: overallStartedAt))"
                logger.info("\(fallbackDoneMessage, privacy: .public)")
                PerformanceLog.record(category: "STTRouter", message: fallbackDoneMessage)
                return transcript
            } catch {
                let fallbackFailedMessage = "STT fallback failed. engine=\(fallback.id) model=\(modelID(for: fallback.id, config: resolvedConfig.stt)) audio_seconds=\(audioDurationSeconds(audio)) error=\(error.localizedDescription) total_elapsed_ms=\(formatElapsedMs(since: overallStartedAt))"
                logger.error("\(fallbackFailedMessage, privacy: .public)")
                PerformanceLog.record(category: "STTRouter", message: fallbackFailedMessage)
                throw STTTranscriptionError.allRoutesFailed(
                    primaryEngine: primary.id,
                    primaryError: primaryError.localizedDescription,
                    fallbackEngine: fallback.id,
                    fallbackError: error.localizedDescription
                )
            }
        }
    }

    private static func shouldChunkLocalPrimary(audio: AudioData, engine: STTEngine, config: Config) -> Bool {
        guard config.stt.mode == .localFirst,
              engine.id == "fluidaudio_local",
              audio.container == .pcm16 else {
            return false
        }
        return audio.samples.count > byteCount(
            seconds: localChunkHardSeconds,
            sampleRate: audio.sampleRate,
            channels: audio.channels
        )
    }

    private static func transcribeLocalChunks(
        _ audio: AudioData,
        engine: STTEngine,
        language: String?,
        config: Config,
        overallStartedAt: CFAbsoluteTime
    ) async throws -> Transcript {
        let chunks = localChunks(for: audio)
        let planMessage = "STT local chunk plan. engine=\(engine.id) model=\(modelID(for: engine.id, config: config.stt)) chunks=\(chunks.count) audio_bytes=\(audio.samples.count) chunk_bytes=\(chunks.map { $0.audio.samples.count }.map(String.init).joined(separator: ",")) target_seconds=\(String(format: "%.1f", localChunkTargetSeconds)) hard_seconds=\(String(format: "%.1f", localChunkHardSeconds)) overlap_ms=\(String(format: "%.0f", localChunkOverlapSeconds * 1000))"
        logger.info("\(planMessage, privacy: .public)")
        PerformanceLog.record(category: "STTRouter", message: planMessage)

        var texts: [String] = []
        var transcriptLanguage: String?
        for (index, chunk) in chunks.enumerated() {
            let startedAt = CFAbsoluteTimeGetCurrent()
            let chunkStartMessage = "STT local chunk started. index=\(index + 1) total=\(chunks.count) bytes=\(chunk.audio.samples.count) audio_seconds=\(audioDurationSeconds(chunk.audio)) range=\(chunk.sourceRange.lowerBound)-\(chunk.sourceRange.upperBound) total_elapsed_ms=\(formatElapsedMs(since: overallStartedAt))"
            logger.info("\(chunkStartMessage, privacy: .public)")
            PerformanceLog.record(category: "STTRouter", message: chunkStartMessage)

            let transcript = try await engine.transcribe(chunk.audio, language: language)
            if transcriptLanguage == nil {
                transcriptLanguage = transcript.language
            }
            let text = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty == false {
                texts.append(text)
            }

            let chunkDoneMessage = "STT local chunk finished. index=\(index + 1) total=\(chunks.count) chars=\(transcript.text.count) elapsed_ms=\(formatElapsedMs(since: startedAt)) total_elapsed_ms=\(formatElapsedMs(since: overallStartedAt))"
            logger.info("\(chunkDoneMessage, privacy: .public)")
            PerformanceLog.record(category: "STTRouter", message: chunkDoneMessage)
        }

        let text = joinedTranscriptChunks(texts)
        return try validateTranscript(
            Transcript(text: text, language: transcriptLanguage ?? language, durationMs: nil, confidence: nil, isFinal: true),
            engineID: engine.id
        )
    }

    private static func localChunks(for audio: AudioData) -> [TranscriptionChunk] {
        let maxBytes = byteCount(seconds: localChunkTargetSeconds, sampleRate: audio.sampleRate, channels: audio.channels)
        let overlapBytes = byteCount(seconds: localChunkOverlapSeconds, sampleRate: audio.sampleRate, channels: audio.channels)
        let ranges = splitRange(
            0..<audio.samples.count,
            maxBytes: maxBytes,
            overlapBytes: overlapBytes,
            frameBytes: frameBytes(for: audio)
        )
        return ranges.compactMap { range in
            let data = audio.samples.subdata(in: range)
            guard data.isEmpty == false else { return nil }
            return TranscriptionChunk(
                audio: AudioData(samples: data, sampleRate: audio.sampleRate, channels: audio.channels, container: audio.container),
                sourceRange: range
            )
        }
    }

    private static func splitRange(
        _ range: Range<Int>,
        maxBytes: Int,
        overlapBytes: Int,
        frameBytes: Int
    ) -> [Range<Int>] {
        guard maxBytes > frameBytes, range.count > maxBytes else { return [range] }
        let alignedOverlap = max(0, overlapBytes - overlapBytes % frameBytes)
        var ranges: [Range<Int>] = []
        var start = range.lowerBound
        while start < range.upperBound {
            let end = min(start + maxBytes, range.upperBound)
            if end > start {
                ranges.append(start..<end)
            }
            guard end < range.upperBound else { break }
            let nextStart = max(range.lowerBound, end - alignedOverlap)
            start = nextStart > start ? nextStart : end
        }
        return ranges
    }

    private static func joinedTranscriptChunks(_ texts: [String]) -> String {
        var output = ""
        for text in texts {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.isEmpty == false else { continue }
            guard output.isEmpty == false else {
                output = value
                continue
            }
            let overlap = transcriptTextOverlapSuffixPrefix(output, value, maxCharacters: chunkTextOverlapMaxCharacters)
            let remainder = String(value.dropFirst(overlap))
            guard remainder.isEmpty == false else { continue }
            output += joinSeparator(previous: output, next: remainder) + remainder
        }
        return output
    }

    private static func transcriptTextOverlapSuffixPrefix(_ previous: String, _ next: String, maxCharacters: Int) -> Int {
        let maxLength = min(maxCharacters, previous.count, next.count)
        guard maxLength >= 2 else { return 0 }
        for length in stride(from: maxLength, through: 2, by: -1) {
            if previous.suffix(length) == next.prefix(length) {
                return length
            }
        }
        return 0
    }

    private static func joinSeparator(previous: String, next: String) -> String {
        guard let previousLast = previous.last, let nextFirst = next.first else { return "" }
        if previousLast.isWhitespace || nextFirst.isWhitespace { return "" }
        let noSpaceBefore = CharacterSet(charactersIn: "，。！？；：、,.!?;:")
        if String(nextFirst).rangeOfCharacter(from: noSpaceBefore) != nil { return "" }
        if isCJK(previousLast) || isCJK(nextFirst) { return "" }
        return " "
    }

    private static func isCJK(_ character: Character) -> Bool {
        String(character).range(of: #"\p{Han}"#, options: .regularExpression) != nil
    }

    private static func validateTranscript(_ transcript: Transcript, engineID: String) throws -> Transcript {
        guard transcript.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw STTTranscriptionError.emptyTranscript(engine: engineID)
        }
        return transcript
    }

    private static func modelID(for engineID: String, config: Config.STTConfig) -> String {
        switch engineID {
        case "openai_compatible":
            return config.remote.model ?? "unknown"
        case "apple_speech":
            return "apple_speech"
        default:
            return config.local.preferredModel ?? config.model ?? "unknown"
        }
    }

    private static func audioDurationSeconds(_ audio: AudioData) -> String {
        guard audio.sampleRate > 0, audio.channels > 0 else { return "0.0" }
        return String(format: "%.1f", Double(audio.samples.count) / Double(audio.sampleRate * audio.channels * 2))
    }

    private static func byteCount(seconds: Double, sampleRate: Int, channels: Int) -> Int {
        guard seconds > 0, sampleRate > 0, channels > 0 else { return 0 }
        let frameBytes = max(1, channels * MemoryLayout<Int16>.size)
        let bytes = Int(seconds * Double(sampleRate * channels * MemoryLayout<Int16>.size))
        return max(frameBytes, bytes - bytes % frameBytes)
    }

    private static func frameBytes(for audio: AudioData) -> Int {
        max(1, audio.channels * MemoryLayout<Int16>.size)
    }
    
    private static func formatElapsedMs(since startedAt: CFAbsoluteTime) -> String {
        String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
    }
    
    private static func normalizedLanguage(_ language: String?) -> String? {
        switch language?.lowercased() {
        case nil, "", "auto":
            return nil
        case "zh", "zh-hans", "zh-cn":
            return "zh"
        case "en", "en-us", "en-gb":
            return "en"
        default:
            return language
        }
    }
}
