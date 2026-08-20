from __future__ import annotations

from dev_helper.commands.file_sync.config import SyncPair
from dev_helper.utils.print import print_header, print_menu_item, print_warning


def format_pairs_list(pairs: list[SyncPair]) -> list[str]:
    return [f"{index + 1}. {pair.source} -> {pair.target}" for index, pair in enumerate(pairs)]


def view_pairs(pairs: list[SyncPair]) -> None:
    if not pairs:
        print_warning("No sync pairs configured.")
        return
    print_header("Current Sync Pairs")
    for line in format_pairs_list(pairs):
        # Rejoining the tail keeps paths that themselves contain ". " intact --
        # only the leading list number is peeled off for separate coloring.
        number, *rest = line.split(". ")
        print_menu_item(f"{number}.", ". ".join(rest))
