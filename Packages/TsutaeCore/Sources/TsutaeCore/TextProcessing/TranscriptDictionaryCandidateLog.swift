import Foundation

public enum TranscriptDictionaryCandidateLog {
    private static let maxStoredCandidateRecords = 5_000
    private static let candidateRetentionDays: TimeInterval = 180

    public static var fileURL: URL {
        Paths.dictionary.appendingPathComponent("candidates.jsonl")
    }

    public static var summaryFileURL: URL {
        Paths.dictionary.appendingPathComponent("candidate-summary.json")
    }

    public struct SourceSnapshot: Codable, Sendable, Equatable {
        public let asrSampleID: String
        public let timestamp: String
        public let context: String
        public let targetApplication: FocusedApplicationSnapshot?
        public let localModel: String?
        public let configuredEngine: String
        public let sttMode: String

        public init(record: ASRSampleLog.Record) {
            self.asrSampleID = record.id
            self.timestamp = record.timestamp
            self.context = record.context
            self.targetApplication = record.targetApplication
            self.localModel = record.localModel
            self.configuredEngine = record.configuredEngine
            self.sttMode = record.sttMode
        }
    }

    public struct EvidenceSnapshot: Codable, Sendable, Equatable {
        public let rawSnippet: String
        public let finalSnippet: String
        public let observedText: String?
        public let normalizedObservedText: String?
        public let occurrenceCount: Int

        public init(
            rawSnippet: String,
            finalSnippet: String,
            observedText: String?,
            normalizedObservedText: String?,
            occurrenceCount: Int
        ) {
            self.rawSnippet = rawSnippet
            self.finalSnippet = finalSnippet
            self.observedText = observedText
            self.normalizedObservedText = normalizedObservedText
            self.occurrenceCount = occurrenceCount
        }
    }

    public struct CandidateRecord: Codable, Sendable, Equatable {
        public let id: String
        public let timestamp: String
        public let kind: String
        public let key: String
        public let value: String?
        public let status: String
        public let confidence: Double
        public let reason: String
        public let source: SourceSnapshot
        public let evidence: EvidenceSnapshot

        public init(
            id: String = UUID().uuidString,
            timestamp: String,
            kind: String,
            key: String,
            value: String?,
            status: String,
            confidence: Double,
            reason: String,
            source: SourceSnapshot,
            evidence: EvidenceSnapshot
        ) {
            self.id = id
            self.timestamp = timestamp
            self.kind = kind
            self.key = key
            self.value = value
            self.status = status
            self.confidence = confidence
            self.reason = reason
            self.source = source
            self.evidence = evidence
        }
    }

    public struct SummaryFile: Codable, Sendable, Equatable {
        public let generatedAt: String
        public let evidenceCount: Int
        public let itemCount: Int
        public let needsReviewCount: Int
        public let alreadyKnownCount: Int
        public let observedCount: Int
        public let items: [SummaryItem]
    }

    public struct SummaryItem: Codable, Sendable, Equatable, Identifiable {
        public let id: String
        public let key: String
        public let suggestedValue: String?
        public let status: String
        public let count: Int
        public let confidence: Double
        public let score: Double
        public let firstSeen: String
        public let lastSeen: String
        public let reasons: [String]
        public let kinds: [String: Int]
        public let apps: [String]
        public let contexts: [String]
        public let sourceSampleIDs: [String]
        public let examples: [SummaryExample]
    }

    public struct SummaryExample: Codable, Sendable, Equatable {
        public let asrSampleID: String
        public let timestamp: String
        public let rawSnippet: String
        public let finalSnippet: String
        public let observedText: String?
        public let normalizedObservedText: String?
    }

