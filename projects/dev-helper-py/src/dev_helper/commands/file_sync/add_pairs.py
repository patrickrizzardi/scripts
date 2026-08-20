from __future__ import annotations

import os

from dev_helper.commands.file_sync.config import SyncPair
from dev_helper.utils.print import print_error, print_header, print_info, print_warning
from dev_helper.utils.prompt import Option, multiselect_prompt, select_prompt, text_prompt


def filter_unsynced_items(items: list[str], cwd: str, existing_pairs: list[SyncPair]) -> list[str]:
    synced_sources = {pair.source for pair in existing_pairs}
    return [item for item in items if os.path.join(cwd, item) not in synced_sources]


def build_pairs_from_selection(cwd: str, target_dir: str, selected_items: list[str]) -> list[SyncPair]:
    return [SyncPair(source=os.path.join(cwd, item), target=os.path.join(target_dir, item)) for item in selected_items]


def _expand_home(path: str) -> str:
    """Expand a single leading ~ only, matching the original's /^~/ replace.

    os.path.expanduser() would also rewrite forms like ~otheruser, which this
    tool never accepted.
    """
    return os.environ["HOME"] + path[1:] if path.startswith("~") else path


def _multi_select_from_dir(existing_pairs: list[SyncPair]) -> list[SyncPair]:
    print_warning("Make sure your terminal is cd'd into the parent folder you want to sync FROM.")
    cwd = os.getcwd()
    print_info(f"Current directory: {cwd}")

    items = filter_unsynced_items(os.listdir(cwd), cwd, existing_pairs)

    if not items:
        print_error("No unsynced files or directories found in this folder.")
        return []

    selected = multiselect_prompt("Select items to sync", [Option(value=item, label=item) for item in items])

    if not selected:
        print_error("No items selected.")
        return []

    target_dir = text_prompt("Enter the target directory (e.g. ~/.claude):")
    return build_pairs_from_selection(cwd, _expand_home(target_dir), selected)


def _manual_entry(existing_pairs: list[SyncPair]) -> list[SyncPair]:
    source = _expand_home(text_prompt("Enter full source path:"))
    target = _expand_home(text_prompt("Enter full target path:"))
    if not source or not target:
        print_error("Source and target paths cannot be empty.")
        return []
    if any(pair.source == source for pair in existing_pairs):
        print_warning(f"{source} is already a synced pair.")
    return [SyncPair(source, target)]


def add_pairs_flow(existing_pairs: list[SyncPair]) -> list[SyncPair]:
    print_header("Add Sync Pairs")
    mode = select_prompt(
        "How would you like to select source(s)?",
        [
            Option(value="multi", label="Multi-select from current directory"),
            Option(value="manual", label="Enter path manually"),
        ],
    )

    return _multi_select_from_dir(existing_pairs) if mode == "multi" else _manual_entry(existing_pairs)
