import AppKit
import Carbon.HIToolbox
import os

private let log = Logger(subsystem: "dev.nota.Nota", category: "lifecycle")

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

        let permissions = PermissionsManager.shared
        permissions.refresh()

        // Re-signing the app invalidates its TCC grants, so a build that was
        // working yesterday can come up mute today. Without Accessibility the
        // readers return nothing and the overlay just sits on its placeholder,
        // which looks identical to a screen with no problem on it.
        log.notice(
            """
            permissions: screen recording \(permissions.hasScreenRecording, privacy: .public), \
            accessibility \(permissions.hasAccessibility, privacy: .public), \
            microphone \(permissions.hasMicrophone, privacy: .public)
            """
        )

        // Tier 3 absence is silent by design; say so once at launch so a
        // degraded run is visible without reading the cards and guessing.
        let provider = TieredGuidanceProvider()
        Task {
            let reachable = await provider.writerIsReachable()
            log.notice("sidecar reachable: \(reachable, privacy: .public)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeys.unregister()
        context.stop()
        engine?.stop()
    }
}
