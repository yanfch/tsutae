import AppKit
import Carbon
import Combine
import Foundation

public enum RecordingShortcutMode: String, CaseIterable, Sendable {
    case keyboardShortcut
    case doubleTapModifier
    case pressAndHoldModifier
}

public enum RecordingShortcutModifier: String, CaseIterable, Sendable {
    case control
    case option
    case shift
    case command

    public var glyph: String {
        switch self {
        case .control: return "⌃"
        case .option: return "⌥"
        case .shift: return "⇧"
        case .command: return "⌘"
        }
    }

    public var displayName: String {
        switch self {
        case .control: return "Control"
        case .option: return "Option"
        case .shift: return "Shift"
        case .command: return "Command"
        }
    }

    fileprivate var eventFlag: NSEvent.ModifierFlags {
        switch self {
        case .control: return .control
        case .option: return .option
        case .shift: return .shift
        case .command: return .command
        }
    }

    fileprivate var carbonFlag: UInt32 {
        switch self {
        case .control: return UInt32(controlKey)
        case .option: return UInt32(optionKey)
        case .shift: return UInt32(shiftKey)
        case .command: return UInt32(cmdKey)
        }
    }

    fileprivate var keyCodes: Set<UInt16> {
        switch self {
        case .control:
            return [UInt16(kVK_Control), UInt16(kVK_RightControl)]
        case .option:
            return [UInt16(kVK_Option), UInt16(kVK_RightOption)]
        case .shift:
            return [UInt16(kVK_Shift), UInt16(kVK_RightShift)]
        case .command:
            return [UInt16(kVK_Command), UInt16(kVK_RightCommand)]
        }
    }

    fileprivate func matches(keyCode: UInt16) -> Bool {
        keyCodes.contains(keyCode)
    }
}

fileprivate struct RecordingShortcutDefinition: Sendable {
    let id: String
    let mode: RecordingShortcutMode
    let keyCode: UInt32?
    let modifiers: UInt32?
    let modifierKey: RecordingShortcutModifier?
    let display: String
}

public enum RecordingShortcut {
    public static let defaultKeyboardShortcutID = "option+shift+r"
    public static let defaultShortcutID = "double+option"
    public static let defaultModifier: RecordingShortcutModifier = .option

    private static let doubleTapPrefix = "double"
    private static let holdPrefix = "hold"
    private static let modifierTokenOrder: [RecordingShortcutModifier] = [.control, .option, .shift, .command]
    private static let modifierFlagMask: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

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

    public static func normalizedID(for rawID: String) -> String? {
        definition(for: rawID)?.id
    }

    public static func displayString(forShortcutID id: String) -> String {
        definition(for: id)?.display ?? definition(for: defaultShortcutID)?.display ?? "⌥⇧R"
    }

    public static func mode(forShortcutID id: String) -> RecordingShortcutMode {
        definition(for: id)?.mode ?? .keyboardShortcut
    }

    public static func modifier(forShortcutID id: String) -> RecordingShortcutModifier? {
        definition(for: id)?.modifierKey
    }

    public static func keyboardShortcutID(forShortcutID id: String) -> String? {
        guard let definition = definition(for: id), definition.mode == .keyboardShortcut else {
            return nil
        }
        return definition.id
    }

    public static func id(
        mode: RecordingShortcutMode,
        keyboardShortcutID: String = defaultKeyboardShortcutID,
        modifier: RecordingShortcutModifier = defaultModifier
    ) -> String {
        switch mode {
        case .keyboardShortcut:
            guard let definition = definition(for: keyboardShortcutID), definition.mode == .keyboardShortcut else {
                return defaultKeyboardShortcutID
            }
            return definition.id
        case .doubleTapModifier:
            return "\(doubleTapPrefix)+\(modifier.rawValue)"
        case .pressAndHoldModifier:
            return "\(holdPrefix)+\(modifier.rawValue)"
        }
    }

