import XCTest
@testable import TsutaeCore

final class TsutaeCoreTests: XCTestCase {
	func testPlaceholderVersionExists() {
		XCTAssertFalse(TsutaePlaceholder.version.isEmpty)
	}
}
