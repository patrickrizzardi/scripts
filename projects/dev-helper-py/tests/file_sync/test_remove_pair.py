from dev_helper.commands.file_sync.config import SyncPair
from dev_helper.commands.file_sync.remove_pair import remove_pair_at

PAIRS = [SyncPair("/src/a", "/dest/a"), SyncPair("/src/b", "/dest/b")]


def test_removes_the_pair_at_the_given_1_based_index() -> None:
    assert remove_pair_at(PAIRS, 1) == [SyncPair("/src/b", "/dest/b")]


def test_returns_the_list_unchanged_for_an_out_of_range_index() -> None:
    assert remove_pair_at(PAIRS, 99) == PAIRS


def test_returns_the_list_unchanged_for_index_0() -> None:
    assert remove_pair_at(PAIRS, 0) == PAIRS


# WHY: remove_pair_flow() decides whether to rewrite pairs.conf and restart the
# watcher by checking `updated is not pairs` -- identity, not equality. An
# out-of-range index must hand back the very same list object, or every
# rejected removal would trigger a pointless config write and service restart.
def test_returns_the_identical_list_object_when_the_index_is_rejected() -> None:
    assert remove_pair_at(PAIRS, 99) is PAIRS
