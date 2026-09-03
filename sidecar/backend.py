"""Model backends for the sidecar.

`StubBackend` exists so the whole path -- Swift provider, HTTP, prompt, parsing
-- can be exercised before any weights are on disk. It answers from the screen
text rather than returning a fixed string, so a wiring mistake that drops the
brief still shows up as a wrong answer.
"""

from __future__ import annotations

import json
import threading
from typing import Protocol


class Backend(Protocol):
    name: str

    def complete(self, system: str, user: str, max_tokens: int) -> str: ...


class StubBackend:
    """Answers without a model, for testing the plumbing."""

    name = "stub"

    def complete(self, system: str, user: str, max_tokens: int) -> str:
        del system, max_tokens

        # Echo back something derived from the input. If the brief failed to
        # arrive, or arrived empty, the caller sees that instead of a plausible
        # looking constant.
        lines = [line.strip() for line in user.splitlines() if line.strip()]
        last = lines[-1] if lines else "(no screen text reached the sidecar)"

        return json.dumps(
            {
                "title": "Stub answer, no model loaded",
                "diagnosis": f"Last line of the brief was: {last[:80]}",
                "steps": [f"Received {len(user)} characters of screen text"],
            }
        )


class MLXBackend:
    """A local model via mlx-lm.

    Loading is eager and happens before the server binds a port, so a
    successful connection means the model is ready. The alternative, a lazily
    loading server, turns a 30 second load into a mystery timeout on whichever
    unlucky screen event arrives first.
    """

    def __init__(self, model_id: str) -> None:
        from mlx_lm import load
        from mlx_lm.sample_utils import make_sampler

        self.name = model_id
        self._model, self._tokenizer = load(model_id)

        # Temperature 0. Tier 2 samples greedily, and the two tiers have to be
        # comparable when the probe runs the same fixtures through both.
        self._sampler = make_sampler(temp=0.0)

        # mlx generation is not safe to run concurrently, and the engine can
        # issue a new request while an earlier one is still going.
        self._lock = threading.Lock()

    def complete(self, system: str, user: str, max_tokens: int) -> str:
        from mlx_lm import generate

        messages = [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ]

        # Qwen3 emits a reasoning block unless thinking is switched off, which
        # costs seconds the overlay does not have. `parse_draft` strips one
        # anyway, for models whose template ignores this.
        try:
            rendered = self._tokenizer.apply_chat_template(
                messages, add_generation_prompt=True, enable_thinking=False
            )
        except TypeError:
            rendered = self._tokenizer.apply_chat_template(
                messages, add_generation_prompt=True
            )

        with self._lock:
            return generate(
                self._model,
                self._tokenizer,
                prompt=rendered,
                max_tokens=max_tokens,
                sampler=self._sampler,
                verbose=False,
            )


def make_backend(model_id: str) -> Backend:
    if model_id == "stub":
        return StubBackend()
    return MLXBackend(model_id)
