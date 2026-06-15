import AVFoundation
import Foundation
import NaturalLanguage
import OSLog

public enum TTSPlaybackState: String, Codable, Sendable {
    case idle
    case queued
    case speaking
    case stopping
}

public struct TTSSpeakRequest: Codable, Sendable {
    public let text: String
    public let source: String?
    public let interrupt: Bool?
    public let voice: String?
    public let rate: Double?
    public let presentationStyle: Config.TTSPresentationStyle?

    public init(
        text: String,
        source: String? = nil,
        interrupt: Bool? = nil,
        voice: String? = nil,
        rate: Double? = nil,
        presentationStyle: Config.TTSPresentationStyle? = nil
    ) {
        self.text = text
        self.source = source
        self.interrupt = interrupt
        self.voice = voice
        self.rate = rate
        self.presentationStyle = presentationStyle
    }

    public func withSource(_ source: String?) -> TTSSpeakRequest {
        TTSSpeakRequest(
            text: text,
            source: source,
            interrupt: interrupt,
            voice: voice,
            rate: rate,
            presentationStyle: presentationStyle
        )
    }
}

public struct TTSSpeakResponse: Codable, Sendable {
    public let ok: Bool
    public let state: TTSPlaybackState
    public let source: String?
    public let presentationStyle: Config.TTSPresentationStyle
    public let queueLength: Int

    public init(
        ok: Bool,
        state: TTSPlaybackState,
        source: String?,
        presentationStyle: Config.TTSPresentationStyle = .standard,
        queueLength: Int = 0
    ) {
        self.ok = ok
        self.state = state
        self.source = source
        self.presentationStyle = presentationStyle
        self.queueLength = queueLength
    }
}

public struct TTSAudioSpeechRequest: Codable, Sendable {
    public let input: String
    public let model: String?
    public let voice: String?
    public let instructions: String?
    public let responseFormat: String?
    public let requestStyle: Config.TTSRemoteRequestStyle?

    public init(
        input: String,
        model: String? = nil,
        voice: String? = nil,
        instructions: String? = nil,
        responseFormat: String? = nil,
        requestStyle: Config.TTSRemoteRequestStyle? = nil
    ) {
        self.input = input
        self.model = model
        self.voice = voice
        self.instructions = instructions
        self.responseFormat = responseFormat
        self.requestStyle = requestStyle
    }

    enum CodingKeys: String, CodingKey {
        case input, model, voice, instructions
        case responseFormat = "response_format"
        case requestStyle = "request_style"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        input = try container.decode(String.self, forKey: .input)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        instructions = try container.decodeIfPresent(String.self, forKey: .instructions)
        responseFormat = try container.decodeIfPresent(String.self, forKey: .responseFormat)
        requestStyle = try container.decodeIfPresent(Config.TTSRemoteRequestStyle.self, forKey: .requestStyle)

        if let voiceString = try? container.decodeIfPresent(String.self, forKey: .voice) {
            voice = voiceString
        } else if let voiceObject = try? container.decodeIfPresent(VoiceObject.self, forKey: .voice) {
            voice = voiceObject.id
        } else {
            voice = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(input, forKey: .input)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encodeIfPresent(voice, forKey: .voice)
        try container.encodeIfPresent(instructions, forKey: .instructions)
        try container.encodeIfPresent(responseFormat, forKey: .responseFormat)
        try container.encodeIfPresent(requestStyle, forKey: .requestStyle)
    }

    private struct VoiceObject: Codable {
        let id: String
    }
}

public struct TTSPlaybackSnapshot: Codable, Sendable {
    public let state: TTSPlaybackState
    public let text: String?
    public let source: String?
    public let voiceID: String?
    public let rate: Double
    public let presentationStyle: Config.TTSPresentationStyle
    public let startedAt: Date?
    public let queueLength: Int

    public init(
        state: TTSPlaybackState,
        text: String?,
        source: String?,
        voiceID: String?,
        rate: Double,
        presentationStyle: Config.TTSPresentationStyle,
        startedAt: Date?,
        queueLength: Int = 0
    ) {
        self.state = state
        self.text = text
        self.source = source
        self.voiceID = voiceID
        self.rate = rate
        self.presentationStyle = presentationStyle
        self.startedAt = startedAt
        self.queueLength = queueLength
    }

