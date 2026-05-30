import Foundation

/// TTS（文字转语音）引擎协议
/// 对应文档: gui-tui/docs/01-voicebar.md (§引擎抽象)
///
/// 实现此协议来添加新的 TTS 引擎：
/// - AVSpeechSynthesizer（系统）
/// - KokoroMLX（本地，MLX）
/// - OpenAICompatible（HTTP API）
/// - ElevenLabs（HTTP API）
public protocol TTSEngine: Sendable {
    
    /// 引擎唯一标识
    var id: String { get }
    
    /// 显示名称
    var displayName: String { get }
    
    /// 是否是本地引擎
    var isLocal: Bool { get }
    
    /// 当前状态
    var status: EngineStatus { get }
    
    /// 可用音色列表
    var voices: [Voice] { get }
    
    /// 一次性合成
    /// - Parameters:
    ///   - text: 要合成的文本
    ///   - voice: 音色
    ///   - options: 选项
    /// - Returns: 音频数据
    func synthesize(_ text: String, voice: Voice, options: TTSOptions) async throws -> AudioData
    
    /// 流式合成
    /// - Parameters:
    ///   - text: 文本流
    ///   - voice: 音色
    ///   - options: 选项
    /// - Returns: 音频块流
    func stream(_ text: AsyncStream<String>, voice: Voice, options: TTSOptions) -> AsyncThrowingStream<AudioChunk, Error>
    
    /// 加载模型（如果需要）
    func load() async throws
    
    /// 卸载模型释放资源
    func unload()
}

// MARK: - 默认实现

extension TTSEngine {
    
    /// 默认空音色列表
    public var voices: [Voice] { [] }
    
    /// 默认空实现
    public func load() async throws {}
    
    /// 默认空实现
    public func unload() {}
    
    /// 流式合成的默认实现（回退到一次性合成）
    public func stream(_ text: AsyncStream<String>, voice: Voice, options: TTSOptions) -> AsyncThrowingStream<AudioChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var fullText = ""
                    for try await chunk in text {
                        fullText += chunk
                    }
                    let audio = try await synthesize(fullText, voice: voice, options: options)
                    continuation.yield(AudioChunk(samples: audio.samples))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
