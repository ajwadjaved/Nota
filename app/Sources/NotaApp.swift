import SwiftUI

/// Nota runs as a menu-bar accessory (`LSUIElement`), so there is no main
/// window scene. `Settings` is the only scene, reachable with Cmd-comma; all of
/// the real wiring happens in `AppDelegate`.
@main
struct NotaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}
