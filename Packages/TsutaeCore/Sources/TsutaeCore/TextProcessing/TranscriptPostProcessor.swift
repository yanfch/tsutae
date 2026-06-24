import Foundation
import OSLog

public struct TranscriptPostProcessingResult: Codable, Sendable, Equatable {
    public let rawText: String
    public let processedText: String
    public let mode: Config.TranscriptPostProcessingMode
    public let task: Config.TranscriptPostProcessingTask
    public let provider: String
    public let model: String?
    public let elapsedMs: Double
    public let dictionaryMatches: [String]

    public init(
        rawText: String,
        processedText: String,
        mode: Config.TranscriptPostProcessingMode,
        task: Config.TranscriptPostProcessingTask,
        provider: String,
        model: String?,
        elapsedMs: Double,
        dictionaryMatches: [String] = []
    ) {
        self.rawText = rawText
        self.processedText = processedText
        self.mode = mode
        self.task = task
        self.provider = provider
        self.model = model
        self.elapsedMs = elapsedMs
        self.dictionaryMatches = dictionaryMatches
    }
}

public enum TranscriptPostProcessingError: LocalizedError, Sendable {
    case emptyInput
    case invalidRemoteConfiguration
    case invalidResponse
    case httpStatus(Int, String)

    public var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Transcript is empty."
        case .invalidRemoteConfiguration:
            return "Transcript post-processing remote configuration is incomplete."
        case .invalidResponse:
            return "Transcript post-processing returned an invalid response."
        case .httpStatus(let status, let message):
            return "Transcript post-processing failed (\(status)): \(message)"
        }
    }
}

public struct TranscriptDictionaryContext: Sendable, Equatable {
    public static let empty = TranscriptDictionaryContext(terms: [])

    public let terms: [String]

    public init(terms: [String]) {
        var seen = Set<String>()
        self.terms = terms
            .compactMap(Self.normalizedTerm)
            .filter { seen.insert($0.lowercased()).inserted }
    }

    public init(config: Config, appContext: String? = nil) {
        var terms: [String] = []
        terms.append(contentsOf: config.server.clients.map(\.name))
        terms.append(contentsOf: [
            config.stt.engine,
            config.stt.model,
            config.stt.remote.model,
            config.stt.local.preferredModel,
            config.stt.local.previewModel,
            config.stt.local.finalModel,
            config.tts.engine,
            config.tts.voice,
            config.tts.remote.model,
            config.tts.remote.voice,
            config.tts.fallbackEngine,
            config.tts.premiumEngine,
            config.tts.premiumVoice,
            config.postProcessing.remote.model,
            appContext
        ].compactMap { $0 })
        self.init(terms: terms)
    }

    var entries: [Config.TranscriptDictionaryEntry] {
        terms.flatMap { term in
            automaticKeys(for: term).map { key in
                Config.TranscriptDictionaryEntry(key: key, value: term)
            }
        }
    }

    private static func normalizedTerm(_ term: String) -> String? {
        let value = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 2,
              value.count <= 80,
              value.range(of: #"https?://|sk-[A-Za-z0-9]|tsutae_[A-Za-z0-9]|^[a-f0-9]{24,}$"#, options: [.regularExpression, .caseInsensitive]) == nil,
              value.range(of: #"[A-Za-z\p{Han}]"#, options: .regularExpression) != nil else {
            return nil
        }
        return value
    }

    private func automaticKeys(for term: String) -> [String] {
        var keys: [String] = [term]
        let separated = term
            .replacingOccurrences(of: #"([a-z0-9])([A-Z])"#, with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: #"[-_]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if separated.isEmpty == false, separated.caseInsensitiveCompare(term) != .orderedSame {
            keys.append(separated)
        }

        var seen = Set<String>()
        return keys.filter { seen.insert($0.lowercased()).inserted }
    }
}

public enum TranscriptPostProcessor {
    private static let logger = Logger(subsystem: "dev.yanfch.Tsutae", category: "TranscriptPostProcessor")

