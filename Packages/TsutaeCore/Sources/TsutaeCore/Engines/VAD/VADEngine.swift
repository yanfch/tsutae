import Foundation

/// VAD（语音活动检测）引擎协议
/// 对应文档: gui-tui/docs/01-voicebar.md (§引擎抽象)
///
/// 实现此协议来添加新的 VAD 引擎：
/// - SileroVAD（本地，ONNX/CoreML）— 业界标准
/// - EnergyVAD（纯算法）— 兜底
public protocol VADEngine: Sendable {
    
    /// 引擎唯一标识
    var id: String { get }
    
    /// 显示名称
    var displayName: String { get }
    
    /// 是否是本地引擎
    var isLocal: Bool { get }
    
    /// 当前状态
    var status: EngineStatus { get }
    
    /// 灵敏度 (0.0 ~ 1.0)
    var sensitivity: Double { get set }
    
    /// 检测单帧
    /// - Parameter frame: 音频帧
    /// - Returns: 检测结果
    func detect(_ frame: AudioFrame) -> VADResult
    
    /// 重置状态（如切换说话人时）
    func reset()
    
    /// 加载模型（如果需要）
    func load() async throws
    
    /// 卸载模型释放资源
    func unload()
}

// MARK: - 默认实现

extension VADEngine {
    
    /// 默认灵敏度
    public var sensitivity: Double {
        get { 0.5 }
        set { }
    }
    
    /// 默认空实现
    public func reset() {}
    
    /// 默认空实现
    public func load() async throws {}
    
    /// 默认空实现
    public func unload() {}
}
