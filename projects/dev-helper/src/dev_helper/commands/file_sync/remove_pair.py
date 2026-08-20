from __future__ import annotations

from dev_helper.commands.file_sync.config import SyncPair
from dev_helper.commands.file_sync.view_pairs import format_pairs_list, view_pairs
from dev_helper.utils.print import print_success, print_warning
from dev_helper.utils.prompt import Option, confirm_prompt, select_prompt


def remove_pair_at(pairs: list[SyncPair], index: int) -> list[SyncPair]:
    if index < 1 or index > len(pairs):
        return pairs
    return [pair for position, pair in enumerate(pairs) if position != index - 1]


def remove_pair_flow(pairs: list[SyncPair]) -> list[SyncPair]:
    if not pairs:
        print_warning("No sync pairs configured.")
        return pairs

    view_pairs(pairs)
    lines = format_pairs_list(pairs)
    choice = select_prompt(
        "Select the pair to remove",
        [Option(value=str(index + 1), label=line) for index, line in enumerate(lines)],
    )

    index = int(choice)
    target = pairs[index - 1]
    if not confirm_prompt(f"Remove {target.source} -> {target.target}?"):
        return pairs

    updated = remove_pair_at(pairs, index)
    print_success("Pair removed.")
    if not updated:
        print_warning("All pairs removed. Consider stopping the service.")
    return updated
