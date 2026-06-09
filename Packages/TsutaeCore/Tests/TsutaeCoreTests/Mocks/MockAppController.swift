import Foundation
@testable import TsutaeCore

/// Mock AppController — 用于测试
/// 可以设置每个方法的返回值或错误，验证调用次数
final class MockAppController: AppControllerProtocol, @unchecked Sendable {
    
    // MARK: - 调用记录
    
    var loadConfigCallCount = 0
    var saveConfigCallCount = 0
    var listSTTEnginesCallCount = 0
    var listTTSEnginesCallCount = 0
    var listVADEnginesCallCount = 0
    var setSecretCallCount = 0
    var getSecretCallCount = 0
    var deleteSecretCallCount = 0
    var listSecretsCallCount = 0
    var listRecipesCallCount = 0
    var loadRecipeCallCount = 0
    var installBuiltinRecipesCallCount = 0
    var loadHotkeysCallCount = 0
    var saveHotkeysCallCount = 0
    var healthCheckCallCount = 0
    var speakCallCount = 0
    var stopSpeakingCallCount = 0
    
    // MARK: - 可配置返回值
    
    var stubbedState: AppState = .idle
    var stubbedTranscript: String? = nil
    var stubbedSpokenText: String? = nil
    var stubbedSpeakingSource: String? = nil
    
    var stubbedConfig: Config = .default
    var configError: Error?
    
    var stubbedSTTEngines: [EngineInfo] = []
    var stubbedTTSEngines: [EngineInfo] = []
    var stubbedVADEngines: [EngineInfo] = []
    
    var secrets: [String: String] = [:]
    var secretsError: Error?
    
    var stubbedRecipes: [Recipe] = []
    var stubbedRecipe: Recipe?
    var recipeError: Error?
    
    var stubbedHotkeys: HotkeysConfig = .default
    var hotkeysError: Error?
    
    var stubbedHealth: HealthStatus = HealthStatus(
        status: "ok",
        version: "0.0.1",
        engines: EngineHealth(stt: 0, tts: 0, vad: 0)
    )
    var speakError: Error?
    var stubbedSpeakResponse = TTSSpeakResponse(ok: true, state: .speaking, source: "test")
    
    // MARK: - AppControllerProtocol
    
    var currentState: AppState {
        stubbedState
    }
    
    var currentTranscript: String? {
        stubbedTranscript
    }
    
    var currentSpokenText: String? {
        stubbedSpokenText
    }
    
    var currentSpeakingSource: String? {
        stubbedSpeakingSource
    }
    
    func loadConfig() throws -> Config {
        loadConfigCallCount += 1
        if let error = configError { throw error }
        return stubbedConfig
    }
    
    func saveConfig(_ config: Config) throws {
        saveConfigCallCount += 1
        if let error = configError { throw error }
        stubbedConfig = config
    }
    
    func listSTTEngines() -> [EngineInfo] {
        listSTTEnginesCallCount += 1
        return stubbedSTTEngines
    }
    
    func listTTSEngines() -> [EngineInfo] {
        listTTSEnginesCallCount += 1
        return stubbedTTSEngines
    }
    
    func listVADEngines() -> [EngineInfo] {
        listVADEnginesCallCount += 1
        return stubbedVADEngines
    }
    
    func setSecret(_ name: String, value: String) throws {
        setSecretCallCount += 1
        if let error = secretsError { throw error }
        secrets[name] = value
    }
    
    func getSecret(_ name: String) throws -> String? {
        getSecretCallCount += 1
        if let error = secretsError { throw error }
        return secrets[name]
    }
    
    func deleteSecret(_ name: String) throws {
        deleteSecretCallCount += 1
        if let error = secretsError { throw error }
        secrets.removeValue(forKey: name)
    }
    
    func listSecrets() throws -> [String] {
        listSecretsCallCount += 1
        if let error = secretsError { throw error }
        return Array(secrets.keys)
    }
    
    func listRecipes() throws -> [Recipe] {
        listRecipesCallCount += 1
        if let error = recipeError { throw error }
        return stubbedRecipes
    }
    
    func loadRecipe(name: String) throws -> Recipe {
        loadRecipeCallCount += 1
        if let error = recipeError { throw error }
        if let recipe = stubbedRecipe { return recipe }
        throw RecipeError.notFound(name)
    }
    
    func installBuiltinRecipes() throws {
        installBuiltinRecipesCallCount += 1
        if let error = recipeError { throw error }
    }
    
    func loadHotkeys() throws -> HotkeysConfig {
        loadHotkeysCallCount += 1
        if let error = hotkeysError { throw error }
        return stubbedHotkeys
    }
    
    func saveHotkeys(_ config: HotkeysConfig) throws {
        saveHotkeysCallCount += 1
        if let error = hotkeysError { throw error }
        stubbedHotkeys = config
    }
    
    func speak(_ request: TTSSpeakRequest) async throws -> TTSSpeakResponse {
        speakCallCount += 1
        if let error = speakError { throw error }
        stubbedSpokenText = request.text
        stubbedSpeakingSource = request.source
        stubbedState = .speaking
        return stubbedSpeakResponse
    }
    
    func stopSpeaking() async throws {
        stopSpeakingCallCount += 1
        if let error = speakError { throw error }
        stubbedState = .idle
        stubbedSpokenText = nil
        stubbedSpeakingSource = nil
    }
    
    func healthCheck() -> HealthStatus {
        healthCheckCallCount += 1
        return stubbedHealth
    }
}

// MARK: - Recipe 错误

enum RecipeError: Error {
    case notFound(String)
}
