// STT engine protocol. To be implemented.
// See ../README.md and workspace doc 01-voicebar.md (§引擎抽象).
import Foundation

public protocol STTEngine {
	var id: String { get }
	var displayName: String { get }
	// transcribe(_:language:) async throws -> Transcript
	// stream(_:language:) -> AsyncThrowingStream<TranscriptUpdate, Error>
}
