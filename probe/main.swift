import FoundationModels
import Foundation

// Exercises the real `ContextBrief` and `FoundationModelsProvider` against
// fixed screens, so prompts can be changed without driving Excel by hand.
//
// Triage is deliberately biased toward silence, and that bias is the first
// thing an innocuous prompt edit breaks. A non-zero exit means the suite
// disagrees with the prompts.

// `--tiered` sends the writing to the sidecar and keeps triage on Tier 2, which
// is the shipping configuration. Without it the suite runs entirely on the
// system model, so the two can be compared over identical fixtures.
// `--briefing` exercises the hotkey path rather than the ambient one. See the
// block further down for what it asserts.
let useTiered = CommandLine.arguments.contains("--tiered")
let useBriefing = CommandLine.arguments.contains("--briefing")
let provider: any GuidanceProvider =
    useTiered ? TieredGuidanceProvider() : FoundationModelsProvider()

print("provider: \(provider.name)")

if useTiered, await !TieredGuidanceProvider().writerIsReachable() {
    print("warning: the sidecar is not answering, so Tier 2 will write instead")
}
print()

enum Outcome {
    case noBrief
    case quiet(reason: String, triage: Duration)
    case guidance(Guidance, triage: Duration, write: Duration)
    case error(String)

    var matches: Expectation? {
        switch self {
        case .noBrief: .noBrief
        case .quiet: .quiet
        case .guidance: .guidance
        case .error: nil
        }
    }
}

func evaluate(_ fixture: Fixture) async -> Outcome {
    guard let brief = ContextBrief.make(from: fixture.context) else {
        return .noBrief
    }

    do {
        let triageStart = ContinuousClock.now
        let verdict = try await provider.triage(brief)
        let triage = ContinuousClock.now - triageStart

        guard verdict.needsHelp else {
            return .quiet(reason: verdict.reason, triage: triage)
        }

        let writeStart = ContinuousClock.now
        let guidance = try await provider.guidance(for: brief)
        let write = ContinuousClock.now - writeStart

        guard let guidance else {
            return .quiet(reason: "declined to be specific", triage: triage)
        }
        return .guidance(guidance, triage: triage, write: write)
    } catch {
        return .error(error.localizedDescription)
    }
}

func report(_ fixture: Fixture, _ outcome: Outcome) {
    let ok = outcome.matches == fixture.expectation
    print("\(ok ? "PASS" : "FAIL")  \(fixture.name)")

    switch outcome {
    case .noBrief:
        print("      no brief built; no model call")
    case .quiet(let reason, let triage):
        print("      quiet after \(triage.milliseconds) ms: \(reason)")
    case .guidance(let guidance, let triage, let write):
        let writer = guidance.writer ?? "unknown"
        print("      \(triage.milliseconds) ms triage, \(write.milliseconds) ms write via \(writer)")
        print("      \(guidance.title)")
        for step in guidance.steps {
            print("        [\(step.isDone ? "x" : " ")] \(step.text)")
        }
    case .error(let message):
        print("      error: \(message)")
    }

    if !ok {
        print("      expected \(fixture.expectation.rawValue)")
    }
}

extension Duration {
    var milliseconds: Int {
        Int(components.seconds) * 1_000
            + Int(components.attoseconds / 1_000_000_000_000_000)
    }
}

// The `noBrief` fixtures are pure logic, so they are worth running even with no
// model available. Everything else has to be skipped rather than failed.
let modelReady = provider.readiness.isReady
if !modelReady {
    if case .unavailable(let reason) = provider.readiness {
        print("Model unavailable: \(reason)")
    }
    print("Running only the fixtures that need no model.\n")
}

// The hotkey path: every screen with readable text on it, whether or not
// anything is wrong, and no triage in the way.
//
// The assertion is the mirror image of the ambient suite's. There, a card on a
// healthy screen is the failure. Here, a readable screen that produces no card
// is: the user pressed a key and is owed an answer. Watch the healthy Excel
// fixtures in particular, since describing `=SUM(B1:B3)` without inventing a
// fault for it is exactly what the separate briefing prompt exists to do.
if useBriefing {
    guard modelReady else {
        print("Model unavailable, so there is nothing to brief.")
        exit(1)
    }

    var briefingFailures = 0

    for fixture in Fixtures.all {
        guard let brief = ContextBrief.make(from: fixture.context, appetite: .anything)
        else {
            print("SKIP  \(fixture.name)")
            print("      no readable text, so the hotkey would say so")
            continue
        }

        do {
            let started = ContinuousClock.now
            let card = try await provider.briefing(for: brief)
            let elapsed = ContinuousClock.now - started

            guard let card else {
                print("FAIL  \(fixture.name)")
                print("      readable screen produced no card")
                briefingFailures += 1
                continue
            }

            print("PASS  \(fixture.name)")
            print("      \(elapsed.milliseconds) ms via \(card.writer ?? "unknown")")
            print("      \(card.title)")
            for step in card.steps {
                print("        [\(step.isDone ? "x" : " ")] \(step.text)")
            }
        } catch {
            print("FAIL  \(fixture.name)")
            print("      error: \(error.localizedDescription)")
            briefingFailures += 1
        }
    }

    print("\n\(briefingFailures) failed")
    exit(briefingFailures == 0 ? 0 : 1)
}

var failures = 0
var skipped = 0

for fixture in Fixtures.all {
    if !modelReady, fixture.expectation != .noBrief {
        skipped += 1
        continue
    }
    let outcome = await evaluate(fixture)
    report(fixture, outcome)
    if outcome.matches != fixture.expectation { failures += 1 }
}

let ran = Fixtures.all.count - skipped
print("\n\(ran - failures)/\(ran) passed", terminator: "")
print(skipped > 0 ? ", \(skipped) skipped (no model)" : "")

exit(failures == 0 ? 0 : 1)
