import Foundation
import Hummingbird
import NIOCore

public struct STTTranscriptionRequest: Sendable {
    public let audio: AudioData
    public let language: String?
    public let model: String?
    public let responseFormat: String?

    public init(
        audio: AudioData,
        language: String? = nil,
        model: String? = nil,
        responseFormat: String? = nil
    ) {
        self.audio = audio
        self.language = language
        self.model = model
        self.responseFormat = responseFormat
    }
}

struct STTTranscriptionUpload: Sendable {
    static let maxBodyBytes = 25 * 1024 * 1024

    let request: STTTranscriptionRequest

    static func decode(from request: inout Request) async throws -> STTTranscriptionUpload {
        guard let contentType = request.headers[.contentType] else {
            throw HTTPError(.badRequest, message: "Missing Content-Type header.")
        }
        let body = try await request.collectBody(upTo: maxBodyBytes)
        guard let data = body.getData(at: body.readerIndex, length: body.readableBytes) else {
            throw HTTPError(.badRequest, message: "Unable to read request body.")
        }
        return try parse(body: data, contentType: contentType)
    }

    static func parse(body: Data, contentType: String) throws -> STTTranscriptionUpload {
        let parsed = try MultipartFormDataParser.parse(body: body, contentType: contentType)
        guard let file = parsed.files["file"] else {
            throw HTTPError(.badRequest, message: "Missing multipart file field `file`.")
        }

        let audio = try UploadedAudioDecoder.decode(
            data: file.data,
            filename: file.filename,
            contentType: file.contentType,
            fields: parsed.fields
        )
        return STTTranscriptionUpload(
            request: STTTranscriptionRequest(
                audio: audio,
                language: parsed.fields["language"]?.nilIfBlank,
                model: parsed.fields["model"]?.nilIfBlank,
                responseFormat: parsed.fields["response_format"]?.nilIfBlank
            )
        )
    }

    func response(for transcript: Transcript) throws -> Response {
        let format = request.responseFormat?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch format {
        case nil, "", "json", "verbose_json":
            let payload = STTTranscriptionResponse(
                text: transcript.text,
                language: transcript.language,
                duration: transcript.durationMs.map { Double($0) / 1000.0 }
            )
            let data = try JSONEncoder().encode(payload)
            var response = Response(status: .ok)
            response.headers[.contentType] = "application/json"
            response.body = .init(byteBuffer: ByteBuffer(data: data))
            return response
        case "text":
            var response = Response(status: .ok)
            response.headers[.contentType] = "text/plain; charset=utf-8"
            response.body = .init(byteBuffer: ByteBuffer(data: Data(transcript.text.utf8)))
            return response
        default:
            throw HTTPError(.badRequest, message: "Unsupported response_format: \(format ?? "").")
        }
    }
}

struct STTTranscriptionResponse: Codable, Sendable {
    let text: String
    let language: String?
    let duration: Double?
}

private struct ParsedMultipartForm: Sendable {
    let fields: [String: String]
    let files: [String: MultipartFile]
}

private struct MultipartFile: Sendable {
    let filename: String?
    let contentType: String?
    let data: Data
}

