import Foundation

/// AppController 默认实现
public final class DefaultAppController: AppControllerProtocol, @unchecked Sendable {
    
    private let engineManager: EngineManager
    private let lock = NSLock()
    private var _currentState: AppState = .idle
    private var _currentTranscript: String?
    
    public init(engineManager: EngineManager = .shared) {
        self.engineManager = engineManager
    }
    
    // MARK: - 状态
    
    public var currentState: AppState {
        lock.lock()
        defer { lock.unlock() }
        return _currentState
    }
    
    public var currentTranscript: String? {
        lock.lock()
        defer { lock.unlock() }
        return _currentTranscript
    }
    
    /// 更新状态（内部用）
    func updateState(_ newState: AppState) {
        lock.lock()
        defer { lock.unlock() }
        _currentState = newState
    }
    
    /// 更新转写文本（内部用）
    func updateTranscript(_ text: String?) {
        lock.lock()
        defer { lock.unlock() }
        _currentTranscript = text
    }
    
    // MARK: - 配置
    
    public func loadConfig() throws -> Config {
        try ConfigLoader.load()
    }
    
    public func saveConfig(_ config: Config) throws {
        try ConfigLoader.save(config)
    }
    
    // MARK: - 引擎
    
    public func listSTTEngines() -> [EngineInfo] {
        engineManager.listSTT()
    }
    
    public func listTTSEngines() -> [EngineInfo] {
        engineManager.listTTS()
    }
    
    public func listVADEngines() -> [EngineInfo] {
        engineManager.listVAD()
    }
    
    // MARK: - Secrets
    
    public func setSecret(_ name: String, value: String) throws {
        try SecretsManager.set(value, for: name)
    }
    
    public func getSecret(_ name: String) throws -> String? {
        try SecretsManager.get(name)
    }
    
    public func deleteSecret(_ name: String) throws {
        try SecretsManager.delete(name)
    }
    
    public func listSecrets() throws -> [String] {
        try SecretsManager.list()
    }
    
    // MARK: - Recipes
    
    public func listRecipes() throws -> [Recipe] {
        try RecipeLoader.loadAll()
    }
    
    public func loadRecipe(name: String) throws -> Recipe {
        try RecipeLoader.load(name: name)
    }
    
    public func installBuiltinRecipes() throws {
        try BuiltInRecipes.installDefaults()
    }
    
    // MARK: - Hotkeys
    
    public func loadHotkeys() throws -> HotkeysConfig {
        try HotkeysLoader.load()
    }
    
    public func saveHotkeys(_ config: HotkeysConfig) throws {
        try HotkeysLoader.save(config)
    }
    
    // MARK: - 健康检查
    
    public func healthCheck() -> HealthStatus {
        let sttCount = engineManager.listSTT().filter { $0.status == .ready }.count
        let ttsCount = engineManager.listTTS().filter { $0.status == .ready }.count
        let vadCount = engineManager.listVAD().filter { $0.status == .ready }.count
        
        return HealthStatus(
            status: "ok",
            version: TsutaeConstants.version,
            engines: EngineHealth(stt: sttCount, tts: ttsCount, vad: vadCount)
        )
    }
}
