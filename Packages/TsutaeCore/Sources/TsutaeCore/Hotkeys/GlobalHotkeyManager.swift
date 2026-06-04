import AppKit
import Carbon
import Foundation

@MainActor
public final class GlobalHotkeyManager {
    
    public static let shared = GlobalHotkeyManager()
    
    private static let hotkeyID: OSType = 0x54535452 // "TSTR"
    private static let hotkeySignature: OSType = 0x54535445 // "TSTE"
    private static let hotkeyKeyCode: UInt32 = UInt32(kVK_ANSI_R)
    private static let hotkeyModifiers: UInt32 = UInt32(optionKey | shiftKey)
    
    private var onToggleRecording: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    
    private init() {}
    
    public func start(onToggleRecordingBar: @escaping () -> Void) {
        self.onToggleRecording = onToggleRecordingBar
        
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
    
    public var toggleRecordingShortcutDisplay: String {
        "⌥⇧R"
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
    
    private func registerHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        
        let hotKeyID = EventHotKeyID(
            signature: Self.hotkeySignature,
            id: UInt32(Self.hotkeyID)
        )
        
        let status = RegisterEventHotKey(
            Self.hotkeyKeyCode,
            Self.hotkeyModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if status != noErr {
            hotKeyRef = nil
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
}
