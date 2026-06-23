import XCTest
import Yams
@testable import TsutaeCore

final class TsutaeCoreTests: XCTestCase {
    
    var tmpDir: URL!
    
    override func setUp() {
        super.setUp()
        // 重置 Paths 缓存
        Paths.resetCache()
        
        // 每个测试用独立临时目录
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tsutae-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        setenv("TSUTAE_ROOT", tmpDir.path, 1)
        // 确保目录存在
        try! Paths.ensureDirectories()
    }
    
    override func tearDown() {
        // 清理临时目录
        try? FileManager.default.removeItem(at: tmpDir)
        Paths.resetCache()
        super.tearDown()
    }
    
    // MARK: - Config Tests
    
    func testDefaultConfigValues() {
        let config = Config.default
        
        XCTAssertFalse(config.general.launchAtLogin)
        XCTAssertEqual(config.general.language, "auto")
        XCTAssertEqual(config.stt.mode, .localFirst)
        XCTAssertEqual(config.stt.engine, "fluidaudio_local")
        XCTAssertEqual(config.stt.model, "parakeet-tdt-v3")
        XCTAssertEqual(config.stt.fallbackEngine, "apple_speech")
        XCTAssertEqual(config.stt.remote.requestStyle, .audioTranscriptions)
        XCTAssertEqual(config.tts.engine, "apple")
        XCTAssertTrue(config.tts.local.enabled)
        XCTAssertEqual(config.tts.rate, 1.0)
        XCTAssertTrue(config.tts.interruptCurrent)
        XCTAssertTrue(config.tts.queueWhenBusy)
        XCTAssertNil(config.tts.fallbackEngine)
        XCTAssertEqual(config.vad.engine, "energy")
        XCTAssertEqual(config.vad.pauseDurationMs, 800)
        XCTAssertTrue(config.vad.allowBargeIn)
        XCTAssertEqual(config.server.port, 1338)
        XCTAssertEqual(config.server.bind, "127.0.0.1")
    }
    
    func testConfigLoadSave() throws {
        print("TSUTAE_ROOT: \(ProcessInfo.processInfo.environment["TSUTAE_ROOT"] ?? "nil")")
        print("Paths.root: \(Paths.root.path)")
        print("Paths.configYML: \(Paths.configYML.path)")
        
        // 加载（应该创建默认配置）
        let config1 = try ConfigLoader.load()
        XCTAssertEqual(config1.server.port, 1338)
        
        // 修改并保存
        var config2 = config1
        config2.server.port = 9999
        try ConfigLoader.save(config2)
        
        // 验证文件已写入
        let yamlContent = try String(contentsOf: Paths.configYML, encoding: .utf8)
        print("YAML content after save: \(yamlContent)")
        
        // 重新加载，验证修改生效
        let config3 = try ConfigLoader.load()
        print("Loaded port: \(config3.server.port)")
        XCTAssertEqual(config3.server.port, 9999, "Reloaded config should have port 9999")
    }

    func testTTSFallbackEngineIsExplicitOptIn() throws {
        let decoder = YAMLDecoder()

        let missingFallback = try decoder.decode(Config.TTSConfig.self, from: "engine: openai_compatible_remote_tts\n")
        XCTAssertNil(missingFallback.fallbackEngine)
        XCTAssertTrue(missingFallback.queueWhenBusy)

        let disabledFallback = try decoder.decode(Config.TTSConfig.self, from: "fallbackEngine: null\n")
        XCTAssertNil(disabledFallback.fallbackEngine)

        let appleFallback = try decoder.decode(Config.TTSConfig.self, from: "fallbackEngine: apple\n")
        XCTAssertEqual(appleFallback.fallbackEngine, "apple")
    }

    func testTTSRemoteVoiceIsStoredSeparately() throws {
        let decoder = YAMLDecoder()
        let config = try decoder.decode(
            Config.TTSConfig.self,
            from: """
            engine: openai_compatible_remote_tts
            voice: kokoro_ane_mandarin
            remote:
              enabled: true
              model: gpt-4o-mini-tts
              voice: alloy
            """
        )

        XCTAssertEqual(config.voice, "kokoro_ane_mandarin")
        XCTAssertEqual(config.remote.voice, "alloy")
    }

