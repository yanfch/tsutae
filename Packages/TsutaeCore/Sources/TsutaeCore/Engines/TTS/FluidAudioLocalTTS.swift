import FluidAudio
import Foundation
import OSLog

public enum FluidAudioLocalTTSError: LocalizedError {
    case unsupportedVoice(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVoice(let voice):
            return "FluidAudio local TTS does not support voice: \(voice)."
        }
    }
}

enum FluidAudioLocalTTSVoice: String, CaseIterable, Sendable, Hashable {
    case english = "kokoro_ane_english"
    case mandarin = "kokoro_ane_mandarin"

    var displayName: String {
        switch self {
        case .english:
            return "Kokoro ANE English"
        case .mandarin:
            return "Kokoro ANE Mandarin"
        }
    }

    var language: String {
        switch self {
        case .english:
            return "en-US"
        case .mandarin:
            return "zh-CN"
        }
    }

    var variant: KokoroAneVariant {
        switch self {
        case .english:
            return .english
        case .mandarin:
            return .mandarin
        }
    }

    var upstreamVoiceID: String {
        variant.defaultVoice
    }

    var aliases: Set<String> {
        switch self {
        case .english:
            return [rawValue, upstreamVoiceID, "english", "en", "en-US"]
        case .mandarin:
            return [rawValue, upstreamVoiceID, "mandarin", "zh", "zh-CN", "chinese"]
        }
    }

    var warmupText: String {
        switch self {
        case .english:
            return "Tsutae is ready."
        case .mandarin:
            return "本地语音已就绪。"
        }
    }

    static func resolve(voiceID: String?, text: String) -> FluidAudioLocalTTSVoice? {
        guard let voiceID = voiceID?.trimmingCharacters(in: .whitespacesAndNewlines), voiceID.isEmpty == false else {
            return text.containsHanzi ? .mandarin : .english
        }
        let normalized = voiceID.lowercased()
        return allCases.first { voice in
            voice.aliases.map { $0.lowercased() }.contains(normalized)
        }
    }
}

public struct LocalTTSVoiceDescriptor: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let upstreamVoiceID: String
    public let language: String
    public let isDefault: Bool

    public init(
        id: String,
        displayName: String,
        upstreamVoiceID: String,
        language: String,
        isDefault: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.upstreamVoiceID = upstreamVoiceID
        self.language = language
        self.isDefault = isDefault
    }
}

public struct LocalTTSModelDescriptor: Identifiable, Equatable, Sendable {
    public let id: String
    public let voiceID: String
    public let displayName: String
    public let runtime: String
    public let language: String
    public let summary: String
    public let size: String
    public let memory: String
    public let tags: [String]
    public let voices: [LocalTTSVoiceDescriptor]
    public let isRecommended: Bool

    public init(
        id: String,
        voiceID: String,
        displayName: String,
        runtime: String = "FluidAudio",
        language: String,
        summary: String,
        size: String,
        memory: String,
        tags: [String],
        voices: [LocalTTSVoiceDescriptor]? = nil,
        isRecommended: Bool = false
    ) {
        self.id = id
        self.voiceID = voiceID
        self.displayName = displayName
        self.runtime = runtime
        self.language = language
        self.summary = summary
        self.size = size
        self.memory = memory
        self.tags = tags
        self.voices = voices ?? [
            LocalTTSVoiceDescriptor(
                id: voiceID,
                displayName: "Default Voice",
                upstreamVoiceID: voiceID,
                language: language,
                isDefault: true
            )
        ]
        self.isRecommended = isRecommended
    }
}