private enum MultipartFormDataParser {
    static func parse(body: Data, contentType: String) throws -> ParsedMultipartForm {
        let boundary = try boundary(from: contentType)
        let delimiter = Data("--\(boundary)".utf8)
        var fields: [String: String] = [:]
        var files: [String: MultipartFile] = [:]

        var cursor = body.startIndex
        guard let firstDelimiter = body.range(of: delimiter, in: cursor..<body.endIndex) else {
            throw HTTPError(.badRequest, message: "Multipart boundary was not found.")
        }
        cursor = firstDelimiter.upperBound

        while cursor < body.endIndex {
            if body.hasBytes([45, 45], at: cursor) {
                break
            }
            if body.hasBytes([13, 10], at: cursor) {
                cursor = body.index(cursor, offsetBy: 2)
            }

            guard let nextDelimiter = body.range(of: delimiter, in: cursor..<body.endIndex) else {
                throw HTTPError(.badRequest, message: "Multipart body is missing closing boundary.")
            }

            var part = Data(body[cursor..<nextDelimiter.lowerBound])
            part.trimTrailingCRLF()
            if part.isEmpty {
                cursor = nextDelimiter.upperBound
                continue
            }

            let parsedPart = try parsePart(part)
            if let filename = parsedPart.filename {
                files[parsedPart.name] = MultipartFile(
                    filename: filename,
                    contentType: parsedPart.contentType,
                    data: parsedPart.data
                )
            } else if let value = String(data: parsedPart.data, encoding: .utf8) {
                fields[parsedPart.name] = value.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            cursor = nextDelimiter.upperBound
        }

        return ParsedMultipartForm(fields: fields, files: files)
    }

    private static func boundary(from contentType: String) throws -> String {
        let components = contentType.split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard components.first?.lowercased() == "multipart/form-data" else {
            throw HTTPError(.badRequest, message: "Content-Type must be multipart/form-data.")
        }
        for component in components.dropFirst() {
            let pair = component.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2, pair[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "boundary" else {
                continue
            }
            let value = pair[1].trimmingCharacters(in: .whitespacesAndNewlines).unquoted
            if value.isEmpty == false {
                return value
            }
        }
        throw HTTPError(.badRequest, message: "Missing multipart boundary.")
    }

    private static func parsePart(_ data: Data) throws -> ParsedPart {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: separator, in: data.startIndex..<data.endIndex) else {
            throw HTTPError(.badRequest, message: "Multipart part is missing headers.")
        }
        guard let headerText = String(data: data[data.startIndex..<headerRange.lowerBound], encoding: .utf8) else {
            throw HTTPError(.badRequest, message: "Multipart part headers are not UTF-8.")
        }

        var name: String?
        var filename: String?
        var contentType: String?

        for line in headerText.components(separatedBy: "\r\n") {
            let lower = line.lowercased()
            if lower.hasPrefix("content-disposition:") {
                let value = String(line.dropFirst("content-disposition:".count))
                let parameters = dispositionParameters(from: value)
                name = parameters["name"]
                filename = parameters["filename"]
            } else if lower.hasPrefix("content-type:") {
                contentType = String(line.dropFirst("content-type:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        guard let name, name.isEmpty == false else {
            throw HTTPError(.badRequest, message: "Multipart part is missing form field name.")
        }

        let bodyStart = headerRange.upperBound
        return ParsedPart(
            name: name,
            filename: filename,
            contentType: contentType,
            data: Data(data[bodyStart..<data.endIndex])
        )
    }

    private static func dispositionParameters(from value: String) -> [String: String] {
        var parameters: [String: String] = [:]
        for segment in value.split(separator: ";").dropFirst() {
            let pair = segment.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard pair.count == 2 else { continue }
            parameters[pair[0].lowercased()] = pair[1].unquoted
        }
        return parameters
    }

    private struct ParsedPart {
        let name: String
        let filename: String?
        let contentType: String?
        let data: Data
    }
}

private enum UploadedAudioDecoder {
    static func decode(data: Data, filename: String?, contentType: String?, fields: [String: String]) throws -> AudioData {
        if data.looksLikeWAV {
            return try decodeWAV(data)
        }

        let lowerFilename = filename?.lowercased() ?? ""
        let lowerContentType = contentType?.lowercased() ?? ""
        if lowerFilename.hasSuffix(".pcm") || lowerFilename.hasSuffix(".raw") || lowerContentType == "audio/l16" || lowerContentType == "application/octet-stream" {
            return AudioData(
                samples: data,
                sampleRate: intField(["sample_rate", "sampleRate"], in: fields) ?? 16_000,
                channels: intField(["channels"], in: fields) ?? 1,
                container: .pcm16
            )
        }

        throw HTTPError(.badRequest, message: "Unsupported audio format. Upload WAV PCM16 or raw PCM16 for now.")
    }

    private static func decodeWAV(_ data: Data) throws -> AudioData {
        guard data.count >= 44,
              data.asciiString(in: 0..<4) == "RIFF",
              data.asciiString(in: 8..<12) == "WAVE" else {
            throw HTTPError(.badRequest, message: "Invalid WAV header.")
        }

        var offset = 12
        var audioFormat: UInt16?
        var channels: UInt16?
        var sampleRate: UInt32?
        var bitsPerSample: UInt16?
        var sampleData: Data?

        while offset + 8 <= data.count {
            guard let chunkID = data.asciiString(in: offset..<(offset + 4)) else { break }
            let chunkSize = Int(data.uint32LE(at: offset + 4))
            let chunkStart = offset + 8
            let chunkEnd = chunkStart + chunkSize
            guard chunkEnd <= data.count else {
                throw HTTPError(.badRequest, message: "Invalid WAV chunk size.")
            }

            switch chunkID {
            case "fmt ":
                guard chunkSize >= 16 else {
                    throw HTTPError(.badRequest, message: "Invalid WAV fmt chunk.")
                }
                audioFormat = data.uint16LE(at: chunkStart)
                channels = data.uint16LE(at: chunkStart + 2)
                sampleRate = data.uint32LE(at: chunkStart + 4)
                bitsPerSample = data.uint16LE(at: chunkStart + 14)
            case "data":
                sampleData = Data(data[chunkStart..<chunkEnd])
            default:
                break
            }

            offset = chunkEnd + (chunkSize % 2)
        }

        guard audioFormat == 1, bitsPerSample == 16 else {
            throw HTTPError(.badRequest, message: "Only WAV PCM16 audio is supported for local transcription.")
        }
        guard let sampleData, sampleData.isEmpty == false, let sampleRate, let channels, channels > 0 else {
            throw HTTPError(.badRequest, message: "WAV file is missing audio samples.")
        }

        return AudioData(
            samples: sampleData,
            sampleRate: Int(sampleRate),
            channels: Int(channels),
            container: .pcm16
        )
    }

    private static func intField(_ keys: [String], in fields: [String: String]) -> Int? {
        for key in keys {
            if let value = fields[key].flatMap(Int.init) {
                return value
            }
        }
        return nil
    }
}

private extension Data {
    var looksLikeWAV: Bool {
        count >= 12 && asciiString(in: 0..<4) == "RIFF" && asciiString(in: 8..<12) == "WAVE"
    }

    func asciiString(in range: Range<Int>) -> String? {
        guard range.lowerBound >= 0, range.upperBound <= count else { return nil }
        return String(data: self[range], encoding: .ascii)
    }

    func uint16LE(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func uint32LE(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }

    func hasBytes(_ bytes: [UInt8], at index: Index) -> Bool {
        guard let end = self.index(index, offsetBy: bytes.count, limitedBy: endIndex), end <= endIndex else {
            return false
        }
        return Array(self[index..<end]) == bytes
    }

    mutating func trimTrailingCRLF() {
        while count >= 2, self[index(endIndex, offsetBy: -2)] == 13, self[index(endIndex, offsetBy: -1)] == 10 {
            removeSubrange(index(endIndex, offsetBy: -2)..<endIndex)
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var unquoted: String {
        var value = trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value.removeFirst()
            value.removeLast()
        }
        return value
    }
}
