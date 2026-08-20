from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass

from dev_helper.commands.disk_usage import show_disk_usage
from dev_helper.commands.file_sync import setup_file_sync
from dev_helper.commands.find_files import find_files_by_name
from dev_helper.commands.git_diff import compare_git_branches
from dev_helper.commands.network import show_network_connections
from dev_helper.commands.port_usage import find_port_usage
from dev_helper.commands.search_text import search_text_in_files
from dev_helper.commands.system_info import show_system_info
from dev_helper.utils.print import print_header
from dev_helper.utils.prompt import Option, select_prompt


@dataclass(frozen=True)
class MenuAction:
    label: str
    run: Callable[[], None]


MENU_ACTIONS: dict[str, MenuAction] = {
    "search_text": MenuAction("Find a file with text in it", search_text_in_files),
    "find_files": MenuAction("Find files by name", find_files_by_name),
    "disk_usage": MenuAction("Show disk usage", show_disk_usage),
    "network": MenuAction("Show network connections", show_network_connections),
    "system_info": MenuAction("Show system info", show_system_info),
    "port_usage": MenuAction("Find port usage", find_port_usage),
    "git_diff": MenuAction("Compare git branches without commit history", compare_git_branches),
    "file_sync": MenuAction("Set up file sync", setup_file_sync),
}


def main() -> None:
    while True:
        print_header("Development Helper Menu")
        choice = select_prompt(
            "Choose an action (or Ctrl+C to exit):",
            [Option(value=key, label=action.label) for key, action in MENU_ACTIONS.items()],
        )
        MENU_ACTIONS[choice].run()


if __name__ == "__main__":
    main()
