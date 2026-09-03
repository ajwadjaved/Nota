import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlay: OverlayController?
    private var menuBar: MenuBarController?
    private var inspector: InspectorWindowController?
    private let context = ContextCoordinator()
    private let hotkeys = HotkeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let overlay = OverlayController()
        self.overlay = overlay

        let inspector = InspectorWindowController(coordinator: context)
        self.inspector = inspector

        menuBar = MenuBarController(
            onToggleOverlay: { overlay.toggle() },
            onRequestPermissions: { Task { await PermissionsManager.shared.requestAll() } },
            onShowInspector: { inspector.show() }
        )

        context.start()

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
        context.stop()
    }
}
