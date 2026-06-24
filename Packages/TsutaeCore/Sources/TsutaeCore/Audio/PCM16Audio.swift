import Foundation

public enum PCM16Audio {
    public static func decode(_ audio: AudioData) -> [Float] {
        decode(audio.samples)
    }

    public static func decode(_ frame: AudioFrame) -> [Float] {
        decode(frame.samples)
    }

    public static func decode(_ data: Data) -> [Float] {
        let sampleCount = data.count / MemoryLayout<Int16>.size
        guard sampleCount > 0 else { return [] }

        return data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return []
            }

            return (0..<sampleCount).map { index in
                let offset = index * 2
                let value = UInt16(base[offset]) | (UInt16(base[offset + 1]) << 8)
                let sample = Int16(bitPattern: value)
                return max(-1.0, min(1.0, Float(sample) / Float(Int16.max)))
            }
        }
    }

    public static func encode(_ samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * MemoryLayout<Int16>.size)
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            var pcm = Int16(clamped * Float(Int16.max)).littleEndian
            Swift.withUnsafeBytes(of: &pcm) { data.append(contentsOf: $0) }
        }
        return data
    }
}
