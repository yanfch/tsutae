import Foundation
import Yams

/// 快捷键配置模型
/// 对应文档: gui-tui/docs/07-integration.md, 01-voicebar.md
///
/// 配置文件: `~/.tsutae/hotkeys.yml`
public struct HotkeysConfig: Codable, Sendable {
    
    /// Leader 键配置（两段式快捷键）
    public var leader: LeaderConfig?
    
    /// 一段式快捷键列表
    public var hotkeys: [HotkeyEntry]
    
    public init(leader: LeaderConfig? = nil, hotkeys: [HotkeyEntry] = []) {
        self.leader = leader
        self.hotkeys = hotkeys
    }
}

/// Leader 键配置
public struct LeaderConfig: Codable, Sendable {
    
    /// Leader 键（如 "option+space"）
    public var key: String
    
    /// 不按第二段键时的默认 action
    public var defaultAction: ActionBinding
    
    /// HUD 显示超时（毫秒）
    public var hudTimeoutMs: Int
    
    /// HUD actions 列表
    public var hudActions: [HUDAction]
    
    public init(
        key: String,
        defaultAction: ActionBinding,
        hudTimeoutMs: Int = 1500,
        hudActions: [HUDAction] = []
    ) {
        self.key = key
        self.defaultAction = defaultAction
        self.hudTimeoutMs = hudTimeoutMs
        self.hudActions = hudActions
    }
}

/// HUD action 条目
public struct HUDAction: Codable, Sendable {
    
    /// 触发键（单字符，如 "n", "o"）
    public var key: String
    
    /// 显示标签
    public var label: String
    
    /// 图标（emoji）
    public var icon: String?
    
    /// 绑定的 recipe 名称（引用 ~/.tsutae/recipes/<name>.yml）
    public var recipe: String?
    
    /// 或者直接内联 action
    public var action: ActionBinding?
    
    /// 子菜单（一层嵌套）
    public var submenu: [HUDAction]?
    
    public init(
        key: String,
        label: String,
        icon: String? = nil,
        recipe: String? = nil,
        action: ActionBinding? = nil,
        submenu: [HUDAction]? = nil
    ) {
        self.key = key
        self.label = label
        self.icon = icon
        self.recipe = recipe
        self.action = action
        self.submenu = submenu
    }
}

/// 一段式快捷键条目
public struct HotkeyEntry: Codable, Sendable {
    
    /// 快捷键（如 "option+v", "option+c"）
    public var key: String
    
    /// 绑定的 recipe 名称
    public var recipe: String?
    
    /// 或者直接内联 action
    public var action: ActionBinding?
    
    public init(key: String, recipe: String? = nil, action: ActionBinding? = nil) {
        self.key = key
        self.recipe = recipe
        self.action = action
    }
}

/// Action 绑定（可以是预定义 action 或 post_http）
public enum ActionBinding: Codable, Sendable {
    
    /// 预定义 action
    case predefined(PredefinedAction)
    
    /// HTTP POST action
    case http(HTTPAction)
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case action
        case url, method, headers, body, bodyFormat
        case timeoutMs, retry
        case onSuccess, onFailure
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let actionType = try container.decode(String.self, forKey: .action)
        
