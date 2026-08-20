from dev_helper.commands.file_sync.add_pairs import build_pairs_from_selection, filter_unsynced_items
from dev_helper.commands.file_sync.config import SyncPair


def test_removes_items_already_present_as_a_source_in_existing_pairs() -> None:
    existing = [SyncPair("/home/pat/plugins", "/dest/plugins")]
    assert filter_unsynced_items(["plugins", "settings.json"], "/home/pat", existing) == ["settings.json"]


def test_keeps_every_item_when_none_are_already_synced() -> None:
    items = ["plugins", "settings.json"]
    assert filter_unsynced_items(items, "/home/pat", []) == items


def test_only_matches_on_the_resolved_cwd_item_path_not_a_same_named_source_elsewhere() -> None:
    existing = [SyncPair("/other/dir/plugins", "/dest/plugins")]
    assert filter_unsynced_items(["plugins"], "/home/pat", existing) == ["plugins"]


def test_builds_one_pair_per_selected_item() -> None:
    assert build_pairs_from_selection("/home/pat", "/dest", ["plugins", "settings.json"]) == [
        SyncPair("/home/pat/plugins", "/dest/plugins"),
        SyncPair("/home/pat/settings.json", "/dest/settings.json"),
    ]
