import Foundation

/// STT（语音转文字）引擎协议
/// 对应文档: gui-tui/docs/01-voicebar.md (§引擎抽象)
///
/// 实现此协议来添加新的 STT 引擎：
/// - WhisperKit（本地，CoreML）
/// - FluidAudio（本地，CoreML）
/// - AppleSpeech（系统）
/// - OpenAICompatible（HTTP API）
public protocol STTEngine: Sendable {
    
    /// 引擎唯一标识
    var id: String { get }
    
    /// 显示名称
    var displayName: String { get }
    
    /// 是否是本地引擎
    var isLocal: Bool { get }
    
    /// 当前状态
    var status: EngineStatus { get }
    
    /// 可用语言列表（空数组表示支持 auto）
    var supportedLanguages: [String] { get }
    
    /// 一次性转写
    /// - Parameters:
    ///   - audio: 音频数据
    ///   - language: 语言代码（nil = auto）
    /// - Returns: 转写结果
    func transcribe(_ audio: AudioData, language: String?) async throws -> Transcript
    
    /// 流式转写
    /// - Parameters:
    ///   - audio: 音频流
    ///   - language: 语言代码（nil = auto）
    /// - Returns: 转写更新流
    func stream(_ audio: AsyncStream<AudioChunk>, language: String?) -> AsyncThrowingStream<TranscriptUpdate, Error>
    
    /// 加载模型（如果需要）
    func load() async throws
    
    /// 卸载模型释放资源
    func unload()
}

// MARK: - 默认实现

extension STTEngine {
    
    /// 默认支持 auto 语言
    public var supportedLanguages: [String] { [] }
    
    /// 默认空实现
    public func load() async throws {}
    
    /// 默认空实现
    public func unload() {}
}
