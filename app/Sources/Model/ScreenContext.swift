import Foundation

struct AppIdentity: Hashable {
    var name: String
    var bundleID: String?
    var pid: pid_t
}

/// Whatever the Accessibility API will tell us about the control the user is
/// currently in. Every field is optional because AX support varies wildly:
/// native apps expose most of this, Electron apps often expose almost none.
struct FocusedElement: Hashable {
    var role: String?
    var subrole: String?
    var title: String?
    var value: String?
    var placeholder: String?
    var selectedText: String?
    var help: String?
}

/// A single named fact pulled from an app that can be scripted directly, which
/// is far more precise than anything vision or AX would give us. For Excel this
/// is the cell address, its formula, and its computed value.
struct AppFact: Hashable, Identifiable {
    var id: String { label }
    var label: String
    var value: String
}

/// Everything Nota knows about the current moment, assembled from the
/// cheapest sources available before any model is involved.
struct ScreenContext {
    var app: AppIdentity
    var windowTitle: String?
    var focused: FocusedElement?
    var appFacts: [AppFact] = []
    var capturedAt: Date = .now

    /// How long the readers took, so the debug inspector can show whether the
    /// cheap path is actually staying cheap.
    var readDuration: TimeInterval = 0
}
