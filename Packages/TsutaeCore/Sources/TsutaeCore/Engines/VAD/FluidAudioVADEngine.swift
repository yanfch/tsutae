@preconcurrency import FluidAudio
import Foundation

public enum FluidAudioVADError: LocalizedError {
    case noSamples
    case notLoaded

    public var errorDescription: String? {
        switch self {
        case .noSamples:
            "VAD frame contains no PCM samples."
        case .notLoaded:
            "FluidAudio VAD did not finish loading."
        }
    }
}

public final class FluidAudioVADEngine: VADEngine, @unchecked Sendable {
    public static let shared = FluidAudioVADEngine()

    public let id = "fluid_audio_vad"
    public let displayName = "FluidAudio VAD"
    public let isLocal = true

    private let lock = NSLock()
    private var manager: VadManager?
    private var streamState: VadStreamState?
    private var _status: EngineStatus = .loading
    private var _sensitivity: Double

    public var status: EngineStatus {
        lock.lock()
        defer { lock.unlock() }
        return _status
    }

    public var sensitivity: Double {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _sensitivity
        }
        set {
            lock.lock()
            _sensitivity = Self.clamp(newValue)
            manager = nil
            streamState = nil
            _status = .loading
            lock.unlock()
        }
    }

    public init(sensitivity: Double = 0.5) {
        self._sensitivity = Self.clamp(sensitivity)
    }

    public func load() async throws {
        let sensitivity = self.sensitivity
        let vad = try await VadManager(
            config: VadConfig(defaultThreshold: Self.threshold(for: sensitivity))
        )
        let state = await vad.makeStreamState()
        setLoaded(manager: vad, state: state)
    }

    public func unload() {
        lock.lock()
        manager = nil
        streamState = nil
        _status = .loading
        lock.unlock()
    }

    public func reset() {
        lock.lock()
        streamState = nil
        lock.unlock()
    }

    public func detect(_ frame: AudioFrame) async throws -> VADResult {
        let samples = PCM16Audio.decode(frame)
        guard samples.isEmpty == false else {
            throw FluidAudioVADError.noSamples
        }

        let manager = try await loadedManager()
        var state = currentStreamState()
        var maxProbability: Float = 0
        var sawSpeech = false

        let chunkSize = VadManager.chunkSize
        for start in stride(from: 0, to: samples.count, by: chunkSize) {
            let end = min(start + chunkSize, samples.count)
            let chunk = Array(samples[start..<end])
            let result = try await manager.processStreamingChunk(chunk, state: state, config: .default)
            state = result.state
            maxProbability = max(maxProbability, result.probability)
            if result.event?.isStart == true || result.probability >= Self.threshold(for: sensitivity) {
                sawSpeech = true
            }
        }

        setStreamState(state)
        return VADResult(probability: Double(maxProbability), isSpeech: sawSpeech)
    }

    private func loadedManager() async throws -> VadManager {
        if let manager = currentManager() {
            return manager
        }

        try await load()

        if let loaded = currentManager() {
            return loaded
        }
        throw FluidAudioVADError.notLoaded
    }

    private func currentManager() -> VadManager? {
        lock.lock()
        defer { lock.unlock() }
        return manager
    }

    private func setLoaded(manager: VadManager, state: VadStreamState) {
        lock.lock()
        self.manager = manager
        self.streamState = state
        self._status = .ready
        lock.unlock()
    }

    private func storedStreamState() -> VadStreamState? {
        lock.lock()
        defer { lock.unlock() }
        return streamState
    }

    private func currentStreamState() -> VadStreamState {
        storedStreamState() ?? VadStreamState.initial()
    }

    private func setStreamState(_ state: VadStreamState) {
        lock.lock()
        streamState = state
        lock.unlock()
    }

    private static func threshold(for sensitivity: Double) -> Float {
        Float(0.95 - clamp(sensitivity) * 0.20)
    }

    private static func clamp(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }
}
