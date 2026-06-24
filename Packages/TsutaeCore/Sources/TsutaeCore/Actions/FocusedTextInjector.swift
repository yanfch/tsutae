import AppKit
import Carbon
import Foundation

public struct FocusedApplicationSnapshot: Codable, Sendable, Equatable {
    public let localizedName: String?
    public let bundleIdentifier: String?
    public let processIdentifier: Int32

    public init(localizedName: String?, bundleIdentifier: String?, processIdentifier: Int32) {
        self.localizedName = localizedName
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
    }
}

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
        if focusedElementAcceptsTextInput() == false {
            throw FocusedTextInjectorError.focusedElementNotEditable
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

    public static func focusedApplicationSnapshot(excludingBundleIdentifier excludedBundleIdentifier: String? = nil) -> FocusedApplicationSnapshot? {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        if let excludedBundleIdentifier,
           application.bundleIdentifier == excludedBundleIdentifier {
            return nil
        }
        return FocusedApplicationSnapshot(
            localizedName: application.localizedName,
            bundleIdentifier: application.bundleIdentifier,
            processIdentifier: application.processIdentifier
        )
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

    private static func focusedElementAcceptsTextInput() -> Bool? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        let focusedError = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        guard focusedError == .success, let focusedValue else {
            return nil
        }

        let focusedElement = focusedValue as! AXUIElement
        if isAttributeSettable(kAXValueAttribute, on: focusedElement)
            || isAttributeSettable(kAXSelectedTextAttribute, on: focusedElement)
            || isAttributeSettable(kAXSelectedTextRangeAttribute, on: focusedElement) {
            return true
        }

        guard let role = stringAttribute(kAXRoleAttribute, on: focusedElement) else {
            return nil
        }

        if editableRoles.contains(role) {
            return true
        }
        if clearlyNonEditableRoles.contains(role) {
            return false
        }
        return nil
    }

    private static func isAttributeSettable(_ attribute: String, on element: AXUIElement) -> Bool {
        var isSettable = DarwinBoolean(false)
        let error = AXUIElementIsAttributeSettable(element, attribute as CFString, &isSettable)
        return error == .success && isSettable.boolValue
    }

    private static func stringAttribute(_ attribute: String, on element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else { return nil }
        return value as? String
    }

    private static let editableRoles: Set<String> = [
        "AXTextArea",
        "AXTextField",
        "AXComboBox",
        "AXSearchField"
    ]

    private static let clearlyNonEditableRoles: Set<String> = [
        "AXButton",
        "AXCheckBox",
        "AXImage",
        "AXMenuButton",
        "AXPopUpButton",
        "AXRadioButton",
        "AXSlider",
        "AXStaticText"
    ]
}

public enum FocusedTextInjectorError: LocalizedError, Sendable {
    case accessibilityPermissionDenied
    case focusedElementNotEditable
    
    public var errorDescription: String? {
        switch self {
        case .accessibilityPermissionDenied:
            return "Accessibility permission is required to inject text into the focused app"
        case .focusedElementNotEditable:
            return "The focused element does not accept text input"
        }
    }
}
