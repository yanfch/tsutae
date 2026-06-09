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
        router.get("/v1/state") { [controller] _, _ in
            StateResponse(
                state: controller.currentState,
                transcript: controller.currentTranscript,
                spokenText: controller.currentSpokenText,
                speakingSource: controller.currentSpeakingSource
            )
        }
        
        // 读取配置
        router.get("/v1/config") { [controller] _, _ in
            try controller.loadConfig()
        }
        
        // 列出引擎
        router.get("/v1/models") { [controller] _, _ in
            ModelsResponse(
                stt: controller.listSTTEngines(),
                tts: controller.listTTSEngines(),
                vad: controller.listVADEngines()
            )
        }
        
        // 列出配方
        router.get("/v1/recipes") { [controller] _, _ in
            try controller.listRecipes()
        }
        
        // 加载单个配方
        router.get("/v1/recipes/:name") { [controller] request, context in
            let name = try context.parameters.require("name", as: String.self)
            return try controller.loadRecipe(name: name)
        }
        
        // 列出 secrets（只返回名称，不返回值）
        router.get("/v1/secrets") { [controller] _, _ in
            let names = try controller.listSecrets()
            return SecretsListResponse(secrets: names)
        }
        
        // STT - 一次性转写（OpenAI 兼容，占位）
        router.post("/v1/audio/transcriptions") { _, _ -> ErrorResponse in
            throw HTTPServerError.notImplemented("STT not implemented yet")
        }
        
        // TTS - 一次性合成（OpenAI 兼容，占位）
        router.post("/v1/audio/speech") { _, _ -> ErrorResponse in
            throw HTTPServerError.notImplemented("TTS not implemented yet")
        }
        
        // 边车 - 开始监听（占位）
        router.post("/v1/listen") { _, _ -> ErrorResponse in
            throw HTTPServerError.notImplemented("Listen not implemented yet")
        }
        
        // 边车 - 播放 TTS
        router.post("/v1/speak") { [controller] request, context async throws -> TTSSpeakResponse in
            let payload = try await request.decode(as: TTSSpeakRequest.self, context: context)
            return try await controller.speak(payload)
        }
        
        // 边车 - 停止播放
        router.post("/v1/stop") { [controller] _, _ async throws -> TTSStopResponse in
            try await controller.stopSpeaking()
            return TTSStopResponse(ok: true, state: .stopping)
        }
        
        return router
    }
}

// MARK: - 响应类型

struct StateResponse: ResponseEncodable, Codable {
    let state: AppState
    let transcript: String?
    let spokenText: String?
    let speakingSource: String?
}

struct ModelsResponse: ResponseEncodable, Codable {
    let stt: [EngineInfo]
    let tts: [EngineInfo]
    let vad: [EngineInfo]
}

struct SecretsListResponse: ResponseEncodable, Codable {
    let secrets: [String]
}

extension TTSSpeakResponse: ResponseEncodable {}

struct TTSStopResponse: ResponseEncodable, Codable {
    let ok: Bool
    let state: TTSPlaybackState
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
