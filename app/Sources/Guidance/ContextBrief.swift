import Foundation

/// Excel's error values, which are a closed set.
enum ExcelError {
    /// The English forms. AppleScript usually returns these regardless of UI
    /// language, but not always, hence the shape check below.
    private static let known: Set<String> = [
        "#REF!", "#DIV/0!", "#VALUE!", "#NAME?", "#N/A",
        "#NULL!", "#NUM!", "#SPILL!", "#CALC!", "#BLOCKED!",
        "#CONNECT!", "#FIELD!", "#UNKNOWN!", "#GETTING_DATA",
    ]

    static func isError(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if known.contains(trimmed) { return true }

        // Localised builds translate the word inside the marker but keep the
        // leading '#' and the trailing '!' or '?', so the shape survives even
        // when the spelling does not.
        return trimmed.hasPrefix("#")
            && (trimmed.hasSuffix("!") || trimmed.hasSuffix("?"))
            && trimmed.count <= 16
    }
}

/// What kind of app the context came from. This drives how the raw reader
/// output is shaped, because "the useful part" sits in a different place for
/// each one: the tail of a terminal buffer, the active cell of a spreadsheet.
enum ContextKind: String {
    case terminal
    case spreadsheet
    case generic
}

/// A `ScreenContext` flattened into the text a model actually sees, plus a
/// fingerprint of that text.
///
/// The fingerprint is the whole reason this type exists. The readers run on a
/// timer and return a near-identical `ScreenContext` every tick, but only a
/// change in the *text we would send* is worth waking a model for. Comparing
/// briefs rather than contexts means moving the mouse, or a clock ticking in a
/// window title, does not count as an event.
struct ContextBrief: Equatable {
    var kind: ContextKind
    var appName: String
    var windowTitle: String?
    /// Where the guidance applies, e.g. "Microsoft Excel - Q3-Budget.xlsx".
    var source: String
    var text: String

    /// Everything the model is shown, so two briefs that would produce the same
    /// answer compare equal. Deliberately excludes timestamps and read duration.
    var fingerprint: String { "\(kind.rawValue)|\(source)|\(text)" }

    static func == (lhs: ContextBrief, rhs: ContextBrief) -> Bool {
        lhs.fingerprint == rhs.fingerprint
    }
}

extension ContextBrief {
    /// Apps the prototype will act on.
    ///
    /// Chosen empirically rather than by taste: these two are the ones that
    /// hand over real text. Browsers and Teams expose a focused element with
    /// nothing in it, so they would burn a model call to describe an empty
    /// room. They come back once the OCR path exists.
    static let supportedBundleIDs: Set<String> = [
        "com.mitchellh.ghostty",
        "com.microsoft.Excel",
    ]

    static func kind(for bundleID: String?) -> ContextKind? {
        switch bundleID {
        case "com.mitchellh.ghostty": return .terminal
        case "com.microsoft.Excel": return .spreadsheet
        default: return nil
        }
    }

    /// Terminal buffers arrive whole. A long build log would blow the context
    /// window and bury the part that matters, so the tail wins.
    private static let terminalLineLimit = 40
    private static let textCharacterLimit = 2_000

    /// Returns `nil` when there is nothing worth asking about, which is the
    /// common case and must stay cheap.
    static func make(from context: ScreenContext) -> ContextBrief? {
        guard let kind = kind(for: context.app.bundleID) else { return nil }

        let text: String? =
            switch kind {
            case .terminal: terminalText(context)
            case .spreadsheet: spreadsheetText(context)
            case .generic: genericText(context)
            }

        guard let text, !text.isEmpty else { return nil }

        return ContextBrief(
            kind: kind,
            appName: context.app.name,
            windowTitle: context.windowTitle,
            source: source(for: context, kind: kind),
            text: String(text.prefix(textCharacterLimit))
        )
    }

    // MARK: - Per-kind shaping

    private static func terminalText(_ context: ScreenContext) -> String? {
        guard let buffer = context.focused?.value ?? context.focused?.selectedText
        else { return nil }

        // Trailing blank lines are just the unused rows below the prompt; they
        // would eat the line budget and push the actual error out of view.
        var lines = buffer.components(separatedBy: .newlines)
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }
        guard !lines.isEmpty else { return nil }

        let tail = lines.suffix(terminalLineLimit).joined(separator: "\n")
        return "Terminal, most recent output last:\n\(tail)"
    }

    private static func spreadsheetText(_ context: ScreenContext) -> String? {
        // The scripted reader gives the formula and the computed value, which is
        // strictly better than anything AX or a screenshot would say about the
        // same cell.
        guard !context.appFacts.isEmpty else { return nil }

        // A cell only reaches a model when its computed value is one of Excel's
        // error values. That is a closed set and a string comparison answers it,
        // so asking a model would be the wrong tier.
        //
        // It also removes the worst failure mode observed here. Shown a
        // perfectly good `=SUM(B1:B3)` returning 1284, triage claimed the
        // formula was missing a closing parenthesis and invented a repair for
        // it. A healthy cell is not evidence of anything, and the model has no
        // way to know what the number was supposed to be.
        //
        // The cost is that a formula which is wrong but computes cleanly stays
        // invisible. Catching that needs the whole sheet, not one cell.
        guard let value = context.appFacts.first(where: { $0.label == "Value" })?.value,
              ExcelError.isError(value)
        else { return nil }

        let facts = context.appFacts
            .map { "\($0.label): \($0.value)" }
            .joined(separator: "\n")
        return "Spreadsheet, active cell:\n\(facts)"
    }

    private static func genericText(_ context: ScreenContext) -> String? {
        guard let focused = context.focused else { return nil }

        let fields: [(String, String?)] = [
            ("Control", focused.role),
            ("Label", focused.title),
            ("Content", focused.value),
            ("Placeholder", focused.placeholder),
            ("Selected", focused.selectedText),
        ]

        let described = fields
            .compactMap { label, value in value.map { "\(label): \($0)" } }
            .joined(separator: "\n")

        return described.isEmpty ? nil : described
    }

    private static func source(for context: ScreenContext, kind: ContextKind) -> String {
        // For a spreadsheet the workbook name is the honest location, and the
        // window title is often a truncated version of the same thing.
        if kind == .spreadsheet,
           let workbook = context.appFacts.first(where: { $0.label == "Workbook" })?.value {
            let sheet = context.appFacts.first(where: { $0.label == "Sheet" })?.value
            let where_ = [workbook, sheet].compactMap { $0 }.joined(separator: " - ")
            return "\(context.app.name) - \(where_)"
        }

        if let title = context.windowTitle, !title.isEmpty {
            return "\(context.app.name) - \(title)"
        }

        return context.app.name
    }
}
