import Foundation

/// OpenAI-compatible transcription client.
///
/// Supports both:
/// - OpenAI-style `POST /v1/audio/transcriptions` multipart uploads
/// - Xiaomi MiMo ASR-style `POST /v1/chat/completions` JSON audio input
public final class OpenAICompatibleSTT: STTEngine, @unchecked Sendable {
    
    public let id: String
    public let displayName: String
    public let isLocal: Bool
    public let supportedLanguages: [String]
    
    private let baseURL: URL
    private let model: String
    private let apiKey: String?
    private let session: URLSessionProtocol
    private let requestStyle: OpenAICompatibleRequestStyle
    
    public var status: EngineStatus { .ready }
    
    public init(
        id: String = "openai_compatible",
        displayName: String = "OpenAI Compatible STT",
        baseURL: URL = URL(string: "http://127.0.0.1:1337")!,
        model: String = "xiaomi/mimo-v2.5",
        apiKey: String? = nil,
        isLocal: Bool = false,
        supportedLanguages: [String] = [],
        requestStyle: OpenAICompatibleRequestStyle = .auto,
        session: URLSessionProtocol = URLSession.shared
    ) {
        self.id = id
        self.displayName = displayName
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.isLocal = isLocal
        self.supportedLanguages = supportedLanguages
        self.requestStyle = requestStyle
        self.session = session
    }
    
    public func transcribe(_ audio: AudioData, language: String?) async throws -> Transcript {
        switch resolvedRequestStyle {
        case .audioTranscriptions:
            return try await transcribeViaAudioTranscriptions(audio, language: language)
        case .chatCompletionsAudio:
            return try await transcribeViaChatCompletions(audio, language: language)
        case .auto:
            fatalError("resolvedRequestStyle must not be .auto")
        }
    }
    
    public func stream(
        _ audio: AsyncStream<AudioChunk>,
        language: String?
    ) -> AsyncThrowingStream<TranscriptUpdate, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var samples = Data()
                for await chunk in audio {
                    samples.append(chunk.samples)
                }
                
                do {
                    let transcript = try await transcribe(AudioData(samples: samples), language: language)
                    continuation.yield(.final(transcript))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    private var resolvedRequestStyle: OpenAICompatibleRequestStyle {
        switch requestStyle {
        case .auto:
            if baseURL.host?.localizedCaseInsensitiveContains("xiaomimimo.com") == true || model == "mimo-v2.5-asr" {
                return .chatCompletionsAudio
            }
            return .audioTranscriptions
        case .audioTranscriptions, .chatCompletionsAudio:
            return requestStyle
        }
    }
    
    private func transcribeViaAudioTranscriptions(_ audio: AudioData, language: String?) async throws -> Transcript {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: endpointURL(for: .audioTranscriptions))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        applyAuthorization(to: &request)
        
        let wav = try WAVEncoder.encode(audio)
        request.httpBody = MultipartFormData(boundary: boundary)
            .addField(name: "model", value: model)
            .addOptionalField(name: "language", value: language)
            .addFile(
                name: "file",
                filename: "audio.wav",
                contentType: "audio/wav",
                data: wav
            )
            .finalize()
        
        let (data, response) = try await session.data(for: request)
        let http = try validatedHTTPResponse(response, data: data)
        _ = http
        
        let decoded = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        return Transcript(
            text: decoded.text,
            language: decoded.language,
            durationMs: decoded.duration.map { Int($0 * 1000) },
            confidence: nil,
            isFinal: true
        )
    }
    
    private func transcribeViaChatCompletions(_ audio: AudioData, language: String?) async throws -> Transcript {
        var request = URLRequest(url: endpointURL(for: .chatCompletionsAudio))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthorization(to: &request)
        
        let wav = try WAVEncoder.encode(audio)
        let dataURL = "data:audio/wav;base64,\(wav.base64EncodedString())"
        let body = ChatCompletionsAudioRequest(
            model: model,
            messages: [
                .init(
                    role: "user",
                    content: [
                        .init(type: "input_audio", inputAudio: .init(data: dataURL))
                    ]
                )
            ],
            asrOptions: .init(language: language ?? "auto")
        )
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await session.data(for: request)
        let http = try validatedHTTPResponse(response, data: data)
        _ = http
        
        let decoded = try JSONDecoder().decode(ChatCompletionsResponse.self, from: data)
        guard let text = decoded.choices.first?.message.contentText?.trimmingCharacters(in: .whitespacesAndNewlines), text.isEmpty == false else {
            throw OpenAICompatibleSTTError.invalidResponse
        }
        
        return Transcript(
            text: text,
            language: language,
            durationMs: nil,
            confidence: nil,
            isFinal: true
        )
    }
    
    private func endpointURL(for style: OpenAICompatibleRequestStyle) -> URL {
        let fullSuffix: String
        let v1Suffix: String
        
        switch style {
        case .audioTranscriptions:
            fullSuffix = "/v1/audio/transcriptions"
            v1Suffix = "/audio/transcriptions"
        case .chatCompletionsAudio:
            fullSuffix = "/v1/chat/completions"
            v1Suffix = "/chat/completions"
        case .auto:
            return endpointURL(for: resolvedRequestStyle)
        }
        
        var absolute = baseURL.absoluteString
        while absolute.hasSuffix("/") {
            absolute.removeLast()
        }
        
        if absolute.hasSuffix(fullSuffix) || absolute.hasSuffix(v1Suffix) {
            return URL(string: absolute)!
        }
        if absolute.hasSuffix("/v1") {
            return URL(string: absolute + v1Suffix)!
        }
        return URL(string: absolute + fullSuffix)!
    }
    
