from __future__ import annotations

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class SyncPair:
    source: str
    target: str


def _resolve_home(home: str | None) -> str:
    """Resolve the home directory at call time, not import time.

    Every path helper takes an optional `home` so the tests can point the whole
    config tree at a temp directory; passing None means "the real one".
    """
    return home if home is not None else os.environ["HOME"]


def get_config_dir(home: str | None = None) -> str:
    return os.path.join(_resolve_home(home), ".config", "rsync-sync")


def get_pairs_file_path(home: str | None = None) -> str:
    return os.path.join(get_config_dir(home), "pairs.conf")


def parse_pairs_file(content: str) -> list[SyncPair]:
    pairs: list[SyncPair] = []
    for line in content.split("\n"):
        if not line or line.startswith("#"):
            continue
        # Split on every separator but keep only the first two fields, so a
        # malformed "a|b|c" line degrades to a|b instead of being dropped.
        fields = line.split("|")
        source = fields[0]
        target = fields[1] if len(fields) > 1 else ""
        if not source or not target:
            continue
        pairs.append(SyncPair(source, target))
    return pairs


def serialize_pairs(pairs: list[SyncPair]) -> str:
    body = "\n".join(f"{pair.source}|{pair.target}" for pair in pairs)
    return body + ("\n" if pairs else "")


def read_pairs(home: str | None = None) -> list[SyncPair]:
    path = get_pairs_file_path(home)
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as handle:
        return parse_pairs_file(handle.read())


def write_pairs(pairs: list[SyncPair], home: str | None = None) -> None:
    os.makedirs(get_config_dir(home), exist_ok=True)
    with open(get_pairs_file_path(home), "w", encoding="utf-8") as handle:
        handle.write(serialize_pairs(pairs))
