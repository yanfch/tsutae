import Foundation
import OSLog
import UserNotifications

/// AppController 默认实现
public final class DefaultAppController: AppControllerProtocol, @unchecked Sendable {
    
    private let engineManager: EngineManager
    private let logger = Logger(subsystem: "dev.yanfch.Tsutae", category: "Notify")
    private let hooksLogger = Logger(subsystem: "dev.yanfch.Tsutae", category: "ServerHooks")
    private let lock = NSLock()
    private var _currentState: AppState = .idle
    private var _currentTranscript: String?
    
    public init(engineManager: EngineManager = .shared) {
        self.engineManager = engineManager
    }
    
    // MARK: - 状态
    
    public var currentState: AppState {
        if TTSPlaybackManager.shared.isSpeaking {
            return .speaking
        }
        lock.lock()
        defer { lock.unlock() }
        return _currentState
    }
    
    public var currentTranscript: String? {
        lock.lock()
        defer { lock.unlock() }
        return _currentTranscript
    }
    
    public var currentSpokenText: String? {
        TTSPlaybackManager.shared.snapshot().text
    }
    
    public var currentSpeakingSource: String? {
        TTSPlaybackManager.shared.snapshot().source
    }

    public var ttsPlaybackSnapshot: TTSPlaybackSnapshot {
        TTSPlaybackManager.shared.snapshot()
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

    public func listTTSVoices(engineID: String?) -> [TTSVoiceEngineInfo] {
        engineManager.listTTSVoices(engineID: engineID)
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
    
    // MARK: - TTS Playback

    public func transcribe(_ request: STTTranscriptionRequest, client: Config.ServerClientConfig?) async throws -> Transcript {
        updateState(.listening)
        do {
            var config = try ConfigLoader.load()
            if let language = request.language?.trimmingCharacters(in: .whitespacesAndNewlines), language.isEmpty == false {
                config.stt.language = language
            }
            let transcript = try await ConfiguredSTTRouter.transcribe(request.audio, config: config)
            updateTranscript(transcript.text)
            updateState(.idle)
            triggerServerHook(.onTranscribed, payload: .transcribed(transcript, source: client?.name ?? "stt"), client: client)
            return transcript
        } catch {
            updateState(.idle)
            triggerServerHook(.onError, payload: .failure(error, source: client?.name ?? "stt"), client: client)
            throw error
        }
    }
    
    public func speak(_ request: TTSSpeakRequest, client: Config.ServerClientConfig?) async throws -> TTSSpeakResponse {
        let source = Self.resolvedRequestSource(request.source, client: client, fallback: "Tsutae")
        let playbackRequest = request.withSource(source)
        do {
            let config = try ConfigLoader.load()
            let response = try await TTSPlaybackManager.shared.speak(playbackRequest, config: config.tts)
            return response
        } catch {
            triggerServerHook(.onError, payload: .failure(error, source: source), client: client)
            throw error
        }
    }

    public func notify(_ request: TTSNotifyRequest, client: Config.ServerClientConfig?) async throws -> TTSNotifyResponse {
        let message = request.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard message.isEmpty == false else {
            triggerServerHook(.onError, payload: .failure(TTSNotifyError.emptyMessage, source: client?.name ?? "notify"), client: client)
            throw TTSNotifyError.emptyMessage
        }

        var spoken = false
        var notificationDelivered = false
        var fallbackUsed = false
        var state: TTSPlaybackState?
        var queueLength = 0
        var deliveryError: String?

        if request.speak {
            do {
                let speakResponse = try await speak(
                    TTSSpeakRequest(
                        text: message,
                        source: Self.resolvedRequestSource(request.title, client: client, fallback: "notify"),
                        interrupt: request.interruptible,
                        voice: request.voice?.nilIfBlank
                    ),
                    client: client
                )
                spoken = true
                state = speakResponse.state
                queueLength = speakResponse.queueLength
            } catch {
                deliveryError = error.localizedDescription
                if request.fallbackToNotification == false && request.notify == false {
                    throw error
                }
            }
        }

        let shouldDeliverNotification = request.notify || (request.fallbackToNotification && spoken == false)
        if shouldDeliverNotification {
            fallbackUsed = spoken == false
            do {
                let config = try ConfigLoader.load()
                try await deliverSystemNotification(for: request, message: message, config: config.notifications)
                notificationDelivered = true
            } catch {
                deliveryError = error.localizedDescription
                if spoken == false {
                    throw error
                }
            }
        }

        let response = TTSNotifyResponse(
            ok: spoken || notificationDelivered,
            spoken: spoken,
            notificationDelivered: notificationDelivered,
            fallbackUsed: fallbackUsed,
            level: request.level,
            state: state,
            queueLength: queueLength,
            error: deliveryError
        )
        let soundOverride = request.sound.map { $0 ? "true" : "false" } ?? "config"
        let logMessage = "Notify handled. level=\(request.level.rawValue) chars=\(message.count) speak=\(request.speak) spoken=\(spoken) notification=\(notificationDelivered) sound_override=\(soundOverride) fallback_used=\(fallbackUsed) queue_length=\(queueLength) error=\(deliveryError ?? "")"
        logger.info("\(logMessage, privacy: .public)")
        PerformanceLog.record(category: "Notify", message: logMessage)
        return response
    }
    
    public func stopSpeaking() async throws {
        TTSPlaybackManager.shared.stop()
    }

    // MARK: - Server Hooks

    public func runServerHook(_ event: Config.ServerHookEvent, payload: ServerHookPayload, client: Config.ServerClientConfig?) async -> ServerHookResult {
        do {
            let config = try ConfigLoader.load()
            let hooks = hooksConfig(for: event, client: client, config: config)
            return try await ServerHookRunner.send(event: event, hooks: hooks, payload: payload.withClient(client))
        } catch {
            hooksLogger.warning("Server hook failed. event=\(event.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            PerformanceLog.record(category: "ServerHooks", message: "Failed \(event.rawValue): \(error.localizedDescription)")
            return ServerHookResult(ok: false, event: event, error: error.localizedDescription)
        }
    }

    public func testServerHook(_ event: Config.ServerHookEvent, client: Config.ServerClientConfig?) async -> ServerHookResult {
        await runServerHook(event, payload: .test(event: event), client: client)
    }

    private func triggerServerHook(_ event: Config.ServerHookEvent, payload: ServerHookPayload, client: Config.ServerClientConfig?) {
        Task { [weak self] in
            guard let self else { return }
            _ = await self.runServerHook(event, payload: payload, client: client)
        }
    }

    static func resolvedRequestSource(
        _ requestedSource: String?,
        client: Config.ServerClientConfig?,
        fallback: String
    ) -> String {
        if let client {
            return client.name.nilIfBlank ?? client.id
        }
        return requestedSource?.nilIfBlank ?? fallback
    }

    private func hooksConfig(
        for event: Config.ServerHookEvent,
        client: Config.ServerClientConfig?,
        config: Config
    ) -> Config.ServerHooksConfig {
        if let client, client.hooks.endpoint(for: event).enabled {
            return client.hooks
        }
        return config.server.hooks
    }

    private func deliverSystemNotification(
        for request: TTSNotifyRequest,
        message: String,
        config: Config.NotificationsConfig
    ) async throws {
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .sound])
        guard granted else {
            throw TTSNotifyError.notificationNotAuthorized
        }

        let content = UNMutableNotificationContent()
        content.title = request.title?.nilIfBlank ?? defaultNotificationTitle(for: request.level)
        content.body = message
        content.sound = shouldPlayNotificationSound(for: request, config: config) ? .default : nil
        content.interruptionLevel = interruptionLevel(for: request.level)
        content.userInfo = notificationUserInfo(for: request)

        try await center.add(
            UNNotificationRequest(
                identifier: "tsutae.notify.\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
        )
    }

    private func notificationUserInfo(for request: TTSNotifyRequest) -> [String: String] {
        var userInfo: [String: String] = [:]
        if let clickAction = request.clickAction {
            userInfo[TTSNotifyUserInfoKey.clickAction] = clickAction.rawValue
        }
        if let openURL = request.openURL?.nilIfBlank {
            userInfo[TTSNotifyUserInfoKey.openURL] = openURL
        }
        if let activateBundleID = request.activateBundleID?.nilIfBlank {
            userInfo[TTSNotifyUserInfoKey.activateBundleID] = activateBundleID
        }
        return userInfo
    }

    private func shouldPlayNotificationSound(for request: TTSNotifyRequest, config: Config.NotificationsConfig) -> Bool {
        if let sound = request.sound {
            return sound
        }
        switch config.soundPolicy {
        case .important:
            return request.level != .info
        case .all:
            return true
        case .silent:
            return false
        }
    }

    private func defaultNotificationTitle(for level: TTSNotifyLevel) -> String {
        switch level {
        case .info:
            return "Tsutae"
        case .warning:
            return "Tsutae Warning"
        case .error:
            return "Tsutae Error"
        }
    }

    private func interruptionLevel(for level: TTSNotifyLevel) -> UNNotificationInterruptionLevel {
        switch level {
        case .info:
            return .active
        case .warning:
            return .active
        case .error:
            return .timeSensitive
        }
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

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
