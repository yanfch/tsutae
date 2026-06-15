import Foundation
import Hummingbird
import NIOCore

/// tsutae HTTP 服务器
/// 对应文档: gui-tui/docs/01-voicebar.md (§对外 API)
///
/// 使用依赖注入 AppController，方便测试
public final class HTTPServer: @unchecked Sendable {
    
    private let controller: AppControllerProtocol
    
    /// 服务器是否运行中
    private(set) var isRunning = false
    
    /// 初始化
    /// - Parameter controller: 应用控制器（可注入 mock）
    public init(controller: AppControllerProtocol) {
        self.controller = controller
    }
    
    /// 启动服务器
    /// - Parameters:
    ///   - host: 绑定地址
    ///   - port: 端口
    public func start(host: String = "127.0.0.1", port: Int = 1338) async throws {
        let router = buildRouter()
        let app = Application(
            responder: router.buildResponder(),
            configuration: .init(address: .hostname(host, port: port))
        )
        
        isRunning = true
        try await app.run()
    }
    
    /// 停止服务器
    public func stop() {
        isRunning = false
    }
    
    /// 构建路由（内部方法，可单独测试）
    func buildRouter() -> Router<BasicRequestContext> {
        let router = Router()
        
        // 健康检查
        router.get("/health") { [controller] _, _ in
            controller.healthCheck()
        }
        
        // 当前状态
        router.get("/v1/state") { [self, controller] request, _ in
            _ = try authenticatedClient(for: request, scope: .state)
            return StateResponse(
                state: controller.currentState,
                transcript: controller.currentTranscript,
                spokenText: controller.currentSpokenText,
                speakingSource: controller.currentSpeakingSource,
                ttsPlayback: controller.ttsPlaybackSnapshot
            )
        }
        
        // 读取配置
        router.get("/v1/config") { [self, controller] request, _ in
            _ = try authenticatedClient(for: request, scope: .configRead)
            return try controller.loadConfig()
        }
        
        // 列出引擎
        router.get("/v1/models") { [self, controller] request, _ in
            _ = try authenticatedClient(for: request, scope: .models)
            return ModelsResponse(
                stt: controller.listSTTEngines(),
                tts: controller.listTTSEngines(),
                vad: controller.listVADEngines()
            )
        }

        // TTS - 列出音色
        router.get("/v1/tts/voices") { [self, controller] request, _ in
            _ = try authenticatedClient(for: request, scope: .models)
            let engineID = request.uri.queryParameters.get("engine")
            return TTSVoicesResponse(engines: controller.listTTSVoices(engineID: engineID))
        }
        
        // 列出配方
        router.get("/v1/recipes") { [self, controller] request, _ in
            _ = try authenticatedClient(for: request, scope: .recipes)
            return try controller.listRecipes()
        }
        
        // 加载单个配方
        router.get("/v1/recipes/:name") { [self, controller] request, context in
            _ = try authenticatedClient(for: request, scope: .recipes)
            let name = try context.parameters.require("name", as: String.self)
            return try controller.loadRecipe(name: name)
        }
        
        // 列出 secrets（只返回名称，不返回值）
        router.get("/v1/secrets") { [self, controller] request, _ in
            _ = try authenticatedClient(for: request, scope: .secrets)
            let names = try controller.listSecrets()
            return SecretsListResponse(secrets: names)
        }
        
        // STT - 一次性转写（OpenAI 兼容）
        router.post("/v1/audio/transcriptions") { [self, controller] request, _ async throws -> Response in
            let client = try authenticatedClient(for: request, scope: .transcribe)
            var request = request
            let upload = try await STTTranscriptionUpload.decode(from: &request)
            let transcript = try await controller.transcribe(upload.request, client: client)
            return try upload.response(for: transcript)
        }
        
        // TTS - 一次性合成（OpenAI 兼容，本地代理导出）
        router.post("/v1/audio/speech") { [self, controller] request, context async throws -> AudioSpeechBinaryResponse in
            _ = try authenticatedClient(for: request, scope: .audioSpeech)
            let payload = try await request.decode(as: TTSAudioSpeechRequest.self, context: context)
            let config = try controller.loadConfig()
            let audio = try await TTSPlaybackManager.shared.synthesizeSpeech(payload, config: config.tts)
            return AudioSpeechBinaryResponse(audio: audio)
        }
        
        // 边车 - 开始监听（占位）
        router.post("/v1/listen") { [self] request, _ -> ErrorResponse in
            _ = try authenticatedClient(for: request, scope: .listen)
            throw HTTPServerError.notImplemented("Listen not implemented yet")
        }
        
        // 边车 - 播放 TTS
        router.post("/v1/speak") { [self, controller] request, context async throws -> TTSSpeakResponse in
            let client = try authenticatedClient(for: request, scope: .speak)
            let payload = try await request.decode(as: TTSSpeakRequest.self, context: context)
            return try await controller.speak(payload, client: client)
        }

        // 边车 - 播报/系统通知
        router.post("/v1/notify") { [self, controller] request, context async throws -> TTSNotifyResponse in
            let client = try authenticatedClient(for: request, scope: .notify)
            let payload = try await request.decode(as: TTSNotifyRequest.self, context: context)
            return try await controller.notify(payload, client: client)
        }
        
        // 边车 - 停止播放
        router.post("/v1/stop") { [self, controller] request, _ async throws -> TTSStopResponse in
            _ = try authenticatedClient(for: request, scope: .stop)
            try await controller.stopSpeaking()
            return TTSStopResponse(ok: true, state: .stopping)
        }
        
        return router
    }

