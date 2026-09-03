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

/// A single piece of advice: what Nota thinks you are trying to do, and the
/// steps to get there.
struct Guidance: Identifiable, Hashable {
    let id: UUID
    var title: String
    /// Where this applies, shown as a subtitle, e.g. "Microsoft Excel - Q3.xlsx".
    var source: String?
    var steps: [GuidanceStep]

    /// Which model wrote this. Never shown on the card, but two tiers can now
    /// produce one and telling their output apart by eye is exactly the thing
    /// the inspector exists to avoid.
    var writer: String?

    init(
        id: UUID = UUID(),
        title: String,
        source: String? = nil,
        steps: [GuidanceStep],
        writer: String? = nil
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.steps = steps
        self.writer = writer
    }
}