    func testTTSPlaybackSnapshotEncodesQueueLength() throws {
        let snapshot = TTSPlaybackSnapshot(
            state: .speaking,
            text: "hello",
            source: "test",
            voiceID: "voice",
            rate: 1.0,
            presentationStyle: .minimal,
            startedAt: nil,
            queueLength: 2
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(TTSPlaybackSnapshot.self, from: data)

        XCTAssertEqual(decoded.queueLength, 2)
        XCTAssertEqual(decoded.presentationStyle, .minimal)
    }

    func testASRSampleLogWritesJSONL() async throws {
        var config = Config.default
        config.stt.local.preferredModel = "sensevoice-small"
        let transcript = Transcript(text: "呃 code x hook", language: "zh", durationMs: 1200, confidence: 0.82)
        let postProcessing = TranscriptPostProcessingResult(
            rawText: transcript.text,
            processedText: "Codex hook。",
            mode: .rules,
            task: .cleanDictation,
            provider: "rules+dictionary",
            model: nil,
            elapsedMs: 1.4,
            dictionaryMatches: ["code x"]
        )
        let record = ASRSampleLog.makeRecord(
            context: "test",
            audio: AudioData(samples: Data(count: 3200), sampleRate: 16000, channels: 1),
            transcript: transcript,
            config: config,
            transcriptionElapsedMs: 42,
            totalElapsedMs: 45,
            postProcessing: postProcessing,
            recordingStartApplication: FocusedApplicationSnapshot(
                localizedName: "Xcode",
                bundleIdentifier: "com.apple.dt.Xcode",
                processIdentifier: 123
            ),
            insertionApplication: FocusedApplicationSnapshot(
                localizedName: "Notes",
                bundleIdentifier: "com.apple.Notes",
                processIdentifier: 456
            ),
            insertion: ASRSampleLog.InsertionSnapshot(
                method: "focused_app",
                succeeded: true,
                elapsedMs: 6
            ),
            endToEndElapsedMs: 51
        )

        await ASRSampleLog.append(record)

        let text = try String(contentsOf: ASRSampleLog.fileURL, encoding: .utf8)
        let line = try XCTUnwrap(text.split(separator: "\n").first)
        let decoded = try JSONDecoder().decode(ASRSampleLog.Record.self, from: Data(line.utf8))
        XCTAssertEqual(decoded.context, "test")
        XCTAssertEqual(decoded.rawText, "呃 code x hook")
        XCTAssertEqual(decoded.finalText, "Codex hook。")
        XCTAssertEqual(decoded.localModel, "sensevoice-small")
        XCTAssertEqual(decoded.postProcessing?.dictionaryMatches, ["code x"])
        XCTAssertEqual(decoded.recordingStartApplication?.bundleIdentifier, "com.apple.dt.Xcode")
        XCTAssertEqual(decoded.insertionApplication?.bundleIdentifier, "com.apple.Notes")
        XCTAssertEqual(decoded.targetApplication?.bundleIdentifier, "com.apple.Notes")
        XCTAssertEqual(decoded.insertion?.method, "focused_app")
        XCTAssertEqual(decoded.endToEndElapsedMs, 51)
    }

    func testTTSPlaybackSnapshotEncodesPreparingState() throws {
        let snapshot = TTSPlaybackSnapshot(
            state: .preparing,
            text: "hello",
            source: "local",
            voiceID: "kokoro_ane_mandarin",
            rate: 1.0,
            presentationStyle: .standard,
            startedAt: nil
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(TTSPlaybackSnapshot.self, from: data)

        XCTAssertEqual(decoded.state, .preparing)
        XCTAssertEqual(decoded.voiceID, "kokoro_ane_mandarin")
    }

    func testFluidAudioLocalTTSVoiceResolution() {
        XCTAssertEqual(
            FluidAudioLocalTTSVoice.resolve(voiceID: nil, text: "你好，构建完成。"),
            .mandarin
        )
        XCTAssertEqual(
            FluidAudioLocalTTSVoice.resolve(voiceID: nil, text: "Build finished."),
            .english
        )
        XCTAssertEqual(
            FluidAudioLocalTTSVoice.resolve(voiceID: "zf_001", text: "Build finished."),
            .mandarin
        )
        XCTAssertNil(FluidAudioLocalTTSVoice.resolve(voiceID: "unknown", text: "Build finished."))
    }

    func testLocalSTTRecordingGuidance() {
        let qwen = LocalSTTModelCatalog.recordingGuidance(for: "qwen3-asr-int8")
        XCTAssertEqual(qwen.warningSeconds, 30)
        XCTAssertEqual(qwen.recommendedMaximumSeconds, 35)
        XCTAssertFalse(qwen.isEstimated)

        let senseVoice = LocalSTTModelCatalog.recordingGuidance(for: "sensevoice-small")
        XCTAssertEqual(senseVoice.warningSeconds, 25)
        XCTAssertEqual(senseVoice.recommendedMaximumSeconds, 30)
        XCTAssertFalse(senseVoice.isEstimated)

        let unknown = LocalSTTModelCatalog.recordingGuidance(for: "unknown")
        XCTAssertEqual(unknown.warningSeconds, 30)
        XCTAssertTrue(unknown.isEstimated)
    }

    func testSTTTranscriptionErrorClassifiesLongAudioLimits() {
        let error = STTTranscriptionError.allRoutesFailed(
            primaryEngine: "fluidaudio_local",
            primaryError: "Generation failed: Prompt length 622 exceeds cache capacity 512",
            fallbackEngine: "apple_speech",
            fallbackError: "STT engine returned an empty transcript. engine=apple_speech"
        )
        XCTAssertTrue(error.isLikelyLongAudioLimit)

        let empty = STTTranscriptionError.emptyTranscript(engine: "apple_speech")
        XCTAssertFalse(empty.isLikelyLongAudioLimit)
    }
    
    // MARK: - Paths Tests
    
    func testPathsRootDirectory() {
        let root = Paths.root
        // TSUTAE_ROOT 环境变量已设置，应该指向临时目录
        XCTAssertTrue(root.path.contains("tsutae-test-"), "Root path: \(root.path)")
    }
    
    func testPathsSubdirectories() {
        XCTAssertEqual(Paths.configYML.lastPathComponent, "config.yml")
        XCTAssertEqual(Paths.hotkeysYML.lastPathComponent, "hotkeys.yml")
        XCTAssertEqual(Paths.models.lastPathComponent, "models")
        XCTAssertEqual(Paths.sttModels.lastPathComponent, "stt")
    }
    
    func testEnsureDirectories() throws {
        try Paths.ensureDirectories()
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: Paths.root.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: Paths.recipes.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: Paths.models.path))
        
        // 检查 .gitignore 被创建
        let gitignore = Paths.root.appendingPathComponent(".gitignore")
        XCTAssertTrue(FileManager.default.fileExists(atPath: gitignore.path))
    }
    
