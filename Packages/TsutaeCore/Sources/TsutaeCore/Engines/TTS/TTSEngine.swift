// TTS engine protocol. To be implemented.
// See ../README.md.
import Foundation

public protocol TTSEngine {
	var id: String { get }
	var displayName: String { get }
	// synthesize(_:voice:options:) async throws -> AudioData
	// stream(_:voice:options:) -> AsyncThrowingStream<AudioChunk, Error>
}
