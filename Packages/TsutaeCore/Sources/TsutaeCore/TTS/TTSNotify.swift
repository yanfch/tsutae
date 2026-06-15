import Foundation

public enum TTSNotifyLevel: String, Codable, Sendable {
    case info
    case warning
    case error
}

public enum TTSNotifyDuration: String, Codable, Sendable {
    case short
    case long
}

public enum TTSNotifyClickAction: String, Codable, Sendable {
    case `default`
    case none

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch rawValue {
        case "", "none", "noop", "ignore":
            self = .none
        case "default", "settings", "tsutae":
            self = .default
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported notification click action: \(rawValue)"
            )
        }
    }
}

public enum TTSNotifyUserInfoKey {
    public static let clickAction = "tsutae.notify.click_action"
    public static let openURL = "tsutae.notify.open_url"
    public static let activateBundleID = "tsutae.notify.activate_bundle_id"
}

public struct TTSNotifyRequest: Codable, Sendable {
    public let message: String
    public let title: String?
    public let level: TTSNotifyLevel
    public let voice: String?
    public let duration: TTSNotifyDuration
    public let interruptible: Bool?
    public let fallbackToNotification: Bool
    public let notify: Bool
    public let speak: Bool
    public let sound: Bool?
    public let clickAction: TTSNotifyClickAction?
    public let openURL: String?
    public let activateBundleID: String?

    public init(
        message: String,
        title: String? = nil,
        level: TTSNotifyLevel = .info,
        voice: String? = nil,
        duration: TTSNotifyDuration = .short,
        interruptible: Bool? = nil,
        fallbackToNotification: Bool = true,
        notify: Bool = false,
        speak: Bool = true,
        sound: Bool? = nil,
        clickAction: TTSNotifyClickAction? = nil,
        openURL: String? = nil,
        activateBundleID: String? = nil
    ) {
        self.message = message
        self.title = title
        self.level = level
        self.voice = voice
        self.duration = duration
        self.interruptible = interruptible
        self.fallbackToNotification = fallbackToNotification
        self.notify = notify
        self.speak = speak
        self.sound = sound
        self.clickAction = clickAction
        self.openURL = openURL
        self.activateBundleID = activateBundleID
    }

    enum CodingKeys: String, CodingKey {
        case message, title, level, voice, duration, interruptible, notify, speak, sound
        case clickAction = "click_action"
        case fallbackToNotification = "fallback_to_notification"
        case openURL = "open_url"
        case activateBundleID = "activate_bundle_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decode(String.self, forKey: .message)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        level = try container.decodeIfPresent(TTSNotifyLevel.self, forKey: .level) ?? .info
        voice = try container.decodeIfPresent(String.self, forKey: .voice)
        duration = try container.decodeIfPresent(TTSNotifyDuration.self, forKey: .duration) ?? .short
        interruptible = try container.decodeIfPresent(Bool.self, forKey: .interruptible)
        fallbackToNotification = try container.decodeIfPresent(Bool.self, forKey: .fallbackToNotification) ?? true
        notify = try container.decodeIfPresent(Bool.self, forKey: .notify) ?? false
        speak = try container.decodeIfPresent(Bool.self, forKey: .speak) ?? true
        sound = try container.decodeIfPresent(Bool.self, forKey: .sound)
        clickAction = try container.decodeIfPresent(TTSNotifyClickAction.self, forKey: .clickAction)
        openURL = try container.decodeIfPresent(String.self, forKey: .openURL)
        activateBundleID = try container.decodeIfPresent(String.self, forKey: .activateBundleID)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(message, forKey: .message)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encode(level, forKey: .level)
        try container.encodeIfPresent(voice, forKey: .voice)
        try container.encode(duration, forKey: .duration)
        try container.encodeIfPresent(interruptible, forKey: .interruptible)
        try container.encode(fallbackToNotification, forKey: .fallbackToNotification)
        try container.encode(notify, forKey: .notify)
        try container.encode(speak, forKey: .speak)
        try container.encodeIfPresent(sound, forKey: .sound)
        try container.encodeIfPresent(clickAction, forKey: .clickAction)
        try container.encodeIfPresent(openURL, forKey: .openURL)
        try container.encodeIfPresent(activateBundleID, forKey: .activateBundleID)
    }
}

public struct TTSNotifyResponse: Codable, Sendable {
    public let ok: Bool
    public let spoken: Bool
    public let notificationDelivered: Bool
    public let fallbackUsed: Bool
    public let level: TTSNotifyLevel
    public let state: TTSPlaybackState?
    public let queueLength: Int
    public let error: String?

    public init(
        ok: Bool,
        spoken: Bool,
        notificationDelivered: Bool,
        fallbackUsed: Bool,
        level: TTSNotifyLevel,
        state: TTSPlaybackState?,
        queueLength: Int = 0,
        error: String? = nil
    ) {
        self.ok = ok
        self.spoken = spoken
        self.notificationDelivered = notificationDelivered
        self.fallbackUsed = fallbackUsed
        self.level = level
        self.state = state
        self.queueLength = queueLength
        self.error = error
    }
}

public enum TTSNotifyError: LocalizedError {
    case emptyMessage
    case notificationNotAuthorized
    case deliveryFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyMessage:
            return "Notification message is empty."
        case .notificationNotAuthorized:
            return "Notifications are not authorized for Tsutae."
        case .deliveryFailed(let reason):
            return "Tsutae could not deliver this notification: \(reason)"
        }
    }
}
