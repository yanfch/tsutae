import Foundation

public enum ASRSampleLog {
    public static var fileURL: URL {
        Paths.logs.appendingPathComponent("asr-samples.jsonl")
    }

    public struct PostProcessingSnapshot: Codable, Sendable, Equatable {
        public let enabled: Bool
        public let mode: String
        public let task: String
        public let provider: String
        public let model: String?
        public let elapsedMs: Double
        public let dictionaryMatches: [String]
        public let dictionaryReplacements: [TranscriptDictionaryReplacement]?
    }

    public struct VADSegmentSnapshot: Codable, Sendable, Equatable {
        public let index: Int
        public let startMs: Double
        public let endMs: Double
        public let byteStart: Int
        public let byteEnd: Int
        public let reason: String

        public init(index: Int, startMs: Double, endMs: Double, byteStart: Int, byteEnd: Int, reason: String) {
            self.index = index
            self.startMs = startMs
            self.endMs = endMs
            self.byteStart = byteStart
            self.byteEnd = byteEnd
            self.reason = reason
        }
    }

    public struct VADSnapshot: Codable, Sendable, Equatable {
        public let engine: String
        public let reason: String
        public let audioMs: Double
        public let processedMs: Double
        public let speechWindows: Int
        public let silenceWindows: Int
        public let maxProbability: Double
        public let firstSpeechMs: Double?
        public let lastSpeechMs: Double?
        public let longestSilenceMs: Double
        public let segmentBytes: Int
        public let segmentSavedPercent: Double
        public let segments: [VADSegmentSnapshot]

        public init(
            engine: String,
            reason: String,
            audioMs: Double,
            processedMs: Double,
            speechWindows: Int,
            silenceWindows: Int,
            maxProbability: Double,
            firstSpeechMs: Double?,
            lastSpeechMs: Double?,
            longestSilenceMs: Double,
            segmentBytes: Int,
            segmentSavedPercent: Double,
            segments: [VADSegmentSnapshot]
        ) {
            self.engine = engine
            self.reason = reason
            self.audioMs = audioMs
            self.processedMs = processedMs
            self.speechWindows = speechWindows
            self.silenceWindows = silenceWindows
            self.maxProbability = maxProbability
            self.firstSpeechMs = firstSpeechMs
            self.lastSpeechMs = lastSpeechMs
            self.longestSilenceMs = longestSilenceMs
            self.segmentBytes = segmentBytes
            self.segmentSavedPercent = segmentSavedPercent
            self.segments = segments
        }
    }

    public struct InsertionSnapshot: Codable, Sendable, Equatable {
        public let method: String
        public let succeeded: Bool
        public let elapsedMs: Double
        public let error: String?

        public init(method: String, succeeded: Bool, elapsedMs: Double, error: String? = nil) {
            self.method = method
            self.succeeded = succeeded
            self.elapsedMs = elapsedMs
            self.error = error
        }
    }

    public struct Record: Codable, Sendable, Equatable {
        public let id: String
        public let timestamp: String
        public let context: String
        public let targetApplication: FocusedApplicationSnapshot?
        public let recordingStartApplication: FocusedApplicationSnapshot?
        public let insertionApplication: FocusedApplicationSnapshot?
        public let audioBytes: Int
        public let audioSeconds: Double
        public let sampleRate: Int
        public let channels: Int
        public let container: String
        public let sttMode: String
        public let configuredEngine: String
        public let localModel: String?
        public let remoteModel: String?
        public let remoteRequestStyle: String
        public let fallbackEngine: String?
        public let languageHint: String?
        public let transcriptLanguage: String?
        public let transcriptDurationMs: Int?
        public let transcriptConfidence: Double?
        public let transcriptionElapsedMs: Double
        public let totalElapsedMs: Double
        public let endToEndElapsedMs: Double?
        public let rawText: String
        public let finalText: String
        public let rawChars: Int
        public let finalChars: Int
        public let postProcessing: PostProcessingSnapshot?
        public let vad: VADSnapshot?
        public let insertion: InsertionSnapshot?
    }

