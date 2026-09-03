import AppKit
import Carbon.HIToolbox

/// System-wide hotkey via Carbon's `RegisterEventHotKey`.
///
/// `NSEvent.addGlobalMonitorForEvents` would be less code but has two problems:
/// it needs Accessibility permission before it works at all, and it observes
/// rather than consumes the keystroke, so the shortcut would also reach the app
/// underneath. Carbon hotkeys have neither issue.
final class HotkeyManager: @unchecked Sendable {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var action: (@MainActor () -> Void)?

    private static let signature: OSType = 0x4B52_4B4F  // 'KRKO'
    private static let identifier: UInt32 = 1

    func register(
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping @MainActor () -> Void
    ) {
        unregister()
        self.action = action

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let context = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            // Captures nothing, so it converts to a C function pointer. State
            // arrives through `userData` instead.
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData)
                    .takeUnretainedValue()
                // Carbon delivers hot-key events on the main thread.
                MainActor.assumeIsolated {
                    manager.action?()
                }
                return noErr
            },
            1,
            &spec,
            context,
            &eventHandler
        )

        let id = EventHotKeyID(signature: Self.signature, id: Self.identifier)
        RegisterEventHotKey(
            keyCode,
            modifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        action = nil
    }
}
