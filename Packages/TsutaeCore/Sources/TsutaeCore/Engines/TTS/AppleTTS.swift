import AVFoundation
import Foundation

public enum AppleTTSError: LocalizedError {
    case synthesisNotSupported

    public var errorDescription: String? {
        switch self {
        case .synthesisNotSupported:
            return "Apple TTS playback does not expose synthesized audio data in this version."
        }
    }
}

public final class AppleTTSEngine: TTSEngine, @unchecked Sendable {
    public static let shared = AppleTTSEngine()

    public let id = "apple"
    public let displayName = "Apple TTS"
    public let isLocal = true

    public var status: EngineStatus { .ready }

    public var voices: [Voice] {
        AVSpeechSynthesisVoice.speechVoices()
            .map {
                Voice(
                    id: $0.identifier,
                    displayName: $0.name,
                    language: $0.language,
                    isPremium: false
                )
            }
            .sorted {
                if $0.language == $1.language {
                    return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
                return $0.language.localizedCaseInsensitiveCompare($1.language) == .orderedAscending
            }
    }

    private init() {}

    public func synthesize(_ text: String, voice: Voice, options: TTSOptions) async throws -> AudioData {
        throw AppleTTSError.synthesisNotSupported
    }
}
