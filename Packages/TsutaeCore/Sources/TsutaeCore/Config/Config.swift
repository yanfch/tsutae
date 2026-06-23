import Foundation
import Yams

/// tsutae 主配置模型
/// 对应文档: gui-tui/docs/01-voicebar.md, 09-paths.md
///
/// 配置文件: `~/.tsutae/config.yml`
public struct Config: Codable, Sendable {
    
    /// 通用设置
    public var general: General
    
    /// STT 引擎设置
    public var stt: STTConfig
    
    /// TTS 引擎设置
    public var tts: TTSConfig
    
    /// VAD 设置
    public var vad: VADConfig
    
    /// 服务器设置
    public var server: ServerConfig

    /// 系统通知设置
    public var notifications: NotificationsConfig

    /// 转写后处理设置
    public var postProcessing: TranscriptPostProcessingConfig
    
    // MARK: - 子类型
    
    public struct General: Codable, Sendable {
        /// 开机自启
        public var launchAtLogin: Bool
        
        /// 默认语言（auto / zh / en / ...）
        public var language: String
        
        /// 界面语言
        public var uiLanguage: String
        
        public init(
            launchAtLogin: Bool = false,
            language: String = "auto",
            uiLanguage: String = "auto"
        ) {
            self.launchAtLogin = launchAtLogin
            self.language = language
            self.uiLanguage = uiLanguage
        }
    }

    public enum NotificationSoundPolicy: String, Codable, CaseIterable, Sendable {
        case important
        case all
        case silent
    }

    public struct NotificationsConfig: Codable, Sendable {
        /// 系统通知声音策略
        public var soundPolicy: NotificationSoundPolicy

        public init(soundPolicy: NotificationSoundPolicy = .important) {
            self.soundPolicy = soundPolicy
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.soundPolicy = try container.decodeIfPresent(NotificationSoundPolicy.self, forKey: .soundPolicy) ?? .important
        }
    }

    public enum TranscriptPostProcessingMode: String, Codable, CaseIterable, Sendable {
        case off
        case smart
        case rules
        case remote
    }

    public enum TranscriptPostProcessingTask: String, Codable, CaseIterable, Sendable {
        case cleanDictation
        case rewriteMessage
        case meetingNotes
    }

    public struct TranscriptPostProcessingRemoteConfig: Codable, Sendable {
        public var enabled: Bool
        public var baseURL: String?
        public var model: String?
        public var apiKeyRef: String?