    public static func process(
        _ text: String,
        config: Config.TranscriptPostProcessingConfig,
        task: Config.TranscriptPostProcessingTask? = nil,
        language: String? = nil,
        appContext: String? = nil,
        dictionaryContext: TranscriptDictionaryContext = .empty,
        apiKeyOverride: String? = nil,
        session: URLSessionProtocol = URLSession.shared
    ) async throws -> TranscriptPostProcessingResult {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let rawText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard rawText.isEmpty == false else {
            throw TranscriptPostProcessingError.emptyInput
        }

        let resolvedTask = task ?? config.defaultTask
        let mode = config.enabled ? config.mode : .off
        let executionMode = executionMode(for: mode, task: resolvedTask, config: config)

        let result: TranscriptPostProcessingResult
        switch executionMode {
        case .off:
            result = TranscriptPostProcessingResult(
                rawText: rawText,
                processedText: rawText,
                mode: mode,
                task: resolvedTask,
                provider: providerName("off", requestedMode: mode, executionMode: executionMode),
                model: nil,
                elapsedMs: elapsedMs(since: startedAt)
            )
        case .rules, .smart:
            let dictionaryResult = TranscriptDictionaryReplacer.apply(
                to: RuleBasedTranscriptCleaner.clean(rawText),
                config: config.dictionary,
                context: dictionaryContext
            )
            let provider = dictionaryResult.matches.isEmpty ? "rules" : "rules+dictionary"
            result = TranscriptPostProcessingResult(
                rawText: rawText,
                processedText: dictionaryResult.text,
                mode: mode,
                task: resolvedTask,
                provider: providerName(provider, requestedMode: mode, executionMode: executionMode),
                model: nil,
                elapsedMs: elapsedMs(since: startedAt),
                dictionaryMatches: dictionaryResult.matches
            )
        case .remote:
            let remote = config.remote
            guard remote.enabled,
                  let baseURLString = remote.baseURL?.nilIfBlank,
                  let baseURL = URL(string: baseURLString),
                  let model = remote.model?.nilIfBlank else {
                throw TranscriptPostProcessingError.invalidRemoteConfiguration
            }

            let apiKey: String?
            if let override = apiKeyOverride?.nilIfBlank {
                apiKey = override
            } else {
                apiKey = try remote.apiKeyRef.flatMap { try SecretsManager.get($0) }
            }
            let preparedInput = TranscriptDictionaryReplacer.apply(
                to: RuleBasedTranscriptCleaner.clean(rawText),
                config: config.dictionary,
                context: dictionaryContext
            )
            let remoteInput = preparedInput.text.nilIfBlank ?? rawText
            let client = OpenAICompatibleTextClient(baseURL: baseURL, model: model, apiKey: apiKey, session: session)
            let remoteProcessed = try await client.rewriteTranscript(
                remoteInput,
                task: resolvedTask,
                language: language,
                appContext: appContext
            )
            let dictionaryResult = TranscriptDictionaryReplacer.apply(
                to: remoteProcessed,
                config: config.dictionary,
                context: dictionaryContext
            )
            let normalizedText = normalizeRemoteOutput(dictionaryResult.text, sourceText: remoteInput, task: resolvedTask)
            let dictionaryMatches = mergedMatches(preparedInput.matches, dictionaryResult.matches)
            let provider = dictionaryMatches.isEmpty ? "openai_compatible" : "openai_compatible+dictionary"
            result = TranscriptPostProcessingResult(
                rawText: rawText,
                processedText: normalizedText,
                mode: mode,
                task: resolvedTask,
                provider: providerName(provider, requestedMode: mode, executionMode: executionMode),
                model: model,
                elapsedMs: elapsedMs(since: startedAt),
                dictionaryMatches: dictionaryMatches
            )
        }

        logger.info("Post-processing finished. mode=\(result.mode.rawValue, privacy: .public) task=\(result.task.rawValue, privacy: .public) chars_in=\(rawText.count) chars_out=\(result.processedText.count) elapsed_ms=\(String(format: "%.1f", result.elapsedMs), privacy: .public)")
        PerformanceLog.record(category: "TranscriptPostProcessor", message: "mode=\(result.mode.rawValue) task=\(result.task.rawValue) chars_in=\(rawText.count) chars_out=\(result.processedText.count) elapsed_ms=\(String(format: "%.1f", result.elapsedMs))")
        return result
    }

    private static func executionMode(
        for mode: Config.TranscriptPostProcessingMode,
        task: Config.TranscriptPostProcessingTask,
        config: Config.TranscriptPostProcessingConfig
    ) -> Config.TranscriptPostProcessingMode {
        guard mode == .smart else { return mode }
        guard task != .cleanDictation,
              config.remote.enabled,
              config.remote.baseURL?.nilIfBlank != nil,
              config.remote.model?.nilIfBlank != nil else {
            return .rules
        }
        return .remote
    }

    private static func providerName(
        _ provider: String,
        requestedMode: Config.TranscriptPostProcessingMode,
        executionMode: Config.TranscriptPostProcessingMode
    ) -> String {
        guard requestedMode == .smart, executionMode != .smart else {
            return provider
        }
        return "smart:\(provider)"
    }

