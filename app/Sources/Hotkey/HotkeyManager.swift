import AppKit
import Carbon.HIToolbox

/// System-wide hotkeys via Carbon's `RegisterEventHotKey`.
///
/// `NSEvent.addGlobalMonitorForEvents` would be less code but has two problems:
/// it needs Accessibility permission before it works at all, and it observes
/// rather than consumes the keystroke, so the shortcut would also reach the app
/// underneath. Carbon hotkeys have neither issue.
final class HotkeyManager: @unchecked Sendable {
    private struct Registration {
        let ref: EventHotKeyRef
        let action: @MainActor () -> Void
    }

    /// Carbon delivers the `EventHotKeyID` with the event, so one handler can
    /// serve every shortcut and the id is what tells them apart.
    private var registrations: [UInt32: Registration] = [:]
    private var eventHandler: EventHandlerRef?
    private var nextID: UInt32 = 1

    private static let signature: OSType = 0x4B52_4B4F  // 'KRKO'

    func register(
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping @MainActor () -> Void
    ) {
        installHandlerIfNeeded()

        let id = nextID
        nextID += 1

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(),
            0,
            &ref
        )

        // Another app already owns the combination. Nothing to be done about it
        // from here, and it must not take the other shortcuts down with it.
        guard status == noErr, let ref else { return }

        registrations[id] = Registration(ref: ref, action: action)
    }

    func unregister() {
        for registration in registrations.values {
            UnregisterEventHotKey(registration.ref)
        }
        registrations.removeAll()

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let context = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            // Captures nothing, so it converts to a C function pointer. State
            // arrives through `userData` instead.
            { _, event, userData in
                guard let userData, let event else {
                    return OSStatus(eventNotHandledErr)
                }

                var id = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &id
                )
                guard status == noErr else { return OSStatus(eventNotHandledErr) }

                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData)
                    .takeUnretainedValue()
                // Carbon delivers hot-key events on the main thread.
                MainActor.assumeIsolated {
                    manager.registrations[id.id]?.action()
                }
                return noErr
            },
            1,
            &spec,
            context,
            &eventHandler
        )
    }
}