        public init(
            enabled: Bool = false,
            baseURL: String? = nil,
            model: String? = nil,
            apiKeyRef: String? = nil
        ) {
            self.enabled = enabled
            self.baseURL = baseURL
            self.model = model
            self.apiKeyRef = apiKeyRef
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
            self.baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL)
            self.model = try container.decodeIfPresent(String.self, forKey: .model)
            self.apiKeyRef = try container.decodeIfPresent(String.self, forKey: .apiKeyRef)
        }
    }

    public struct TranscriptDictionaryEntry: Codable, Sendable, Identifiable, Equatable {
        public var id: String
        public var key: String
        public var value: String
        public var enabled: Bool

        public init(
            id: String = UUID().uuidString,
            key: String,
            value: String,
            enabled: Bool = true
        ) {
            self.id = id
            self.key = key
            self.value = value
            self.enabled = enabled
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
            self.key = try container.decodeIfPresent(String.self, forKey: .key) ?? ""
            self.value = try container.decodeIfPresent(String.self, forKey: .value) ?? ""
            self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        }
    }

    public struct TranscriptDictionaryConfig: Codable, Sendable {
        public var enabled: Bool
        public var useBuiltIn: Bool
        public var useAutomatic: Bool
        public var entries: [TranscriptDictionaryEntry]

        public init(
            enabled: Bool = true,
            useBuiltIn: Bool = true,
            useAutomatic: Bool = true,
            entries: [TranscriptDictionaryEntry] = []
        ) {
            self.enabled = enabled
            self.useBuiltIn = useBuiltIn
            self.useAutomatic = useAutomatic
            self.entries = entries
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
            self.useBuiltIn = try container.decodeIfPresent(Bool.self, forKey: .useBuiltIn) ?? true
            self.useAutomatic = try container.decodeIfPresent(Bool.self, forKey: .useAutomatic) ?? true
            self.entries = try container.decodeIfPresent([TranscriptDictionaryEntry].self, forKey: .entries) ?? []
        }
    }

    public struct TranscriptPostProcessingConfig: Codable, Sendable {
        public var enabled: Bool
        public var mode: TranscriptPostProcessingMode
        public var defaultTask: TranscriptPostProcessingTask
        public var remote: TranscriptPostProcessingRemoteConfig
        public var dictionary: TranscriptDictionaryConfig

        public init(
            enabled: Bool = true,
            mode: TranscriptPostProcessingMode = .smart,
            defaultTask: TranscriptPostProcessingTask = .cleanDictation,
            remote: TranscriptPostProcessingRemoteConfig = TranscriptPostProcessingRemoteConfig(),
            dictionary: TranscriptDictionaryConfig = TranscriptDictionaryConfig()
        ) {
            self.enabled = enabled
            self.mode = mode
            self.defaultTask = defaultTask
            self.remote = remote
            self.dictionary = dictionary
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
            self.mode = try container.decodeIfPresent(TranscriptPostProcessingMode.self, forKey: .mode) ?? .smart
            self.defaultTask = try container.decodeIfPresent(TranscriptPostProcessingTask.self, forKey: .defaultTask) ?? .cleanDictation
            self.remote = try container.decodeIfPresent(TranscriptPostProcessingRemoteConfig.self, forKey: .remote) ?? TranscriptPostProcessingRemoteConfig()
            self.dictionary = try container.decodeIfPresent(TranscriptDictionaryConfig.self, forKey: .dictionary) ?? TranscriptDictionaryConfig()
        }
    }
    
    public enum STTRoutingMode: String, Codable, CaseIterable, Sendable {
        case localFirst
        case remoteFirst
    }
    
    public enum STTRemoteRequestStyle: String, Codable, CaseIterable, Sendable {
        case audioTranscriptions
        case chatCompletionsAudio
    }
    
    public struct STTRemoteConfig: Codable, Sendable {
        /// 是否启用远程 API
        public var enabled: Bool
        
        /// OpenAI-compatible base URL
        public var baseURL: String?
        
        /// 远程模型名称
        public var model: String?
        
        /// 远程请求协议
        public var requestStyle: STTRemoteRequestStyle
        
        /// API Key 引用名（存在 Keychain）
        public var apiKeyRef: String?
        
        public init(
            enabled: Bool = false,
            baseURL: String? = nil,
            model: String? = nil,
            requestStyle: STTRemoteRequestStyle = .audioTranscriptions,
            apiKeyRef: String? = nil
        ) {
            self.enabled = enabled
            self.baseURL = baseURL
            self.model = model
            self.requestStyle = requestStyle
            self.apiKeyRef = apiKeyRef
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
            self.baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL)
            self.model = try container.decodeIfPresent(String.self, forKey: .model)
            self.requestStyle = try container.decodeIfPresent(STTRemoteRequestStyle.self, forKey: .requestStyle) ?? .audioTranscriptions
            self.apiKeyRef = try container.decodeIfPresent(String.self, forKey: .apiKeyRef)
        }
    }
    
    public struct STTLocalConfig: Codable, Sendable {
        /// 默认本地模型 ID
        public var preferredModel: String?
        
        /// 已下载模型 ID（仅作配置记忆，磁盘探测仍以运行时为准）
        public var downloadedModels: [String]
        
        /// 预览模型 ID
        public var previewModel: String?
        
        /// 最终模型 ID
        public var finalModel: String?
        
        /// Remote First 下是否仍保持本地模型热加载待命
        public var keepModelWarmedInRemoteFirst: Bool
        
        public init(
            preferredModel: String? = nil,
            downloadedModels: [String] = [],
            previewModel: String? = nil,
            finalModel: String? = nil,
            keepModelWarmedInRemoteFirst: Bool = false
        ) {
            self.preferredModel = preferredModel
            self.downloadedModels = downloadedModels
            self.previewModel = previewModel
            self.finalModel = finalModel
            self.keepModelWarmedInRemoteFirst = keepModelWarmedInRemoteFirst
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.preferredModel = try container.decodeIfPresent(String.self, forKey: .preferredModel)
            self.downloadedModels = try container.decodeIfPresent([String].self, forKey: .downloadedModels) ?? []
            self.previewModel = try container.decodeIfPresent(String.self, forKey: .previewModel)
            self.finalModel = try container.decodeIfPresent(String.self, forKey: .finalModel)
            self.keepModelWarmedInRemoteFirst = try container.decodeIfPresent(Bool.self, forKey: .keepModelWarmedInRemoteFirst) ?? false
        }
    }
    
    public struct STTConfig: Codable, Sendable {
        /// 路由模式
        public var mode: STTRoutingMode
        
        /// 本地主引擎 ID
        public var engine: String
        
        /// 当前主模型 ID
        public var model: String?
        
        /// 语言
        public var language: String?
        
        /// Fallback 引擎 ID
        public var fallbackEngine: String?
        
        /// 兼容旧配置：fallback Base URL（用于 OpenAI-compatible）
        public var fallbackBaseURL: String?
        
        /// 兼容旧配置：fallback API Key 引用名（存在 Keychain）
        public var fallbackAPIKeyRef: String?
        
        /// 远程 API 设置
        public var remote: STTRemoteConfig
        
        /// 本地模型设置
        public var local: STTLocalConfig
        
        public init(
            mode: STTRoutingMode = .localFirst,
            engine: String = "fluidaudio_local",
            model: String? = "parakeet-tdt-v3",
            language: String? = nil,
            fallbackEngine: String? = "apple_speech",
            fallbackBaseURL: String? = nil,
            fallbackAPIKeyRef: String? = nil,
            remote: STTRemoteConfig = STTRemoteConfig(),
            local: STTLocalConfig = STTLocalConfig(
                preferredModel: "parakeet-tdt-v3",
                downloadedModels: [],
                previewModel: "parakeet-eou",
                finalModel: "parakeet-tdt-v3"
            )
        ) {
            self.mode = mode
            self.engine = engine
            self.model = model
            self.language = language
            self.fallbackEngine = fallbackEngine
            self.fallbackBaseURL = fallbackBaseURL
            self.fallbackAPIKeyRef = fallbackAPIKeyRef
            self.remote = remote
            self.local = local
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let defaults = STTConfig()
            
            let legacyFallbackBaseURL = try container.decodeIfPresent(String.self, forKey: .fallbackBaseURL)
            let legacyFallbackAPIKeyRef = try container.decodeIfPresent(String.self, forKey: .fallbackAPIKeyRef)
            let legacyModel = try container.decodeIfPresent(String.self, forKey: .model)
            
            self.mode = try container.decodeIfPresent(STTRoutingMode.self, forKey: .mode) ?? defaults.mode
            self.engine = try container.decodeIfPresent(String.self, forKey: .engine) ?? defaults.engine
            self.model = legacyModel ?? defaults.model
            self.language = try container.decodeIfPresent(String.self, forKey: .language) ?? defaults.language
            self.fallbackEngine = try container.decodeIfPresent(String.self, forKey: .fallbackEngine) ?? defaults.fallbackEngine
            self.fallbackBaseURL = legacyFallbackBaseURL
            self.fallbackAPIKeyRef = legacyFallbackAPIKeyRef
            self.remote = try container.decodeIfPresent(STTRemoteConfig.self, forKey: .remote)
                ?? STTRemoteConfig(
                    enabled: legacyFallbackBaseURL != nil || legacyFallbackAPIKeyRef != nil,
                    baseURL: legacyFallbackBaseURL,
                    model: nil,
                    requestStyle: .audioTranscriptions,
                    apiKeyRef: legacyFallbackAPIKeyRef
                )
            self.local = try container.decodeIfPresent(STTLocalConfig.self, forKey: .local)
                ?? STTLocalConfig(
                    preferredModel: legacyModel ?? defaults.local.preferredModel,
                    downloadedModels: [],
                    previewModel: defaults.local.previewModel,
                    finalModel: legacyModel ?? defaults.local.finalModel
                )
        }
    }

    public enum TTSPresentationStyle: String, Codable, CaseIterable, Sendable {
        case standard
        case minimal
    }

    public enum TTSRemoteRequestStyle: String, Codable, CaseIterable, Sendable {
        case audioSpeech
        case chatCompletionsAudio
    }

    public struct TTSLocalConfig: Codable, Sendable {
        public var enabled: Bool

        public init(enabled: Bool = true) {
            self.enabled = enabled
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        }
    }

    public struct TTSRemoteConfig: Codable, Sendable {
        public var enabled: Bool
        public var baseURL: String?
        public var model: String?
        public var voice: String?
        public var requestStyle: TTSRemoteRequestStyle
        public var apiKeyRef: String?
        public var instructions: String?

        public init(
            enabled: Bool = false,
            baseURL: String? = nil,
            model: String? = nil,
            voice: String? = nil,
            requestStyle: TTSRemoteRequestStyle = .audioSpeech,
            apiKeyRef: String? = nil,
            instructions: String? = nil
        ) {
            self.enabled = enabled
            self.baseURL = baseURL
            self.model = model
            self.voice = voice
            self.requestStyle = requestStyle
            self.apiKeyRef = apiKeyRef
            self.instructions = instructions
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
            self.baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL)
            self.model = try container.decodeIfPresent(String.self, forKey: .model)
            self.voice = try container.decodeIfPresent(String.self, forKey: .voice)
            self.requestStyle = try container.decodeIfPresent(TTSRemoteRequestStyle.self, forKey: .requestStyle) ?? .audioSpeech
            self.apiKeyRef = try container.decodeIfPresent(String.self, forKey: .apiKeyRef)
            self.instructions = try container.decodeIfPresent(String.self, forKey: .instructions)
        }
    }

    public struct TTSConfig: Codable, Sendable {
        /// 主引擎 ID
        public var engine: String
        
        /// 音色
        public var voice: String?
        
        /// 语速 (0.5 ~ 2.0)
        public var rate: Double
        
        /// speaking 胶囊展示密度
        public var presentationStyle: TTSPresentationStyle
        
        /// 新播报是否打断当前播放
        public var interruptCurrent: Bool

        /// 当前正在播报时是否排队等待
        public var queueWhenBusy: Bool

        /// 本地 TTS 设置
        public var local: TTSLocalConfig
        
        /// 远程 API 设置
        public var remote: TTSRemoteConfig

        /// 失败时允许回退的引擎 ID
        public var fallbackEngine: String?

        /// 兼容旧配置：Premium 引擎 ID
        public var premiumEngine: String?
        
        /// 兼容旧配置：Premium 音色
        public var premiumVoice: String?
        
        /// 兼容旧配置：Premium 用于 /speak
        public var premiumForSpeak: Bool
        
        /// 兼容旧配置：Premium 用于 /v1/audio/speech
        public var premiumForAPI: Bool
        
        public init(
            engine: String = "apple",
            voice: String? = nil,
            rate: Double = 1.0,
            presentationStyle: TTSPresentationStyle = .standard,
            interruptCurrent: Bool = true,
            queueWhenBusy: Bool = true,
            local: TTSLocalConfig = TTSLocalConfig(),
            remote: TTSRemoteConfig = TTSRemoteConfig(),
            fallbackEngine: String? = nil,
            premiumEngine: String? = nil,
            premiumVoice: String? = nil,
            premiumForSpeak: Bool = false,
            premiumForAPI: Bool = false
        ) {
            self.engine = engine
            self.voice = voice
            self.rate = rate
            self.presentationStyle = presentationStyle
            self.interruptCurrent = interruptCurrent
            self.queueWhenBusy = queueWhenBusy
            self.local = local
            self.remote = remote
            self.fallbackEngine = fallbackEngine
            self.premiumEngine = premiumEngine
            self.premiumVoice = premiumVoice
            self.premiumForSpeak = premiumForSpeak
            self.premiumForAPI = premiumForAPI
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let defaults = TTSConfig()
            self.engine = try container.decodeIfPresent(String.self, forKey: .engine) ?? defaults.engine
            self.voice = try container.decodeIfPresent(String.self, forKey: .voice)
            self.rate = try container.decodeIfPresent(Double.self, forKey: .rate) ?? defaults.rate
            self.presentationStyle = try container.decodeIfPresent(TTSPresentationStyle.self, forKey: .presentationStyle) ?? defaults.presentationStyle
            self.interruptCurrent = try container.decodeIfPresent(Bool.self, forKey: .interruptCurrent) ?? defaults.interruptCurrent
            self.queueWhenBusy = try container.decodeIfPresent(Bool.self, forKey: .queueWhenBusy) ?? defaults.queueWhenBusy
            self.local = try container.decodeIfPresent(TTSLocalConfig.self, forKey: .local) ?? defaults.local
            self.remote = try container.decodeIfPresent(TTSRemoteConfig.self, forKey: .remote) ?? defaults.remote
            self.fallbackEngine = try container.decodeIfPresent(String.self, forKey: .fallbackEngine) ?? defaults.fallbackEngine
            self.premiumEngine = try container.decodeIfPresent(String.self, forKey: .premiumEngine)
            self.premiumVoice = try container.decodeIfPresent(String.self, forKey: .premiumVoice)
            self.premiumForSpeak = try container.decodeIfPresent(Bool.self, forKey: .premiumForSpeak) ?? defaults.premiumForSpeak
            self.premiumForAPI = try container.decodeIfPresent(Bool.self, forKey: .premiumForAPI) ?? defaults.premiumForAPI
        }
    }
    
    public struct VADConfig: Codable, Sendable {
        /// VAD 引擎 ID
        public var engine: String
        
        /// 灵敏度 (0.0 ~ 1.0)
        public var sensitivity: Double
        
        /// 停顿时长（毫秒）
        public var pauseDurationMs: Int
        
        /// 允许打断
        public var allowBargeIn: Bool
        
        /// 回声消除
        public var echoCancel: Bool
        
        public init(
            engine: String = "energy",
            sensitivity: Double = 0.5,
            pauseDurationMs: Int = 800,
            allowBargeIn: Bool = true,
            echoCancel: Bool = true
        ) {
            self.engine = engine
            self.sensitivity = sensitivity
            self.pauseDurationMs = pauseDurationMs
            self.allowBargeIn = allowBargeIn
            self.echoCancel = echoCancel
        }
    }
    
    public enum ServerHookEvent: String, Codable, CaseIterable, Sendable {
        case onTranscribed
        case onSpoken
        case onError
    }

    public enum ServerClientScope: String, Codable, CaseIterable, Sendable {
        case state
        case models
        case transcribe
        case audioSpeech
        case speak
        case notify
        case stop
        case listen
        case recipes
        case secrets
        case configRead

        public static var defaultScopes: [ServerClientScope] {
            [.state, .models, .transcribe, .audioSpeech, .speak, .notify, .stop]
        }
    }

    public struct ServerHookEndpoint: Codable, Sendable {
        /// 是否启用该 hook
        public var enabled: Bool

        /// Webhook URL
        public var url: String?

        /// 认证 token 的 Keychain 引用名
        public var tokenRef: String?

        /// 请求超时（毫秒）
        public var timeoutMs: Int

        public init(
            enabled: Bool = false,
            url: String? = nil,
            tokenRef: String? = nil,
            timeoutMs: Int = 5_000
        ) {
            self.enabled = enabled
            self.url = url
            self.tokenRef = tokenRef
            self.timeoutMs = timeoutMs
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
            self.url = try container.decodeIfPresent(String.self, forKey: .url)
            self.tokenRef = try container.decodeIfPresent(String.self, forKey: .tokenRef)
            self.timeoutMs = try container.decodeIfPresent(Int.self, forKey: .timeoutMs) ?? 5_000
        }
    }

    public struct ServerHooksConfig: Codable, Sendable {
        public var onTranscribed: ServerHookEndpoint
        public var onSpoken: ServerHookEndpoint
        public var onError: ServerHookEndpoint

        public init(
            onTranscribed: ServerHookEndpoint = ServerHookEndpoint(),
            onSpoken: ServerHookEndpoint = ServerHookEndpoint(),
            onError: ServerHookEndpoint = ServerHookEndpoint()
        ) {
            self.onTranscribed = onTranscribed
            self.onSpoken = onSpoken
            self.onError = onError
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.onTranscribed = try container.decodeIfPresent(ServerHookEndpoint.self, forKey: .onTranscribed) ?? ServerHookEndpoint()
            self.onSpoken = try container.decodeIfPresent(ServerHookEndpoint.self, forKey: .onSpoken) ?? ServerHookEndpoint()
            self.onError = try container.decodeIfPresent(ServerHookEndpoint.self, forKey: .onError) ?? ServerHookEndpoint()
        }

        public func endpoint(for event: ServerHookEvent) -> ServerHookEndpoint {
            switch event {
            case .onTranscribed:
                return onTranscribed
            case .onSpoken:
                return onSpoken
            case .onError:
                return onError
            }
        }
    }

    public struct ServerClientConfig: Codable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var enabled: Bool
        public var tokenHash: String
        public var scopes: [ServerClientScope]
        public var hooks: ServerHooksConfig
        public var createdAt: String?

        public init(
            id: String,
            name: String,
            enabled: Bool = true,
            tokenHash: String,
            scopes: [ServerClientScope] = ServerClientScope.defaultScopes,
            hooks: ServerHooksConfig = ServerHooksConfig(),
            createdAt: String? = nil
        ) {
            self.id = id
            self.name = name
            self.enabled = enabled
            self.tokenHash = tokenHash
            self.scopes = scopes
            self.hooks = hooks
            self.createdAt = createdAt
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try container.decode(String.self, forKey: .id)
            self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? id
            self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
            self.tokenHash = try container.decode(String.self, forKey: .tokenHash)
            self.scopes = try container.decodeIfPresent([ServerClientScope].self, forKey: .scopes) ?? ServerClientScope.defaultScopes
            self.hooks = try container.decodeIfPresent(ServerHooksConfig.self, forKey: .hooks) ?? ServerHooksConfig()
            self.createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        }

        public func hasScope(_ scope: ServerClientScope) -> Bool {
            scopes.contains(scope)
        }
    }

    public struct ServerConfig: Codable, Sendable {
        /// 端口
        public var port: Int
        
        /// 绑定地址
        public var bind: String
        
        /// 开机自启服务器
        public var autoStart: Bool

        /// 是否要求所有 API 请求携带 client token
        public var requireToken: Bool

        /// 外部应用/client 列表
        public var clients: [ServerClientConfig]

        /// 服务事件 hooks
        public var hooks: ServerHooksConfig

        public init(
            port: Int = 1338,
            bind: String = "127.0.0.1",
            autoStart: Bool = true,
            requireToken: Bool = false,
            clients: [ServerClientConfig] = [],
            hooks: ServerHooksConfig = ServerHooksConfig()
        ) {
            self.port = port
            self.bind = bind
            self.autoStart = autoStart
            self.requireToken = requireToken
            self.clients = clients
            self.hooks = hooks
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 1338
            self.bind = try container.decodeIfPresent(String.self, forKey: .bind) ?? "127.0.0.1"
            self.autoStart = try container.decodeIfPresent(Bool.self, forKey: .autoStart) ?? true
            self.requireToken = try container.decodeIfPresent(Bool.self, forKey: .requireToken) ?? false
            self.clients = try container.decodeIfPresent([ServerClientConfig].self, forKey: .clients) ?? []
            self.hooks = try container.decodeIfPresent(ServerHooksConfig.self, forKey: .hooks) ?? ServerHooksConfig()
        }
    }

    enum CodingKeys: String, CodingKey {
        case general, stt, tts, vad, server, notifications, postProcessing
    }

    public init(
        general: General = General(),
        stt: STTConfig = STTConfig(),
        tts: TTSConfig = TTSConfig(),
        vad: VADConfig = VADConfig(),
        server: ServerConfig = ServerConfig(),
        notifications: NotificationsConfig = NotificationsConfig(),
        postProcessing: TranscriptPostProcessingConfig = TranscriptPostProcessingConfig()
    ) {
        self.general = general
        self.stt = stt
        self.tts = tts
        self.vad = vad
        self.server = server
        self.notifications = notifications
        self.postProcessing = postProcessing
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.general = try container.decodeIfPresent(General.self, forKey: .general) ?? General()
        self.stt = try container.decodeIfPresent(STTConfig.self, forKey: .stt) ?? STTConfig()
        self.tts = try container.decodeIfPresent(TTSConfig.self, forKey: .tts) ?? TTSConfig()
        self.vad = try container.decodeIfPresent(VADConfig.self, forKey: .vad) ?? VADConfig()
        self.server = try container.decodeIfPresent(ServerConfig.self, forKey: .server) ?? ServerConfig()
        self.notifications = try container.decodeIfPresent(NotificationsConfig.self, forKey: .notifications) ?? NotificationsConfig()
        self.postProcessing = try container.decodeIfPresent(TranscriptPostProcessingConfig.self, forKey: .postProcessing) ?? TranscriptPostProcessingConfig()
    }
    
    // MARK: - 默认配置
    
    public static let `default` = Config(
        general: General(),
        stt: STTConfig(),
        tts: TTSConfig(),
        vad: VADConfig(),
        server: ServerConfig(),
        notifications: NotificationsConfig(),
        postProcessing: TranscriptPostProcessingConfig()
    )
}

// MARK: - 配置加载/保存

public enum ConfigLoader {
    
    /// 从 `~/.tsutae/config.yml` 加载配置
    /// 如果文件不存在，返回默认配置并保存
    public static func load() throws -> Config {
        let url = Paths.configYML
        
        // 确保目录存在
        try Paths.ensureDirectories()
        
        // 如果配置文件不存在，创建默认配置
        if !FileManager.default.fileExists(atPath: url.path) {
            let config = Config.default
            try save(config)
            return config
        }
        
        return try load(from: url)
    }

    /// 从指定 YAML 文件加载配置，不创建默认文件。
    public static func load(from url: URL) throws -> Config {
        let data = try Data(contentsOf: url)
        let yaml = String(data: data, encoding: .utf8) ?? ""
        let decoder = YAMLDecoder()
        return try decoder.decode(Config.self, from: yaml)
    }
    
    /// 保存配置到 `~/.tsutae/config.yml`
    public static func save(_ config: Config) throws {
        let url = Paths.configYML
        let encoder = YAMLEncoder()
        let yaml = try encoder.encode(config)
        try yaml.write(to: url, atomically: true, encoding: .utf8)
    }
}
