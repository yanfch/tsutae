import Foundation
import OSLog
@preconcurrency import FluidAudio

public struct LocalSTTModelDescriptor: Identifiable, Equatable, Sendable {
    public enum Group: String, Sendable {
        case auto
        case chinese
        case english
        case preview
    }
    
    public let id: String
    public let displayName: String
    public let runtime: String
    public let summary: String
    public let size: String
    public let memory: String
    public let tags: [String]
    public let group: Group
    public let isRecommended: Bool
    
    public init(
        id: String,
        displayName: String,
        runtime: String = "FluidAudio",
        summary: String,
        size: String,
        memory: String,
        tags: [String],
        group: Group,
        isRecommended: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.runtime = runtime
        self.summary = summary
        self.size = size
        self.memory = memory
        self.tags = tags
        self.group = group
        self.isRecommended = isRecommended
    }
}

public struct LocalSTTRecordingGuidance: Equatable, Sendable {
    public let warningSeconds: Int
    public let recommendedMaximumSeconds: Int
    public let isEstimated: Bool

    public init(warningSeconds: Int, recommendedMaximumSeconds: Int, isEstimated: Bool = true) {
        self.warningSeconds = warningSeconds
        self.recommendedMaximumSeconds = recommendedMaximumSeconds
        self.isEstimated = isEstimated
    }
}

public enum LocalSTTModelCatalog {
    public static let all: [LocalSTTModelDescriptor] = [
        LocalSTTModelDescriptor(
            id: "sensevoice-small",
            displayName: "SenseVoice Small",
            summary: "Balanced local model for mixed Chinese and English speech.",
            size: "1.6 GB",
            memory: "~0.4 GB",
            tags: ["Best for Mixed", "Balanced", "Low Memory"],
            group: .auto,
            isRecommended: true
        ),
        LocalSTTModelDescriptor(
            id: "qwen3-asr-int8",
            displayName: "Qwen3-ASR Int8",
            summary: "Mixed-language option with better coverage but slower runtime.",
            size: "2.9 GB",
            memory: "1.7–2.2 GB",
            tags: ["Mixed Language", "Higher Memory", "Slower"],
            group: .auto
        ),
        LocalSTTModelDescriptor(
            id: "paraformer-large-zh",
            displayName: "Paraformer Large ZH",
            summary: "Fast local model tuned for Chinese transcription.",
            size: "623 MB",
            memory: "~0.4 GB",
            tags: ["Best for Chinese", "Chinese Focused", "Low Memory"],
            group: .chinese
        ),
        LocalSTTModelDescriptor(
            id: "parakeet-ctc-zh-cn",
            displayName: "Parakeet CTC Chinese",
            summary: "Mandarin-focused CoreML path with weaker text spacing output.",
            size: "1.7 GB",
            memory: "~0.4 GB",
            tags: ["Chinese", "Low Memory", "Spacing Issues"],
            group: .chinese
        ),
        LocalSTTModelDescriptor(
            id: "parakeet-tdt-v3",
            displayName: "Parakeet TDT v3",
            summary: "Fast 0.6B model for English and other European languages.",
            size: "461 MB",
            memory: "~0.4 GB",
            tags: ["Best for English", "Fast", "Low Memory", "0.6B"],
            group: .english
        ),
        LocalSTTModelDescriptor(
            id: "parakeet-eou",
            displayName: "Parakeet EOU",
            summary: "Preview-only streaming candidate for future partial transcription.",
            size: "~430 MB",
            memory: "Not measured",
            tags: ["Preview Only"],
            group: .preview
        ),
    ]
    
    public static func descriptor(id: String) -> LocalSTTModelDescriptor? {
        all.first(where: { $0.id == id })
    }

    public static func recordingGuidance(for id: String?) -> LocalSTTRecordingGuidance {
        switch id {
        case "paraformer-large-zh":
            return LocalSTTRecordingGuidance(warningSeconds: 25, recommendedMaximumSeconds: 30, isEstimated: false)
        case "qwen3-asr-int8":
            return LocalSTTRecordingGuidance(warningSeconds: 30, recommendedMaximumSeconds: 35, isEstimated: false)
        case "sensevoice-small":
            return LocalSTTRecordingGuidance(warningSeconds: 25, recommendedMaximumSeconds: 30, isEstimated: false)
        case "parakeet-ctc-zh-cn", "parakeet-tdt-v3":
            return LocalSTTRecordingGuidance(warningSeconds: 30, recommendedMaximumSeconds: 35)
        default:
            return LocalSTTRecordingGuidance(warningSeconds: 30, recommendedMaximumSeconds: 35)
        }
    }
    
