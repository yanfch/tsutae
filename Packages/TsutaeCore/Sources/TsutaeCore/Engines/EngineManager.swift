import Foundation

/// 引擎管理器
/// 对应文档: gui-tui/docs/01-voicebar.md (§主引擎 + Fallback)
///
/// 职责：
/// - 注册/注销引擎
/// - 按 ID 获取引擎
/// - 主引擎 + fallback 自动切换
/// - 列出可用引擎
public final class EngineManager: @unchecked Sendable {
    
    // MARK: - 单例
    
    public static let shared = EngineManager()
    
    // MARK: - 引擎注册表
    
    private var sttEngines: [String: STTEngine] = [:]
    private var ttsEngines: [String: TTSEngine] = [:]
    private var vadEngines: [String: VADEngine] = [:]
    
    private let lock = NSLock()
    
    private init() {}
    
    // MARK: - STT
    
    /// 注册 STT 引擎
    public func registerSTT(_ engine: STTEngine) {
        lock.lock()
        defer { lock.unlock() }
        sttEngines[engine.id] = engine
    }
    
    /// 注销 STT 引擎
    public func unregisterSTT(id: String) {
        lock.lock()
        defer { lock.unlock() }
        sttEngines.removeValue(forKey: id)
    }
    
    /// 获取 STT 引擎
    public func stt(id: String) -> STTEngine? {
        lock.lock()
        defer { lock.unlock() }
        return sttEngines[id]
    }
    
    /// 列出所有 STT 引擎
    public func listSTT() -> [EngineInfo] {
        lock.lock()
        defer { lock.unlock() }
        return sttEngines.values.map { engine in
            EngineInfo(
                id: engine.id,
                displayName: engine.displayName,
                status: engine.status,
                isLocal: engine.isLocal
            )
        }.sorted { $0.id < $1.id }
    }
    
    /// 获取 STT 引擎，支持 fallback
    /// - Parameters:
    ///   - primary: 主引擎 ID
    ///   - fallback: fallback 引擎 ID（可选）
    /// - Returns: 可用的引擎
    public func getSTT(primary: String, fallback: String?) throws -> STTEngine {
        lock.lock()
        defer { lock.unlock() }
        
        // 尝试主引擎
        if let engine = sttEngines[primary], engine.status == .ready {
            return engine
        }
        
        // 尝试 fallback
        if let fallbackId = fallback, let engine = sttEngines[fallbackId], engine.status == .ready {
            return engine
        }
        
        // 都不可用
        throw EngineError.noAvailableEngine(type: "STT", primary: primary, fallback: fallback)
    }
    
    // MARK: - TTS
    
    /// 注册 TTS 引擎
    public func registerTTS(_ engine: TTSEngine) {
        lock.lock()
        defer { lock.unlock() }
        ttsEngines[engine.id] = engine
    }
    
    /// 注销 TTS 引擎
    public func unregisterTTS(id: String) {
        lock.lock()
        defer { lock.unlock() }
        ttsEngines.removeValue(forKey: id)
    }
    
    /// 获取 TTS 引擎
    public func tts(id: String) -> TTSEngine? {
        lock.lock()
        defer { lock.unlock() }
        return ttsEngines[id]
    }
    
    /// 列出所有 TTS 引擎
    public func listTTS() -> [EngineInfo] {
        lock.lock()
        defer { lock.unlock() }
        return ttsEngines.values.map { engine in
            EngineInfo(
                id: engine.id,
                displayName: engine.displayName,
                status: engine.status,
                isLocal: engine.isLocal
            )
        }.sorted { $0.id < $1.id }
    }