    fileprivate static func definition(for rawID: String) -> RecordingShortcutDefinition? {
        let components = shortcutComponents(from: rawID)
        guard components.isEmpty == false else { return nil }

        if components.count == 2,
           let mode = specialMode(from: components[0]),
           let modifier = RecordingShortcutModifier(rawValue: components[1]) {
            let prefix = mode == .doubleTapModifier ? doubleTapPrefix : holdPrefix
            let displayPrefix = mode == .doubleTapModifier ? "Double" : "Hold"
            return RecordingShortcutDefinition(
                id: "\(prefix)+\(modifier.rawValue)",
                mode: mode,
                keyCode: nil,
                modifiers: nil,
                modifierKey: modifier,
                display: "\(displayPrefix) \(modifier.glyph)"
            )
        }

        var modifiers: UInt32 = 0
        var activeModifiers = Set<RecordingShortcutModifier>()
        var keyToken: String?

        for component in components {
            if let modifier = RecordingShortcutModifier(rawValue: component) {
                modifiers |= modifier.carbonFlag
                activeModifiers.insert(modifier)
            } else {
                guard keyToken == nil else { return nil }
                keyToken = component
            }
        }

        guard modifiers != 0, let keyToken, let keyCode = tokenToKeyCode[keyToken] else {
            return nil
        }

        let orderedModifiers = modifierTokenOrder.filter { activeModifiers.contains($0) }
        let normalizedID = (orderedModifiers.map(\.rawValue) + [keyToken]).joined(separator: "+")
        let display = (orderedModifiers.map(\.glyph) + [displayKey(for: keyToken)]).joined()
        return RecordingShortcutDefinition(
            id: normalizedID,
            mode: .keyboardShortcut,
            keyCode: keyCode,
            modifiers: modifiers,
            modifierKey: nil,
            display: display
        )
    }

    fileprivate static func keyboardShortcutID(from event: NSEvent) -> String? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var tokens: [String] = []
        if flags.contains(.control) { tokens.append(RecordingShortcutModifier.control.rawValue) }
        if flags.contains(.option) { tokens.append(RecordingShortcutModifier.option.rawValue) }
        if flags.contains(.shift) { tokens.append(RecordingShortcutModifier.shift.rawValue) }
        if flags.contains(.command) { tokens.append(RecordingShortcutModifier.command.rawValue) }
        guard tokens.isEmpty == false else { return nil }
        guard let keyToken = keyCodeToToken[event.keyCode] else { return nil }
        tokens.append(keyToken)
        return tokens.joined(separator: "+")
    }

    fileprivate static func containsOnlySelectedModifierOrNoModifier(
        _ flags: NSEvent.ModifierFlags,
        modifier: RecordingShortcutModifier
    ) -> Bool {
        let relevantFlags = flags.intersection(modifierFlagMask)
        return relevantFlags.isEmpty || relevantFlags == modifier.eventFlag
    }

    private static func shortcutComponents(from rawID: String) -> [String] {
        let components = rawID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split { character in
                character == "+" || character == "_" || character == "-" || character.isWhitespace
            }
            .map(String.init)
            .filter { $0.isEmpty == false }

        guard components.count == 1, let compact = components.first else {
            return components
        }

        let compactSpecialPrefixes: [(String, String)] = [
            ("doubletapmodifier", doubleTapPrefix),
            ("doubletap", doubleTapPrefix),
            ("double", doubleTapPrefix),
            ("pressandholdmodifier", holdPrefix),
            ("pressandhold", holdPrefix),
            ("presshold", holdPrefix),
            ("hold", holdPrefix),
        ]

        for (compactPrefix, canonicalPrefix) in compactSpecialPrefixes {
            guard compact.hasPrefix(compactPrefix) else { continue }
            let suffix = String(compact.dropFirst(compactPrefix.count))
            if RecordingShortcutModifier(rawValue: suffix) != nil {
                return [canonicalPrefix, suffix]
            }
        }

        return components
    }

    private static func specialMode(from token: String) -> RecordingShortcutMode? {
        switch token {
        case "double", "doubletap", "doubletapmodifier":
            return .doubleTapModifier
        case "hold", "presshold", "pressandhold", "pressandholdmodifier":
            return .pressAndHoldModifier
        default:
            return nil
        }
    }

    private static func displayKey(for token: String) -> String {
        switch token {
        case "space": return "Space"
        default: return token.uppercased()
        }
    }
}

@MainActor
public final class GlobalHotkeyManager: ObservableObject {

    public static let shared = GlobalHotkeyManager()

    private enum MonitoredEventKind: Sendable {
        case flagsChanged
        case keyDown
    }

    private static let hotkeyID: OSType = 0x54535452 // "TSTR"
    private static let hotkeySignature: OSType = 0x54535445 // "TSTE"
    private static let doubleTapInterval: TimeInterval = 0.36
    private static let maxModifierTapDuration: TimeInterval = 0.32
    private static let holdStartDelay: TimeInterval = 0.18

