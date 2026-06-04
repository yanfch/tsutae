import Foundation
import XCTest
@testable import TsutaeCore

final class OpenAICompatibleSTTTests: XCTestCase {
    
    func testWAVEncoderProducesValidHeader() throws {
        let samples = Data([0x01, 0x00, 0x02, 0x00])
        let wav = try WAVEncoder.encode(AudioData(samples: samples, sampleRate: 16000, channels: 1))
        
        XCTAssertEqual(String(data: wav[0..<4], encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: wav[8..<12], encoding: .ascii), "WAVE")
        XCTAssertEqual(String(data: wav[12..<16], encoding: .ascii), "fmt ")
        XCTAssertEqual(String(data: wav[36..<40], encoding: .ascii), "data")
        XCTAssertEqual(wav.count, 44 + samples.count)
    }
    
    func testTranscribeSendsMultipartAndParsesResponse() async throws {
        let session = MockURLSession(
            data: Data(#"{"text":"hello world","language":"en","duration":1.25}"#.utf8),
            statusCode: 200
        )
        let stt = OpenAICompatibleSTT(
            baseURL: URL(string: "http://127.0.0.1:1337")!,
            model: "test-model",
            apiKey: "test-key",
            session: session
        )
        
        let transcript = try await stt.transcribe(
            AudioData(samples: Data(repeating: 0, count: 3200), sampleRate: 16000, channels: 1),
            language: "en"
        )
        
        XCTAssertEqual(transcript.text, "hello world")
        XCTAssertEqual(transcript.language, "en")
        XCTAssertEqual(transcript.durationMs, 1250)
        
        let request = try XCTUnwrap(session.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:1337/v1/audio/transcriptions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.contains("multipart/form-data") == true)
        
        let body = try XCTUnwrap(request.httpBody)
        XCTAssertTrue(body.containsASCII("name=\"model\""))
        XCTAssertTrue(body.containsASCII("test-model"))
        XCTAssertTrue(body.containsASCII("name=\"language\""))
        XCTAssertTrue(body.containsASCII("name=\"file\"; filename=\"audio.wav\""))
    }
}

private extension Data {
    func containsASCII(_ string: String) -> Bool {
        range(of: Data(string.utf8)) != nil
    }
}

private final class MockURLSession: URLSessionProtocol, @unchecked Sendable {
    private let data: Data
    private let statusCode: Int
    var lastRequest: URLRequest?
    
    init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }
    
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}
