import AppKit
import Foundation

enum AppReadResult {
    /// No scripted reader exists for this app; the AX tree or OCR is all we get.
    case unavailable
    /// The user declined the Automation prompt for this app.
    case notPermitted
    case facts([AppFact])
    case failed(String)
}

/// Apps that expose a real scripting dictionary let us skip vision entirely.
/// Reading `formula of active cell` costs a few dozen tokens and is exactly
/// right; reading it off a screenshot costs thousands and can be wrong.
protocol ScriptableAppReader {
    static var bundleIDs: Set<String> { get }
    @MainActor static func read() -> AppReadResult
}

enum AppReaders {
    private static let all: [any ScriptableAppReader.Type] = [ExcelReader.self]

    @MainActor
    static func read(bundleID: String?) -> AppReadResult {
        guard let bundleID,
              let reader = all.first(where: { $0.bundleIDs.contains(bundleID) })
        else { return .unavailable }
        return reader.read()
    }
}

// MARK: - Excel

enum ExcelReader: ScriptableAppReader {
    static let bundleIDs: Set<String> = ["com.microsoft.Excel"]

    /// Every lookup is individually wrapped in `try`, because an empty cell, an
    /// unsaved workbook or a multi-cell selection each make a different one of
    /// these fail, and a single failure must not lose the rest.
    private static let source = """
    tell application "Microsoft Excel"
        set out to ""
        try
            set c to active cell
            try
                set out to out & "Cell=" & (get address of c) & linefeed
            end try
            try
                set out to out & "Formula=" & (get formula of c) & linefeed
            end try
            try
                set out to out & "Value=" & ((get value of c) as string) & linefeed
            end try
        end try
        try
            set out to out & "Selection=" & (get address of selection) & linefeed
        end try
        try
            set out to out & "Sheet=" & (name of active sheet) & linefeed
        end try
        try
            set out to out & "Workbook=" & (name of active workbook) & linefeed
        end try
        return out
    end tell
    """

    @MainActor
    static func read() -> AppReadResult {
        // Only ever called when Excel is already frontmost. Calling it blind
        // would be worse than useless: `tell application` launches the app.
        guard let script = NSAppleScript(source: source) else {
            return .failed("could not compile script")
        }

        var error: NSDictionary?
        let output = script.executeAndReturnError(&error)

        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            // -1743 is "not authorised to send Apple events", i.e. the user
            // said no to the Automation prompt.
            if code == -1743 {
                return .notPermitted
            }
            let message = error[NSAppleScript.errorMessage] as? String
                ?? "AppleScript error \(code)"
            return .failed(message)
        }

        guard let text = output.stringValue, !text.isEmpty else {
            return .facts([])
        }

        let facts = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> AppFact? in
                guard let split = line.firstIndex(of: "=") else { return nil }
                let label = String(line[line.startIndex..<split])
                let value = String(line[line.index(after: split)...])
                guard !value.isEmpty else { return nil }
                return AppFact(label: label, value: value)
            }

        return .facts(facts)
    }
}
