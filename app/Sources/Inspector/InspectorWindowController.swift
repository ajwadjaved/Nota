import AppKit
import SwiftUI

@MainActor
final class InspectorWindowController {
    private var window: NSWindow?
    private let coordinator: ContextCoordinator

    init(coordinator: ContextCoordinator) {
        self.coordinator = coordinator
    }

    func show() {
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 460),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Context Inspector"
        window.contentView = NSHostingView(
            rootView: ContextInspectorView(coordinator: coordinator)
        )
        window.isReleasedWhenClosed = false
        window.center()

        self.window = window

        // An accessory app has to activate explicitly, or the window opens
        // behind whatever the user is looking at.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