    public static func makeRecord(
        context: String,
        audio: AudioData,
        transcript: Transcript,
        config: Config,
        transcriptionElapsedMs: Double,
        totalElapsedMs: Double,
        postProcessing: TranscriptPostProcessingResult?,
        targetApplication: FocusedApplicationSnapshot? = nil,
        recordingStartApplication: FocusedApplicationSnapshot? = nil,
        insertionApplication: FocusedApplicationSnapshot? = nil,
        insertion: InsertionSnapshot? = nil,
        endToEndElapsedMs: Double? = nil,
        vad: VADSnapshot? = nil
    ) -> Record {
        let resolvedTargetApplication = targetApplication ?? insertionApplication ?? recordingStartApplication
        return Record(
            id: UUID().uuidString,
            timestamp: isoTimestamp(),
            context: context,
            targetApplication: resolvedTargetApplication,
            recordingStartApplication: recordingStartApplication,
            insertionApplication: insertionApplication,
            audioBytes: audio.samples.count,
            audioSeconds: audioSeconds(audio),
            sampleRate: audio.sampleRate,
            channels: audio.channels,
            container: audio.container.rawValue,
            sttMode: config.stt.mode.rawValue,
            configuredEngine: config.stt.engine,
            localModel: config.stt.local.preferredModel ?? config.stt.model,
            remoteModel: config.stt.remote.model,
            remoteRequestStyle: config.stt.remote.requestStyle.rawValue,
            fallbackEngine: config.stt.fallbackEngine,
            languageHint: config.stt.language,
            transcriptLanguage: transcript.language,
            transcriptDurationMs: transcript.durationMs,
            transcriptConfidence: transcript.confidence,
            transcriptionElapsedMs: transcriptionElapsedMs,
            totalElapsedMs: totalElapsedMs,
            endToEndElapsedMs: endToEndElapsedMs,
            rawText: transcript.text,
            finalText: postProcessing?.processedText ?? transcript.text,
            rawChars: transcript.text.count,
            finalChars: (postProcessing?.processedText ?? transcript.text).count,
            postProcessing: postProcessing.map {
                PostProcessingSnapshot(
                    enabled: config.postProcessing.enabled,
                    mode: $0.mode.rawValue,
                    task: $0.task.rawValue,
                    provider: $0.provider,
                    model: $0.model,
                    elapsedMs: $0.elapsedMs,
                    dictionaryMatches: $0.dictionaryMatches,
                    dictionaryReplacements: $0.dictionaryReplacements
                )
            },
            vad: vad,
            insertion: insertion
        )
    }

    public static func record(_ record: Record) {
        guard isEnabled else { return }
        Task {
            await Writer.shared.append(record)
            await TranscriptDictionaryCandidateLog.recordCandidates(from: record)
        }
    }

    public static func append(_ record: Record) async {
        await Writer.shared.append(record)
        await TranscriptDictionaryCandidateLog.recordCandidates(from: record)
    }

    private static func audioSeconds(_ audio: AudioData) -> Double {
        guard audio.sampleRate > 0, audio.channels > 0 else { return 0 }
        return Double(audio.samples.count) / Double(audio.sampleRate * audio.channels * 2)
    }

    private static var isEnabled: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["TSUTAE_ASR_SAMPLE_LOG"] != "0"
        #else
        return ProcessInfo.processInfo.environment["TSUTAE_ASR_SAMPLE_LOG"] == "1"
        #endif
    }

    private static func isoTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private actor Writer {
        static let shared = Writer()
        private let encoder: JSONEncoder = {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return encoder
        }()

        func append(_ record: Record) {
            do {
                try Paths.ensureDirectories()
                let data = try encoder.encode(record)
                var line = Data()
                line.append(data)
                line.append(0x0A)

                let fileURL = ASRSampleLog.fileURL
                if FileManager.default.fileExists(atPath: fileURL.path) == false {
                    try line.write(to: fileURL, options: .atomic)
                    return
                }

                let handle = try FileHandle(forWritingTo: fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } catch {
                // Sample capture is best-effort and must never affect dictation.
            }
        }
    }
}
