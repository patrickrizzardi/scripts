from __future__ import annotations

import subprocess
from collections.abc import Sequence
from dataclasses import dataclass


@dataclass(frozen=True)
class Completed:
    exit_code: int
    stdout: str


@dataclass(frozen=True)
class CompletedBytes:
    exit_code: int
    stdout: bytes


def run(argv: Sequence[str], *, stdin: str | None = None) -> Completed:
    """Run argv and capture its output as text.

    Mirrors a plain Bun.spawnSync() call, which pipes both stdout and stderr
    rather than letting them reach the terminal. stderr is captured and
    dropped here for the same reason: callers that want it on screen use
    run_inherit() instead.

    Decoding is lossy (errors="replace") because some of these commands can
    emit non-UTF-8 bytes -- a binary hunk in a diff, a mislabelled filename --
    and a hard UnicodeDecodeError there would take down the whole menu.
    """
    result = subprocess.run(list(argv), input=stdin, capture_output=True, text=True, errors="replace", check=False)
    return Completed(result.returncode, result.stdout)


def run_bytes(argv: Sequence[str], *, stdin: bytes | None = None) -> CompletedBytes:
    """Byte-oriented run(), for piping binary payloads between processes.

    `git archive | tar -x` is not text: decoding the tarball to str and back
    would corrupt it, so this variant keeps stdout as raw bytes.
    """
    result = subprocess.run(list(argv), input=stdin, capture_output=True, check=False)
    return CompletedBytes(result.returncode, result.stdout)


def run_inherit(argv: Sequence[str], *, stdin: str | None = None) -> int:
    """Run argv with its output going straight to the terminal.

    The equivalent of Bun's `{ stdout: "inherit" }` — used where the child's
    own formatting (df, ss, colordiff) is the point and re-printing captured
    output would strip its colors.
    """
    result = subprocess.run(list(argv), input=stdin, text=True, check=False)
    return result.returncode


def sh(script: str) -> Completed:
    """Run a shell snippet and capture its output.

    Kept for the handful of places that genuinely need a pipeline (`lscpu |
    grep | cut | sed`) rather than a single argv.
    """
    return run(["sh", "-c", script])