    @Published public private(set) var toggleRecordingShortcutID = RecordingShortcut.defaultShortcutID
    @Published public private(set) var toggleRecordingShortcutDisplay = RecordingShortcut.displayString(forShortcutID: RecordingShortcut.defaultShortcutID)

    private var onToggleRecording: (() -> Void)?
    private var onHoldRecordingStart: (() -> Void)?
    private var onHoldRecordingStop: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var localModifierMonitor: Any?
    private var globalModifierMonitor: Any?
    private var isSuspendedForShortcutCapture = false
    private var currentShortcutDefinition: RecordingShortcutDefinition

    private var selectedModifierIsDown = false
    private var modifierDownStartedAt: TimeInterval?
    private var lastModifierTapEndedAt: TimeInterval?
    private var modifierGestureInterrupted = false
    private var ignoreCurrentModifierRelease = false
    private var pendingHoldWorkItem: DispatchWorkItem?
    private var holdGestureActive = false

    private init() {
        self.currentShortcutDefinition = RecordingShortcut.definition(for: RecordingShortcut.defaultShortcutID)
            ?? RecordingShortcutDefinition(
                id: RecordingShortcut.defaultShortcutID,
                mode: .keyboardShortcut,
                keyCode: UInt32(kVK_ANSI_R),
                modifiers: UInt32(optionKey | shiftKey),
                modifierKey: nil,
                display: "⌥⇧R"
            )
        applyConfiguredShortcutID(loadConfiguredShortcutID(), persist: false, registerHotKeyIfPossible: false)
    }

    public var toggleRecordingBarShortcutDisplay: String {
        toggleRecordingShortcutDisplay
    }

    public var isToggleRecordingShortcutEnabled: Bool {
        switch currentShortcutDefinition.mode {
        case .keyboardShortcut:
            return hotKeyRef != nil && eventHandlerRef != nil
        case .doubleTapModifier, .pressAndHoldModifier:
            return localModifierMonitor != nil || globalModifierMonitor != nil
        }
    }

    public var isToggleRecordingBarEnabled: Bool {
        isToggleRecordingShortcutEnabled
    }

    public func shortcutID(from event: NSEvent) -> String? {
        RecordingShortcut.keyboardShortcutID(from: event)
    }

    public func displayString(forShortcutID id: String) -> String {
        RecordingShortcut.displayString(forShortcutID: id)
    }

    public func start(
        onToggleRecordingBar: @escaping () -> Void,
        onHoldRecordingStart: (() -> Void)? = nil,
        onHoldRecordingStop: (() -> Void)? = nil
    ) {
        self.onToggleRecording = onToggleRecordingBar
        self.onHoldRecordingStart = onHoldRecordingStart
        self.onHoldRecordingStop = onHoldRecordingStop
        PerformanceLog.record(category: "Hotkey", message: "Global hotkey manager starting")
        applyConfiguredShortcutID(loadConfiguredShortcutID(), persist: false, registerHotKeyIfPossible: false)

        if eventHandlerRef == nil {
            installCarbonEventHandler()
        }

        registerHotKey()
    }

