import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class OverlayModel {
    var guidance: Guidance?
}

@MainActor
final class OverlayController {
    private let panel = OverlayPanel()
    private let model = OverlayModel()
    private var isVisible = false

    /// Screen-capture code must exclude this window, or the model reads its own
    /// previous advice off the screen and feeds it back to itself.
    var panelWindowID: CGWindowID {
        CGWindowID(panel.windowNumber)
    }

    init() {
        let hosting = NSHostingView(rootView: OverlayView(model: model))
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hosting
    }

    func show(guidance: Guidance) {
        model.guidance = guidance
        reposition()
        // Not `makeKeyAndOrderFront`: that would activate Kuroko and steal focus.
        panel.orderFrontRegardless()
        isVisible = true
    }

    func hide() {
        panel.orderOut(nil)
        isVisible = false
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show(guidance: model.guidance ?? .demo)
        }
    }

    /// Pins the panel to the top-right of the active screen, inside the visible
    /// frame so it clears the menu bar.
    private func reposition() {
        guard let screen = NSScreen.main else { return }

        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? NSSize(width: 320, height: 160)
        panel.setContentSize(size)

        let margin: CGFloat = 16
        let area = screen.visibleFrame
        panel.setFrameOrigin(
            NSPoint(
                x: area.maxX - size.width - margin,
                y: area.maxY - size.height - margin
            )
        )
    }
}
