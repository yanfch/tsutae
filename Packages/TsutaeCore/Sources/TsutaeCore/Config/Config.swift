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
    
    public struct STTConfig: Codable, Sendable {
        /// 主引擎 ID
        public var engine: String
        
        /// 模型名称
        public var model: String?
        
        /// 语言
        public var language: String?
        
        /// Fallback 引擎 ID
        public var fallbackEngine: String?
        
        /// Fallback Base URL（用于 OpenAI 兼容引擎）
        public var fallbackBaseURL: String?
        
        /// Fallback API Key 引用名（存在 Keychain）
        public var fallbackAPIKeyRef: String?
        
        public init(
            engine: String = "apple",
            model: String? = nil,
            language: String? = nil,
            fallbackEngine: String? = nil,
            fallbackBaseURL: String? = nil,
            fallbackAPIKeyRef: String? = nil
        ) {
            self.engine = engine
            self.model = model
            self.language = language
            self.fallbackEngine = fallbackEngine
            self.fallbackBaseURL = fallbackBaseURL
            self.fallbackAPIKeyRef = fallbackAPIKeyRef
        }
    }
    
    public struct TTSConfig: Codable, Sendable {
        /// 主引擎 ID
        public var engine: String
        
        /// 音色
        public var voice: String?
        
        /// 语速 (0.5 ~ 2.0)
        public var rate: Double
        
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
            premiumEngine: String? = nil,
            premiumVoice: String? = nil,
            premiumForSpeak: Bool = false,
            premiumForAPI: Bool = false
        ) {
            self.engine = engine
            self.voice = voice
            self.rate = rate
            self.premiumEngine = premiumEngine
            self.premiumVoice = premiumVoice
            self.premiumForSpeak = premiumForSpeak
            self.premiumForAPI = premiumForAPI
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