    public static let idle = TTSPlaybackSnapshot(
        state: .idle,
        text: nil,
        source: nil,
        voiceID: nil,
        rate: 1.0,
        presentationStyle: .standard,
        startedAt: nil,
        queueLength: 0
    )
}

public enum TTSPlaybackError: LocalizedError {
    case emptyText
    case busy
    case playbackFailed
    case unsupportedFormat(String)

    public var errorDescription: String? {
        switch self {
        case .emptyText:
            return "Text to speak is empty."
        case .busy:
            return "Tsutae is already speaking."
        case .playbackFailed:
            return "Tsutae could not start audio playback."
        case .unsupportedFormat(let format):
            return "Tsutae TTS export only supports wav for now. Requested: \(format)."
        }
    }
}

public extension Notification.Name {
    static let tsutaeTTSPlaybackDidChange = Notification.Name("tsutae.ttsPlaybackDidChange")
}

private struct QueuedTTSPlaybackRequest: Sendable {
    let id: UUID
    let text: String
    let source: String
    let voiceID: String?
    let rate: Double
    let presentationStyle: Config.TTSPresentationStyle
    let config: Config.TTSConfig
    let queuedAt: Date
}

public final class TTSPlaybackManager: NSObject, @unchecked Sendable {
    public static let shared = TTSPlaybackManager()

    private let logger = Logger(subsystem: "dev.yanfch.Tsutae", category: "TTSPlayback")
    private let lock = NSLock()
    private let synthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private var snapshotValue = TTSPlaybackSnapshot.idle
    private var activeRequestID: UUID?
    private var activeRequestStartedAt: Date?
    private var activePlaybackStartedAt: Date?
    private var activeEngineID: String?
    private var queuedRequests: [QueuedTTSPlaybackRequest] = []
    private var suppressedAppleCancelCount = 0

    private override init() {
        super.init()
        DispatchQueue.main.async {
            self.synthesizer.delegate = self
        }
    }

    public func snapshot() -> TTSPlaybackSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshotValue
    }

    @discardableResult
    public func speak(_ request: TTSSpeakRequest, config: Config.TTSConfig) async throws -> TTSSpeakResponse {
        let trimmed = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw TTSPlaybackError.emptyText
        }

        let interrupt = request.interrupt ?? config.interruptCurrent
        let selectedVoiceID = selectedVoiceID(requestVoice: request.voice, config: config)
        let selectedRate = request.rate ?? config.rate
        let presentationStyle = request.presentationStyle ?? config.presentationStyle
        let source = request.source?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Tsutae"
        let prepared = QueuedTTSPlaybackRequest(
            id: UUID(),
            text: trimmed,
            source: source,
            voiceID: selectedVoiceID,
            rate: selectedRate,
            presentationStyle: presentationStyle,
            config: config,
            queuedAt: Date()
        )

        let queuedLength: Int? = try onMain {
            if self.isActivelyPlayingOrPending {
                guard interrupt else {
                    guard config.queueWhenBusy else { throw TTSPlaybackError.busy }
                    self.queuedRequests.append(prepared)
                    self.updateSnapshot(self.snapshotValue)
                    self.recordPerf("TTS playback queued. engine=\(config.engine) source=\(source) chars=\(trimmed.count) queue_length=\(self.queuedRequests.count)")
                    return self.queuedRequests.count
                }
                self.stopCurrentPlaybackForReplacement(clearQueue: true)
            }

            self.activate(prepared, startedAt: Date())
            return nil
        }

        if let queuedLength {
            return TTSSpeakResponse(ok: true, state: .queued, source: source, presentationStyle: presentationStyle, queueLength: queuedLength)
        }

