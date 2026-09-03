import AppKit

/// The floating card in the top-right corner.
///
/// Every flag here exists to keep the panel from behaving like a normal window:
/// it must never take keyboard focus away from whatever the user is actually
/// working in, and it must stay put across Spaces and full-screen apps.
final class OverlayPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
            // `.nonactivatingPanel` is the load-bearing one: without it, showing
            // the panel pulls focus out of Excel and the user loses their cell.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        // Above normal windows but below the menu bar's own drop-downs.
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        // Accessory apps get deactivated constantly; without this the panel
        // would vanish every time focus moved.
        hidesOnDeactivate = false

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        // Clicks pass straight through to the app underneath. Milestone 6 flips
        // this off only while a step is interactive.
        ignoresMouseEvents = true

        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