public enum LocalTTSModelCatalog {
    public static let all: [LocalTTSModelDescriptor] = [
        LocalTTSModelDescriptor(
            id: "kokoro-ane-mandarin",
            voiceID: FluidAudioLocalTTSVoice.mandarin.rawValue,
            displayName: "Kokoro ANE Mandarin",
            language: "zh-CN",
            summary: "Offline Mandarin voice using FluidAudio Kokoro ANE.",
            size: "CoreML bundle",
            memory: "Warmup required",
            tags: ["Mandarin", "Offline", "ANE"],
            voices: [
                LocalTTSVoiceDescriptor(
                    id: FluidAudioLocalTTSVoice.mandarin.rawValue,
                    displayName: "Default Mandarin",
                    upstreamVoiceID: FluidAudioLocalTTSVoice.mandarin.upstreamVoiceID,
                    language: "zh-CN",
                    isDefault: true
                )
            ],
            isRecommended: true
        ),
        LocalTTSModelDescriptor(
            id: "kokoro-ane-english",
            voiceID: FluidAudioLocalTTSVoice.english.rawValue,
            displayName: "Kokoro ANE English",
            language: "en-US",
            summary: "Offline English voice using FluidAudio Kokoro ANE.",
            size: "CoreML bundle",
            memory: "Warmup required",
            tags: ["English", "Offline", "ANE"],
            voices: [
                LocalTTSVoiceDescriptor(
                    id: FluidAudioLocalTTSVoice.english.rawValue,
                    displayName: "Default English",
                    upstreamVoiceID: FluidAudioLocalTTSVoice.english.upstreamVoiceID,
                    language: "en-US",
                    isDefault: true
                )
            ]
        ),
    ]

    public static func descriptor(id: String) -> LocalTTSModelDescriptor? {
        all.first(where: { $0.id == id })
    }

    public static func descriptor(voiceID: String?) -> LocalTTSModelDescriptor? {
        guard let voiceID = voiceID?.trimmingCharacters(in: .whitespacesAndNewlines), voiceID.isEmpty == false else {
            return all.first
        }
        guard let voice = FluidAudioLocalTTSVoice.resolve(voiceID: voiceID, text: "") else {
            return all.first
        }
        return all.first(where: { $0.voiceID == voice.rawValue })
    }

    public static func isKnownVoiceID(_ voiceID: String?) -> Bool {
        guard let voiceID = voiceID?.trimmingCharacters(in: .whitespacesAndNewlines), voiceID.isEmpty == false else {
            return false
        }
        return all.contains { descriptor in
            descriptor.voiceID == voiceID || descriptor.voices.contains { $0.id == voiceID }
        }
    }

    public static func isCached(id: String) -> Bool {
        guard let descriptor = descriptor(id: id),
              let voice = FluidAudioLocalTTSVoice.resolve(voiceID: descriptor.voiceID, text: "") else {
            return false
        }
        do {
            let modelsDirectory = try TtsCacheDirectory.ensure()
                .appendingPathComponent(KokoroAneResourceDownloader.modelsSubdirectory)
            let repoDir = modelsDirectory.appendingPathComponent(voice.variant.repo.folderName)
            let required: Set<String> = voice == .mandarin
                ? ModelNames.KokoroAne.requiredModelsZh
                : ModelNames.KokoroAne.requiredModels
            return required.allSatisfy { name in
                FileManager.default.fileExists(atPath: repoDir.appendingPathComponent(name).path)
            }
        } catch {
            return false
        }
    }
}

public final class FluidAudioLocalTTSEngine: TTSEngine, @unchecked Sendable {
    public static let shared = FluidAudioLocalTTSEngine()

    public let id = "fluidaudio_local_tts"
    public let displayName = "FluidAudio Local TTS"
    public let isLocal = true

    public var status: EngineStatus { .ready }

    public var voices: [Voice] {
        FluidAudioLocalTTSVoice.allCases.map {
            Voice(
                id: $0.rawValue,
                displayName: "\($0.displayName) · \($0.upstreamVoiceID)",
                language: $0.language
            )
        }
    }

    private let runtime = FluidAudioLocalTTSRuntime()

    private init() {}

    public func synthesize(_ text: String, voice: Voice, options: TTSOptions) async throws -> AudioData {
        try await synthesize(text, voiceID: voice.id, rate: options.rate)
    }

