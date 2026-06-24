import XCTest
@testable import TsutaeCore

final class VADTests: XCTestCase {
    func testPCM16RoundTrip() {
        let samples: [Float] = [-1.0, -0.5, 0.0, 0.5, 1.0]
        let decoded = PCM16Audio.decode(PCM16Audio.encode(samples))

        XCTAssertEqual(decoded.count, samples.count)
        for (actual, expected) in zip(decoded, samples) {
            XCTAssertEqual(actual, expected, accuracy: 0.0001)
        }
    }

    func testEnergyVADRejectsSilence() async throws {
        let engine = EnergyVADEngine(sensitivity: 0.5)
        let frame = AudioFrame(samples: PCM16Audio.encode(Array(repeating: 0.0, count: 4096)))

        let result = try await engine.detect(frame)

        XCTAssertFalse(result.isSpeech)
        XCTAssertEqual(result.probability, 0, accuracy: 0.0001)
    }

    func testEnergyVADDetectsSignal() async throws {
        let engine = EnergyVADEngine(sensitivity: 0.5)
        let sampleRate = 16_000.0
        let samples = (0..<4096).map { index in
            Float(0.35 * sin(2.0 * Double.pi * 220.0 * Double(index) / sampleRate))
        }
        let frame = AudioFrame(samples: PCM16Audio.encode(samples))

        let result = try await engine.detect(frame)

        XCTAssertTrue(result.isSpeech)
        XCTAssertGreaterThan(result.probability, 0.5)
    }

    func testFluidAudioVADIsLazyLoaded() {
        let engine = FluidAudioVADEngine(sensitivity: 0.5)

        XCTAssertEqual(engine.status, .loading)
    }

    func testConfiguredVADUsesConfiguredSensitivity() async throws {
        let originalEngine = EngineManager.shared.vad(id: "energy")
        EngineManager.shared.registerVAD(EnergyVADEngine(sensitivity: 0.5))
        defer {
            if let originalEngine {
                EngineManager.shared.registerVAD(originalEngine)
            } else {
                EngineManager.shared.unregisterVAD(id: "energy")
            }
        }

        let sampleRate = 16_000.0
        let samples = (0..<4096).map { index in
            Float(0.03 * sin(2.0 * Double.pi * 220.0 * Double(index) / sampleRate))
        }
        let frame = AudioFrame(samples: PCM16Audio.encode(samples))

        let lowSensitivity = Config(vad: Config.VADConfig(sensitivity: 0.0))
        let highSensitivity = Config(vad: Config.VADConfig(sensitivity: 1.0))

        let lowResult = try await ConfiguredVADDetector.detect(frame, config: lowSensitivity)
        let highResult = try await ConfiguredVADDetector.detect(frame, config: highSensitivity)

        XCTAssertFalse(lowResult.isSpeech)
        XCTAssertTrue(highResult.isSpeech)
    }
}
