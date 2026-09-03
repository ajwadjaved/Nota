"""Prompt construction and response parsing for Tier 3.

Deliberately free of any MLX import so it can be tested without weights, which
matters because the parsing is where a local model will actually hurt you: it
will wrap JSON in prose, in a fence, or in a thinking block, and it will do so
inconsistently.

The rules below mirror `guidanceInstructions` in FoundationModelsProvider.swift.
They are duplicated rather than shared because the two run in different
languages, but they are not independent: they are the product's definition of
what advice may look like, and changing one without the other is a bug. The
probe runs both providers over the same fixtures for exactly that reason.
"""

from __future__ import annotations

import json
import re
from typing import Any

# No literal examples anywhere in here. A small model returns a sample answer
# verbatim; see the note in FoundationModelsProvider.swift. A 27B is less prone
# to it, but the instruction is no worse for being safe.
SYSTEM = """\
You help someone who is stuck at their Mac, in a small overlay card they read \
out of the corner of their eye.

Everything you write must be grounded in the screen text you are given. Name \
the actual cell, file, flag or command from that text. If the text does not \
tell you something, do not supply it from memory.

Describe the change to make, never the mechanism for making it. The person \
already knows how to use their own tools, and is already in the application \
you are looking at.

This means you must never write a keyboard shortcut, a menu path, a button \
name, a dialog name, or an instruction to open or switch to an application. \
Never write an installation command unless that exact command appears in the \
screen text. State which value, formula, argument or file should change and \
what it should become.

Never explain what you are doing, never greet them, and never suggest they \
read documentation or search the web. Assume they are competent and just \
missing one fact.

You do not control the machine, so never claim to have done anything. \
Describe what they should do.

Reply with a single JSON object and nothing else, with exactly these keys:
  "title":     the goal as one short imperative phrase, at most 60 characters,
               naming the specific thing that is wrong using an identifier that
               appears in the screen text, with no trailing period
  "diagnosis": what is actually wrong, one sentence under 90 characters,
               stating the cause rather than the fix
  "steps":     an array of one to three strings, each an imperative change
               under 80 characters, each naming something that appears in the
               screen text\
"""


def build_prompt(brief: dict[str, Any]) -> str:
    """Render a brief the way the Swift side renders it for Tier 2.

    Both tiers must see the same description of the screen. If triage decided
    the last line of a terminal is a failure, the writer needs that same last
    line, and any divergence shows up as advice about something that was never
    on screen.
    """
    lines = [f"Application: {brief.get('appName', 'Unknown')}"]

    window = brief.get("windowTitle")
    if window:
        lines.append(f"Window: {window}")

    lines.append("")
    lines.append(brief.get("text", ""))
    return "\n".join(lines)


_THINK = re.compile(r"<think>.*?</think>", re.DOTALL)
_FENCE = re.compile(r"^\s*```(?:json)?\s*|\s*```\s*$", re.MULTILINE)


def _first_json_object(text: str) -> str | None:
    """Return the first balanced ``{...}`` span.

    A regex cannot do this correctly once a value contains a brace, and model
    output does contain braces: formulas, shell snippets and JSON-in-JSON all
    turn up. Counting depth while ignoring braces inside strings is the only
    version that survives real output.
    """
    start = text.find("{")
    if start == -1:
        return None

    depth = 0
    in_string = False
    escaped = False

    for index in range(start, len(text)):
        char = text[index]

        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue

        if char == '"':
            in_string = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[start : index + 1]

    return None


class ParseError(ValueError):
    """The model produced something that is not a usable draft."""


def parse_draft(raw: str) -> dict[str, Any]:
    """Pull a draft out of whatever the model actually emitted.

    Returns the three fields with their expected types. Enforcing the step cap
    and rejecting implausible steps is the Swift side's job, in GuidanceDraft,
    so that Tier 2 and Tier 3 are held to identical standards.
    """
    text = _THINK.sub("", raw)
    text = _FENCE.sub("", text)

    candidate = _first_json_object(text)
    if candidate is None:
        raise ParseError("no JSON object in model output")

    try:
        parsed = json.loads(candidate)
    except json.JSONDecodeError as error:
        raise ParseError(f"malformed JSON: {error}") from error

    if not isinstance(parsed, dict):
        raise ParseError("model returned JSON that is not an object")

    title = parsed.get("title")
    diagnosis = parsed.get("diagnosis")
    steps = parsed.get("steps")

    if not isinstance(title, str) or not title.strip():
        raise ParseError("missing title")

    # A single string where an array was asked for is common enough to accept
    # rather than discard an otherwise good answer.
    if isinstance(steps, str):
        steps = [steps]
    if not isinstance(steps, list):
        raise ParseError("steps is not a list")

    return {
        "title": title.strip(),
        "diagnosis": diagnosis.strip() if isinstance(diagnosis, str) else "",
        "steps": [step.strip() for step in steps if isinstance(step, str) and step.strip()],
    }