    public static func isDownloaded(id: String) -> Bool {
        switch id {
        case "sensevoice-small":
            return SenseVoiceModels.modelsExist(at: senseVoiceDirectory(), precision: .fp16)
                || SenseVoiceModels.modelsExist(at: senseVoiceDirectory(), precision: .int8)
                || SenseVoiceModels.modelsExist(at: senseVoiceDirectory(), precision: .fp32)
        case "qwen3-asr-int8":
            if #available(macOS 15, *) {
                return Qwen3AsrModels.modelsExist(at: Qwen3AsrModels.defaultCacheDirectory(variant: .int8))
            }
            return false
        case "paraformer-large-zh":
            return ParaformerModels.modelsExist(at: paraformerDirectory(), precision: .fp16)
                || ParaformerModels.modelsExist(at: paraformerDirectory(), precision: .int8)
        case "parakeet-ctc-zh-cn":
            return CtcZhCnModels.modelsExist(at: ctcZhCnDirectory())
        case "parakeet-tdt-v3":
            return AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: .v3), version: .v3)
        case "parakeet-eou":
            return FileManager.default.fileExists(atPath: eouDirectory().path)
        default:
            return false
        }
    }
    
    public static func download(id: String, progressHandler: (@Sendable (Double) -> Void)? = nil) async throws {
        let wrappedProgress: DownloadUtils.ProgressHandler?
        if let progressHandler {
            let totalPasses = progressPassCount(for: id)
            final class ProgressAccumulator: @unchecked Sendable {
                let lock = NSLock()
                var completedPasses = 0
                var lastFraction = 0.0
            }
            let accumulator = ProgressAccumulator()
            wrappedProgress = { progress in
                let fraction = max(0, min(progress.fractionCompleted, 1))
                accumulator.lock.lock()
                if totalPasses > 1, fraction + 0.2 < accumulator.lastFraction {
                    accumulator.completedPasses = min(accumulator.completedPasses + 1, totalPasses - 1)
                }
                accumulator.lastFraction = fraction
                let overall = totalPasses > 1
                    ? (Double(accumulator.completedPasses) + fraction) / Double(totalPasses)
                    : fraction
                accumulator.lock.unlock()
                progressHandler(min(max(overall, 0), 1))
            }
        } else {
            wrappedProgress = nil
        }
        switch id {
        case "sensevoice-small":
            _ = try await SenseVoiceModels.download(precision: .fp16, progressHandler: wrappedProgress)
        case "qwen3-asr-int8":
            guard #available(macOS 15, *) else {
                throw FluidAudioSTTError.unsupportedModel(id)
            }
            _ = try await Qwen3AsrModels.download(variant: .int8, progressHandler: wrappedProgress)
        case "paraformer-large-zh":
            _ = try await ParaformerModels.download(precision: .fp16, progressHandler: wrappedProgress)
        case "parakeet-ctc-zh-cn":
            _ = try await CtcZhCnModels.download(progressHandler: wrappedProgress)
        case "parakeet-tdt-v3":
            _ = try await AsrModels.download(version: .v3, progressHandler: wrappedProgress)
        case "parakeet-eou":
            let manager = StreamingEouAsrManager()
            try await manager.loadModels(to: nil, configuration: nil, progressHandler: wrappedProgress)
            await manager.cleanup()
        default:
            throw FluidAudioSTTError.unsupportedModel(id)
        }
    }
    
    public static func delete(id: String) async throws {
        await FluidAudioSTTRuntime.shared.unload(modelID: id)
        guard let directory = modelDirectory(for: id) else {
            throw FluidAudioSTTError.unsupportedModel(id)
        }
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }
    
    private static func progressPassCount(for id: String) -> Int {
        switch id {
        case "parakeet-tdt-v3":
            return 4
        default:
            return 1
        }
    }
    
    public static func estimatedDownloadBytes(id: String) -> Int64? {
        switch id {
        case "sensevoice-small":
            return 447 * 1_000_000
        case "qwen3-asr-int8":
            return 179 * 1_000_000
        case "paraformer-large-zh":
            return 411 * 1_000_000
        case "parakeet-ctc-zh-cn":
            return 1_100 * 1_000_000
        case "parakeet-tdt-v3":
            return 500 * 1_000_000
        case "parakeet-eou":
            return 250 * 1_000_000
        default:
            return nil
        }
    }
    
    public static func downloadedByteCount(id: String) -> Int64 {
        guard let directory = modelDirectory(for: id) else { return 0 }
        return directoryByteCount(at: directory)
    }
    
    private static func modelDirectory(for id: String) -> URL? {
        switch id {
        case "sensevoice-small":
            return senseVoiceDirectory()
        case "qwen3-asr-int8":
            if #available(macOS 15, *) {
                return Qwen3AsrModels.defaultCacheDirectory(variant: .int8)
            }
            return nil
        case "paraformer-large-zh":
            return paraformerDirectory()
        case "parakeet-ctc-zh-cn":
            return ctcZhCnDirectory()
        case "parakeet-tdt-v3":
            return AsrModels.defaultCacheDirectory(for: .v3)
        case "parakeet-eou":
            return eouDirectory()
        default:
            return nil
        }
    }
    
    private static func senseVoiceDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(Repo.senseVoiceSmall.folderName, isDirectory: true)
        ?? FileManager.default.temporaryDirectory
    }
    
    private static func paraformerDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(Repo.paraformerLargeZh.folderName, isDirectory: true)
        ?? FileManager.default.temporaryDirectory
    }
    
    private static func ctcZhCnDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(Repo.parakeetCtcZhCn.folderName, isDirectory: true)
        ?? FileManager.default.temporaryDirectory
    }
    
    private static func eouDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(Repo.parakeetEou160.folderName, isDirectory: true)
        ?? FileManager.default.temporaryDirectory
    }
    
    private static func directoryByteCount(at directory: URL) -> Int64 {
        guard FileManager.default.fileExists(atPath: directory.path) else { return 0 }
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard
                let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                values.isRegularFile == true
            else {
                continue
            }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}

