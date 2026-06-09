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
        
        /// Premium 引擎 ID
        public var premiumEngine: String?
        
        /// Premium 音色
        public var premiumVoice: String?
        
        /// Premium 用于 /speak
        public var premiumForSpeak: Bool
        
        /// Premium 用于 /v1/audio/speech
        public var premiumForAPI: Bool
        
        public init(
            engine: String = "apple",
            voice: String? = nil,
            rate: Double = 1.0,
            presentationStyle: TTSPresentationStyle = .standard,
            interruptCurrent: Bool = true,
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
    
    public struct ServerConfig: Codable, Sendable {
        /// 端口
        public var port: Int
        
        /// 绑定地址
        public var bind: String
        
        /// 开机自启服务器
        public var autoStart: Bool
        
        public init(
            port: Int = 1338,
            bind: String = "127.0.0.1",
            autoStart: Bool = true
        ) {
            self.port = port
            self.bind = bind
            self.autoStart = autoStart
        }
    }
    
    // MARK: - 默认配置
    
    public static let `default` = Config(
        general: General(),
        stt: STTConfig(),
        tts: TTSConfig(),
        vad: VADConfig(),
        server: ServerConfig()
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
        
        // 读取并解析 YAML
        let data = try Data(contentsOf: url)
        let yaml = String(data: data, encoding: .utf8) ?? ""
        let decoder = YAMLDecoder()
        let config = try decoder.decode(Config.self, from: yaml)
        
        return config
    }
    
    /// 保存配置到 `~/.tsutae/config.yml`
    public static func save(_ config: Config) throws {
        let url = Paths.configYML
        let encoder = YAMLEncoder()
        let yaml = try encoder.encode(config)
        try yaml.write(to: url, atomically: true, encoding: .utf8)
    }
}
