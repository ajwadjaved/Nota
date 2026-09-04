#!/usr/bin/env python3
"""Tier 3: a local model that writes guidance, over HTTP on loopback.

Why a long-lived server rather than a subprocess the app spawns: loading a
27B model takes tens of seconds, and Nota is a login item that the user will
quit and relaunch. Tying the weights to the app's lifetime would pay that cost
every time. A separate process also means a crash in MLX cannot take the menu
bar app down with it.

Only ever bound to loopback. This process receives the contents of the user's
screen, and must not be reachable from the network.

Usage:
    ./.venv/bin/python server.py                     # default model
    NOTA_MODEL=stub ./.venv/bin/python server.py   # no weights needed
"""

from __future__ import annotations

import json
import os
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import prompt as prompt_module
from backend import make_backend

HOST = "127.0.0.1"
PORT = int(os.environ.get("NOTA_SIDECAR_PORT", "8765"))
MODEL = os.environ.get("NOTA_MODEL", "mlx-community/Qwen3.8-27B-4bit")
MAX_TOKENS = int(os.environ.get("NOTA_MAX_TOKENS", "300"))

# A briefing carries up to five todo items where guidance carries three, and a
# budget that truncates the JSON mid-string costs the whole answer, not the
# last item.
BRIEFING_MAX_TOKENS = int(os.environ.get("NOTA_BRIEFING_MAX_TOKENS", "500"))

# The screen text is already capped on the Swift side; this is a second bound
# so a bug there cannot hand the model an unbounded prompt.
MAX_TEXT_CHARS = 8_000

BACKEND = None


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, format: str, *args: object) -> None:
        # The default logs to stderr per request with a timestamp already in
        # the line. Keep it, but on one line and without the client address,
        # which is always loopback.
        sys.stderr.write("%s\n" % (format % args))

    # MARK: - Routing

    def do_GET(self) -> None:
        if self.path == "/health":
            self._send(
                200,
                {
                    "status": "ready",
                    "model": BACKEND.name,
                    "maxTokens": MAX_TOKENS,
                },
            )
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self) -> None:
        # Same wire format either way; the path picks the question.
        route = {
            "/guidance": (prompt_module.SYSTEM, MAX_TOKENS),
            "/briefing": (prompt_module.SYSTEM_BRIEFING, BRIEFING_MAX_TOKENS),
        }.get(self.path)

        if route is None:
            self._send(404, {"error": "not found"})
            return

        system, max_tokens = route

        try:
            brief = self._read_json()
        except ValueError as error:
            self._send(400, {"error": str(error)})
            return

        text = brief.get("text")
        if not isinstance(text, str) or not text.strip():
            self._send(400, {"error": "brief has no text"})
            return

        brief["text"] = text[:MAX_TEXT_CHARS]

        started = time.monotonic()
        try:
            raw = BACKEND.complete(
                system,
                prompt_module.build_prompt(brief),
                max_tokens,
            )
        except Exception as error:  # noqa: BLE001 - surfaced to the client
            self._send(500, {"error": f"generation failed: {error}"})
            return

        try:
            draft = prompt_module.parse_draft(raw)
        except prompt_module.ParseError as error:
            # Include what the model said. When a local model starts returning
            # prose instead of JSON, the raw output is the only useful clue,
            # and it is otherwise invisible from the Swift side.
            self._send(
                502,
                {"error": str(error), "raw": raw[:600]},
            )
            return

        draft["elapsedMs"] = round((time.monotonic() - started) * 1000)
        self._send(200, draft)

    # MARK: - Plumbing

    def _read_json(self) -> dict:
        length = self.headers.get("Content-Length")
        if length is None:
            raise ValueError("missing Content-Length")

        try:
            size = int(length)
        except ValueError as error:
            raise ValueError("bad Content-Length") from error

        if size <= 0 or size > 1_000_000:
            raise ValueError("unreasonable Content-Length")

        try:
            body = json.loads(self.rfile.read(size))
        except json.JSONDecodeError as error:
            raise ValueError(f"malformed request JSON: {error}") from error

        if not isinstance(body, dict):
            raise ValueError("request body is not an object")

        return body

    def _send(self, status: int, payload: dict) -> None:
        encoded = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)


def main() -> int:
    global BACKEND

    print(f"loading {MODEL}...", flush=True)
    started = time.monotonic()
    try:
        BACKEND = make_backend(MODEL)
    except Exception as error:  # noqa: BLE001 - a startup failure must be readable
        print(f"failed to load {MODEL}: {error}", file=sys.stderr)
        if "not found" in str(error).lower() or "does not exist" in str(error).lower():
            print(
                "\nThe weights are not on disk. Run sidecar/setup.sh, which "
                "prints the download command,\nor start with NOTA_MODEL=stub "
                "to test everything except the model.",
                file=sys.stderr,
            )
        return 1

    # Binding only after the model is up means a successful connection implies
    # readiness, and the Swift side needs no "still loading" state.
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(
        f"ready in {time.monotonic() - started:.1f}s, "
        f"listening on http://{HOST}:{PORT}",
        flush=True,
    )

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("stopping", flush=True)
    finally:
        server.server_close()

    return 0


if __name__ == "__main__":
    sys.exit(main())
