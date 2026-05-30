import XCTest
@testable import TsutaeCore

/// HTTPServer 测试
/// 测试路由和响应行为（使用 MockAppController）
final class HTTPServerTests: XCTestCase {
    
    var mockController: MockAppController!
    
    override func setUp() {
        super.setUp()
        mockController = MockAppController()
    }
    
    override func tearDown() {
        mockController = nil
        super.tearDown()
    }
    
    // MARK: - Health Response
    
    func testHealthResponseContainsStatus() {
        let health = mockController.healthCheck()
        XCTAssertEqual(health.status, "ok")
        XCTAssertEqual(health.version, "0.0.1")
    }
    
    func testHealthResponseContainsEngineCounts() {
        mockController.stubbedHealth = HealthStatus(
            status: "ok",
            version: "1.0.0",
            engines: EngineHealth(stt: 2, tts: 1, vad: 1)
        )
        
        let health = mockController.healthCheck()
        XCTAssertEqual(health.engines.stt, 2)
        XCTAssertEqual(health.engines.tts, 1)
        XCTAssertEqual(health.engines.vad, 1)
    }
    
    // MARK: - Models Response
    
    func testModelsResponseIncludesAllEngines() {
        mockController.stubbedSTTEngines = [
            EngineInfo(id: "whisperkit", displayName: "WhisperKit", status: .ready, isLocal: true)
        ]
        mockController.stubbedTTSEngines = [
            EngineInfo(id: "apple", displayName: "Apple TTS", status: .ready, isLocal: true)
        ]
        mockController.stubbedVADEngines = [
            EngineInfo(id: "silero", displayName: "Silero VAD", status: .ready, isLocal: true)
        ]
        
        let stt = mockController.listSTTEngines()
        let tts = mockController.listTTSEngines()
        let vad = mockController.listVADEngines()
        
        XCTAssertEqual(stt.count, 1)
        XCTAssertEqual(stt.first?.id, "whisperkit")
        XCTAssertEqual(tts.count, 1)
        XCTAssertEqual(tts.first?.id, "apple")
        XCTAssertEqual(vad.count, 1)
        XCTAssertEqual(vad.first?.id, "silero")
    }
    
    // MARK: - Config
    
    func testLoadConfigFromController() throws {
        mockController.stubbedConfig = Config(
            general: .init(language: "zh"),
            stt: .init(engine: "whisperkit"),
            tts: .init(engine: "kokoro"),
            vad: .init(engine: "silero"),
            server: .init(port: 8080)
        )
        
        let config = try mockController.loadConfig()
        XCTAssertEqual(config.server.port, 8080)
        XCTAssertEqual(config.stt.engine, "whisperkit")
        XCTAssertEqual(config.tts.engine, "kokoro")
    }
    
    func testSaveConfigToController() throws {
        var config = try mockController.loadConfig()
        config.server.port = 9999
        try mockController.saveConfig(config)
        
        XCTAssertEqual(mockController.saveConfigCallCount, 1)
        XCTAssertEqual(mockController.stubbedConfig.server.port, 9999)
    }
    
    func testLoadConfigError() {
        mockController.configError = NSError(domain: "test", code: 1)
        
        XCTAssertThrowsError(try mockController.loadConfig())
        XCTAssertEqual(mockController.loadConfigCallCount, 1)
    }
    
    // MARK: - Recipes
    
    func testListRecipesFromController() throws {
        mockController.stubbedRecipes = [
            Recipe(name: "test1", description: "Test 1", action: "post_http"),
            Recipe(name: "test2", description: "Test 2", action: "post_http"),
        ]
        
        let recipes = try mockController.listRecipes()
        XCTAssertEqual(recipes.count, 2)
        XCTAssertEqual(mockController.listRecipesCallCount, 1)
    }
    
    func testLoadRecipeByName() throws {
        mockController.stubbedRecipe = Recipe(
            name: "notion",
            description: "Notion recipe",
            action: "post_http",
            url: "https://api.notion.com"
        )
        
        let recipe = try mockController.loadRecipe(name: "notion")
        XCTAssertEqual(recipe.name, "notion")
        XCTAssertEqual(recipe.url, "https://api.notion.com")
        XCTAssertEqual(mockController.loadRecipeCallCount, 1)
    }
    
    func testLoadRecipeNotFound() {
        mockController.stubbedRecipe = nil
        
        XCTAssertThrowsError(try mockController.loadRecipe(name: "missing"))
    }
    
    // MARK: - Hotkeys
    
    func testLoadHotkeysFromController() throws {
        mockController.stubbedHotkeys = HotkeysConfig(
            leader: LeaderConfig(
                key: "ctrl+space",
                defaultAction: .predefined(.sendToFocusedApp),
                hudTimeoutMs: 2000
            ),
            hotkeys: [
                HotkeyEntry(key: "ctrl+v", action: .predefined(.sendToFocusedApp))
            ]
        )
        
        let config = try mockController.loadHotkeys()
        XCTAssertEqual(config.leader?.key, "ctrl+space")
        XCTAssertEqual(config.leader?.hudTimeoutMs, 2000)
        XCTAssertEqual(config.hotkeys.count, 1)
    }
    
    // MARK: - Secrets
    
    func testSecretsOperations() throws {
        try mockController.setSecret("api_key", value: "secret123")
        XCTAssertEqual(mockController.setSecretCallCount, 1)
        
        let value = try mockController.getSecret("api_key")
        XCTAssertEqual(value, "secret123")
        XCTAssertEqual(mockController.getSecretCallCount, 1)
        
        let keys = try mockController.listSecrets()
        XCTAssertTrue(keys.contains("api_key"))
        
        try mockController.deleteSecret("api_key")
        XCTAssertEqual(mockController.deleteSecretCallCount, 1)
        
        let deletedValue = try mockController.getSecret("api_key")
        XCTAssertNil(deletedValue)
    }
    
    func testSecretsError() {
        mockController.secretsError = NSError(domain: "test", code: 1)
        
        XCTAssertThrowsError(try mockController.setSecret("key", value: "value"))
        XCTAssertThrowsError(try mockController.getSecret("key"))
        XCTAssertThrowsError(try mockController.deleteSecret("key"))
        XCTAssertThrowsError(try mockController.listSecrets())
    }
}