    // MARK: - Hotkeys Tests
    
    func testHotkeysDefaultConfig() {
        let config = HotkeysConfig.default
        
        XCTAssertNotNil(config.leader)
        XCTAssertEqual(config.leader?.key, "option+space")
        XCTAssertEqual(config.leader?.hudTimeoutMs, 1500)
        XCTAssertEqual(config.leader?.hudActions.count, 2)
        XCTAssertEqual(config.hotkeys.count, 3)
    }
    
    func testHotkeysLoadSave() throws {
        try Paths.ensureDirectories()
        
        // 加载（应该创建默认配置）
        let config1 = try HotkeysLoader.load()
        XCTAssertNotNil(config1.leader)
        
        // 修改并保存
        var config2 = config1
        config2.leader?.hudTimeoutMs = 2000
        try HotkeysLoader.save(config2)
        
        // 重新加载
        let config3 = try HotkeysLoader.load()
        XCTAssertEqual(config3.leader?.hudTimeoutMs, 2000)
    }
    
    func testActionBindingCodable() throws {
        // 测试预定义 action
        let predefined = ActionBinding.predefined(.sendToFocusedApp)
        let encoder = JSONEncoder()
        let data = try encoder.encode(predefined)
        let decoded = try JSONDecoder().decode(ActionBinding.self, from: data)
        
        if case .predefined(let action) = decoded {
            XCTAssertEqual(action, .sendToFocusedApp)
        } else {
            XCTFail("Expected predefined action")
        }
    }
    
    // MARK: - Recipes Tests
    
    func testRecipeLoadAll() throws {
        try Paths.ensureDirectories()
        
        // 安装内置配方
        try BuiltInRecipes.installDefaults()
        
        // 加载所有
        let recipes = try RecipeLoader.loadAll()
        XCTAssertEqual(recipes.count, 5)
        
        // 验证名称
        let names = recipes.map(\.name)
        XCTAssertTrue(names.contains("notion_daily"))
        XCTAssertTrue(names.contains("obsidian_daily"))
        XCTAssertTrue(names.contains("linear_issue"))
    }
    