        switch actionType {
        case "post_http", "open_url":
            let url = try container.decode(String.self, forKey: .url)
            let method = try container.decodeIfPresent(String.self, forKey: .method) ?? "POST"
            let headers = try container.decodeIfPresent([String: String].self, forKey: .headers)
            let body = try container.decodeIfPresent(String.self, forKey: .body)
            let bodyFormat = try container.decodeIfPresent(String.self, forKey: .bodyFormat)
            let timeoutMs = try container.decodeIfPresent(Int.self, forKey: .timeoutMs) ?? 5000
            let retry = try container.decodeIfPresent(Int.self, forKey: .retry) ?? 0
            
            self = .http(HTTPAction(
                url: url,
                method: method,
                headers: headers,
                body: body,
                bodyFormat: bodyFormat,
                timeoutMs: timeoutMs,
                retry: retry
            ))
            
        default:
            guard let predefined = PredefinedAction(rawValue: actionType) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .action,
                    in: container,
                    debugDescription: "Unknown action: \(actionType)"
                )
            }
            self = .predefined(predefined)
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .predefined(let action):
            try container.encode(action.rawValue, forKey: .action)
            
        case .http(let action):
            try container.encode("post_http", forKey: .action)
            try container.encode(action.url, forKey: .url)
            try container.encode(action.method, forKey: .method)
            try container.encodeIfPresent(action.headers, forKey: .headers)
            try container.encodeIfPresent(action.body, forKey: .body)
            try container.encodeIfPresent(action.bodyFormat, forKey: .bodyFormat)
            try container.encode(action.timeoutMs, forKey: .timeoutMs)
            try container.encode(action.retry, forKey: .retry)
        }
    }
}

/// 预定义 action 类型
public enum PredefinedAction: String, Codable, Sendable {
    /// 打开或关闭录音胶囊
    case toggleRecordingBar = "toggle_recording_bar"
    /// 转写到剪贴板
    case transcribeToClipboard = "transcribe_to_clipboard"
    /// 转写注入到焦点 App
    case sendToFocusedApp = "send_to_focused_app"
    /// 停止 TTS 播放
    case stopSpeaking = "stop_speaking"
    /// 打开 URL
    case openUrl = "open_url"
}

/// HTTP POST action 配置
public struct HTTPAction: Codable, Sendable {
    public var url: String
    public var method: String
    public var headers: [String: String]?
    public var body: String?
    public var bodyFormat: String?  // json, text, form_urlencoded
    public var timeoutMs: Int
    public var retry: Int
    
    public init(
        url: String,
        method: String = "POST",
        headers: [String: String]? = nil,
        body: String? = nil,
        bodyFormat: String? = nil,
        timeoutMs: Int = 5000,
        retry: Int = 0
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.bodyFormat = bodyFormat
        self.timeoutMs = timeoutMs
        self.retry = retry
    }
}

// MARK: - 加载器

public enum HotkeysLoader {
    
    /// 从 `~/.tsutae/hotkeys.yml` 加载配置
    /// 如果文件不存在，返回默认配置并保存
    public static func load() throws -> HotkeysConfig {
        let url = Paths.hotkeysYML
        
        // 如果配置文件不存在，创建默认配置
        if !FileManager.default.fileExists(atPath: url.path) {
            let config = HotkeysConfig.default
            try save(config)
            return config
        }
        
        // 读取并解析 YAML
        let data = try Data(contentsOf: url)
        let yaml = String(data: data, encoding: .utf8) ?? ""
        let decoder = YAMLDecoder()
        let config = try decoder.decode(HotkeysConfig.self, from: yaml)
        
        return config
    }
    
    /// 保存配置到 `~/.tsutae/hotkeys.yml`
    public static func save(_ config: HotkeysConfig) throws {
        let url = Paths.hotkeysYML
        let encoder = YAMLEncoder()
        let yaml = try encoder.encode(config)
        try yaml.write(to: url, atomically: true, encoding: .utf8)
    }
}

extension HotkeysConfig {
    
    /// 默认快捷键配置
    public static let `default` = HotkeysConfig(
        leader: LeaderConfig(
            key: "option+space",
            defaultAction: .predefined(.sendToFocusedApp),
            hudTimeoutMs: 1500,
            hudActions: [
                HUDAction(key: "c", label: "剪贴板", icon: "📋", action: .predefined(.transcribeToClipboard)),
                HUDAction(key: "v", label: "焦点 App", icon: "⌨️", action: .predefined(.sendToFocusedApp)),
            ]
        ),
        hotkeys: [
            HotkeyEntry(key: "option+v", action: .predefined(.sendToFocusedApp)),
            HotkeyEntry(key: "option+c", action: .predefined(.transcribeToClipboard)),
            HotkeyEntry(key: "option+escape", action: .predefined(.stopSpeaking)),
        ]
    )
}
