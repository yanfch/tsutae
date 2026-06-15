import Foundation
import OSLog

public struct ServerHookPayload: Codable, Sendable {
    public let event: Config.ServerHookEvent
    public let text: String?
    public let source: String?
    public let clientId: String?
    public let clientName: String?
    public let language: String?
    public let durationMs: Int?
    public let error: String?
    public let timestamp: String
    public let metadata: [String: String]?

    public init(
        event: Config.ServerHookEvent,
        text: String? = nil,
        source: String? = nil,
        clientId: String? = nil,
        clientName: String? = nil,
        language: String? = nil,
        durationMs: Int? = nil,
        error: String? = nil,
        timestamp: String = ISO8601DateFormatter().string(from: Date()),
        metadata: [String: String]? = nil
    ) {
        self.event = event
        self.text = text
        self.source = source
        self.clientId = clientId
        self.clientName = clientName
        self.language = language
        self.durationMs = durationMs
        self.error = error
        self.timestamp = timestamp
        self.metadata = metadata
    }

    public static func transcribed(_ transcript: Transcript, source: String? = nil) -> ServerHookPayload {
        ServerHookPayload(
            event: .onTranscribed,
            text: transcript.text,
            source: source,
            language: transcript.language,
            durationMs: transcript.durationMs,
            metadata: [
                "isFinal": transcript.isFinal ? "true" : "false",
                "confidence": transcript.confidence.map { String($0) } ?? ""
            ].filter { $0.value.isEmpty == false }
        )
    }

    public static func failure(_ error: Error, source: String) -> ServerHookPayload {
        ServerHookPayload(
            event: .onError,
            source: source,
            error: error.localizedDescription
        )
    }

    public static func test(event: Config.ServerHookEvent) -> ServerHookPayload {
        switch event {
        case .onTranscribed:
            return ServerHookPayload(
                event: event,
                text: "Tsutae hook test transcription.",
                source: "settings.test",
                language: "en",
                durationMs: 1_000
            )
        case .onSpoken:
            return ServerHookPayload(
                event: event,
                text: "Tsutae hook test speech.",
                source: "settings.test"
            )
        case .onError:
            return ServerHookPayload(
                event: event,
                source: "settings.test",
                error: "Tsutae hook test error."
            )
        }
    }

    public func withClient(_ client: Config.ServerClientConfig?) -> ServerHookPayload {
        guard let client else { return self }
        return ServerHookPayload(
            event: event,
            text: text,
            source: source ?? client.name,
            clientId: client.id,
            clientName: client.name,
            language: language,
            durationMs: durationMs,
            error: error,
            timestamp: timestamp,
            metadata: metadata
        )
    }
}

public struct ServerHookResult: Codable, Sendable {
    public let ok: Bool
    public let event: Config.ServerHookEvent
    public let statusCode: Int?
    public let error: String?

    public init(ok: Bool, event: Config.ServerHookEvent, statusCode: Int? = nil, error: String? = nil) {
        self.ok = ok
        self.event = event
        self.statusCode = statusCode
        self.error = error
    }
}

public enum ServerHookError: LocalizedError {
    case disabled(Config.ServerHookEvent)
    case missingURL(Config.ServerHookEvent)
    case invalidURL(String)
    case invalidResponse
    case httpStatus(Int, String?)

    public var errorDescription: String? {
        switch self {
        case .disabled(let event):
            return "\(event.rawValue) hook is disabled."
        case .missingURL(let event):
            return "\(event.rawValue) hook URL is required."
        case .invalidURL(let url):
            return "Invalid hook URL: \(url)"
        case .invalidResponse:
            return "Hook returned an invalid response."
        case .httpStatus(let status, let message):
            if let message, message.isEmpty == false {
                return "Hook failed (\(status)): \(message)"
            }
            return "Hook failed with HTTP \(status)."
        }
    }
}

public enum ServerHookRunner {
    private static let logger = Logger(subsystem: "dev.yanfch.Tsutae", category: "ServerHooks")

    public static func send(
        event: Config.ServerHookEvent,
        hooks: Config.ServerHooksConfig,
        payload: ServerHookPayload,
        session: URLSession = .shared
    ) async throws -> ServerHookResult {
        let endpoint = hooks.endpoint(for: event)
        guard endpoint.enabled else {
            throw ServerHookError.disabled(event)
        }
        let token = try endpoint.tokenRef.flatMap { try SecretsManager.get($0) }
        let request = try makeRequest(endpoint: endpoint, payload: payload, token: token)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ServerHookError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ServerHookError.httpStatus(http.statusCode, extractMessage(from: data))
        }
        logger.info("Server hook delivered. event=\(event.rawValue, privacy: .public) status=\(http.statusCode, privacy: .public)")
        PerformanceLog.record(category: "ServerHooks", message: "Delivered \(event.rawValue) status=\(http.statusCode)")
        return ServerHookResult(ok: true, event: event, statusCode: http.statusCode)
    }

    static func makeRequest(
        endpoint: Config.ServerHookEndpoint,
        payload: ServerHookPayload,
        token: String?
    ) throws -> URLRequest {
        guard let rawURL = endpoint.url?.trimmingCharacters(in: .whitespacesAndNewlines), rawURL.isEmpty == false else {
            throw ServerHookError.missingURL(payload.event)
        }
        guard let url = URL(string: rawURL), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            throw ServerHookError.invalidURL(rawURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = TimeInterval(max(endpoint.timeoutMs, 1_000)) / 1_000
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(payload.event.rawValue, forHTTPHeaderField: "X-Tsutae-Hook-Event")
        if let token = token?.trimmingCharacters(in: .whitespacesAndNewlines), token.isEmpty == false {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    private static func extractMessage(from data: Data) -> String? {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let message = json["message"] as? String { return message }
            if let error = json["error"] as? String { return error }
            if let error = json["error"] as? [String: Any] {
                return error["message"] as? String
            }
        }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
