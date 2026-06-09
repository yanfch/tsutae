import AppKit
import Carbon
import Combine
import Foundation

@MainActor
public final class GlobalHotkeyManager: ObservableObject {
    
    private struct ShortcutDefinition: Sendable {
        let id: String
        let keyCode: UInt32
        let modifiers: UInt32
        let display: String
    }
    
    public static let shared = GlobalHotkeyManager()
    
    private static let hotkeyID: OSType = 0x54535452 // "TSTR"
    private static let hotkeySignature: OSType = 0x54535445 // "TSTE"
    private static let defaultShortcutID = "option+shift+r"
    private static let modifierTokenOrder = ["control", "option", "shift", "command"]
    private static let modifierGlyphs: [String: String] = [
        "control": "⌃",
        "option": "⌥",
        "shift": "⇧",
        "command": "⌘"
    ]
    private static let tokenToKeyCode: [String: UInt32] = {
        var mapping: [String: UInt32] = ["space": UInt32(kVK_Space)]
        let pairs: [(String, Int)] = [
            ("a", kVK_ANSI_A), ("b", kVK_ANSI_B), ("c", kVK_ANSI_C), ("d", kVK_ANSI_D),
            ("e", kVK_ANSI_E), ("f", kVK_ANSI_F), ("g", kVK_ANSI_G), ("h", kVK_ANSI_H),
            ("i", kVK_ANSI_I), ("j", kVK_ANSI_J), ("k", kVK_ANSI_K), ("l", kVK_ANSI_L),
            ("m", kVK_ANSI_M), ("n", kVK_ANSI_N), ("o", kVK_ANSI_O), ("p", kVK_ANSI_P),
            ("q", kVK_ANSI_Q), ("r", kVK_ANSI_R), ("s", kVK_ANSI_S), ("t", kVK_ANSI_T),
            ("u", kVK_ANSI_U), ("v", kVK_ANSI_V), ("w", kVK_ANSI_W), ("x", kVK_ANSI_X),
            ("y", kVK_ANSI_Y), ("z", kVK_ANSI_Z)
        ]
        for (token, code) in pairs {
            mapping[token] = UInt32(code)
        }
        return mapping
    }()
    private static let keyCodeToToken: [UInt16: String] = {
        Dictionary(uniqueKeysWithValues: tokenToKeyCode.map { (UInt16($0.value), $0.key) })
    }()
    
    @Published public private(set) var toggleRecordingShortcutID = defaultShortcutID
    @Published public private(set) var toggleRecordingShortcutDisplay = "⌥⇧R"
    
    private var onToggleRecording: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var isSuspendedForShortcutCapture = false
    private var currentShortcutDefinition: ShortcutDefinition
    
    private init() {
        self.currentShortcutDefinition = Self.shortcutDefinition(for: Self.defaultShortcutID)
            ?? ShortcutDefinition(id: Self.defaultShortcutID, keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(optionKey | shiftKey), display: "⌥⇧R")
        applyConfiguredShortcutID(loadConfiguredShortcutID(), persist: false, registerHotKeyIfPossible: false)
    }
    
    public var toggleRecordingBarShortcutDisplay: String {
        toggleRecordingShortcutDisplay
    }
    
    public var isToggleRecordingShortcutEnabled: Bool {
        hotKeyRef != nil && eventHandlerRef != nil
    }
    
    public var isToggleRecordingBarEnabled: Bool {
        isToggleRecordingShortcutEnabled
    }
    
    public func shortcutID(from event: NSEvent) -> String? {
        Self.shortcutID(from: event)
    }
    
    public func displayString(forShortcutID id: String) -> String {
        Self.shortcutDefinition(for: id)?.display ?? toggleRecordingShortcutDisplay
    }
    
