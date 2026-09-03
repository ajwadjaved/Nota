import Foundation
import Observation

/// Sits between the readers and the overlay and decides when a model runs.
///
/// The readers fire on a timer, so almost every tick describes a screen that
/// has not meaningfully changed. Three rules keep the model idle:
///
/// - a brief whose text matches the last one we acted on is dropped outright;
/// - a changing brief re-arms a settle timer, so nothing runs while typing;
/// - triage gates guidance, so the longer call only happens after a yes.
@MainActor
@Observable
final class GuidanceEngine {
    enum Phase: Equatable {
        case idle
        /// Frontmost app is outside the prototype's allowlist.
        case unsupported(String)
        /// A change arrived and we are waiting for the screen to settle.
        case waiting
        case triaging
        case generating
        /// Triage ran and said no. Carries its reason.
        case quiet(String)
        case showing
        case failed(String)
        case modelUnavailable(String)

        var label: String {
            switch self {
            case .idle: "Idle"
            case .unsupported(let app): "No reader for \(app)"
            case .waiting: "Waiting for the screen to settle"
            case .triaging: "Triaging"
            case .generating: "Writing guidance"
            case .quiet: "Quiet"
            case .showing: "Showing guidance"
            case .failed: "Failed"
            case .modelUnavailable: "Model unavailable"
            }
        }
    }

    private(set) var phase: Phase = .idle
    private(set) var lastVerdict: TriageVerdict?
    private(set) var triageDuration: TimeInterval?
    private(set) var guidanceDuration: TimeInterval?
    private(set) var lastBrief: ContextBrief?

    let providerName: String

    private let provider: any GuidanceProvider
    private let present: (Guidance) -> Void
    private let dismiss: () -> Void

    /// How long the screen has to hold still before a model runs. Long enough
    /// that typing a command does not trigger a verdict on every keystroke,
    /// short enough that it still feels like a reaction.
    private let settleDelay: Duration = .milliseconds(1_200)

    /// Fingerprint we have already run, or are running right now.
    private var handled: String?
    private var pending: ContextBrief?
    private var work: Task<Void, Never>?

    /// Which app the guidance on screen belongs to. Advice about an Excel
    /// formula must not stay up once the user is somewhere else.
    private var guidanceBundleID: String?

    init(
        provider: any GuidanceProvider = FoundationModelsProvider(),
        present: @escaping (Guidance) -> Void,
        dismiss: @escaping () -> Void
    ) {
        self.provider = provider
        self.providerName = provider.name
        self.present = present
        self.dismiss = dismiss

        if case .unavailable(let reason) = provider.readiness {
            phase = .modelUnavailable(reason)
        }
        provider.prewarm()
    }

    func stop() {
        work?.cancel()
        work = nil
    }

    // MARK: - Input

    func handle(_ context: ScreenContext) {
        if case .unavailable(let reason) = provider.readiness {
            phase = .modelUnavailable(reason)
            return
        }

        clearGuidanceIfAppChanged(to: context.app.bundleID)

        guard let brief = ContextBrief.make(from: context) else {
            // Not a failure. Most apps land here, and it must stay silent.
            work?.cancel()
            pending = nil
            lastBrief = nil
            phase =
                ContextBrief.supportedBundleIDs.contains(context.app.bundleID ?? "")
                ? .idle : .unsupported(context.app.name)
            return
        }

        lastBrief = brief

        // Already answered this exact screen, or answering it now.
        guard brief.fingerprint != handled else { return }
        // The settle timer is already armed for this exact text; re-arming it
        // here would mean an unchanging screen never reaches the model at all.
        guard brief.fingerprint != pending?.fingerprint else { return }

        pending = brief
        phase = .waiting

        work?.cancel()
        work = Task { [weak self] in
            try? await Task.sleep(for: self?.settleDelay ?? .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.run(brief)
        }
    }

    // MARK: - The ladder

    private func run(_ brief: ContextBrief) async {
        // Marked handled before the call, not after, so a failure does not get
        // retried on every poll tick. A terminal or a spreadsheet changes again
        // within seconds, and that next change is the retry.
        handled = brief.fingerprint
        pending = nil
        guidanceDuration = nil

        do {
            phase = .triaging
            let triageStart = ContinuousClock.now
            let verdict = try await provider.triage(brief)
            triageDuration = Self.seconds(since: triageStart)

            guard !Task.isCancelled else { return }
            lastVerdict = verdict

            guard verdict.needsHelp else {
                phase = .quiet(verdict.reason)
                return
            }

            phase = .generating
            let guidanceStart = ContinuousClock.now
            let guidance = try await provider.guidance(for: brief)
            guidanceDuration = Self.seconds(since: guidanceStart)

            guard !Task.isCancelled else { return }

            guard let guidance else {
                phase = .quiet("Model declined to be specific")
                return
            }

            guidanceBundleID = currentBundleID
            present(guidance)
            phase = .showing
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private var currentBundleID: String?

    private func clearGuidanceIfAppChanged(to bundleID: String?) {
        currentBundleID = bundleID
        guard let guidanceBundleID, guidanceBundleID != bundleID else { return }
        self.guidanceBundleID = nil
        dismiss()
        if phase == .showing { phase = .idle }
    }

    private static func seconds(since start: ContinuousClock.Instant) -> TimeInterval {
        let elapsed = ContinuousClock.now - start
        return TimeInterval(elapsed.components.seconds)
            + TimeInterval(elapsed.components.attoseconds) / 1e18
    }
}