    func testRecipeLoadByName() throws {
        try Paths.ensureDirectories()
        try BuiltInRecipes.installDefaults()
        
        let recipe = try RecipeLoader.load(name: "notion_daily")
        XCTAssertEqual(recipe.name, "notion_daily")
        XCTAssertEqual(recipe.action, "post_http")
        XCTAssertEqual(recipe.url, "https://api.notion.com/v1/pages")
        XCTAssertNotNil(recipe.onSuccess?.tts)
    }
    
    func testRecipeSaveDelete() throws {
        try Paths.ensureDirectories()
        
        let recipe = Recipe(
            name: "test_recipe",
            description: "测试配方",
            action: "post_http",
            url: "https://example.com"
        )
        
        // 保存
        try RecipeLoader.save(recipe)
        XCTAssertTrue(RecipeLoader.exists(name: "test_recipe"))
        
        // 加载
        let loaded = try RecipeLoader.load(name: "test_recipe")
        XCTAssertEqual(loaded.name, "test_recipe")
        XCTAssertEqual(loaded.url, "https://example.com")
        
        // 删除
        try RecipeLoader.delete(name: "test_recipe")
        XCTAssertFalse(RecipeLoader.exists(name: "test_recipe"))
    }
    
    func testBuiltInRecipesHaveRequiredFields() {
        for recipe in BuiltInRecipes.all {
            XCTAssertFalse(recipe.name.isEmpty, "Recipe name should not be empty")
            XCTAssertFalse(recipe.description.isEmpty, "Recipe description should not be empty")
            XCTAssertFalse(recipe.action.isEmpty, "Recipe action should not be empty")
        }
    }
    
    // MARK: - EngineManager Tests
    
    func testEngineManagerRegisterAndList() {
        let manager = EngineManager.shared
        
        // 清理（防止其他测试污染）
        manager.unregisterSTT(id: "test-stt")
        
        // 注册测试引擎
        let engine = MockSTTEngine(id: "test-stt")
        manager.registerSTT(engine)
        
        // 列表应该包含
        let list = manager.listSTT()
        XCTAssertTrue(list.contains { $0.id == "test-stt" })
        
        // 获取
        let retrieved = manager.stt(id: "test-stt")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.id, "test-stt")
        
        // 清理
        manager.unregisterSTT(id: "test-stt")
        XCTAssertNil(manager.stt(id: "test-stt"))
    }
    
    func testEngineManagerFallback() throws {
        let manager = EngineManager.shared
        
        // 清理
        manager.unregisterSTT(id: "primary")
        manager.unregisterSTT(id: "fallback")
        
        // 注册主引擎（error 状态）
        let primary = MockSTTEngine(id: "primary", status: .error)
        manager.registerSTT(primary)
        
        // 注册 fallback（ready 状态）
        let fallback = MockSTTEngine(id: "fallback", status: .ready)
        manager.registerSTT(fallback)
        
        // 应该返回 fallback
        let engine = try manager.getSTT(primary: "primary", fallback: "fallback")
        XCTAssertEqual(engine.id, "fallback")
        
        // 清理
        manager.unregisterSTT(id: "primary")
        manager.unregisterSTT(id: "fallback")
    }
    
    func testEngineManagerNoAvailable() {
        let manager = EngineManager.shared
        
        // 清理
        manager.unregisterSTT(id: "missing")
        
        // 应该抛错
        XCTAssertThrowsError(try manager.getSTT(primary: "missing", fallback: nil)) { error in
            XCTAssertTrue(error is EngineError)
        }
    }
}

// MARK: - Mock 引擎

final class MockSTTEngine: STTEngine {
    let id: String
    let displayName: String
    let isLocal: Bool
    let status: EngineStatus
    
    init(id: String, displayName: String = "Mock", isLocal: Bool = true, status: EngineStatus = .ready) {
        self.id = id
        self.displayName = displayName
        self.isLocal = isLocal
        self.status = status
    }
    
    func transcribe(_ audio: AudioData, language: String?) async throws -> Transcript {
        Transcript(text: "mock transcription")
    }
    
    func stream(_ audio: AsyncStream<AudioChunk>, language: String?) -> AsyncThrowingStream<TranscriptUpdate, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}