private actor FluidAudioSTTRuntime {
    static let shared = FluidAudioSTTRuntime()
    private let logger = Logger(subsystem: "dev.yanfch.Tsutae", category: "FluidAudioSTT")
    
    private struct LoadedModel: Sendable {
        let transcribe: @Sendable ([Float], String?) async throws -> String
        let cleanup: @Sendable () async -> Void
    }
    
    private var loadedModels: [String: LoadedModel] = [:]
    private var loadingTasks: [String: Task<LoadedModel, Error>] = [:]
    
    func preload(modelID: String) async throws {
        _ = try await loadedModel(for: modelID)
    }
    
    func isLoaded(modelID: String) -> Bool {
        loadedModels[modelID] != nil
    }
    
    func isLoading(modelID: String) -> Bool {
        loadingTasks[modelID] != nil
    }
    
    func transcribe(modelID: String, samples: [Float], language: String?) async throws -> String {
        let loadedModel = try await loadedModel(for: modelID)
        return try await loadedModel.transcribe(samples, language)
    }
    
    func unload(modelID: String) async {
        loadingTasks[modelID]?.cancel()
        loadingTasks[modelID] = nil
        guard let loadedModel = loadedModels.removeValue(forKey: modelID) else { return }
        let message = "Unloaded local STT model. model=\(modelID)"
        logger.info("\(message, privacy: .public)")
        PerformanceLog.record(category: "FluidAudioSTT", message: message)
        await loadedModel.cleanup()
    }
    
    func unloadAll(except keptModelID: String? = nil) async {
        let loadingIDs = Array(loadingTasks.keys)
        for modelID in loadingIDs where modelID != keptModelID {
            loadingTasks[modelID]?.cancel()
            loadingTasks[modelID] = nil
            let message = "Cancelled local STT model load. model=\(modelID)"
            logger.info("\(message, privacy: .public)")
            PerformanceLog.record(category: "FluidAudioSTT", message: message)
        }
        
        let loadedIDs = Array(loadedModels.keys)
        for modelID in loadedIDs where modelID != keptModelID {
            guard let loadedModel = loadedModels.removeValue(forKey: modelID) else { continue }
            let message = "Unloaded local STT model. model=\(modelID)"
            logger.info("\(message, privacy: .public)")
            PerformanceLog.record(category: "FluidAudioSTT", message: message)
            await loadedModel.cleanup()
        }
    }
    
    private func loadedModel(for modelID: String) async throws -> LoadedModel {
        if let loadedModel = loadedModels[modelID] {
            return loadedModel
        }
        
        if let task = loadingTasks[modelID] {
            return try await task.value
        }
        
        let task = Task<LoadedModel, Error> {
            try await Self.makeLoadedModel(modelID: modelID)
        }
        loadingTasks[modelID] = task
        
        do {
            let loadedModel = try await task.value
            loadedModels[modelID] = loadedModel
            loadingTasks[modelID] = nil
            let message = "Loaded local STT model into runtime cache. model=\(modelID)"
            logger.info("\(message, privacy: .public)")
            PerformanceLog.record(category: "FluidAudioSTT", message: message)
            return loadedModel
        } catch {
            loadingTasks[modelID] = nil
            throw error
        }
    }
    
    private static func makeLoadedModel(modelID: String) async throws -> LoadedModel {
        guard LocalSTTModelCatalog.isDownloaded(id: modelID) else {
            throw FluidAudioSTTError.modelNotDownloaded(modelID)
        }
        
        switch modelID {
        case "sensevoice-small":
            let manager = try await SenseVoiceManager.load(precision: .fp16)
            return LoadedModel(
                transcribe: { samples, _ in
                    try await manager.transcribe(audio: samples)
                },
                cleanup: {}
            )
        case "qwen3-asr-int8":
            guard #available(macOS 15, *) else {
                throw FluidAudioSTTError.unsupportedModel(modelID)
            }
            let manager = Qwen3AsrManager()
            try await manager.loadModels(from: Qwen3AsrModels.defaultCacheDirectory(variant: .int8))
            return LoadedModel(
                transcribe: { samples, language in
                    try await manager.transcribe(audioSamples: samples, language: language)
                },
                cleanup: {}
            )
        case "paraformer-large-zh":
            let manager = try await ParaformerManager.load(precision: .fp16)
            return LoadedModel(
                transcribe: { samples, _ in
                    try await manager.transcribe(audio: samples)
                },
                cleanup: {}
            )
        case "parakeet-ctc-zh-cn":
            let manager = try await CtcZhCnManager.load()
            return LoadedModel(
                transcribe: { samples, _ in
                    try await manager.transcribe(audio: samples)
                },
                cleanup: {}
            )
        case "parakeet-tdt-v3":
            let models = try await AsrModels.load(from: AsrModels.defaultCacheDirectory(for: .v3), version: .v3)
            let manager = AsrManager()
            try await manager.loadModels(models)
            return LoadedModel(
                transcribe: { samples, language in
                    var decoderState = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
                    let result = try await manager.transcribe(samples, decoderState: &decoderState, language: FluidAudioSTT.parakeetLanguage(for: language))
                    return result.text
                },
                cleanup: {
                    await manager.cleanup()
                }
            )
        case "parakeet-eou":
            throw FluidAudioSTTError.previewOnly(modelID)
        default:
            throw FluidAudioSTTError.unsupportedModel(modelID)
        }
    }
}