    public func start(onToggleRecordingBar: @escaping () -> Void) {
        self.onToggleRecording = onToggleRecordingBar
        applyConfiguredShortcutID(loadConfiguredShortcutID(), persist: false, registerHotKeyIfPossible: false)
        
        guard eventHandlerRef == nil else {
            registerHotKey()
            return
        }
        
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyReleased)
        )
        
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard
                    let userData,
                    let event
                else {
                    return OSStatus(eventNotHandledErr)
                }
                
                let manager = Unmanaged<GlobalHotkeyManager>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                
                return manager.handleHotKeyEvent(event)
            },
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        
        guard status == noErr else {
            eventHandlerRef = nil
            return
        }
        
        registerHotKey()
    }
    
    public func stop() {
        onToggleRecording = nil
        
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }
    
    public func updateToggleRecordingShortcut(id: String) {
        applyConfiguredShortcutID(id, persist: true, registerHotKeyIfPossible: true)
    }
    
    public func resetToggleRecordingShortcutToDefault() {
        updateToggleRecordingShortcut(id: Self.defaultShortcutID)
    }
    
    public func beginShortcutCapture() {
        isSuspendedForShortcutCapture = true
        unregisterHotKey()
    }
    
    public func endShortcutCapture() {
        isSuspendedForShortcutCapture = false
        registerHotKey()
    }
    
    private func applyConfiguredShortcutID(_ id: String, persist: Bool, registerHotKeyIfPossible: Bool) {
        let definition = Self.shortcutDefinition(for: id)
            ?? Self.shortcutDefinition(for: Self.defaultShortcutID)
            ?? ShortcutDefinition(id: Self.defaultShortcutID, keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(optionKey | shiftKey), display: "⌥⇧R")
        
        currentShortcutDefinition = definition
        toggleRecordingShortcutID = definition.id
        toggleRecordingShortcutDisplay = definition.display
        
        if registerHotKeyIfPossible {
            registerHotKey()
        }
        
        guard persist else { return }
        persistShortcutID(definition.id)
    }
    
    private func registerHotKey() {
        unregisterHotKey()
        
        guard eventHandlerRef != nil, isSuspendedForShortcutCapture == false else {
            return
        }
        
        let hotKeyID = EventHotKeyID(
            signature: Self.hotkeySignature,
            id: UInt32(Self.hotkeyID)
        )
        
        let status = RegisterEventHotKey(
            currentShortcutDefinition.keyCode,
            currentShortcutDefinition.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if status != noErr {
            hotKeyRef = nil
        }
    }
    
    private func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }
    
    private func handleHotKeyEvent(_ event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        
        guard
            status == noErr,
            hotKeyID.signature == Self.hotkeySignature,
            hotKeyID.id == UInt32(Self.hotkeyID)
        else {
            return OSStatus(eventNotHandledErr)
        }
        
        onToggleRecording?()
        return noErr
    }
    
    private func loadConfiguredShortcutID() -> String {
        guard let config = try? HotkeysLoader.load() else {
            return Self.defaultShortcutID
        }
        
        for entry in config.hotkeys {
            if case .predefined(.toggleRecordingBar)? = entry.action {
                return entry.key
            }
        }
        
        return Self.defaultShortcutID
    }
    
    private static func shortcutID(from event: NSEvent) -> String? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var tokens: [String] = []
        if flags.contains(.control) { tokens.append("control") }
        if flags.contains(.option) { tokens.append("option") }
        if flags.contains(.shift) { tokens.append("shift") }
        if flags.contains(.command) { tokens.append("command") }
        guard tokens.isEmpty == false else { return nil }
        guard let keyToken = keyCodeToToken[event.keyCode] else { return nil }
        tokens.append(keyToken)
        return tokens.joined(separator: "+")
    }
    
    private static func shortcutDefinition(for rawID: String) -> ShortcutDefinition? {
        let components = rawID
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { $0.isEmpty == false }
        guard components.isEmpty == false else { return nil }
        
        var modifiers: UInt32 = 0
        var activeModifiers = Set<String>()
        var keyToken: String?
        
        for component in components {
            switch component {
            case "control":
                modifiers |= UInt32(controlKey)
                activeModifiers.insert(component)
            case "option":
                modifiers |= UInt32(optionKey)
                activeModifiers.insert(component)
            case "shift":
                modifiers |= UInt32(shiftKey)
                activeModifiers.insert(component)
            case "command":
                modifiers |= UInt32(cmdKey)
                activeModifiers.insert(component)
            default:
                guard keyToken == nil else { return nil }
                keyToken = component
            }
        }
        
        guard modifiers != 0, let keyToken, let keyCode = tokenToKeyCode[keyToken] else {
            return nil
        }
        
        let orderedModifiers = modifierTokenOrder.filter { activeModifiers.contains($0) }
        let normalizedID = (orderedModifiers + [keyToken]).joined(separator: "+")
        let displayParts = orderedModifiers.compactMap { modifierGlyphs[$0] } + [displayKey(for: keyToken)]
        let display = displayParts.joined()
        return ShortcutDefinition(id: normalizedID, keyCode: keyCode, modifiers: modifiers, display: display)
    }
    
    private static func displayKey(for token: String) -> String {
        switch token {
        case "space":
            return "Space"
        default:
            return token.uppercased()
        }
    }
    
    private func persistShortcutID(_ id: String) {
        var config = (try? HotkeysLoader.load()) ?? .default
        if let index = config.hotkeys.firstIndex(where: { entry in
            if case .predefined(.toggleRecordingBar)? = entry.action {
                return true
            }
            return false
        }) {
            config.hotkeys[index].key = id
        } else {
            config.hotkeys.insert(HotkeyEntry(key: id, action: .predefined(.toggleRecordingBar)), at: 0)
        }
        
        try? HotkeysLoader.save(config)
    }
}
