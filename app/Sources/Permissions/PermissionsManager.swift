import AVFoundation
import AppKit
import ApplicationServices
import CoreGraphics
import Observation

/// Kuroko needs three separate TCC grants. They are deliberately requested
/// on demand rather than all at launch, so the user sees why each one is asked
/// for.
@MainActor
@Observable
final class PermissionsManager {
    static let shared = PermissionsManager()

    var hasScreenRecording = false
    var hasAccessibility = false
    var hasMicrophone = false

    private init() {}

    var allGranted: Bool {
        hasScreenRecording && hasAccessibility && hasMicrophone
    }

    func refresh() {
        hasScreenRecording = CGPreflightScreenCaptureAccess()
        hasAccessibility = AXIsProcessTrusted()
        hasMicrophone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    func requestAll() async {
        // Prompts once per code signature, then silently returns false forever;
        // `openSettings` is the only recourse after a denial.
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }

        if !AXIsProcessTrusted() {
            // Spelled out rather than using `kAXTrustedCheckOptionPrompt`, which
            // the SDK imports as a mutable global and Swift 6 therefore rejects
            // as non-Sendable. The underlying value is a documented constant.
            AXIsProcessTrustedWithOptions(
                ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            )
        }

        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }

        refresh()
    }

    func openSettings(for pane: Pane) {
        guard let url = URL(string: pane.urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    enum Pane {
        case screenRecording
        case accessibility
        case microphone

        var urlString: String {
            let base = "x-apple.systempreferences:com.apple.preference.security?"
            switch self {
            case .screenRecording: return base + "Privacy_ScreenCapture"
            case .accessibility: return base + "Privacy_Accessibility"
            case .microphone: return base + "Privacy_Microphone"
            }
        }
    }
}