        return try await performPlayback(prepared, startedAt: prepared.queuedAt)
    }

    private func performPlayback(_ request: QueuedTTSPlaybackRequest, startedAt: Date) async throws -> TTSSpeakResponse {
        do {
            if request.config.engine == AppleTTSEngine.shared.id {
                let resolvedVoiceID = try onMain {
                    try self.startAppleSpeech(
                        text: request.text,
                        preferredVoiceID: request.voiceID,
                        rate: request.rate,
                        requestID: request.id
                    )
                }
                recordPerf("TTS playback started. engine=apple voice=\(resolvedVoiceID ?? request.voiceID ?? "default") chars=\(request.text.count) startup_elapsed_ms=\(Self.ms(since: startedAt)) queue_length=\(currentQueueLength())")
                return TTSSpeakResponse(ok: true, state: .speaking, source: request.source, presentationStyle: request.presentationStyle, queueLength: currentQueueLength())
            }

            let audio: AudioData
            if request.config.engine == FluidAudioLocalTTSEngine.shared.id {
                audio = try await FluidAudioLocalTTSEngine.shared.synthesize(
                    request.text,
                    voiceID: request.voiceID,
                    rate: request.rate
                )
                recordPerf("TTS local synthesis finished. engine=\(request.config.engine) voice=\(request.voiceID ?? "auto") chars=\(request.text.count) audio_bytes=\(audio.samples.count) container=\(audio.container.rawValue) synth_elapsed_ms=\(Self.ms(since: startedAt)) queue_length=\(currentQueueLength())")
            } else {
                audio = try await OpenAICompatibleRemoteTTSEngine.shared.synthesize(
                    request.text,
                    voiceID: request.voiceID,
                    instructions: request.config.remote.instructions,
                    config: request.config
                )
                recordPerf("TTS remote synthesis finished. engine=\(request.config.engine) protocol=\(request.config.remote.requestStyle.rawValue) model=\(request.config.remote.model ?? "") voice=\(request.voiceID ?? "default") chars=\(request.text.count) audio_bytes=\(audio.samples.count) container=\(audio.container.rawValue) synth_elapsed_ms=\(Self.ms(since: startedAt)) queue_length=\(currentQueueLength())")
            }

            try onMain {
                guard self.activeRequestID == request.id else { return }
                try self.startRemotePlayback(audio: audio, requestID: request.id)
            }
            recordPerf("TTS playback started. engine=\(request.config.engine) total_startup_elapsed_ms=\(Self.ms(since: startedAt)) queue_length=\(currentQueueLength())")
            return TTSSpeakResponse(ok: true, state: .speaking, source: request.source, presentationStyle: request.presentationStyle, queueLength: currentQueueLength())
        } catch {
            recordPerf("TTS playback failed. engine=\(request.config.engine) elapsed_ms=\(Self.ms(since: startedAt)) queue_length=\(currentQueueLength()) error=\(error.localizedDescription)")
            if shouldFallbackToApple(config: request.config) {
                do {
                    let resolvedVoiceID = try onMain {
                        guard self.activeRequestID == request.id else { throw error }
                        self.audioPlayer?.stop()
                        self.audioPlayer = nil
                        self.activeEngineID = AppleTTSEngine.shared.id
                        self.activePlaybackStartedAt = nil
                        return try self.startAppleSpeech(
                            text: request.text,
                            preferredVoiceID: request.voiceID,
                            rate: request.rate,
                            requestID: request.id
                        )
                    }
                    recordPerf("TTS playback fallback started. primary_engine=\(request.config.engine) fallback_engine=apple voice=\(resolvedVoiceID ?? request.voiceID ?? "default") chars=\(request.text.count) startup_elapsed_ms=\(Self.ms(since: startedAt)) queue_length=\(currentQueueLength())")
                    return TTSSpeakResponse(ok: true, state: .speaking, source: request.source, presentationStyle: request.presentationStyle, queueLength: currentQueueLength())
                } catch {
                    recordPerf("TTS playback fallback failed. primary_engine=\(request.config.engine) fallback_engine=apple elapsed_ms=\(Self.ms(since: startedAt)) queue_length=\(currentQueueLength()) error=\(error.localizedDescription)")
                }
            }
            onMain {
                self.finishFailedPlayback(requestID: request.id)
            }
            throw error
        }
    }

    private func shouldFallbackToApple(config: Config.TTSConfig) -> Bool {
        config.engine != AppleTTSEngine.shared.id
            && config.fallbackEngine?.trimmingCharacters(in: .whitespacesAndNewlines) == AppleTTSEngine.shared.id
    }

    public func synthesizeSpeech(_ request: TTSAudioSpeechRequest, config: Config.TTSConfig) async throws -> AudioData {
        let trimmed = request.input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw TTSPlaybackError.emptyText
        }

        let requestedFormat = request.responseFormat?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let requestedFormat, requestedFormat.isEmpty == false, requestedFormat != "wav" {
            throw TTSPlaybackError.unsupportedFormat(requestedFormat)
        }

        let selectedVoiceID = selectedVoiceID(requestVoice: request.voice, config: config)
        var effectiveConfig = config
        let startedAt = Date()

        if effectiveConfig.engine == FluidAudioLocalTTSEngine.shared.id {
            let audio = try await FluidAudioLocalTTSEngine.shared.synthesize(
                trimmed,
                voiceID: selectedVoiceID,
                rate: effectiveConfig.rate
            )
            recordPerf("TTS audio export finished. engine=\(FluidAudioLocalTTSEngine.shared.id) voice=\(selectedVoiceID ?? "auto") chars=\(trimmed.count) audio_bytes=\(audio.samples.count) container=\(audio.container.rawValue) synth_elapsed_ms=\(Self.ms(since: startedAt))")
            return audio
        }

        effectiveConfig.remote.enabled = true
        if let model = request.model?.trimmingCharacters(in: .whitespacesAndNewlines), model.isEmpty == false {
            effectiveConfig.remote.model = model
        }
        if let requestStyle = request.requestStyle {
            effectiveConfig.remote.requestStyle = requestStyle
        }

        let resolvedInstructions = request.instructions?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? effectiveConfig.remote.instructions
        let audio = try await OpenAICompatibleRemoteTTSEngine.shared.synthesize(
            trimmed,
            voiceID: selectedVoiceID,
            instructions: resolvedInstructions,
            config: effectiveConfig
        )
        recordPerf("TTS audio export finished. engine=\(OpenAICompatibleRemoteTTSEngine.shared.id) protocol=\(effectiveConfig.remote.requestStyle.rawValue) model=\(effectiveConfig.remote.model ?? "") voice=\(selectedVoiceID ?? "default") chars=\(trimmed.count) audio_bytes=\(audio.samples.count) container=\(audio.container.rawValue) synth_elapsed_ms=\(Self.ms(since: startedAt))")
        return audio
    }

    private func selectedVoiceID(requestVoice: String?, config: Config.TTSConfig) -> String? {
        if let requestVoice = requestVoice?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            return requestVoice
        }
        if config.engine == OpenAICompatibleRemoteTTSEngine.shared.id {
            return config.remote.voice?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? legacyRemoteVoice(from: config.voice)
        }
        return config.voice?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private func legacyRemoteVoice(from voiceID: String?) -> String? {
        guard let voiceID = voiceID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return nil
        }
        return LocalTTSModelCatalog.isKnownVoiceID(voiceID) ? nil : voiceID
    }

    public func stop() {
        onMain {
            let clearedQueueLength = self.queuedRequests.count
            self.queuedRequests.removeAll()
            if clearedQueueLength > 0 {
                self.recordPerf("TTS playback queue cleared. reason=stop cleared_count=\(clearedQueueLength)")
            }

            guard self.snapshot().state != .idle else {
                self.updateSnapshot(.idle)
                return
            }

            let current = self.snapshot()
            self.updateSnapshot(
                TTSPlaybackSnapshot(
                    state: .stopping,
                    text: current.text,
                    source: current.source,
                    voiceID: current.voiceID,
                    rate: current.rate,
                    presentationStyle: current.presentationStyle,
                    startedAt: current.startedAt
                )
            )

            self.activeRequestID = nil
            if self.audioPlayer?.isPlaying == true {
                self.recordCompletion(reason: "stopped")
                self.audioPlayer?.stop()
                self.audioPlayer = nil
                self.activeRequestStartedAt = nil
                self.activePlaybackStartedAt = nil
                self.activeEngineID = nil
                self.updateSnapshot(.idle)
                return
            }

            if self.synthesizer.isSpeaking {
                self.synthesizer.stopSpeaking(at: .immediate)
                return
            }

            self.updateSnapshot(.idle)
        }
    }

    public var isSpeaking: Bool {
        let state = snapshot().state
        return state == .speaking || state == .stopping
    }

    private var isActivelyPlayingOrPending: Bool {
        activeRequestID != nil || synthesizer.isSpeaking || audioPlayer?.isPlaying == true || snapshotValue.state == .speaking || snapshotValue.state == .stopping
    }

    private func stopCurrentPlaybackForReplacement(clearQueue: Bool) {
        if clearQueue {
            let clearedQueueLength = queuedRequests.count
            queuedRequests.removeAll()
            if clearedQueueLength > 0 {
                recordPerf("TTS playback queue cleared. reason=interrupt cleared_count=\(clearedQueueLength)")
            }
        }

        activeRequestID = nil
        activeRequestStartedAt = nil
        activePlaybackStartedAt = nil
        activeEngineID = nil
        if audioPlayer?.isPlaying == true {
            audioPlayer?.stop()
            audioPlayer = nil
        }
        if synthesizer.isSpeaking {
            suppressedAppleCancelCount += 1
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    private func activate(_ request: QueuedTTSPlaybackRequest, startedAt: Date) {
        activeRequestID = request.id
        activeRequestStartedAt = startedAt
        activePlaybackStartedAt = nil
        activeEngineID = request.config.engine
        updateSnapshot(
            TTSPlaybackSnapshot(
                state: .speaking,
                text: request.text,
                source: request.source,
                voiceID: request.voiceID,
                rate: request.rate,
                presentationStyle: request.presentationStyle,
                startedAt: startedAt
            )
        )
    }

    private func startAppleSpeech(text: String, preferredVoiceID: String?, rate: Double, requestID: UUID) throws -> String? {
        let utterance = AVSpeechUtterance(string: text)
        utterance.volume = 1.0
        utterance.pitchMultiplier = 1.0
        utterance.rate = platformSpeechRate(for: rate)

        let resolvedVoice = resolveVoice(for: text, preferredVoiceID: preferredVoiceID)
        utterance.voice = resolvedVoice
        let current = snapshot()
        updateSnapshot(
            TTSPlaybackSnapshot(
                state: current.state,
                text: current.text,
                source: current.source,
                voiceID: resolvedVoice?.identifier ?? preferredVoiceID,
                rate: current.rate,
                presentationStyle: current.presentationStyle,
                startedAt: current.startedAt
            )
        )
        activeRequestID = requestID
        activePlaybackStartedAt = Date()
        synthesizer.speak(utterance)
        return resolvedVoice?.identifier ?? preferredVoiceID
    }

    private func startRemotePlayback(audio: AudioData, requestID: UUID) throws {
        guard activeRequestID == requestID else { return }
        switch audio.container {
        case .wav, .mp3, .m4a:
            let player = try AVAudioPlayer(data: audio.samples)
            player.delegate = self
            player.prepareToPlay()
            guard player.play() else {
                activePlaybackStartedAt = nil
                throw TTSPlaybackError.playbackFailed
            }
            audioPlayer = player
            activePlaybackStartedAt = Date()
        case .pcm16:
            throw TTSPlaybackError.playbackFailed
        }
    }

    private func finishPlayback(reason: String) {
        recordCompletion(reason: reason)
        audioPlayer = nil
        activeRequestID = nil
        activeRequestStartedAt = nil
        activePlaybackStartedAt = nil
        activeEngineID = nil
        startNextQueuedPlaybackIfAvailable()
    }

    private func finishFailedPlayback(requestID: UUID) {
        guard activeRequestID == requestID else { return }
        audioPlayer?.stop()
        audioPlayer = nil
        activeRequestID = nil
        activeRequestStartedAt = nil
        activePlaybackStartedAt = nil
        activeEngineID = nil
        startNextQueuedPlaybackIfAvailable()
    }

    private func startNextQueuedPlaybackIfAvailable() {
        guard activeRequestID == nil else { return }
        guard queuedRequests.isEmpty == false else {
            updateSnapshot(.idle)
            return
        }

        let next = queuedRequests.removeFirst()
        let startedAt = Date()
        activate(next, startedAt: startedAt)
        recordPerf("TTS queued playback activated. engine=\(next.config.engine) source=\(next.source) chars=\(next.text.count) queued_elapsed_ms=\(Self.ms(since: next.queuedAt)) queue_length=\(queuedRequests.count)")

        Task {
            do {
                _ = try await self.performPlayback(next, startedAt: startedAt)
            } catch {
                self.recordPerf("TTS queued playback failed. engine=\(next.config.engine) source=\(next.source) chars=\(next.text.count) error=\(error.localizedDescription)")
            }
        }
    }

    private func updateSnapshot(_ snapshot: TTSPlaybackSnapshot) {
        let updatedSnapshot = TTSPlaybackSnapshot(
            state: snapshot.state,
            text: snapshot.text,
            source: snapshot.source,
            voiceID: snapshot.voiceID,
            rate: snapshot.rate,
            presentationStyle: snapshot.presentationStyle,
            startedAt: snapshot.startedAt,
            queueLength: queuedRequests.count
        )
        lock.lock()
        snapshotValue = updatedSnapshot
        lock.unlock()
        NotificationCenter.default.post(name: .tsutaeTTSPlaybackDidChange, object: nil)
    }

    private func currentQueueLength() -> Int {
        onMain {
            queuedRequests.count
        }
    }

    private func onMain<T>(_ block: () throws -> T) rethrows -> T {
        if Thread.isMainThread {
            return try block()
        }
        return try DispatchQueue.main.sync(execute: block)
    }

    private func platformSpeechRate(for rate: Double) -> Float {
        let clamped = max(0.5, min(rate, 2.0))
        let base = AVSpeechUtteranceDefaultSpeechRate * Float(clamped)
        return max(AVSpeechUtteranceMinimumSpeechRate, min(base, AVSpeechUtteranceMaximumSpeechRate))
    }

    private func resolveVoice(for text: String, preferredVoiceID: String?) -> AVSpeechSynthesisVoice? {
        let preferredLanguage = preferredLanguageCode(for: text)

        if let preferredVoiceID,
           let preferredVoice = AVSpeechSynthesisVoice(identifier: preferredVoiceID) {
            if isVoice(preferredVoice, compatibleWith: preferredLanguage) {
                return preferredVoice
            }
            logger.info("Falling back from incompatible preferred voice \(preferredVoiceID, privacy: .public) for language \(preferredLanguage, privacy: .public)")
        }

        if let exactVoice = AVSpeechSynthesisVoice(language: preferredLanguage) {
            return exactVoice
        }

        if let prefixVoice = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.language.hasPrefix(languagePrefix(for: preferredLanguage)) }) {
            return prefixVoice
        }

        return nil
    }

    private func preferredLanguageCode(for text: String) -> String {
        if text.containsScalar(where: { (0x4E00...0x9FFF).contains($0.value) }) {
            return "zh-CN"
        }
        if text.containsScalar(where: { (0x3040...0x30FF).contains($0.value) }) {
            return "ja-JP"
        }
        if text.containsScalar(where: { (0xAC00...0xD7AF).contains($0.value) }) {
            return "ko-KR"
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        if let language = recognizer.dominantLanguage {
            switch language {
            case .simplifiedChinese, .traditionalChinese:
                return "zh-CN"
            case .japanese:
                return "ja-JP"
            case .korean:
                return "ko-KR"
            default:
                return "en-US"
            }
        }

        return "en-US"
    }

    private func isVoice(_ voice: AVSpeechSynthesisVoice, compatibleWith languageCode: String) -> Bool {
        voice.language.hasPrefix(languagePrefix(for: languageCode))
    }

    private func languagePrefix(for languageCode: String) -> String {
        languageCode.split(separator: "-").first.map(String.init) ?? languageCode
    }

    private func recordCompletion(reason: String) {
        let total = Self.ms(since: activeRequestStartedAt)
        let playback = Self.ms(since: activePlaybackStartedAt)
        recordPerf("TTS playback finished. engine=\(activeEngineID ?? "unknown") reason=\(reason) playback_elapsed_ms=\(playback) total_elapsed_ms=\(total)")
    }

    private func recordPerf(_ message: String) {
        logger.info("\(message, privacy: .public)")
        PerformanceLog.record(category: "TTSPlayback", message: message)
    }

    private static func ms(since start: Date?) -> String {
        guard let start else { return "0.0" }
        return String(format: "%.1f", Date().timeIntervalSince(start) * 1000)
    }
}

extension TTSPlaybackManager: AVSpeechSynthesizerDelegate {
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onMain {
            finishPlayback(reason: "finished")
        }
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onMain {
            if suppressedAppleCancelCount > 0 {
                suppressedAppleCancelCount -= 1
                recordPerf("TTS Apple cancel suppressed. remaining=\(suppressedAppleCancelCount)")
                return
            }
            finishPlayback(reason: "cancelled")
        }
    }
}

extension TTSPlaybackManager: AVAudioPlayerDelegate {
    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onMain {
            finishPlayback(reason: flag ? "finished" : "failed")
        }
    }

    public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        onMain {
            logger.error("Remote TTS decode error: \(String(describing: error), privacy: .public)")
            recordPerf("TTS playback decode error. engine=\(activeEngineID ?? "unknown") error=\(String(describing: error))")
            finishPlayback(reason: "decode_error")
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    func containsScalar(where predicate: (UnicodeScalar) -> Bool) -> Bool {
        unicodeScalars.contains(where: predicate)
    }
}
