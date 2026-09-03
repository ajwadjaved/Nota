import AppKit
import Observation

/// Tier 0 and Tier 1 of the pipeline: work out that something happened, then
/// gather the cheapest useful description of it. No model is involved here, and
/// nothing on this path costs more than a few milliseconds.
@MainActor
@Observable
final class ContextCoordinator {
    private(set) var current: ScreenContext?
    private(set) var lastAppRead: AppReadResult = .unavailable

    /// Called on every read, changed or not. Deciding whether a read is worth
    /// reacting to needs the brief, not the raw context, so that judgement
    /// belongs downstream in `GuidanceEngine` rather than here.
    var onRead: ((ScreenContext) -> Void)?

    private var activationObserver: NSObjectProtocol?
    private var pollTimer: Timer?

    func start() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        startPolling()
        refresh()
    }

    func stop() {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        stopPolling()
    }

    /// App-activation alone misses focus changes *inside* an app, such as
    /// moving between Excel cells. Real AX observers replace this.
    ///
    /// 1.5s rather than 1s because each tick can send Excel an Apple event,
    /// which is milliseconds of blocked main thread rather than microseconds.
    func startPolling(interval: TimeInterval = 1.5) {
        stopPolling()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func refresh() {
        let started = Date()

        guard let frontmost = NSWorkspace.shared.frontmostApplication else {
            current = nil
            return
        }

        // Reading our own overlay back would be circular, and there is nothing
        // in Nota worth guiding anyone through.
        guard frontmost.processIdentifier != getpid() else { return }

        let identity = AppIdentity(
            name: frontmost.localizedName ?? "Unknown",
            bundleID: frontmost.bundleIdentifier,
            pid: frontmost.processIdentifier
        )

        let appRead = AppReaders.read(bundleID: identity.bundleID)
        lastAppRead = appRead

        let context = ScreenContext(
            app: identity,
            windowTitle: AccessibilityReader.focusedWindowTitle(pid: identity.pid),
            focused: AccessibilityReader.focusedElement(pid: identity.pid),
            appFacts: {
                if case .facts(let facts) = appRead { return facts }
                return []
            }(),
            capturedAt: .now,
            readDuration: Date().timeIntervalSince(started)
        )

        current = context
        onRead?(context)
    }
}
