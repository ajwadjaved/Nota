import Foundation
import Observation
import os

/// Screen text never reaches the log. Phase labels are a closed vocabulary and
/// are safe to emit, but triage reasons and error messages are written by a
/// model that was shown the user's screen, so they are logged `.private` and
/// Console redacts them. The menu bar already shows the quiet reason in plain
/// text to the one person entitled to read it.
private let log = Logger(subsystem: "dev.nota.Nota", category: "engine")

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

    /// Kept so the inspector can name the tier that wrote the card on screen.
    /// Two models can produce one now, and their output is not always
    /// distinguishable by eye.
    private(set) var lastGuidance: Guidance?

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
        provider: any GuidanceProvider = TieredGuidanceProvider(),
        present: @escaping (Guidance) -> Void,
        dismiss: @escaping () -> Void
    ) {
        self.provider = provider
        self.providerName = provider.name
        self.present = present
        self.dismiss = dismiss

        log.notice("engine ready, provider \(provider.name, privacy: .public)")
        if case .unavailable(let reason) = provider.readiness {
            phase = .modelUnavailable(reason)
            log.error("provider unavailable: \(reason, privacy: .public)")
        }
        provider.prewarm()
    }

    func stop() {
        work?.cancel()
        work = nil
    }

    // MARK: - Phase

    /// Every phase change goes through here so the log is a complete trace
    /// rather than whichever transitions someone remembered to instrument.
    ///
    /// A plain `didSet` would be the obvious way to do this, but `@Observable`
    /// rewrites stored properties into computed ones, so property observers on
    /// `phase` are not reliable here.
    private func setPhase(_ next: Phase, detail: String? = nil) {
        guard next != phase else { return }

        // `.notice` rather than `.debug`: debug messages live in a memory
        // buffer that `log show` will not return, so they are useless for
        // working out what the app did five minutes ago. Transitions are
        // deduplicated above and gated by the settle timer, so this stays quiet
        // even while the readers poll every 1.5 seconds.
        if let detail {
            log.notice("\(self.phase.label, privacy: .public) -> \(next.label, privacy: .public): \(detail, privacy: .private)")
        } else {
            log.notice("\(self.phase.label, privacy: .public) -> \(next.label, privacy: .public)")
        }

        phase = next
    }

    // MARK: - Input

    func handle(_ context: ScreenContext) {
        if case .unavailable(let reason) = provider.readiness {
            setPhase(.modelUnavailable(reason), detail: reason)
            return
        }

        clearGuidanceIfAppChanged(to: context.app.bundleID)

        guard let brief = ContextBrief.make(from: context) else {
            // Not a failure. Most apps land here, and it must stay silent.
            work?.cancel()
            pending = nil
            lastBrief = nil

            let supported =
                ContextBrief.supportedBundleIDs.contains(context.app.bundleID ?? "")

            // The two ways to get here are worth telling apart. An unsupported
            // app is the allowlist working; a supported one that yields no
            // brief means the reader came back empty, which is what a missing
            // Accessibility grant looks like from in here.
            if supported {
                log.debug(
                    """
                    no brief from \(context.app.name, privacy: .public) \
                    (supported); focused element \
                    \(context.focused == nil ? "nil" : "present", privacy: .public), \
                    \(context.appFacts.count, privacy: .public) app facts
                    """
                )
            }

            setPhase(supported ? .idle : .unsupported(context.app.name))
            return
        }

        lastBrief = brief

        // Already answered this exact screen, or answering it now.
        guard brief.fingerprint != handled else { return }
        // The settle timer is already armed for this exact text; re-arming it
        // here would mean an unchanging screen never reaches the model at all.
        guard brief.fingerprint != pending?.fingerprint else { return }

        log.notice(
            """
            new brief from \(context.app.name, privacy: .public), \
            kind \(brief.kind.rawValue, privacy: .public), \
            \(brief.text.count, privacy: .public) chars
            """
        )

        pending = brief
        setPhase(.waiting)

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
            setPhase(.triaging)
            let triageStart = ContinuousClock.now
            let verdict = try await provider.triage(brief)
            triageDuration = Self.seconds(since: triageStart)

            guard !Task.isCancelled else { return }
            lastVerdict = verdict

            log.notice(
                """
                triage \(verdict.needsHelp ? "needs help" : "quiet", privacy: .public) \
                in \(Self.milliseconds(self.triageDuration), privacy: .public) ms
                """
            )

            guard verdict.needsHelp else {
                setPhase(.quiet(verdict.reason), detail: verdict.reason)
                return
            }

            setPhase(.generating)
            let guidanceStart = ContinuousClock.now
            let guidance = try await provider.guidance(for: brief)
            guidanceDuration = Self.seconds(since: guidanceStart)

            guard !Task.isCancelled else { return }

            guard let guidance else {
                setPhase(.quiet("Model declined to be specific"))
                return
            }

            // Which tier answered is the thing worth knowing when the cards
            // suddenly get worse: a sidecar that died falls back silently.
            log.notice(
                """
                card written by \(guidance.writer ?? "unknown", privacy: .public) \
                in \(Self.milliseconds(self.guidanceDuration), privacy: .public) ms
                """
            )

            guidanceBundleID = currentBundleID
            lastGuidance = guidance
            present(guidance)
            setPhase(.showing)
        } catch {
            guard !Task.isCancelled else { return }
            log.error("ladder failed: \(error.localizedDescription, privacy: .private)")
            setPhase(.failed(error.localizedDescription), detail: error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private var currentBundleID: String?

    private func clearGuidanceIfAppChanged(to bundleID: String?) {
        currentBundleID = bundleID
        guard let guidanceBundleID, guidanceBundleID != bundleID else { return }
        self.guidanceBundleID = nil
        dismiss()
        if phase == .showing { setPhase(.idle) }
    }

    private static func seconds(since start: ContinuousClock.Instant) -> TimeInterval {
        let elapsed = ContinuousClock.now - start
        return TimeInterval(elapsed.components.seconds)
            + TimeInterval(elapsed.components.attoseconds) / 1e18
    }

    private static func milliseconds(_ seconds: TimeInterval?) -> Int {
        Int(((seconds ?? 0) * 1_000).rounded())
    }
}
