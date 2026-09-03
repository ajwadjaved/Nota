"""Tests for the pure parts of the sidecar.

Run with `./.venv/bin/python test_prompt.py`. No model and no network needed,
which is the point: `parse_draft` is what breaks when a local model has a bad
day, and it has to be verifiable independently of one.
"""

from __future__ import annotations

import sys

from prompt import ParseError, build_prompt, parse_draft

FAILURES: list[str] = []


def check(label: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"PASS  {label}")
        return
    FAILURES.append(label)
    print(f"FAIL  {label}")
    if detail:
        print(f"      {detail}")


def expect_parse_error(label: str, raw: str) -> None:
    try:
        parse_draft(raw)
    except ParseError:
        print(f"PASS  {label}")
    else:
        FAILURES.append(label)
        print(f"FAIL  {label}: expected a ParseError")


GOOD = '{"title": "Fix the scheme name", "diagnosis": "No such scheme.", "steps": ["Use Kuroko"]}'


def main() -> int:
    draft = parse_draft(GOOD)
    check("clean JSON", draft["title"] == "Fix the scheme name")
    check("steps parsed", draft["steps"] == ["Use Kuroko"], repr(draft["steps"]))

    # Models wrap JSON in a fence more often than not.
    draft = parse_draft(f"```json\n{GOOD}\n```")
    check("fenced JSON", draft["title"] == "Fix the scheme name")

    # Qwen3 reasons out loud unless told not to, and the template does not
    # always honour that.
    draft = parse_draft(f"<think>The user typed the wrong name.</think>\n{GOOD}")
    check("thinking block stripped", draft["title"] == "Fix the scheme name")

    # Prose on either side is common.
    draft = parse_draft(f"Here is the card you asked for:\n{GOOD}\nHope that helps.")
    check("surrounding prose", draft["title"] == "Fix the scheme name")

    # The reason `_first_json_object` counts depth instead of using a regex: a
    # brace inside a string value is normal in this domain.
    nested = (
        '{"title": "Fix IFERROR", "diagnosis": "Braces {like this} appear.", '
        '"steps": ["Set D14 to =IFERROR(SUM(B1:B3), \\"\\")"]}'
    )
    draft = parse_draft(nested)
    check("brace inside a string value", draft["diagnosis"] == "Braces {like this} appear.")
    check(
        "escaped quotes survive",
        draft["steps"] == ['Set D14 to =IFERROR(SUM(B1:B3), "")'],
        repr(draft["steps"]),
    )

    # A single string where an array was asked for is worth accepting.
    draft = parse_draft('{"title": "T", "diagnosis": "D", "steps": "Just one"}')
    check("string coerced to a list", draft["steps"] == ["Just one"])

    # Missing diagnosis is survivable; the card just leads with the title.
    draft = parse_draft('{"title": "T", "steps": ["S"]}')
    check("absent diagnosis becomes empty", draft["diagnosis"] == "")

    # Blank and non-string steps are dropped rather than shown.
    draft = parse_draft('{"title": "T", "diagnosis": "D", "steps": ["  ", "Real", 7, null]}')
    check("junk steps dropped", draft["steps"] == ["Real"], repr(draft["steps"]))

    expect_parse_error("no JSON at all", "I could not work out what is wrong.")
    expect_parse_error("unterminated object", '{"title": "T", "steps": [')
    expect_parse_error("missing title", '{"diagnosis": "D", "steps": ["S"]}')
    expect_parse_error("blank title", '{"title": "   ", "steps": ["S"]}')
    expect_parse_error("array instead of object", '["title", "steps"]')
    expect_parse_error("steps is a number", '{"title": "T", "steps": 3}')

    # The brief must reach the model intact; a dropped window title or body is
    # the kind of wiring bug that looks like a bad model.
    rendered = build_prompt(
        {"appName": "Ghostty", "windowTitle": "~/Dev/Kuroko", "text": "zsh: command not found"}
    )
    check("prompt names the app", "Application: Ghostty" in rendered)
    check("prompt names the window", "Window: ~/Dev/Kuroko" in rendered)
    check("prompt carries the text", rendered.endswith("zsh: command not found"))

    rendered = build_prompt({"appName": "Ghostty", "text": "x"})
    check("window line omitted when absent", "Window:" not in rendered)

    print()
    if FAILURES:
        print(f"{len(FAILURES)} failed: {', '.join(FAILURES)}")
        return 1
    print("all passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