    private func applyAuthorization(to request: inout URLRequest) {
        guard let apiKey, apiKey.isEmpty == false else { return }
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if usesXiaomiAPIKeyHeader {
            request.setValue(apiKey, forHTTPHeaderField: "api-key")
        }
    }
    
    private var usesXiaomiAPIKeyHeader: Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return host.contains("xiaomimimo.com")
    }
    
    @discardableResult
    private func validatedHTTPResponse(_ response: URLResponse, data: Data) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else {
            throw OpenAICompatibleSTTError.invalidResponse
        }
        
        guard (200..<300).contains(http.statusCode) else {
            let message = OpenAICompatibleSTTError.extractErrorMessage(from: data)
            throw OpenAICompatibleSTTError.httpStatus(http.statusCode, message)
        }
        
        return http
    }
}

public enum OpenAICompatibleRequestStyle: Sendable {
    case auto
    case audioTranscriptions
    case chatCompletionsAudio
}

public protocol URLSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

private struct TranscriptionResponse: Decodable {
    let text: String
    let language: String?
    let duration: Double?
}

private struct ChatCompletionsAudioRequest: Encodable {
    let model: String
    let messages: [Message]
    let asrOptions: AsrOptions
    
    struct Message: Encodable {
        let role: String
        let content: [ContentPart]
    }
    
    struct ContentPart: Encodable {
        let type: String
        let inputAudio: InputAudio
        
        enum CodingKeys: String, CodingKey {
            case type
            case inputAudio = "input_audio"
        }
    }
    
    struct InputAudio: Encodable {
        let data: String
    }
    
    struct AsrOptions: Encodable {
        let language: String
    }
    
    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case asrOptions = "asr_options"
    }
}

private struct ChatCompletionsResponse: Decodable {
    let choices: [Choice]
    
    struct Choice: Decodable {
        let message: Message
    }
    
    struct Message: Decodable {
        let content: ContentValue
        
        var contentText: String? {
            content.text
        }
    }
    
    enum ContentValue: Decodable {
        case string(String)
        case parts([Part])
        
        struct Part: Decodable {
            let type: String?
            let text: String?
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                self = .string(string)
                return
            }
            self = .parts(try container.decode([Part].self))
        }
        
        var text: String? {
            switch self {
            case .string(let value):
                return value
            case .parts(let parts):
                let combined = parts.compactMap(\.text).joined(separator: " ")
                return combined.isEmpty ? nil : combined
            }
        }
    }
}

public enum OpenAICompatibleSTTError: LocalizedError, Sendable {
    case invalidResponse
    case invalidAudioFormat(String)
    case httpStatus(Int, String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid transcription response"
        case .invalidAudioFormat(let message):
            return message
        case .httpStatus(let status, let message):
            return "Transcription request failed (\(status)): \(message)"
        }
    }
    
    static func extractErrorMessage(from data: Data) -> String {
        guard let decoded = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) else {
            return String(data: data, encoding: .utf8) ?? "Unknown error"
        }
        return decoded.error.message
    }
}

private struct ErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String
    }
    
    let error: APIError
}

struct MultipartFormData {
    private let boundary: String
    private var body = Data()
    
    init(boundary: String) {
        self.boundary = boundary
    }
    
    func addField(name: String, value: String) -> MultipartFormData {
        var copy = self
        copy.append("--\(boundary)\r\n")
        copy.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        copy.append("\(value)\r\n")
        return copy
    }
    
    func addOptionalField(name: String, value: String?) -> MultipartFormData {
        guard let value, !value.isEmpty else { return self }
        return addField(name: name, value: value)
    }
    
    func addFile(name: String, filename: String, contentType: String, data: Data) -> MultipartFormData {
        var copy = self
        copy.append("--\(boundary)\r\n")
        copy.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        copy.append("Content-Type: \(contentType)\r\n\r\n")
        copy.body.append(data)
        copy.append("\r\n")
        return copy
    }
    
    func finalize() -> Data {
        var copy = self
        copy.append("--\(boundary)--\r\n")
        return copy.body
    }
    
    private mutating func append(_ string: String) {
        body.append(Data(string.utf8))
    }
}

public enum WAVEncoder {
    public static func encode(_ audio: AudioData) throws -> Data {
        guard audio.channels > 0 else {
            throw OpenAICompatibleSTTError.invalidAudioFormat("Audio channel count must be greater than zero")
        }
        
        guard audio.sampleRate > 0 else {
            throw OpenAICompatibleSTTError.invalidAudioFormat("Audio sample rate must be greater than zero")
        }
        
        var data = Data()
        let byteRate = audio.sampleRate * audio.channels * 2
        let blockAlign = audio.channels * 2
        let fileSizeMinus8 = UInt32(36 + audio.samples.count)
        let sampleDataSize = UInt32(audio.samples.count)
        
        data.appendASCII("RIFF")
        data.appendLE(fileSizeMinus8)
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendLE(UInt32(16))
        data.appendLE(UInt16(1))
        data.appendLE(UInt16(audio.channels))
        data.appendLE(UInt32(audio.sampleRate))
        data.appendLE(UInt32(byteRate))
        data.appendLE(UInt16(blockAlign))
        data.appendLE(UInt16(16))
        data.appendASCII("data")
        data.appendLE(sampleDataSize)
        data.append(audio.samples)
        
        return data
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(Data(string.utf8))
    }
    
    mutating func appendLE(_ value: UInt16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
    
    mutating func appendLE(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
