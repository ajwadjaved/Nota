import Foundation

/// What a fixture is allowed to produce.
enum Expectation: String {
    /// Must not reach a model at all. Checked without one, so these still run
    /// when Apple Intelligence is off.
    case noBrief = "no brief"
    /// A brief is built, but triage has to decide the user is fine.
    case quiet = "quiet"
    /// Triage says yes and a card comes out of it.
    case guidance = "guidance"
}

struct Fixture {
    var name: String
    var expectation: Expectation
    var context: ScreenContext
}

private func ghostty(_ buffer: String, title: String = "~/Dev/Nota") -> ScreenContext {
    ScreenContext(
        app: AppIdentity(name: "Ghostty", bundleID: "com.mitchellh.ghostty", pid: 1),
        windowTitle: title,
        focused: FocusedElement(role: "AXTextArea", value: buffer)
    )
}

private func excel(_ facts: [(String, String)], workbook: String = "Q3-Budget.xlsx")
    -> ScreenContext
{
    ScreenContext(
        app: AppIdentity(name: "Microsoft Excel", bundleID: "com.microsoft.Excel", pid: 2),
        windowTitle: workbook,
        appFacts: facts.map { AppFact(label: $0.0, value: $0.1) }
            + [AppFact(label: "Workbook", value: workbook)]
    )
}

/// The suite exists for one reason: triage is deliberately biased toward
/// silence, and that bias is the first thing to break when the prompt is
/// edited. Most of these fixtures are therefore negative cases.
enum Fixtures {
    static let all: [Fixture] = [
        // MARK: Should produce guidance

        Fixture(
            name: "terminal / missing scheme",
            expectation: .guidance,
            context: ghostty(
                """
                ~/Dev/Nota main
                > xcodebuild -scheme Notta build
                xcodebuild: error: The project named "Nota" does not contain a scheme named "Notta".
                The "-list" option can be used to find the names of the schemes in the project.
                ~/Dev/Nota main
                >
                """
            )
        ),

        Fixture(
            name: "terminal / command not found",
            expectation: .guidance,
            context: ghostty(
                """
                ~/Dev/Nota main
                > xcodegen generate
                zsh: command not found: xcodegen
                ~/Dev/Nota main
                >
                """
            )
        ),

        Fixture(
            name: "excel / #DIV/0!",
            expectation: .guidance,
            context: excel([
                ("Cell", "$D$14"),
                ("Formula", "=SUM(Sheet2!B7:B20)/C14"),
                ("Value", "#DIV/0!"),
                ("Sheet", "Summary"),
            ])
        ),

        Fixture(
            name: "excel / #REF! after a deleted range",
            expectation: .guidance,
            context: excel([
                ("Cell", "$D$14"),
                ("Formula", "=SUM(#REF!)"),
                ("Value", "#REF!"),
                ("Sheet", "Summary"),
            ])
        ),

        // MARK: Must stay quiet

        Fixture(
            name: "terminal / clean commands",
            expectation: .quiet,
            context: ghostty(
                """
                ~/Dev/Nota main
                > git status --short
                ~/Dev/Nota main
                > ls
                README.md  app  install.sh  probe  project.yml  sidecar
                ~/Dev/Nota main
                >
                """
            )
        ),

        Fixture(
            name: "terminal / long successful build",
            expectation: .quiet,
            context: ghostty(
                """
                > xcodebuild -scheme Nota build
                CompileSwiftSources normal arm64 com.apple.xcode.tools.swift.compiler
                    cd /Users/me/Dev/Nota
                    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
                Ld /Users/me/Library/Developer/Xcode/DerivedData/Nota/Build/Nota.app
                CodeSign /Users/me/Library/Developer/Xcode/DerivedData/Nota/Build/Nota.app
                ** BUILD SUCCEEDED **
                ~/Dev/Nota main
                >
                """
            )
        ),

        Fixture(
            name: "terminal / idle prompt",
            expectation: .quiet,
            context: ghostty(
                """
                ~/Dev/Nota main
                >
                """
            )
        ),

        Fixture(
            name: "terminal / non-blocking deprecation warning",
            expectation: .quiet,
            context: ghostty(
                """
                > npm install
                npm warn deprecated inflight@1.0.6: This module is not supported.
                npm warn deprecated glob@7.2.3: Glob versions prior to v9 are no longer supported.
                added 214 packages, and audited 215 packages in 3s
                ~/Dev/site main
                >
                """
            )
        ),

        // MARK: Must not reach a model

        // A healthy cell is gated out by `ExcelError`, not by triage. It used
        // to be a `.quiet` case and triage failed it: the model decided
        // `=SUM(B1:B3)` was missing a parenthesis and invented a fix.
        Fixture(
            name: "excel / healthy formula",
            expectation: .noBrief,
            context: excel([
                ("Cell", "$B$4"),
                ("Formula", "=SUM(B1:B3)"),
                ("Value", "1284"),
                ("Sheet", "Summary"),
            ])
        ),

        Fixture(
            name: "excel / empty cell",
            expectation: .noBrief,
            context: excel([
                ("Cell", "$F$22"),
                ("Sheet", "Summary"),
            ])
        ),

        Fixture(
            name: "excel / text value that merely starts with a hash",
            expectation: .noBrief,
            context: excel([
                ("Cell", "$A$2"),
                ("Formula", "#1 priority for Q3"),
                ("Value", "#1 priority for Q3"),
                ("Sheet", "Notes"),
            ])
        ),

        Fixture(
            name: "teams / nothing exposed",
            expectation: .noBrief,
            context: ScreenContext(
                app: AppIdentity(
                    name: "Microsoft Teams",
                    bundleID: "com.microsoft.teams2",
                    pid: 3
                ),
                windowTitle: "Chat | Microsoft Teams",
                focused: nil
            )
        ),

        Fixture(
            name: "browser / focused element with no content",
            expectation: .noBrief,
            context: ScreenContext(
                app: AppIdentity(
                    name: "Safari",
                    bundleID: "com.apple.Safari",
                    pid: 4
                ),
                windowTitle: "Apple Developer Documentation",
                focused: FocusedElement(role: "AXWebArea")
            )
        ),
    ]
}
