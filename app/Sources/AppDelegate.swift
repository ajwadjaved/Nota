import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlay: OverlayController?
    private var menuBar: MenuBarController?
    private var inspector: InspectorWindowController?
    private var engine: GuidanceEngine?
    private let context = ContextCoordinator()
    private let hotkeys = HotkeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let overlay = OverlayController()
        self.overlay = overlay

        let engine = GuidanceEngine(
            provider: TieredGuidanceProvider(),
            present: { overlay.show(guidance: $0) },
            dismiss: { overlay.clear() }
        )
        self.engine = engine

        let inspector = InspectorWindowController(coordinator: context, engine: engine)
        self.inspector = inspector

        menuBar = MenuBarController(
            engine: engine,
            onToggleOverlay: { overlay.toggle() },
            onRequestPermissions: { Task { await PermissionsManager.shared.requestAll() } },
            onShowInspector: { inspector.show() }
        )

        context.onRead = { [weak engine] in engine?.handle($0) }
        context.start()

        hotkeys.register(
            keyCode: UInt32(kVK_ANSI_K),
            modifiers: UInt32(cmdKey | optionKey)
        ) {
            overlay.toggle()
        }

        PermissionsManager.shared.refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeys.unregister()
        context.stop()
        engine?.stop()
    }
}