    public func stop() {
        onToggleRecording = nil
        onHoldRecordingStart = nil
        onHoldRecordingStop = nil

        unregisterHotKey()
        removeModifierMonitors(notifyHoldStop: false)

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    public func updateToggleRecordingShortcut(id: String) {
        applyConfiguredShortcutID(id, persist: true, registerHotKeyIfPossible: true)
    }

    public func updateToggleRecordingShortcut(
        mode: RecordingShortcutMode,
        keyboardShortcutID: String = RecordingShortcut.defaultKeyboardShortcutID,
        modifier: RecordingShortcutModifier = RecordingShortcut.defaultModifier
    ) {
        updateToggleRecordingShortcut(id: RecordingShortcut.id(mode: mode, keyboardShortcutID: keyboardShortcutID, modifier: modifier))
    }

    public func resetToggleRecordingShortcutToDefault() {
        updateToggleRecordingShortcut(id: RecordingShortcut.defaultShortcutID)
    }

    public func beginShortcutCapture() {
        isSuspendedForShortcutCapture = true
        unregisterHotKey()
        removeModifierMonitors(notifyHoldStop: true)
    }

    public func endShortcutCapture() {
        isSuspendedForShortcutCapture = false
        registerHotKey()
    }

    private func installCarbonEventHandler() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyReleased)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData, let event else {
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
            PerformanceLog.record(category: "Hotkey", message: "Global hotkey event handler install failed. status=\(status)")
            return
        }
    }

    private func applyConfiguredShortcutID(_ id: String, persist: Bool, registerHotKeyIfPossible: Bool) {
        let definition = RecordingShortcut.definition(for: id)
            ?? RecordingShortcut.definition(for: RecordingShortcut.defaultShortcutID)
            ?? RecordingShortcutDefinition(
                id: RecordingShortcut.defaultShortcutID,
                mode: .keyboardShortcut,
                keyCode: UInt32(kVK_ANSI_R),
                modifiers: UInt32(optionKey | shiftKey),
                modifierKey: nil,
                display: "⌥⇧R"
            )

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
        removeModifierMonitors(notifyHoldStop: true)

        guard isSuspendedForShortcutCapture == false else {
            return
        }

        switch currentShortcutDefinition.mode {
        case .keyboardShortcut:
            registerKeyboardShortcutHotKey()
        case .doubleTapModifier, .pressAndHoldModifier:
            installModifierMonitors()
        }
    }

    private func registerKeyboardShortcutHotKey() {
        guard eventHandlerRef != nil,
              let keyCode = currentShortcutDefinition.keyCode,
              let modifiers = currentShortcutDefinition.modifiers else {
            return
        }

        let hotKeyID = EventHotKeyID(
            signature: Self.hotkeySignature,
            id: UInt32(Self.hotkeyID)
        )

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            hotKeyRef = nil
            PerformanceLog.record(category: "Hotkey", message: "Global hotkey registration failed. shortcut=\(currentShortcutDefinition.id) status=\(status)")
        } else {
            PerformanceLog.record(category: "Hotkey", message: "Global hotkey registered. shortcut=\(currentShortcutDefinition.id)")
        }
    }

    private func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installModifierMonitors() {
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]

        localModifierMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            let kind: MonitoredEventKind? = switch event.type {
            case .flagsChanged: .flagsChanged
            case .keyDown: .keyDown
            default: nil
            }
            let keyCode = event.keyCode
            let modifierFlagsRawValue = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
            Task { @MainActor [weak self] in
                guard let kind else { return }
                self?.handleMonitoredEvent(kind: kind, keyCode: keyCode, modifierFlagsRawValue: modifierFlagsRawValue)
            }
            return event
        }

        globalModifierMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            let kind: MonitoredEventKind? = switch event.type {
            case .flagsChanged: .flagsChanged
            case .keyDown: .keyDown
            default: nil
            }
            let keyCode = event.keyCode
            let modifierFlagsRawValue = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
            Task { @MainActor [weak self] in
                guard let kind else { return }
                self?.handleMonitoredEvent(kind: kind, keyCode: keyCode, modifierFlagsRawValue: modifierFlagsRawValue)
            }
        }

        PerformanceLog.record(category: "Hotkey", message: "Modifier hotkey monitor installed. shortcut=\(currentShortcutDefinition.id)")
    }

    private func removeModifierMonitors(notifyHoldStop: Bool) {
        if let localModifierMonitor {
            NSEvent.removeMonitor(localModifierMonitor)
            self.localModifierMonitor = nil
        }

        if let globalModifierMonitor {
            NSEvent.removeMonitor(globalModifierMonitor)
            self.globalModifierMonitor = nil
        }

        resetModifierGestureState(notifyHoldStop: notifyHoldStop)
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

    private func handleMonitoredEvent(
        kind: MonitoredEventKind,
        keyCode: UInt16,
        modifierFlagsRawValue: UInt
    ) {
        guard isSuspendedForShortcutCapture == false else { return }
        guard let modifier = currentShortcutDefinition.modifierKey else { return }
        let flags = NSEvent.ModifierFlags(rawValue: modifierFlagsRawValue).intersection(.deviceIndependentFlagsMask)

        switch kind {
        case .keyDown:
            handleNonModifierKeyDownWhileTrackingModifier()
        case .flagsChanged:
            guard modifier.matches(keyCode: keyCode) else {
                return
            }
            let isDown = flags.contains(modifier.eventFlag)
            switch currentShortcutDefinition.mode {
            case .keyboardShortcut:
                return
            case .doubleTapModifier:
                handleDoubleTapModifierEvent(modifier: modifier, isDown: isDown, flags: flags)
            case .pressAndHoldModifier:
                handlePressAndHoldModifierEvent(modifier: modifier, isDown: isDown, flags: flags)
            }
        }
    }

    private func handleNonModifierKeyDownWhileTrackingModifier() {
        modifierGestureInterrupted = true
        lastModifierTapEndedAt = nil

        if currentShortcutDefinition.mode == .pressAndHoldModifier, holdGestureActive == false {
            pendingHoldWorkItem?.cancel()
            pendingHoldWorkItem = nil
        }
    }

    private func handleDoubleTapModifierEvent(
        modifier: RecordingShortcutModifier,
        isDown: Bool,
        flags: NSEvent.ModifierFlags
    ) {
        let now = Date().timeIntervalSinceReferenceDate

        if isDown {
            guard selectedModifierIsDown == false else { return }
            selectedModifierIsDown = true

            guard RecordingShortcut.containsOnlySelectedModifierOrNoModifier(flags, modifier: modifier) else {
                resetModifierGestureState(notifyHoldStop: false)
                return
            }

            if let lastModifierTapEndedAt,
               now - lastModifierTapEndedAt <= Self.doubleTapInterval {
                ignoreCurrentModifierRelease = true
                self.lastModifierTapEndedAt = nil
                modifierDownStartedAt = now
                modifierGestureInterrupted = true
                onToggleRecording?()
                return
            }

            modifierDownStartedAt = now
            modifierGestureInterrupted = false
            ignoreCurrentModifierRelease = false
            return
        }

        guard selectedModifierIsDown else { return }
        selectedModifierIsDown = false
        defer {
            modifierDownStartedAt = nil
            ignoreCurrentModifierRelease = false
        }

        guard ignoreCurrentModifierRelease == false,
              let modifierDownStartedAt,
              now - modifierDownStartedAt <= Self.maxModifierTapDuration,
              modifierGestureInterrupted == false,
              RecordingShortcut.containsOnlySelectedModifierOrNoModifier(flags, modifier: modifier) else {
            lastModifierTapEndedAt = nil
            return
        }

        lastModifierTapEndedAt = now
    }

    private func handlePressAndHoldModifierEvent(
        modifier: RecordingShortcutModifier,
        isDown: Bool,
        flags: NSEvent.ModifierFlags
    ) {
        if isDown {
            guard selectedModifierIsDown == false else { return }
            selectedModifierIsDown = true

            guard RecordingShortcut.containsOnlySelectedModifierOrNoModifier(flags, modifier: modifier) else {
                resetModifierGestureState(notifyHoldStop: true)
                return
            }

            modifierGestureInterrupted = false
            scheduleHoldStartIfNeeded()
            return
        }

        guard selectedModifierIsDown else { return }
        selectedModifierIsDown = false
        pendingHoldWorkItem?.cancel()
        pendingHoldWorkItem = nil

        if holdGestureActive {
            holdGestureActive = false
            onHoldRecordingStop?()
        }

        modifierGestureInterrupted = false
    }

    private func scheduleHoldStartIfNeeded() {
        pendingHoldWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.fireHoldStartIfStillValid()
            }
        }
        pendingHoldWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdStartDelay, execute: workItem)
    }

    private func fireHoldStartIfStillValid() {
        pendingHoldWorkItem = nil
        guard currentShortcutDefinition.mode == .pressAndHoldModifier else { return }
        guard selectedModifierIsDown, modifierGestureInterrupted == false, holdGestureActive == false else { return }
        holdGestureActive = true
        onHoldRecordingStart?()
    }

    private func resetModifierGestureState(notifyHoldStop: Bool) {
        pendingHoldWorkItem?.cancel()
        pendingHoldWorkItem = nil
        selectedModifierIsDown = false
        modifierDownStartedAt = nil
        lastModifierTapEndedAt = nil
        modifierGestureInterrupted = false
        ignoreCurrentModifierRelease = false

        if holdGestureActive {
            holdGestureActive = false
            if notifyHoldStop {
                onHoldRecordingStop?()
            }
        }
    }

    private func loadConfiguredShortcutID() -> String {
        guard let config = try? HotkeysLoader.load() else {
            return RecordingShortcut.defaultShortcutID
        }

        for entry in config.hotkeys {
            if case .predefined(.toggleRecordingBar)? = entry.action {
                return entry.key
            }
        }

        return RecordingShortcut.defaultShortcutID
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