    private static func normalizeRemoteOutput(
        _ text: String,
        sourceText: String,
        task: Config.TranscriptPostProcessingTask
    ) -> String {
        var output = text
        if hasExplicitOpenQuestionSignal(sourceText) == false {
            output = output.replacingOccurrences(
                of: #"(?s)\n{0,2}##\s*(开放问题|Open Questions)\s*\n.*?(?=$|\n##\s)"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        output = output.replacingOccurrences(
            of: #"(?s)\n{0,2}##\s*(摘要|Summary|决策|Decisions|行动项|Action Items|开放问题|Open Questions)\s*\n\s*(?:[-*]\s*)?(?:（无）|\(无\)|无|\(none\)|none|n/a)\s*(?=$|\n##\s)"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        if task == .cleanDictation {
            output = preservingSourceTerminalPunctuation(output, sourceText: sourceText)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func preservingSourceTerminalPunctuation(_ output: String, sourceText: String) -> String {
        guard let sourceTerminal = sourceText.trimmingCharacters(in: .whitespacesAndNewlines).last,
              let outputTerminal = output.trimmingCharacters(in: .whitespacesAndNewlines).last else {
            return output
        }
        let sourceQuestionMarks = CharacterSet(charactersIn: "?？")
        guard String(sourceTerminal).rangeOfCharacter(from: sourceQuestionMarks) != nil else {
            return output
        }
        let replaceableTerminal = CharacterSet(charactersIn: ".。")
        guard String(outputTerminal).rangeOfCharacter(from: replaceableTerminal) != nil else {
            return output
        }

        var normalized = output.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.removeLast()
        normalized.append(sourceTerminal)
        return normalized
    }

    private static func hasExplicitOpenQuestionSignal(_ text: String) -> Bool {
        text.range(
            of: #"(开放问题|待确认|不确定|还没确定|问题是|open questions?|uncertain|pending decision)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func elapsedMs(since startedAt: CFAbsoluteTime) -> Double {
        (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
    }

    private static func mergedMatches(_ lhs: [String], _ rhs: [String]) -> [String] {
        var seen = Set<String>()
        var merged: [String] = []
        for value in lhs + rhs where seen.insert(value).inserted {
            merged.append(value)
        }
        return merged
    }
}

public enum TranscriptDictionaryReplacer {
    public struct Result: Sendable, Equatable {
        public let text: String
        public let matches: [String]
    }

    public static var builtInPreviewEntries: [Config.TranscriptDictionaryEntry] {
        builtInEntries
    }

    public static func apply(
        to text: String,
        config: Config.TranscriptDictionaryConfig,
        context: TranscriptDictionaryContext = .empty
    ) -> Result {
        guard config.enabled else {
            return Result(text: text, matches: [])
        }

        let entries = resolvedEntries(config: config, context: context)
            .filter { $0.enabled && $0.key.nilIfBlank != nil && $0.value.nilIfBlank != nil }
            .map { (entry: $0, lookupKey: $0.key.lowercased()) }
            .sorted {
                if $0.entry.key.count == $1.entry.key.count {
                    return $0.entry.key < $1.entry.key
                }
                return $0.entry.key.count > $1.entry.key.count
            }

        var output = normalizeMixedScriptSpacing(text)
        var lookupText = output.lowercased()
        var matches: [String] = []
        for entry in entries {
            guard lookupText.contains(entry.lookupKey) else { continue }
            let next = replace(entry.entry.key, with: entry.entry.value, in: output)
            if next != output {
                output = next
                lookupText = output.lowercased()
                matches.append(entry.entry.key)
            }
        }
        return Result(text: normalizeMixedScriptSpacing(output), matches: matches)
    }

    private static func resolvedEntries(
        config: Config.TranscriptDictionaryConfig,
        context: TranscriptDictionaryContext
    ) -> [Config.TranscriptDictionaryEntry] {
        var entriesByKey: [String: Config.TranscriptDictionaryEntry] = [:]
        if config.useBuiltIn {
            for entry in builtInEntries {
                entriesByKey[entry.key.lowercased()] = entry
            }
        }
        if config.useAutomatic {
            for entry in context.entries {
                entriesByKey[entry.key.lowercased()] = entry
            }
        }
        for entry in config.entries {
            entriesByKey[entry.key.lowercased()] = entry
        }
        return Array(entriesByKey.values)
    }

    private static func replace(_ key: String, with value: String, in text: String) -> String {
        let pattern = regexPattern(for: key)
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }

        var result = text
        let range = NSRange(result.startIndex..<result.endIndex, in: result)
        for match in regex.matches(in: result, options: [], range: range).reversed() {
            guard let swiftRange = Range(match.range, in: result) else { continue }
            result.replaceSubrange(swiftRange, with: value)
        }
        return result
    }

    private static func regexPattern(for key: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: key)
        if containsCJKScript(key) {
            return escaped
        }

        let startsWordLike = key.range(of: #"^[\p{L}\p{N}\p{M}_]"#, options: .regularExpression) != nil
        let endsWordLike = key.range(of: #"[\p{L}\p{N}\p{M}_]$"#, options: .regularExpression) != nil
        let prefix = startsWordLike ? #"(?<![\p{L}\p{N}\p{M}_])"# : ""
        let suffix = endsWordLike ? #"(?![\p{L}\p{N}\p{M}_])"# : ""
        return prefix + escaped + suffix
    }

    private static func containsCJKScript(_ text: String) -> Bool {
        text.range(of: #"[\p{Han}\p{Hiragana}\p{Katakana}\p{Hangul}]"#, options: .regularExpression) != nil
    }

    private static func normalizeMixedScriptSpacing(_ text: String) -> String {
        var output = text
        output = output.replacingOccurrences(
            of: #"(\p{Han})([A-Za-z0-9_][A-Za-z0-9_+-]*)"#,
            with: "$1 $2",
            options: .regularExpression
        )
        output = output.replacingOccurrences(
            of: #"([A-Za-z0-9_][A-Za-z0-9_+-]*)(\p{Han})"#,
            with: "$1 $2",
            options: .regularExpression
        )
        output = output.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        output = output.replacingOccurrences(of: #"\s+([，。！？；：、,.!?;:])"#, with: "$1", options: .regularExpression)
        output = output.replacingOccurrences(
            of: #"\n{0,2}##\s*(开放问题|Open Questions)\s*\n\s*(?:[-*]\s*)?(?:（无）|\(无\)|无|\(none\)|none|n/a)\s*$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let builtInEntries: [Config.TranscriptDictionaryEntry] = [
        .init(key: "open ai compatible", value: "OpenAI-compatible"),
        .init(key: "open ai", value: "OpenAI"),
        .init(key: "github issue", value: "GitHub Issue"),
        .init(key: "github actions", value: "GitHub Actions"),
        .init(key: "type script", value: "TypeScript"),
        .init(key: "swift ui", value: "SwiftUI"),
        .init(key: "swift package manager", value: "Swift Package Manager"),
        .init(key: "server api stt", value: "Server API、STT"),
        .init(key: "server api", value: "Server API"),
        .init(key: "server token", value: "Server token"),
        .init(key: "remoteapi", value: "Remote API"),
        .init(key: "remote api", value: "Remote API"),
        .init(key: "localapi", value: "Local API"),
        .init(key: "local api", value: "Local API"),
        .init(key: "base url", value: "Base URL"),
        .init(key: "key chain", value: "Keychain"),
        .init(key: "full back", value: "fallback"),
        .init(key: "fullback", value: "fallback"),
        .init(key: "voice id", value: "voiceId"),
        .init(key: "voiceid", value: "voiceId"),
        .init(key: "local host", value: "localhost"),
        .init(key: "deep seek", value: "DeepSeek"),
        .init(key: "codex hook", value: "Codex hook"),
        .init(key: "code x", value: "Codex"),
        .init(key: "code ex", value: "Codex"),
        .init(key: "codex", value: "Codex"),
        .init(key: "git hub actions", value: "GitHub Actions"),
        .init(key: "git hub issue", value: "GitHub Issue"),
        .init(key: "git hub", value: "GitHub"),
        .init(key: "github", value: "GitHub"),
        .init(key: "kanade", value: "Kanade"),
        .init(key: "tsutae", value: "Tsutae"),
        .init(key: "x code", value: "Xcode"),
        .init(key: "readme", value: "README"),
        .init(key: "json", value: "JSON"),
        .init(key: "yaml", value: "YAML"),
        .init(key: "apple", value: "Apple"),
        .init(key: "https", value: "HTTPS"),
        .init(key: "http", value: "HTTP"),
        .init(key: "url", value: "URL"),
        .init(key: "mac os", value: "macOS"),
        .init(key: "ios", value: "iOS"),
        .init(key: "stt", value: "STT"),
        .init(key: "tts", value: "TTS"),
        .init(key: "asr", value: "ASR"),
        .init(key: "llm", value: "LLM"),
        .init(key: "transscribe", value: "transcribe"),
        .init(key: "condexapp", value: "Codex app"),
        .init(key: "codex app", value: "Codex app"),
        .init(key: "ssd", value: "SSD"),
        .init(key: "vr", value: "VR"),
        .init(key: "scope type", value: "scopeType"),
        .init(key: "scopetype", value: "scopeType"),
        .init(key: "api", value: "API"),
        .init(key: "ui", value: "UI"),
        .init(key: "mimo", value: "Mimo"),
        .init(key: "kokoro", value: "Kokoro"),
        .init(key: "卡纳德", value: "Kanade"),
        .init(key: "卡纳的", value: "Kanade"),
        .init(key: "扣得克斯", value: "Codex"),
        .init(key: "扣的克斯", value: "Codex"),
        .init(key: "次他诶", value: "Tsutae"),
        .init(key: "辞他诶", value: "Tsutae")
    ]
}

public enum RuleBasedTranscriptCleaner {
    public static func clean(_ text: String) -> String {
        var cleaned = TranscriptInitialNormalizer.normalize(text)
        cleaned = TranscriptFillerCleaner.clean(cleaned)
        cleaned = SpokenPunctuationNormalizer.normalize(cleaned)
        cleaned = ChineseRunOnSegmenter.segment(cleaned)
        cleaned = TranscriptSpacingNormalizer.normalize(cleaned)
        cleaned = TerminalPunctuationAppender.appendIfNeeded(cleaned)
        return cleaned
    }
}

private enum TranscriptInitialNormalizer {
    static func normalize(_ text: String) -> String {
        var output = text.trimmingCharacters(in: .whitespacesAndNewlines)
        output = output.replacingOccurrences(of: "\r\n", with: "\n")
        output = output.replacingOccurrences(of: "\r", with: "\n")
        output = output.replacingOccurrences(
            of: #"(?<=[A-Za-z])@@(?=[A-Za-z])"#,
            with: "",
            options: .regularExpression
        )
        output = output.replacingOccurrences(
            of: #"(?m)^[\s"'“”‘’]+|[\s"'“”‘’]+$"#,
            with: "",
            options: .regularExpression
        )
        return output
    }
}

private enum TranscriptFillerCleaner {
    static func clean(_ text: String) -> String {
        var output = text
        output = output.replacingOccurrences(of: #"\b(um+|uh+|erm)\b[,\s]*"#, with: "", options: [.regularExpression, .caseInsensitive])
        output = output.replacingOccurrences(of: #"(嗯啊+|呃+|嗯+|啊{2,})[，,、\s]*"#, with: "", options: .regularExpression)
        output = output.replacingOccurrences(of: #"(^|[，,、\s])额+[，,、\s]+"#, with: "$1", options: .regularExpression)
        output = output.replacingOccurrences(of: #"(^|[，,、\s])啊[，,、\s]*"#, with: "$1", options: .regularExpression)
        output = output.replacingOccurrences(of: #"[^。！？.!?\n]*[，,、\s]*(等等)?不对[，,、\s]*其实"#, with: "", options: .regularExpression)
        output = output.replacingOccurrences(of: #"(然后|就是|那个|这个)(?:[，,、\s]*\1)+"#, with: "$1", options: .regularExpression)
        return output
    }
}

private enum SpokenPunctuationNormalizer {
    static func normalize(_ text: String) -> String {
        var output = text
        let chineseCommands: [(String, String)] = [
            ("新段落", "\n\n"),
            ("换行", "\n"),
            ("逗号", "，"),
            ("句号", "。"),
            ("问号", "？"),
            ("感叹号", "！"),
            ("叹号", "！"),
            ("冒号", "："),
            ("分号", "；")
        ]
        for (command, replacement) in chineseCommands {
            output = output.replacingOccurrences(of: command, with: replacement)
        }

        let englishCommands: [(String, String)] = [
            (#"\bnew paragraph\b"#, "\n\n"),
            (#"\bnew line\b"#, "\n"),
            (#"\bquestion mark\b"#, "?"),
            (#"\bexclamation (?:point|mark)\b"#, "!"),
            (#"\bfull stop\b"#, "."),
            (#"\bperiod\b"#, "."),
            (#"\bcomma\b"#, ","),
            (#"\bcolon\b"#, ":"),
            (#"\bsemicolon\b"#, ";")
        ]
        for (pattern, replacement) in englishCommands {
            output = output.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return output
    }
}

private enum ChineseRunOnSegmenter {
    static func segment(_ text: String) -> String {
        guard TranscriptPunctuationHeuristics.containsCJK(text), text.count >= 24 else { return text }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return lines
            .map { segmentParagraph(String($0)) }
            .joined(separator: "\n")
    }

    private static func segmentParagraph(_ paragraph: String) -> String {
        guard paragraph.count >= 24,
              TranscriptPunctuationHeuristics.containsCJK(paragraph),
              paragraph.range(of: #"[。！？!?]"#, options: .regularExpression) == nil else {
            return paragraph
        }

        var output = paragraph
        output = insertChineseBoundary(
            in: output,
            before: ["另外", "接下来", "我想", "我们需要", "我们可以", "你觉得"],
            punctuation: "。",
            minPrefix: 8,
            minSuffix: 8
        )
        output = insertChineseBoundary(
            in: output,
            before: ["然后", "但是", "所以", "不过"],
            punctuation: "，",
            minPrefix: 6,
            minSuffix: 3
        )
        output = insertChineseBoundary(
            in: output,
            before: ["在目前", "目前", "现在", "当前", "后面", "之前", "其实", "就比如", "比如", "感觉", "我觉得", "可能跟", "是不是", "是什么", "怎么", "为什么", "能不能", "可不可以", "有没有"],
            punctuation: "，",
            minPrefix: 8,
            minSuffix: 3
        )
        output = output.replacingOccurrences(
            of: #"(可以啊|可以|没问题|有点空|好多了|行|好)(我们|我|你|这个|那)"#,
            with: "$1，$2",
            options: .regularExpression
        )
        return output
    }

    private static func insertChineseBoundary(
        in text: String,
        before markers: [String],
        punctuation: String,
        minPrefix: Int,
        minSuffix: Int
    ) -> String {
        var output = text
        var searchStart = output.startIndex

        while searchStart < output.endIndex {
            guard let match = nextMarker(in: output, markers: markers, from: searchStart) else {
                break
            }
            let markerOffset = output.distance(from: output.startIndex, to: match.range.lowerBound)

            if shouldInsertBoundary(
                in: output,
                at: match.range.lowerBound,
                markerEnd: match.range.upperBound,
                punctuation: punctuation,
                minPrefix: minPrefix,
                minSuffix: minSuffix
            ) {
                output = String(output[..<match.range.lowerBound]) + punctuation + String(output[match.range.lowerBound...])
                let nextOffset = min(markerOffset + punctuation.count + match.marker.count, output.count)
                searchStart = output.index(output.startIndex, offsetBy: nextOffset)
            } else {
                if punctuation == "。",
                   shouldInsertQuestionContinuationBoundary(
                       in: output,
                       at: match.range.lowerBound,
                       markerEnd: match.range.upperBound,
                       minSuffix: 4
                   ) {
                    output = String(output[..<match.range.lowerBound]) + "，" + String(output[match.range.lowerBound...])
                    let nextOffset = min(markerOffset + 1 + match.marker.count, output.count)
                    searchStart = output.index(output.startIndex, offsetBy: nextOffset)
                } else {
                    searchStart = match.range.upperBound
                }
            }
        }

        return output
    }

    private static func nextMarker(
        in text: String,
        markers: [String],
        from start: String.Index
    ) -> (range: Range<String.Index>, marker: String)? {
        var selected: (range: Range<String.Index>, marker: String)?
        for marker in markers {
            guard let range = text.range(of: marker, range: start..<text.endIndex) else { continue }
            if selected == nil || range.lowerBound < selected!.range.lowerBound {
                selected = (range, marker)
            }
        }
        return selected
    }

    private static func shouldInsertBoundary(
        in text: String,
        at markerStart: String.Index,
        markerEnd: String.Index,
        punctuation: String,
        minPrefix: Int,
        minSuffix: Int
    ) -> Bool {
        guard markerStart > text.startIndex else { return false }
        guard hasBoundaryBeforeMarker(in: text, at: markerStart) == false else {
            return false
        }

        let prefixCount = countSinceLastBoundary(in: text[..<markerStart])
        let suffixCount = countUntilNextBoundary(in: text[markerEnd...])
        if punctuation == "。", TranscriptPunctuationHeuristics.isLikelyChineseQuestion(String(text[..<markerStart])) {
            return false
        }
        return prefixCount >= minPrefix && suffixCount >= minSuffix
    }

    private static func shouldInsertQuestionContinuationBoundary(
        in text: String,
        at markerStart: String.Index,
        markerEnd: String.Index,
        minSuffix: Int
    ) -> Bool {
        guard markerStart > text.startIndex else { return false }
        let previousIndex = text.index(before: markerStart)
        let previous = String(text[previousIndex])
        let boundaryCharacters = CharacterSet(charactersIn: "，,、。！？!?；;：:\n ")
        guard previous.rangeOfCharacter(from: boundaryCharacters) == nil else {
            return false
        }
        guard TranscriptPunctuationHeuristics.isLikelyChineseQuestion(String(text[..<markerStart])) else {
            return false
        }
        return countUntilNextBoundary(in: text[markerEnd...]) >= minSuffix
    }

    private static func hasBoundaryBeforeMarker(in text: String, at markerStart: String.Index) -> Bool {
        var index = text.index(before: markerStart)
        while text[index].isWhitespace, index > text.startIndex {
            index = text.index(before: index)
        }
        let previous = String(text[index])
        let boundaryCharacters = CharacterSet(charactersIn: "，,、。！？!?；;：:\n")
        return previous.rangeOfCharacter(from: boundaryCharacters) != nil
    }

    private static func countSinceLastBoundary(in prefix: Substring) -> Int {
        var count = 0
        let boundaries = CharacterSet(charactersIn: "，,、。！？!?；;：:\n")
        for character in prefix.reversed() {
            if String(character).rangeOfCharacter(from: boundaries) != nil {
                break
            }
            count += 1
        }
        return count
    }

    private static func countUntilNextBoundary(in suffix: Substring) -> Int {
        var count = 0
        let boundaries = CharacterSet(charactersIn: "，,、。！？!?；;：:\n")
        for character in suffix {
            if String(character).rangeOfCharacter(from: boundaries) != nil {
                break
            }
            count += 1
        }
        return count
    }
}

private enum TranscriptSpacingNormalizer {
    static func normalize(_ text: String) -> String {
        var output = text
        output = output.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        output = output.replacingOccurrences(of: #"[ \t]*\n[ \t]*"#, with: "\n", options: .regularExpression)
        output = output.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        output = output.replacingOccurrences(of: #"\s+([，。！？；：、,.!?;:])"#, with: "$1", options: .regularExpression)
        output = output.replacingOccurrences(of: #"(\p{Han})[ \t]+(\p{Han})"#, with: "$1$2", options: .regularExpression)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum TerminalPunctuationAppender {
    static func appendIfNeeded(_ text: String) -> String {
        guard let last = text.last else { return text }
        let terminal = CharacterSet(charactersIn: "。.!?！？")
        if String(last).rangeOfCharacter(from: terminal) != nil {
            return text
        }
        if TranscriptPunctuationHeuristics.containsCJK(text) {
            return text + chineseTerminalPunctuation(for: text)
        }
        return text + englishTerminalPunctuation(for: text)
    }

    private static func chineseTerminalPunctuation(for text: String) -> String {
        if TranscriptPunctuationHeuristics.isLikelyChineseQuestion(text) {
            return "？"
        }
        if TranscriptPunctuationHeuristics.isLikelyChineseExclamation(text) {
            return "！"
        }
        return "。"
    }

    private static func englishTerminalPunctuation(for text: String) -> String {
        if TranscriptPunctuationHeuristics.isLikelyEnglishQuestion(text) {
            return "?"
        }
        if TranscriptPunctuationHeuristics.isLikelyEnglishExclamation(text) {
            return "!"
        }
        return "."
    }
}

private enum TranscriptPunctuationHeuristics {
    static func isLikelyChineseQuestion(_ text: String) -> Bool {
        let compact = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let terminalQuestionPattern = #"(吗|么|呢|什么|为什么|怎么|如何|哪里|哪儿|哪个|哪种|谁|多少|几点|能不能|是不是|可不可以|要不要|有没有|行不行|对不对|好不好|可以吗|对吗)$"#
        if compact.range(of: terminalQuestionPattern, options: .regularExpression) != nil {
            return true
        }
        let binaryQuestionPattern = #"(是不是|能不能|可不可以|要不要|有没有|行不行|对不对|好不好)"#
        if compact.range(of: binaryQuestionPattern, options: .regularExpression) != nil {
            return true
        }
        let leadingQuestionPattern = #"^(为什么|怎么|如何|哪里|哪儿|谁|多少|几点|哪个|哪种)"#
        return compact.range(of: leadingQuestionPattern, options: .regularExpression) != nil
    }

    static func isLikelyChineseExclamation(_ text: String) -> Bool {
        let compact = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let imperativePattern = #"^(注意|小心|别|不要|必须|一定)"#
        if compact.range(of: imperativePattern, options: .regularExpression) != nil {
            return true
        }
        let emphasisPattern = #"(太.+了|真.+|好.+啊|.+极了)$"#
        return compact.range(of: emphasisPattern, options: .regularExpression) != nil
    }

    static func isLikelyEnglishQuestion(_ text: String) -> Bool {
        let compact = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let leadingQuestionPattern = #"^(what|why|how|where|when|who|which|can|could|should|would|will|do|does|did|is|are|was|were|am|may|might)\b"#
        return compact.range(of: leadingQuestionPattern, options: .regularExpression) != nil
    }

    static func isLikelyEnglishExclamation(_ text: String) -> Bool {
        let compact = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let expressionPattern = #"^(great|awesome|nice|perfect|warning|stop|don'?t)\b"#
        return compact.range(of: expressionPattern, options: .regularExpression) != nil
    }

    static func containsCJK(_ text: String) -> Bool {
        text.range(of: #"\p{Han}"#, options: .regularExpression) != nil
    }
}

public final class OpenAICompatibleTextClient: @unchecked Sendable {
    private let baseURL: URL
    private let model: String
    private let apiKey: String?
    private let session: URLSessionProtocol

    public init(
        baseURL: URL,
        model: String,
        apiKey: String? = nil,
        session: URLSessionProtocol = URLSession.shared
    ) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.session = session
    }

    public func rewriteTranscript(
        _ text: String,
        task: Config.TranscriptPostProcessingTask,
        language: String? = nil,
        appContext: String? = nil
    ) async throws -> String {
        var request = URLRequest(url: endpointURL())
        request.httpMethod = "POST"
        request.timeoutInterval = 75
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthorization(to: &request)
        request.httpBody = try JSONEncoder().encode(ChatCompletionsTextRequest(
            model: model,
            messages: PromptBuilder.messages(text: text, task: task, language: language, appContext: appContext),
            temperature: 0.1
        ))

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        let decoded = try decodeTextResponse(from: data)
        guard let content = decoded.choices.first?.message.content.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              content.isEmpty == false else {
            throw TranscriptPostProcessingError.invalidResponse
        }
        return stripMarkdownFence(content)
    }

    private func endpointURL() -> URL {
        var absolute = baseURL.absoluteString
        while absolute.hasSuffix("/") { absolute.removeLast() }
        if absolute.hasSuffix("/v1/chat/completions") || absolute.hasSuffix("/chat/completions") {
            return URL(string: absolute)!
        }
        if absolute.hasSuffix("/v1") {
            return URL(string: absolute + "/chat/completions")!
        }
        return URL(string: absolute + "/v1/chat/completions")!
    }

    private func applyAuthorization(to request: inout URLRequest) {
        guard let apiKey, apiKey.isEmpty == false else { return }
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if baseURL.host?.lowercased().contains("xiaomimimo.com") == true {
            request.setValue(apiKey, forHTTPHeaderField: "api-key")
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw TranscriptPostProcessingError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw TranscriptPostProcessingError.httpStatus(http.statusCode, extractErrorMessage(from: data))
        }
    }

    private func extractErrorMessage(from data: Data) -> String {
        if let decoded = try? JSONDecoder().decode(TextErrorEnvelope.self, from: data) {
            return decoded.error.message
        }
        return String(data: data, encoding: .utf8)?.nilIfBlank ?? "Unknown error"
    }

    private func decodeTextResponse(from data: Data) throws -> ChatCompletionsTextResponse {
        do {
            return try JSONDecoder().decode(ChatCompletionsTextResponse.self, from: data)
        } catch {
            let sanitized = Self.escapingControlCharactersInsideJSONStrings(data)
            guard sanitized != data else { throw error }
            return try JSONDecoder().decode(ChatCompletionsTextResponse.self, from: sanitized)
        }
    }

    private static func escapingControlCharactersInsideJSONStrings(_ data: Data) -> Data {
        var output = Data()
        output.reserveCapacity(data.count)
        var inString = false
        var isEscaped = false

        for byte in data {
            if inString, byte < 0x20 {
                switch byte {
                case 0x08:
                    output.append(contentsOf: [0x5C, 0x62])
                case 0x09:
                    output.append(contentsOf: [0x5C, 0x74])
                case 0x0A:
                    output.append(contentsOf: [0x5C, 0x6E])
                case 0x0C:
                    output.append(contentsOf: [0x5C, 0x66])
                case 0x0D:
                    output.append(contentsOf: [0x5C, 0x72])
                default:
                    output.append(contentsOf: Array(String(format: "\\u%04X", byte).utf8))
                }
                isEscaped = false
                continue
            }

            output.append(byte)

            if isEscaped {
                isEscaped = false
                continue
            }
            if byte == 0x5C {
                isEscaped = true
                continue
            }
            if byte == 0x22 {
                inString.toggle()
            }
        }
        return output
    }

    private func stripMarkdownFence(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("```") {
            value = value.replacingOccurrences(of: #"^```[a-zA-Z-]*\s*"#, with: "", options: .regularExpression)
            value = value.replacingOccurrences(of: #"\s*```$"#, with: "", options: .regularExpression)
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum PromptBuilder {
    static func messages(
        text: String,
        task: Config.TranscriptPostProcessingTask,
        language: String?,
        appContext: String?
    ) -> [ChatCompletionsTextRequest.Message] {
        [
            .init(role: "system", content: systemPrompt(for: task)),
            .init(role: "user", content: userPrompt(text: text, task: task, language: language, appContext: appContext))
        ]
    }

    private static func systemPrompt(for task: Config.TranscriptPostProcessingTask) -> String {
        switch task {
        case .cleanDictation:
            return """
            You are a strict transcript editor. Improve speech-to-text output with minimal edits.
            Keep the speaker's meaning, language, names, code identifiers, URLs, numbers, and technical terms.
            Fix punctuation, casing, spacing, obvious ASR mistakes, filler words, repetitions, and explicit self-corrections.
            Remove standalone hesitation/filler words and discard corrected-away phrases when the speaker explicitly corrects themselves.
            Keep the same primary language as the input.
            Do not add new facts. Return only the final edited text.
            """
        case .rewriteMessage:
            return """
            You rewrite rough dictated notes into a concise message that is ready to send.
            Keep the user's intent, facts, names, code identifiers, URLs, dates, and numbers.
            Remove filler words, repeated phrases, and explicit self-corrections.
            Improve organization, punctuation, and tone without adding new facts.
            Keep the same primary language as the input.
            Preserve technical terms, product names, API names, model names, callback names, code identifiers, configuration values, and mixed-case tokens exactly as written.
            Do not translate or recase literal technical tokens found in the input.
            Prefer one or two short sentences.
            Return only the final message.
            """
        case .meetingNotes:
            return """
            You turn rough dictated meeting transcripts into concise meeting notes.
            Preserve decisions, action items, owners, dates, risks, and open questions.
            Do not invent missing owners, dates, or facts. Use the same primary language as the input.
            If an action has no explicit owner, write "未指定" or "Unassigned" instead of guessing.
            Every action item bullet must include an owner label. If the transcript does not name an owner, start the bullet with "未指定：" or "Unassigned:".
            For Chinese action items without an explicit owner, use exactly "- 未指定：<action>".
            App names, project names, and product names are not owners unless the transcript explicitly says they are responsible.
            Never use the project being discussed as an owner just because it appears before the action.
            Do not convert decisions, defaults, or policy statements into action items unless the transcript explicitly says someone needs to do work.
            Preserve exact product names, app names, technical terms, API names, code identifiers, model names, and owner names from the transcript.
            Keep adjacent technical terms as separate concepts; do not merge terms such as "Server API" and "STT" into a new phrase.
            Use Markdown heading syntax with "##".
            For Chinese input, use exactly these headings when relevant: ## 摘要, ## 决策, ## 行动项, ## 开放问题.
            For English input, use exactly these headings when relevant: ## Summary, ## Decisions, ## Action Items, ## Open Questions.
            Only include Open Questions/开放问题 when the transcript explicitly says a question, uncertainty, pending decision, or "待确认".
            Keep notes concise, omit empty sections, and never output a heading with no bullet or content under it.
            Return only the notes.
            """
        }
    }

    private static func userPrompt(
        text: String,
        task: Config.TranscriptPostProcessingTask,
        language: String?,
        appContext: String?
    ) -> String {
        var lines: [String] = []
        if let language = language?.nilIfBlank {
            lines.append("Language hint: \(language)")
        }
        if let appContext = appContext?.nilIfBlank {
            lines.append("App context: \(appContext)")
        }
        switch task {
        case .cleanDictation:
            lines.append("Clean this dictated transcript:")
        case .rewriteMessage:
            lines.append("Rewrite this dictated note into a ready-to-send message:")
        case .meetingNotes:
            lines.append("Create meeting notes from this transcript:")
        }
        lines.append(text)
        return lines.joined(separator: "\n\n")
    }
}

private struct ChatCompletionsTextRequest: Encodable {
    let model: String
    let messages: [Message]
    let temperature: Double

    struct Message: Encodable {
        let role: String
        let content: String
    }
}

private struct ChatCompletionsTextResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: ContentValue
    }

    enum ContentValue: Decodable {
        case string(String)
        case parts([Part])

        struct Part: Decodable {
            let type: String?
            let text: String?
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                self = .string(string)
                return
            }
            self = .parts(try container.decode([Part].self))
        }

        var text: String? {
            switch self {
            case .string(let value):
                return value
            case .parts(let parts):
                let combined = parts.compactMap(\.text).joined(separator: "\n")
                return combined.isEmpty ? nil : combined
            }
        }
    }
}

private struct TextErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String
    }

    let error: APIError
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
