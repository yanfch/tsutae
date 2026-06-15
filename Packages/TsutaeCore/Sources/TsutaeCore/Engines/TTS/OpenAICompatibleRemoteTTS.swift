import Foundation

public enum OpenAICompatibleRemoteTTSError: LocalizedError {
    case invalidConfiguration
    case invalidResponse
    case missingAudioData
    case httpStatus(Int, String?)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Remote TTS configuration is incomplete."
        case .invalidResponse:
            return "Remote TTS returned an invalid response."
        case .missingAudioData:
            return "Remote TTS did not return playable audio data."
        case .httpStatus(let code, let message):
            if let message, message.isEmpty == false {
                return "Remote TTS failed (\(code)): \(message)"
            }
            return "Remote TTS failed with HTTP \(code)."
        }
    }
}

public final class OpenAICompatibleRemoteTTSEngine: TTSEngine, @unchecked Sendable {
    public static let shared = OpenAICompatibleRemoteTTSEngine()

    public let id = "openai_compatible_remote_tts"
    public let displayName = "OpenAI-Compatible Remote TTS"
    public let isLocal = false

    public var status: EngineStatus { .ready }
    public var voices: [Voice] { [] }

    private init() {}

    public func synthesize(_ text: String, voice: Voice, options: TTSOptions) async throws -> AudioData {
        throw OpenAICompatibleRemoteTTSError.invalidConfiguration
    }

    public func synthesize(
        _ text: String,
        voiceID: String?,
        instructions: String? = nil,
        config: Config.TTSConfig,
        apiKeyOverride: String? = nil,
        session: URLSession = .shared
    ) async throws -> AudioData {
        guard config.remote.enabled,
              let baseURLString = config.remote.baseURL,
              let model = config.remote.model,
              let baseURL = URL(string: baseURLString),
              model.isEmpty == false else {
            throw OpenAICompatibleRemoteTTSError.invalidConfiguration
        }

        let apiKey: String?
        if let override = apiKeyOverride?.nilIfBlank {
            apiKey = override
        } else {
            apiKey = try config.remote.apiKeyRef.flatMap { try SecretsManager.get($0) }
        }
        let resolvedInstructions = instructions?.nilIfBlank ?? config.remote.instructions?.nilIfBlank
        switch resolvedRequestStyle(config.remote.requestStyle, baseURL: baseURL, model: model) {
        case .audioSpeech:
            return try await synthesizeViaAudioSpeech(
                text,
                voiceID: voiceID,
                instructions: resolvedInstructions,
                model: model,
                baseURL: baseURL,
                apiKey: apiKey,
                session: session
            )
        case .chatCompletionsAudio:
            return try await synthesizeViaChatCompletions(
                text,
                voiceID: voiceID,
                instructions: resolvedInstructions,
                model: model,
                baseURL: baseURL,
                apiKey: apiKey,
                session: session
            )
        }
    }

    private func synthesizeViaAudioSpeech(
        _ text: String,
        voiceID: String?,
        instructions: String?,
        model: String,
        baseURL: URL,
        apiKey: String?,
        session: URLSession
    ) async throws -> AudioData {
        var request = URLRequest(url: endpointURL(baseURL: baseURL, style: .audioSpeech))
        request.timeoutInterval = 75
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthorization(apiKey: apiKey, baseURL: baseURL, request: &request)
        request.httpBody = try JSONEncoder().encode(AudioSpeechRequest(
            model: model,
            input: text,
            voice: voiceID?.nilIfBlank ?? "alloy",
            instructions: instructions,
            responseFormat: "wav"
        ))

        let (data, response) = try await session.data(for: request)
        _ = try validated(response: response, data: data)
        return AudioData(samples: data, sampleRate: 24000, channels: 1, container: .wav)
    }

