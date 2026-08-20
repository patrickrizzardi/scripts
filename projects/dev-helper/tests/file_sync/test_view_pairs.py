from dev_helper.commands.file_sync.config import SyncPair
from dev_helper.commands.file_sync.view_pairs import format_pairs_list


def test_numbers_each_pair_as_n_source_arrow_target() -> None:
    result = format_pairs_list([SyncPair("/src/a", "/dest/a"), SyncPair("/src/b", "/dest/b")])
    assert result == ["1. /src/a -> /dest/a", "2. /src/b -> /dest/b"]


def test_returns_an_empty_list_for_no_pairs() -> None:
    assert format_pairs_list([]) == []
