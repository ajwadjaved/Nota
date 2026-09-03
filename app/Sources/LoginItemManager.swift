import Observation
import ServiceManagement

/// Launch-at-login via `SMAppService`, which registers the app bundle itself
/// rather than installing a separate helper.
///
/// This only works from a stable, properly signed location. Registering while
/// running out of the build directory either fails or pins the login item to a
/// path that the next build replaces, so `install.sh` puts the app in
/// /Applications first.
@MainActor
@Observable
final class LoginItemManager {
    static let shared = LoginItemManager()

    private(set) var isEnabled = false
    private(set) var lastError: String?

    private init() {
        refresh()
    }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }
}
