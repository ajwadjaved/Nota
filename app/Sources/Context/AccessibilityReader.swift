import ApplicationServices
import Foundation

/// Attribute names as literals rather than the SDK's `kAX...` globals, which
/// are imported as mutable globals and rejected by Swift 6 strict concurrency.
/// The underlying values are stable and documented.
private enum AX {
    static let focusedUIElement = "AXFocusedUIElement"
    static let focusedWindow = "AXFocusedWindow"
    static let role = "AXRole"
    static let subrole = "AXSubrole"
    static let title = "AXTitle"
    static let value = "AXValue"
    static let selectedText = "AXSelectedText"
    static let placeholder = "AXPlaceholderValue"
    static let help = "AXHelp"
}

enum AccessibilityReader {
    /// Reads the focused control out of the given process.
    ///
    /// Returns `nil` when Accessibility has not been granted, or when the app
    /// simply exposes nothing useful. Callers should treat a `nil` here as
    /// "fall back to OCR", not as an error.
    static func focusedElement(pid: pid_t) -> FocusedElement? {
        let app = AXUIElementCreateApplication(pid)

        guard let focused = element(app, AX.focusedUIElement) else { return nil }

        let result = FocusedElement(
            role: string(focused, AX.role),
            subrole: string(focused, AX.subrole),
            title: string(focused, AX.title),
            value: string(focused, AX.value),
            placeholder: string(focused, AX.placeholder),
            selectedText: string(focused, AX.selectedText),
            help: string(focused, AX.help)
        )

        // An element where nothing at all resolved is noise, not context.
        let isEmpty = [
            result.role, result.subrole, result.title, result.value,
            result.placeholder, result.selectedText, result.help,
        ].allSatisfy { $0 == nil }

        return isEmpty ? nil : result
    }

    static func focusedWindowTitle(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        guard let window = element(app, AX.focusedWindow) else { return nil }
        return string(window, AX.title)
    }

    // MARK: - Attribute plumbing

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return status == .success ? value : nil
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let raw = copy(element, attribute),
              CFGetTypeID(raw) == AXUIElementGetTypeID()
        else { return nil }
        return (raw as! AXUIElement)
    }

    /// AX values arrive as untyped `CFTypeRef`; numbers and booleans are common
    /// for things like stepper and checkbox values, so coerce rather than
    /// insisting on a string.
    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        guard let raw = copy(element, attribute) else { return nil }

        let value: String?
        switch CFGetTypeID(raw) {
        case CFStringGetTypeID():
            value = (raw as! CFString) as String
        case CFNumberGetTypeID():
            value = "\((raw as! CFNumber))"
        case CFBooleanGetTypeID():
            value = CFBooleanGetValue((raw as! CFBoolean)) ? "true" : "false"
        default:
            value = nil
        }

        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