    /// 列出 TTS 引擎音色
    public func listTTSVoices(engineID: String? = nil) -> [TTSVoiceEngineInfo] {
        lock.lock()
        defer { lock.unlock() }

        let engines: [TTSEngine]
        if let engineID = engineID?.trimmingCharacters(in: .whitespacesAndNewlines), engineID.isEmpty == false {
            engines = ttsEngines[engineID].map { [$0] } ?? []
        } else {
            engines = Array(ttsEngines.values)
        }

        return engines.map { engine in
            TTSVoiceEngineInfo(
                engine: EngineInfo(
                    id: engine.id,
                    displayName: engine.displayName,
                    status: engine.status,
                    isLocal: engine.isLocal
                ),
                voices: engine.voices
            )
        }.sorted { $0.engine.id < $1.engine.id }
    }
    
    /// 获取 TTS 引擎，支持 fallback
    public func getTTS(primary: String, fallback: String?) throws -> TTSEngine {
        lock.lock()
        defer { lock.unlock() }
        
        if let engine = ttsEngines[primary], engine.status == .ready {
            return engine
        }
        
        if let fallbackId = fallback, let engine = ttsEngines[fallbackId], engine.status == .ready {
            return engine
        }
        
        throw EngineError.noAvailableEngine(type: "TTS", primary: primary, fallback: fallback)
    }
    
    // MARK: - VAD
    
    /// 注册 VAD 引擎
    public func registerVAD(_ engine: VADEngine) {
        lock.lock()
        defer { lock.unlock() }
        vadEngines[engine.id] = engine
    }
    
    /// 注销 VAD 引擎
    public func unregisterVAD(id: String) {
        lock.lock()
        defer { lock.unlock() }
        vadEngines.removeValue(forKey: id)
    }
    
    /// 获取 VAD 引擎
    public func vad(id: String) -> VADEngine? {
        lock.lock()
        defer { lock.unlock() }
        return vadEngines[id]
    }
    
    /// 列出所有 VAD 引擎
    public func listVAD() -> [EngineInfo] {
        lock.lock()
        defer { lock.unlock() }
        return vadEngines.values.map { engine in
            EngineInfo(
                id: engine.id,
                displayName: engine.displayName,
                status: engine.status,
                isLocal: engine.isLocal
            )
        }.sorted { $0.id < $1.id }
    }
    
    /// 获取 VAD 引擎，支持 fallback
    public func getVAD(primary: String, fallback: String?) throws -> VADEngine {
        lock.lock()
        defer { lock.unlock() }
        
        if let engine = vadEngines[primary], engine.status == .ready {
            return engine
        }
        
        if let fallbackId = fallback, let engine = vadEngines[fallbackId], engine.status == .ready {
            return engine
        }
        
        throw EngineError.noAvailableEngine(type: "VAD", primary: primary, fallback: fallback)
    }
    
    // MARK: - 批量操作
    
    /// 加载所有已注册引擎
    public func loadAll() async {
        await withTaskGroup(of: Void.self) { group in
            for engine in sttEngines.values {
                group.addTask {
                    try? await engine.load()
                }
            }
            for engine in ttsEngines.values {
                group.addTask {
                    try? await engine.load()
                }
            }
            for engine in vadEngines.values {
                group.addTask {
                    try? await engine.load()
                }
            }
        }
    }
    
    /// 卸载所有引擎
    public func unloadAll() {
        lock.lock()
        defer { lock.unlock() }
        
        for engine in sttEngines.values {
            engine.unload()
        }
        for engine in ttsEngines.values {
            engine.unload()
        }
        for engine in vadEngines.values {
            engine.unload()
        }
    }
}

// MARK: - 错误类型

public enum EngineError: LocalizedError {
    case noAvailableEngine(type: String, primary: String, fallback: String?)
    case engineNotFound(id: String)
    case engineNotReady(id: String, status: EngineStatus)
    
    public var errorDescription: String? {
        switch self {
        case .noAvailableEngine(let type, let primary, let fallback):
            if let fallback = fallback {
                return "No available \(type) engine (primary: \(primary), fallback: \(fallback))"
            }
            return "No available \(type) engine (primary: \(primary))"
        case .engineNotFound(let id):
            return "Engine not found: \(id)"
        case .engineNotReady(let id, let status):
            return "Engine \(id) is not ready (status: \(status.rawValue))"
        }
    }
}
