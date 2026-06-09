import AVFoundation
import Foundation

public enum TTSPlaybackState: String, Codable, Sendable {
    case idle
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
}

public struct TTSSpeakResponse: Codable, Sendable {
    public let ok: Bool
    public let state: TTSPlaybackState
    public let source: String?

    public init(ok: Bool, state: TTSPlaybackState, source: String?) {
        self.ok = ok
        self.state = state
        self.source = source
    }
}

public struct TTSPlaybackSnapshot: Sendable {
    public let state: TTSPlaybackState
    public let text: String?
    public let source: String?
    public let voiceID: String?
    public let rate: Double
    public let presentationStyle: Config.TTSPresentationStyle
    public let startedAt: Date?

    public static let idle = TTSPlaybackSnapshot(
        state: .idle,
        text: nil,
        source: nil,
        voiceID: nil,
        rate: 1.0,
        presentationStyle: .standard,
        startedAt: nil
    )
}

public enum TTSPlaybackError: LocalizedError {
    case emptyText
    case busy

    public var errorDescription: String? {
        switch self {
        case .emptyText:
            return "Text to speak is empty."
        case .busy:
            return "Tsutae is already speaking."
        }
    }
}

public extension Notification.Name {
    static let tsutaeTTSPlaybackDidChange = Notification.Name("tsutae.ttsPlaybackDidChange")
}

public final class TTSPlaybackManager: NSObject, @unchecked Sendable {
    public static let shared = TTSPlaybackManager()

    private let lock = NSLock()
    private let synthesizer = AVSpeechSynthesizer()
    private var snapshotValue = TTSPlaybackSnapshot.idle

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
    public func speak(_ request: TTSSpeakRequest, config: Config.TTSConfig) throws -> TTSSpeakResponse {
        let trimmed = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw TTSPlaybackError.emptyText
        }

        let interrupt = request.interrupt ?? config.interruptCurrent
        let selectedVoiceID = request.voice ?? config.voice
        let selectedRate = request.rate ?? config.rate
        let presentationStyle = request.presentationStyle ?? config.presentationStyle
        let source = request.source?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Tsutae"

        try onMain {
            if self.synthesizer.isSpeaking {
                guard interrupt else { throw TTSPlaybackError.busy }
                self.synthesizer.stopSpeaking(at: .immediate)
            }

            let utterance = AVSpeechUtterance(string: trimmed)
            utterance.volume = 1.0
            utterance.pitchMultiplier = 1.0
            utterance.rate = self.platformSpeechRate(for: selectedRate)

            if let selectedVoiceID,
               let voice = AVSpeechSynthesisVoice(identifier: selectedVoiceID) {
                utterance.voice = voice
            }

            self.updateSnapshot(
                TTSPlaybackSnapshot(
                    state: .speaking,
                    text: trimmed,
                    source: source,
                    voiceID: selectedVoiceID,
                    rate: selectedRate,
                    presentationStyle: presentationStyle,
                    startedAt: Date()
                )
            )
            self.synthesizer.speak(utterance)
        }

        return TTSSpeakResponse(ok: true, state: .speaking, source: source)
    }

    public func stop() {
        onMain {
            guard self.synthesizer.isSpeaking else {
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
            self.synthesizer.stopSpeaking(at: .immediate)
        }
    }

    public var isSpeaking: Bool {
        let state = snapshot().state
        return state == .speaking || state == .stopping
    }

    private func updateSnapshot(_ snapshot: TTSPlaybackSnapshot) {
        lock.lock()
        snapshotValue = snapshot
        lock.unlock()
        NotificationCenter.default.post(name: .tsutaeTTSPlaybackDidChange, object: nil)
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
}

extension TTSPlaybackManager: AVSpeechSynthesizerDelegate {
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        updateSnapshot(.idle)
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        updateSnapshot(.idle)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