public final class FluidAudioSTT: STTEngine, @unchecked Sendable {
    public let id: String
    public let displayName: String
    public let isLocal = true
    public let supportedLanguages = ["auto", "zh", "en"]
    
    private let modelID: String
    private let languageHint: String?
    
    public var status: EngineStatus {
        LocalSTTModelCatalog.isDownloaded(id: modelID) ? .ready : .loading
    }
    
    public init(modelID: String, languageHint: String? = nil) {
        self.modelID = modelID
        self.languageHint = languageHint
        self.id = "fluidaudio_local"
        self.displayName = LocalSTTModelCatalog.descriptor(id: modelID)?.displayName ?? "FluidAudio Local"
    }
    
    public static func isModelReady(_ modelID: String) async -> Bool {
        await FluidAudioSTTRuntime.shared.isLoaded(modelID: modelID)
    }
    
    public static func isModelLoading(_ modelID: String) async -> Bool {
        await FluidAudioSTTRuntime.shared.isLoading(modelID: modelID)
    }
    
    public func load() async throws {
        try await FluidAudioSTTRuntime.shared.preload(modelID: modelID)
    }
    
    public func unload() {
        Task {
            await FluidAudioSTTRuntime.shared.unload(modelID: modelID)
        }
    }
    
    public static func unloadAllModels(except keptModelID: String? = nil) async {
        await FluidAudioSTTRuntime.shared.unloadAll(except: keptModelID)
    }
    
    public func transcribe(_ audio: AudioData, language: String?) async throws -> Transcript {
        let effectiveLanguage = normalizedLanguage(language ?? languageHint)
        let samples = PCM16Audio.decode(audio)
        let text = try await FluidAudioSTTRuntime.shared.transcribe(modelID: modelID, samples: samples, language: effectiveLanguage)
        return Transcript(text: text, language: effectiveLanguage, durationMs: nil, confidence: nil, isFinal: true)
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
    
    private func normalizedLanguage(_ language: String?) -> String? {
        guard let language else { return nil }
        switch language.lowercased() {
        case "auto", "":
            return nil
        case "zh", "zh-hans", "zh-cn":
            return "zh"
        case "en", "en-us", "en-gb":
            return "en"
        default:
            return language
        }
    }
    
    fileprivate static func parakeetLanguage(for language: String?) -> Language? {
        switch language {
        case "en":
            return .english
        default:
            return nil
        }
    }
}

public enum FluidAudioSTTError: LocalizedError {
    case unsupportedModel(String)
    case previewOnly(String)
    case modelNotDownloaded(String)
    
    public var errorDescription: String? {
        switch self {
        case .unsupportedModel(let id):
            return "Unsupported local STT model: \(id)"
        case .previewOnly(let id):
            return "\(id) is marked as a preview-only streaming model right now."
        case .modelNotDownloaded(let id):
            return "Local STT model is not downloaded yet: \(id)"
        }
    }
}
