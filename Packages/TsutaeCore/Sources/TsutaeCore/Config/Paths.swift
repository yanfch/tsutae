import Foundation

/// tsutae 文件系统路径约定
/// 对应文档: gui-tui/docs/09-paths.md
///
/// 所有路径基于 `~/.tsutae/`，可通过环境变量 `TSUTAE_ROOT` 覆盖（测试用）。
public enum Paths {
    
    // MARK: - 根目录
    
    /// `~/.tsutae/`
    /// 支持环境变量 TSUTAE_ROOT 覆盖（测试用）
    public static var root: URL {
        if let env = ProcessInfo.processInfo.environment["TSUTAE_ROOT"] {
            return URL(fileURLWithPath: env)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".tsutae")
    }
    
    /// 重置缓存（测试用，目前无缓存，保留接口兼容）
    public static func resetCache() {
        // 无缓存，无需操作
    }
    
    // MARK: - 配置文件（可 git 同步）
    
    /// `~/.tsutae/config.yml` — 主配置
    public static var configYML: URL { root.appendingPathComponent("config.yml") }
    
    /// `~/.tsutae/hotkeys.yml` — 快捷键和 HUD
    public static var hotkeysYML: URL { root.appendingPathComponent("hotkeys.yml") }
    
    /// `~/.tsutae/engines/` — 引擎特化配置
    public static var engines: URL { root.appendingPathComponent("engines") }
    
    /// `~/.tsutae/recipes/` — 配方目录
    public static var recipes: URL { root.appendingPathComponent("recipes") }
    
    // MARK: - 数据目录（不进 git）
    
    /// `~/.tsutae/models/` — 下载的模型文件
    public static var models: URL { root.appendingPathComponent("models") }
    
    /// `~/.tsutae/traces/` — OTLP jsonl
    public static var traces: URL { root.appendingPathComponent("traces") }
    
    /// `~/.tsutae/state.db` — 运行状态数据库
    public static var stateDB: URL { root.appendingPathComponent("state.db") }
    
    /// `~/.tsutae/logs/` — 应用日志
    public static var logs: URL { root.appendingPathComponent("logs") }
    
    // MARK: - 子目录快捷方式
    
    /// STT 模型目录
    public static var sttModels: URL { models.appendingPathComponent("stt") }
    
    /// TTS 模型目录
    public static var ttsModels: URL { models.appendingPathComponent("tts") }
    
    /// VAD 模型目录
    public static var vadModels: URL { models.appendingPathComponent("vad") }
    
    // MARK: - 工具方法
    
    /// 确保目录存在，不存在则创建
    public static func ensureDirectories() throws {
        let fm = FileManager.default
        for dir in [root, engines, recipes, models, sttModels, ttsModels, vadModels, traces, logs] {
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
        
        // 创建 .gitignore（如果不存在）
        let gitignore = root.appendingPathComponent(".gitignore")
        if !fm.fileExists(atPath: gitignore.path) {
            let content = """
                models/
                traces/
                state.db
                state.db-*
                logs/
                *.log
                """
            try content.write(to: gitignore, atomically: true, encoding: .utf8)
        }
    }
}
