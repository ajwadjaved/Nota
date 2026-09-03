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

/// The seam between the pipeline and whatever writes the actual advice.
///
/// Two methods rather than one because they sit at different points on the cost
/// curve. `triage` runs on every settled screen event and has to be nearly
/// free; `guidance` only runs after triage says yes. A hosted model would
/// implement the same pair, and the engine above would not change.
protocol GuidanceProvider: Sendable {
    /// Shown in the inspector so it is obvious which tier answered.
    var name: String { get }

    var readiness: ProviderReadiness { get }

    /// Called for every settled context change. Must be cheap.
    func triage(_ brief: ContextBrief) async throws -> TriageVerdict

    /// Called only when `triage` returned `needsHelp`. Returns `nil` if the
    /// model reconsidered once it had to be specific, which happens often
    /// enough to be worth modelling as a real outcome rather than an error.
    func guidance(for brief: ContextBrief) async throws -> Guidance?

    /// Optional hook to pay model start-up cost before the first real request.
    func prewarm()
}

extension GuidanceProvider {
    func prewarm() {}
}
