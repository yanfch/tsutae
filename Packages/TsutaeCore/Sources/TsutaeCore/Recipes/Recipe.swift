import Foundation
import Yams

/// Recipe（配方）模型
/// 对应文档: gui-tui/docs/08-recipes.md, 07-integration.md
///
/// 配方文件: `~/.tsutae/recipes/<name>.yml`
public struct Recipe: Codable, Sendable, Identifiable {
    
    /// 配方名称（等于文件名去 .yml）
    public var id: String { name }
    
    /// 配方名称
    public var name: String
    
    /// 描述
    public var description: String
    
    /// Action 类型（post_http / open_url / ...）
    public var action: String
    
    /// HTTP URL
    public var url: String?
    
    /// HTTP 方法
    public var method: String?
    
    /// HTTP Headers
    public var headers: [String: String]?
    
    /// Body 格式: json, text, form_urlencoded
    public var bodyFormat: String?
    
    /// Body 模板（支持占位符）
    public var body: String?
    
    /// 超时（毫秒）
    public var timeoutMs: Int?
    
    /// 重试次数
    public var retry: Int?
    
    /// 成功回调
    public var onSuccess: RecipeCallback?
    
    /// 失败回调
    public var onFailure: RecipeCallback?
    
    public init(
        name: String,
        description: String,
        action: String,
        url: String? = nil,
        method: String? = nil,
        headers: [String: String]? = nil,
        bodyFormat: String? = nil,
        body: String? = nil,
        timeoutMs: Int? = nil,
        retry: Int? = nil,
        onSuccess: RecipeCallback? = nil,
        onFailure: RecipeCallback? = nil
    ) {
        self.name = name
        self.description = description
        self.action = action
        self.url = url
        self.method = method
        self.headers = headers
        self.bodyFormat = bodyFormat
        self.body = body
        self.timeoutMs = timeoutMs
        self.retry = retry
        self.onSuccess = onSuccess
        self.onFailure = onFailure
    }
}

/// Recipe 回调配置
public struct RecipeCallback: Codable, Sendable {
    
    /// TTS 播报文本
    public var tts: String?
    
    /// 失败时是否把转写结果放剪贴板
    public var logToClipboard: Bool?
    
    public init(tts: String? = nil, logToClipboard: Bool? = nil) {
        self.tts = tts
        self.logToClipboard = logToClipboard
    }
}

// MARK: - Recipe 加载器

public enum RecipeLoader {
    
    /// 加载所有配方
    public static func loadAll() throws -> [Recipe] {
        let recipesDir = Paths.recipes
        let fm = FileManager.default
        
        // 确保目录存在
        if !fm.fileExists(atPath: recipesDir.path) {
            try fm.createDirectory(at: recipesDir, withIntermediateDirectories: true)
            return []
        }
        
        // 读取所有 .yml 文件
        let contents = try fm.contentsOfDirectory(at: recipesDir, includingPropertiesForKeys: nil)
        let ymlFiles = contents.filter { $0.pathExtension == "yml" || $0.pathExtension == "yaml" }
        
        var recipes: [Recipe] = []
        for file in ymlFiles {
            do {
                let recipe = try load(from: file)
                recipes.append(recipe)
            } catch {
                // 跳过无法解析的文件，打印警告
                print("Warning: Failed to load recipe \(file.lastPathComponent): \(error)")
            }
        }
        
        return recipes.sorted { $0.name < $1.name }
    }
    
    /// 按名称加载配方
    public static func load(name: String) throws -> Recipe {
        let url = Paths.recipes.appendingPathComponent("\(name).yml")
        return try load(from: url)
    }
    
    /// 从文件 URL 加载配方
    private static func load(from url: URL) throws -> Recipe {
        let data = try Data(contentsOf: url)
        let yaml = String(data: data, encoding: .utf8) ?? ""
        let decoder = YAMLDecoder()
        var recipe = try decoder.decode(Recipe.self, from: yaml)
        
        // 如果 name 为空，用文件名
        if recipe.name.isEmpty {
            recipe.name = url.deletingPathExtension().lastPathComponent
        }
        
        return recipe
    }
    
    /// 保存配方
    public static func save(_ recipe: Recipe) throws {
        let dir = Paths.recipes
        let url = dir.appendingPathComponent("\(recipe.name).yml")
        
        // 确保目录存在
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        
        let encoder = YAMLEncoder()
        let yaml = try encoder.encode(recipe)
        try yaml.write(to: url, atomically: true, encoding: .utf8)
    }
    
    /// 删除配方
    public static func delete(name: String) throws {
        let url = Paths.recipes.appendingPathComponent("\(name).yml")
        try FileManager.default.removeItem(at: url)
    }
    
    /// 检查配方是否存在
    public static func exists(name: String) -> Bool {
        let url = Paths.recipes.appendingPathComponent("\(name).yml")
        return FileManager.default.fileExists(atPath: url.path)
    }
}