    public static func candidates(from record: ASRSampleLog.Record) -> [CandidateRecord] {
        var candidates: [CandidateRecord] = []
        let source = SourceSnapshot(record: record)
        let rawSnippet = snippet(record.rawText)
        let finalSnippet = snippet(record.finalText)

        if let replacements = record.postProcessing?.dictionaryReplacements {
            for replacement in replacements {
                let key = replacement.key.trimmingCharacters(in: .whitespacesAndNewlines)
                guard key.isEmpty == false else { continue }
                candidates.append(
                    CandidateRecord(
                        timestamp: record.timestamp,
                        kind: "dictionary_usage",
                        key: key,
                        value: replacement.value,
                        status: "observed",
                        confidence: 1.0,
                        reason: "existing_dictionary_replacement_matched",
                        source: source,
                        evidence: EvidenceSnapshot(
                            rawSnippet: rawSnippet,
                            finalSnippet: finalSnippet,
                            observedText: key,
                            normalizedObservedText: replacement.value,
                            occurrenceCount: 1
                        )
                    )
                )
            }
        }

        let artifactTokens = subwordArtifactTokens(in: record.rawText)
        for token in artifactTokens {
            let normalized = normalizeSubwordArtifact(token)
            guard shouldSuggestSubwordArtifact(normalized) else { continue }
            candidates.append(
                CandidateRecord(
                    timestamp: record.timestamp,
                    kind: "dictionary_candidate",
                    key: normalized.lowercased(),
                    value: suggestedValue(forNormalizedArtifact: normalized),
                    status: "needs_review",
                    confidence: 0.35,
                    reason: "asr_subword_artifact",
                    source: source,
                    evidence: EvidenceSnapshot(
                        rawSnippet: rawSnippet,
                        finalSnippet: finalSnippet,
                        observedText: token,
                        normalizedObservedText: normalized,
                        occurrenceCount: 1
                    )
                )
            )
        }

        return deduplicated(candidates)
    }

    public static func recordCandidates(from record: ASRSampleLog.Record) async {
        let records = candidates(from: record)
        guard records.isEmpty == false else { return }
        await Writer.shared.append(records)
        await refreshSummary()
    }

    public static func append(_ records: [CandidateRecord]) async {
        await Writer.shared.append(records)
        await refreshSummary()
    }

    public static func loadCandidates(limit: Int? = nil) -> [CandidateRecord] {
        loadCandidatesWithLineData(limit: limit).records
    }

    public static func makeSummary(
        from records: [CandidateRecord],
        config: Config? = nil,
        generatedAt: String? = nil,
        maxExamples: Int = 3
    ) -> SummaryFile {
        let config = config ?? ((try? ConfigLoader.load()) ?? .default)
        let generatedAt = generatedAt ?? isoTimestamp()
        let knownEntries = knownDictionaryEntries(config: config)
        var accumulators: [String: SummaryAccumulator] = [:]

        for record in records {
            let key = record.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard key.isEmpty == false else { continue }
            let knownValue = knownEntries[key]
            let suggestedValue = knownValue ?? nonBlank(record.value)
            let groupID = summaryID(key: key, value: suggestedValue)
            var accumulator = accumulators[groupID] ?? SummaryAccumulator(key: key, suggestedValue: suggestedValue)
            accumulator.add(record, knownValue: knownValue, maxExamples: maxExamples)
            accumulators[groupID] = accumulator
        }

        let items = accumulators.values
            .map { $0.item }
            .sorted { lhs, rhs in
                let lhsPriority = statusPriority(lhs.status)
                let rhsPriority = statusPriority(rhs.status)
                if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.lastSeen != rhs.lastSeen { return lhs.lastSeen > rhs.lastSeen }
                return lhs.key < rhs.key
            }

        return SummaryFile(
            generatedAt: generatedAt,
            evidenceCount: records.count,
            itemCount: items.count,
            needsReviewCount: items.filter { $0.status == "needs_review" }.count,
            alreadyKnownCount: items.filter { $0.status == "already_known" }.count,
            observedCount: items.filter { $0.status == "observed" }.count,
            items: items
        )
    }

    public static func refreshSummary(limit: Int? = nil) async {
        let records = loadCandidates(limit: limit)
        let summary = makeSummary(from: records)
        await SummaryWriter.shared.write(summary)
    }

