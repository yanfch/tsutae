// VAD engine protocol. To be implemented.
// See ../README.md.
import Foundation

public protocol VADEngine {
	var id: String { get }
	// detect(_ frame: AudioFrame) -> VADResult
}
