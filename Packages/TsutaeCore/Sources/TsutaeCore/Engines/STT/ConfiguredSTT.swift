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
    
    public static func shouldKeepLocalModelWarmed(config: Config? = nil) throws -> Bool {
        let resolvedConfig = try config ?? ConfigLoader.load()
        return resolvedConfig.stt.mode == .localFirst || resolvedConfig.stt.local.keepModelWarmedInRemoteFirst
    }
    
    public static func applyLocalModelResidencyPolicy(config: Config? = nil) async throws {
        let resolvedConfig = try config ?? ConfigLoader.load()
        let localEngine = STTEngineFactory.makeLocalEngine(config: resolvedConfig.stt)
        let modelID = resolvedConfig.stt.local.preferredModel ?? resolvedConfig.stt.model ?? ""
        
        if try shouldKeepLocalModelWarmed(config: resolvedConfig) {
            let startedAt = CFAbsoluteTimeGetCurrent()
            try await localEngine.load()
            let message = "STT prewarm finished. engine=\(localEngine.id) model=\(modelID) elapsed_ms=\(formatElapsedMs(since: startedAt))"
            logger.info("\(message, privacy: .public)")
            PerformanceLog.record(category: "STTRouter", message: message)
        } else {
            localEngine.unload()
            let message = "STT local model unloaded by residency policy. engine=\(localEngine.id) model=\(modelID) mode=\(resolvedConfig.stt.mode.rawValue)"
            logger.info("\(message, privacy: .public)")
            PerformanceLog.record(category: "STTRouter", message: message)
        }
    }
    
    public static func prewarmLocalModel(config: Config? = nil) async throws {
        try await applyLocalModelResidencyPolicy(config: config)
    }
    
    public static func transcribe(_ audio: AudioData, config: Config? = nil) async throws -> Transcript {
        let overallStartedAt = CFAbsoluteTimeGetCurrent()
        let resolvedConfig = try config ?? ConfigLoader.load()
        let primary = try STTEngineFactory.makePrimaryEngine(config: resolvedConfig.stt)
        let fallback = try STTEngineFactory.makeFallbackEngine(config: resolvedConfig.stt)
        let language = normalizedLanguage(resolvedConfig.stt.language)
        let startMessage = "STT transcription started. mode=\(resolvedConfig.stt.mode.rawValue) primary=\(primary.id) fallback=\(fallback?.id ?? "none") language=\(language ?? "auto") audio_bytes=\(audio.samples.count)"
        logger.info("\(startMessage, privacy: .public)")
        PerformanceLog.record(category: "STTRouter", message: startMessage)
        
        do {
            let primaryLoadStartedAt = CFAbsoluteTimeGetCurrent()
            try await primary.load()
            let primaryLoadMessage = "STT primary load finished. engine=\(primary.id) elapsed_ms=\(formatElapsedMs(since: primaryLoadStartedAt))"
            logger.info("\(primaryLoadMessage, privacy: .public)")
            PerformanceLog.record(category: "STTRouter", message: primaryLoadMessage)
            
            let primaryTranscribeStartedAt = CFAbsoluteTimeGetCurrent()
            let transcript = try await primary.transcribe(audio, language: language)
            let primaryDoneMessage = "STT primary transcription finished. engine=\(primary.id) text_chars=\(transcript.text.count) elapsed_ms=\(formatElapsedMs(since: primaryTranscribeStartedAt)) total_elapsed_ms=\(formatElapsedMs(since: overallStartedAt))"
            logger.info("\(primaryDoneMessage, privacy: .public)")
            PerformanceLog.record(category: "STTRouter", message: primaryDoneMessage)
            return transcript
        } catch {
            let primaryFailedMessage = "STT primary failed. engine=\(primary.id) error=\(error.localizedDescription) elapsed_ms=\(formatElapsedMs(since: overallStartedAt))"
            logger.error("\(primaryFailedMessage, privacy: .public)")
            PerformanceLog.record(category: "STTRouter", message: primaryFailedMessage)
            guard let fallback, fallback.id != primary.id else {
                throw error
            }
            
            let fallbackLoadStartedAt = CFAbsoluteTimeGetCurrent()
            try await fallback.load()
            let fallbackLoadMessage = "STT fallback load finished. engine=\(fallback.id) elapsed_ms=\(formatElapsedMs(since: fallbackLoadStartedAt))"
            logger.info("\(fallbackLoadMessage, privacy: .public)")
            PerformanceLog.record(category: "STTRouter", message: fallbackLoadMessage)
            
            let fallbackTranscribeStartedAt = CFAbsoluteTimeGetCurrent()
            let transcript = try await fallback.transcribe(audio, language: language)
            let fallbackDoneMessage = "STT fallback transcription finished. engine=\(fallback.id) text_chars=\(transcript.text.count) elapsed_ms=\(formatElapsedMs(since: fallbackTranscribeStartedAt)) total_elapsed_ms=\(formatElapsedMs(since: overallStartedAt))"
            logger.info("\(fallbackDoneMessage, privacy: .public)")
            PerformanceLog.record(category: "STTRouter", message: fallbackDoneMessage)
            return transcript
        }
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
