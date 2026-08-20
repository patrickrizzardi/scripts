from __future__ import annotations

from dataclasses import dataclass

from dev_helper.utils.print import print_info, print_success
from dev_helper.utils.proc import run_inherit
from dev_helper.utils.prompt import text_prompt


@dataclass(frozen=True)
class SearchTextOptions:
    search_path: str
    search_text: str
    exclude_dirs: list[str]


def build_grep_args(opts: SearchTextOptions) -> list[str]:
    exclude_args = [f"--exclude-dir={directory}" for directory in opts.exclude_dirs]
    return ["-r", *exclude_args, opts.search_text, opts.search_path]


def search_text_in_files() -> None:
    search_path = text_prompt("Enter the path to search in:", default_value=".")
    search_text = text_prompt("Enter the text to search for:")
    exclude_input = text_prompt("Enter directories to exclude (comma-separated):", default_value="")
    exclude_dirs = [directory.strip() for directory in exclude_input.split(",")] if exclude_input else []

    print_info(f"Searching for '{search_text}' in {search_path}...")
    args = build_grep_args(SearchTextOptions(search_path, search_text, exclude_dirs))
    if run_inherit(["grep", *args]) == 0:
        print_success("Search complete.")
