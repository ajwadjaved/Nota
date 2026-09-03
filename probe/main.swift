import FoundationModels
import Foundation

// Exercises the real `ContextBrief` and `FoundationModelsProvider` against
// fixed screens, so prompts can be changed without driving Excel by hand.
//
// Triage is deliberately biased toward silence, and that bias is the first
// thing an innocuous prompt edit breaks. A non-zero exit means the suite
// disagrees with the prompts.

let provider = FoundationModelsProvider()

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
        print("      \(triage.milliseconds) ms triage, \(write.milliseconds) ms write")
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
