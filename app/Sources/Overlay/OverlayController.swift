import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class OverlayModel {
    var guidance: Guidance?

    /// Shown in the card's place while there is no card: what the hotkey is
    /// doing, or why it produced nothing.
    var status: String?
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
        model.status = nil
        model.guidance = guidance
        reposition()
        // Not `makeKeyAndOrderFront`: that would activate Nota and steal focus.
        panel.orderFrontRegardless()
        isVisible = true
    }

    /// Replaces the card with a line of text. The previous card goes with it:
    /// once the user has asked about this screen, advice about the last one is
    /// no longer an answer to anything.
    func show(status: String) {
        model.guidance = nil
        model.status = status
        reposition()
        panel.orderFrontRegardless()
        isVisible = true
    }

    func hide() {
        panel.orderOut(nil)
        isVisible = false
    }

    /// Hides the panel *and* forgets what it said, so the hotkey cannot bring
    /// back advice about a cell in a workbook the user has since left.
    func clear() {
        model.guidance = nil
        model.status = nil
        hide()
    }

    /// The hotkey path. With nothing to say the panel still comes up, in its
    /// empty state, because a hotkey that does nothing visible reads as broken.
    func toggle() {
        if isVisible {
            hide()
        } else if let guidance = model.guidance {
            show(guidance: guidance)
        } else {
            reposition()
            panel.orderFrontRegardless()
            isVisible = true
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
