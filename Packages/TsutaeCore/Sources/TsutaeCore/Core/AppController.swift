import Foundation

/// 应用控制器协议 — 业务逻辑层
/// 所有核心操作都通过此协议暴露，方便 mock 测试
public protocol AppControllerProtocol: Sendable {
    
    // MARK: - 状态
    
    /// 当前应用状态
    var currentState: AppState { get }
    
    /// 当前转写文本
    var currentTranscript: String? { get }
    
    // MARK: - 配置
    
    /// 加载配置
    func loadConfig() throws -> Config
    
    /// 保存配置
    func saveConfig(_ config: Config) throws
    
    // MARK: - 引擎
    
    /// 列出所有 STT 引擎
    func listSTTEngines() -> [EngineInfo]
    
    /// 列出所有 TTS 引擎
    func listTTSEngines() -> [EngineInfo]
    
    /// 列出所有 VAD 引擎
    func listVADEngines() -> [EngineInfo]
    
    // MARK: - Secrets
    
    /// 保存 secret
    func setSecret(_ name: String, value: String) throws
    
    /// 读取 secret
    func getSecret(_ name: String) throws -> String?
    
    /// 删除 secret
    func deleteSecret(_ name: String) throws
    
    /// 列出所有 secret 名称
    func listSecrets() throws -> [String]
    
    // MARK: - Recipes
    
    /// 列出所有配方
    func listRecipes() throws -> [Recipe]
    
    /// 按名称加载配方
    func loadRecipe(name: String) throws -> Recipe
    
    /// 安装内置配方
    func installBuiltinRecipes() throws
    
    // MARK: - Hotkeys
    
    /// 加载快捷键配置
    func loadHotkeys() throws -> HotkeysConfig
    
    /// 保存快捷键配置
    func saveHotkeys(_ config: HotkeysConfig) throws
    
    // MARK: - 健康检查
    
    /// 健康检查
    func healthCheck() -> HealthStatus
}

/// 健康状态
public struct HealthStatus: Codable, Sendable {
    public let status: String
    public let version: String
    public let engines: EngineHealth
    
    public init(status: String, version: String, engines: EngineHealth) {
        self.status = status
        self.version = version
        self.engines = engines
    }
}

/// 引擎健康状态
public struct EngineHealth: Codable, Sendable {
    public let stt: Int  // 可用数量
    public let tts: Int
    public let vad: Int
    
    public init(stt: Int, tts: Int, vad: Int) {
        self.stt = stt
        self.tts = tts
        self.vad = vad
    }
}

/// 应用状态
public enum AppState: String, Codable, Sendable {
    case idle
    case listening
    case thinking
    case speaking
}
