import XCTest
import Hummingbird
import HummingbirdTesting
import NIOCore
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

    func testTTSVoicesResponseCanFilterByEngine() {
        let apple = EngineInfo(id: "apple", displayName: "Apple TTS", status: .ready, isLocal: true)
        let remote = EngineInfo(id: "openai_compatible_remote", displayName: "Remote TTS", status: .ready, isLocal: false)
        mockController.stubbedTTSVoices = [
            TTSVoiceEngineInfo(
                engine: apple,
                voices: [Voice(id: "com.apple.voice.compact.en-US.Samantha", displayName: "Samantha", language: "en-US")]
            ),
            TTSVoiceEngineInfo(engine: remote, voices: [])
        ]

        let voices = mockController.listTTSVoices(engineID: "apple")

        XCTAssertEqual(voices.count, 1)
        XCTAssertEqual(voices.first?.engine.id, "apple")
        XCTAssertEqual(voices.first?.voices.first?.displayName, "Samantha")
        XCTAssertEqual(mockController.listTTSVoicesCallCount, 1)
    }

    func testNotifyRequestDecodesDocumentedFields() throws {
        let json = """
        {
          "message": "Build succeeded",
          "level": "warning",
          "voice": "alloy",
          "duration": "long",
          "interruptible": false,
          "sound": true,
          "click_action": "default",
          "open_url": "codex://thread/current",
          "activate_bundle_id": "com.openai.codex",
          "fallback_to_notification": false
        }
        """.data(using: .utf8)!

        let request = try JSONDecoder().decode(TTSNotifyRequest.self, from: json)

        XCTAssertEqual(request.message, "Build succeeded")
        XCTAssertEqual(request.level, .warning)
        XCTAssertEqual(request.voice, "alloy")
        XCTAssertEqual(request.duration, .long)
        XCTAssertEqual(request.interruptible, false)
        XCTAssertEqual(request.sound, true)
        XCTAssertEqual(request.clickAction, .default)
        XCTAssertEqual(request.openURL, "codex://thread/current")
        XCTAssertEqual(request.activateBundleID, "com.openai.codex")
        XCTAssertFalse(request.fallbackToNotification)
        XCTAssertTrue(request.speak)
        XCTAssertFalse(request.notify)
    }

    func testNotifyRequestDefaultsToSpeakAndFallbackNotification() throws {
        let json = #"{"message":"Build succeeded"}"#.data(using: .utf8)!

        let request = try JSONDecoder().decode(TTSNotifyRequest.self, from: json)

        XCTAssertEqual(request.level, .info)
        XCTAssertEqual(request.duration, .short)
        XCTAssertTrue(request.fallbackToNotification)
        XCTAssertTrue(request.speak)
        XCTAssertFalse(request.notify)
        XCTAssertNil(request.sound)
    }

    func testNotifyClickActionSupportsNoOpAliases() throws {
        let none = try JSONDecoder().decode(
            TTSNotifyRequest.self,
            from: Data(#"{"message":"Done","click_action":"none"}"#.utf8)
        )
        let blank = try JSONDecoder().decode(
            TTSNotifyRequest.self,
            from: Data(#"{"message":"Done","click_action":""}"#.utf8)
        )

        XCTAssertEqual(none.clickAction, TTSNotifyClickAction.none)
        XCTAssertEqual(blank.clickAction, TTSNotifyClickAction.none)
    }

    func testConfigDefaultsNotificationSoundPolicy() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data("{}".utf8))

        XCTAssertEqual(config.notifications.soundPolicy, .important)
    }

    func testConfigDefaultsServerHooks() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data("{}".utf8))

        XCTAssertFalse(config.server.hooks.onTranscribed.enabled)
        XCTAssertFalse(config.server.hooks.onError.enabled)
        XCTAssertFalse(config.server.hooks.onSpoken.enabled)
        XCTAssertEqual(config.server.hooks.onTranscribed.timeoutMs, 5_000)
        XCTAssertFalse(config.server.requireToken)
        XCTAssertTrue(config.server.clients.isEmpty)
    }

    func testServerClientRegistryCreatesTokenAndAuthenticatesClient() throws {
        let created = ServerClientRegistry.createClient(name: "Codex", scopes: [.notify])
        let config = Config.ServerConfig(requireToken: true, clients: [created.client])

        let client = try ServerClientRegistry.authenticate(token: created.token, requiredScope: .notify, server: config)

        XCTAssertEqual(client?.name, "Codex")
        XCTAssertTrue(created.token.hasPrefix("tsutae_"))
        XCTAssertNotNil(created.token.range(of: #"^tsutae_[0-9a-f]{64}$"#, options: .regularExpression))
        XCTAssertFalse(created.client.tokenHash.contains(created.token))
    }

    func testServerClientRegistryRejectsMissingTokenWhenRequired() throws {
        let created = ServerClientRegistry.createClient(name: "Codex", scopes: [.notify])
        let config = Config.ServerConfig(requireToken: true, clients: [created.client])

        XCTAssertThrowsError(
            try ServerClientRegistry.authenticate(token: nil, requiredScope: .notify, server: config)
        ) { error in
            XCTAssertTrue(error is ServerClientAuthError)
        }
    }

    func testServerClientRegistryRejectsInvalidToken() throws {
        let created = ServerClientRegistry.createClient(name: "Codex", scopes: [.notify])
        let config = Config.ServerConfig(requireToken: true, clients: [created.client])

        XCTAssertThrowsError(
            try ServerClientRegistry.authenticate(token: "tsutae_wrong", requiredScope: .notify, server: config)
        ) { error in
            XCTAssertTrue(error is ServerClientAuthError)
        }
    }

    func testServerClientRegistryRejectsMissingScope() throws {
        let created = ServerClientRegistry.createClient(name: "Codex", scopes: [.notify])
        let config = Config.ServerConfig(requireToken: true, clients: [created.client])

        XCTAssertThrowsError(
            try ServerClientRegistry.authenticate(token: created.token, requiredScope: .speak, server: config)
        )
    }

    func testServerHookPayloadAddsClientIdentity() {
        let client = Config.ServerClientConfig(
            id: "client_codex",
            name: "Codex",
            tokenHash: "hash"
        )
        let payload = ServerHookPayload(event: .onError, source: "notify", error: "failed")
            .withClient(client)

        XCTAssertEqual(payload.source, "Codex")
        XCTAssertEqual(payload.clientId, "client_codex")
        XCTAssertEqual(payload.clientName, "Codex")
    }

    func testRequestSourceUsesAuthenticatedClientBeforePayloadSource() {
        let client = Config.ServerClientConfig(
            id: "client_codex",
            name: "Codex",
            tokenHash: "hash"
        )

        let resolved = DefaultAppController.resolvedRequestSource("custom-source", client: client, fallback: "Tsutae")

        XCTAssertEqual(resolved, "Codex")
    }

    func testRequestSourceUsesPayloadSourceWithoutClient() {
        let resolved = DefaultAppController.resolvedRequestSource("custom-source", client: nil, fallback: "Tsutae")

        XCTAssertEqual(resolved, "custom-source")
    }

    func testServerHookSpokenPayloadIncludesPlaybackMetadata() {
        let response = TTSSpeakResponse(
            ok: true,
            state: .queued,
            source: "Codex",
            presentationStyle: .minimal,
            queueLength: 2
        )

        let payload = ServerHookPayload.spoken(text: "Done", source: "Codex", response: response)

        XCTAssertEqual(payload.event, .onSpoken)
        XCTAssertEqual(payload.text, "Done")
        XCTAssertEqual(payload.source, "Codex")
        XCTAssertEqual(payload.metadata?["state"], "queued")
        XCTAssertEqual(payload.metadata?["queueLength"], "2")
        XCTAssertEqual(payload.metadata?["presentationStyle"], "minimal")
    }

    func testClientHookConfigDoesNotFallbackToGlobalHook() {
        let globalHooks = Config.ServerHooksConfig(
            onSpoken: Config.ServerHookEndpoint(enabled: true, url: "https://global.example/hook")
        )
        let client = Config.ServerClientConfig(
            id: "client_codex",
            name: "Codex",
            tokenHash: "hash",
            hooks: Config.ServerHooksConfig(
                onSpoken: Config.ServerHookEndpoint(enabled: false, url: "https://codex.example/hook")
            )
        )
        let config = Config(server: Config.ServerConfig(hooks: globalHooks))

        let hooks = DefaultAppController.resolvedHooksConfig(for: .onSpoken, client: client, config: config)

        XCTAssertFalse(hooks.onSpoken.enabled)
        XCTAssertEqual(hooks.onSpoken.url, "https://codex.example/hook")
    }

    func testGlobalHookConfigIsUsedWhenRequestHasNoClient() {
        let globalHooks = Config.ServerHooksConfig(
            onSpoken: Config.ServerHookEndpoint(enabled: true, url: "https://global.example/hook")
        )
        let config = Config(server: Config.ServerConfig(hooks: globalHooks))

        let hooks = DefaultAppController.resolvedHooksConfig(for: .onSpoken, client: nil, config: config)

        XCTAssertTrue(hooks.onSpoken.enabled)
        XCTAssertEqual(hooks.onSpoken.url, "https://global.example/hook")
    }

    func testSpeakRouteAuthenticatesAndPassesClientToController() async throws {
        let created = ServerClientRegistry.createClient(name: "Codex", scopes: [.speak])
        mockController.stubbedConfig.server = Config.ServerConfig(requireToken: true, clients: [created.client])

        try await testServer { client in
            try await client.execute(
                uri: "/v1/speak",
                method: .post,
                headers: Self.jsonHeaders(token: created.token),
                body: Self.jsonBody(#"{"text":"Done","source":"payload-source"}"#)
            ) { response in
                XCTAssertEqual(response.status, .ok)
            }
        }

        XCTAssertEqual(mockController.speakCallCount, 1)
        XCTAssertEqual(mockController.lastClient?.id, created.client.id)
        XCTAssertEqual(mockController.stubbedSpokenText, "Done")
        XCTAssertEqual(mockController.stubbedSpeakingSource, "payload-source")
    }

    func testSpeakRouteRejectsMissingTokenWhenRequired() async throws {
        let created = ServerClientRegistry.createClient(name: "Codex", scopes: [.speak])
        mockController.stubbedConfig.server = Config.ServerConfig(requireToken: true, clients: [created.client])

        try await testServer { client in
            try await client.execute(
                uri: "/v1/speak",
                method: .post,
                headers: Self.jsonHeaders(),
                body: Self.jsonBody(#"{"text":"Done"}"#)
            ) { response in
                XCTAssertEqual(response.status, .unauthorized)
            }
        }

        XCTAssertEqual(mockController.speakCallCount, 0)
    }

    func testSpeakRouteRejectsClientWithoutSpeakScope() async throws {
        let created = ServerClientRegistry.createClient(name: "Codex", scopes: [.notify])
        mockController.stubbedConfig.server = Config.ServerConfig(requireToken: true, clients: [created.client])

        try await testServer { client in
            try await client.execute(
                uri: "/v1/speak",
                method: .post,
                headers: Self.jsonHeaders(token: created.token),
                body: Self.jsonBody(#"{"text":"Done"}"#)
            ) { response in
                XCTAssertEqual(response.status, .forbidden)
            }
        }

        XCTAssertEqual(mockController.speakCallCount, 0)
    }

    func testStateRouteRequiresStateScopeAndReturnsPlaybackSnapshot() async throws {
        let created = configureRequiredTokenClient(scopes: [.state])
        mockController.stubbedState = .speaking
        mockController.stubbedTranscript = "latest transcript"
        mockController.stubbedSpokenText = "spoken"
        mockController.stubbedSpeakingSource = "Codex"
        mockController.stubbedTTSPlaybackSnapshot = TTSPlaybackSnapshot(
            state: .preparing,
            text: "spoken",
            source: "Codex",
            voiceID: "kokoro_ane_mandarin",
            rate: 1.0,
            presentationStyle: .standard,
            startedAt: nil,
            queueLength: 1
        )

        try await testServer { client in
            try await client.execute(
                uri: "/v1/state",
                method: .get,
                headers: Self.authHeaders(token: created.token)
            ) { response in
                XCTAssertEqual(response.status, .ok)
                let decoded = try Self.decodeJSON(StateResponse.self, from: response)
                XCTAssertEqual(decoded.state, .speaking)
                XCTAssertEqual(decoded.transcript, "latest transcript")
                XCTAssertEqual(decoded.ttsPlayback.state, .preparing)
                XCTAssertEqual(decoded.ttsPlayback.queueLength, 1)
            }
        }
    }

    func testNotifyRouteAuthenticatesAndPassesClientToController() async throws {
        let created = configureRequiredTokenClient(scopes: [.notify])
        mockController.stubbedNotifyResponse = TTSNotifyResponse(
            ok: true,
            spoken: true,
            notificationDelivered: false,
            fallbackUsed: false,
            level: .info,
            state: .queued,
            queueLength: 1
        )

        try await testServer { client in
            try await client.execute(
                uri: "/v1/notify",
                method: .post,
                headers: Self.jsonHeaders(token: created.token),
                body: Self.jsonBody(#"{"message":"Done","title":"Codex"}"#)
            ) { response in
                XCTAssertEqual(response.status, .ok)
                let decoded = try Self.decodeJSON(TTSNotifyResponse.self, from: response)
                XCTAssertTrue(decoded.ok)
                XCTAssertEqual(decoded.state, .queued)
                XCTAssertEqual(decoded.queueLength, 1)
            }
        }

        XCTAssertEqual(mockController.notifyCallCount, 1)
        XCTAssertEqual(mockController.lastClient?.id, created.client.id)
    }

    func testNotifyRouteRejectsClientWithoutNotifyScope() async throws {
        let created = configureRequiredTokenClient(scopes: [.speak])

        try await testServer { client in
            try await client.execute(
                uri: "/v1/notify",
                method: .post,
                headers: Self.jsonHeaders(token: created.token),
                body: Self.jsonBody(#"{"message":"Done"}"#)
            ) { response in
                XCTAssertEqual(response.status, .forbidden)
            }
        }

        XCTAssertEqual(mockController.notifyCallCount, 0)
    }

    func testStopRouteRequiresStopScopeAndCallsController() async throws {
        let created = configureRequiredTokenClient(scopes: [.stop])

        try await testServer { client in
            try await client.execute(
                uri: "/v1/stop",
                method: .post,
                headers: Self.authHeaders(token: created.token)
            ) { response in
                XCTAssertEqual(response.status, .ok)
                let decoded = try Self.decodeJSON(TTSStopResponse.self, from: response)
                XCTAssertTrue(decoded.ok)
                XCTAssertEqual(decoded.state, .stopping)
            }
        }

        XCTAssertEqual(mockController.stopSpeakingCallCount, 1)
    }

    func testAudioTranscriptionsRouteAuthenticatesAndPassesClientToController() async throws {
        let created = configureRequiredTokenClient(scopes: [.transcribe])
        mockController.stubbedTranscription = Transcript(
            text: "route transcript",
            language: "en",
            durationMs: 1_500,
            confidence: nil,
            isFinal: true
        )
        let boundary = "Boundary-\(UUID().uuidString)"
        let pcm = Data([0, 0, 255, 127])
        let wav = try WAVEncoder.encode(AudioData(samples: pcm, sampleRate: 16_000, channels: 1))
        let body = MultipartFormData(boundary: boundary)
            .addField(name: "model", value: "whisper-1")
            .addFile(name: "file", filename: "audio.wav", contentType: "audio/wav", data: wav)
            .finalize()

        try await testServer { client in
            try await client.execute(
                uri: "/v1/audio/transcriptions",
                method: .post,
                headers: Self.multipartHeaders(boundary: boundary, token: created.token),
                body: ByteBuffer(data: body)
            ) { response in
                XCTAssertEqual(response.status, .ok)
                let decoded = try Self.decodeJSON(STTTranscriptionResponse.self, from: response)
                XCTAssertEqual(decoded.text, "route transcript")
                XCTAssertEqual(decoded.language, "en")
                XCTAssertEqual(decoded.duration, 1.5)
            }
        }

        XCTAssertEqual(mockController.transcribeCallCount, 1)
        XCTAssertEqual(mockController.lastClient?.id, created.client.id)
    }

    func testAudioSpeechRouteRejectsClientWithoutAudioSpeechScope() async throws {
        let created = configureRequiredTokenClient(scopes: [.speak])

        try await testServer { client in
            try await client.execute(
                uri: "/v1/audio/speech",
                method: .post,
                headers: Self.jsonHeaders(token: created.token),
                body: Self.jsonBody(#"{"input":"hello","voice":"alloy"}"#)
            ) { response in
                XCTAssertEqual(response.status, .forbidden)
            }
        }
    }

    func testServerHookRequestUsesJSONAndBearerToken() throws {
        let endpoint = Config.ServerHookEndpoint(
            enabled: true,
            url: "https://example.com/hooks/transcribed",
            tokenRef: "hook_token",
            timeoutMs: 2_500
        )
        let payload = ServerHookPayload(
            event: .onTranscribed,
            text: "hello",
            source: "test",
            timestamp: "2026-06-15T00:00:00Z"
        )

        let request = try ServerHookRunner.makeRequest(endpoint: endpoint, payload: payload, token: "secret-token")

        XCTAssertEqual(request.url?.absoluteString, "https://example.com/hooks/transcribed")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, 2.5)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Tsutae-Hook-Event"), "onTranscribed")
        XCTAssertNotNil(request.httpBody)
    }

    func testNotifyControllerResponse() async throws {
        mockController.stubbedNotifyResponse = TTSNotifyResponse(
            ok: true,
            spoken: false,
            notificationDelivered: true,
            fallbackUsed: true,
            level: .error,
            state: nil
        )

        let response = try await mockController.notify(
            TTSNotifyRequest(
                message: "Needs attention",
                level: .error,
                interruptible: false,
                fallbackToNotification: true
            )
        )

        XCTAssertTrue(response.ok)
        XCTAssertTrue(response.notificationDelivered)
        XCTAssertEqual(response.level, .error)
        XCTAssertEqual(mockController.notifyCallCount, 1)
    }

    func testServerHookControllerResponse() async throws {
        let response = await mockController.testServerHook(.onError)

        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.event, .onError)
        XCTAssertEqual(response.statusCode, 204)
        XCTAssertEqual(mockController.testServerHookCallCount, 1)
        XCTAssertEqual(mockController.runServerHookCallCount, 1)
    }

    func testStateResponseIncludesTTSPlaybackSnapshot() throws {
        mockController.stubbedTTSPlaybackSnapshot = TTSPlaybackSnapshot(
            state: .speaking,
            text: "hello",
            source: "test",
            voiceID: "voice-1",
            rate: 1.1,
            presentationStyle: .standard,
            startedAt: Date(timeIntervalSince1970: 1)
        )

        let response = StateResponse(
            state: mockController.currentState,
            transcript: mockController.currentTranscript,
            spokenText: mockController.currentSpokenText,
            speakingSource: mockController.currentSpeakingSource,
            ttsPlayback: mockController.ttsPlaybackSnapshot
        )
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(StateResponse.self, from: data)

        XCTAssertEqual(decoded.ttsPlayback.state, .speaking)
        XCTAssertEqual(decoded.ttsPlayback.voiceID, "voice-1")
        XCTAssertEqual(decoded.ttsPlayback.presentationStyle, .standard)
    }

    // MARK: - STT Transcriptions

    func testAudioTranscriptionsUploadParsesMultipartWAV() throws {
        let boundary = "Boundary-\(UUID().uuidString)"
        let pcm = Data([0, 0, 255, 127, 0, 128])
        let wav = try WAVEncoder.encode(AudioData(samples: pcm, sampleRate: 16_000, channels: 1))
        let body = MultipartFormData(boundary: boundary)
            .addField(name: "model", value: "whisper-1")
            .addField(name: "language", value: "en")
            .addField(name: "response_format", value: "verbose_json")
            .addFile(name: "file", filename: "audio.wav", contentType: "audio/wav", data: wav)
            .finalize()

        let upload = try STTTranscriptionUpload.parse(
            body: body,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )

        XCTAssertEqual(upload.request.model, "whisper-1")
        XCTAssertEqual(upload.request.language, "en")
        XCTAssertEqual(upload.request.responseFormat, "verbose_json")
        XCTAssertEqual(upload.request.audio.samples, pcm)
        XCTAssertEqual(upload.request.audio.sampleRate, 16_000)
        XCTAssertEqual(upload.request.audio.channels, 1)
        XCTAssertEqual(upload.request.audio.container, .pcm16)
    }

    func testAudioTranscriptionsUploadRejectsUnsupportedContainer() throws {
        let boundary = "Boundary-\(UUID().uuidString)"
        let body = MultipartFormData(boundary: boundary)
            .addField(name: "model", value: "whisper-1")
            .addFile(name: "file", filename: "audio.m4a", contentType: "audio/mp4", data: Data([1, 2, 3, 4]))
            .finalize()

        XCTAssertThrowsError(
            try STTTranscriptionUpload.parse(
                body: body,
                contentType: "multipart/form-data; boundary=\(boundary)"
            )
        )
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

    private func testServer(_ test: @Sendable (any TestClientProtocol) async throws -> Void) async throws {
        let server = HTTPServer(controller: mockController)
        let app = Application(responder: server.buildRouter().buildResponder())
        try await app.test(.router, test)
    }

    private func configureRequiredTokenClient(scopes: [Config.ServerClientScope]) -> ServerClientCreationResult {
        let created = ServerClientRegistry.createClient(name: "Codex", scopes: scopes)
        mockController.stubbedConfig.server = Config.ServerConfig(requireToken: true, clients: [created.client])
        return created
    }

    private static func authHeaders(token: String? = nil) -> HTTPFields {
        var headers = HTTPFields()
        if let token {
            headers[.authorization] = "Bearer \(token)"
        }
        return headers
    }

    private static func jsonHeaders(token: String? = nil) -> HTTPFields {
        var headers: HTTPFields = [.contentType: "application/json"]
        if let token {
            headers[.authorization] = "Bearer \(token)"
        }
        return headers
    }

    private static func multipartHeaders(boundary: String, token: String? = nil) -> HTTPFields {
        var headers: HTTPFields = [.contentType: "multipart/form-data; boundary=\(boundary)"]
        if let token {
            headers[.authorization] = "Bearer \(token)"
        }
        return headers
    }

    private static func jsonBody(_ string: String) -> ByteBuffer {
        ByteBuffer(data: Data(string.utf8))
    }

    private static func decodeJSON<T: Decodable>(_ type: T.Type, from response: TestResponse) throws -> T {
        var body = response.body
        let data = body.readData(length: body.readableBytes) ?? Data()
        return try JSONDecoder().decode(T.self, from: data)
    }
}
