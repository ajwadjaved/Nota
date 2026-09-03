import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let onToggleOverlay: () -> Void
    private let onRequestPermissions: () -> Void

    init(
        onToggleOverlay: @escaping () -> Void,
        onRequestPermissions: @escaping () -> Void
    ) {
        self.onToggleOverlay = onToggleOverlay
        self.onRequestPermissions = onRequestPermissions
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        super.init()

        statusItem.button?.image = NSImage(
            systemSymbolName: "eye.circle",
            accessibilityDescription: "Kuroko"
        )

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        PermissionsManager.shared.refresh()
        rebuild(menu)
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()

        let permissions = PermissionsManager.shared

        let header = NSMenuItem(
            title: permissions.allGranted ? "Watching" : "Needs permissions",
            action: nil,
            keyEquivalent: ""
        )
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        addStatus(to: menu, "Screen Recording", granted: permissions.hasScreenRecording)
        addStatus(to: menu, "Accessibility", granted: permissions.hasAccessibility)
        addStatus(to: menu, "Microphone", granted: permissions.hasMicrophone)

        if !permissions.allGranted {
            menu.addItem(
                item("Grant Permissions...", action: #selector(requestPermissions))
            )
        }

        menu.addItem(.separator())

        let toggle = item("Toggle Overlay", action: #selector(toggleOverlay), key: "k")
        toggle.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(toggle)

        menu.addItem(item("Settings...", action: #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("Quit Kuroko", action: #selector(quit), key: "q"))
    }

    private func item(
        _ title: String,
        action: Selector,
        key: String = ""
    ) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = self
        return menuItem
    }

    private func addStatus(to menu: NSMenu, _ title: String, granted: Bool) {
        let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menuItem.image = NSImage(
            systemSymbolName: granted
                ? "checkmark.circle.fill"
                : "exclamationmark.triangle.fill",
            accessibilityDescription: nil
        )
        menuItem.isEnabled = false
        menu.addItem(menuItem)
    }

    @objc private func toggleOverlay() {
        onToggleOverlay()
    }

    @objc private func requestPermissions() {
        onRequestPermissions()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func openSettings() {
        NSApp.activate()
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
