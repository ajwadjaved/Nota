import Foundation

struct GuidanceStep: Identifiable, Hashable {
    let id: UUID
    var text: String
    var isDone: Bool

    init(id: UUID = UUID(), text: String, isDone: Bool = false) {
        self.id = id
        self.text = text
        self.isDone = isDone
    }
}

/// A single piece of advice: what Kuroko thinks you are trying to do, and the
/// steps to get there.
struct Guidance: Identifiable, Hashable {
    let id: UUID
    var title: String
    /// Where this applies, shown as a subtitle, e.g. "Microsoft Excel - Q3.xlsx".
    var source: String?
    var steps: [GuidanceStep]

    init(id: UUID = UUID(), title: String, source: String? = nil, steps: [GuidanceStep]) {
        self.id = id
        self.title = title
        self.source = source
        self.steps = steps
    }
}

extension Guidance {
    static let demo = Guidance(
        title: "Fix the #REF! error in D14",
        source: "Microsoft Excel - Q3-Budget.xlsx",
        steps: [
            GuidanceStep(text: "D14 points at Sheet2!B7, which no longer exists", isDone: true),
            GuidanceStep(text: "Repoint the formula at the renamed Costs range"),
            GuidanceStep(text: "Wrap it in IFERROR so blank rows stay empty"),
        ]
    )
}