    private func synthesizeViaChatCompletions(
        _ text: String,
        voiceID: String?,
        instructions: String?,
        model: String,
        baseURL: URL,
        apiKey: String?,
        session: URLSession
    ) async throws -> AudioData {
        var request = URLRequest(url: endpointURL(baseURL: baseURL, style: .chatCompletionsAudio))
        request.timeoutInterval = 75
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthorization(apiKey: apiKey, baseURL: baseURL, request: &request)

        var messages: [ChatCompletionsAudioRequest.Message] = []
        if let instructions = instructions?.trimmingCharacters(in: .whitespacesAndNewlines), instructions.isEmpty == false {
            messages.append(.init(role: "user", content: instructions))
        }
        messages.append(.init(role: "assistant", content: text))

        request.httpBody = try JSONEncoder().encode(ChatCompletionsAudioRequest(
            model: model,
            messages: messages,
            audio: .init(format: "wav", voice: voiceID?.nilIfBlank ?? "mimo_default")
        ))

        let (data, response) = try await session.data(for: request)
        _ = try validated(response: response, data: data)

        let decoded = try JSONDecoder().decode(ChatCompletionsAudioResponse.self, from: data)
        guard let base64 = decoded.choices.first?.message.audio?.data,
              let audioData = Data(base64Encoded: base64) else {
            throw OpenAICompatibleRemoteTTSError.missingAudioData
        }
        return AudioData(samples: audioData, sampleRate: 24000, channels: 1, container: .wav)
    }

    private func endpointURL(baseURL: URL, style: Config.TTSRemoteRequestStyle) -> URL {
        let fullSuffix: String
        let v1Suffix: String
        switch style {
        case .audioSpeech:
            fullSuffix = "/v1/audio/speech"
            v1Suffix = "/audio/speech"
        case .chatCompletionsAudio:
            fullSuffix = "/v1/chat/completions"
            v1Suffix = "/chat/completions"
        }

        var absolute = baseURL.absoluteString
        while absolute.hasSuffix("/") { absolute.removeLast() }
        if absolute.hasSuffix(fullSuffix) || absolute.hasSuffix(v1Suffix) {
            return URL(string: absolute)!
        }
        if absolute.hasSuffix("/v1") {
            return URL(string: absolute + v1Suffix)!
        }
        return URL(string: absolute + fullSuffix)!
    }

    private func resolvedRequestStyle(_ style: Config.TTSRemoteRequestStyle, baseURL: URL, model: String) -> Config.TTSRemoteRequestStyle {
        switch style {
        case .audioSpeech:
            return .audioSpeech
        case .chatCompletionsAudio:
            return .chatCompletionsAudio
        }
    }

    private func applyAuthorization(apiKey: String?, baseURL: URL, request: inout URLRequest) {
        guard let apiKey, apiKey.isEmpty == false else { return }
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if baseURL.host?.lowercased().contains("xiaomimimo.com") == true {
            request.setValue(apiKey, forHTTPHeaderField: "api-key")
        }
    }

    @discardableResult
    private func validated(response: URLResponse, data: Data) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else {
            throw OpenAICompatibleRemoteTTSError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OpenAICompatibleRemoteTTSError.httpStatus(http.statusCode, extractErrorMessage(from: data))
        }
        return http
    }

    private func extractErrorMessage(from data: Data) -> String? {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? [String: Any] {
                return error["message"] as? String ?? error["error"] as? String
            }
            if let message = json["message"] as? String { return message }
            if let error = json["error"] as? String { return error }
        }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct AudioSpeechRequest: Encodable {
    let model: String
    let input: String
    let voice: String
    let instructions: String?
    let responseFormat: String

    enum CodingKeys: String, CodingKey {
        case model, input, voice
        case responseFormat = "response_format"
    }
}

private struct ChatCompletionsAudioRequest: Encodable {
    let model: String
    let messages: [Message]
    let audio: Audio

    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct Audio: Encodable {
        let format: String
        let voice: String
    }
}

private struct ChatCompletionsAudioResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let audio: Audio?
    }

    struct Audio: Decodable {
        let data: String
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