    public func synthesize(_ text: String, voiceID: String?, rate: Double = 1.0) async throws -> AudioData {
        guard let voice = FluidAudioLocalTTSVoice.resolve(voiceID: voiceID, text: text) else {
            throw FluidAudioLocalTTSError.unsupportedVoice(voiceID ?? "")
        }
        return try await runtime.synthesize(text: text, voice: voice, rate: rate)
    }

    @discardableResult
    public func prewarm(voiceID: String?) async throws -> String {
        let voice = FluidAudioLocalTTSVoice.resolve(voiceID: voiceID, text: "") ?? .mandarin
        try await runtime.prewarm(voice: voice)
        return voice.rawValue
    }

    public func isVoiceReady(_ voiceID: String?) async -> Bool {
        let voice = FluidAudioLocalTTSVoice.resolve(voiceID: voiceID, text: "") ?? .mandarin
        return await runtime.isWarmed(voice: voice)
    }

    public func load() async throws {
        try await runtime.prewarm(voice: .english)
    }

    public func unload() {
        Task {
            await runtime.unload()
        }
    }
}

private actor FluidAudioLocalTTSRuntime {
    private var managers: [FluidAudioLocalTTSVoice: KokoroAneManager] = [:]
    private var warmedVoices: Set<FluidAudioLocalTTSVoice> = []
    private let logger = Logger(subsystem: "dev.yanfch.Tsutae", category: "FluidAudioLocalTTS")

    func manager(for voice: FluidAudioLocalTTSVoice) async throws -> KokoroAneManager {
        if let manager = managers[voice] {
            return manager
        }
        let startedAt = Date()
        record("TTS local model load started. voice=\(voice.rawValue) upstream_voice=\(voice.upstreamVoiceID)")
        let manager = KokoroAneManager(variant: voice.variant, defaultVoice: voice.upstreamVoiceID)
        try await manager.initialize(preloadVoices: [voice.upstreamVoiceID])
        managers[voice] = manager
        record("TTS local model load finished. voice=\(voice.rawValue) elapsed_ms=\(formatElapsedMs(since: startedAt))")
        return manager
    }

    func prewarm(voice: FluidAudioLocalTTSVoice) async throws {
        if warmedVoices.contains(voice) {
            return
        }
        let startedAt = Date()
        record("TTS local model warmup started. voice=\(voice.rawValue)")
        let manager = try await manager(for: voice)
        _ = try await manager.synthesize(text: voice.warmupText, voice: voice.upstreamVoiceID, speed: 1.0)
        warmedVoices.insert(voice)
        record("TTS local model warmup finished. voice=\(voice.rawValue) elapsed_ms=\(formatElapsedMs(since: startedAt))")
    }

    func isWarmed(voice: FluidAudioLocalTTSVoice) -> Bool {
        warmedVoices.contains(voice)
    }

    func synthesize(text: String, voice: FluidAudioLocalTTSVoice, rate: Double) async throws -> AudioData {
        let manager = try await manager(for: voice)
        let speed = Float(max(0.5, min(rate, 2.0)))
        let data = try await manager.synthesize(text: text, voice: voice.upstreamVoiceID, speed: speed)
        warmedVoices.insert(voice)
        return AudioData(
            samples: data,
            sampleRate: KokoroAneConstants.sampleRate,
            channels: 1,
            container: .wav
        )
    }

    func unload() async {
        let loaded = managers.values
        managers.removeAll()
        warmedVoices.removeAll()
        for manager in loaded {
            await manager.cleanup()
        }
    }

    private func record(_ message: String) {
        logger.info("\(message, privacy: .public)")
        PerformanceLog.record(category: "FluidAudioLocalTTS", message: message)
    }

    private func formatElapsedMs(since start: Date) -> String {
        String(format: "%.1f", Date().timeIntervalSince(start) * 1000)
    }
}

private extension String {
    var containsHanzi: Bool {
        unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
        }
    }
}
