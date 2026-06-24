import Foundation

public enum ConfiguredVADDetector {
    public static func detect(
        _ frame: AudioFrame,
        config: Config? = nil,
        engineManager: EngineManager = .shared
    ) async throws -> VADResult {
        let resolvedConfig = try config ?? ConfigLoader.load()
        let engineID = resolvedConfig.vad.engine
        guard var engine = engineManager.vad(id: engineID) else {
            throw EngineError.engineNotFound(id: engineID)
        }

        if abs(engine.sensitivity - resolvedConfig.vad.sensitivity) > 0.0001 {
            engine.sensitivity = resolvedConfig.vad.sensitivity
        }
        if engine.status != .ready {
            try await engine.load()
        }
        return try await engine.detect(frame)
    }
}