    private func authenticatedClient(
        for request: Request,
        scope: Config.ServerClientScope
    ) throws -> Config.ServerClientConfig? {
        let config = try controller.loadConfig()
        do {
            return try ServerClientRegistry.authenticate(
                token: request.bearerToken,
                requiredScope: scope,
                server: config.server
            )
        } catch ServerClientAuthError.missingToken, ServerClientAuthError.invalidToken {
            throw HTTPError(.unauthorized, message: "Invalid or missing bearer token.")
        } catch ServerClientAuthError.disabledClient(let name) {
            throw HTTPError(.forbidden, message: "Client is disabled: \(name).")
        } catch ServerClientAuthError.insufficientScope(let name, let missingScope) {
            throw HTTPError(.forbidden, message: "Client \(name) is missing scope: \(missingScope.rawValue).")
        }
    }
}

// MARK: - 响应类型

struct StateResponse: ResponseEncodable, Codable {
    let state: AppState
    let transcript: String?
    let spokenText: String?
    let speakingSource: String?
    let ttsPlayback: TTSPlaybackSnapshot
}

struct ModelsResponse: ResponseEncodable, Codable {
    let stt: [EngineInfo]
    let tts: [EngineInfo]
    let vad: [EngineInfo]
}

struct TTSVoicesResponse: ResponseEncodable, Codable {
    let engines: [TTSVoiceEngineInfo]
}

struct SecretsListResponse: ResponseEncodable, Codable {
    let secrets: [String]
}

extension TTSSpeakResponse: ResponseEncodable {}
extension TTSNotifyResponse: ResponseEncodable {}

struct TTSStopResponse: ResponseEncodable, Codable {
    let ok: Bool
    let state: TTSPlaybackState
}

struct AudioSpeechBinaryResponse: ResponseGenerator {
    let audio: AudioData

    func response(from request: Request, context: some RequestContext) throws -> Response {
        var response = Response(status: .ok)
        response.headers[.contentType] = contentType(for: audio.container)
        response.headers[.contentDisposition] = "attachment; filename=tsutae-tts.\(fileExtension(for: audio.container))"
        response.body = .init(byteBuffer: ByteBuffer(data: audio.samples))
        return response
    }

    private func contentType(for container: AudioContainerFormat) -> String {
        switch container {
        case .wav:
            return "audio/wav"
        case .mp3:
            return "audio/mpeg"
        case .m4a:
            return "audio/mp4"
        case .pcm16:
            return "audio/L16"
        }
    }

    private func fileExtension(for container: AudioContainerFormat) -> String {
        switch container {
        case .wav:
            return "wav"
        case .mp3:
            return "mp3"
        case .m4a:
            return "m4a"
        case .pcm16:
            return "pcm"
        }
    }
}

// MARK: - HTTP 错误响应

struct ErrorResponse: ResponseEncodable, Codable {
    let error: String
    let message: String
}

// MARK: - HTTP 错误

enum HTTPServerError: Error {
    case notImplemented(String)
    case badRequest(String)
    case notFound(String)
    case internalError(String)
}

private extension Request {
    var bearerToken: String? {
        guard let authorization = headers[.authorization]?.trimmingCharacters(in: .whitespacesAndNewlines),
              authorization.isEmpty == false else {
            return nil
        }
        if authorization.lowercased().hasPrefix("bearer ") {
            let token = authorization.dropFirst("bearer ".count)
            return token.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return authorization
    }
}
