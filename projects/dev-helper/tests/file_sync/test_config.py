import os
from pathlib import Path

from dev_helper.commands.file_sync.config import (
    SyncPair,
    get_pairs_file_path,
    parse_pairs_file,
    read_pairs,
    serialize_pairs,
    write_pairs,
)


def test_parses_source_target_lines() -> None:
    assert parse_pairs_file("/src/a|/dest/a\n/src/b|/dest/b\n") == [
        SyncPair("/src/a", "/dest/a"),
        SyncPair("/src/b", "/dest/b"),
    ]


def test_skips_blank_lines_and_comment_lines() -> None:
    assert parse_pairs_file("\n#comment\n/src/a|/dest/a\n") == [SyncPair("/src/a", "/dest/a")]


def test_serialize_pairs_round_trips_through_parse_pairs_file() -> None:
    pairs = [SyncPair("/src/a", "/dest/a"), SyncPair("/src/b", "/dest/b")]
    assert parse_pairs_file(serialize_pairs(pairs)) == pairs


def test_serialize_pairs_of_nothing_is_empty_not_a_bare_newline() -> None:
    assert serialize_pairs([]) == ""


def test_read_pairs_returns_empty_list_when_pairs_conf_does_not_exist(tmp_path: Path) -> None:
    assert read_pairs(str(tmp_path)) == []


def test_write_pairs_then_read_pairs_round_trips(tmp_path: Path) -> None:
    pairs = [SyncPair("/src/a", "/dest/a")]
    write_pairs(pairs, str(tmp_path))
    assert read_pairs(str(tmp_path)) == pairs


def test_get_pairs_file_path_resolves_under_config_rsync_sync(tmp_path: Path) -> None:
    assert get_pairs_file_path(str(tmp_path)) == os.path.join(str(tmp_path), ".config", "rsync-sync", "pairs.conf")
