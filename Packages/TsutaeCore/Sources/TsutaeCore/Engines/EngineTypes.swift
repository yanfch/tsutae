import Foundation

/// 引擎状态
public enum EngineStatus: String, Codable, Sendable {
    /// 就绪可用
    case ready
    /// 加载中（如下载模型）
    case loading
    /// 错误不可用
    case error
}

/// 引擎信息
public struct EngineInfo: Codable, Sendable {
    /// 引擎 ID
    public let id: String
    
    /// 显示名称
    public let displayName: String
    
    /// 当前状态
    public let status: EngineStatus
    
    /// 是否是本地引擎
    public let isLocal: Bool
    
    public init(id: String, displayName: String, status: EngineStatus, isLocal: Bool) {
        self.id = id
        self.displayName = displayName
        self.status = status
        self.isLocal = isLocal
    }
}

// MARK: - STT 类型

public enum AudioContainerFormat: String, Codable, Sendable {
    case pcm16
    case wav
    case mp3
    case m4a
}

/// 音频数据
public struct AudioData: Sendable {
    /// 音频数据；本地 STT/TTS 默认是 PCM，远程 TTS 也可返回带容器的数据（如 wav/mp3）
    public let samples: Data
    
    /// 采样率
    public let sampleRate: Int
    
    /// 通道数
    public let channels: Int
    
    /// 容器格式
    public let container: AudioContainerFormat

    public init(samples: Data, sampleRate: Int = 16000, channels: Int = 1, container: AudioContainerFormat = .pcm16) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.channels = channels
        self.container = container
    }
}

/// 音频块（流式）
public struct AudioChunk: Sendable {
    /// PCM 数据
    public let samples: Data
    
    /// 时间戳（毫秒）
    public let timestampMs: Int
    
    public init(samples: Data, timestampMs: Int = 0) {
        self.samples = samples
        self.timestampMs = timestampMs
    }
}

/// 音频帧（VAD 用）
public struct AudioFrame: Sendable {
    /// PCM 数据
    public let samples: Data
    
    /// 帧序号
    public let frameIndex: Int
    
    public init(samples: Data, frameIndex: Int = 0) {
        self.samples = samples
        self.frameIndex = frameIndex
    }
}

/// 转写结果
public struct Transcript: Codable, Sendable {
    /// 转写文本
    public let text: String
    
    /// 检测到的语言
    public let language: String?
    
    /// 音频时长（毫秒）
    public let durationMs: Int?
    
    /// 置信度 (0.0 ~ 1.0)
    public let confidence: Double?
    
    /// 是否是最终结果
    public let isFinal: Bool
    
    public init(
        text: String,
        language: String? = nil,
        durationMs: Int? = nil,
        confidence: Double? = nil,
        isFinal: Bool = true
    ) {
        self.text = text
        self.language = language
        self.durationMs = durationMs
        self.confidence = confidence
        self.isFinal = isFinal
    }
}

/// 流式转写更新
public enum TranscriptUpdate: Sendable {
    /// 部分结果
    case partial(Transcript)
    
    /// 最终结果
    case final(Transcript)
    
    /// 错误
    case error(Error)
}

// MARK: - TTS 类型

/// TTS 选项
public struct TTSOptions: Codable, Sendable {
    /// 语速 (0.5 ~ 2.0)
    public let rate: Double
    
    /// 音量 (0.0 ~ 1.0)
    public let volume: Double
    
    /// 音高 (0.5 ~ 2.0)
    public let pitch: Double
    
    public init(rate: Double = 1.0, volume: Double = 1.0, pitch: Double = 1.0) {
        self.rate = rate
        self.volume = volume
        self.pitch = pitch
    }
}

/// TTS 音色
public struct Voice: Codable, Sendable, Identifiable {
    /// 音色 ID
    public let id: String
    
    /// 显示名称
    public let displayName: String
    
    /// 语言
    public let language: String
    
    /// 是否是 Premium 音色
    public let isPremium: Bool
    
    public init(id: String, displayName: String, language: String, isPremium: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.language = language
        self.isPremium = isPremium
    }
}

public struct TTSVoiceEngineInfo: Codable, Sendable {
    public let engine: EngineInfo
    public let voices: [Voice]

    public init(engine: EngineInfo, voices: [Voice]) {
        self.engine = engine
        self.voices = voices
    }
}

// MARK: - VAD 类型

/// VAD 检测结果
public struct VADResult: Sendable {
    /// 语音概率 (0.0 ~ 1.0)
    public let probability: Double
    
    /// 是否是语音
    public let isSpeech: Bool
    
    public init(probability: Double, isSpeech: Bool) {
        self.probability = probability
        self.isSpeech = isSpeech
    }
}
