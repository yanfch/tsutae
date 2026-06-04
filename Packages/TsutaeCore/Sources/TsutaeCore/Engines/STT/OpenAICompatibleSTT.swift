import Foundation

/// OpenAI-compatible transcription client.
///
/// Default target is osaurus at `http://127.0.0.1:1337/v1/audio/transcriptions`.
public final class OpenAICompatibleSTT: STTEngine, @unchecked Sendable {
    
    public let id: String
    public let displayName: String
    public let isLocal: Bool
    public let supportedLanguages: [String]
    
    private let baseURL: URL
    private let model: String
    private let apiKey: String?
    private let session: URLSessionProtocol
    
    public var status: EngineStatus { .ready }
    
    public init(
        id: String = "openai_compatible",
        displayName: String = "OpenAI Compatible STT",
        baseURL: URL = URL(string: "http://127.0.0.1:1337")!,
        model: String = "xiaomi/mimo-v2.5",
        apiKey: String? = nil,
        isLocal: Bool = false,
        supportedLanguages: [String] = [],
        session: URLSessionProtocol = URLSession.shared
    ) {
        self.id = id
        self.displayName = displayName
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.isLocal = isLocal
        self.supportedLanguages = supportedLanguages
        self.session = session
    }
    
    public func transcribe(_ audio: AudioData, language: String?) async throws -> Transcript {
        let boundary = "Boundary-\(UUID().uuidString)"
        let url = baseURL.appendingPathComponent("v1/audio/transcriptions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
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
        guard let http = response as? HTTPURLResponse else {
            throw OpenAICompatibleSTTError.invalidResponse
        }
        
        guard (200..<300).contains(http.statusCode) else {
            let message = OpenAICompatibleSTTError.extractErrorMessage(from: data)
            throw OpenAICompatibleSTTError.httpStatus(http.statusCode, message)
        }
        
        let decoded = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        return Transcript(
            text: decoded.text,
            language: decoded.language,
            durationMs: decoded.duration.map { Int($0 * 1000) },
            confidence: nil,
            isFinal: true
        )
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
        guard
            let decoded = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
        else {
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
