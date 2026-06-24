import Foundation

public final class EnergyVADEngine: VADEngine, @unchecked Sendable {
    public static let shared = EnergyVADEngine()

    public let id = "energy"
    public let displayName = "Energy VAD"
    public let isLocal = true
    public let status: EngineStatus = .ready

    private let lock = NSLock()
    private var _sensitivity: Double

    public var sensitivity: Double {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _sensitivity
        }
        set {
            lock.lock()
            _sensitivity = Self.clamp(newValue)
            lock.unlock()
        }
    }

    public init(sensitivity: Double = 0.5) {
        self._sensitivity = Self.clamp(sensitivity)
    }

    public func detect(_ frame: AudioFrame) async throws -> VADResult {
        let samples = PCM16Audio.decode(frame)
        guard samples.isEmpty == false else {
            return VADResult(probability: 0, isSpeech: false)
        }

        let rms = Self.rms(samples)
        let threshold = Self.threshold(for: sensitivity)
        let probability = min(1.0, rms / max(threshold * 2.0, 0.0001))
        return VADResult(probability: probability, isSpeech: rms >= threshold)
    }

    private static func rms(_ samples: [Float]) -> Double {
        let sum = samples.reduce(Double.zero) { partial, sample in
            let value = Double(sample)
            return partial + value * value
        }
        return sqrt(sum / Double(samples.count))
    }

    private static func threshold(for sensitivity: Double) -> Double {
        0.05 - clamp(sensitivity) * 0.04
    }

    private static func clamp(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }
}