    private static func loadCandidatesWithLineData(limit: Int? = nil) -> (records: [CandidateRecord], lines: [String]) {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return ([], []) }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let selectedLines = limit.map { Array(lines.suffix($0)) } ?? lines
        let decoder = JSONDecoder()
        var records: [CandidateRecord] = []
        var keptLines: [String] = []
        for line in selectedLines {
            guard let data = line.data(using: .utf8),
                  let record = try? decoder.decode(CandidateRecord.self, from: data) else {
                continue
            }
            records.append(record)
            keptLines.append(line)
        }
        return (records, keptLines)
    }

    private static func prunedRecords(_ records: [CandidateRecord], now: Date = Date()) -> [CandidateRecord] {
        let cutoff = now.addingTimeInterval(-candidateRetentionDays * 24 * 60 * 60)
        let recent = records.filter { record in
            guard let date = isoDate(record.timestamp) else { return true }
            return date >= cutoff
        }
        guard recent.count > maxStoredCandidateRecords else { return recent }
        return Array(recent.suffix(maxStoredCandidateRecords))
    }

    private static func isoDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func deduplicated(_ candidates: [CandidateRecord]) -> [CandidateRecord] {
        var seen = Set<String>()
        var output: [CandidateRecord] = []
        for candidate in candidates {
            let signature = [
                candidate.kind,
                candidate.key.lowercased(),
                candidate.value?.lowercased() ?? "",
                candidate.reason
            ].joined(separator: "\u{1f}")
            if seen.insert(signature).inserted {
                output.append(candidate)
            }
        }
        return output
    }

    private static func subwordArtifactTokens(in text: String) -> [String] {
        let pattern = #"[A-Za-z][A-Za-z@]{1,}[A-Za-z]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: nsRange).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let token = String(text[range])
            return token.contains("@@") ? token : nil
        }
    }

    private static func normalizeSubwordArtifact(_ token: String) -> String {
        token
            .replacingOccurrences(of: "@@", with: "")
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    }

    private static func shouldSuggestSubwordArtifact(_ value: String) -> Bool {
        guard value.count >= 4 else { return false }
        guard value.range(of: #"^[A-Za-z][A-Za-z0-9+-]*$"#, options: .regularExpression) != nil else { return false }
        let lower = value.lowercased()
        let ignored = Set(["okay", "ok", "the", "this", "that", "then", "and"])
        return ignored.contains(lower) == false
    }

    private static func suggestedValue(forNormalizedArtifact value: String) -> String {
        let lower = value.lowercased()
        let known: [String: String] = [
            "api": "API",
            "asr": "ASR",
            "stt": "STT",
            "tts": "TTS",
            "vad": "VAD",
            "ui": "UI",
            "dmg": "DMG",
            "llm": "LLM",
            "github": "GitHub",
            "codex": "Codex",
            "tsutae": "Tsutae",
            "kanade": "Kanade",
            "appledeveloperprogram": "Apple Developer Program",
            "doubleoption": "Double Option",
            "doubletap": "Double Tap",
            "codingagent": "coding agent"
        ]
        return known[lower] ?? value
    }

    private static func snippet(_ text: String, maxLength: Int = 180) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else { return trimmed }
        return String(trimmed.prefix(maxLength)) + "…"
    }

    private struct SummaryAccumulator {
        var key: String
        var suggestedValue: String?
        var count: Int = 0
        var confidenceTotal: Double = 0
        var firstSeen: String = ""
        var lastSeen: String = ""
        var reasons = Set<String>()
        var kinds: [String: Int] = [:]
        var apps = Set<String>()
        var contexts = Set<String>()
        var sourceSampleIDs = Set<String>()
        var examples: [SummaryExample] = []
        var hasCandidate = false
        var hasUsage = false
        var isKnown = false

        mutating func add(_ record: CandidateRecord, knownValue: String?, maxExamples: Int) {
            let occurrenceCount = max(1, record.evidence.occurrenceCount)
            count += occurrenceCount
            confidenceTotal += record.confidence * Double(occurrenceCount)
            if suggestedValue == nil {
                suggestedValue = knownValue ?? TranscriptDictionaryCandidateLog.nonBlank(record.value)
            }
            if let knownValue {
                suggestedValue = knownValue
                isKnown = true
            }

            if firstSeen.isEmpty || record.timestamp < firstSeen {
                firstSeen = record.timestamp
            }
            if lastSeen.isEmpty || record.timestamp > lastSeen {
                lastSeen = record.timestamp
            }

            reasons.insert(record.reason)
            kinds[record.kind, default: 0] += occurrenceCount
            contexts.insert(record.source.context)
            sourceSampleIDs.insert(record.source.asrSampleID)
            if let app = appName(record.source.targetApplication) {
                apps.insert(app)
            }
            if record.kind == "dictionary_candidate" {
                hasCandidate = true
            }
            if record.kind == "dictionary_usage" {
                hasUsage = true
            }

            if examples.count < maxExamples,
               examples.contains(where: { $0.asrSampleID == record.source.asrSampleID && $0.observedText == record.evidence.observedText }) == false {
                examples.append(
                    SummaryExample(
                        asrSampleID: record.source.asrSampleID,
                        timestamp: record.timestamp,
                        rawSnippet: record.evidence.rawSnippet,
                        finalSnippet: record.evidence.finalSnippet,
                        observedText: record.evidence.observedText,
                        normalizedObservedText: record.evidence.normalizedObservedText
                    )
                )
            }
        }

        var item: SummaryItem {
            let averageConfidence = count > 0 ? confidenceTotal / Double(count) : 0
            let frequencyBoost = min(0.25, Double(max(0, count - 1)) * 0.08)
            let confidence = rounded(min(1.0, averageConfidence + frequencyBoost))
            let status: String
            if hasCandidate, isKnown {
                status = "already_known"
            } else if hasCandidate {
                status = "needs_review"
            } else if hasUsage {
                status = "observed"
            } else {
                status = "needs_review"
            }

            return SummaryItem(
                id: TranscriptDictionaryCandidateLog.summaryID(key: key, value: suggestedValue),
                key: key,
                suggestedValue: suggestedValue,
                status: status,
                count: count,
                confidence: confidence,
                score: rounded(confidence * Double(count)),
                firstSeen: firstSeen,
                lastSeen: lastSeen,
                reasons: reasons.sorted(),
                kinds: kinds,
                apps: apps.sorted(),
                contexts: contexts.sorted(),
                sourceSampleIDs: sourceSampleIDs.sorted(),
                examples: examples
            )
        }

        private func appName(_ app: FocusedApplicationSnapshot?) -> String? {
            let value = app?.localizedName ?? app?.bundleIdentifier
            return TranscriptDictionaryCandidateLog.nonBlank(value)
        }

        private func rounded(_ value: Double) -> Double {
            (value * 1000).rounded() / 1000
        }
    }

    private static func knownDictionaryEntries(config: Config) -> [String: String] {
        let dictionary = config.postProcessing.dictionary
        guard dictionary.enabled else { return [:] }
        var entries: [String: String] = [:]
        if dictionary.useBuiltIn {
            for entry in TranscriptDictionaryReplacer.builtInPreviewEntries where entry.enabled {
                if let key = nonBlank(entry.key), let value = nonBlank(entry.value) {
                    entries[key.lowercased()] = value
                }
            }
        }
        for entry in dictionary.entries where entry.enabled {
            if let key = nonBlank(entry.key), let value = nonBlank(entry.value) {
                entries[key.lowercased()] = value
            }
        }
        return entries
    }

    private static func nonBlank(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func summaryID(key: String, value: String?) -> String {
        "\(key.lowercased())->\((value ?? "").lowercased())"
    }

    private static func statusPriority(_ status: String) -> Int {
        switch status {
        case "needs_review": return 0
        case "already_known": return 1
        case "observed": return 2
        default: return 3
        }
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

        func append(_ records: [CandidateRecord]) {
            do {
                try Paths.ensureDirectories()
                var data = Data()
                for record in records {
                    data.append(try encoder.encode(record))
                    data.append(0x0A)
                }

                let fileURL = TranscriptDictionaryCandidateLog.fileURL
                if FileManager.default.fileExists(atPath: fileURL.path) == false {
                    try data.write(to: fileURL, options: .atomic)
                    try compactIfNeeded()
                    return
                }

                let handle = try FileHandle(forWritingTo: fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try compactIfNeeded()
            } catch {
                // Candidate capture is best-effort and must never affect dictation.
            }
        }

        private func compactIfNeeded() throws {
            let loaded = TranscriptDictionaryCandidateLog.loadCandidatesWithLineData()
            guard loaded.records.count > TranscriptDictionaryCandidateLog.maxStoredCandidateRecords else {
                let prunedByAge = TranscriptDictionaryCandidateLog.prunedRecords(loaded.records)
                guard prunedByAge.count != loaded.records.count else { return }
                try rewrite(prunedByAge)
                return
            }
            try rewrite(TranscriptDictionaryCandidateLog.prunedRecords(loaded.records))
        }

        private func rewrite(_ records: [CandidateRecord]) throws {
            var data = Data()
            for record in records {
                data.append(try encoder.encode(record))
                data.append(0x0A)
            }
            try data.write(to: TranscriptDictionaryCandidateLog.fileURL, options: .atomic)
        }
    }

    private actor SummaryWriter {
        static let shared = SummaryWriter()
        private let encoder: JSONEncoder = {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return encoder
        }()

        func write(_ summary: SummaryFile) {
            do {
                try Paths.ensureDirectories()
                let data = try encoder.encode(summary)
                try data.write(to: TranscriptDictionaryCandidateLog.summaryFileURL, options: .atomic)
            } catch {
                // Summary refresh is best-effort and must never affect dictation.
            }
        }
    }
}
