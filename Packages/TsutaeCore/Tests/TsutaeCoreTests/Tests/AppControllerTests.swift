import XCTest
@testable import TsutaeCore

/// AppController 测试
/// 测试业务逻辑层的行为
final class AppControllerTests: XCTestCase {
    
    var tmpDir: URL!
    var controller: DefaultAppController!
    
    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tsutae-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        setenv("TSUTAE_ROOT", tmpDir.path, 1)
        
        controller = DefaultAppController()
    }
    
    override func tearDown() {
        unsetenv("TSUTAE_ROOT")
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }
    
    // MARK: - 状态管理
    
    func testInitialStateIsIdle() {
        XCTAssertEqual(controller.currentState, .idle)
        XCTAssertNil(controller.currentTranscript)
    }
    
    // MARK: - 配置
    
    func testLoadConfigReturnsDefault() throws {
        let config = try controller.loadConfig()
        XCTAssertEqual(config.server.port, 1338)
        XCTAssertEqual(config.stt.mode, .localFirst)
        XCTAssertEqual(config.stt.engine, "fluidaudio_local")
        XCTAssertEqual(config.stt.model, "parakeet-tdt-v3")
        XCTAssertEqual(config.stt.remote.requestStyle, .audioTranscriptions)
    }

    func testServerClientSourceOverridesRequestSource() {
        let client = Config.ServerClientConfig(
            id: "client_kanade",
            name: "Kanade",
            tokenHash: "hash"
        )

        XCTAssertEqual(
            DefaultAppController.resolvedRequestSource("spoofed", client: client, fallback: "Tsutae"),
            "Kanade"
        )
        XCTAssertEqual(
            DefaultAppController.resolvedRequestSource("legacy", client: nil, fallback: "Tsutae"),
            "legacy"
        )
        XCTAssertEqual(
            DefaultAppController.resolvedRequestSource("  ", client: nil, fallback: "Tsutae"),
            "Tsutae"
        )
    }
    
    func testSaveAndLoadConfig() throws {
        var config = try controller.loadConfig()
        config.server.port = 9999
        try controller.saveConfig(config)
        
        let loaded = try controller.loadConfig()
        XCTAssertEqual(loaded.server.port, 9999)
    }
    
    // MARK: - Secrets
    
    func testSetAndGetSecret() throws {
        try controller.setSecret("test_key", value: "test_value")
        let value = try controller.getSecret("test_key")
        XCTAssertEqual(value, "test_value")
    }
    
    func testGetNonexistentSecretReturnsNil() throws {
        let value = try controller.getSecret("nonexistent")
        XCTAssertNil(value)
    }
    
    func testDeleteSecret() throws {
        try controller.setSecret("to_delete", value: "value")
        try controller.deleteSecret("to_delete")
        let value = try controller.getSecret("to_delete")
        XCTAssertNil(value)
    }
    
    func testListSecrets() throws {
        try controller.setSecret("key1", value: "value1")
        try controller.setSecret("key2", value: "value2")
        
        let keys = try controller.listSecrets()
        XCTAssertTrue(keys.contains("key1"))
        XCTAssertTrue(keys.contains("key2"))
    }
    
    // MARK: - Recipes
    
    func testListRecipesEmptyByDefault() throws {
        let recipes = try controller.listRecipes()
        XCTAssertTrue(recipes.isEmpty)
    }
    
    func testInstallBuiltinRecipes() throws {
        try controller.installBuiltinRecipes()
        let recipes = try controller.listRecipes()
        XCTAssertEqual(recipes.count, 5)
    }
    
    func testLoadRecipeByName() throws {
        try controller.installBuiltinRecipes()
        let recipe = try controller.loadRecipe(name: "notion_daily")
        XCTAssertEqual(recipe.name, "notion_daily")
        XCTAssertEqual(recipe.action, "post_http")
    }
    
    // MARK: - Hotkeys
    
    func testLoadHotkeysReturnsDefault() throws {
        let config = try controller.loadHotkeys()
        XCTAssertNotNil(config.leader)
        XCTAssertEqual(config.leader?.key, "option+space")
    }
    
    func testSaveAndLoadHotkeys() throws {
        var config = try controller.loadHotkeys()
        config.leader?.hudTimeoutMs = 3000
        try controller.saveHotkeys(config)
        
        let loaded = try controller.loadHotkeys()
        XCTAssertEqual(loaded.leader?.hudTimeoutMs, 3000)
    }
    
    // MARK: - 健康检查
    
    func testHealthCheckReturnsOK() {
        let health = controller.healthCheck()
        XCTAssertEqual(health.status, "ok")
        XCTAssertFalse(health.version.isEmpty)
    }
}
