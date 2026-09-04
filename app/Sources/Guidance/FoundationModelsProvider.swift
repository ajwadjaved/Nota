import FoundationModels
import Foundation

/// Tier 2: Apple's on-device model, used for both triage and guidance.
///
/// The tier table puts guidance on a local vision-language model, and for a
/// screenshot that is still right. But Ghostty and Excel hand over real text —
/// a terminal buffer, a cell formula and its computed value — and once the
/// context is already text there is nothing for a vision model to add. It would
/// cost seconds and a few gigabytes of weights to re-read what we can state
/// exactly. So for these two apps the ladder stops here, and Tier 3 stays for
/// the apps that only give us pixels.
struct FoundationModelsProvider: GuidanceProvider {
    let name = "Apple Foundation Models"

    /// Triage runs constantly and only has to pick between two answers, so
    /// greedy sampling is right: it is the cheapest and it makes the verdict
    /// reproducible for the same screen, which matters when the alternative is
    /// an overlay that flickers between "stuck" and "fine" while the user reads.
    private static let triageOptions = GenerationOptions(
        sampling: .greedy,
        maximumResponseTokens: 120
    )

    private static let guidanceOptions = GenerationOptions(
        sampling: .greedy,
        maximumResponseTokens: 400
    )

    var readiness: ProviderReadiness {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .ready
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("Apple Intelligence is off in System Settings")
        case .unavailable(.modelNotReady):
            return .unavailable("The system model is still downloading")
        case .unavailable(.deviceNotEligible):
            return .unavailable("This Mac cannot run Apple Intelligence")
        case .unavailable:
            return .unavailable("The system model is unavailable")
        }
    }

    func prewarm() {
        guard readiness.isReady else { return }
        // Loading the model on the first real screen event would put a
        // multi-second stall in front of the first piece of advice.
        LanguageModelSession(instructions: Self.triageInstructions).prewarm()
    }

    // MARK: - Tier 2: triage

    // `fileprivate` rather than `private`: the `@Generable` macro adds a
    // conformance extension at file scope, which cannot see a `private` member.
    // No literal examples in any of these descriptions, here or in the
    // instructions. A 3B-class model treats a sample answer as the answer: an
    // earlier version offered 'Fix the #REF! error in D14' as a format hint for
    // the title and got it back verbatim for a terminal error, a #DIV/0! and a
    // healthy cell alike. Describe the shape, never fill it in.
    @Generable
    fileprivate struct TriageAnswer {
        @Guide(description: """
            True only if there is a concrete, visible problem the person is \
            currently blocked on. False if they are simply working, reading, \
            or the screen shows a normal successful state.
            """)
        var needsHelp: Bool

        @Guide(description: """
            One short clause naming the specific thing on this screen that led \
            to your answer. Quote the identifier or message you are describing. \
            Never a question and never a suggestion.
            """)
        var reason: String
    }

    private static let triageInstructions = """
        You decide whether someone working at their Mac is stuck. You are shown \
        the text that is on their screen right now.

        Answer true only when the screen text itself contains an explicit \
        failure: an error message, a non-zero exit, a command that was not \
        found, or a cell whose value is an error. The failure must be visible \
        in the text you were given.

        Answer false for everything else, and most of the time the answer is \
        false. Answer false for a command that succeeded, for output that is \
        merely long, for a shell prompt waiting for input, for an empty cell, \
        and for a warning that did not stop the work from completing.

        Never infer a problem from code or a formula that looks unusual to you. \
        If you cannot quote the failure, there is no failure. Do not reason \
        about whether something is correct; only report what the screen says. \
        Interrupting someone who is working is worse than staying quiet.
        """

    func triage(_ brief: ContextBrief) async throws -> TriageVerdict {
        let answer = try await Self.generate(
            TriageAnswer.self,
            instructions: Self.triageInstructions,
            prompt: Self.prompt(for: brief),
            options: Self.triageOptions
        )

        return TriageVerdict(needsHelp: answer.needsHelp, reason: answer.reason)
    }

    // MARK: - Guidance

    @Generable
    fileprivate struct GuidanceAnswer {
        @Guide(description: """
            The goal as one short imperative phrase, at most 60 characters, \
            naming the specific thing that is wrong using an identifier that \
            appears in the screen text. No trailing period.
            """)
        var title: String

        @Guide(description: """
            What is actually wrong, in one sentence under 90 characters. State \
            the cause, not the fix.
            """)
        var diagnosis: String

        @Guide(
            description: """
                One or two changes to make, each imperative and under 80 \
                characters. Each one names a value, formula, argument or file \
                that appears in the screen text above and says what it should \
                become. Not a procedure, not a click, not a keystroke.
                """,
            // 1...3, not 1...2. Narrowing it to two started producing output
            // that failed to decode against the schema at all, which is a worse
            // outcome than a third step the card can drop itself.
            .count(1...3)
        )
        var steps: [String]
    }

    private static let guidanceInstructions = """
        You help someone who is stuck at their Mac, in a small overlay card \
        they read out of the corner of their eye.

        Everything you write must be grounded in the screen text you are given. \
        Name the actual cell, file, flag or command from that text. If the text \
        does not tell you something, do not supply it from memory.

        Describe the change to make, never the mechanism for making it. The \
        person already knows how to use their own tools, and is already in the \
        application you are looking at.

        This means you must never write a keyboard shortcut, a menu path, a \
        button name, a dialog name, or an instruction to open or switch to an \
        application. Never write an installation command unless that exact \
        command appears in the screen text. State which value, formula, \
        argument or file should change and what it should become.

        Never explain what you are doing, never greet them, and never suggest \
        they read documentation or search the web. Assume they are competent \
        and just missing one fact.

        You do not control the machine, so never claim to have done anything. \
        Describe what they should do.
        """

    func guidance(for brief: ContextBrief) async throws -> Guidance? {
        let answer = try await Self.generate(
            GuidanceAnswer.self,
            instructions: Self.guidanceInstructions,
            prompt: Self.prompt(for: brief),
            options: Self.guidanceOptions
        )

        // Guides are a hint, not a contract: `.count(1...3)` still came back
        // with four steps, and "no trailing period" came back with one. The
        // draft is where that gets enforced.
        return GuidanceDraft(
            title: answer.title,
            diagnosis: answer.diagnosis,
            steps: answer.steps
        )
        .card(source: brief.source, writer: name)
    }

    // MARK: - Briefing

    private static let briefingOptions = GenerationOptions(
        sampling: .greedy,
        maximumResponseTokens: 500
    )

    @Generable
    fileprivate struct BriefingAnswer {
        @Guide(description: """
            What the person is working on, as one short phrase of at most 60 \
            characters, naming a file, command, workbook or cell that appears \
            in the screen text. No trailing period.
            """)
        var title: String

        @Guide(description: """
            The state of the work right now, in one sentence under 90 \
            characters. Say what has happened, not what to do about it.
            """)
        var summary: String

        @Guide(
            description: """
                What is still outstanding, as a todo list. Each item is one \
                imperative line under 80 characters naming something that \
                appears in the screen text. Include only work the screen text \
                shows is unfinished. Not a procedure, not a click, not a \
                keystroke.
                """,
            .count(1...5)
        )
        var todo: [String]
    }

    /// Deliberately not `guidanceInstructions` with the word "stuck" swapped
    /// out. That prompt's entire frame is that a failure exists and must be
    /// repaired, and a model held to it on a healthy screen manufactures a
    /// problem to solve. This one has to be allowed to say the work is fine.
    private static let briefingInstructions = """
        You describe what someone at their Mac is working on, in a small \
        overlay card they asked for and are reading right now.

        Everything you write must be grounded in the screen text you are given. \
        Name the actual cell, file, flag or command from that text. If the text \
        does not tell you something, do not supply it from memory, and do not \
        guess at what they intend beyond what is written.

        Nothing is necessarily wrong. If the work is proceeding normally, say \
        so plainly; do not invent a problem, a risk or a correction to justify \
        the card. Only call something an error if the screen text shows it \
        failing.

        The todo is what the screen text shows is not finished yet: a command \
        still running, a cell still empty, a step named in the output that has \
        not happened. If everything visible is complete, say that in one item \
        rather than padding the list.

        Describe the work, never the mechanism. Never write a keyboard \
        shortcut, a menu path, a button name, or an instruction to open or \
        switch to an application. Never explain what you are doing and never \
        greet them.

        You do not control the machine, so never claim to have done anything.
        """

    func briefing(for brief: ContextBrief) async throws -> Guidance? {
        let answer = try await Self.generate(
            BriefingAnswer.self,
            instructions: Self.briefingInstructions,
            prompt: Self.prompt(for: brief),
            options: Self.briefingOptions
        )

        return GuidanceDraft(
            title: answer.title,
            diagnosis: answer.summary,
            steps: answer.todo
        )
        .card(
            source: brief.source,
            writer: name,
            maximumSteps: GuidanceDraft.maximumBriefingSteps
        )
    }

    // MARK: - Generation

    /// One request, with a single retry if the model produces something that
    /// does not fit the schema.
    ///
    /// The retry is not defensive padding. Both tiers sample greedily, which
    /// makes a decode failure deterministic: the same screen would fail on
    /// every poll tick, forever. Re-asking with sampling on a fixed seed gives
    /// the model a different path to a valid answer while keeping the whole
    /// thing reproducible for the probe.
    private static func generate<Content: Generable>(
        _ type: Content.Type,
        instructions: String,
        prompt: String,
        options: GenerationOptions
    ) async throws -> Content {
        // A fresh session per call on purpose. Reusing one would accumulate a
        // transcript of every screen the user has visited, which grows the
        // prompt without bound and lets an earlier screen colour this answer.
        func ask(_ options: GenerationOptions) async throws -> Content {
            try await LanguageModelSession(instructions: instructions)
                .respond(to: prompt, generating: type, options: options)
                .content
        }

        do {
            return try await ask(options)
        } catch let error as LanguageModelSession.GenerationError {
            guard case .decodingFailure = error else { throw describe(error) }

            var retry = options
            retry.sampling = .random(top: 8, seed: 0)

            do {
                return try await ask(retry)
            } catch let retryError as LanguageModelSession.GenerationError {
                throw describe(retryError)
            }
        }
    }

    // MARK: - Errors

    /// `GenerationError` describes itself in terms of sessions and schemas.
    /// Only a few of its cases mean anything actionable here, and the rest are
    /// worth collapsing rather than surfacing verbatim.
    private static func describe(
        _ error: LanguageModelSession.GenerationError
    ) -> GuidanceError {
        let reason =
            switch error {
            case .exceededContextWindowSize:
                "Context was too long for the model"
            case .assetsUnavailable:
                "Model assets are unavailable"
            case .guardrailViolation:
                "The screen tripped the model's safety guardrail"
            case .rateLimited:
                "Rate limited by the system model"
            case .concurrentRequests:
                "Overlapping requests to the system model"
            case .decodingFailure:
                "Model returned something that did not fit the schema"
            case .refusal:
                "Model refused to answer"
            case .unsupportedGuide, .unsupportedLanguageOrLocale:
                "Unsupported request for the system model"
            @unknown default:
                error.localizedDescription
            }
        return GuidanceError(reason: reason)
    }

    // MARK: - Prompt

    /// Both tiers see exactly the same prompt. If triage says the terminal's
    /// last line is a failure, the guidance call needs that same last line to
    /// act on, and any divergence here would show up as advice about something
    /// that was never on screen.
    private static func prompt(for brief: ContextBrief) -> String {
        var lines = ["Application: \(brief.appName)"]
        if let title = brief.windowTitle, !title.isEmpty {
            lines.append("Window: \(title)")
        }
        lines.append("")
        lines.append(brief.text)
        return lines.joined(separator: "\n")
    }
}

