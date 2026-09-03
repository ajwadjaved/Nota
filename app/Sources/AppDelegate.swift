import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlay: OverlayController?
    private var menuBar: MenuBarController?
    private let hotkeys = HotkeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let overlay = OverlayController()
        self.overlay = overlay

        menuBar = MenuBarController(
            onToggleOverlay: { overlay.toggle() },
            onRequestPermissions: { Task { await PermissionsManager.shared.requestAll() } }
        )

        hotkeys.register(
            keyCode: UInt32(kVK_ANSI_K),
            modifiers: UInt32(cmdKey | optionKey)
        ) {
            overlay.toggle()
        }

        PermissionsManager.shared.refresh()

        // M1 placeholder. Milestone 3 replaces this with output from the model.
        overlay.show(guidance: .demo)
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeys.unregister()
    }
}
