import Foundation

/// Tier 2's answer: is the user stuck, and cheaply, why do we think so.
///
/// The reason is kept even on a negative verdict. Without it there is no way to
/// tell "triage is working and the user is fine" apart from "triage is broken",
/// and those need very different fixes.
struct TriageVerdict: Equatable {
    var needsHelp: Bool
    var reason: String
}

/// What a model returned, before it is allowed onto the card.
///
/// Every provider produces one of these rather than a `Guidance` directly, so
/// the rules about what may reach the screen live in exactly one place. They
/// were expensive to learn and they apply regardless of which model answered.
struct GuidanceDraft {
    var title: String
    var diagnosis: String
    var steps: [String]
}

extension GuidanceDraft {
    /// The card is 320 points wide and shows a handful of lines.
    static let maximumSteps = 3

    /// Prompts ask for under 80 characters and are routinely ignored, so this
    /// is the limit that actually holds.
    static let stepCharacterLimit = 110

    /// Fragments that only appear once a model has stopped answering and
    /// started reciting. Observed in the wild: a step containing
    /// `var __webpack_require__ = ...`, which is training data, not advice.
    private static let sludge = ["```", "__", "=>", "function(", "function ("]

    static func isPlausibleStep(_ step: String) -> Bool {
        guard !step.isEmpty, step.count <= stepCharacterLimit else { return false }
        guard !sludge.contains(where: step.contains) else { return false }

        // Semicolons and braces are punctuation in code and vanishingly rare in
        // a one-line instruction, even one naming a formula.
        return !step.contains(";") && !step.contains("{")
    }

    /// Returns `nil` when nothing survives, which is the model declining to be
    /// specific. A card saying nothing is worse than no card.
    func card(source: String, writer: String) -> Guidance? {
        let title = Self.clean(title).droppingTrailingPeriod
        let surviving =
            steps
            .map(Self.clean)
            .filter(Self.isPlausibleStep)
            .prefix(Self.maximumSteps)

        guard !title.isEmpty, !surviving.isEmpty else { return nil }

        // The diagnosis leads as an already-established fact, which is what the
        // filled checkmark means: this part is not for the reader to do, it is
        // what Nota worked out.
        let diagnosis = Self.clean(diagnosis)
        let leading =
            diagnosis.isEmpty
            ? [] : [GuidanceStep(text: diagnosis, isDone: true)]

        return Guidance(
            title: title,
            source: source,
            steps: leading + surviving.map { GuidanceStep(text: $0) },
            writer: writer
        )
    }

    private static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension String {
    /// Only a single trailing period. An ellipsis or a question mark is
    /// meaningful punctuation and stays.
    fileprivate var droppingTrailingPeriod: String {
        guard hasSuffix("."), !hasSuffix("..") else { return self }
        return String(dropLast())
    }
}

/// A provider failure already phrased for the inspector. Raw framework errors
/// describe themselves in terms of sessions and schemas, which says nothing
/// about what to do next.
struct GuidanceError: LocalizedError {
    var reason: String
    var errorDescription: String? { reason }
}

enum ProviderReadiness: Equatable {
    case ready
    case unavailable(String)

    var isReady: Bool { self == .ready }
}

/// Something that can write advice, given a screen worth writing about.
///
/// Separate from `GuidanceProvider` because the tiers are not symmetrical. The
/// sidecar writes but has no business triaging: triage runs on every settled
/// screen event, and waking a 27B model that often would undo the entire point
/// of the ladder.
protocol GuidanceWriter: Sendable {
    /// Shown in the inspector so it is obvious which tier answered.
    var name: String { get }

    /// Returns `nil` if the model reconsidered once it had to be specific,
    /// which happens often enough to be worth modelling as a real outcome
    /// rather than an error.
    func guidance(for brief: ContextBrief) async throws -> Guidance?
}

/// The seam between the pipeline and the models. A hosted model would implement
/// this same pair, and the engine above it would not change.
///
/// `triage` runs on every settled screen event and has to be nearly free;
/// `guidance` only runs after triage says yes.
protocol GuidanceProvider: GuidanceWriter {
    var readiness: ProviderReadiness { get }

    /// Called for every settled context change. Must be cheap.
    func triage(_ brief: ContextBrief) async throws -> TriageVerdict

    /// Optional hook to pay model start-up cost before the first real request.
    func prewarm()
}

extension GuidanceProvider {
    func prewarm() {}
}
