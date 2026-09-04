import Foundation

/// The ladder, assembled: Tier 2 decides, Tier 3 writes.
///
/// The split follows what the two are actually good at. Measured over the probe
/// fixtures, the system model triages correctly and in well under a second, and
/// diagnoses correctly, but invents fixes: keystrokes that do not exist, a
/// `gem install` for a Homebrew formula, and once a fragment of webpack source.
/// Triage is therefore kept and the writing is handed up a tier.
///
/// Tier 3 is optional. The sidecar is a separate process holding gigabytes of
/// weights, and it will often not be running; when it is not, Tier 2 writes the
/// card as before. That is worse advice, not no advice, and the inspector says
/// which one answered.
struct TieredGuidanceProvider: GuidanceProvider {
    var name: String { "\(triager.name) + \(writer.name)" }

    private let triager: FoundationModelsProvider
    private let writer: SidecarWriter

    init(
        triager: FoundationModelsProvider = FoundationModelsProvider(),
        writer: SidecarWriter = SidecarWriter()
    ) {
        self.triager = triager
        self.writer = writer
    }

    /// Only the triager's readiness matters. Without Tier 2 nothing runs at
    /// all; without Tier 3 the cards are just written by a smaller model.
    var readiness: ProviderReadiness { triager.readiness }

    func prewarm() {
        triager.prewarm()
    }

    func triage(_ brief: ContextBrief) async throws -> TriageVerdict {
        try await triager.triage(brief)
    }

    func briefing(for brief: ContextBrief) async throws -> Guidance? {
        do {
            return try await writer.briefing(for: brief)
        } catch is SidecarUnavailable {
            return try await triager.briefing(for: brief)
        } catch {
            NSLog("Nota: sidecar briefing failed, falling back to Tier 2: %@", error.localizedDescription)
            return try await triager.briefing(for: brief)
        }
    }

    func guidance(for brief: ContextBrief) async throws -> Guidance? {
        do {
            return try await writer.guidance(for: brief)
        } catch is SidecarUnavailable {
            // Ordinary. The sidecar is not running.
            return try await triager.guidance(for: brief)
        } catch {
            // The sidecar answered and something went wrong inside it: a model
            // that would not produce JSON, an out-of-memory, a bad prompt.
            // Falling back keeps the overlay useful, and the thrown error would
            // otherwise be the only record, so it goes to the log.
            NSLog("Nota: sidecar failed, falling back to Tier 2: %@", error.localizedDescription)
            return try await triager.guidance(for: brief)
        }
    }

    /// For the inspector. Not consulted before writing: probing first would add
    /// a round trip to every card, and the write path already handles absence.
    func writerIsReachable() async -> Bool {
        await writer.isReachable()
    }
}
