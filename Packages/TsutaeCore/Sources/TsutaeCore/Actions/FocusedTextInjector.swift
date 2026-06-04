import AppKit
import Carbon
import Foundation

/// Injects text into the currently focused app by temporarily using pasteboard
/// and sending Command-V.
///
/// Accessibility permission is required for CGEvent keyboard injection.
@MainActor
public enum FocusedTextInjector {
    
    public static func hasAccessibilityPermission(prompt: Bool = false) -> Bool {
        let options = [
            "AXTrustedCheckOptionPrompt": prompt
        ] as CFDictionary
        
        return AXIsProcessTrustedWithOptions(options)
    }
    
    @discardableResult
    public static func requestAccessibilityPermission() -> Bool {
        hasAccessibilityPermission(prompt: true)
    }
    
    public static func inject(_ text: String, restorePasteboard: Bool = false) throws {
        guard hasAccessibilityPermission(prompt: true) else {
            throw FocusedTextInjectorError.accessibilityPermissionDenied
        }
        
        let pasteboard = NSPasteboard.general
        let oldItems = restorePasteboard
            ? pasteboard.pasteboardItems?.compactMap { $0.copy() as? NSPasteboardItem }
            : nil
        
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        sendPasteShortcut()
        
        if let oldItems {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                pasteboard.clearContents()
                pasteboard.writeObjects(oldItems)
            }
        }
    }
    
    private static func sendPasteShortcut() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyCode = CGKeyCode(kVK_ANSI_V)
        
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = CGEventFlags.maskCommand
        keyDown?.post(tap: CGEventTapLocation.cghidEventTap)
        
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = CGEventFlags.maskCommand
        keyUp?.post(tap: CGEventTapLocation.cghidEventTap)
    }
}

public enum FocusedTextInjectorError: LocalizedError, Sendable {
    case accessibilityPermissionDenied
    
    public var errorDescription: String? {
        switch self {
        case .accessibilityPermissionDenied:
            return "Accessibility permission is required to inject text into the focused app"
        }
    }
}
